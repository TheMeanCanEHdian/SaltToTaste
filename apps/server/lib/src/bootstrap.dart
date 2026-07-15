import 'package:salt_server/src/config.dart';

ServerConfig? _config;

/// The process-wide server config, created (and logging configured) on first
/// access.
///
/// [initServer] triggers this eagerly at startup so an invalid `LOG_LEVEL` or
/// `DATA_DIR` fails the process fast, rather than surfacing as silent
/// per-request 500s with no log output (logging is only configured once the
/// config parses successfully).
ServerConfig get serverConfig => _config ??= _init();

ServerConfig _init() {
  final config = ServerConfig.fromEnvironment();
  configureLogging(config);
  return config;
}

/// Eagerly initializes configuration and logging. Call once at startup.
ServerConfig initServer() => serverConfig;
