import 'dart:io';

// dart_frog ships its own `requestLogger`; ours is the one wired here.
import 'package:dart_frog/dart_frog.dart' hide requestLogger;
import 'package:salt_server/src/bootstrap.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/middleware/request_logger.dart';

/// Top-level middleware chain.
///
/// `.use` wraps, so the LAST `.use` is the OUTERMOST middleware. Order
/// (outermost first): requestIdProvider -> requestLogger -> devCors ->
/// errorHandler -> ServerConfig provider -> SaltDatabase provider ->
/// AuthRuntime provider -> authProvider -> routes.
///
/// requestIdProvider sits outside errorHandler so error envelopes carry a
/// matching `request_id` and every response — including error envelopes —
/// gets the `X-Request-Id` header. requestLogger sits outside errorHandler
/// so failed requests are still logged with their envelope status.
/// errorHandler wraps everything below it (providers, auth, routes), so any
/// exception thrown there becomes a clean envelope. authProvider is
/// innermost (first `.use`, closest to the handler) because it reads the
/// [SaltDatabase] provider above it; the process-wide singletons themselves
/// live in `bootstrap.dart` and are created at startup by `initServer`.
/// Adds permissive CORS headers (and answers preflight `OPTIONS`) when
/// `DEV_ALLOW_CORS=true` (development only — see [ServerConfig.devAllowCors]).
///
/// Production serves the web build same-origin and leaves this off.
const Map<String, String> _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
      'Authorization, Content-Type, X-Requested-With',
  'Access-Control-Max-Age': '86400',
};

Middleware _devCors() {
  return (handler) {
    return (context) async {
      if (!serverConfig.devAllowCors) {
        return handler(context);
      }
      // Short-circuit the browser's preflight before it reaches a route that
      // only allows GET (which would 405 the preflight and block the real
      // request).
      if (context.request.method == HttpMethod.options) {
        return Response(
          statusCode: HttpStatus.noContent,
          headers: _corsHeaders,
        );
      }
      final response = await handler(context);
      return response.copyWith(
        headers: {...response.headers, ..._corsHeaders},
      );
    };
  };
}

Handler middleware(Handler handler) {
  return handler
      // Innermost: lazily resolves AuthUser? from the session cookie or
      // bearer token; needs the SaltDatabase provider wired outside it.
      .use(authProvider())
      .use(provider<AuthRuntime>((_) => authRuntime))
      .use(provider<SaltDatabase>((_) => saltDatabase))
      .use(provider<ServerConfig>((_) => serverConfig))
      .use(errorHandler())
      .use(_devCors())
      .use(requestLogger())
      .use(requestIdProvider());
}
