/// Builds the cross-recipe nutrition-match review report — every ingredient
/// line that still needs a look, across all computed recipes, in one queue.
library;

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_shared/salt_shared.dart';

/// Human labels for the triage buckets (the filter chips + row badges).
const Map<String, String> nutritionReviewBucketLabels = {
  'no_match': 'No match',
  'no_grams': 'No grams',
  'check': 'Low confidence',
  'skipped': 'Skipped',
};

/// The buckets that count as "needs attention" (the queue's default view).
/// `skipped` is browsable but excluded from the total and the default list.
const List<String> nutritionReviewFlaggedBuckets = [
  'no_match',
  'no_grams',
  'check',
];

/// Builds the report body for `GET /api/v1/admin/nutrition_review`. [bucket],
/// when set, narrows the item list (and its pagination) to one triage bucket;
/// the bucket counts and the overall total stay whole-library so the chips are
/// stable across filters (mirrors the recipe-review report).
///
/// [grouped] switches the ITEMS (and their pagination) to one row per
/// ingredient — the group's example line, flattened exactly like a line item
/// so every consumer parses it unchanged, plus the group's key, reach,
/// decided flag and amount spread. The counts never change unit: `total` and
/// `buckets[].count` are lines in both modes, and `groups` — top level and
/// per bucket — is reported in both, so a header can say "81 ingredients,
/// 118 lines" without a second request.
Map<String, Object?> buildNutritionReview(
  SaltDatabase db, {
  required int page,
  required int limit,
  String? bucket,
  bool grouped = false,
}) {
  final counts = db.nutritionReviewCounts();
  final groupCounts = db.nutritionReviewGroupCounts();
  final total = nutritionReviewFlaggedBuckets.fold<int>(
    0,
    (sum, b) => sum + (counts[b] ?? 0),
  );
  final offset = (page - 1) * limit;
  final items = grouped
      ? _groupItems(
          db,
          db.nutritionReviewGroups(
            bucket: bucket,
            limit: limit,
            offset: offset,
          ),
        )
      : [
          for (final line in db.nutritionReviewLines(
            bucket: bucket,
            limit: limit,
            offset: offset,
          ))
            _lineJson(line),
        ];
  return {
    'total': total,
    'groups': groupCounts.flagged,
    'buckets': [
      for (final b in [...nutritionReviewFlaggedBuckets, 'skipped'])
        {
          'id': b,
          'label': nutritionReviewBucketLabels[b],
          'count': counts[b] ?? 0,
          'groups': groupCounts.byBucket[b] ?? 0,
        },
    ],
    'items': items,
    'page': page,
    'limit': limit,
  };
}

/// The group rows as JSON: each one a line item (the example) plus the group's
/// own fields. `item` — the example line's parsed ingredient, what the app
/// labels the row with — is the one field the database cannot supply
/// (`ingredient_matches` stores no item text), so the example's recipe is
/// decoded for it, memoised per recipe: at most one decode per row on a page.
List<Map<String, Object?>> _groupItems(
  SaltDatabase db,
  List<NutritionReviewGroupRow> groups,
) {
  final byRecipe = <String, List<IngredientLine>?>{};
  return [
    for (final group in groups)
      {
        ..._lineJson((
          match: group.match,
          slug: group.slug,
          title: group.title,
          bucket: group.bucket,
        )),
        'item_key': group.itemKey,
        'item': _exampleItem(db, byRecipe, group.match),
        'lines': group.lines,
        'recipes': group.recipes,
        'decided': group.decided,
        'grams': {
          'min': group.gramsMin,
          'max': group.gramsMax,
          'missing': group.gramsMissing,
        },
      },
  ];
}

/// The parsed ingredient item of [match]'s line, VERBATIM — the same string
/// `GET …/nutrition/matches` reports for it. Null when the recipe will not
/// decode, the position is past its end, or the line's text has changed since
/// the row was written (the row then describes a line that no longer exists,
/// and naming it after the new text would be a lie).
String? _exampleItem(
  SaltDatabase db,
  Map<String, List<IngredientLine>?> byRecipe,
  IngredientMatchRow match,
) {
  final lines = byRecipe.putIfAbsent(match.recipeId, () {
    try {
      final found = db.recipeByIdOrSlug(match.recipeId);
      return found == null ? null : nutritionLines(found.recipe);
      // recipeByIdOrSlug DECODES: one recipe whose stored document no longer
      // parses must cost this row its label, not the whole queue a 500 (the
      // line mode decodes nothing and cannot fail that way).
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  });
  if (lines == null || match.position >= lines.length) {
    return null;
  }
  final line = lines[match.position];
  return line.raw == match.raw ? line.item : null;
}

Map<String, Object?> _lineJson(NutritionReviewLineRow line) {
  final match = line.match;
  return {
    'recipe': {'id': match.recipeId, 'slug': line.slug, 'title': line.title},
    'position': match.position,
    'raw': match.raw,
    'bucket': line.bucket,
    // The stored match for the row display; candidates are fetched lazily from
    // the per-recipe matches endpoint when a row is opened.
    'match': match.fdcId == null
        ? null
        : {
            'fdc_id': match.fdcId,
            'description': match.description,
            'data_type': match.dataType,
            'confidence': match.confidence,
            'grams': match.grams,
            'gram_source': match.gramSource,
            'status': match.status,
            'hold': match.hold,
          },
  };
}
