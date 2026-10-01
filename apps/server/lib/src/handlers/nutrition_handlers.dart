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
  final stale = !nutritionIsFresh(db, recipe, row);
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
  // Each line's row as the next layout pairs it (in memory: a GET writes
  // nothing), so an edit since the last compute never shows a line
  // another line's row.
  final matches = pairRowsToLines(
    db.ingredientMatchesFor(recipe.id),
    lines,
    laidOut: db.layoutOf(recipe.id).lines,
  );
  // The line each of this recipe's stored rows is paired to (by stored
  // position): the offer below counts this recipe's rows as laid out.
  final pairedTo = {
    for (final (at, row) in matches.indexed)
      if (row != null) row.position: at,
  };
  final items = <Map<String, Object?>>[];
  for (final (position, line) in lines.indexed) {
    var row = matches[position];
    // A row of another text the layout gives this line: an engine row is
    // the next compute's to re-derive (none shown). A person's decision an
    // amount edit carried (Run 052, Opus critic 2: shown as no match while
    // the totals and the PUT acted on it) shows as what the next compute
    // and a person's write make of it ([editedDecisionRow]: its status and
    // food, the new line's grams — from the cache alone, a GET never
    // fetches), with `carried_from`: the line's previous text.
    String? carriedFrom;
    if (row != null && row.raw != line.raw) {
      if (isDecidedRow(row)) {
        carriedFrom = row.raw;
        final carried = row;
        try {
          row = (await editedDecisionRow(
            db,
            const _CacheOnly(),
            recipe,
            position,
            line,
            carried,
          )).row;
        } on NutritionProviderException {
          // Its grams need a fetch: none shown until the compute weighs it.
          row = carried.copyWith(
            raw: line.raw,
            clearGrams: true,
            clearGramSource: true,
          );
        }
      } else {
        row = null;
      }
    }
    // What the line weighs, matches and queries: a sub-recipe's eaten
    // "plus" part (0711's oil), as every write path reads it.
    final weighed = weighedLine(recipe, line);
    // Cache-only: a GET must never spend FDC budget or block on the rate
    // limiter (members can call this).
    final candidates = row == null
        ? const <RankedCandidate>[]
        : await candidatesForLine(db, provider, weighed, cacheOnly: true);
    final itemKey = lineKeyOf(line);
    // How far an apply-to-all from this line would reach: the undecided lines
    // of the same ingredient, in recipes and in lines — a sibling on another
    // food at any score, a sibling on THIS food only while it is still a
    // flagged guess (below `lowConfidence`); one already counted waits on
    // nothing this decision can give it, and neither does a line-held row or
    // a line naming a second food. The same rows the apply writes — this
    // recipe's own as the layout places them: never the row this line takes
    // (wherever it is stored), nor a row the layout would delete (Run 050:
    // after a save shifting the lines, a line was offered its own row).
    final reach = itemKey.isEmpty
        ? const <IngredientMatchRow>[]
        : [
            for (final other in decisionReach(
              db,
              itemKey,
              excluding: (recipeId: recipe.id, position: -1),
              fdcId: row?.fdcId,
            ))
              if (other.recipeId != recipe.id ||
                  (pairedTo[other.position] ?? position) != position)
                other,
          ];
    // The KEY (singular) joins decisions; the QUERY keeps the line's words —
    // reported as the words whose cached answer the line reads (a same-key
    // sibling's, or an "A or B" line's A), so a live search lands there.
    // The weighed line's key, as the compute reads it: a plus line's own
    // key ("crispy onion") would miss the answer its eaten plural item
    // reads through the sibling key ('onion' for "reserved onions") and
    // report "onions", uncached (Run 049).
    final search = itemKey.isEmpty
        ? null
        : lineSearchFor(
            db,
            normalizeItem(lineItemOf(weighed)),
            lineKeyOf(weighed),
          );
    final query = search?.answer;
    // The picked record's USDA portions, from the cache alone (a search hit
    // stand-in has none): what the fix sheet's amount block offers. (`line:`
    // only orders the cached answers [knownFood] scans for the food — the
    // same hit either way, Run 048 P9; weighed like every path.)
    final food = row?.fdcId == null
        ? null
        : knownFood(db, row!.fdcId!, line: weighed);
    // What the totals count for [food]: its [nutrientSiblings] record when
    // it has one (null while that is uncached — a GET never fetches).
    final sibling = food == null ? null : nutrientSiblings[food.fdcId];
    final counted = sibling == null ? food : knownFood(db, sibling);
    // A held medium's line amount is what is poured away: no portion is
    // filled from it (Run 048: the sheet offered "Confirm · 36 g" of a
    // rinsed-off salt).
    final held = heldMediumLine(recipe, weighed);
    items.add({
      'position': position,
      'raw': line.raw,
      // The parsed ingredient item ("unsalted butter"), null when the line
      // has none — what an apply-to-all offer names, since `others` is
      // counted by item, not by line.
      'item': line.item,
      // The line's first unit amount as written ("4 stick"), else its bare
      // count ("8"); null when the line gives no amount.
      'line_amount': lineAmountText(weighed.amounts),
      // The picked record's calories per 100 g, from the same cache: the
      // fix sheet says it where a line has no amount yet. As the totals
      // count them — a record in [nutrientSiblings] by its sibling's
      // nutrients (napa 2727583 counts 169979's 16, not its own 4.26); null
      // while the sibling is uncached (a GET never fetches).
      'kcal_per_100g': counted == null ? null : kcalPer100g(counted),
      // The picked record's cached portions, each with `fill`: the grams
      // the line's unit amount weighs on it when the portion names that
      // unit (4 × stick 113 g = 452), else null — always null on a held
      // medium's line. Empty when the record's detail was never fetched,
      // or nothing is picked. Never a fetch.
      'portions': [
        for (final portion in food?.portions ?? const <FdcPortion>[])
          {
            'amount': portion.amount,
            'unit': portion.unit,
            'description': portion.description,
            'grams': portion.gramWeight,
            'fill': held ? null : portionFill(portion, weighed.amounts),
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
              'gram_basis': gramBasisFor(db, line, row, recipe: recipe),
              'status': row.status,
              // Why an `auto` row is held out of the totals although its
              // score passes (`no_nutrients` | `discarded_medium` |
              // `second_food`); null when nothing holds it.
              'hold': row.hold,
              // What a reviewer needs to judge the hold, in words: for a
              // `partial_pour_away` the part of the strained liquid a step
              // keeps ("1 cup defatted cooking liquid"), and a divided
              // line's part eaten outside the dredge or braise ([holdNoteOf]);
              // null otherwise.
              'hold_note': holdNoteOf(recipe, line, row.hold),
              // The line's previous text when this is a decision an amount
              // edit carried, not yet written for this line (its grams are
              // re-derived for this line until the next compute writes it);
              // null otherwise.
              'carried_from': carriedFrom,
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
  int moved,
  int decided,
  int gone,
  int failedLines,
});

/// The receipt's wire shape (`applied` on the `PUT …/matches/{pos}` body).
Map<String, Object?> appliedJson(AppliedToOthers applied) => {
  'recipes': applied.recipes,
  'lines': applied.lines,
  'failed': applied.failed,
  'completed': applied.completed,
  'completed_recipes': applied.completedRecipes,
  'moved': applied.moved,
  'decided': applied.decided,
  'gone': applied.gone,
  'failed_lines': applied.failedLines,
};

/// Applies a `PUT .../nutrition/matches/<pos>` override [body] and
/// recomputes the stored totals (no FDC searches; at most one cached food
/// fetch for a re-pick). With `apply_to_all: true`, also lands the decided
/// food on every other recipe's undecided line of the same item and returns
/// what that reached; null otherwise.
Future<AppliedToOthers?> applyMatchOverride(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe given,
  int position,
  Map<String, Object?> body, {
  int? decidedBy,
}) async {
  // The STORED recipe, never the caller's copy: a save since the caller
  // read it (the route's body read, a client's stale screen) would lay the
  // rows out on lines that are no longer the recipe's.
  var recipe = db.recipeByIdOrSlug(given.id)?.recipe ?? given;
  final version = db.contentHashOf(recipe.id);
  final lines = nutritionLines(recipe);
  // `raw`: the line text the client saw at [position]. A save since then
  // moved it: 409 line_moved, naming where it is now; nothing is written.
  final seen = body['raw'];
  if (seen != null && seen is! String) {
    throw const ValidationException("'raw' must be a string.");
  }
  if (seen is String &&
      (position < 0 ||
          position >= lines.length ||
          lines[position].raw != seen)) {
    throw LineMovedException(nearestLineOf(lines, seen, position));
  }
  if (position < 0 || position >= lines.length) {
    throw NotFoundException('No ingredient line at position $position.');
  }
  final line = lines[position];
  // What the line weighs and matches: a sub-recipe's eaten "plus" part
  // (0711's oil), as the compute weighs it.
  final weighed = weighedLine(recipe, line);
  final itemKey = lineKeyOf(line);
  // A recipe saved since its last compute still has its rows where its old
  // lines stood: lay them out on the new lines first ([layoutMatchRows]),
  // so this write reads and replaces THIS line's row, never the row (or a
  // person's decision) another line left at this position.
  // Known limit (pairing panel): the layout runs before the body is
  // validated, so a refused request (a 422, the zero-row confirm) can still
  // move or drop rows as the next compute would — no decision's content
  // changes. A save during this request's own awaits (cachedFood,
  // gramsFor) is read again before the write (below).
  layoutMatchRows(db, recipe);
  // The layout this request reads its row under ([SaltDatabase.layoutOf]).
  var seq = db.layoutOf(recipe.id).seq;
  final existing = {
    for (final row in db.ingredientMatchesFor(recipe.id)) row.position: row,
  };
  final read = existing[position];
  var row = read;
  // A row the layout carried here from its line's old text (the same
  // ingredient, edited — the compute has not run since the save) is first
  // what that compute makes of it ([editedDecisionRow]: its food and
  // status, the grams for the NEW amount), so a skip, confirm or un-skip
  // here never stamps the old amount's grams under the new text (Run 051
  // B2: a skip then an un-skip in that window counted 3 g typed for "½
  // cup" on "1 cup" of oil). With no row, start fresh.
  if (row != null && row.raw != line.raw) {
    row = (await editedDecisionRow(
      db,
      provider,
      recipe,
      position,
      line,
      row,
    )).row;
  }
  row ??= IngredientMatchRow(
    recipeId: recipe.id,
    position: position,
    raw: line.raw,
    fdcId: null,
    description: null,
    dataType: null,
    confidence: 0,
    grams: null,
    gramSource: null,
    status: 'unmatched',
    itemKey: itemKey,
  );

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
  var keptHold = false;
  if (skipped == true) {
    row = row.copyWith(status: 'skipped');
  } else if (skipped == false) {
    // Un-skip returns the line to automatic triage, as a compute writes it
    // ([unskippedRow]). It must NOT set 'confirmed': blessing whatever
    // low-confidence match the line had would hide it from the review queue
    // as resolved (review B7) — only grams a person typed come back as
    // their counted row.
    row = await unskippedRow(db, provider, recipe, position, row);
  } else if (fdcId != null) {
    if (fdcId is! num || fdcId <= 0) {
      throw const ValidationException("'fdc_id' must be a positive number.");
    }
    // A candidate the sheet showed is a cached hit: it stands in until the
    // grams need FDC's portions (gramsFor), so a pick lands with no provider
    // call while the hourly budget is spent.
    // (`line:` orders the answers scanned — equivalent, as in matchesBody.)
    final picked =
        knownFood(db, fdcId.toInt(), line: weighed) ??
        await cachedFood(db, provider, fdcId.toInt());
    if (picked == null) {
      throw const ValidationException(
        'FoodData Central has no food with that id.',
      );
    }
    final (food, resolution) = await gramsFor(db, provider, picked, weighed);
    // A discarded medium stays discarded whatever food a person picks for
    // it — frying oil re-picked as "Oil, peanut" is still thrown away (a
    // grams edit is how a person counts it). Read on the weighed line, as
    // the compute reads it (Run 048: a plus line whose eaten part is a
    // medium — 0711's reserve at 2 cups — counted the oil the compute
    // zeroes).
    final outcome = engineOutcome(
      recipe,
      weighed,
      food,
      resolution,
      decided: true,
    );
    // So does a second food picked onto its rule's record: the juice
    // amount, or the egg parts' sum, not the first part's grams. A HELD
    // discarded medium with no eaten part is poured away, as a confirm
    // writes it (B6, below). A medium part of which is eaten — a dredge, a
    // braise kept in part, a starter's feeding — keeps its hold on a pick
    // alone (v23, Run 053 O8): 0 g would drop the eaten part with no flag;
    // a skip or typed grams answers it, as the panel says.
    keptHold = grams == null && eatenInPartHolds.contains(outcome.hold);
    final poured =
        !keptHold &&
        mediumHolds.contains(outcome.hold) &&
        outcome.source != GramSource.discarded.name;
    final byEngine =
        keptHold ||
        poured ||
        outcome.source == GramSource.discarded.name ||
        // (The weighed line, Run 048 P9: equivalent — a rule reads "zest
        // plus juice" or "eggs plus yolks", and neither a "1 recipe X, plus
        // …" line nor its single eaten part is one.)
        secondFoodRuleOf(weighed)?.fdcId == food.fdcId;
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
      hold: keptHold ? outcome.hold : null,
      status: 'overridden',
    );
    decidedFood = true;
  } else if (confirmed == true) {
    // A below-gate zero row (0 g, unmeasured or discarded) hides its food:
    // the weak guess is no food a person looked at (ruling 9), and the UI
    // offers no confirm-as-is on it. A bare confirm would still decide
    // that food library-wide — refused (Run 046). A pick, or typed grams,
    // is a real answer; so is a skip. A skipped zero row hides it too.
    // (The food term is equivalent, Run 048 P9: a row on no food at 0 g is
    // a rule row, written at confidence 1, over the gate — it stands for
    // what "hides its food" means.)
    if (grams == null &&
        (row.status == 'auto' || row.status == 'skipped') &&
        row.fdcId != null &&
        row.grams == 0 &&
        (row.gramSource == GramSource.unmeasured.name ||
            row.gramSource == GramSource.discarded.name) &&
        row.hold != 'unnamed_food' &&
        belowConfidenceGate(row.confidence)) {
      throw const ZeroRowException(
        'This line counts as zero on a guessed food: pick a food (with an '
        'amount) or skip it — it cannot be confirmed as it is.',
      );
    }
    row = row.copyWith(status: 'confirmed');
    decidedFood = row.fdcId != null;
    // A held medium with no eaten part (B6, checkpoint 8: its row stores
    // no grams — or, written before v14, the whole poured-away line): a
    // confirm says it is poured away, 0 g — typed grams (below) count
    // that much instead. One with an eaten part keeps it. Held by the
    // engine's own detector, not only the stored hold (Run 047: a row an
    // amount edit had left with no hold counted the whole line), or by the
    // stored hold — a row an older matcher held. Grams a
    // person typed for the eaten part stand (Run 048: a bare re-confirm
    // zeroed them).
    if (row.fdcId != null &&
        (mediumHolds.contains(row.hold) || heldMediumLine(recipe, weighed)) &&
        row.gramSource != GramSource.discarded.name &&
        row.gramSource != GramSource.override.name) {
      row = row.copyWith(grams: 0, gramSource: GramSource.discarded.name);
    } else if (row.fdcId != null &&
        row.grams == null &&
        row.gramSource != GramSource.override.name) {
      // (`line:` orders the answers scanned — equivalent, Run 048 P9.)
      final onRow =
          knownFood(db, row.fdcId!, line: weighed) ??
          await cachedFood(db, provider, row.fdcId!);
      if (onRow != null) {
        final (_, resolution) = await gramsFor(db, provider, onRow, weighed);
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
  // a refused request changes nothing — not the line, not the totals (the
  // layout above may still have moved rows; no decision's content changes).
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
  // A save, or a layout, during the awaits above (Run 051 C1: a save and
  // its revert hash the same, so the content hash alone cannot tell — the
  // layout sequence can): the rows are laid out on the stored lines again,
  // and the write lands only while this line still stands at [position]
  // and the row the layout gives it is the one this request read (else 409
  // line_moved; this line's row is left as it was). A recipe deleted
  // meanwhile is a 404.
  if (db.contentHashOf(recipe.id) != version ||
      db.layoutOf(recipe.id).seq != seq) {
    recipe =
        db.recipeByIdOrSlug(recipe.id)?.recipe ??
        (throw const NotFoundException('Recipe not found.'));
    final now = nutritionLines(recipe);
    if (position >= now.length || now[position].raw != line.raw) {
      throw LineMovedException(nearestLineOf(now, line.raw, position));
    }
    layoutMatchRows(db, recipe);
    final laid = db
        .ingredientMatchesFor(recipe.id)
        .where((row) => row.position == position)
        .firstOrNull;
    if (!sameMatchRow(laid, read)) {
      throw LineMovedException(position);
    }
    seq = db.layoutOf(recipe.id).seq;
  }
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
  // un-skip re-derived its own above). The sub-recipe rule gates a confirm
  // and a pick as it gates the compute ([subRecipeRowFor]): a marked line
  // whose food gives no grams, and a sub-recipe the recipe makes apart, are
  // the 0 g sub-recipe unless a person types the grams — in this request
  // or before it (Run 048: a bare confirm replaced typed grams on a
  // made-apart line with the 0 g row). The decision on the food stands
  // (above).
  final stored =
      skipped == null &&
          grams == null &&
          row.gramSource != GramSource.override.name
      ? subRecipeRowFor(recipe, position, line) ??
            subRecipeRowFor(
              recipe,
              position,
              line,
              onFood: true,
              grams: row.grams,
            ) ??
            row
      : row;
  if (!db.upsertIngredientMatch(
    stored.copyWith(
      itemKey: itemKey,
      clearHold: skipped != false && !keptHold,
    ),
    layoutSeq: seq,
  )) {
    throw LineMovedException(position);
  }
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

/// The position of the line of [lines] reading [raw] nearest [position]
/// (the earlier on a tie), or null when none does.
int? nearestLineOf(List<IngredientLine> lines, String raw, int position) {
  int? best;
  for (final (at, line) in lines.indexed) {
    if (line.raw == raw &&
        (best == null || (at - position).abs() < (best - position).abs())) {
      best = at;
    }
  }
  return best;
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

/// A provider that never fetches (it throws, so nothing caches a miss):
/// the cache-only reads of a GET.
class _CacheOnly implements NutritionProvider {
  const _CacheOnly();

  @override
  Future<List<FdcCandidate>> search(String query) =>
      throw NutritionProviderException('cache only: search "$query"');

  @override
  Future<FdcFood?> food(int fdcId) =>
      throw NutritionProviderException('cache only: food $fdcId');
}

/// Masks a stored API key for display: last four characters only.
String maskKey(String key) =>
    key.length <= 4 ? '****' : '****${key.substring(key.length - 4)}';
