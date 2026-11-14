// The v108 pins (fix108: dual-fleet review Run 085/086, union_V): V3 the
// pair fetch reads withParts' predicate; V6 the negation verdict by match
// span. Corpus-backed: the group skips without SALT_CORPUS_DIR, and every
// corpus read sits inside a test body (the loader never reads the corpus);
// the last test (the span memo's clear) reads no corpus and always runs.
// ignore_for_file: lines_longer_than_80_chars
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'nutrition_v28_rule_a_test.dart' as v28;
import 'support/corpus.dart';
import 'support/cost_bounds.dart' show backstopMs;
import 'support/fdc_fixtures.dart';

final _fx = FixtureProvider(pending: pendingSearches);

void main() {
  group('v108 (fix108: Run 085/086 union V)', skip: skipIfNoCorpus, () {
    v3();
    v6();
  });

  // The owner gate's pin (no corpus read: CI runs it). STATED synthesized
  // (a cost shape no corpus step reaches: the corpus's one negated act is
  // 0492's): the span memo is process-wide, so its only bound is the clear
  // past 2 MiB of keyed text — unpinned, a mutant raising the cap survived.
  test('V6: the span memo is cleared past 2 MiB of keyed text — a sentence '
      'seen before the clear is scanned again, one inside it is not', () {
    String s(int n) => 'do not skim the fat $n ${'x' * 1000}';
    forbidsEvaluations = 0;
    expect(defatsSentence(s(0)), isFalse);
    defatsSentence(s(0));
    // The repeat is a memo hit.
    expect(forbidsEvaluations, 1);
    // 2,200 distinct ~1,020-character sentences: 2.2 MiB of keys.
    for (var i = 1; i <= 2200; i++) {
      defatsSentence(s(i));
    }
    expect(forbidsEvaluations, 2201);
    // Kept since the ONE clear (at s(2047): the count restarts there — a
    // mutant clearing without the restart clears on every later miss and
    // scans both again: 2,203) …
    defatsSentence(s(2100));
    defatsSentence(s(2200));
    expect(forbidsEvaluations, 2201);
    // … and dropped by it (a mutant never clearing: 2,201).
    defatsSentence(s(0));
    expect(forbidsEvaluations, 2202);
  });
}

/// V3 (MED; S5 S6 / O4 O5): v107 U4's pair fetch in derivedFor ran for a
/// PICK too (a row withParts never splits): a pick of the peel during a
/// juice outage was stored underived, then held out of the totals; "no such
/// food" cost a request per compute; and a confirm on a row storing no
/// parts held with held_on null (the juice's arrival never re-opened it).
/// 0536 Crispy Orange Beef line 3 ("10 (3-inch) strips orange peel … plus
/// ¼ cup juice (2 oranges)": peel 169103, juice 169098), the fixtures' own
/// figures. STATED synthesized (negative path, as T7's U4 pin: no code
/// evicts fdc_food_cache): 169098 dropped from both caches and a fault on
/// it.
void v3() {
  const beef = '0536-crispy-orange-beef.yaml';
  const peel = 169103;
  const juice = 169098;

  test('V3 (a): a PICK of the peel during a juice FOOD outage is derived at '
      'the PUT, 0 juice requests, and stays so over 3 computes', () async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe(beef);
    await d.editAndCompute(db, _fx, r);
    v28.dropFood(path, juice);
    final fault = v28.FoodFault(_fx, {juice}, scope: FailureScope.food);
    for (var p = 1; p <= 3; p++) {
      await matchAndCompute(db, fault, r);
    }
    // The engine row held on the juice (T7's undecided control).
    expect(d.rowOf(db, r, 3).hold, 'food_unavailable');
    final before = fault.asked;
    await applyMatchOverride(db, fault, r, 3, {
      'raw': nutritionLines(r)[3].raw,
      'fdc_id': peel,
    });
    void derived() {
      final row = d.rowOf(db, r, 3);
      // Base: grams null, underived, stale; then held food_unavailable.
      expect(
        (row.status, row.fdcId, row.hold, row.parts, row.derivedSeq != null),
        ('overridden', peel, null, null, true),
      );
      expect(row.grams, closeTo(24.0, 0.005));
      expect(nutritionIsFresh(db, r), isTrue);
      expect(db.nutritionFor(r.id)!.caloriesPerServing, closeTo(596.95, 0.005));
      // Base: one request at the PUT and one per compute.
      expect(fault.asked, before);
    }

    derived();
    for (var p = 1; p <= 3; p++) {
      await matchAndCompute(db, fault, r);
    }
    derived();
  });

  test('V3 (b): FDC answering "no such food" for the juice: a pick of the '
      'peel asks for it 0 times over the PUT and 4 computes', () async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe(beef);
    await d.editAndCompute(db, _fx, r);
    v28.dropFood(path, juice);
    final gone = v28.FoodFault(_fx, {juice}, gone: true);
    await applyMatchOverride(db, gone, r, 3, {
      'raw': nutritionLines(r)[3].raw,
      'fdc_id': peel,
    });
    for (var p = 1; p <= 4; p++) {
      await matchAndCompute(db, gone, r);
    }
    // Base: 5 (the PUT + one per compute — no negative cache).
    expect(gone.asked, 0);
    final row = d.rowOf(db, r, 3);
    expect((row.status, row.hold), ('overridden', null));
    expect(row.grams, closeTo(24.0, 0.005));
  });

  test('V3 (c): a CONFIRM of a row storing NO parts during the outage holds '
      'food_unavailable ON THE JUICE; its arrival re-opens it and the next '
      'compute derives the pair', () async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe(beef);
    await d.editAndCompute(db, _fx, r);
    // A pick of the peel first (one record, no parts), then the outage.
    await applyMatchOverride(db, _fx, r, 3, {
      'raw': nutritionLines(r)[3].raw,
      'fdc_id': peel,
    });
    expect(d.rowOf(db, r, 3).parts, isNull);
    v28.dropFood(path, juice);
    final fault = v28.FoodFault(_fx, {juice}, scope: FailureScope.food);
    await applyMatchOverride(db, fault, r, 3, {
      'raw': nutritionLines(r)[3].raw,
      'confirmed': true,
    });
    for (var p = 1; p <= 3; p++) {
      await matchAndCompute(db, fault, r);
    }
    final held = d.rowOf(db, r, 3);
    // Base: held_on null (the stored row carries no parts).
    expect(
      (held.status, held.hold, held.heldOn, held.parts),
      ('confirmed', 'food_unavailable', juice, null),
    );
    expect(nutritionIsFresh(db, r), isTrue);
    await cachedFood(db, _fx, juice);
    // Base: unholdOn a no-op — derived_seq kept, the recipe fresh.
    expect(d.rowOf(db, r, 3).derivedSeq, isNull);
    expect(nutritionIsFresh(db, r), isFalse);
    await matchAndCompute(db, _fx, r);
    final healed = d.rowOf(db, r, 3);
    expect(
      (healed.status, healed.hold, healed.heldOn, healed.grams),
      ('confirmed', null, null, 86.0),
    );
    expect([for (final p in partsOf(healed.parts)) p.fdcId], [peel, juice]);
    expect(db.nutritionFor(r.id)!.caloriesPerServing, closeTo(603.92, 0.005));
  });

  // The owner gate's pin: the mutant dropping the own-record test of
  // `_heldOnOf`'s rule arm survived (c) — there the peel is cached.
  test("V3 (e): the row's OWN record uncached too — the hold names NO part "
      '(the failure was its own fetch; the juice was never asked): held_on '
      'null, and the juice arriving first re-opens nothing', () async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe(beef);
    await d.editAndCompute(db, _fx, r);
    await applyMatchOverride(db, _fx, r, 3, {
      'raw': nutritionLines(r)[3].raw,
      'fdc_id': peel,
    });
    expect(d.rowOf(db, r, 3).parts, isNull);
    v28.dropFood(path, juice);
    v28.dropFood(path, peel);
    final fault = v28.FoodFault(_fx, {peel, juice}, scope: FailureScope.food);
    await applyMatchOverride(db, fault, r, 3, {
      'raw': nutritionLines(r)[3].raw,
      'confirmed': true,
    });
    for (var p = 1; p <= 3; p++) {
      await matchAndCompute(db, fault, r);
    }
    final held = d.rowOf(db, r, 3);
    // The mutant: held_on 169098.
    expect(
      (held.status, held.fdcId, held.hold, held.heldOn, held.parts),
      ('confirmed', peel, 'food_unavailable', null, null),
    );
    final stamp = held.derivedSeq;
    expect(stamp, isNotNull);
    expect(nutritionIsFresh(db, r), isTrue);
    await cachedFood(db, _fx, juice);
    // The juice alone cannot derive the row: nothing re-opened.
    expect(d.rowOf(db, r, 3).derivedSeq, stamp);
    expect(nutritionIsFresh(db, r), isTrue);
  });
}

Recipe _ed(Recipe r, String a, String b) => r.copyWith(
  steps: [
    for (final s in r.steps)
      s.text.contains(a) ? s.copyWith(text: s.text.replaceFirst(a, b)) : s,
  ],
);

/// V6 (LOW; S4 S9 S10 / O3 O6): v107 judged each act match by the CLAUSE
/// holding its verb — an object borrowed from a forbidding clause read as a
/// real skim (a regression vs v106), a coordinated object split by the cut
/// read as real (narrower than v105), the 3-word bridge swallowed a second
/// verb, and every reader built its own guard. v108: the verdict by MATCH
/// SPAN, found once per (sentence, act). STATED synthesized re-texts (as
/// T7's: no corpus step holds these sentences — the corpus's one negated
/// act is 0492's "do not skim the fat from the liquid"): 0224 Braised
/// Brisket's skim sentence replaced, and 0351 Sunday Gravy's step 4 with a
/// sentence after the meatballs' lift-out.
void v6() {
  const brisket =
      '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml';
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
    final g = loadCorpusRecipe(
      '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml',
    );
    const lift =
        'Transfer the meatballs to a paper towel–lined plate to drain briefly. ';
    const garlic =
        'Stir in the garlic and cook until fragrant, about 30 seconds. ';
    final s3 = g.steps[3].text;
    expect(s3, contains(lift));
    // T7's `_gravy` verbatim (the pour, then a cooking sentence).
    return g.copyWith(
      steps: [
        for (final (i, st) in g.steps.indexed)
          i == 3
              ? st.copyWith(text: s3.replaceFirst(lift, '$lift$pour$garlic'))
              : st,
      ],
    );
  }

  test('V6: the skim sentences in both directions — defatsSentence and '
      'braisedKeptOf on 0224', () {
    for (final (sentence, skims) in [
      // The object only inside the forbidding span (v107: a skim).
      ('Skim the foam from the liquid; do not skim the fat.', false),
      ('Do not skim the fat, skim the foam.', false),
      // A coordinated object (v107: the cut split it — a skim).
      ('Remove the herbs (do not skim the liquid and fat).', false),
      ('Remove the herbs (do not skim the juices, onions, and fat).', false),
      ('Remove the herbs (do not skim the liquid or fat).', false),
      // The bridge never crosses the act's own verb (v107: no skim).
      ('Do not skim the broth then skim fat from the surface.', true),
      // A real skim beside a forbidden one of another object.
      ('Skim the fat; do not skim the broth.', true),
      ('Skim fat from surface and discard.', true),
    ]) {
      expect(
        defatsSentence(sentence.toLowerCase()),
        skims,
        reason: sentence,
      );
      expect(
        braisedKeptOf(flat(), 170827, braise(sentence)) != null,
        skims,
        reason: sentence,
      );
    }
  });

  test('V6: the pour-off / drain-off / wipe sentences through '
      'shallowFryLinesOf on 0351', () {
    for (final (pour, lines) in [
      // 0351's own reading of a real "Pour off the liquid." is {20} (base
      // and tip, measured): the forbidden fat adds nothing to it.
      ('Pour off the liquid. ', {20}),
      ('Pour off the liquid; do not pour off the fat. ', {20}),
      // Base (v107): {20} — the real verb's clause borrowed the fat.
      ('Pour off the juices and onions; never pour off the fat. ', <int>{}),
      ('Drain off the water; do not drain off the fat. ', <int>{}),
      ('Pour off the juices; never pour off the fat. ', <int>{}),
      ('Do not pour off the juices and fat. ', <int>{}),
      ('Do not pour off the juices or fat. ', <int>{}),
      ('Wipe out the skillet; do not wipe out the pot. ', {20}),
      ('Pour off the fat; do not pour off the broth. ', {20}),
      ('Do not pour off the broth then pour off the fat. ', {20}),
    ]) {
      expect(shallowFryLinesOf(gravy(pour)), lines, reason: pour);
    }
  });

  /// The O6 probe's harness: one sentence's spans scanned through
  /// shallowFryLinesOf, a compute and the matches GET, each counted cold.
  Future<(int, int, int)> counts(Recipe r) async {
    final dir = Directory.systemTemp.createTempSync('salt-v108-');
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
    shallowFryLinesOf(r);
    final fry = forbidsEvaluations;
    forbidsEvaluations = 0;
    expect(
      await matchAndCompute(db, _fx, db.recipeByIdOrSlug(r.id)!.recipe),
      isNull,
    );
    final compute = forbidsEvaluations;
    forbidsEvaluations = 0;
    await matchesBody(db, _fx, db.recipeByIdOrSlug(r.id)!.recipe);
    return (fry, compute, forbidsEvaluations);
  }

  test('V6 COST: 39 negated discard clauses + one real — ONE span scan per '
      'path (base: 78 / 117 / 117)', () async {
    final s =
        '${List.filled(39, 'do not discard the oil').join('; ')}; '
        'discard the oil.';
    for (final file in [
      '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
      '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml',
    ]) {
      final base = loadCorpusRecipe(file);
      final r = base.copyWith(
        steps: [
          ...base.steps,
          RecipeStep(number: base.steps.length + 1, text: s),
        ],
      );
      final (bf, bc, bg) = await counts(base);
      final (tf, tc, tg) = await counts(r);
      expect((tf - bf, tc - bc, tg - bg), (1, 1, 1), reason: file);
    }
  });

  // v109 W16: true for this shape's ONE act; several acts per sentence are
  // the v109 W16 pin's (the memo keyed on the sentence).
  test('V6 COST at the caps: 119 steps of ten DISTINCT ~1,000-character '
      'sentences, one act — one scan per sentence, under the backstop', () {
    final base = loadCorpusRecipe(
      '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml',
    );
    String sentence(int n) {
      final b = StringBuffer('step $n ');
      while (b.length < 975) {
        b.write('discard the oil ');
      }
      b.write('do not discard the oil.');
      return b.toString();
    }

    final r = base.copyWith(
      steps: [
        ...base.steps,
        for (var i = 0; i < 119; i++)
          RecipeStep(
            number: base.steps.length + i + 1,
            text: [for (var j = 0; j < 10; j++) sentence(i * 10 + j)].join(' '),
          ),
      ],
    );
    forbidsEvaluations = 0;
    final sw = Stopwatch()..start();
    expect(shallowFryLinesOf(r), <int>{});
    expect(sw.elapsedMilliseconds, lessThan(backstopMs));
    // One discard-act scan per distinct sentence (base: one guard per
    // reader — the S9 probe's 3,570 on the identical-text shape).
    expect(forbidsEvaluations, 1190);
    forbidsEvaluations = 0;
    for (var i = 0; i < 1190; i++) {
      defatsSentence(
        sentence(i).replaceAll('discard the oil', 'skim fat').toLowerCase(),
      );
    }
    // The S9 defats shape made distinct: one skim-act scan per sentence
    // (base: one per call too, but a guard rebuilt per reader).
    expect(forbidsEvaluations, 1190);
  });
}
