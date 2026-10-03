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
    // Why (v28, Run 058 S15 / Opus critic 1 #3): `inputs` — the recipe's
    // inputs or layout moved since the totals were stamped; `underived` —
    // the stamp is current but a person's decision is waiting on USDA (a
    // derivation that could not run). The page names the cause.
    // v29: `interrupted` — a pass is IN PROGRESS or never wrote its totals
    // (migration 017's owned count above zero — a live compute, PUT or
    // apply target, or one a hung await holds — or a stamp the boot or a
    // throw cleared); `underived` also when the stamp
    // says the last totals could not count a food USDA could not serve
    // ([unavailableStampOf] the current inputs) — never `inputs` when
    // nothing changed (Run 059 O23).
    if (stale)
      'stale_reason':
          row.computing > 0 ||
              row.ingredientsHash.startsWith(SaltDatabase.interruptedStamp)
          ? 'interrupted'
          : nutritionStampCurrent(db, recipe, row) ||
                row.ingredientsHash ==
                    unavailableStampOf(ingredientsHashOf(recipe))
          ? 'underived'
          : 'inputs',
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
  // Every line's reach reads the same rows: each reached recipe and line
  // once for the whole body (Run 054 S4: once per line, 1.1 s on 0491).
  final reads = ReachMemo();
  for (final (position, line) in lines.indexed) {
    var row = matches[position];
    // A person's decision shows what it derives on the recipe as it is now
    // (RULE A, [derivedFor] — from the cache alone, a GET never fetches):
    // on its own line, its status and food with the hold, grams and note
    // the next compute writes ([withDerived]); carried by an amount edit
    // (Run 052, Opus critic 2: shown as no match while the totals and the
    // PUT acted on it), what that compute and a person's write make of it,
    // with `carried_from`: the line's previous text. A row of another text
    // that is the engine's is the next compute's to re-derive (none shown).
    String? carriedFrom;
    String? note;
    var derived = false;
    // What the line weighs, matches and queries: a sub-recipe's eaten
    // "plus" part (0711's oil), as every write path reads it.
    final weighed = weighedLine(recipe, line);
    // The row's food from the caches, resolved ONCE per row and request
    // (RULE C v28, Run 058 O5/S10: the derivation and this body each
    // resolved it — two or three reads per typed row): [derivedFor] reads
    // it, and the portions and nutrient record below show it.
    final onRow = row?.fdcId == null
        ? null
        : (food: knownFood(db, row!.fdcId!, line: weighed), id: row.fdcId);
    if (row != null && isDecidedRow(row)) {
      final decided = row;
      final carried = decided.raw != line.raw;
      carriedFrom = carried ? decided.raw : null;
      // A derivation that needs what no cache holds is RULE A's one
      // unhappy outcome ([derivedFor]'s `unavailable`): the stored row
      // shown as is — its derived fields as the last derivation left them,
      // what the totals count — carried rows under the line's text.
      final d = await derivedFor(
        db,
        cacheOnly,
        recipe,
        position,
        line,
        decided,
        resolved: (food: onRow?.food),
      );
      row = carried ? d.row : withDerived(decided, d.row);
      note = d.note;
      derived = true;
    } else if (row != null && row.raw != line.raw) {
      row = null;
    }
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
              memo: reads,
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
        : row!.fdcId == onRow?.id
        ? onRow!.food
        : knownFood(db, row.fdcId!, line: weighed);
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
              // on a person's decision, what it resolved ("eaten part
              // counted after your pick", "poured away after your confirm")
              // or the hold a pick keeps ([derivedFor]); null otherwise.
              'hold_note': derived ? note : holdNoteOf(recipe, line, row.hold),
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
  int unavailable,
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
  'unavailable': applied.unavailable,
};

/// Applies a `PUT .../nutrition/matches/<pos>` override [body] and
/// recomputes the stored totals (no FDC searches; at most one cached food
/// fetch for a re-pick). With `apply_to_all: true`, also lands the decided
/// food on every other recipe's undecided line of the same item and returns
/// what that reached; null otherwise.
Future<AppliedToOthers?> applyMatchOverride(
  SaltDatabase db,
  NutritionProvider fdc,
  Recipe given,
  int position,
  Map<String, Object?> body, {
  int? decidedBy,
}) async {
  // One request per FOOD for the write and its apply-to-all ([onePass]).
  final provider = onePass(fdc, recipe: given.id);
  // The STORED recipe, never the caller's copy: a save since the caller
  // read it (the route's body read, a client's stale screen) would lay the
  // rows out on lines that are no longer the recipe's.
  var recipe = db.recipeByIdOrSlug(given.id)?.recipe ?? given;
  final version = db.contentHashOf(recipe.id);
  // The inputs every derivation below reads (a save during the awaits is
  // refused below unless this line still stands; its derivation is then
  // of these inputs, and a stamp of the new ones reads it underived).
  final derivedOn = ingredientsHashOf(recipe);
  // The recipe [derivedOn] hashes ([recipe] is re-read below after a save).
  final hashedRecipe = recipe;
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
  var seq = db.layoutSeqOf(recipe.id);
  final existing = {
    for (final row in db.ingredientMatchesFor(recipe.id)) row.position: row,
  };
  final read = existing[position];
  var row = read;
  // A row the layout carried here from its line's old text (the same
  // ingredient, edited — the compute has not run since the save) is first
  // what that compute makes of it ([derivedFor]: its food and
  // status, the grams for the NEW amount), so a skip, confirm or un-skip
  // here never stamps the old amount's grams under the new text (Run 051
  // B2: a skip then an un-skip in that window counted 3 g typed for "½
  // cup" on "1 cup" of oil). With no row, start fresh.
  // A derivation that cannot run ([derivedFor]'s `unavailable`, RULE A's
  // one unhappy outcome) here or below: the decision is stored with the
  // derived fields as they were and NO `derived_seq` — underived, so the
  // recipe reads stale until a compute derives it (v27: the row's own
  // fact, which no concurrent compute's stamp can overwrite).
  var unavailable = false;
  final skipped = body['skipped'];
  final confirmed = body['confirmed'];
  final fdcId = body['fdc_id'];
  final grams = body['grams'];
  // The hold's ONE action table (RULE A v28, salt_shared `holdActions`;
  // Run 058 O7/S13, Opus critic 2): a decision the line's hold does not
  // accept is refused before anything is written — a confirm or typed
  // grams on a food with no record (`food_gone`, `food_unavailable`)
  // cannot count it, and must never reach the library-wide decision. The
  // table needs only the hold: the STORED row's is read first, so a
  // carried row (its line edited, not yet computed) is refused before its
  // derivation asks FDC anything (the v28 closer's D3); the derived row's
  // is read again below.
  // EVERY verb the body carries is judged (v29, Run 059 Opus critics 2/3:
  // `{skipped: true, grams}` passed as a skip and wrote typed grams on a
  // food with no record). A pick puts another food on the line, so the
  // confirm or grams with it are that food's, not the held one's.
  final verbs = {
    if (skipped == true) HoldDecision.skip,
    if (fdcId != null) HoldDecision.pick,
    if (confirmed == true) HoldDecision.confirm,
    if (grams != null) HoldDecision.typed,
  };
  final judged = verbs.contains(HoldDecision.pick)
      ? const {HoldDecision.pick}
      : verbs;
  // One verb at a time with a skip: `skipped` together with a food verb
  // would let the status chain drop the food (skip wins) while the
  // decision below still fired on the request — recording the engine's own
  // guess as a person's decision, library-wide (review, 2026-09-07); with
  // typed grams, it wrote them on a held food's row (v29). Refused before
  // anything is read or written.
  if (skipped != null &&
      (fdcId != null || confirmed != null || grams != null)) {
    throw const ValidationException(oneDecisionMessage);
  }
  bool refuses(IngredientMatchRow row) =>
      !judged.every(holdActionsOf(row.hold).accepts.contains);
  void gate(IngredientMatchRow row) {
    if (refuses(row)) {
      throw ValidationException(refusalOf(row.hold));
    }
  }

  // A stored hold is RE-READ before it is enforced (RULE A v29, Run 059
  // O6/S1/S6/S27): derived from the caches alone ([cacheOnly] — the GET's
  // reading, [knownFood]; no request), and the DERIVED hold judged: a cache
  // that holds the food again lets the confirm through, as the GET shows.
  // The re-read row is the row the decision lands on (its own line's).
  if (row != null && refuses(row)) {
    final reread = (await derivedFor(
      db,
      cacheOnly,
      recipe,
      position,
      line,
      row,
    )).row;
    gate(reread);
    if (row.raw == line.raw) {
      row = reread;
    }
  }
  if (row != null && row.raw != line.raw) {
    final d = await derivedFor(db, provider, recipe, position, line, row);
    row = d.row;
    unavailable = d.unavailable != null;
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

  // The action table again, on the row as derived (a carried row's).
  gate(row);
  // Set only by the branches that PUT a food on the row in this request.
  var decidedFood = false;
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
    // The decision: this food, by a person. What it weighs and holds is
    // derived below ([derivedFor], RULE A — the compute's rule).
    row = row.copyWith(
      fdcId: picked.fdcId,
      description: picked.description,
      dataType: picked.dataType,
      confidence: 1,
      clearGrams: true,
      clearGramSource: true,
      status: 'overridden',
      // The old food's `food_gone` / `food_unavailable` is answered by
      // picking another (v27, v28).
      clearHold: noRecordHolds.contains(row.hold),
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
    // Its grams and hold are derived below ([derivedFor]): the engine's
    // current weight on this food — a held medium's eaten part, else 0 g
    // poured away (B6, checkpoint 8) — and no hold.
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
    // Typed for the line as it reads NOW: a decision an amount edit
    // carried whose derivation could not run still has its old text
    // ([derivedFor]'s `unavailable`), and these grams are not the old
    // amount's.
    row = row.copyWith(
      raw: line.raw,
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
  // RULE A: the decision set above (status, food, typed grams); the row
  // stores what it derives on the recipe as it is ([derivedFor] — the hold,
  // the grams unless typed, their source; the sub-recipe rule's gate), the
  // one rule every compute and the matches GET apply. An un-skip is the
  // engine's row again ([unskippedRow]). A derivation that cannot run
  // (FDC out of budget or down for a detail it needs, a food no cache and
  // no FDC answer holds) is RULE A's one unhappy outcome, as at every
  // compute (v26, Run 056 S2/S29): the decision is stored (200), its
  // derived fields as the last derivation left them — the hold kept, a
  // pick's grams none (it clears the old food's) — and the row left
  // UNDERIVED (no `derived_seq`; the totals' stamp stays current), so the
  // recipe reads stale (`stale_reason: underived`) and the next sweep
  // derives it (v27/v28). (v25 dropped the hold and kept
  // the stamp fresh: 0129's held liquid smoke confirmed in an outage sat
  // in `no_grams` for good.) A pick still needs its food above.
  var stored = row;
  // An un-skip that gives typed grams back (`overridden`, [unskippedRow])
  // is a decision again: derived like any (v29, Opus critic 3 — a row
  // typed before its food went is held, never counted unheld).
  if (skipped != false || isDecidedRow(row)) {
    final d = await derivedFor(db, provider, recipe, position, line, row);
    stored = d.row;
    unavailable = unavailable || d.unavailable != null;
  }
  // A food this derivation found has no record (a confirm of a food FDC
  // no longer serves): the decision stands on the line, held, but is never
  // the ingredient's decision library-wide (Run 058 Opus critic 2: 0148's
  // confirm replaced the key's decision 173468 with the gone food).
  if (!holdActionsOf(stored.hold).decidesLibraryWide) {
    if (applyToAll == true) {
      throw ValidationException(refusalOf(stored.hold));
    }
    decidedFood = false;
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
      db.layoutSeqOf(recipe.id) != seq) {
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
    seq = db.layoutSeqOf(recipe.id);
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
  // In progress until the totals below are written (v29, migration 017),
  // marked BEFORE the row: a restart between them, or during the totals'
  // await, leaves the recipe stale, never this decision marked derived
  // under totals that miss it (Opus critic 1). The mark is this write's
  // own ([SaltDatabase.markComputing]): its totals release it, never a
  // concurrent pass's.
  final marked = db.markComputing(recipe.id);
  var wrote = false;
  var ended = false;
  try {
    // Derived FOR the layout this write lands under and the inputs the
    // derivation read ([derivedKeyOf]); none when it could not run.
    wrote = db.upsertIngredientMatch(
      stored.copyWith(
        itemKey: itemKey,
        derivedSeq: derivedKeyOf(seq, derivedOn),
        clearDerivedSeq: unavailable,
      ),
      layoutSeq: seq,
    );
    if (!wrote) {
      throw LineMovedException(position);
    }
    // A plain recompute: the stamp stays what it was; freshness reads the
    // row ([nutritionIsFresh]). Only THIS line's food and its nutrient
    // record are resolved if no cache holds them (v29, Run 059 S13: at
    // most two requests); another row whose food no cache holds stays
    // underived.
    await recomputeTotalsResolving(
      db,
      provider,
      recipe,
      only: foodsOf(stored.fdcId),
      hashed: (recipe: hashedRecipe, hash: derivedOn),
      ending: marked,
    );
    ended = true;
  } finally {
    if (!ended) {
      db.releaseComputing(recipe.id, owned: marked, stale: wrote);
    }
  }

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

/// The 422 for a decision a held line's action table refuses
/// ([holdActions]): only another food or a skip answers a food with no
/// USDA record.
const String noRecordMessage =
    'USDA has no record of this food to count — pick another food or skip '
    'the line.';

/// The 422 for a confirm or typed grams on a food USDA keeps failing on
/// (`food_unavailable`, v29 — Run 059 S3: it said "no record" of a food
/// USDA serves when it is up).
const String unavailableMessage =
    'USDA could not serve this food — pick another food or skip the line.';

/// The 422 for a skip carried with another verb.
const String oneDecisionMessage =
    "'skipped' cannot be combined with 'fdc_id', 'confirmed' or 'grams' — "
    'one decision per request.';

/// The 422 a held line's action table refuses with, by [hold].
String refusalOf(String? hold) =>
    hold == foodUnavailableHold ? unavailableMessage : noRecordMessage;

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

/// Masks a stored API key for display: last four characters only.
String maskKey(String key) =>
    key.length <= 4 ? '****' : '****${key.substring(key.length - 4)}';
