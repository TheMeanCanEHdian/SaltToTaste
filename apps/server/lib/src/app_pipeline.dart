// dart_frog ships its own `requestLogger`; ours is the one wired here.
import 'package:dart_frog/dart_frog.dart' hide requestLogger;
import 'package:logging/logging.dart';
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/middleware/dev_cors.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/middleware/request_logger.dart';
import 'package:salt_server/src/middleware/web_app.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart'
    show BulkNutritionProvider;
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/search/search_service.dart';

final Logger _log = Logger('proxy');

/// Wraps the ENTIRE handler dart_frog's generated entry point builds —
/// `Cascade().add(createStaticFileHandler()).add(buildRootHandler())` — so
/// [securityHeaders] also covers the arm no route middleware can reach.
///
/// `routes/_middleware.dart`, and therefore [buildAppMiddleware], wraps only
/// the SECOND arm. The static `public/` tree is the FIRST, served before and
/// outside the chain, so `/index.html` and `/main.dart.js` shipped with no
/// CSP and no `Referrer-Policy` while `/r/<slug>` — byte for byte the same
/// app shell, via [spaFallback] — carried both. The `nosniff` and
/// `X-Frame-Options: SAMEORIGIN` those static responses did carry came from
/// dart:io's `HttpServer.defaultResponseHeaders`, not from us, which is why
/// the promised `DENY` silently degraded to `SAMEORIGIN`. Middleware inside
/// the chain cannot reach outside it; `main.dart`'s `run()` is the only seam
/// that can, because it is handed the composed cascade.
///
/// [securityHeaders] therefore runs twice on a routed response. It is
/// idempotent (same header names, same values), and keeping the in-chain copy
/// is what lets the suite drive it without rebuilding the cascade.
Handler buildOutermostMiddleware(Handler handler) => securityHeaders()(handler);

/// The runtime counterpart to bootstrap's `configWarnings`: warns when a
/// request carrying `X-Forwarded-For`/`-Proto` arrives from a peer that
/// `TRUSTED_PROXIES` does not cover, while `TRUST_PROXY` is on.
///
/// This is the likeliest real misconfiguration and the only one no boot check
/// can see: `172.17.0.0/16` (the README's own example, the DEFAULT Docker
/// bridge) parses fine, names a plausible network, and matches nobody once
/// `docker compose` puts the proxy on a user-defined bridge at 172.18+. Every
/// boot warning passes and every consequence is silent — forwarded headers are
/// ignored, so rate limits key on the proxy's own address (one bucket for
/// everyone behind it) and `isSecureRequest` is false, so every session cookie
/// ships WITHOUT `Secure`: a live token the browser will send over plaintext.
/// Only a live request carries the peer's address, so only a live request can
/// tell "no proxy at all" apart from "proxy configured with the wrong one".
///
/// Rate-limited to one record per [every]: the log store is small and rotates
/// keeping one generation, so a per-request warning would evict the history it
/// exists to preserve. The state is closure-local, so it is per-chain —
/// production builds the chain once.
Middleware untrustedProxyWarning(
  ServerConfig config, {
  Duration every = const Duration(hours: 1),
}) {
  DateTime? lastWarned;
  return (handler) => (context) {
    final headers = context.request.headers;
    if (config.trustProxy &&
        (headers['x-forwarded-for'] != null ||
            headers['x-forwarded-proto'] != null) &&
        !trustsForwardedHeaders(context)) {
      final now = DateTime.now();
      final last = lastWarned;
      if (last == null || now.difference(last) >= every) {
        lastWarned = now;
        _log.warning(
          'TRUST_PROXY is on but the peer sending X-Forwarded-* '
          '(${clientIp(context)}) matches no TRUSTED_PROXIES entry '
          '(${config.trustedProxies.join(', ')}), so forwarded headers are '
          'ignored: rate limits key on that one address for everyone behind '
          'it, and session cookies are issued WITHOUT Secure. Add that peer '
          'to TRUSTED_PROXIES, or set SECURE_COOKIES=true if nothing is '
          'proxying.',
        );
      }
    }
    return handler(context);
  };
}

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
/// untrustedProxyWarning -> SaltDatabase provider -> NutritionProvider
/// provider -> SearchService provider -> AuthRuntime provider -> authProvider
/// -> routes.
///
/// This chain is NOT the outermost thing production runs: the generated entry
/// point serves the static `public/` tree from a cascade arm above it. See
/// [buildOutermostMiddleware].
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
  required LogStore logStore,
  String indexPath = 'public/index.html',
  // Optional so every existing harness keeps working AND becomes hermetic:
  // a test that injects a fixture as the interactive client gets the same
  // fixture for bulk jobs. Production passes the uncapped bulk client.
  NutritionProvider? bulkNutritionProvider,
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
      .use(provider<LogStore>((_) => logStore))
      .use(provider<NutritionProvider>((_) => nutritionProvider))
      .use(
        provider<BulkNutritionProvider>(
          (_) => BulkNutritionProvider(
            bulkNutritionProvider ?? nutritionProvider,
          ),
        ),
      )
      .use(provider<SaltDatabase>((_) => database))
      // Inside the ServerConfig provider it reads, outside everything else so
      // it sees every request that reaches the chain.
      .use(untrustedProxyWarning(config))
      .use(provider<ServerConfig>((_) => config))
      .use(errorHandler())
      .use(devCors(config))
      .use(spaFallback(indexPath: indexPath))
      .use(securityHeaders())
      .use(requestLogger(config))
      .use(requestIdProvider());
}
