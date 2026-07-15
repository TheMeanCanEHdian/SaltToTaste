// dart_frog ships its own `requestLogger`; ours is the one wired here.
import 'package:dart_frog/dart_frog.dart' hide requestLogger;
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/middleware/request_logger.dart';

/// Process-wide config singleton: created (and logging configured) exactly
/// once, on the first request.
ServerConfig? _config;

ServerConfig _serverConfig() {
  return _config ??= _initConfig();
}

ServerConfig _initConfig() {
  final config = ServerConfig.fromEnvironment();
  configureLogging(config);
  return config;
}

/// Process-wide database singleton: opened lazily on the first
/// `context.read<SaltDatabase>()`, never per request.
SaltDatabase? _database;

SaltDatabase _saltDatabase(RequestContext context) {
  return _database ??= SaltDatabase.open(context.read<ServerConfig>().dbPath);
}

/// Top-level middleware chain.
///
/// `.use` wraps, so the LAST `.use` is the OUTERMOST middleware. Order
/// (outermost first): requestIdProvider -> requestLogger -> errorHandler ->
/// ServerConfig provider -> routes.
///
/// requestIdProvider sits outside errorHandler so error envelopes carry a
/// matching `request_id` and every response — including error envelopes —
/// gets the `X-Request-Id` header. requestLogger sits outside errorHandler
/// so failed requests are still logged with their envelope status.
/// errorHandler wraps everything below it (config + DB providers, routes),
/// so any exception thrown there becomes a clean envelope.
Handler middleware(Handler handler) {
  return handler
      // Innermost so it can read ServerConfig; dart_frog providers are lazy,
      // so the connection only opens when a route actually reads the DB.
      .use(provider<SaltDatabase>(_saltDatabase))
      .use(provider<ServerConfig>((_) => _serverConfig()))
      .use(errorHandler())
      .use(requestLogger())
      .use(requestIdProvider());
}
