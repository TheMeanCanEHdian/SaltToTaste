// The v111 pins (fix111: dual-fleet review Run 091/092, union_Y): Y1 the
// rule row's target is its DETAIL (a), `_heldOnOf`'s own-record read (b), a
// re-hold writes `held_on` as computed (c); Y2 "second food" only for a
// pair's second record; Y4 the fleets' surviving mutants; Y9 ONE corpusless
// pin of the negated-act bridge. Corpus-backed except Y9: the group skips
// without SALT_CORPUS_DIR, and every corpus read sits inside a test body
// (the loader never reads the corpus).
// ignore_for_file: lines_longer_than_80_chars
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'nutrition_v28_rule_a_test.dart' as v28;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

final _fx = FixtureProvider(pending: pendingSearches);

const _beef = '0536-crispy-orange-beef.yaml';
const _peel = 169103;
const _juice = 169098;
const _plain =
    'USDA could not serve this food — pick another food or skip the line.';
const _second =
    "USDA could not serve this line's second food — pick another food or "
    'skip the line.';

void main() {
  y9();
  group('v111 (fix111: Run 091/092 union Y)', skip: skipIfNoCorpus, () {
    y1a();
    y1bc();
    y2();
    y4();
  });
}

/// Y9 (Sonnet critic 3, unionY/c C4): every v110 server pin of the bridge
/// is corpus-gated, so CI ran none. [defatsSentence] needs a sentence
/// alone. STATED synthesized NEGATIVE-path sentences (as CLAUDE.md allows;
/// v110 X4's own re-texts of 0224 Braised Brisket's "skim fat from surface
/// and discard" — no corpus step holds them: the corpus scan's 24,173
/// sentences hold no punctuation-only token). Measured (C4): v109 false on
/// the dash / quote tokens, v110 true; a word bridge negated on both.
void y9() {
  test('v111 Y9 (corpusless): a punctuation-only token is no bridge word — '
      'a real skim; a word bridge (an apostrophe, a hyphen) is still '
      'negated', () {
    for (final (sentence, skims) in [
      ('Do not skim the foam - just fat.', true),
      ('Do not skim the foam -- just fat.', true),
      ("Do not skim the foam ' just fat.", true),
      ('Do not skim the foam ’ just fat.', true),
      ("Do not skim the soup's fat.", false),
      ('Do not skim the pan-juice fat.', false),
      ("Do not skim the 'nduja fat.", false),
    ]) {
      expect(
        defatsSentence(sentence.toLowerCase()),
        skims,
        reason: sentence,
      );
    }
  });
}

void _dropDetail(String path, int id) {
  sqlite3.open(path)
    ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [id])
    ..dispose();
}

class _Asks implements NutritionProvider {
  _Asks(this.inner);
  final NutritionProvider inner;
  final asked = <int>[];
  @override
  Future<List<FdcCandidate>> search(String query) => inner.search(query);
  @override
  Future<FdcFood?> food(int fdcId) {
    asked.add(fdcId);
    return inner.food(fdcId);
  }
}

Future<Map<String, Object?>> _matchOf(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe r,
  int at,
) async {
  final body = await matchesBody(db, provider, r);
  final item = (body['items']! as List)[at] as Map<String, Object?>;
  return item['match']! as Map<String, Object?>;
}

Future<String> _confirmRefusal(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe r,
  int at,
) async {
  try {
    await applyMatchOverride(db, provider, r, at, {
      'raw': nutritionLines(r)[at].raw,
      'confirmed': true,
    });
    return 'ACCEPTED';
  } on ValidationException catch (e) {
    return e.message;
  }
}

/// 0536 (or [file]) computed with the fixtures, a search answer listing the
/// rule's record [peel] cached ([query], the fixtures' own answer), the
/// peel's DETAIL dropped: the stand-in alone. STATED synthesized (the
/// fleets' negative-path state, as v110 X2's: no code evicts
/// fdc_food_cache).
Future<(SaltDatabase, String, Recipe)> _peelStandIn({
  String file = _beef,
  int peel = _peel,
  String query = 'orange peel',
  bool skipFirst = false,
  int at = 3,
}) async {
  final (db, path) = a.pathDb();
  final r = loadCorpusRecipe(file);
  await d.editAndCompute(db, _fx, r);
  await searchCandidates(db, _fx, query);
  if (skipFirst) {
    await applyMatchOverride(db, _fx, r, at, {
      'raw': nutritionLines(r)[at].raw,
      'skipped': true,
    });
  }
  _dropDetail(path, peel);
  // Not vacuous: no detail, a stand-in.
  expect(db.fdcFoodCacheGet(peel), isNull);
  expect(knownFood(db, peel), isNotNull);
  return (db, path, r);
}

/// Y1 (a) (S1 S2 S8 S10 S11 / O1 O4 O9, unionY/a A3): `_ruleRowFor`'s
/// target read [knownFood] FIRST — with the peel's detail uncached and a
/// search answer listing it, 0536 line 3 ("10 (3-inch) strips orange peel …
/// plus ¼ cup juice (2 oranges)": peel 169103, juice 169098) was stored
/// `auto`, unheld, grams NULL, FRESH, 0 asks, never re-opened (591.13 for
/// 603.92 kcal per serving). v111: the target is the DETAIL ([cachedFood]),
/// the stand-in only when FDC answers "no such food" — then held
/// `food_gone` on its own record. Figures: the fixtures' (v109 W8's 86.0 g,
/// 603.92 kcal; the skipped line's 591.13).
void y1a() {
  void healed(SaltDatabase db, Recipe r, String status) {
    final row = d.rowOf(db, r, 3);
    expect(
      (row.status, row.fdcId, row.hold, row.heldOn, row.grams),
      (status, _peel, null, null, 86.0),
    );
    expect([for (final p in partsOf(row.parts)) p.fdcId], [_peel, _juice]);
    expect(nutritionIsFresh(db, r), isTrue);
    // RE-PIN (M105 batch, v118): crispy-orange-beef|11 "2 tablespoons grated fresh ginger" on 169231 at the record's tsp 2.0 g, 15.97 → 12.00 g (−3.18 kcal ÷ 4 servings): 603.92 → 603.13.
    expect(db.nutritionFor(r.id)!.caloriesPerServing, closeTo(603.13, 0.005));
  }

  test('Y1 (a) FDC serving: ONE ask, the pair derived (86.0 g, two parts, '
      '603.92, fresh); the matches GET asks 0', () async {
    final (db, _, r) = await _peelStandIn();
    final get = _Asks(_fx);
    await matchesBody(db, get, r);
    expect(get.asked, isEmpty);
    final serve = _Asks(_fx);
    db.clearDerivedSeq(r.id, [3]);
    await matchAndCompute(db, serve, r);
    // Base: [] — (auto, hold null, grams NULL) fresh at 591.13.
    expect(serve.asked, [_peel]);
    healed(db, r, 'auto');
  });

  test('Y1 (a) a FOOD failure: returned, the row as stored (stale); a '
      'GLOBAL failure: thrown, the row as stored; each heals at FDC '
      'serving', () async {
    for (final scope in [FailureScope.food, FailureScope.global]) {
      final (db, _, r) = await _peelStandIn();
      final stored = d.rowOf(db, r, 3);
      final down = v28.FoodFault(_fx, {_peel}, scope: scope);
      db.clearDerivedSeq(r.id, [3]);
      Object? thrown;
      NutritionProviderException? returned;
      try {
        returned = await matchAndCompute(db, down, r);
      } on NutritionProviderException catch (e) {
        thrown = e;
      }
      // Base: 0 asks, nothing returned or thrown, the stand-in's NULL row.
      expect(down.asked, 1, reason: '$scope');
      expect(
        (returned?.scope, thrown != null),
        scope == FailureScope.food ? (FailureScope.food, false) : (null, true),
        reason: '$scope',
      );
      final kept = d.rowOf(db, r, 3);
      expect(
        (kept.status, kept.hold, kept.grams, kept.parts),
        (stored.status, null, 86.0, stored.parts),
        reason: '$scope',
      );
      expect(nutritionIsFresh(db, r), isFalse, reason: '$scope');
      await matchAndCompute(db, _fx, r);
      healed(db, r, 'auto');
    }
  });

  test('Y1 (a) GONE: one ask, held food_gone on its OWN record (no '
      'held_on), out of the totals; 0 asks after; re-opened by the '
      "record's arrival", () async {
    final (db, _, r) = await _peelStandIn();
    final gone = v28.FoodFault(_fx, {_peel}, gone: true);
    db.clearDerivedSeq(r.id, [3]);
    await matchAndCompute(db, gone, r);
    expect(gone.asked, 1);
    final held = d.rowOf(db, r, 3);
    // Base: 0 asks, (auto, hold null, grams NULL) fresh — unheld.
    expect(
      (held.status, held.fdcId, held.hold, held.heldOn, held.grams),
      ('auto', _peel, 'food_gone', null, null),
    );
    expect(held.parts, isNull);
    // RE-PIN (M105 batch, v118): crispy-orange-beef|11 "2 tablespoons grated fresh ginger" on 169231 at the record's tsp 2.0 g, 15.97 → 12.00 g (−3.18 kcal ÷ 4 servings): 591.13 → 590.33.
    expect(db.nutritionFor(r.id)!.caloriesPerServing, closeTo(590.33, 0.005));
    for (var p = 2; p <= 3; p++) {
      await matchAndCompute(db, gone, r);
      expect(gone.asked, 1, reason: 'compute $p');
    }
    expect(nutritionIsFresh(db, r), isTrue);
    final match = await _matchOf(db, gone, r, 3);
    expect(match['hold'], 'food_gone');
    expect(match.containsKey('held_on'), isFalse);
    expect(gone.asked, 1);
    await cachedFood(db, _fx, _peel);
    expect(nutritionIsFresh(db, r), isFalse);
    await matchAndCompute(db, gone, r);
    healed(db, r, 'auto');
  });

  test('Y1 (a) GONE on a rule record whose stand-in RESOLVES grams (a juice '
      'by density, eggs by piece): held food_gone with NO grams', () async {
    // Owner gate (the hand-edit verifier's VA1): the gone row keeping the
    // stand-in's grams survived both peel pins — their stand-ins give none;
    // a portion-less stand-in resolves grams on 105 of the 115 corpus rule
    // lines (the verifier's scan).
    for (final (file, at, record, query) in [
      ('0859-marbled-blueberry-bundt-cake.yaml', 15, 167747, 'lemon juice'),
      ('0866-french-apple-cake.yaml', 7, 748967, 'egg'),
    ]) {
      final (db, _, r) = await _peelStandIn(
        file: file,
        peel: record,
        query: query,
        at: at,
      );
      final gone = v28.FoodFault(_fx, {record}, gone: true);
      db.clearDerivedSeq(r.id, [at]);
      await matchAndCompute(db, gone, r);
      expect(gone.asked, 1, reason: file);
      final row = d.rowOf(db, r, at);
      expect(
        (row.fdcId, row.hold, row.heldOn, row.grams, row.gramSource),
        (record, 'food_gone', null, null, null),
        reason: file,
      );
      final match = await _matchOf(db, gone, r, at);
      expect(
        (match['hold'], match['grams'], match['gram_source']),
        ('food_gone', null, null),
        reason: file,
      );
    }
  });

  test("Y1 (a) the UN-SKIP's next compute keeps the PUT's food_unavailable "
      'hold, 0 asks; the arrival heals it', () async {
    final (db, _, r) = await _peelStandIn(skipFirst: true);
    await applyMatchOverride(db, _fx, r, 3, {
      'raw': nutritionLines(r)[3].raw,
      'skipped': false,
    });
    expect(
      (d.rowOf(db, r, 3).hold, d.rowOf(db, r, 3).heldOn),
      ('food_unavailable', null),
    );
    final next = _Asks(_fx);
    await matchAndCompute(db, next, r);
    expect(next.asked, isEmpty);
    final row = d.rowOf(db, r, 3);
    // Base: (auto, hold NULL, grams NULL) fresh at 591.13 — the stand-in.
    expect(
      (row.status, row.hold, row.heldOn, row.grams),
      ('auto', 'food_unavailable', null, null),
    );
    expect(nutritionIsFresh(db, r), isTrue);
    // RE-PIN (M105 batch, v118): crispy-orange-beef|11 "2 tablespoons grated fresh ginger" on 169231 at the record's tsp 2.0 g, 15.97 → 12.00 g (−3.18 kcal ÷ 4 servings): 591.13 → 590.33.
    expect(db.nutritionFor(r.id)!.caloriesPerServing, closeTo(590.33, 0.005));
    await cachedFood(db, _fx, _peel);
    await matchAndCompute(db, next, r);
    expect(next.asked, isEmpty);
    healed(db, r, 'auto');
  });

  test('Y1 (a) a DENSITY pair (0142 line 8, lemon peel 167749 + juice '
      '167747): serving derives the stored pair at ONE ask; gone holds '
      'food_gone on the peel', () async {
    const file = '0142-skillet-roasted-chicken-in-lemon-sauce.yaml';
    const peel = 167749;
    for (final gone in [false, true]) {
      final (db, _, r) = await _peelStandIn(
        file: file,
        peel: peel,
        query: 'lemon zest',
        at: 8,
      );
      final stored = d.rowOf(db, r, 8);
      expect(partsOf(stored.parts).length, 2);
      final kcal = db.nutritionFor(r.id)!.caloriesPerServing;
      final fault = v28.FoodFault(_fx, {peel}, gone: true)..up = !gone;
      final serve = _Asks(fault);
      db.clearDerivedSeq(r.id, [8]);
      await matchAndCompute(db, serve, r);
      expect(serve.asked, [peel], reason: '$gone');
      final row = d.rowOf(db, r, 8);
      if (gone) {
        expect(
          (row.fdcId, row.hold, row.heldOn, row.grams, row.parts),
          (peel, 'food_gone', null, null, null),
        );
        await matchAndCompute(db, serve, r);
        expect(serve.asked, [peel]);
      } else {
        // The stored pair re-derived (68.92 g on the fixtures: zest 8.0 +
        // juice 60.92), the kcal as before the drop.
        expect(
          (row.hold, row.grams, row.parts),
          (null, stored.grams, stored.parts),
        );
        expect(row.grams, 68.92);
        expect(nutritionIsFresh(db, r), isTrue);
        expect(db.nutritionFor(r.id)!.caloriesPerServing, kcal);
      }
    }
  });
}

/// Y1 (b) O8 (a v110 regression vs v109, unionY/a A4 (b), unionY/c C1):
/// `_heldOnOf`'s own-record test read [knownFood] — with BOTH details
/// uncached (search answers listing each cached) and the PEEL failing, the
/// confirm's hold was pinned ON the juice (held_on 169098, "this line's
/// second food"; v109: null, "this food"). v111: the own record is its
/// DETAIL. Y1 (c) (Opus critic 1, unionY/a A6): a re-hold kept a STALE
/// `held_on` (`copyWith` keeps it on a null argument) — a row held ON the
/// juice whose juice then ARRIVED and whose PEEL then failed stayed
/// `held_on: 169098`, served and worded "second food", under the `all`
/// scope's `retryUnavailable`. v111: held_on AS COMPUTED, null clears it.
/// STATED synthesized: the dropped details and the provider faults.
void y1bc() {
  test(
    'Y1 (b) O8: the peel failing with both details uncached is the '
    "row's OWN failure — no held_on, \"this food\"; the control (juice "
    'cached) alike; the orange rule and a DENSITY pair (0142 line 8)',
    () async {
      // Owner gate: the own-record test narrowed to the orange peel survived
      // the orange row alone — every rule record reads its DETAIL.
      for (final (file, at, peel, juice, peelQuery, juiceQuery) in [
        (_beef, 3, _peel, _juice, 'orange peel', 'orange juice'),
        (
          '0142-skillet-roasted-chicken-in-lemon-sauce.yaml',
          8,
          167749,
          167747,
          'lemon zest',
          'lemon juice',
        ),
      ]) {
        for (final dropJuice in [false, true]) {
          final why = '$file $dropJuice';
          final (db, path, r) = await _peelStandIn(
            file: file,
            peel: peel,
            query: peelQuery,
            at: at,
          );
          await searchCandidates(db, _fx, juiceQuery);
          if (dropJuice) {
            _dropDetail(path, juice);
            expect(knownFood(db, juice), isNotNull, reason: why);
          }
          final down = v28.FoodFault(_fx, {peel}, scope: FailureScope.food);
          await applyMatchOverride(db, down, r, at, {
            'raw': nutritionLines(r)[at].raw,
            'confirmed': true,
          });
          for (var p = 0; p < 3; p++) {
            db.clearDerivedSeq(r.id, [at]);
            await matchAndCompute(db, down, r);
          }
          final row = d.rowOf(db, r, at);
          // Base (dropJuice): held_on the juice, the body's key, "second food".
          expect(
            (row.status, row.fdcId, row.hold, row.heldOn),
            ('confirmed', peel, 'food_unavailable', null),
            reason: why,
          );
          final match = await _matchOf(db, down, r, at);
          expect(match.containsKey('held_on'), isFalse, reason: why);
          expect(await _confirmRefusal(db, down, r, at), _plain, reason: why);
        }
      }
    },
  );

  test('Y1 (c) A6: held ON the juice, the juice arrives, the PEEL fails — '
      'the re-hold clears held_on (engine and confirm arms, retryUnavailable '
      'false and true)', () async {
    for (final confirm in [false, true]) {
      for (final retry in [false, true]) {
        final why = 'confirm $confirm retry $retry';
        final (db, path) = a.pathDb();
        final r = loadCorpusRecipe(_beef);
        await d.editAndCompute(db, _fx, r);
        await searchCandidates(db, _fx, 'orange juice');
        await searchCandidates(db, _fx, 'orange peel');
        _dropDetail(path, _juice);
        final jDown = v28.FoodFault(_fx, {_juice}, scope: FailureScope.food);
        if (confirm) {
          await applyMatchOverride(db, jDown, r, 3, {
            'raw': nutritionLines(r)[3].raw,
            'confirmed': true,
          });
        }
        db.clearDerivedSeq(r.id, [3]);
        for (var p = 1; p <= foodUnavailableAfter; p++) {
          await matchAndCompute(db, jDown, r);
        }
        // Not vacuous: held ON the juice first.
        expect(
          (d.rowOf(db, r, 3).hold, d.rowOf(db, r, 3).heldOn),
          ('food_unavailable', _juice),
          reason: why,
        );
        _dropDetail(path, _peel);
        await cachedFood(db, _fx, _juice);
        final pDown = v28.FoodFault(_fx, {_peel}, scope: FailureScope.food);
        for (var p = 1; p <= foodUnavailableAfter; p++) {
          await matchAndCompute(db, pDown, r, retryUnavailable: retry);
        }
        // retryUnavailable asks once per pass; else the re-read is
        // cache-only.
        expect(pDown.asked, retry ? foodUnavailableAfter : 0, reason: why);
        final row = d.rowOf(db, r, 3);
        // Base (retry): held_on 169098 STALE — the juice cached and fine.
        expect(
          (row.status, row.hold, row.heldOn, row.grams),
          (confirm ? 'confirmed' : 'auto', 'food_unavailable', null, null),
          reason: why,
        );
        expect(nutritionIsFresh(db, r), isTrue, reason: why);
        final match = await _matchOf(db, _fx, r, 3);
        expect(match.containsKey('held_on'), isFalse, reason: why);
        expect(await _confirmRefusal(db, pDown, r, 3), _plain, reason: why);
      }
    }
  });
}

/// Y2 (S3 S9 / O2 O3 O7, unionY/c C1; a v110 regression vs v109): the
/// "second food" key and texts read `held_on != fdc_id` alone, and
/// `_heldOnOf`'s parts loop stamps `held_on` with a rule B1 BACON row's own
/// uncached part: 0040 Wilted Spinach Salad line 5 (row 168277, parts
/// 168322 + 172345, no role) held on 168322 was served `held_on` and
/// refused with "this line's second food". v111: only a pair's second
/// record (no stored part, or the part stored under it is the `juice`).
/// v103 U5's state (0118 computed first; 168322 dropped from both caches,
/// a FOOD outage on it ×3 computes) — STATED synthesized as there.
void y2() {
  test('Y2: a bacon row held on its own part reads "this food" — no '
      'held_on key; a pair held ON its juice WITH its parts kept keeps the '
      'key and "second food"', () async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe(
      '0040-wilted-spinach-salad-with-warm-bacon-dressing.yaml',
    );
    await d.editAndCompute(
      db,
      _fx,
      loadCorpusRecipe(
        '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
      ),
    );
    await d.editAndCompute(db, _fx, r);
    v28.dropFood(path, 168322);
    final fault = v28.FoodFault(_fx, {168322}, scope: FailureScope.food);
    for (var p = 1; p <= 3; p++) {
      await matchAndCompute(db, fault, r);
    }
    final bacon = d.rowOf(db, r, 5);
    expect(
      (bacon.fdcId, bacon.hold, bacon.heldOn),
      (168277, 'food_unavailable', 168322),
    );
    // Base: held_on 168322 served, "this line's second food".
    final match = await _matchOf(db, fault, r, 5);
    expect(match.containsKey('held_on'), isFalse);
    expect(await _confirmRefusal(db, fault, r, 5), _plain);

    // State 1c: 0536's pair, the juice dropped from both caches, a FOOD
    // outage ×3 computes — the parts loop names the juice, parts KEPT.
    final (db2, path2) = a.pathDb();
    final r2 = loadCorpusRecipe(_beef);
    await d.editAndCompute(db2, _fx, r2);
    v28.dropFood(path2, _juice);
    final down = v28.FoodFault(_fx, {_juice}, scope: FailureScope.food);
    for (var p = 1; p <= 3; p++) {
      await matchAndCompute(db2, down, r2);
    }
    final pair = d.rowOf(db2, r2, 3);
    expect(
      (pair.status, pair.hold, pair.heldOn),
      ('auto', 'food_unavailable', _juice),
    );
    expect([for (final p in partsOf(pair.parts)) p.fdcId], [_peel, _juice]);
    final match2 = await _matchOf(db2, down, r2, 3);
    expect(match2['held_on'], _juice);
    expect(await _confirmRefusal(db2, down, r2, 3), _second);
  });
}

/// Y4 (S6 S7, unionY/c C2): pins for mutants that survived once each.
/// S6: the apply_to_all refusal under `food_unavailable` — reached ONLY by
/// an UN-SKIP carrying apply_to_all (a held row's confirm is answered by
/// the gate first): 0536 skipped, the juice dropped, a FOOD outage, the
/// un-skip + apply_to_all → 422, nothing written. S7 (a): `_heldOnOf`'s pair
/// arm on the two DENSITY juices (0142 line 8 → 167747; 0989 Key Lime Pie
/// line 1 → 168156). S7 (b): its parts loop reads [knownFood] (the pin of
/// Y1's "the parts loop stays", unionY/a A4 (c)) — 0040 line 5 held on its
/// kept-fat part 172345 with 168322 a search-listed stand-in (a hit of
/// 0118's "thin-sliced cooked deli ham" answer, snapshot 32's own state)
/// names 172345, never 168322. STATED synthesized: the cache deletions and
/// the provider faults.
void y4() {
  test('Y4 S6: an un-skip carrying apply_to_all under the juice outage is '
      "refused \"this line's second food\"; the row stays skipped", () async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe(_beef);
    final raw = nutritionLines(r)[3].raw;
    await d.editAndCompute(db, _fx, r);
    await applyMatchOverride(db, _fx, r, 3, {'raw': raw, 'skipped': true});
    v28.dropFood(path, _juice);
    final down = v28.FoodFault(_fx, {_juice}, scope: FailureScope.food);
    await expectLater(
      applyMatchOverride(db, down, r, 3, {
        'raw': raw,
        'skipped': false,
        'apply_to_all': true,
      }),
      throwsA(
        isA<ValidationException>().having((e) => e.message, 'message', _second),
      ),
    );
    expect(d.rowOf(db, r, 3).status, 'skipped');
  });

  test('Y4 S7 (a): an un-skip under the outage holds a density pair ON its '
      'juice', () async {
    for (final (file, at, second) in [
      ('0142-skillet-roasted-chicken-in-lemon-sauce.yaml', 8, 167747),
      ('0989-key-lime-pie.yaml', 1, 168156),
    ]) {
      final (db, path) = a.pathDb();
      final r = loadCorpusRecipe(file);
      final raw = nutritionLines(r)[at].raw;
      await d.editAndCompute(db, _fx, r);
      await applyMatchOverride(db, _fx, r, at, {'raw': raw, 'skipped': true});
      v28.dropFood(path, second);
      final down = v28.FoodFault(_fx, {second}, scope: FailureScope.food);
      await applyMatchOverride(db, down, r, at, {
        'raw': raw,
        'skipped': false,
      });
      final row = d.rowOf(db, r, at);
      expect(
        (row.status, row.hold, row.heldOn, row.parts),
        ('auto', 'food_unavailable', second, null),
        reason: file,
      );
    }
  });

  test('Y4 S7 (b): the parts loop takes a search-listed part as known — '
      'held_on names the failing kept-fat part 172345', () async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe(
      '0040-wilted-spinach-salad-with-warm-bacon-dressing.yaml',
    );
    await d.editAndCompute(
      db,
      _fx,
      loadCorpusRecipe(
        '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
      ),
    );
    await d.editAndCompute(db, _fx, r);
    // Not vacuous: 168322 is a stand-in, no detail.
    expect(db.fdcFoodCacheGet(168322), isNull);
    expect(knownFood(db, 168322), isNotNull);
    v28.dropFood(path, 172345);
    final fault = v28.FoodFault(_fx, {172345}, scope: FailureScope.food);
    for (var p = 1; p <= 3; p++) {
      await matchAndCompute(db, fault, r);
    }
    final held = d.rowOf(db, r, 5);
    expect(
      (held.fdcId, held.hold, held.heldOn),
      (168277, 'food_unavailable', 172345),
    );
    // Its arrival re-opens the recipe (held_on is the part that failed).
    await cachedFood(db, _fx, 172345);
    expect(nutritionIsFresh(db, r), isFalse);
  });
}
