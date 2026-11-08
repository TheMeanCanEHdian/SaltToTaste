import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_shared/salt_shared.dart' show ApiErrorCodes;

/// Content-Security-Policy for the served Flutter web build.
///
/// Everything is bundled same-origin (CanvasKit included), so only `self`
/// plus what the Flutter engine itself needs: `wasm-unsafe-eval` for
/// CanvasKit, inline styles injected by the engine, and data:/blob: image
/// and worker URLs (service worker caching, decoded images).
const String _contentSecurityPolicy =
    "default-src 'self'; "
    "script-src 'self' 'wasm-unsafe-eval'; "
    "style-src 'self' 'unsafe-inline'; "
    "img-src 'self' data: blob:; "
    "font-src 'self'; "
    "connect-src 'self'; "
    "worker-src 'self' blob:; "
    "frame-ancestors 'none'; "
    "base-uri 'self'; "
    "form-action 'self'";

/// Adds defense-in-depth headers to every response: `nosniff` and a strict
/// referrer policy globally, plus CSP and `X-Frame-Options: DENY` on HTML
/// (the web-app shell — API responses are JSON and gain nothing from CSP).
///
/// "Every response" only became true once `buildOutermostMiddleware` applied
/// this around the WHOLE generated cascade. Wired only into
/// `buildAppMiddleware`, it missed the static `public/` arm entirely — the
/// shipped `/index.html` had no CSP while `/r/<slug>`, the same shell through
/// [spaFallback], had one.
Middleware securityHeaders() {
  return (handler) {
    return (context) async {
      final response = await handler(context);
      final contentType = response.headers[HttpHeaders.contentTypeHeader] ?? '';
      // v106 U7: copyWith MERGES — no `...response.headers` spread, which
      // joined a multi-value header (two Set-Cookie → one "a=1,b=2").
      return response.copyWith(
        headers: {
          'X-Content-Type-Options': 'nosniff',
          'Referrer-Policy': 'same-origin',
          if (contentType.startsWith('text/html')) ...{
            'Content-Security-Policy': _contentSecurityPolicy,
            'X-Frame-Options': 'DENY',
          },
        },
      );
    };
  };
}

/// SPA deep-link fallback: a `GET` that matched no route or file and does
/// not target the API surface gets `public/index.html`, so refreshing
/// `/r/rich-chocolate-bundt-cake` (or opening it from a bookmark) boots the
/// web app instead of returning the JSON 404 envelope.
///
/// Non-HTML misses keep their 404: API paths (`/api/`, `/healthz`,
/// `/images/`) must stay machine-readable, and a path whose last segment
/// has an extension is a missing asset, not a route.
Middleware spaFallback({String indexPath = 'public/index.html'}) {
  return (handler) {
    return (context) async {
      final response = await handler(context);
      if (response.statusCode != HttpStatus.notFound ||
          context.request.method != HttpMethod.get) {
        return response;
      }
      final path = context.request.uri.path;
      if (path.startsWith('/api/') ||
          path == '/healthz' ||
          path.startsWith('/images/')) {
        return response;
      }
      // A dotted last segment is a missing asset, not a route — except
      // under /r/, where hand-edited YAML may legally put a dot in a
      // recipe slug.
      if (!path.startsWith('/r/') && path.split('/').last.contains('.')) {
        return response;
      }
      try {
        final index = File(indexPath);
        if (!index.existsSync()) {
          return response;
        }
        return Response.bytes(
          body: index.readAsBytesSync(),
          headers: {
            HttpHeaders.contentTypeHeader: 'text/html; charset=utf-8',
          },
        );
        // This middleware sits OUTSIDE the error handler; a read race
        // (mid-redeploy rm/cp of public/) must degrade to the original
        // 404, not a bare unenveloped 500.
      } on FileSystemException {
        return response;
      }
    };
  };
}

/// v106 U3 / U4 (Run 081/082): the validators of a file the static
/// `public/` arm serves. v107 U1 (Run 083/084): the URL is CANONICALISED
/// first — a request whose decoded segment holds a path separator (`/` or
/// `\`, the `%2F` absolute-segment reset and its reverse) is REFUSED here
/// (the 404 envelope, never reaching shelf_static; under `/api/` only a
/// LEADING separator — an inner one is route data, closer 1 D1); the empty
/// segments are dropped (`/main.dart.js/`, `//main.dart.js`,
/// `/main.dart.js/.` ARE `/main.dart.js` — Dart's `Uri` removes a dot
/// segment, a `%2E`-encoded one too, before `pathSegments`, so no `.` or
/// `..` ever arrives here (measured, the owner gate), and shelf_static's
/// `p.joinAll` drops an empty one, so it served them; now the validators
/// apply too). Every segment left is a plain name (or, under `/api/`, holds
/// only an INNER separator, which `p.joinAll` joins exactly as the
/// separator join does), so this resolver and shelf_static join the same
/// path: the root's real path joined with them, a file, its real path
/// inside the root. For such a file:
/// - a strong `ETag` (md5 of the bytes, hashed ONCE per RESOLVED path +
///   mtime + size — one entry per file of the root, whatever the URL's
///   spelling), answered here on `If-None-Match` (GET / HEAD: 304 with the
///   ETag; RFC 7232 §6: the entity tag governs);
/// - `If-Modified-Since` STRIPPED before shelf_static — its date-only 304
///   ("not after") answered 304 to a rolled-back, older-mtime bundle (U4),
///   and its parse threw on a malformed date (a bare 500, U3);
/// - a `Range` other than `bytes=<≤15 digits>-<≤15 digits>` dropped (an
///   int64 overflow threw, U3) — an unusable range is ignored (RFC 7233);
///   v107 U5: dropped too under an `If-Range` that is not this strong ETag
///   (a resumed download of an OLD build gets the whole new file, RFC 9110
///   §13.1.5 — a weak or date If-Range included); v107 U8: and one starting
///   at or past the file's size (shelf_static's bare 416, no
///   Content-Range) — the whole file, 200.
/// Every other request passes untouched (`/`, the SPA fallback, routes).
Middleware staticFileValidators({String publicDir = 'public'}) {
  final etags = <String, (DateTime, int, String)>{};
  String? root;
  File? fileOf(List<String> segments) {
    try {
      root ??= Directory(publicDir).resolveSymbolicLinksSync();
      final path = [root, ...segments].join(Platform.pathSeparator);
      if (FileSystemEntity.typeSync(path) != FileSystemEntityType.file) {
        return null;
      }
      final real = File(path).resolveSymbolicLinksSync();
      // The RESOLVED path (closer 1 D1): '//x' and '/x' are one cache entry,
      // so the ETag map holds at most one entry per file of the root.
      return real.startsWith('$root${Platform.pathSeparator}')
          ? File(real)
          : null;
    } on FileSystemException {
      return null;
    }
  }

  return (handler) {
    return (context) async {
      final request = context.request;
      final segments = request.uri.pathSegments;
      // v107 closer 1 D1: under /api/ a decoded separator is route data (a
      // free-text tag name: `/api/v1/tags/a%2Fb/style`), so only what makes
      // the two resolvers diverge is refused there — a segment STARTING
      // with a separator (p.joinAll's absolute reset); an inner one joins
      // identically in both. Elsewhere every separator is refused. (A `.`
      // or `..` segment never arrives: `Uri` removes dot segments first.)
      final api = segments.isNotEmpty && segments.first == 'api';
      if (segments.any(
        (s) =>
            s.startsWith('/') ||
            s.startsWith(r'\') ||
            !api && (s.contains('/') || s.contains(r'\')),
      )) {
        final id = requestIdOf(context) ?? newRequestId();
        return errorResponse(
          statusCode: HttpStatus.notFound,
          code: ApiErrorCodes.notFound,
          message: 'Not found.',
          requestId: id,
          headers: {requestIdHeader: id},
        );
      }
      final file = fileOf([
        for (final s in segments)
          if (s.isNotEmpty) s,
      ]);
      if (file == null) {
        return handler(context);
      }
      final stat = file.statSync();
      final known = etags[file.path];
      final etag =
          known != null && known.$1 == stat.modified && known.$2 == stat.size
          ? known.$3
          : (etags[file.path] = (
              stat.modified,
              stat.size,
              '"${md5.convert(file.readAsBytesSync())}"',
            )).$3;
      final inm = request.headers[HttpHeaders.ifNoneMatchHeader];
      if ((request.method == HttpMethod.get ||
              request.method == HttpMethod.head) &&
          inm != null &&
          // The weak comparison (RFC 7232 §3.2): a proxy's W/ is dropped.
          inm.split(',').any((t) {
            final tag = t.trim();
            return tag == '*' ||
                (tag.startsWith('W/') ? tag.substring(2) : tag) == etag;
          })) {
        return Response(
          statusCode: HttpStatus.notModified,
          headers: {HttpHeaders.etagHeader: etag},
        );
      }
      final range = request.headers[HttpHeaders.rangeHeader];
      final ifRange = request.headers['if-range'];
      final usable = range == null ? null : _usableRange.firstMatch(range);
      final dropRange =
          range != null &&
          (usable == null ||
              (ifRange != null && ifRange != etag) ||
              (int.tryParse(usable[1]!) ?? 0) >= stat.size);
      final response = await fromShelfMiddleware(
        (inner) =>
            (request) => inner(
              request.change(
                headers: {
                  HttpHeaders.ifModifiedSinceHeader: null,
                  if (dropRange) HttpHeaders.rangeHeader: null,
                },
              ),
            ),
      )(handler)(context);
      return response.copyWith(headers: {HttpHeaders.etagHeader: etag});
    };
  };
}

/// The one byte range shelf_static parses without overflow (U3).
final RegExp _usableRange = RegExp(r'^bytes=(\d{0,15})-\d{0,15}$');
