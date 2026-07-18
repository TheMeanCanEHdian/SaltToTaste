import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/logging/log_buffer.dart';
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

/// The JSON body of `GET /api/v1/admin/logs`: recent buffered log records
/// (newest first, secrets already redacted) plus the buffer capacity and the
/// distinct logger names for the viewer's source filter.
///
/// [level] shows that severity bucket and above; [logger] filters to one
/// source; [query] is a message/request-id substring; [limit] caps the count.
Map<String, Object?> logsHandler(
  LogBuffer buffer, {
  required int limit,
  String? level,
  String? logger,
  String? query,
}) {
  LogEntryMapper.ensureInitialized();
  final entries = buffer.entries(
    minLevel: level,
    logger: logger,
    query: query,
    limit: limit,
  );
  return {
    'items': [for (final entry in entries) entry.toMap()],
    'capacity': buffer.capacity,
    'loggers': buffer.loggers,
  };
}
