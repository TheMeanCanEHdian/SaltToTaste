import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/services/nutrition_review.dart';
import 'package:salt_server/src/services/recipe_health.dart';
import 'package:salt_shared/salt_shared.dart';

/// The JSON body of `GET /api/v1/admin/recipe_review`: the recipe
/// data-quality report ([RecipeReviewReport]).
///
/// [issue], when a non-empty known check id, narrows the item list to recipes
/// carrying that issue; an unknown id is a 422 rather than a silent empty list.
Map<String, Object?> recipeReviewHandler(
  SaltDatabase db, {
  required int page,
  required int limit,
  String? issue,
}) {
  final filter = (issue == null || issue.isEmpty) ? null : issue;
  if (filter != null && !recipeChecks.any((check) => check.id == filter)) {
    throw ValidationException('Unknown issue filter: $filter');
  }
  final report = buildRecipeReviewReport(
    db,
    issue: filter,
    page: page,
    limit: limit,
  );
  // Register the mappers so the nested DTOs encode at runtime (idempotent).
  RecipeReviewReportMapper.ensureInitialized();
  return report.toMap();
}

/// The JSON body of `GET /api/v1/admin/nutrition_review`: the cross-recipe
/// queue of ingredient-match lines that still need a look.
///
/// [bucket], when a non-empty known triage bucket, narrows the item list to
/// that bucket; an unknown id is a 422 rather than a silent empty list.
Map<String, Object?> nutritionReviewHandler(
  SaltDatabase db, {
  required int page,
  required int limit,
  String? bucket,
}) {
  final filter = (bucket == null || bucket.isEmpty) ? null : bucket;
  if (filter != null && !nutritionReviewBucketLabels.containsKey(filter)) {
    throw ValidationException('Unknown bucket filter: $filter');
  }
  return buildNutritionReview(db, bucket: filter, page: page, limit: limit);
}

/// The JSON body of `GET /api/v1/admin/logs`: recent persisted log records
/// (newest first, secrets already redacted) plus the distinct logger names for
/// the viewer's source filter.
///
/// [level] shows that severity bucket and above; [logger] filters to one
/// source; [query] is a message/request-id substring; [limit] caps the count.
///
/// [fullScan] chooses the read strategy. The recurring Live poll leaves it
/// false and reads only a recent tail (a few ms, on the serving isolate). An
/// explicit filter/search sets it true, reading the WHOLE history off the
/// serving isolate so a large log doesn't stall other requests.
Future<Map<String, Object?>> logsHandler(
  LogStore store, {
  required int limit,
  String? level,
  String? logger,
  String? query,
  bool fullScan = false,
}) async {
  LogEntryMapper.ensureInitialized();
  final result = fullScan
      ? await store.queryFull(
          minLevel: level,
          logger: logger,
          query: query,
          limit: limit,
        )
      : store.query(
          minLevel: level,
          logger: logger,
          query: query,
          limit: limit,
          maxScanBytes: logViewerScanBytes,
        );
  return {
    'items': [for (final entry in result.items) entry.toMap()],
    // The dropdown lists ALL loggers in history (store.knownLoggers), not just
    // those in this read's window — a tail poll would otherwise drop a quiet
    // logger older than the 512 KiB window and make it unselectable.
    'loggers': store.knownLoggers,
  };
}

/// The download body + filename of `GET /api/v1/admin/logs/export`: the full
/// matching log (no row cap, honoring [level]/[logger]/[query]) as one text
/// line per record, oldest-first — the way a log file conventionally reads.
///
/// Secrets are already redacted in the store, so this is safe to hand out. The
/// filename carries a UTC timestamp so repeated downloads don't collide.
({String filename, String body}) logsExportHandler(
  LogStore store, {
  String? level,
  String? logger,
  String? query,
}) {
  // No row cap on an explicit export — read everything that matches.
  final result = store.query(
    minLevel: level,
    logger: logger,
    query: query,
    limit: 1 << 30,
  );
  final buffer = StringBuffer();
  // query() is newest-first; a downloaded log reads oldest-first.
  for (final entry in result.items.reversed) {
    buffer
      ..write(entry.time)
      ..write(' ')
      ..write(entry.level)
      ..write(' ')
      ..write(entry.logger)
      ..write(' ')
      ..write(entry.message);
    if (entry.requestId != null) {
      buffer
        ..write(' rid=')
        ..write(entry.requestId);
    }
    buffer.writeln();
  }
  final stamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .split('.')
      .first
      .replaceAll(':', '');
  return (filename: 'salttotaste-logs-$stamp.log', body: buffer.toString());
}
