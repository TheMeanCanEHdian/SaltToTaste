import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/logging/log_store.dart';
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

/// The JSON body of `GET /api/v1/admin/logs`: recent persisted log records
/// (newest first, secrets already redacted) plus the distinct logger names for
/// the viewer's source filter.
///
/// [level] shows that severity bucket and above; [logger] filters to one
/// source; [query] is a message/request-id substring; [limit] caps the count.
Map<String, Object?> logsHandler(
  LogStore store, {
  required int limit,
  String? level,
  String? logger,
  String? query,
}) {
  LogEntryMapper.ensureInitialized();
  final result = store.query(
    minLevel: level,
    logger: logger,
    query: query,
    limit: limit,
  );
  return {
    'items': [for (final entry in result.items) entry.toMap()],
    'loggers': result.loggers,
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
