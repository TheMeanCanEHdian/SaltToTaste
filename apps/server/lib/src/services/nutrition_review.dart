/// Builds the cross-recipe nutrition-match review report — every ingredient
/// line that still needs a look, across all computed recipes, in one queue.
library;

import 'package:salt_server/src/db/salt_database.dart';

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
Map<String, Object?> buildNutritionReview(
  SaltDatabase db, {
  required int page,
  required int limit,
  String? bucket,
}) {
  final counts = db.nutritionReviewCounts();
  final total = nutritionReviewFlaggedBuckets.fold<int>(
    0,
    (sum, b) => sum + (counts[b] ?? 0),
  );
  final offset = (page - 1) * limit;
  final lines = db.nutritionReviewLines(
    bucket: bucket,
    limit: limit,
    offset: offset,
  );
  return {
    'total': total,
    'buckets': [
      for (final b in [...nutritionReviewFlaggedBuckets, 'skipped'])
        {
          'id': b,
          'label': nutritionReviewBucketLabels[b],
          'count': counts[b] ?? 0,
        },
    ],
    'items': [
      for (final line in lines) _lineJson(line),
    ],
    'page': page,
    'limit': limit,
  };
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
          },
  };
}
