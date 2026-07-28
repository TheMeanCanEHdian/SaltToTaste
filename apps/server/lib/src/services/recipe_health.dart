import 'dart:convert';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_shared/salt_shared.dart';

/// The inputs a [RecipeCheck] inspects: the decoded recipe plus its computed
/// nutrition summary (null when nutrition was never computed).
class RecipeHealth {
  /// Bundles a decoded [recipe] with its [nutrition] summary for the checks.
  const RecipeHealth({required this.recipe, this.nutrition});

  /// The decoded recipe document.
  final Recipe recipe;

  /// The recipe's nutrition summary, or null if it was never computed.
  final NutritionSummary? nutrition;
}

/// The bit of the nutrition row a check needs.
class NutritionSummary {
  /// The match [status] plus [matched]/[total] line counts.
  const NutritionSummary({
    required this.status,
    required this.matched,
    required this.total,
  });

  /// `partial` (some lines unmatched) or `complete`.
  final String status;

  /// Ingredient lines that resolved to a food.
  final int matched;

  /// Total ingredient lines considered.
  final int total;
}

/// One recipe data-quality check.
///
/// The set of checks is an OPEN registry ([recipeChecks]): adding a category is
/// one entry here — the DB query, the endpoint, and the DTO are all generic
/// over it, so nothing else changes.
class RecipeCheck {
  /// Defines a check by its [id], display [label], [description], and
  /// [evaluate] predicate.
  const RecipeCheck({
    required this.id,
    required this.label,
    required this.description,
    required this.evaluate,
  });

  /// Stable machine id, also the `issue` filter value (e.g. `no_instructions`).
  final String id;

  /// Human-readable category name (e.g. `No instructions`).
  final String label;

  /// One-sentence definition of what puts a recipe in this category, surfaced
  /// in the app's help modal (so a new check documents itself).
  final String description;

  /// Returns a human-readable detail when the recipe HAS this issue, else null.
  final String? Function(RecipeHealth health) evaluate;
}

/// A `raw` line that STARTS with a quantity immediately followed by a known
/// measurement unit — the shape of an ingredient amount. A line matching this
/// but parsing no [Amount] is a real parse miss ("2 tablespoons juice"). It
/// deliberately does NOT match amountless prose that merely contains a number —
/// a dimension ("1-inch dice"), equipment ("2 pie plates"), or "salt to taste".
final RegExp _looksLikeAmount = RegExp(
  r'^\s*[0-9¼½¾⅓⅔⅕⅖⅗⅘⅛⅜⅝⅞][0-9¼½¾⅓⅔⅕⅖⅗⅘⅛⅜⅝⅞ ./-]*\s*'
  '(?:cups?|tablespoons?|tbsps?|teaspoons?|tsps?|ounces?|oz|pounds?|lbs?|'
  'grams?|g|kg|kilograms?|milliliters?|ml|liters?|l|quarts?|pints?|'
  'gallons?|sticks?|cloves?|cans?|jars?|packages?|pkgs?|envelopes?|'
  r'packets?|pinch|dash|sprigs?|slices?|heads?|bunch(?:es)?)\b',
  caseSensitive: false,
);

/// The registry, in display order. Each entry is independent and pure.
const List<RecipeCheck> recipeChecks = [
  RecipeCheck(
    id: 'no_instructions',
    label: 'No instructions',
    description: 'The recipe has no method steps at all.',
    evaluate: _noInstructions,
  ),
  RecipeCheck(
    id: 'unparsed_ingredients',
    label: 'Unparsed ingredients',
    description:
        'An ingredient line starts with a quantity and a unit '
        '(e.g. “2 tablespoons juice”) but no amount could be parsed from it. '
        'Lines with an incidental number — a dimension like “1-inch dice” or '
        'equipment like “2 pie plates” — are not flagged.',
    evaluate: _unparsedIngredients,
  ),
  RecipeCheck(
    id: 'incomplete_nutrition',
    label: 'Incomplete nutrition',
    description:
        'Nutrition was computed but some ingredient lines did not match a '
        'food, so the totals are partial (e.g. 12 of 13 matched).',
    evaluate: _incompleteNutrition,
  ),
  RecipeCheck(
    id: 'no_nutrition',
    label: 'No nutrition data',
    description: 'Nutrition has never been computed for this recipe.',
    evaluate: _noNutrition,
  ),
  RecipeCheck(
    id: 'extraction_warnings',
    label: 'Extraction warnings',
    description:
        'The extractor recorded a warning on this recipe (e.g. duplicate step '
        'numbering) that is worth a human glance.',
    evaluate: _extractionWarnings,
  ),
  RecipeCheck(
    id: 'no_servings',
    label: 'No servings',
    description:
        'The recipe has no numeric serving count, so per-serving nutrition '
        'cannot be computed.',
    evaluate: _noServings,
  ),
  RecipeCheck(
    id: 'serves_mismatch',
    label: 'Servings disagree',
    description:
        'The stored serving count disagrees with what the servings text '
        'says (e.g. the text was hand-edited to “SERVES 8” while the stored '
        'count still reads 6). A hand-set count on a text that states no '
        'servings at all is a deliberate override and is not flagged.',
    evaluate: _servesMismatch,
  ),
];

String? _noInstructions(RecipeHealth h) =>
    h.recipe.steps.isEmpty ? 'no method steps' : null;

String? _unparsedIngredients(RecipeHealth h) {
  final unparsed = <String>[
    for (final group in h.recipe.ingredients)
      for (final line in group.items)
        if (line.amounts.isEmpty && _looksLikeAmount.hasMatch(line.raw))
          line.raw,
  ];
  if (unparsed.isEmpty) {
    return null;
  }
  final sample = unparsed.take(2).map((r) => '“$r”').join(', ');
  return unparsed.length > 2 ? '$sample +${unparsed.length - 2} more' : sample;
}

String? _incompleteNutrition(RecipeHealth h) {
  final n = h.nutrition;
  if (n == null || n.status != 'partial') {
    return null;
  }
  return '${n.matched} / ${n.total} matched';
}

String? _noNutrition(RecipeHealth h) =>
    h.nutrition == null ? 'nutrition never computed' : null;

String? _extractionWarnings(RecipeHealth h) {
  final warnings = h.recipe.extraction?.warnings ?? const [];
  if (warnings.isEmpty) {
    return null;
  }
  return warnings.length == 1
      ? warnings.first
      : '${warnings.first} +${warnings.length - 1} more';
}

String? _noServings(RecipeHealth h) => h.recipe.serves == null
    ? 'no serving count — per-serving nutrition can’t be computed'
    : null;

String? _servesMismatch(RecipeHealth h) {
  // Both sides must state a value: a null stored count is `no_servings`'s
  // territory, and a hand-set count on an unparseable servings string is a
  // legitimate manual override (the corpus's yield-only recipes), not a
  // disagreement (review Y1/B9).
  final derived = parseServings(h.recipe.servings);
  final stored = h.recipe.serves;
  if (derived == null || stored == null) {
    return null;
  }
  if (derived.min == stored.min && derived.max == stored.max) {
    return null;
  }
  String range(Serves s) => s.min == s.max ? '${s.min}' : '${s.min}–${s.max}';
  return 'stored serves ${range(stored)} vs “${h.recipe.servings}” '
      '(parses to ${range(derived)})';
}

/// The expensive part of the report: the full flagged list plus whole-library
/// category counts, both independent of the `issue` filter and pagination.
class _ReviewScan {
  const _ReviewScan(this.key, this.flagged, this.categories);
  final String key;
  final List<RecipeReviewItem> flagged;
  final List<RecipeReviewCategory> categories;
}

/// Memoized full scan, keyed by the DB identity + its review fingerprint.
/// Paging and filter switches within one browsing session (no recipe writes
/// between them) reuse it instead of re-decoding the whole library each call.
_ReviewScan? _cachedScan;

/// The full scan for [db], from cache when the review fingerprint is unchanged,
/// otherwise recomputed (running every [recipeChecks] entry over every recipe)
/// and cached. Decoding every stored doc is the ~0.25s cost this memoizes.
_ReviewScan _reviewScan(SaltDatabase db) {
  // identityHashCode keeps two SaltDatabase instances (e.g. parallel tests)
  // from sharing a cache entry when their fingerprints happen to coincide.
  final key = '${identityHashCode(db)}|${db.recipeReviewFingerprint()}';
  final cached = _cachedScan;
  if (cached != null && cached.key == key) {
    return cached;
  }

  final counts = {for (final check in recipeChecks) check.id: 0};
  final flagged = <RecipeReviewItem>[];
  for (final row in db.recipeReviewScanRows()) {
    final recipe = RecipeMapper.fromMap(
      jsonDecode(row.doc) as Map<String, dynamic>,
    );
    final health = RecipeHealth(
      recipe: recipe,
      nutrition: row.nutStatus == null
          ? null
          : NutritionSummary(
              status: row.nutStatus!,
              matched: row.matched,
              total: row.total,
            ),
    );
    final issues = <RecipeReviewIssue>[];
    for (final check in recipeChecks) {
      final detail = check.evaluate(health);
      if (detail != null) {
        counts[check.id] = counts[check.id]! + 1;
        issues.add(
          RecipeReviewIssue(
            check: check.id,
            label: check.label,
            detail: detail,
          ),
        );
      }
    }
    if (issues.isNotEmpty) {
      flagged.add(
        RecipeReviewItem(
          id: row.id,
          slug: row.slug,
          title: row.title,
          source: row.source,
          issues: issues,
        ),
      );
    }
  }

  final categories = [
    for (final check in recipeChecks)
      RecipeReviewCategory(
        id: check.id,
        label: check.label,
        description: check.description,
        count: counts[check.id]!,
      ),
  ];
  final scan = _ReviewScan(key, flagged, categories);
  _cachedScan = scan;
  return scan;
}

/// Builds the recipe-review report. `issue`, when set, narrows the item list
/// (and its pagination) to recipes carrying that check; the category counts and
/// the overall total stay whole-library so the chips are stable across filters.
///
/// The whole-library scan is memoized (see [_reviewScan]) so paging and filter
/// switches only re-slice an already-decoded list; the scan reruns when a
/// recipe or nutrition write moves the fingerprint.
RecipeReviewReport buildRecipeReviewReport(
  SaltDatabase db, {
  required int page,
  required int limit,
  String? issue,
}) {
  final scan = _reviewScan(db);
  final filtered = issue == null
      ? scan.flagged
      : scan.flagged
            .where((item) => item.issues.any((i) => i.check == issue))
            .toList();
  final offset = (page - 1) * limit;
  final pageItems = offset >= filtered.length
      ? const <RecipeReviewItem>[]
      : filtered.sublist(offset, (offset + limit).clamp(0, filtered.length));

  return RecipeReviewReport(
    total: scan.flagged.length,
    categories: scan.categories,
    items: pageItems,
    page: page,
    limit: limit,
  );
}
