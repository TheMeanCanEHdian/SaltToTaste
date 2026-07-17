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
