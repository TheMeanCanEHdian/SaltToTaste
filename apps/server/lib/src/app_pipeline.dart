// dart_frog ships its own `requestLogger`; ours is the one wired here.
import 'package:dart_frog/dart_frog.dart' hide requestLogger;
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/middleware/dev_cors.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/middleware/request_logger.dart';
import 'package:salt_server/src/middleware/web_app.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/search/search_service.dart';

/// Builds the top-level middleware chain from explicit collaborators.
///
/// `routes/_middleware.dart` calls this with the process-wide singletons
/// created at startup by `initServer`; a test calls it with fakes and drives
/// the REAL chain over a socket. The order below carries security-relevant
/// behavior — the app shell must keep its CSP and `X-Frame-Options`, and error
/// envelopes must wrap everything below — and a reorder that breaks either used
/// to keep the suite green, because the test built its own parallel pipeline.
/// Pulling the chain here is the pin: those properties are now asserted against
/// what production actually runs.
///
/// `.use` wraps, so the LAST `.use` is the OUTERMOST middleware. Order
/// (outermost first): requestIdProvider -> requestLogger -> securityHeaders ->
/// spaFallback -> devCors -> errorHandler -> ServerConfig provider ->
/// SaltDatabase provider -> NutritionProvider provider -> SearchService
/// provider -> AuthRuntime provider -> authProvider -> routes.
///
/// spaFallback sits outside errorHandler (it rewrites the enveloped 404 for
/// deep links) and inside securityHeaders (the fallback HTML must carry the
/// CSP); requestLogger outside both records what was actually served.
///
/// requestIdProvider sits outside errorHandler so error envelopes carry a
/// matching `request_id` and every response — including error envelopes — gets
/// the `X-Request-Id` header. requestLogger sits outside errorHandler so failed
/// requests are still logged with their envelope status. errorHandler wraps
/// everything below it (providers, auth, routes), so any exception thrown there
/// becomes a clean envelope. authProvider is innermost (first `.use`, closest
/// to the handler) because it reads the [SaltDatabase] provider above it.
Handler buildAppMiddleware(
  Handler handler, {
  required ServerConfig config,
  required SaltDatabase database,
  required AuthRuntime authRuntime,
  required NutritionProvider nutritionProvider,
  required RequestRateLimiter searchRateLimiter,
  required SearchService Function() searchService,
  String indexPath = 'public/index.html',
}) {
  return handler
      // Innermost: lazily resolves AuthUser? from the session cookie or
      // bearer token; needs the SaltDatabase provider wired outside it.
      .use(authProvider())
      .use(provider<AuthRuntime>((_) => authRuntime))
      .use(provider<RequestRateLimiter>((_) => searchRateLimiter))
      // Resolved PER REQUEST, not captured. The dart_frog entrypoint builds
      // this chain BEFORE the custom run() calls initSearchService(), so a
      // value captured here would freeze the InlineSearchService fallback in
      // and leave the isolate pool spawned-but-unused (#48 review, HIGH). The
      // thunk reads the live singleton, so the post-build swap is honored.
      .use(provider<SearchService>((_) => searchService()))
      .use(provider<NutritionProvider>((_) => nutritionProvider))
      .use(provider<SaltDatabase>((_) => database))
      .use(provider<ServerConfig>((_) => config))
      .use(errorHandler())
      .use(devCors(config))
      .use(spaFallback(indexPath: indexPath))
      .use(securityHeaders())
      .use(requestLogger())
      .use(requestIdProvider());
}
