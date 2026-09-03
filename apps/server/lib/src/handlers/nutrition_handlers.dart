import 'dart:convert';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';

/// `GET .../nutrition` body: the label data plus match transparency.
///
/// [forAdmin] gates `computing_job_id`. The id is only useful to a client that
/// can poll `/nutrition/jobs/<id>`, which is admin-only — sending it to a
/// member would have them poll an endpoint that 403s every time and surface
/// the failure as a compute error on a page they cannot compute from anyway.
Map<String, Object?> nutritionBody(
  SaltDatabase db,
  Recipe recipe, {
  required bool forAdmin,
}) {
  // A background compute in flight for this recipe (lets a reopened page
  // re-attach and keep showing progress instead of an enabled Compute button).
  final computingJobId = forAdmin ? recipeComputeJobId(recipe.id) : null;
  final row = db.nutritionFor(recipe.id);
  if (row == null) {
    return {
      'status': 'none',
      if (computingJobId != null) 'computing_job_id': computingJobId,
    };
  }
  final stale = row.ingredientsHash != ingredientsHashOf(recipe);
  // Unreviewed low-confidence matches: the UI's badge only turns green
  // once every line is matched AND none of these remain (a human
  // confirm/override clears one).
  final lineCount = nutritionLines(recipe).length;
  final lowConfidence = db
      .ingredientMatchesFor(recipe.id)
      .where(
        (match) =>
            match.position < lineCount &&
            match.status == 'auto' &&
            match.confidence < 0.5,
      )
      .length;
  return {
    'status': stale ? 'stale' : row.status,
    'serving_basis': row.servingBasis,
    'calories_per_serving': row.caloriesPerServing,
    'per_serving': jsonDecode(row.nutrientsJson),
    'total_grams': row.totalGrams,
    'matched_count': row.matchedCount,
    'total_count': row.totalCount,
    'low_confidence': lowConfidence,
    'computed_at': row.computedAt,
    if (computingJobId != null) 'computing_job_id': computingJobId,
  };
}

/// `GET /api/v1/nutrition/search` body: ranked FDC candidates for an
/// admin-typed term, in the same shape as a line's `candidates` so the review
/// sheet can reuse one row widget.
Future<Map<String, Object?>> foodSearchBody(
  SaltDatabase db,
  NutritionProvider provider,
  String query,
) async {
  final ranked = await searchCandidates(db, provider, query);
  return {
    'items': [
      for (final candidate in ranked)
        {
          'fdc_id': candidate.candidate.fdcId,
          'description': candidate.candidate.description,
          'data_type': candidate.candidate.dataType,
          'confidence': candidate.confidence,
        },
    ],
  };
}

/// `GET .../nutrition/matches` body: one entry per ingredient line with the
/// stored decision and (for re-picking) the top-ranked candidates.
Future<Map<String, Object?>> matchesBody(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe recipe,
) async {
  final lines = nutritionLines(recipe);
  final matches = {
    for (final row in db.ingredientMatchesFor(recipe.id)) row.position: row,
  };
  final items = <Map<String, Object?>>[];
  for (final (position, line) in lines.indexed) {
    var row = matches[position];
    // A stored decision whose raw text no longer matches the line belongs
    // to a PREVIOUS ingredient list (edit/insert since the last compute) —
    // showing it against the new text would be a lie.
    if (row != null && row.raw != line.raw) {
      row = null;
    }
    // Cache-only: a GET must never spend FDC budget or block on the rate
    // limiter (members can call this).
    final candidates = row == null
        ? const <RankedCandidate>[]
        : await candidatesForLine(db, provider, line, cacheOnly: true);
    final itemKey = normalizeItem(line.item ?? line.raw);
    items.add({
      'position': position,
      'raw': line.raw,
      // How many OTHER recipes hold an undecided line with this item — what
      // an apply-to-all from here would reach.
      'others': itemKey.isEmpty
          ? 0
          : db.otherRecipesUndecidedCount(
              itemKey,
              excludingRecipeId: recipe.id,
            ),
      'match': row == null
          ? null
          : {
              'fdc_id': row.fdcId,
              'description': row.description,
              'data_type': row.dataType,
              'confidence': row.confidence,
              'grams': row.grams,
              'gram_source': row.gramSource,
              // What the grams were computed against, so a reviewer can
              // sanity-check a volume/piece estimate. Cache-only.
              'gram_basis': gramBasisFor(db, line, row),
              'status': row.status,
            },
      'candidates': [
        for (final ranked in candidates)
          {
            'fdc_id': ranked.candidate.fdcId,
            'description': ranked.candidate.description,
            'data_type': ranked.candidate.dataType,
            'confidence': ranked.confidence,
          },
      ],
    });
  }
  return {'items': items};
}

/// What an `apply_to_all` reached: recipes and lines changed.
typedef AppliedToOthers = ({int recipes, int lines});

/// Applies a `PUT .../nutrition/matches/<pos>` override [body] and
/// recomputes the stored totals (no FDC searches; at most one cached food
/// fetch for a re-pick). With `apply_to_all: true`, also lands the decided
/// food on every other recipe's undecided line of the same item and returns
/// what that reached; null otherwise.
Future<AppliedToOthers?> applyMatchOverride(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe recipe,
  int position,
  Map<String, Object?> body,
) async {
  final lines = nutritionLines(recipe);
  if (position < 0 || position >= lines.length) {
    throw NotFoundException('No ingredient line at position $position.');
  }
  final line = lines[position];
  final itemKey = normalizeItem(line.item ?? line.raw);
  final existing = {
    for (final row in db.ingredientMatchesFor(recipe.id)) row.position: row,
  };
  var row = existing[position];
  // A decision always applies to the line's CURRENT text: rows carrying a
  // pre-edit raw would be silently reverted by the next compute (and
  // grams applied under old text would mislead). Start fresh in that case.
  if (row == null || row.raw != line.raw) {
    row = IngredientMatchRow(
      recipeId: recipe.id,
      position: position,
      raw: line.raw,
      fdcId: row?.fdcId,
      description: row?.description,
      dataType: row?.dataType,
      confidence: row?.confidence ?? 0,
      grams: row?.grams,
      gramSource: row?.gramSource,
      status: row?.status ?? 'unmatched',
      itemKey: itemKey,
    );
  }

  final applyToAll = body['apply_to_all'];
  if (applyToAll != null && applyToAll is! bool) {
    throw const ValidationException("'apply_to_all' must be true or false.");
  }
  final skipped = body['skipped'];
  final confirmed = body['confirmed'];
  final fdcId = body['fdc_id'];
  final grams = body['grams'];

  if (skipped == true) {
    row = row.copyWith(status: 'skipped');
  } else if (skipped == false) {
    // Un-skip returns the line to automatic triage. It must NOT set
    // 'confirmed': blessing whatever low-confidence match the line had
    // would hide it from the review queue as resolved (review B7).
    row = row.copyWith(status: 'auto');
  } else if (fdcId != null) {
    if (fdcId is! num || fdcId <= 0) {
      throw const ValidationException("'fdc_id' must be a positive number.");
    }
    final food = await cachedFood(db, provider, fdcId.toInt());
    if (food == null) {
      throw const ValidationException(
        'FoodData Central has no food with that id.',
      );
    }
    final resolution = resolveGrams(
      amounts: line.amounts,
      food: food,
      normalizedItem: normalizeItem(line.item ?? line.raw),
      raw: line.raw,
    );
    row = row.copyWith(
      fdcId: food.fdcId,
      description: food.description,
      dataType: food.dataType,
      confidence: 1,
      grams: resolution?.grams,
      clearGrams: resolution == null,
      gramSource: resolution?.source.name,
      clearGramSource: resolution == null,
      status: 'overridden',
    );
  } else if (confirmed == true) {
    row = row.copyWith(status: 'confirmed');
  }

  if (grams != null) {
    if (grams is! num || grams <= 0 || grams > 100000) {
      throw const ValidationException(
        "'grams' must be a positive number (at most 100000).",
      );
    }
    if (row.fdcId == null) {
      // Grams without a matched food contribute nothing — a silent no-op
      // the user would mistake for success.
      throw const ValidationException(
        'Pick a matching food first, then set the grams.',
      );
    }
    row = row.copyWith(
      grams: grams.toDouble(),
      gramSource: GramSource.override.name,
      status: row.status == 'auto' ? 'overridden' : row.status,
    );
  }

  if (skipped == null && confirmed == null && fdcId == null && grams == null) {
    throw const ValidationException(
      "Provide at least one of 'fdc_id', 'grams', 'confirmed', 'skipped'.",
    );
  }
  // Everything apply_to_all needs is checked BEFORE the line is written, so
  // a refused request changes nothing — not the line, not the totals.
  FdcFood? food;
  if (applyToAll == true) {
    if (row.fdcId == null ||
        (row.status != 'overridden' && row.status != 'confirmed')) {
      throw const ValidationException(
        "'apply_to_all' needs a food decision on this line — pick or "
        'confirm a food.',
      );
    }
    if (itemKey.isEmpty) {
      throw const ValidationException(
        'Nothing searchable in this line to match other recipes on.',
      );
    }
    food = await cachedFood(db, provider, row.fdcId!);
    if (food == null) {
      throw const ValidationException(
        'FoodData Central has no food with that id.',
      );
    }
  }

  db.upsertIngredientMatch(row.copyWith(itemKey: itemKey));
  await recomputeTotals(db, provider, recipe);

  if (food == null) {
    return null;
  }
  return applyDecisionToOthers(
    db,
    provider,
    itemKey: itemKey,
    food: food,
    excludingRecipeId: recipe.id,
  );
}

/// Masks a stored API key for display: last four characters only.
String maskKey(String key) =>
    key.length <= 4 ? '****' : '****${key.substring(key.length - 4)}';
