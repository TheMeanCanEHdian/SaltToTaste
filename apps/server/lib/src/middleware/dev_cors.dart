import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/config.dart';

Map<String, String> _corsHeaders(RequestContext context) => {
  'Access-Control-Allow-Origin': context.request.headers['origin'] ?? '*',
  'Vary': 'Origin',
  'Access-Control-Allow-Credentials': 'true',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
      'Authorization, Content-Type, X-Requested-With',
  'Access-Control-Max-Age': '86400',
};

/// Adds CORS headers (and answers preflight `OPTIONS`) when
/// [ServerConfig.devAllowCors] is set — development only. Off, it is a
/// pass-through.
///
/// The dev Flutter app authenticates with the session cookie, and browsers
/// reject credentialed responses carrying a wildcard origin — so the request
/// origin is echoed and `Allow-Credentials` set instead of `*`. Production
/// serves the web build same-origin and leaves this off.
///
/// Takes [config] as a parameter (rather than the process global) so the
/// pipeline that installs it can be assembled from explicit collaborators and
/// driven in a test — see `buildAppMiddleware`.
Middleware devCors(ServerConfig config) {
  return (handler) {
    return (context) async {
      if (!config.devAllowCors) {
        return handler(context);
      }
      // Short-circuit the browser's preflight before it reaches a route that
      // only allows GET (which would 405 the preflight and block the real
      // request).
      if (context.request.method == HttpMethod.options) {
        return Response(
          statusCode: HttpStatus.noContent,
          headers: _corsHeaders(context),
        );
      }
      final response = await handler(context);
      return response.copyWith(
        headers: {...response.headers, ..._corsHeaders(context)},
      );
    };
  };
}
