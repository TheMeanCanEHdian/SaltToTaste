import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
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
