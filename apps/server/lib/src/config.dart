import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';

/// Whether [address] matches a `TRUSTED_PROXIES` entry: an exact address, or
/// an IPv4 CIDR block.
///
/// CIDR matters in practice — the documented deployment puts the reverse proxy
/// on a Docker bridge, where its address is assigned and moves. Requiring an
/// exact IP there would mean an operator either pins addresses by hand or,
/// far more likely, gives up and leaves the header unchecked.
bool _matchesProxy(String entry, String address) {
  if (!entry.contains('/')) {
    return entry == address;
  }
  final parts = entry.split('/');
  if (parts.length != 2) {
    return false;
  }
  final bits = int.tryParse(parts[1]);
  final network = _ipv4ToInt(parts[0]);
  final candidate = _ipv4ToInt(address);
  if (bits == null ||
      bits < 0 ||
      bits > 32 ||
      network == null ||
      candidate == null) {
    // Not parseable as IPv4 CIDR (an IPv6 entry, or a typo). Refuse rather
    // than guess: an unparseable rule must never widen trust.
    return false;
  }
  if (bits == 0) {
    return true;
  }
  final mask = (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF;
  return (network & mask) == (candidate & mask);
}

/// [address] as a 32-bit int, or null when it is not dotted-quad IPv4.
int? _ipv4ToInt(String address) {
  final octets = address.split('.');
  if (octets.length != 4) {
    return null;
  }
  var value = 0;
  for (final octet in octets) {
    final part = int.tryParse(octet);
    if (part == null || part < 0 || part > 255) {
      return null;
    }
    value = (value << 8) | part;
  }
  return value;
}

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
    this.trustedProxies = const [],
    String? importDir,
  }) : importDir = importDir ?? '$dataDir/import';

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
  ///   (or unset) means `false`. Only takes effect together with
  ///   `TRUSTED_PROXIES`: on its own it now trusts nothing, and says so at
  ///   boot.
  /// * `TRUSTED_PROXIES` — comma-separated addresses that may set
  ///   `X-Forwarded-For`/`X-Forwarded-Proto`, as exact IPs (`10.0.0.5`,
  ///   `::1`) or IPv4 CIDR (`172.17.0.0/16` — a Docker bridge). A forwarded
  ///   header from any OTHER peer is ignored.
  ///
  ///   This exists because `TRUST_PROXY=true` alone honoured
  ///   `X-Forwarded-For` from whoever connected, so anyone who could reach
  ///   the port got a fresh rate-limit bucket per request by making the
  ///   header up — login throttling was decorative in the deployment the
  ///   README documents. The header is only meaningful from the hop that
  ///   appends it, so the peer has to be checked.
  /// * `DEV_ALLOW_CORS` — `true` to add permissive CORS headers to every
  ///   response. DEVELOPMENT ONLY — this defeats CSRF protection (a loud
  ///   warning is logged at boot). Production serves the web build
  ///   same-origin and must leave this off.
  /// * `SECURE_COOKIES` — `true` to always mark session cookies `Secure`
  ///   (for deployments reached exclusively over HTTPS).
  /// * `IMPORT_DIR` — allowlist root for bulk imports (default
  ///   `DATA_DIR/import`). Only source folders inside it can be imported
  ///   through the API; mount a corpus there in Docker.
  factory ServerConfig.fromEnvironment({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;

    final rawDataDir = env['DATA_DIR']?.trim();
    final dataDirInput = (rawDataDir == null || rawDataDir.isEmpty)
        ? '.data'
        : rawDataDir;
    var dataDir = Directory(dataDirInput).absolute.path;
    while (dataDir.length > 1 &&
        (dataDir.endsWith('/') || dataDir.endsWith(r'\'))) {
      dataDir = dataDir.substring(0, dataDir.length - 1);
    }

    final rawImportDir = env['IMPORT_DIR']?.trim();
    final config = ServerConfig(
      dataDir: dataDir,
      logLevel: _parseLogLevel(env['LOG_LEVEL']),
      trustProxy: env['TRUST_PROXY']?.trim().toLowerCase() == 'true',
      trustedProxies: [
        for (final entry in (env['TRUSTED_PROXIES'] ?? '').split(','))
          if (entry.trim().isNotEmpty) entry.trim(),
      ],
      devAllowCors: env['DEV_ALLOW_CORS']?.trim().toLowerCase() == 'true',
      secureCookies: env['SECURE_COOKIES']?.trim().toLowerCase() == 'true',
      importDir: (rawImportDir == null || rawImportDir.isEmpty)
          ? null
          : Directory(rawImportDir).absolute.path,
    );
    Directory(config.libraryDir).createSync(recursive: true);
    Directory(config.importDir).createSync(recursive: true);
    return config;
  }

  /// Absolute path of the data directory.
  final String dataDir;

  /// Root log level applied by [configureLogging].
  final Level logLevel;

  /// Whether reverse-proxy headers (e.g. `X-Forwarded-For`) are trusted.
  final bool trustProxy;

  /// Peers whose `X-Forwarded-*` headers are honoured, when [trustProxy] is
  /// on. Exact IPs or IPv4 CIDR. Empty means no peer is trusted, which makes
  /// [trustProxy] inert — deliberately: failing closed costs a shared
  /// rate-limit bucket, failing open costs the rate limit entirely.
  final List<String> trustedProxies;

  /// Whether [address] is one of [trustedProxies].
  bool isTrustedProxy(String? address) {
    if (address == null || !trustProxy) {
      return false;
    }
    for (final entry in trustedProxies) {
      if (_matchesProxy(entry, address)) {
        return true;
      }
    }
    return false;
  }

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

  /// Allowlist root for bulk imports: only source folders that
  /// canonicalize inside this directory may be imported via the API.
  final String importDir;

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
