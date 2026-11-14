// The v109 pins (fix109: dual-fleet review Run 087/088, union_W): W8 the
// pair row's second record on every withParts caller; W6 the negated-act
// bridge; W16 the span memo keyed on the sentence. Corpus-backed: the group
// skips without SALT_CORPUS_DIR, and every corpus read sits inside a test
// body (the loader never reads the corpus).
// ignore_for_file: lines_longer_than_80_chars
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'nutrition_v28_rule_a_test.dart' as v28;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

final _fx = FixtureProvider(pending: pendingSearches);

void main() {
  group('v109 (fix109: Run 087/088 union W)', skip: skipIfNoCorpus, () {
    w8();
    w6();
  });
}

/// W8 (S4 / O3, Opus critic 2): v108 V3 left two arms storing withParts'
/// partial `second_food` under a FRESH stamp with `held_on` null — a CONFIRM
/// while FDC answers "no such food" for the juice (a request per PUT and per
/// compute, never re-opened), and an UN-SKIP of a pair row with the juice
/// uncached (no fetch at all; its arrival re-opened nothing). v109: withParts
/// fetches the second record for every caller; "no such food" holds the row
/// `food_gone` ON the juice. 0536 Crispy Orange Beef line 3 ("10 (3-inch)
/// strips orange peel … plus ¼ cup juice (2 oranges)": peel 169103, juice
/// 169098), the fixtures' own figures (86.0 g, 603.92 kcal per serving — V3
/// (c)'s). STATED synthesized (negative paths, as V3's: no code evicts
/// fdc_food_cache): 169098 dropped from both caches and a fault on it.
void w8() {
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
    expect(db.nutritionFor(r.id)!.caloriesPerServing, closeTo(603.92, 0.005));
  }

  test('W8 (a): a CONFIRM while FDC answers "no such food" for the juice: 1 '
      'ask at the PUT, 0 over 4 computes, held food_gone ON the juice; its '
      'arrival re-opens it and the next compute derives the pair', () async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe(beef);
    await d.editAndCompute(db, _fx, r);
    v28.dropFood(path, juice);
    final gone = v28.FoodFault(_fx, {juice}, gone: true);
    final raw = nutritionLines(r)[3].raw;
    await applyMatchOverride(db, gone, r, 3, {'raw': raw, 'confirmed': true});
    expect(gone.asked, 1);
    // Held ON the juice by the PUT itself (no compute has run).
    expect(
      (d.rowOf(db, r, 3).hold, d.rowOf(db, r, 3).heldOn),
      ('food_gone', juice),
    );
    for (var p = 1; p <= 4; p++) {
      await matchAndCompute(db, gone, r);
    }
    // Base: 5 (one per compute — `second_food` is no no-record hold).
    expect(gone.asked, 1);
    await matchesBody(db, gone, r);
    expect(gone.asked, 1);
    final held = d.rowOf(db, r, 3);
    // Base: ('confirmed', 'second_food', null, null) — the partial.
    expect(
      (held.status, held.fdcId, held.hold, held.heldOn, held.parts),
      ('confirmed', peel, 'food_gone', juice, null),
    );
    // Fresh under a DERIVED hold (V3 (c)'s state): the whole line out of
    // the totals until the juice is had — the skipped line's 591.13 (O3's
    // figure); base 596.95, the partial counting the peel's 24 g alone.
    expect(held.derivedSeq, isNotNull);
    expect(nutritionIsFresh(db, r), isTrue);
    expect(db.nutritionFor(r.id)!.caloriesPerServing, closeTo(591.13, 0.005));
    // A second confirm is refused while held (the no-record action table:
    // pick or skip — V3 (c)'s `food_unavailable` reads the same).
    await expectLater(
      applyMatchOverride(db, gone, r, 3, {'raw': raw, 'confirmed': true}),
      throwsA(isA<ValidationException>()),
    );
    expect(gone.asked, 1);
    await cachedFood(db, _fx, juice);
    // Base: nothing re-opened (held_on null) — the recipe still fresh.
    expect(d.rowOf(db, r, 3).derivedSeq, isNull);
    expect(nutritionIsFresh(db, r), isFalse);
    await matchAndCompute(db, _fx, r);
    healed(db, r, 'confirmed');
  });

  test(
    "W8 (a') a CONFIRMED pair whose juice FDC later answers \"no such "
    'food" for: the COMPUTE holds it food_gone ON the juice at once',
    () async {
      final (db, path) = a.pathDb();
      final r = loadCorpusRecipe(beef);
      await d.editAndCompute(db, _fx, r);
      final raw = nutritionLines(r)[3].raw;
      await applyMatchOverride(db, _fx, r, 3, {'raw': raw, 'confirmed': true});
      v28.dropFood(path, juice);
      final gone = v28.FoodFault(_fx, {juice}, gone: true);
      // A recompute of the recipe (no reread: the confirm holds nothing).
      db.clearDerivedSeq(r.id, [3]);
      await matchAndCompute(db, gone, r);
      expect(gone.asked, 1);
      final held = d.rowOf(db, r, 3);
      // The decided arm's write carries the derived held_on (`withDerived`).
      expect((held.hold, held.heldOn), ('food_gone', juice));
      await matchAndCompute(db, gone, r);
      expect(gone.asked, 1);
    },
  );

  test('W8 (b): an UN-SKIP with the juice uncached and no fault FETCHES it — '
      'the pair derived at the PUT', () async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe(beef);
    await d.editAndCompute(db, _fx, r);
    final raw = nutritionLines(r)[3].raw;
    await applyMatchOverride(db, _fx, r, 3, {'raw': raw, 'skipped': true});
    v28.dropFood(path, juice);
    expect(db.fdcFoodCacheGet(juice), isNull);
    await applyMatchOverride(db, _fx, r, 3, {'raw': raw, 'skipped': false});
    // Base: no fetch — ('auto', 'second_food', null, …) fresh at 591.13.
    expect(db.fdcFoodCacheGet(juice), isNotNull);
    healed(db, r, 'auto');
  });

  test(
    'W8 (b) outage: the un-skip is held food_unavailable ON the juice, '
    'stale; its arrival re-opens it and a compute derives the pair',
    () async {
      final (db, path) = a.pathDb();
      final r = loadCorpusRecipe(beef);
      await d.editAndCompute(db, _fx, r);
      final raw = nutritionLines(r)[3].raw;
      await applyMatchOverride(db, _fx, r, 3, {'raw': raw, 'skipped': true});
      v28.dropFood(path, juice);
      final fault = v28.FoodFault(_fx, {juice}, scope: FailureScope.food);
      await applyMatchOverride(db, fault, r, 3, {'raw': raw, 'skipped': false});
      expect(fault.asked, 1);
      final held = d.rowOf(db, r, 3);
      // Base: ('auto', 'second_food', null) under a fresh stamp, 0 asks.
      expect(
        (held.status, held.hold, held.heldOn, held.grams),
        ('auto', 'food_unavailable', juice, null),
      );
      expect(nutritionIsFresh(db, r), isFalse);
      // Held, a compute re-reads it from the caches: no request.
      await matchAndCompute(db, fault, r);
      expect(fault.asked, 1);
      await cachedFood(db, _fx, juice);
      await matchAndCompute(db, fault, r);
      expect(fault.asked, 1);
      healed(db, r, 'auto');
    },
  );

  test('W8 (b) gone: an un-skip while FDC answers "no such food" is held '
      'food_gone ON the juice — 0 asks over 4 computes, its arrival reads the '
      'recipe stale', () async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe(beef);
    await d.editAndCompute(db, _fx, r);
    final raw = nutritionLines(r)[3].raw;
    await applyMatchOverride(db, _fx, r, 3, {'raw': raw, 'skipped': true});
    v28.dropFood(path, juice);
    final gone = v28.FoodFault(_fx, {juice}, gone: true);
    await applyMatchOverride(db, gone, r, 3, {'raw': raw, 'skipped': false});
    expect(gone.asked, 1);
    expect(d.rowOf(db, r, 3).heldOn, juice);
    for (var p = 1; p <= 4; p++) {
      await matchAndCompute(db, gone, r);
    }
    // The engine arm re-reads a no-record hold cache-only ([_rereadsHold];
    // it read `food_unavailable` alone: 5).
    expect(gone.asked, 1);
    final held = d.rowOf(db, r, 3);
    expect(
      (held.status, held.hold, held.heldOn),
      ('auto', 'food_gone', juice),
    );
    expect(nutritionIsFresh(db, r), isTrue);
    await cachedFood(db, _fx, juice);
    // The kept engine row's no-record hold, underived, reads stale
    // (`underivedSql`: it read `food_unavailable` alone — fresh).
    expect(nutritionIsFresh(db, r), isFalse);
    await matchAndCompute(db, gone, r);
    expect(gone.asked, 1);
    healed(db, r, 'auto');
  });

  // The owner gate's G4: the un-skip's TWO catches answer a GLOBAL failure
  // alike — its own decided food's ([decidedKeyRowFor]) and the pair's
  // second record's ([withParts]): the PUT throws the provider's failure
  // (the route's 422 `validation` with its message) and stores nothing.
  // STATED synthesized (as W8's: no code evicts fdc_food_cache): line 1's
  // soy sauce picked, both foods dropped, a GLOBAL fault on each.
  test('W8 (b) GLOBAL: an un-skip whose decided food or whose juice FDC '
      'fails GLOBALLY throws it — the row stays skipped, unchanged', () async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe(beef);
    await d.editAndCompute(db, _fx, r);
    String shape(IngredientMatchRow m) =>
        '${m.status}|${m.fdcId}|${m.grams}|${m.hold}|${m.heldOn}|'
        '${m.parts}|${m.derivedSeq}';
    for (final (at, food) in [(1, null), (3, juice)]) {
      final raw = nutritionLines(r)[at].raw;
      final dropped = food ?? d.rowOf(db, r, at).fdcId!;
      if (food == null) {
        await applyMatchOverride(db, _fx, r, at, {
          'raw': raw,
          'fdc_id': dropped,
        });
      }
      await applyMatchOverride(db, _fx, r, at, {'raw': raw, 'skipped': true});
      v28.dropFood(path, dropped);
      final before = shape(d.rowOf(db, r, at));
      final down = v28.FoodFault(_fx, {dropped});
      await expectLater(
        applyMatchOverride(db, down, r, at, {'raw': raw, 'skipped': false}),
        throwsA(
          isA<NutritionProviderException>()
              .having((e) => e.scope, 'scope', FailureScope.global)
              .having((e) => e.message, 'message', down.failWith),
        ),
        reason: 'line $at',
      );
      expect(down.asked, 1, reason: 'line $at');
      // Each catch's scope check deleted: that line's PUT completes (no
      // throw) — the gate's mutants.
      expect(shape(d.rowOf(db, r, at)), before, reason: 'line $at');
      expect(d.rowOf(db, r, at).status, 'skipped', reason: 'line $at');
    }
  });
}

Recipe _ed(Recipe r, String a, String b) => r.copyWith(
  steps: [
    for (final s in r.steps)
      s.text.contains(a) ? s.copyWith(text: s.text.replaceFirst(a, b)) : s,
  ],
);

/// W6 (O2 — a v108 regression vs v107; S2 carried since v106; S9 unpinned)
/// and W16 (Opus critic 2; the union's T2). STATED synthesized re-texts (as
/// T8's / v108 V6's: no corpus step holds these sentences — the corpus's one
/// negated act is 0492's "do not skim the fat from the liquid"): 0224
/// Braised Brisket's skim sentence replaced, and 0351 Sunday Gravy's step 4
/// with a sentence after the meatballs' lift-out (v108's harness).
void w6() {
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

  test('W6: the skim sentences — defatsSentence and braisedKeptOf on 0224', () {
    for (final (sentence, skims) in [
      // (a) a comma before a contrast word ends the bridge (v108: no skim —
      // the regression; v107: a skim).
      ('Do not skim the broth, only the fat.', true),
      ('Do not skim the liquid, just the fat.', true),
      ('Do not skim the broth, instead the fat.', true),
      // closer 1 D3: the two other contrast words of the ruled list.
      ('Do not skim the broth, rather the fat.', true),
      ('Do not skim the broth, but the fat.', true),
      ('Do not skim the foam, then skimmed fat from the surface.', true),
      // (b) the exclusion reads the verb's inflections (v108 and v107: no
      // skim — the bridge swallowed "skimmed").
      ('Do not skim the broth then skimmed fat from the surface.', true),
      // (c) a possessive or hyphenated bridge word (v108 and v107: a skim).
      ("Do not skim the soup's fat.", false),
      ('Do not skim the soup’s fat.', false),
      ('Do not skim the pan-juice fat.', false),
      // The list forms keep their v108 values (T8's).
      ('Remove the herbs (do not skim the juices, onions, and fat).', false),
      ('Remove the herbs (do not skim the liquid and fat).', false),
      ('Remove the herbs (do not skim the liquid or fat).', false),
      // The and/but clause-end arm (S9: no pin; deleted, both read a skim).
      ('Do not skim but then add the fat.', false),
      ('Do not skim and then stir in the fat.', false),
      // STATED, not widened (reach 0; each widening has cost a
      // regression): more than three bridge words, a quantity before the
      // object, a coordinated verb — each read as a skim.
      ('Do not skim the thin top layer of fat.', true),
      ('Do not skim 2 tablespoons of the fat.', true),
      ('Do not skim or pour off the fat.', true),
      // The owner gate's G2: a comma before "then" ends the bridge on its
      // own (v108: no skim; v107 and v109: a skim) — no inflected verb after.
      ('Do not skim the broth, then the fat.', true),
      // G1: the act's own inflected verb ends the bridge — here a skim after
      // a list comma is a real one (no exclusion: one span to "fat", none).
      ('Do not skim the foam, skim the fat.', true),
    ]) {
      expect(defatsSentence(sentence.toLowerCase()), skims, reason: sentence);
      expect(
        braisedKeptOf(flat(), 170827, braise(sentence)) != null,
        skims,
        reason: sentence,
      );
    }
  });

  test('W6: the pour-off sentences through shallowFryLinesOf on 0351', () {
    for (final (pour, lines) in [
      // 0351's own reading of a real pour-off is {20} (v108 V6's pin).
      ('Do not pour off the liquid, just the fat. ', {20}),
      ('Do not pour off the broth, only the fat. ', {20}),
      ("Do not pour off the pan's fat. ", <int>{}),
      ('Do not pour off the pan-juice fat. ', <int>{}),
      ('Do not pour off the juices and fat. ', <int>{}),
      // The owner gate's G2: "then" of the contrast list ends the bridge on
      // its own (v108: forbidden — {}; v107: a pour-off). Not "the liquid":
      // it switches the pan away (`_awayFromPan`), {20} either way.
      ('Do not pour off the broth, then the fat. ', {20}),
      // G1: the exclusion reads the act's own INFLECTED verb, its particle
      // included — an adjective or noun on the stem is a bridge word, so
      // each is forbidden as v107 and v108 read it (the gate tree: a real
      // pour-off, {20}).
      ('Do not pour off the drained fat. ', <int>{}),
      ('Do not pour off any drained grease. ', <int>{}),
      ('Do not drain off the spoonful of fat. ', <int>{}),
      ('Do not spoon off the poured fat. ', <int>{}),
      // G1: one row per act whose own inflected verb after a list comma
      // ends the bridge — a real act (no exclusion: the span reaches the
      // second verb's object and the act is forbidden).
      ('Do not pour off the broth, pour off fat. ', {20}),
      ('Do not wipe the pot, wipe the skillet. ', {20}),
      // A real discard of the oil makes the oil a discarded medium (no
      // shallow-fry line), and a real deglaze is a reuse refused before the
      // pour-off — each {}; forbidden, the pour-off after it reads {20}.
      (
        'Do not discard the butter, discard the oil. Pour off the fat. ',
        <int>{},
      ),
      ('Do not leave the broth, deglaze the pan. Pour off the fat. ', <int>{}),
      // The owner's delta gate: reuse's two-word verb keeps its PARTICLE in
      // the exclusion (`scrap\w* up`) — "scraped" alone is a bridge word, so
      // the deglaze is forbidden and the pour-off after it reads {20}
      // (`scrap\w*`: no span, a real deglaze — a reuse, {}; G1's shape).
      ('Do not deglaze the scraped skillet. Pour off the fat. ', {20}),
    ]) {
      expect(shallowFryLinesOf(gravy(pour)), lines, reason: pour);
    }
    // G1: the four sentences read no skim or pour-off fat either.
    for (final s in [
      'Do not pour off the drained fat.',
      'Do not pour off any drained grease.',
      'Do not drain off the spoonful of fat.',
      'Do not spoon off the poured fat.',
    ]) {
      expect(defatsSentence(s.toLowerCase()), isFalse, reason: s);
    }
  });

  // W16: the five-act shape (Opus critic 2's sentence, STATED synthesized: a
  // cost shape no corpus step reaches) — 0351 + 80 steps of ten DISTINCT
  // ~980-character sentences, each carrying five negated acts, through ONE
  // compute. The memo counted a sentence's length once per ACT, so the
  // 2 MiB clear came after ~0.5 M characters and every sentence was scanned
  // again: 7 scans per sentence (5,600) for 4 (3,200).
  test('W16 COST: five negated acts per sentence at 80 steps — one length '
      'per sentence, 3,200 scans in one compute', () async {
    String sentence(int n) {
      final b = StringBuffer(
        'Step $n: do not discard the oil, do not skim the fat, do not pour '
        'off the fat, do not wipe out the skillet, do not scrape up the '
        'browned bits',
      );
      while (b.length < 975) {
        b.write(' and stir well');
      }
      b.write('.');
      return b.toString();
    }

    Future<int> scans(Recipe r) async {
      final dir = Directory.systemTemp.createTempSync('salt-v109-');
      final db = SaltDatabase.open(
        ServerConfig(
          dataDir: dir.path,
          logLevel: Level.WARNING,
          trustProxy: false,
        ).dbPath,
      )..upsertSource(slug: 'atk-tv-2023', name: 'ATK', type: 'epub');
      addTearDown(() {
        db.dispose();
        dir.deleteSync(recursive: true);
      });
      db.upsertRecipe(
        r,
        sourceSlug: 'atk-tv-2023',
        contentHash: contentHashOf(r),
      );
      forbidsEvaluations = 0;
      await matchAndCompute(db, _fx, db.recipeByIdOrSlug(r.id)!.recipe);
      return forbidsEvaluations;
    }

    final base = loadCorpusRecipe(sundayGravy);
    expect(await scans(base), 0);
    final r = base.copyWith(
      steps: [
        ...base.steps,
        for (var i = 0; i < 80; i++)
          RecipeStep(
            number: base.steps.length + i + 1,
            text: [for (var j = 0; j < 10; j++) sentence(i * 10 + j)].join(' '),
          ),
      ],
    );
    // Base: 5,600 (the length counted per act: the memo cleared mid-way).
    expect(await scans(r), 3200);
  });
}
