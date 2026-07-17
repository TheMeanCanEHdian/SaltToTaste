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
  /// Defines a check by its [id], display [label], and [evaluate] predicate.
  const RecipeCheck({
    required this.id,
    required this.label,
    required this.evaluate,
  });

  /// Stable machine id, also the `issue` filter value (e.g. `no_instructions`).
  final String id;

  /// Human-readable category name (e.g. `No instructions`).
  final String label;

  /// Returns a human-readable detail when the recipe HAS this issue, else null.
  final String? Function(RecipeHealth health) evaluate;
}

/// Numbers and vulgar fractions — a `raw` ingredient line that contains one but
/// parsed no amount is a parse miss (as opposed to a genuinely amountless line
/// like "salt to taste", which we do not flag).
final RegExp _quantified = RegExp('[0-9¼½¾⅓⅔⅕⅖⅗⅘⅛⅜⅝⅞]');

/// The registry, in display order. Each entry is independent and pure.
const List<RecipeCheck> recipeChecks = [
  RecipeCheck(
    id: 'no_instructions',
    label: 'No instructions',
    evaluate: _noInstructions,
  ),
  RecipeCheck(
    id: 'unparsed_ingredients',
    label: 'Unparsed ingredients',
    evaluate: _unparsedIngredients,
  ),
  RecipeCheck(
    id: 'incomplete_nutrition',
    label: 'Incomplete nutrition',
    evaluate: _incompleteNutrition,
  ),
  RecipeCheck(
    id: 'no_nutrition',
    label: 'No nutrition data',
    evaluate: _noNutrition,
  ),
  RecipeCheck(
    id: 'extraction_warnings',
    label: 'Extraction warnings',
    evaluate: _extractionWarnings,
  ),
  RecipeCheck(
    id: 'no_servings',
    label: 'No servings',
    evaluate: _noServings,
  ),
];

String? _noInstructions(RecipeHealth h) =>
    h.recipe.steps.isEmpty ? 'no method steps' : null;

String? _unparsedIngredients(RecipeHealth h) {
  final unparsed = <String>[
    for (final group in h.recipe.ingredients)
      for (final line in group.items)
        if (line.amounts.isEmpty && _quantified.hasMatch(line.raw)) line.raw,
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

/// Builds the recipe-review report by running every [recipeChecks] entry over
/// every recipe. `issue`, when set, narrows the item list (and its pagination)
/// to recipes carrying that check; the category counts and the overall total
/// stay whole-library so the chips are stable across filters.
///
/// This scans and decodes every stored doc on each call. It is admin-only and
/// not a hot path; if the library grows large enough for that to bite, cache
/// the report and invalidate it on recipe writes.
RecipeReviewReport buildRecipeReviewReport(
  SaltDatabase db, {
  required int page,
  required int limit,
  String? issue,
}) {
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
        count: counts[check.id]!,
      ),
  ];

  final filtered = issue == null
      ? flagged
      : flagged
            .where((item) => item.issues.any((i) => i.check == issue))
            .toList();
  final offset = (page - 1) * limit;
  final pageItems = offset >= filtered.length
      ? const <RecipeReviewItem>[]
      : filtered.sublist(offset, (offset + limit).clamp(0, filtered.length));

  return RecipeReviewReport(
    total: flagged.length,
    categories: categories,
    items: pageItems,
    page: page,
    limit: limit,
  );
}
