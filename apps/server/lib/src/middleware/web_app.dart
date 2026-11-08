import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_frog/dart_frog.dart';

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
/// `public/` arm serves — [publicDir] resolved exactly as shelf_static
/// resolves it (the root's real path joined with the URL's segments, a
/// file, its real path inside the root). For such a file:
/// - a strong `ETag` (md5 of the bytes, hashed ONCE per RESOLVED path +
///   mtime + size — one entry per file of the root, whatever the URL's
///   spelling), answered here on `If-None-Match` (GET / HEAD: 304 with the
///   ETag; RFC 7232 §6: the entity tag governs);
/// - `If-Modified-Since` STRIPPED before shelf_static — its date-only 304
///   ("not after") answered 304 to a rolled-back, older-mtime bundle (U4),
///   and its parse threw on a malformed date (a bare 500, U3);
/// - a `Range` other than `bytes=<≤15 digits>-<≤15 digits>` dropped (an
///   int64 overflow threw, U3) — an unusable range is ignored (RFC 7233).
/// Every other request passes untouched (`/`, the SPA fallback, routes).
Middleware staticFileValidators({String publicDir = 'public'}) {
  final etags = <String, (DateTime, int, String)>{};
  String? root;
  File? fileOf(Uri uri) {
    try {
      root ??= Directory(publicDir).resolveSymbolicLinksSync();
      final path = [root, ...uri.pathSegments].join(Platform.pathSeparator);
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
    final revalidated = fromShelfMiddleware(
      (inner) => (request) {
        final range = request.headers[HttpHeaders.rangeHeader];
        return inner(
          request.change(
            headers: {
              HttpHeaders.ifModifiedSinceHeader: null,
              if (range != null && !_usableRange.hasMatch(range))
                HttpHeaders.rangeHeader: null,
            },
          ),
        );
      },
    )(handler);
    return (context) async {
      final request = context.request;
      final file = fileOf(request.uri);
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
      final response = await revalidated(context);
      return response.copyWith(headers: {HttpHeaders.etagHeader: etag});
    };
  };
}

/// The one byte range shelf_static parses without overflow (U3).
final RegExp _usableRange = RegExp(r'^bytes=\d{0,15}-\d{0,15}$');
