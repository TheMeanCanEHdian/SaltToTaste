import 'dart:io';

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
Middleware securityHeaders() {
  return (handler) {
    return (context) async {
      final response = await handler(context);
      final contentType = response.headers[HttpHeaders.contentTypeHeader] ?? '';
      return response.copyWith(
        headers: {
          ...response.headers,
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
            // Same contract as `/`: the shell revalidates so deploys take
            // effect immediately.
            HttpHeaders.cacheControlHeader: 'no-cache',
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
