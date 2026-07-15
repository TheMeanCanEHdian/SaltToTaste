import 'dart:io';

import 'package:salt_server/src/auth/setup_code.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';

ServerConfig? _config;
SaltDatabase? _database;
AuthRuntime? _authRuntime;

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

/// The process-wide database, opened once at [serverConfig]'s `dbPath`
/// (eagerly by [initServer]; lazily on first request otherwise).
SaltDatabase get saltDatabase =>
    _database ??= SaltDatabase.open(serverConfig.dbPath);

/// The process-wide auth collaborators (password hasher, login rate
/// limiter, first-boot setup code).
///
/// Created on first access: when the database holds zero users, a one-time
/// setup code is generated and printed to stdout so the operator can create
/// the admin account via `POST /api/v1/auth/setup`.
AuthRuntime get authRuntime => _authRuntime ??= _initAuthRuntime();

AuthRuntime _initAuthRuntime() {
  final runtime = AuthRuntime();
  if (serverConfig.devAllowCors) {
    // Reflected-origin CORS with credentials defeats the CSRF protection
    // entirely; this must never be enabled outside local development.
    stderr.writeln(
      'WARNING: DEV_ALLOW_CORS is enabled. Cross-origin requests with '
      'credentials are allowed and CSRF protection is OFF. '
      'Never run production with this flag.',
    );
  }
  // Housekeeping: drop sessions that expired while the server was down.
  saltDatabase.deleteExpiredSessions();
  if (saltDatabase.userCount() == 0) {
    final code = generateSetupCode();
    runtime.setupCode = code;
    // The one deliberate secret-on-stdout line in the server: the code
    // exists to be read from the console/container logs by the operator.
    stdout.writeln(
      'SaltToTaste setup code: $code '
      '— open the app to create the admin account.',
    );
  }
  return runtime;
}

/// Eagerly initializes configuration, logging, the database, and the auth
/// runtime (printing the first-boot setup code when no users exist yet).
/// Call once at startup.
ServerConfig initServer() {
  final config = serverConfig;
  _authRuntime ??= _initAuthRuntime();
  return config;
}
