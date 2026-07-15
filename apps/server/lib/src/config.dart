import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';

/// Server configuration resolved from process environment variables.
class ServerConfig {
  /// Creates a config from already-resolved values.
  ///
  /// Prefer [ServerConfig.fromEnvironment] outside of tests.
  ServerConfig({
    required this.dataDir,
    required this.logLevel,
    required this.trustProxy,
    this.devAllowCors = false,
    this.secureCookies = false,
  });

  /// Builds a config from [environment] (defaults to
  /// [Platform.environment]).
  ///
  /// Recognized variables:
  ///
  /// * `DATA_DIR` — data directory (default `.data`), resolved to an
  ///   absolute path. The directory and its `library/` subdirectory are
  ///   created when missing.
  /// * `LOG_LEVEL` — one of `ERROR`, `WARN`, `WARNING`, `INFO`, `DEBUG`
  ///   (case-insensitive, default `INFO`). Throws [FormatException] on any
  ///   other value.
  /// * `TRUST_PROXY` — `true` to trust reverse-proxy headers; anything else
  ///   (or unset) means `false`.
  /// * `DEV_ALLOW_CORS` — `true` to add permissive CORS headers to every
  ///   response. DEVELOPMENT ONLY — this defeats CSRF protection (a loud
  ///   warning is logged at boot). Production serves the web build
  ///   same-origin and must leave this off.
  /// * `SECURE_COOKIES` — `true` to always mark session cookies `Secure`
  ///   (for deployments reached exclusively over HTTPS).
  factory ServerConfig.fromEnvironment({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;

    final rawDataDir = env['DATA_DIR']?.trim();
    final dataDirInput =
        (rawDataDir == null || rawDataDir.isEmpty) ? '.data' : rawDataDir;
    var dataDir = Directory(dataDirInput).absolute.path;
    while (dataDir.length > 1 &&
        (dataDir.endsWith('/') || dataDir.endsWith(r'\'))) {
      dataDir = dataDir.substring(0, dataDir.length - 1);
    }

    final config = ServerConfig(
      dataDir: dataDir,
      logLevel: _parseLogLevel(env['LOG_LEVEL']),
      trustProxy: env['TRUST_PROXY']?.trim().toLowerCase() == 'true',
      devAllowCors: env['DEV_ALLOW_CORS']?.trim().toLowerCase() == 'true',
      secureCookies: env['SECURE_COOKIES']?.trim().toLowerCase() == 'true',
    );
    Directory(config.libraryDir).createSync(recursive: true);
    return config;
  }

  /// Absolute path of the data directory.
  final String dataDir;

  /// Root log level applied by [configureLogging].
  final Level logLevel;

  /// Whether reverse-proxy headers (e.g. `X-Forwarded-For`) are trusted.
  final bool trustProxy;

  /// Whether `Access-Control-Allow-Origin: *` is added to every response.
  /// Development only (Flutter dev server on a different port); production
  /// serves the web build same-origin.
  final bool devAllowCors;

  /// Forces the `Secure` attribute on session cookies regardless of proxy
  /// headers — for deployments that are always reached over HTTPS.
  final bool secureCookies;

  /// Path of the SQLite database file inside [dataDir].
  String get dbPath => '$dataDir/salt.db';

  /// Directory holding the exported canonical YAML recipe library.
  String get libraryDir => '$dataDir/library';

  static Level _parseLogLevel(String? raw) {
    final value = raw?.trim().toUpperCase();
    return switch (value) {
      null || '' || 'INFO' => Level.INFO,
      'ERROR' => Level.SEVERE,
      'WARN' || 'WARNING' => Level.WARNING,
      'DEBUG' => Level.FINE,
      _ => throw FormatException(
          'Invalid LOG_LEVEL "$raw": '
          'expected ERROR, WARN, WARNING, INFO, or DEBUG.',
        ),
    };
  }
}

StreamSubscription<LogRecord>? _logSubscription;

/// Configures `package:logging` output for the server process.
///
/// Sets the root level from [config] and prints
/// `<time> <level> <loggerName> <message>` (with error and stack trace on
/// the lines below, when present) to stdout, or stderr for
/// [Level.SEVERE] and above. Secrets must never be logged.
///
/// The middleware wiring calls this exactly once per process; calling it
/// again replaces the previous listener instead of duplicating output.
void configureLogging(ServerConfig config) {
  hierarchicalLoggingEnabled = true;
  Logger.root.level = config.logLevel;
  unawaited(_logSubscription?.cancel());
  _logSubscription = Logger.root.onRecord.listen(_printRecord);
}

void _printRecord(LogRecord record) {
  final buffer = StringBuffer()
    ..write(record.time.toIso8601String())
    ..write(' ')
    ..write(record.level.name)
    ..write(' ')
    ..write(record.loggerName)
    ..write(' ')
    ..write(record.message);
  final error = record.error;
  if (error != null) {
    buffer.write('\n  $error');
  }
  final stackTrace = record.stackTrace;
  if (stackTrace != null) {
    buffer.write('\n$stackTrace');
  }
  (record.level >= Level.SEVERE ? stderr : stdout).writeln(buffer);
}
