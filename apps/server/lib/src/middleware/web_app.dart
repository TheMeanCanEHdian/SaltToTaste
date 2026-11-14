import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:meta/meta.dart';

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
/// `public/` arm serves. v108 V5 (Run 085/086): the file is resolved
/// EXACTLY as shelf_static 1.1.3 resolves it (static_handler.dart:
/// `p.joinAll([root, ...request.url.pathSegments])`, a file, its resolved
/// path `p.isWithin` the root) — the same decoded segments, the POSIX
/// join (an empty part skipped, a part starting with `/` RESETS the path),
/// the same containment on the real path. So every spelling shelf_static
/// serves is the file WITH its validators (`/main.dart.js/`,
/// `//main.dart.js`, `/<root>%2Fmain.dart.js`, `/assets%2Fx.js`), and a
/// request that names no file passes through UNTOUCHED, under `/api/` and
/// outside it (a tag route `/api/v1/tags/%2Fquick/style`, a deep link
/// `/r/a%2Fb`) — v107's separator refusal, wider than that, is deleted.
/// No dot segment arrives here: `Uri.parse` keeps a final `.` before a
/// `?` or `#` (`/x/.?`), but shelf's `Request` constructor (shelf 1.4.2
/// request.dart: handlerPath + url must equal the requested path's
/// segments) refuses such a target, and shelf_io answers its bare 400
/// before any middleware. Windows (a dev-only platform): `p.joinAll` there
/// also splits on `\`, this join does not — the stated limit.
/// For such a file:
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
  File? fileOf(Uri url) {
    // v109 W1: a path no file can have is not resolved at all (O(1), before
    // the root or the segments are read) — the request passes untouched.
    if (url.path.length > _maxPathLength) {
      return null;
    }
    try {
      final base = root ??= Directory(publicDir).resolveSymbolicLinksSync();
      final path = staticJoin(base, url.pathSegments);
      if (FileSystemEntity.typeSync(path) != FileSystemEntityType.file) {
        return null;
      }
      final real = File(path).resolveSymbolicLinksSync();
      // The RESOLVED path (closer 1 D1): '//x' and '/x' are one cache entry,
      // so the ETag map holds at most one entry per file of the root.
      return real.startsWith('$base/') ? File(real) : null;
    } on FileSystemException {
      return null;
    }
  }

  return (handler) {
    return (context) async {
      final request = context.request;
      final file = fileOf(request.url);
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

/// shelf_static's join of [segments] under [root] (`p.joinAll`'s POSIX
/// rule: an empty part skipped, a part starting with `/` RESETS the path,
/// one separator between parts) in ONE pass — v109 W1: v108's
/// per-segment concatenation copied the whole path per segment (quadratic).
@visibleForTesting
String staticJoin(String root, List<String> segments) {
  final joined = StringBuffer(root);
  var slash = root.endsWith('/');
  for (final s in segments) {
    if (s.isEmpty) {
      continue;
    }
    if (s.startsWith('/')) {
      joined.clear();
    } else if (!slash) {
      joined.write('/');
    }
    joined.write(s);
    slash = s.endsWith('/');
  }
  return '$joined';
}

/// v109 W1 (Run 087/088 S5 / O4): the longest request path `fileOf`
/// resolves — Linux's PATH_MAX (macOS's is 1,024): no file under the root
/// has a longer path, so a longer request is never joined (one 400 KB path
/// of 200,000 segments stalled v108's quadratic join 9–17 s).
const int _maxPathLength = 4096;

/// The one byte range shelf_static parses without overflow (U3).
final RegExp _usableRange = RegExp(r'^bytes=(\d{0,15})-\d{0,15}$');
