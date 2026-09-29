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
  // Unreviewed low-confidence or held matches — the `check` bucket: the
  // UI's badge only turns green once every line is matched AND none of these
  // remain (a human confirm/override clears one).
  final lineCount = nutritionLines(recipe).length;
  final lowConfidence = db
      .ingredientMatchesFor(recipe.id)
      .where(
        (match) =>
            match.position < lineCount &&
            matchBucketFor(
                  status: match.status,
                  fdcId: match.fdcId,
                  grams: match.grams,
                  confidence: match.confidence,
                  hold: match.hold,
                  gramSource: match.gramSource,
                ) ==
                MatchBucket.check,
      )
      .length;
  return {
    'status': stale ? 'stale' : row.status,
    'serving_basis': row.servingBasis,
    'basis_kind': basisKindOf(
      row.servingBasis ?? 1,
      servings: recipe.servings,
    ),
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
  String query, {
  bool fresh = false,
}) async {
  // What the cache held BEFORE this search decides whether the answer was
  // served from it; the entry afterwards says when it was fetched.
  final key = searchQueryFor(normalizeItem(query));
  final before = key.isEmpty ? null : db.fdcSearchCacheEntry(key);
  final ranked = await searchCandidates(db, provider, query, fresh: fresh);
  final after = key.isEmpty ? null : db.fdcSearchCacheEntry(key);
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
    // The words FDC was actually asked (after normalization and rewrites),
    // whether this answer came from the cache, and when it was fetched.
    'query': key,
    'cached': before != null && !fresh,
    'cached_at': after?.fetchedAt,
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
    final itemKey = lineKeyOf(line);
    // How far an apply-to-all from this line would reach: the undecided lines
    // of the same ingredient, in recipes and in lines — a sibling on another
    // food at any score, a sibling on THIS food only while it is still a
    // flagged guess (below `lowConfidence`); one already counted waits on
    // nothing this decision can give it, and neither does a line-held row or
    // a line naming a second food. The same rows the apply writes.
    final reach = itemKey.isEmpty
        ? const <IngredientMatchRow>[]
        : decisionReach(
            db,
            itemKey,
            excluding: (recipeId: recipe.id, position: position),
            fdcId: row?.fdcId,
          );
    // The KEY (singular) joins decisions; the QUERY keeps the line's words —
    // reported as the words whose cached answer the line reads (a same-key
    // sibling's, or an "A or B" line's A), so a live search lands there.
    final search = itemKey.isEmpty
        ? null
        : lineSearchFor(db, normalizeItem(lineItemOf(line)), itemKey);
    final query = search?.answer;
    // The picked record's USDA portions, from the cache alone (a search hit
    // stand-in has none): what the fix sheet's amount block offers.
    final food = row?.fdcId == null
        ? null
        : knownFood(db, row!.fdcId!, line: line);
    items.add({
      'position': position,
      'raw': line.raw,
      // The parsed ingredient item ("unsalted butter"), null when the line
      // has none — what an apply-to-all offer names, since `others` is
      // counted by item, not by line.
      'item': line.item,
      // The line's first unit amount as written ("4 stick"), null when none.
      'line_amount': lineAmountText(line.amounts),
      // The picked record's calories per 100 g, from the same cache: the
      // fix sheet says it where a line has no amount yet.
      'kcal_per_100g': food == null ? null : kcalPer100g(food),
      // The picked record's cached portions, each with `fill`: the grams
      // the line's unit amount weighs on it when the portion names that
      // unit (4 × stick 113 g = 452), else null. Empty when the record's
      // detail was never fetched, or nothing is picked. Never a fetch.
      'portions': [
        for (final portion in food?.portions ?? const <FdcPortion>[])
          {
            'amount': portion.amount,
            'unit': portion.unit,
            'description': portion.description,
            'grams': portion.gramWeight,
            'fill': portionFill(portion, line.amounts),
          },
      ],
      // How many OTHER recipes hold an undecided line with this item — what
      // an apply-to-all from here would reach — and how many lines that is.
      'others': {for (final other in reach) other.recipeId}.length,
      'others_lines': reach.length,
      // The words FDC is asked for this line's candidates (after the
      // matcher's rewrites — "spices pepper black" for a pepper line), and
      // when it was last asked (the search cache never expires); null when
      // the line has nothing searchable / was never asked.
      'candidates_query': query,
      // False when the answer holds no record of the food at all — a list
      // that is hopeless, not mis-ranked; null when never searched.
      'candidates_name_ingredient': search == null
          ? null
          : _answerNamesIngredient(db, search.query, search.answer),
      'candidates_cached_at': query == null
          ? null
          : db.fdcSearchCacheEntry(query)?.fetchedAt,
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
              // Why an `auto` row is held out of the totals although its
              // score passes (`no_nutrients` | `discarded_medium` |
              // `second_food`); null when nothing holds it.
              'hold': row.hold,
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

/// What an `apply_to_all` reached: recipes and lines changed, recipes that
/// failed part-way (logged; their earlier lines stay as written), and the
/// reached recipes the apply completed (and their ids).
typedef AppliedToOthers = ({
  int recipes,
  int lines,
  int failed,
  int completed,
  List<String> completedRecipes,
});

/// The receipt's wire shape (`applied` on the `PUT …/matches/{pos}` body).
Map<String, Object?> appliedJson(AppliedToOthers applied) => {
  'recipes': applied.recipes,
  'lines': applied.lines,
  'failed': applied.failed,
  'completed': applied.completed,
  'completed_recipes': applied.completedRecipes,
};

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
  Map<String, Object?> body, {
  int? decidedBy,
}) async {
  final lines = nutritionLines(recipe);
  if (position < 0 || position >= lines.length) {
    throw NotFoundException('No ingredient line at position $position.');
  }
  final line = lines[position];
  final itemKey = lineKeyOf(line);
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

  // One verb at a time: `skipped` together with a food verb would let the
  // status chain drop the food (skip wins) while the decision below still
  // fired on the request — recording the engine's own guess as a person's
  // decision, library-wide. Refuse rather than guess (review, 2026-09-07).
  if (skipped != null && (fdcId != null || confirmed != null)) {
    throw const ValidationException(
      "'skipped' cannot be combined with 'fdc_id' or 'confirmed'.",
    );
  }
  // Set only by the branches that PUT a food on the row in this request.
  var decidedFood = false;
  if (skipped == true) {
    row = row.copyWith(status: 'skipped');
  } else if (skipped == false) {
    // Un-skip returns the line to automatic triage. It must NOT set
    // 'confirmed': blessing whatever low-confidence match the line had
    // would hide it from the review queue as resolved (review B7). Its hold
    // is re-derived for the food now on the row — never an engine-era hold
    // left over from another food. A person's food (confidence 1: a pick or
    // a decision, inherited or not) answers every FOOD hold, never a LINE
    // hold ([engineOutcome] with `decided`): a discarded medium, a second
    // food, shellfish bought in the shell stay held — an un-skip is no
    // confirm, and a decision inherited from another recipe was never a
    // look at this line (v11: skip then un-skip counted 1,814 g of mussels
    // in the shell, 0294). Only a confirm or a pick clears them. An engine
    // row whose line the second-food rule counts moves to the rule's record
    // with the rule's grams, as a fresh compute writes it (checkpoint 5
    // review: an un-skip left a rule line held on the peel for good).
    row = row.copyWith(status: 'auto', clearHold: true);
    final personal = row.confidence >= 1;
    final byRule = personal || secondFoodRuleOf(line)?.fdcId == row.fdcId
        ? null
        : await ruleRowFor(db, provider, recipe, position, line);
    final onRow = row.fdcId == null || byRule != null
        ? null
        : knownFood(db, row.fdcId!, line: line);
    final source = GramSource.values.asNameMap()[row.gramSource];
    if (byRule != null) {
      row = byRule.row;
    } else if (onRow != null) {
      final outcome = engineOutcome(
        recipe,
        line,
        onRow,
        row.grams == null || source == null
            ? null
            : GramResolution(grams: row.grams!, source: source),
        picked: !personal,
        decided: personal,
        confidence: row.confidence,
      );
      row = row.copyWith(hold: outcome.hold);
    }
  } else if (fdcId != null) {
    if (fdcId is! num || fdcId <= 0) {
      throw const ValidationException("'fdc_id' must be a positive number.");
    }
    // A candidate the sheet showed is a cached hit: it stands in until the
    // grams need FDC's portions (gramsFor), so a pick lands with no provider
    // call while the hourly budget is spent.
    final picked =
        knownFood(db, fdcId.toInt(), line: line) ??
        await cachedFood(db, provider, fdcId.toInt());
    if (picked == null) {
      throw const ValidationException(
        'FoodData Central has no food with that id.',
      );
    }
    final (food, resolution) = await gramsFor(db, provider, picked, line);
    // A discarded medium stays discarded whatever food a person picks for
    // it — frying oil re-picked as "Oil, peanut" is still thrown away (a
    // grams edit is how a person counts it).
    final outcome = engineOutcome(
      recipe,
      line,
      food,
      resolution,
      decided: true,
    );
    // So does a second food picked onto its rule's record: the juice
    // amount, or the egg parts' sum, not the first part's grams. A HELD
    // medium with no eaten part is poured away, as a confirm writes it
    // (B6, below).
    final poured =
        outcome.hold == 'discarded_medium' &&
        outcome.source != GramSource.discarded.name;
    final byEngine =
        poured ||
        outcome.source == GramSource.discarded.name ||
        secondFoodRuleOf(line)?.fdcId == food.fdcId;
    final pickedGrams = poured
        ? 0.0
        : byEngine
        ? outcome.grams
        : resolution?.grams;
    row = row.copyWith(
      fdcId: food.fdcId,
      description: food.description,
      dataType: food.dataType,
      confidence: 1,
      grams: pickedGrams,
      clearGrams: pickedGrams == null,
      gramSource: poured
          ? GramSource.discarded.name
          : byEngine
          ? outcome.source
          : resolution?.source.name,
      clearGramSource: pickedGrams == null,
      status: 'overridden',
    );
    decidedFood = true;
  } else if (confirmed == true) {
    row = row.copyWith(status: 'confirmed');
    decidedFood = row.fdcId != null;
    // A held medium with no eaten part (B6, checkpoint 8: its row stores
    // no grams — or, written before v14, the whole poured-away line): a
    // confirm says it is poured away, 0 g — typed grams (below) count
    // that much instead. One with an eaten part keeps it.
    if (row.fdcId != null &&
        row.hold == 'discarded_medium' &&
        row.gramSource != GramSource.discarded.name) {
      row = row.copyWith(grams: 0, gramSource: GramSource.discarded.name);
    } else if (row.fdcId != null &&
        row.grams == null &&
        row.gramSource != GramSource.override.name) {
      final onRow =
          knownFood(db, row.fdcId!, line: line) ??
          await cachedFood(db, provider, row.fdcId!);
      if (onRow != null) {
        final (_, resolution) = await gramsFor(db, provider, onRow, line);
        if (resolution != null) {
          row = row.copyWith(
            grams: resolution.grams,
            gramSource: resolution.source.name,
          );
        }
      }
    }
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
    // The decision must be made IN THIS REQUEST — a pick (`fdc_id`) or a
    // confirm. A grams-only edit promotes the engine's own guess to
    // `overridden` on this line, and broadcasting that guess as if a person
    // had chosen the food is exactly what the gate exists to refuse.
    if (!decidedFood) {
      throw const ValidationException(
        "'apply_to_all' needs a food decision in this request — pick a food "
        '(fdc_id) or confirm the current one.',
      );
    }
    if (itemKey.isEmpty) {
      throw const ValidationException(
        'Nothing searchable in this line to match other recipes on.',
      );
    }
    // The food this line was matched on, with no provider call when a
    // cache holds it: a lazy compute's stand-in lives only in a cached
    // search answer, and a decision must land while FDC is out of budget.
    food =
        knownFood(db, row.fdcId!, line: line) ??
        await cachedFood(db, provider, row.fdcId!);
    if (food == null) {
      throw const ValidationException(
        'FoodData Central has no food with that id.',
      );
    }
  }

  // A food decided IN THIS REQUEST — a pick, or a confirm of a food — is the
  // ingredient's decision from now on, in every recipe: it gets a row of its
  // own, so it outlives this recipe being edited or deleted (before, other
  // lines borrowed it from this row and lost it with it). A grams-only edit
  // decides the amount, not the food, and writes nothing; neither does a
  // skip. The same gate apply_to_all uses.
  if (decidedFood && itemKey.isNotEmpty) {
    db.putDecision(
      itemKey: itemKey,
      item: decisionItemOf(line),
      fdcId: row.fdcId,
      description: row.description,
      dataType: row.dataType,
      decidedBy: decidedBy,
    );
  }
  // A person's decision supersedes the engine's reason to hold the row (an
  // un-skip re-derived its own above).
  db.upsertIngredientMatch(
    row.copyWith(itemKey: itemKey, clearHold: skipped != false),
  );
  await recomputeTotals(db, provider, recipe);

  if (food == null) {
    return null;
  }
  return applyDecisionToOthers(
    db,
    provider,
    itemKey: itemKey,
    decided: food,
    excluding: (recipeId: recipe.id, position: position),
  );
}

/// Whether FDC's WHOLE cached answer (the row under [answerQuery]) names
/// the ingredient of [query] — the answer, not the eight candidates the body
/// shows (a carrier ranked ninth still means the search found the food).
/// Null when never searched; false for an empty answer.
bool? _answerNamesIngredient(
  SaltDatabase db,
  String query,
  String answerQuery,
) {
  final cached = db.fdcSearchCacheGet(answerQuery);
  if (cached == null) {
    return null;
  }
  final answer = [
    for (final entry in jsonDecode(cached) as List<dynamic>)
      FdcCandidate.fromJson(entry as Map<String, dynamic>),
  ];
  return answer.isNotEmpty && candidatesNameIngredient(query, answer);
}

/// Masks a stored API key for display: last four characters only.
String maskKey(String key) =>
    key.length <= 4 ? '****' : '****${key.substring(key.length - 4)}';
