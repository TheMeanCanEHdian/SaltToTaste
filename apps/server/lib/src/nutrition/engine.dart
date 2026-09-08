import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';

final Logger _log = Logger('nutrition');

/// Confidence below which an auto match is reported as needs-review.
const double lowConfidence = 0.5;

/// Whether [food] reports all four macros (energy — any variant — fat,
/// carbs, protein). Vitamins may still be missing; macros are the floor
/// for a trustworthy label.
bool _macroComplete(FdcFood food) {
  final n = food.nutrientsPer100g;
  final hasEnergy =
      n.containsKey('208') || n.containsKey('957') || n.containsKey('958');
  return hasEnergy &&
      n.containsKey('204') &&
      n.containsKey('205') &&
      n.containsKey('203');
}

/// The flattened, positioned ingredient lines nutrition works over.
List<IngredientLine> nutritionLines(Recipe recipe) => [
  for (final group in recipe.ingredients)
    for (final line in group.items) line,
];

/// Hash of everything nutrition depends on — when it changes, stored
/// results are stale.
String ingredientsHashOf(Recipe recipe) {
  // The matcher version is part of it: a bump makes every computed recipe
  // stale, so the stale sweep re-resolves its engine rows instead of leaving
  // scores and picks frozen at the matcher that wrote them.
  final payload = jsonEncode({
    'matcher': matcherVersion,
    'lines': [
      for (final line in nutritionLines(recipe))
        {
          'raw': line.raw,
          'item': line.item,
          'amounts': [for (final amount in line.amounts) amount.toMap()],
        },
    ],
  });
  return sha256.convert(utf8.encode(payload)).toString();
}

/// Matches every ingredient line of [recipe] against FDC and computes the
/// per-serving totals. Existing user decisions (confirmed / overridden /
/// skipped rows whose raw text is unchanged) are preserved; only `auto`
/// and changed rows are re-resolved.
Future<void> matchAndCompute(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe recipe,
) async {
  final lines = nutritionLines(recipe);
  final existingRows = db.ingredientMatchesFor(recipe.id);
  final existing = {for (final row in existingRows) row.position: row};
  // Decided rows by their text, in position order. Rows are keyed by
  // POSITION, so an edit above a decided line (insert, delete, reorder)
  // moved the line out from under its row and the decision was lost —
  // reproduced on the Bundt cake, survey 2026-09-04. A moved line is found
  // here by its text and its row travels with it. A list per text, not a
  // map: 80 corpus recipes repeat a raw line, and the nth line keeps the
  // nth row.
  final decidedByRaw = <String, List<IngredientMatchRow>>{};
  for (final row in existingRows) {
    if (_isDecided(row)) {
      decidedByRaw.putIfAbsent(row.raw, () => []).add(row);
    }
  }
  // Decided rows whose exact text is GONE from the recipe: the line was
  // edited (an amount changed), possibly moved too. Such a row may be
  // re-attached by ingredient key — but only when the recipe still holds
  // as many lines of that ingredient as it held rows, i.e. an edit, not a
  // delete-and-add. Never by position alone: after a shift the row at a
  // line's old position can belong to a DIFFERENT line of the same
  // ingredient, and a skip copied onto it would silently drop that line
  // from the label (review, 2026-09-07).
  final newRaws = {for (final line in lines) line.raw};
  final orphansByKey = <String, List<IngredientMatchRow>>{};
  final oldKeyCounts = <String, int>{};
  for (final row in existingRows) {
    final rowKey = row.itemKey;
    if (rowKey == null || rowKey.isEmpty) {
      continue;
    }
    oldKeyCounts.update(rowKey, (n) => n + 1, ifAbsent: () => 1);
    if (_isDecided(row) && !newRaws.contains(row.raw)) {
      orphansByKey.putIfAbsent(rowKey, () => []).add(row);
    }
  }
  final newKeyCounts = <String, int>{};
  for (final line in lines) {
    final lineKey = itemKeyFor(line.item ?? line.raw);
    if (lineKey.isNotEmpty) {
      newKeyCounts.update(lineKey, (n) => n + 1, ifAbsent: () => 1);
    }
  }

  for (final (position, line) in lines.indexed) {
    final kept = existing[position];
    // A human decided this row; their call stands. `unmatched` is NOT a
    // decision — it is the engine's own "FDC had nothing", and a sweep exists
    // precisely to retry those once FDC gains data or the matcher improves.
    // (A cached empty search answer still short-circuits it, so the retry is
    // free but only helps once the normalised query or the cache changes.)
    if (kept != null && kept.raw == line.raw && _isDecided(kept)) {
      decidedByRaw[line.raw]?.remove(kept);
      continue;
    }

    final normalized = normalizeItem(line.item ?? line.raw);
    // The query keeps the line's own words; the KEY a decision is stored and
    // reused under is the singular form, so "onion" and "onions" are one.
    final key = itemKeyFor(line.item ?? line.raw);

    // The line moved: a decided row for exactly this text sits at another
    // position. Bring it here, decision and all; its old position is either
    // rewritten by the line now there or dropped past the end.
    final moved = decidedByRaw[line.raw];
    if (moved != null && moved.isNotEmpty) {
      final row = moved.removeAt(0);
      db.upsertIngredientMatchIfUndecided(
        row.copyWith(position: position, itemKey: key),
      );
      continue;
    }

    // A decided line whose amount was edited (and possibly moved): its
    // text is gone, but the recipe still holds the same number of lines of
    // that ingredient. The food and the status stand, the grams are
    // re-derived for the new amount (a weight typed for the old amount no
    // longer applies); a skip stays a skip.
    // (A decided row kept at THIS position cannot be this line's own — a
    // same-text row was kept above — so it never blocks a re-attachment.)
    final orphans = orphansByKey[key];
    if (orphans != null &&
        orphans.isNotEmpty &&
        oldKeyCounts[key] == newKeyCounts[key]) {
      final edited = orphans.removeAt(0);
      if (edited.status == 'skipped') {
        db.upsertIngredientMatchIfUndecided(
          edited.copyWith(position: position, raw: line.raw, itemKey: key),
        );
        continue;
      }
      if (edited.fdcId != null) {
        final food = await _cachedFood(db, provider, edited.fdcId!);
        if (food != null) {
          final resolution = resolveGrams(
            amounts: line.amounts,
            food: food,
            normalizedItem: normalized,
            raw: line.raw,
          );
          db.upsertIngredientMatchIfUndecided(
            edited.copyWith(
              position: position,
              raw: line.raw,
              itemKey: key,
              grams: resolution?.grams,
              clearGrams: resolution == null,
              gramSource: resolution?.source.name,
              clearGramSource: resolution == null,
            ),
          );
          continue;
        }
      }
    }
    final seasoning = line.amounts.isEmpty && isSeasoningToTaste(normalized);
    if (normalized.isEmpty || isWaterLike(normalized) || seasoning) {
      db.upsertIngredientMatchIfUndecided(
        IngredientMatchRow(
          recipeId: recipe.id,
          position: position,
          raw: line.raw,
          itemKey: key,
          fdcId: null,
          description: normalized.isEmpty
              ? 'Nothing searchable in this line'
              : seasoning
              ? 'Seasoning to taste — no measurable amount'
              : 'Water/ice — counts as zero',
          dataType: null,
          confidence: 1,
          grams: null,
          gramSource: null,
          status: normalized.isEmpty ? 'unmatched' : 'confirmed',
        ),
      );
      continue;
    }

    // A person already decided this ingredient (in any recipe, even one
    // since deleted): their food travels, with grams from THIS line's
    // amounts. Still `auto` (an engine write), so a decision made here later
    // still wins, and the review queue treats it as counted — confidence 1
    // says a person chose it.
    final prior = db.decisionFor(key);
    if (prior != null && prior.fdcId != null) {
      final food = await _cachedFood(db, provider, prior.fdcId!);
      if (food != null) {
        final resolution = resolveGrams(
          amounts: line.amounts,
          food: food,
          normalizedItem: normalized,
          raw: line.raw,
        );
        db.upsertIngredientMatchIfUndecided(
          IngredientMatchRow(
            recipeId: recipe.id,
            position: position,
            raw: line.raw,
            itemKey: key,
            fdcId: food.fdcId,
            description: food.description,
            dataType: food.dataType,
            confidence: 1,
            grams: resolution?.grams,
            gramSource: resolution?.source.name,
            status: 'auto',
          ),
        );
        continue;
      }
    }

    final query = searchQueryFor(normalized);
    final candidates = await _cachedSearch(db, provider, query);
    final ranked = rankCandidates(query, candidates);
    if (ranked.isEmpty) {
      db.upsertIngredientMatchIfUndecided(
        IngredientMatchRow(
          recipeId: recipe.id,
          position: position,
          raw: line.raw,
          itemKey: key,
          fdcId: null,
          description: 'No FoodData Central match',
          dataType: null,
          confidence: 0,
          grams: null,
          gramSource: null,
          status: 'unmatched',
        ),
      );
      continue;
    }

    // Candidate selection handles two real FDC quirks: the detail
    // endpoint 404s for superseded records (the search payload's own
    // nutrient list stands in), and some records omit whole macros
    // (Foundation butter publishes no energy or saturated fat at all) —
    // a macro-complete record slightly lower in the ranking beats an
    // incomplete one at the top.
    RankedCandidate? best;
    FdcFood? food;
    RankedCandidate? fallbackCandidate;
    FdcFood? fallbackFood;
    for (final candidate in ranked.take(3)) {
      var resolved = await _cachedFood(db, provider, candidate.candidate.fdcId);
      if (resolved == null &&
          (candidate.candidate.nutrientsPer100g?.isNotEmpty ?? false)) {
        resolved = candidate.candidate.toFood();
        db.fdcFoodCachePut(resolved.fdcId, jsonEncode(resolved.toJson()));
      }
      if (resolved == null) {
        continue;
      }
      if (_macroComplete(resolved)) {
        best = candidate;
        food = resolved;
        break;
      }
      fallbackCandidate ??= candidate;
      fallbackFood ??= resolved;
    }
    if (best == null && fallbackCandidate != null) {
      best = fallbackCandidate;
      food = fallbackFood;
    }
    if (best == null) {
      db.upsertIngredientMatchIfUndecided(
        IngredientMatchRow(
          recipeId: recipe.id,
          position: position,
          raw: line.raw,
          itemKey: key,
          fdcId: null,
          description: 'No fetchable FoodData Central match',
          dataType: null,
          confidence: 0,
          grams: null,
          gramSource: null,
          status: 'unmatched',
        ),
      );
      continue;
    }
    final resolution = resolveGrams(
      amounts: line.amounts,
      food: food,
      normalizedItem: normalized,
      raw: line.raw,
    );
    db.upsertIngredientMatchIfUndecided(
      IngredientMatchRow(
        recipeId: recipe.id,
        position: position,
        raw: line.raw,
        itemKey: key,
        fdcId: best.candidate.fdcId,
        description: best.candidate.description,
        dataType: best.candidate.dataType,
        confidence: best.confidence,
        grams: resolution?.grams,
        gramSource: resolution?.source.name,
        status: 'auto',
      ),
    );
  }

  // Lines removed by an edit leave orphan rows behind.
  db.deleteIngredientMatchesFrom(recipe.id, lines.length);

  await recomputeTotals(db, provider, recipe, freshMatch: true);
}

/// A person's call on a row: anything but the engine's own `auto` and
/// `unmatched`.
bool _isDecided(IngredientMatchRow row) =>
    row.status != 'auto' && row.status != 'unmatched';

/// Recomputes the stored per-serving totals from the persisted matches —
/// instant (food details come from the cache; no searches).
Future<void> recomputeTotals(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe recipe, {
  int? servingBasis,
  bool freshMatch = false,
}) async {
  final lines = nutritionLines(recipe);
  // Rows beyond the current line count are orphans from an edit — they
  // must not contribute (matchAndCompute deletes them; a recompute
  // between the edit and the next full match must ignore them).
  final matches = db
      .ingredientMatchesFor(recipe.id)
      .where((row) => row.position < lines.length)
      .toList();
  final stored = db.nutritionFor(recipe.id);
  // Servings first; then the recipe's YIELD count as an editable default so
  // 'MAKES ABOUT 16 LARGE COOKIES' still lands per-cookie rather than
  // reporting one 16-cookie batch as a serving. A yield is not a serving
  // count (that is why it never reaches Recipe.serves) — it is only a
  // better starting basis than the whole batch, and the admin can override.
  var basis =
      servingBasis ??
      stored?.servingBasis ??
      recipe.serves?.min ??
      parseYieldCount(recipe.servings)?.min ??
      1;
  if (basis < 1) {
    basis = 1; // Hand-edited YAML can carry serves 0.
  }

  final totals = <String, double>{};
  var totalGrams = 0.0;
  var contributing = 0;
  var accounted = 0;
  for (final row in matches) {
    if (row.status == 'skipped') {
      accounted += 1;
      continue;
    }
    if (row.fdcId == null) {
      // Water-like confirmed rows count as fully accounted zeros.
      if (row.status == 'confirmed') {
        accounted += 1;
        contributing += 1;
      }
      continue;
    }
    final grams = row.grams;
    if (grams == null || grams <= 0) {
      continue;
    }
    // Held for review: a low-confidence auto match is likely the WRONG food,
    // so it stays out of the totals — a bad match must never silently feed the
    // label. It still surfaces in the review sheet ("check match"); confirming
    // or re-picking it (status leaves 'auto') opts it back in. The recipe also
    // stays "partial" until then, since the line is not yet accounted.
    if (row.status == 'auto' && row.confidence < lowConfidence) {
      continue;
    }
    final food = await _cachedFood(db, provider, row.fdcId!);
    if (food == null) {
      continue;
    }
    accounted += 1;
    contributing += 1;
    totalGrams += grams;
    for (final def in nutrientDefs) {
      for (final number in def.fdcNumbers) {
        final per100 = food.nutrientsPer100g[number];
        if (per100 != null) {
          totals[def.key] = (totals[def.key] ?? 0) + per100 * grams / 100;
          break;
        }
      }
    }
    // A record without any published energy still contributes calories
    // via the standard Atwater 4/9/4 factors — FDC's own computed-energy
    // fields do the same math.
    final hasEnergy =
        food.nutrientsPer100g.containsKey('208') ||
        food.nutrientsPer100g.containsKey('957') ||
        food.nutrientsPer100g.containsKey('958');
    if (!hasEnergy) {
      final protein = food.nutrientsPer100g['203'] ?? 0;
      final fat = food.nutrientsPer100g['204'] ?? 0;
      final carbs = food.nutrientsPer100g['205'] ?? 0;
      totals['energy'] =
          (totals['energy'] ?? 0) +
          (4 * protein + 9 * fat + 4 * carbs) * grams / 100;
    }
  }

  final perServing = <String, Map<String, Object?>>{};
  for (final def in nutrientDefs) {
    final total = totals[def.key];
    if (total == null) {
      continue;
    }
    final amount = total / basis;
    perServing[def.key] = {
      'label': def.label,
      'amount': double.parse(amount.toStringAsFixed(2)),
      'unit': def.unit,
      if (def.dailyValue != null)
        'dv_percent': double.parse(
          (amount / def.dailyValue! * 100).toStringAsFixed(1),
        ),
    };
  }

  final calories = perServing['energy']?['amount'] as double?;
  final status = accounted >= lines.length ? 'complete' : 'partial';
  // Only a full re-match may stamp the current recipe's hash — a plain
  // recompute (serving basis, match override) after an ingredient edit
  // must keep reporting `stale` until the admin recomputes for real.
  final hash = freshMatch
      ? ingredientsHashOf(recipe)
      : (stored?.ingredientsHash ?? ingredientsHashOf(recipe));
  db.upsertRecipeNutrition(
    recipeId: recipe.id,
    servingBasis: basis,
    caloriesPerServing: calories,
    nutrientsJson: jsonEncode(perServing),
    totalGrams: double.parse(totalGrams.toStringAsFixed(1)),
    matchedCount: contributing > lines.length ? lines.length : contributing,
    totalCount: lines.length,
    status: status,
    ingredientsHash: hash,
  );
  _log.info(
    'Nutrition for ${recipe.id}: $status, '
    '$contributing/${lines.length} lines, '
    '${calories?.toStringAsFixed(0) ?? '?'} kcal/serving (basis $basis)',
  );
}

/// Re-ranked candidates for one line. With [cacheOnly] (the GET path —
/// any authenticated user) the search cache is the sole source: a read
/// must never spend the FDC request budget or block on the rate limiter.
Future<List<RankedCandidate>> candidatesForLine(
  SaltDatabase db,
  NutritionProvider provider,
  IngredientLine line, {
  bool cacheOnly = false,
}) async {
  final normalized = normalizeItem(line.item ?? line.raw);
  if (normalized.isEmpty || isWaterLike(normalized)) {
    return const [];
  }
  final query = searchQueryFor(normalized);
  final List<FdcCandidate> candidates;
  if (cacheOnly) {
    final cached = db.fdcSearchCacheGet(query);
    if (cached == null) {
      return const [];
    }
    candidates = [
      for (final entry in jsonDecode(cached) as List<dynamic>)
        FdcCandidate.fromJson(entry as Map<String, dynamic>),
    ];
  } else {
    candidates = await _cachedSearch(db, provider, query);
  }
  return rankCandidates(query, candidates).take(8).toList();
}

/// Ranked candidates for an ADMIN-SUPPLIED search term — the review sheet's
/// manual re-pick, for when none of the auto-found candidates fit (the
/// matcher searched the wrong words, e.g. "minced oregano" -> ham).
///
/// Unlike [candidatesForLine]'s cache-only GET path this MAY spend the FDC
/// request budget on a cache miss, which is why its route is admin-only. The
/// term is normalized so it shares the matcher's cache keys and ranking.
Future<List<RankedCandidate>> searchCandidates(
  SaltDatabase db,
  NutritionProvider provider,
  String query, {
  bool fresh = false,
}) async {
  final normalized = normalizeItem(query);
  if (normalized.isEmpty) {
    return const [];
  }
  final rewritten = searchQueryFor(normalized);
  final candidates = await _cachedSearch(db, provider, rewritten, fresh: fresh);
  return rankCandidates(rewritten, candidates).take(8).toList();
}

/// A short, human-readable description of what the stored grams were computed
/// against — e.g. "½ cup ≈ 118 mL" for a density estimate, "8¾ ounces" for a
/// direct weight — so a reviewer can sanity-check a volume/piece estimate.
///
/// Cache-only (the food comes from the local cache, never a fresh FDC call),
/// so it is safe on the member-callable matches GET. Null when the line has no
/// amount, or when the grams were entered by hand. Re-derived rather than
/// stored; deterministic, so it matches the stored grams for the common case.
String? gramBasisFor(
  SaltDatabase db,
  IngredientLine line,
  IngredientMatchRow row,
) {
  if (row.grams == null) {
    return null;
  }
  if (row.gramSource == 'override') {
    return 'entered by hand';
  }
  FdcFood? food;
  final fdcId = row.fdcId;
  if (fdcId != null) {
    final cached = db.fdcFoodCacheGet(fdcId);
    if (cached != null) {
      food = FdcFood.fromJson(jsonDecode(cached) as Map<String, dynamic>);
    }
  }
  return resolveGrams(
    amounts: line.amounts,
    food: food,
    normalizedItem: normalizeItem(line.item ?? line.raw),
    raw: line.raw,
  )?.basis;
}

Future<List<FdcCandidate>> _cachedSearch(
  SaltDatabase db,
  NutritionProvider provider,
  String query, {
  bool fresh = false,
}) async {
  // [fresh]: a person asked for a live answer — skip the cache and replace
  // the stored row, so the next compute sees the newer answer too.
  final cached = fresh ? null : db.fdcSearchCacheGet(query);
  if (cached != null) {
    return [
      for (final entry in jsonDecode(cached) as List<dynamic>)
        FdcCandidate.fromJson(entry as Map<String, dynamic>),
    ];
  }
  final results = await provider.search(query);
  // A live answer with NO hits must not evict a stored one that had some:
  // the cache never expires and an empty row is a hit, so one no-hits reply
  // would blank every line with this item — and the compute path — for
  // good. (A provider error already throws before this write; this is the
  // 200-with-no-foods case.) The caller still gets the live answer.
  if (fresh && results.isEmpty) {
    final stored = db.fdcSearchCacheGet(query);
    if (stored != null && stored != '[]') {
      return results;
    }
  }
  db.fdcSearchCachePut(
    query,
    jsonEncode([for (final candidate in results) candidate.toJson()]),
  );
  return results;
}

/// Food detail through the cache; null when FDC has no such id.
Future<FdcFood?> _cachedFood(
  SaltDatabase db,
  NutritionProvider provider,
  int fdcId,
) async {
  final cached = db.fdcFoodCacheGet(fdcId);
  if (cached != null) {
    return FdcFood.fromJson(jsonDecode(cached) as Map<String, dynamic>);
  }
  final food = await provider.food(fdcId);
  if (food != null) {
    db.fdcFoodCachePut(fdcId, jsonEncode(food.toJson()));
  }
  return food;
}

/// Public cache-aware food lookup (the match-override endpoint needs it).
Future<FdcFood?> cachedFood(
  SaltDatabase db,
  NutritionProvider provider,
  int fdcId,
) => _cachedFood(db, provider, fdcId);

/// Lands [food] — a person's decision on [itemKey] made on the line
/// [excluding] — on every other undecided line with that item (other
/// recipes, and the same recipe's other lines) not already on that food,
/// each with grams from its own amounts, then recomputes those recipes'
/// totals.
///
/// The rows are written as `auto` at confidence 1 — machine propagation of
/// a human decision, exactly like inheritance at compute time — NOT as a
/// human status: a status of `overridden` would shield them from every
/// later propagation, so a wrong pick applied to 456 recipes could never be
/// corrected in bulk. As `auto` rows they are reached again by a corrective
/// apply-to-all and re-inherited from the newest decision at the next
/// sweep, while a decision a person makes on any of them still stands.
///
/// A decision already made on a target line stands: the write is guarded
/// at the statement, and a guarded-out write is not counted. A row whose
/// recipe no longer has that line, or whose text changed, is left for the
/// next compute. A recipe that fails — its document will not decode, or the
/// provider fails while its totals recompute — is logged, counted in
/// `failed`, and does not stop the rest; what was already written stays,
/// and the counts say exactly what landed.
Future<({int recipes, int lines, int failed})> applyDecisionToOthers(
  SaltDatabase db,
  NutritionProvider provider, {
  required String itemKey,
  required FdcFood food,
  required ({String recipeId, int position}) excluding,
}) async {
  final byRecipe = <String, List<IngredientMatchRow>>{};
  for (final target in db.undecidedMatchesForItemKey(
    itemKey,
    excluding: excluding,
    fdcId: food.fdcId,
  )) {
    byRecipe.putIfAbsent(target.recipeId, () => []).add(target);
  }
  var recipes = 0;
  var lines = 0;
  var failed = 0;
  for (final entry in byRecipe.entries) {
    try {
      final found = db.recipeByIdOrSlug(entry.key);
      if (found == null) {
        continue; // Deleted meanwhile; its rows cascaded away.
      }
      final recipeLines = nutritionLines(found.recipe);
      var applied = 0;
      for (final target in entry.value) {
        if (target.position >= recipeLines.length) {
          continue;
        }
        final line = recipeLines[target.position];
        if (line.raw != target.raw) {
          continue; // The line changed since that row was written.
        }
        final resolution = resolveGrams(
          amounts: line.amounts,
          food: food,
          // The grams tables match on the line's own words, not the key.
          normalizedItem: normalizeItem(line.item ?? line.raw),
          raw: line.raw,
        );
        final written = db.upsertIngredientMatchIfUndecided(
          IngredientMatchRow(
            recipeId: found.recipe.id,
            position: target.position,
            raw: line.raw,
            itemKey: itemKey,
            fdcId: food.fdcId,
            description: food.description,
            dataType: food.dataType,
            confidence: 1,
            grams: resolution?.grams,
            gramSource: resolution?.source.name,
            status: 'auto',
          ),
        );
        if (written) {
          applied += 1;
        }
      }
      if (applied == 0) {
        continue;
      }
      await recomputeTotals(db, provider, found.recipe);
      recipes += 1;
      lines += applied;
      // A recipe that will not decode, or whose totals cannot recompute
      // (the provider failed), must not stop the rest — and must be counted.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      failed += 1;
      _log.warning('apply-to-all failed for ${entry.key}: $error');
    }
  }
  return (recipes: recipes, lines: lines, failed: failed);
}
