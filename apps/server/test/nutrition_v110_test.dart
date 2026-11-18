// The v110 pins (fix110: dual-fleet review Run 089/090, union_X): X4 the
// negated-act bridge word holds a word character; X2 the pair row's second
// record is its DETAIL; X3 `held_on` served. Corpus-backed: the group skips
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

void main() {
  group('v110 (fix110: Run 089/090 union X)', skip: skipIfNoCorpus, () {
    x4();
    x2();
    x3();
  });
}

Recipe _ed(Recipe r, String a, String b) => r.copyWith(
  steps: [
    for (final s in r.steps)
      s.text.contains(a) ? s.copyWith(text: s.text.replaceFirst(a, b)) : s,
  ],
);

/// X4 (the Sonnet step-reader's killed claim, revived by the union's
/// three-version table): v109 W6 (c)'s bridge word `[\w'’-]+` admitted a
/// PUNCTUATION-ONLY token, so "Do not skim the foam - just fat." read a
/// NEGATED skim at v109 and a real skim at v107 and v108. v110: a bridge word
/// must hold a word character — those rows read v107 = v108 again. STATED
/// synthesized re-texts (v109 W6's harness: no corpus step holds these
/// sentences — the corpus scan's 24,173 sentences hold no punctuation-only
/// token): 0224 Braised Brisket's skim sentence replaced, and 0351 Sunday
/// Gravy's step 4 with a sentence after the meatballs' lift-out.
void x4() {
  const brisket =
      '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml';
  const sundayGravy =
      '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml';
  Recipe braise(String sentence) => _ed(
    _ed(
      loadCorpusRecipe(brisket),
      'Using wide, shallow spoon, skim fat from surface and discard.',
      sentence,
    ),
    'return defatted liquid to pan',
    'return liquid to pan',
  );
  String flat() => nutritionLines(loadCorpusRecipe(brisket))[0].raw;
  Recipe gravy(String pour) {
    final g = loadCorpusRecipe(sundayGravy);
    const lift =
        'Transfer the meatballs to a paper towel–lined plate to drain briefly. ';
    const garlic =
        'Stir in the garlic and cook until fragrant, about 30 seconds. ';
    final s3 = g.steps[3].text;
    expect(s3, contains(lift));
    return g.copyWith(
      steps: [
        for (final (i, st) in g.steps.indexed)
          i == 3
              ? st.copyWith(text: s3.replaceFirst(lift, '$lift$pour$garlic'))
              : st,
      ],
    );
  }

  test('X4: a dash-only token is no bridge word — the skim rows through '
      'defatsSentence and braisedKeptOf on 0224', () {
    for (final (sentence, skims) in [
      // v109: no skim (the dash bridged "foam" to "fat"); v107 = v108 = v110.
      ('Do not skim the foam - just fat.', true),
      ('Do not skim the foam -- just fat.', true),
      ('Do not skim the foam -- only fat.', true),
      ("Do not skim the foam ' just fat.", true),
      ('Do not skim the foam ’ just fat.', true),
      // Controls that must NOT move (v109 W6 (c)'s in-word apostrophe and
      // hyphen, and v108's four-word limit).
      ("Do not skim the soup's fat.", false),
      ('Do not skim the pan-juice fat.', false),
      // The owner gate (o4n): the word character may sit anywhere in the
      // bridge word — a lookahead narrowed to a LEADING one (`(?=\w)`)
      // read this a real skim.
      ("Do not skim the 'nduja fat.", false),
      ('Do not skim the foam - just the fat.', true),
    ]) {
      expect(defatsSentence(sentence.toLowerCase()), skims, reason: sentence);
      expect(
        braisedKeptOf(flat(), 170827, braise(sentence)) != null,
        skims,
        reason: sentence,
      );
    }
  });

  test('X4: the pour-off and reuse rows through shallowFryLinesOf on 0351', () {
    for (final (pour, lines) in [
      // 0351's own reading of a real pour-off is {20} (v108 V6's pin);
      // v109: forbidden — {}.
      ('Do not pour off the broth - just fat. ', {20}),
      ('Do not pour off the broth -- only fat. ', {20}),
      // A real reserve of the fat is a reuse, refused before the pour-off
      // ({}); v109 read it forbidden, the pour-off after it {20}.
      ('Do not reserve the broth - just fat. Pour off the fat. ', <int>{}),
      // Controls (v109 W6's): forbidden at v109 and v110.
      ("Do not pour off the pan's fat. ", <int>{}),
      ('Do not pour off the pan-juice fat. ', <int>{}),
    ]) {
      expect(shallowFryLinesOf(gravy(pour)), lines, reason: pour);
    }
  });

  test('X4: the discard and wipe acts — a dash-only token is no bridge word '
      'there either', () {
    // The owner gate: the lookahead dropped for the discard act alone, or
    // the wipe act alone, survived every row above — and the hand-edit
    // verifier refuted "equivalent". Their readers take a real act as verb
    // + object, contiguous, so the bridge decides only where a span reaches
    // a SECOND verb of the act; the exclusion reads a bridge word's START,
    // so an act verb after an in-word hyphen ("re-discard") sits inside a
    // bridge word (STATED limit, reach 0). With the dash a bridge word
    // (v109) the span reaches it and forbids the real act; v110: the span
    // ends at the dash. STATED synthesized sentences (no corpus step).
    final pom = loadCorpusRecipe(brisket);
    final first = pom.steps.first.text;
    bool fries(String s) => friesForTest(_ed(pom, first, '$s $first'));
    expect(friesForTest(pom), isFalse);
    expect(fries('Do not discard the oil.'), isFalse);
    expect(fries('Do not discard - re-discard oil.'), isTrue);

    final fish = loadCorpusRecipe(
      '0466-fish-meuniere-with-browned-butter-and-lemon.yaml',
    );
    const wipeAt = 'Wipe out the skillet and repeat';
    Set<int> wiped(String s) => panFatLinesOf(_ed(fish, wipeAt, '$s Repeat'));
    expect(panFatLinesOf(fish), {3, 4});
    expect(wiped('Do not wipe out the skillet.'), isEmpty);
    expect(wiped('Do not wipe - re-wipe skillet.'), {3, 4});
  });
}

/// Counts every detail ask of [inner].
final class _Asks implements NutritionProvider {
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

/// Deletes [id]'s DETAIL alone (fdc_food_cache); the search answers that
/// list it stay.
void _dropDetail(String path, int id) {
  sqlite3.open(path)
    ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [id])
    ..dispose();
}

/// X2 (S2 / O3, unionX/c): withParts fetched a pair's second record only
/// when [knownFood] answered null — and [knownFood] also answers a cached
/// SEARCH hit (no portions): with the juice's detail uncached but an answer
/// listing it, no fetch was made and 0536 line 3 stored the partial
/// `second_food` (24 g of 86 g) under a fresh stamp. And a row held
/// `food_gone` ON the juice was re-opened by a search answer listing it,
/// then stored the partial with a STALE `held_on`. v110: the second record
/// is its DETAIL — read by withParts' gate and `_heldOnOf`'s arm alike.
/// 0536 Crispy Orange Beef line 3 (peel 169103, juice 169098), the
/// fixtures' figures (86.0 g, 603.92 kcal per serving — v109 W8's). STATED
/// synthesized cache states (as W8's: no code evicts fdc_food_cache): the
/// juice's detail dropped while a search answer listing it ("orange juice",
/// the fixtures' own answer) is cached.
void x2() {
  const beef = '0536-crispy-orange-beef.yaml';
  const peel = 169103;
  const juice = 169098;

  void healed(SaltDatabase db, Recipe r, String status) {
    final row = d.rowOf(db, r, 3);
    expect(
      (row.status, row.hold, row.heldOn, row.grams),
      (status, null, null, 86.0),
    );
    expect([for (final p in partsOf(row.parts)) p.fdcId], [peel, juice]);
    expect(nutritionIsFresh(db, r), isTrue);
    // RE-PIN (M105 batch, v118): crispy-orange-beef|11 "2 tablespoons grated fresh ginger" on 169231 at the record's tsp 2.0 g, 15.97 → 12.00 g (−3.18 kcal ÷ 4 servings): 603.92 → 603.13.
    expect(db.nutritionFor(r.id)!.caloriesPerServing, closeTo(603.13, 0.005));
  }

  /// 0536 computed, then the juice's detail dropped with an answer listing
  /// it cached: the stand-in alone.
  Future<(SaltDatabase, String, Recipe)> standIn() async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe(beef);
    await d.editAndCompute(db, _fx, r);
    await searchCandidates(db, _fx, 'orange juice');
    _dropDetail(path, juice);
    // Not vacuous: no detail, a stand-in.
    expect(db.fdcFoodCacheGet(juice), isNull);
    expect(knownFood(db, juice), isNotNull);
    return (db, path, r);
  }

  test('X2 (a): the stand-in alone — a compute asks ONCE and derives the '
      'pair; the matches GET keeps the row as stored, 0 asks', () async {
    final (db, _, r) = await standIn();
    final stored = d.rowOf(db, r, 3);
    final serve = _Asks(_fx);
    await matchesBody(db, serve, r);
    expect(serve.asked, isEmpty);
    final after = d.rowOf(db, r, 3);
    expect(
      (after.grams, after.parts, after.hold, after.derivedSeq),
      (stored.grams, stored.parts, stored.hold, stored.derivedSeq),
    );
    db.clearDerivedSeq(r.id, [3]);
    await matchAndCompute(db, serve, r);
    // Base: 0 asks, ('auto', 'second_food', null, 24.0) fresh at 596.95.
    expect(serve.asked, [juice]);
    healed(db, r, 'auto');
  });

  test('X2 (a) outage: the stand-in never counts the juice — a compute '
      'keeps the stored row, stale, one ask per pass, and holds it '
      'food_unavailable ON the juice at the third; a confirm keeps its row '
      'stale and an un-skip is held ON the juice at the PUT; the arrival '
      're-opens each and a compute derives the pair', () async {
    final (db, _, r) = await standIn();
    final fault = v28.FoodFault(_fx, {juice}, scope: FailureScope.food);
    db.clearDerivedSeq(r.id, [3]);
    for (var p = 1; p <= foodUnavailableAfter; p++) {
      await matchAndCompute(db, fault, r);
      // Base: 0 asks — the stand-in's partial ('auto', 'second_food',
      // null, 24.0) under a fresh stamp.
      expect(fault.asked, p);
      expect(nutritionIsFresh(db, r), p == foodUnavailableAfter);
    }
    final held = d.rowOf(db, r, 3);
    // `_heldOnOf`'s arm reads the DETAIL (with the stand-in, the old read
    // answered it: held_on null, nothing re-opens at the arrival). Held:
    // the line out of the totals (the skipped line's 591.13).
    expect(
      (held.status, held.hold, held.heldOn, held.grams),
      ('auto', 'food_unavailable', juice, null),
    );
    // RE-PIN (M105 batch, v118): crispy-orange-beef|11 "2 tablespoons grated fresh ginger" on 169231 at the record's tsp 2.0 g, 15.97 → 12.00 g (−3.18 kcal ÷ 4 servings): 591.13 → 590.33.
    expect(db.nutritionFor(r.id)!.caloriesPerServing, closeTo(590.33, 0.005));
    await matchAndCompute(db, fault, r);
    expect(fault.asked, foodUnavailableAfter);
    await cachedFood(db, _fx, juice);
    expect(nutritionIsFresh(db, r), isFalse);
    await matchAndCompute(db, fault, r);
    healed(db, r, 'auto');

    final raw = nutritionLines(r)[3].raw;
    for (final (body, status, hold, heldOn) in [
      // The decided arm's outage (v36): the row kept as stored — never
      // the partial — underived until held.
      ({'raw': raw, 'confirmed': true}, 'confirmed', null, null),
      ({'raw': raw, 'skipped': false}, 'auto', foodUnavailableHold, juice),
    ]) {
      final (db2, path2, r2) = await standIn();
      if (body['skipped'] == false) {
        await applyMatchOverride(db2, _fx, r2, 3, {
          'raw': raw,
          'skipped': true,
        });
        await cachedFood(db2, _fx, juice);
        _dropDetail(path2, juice);
        expect(knownFood(db2, juice), isNotNull);
      }
      final down = v28.FoodFault(_fx, {juice}, scope: FailureScope.food);
      await applyMatchOverride(db2, down, r2, 3, body);
      // Base: 0 asks, the partial `second_food` (24 g), held_on null, fresh.
      expect(down.asked, 1, reason: '$body');
      final row = d.rowOf(db2, r2, 3);
      expect(
        (row.status, row.hold, row.heldOn, row.grams != 24.0),
        (status, hold, heldOn, true),
        reason: '$body',
      );
      expect(nutritionIsFresh(db2, r2), isFalse, reason: '$body');
      await cachedFood(db2, _fx, juice);
      await matchAndCompute(db2, down, r2);
      expect(down.asked, 1, reason: '$body');
      healed(db2, r2, status);
    }
  });

  test('X2 (a): a CONFIRM and an UN-SKIP alike fetch the detail — one ask '
      'each, the pair derived at the PUT', () async {
    final (db, _, r) = await standIn();
    final raw = nutritionLines(r)[3].raw;
    final serve = _Asks(_fx);
    await applyMatchOverride(db, serve, r, 3, {'raw': raw, 'confirmed': true});
    // Base: 0 asks, ('confirmed', 'second_food', …) at 596.95.
    expect(serve.asked, [juice]);
    await matchAndCompute(db, serve, r);
    healed(db, r, 'confirmed');

    final (db2, path2, r2) = await standIn();
    await applyMatchOverride(db2, _fx, r2, 3, {'raw': raw, 'skipped': true});
    await cachedFood(db2, _fx, juice);
    _dropDetail(path2, juice);
    expect(knownFood(db2, juice), isNotNull);
    final serve2 = _Asks(_fx);
    await applyMatchOverride(db2, serve2, r2, 3, {
      'raw': raw,
      'skipped': false,
    });
    // Base: 0 asks — the stand-in's partial.
    expect(serve2.asked, [juice]);
    healed(db2, r2, 'auto');
  });

  test("X2 (b) O3's chain: food_gone ON the juice, re-opened by a search "
      'answer listing it — the compute re-reads it cache-only and holds it food_gone '
      'again; a second confirm is refused; the detail heals it', () async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe(beef);
    await d.editAndCompute(db, _fx, r);
    v28.dropFood(path, juice);
    final gone = v28.FoodFault(_fx, {juice}, gone: true);
    final raw = nutritionLines(r)[3].raw;
    await applyMatchOverride(db, gone, r, 3, {'raw': raw, 'confirmed': true});
    expect(gone.asked, 1);
    expect(
      (d.rowOf(db, r, 3).hold, d.rowOf(db, r, 3).heldOn),
      ('food_gone', juice),
    );
    await searchCandidates(db, gone, 'orange juice');
    expect(knownFood(db, juice), isNotNull);
    expect(nutritionIsFresh(db, r), isFalse);
    await matchAndCompute(db, gone, r);
    // The held row is re-read from the caches (`_rereadsHold`): no ask —
    // and the stand-in is no record of the juice. Base: no ask either, but
    // ('confirmed', 'second_food', held_on 169098 STALE) — the partial.
    expect(gone.asked, 1);
    final held = d.rowOf(db, r, 3);
    expect(
      (held.status, held.fdcId, held.hold, held.heldOn, held.parts),
      ('confirmed', peel, 'food_gone', juice, null),
    );
    expect(nutritionIsFresh(db, r), isTrue);
    // RE-PIN (M105 batch, v118): crispy-orange-beef|11 "2 tablespoons grated fresh ginger" on 169231 at the record's tsp 2.0 g, 15.97 → 12.00 g (−3.18 kcal ÷ 4 servings): 591.13 → 590.33.
    expect(db.nutritionFor(r.id)!.caloriesPerServing, closeTo(590.33, 0.005));
    await matchAndCompute(db, gone, r);
    expect(gone.asked, 1);
    // Base: accepted.
    await expectLater(
      applyMatchOverride(db, gone, r, 3, {'raw': raw, 'confirmed': true}),
      throwsA(isA<ValidationException>()),
    );
    await cachedFood(db, _fx, juice);
    expect(nutritionIsFresh(db, r), isFalse);
    await matchAndCompute(db, gone, r);
    healed(db, r, 'confirmed');
  });

  test('X2 (a) gone: the juice gone at FDC with a search answer listing it '
      'cached — a confirm and a compute alike hold food_gone ON the juice; '
      'the stand-in never supplies the second record', () async {
    final raw = nutritionLines(loadCorpusRecipe(beef))[3].raw;
    for (final confirm in [true, false]) {
      final (db, _, r) = await standIn();
      final gone = v28.FoodFault(_fx, {juice}, gone: true);
      if (confirm) {
        await applyMatchOverride(db, gone, r, 3, {
          'raw': raw,
          'confirmed': true,
        });
      } else {
        db.clearDerivedSeq(r.id, [3]);
        await matchAndCompute(db, gone, r);
      }
      // verify1 D1: a gone arm gated on the stand-in (`detail == null &&
      // knownFood(…) == null`) stored the base's partial here — measured
      // on the confirm: ('confirmed', 169103, 'second_food', null, null).
      expect(gone.asked, 1, reason: '$confirm');
      final row = d.rowOf(db, r, 3);
      expect(
        (row.status, row.fdcId, row.hold, row.heldOn, row.parts),
        (confirm ? 'confirmed' : 'auto', peel, 'food_gone', juice, null),
        reason: '$confirm',
      );
      // Measured on the tip: fresh after the confirm's PUT, stale after
      // the compute (both at the skipped line's 591.13).
      expect(nutritionIsFresh(db, r), confirm, reason: '$confirm');
      expect(
        db.nutritionFor(r.id)!.caloriesPerServing,
        // RE-PIN (M105 batch, v118): crispy-orange-beef|11 "2 tablespoons grated fresh ginger" on 169231 at the record's tsp 2.0 g, 15.97 → 12.00 g (−3.18 kcal ÷ 4 servings): 591.13 → 590.33.
        closeTo(590.33, 0.005),
        reason: '$confirm',
      );
    }
  });

  test('X2 (c): the other four pair rows keep their stored values on the '
      'same drop (each juice on a density entry)', () async {
    for (final (file, at, second) in [
      ('0142-skillet-roasted-chicken-in-lemon-sauce.yaml', 8, 167747),
      ('0860-lemon-bundt-cake.yaml', 2, 167747),
      ('0861-lemon-pound-cake.yaml', 5, 167747),
      ('0989-key-lime-pie.yaml', 1, 168156),
    ]) {
      final (db, path) = a.pathDb();
      final r = loadCorpusRecipe(file);
      await d.editAndCompute(db, _fx, r);
      final stored = d.rowOf(db, r, at);
      expect(partsOf(stored.parts).length, 2, reason: file);
      final kcal = db.nutritionFor(r.id)!.caloriesPerServing;
      _dropDetail(path, second);
      db.clearDerivedSeq(r.id, [at]);
      await matchAndCompute(db, _fx, r);
      final row = d.rowOf(db, r, at);
      expect(
        (row.status, row.grams, row.parts, row.hold, row.heldOn),
        (stored.status, stored.grams, stored.parts, null, null),
        reason: file,
      );
      expect(db.nutritionFor(r.id)!.caloriesPerServing, kcal, reason: file);
      // The owner gate (o2a): the gone arm is every pair's, a density
      // juice's too (narrowed to the orange juice it survived every pin) —
      // the detail dropped again and FDC answering "no such food".
      _dropDetail(path, second);
      db.clearDerivedSeq(r.id, [at]);
      final gone = v28.FoodFault(_fx, {second}, gone: true);
      await matchAndCompute(db, gone, r);
      final held = d.rowOf(db, r, at);
      expect(
        (gone.asked, held.hold, held.heldOn, held.parts),
        (1, 'food_gone', second, null),
        reason: file,
      );
    }
  });
}

/// X3 (O4; Opus critic 3, unionX/c C4 C5): a pair row held `food_gone` ON
/// its JUICE was shown as "USDA no longer serves this food" against the
/// PEEL — `held_on` was served nowhere; and two confirms are refused there,
/// each naming "this food". v110: the matches body serves `held_on` when
/// the hold waits on another record than the row's food, and both 422s say
/// "this line's second food". 0536 line 3 (as X2); line 1 (soy sauce) the
/// own-record control. STATED synthesized cache states (W8's).
void x3() {
  const beef = '0536-crispy-orange-beef.yaml';
  const juice = 169098;
  const second =
      "USDA has no record of this line's second food to count — pick "
      'another food or skip the line.';

  Future<Map<String, Object?>> matchOf(
    SaltDatabase db,
    NutritionProvider provider,
    Recipe r,
    int at,
  ) async {
    final body = await matchesBody(db, provider, r);
    final item = (body['items']! as List)[at] as Map<String, Object?>;
    return item['match']! as Map<String, Object?>;
  }

  test('X3: held ON the juice — the body serves held_on and both refusals '
      "name the line's second food; an unheld row and an own-record hold "
      'carry no held_on and keep "this food"', () async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe(beef);
    await d.editAndCompute(db, _fx, r);
    // Unheld: no key (no existing body changes).
    expect((await matchOf(db, _fx, r, 3)).containsKey('held_on'), isFalse);
    v28.dropFood(path, juice);
    final gone = v28.FoodFault(_fx, {juice}, gone: true);
    final raw = nutritionLines(r)[3].raw;
    // (b) of the record: a confirm + apply_to_all on the UNHELD pair row
    // whose derivation ends held ON the juice (Opus critic 3's GAP 1).
    await expectLater(
      applyMatchOverride(db, gone, r, 3, {
        'raw': raw,
        'confirmed': true,
        'apply_to_all': true,
      }),
      throwsA(
        isA<ValidationException>().having((e) => e.message, 'message', second),
      ),
    );
    await applyMatchOverride(db, gone, r, 3, {'raw': raw, 'confirmed': true});
    final match = await matchOf(db, gone, r, 3);
    // Base: no key — the app named the peel.
    expect((match['hold'], match['held_on']), ('food_gone', juice));
    // (a): a confirm on the stored held row.
    await expectLater(
      applyMatchOverride(db, gone, r, 3, {'raw': raw, 'confirmed': true}),
      throwsA(
        isA<ValidationException>().having((e) => e.message, 'message', second),
      ),
    );

    // The own-record control: line 1's food gone, held on itself.
    final own = d.rowOf(db, r, 1).fdcId!;
    v28.dropFood(path, own);
    final ownGone = v28.FoodFault(_fx, {own}, gone: true);
    final raw1 = nutritionLines(r)[1].raw;
    await applyMatchOverride(db, ownGone, r, 1, {
      'raw': raw1,
      'confirmed': true,
    });
    final match1 = await matchOf(db, ownGone, r, 1);
    expect(match1['hold'], 'food_gone');
    expect(match1.containsKey('held_on'), isFalse);
    await expectLater(
      applyMatchOverride(db, ownGone, r, 1, {'raw': raw1, 'confirmed': true}),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.message,
          'message',
          noRecordMessage,
        ),
      ),
    );

    // The owner gate (o3a, o3b): the OUTAGE hold too — the body key and
    // the refusal narrowed to `food_gone` survived every pin. An un-skip
    // with the juice uncached under an outage is held `food_unavailable`
    // ON the juice at the PUT (v109 W8).
    final (db2, path2) = a.pathDb();
    final r2 = loadCorpusRecipe(beef);
    await d.editAndCompute(db2, _fx, r2);
    await applyMatchOverride(db2, _fx, r2, 3, {'raw': raw, 'skipped': true});
    v28.dropFood(path2, juice);
    final down = v28.FoodFault(_fx, {juice}, scope: FailureScope.food);
    await applyMatchOverride(db2, down, r2, 3, {'raw': raw, 'skipped': false});
    final match2 = await matchOf(db2, down, r2, 3);
    expect((match2['hold'], match2['held_on']), ('food_unavailable', juice));
    await expectLater(
      applyMatchOverride(db2, down, r2, 3, {'raw': raw, 'confirmed': true}),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.message,
          'message',
          "USDA could not serve this line's second food — pick another food "
              'or skip the line.',
        ),
      ),
    );
  });
}
