import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_shared/salt_shared.dart';

/// Default `limit` for the recipe list endpoint.
const int defaultRecipeListLimit = 24;

/// Maximum `limit` for the recipe list endpoint.
const int maxRecipeListLimit = 100;

/// Parses and validates the `page`/`limit` query parameters of the recipe
/// list endpoint.
///
/// `page` defaults to 1 and must be an integer >= 1; `limit` defaults to
/// [defaultRecipeListLimit] and must be an integer in
/// 1..[maxRecipeListLimit]. Throws [ValidationException] on any other value.
({int page, int limit}) parseListParams(Map<String, String> query) {
  final page = _parsePositiveInt(query, 'page', defaultValue: 1);
  final limit = _parsePositiveInt(
    query,
    'limit',
    defaultValue: defaultRecipeListLimit,
  );
  if (limit > maxRecipeListLimit) {
    throw ValidationException(
      'limit must be an integer between 1 and $maxRecipeListLimit, '
      "got '${query['limit']}'.",
    );
  }
  return (page: page, limit: limit);
}

int _parsePositiveInt(
  Map<String, String> query,
  String name, {
  required int defaultValue,
}) {
  final raw = query[name];
  if (raw == null) {
    return defaultValue;
  }
  final value = int.tryParse(raw);
  if (value == null || value < 1) {
    throw ValidationException("$name must be an integer >= 1, got '$raw'.");
  }
  return value;
}

/// One page of recipe cards as the JSON body of `GET /api/v1/recipes`:
/// `{"items": [...], "total": n, "page": p, "limit": l}`.
Map<String, Object?> listRecipes(
  SaltDatabase db, {
  required int page,
  required int limit,
}) {
  final result = db.listCards(page: page, limit: limit);
  return {
    'items': [for (final card in result.items) card.toMap()],
    'total': result.total,
    'page': page,
    'limit': limit,
  };
}

/// The JSON body of `GET /api/v1/recipes/<key>`: the full recipe document
/// plus its source slug and serving URL for the hero image (or null).
///
/// [key] matches either the recipe id or its slug; throws
/// [NotFoundException] when neither matches.
Map<String, Object?> recipeDetail(SaltDatabase db, String key) {
  final found = _recipeOrThrow(db, key);
  return {
    'recipe': found.recipe.toMap(),
    'source_slug': found.sourceSlug,
    'hero_image_url':
        _heroImageUrl(found.recipe.images.hero, found.sourceSlug),
  };
}

/// The canonical v2 YAML export of the recipe matched by [key] (id or slug),
/// plus the download file name `<recipe id>.yaml`.
///
/// Throws [NotFoundException] when no recipe matches.
({String yaml, String fileName}) recipeYaml(SaltDatabase db, String key) {
  final found = _recipeOrThrow(db, key);
  return (
    yaml: RecipeYamlCodec.encode(found.recipe),
    fileName: '${found.recipe.id}.yaml',
  );
}

({Recipe recipe, String sourceSlug}) _recipeOrThrow(
  SaltDatabase db,
  String key,
) {
  final found = db.recipeByIdOrSlug(key);
  if (found == null) {
    throw NotFoundException('recipe not found: $key');
  }
  return found;
}

/// Rewrites the doc-relative hero path (`images/<file>`) to its serving URL
/// `/images/<source_slug>/<basename>`; null in, null out.
String? _heroImageUrl(String? heroImage, String sourceSlug) {
  if (heroImage == null || heroImage.isEmpty) {
    return null;
  }
  const prefix = 'images/';
  final basename = heroImage.startsWith(prefix)
      ? heroImage.substring(prefix.length)
      : heroImage.split('/').last;
  return '/images/$sourceSlug/$basename';
}
