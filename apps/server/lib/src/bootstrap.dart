import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/auth/setup_code.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/nutrition/fdc_provider.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/backup_service.dart';
import 'package:salt_server/src/services/library_scan.dart';

final Logger _log = Logger('bootstrap');

/// Settings-table key holding the FDC API key. The value is a secret:
/// write-only through the API (reads return a masked form) and never
/// logged.
const String fdcApiKeySetting = 'fdc.api_key';

ServerConfig? _config;
SaltDatabase? _database;
AuthRuntime? _authRuntime;
NutritionProvider? _nutritionProvider;
NutritionProvider? _bulkNutritionProvider;
TokenBucket? _fdcBucket;
Timer? _backupTimer;

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

TokenBucket get _sharedFdcBucket => _fdcBucket ??= TokenBucket();

/// The interactive FDC client: shares the process-wide token bucket
/// (900 requests/hr) with [bulkNutritionProvider], reads the API key live
/// from settings on every request (replacing it takes effect immediately),
/// and gives up after ~30s of rate-limit waiting so a drained budget turns
/// into an explained 4xx instead of a stuck request.
NutritionProvider get nutritionProvider =>
    _nutritionProvider ??= UsdaFdcProvider(
      apiKey: () => saltDatabase.getSetting(fdcApiKeySetting),
      bucket: _sharedFdcBucket,
      maxRateWait: const Duration(seconds: 30),
    );

/// The bulk-job FDC client: same bucket and key as [nutritionProvider] but
/// with no wait cap — a bulk compute is expected to ride out the hourly
/// budget for as long as it takes.
NutritionProvider get bulkNutritionProvider =>
    _bulkNutritionProvider ??= UsdaFdcProvider(
      apiKey: () => saltDatabase.getSetting(fdcApiKeySetting),
      bucket: _sharedFdcBucket,
    );

/// Eagerly initializes configuration, logging, the database, and the auth
/// runtime (printing the first-boot setup code when no users exist yet),
/// reconciles the YAML library with the database (hand edits made while the
/// server was down get picked up), and starts the daily backup timer.
/// Call once at startup.
ServerConfig initServer() {
  final config = serverConfig;
  _authRuntime ??= _initAuthRuntime();
  // Jobs only run inside this process; `running` rows at boot are
  // orphans from a restart and would poll as running forever.
  final orphaned = saltDatabase.failOrphanedNutritionJobs() +
      saltDatabase.failOrphanedImportJobs();
  if (orphaned > 0) {
    _log.warning('Marked $orphaned interrupted job(s) as failed');
  }
  try {
    scanLibrary(db: saltDatabase, config: config);
    // Boot must survive a broken library directory; the scan logs details.
    // ignore: avoid_catches_without_on_clauses
  } catch (error, stackTrace) {
    _log.severe('Startup library scan failed', error, stackTrace);
  }
  _scheduleDailyBackups(config);
  return config;
}

/// Releases process-wide resources for a clean exit: stops the backup
/// timer and closes the database (the final connection close checkpoints
/// and removes the WAL, so the next boot starts clean).
void disposeServer() {
  _backupTimer?.cancel();
  _backupTimer = null;
  _database?.dispose();
  _database = null;
}

/// Runs a `scheduled` backup daily, plus one at boot when the newest backup
/// is older than a day (covers servers that are not up for 24h straight).
void _scheduleDailyBackups(ServerConfig config) {
  if (_backupTimer != null) {
    return;
  }
  void run() {
    try {
      createBackup(db: saltDatabase, config: config, trigger: 'scheduled');
      // A failed backup must not kill the timer or the server; the backup
      // service logs details.
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stackTrace) {
      _log.severe('Scheduled backup failed', error, stackTrace);
    }
  }

  final newest = listBackups(config).firstOrNull;
  if (newest == null ||
      DateTime.now().toUtc().difference(newest.createdAt) >
          const Duration(hours: 24)) {
    run();
  }
  _backupTimer = Timer.periodic(const Duration(hours: 24), (_) => run());
}
