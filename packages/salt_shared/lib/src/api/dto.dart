import 'package:dart_mappable/dart_mappable.dart';

part 'dto.mapper.dart';

/// A page of results from a list endpoint.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class Paged<T> with PagedMappable<T> {
  const Paged({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });

  final List<T> items;

  /// Total matching items across all pages.
  final int total;

  /// 1-based page index.
  final int page;
  final int limit;
}

/// The grid-card projection of a recipe returned by the list endpoint.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class RecipeCard with RecipeCardMappable {
  const RecipeCard({
    required this.id,
    required this.slug,
    required this.title,
    this.category,
    this.heroImage,
    this.tags = const [],
    this.servingsText,
    this.totalMinutes,
    this.caloriesPerServing,
    this.favorite = false,
    this.variationCount = 0,
  });

  final String id;
  final String slug;
  final String title;
  final String? category;

  /// Image URL path (e.g. `/images/<source-slug>/<file>.jpg`) or null.
  final String? heroImage;
  final List<String> tags;

  /// Verbatim servings string (`SERVES 6 TO 8`).
  final String? servingsText;
  final int? totalMinutes;

  /// Populated once nutrition is computed (P6); null until then.
  final double? caloriesPerServing;

  /// Whether the requesting user has favorited this recipe.
  final bool favorite;

  /// How many `variation` subsections the recipe carries — 0 for most.
  ///
  /// A COUNT rather than a flag, so a later `has:variants` filter or a
  /// "3 variations" label needs no second migration. Counts `variation` only:
  /// a `component` subsection is a sub-recipe (the dough for the pie), not a
  /// variant of the recipe, and badging those would be wrong.
  final int variationCount;

  /// Whether the recipe has any variation to show.
  bool get hasVariations => variationCount > 0;
}

/// The admin recipe-data-quality report (`GET /api/v1/admin/recipe-review`):
/// which recipes are missing or have incomplete data, grouped by issue.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class RecipeReviewReport with RecipeReviewReportMappable {
  const RecipeReviewReport({
    required this.total,
    required this.categories,
    required this.items,
    required this.page,
    required this.limit,
  });

  /// Distinct recipes with at least one issue (across all categories).
  final int total;

  /// Every check with its count, in display order (a count of 0 is included so
  /// the UI can render the full set of chips).
  final List<RecipeReviewCategory> categories;

  /// The flagged recipes on this page (narrowed by the `issue` filter).
  final List<RecipeReviewItem> items;

  /// 1-based page index over [items].
  final int page;
  final int limit;
}

/// One issue category and how many recipes currently have it.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class RecipeReviewCategory with RecipeReviewCategoryMappable {
  const RecipeReviewCategory({
    required this.id,
    required this.label,
    required this.count,
  });

  /// Stable machine id (e.g. `no_instructions`); also the `issue` filter value.
  final String id;
  final String label;
  final int count;
}

/// A flagged recipe with the specific issues found on it.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class RecipeReviewItem with RecipeReviewItemMappable {
  const RecipeReviewItem({
    required this.id,
    required this.slug,
    required this.title,
    required this.source,
    required this.issues,
  });

  final String id;
  final String slug;
  final String title;

  /// Source slug (e.g. `atk`) for a small provenance line.
  final String source;
  final List<RecipeReviewIssue> issues;
}

/// One issue on a recipe: the check that fired plus a human-readable detail.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class RecipeReviewIssue with RecipeReviewIssueMappable {
  const RecipeReviewIssue({
    required this.check,
    required this.label,
    required this.detail,
  });

  /// The [RecipeReviewCategory.id] this issue belongs to.
  final String check;
  final String label;

  /// e.g. `12 / 13 matched` or `no method steps`.
  final String detail;
}

/// The uniform API error envelope: `{"error": {code, message, request_id}}`.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class ApiError with ApiErrorMappable {
  const ApiError({required this.code, required this.message, this.requestId});

  /// Stable machine-readable code (e.g. `not_found`, `validation`,
  /// `internal`). The catalog lives in docs/API.md.
  final String code;

  /// Human-readable, actionable message. Never a stack trace.
  final String message;
  final String? requestId;
}
