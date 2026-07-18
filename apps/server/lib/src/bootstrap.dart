import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/auth/setup_code.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/nutrition/fdc_provider.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/search/search_service.dart';
import 'package:salt_server/src/services/backup_service.dart';
import 'package:salt_server/src/services/library_scan.dart';
import 'package:salt_server/src/services/serves_backfill.dart';

final Logger _log = Logger('bootstrap');

/// Settings-table key holding the FDC API key. The value is a secret:
/// write-only through the API (reads return a masked form) and never
/// logged.
const String fdcApiKeySetting = 'fdc.api_key';

ServerConfig? _config;
SaltDatabase? _database;
AuthRuntime? _authRuntime;
RequestRateLimiter? _searchRateLimiter;
SearchService? _searchService;
LogStore? _logStore;
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
AuthRuntime get authRuntime => _authRuntime ??= initAuthRuntime(
  config: serverConfig,
  database: saltDatabase,
);

/// The process-wide search rate limiter, sized from [serverConfig] (the
/// `SEARCH_RATE_LIMIT` env, default 60/min per user; `0` disables it). Bounds
/// how much of the single serving isolate one caller's text searches can hold.
RequestRateLimiter get searchRateLimiter => _searchRateLimiter ??=
    RequestRateLimiter(maxRequests: serverConfig.searchRateLimit);

/// The process-wide, file-backed log store feeding the admin log viewer,
/// persisted under `<dataDir>/logs/` and rotated at `LOG_MAX_BYTES`.
/// [initServer] attaches it to the root logger at boot so it captures startup
/// records (secrets redacted on the way in). It survives restarts, so the
/// viewer shows history from before the current process.
LogStore get logStore => _logStore ??= LogStore(
  directory: serverConfig.logDir,
  maxBytes: serverConfig.logMaxBytes,
);

/// The process-wide search service (#48). [initSearchService] replaces this
/// with the background-isolate pool at startup; until then (and in tests) it
/// falls back to running search inline on the caller's isolate, so the provider
/// always resolves.
SearchService get searchService =>
    _searchService ??= InlineSearchService(saltDatabase);

/// Spawns the background search isolates sized from `SEARCH_WORKER_ISOLATES`
/// (default 1; `0` keeps search inline). Call once at startup AFTER the writer
/// connection has opened and migrated the database, so the read-only workers
/// can attach. Idempotent.
Future<void> initSearchService() async {
  if (_searchService is IsolateSearchService) {
    return;
  }
  final count = serverConfig.searchWorkerIsolates;
  if (count <= 0) {
    _searchService = InlineSearchService(saltDatabase);
    return;
  }
  _searchService = await IsolateSearchService.spawn(
    dbPath: serverConfig.dbPath,
    count: count,
  );
}

/// Tears down the background search isolates (closing their read-only
/// connections). Must run BEFORE [disposeServer], so the writer's final WAL
/// checkpoint is not blocked by a still-open reader.
Future<void> disposeSearchService() async {
  await _searchService?.dispose();
  _searchService = null;
}

/// Startup warnings for a configuration that LOOKS set up but is not.
///
/// Returned rather than printed so they can be tested. Every warning here
/// describes a config that fails closed silently, which is the shape of the
/// bug this surface was fixed for twice: `TRUSTED_PROXIES` that matched no
/// real peer looked configured and did nothing, and took the session cookie's
/// `Secure` attribute down with it. A guard nobody can see is worth little
/// more than no guard.
List<String> configWarnings(ServerConfig config) {
  final warnings = <String>[];
  if (config.devAllowCors) {
    // Reflected-origin CORS with credentials defeats the CSRF protection
    // entirely; this must never be enabled outside local development.
    warnings.add(
      'WARNING: DEV_ALLOW_CORS is enabled. Cross-origin requests with '
      'credentials are allowed and CSRF protection is OFF. '
      'Never run production with this flag.',
    );
  }
  if (config.trustProxy && config.trustedProxies.isEmpty) {
    // Fail closed, but loudly: TRUST_PROXY on its own now believes nobody, so
    // rate limits key on the proxy's own address and the whole household
    // shares one bucket. That is the safe direction — the alternative was
    // believing X-Forwarded-For from any peer, which let anyone mint a fresh
    // bucket per request — but it is silent unless we say so here.
    warnings.add(
      'WARNING: TRUST_PROXY is enabled but TRUSTED_PROXIES is empty, so no '
      'peer is trusted and forwarded headers are ignored. Rate limits will '
      "key on the proxy's address (one bucket for everyone behind it). Set "
      'TRUSTED_PROXIES to your proxy, e.g. 172.17.0.0/16 for a Docker bridge.',
    );
  }
  if (!config.trustProxy && config.trustedProxies.isNotEmpty) {
    // The mirror image, and the easier mistake to make: the list is set, so
    // the warning above cannot fire, but TRUST_PROXY gates the whole check.
    warnings.add(
      'WARNING: TRUSTED_PROXIES is set but TRUST_PROXY is not enabled, so the '
      'list is ignored entirely and no forwarded header is believed. Set '
      'TRUST_PROXY=true to use it.',
    );
  }
  final unusable = config.trustedProxies
      .where((entry) => !isUsableProxyEntry(entry))
      .toList();
  if (config.trustProxy && unusable.isNotEmpty) {
    // A non-empty list of entries that can never match reaches the same dead
    // end as an empty one, but slips past the warning above — the operator
    // sees a configured TRUSTED_PROXIES and is told nothing. Name the entries
    // rather than the count, since the whole failure is that they look fine.
    warnings.add(
      'WARNING: TRUSTED_PROXIES entries that can never match any peer and are '
      'being ignored: ${unusable.join(', ')}. Entries must be an exact '
      'address (10.0.0.5, ::1) or an IPv4 CIDR (172.17.0.0/16); an IPv6 CIDR '
      'and a hostname are both unsupported. Forwarded headers from the '
      'intended proxy will be ignored, so rate limits will key on its address '
      'and the session cookie will not gain Secure behind a TLS proxy.',
    );
  }
  return warnings;
}

/// Builds the auth runtime and performs the boot-time side effects that depend
/// on config and the database: it EMITS the [configWarnings] to [warn], drops
/// sessions that expired while the server was down, and on an empty user table
/// generates the first-boot setup code and announces it via
/// [announceSetupCode].
///
/// Takes [config] and [database] explicitly (rather than reading the process
/// globals) and routes its two side-effect streams through injectable sinks, so
/// the whole boot path can be driven from a test. That is the point: emitting
/// the warnings was untested wiring the b9c8330 review flagged — deleting the
/// `configWarnings(...).forEach(warn)` line used to leave the suite green, so a
/// config that fails closed silently would ship unannounced.
AuthRuntime initAuthRuntime({
  required ServerConfig config,
  required SaltDatabase database,
  void Function(String) warn = _stderrLine,
  void Function(String) announceSetupCode = _stdoutLine,
}) {
  final runtime = AuthRuntime();
  configWarnings(config).forEach(warn);
  // Housekeeping: drop sessions that expired while the server was down.
  database.deleteExpiredSessions();
  if (database.userCount() == 0) {
    final code = generateSetupCode();
    runtime.setupCode = code;
    // The one deliberate secret-on-stdout line in the server: the code exists
    // to be read from the console/container logs by the operator.
    announceSetupCode(
      'SaltToTaste setup code: $code '
      '— open the app to create the admin account.',
    );
  }
  return runtime;
}

void _stderrLine(String line) => stderr.writeln(line);
void _stdoutLine(String line) => stdout.writeln(line);

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
/// server was down get picked up), applies the one-shot serves-vs-yield
/// backfill, and starts the daily backup timer. Call once at startup.
ServerConfig initServer() {
  final config = serverConfig;
  // Start persisting log records now, before initAuthRuntime emits the setup
  // code, so the viewer has boot context (the code is redacted on the way in).
  logStore.attach(Logger.root.onRecord);
  _authRuntime ??= initAuthRuntime(config: config, database: saltDatabase);
  // Jobs only run inside this process; `running` rows at boot are
  // orphans from a restart and would poll as running forever.
  final orphaned =
      saltDatabase.failOrphanedNutritionJobs() +
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
  try {
    // After the scan, so hand edits made while the server was down are
    // already reconciled and this corrects `serves` on top of them.
    backfillServes(saltDatabase, config);
    // A one-shot data fix must never keep the server from booting.
    // ignore: avoid_catches_without_on_clauses
  } catch (error, stackTrace) {
    _log.severe('Serves backfill failed', error, stackTrace);
  }
  _scheduleDailyMaintenance(config);
  return config;
}

/// Releases process-wide resources for a clean exit: stops the backup
/// timer and closes the database (the final connection close checkpoints
/// and removes the WAL, so the next boot starts clean).
void disposeServer() {
  _backupTimer?.cancel();
  _backupTimer = null;
  unawaited(_logStore?.dispose());
  _logStore = null;
  _database?.dispose();
  _database = null;
}

/// Runs daily housekeeping: a `scheduled` backup (plus one at boot when the
/// newest backup is older than a day, covering servers not up 24h straight)
/// and a prune of revoked API tokens past their retention window. The prune
/// runs at every boot as well, so a long-lived server does not accumulate
/// revoked rows only to shed them on restart.
void _scheduleDailyMaintenance(ServerConfig config) {
  if (_backupTimer != null) {
    return;
  }
  void backup() {
    try {
      createBackup(db: saltDatabase, config: config, trigger: 'scheduled');
      // A failed backup must not kill the timer or the server; the backup
      // service logs details.
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stackTrace) {
      _log.severe('Scheduled backup failed', error, stackTrace);
    }
  }

  void maintain({required bool includeBackup}) {
    if (includeBackup) {
      backup();
    }
    _pruneRevokedApiTokens(config);
  }

  final newest = listBackups(config).firstOrNull;
  final backupDue =
      newest == null ||
      DateTime.now().toUtc().difference(newest.createdAt) >
          const Duration(hours: 24);
  // Boot: always prune; back up only when one is actually due.
  maintain(includeBackup: backupDue);
  _backupTimer = Timer.periodic(
    const Duration(hours: 24),
    (_) => maintain(includeBackup: true),
  );
}

/// Deletes revoked API tokens whose revocation is older than the configured
/// retention window ([ServerConfig.apiTokenRetentionDays]); a window of `0`
/// keeps them forever. A failed prune must never take the server down.
void _pruneRevokedApiTokens(ServerConfig config) {
  final days = config.apiTokenRetentionDays;
  if (days <= 0) {
    return;
  }
  try {
    final cutoff = DateTime.now().toUtc().subtract(Duration(days: days));
    final pruned = saltDatabase.deleteRevokedApiTokensBefore(cutoff);
    if (pruned > 0) {
      _log.info('Pruned $pruned revoked API token(s) older than $days days');
    }
    // Housekeeping must not keep the server from booting or kill the timer.
    // ignore: avoid_catches_without_on_clauses
  } catch (error, stackTrace) {
    _log.severe('Revoked-token prune failed', error, stackTrace);
  }
}
