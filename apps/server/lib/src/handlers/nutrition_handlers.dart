import 'dart:convert';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';

/// `GET .../nutrition` body: the label data plus match transparency.
Map<String, Object?> nutritionBody(SaltDatabase db, Recipe recipe) {
  final row = db.nutritionFor(recipe.id);
  if (row == null) {
    return {'status': 'none'};
  }
  final stale = row.ingredientsHash != ingredientsHashOf(recipe);
  // Unreviewed low-confidence matches: the UI's badge only turns green
  // once every line is matched AND none of these remain (a human
  // confirm/override clears one).
  final lineCount = nutritionLines(recipe).length;
  final lowConfidence = db
      .ingredientMatchesFor(recipe.id)
      .where((match) =>
          match.position < lineCount &&
          match.status == 'auto' &&
          match.confidence < 0.5)
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
    items.add({
      'position': position,
      'raw': line.raw,
      'match': row == null
          ? null
          : {
              'fdc_id': row.fdcId,
              'description': row.description,
              'data_type': row.dataType,
              'confidence': row.confidence,
              'grams': row.grams,
              'gram_source': row.gramSource,
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

/// Applies a `PUT .../nutrition/matches/<pos>` override [body] and
/// recomputes the stored totals (no FDC searches; at most one cached food
/// fetch for a re-pick).
Future<void> applyMatchOverride(
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
    );
  }

  final skipped = body['skipped'];
  final confirmed = body['confirmed'];
  final fdcId = body['fdc_id'];
  final grams = body['grams'];

  if (skipped == true) {
    row = row.copyWith(status: 'skipped');
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
  db.upsertIngredientMatch(row);
  await recomputeTotals(db, provider, recipe);
}

/// Masks a stored API key for display: last four characters only.
String maskKey(String key) => key.length <= 4
    ? '****'
    : '****${key.substring(key.length - 4)}';
