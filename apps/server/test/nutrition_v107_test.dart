// Matcher v107 (batch fix107 at the base 069fe70; matcherVersion 97
// unchanged) — the fixes of dual-fleet review Run 083/084 over v106,
// union U1–U11 (.claude/diag/2026-11-07/review083/union_U.md; the rulings
// in fix107/brief.md). Every pin is a real corpus recipe through the real
// compute / PUT on the recorded fixtures; each STATED synthesized input
// names its exception and its corpus source. The HTTP arm's pins (U1 / U5
// / U7 / U8 / U9) live in static_asset_headers_test.dart.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'nutrition_v28_rule_a_test.dart' as v28;
import 'support/corpus.dart';
import 'support/cost_bounds.dart' show backstopMs;
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _herb = '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml';

final _fx = FixtureProvider(pending: pendingSearches);

SaltDatabase _db() {
  final dir = Directory.systemTemp.createTempSync('salt-v107-');
  final config = ServerConfig(
    dataDir: dir.path,
    logLevel: Level.WARNING,
    trustProxy: false,
  );
  final db = SaltDatabase.open(config.dbPath)
    ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
  addTearDown(() {
    db.dispose();
    dir.deleteSync(recursive: true);
  });
  return db;
}

Recipe _store(SaltDatabase db, Recipe r) {
  db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

/// [r] stored and computed (its section children first); the stored copy.
Future<Recipe> _compute(
  SaltDatabase db,
  NutritionProvider fdc,
  Recipe r,
) async {
  final stored = _store(db, r);
  for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
    expect(
      await matchAndCompute(db, fdc, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }
  expect(await matchAndCompute(db, fdc, stored), isNull);
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

IngredientMatchRow _row(SaltDatabase db, String id, int position) =>
    db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

/// [r] with its main line [position]'s raw text replaced and its amounts
/// set to [amounts].
Recipe _withLine(Recipe r, int position, String raw, List<Amount> amounts) {
  var at = 0;
  return r.copyWith(
    ingredients: [
      for (final g in r.ingredients)
        g.copyWith(
          items: [
            for (final l in g.items)
              (at++ == position) ? l.copyWith(raw: raw, amounts: amounts) : l,
          ],
        ),
    ],
  );
}

Future<Map<String, Object?>> _child(
  SaltDatabase db,
  NutritionProvider fdc,
  String id,
  int at,
) async {
  final body = await matchesBody(db, fdc, nutritionRecipeOf(db, id)!.recipe);
  jsonEncode(body);
  final item = (body['items']! as List)
      .cast<Map<String, Object?>>()
      .singleWhere((i) => i['position'] == at);
  return (item['match']! as Map<String, Object?>)['child']!
      as Map<String, Object?>;
}

void main() {
  group('v107 (fix107: Run 083/084 U1–U11)', skip: skipIfNoCorpus, () {
    u2();
    u3();
    u4();
    u6();
  });
}

/// U2 (LOW; S2 S11 / O3 O6 O14): the share grammar. '(1 / 2 recipe' wrote
/// no share and routed the WHOLE batch (0184|3: 1.0 / 1,456.7 g / 425.67);
/// '(1E9' was no token; '(2-recipe batch' over-read as a written share and
/// killed the amount's yield share. STATED synthesized (negative path: the
/// corpus `raw:` writes only '(½ recipe' — 3 lines, grep): 0184 Herb Sauce
/// line 3 "¼ cup Sauce Base (½ recipe; recipe follows)" edited as below,
/// with amounts [count '1'] (the A9 arm) and none (the whole-batch arm).
void u2() {
  const one = [Amount(measure: Measure.count, quantity: '1', primary: true)];
  const cup = [
    Amount(measure: Measure.volume, quantity: '1', unit: 'cup', primary: true),
  ];
  Future<(IngredientMatchRow, Map<String, Object?>)> run(
    String edit,
    List<Amount> amounts,
  ) async {
    final db = _db();
    final real = loadCorpusRecipe(_herb);
    expect(
      nutritionLines(real)[3].raw,
      '¼ cup Sauce Base (½ recipe; recipe follows)',
    );
    final stored = await _compute(db, _fx, _withLine(real, 3, edit, amounts));
    return (_row(db, stored.id, 3), await _child(db, _fx, stored.id, 3));
  }

  for (final written in ['(1 / 2 recipe', '(1 /2 recipe', '(1/ 2 recipe']) {
    for (final (arm, amounts, edit) in [
      ('A9', one, '1 Sauce Base $written)'),
      ('WB', const <Amount>[], 'Sauce Base $written; recipe follows)'),
    ]) {
      test('U2: "$edit" ($arm) reads 0.5 / 728.35 g / 212.83', () async {
        final (row, child) = await run(edit, amounts);
        // Base: child_share 1.0, 1,456.7 g, 425.67 (the whole batch).
        expect(row.childShare, 0.5);
        expect(row.grams, closeTo(728.35, 0.005));
        expect(child['kcal'], 212.83);
      });
    }
  }

  for (final edit in [
    '1 Sauce Base (1E9 recipes)',
    '1 Sauce Base (1-2 recipes)',
  ]) {
    test('U2: "$edit" reads not_routed no_share', () async {
      final (row, child) = await run(edit, one);
      expect(
        (row.status, row.hold, row.childShare, row.grams),
        ('confirmed', null, null, 0.0),
      );
      expect((child['state'], child['reason']), ('not_routed', 'no_share'));
    });
  }

  test('U2: "1 cup Sauce Base (2-recipe batch)" reads the amount share '
      "(1 cup of the child's MAKES ½ CUP = 2)", () async {
    final (row, child) = await run('1 cup Sauce Base (2-recipe batch)', cup);
    // Base (v106): no_share — the token over-read as a written share; the
    // eb9614c reading (the amount over the yield) restored.
    expect(row.childShare, 2.0);
    expect(row.grams, closeTo(2913.4, 0.005));
    expect((child['state'], child['kcal']), ('routed', 851.33));
  });
}

/// [r] with its first step text holding [a] given [b] in its place.
Recipe _ed(Recipe r, String a, String b) => r.copyWith(
  steps: [
    for (final s in r.steps)
      s.text.contains(a) ? s.copyWith(text: s.text.replaceFirst(a, b)) : s,
  ],
);

/// 0351 Sunday Gravy with [pour] inserted in step 4 after the meatballs'
/// lift-out (the v106 U1 / T6 shape — STATED synthesized: no corpus step
/// holds these sentences; 0351's own S4 text around them).
Recipe _gravy(String pour) {
  final g = loadCorpusRecipe(
    '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml',
  );
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

/// U3 (LOW ×6; S3 S4 S5 / O2 O7 OC2): v106's `_negatedAct` was NARROWER
/// than v105's substrings (one literal space, a closed determiner list,
/// the object required — "do not skim the surface fat", "(do not skim)",
/// "cannot pour off" read as a real skim / pour-off); `_forbids` read the
/// whole sentence (a same-verb negation of ANOTHER object erased a real
/// wipe); the regexes' other readers (`_Fat.discards` ×4, the `reused`
/// arm) read no negation. STATED synthesized re-texts (negative path: the
/// corpus step scan finds one object-bearing fat negation, 0492's "(do not
/// skim the fat from the liquid)"): 0224 Braised Brisket with Pomegranate's
/// "Using wide, shallow spoon, skim fat from surface and discard." and 0351
/// Sunday Gravy's step 4 (above).
void u3() {
  Recipe braise(String s) => _ed(
    _ed(
      loadCorpusRecipe(
        '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml',
      ),
      'Using wide, shallow spoon, skim fat from surface and discard.',
      'Using wide, shallow spoon, remove the herbs $s.',
    ),
    'return defatted liquid to pan',
    'return liquid to pan',
  );
  String flat() => nutritionLines(
    loadCorpusRecipe(
      '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml',
    ),
  )[0].raw;

  test('U3: every negated skim is forbidden — braisedKeptOf null on 0224 '
      '(base: the defatted-braise map, a deduction)', () {
    for (final s in [
      '(do not skim the surface fat)',
      '(do not skim any floating fat)',
      '(do not skim the rendered fat)',
      '(do not skim the accumulated fat)',
      '(do not skim the hot fat)',
      '(do not skim the bacon fat)',
      ', and leave the fat (do not skim)',
      ', and leave the fat (do not skim it)',
      '(do not skim the liquid or fat)',
      '(do not  skim the fat)',
      '(being careful not to skim the fat)',
      '(taking care not to skim off the fat)',
      '(do not ever skim the fat)',
      "(don't bother skimming the fat)",
      '(you cannot skim the fat)',
      // The owner gate: the `first` slot and the third qualifier word, each
      // unkilled by the fifteen above.
      '(do not first skim the fat)',
      '(do not skim the thick yellow surface fat)',
    ]) {
      expect(braisedKeptOf(flat(), 170827, braise(s)), isNull, reason: s);
    }
    // The controls: v106's own forbidden form, and a real skim kept.
    expect(
      braisedKeptOf(flat(), 170827, braise('(do not skim the fat)')),
      isNull,
    );
    expect(
      braisedKeptOf(flat(), 170827, braise('and skim fat from surface')),
      isNotNull,
    );
  });

  test('U3: defatsSentence reads the clause', () {
    // Base: true (v105: false) — the object-less negation.
    expect(defatsSentence('leave the fat; do not skim.'), isFalse);
    expect(defatsSentence('skim the fat; do not skim the broth.'), isTrue);
    expect(defatsSentence('do not skim the broth; skim the fat.'), isTrue);
  });

  test('U3: shallowFryLinesOf on 0351 — the forbidden pour-off, the clause '
      'rule, the discards readers and the reuse negation', () {
    for (final (pour, lines) in [
      // A forbidden pour-off of the fat (base {20}: read as a discard).
      ('Do not pour off the rendered fat. ', <int>{}),
      ('You cannot pour off the fat. ', <int>{}),
      ('Do not pour off the fat. ', <int>{}),
      // The same verb on ANOTHER object never erases the real act (base {}).
      ('Wipe out the skillet; do not wipe out the pot. ', {20}),
      ('Wipe out the skillet (do not wipe the pot). ', {20}),
      ('Wipe out the skillet, but do not wipe out the pan. ', {20}),
      // Closer 1 D5: each cut of `_clauseCut` its own pin (base {}; the
      // cut removed: {} — the negation of the pot erases the wipe).
      ('Wipe out the skillet and do not wipe out the pot. ', {20}),
      ('Wipe out the skillet but do not wipe out the pot. ', {20}),
      ('Wipe out the skillet, do not wipe out the pot. ', {20}),
      ('Wipe out the skillet. ', {20}),
      ('Do not wipe out the skillet. ', <int>{}),
      // A forbidden discard of the oil is none (base {}).
      ('Pour off the fat in skillet. Do not discard the oil. ', {20}),
      ('Pour off the fat in skillet. Discard the oil. ', <int>{}),
      ('Discard the oil; do not discard the fat. ', <int>{}),
      // A forbidden reuse act is no reuse (base {}: read as reused).
      (
        'Pour off and discard fat in skillet (do not scrape up the browned '
            'bits). ',
        {20},
      ),
      (
        'Pour off and discard fat in skillet; do not deglaze the skillet. ',
        {20},
      ),
      (
        'Do not leave the fat in skillet; pour off and discard fat in '
            'skillet. ',
        {20},
      ),
      ('Pour off and discard fat in skillet (do not reserve the fat). ', {20}),
      ('Pour off and discard fat in skillet (do not skim the sauce). ', {20}),
      ('Pour off and discard fat in skillet. ', {20}),
    ]) {
      expect(shallowFryLinesOf(_gravy(pour)), lines, reason: pour);
    }
  });

  test(
    'U3: the other readers of the guarded regexes read the clause guard',
    () async {
      const negated = 'Do not discard the oil. ';
      // `_fries` (friesForTest): 0224 browns, never fries — a forbidden
      // discard of the oil is no frying signal (base: true).
      final pom = loadCorpusRecipe(
        '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml',
      );
      final first = pom.steps.first.text;
      expect(friesForTest(pom), isFalse);
      expect(
        friesForTest(_ed(pom, first, '$negated$first')),
        isFalse,
      );
      expect(friesForTest(_ed(pom, first, 'Discard the oil. $first')), isTrue);
      // `_panFactsOf`'s oil discard: 0351 with the negation alone after the
      // lift-out (base: read as the discard).
      expect(shallowFryLinesOf(_gravy(negated)), <int>{});
      expect(shallowFryLinesOf(_gravy('Discard the oil. ')), <int>{});
      // `_panFatLines`: 0466's S2 "Wipe out the skillet and repeat …"
      // forbidden — no wipe closes the window (base: {3, 4}).
      final fish = loadCorpusRecipe(
        '0466-fish-meuniere-with-browned-butter-and-lemon.yaml',
      );
      expect(panFatLinesOf(fish), {3, 4});
      expect(
        panFatLinesOf(
          _ed(
            fish,
            'Wipe out the skillet and repeat',
            'Do not wipe out the skillet and repeat',
          ),
        ),
        <int>{},
      );
      // `_skimsFatIn` (fatSkimmedOf): 0224 with its skim re-texted to a
      // forbidden skim / pour-off reads no skim (base: true both).
      for (final s in [
        '(do not skim the surface fat)',
        '(do not pour off the rendered fat)',
      ]) {
        expect(fatSkimmedOf(braise(s)), isFalse, reason: s);
      }
      expect(fatSkimmedOf(braise('and skim fat from surface')), isTrue);
      // `_eatenAfterDiscard`: 0042's dressing eats "1 tablespoon more oil" +
      // "the remaining 1 tablespoon oil" after the LAST discard (the owner's
      // R4); a forbidden discard between them is not the last discard (base:
      // the plus part lost — the line read whole).
      final oil = (await FixtureProvider().food(2710180))!;
      double? discardedGrams(Recipe r, String raw) {
        final line = nutritionLines(r).firstWhere((l) => l.raw == raw);
        final whole = resolveGrams(
          amounts: line.amounts,
          food: oil,
          normalizedItem: normalizeItem(lineItemOf(line)),
          raw: line.raw,
        );
        final out = engineOutcome(r, line, oil, whole, picked: true);
        return out.source == 'discarded' ? out.grams : null;
      }

      const almondOil = '¾ cup plus 2 tablespoons vegetable oil';
      final almond = loadCorpusRecipe(
        '0042-almond-crusted-chicken-with-wilted-spinach-salad.yaml',
      );
      const smoking =
          'Heat 1 tablespoon more oil in the skillet over high heat until just '
          'smoking. ';
      final eaten = discardedGrams(almond, almondOil);
      expect(eaten, isNotNull);
      expect(
        discardedGrams(_ed(almond, smoking, '$smoking$negated'), almondOil),
        eaten,
      );
      // `_m52Fries`: 0118's rolls fried then baked read C2 (the LAST cook);
      // a forbidden discard after the bake is no later fry — every row as the
      // corpus recipe's (base: C1).
      const bake = 'about 15 minutes. ';
      final cutlets = loadCorpusRecipe(
        '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
      );
      Future<List<(int, double?, String?, String)>> rows(Recipe r) async {
        final db = _db();
        final stored = await _compute(db, _fx, r);
        return [
          for (final m in db.ingredientMatchesFor(stored.id))
            (m.position, m.grams, m.hold, m.status),
        ];
      }

      expect(
        await rows(_ed(cutlets, bake, '$bake$negated')),
        await rows(cutlets),
      );
    },
  );
}

/// U6 (LOW; S8 / O10): RULE C at the caps — v106's `_panFactsOf` ran
/// `_forbids` over the WHOLE sentence once per `_pansWiped` match (~77 per
/// ~1,000-char sentence with the negated act at its end): measured at the
/// base 2,936 / 3,167 / 3,199 ms (shallowFryLinesOf / matchAndCompute /
/// GET) on the pour shape, 1,054 / 1,299 / 1,315 on the wipe shape (plain
/// 232 / 487 / 500); the tip ~450 / ~680 / ~700 and ~280 / ~490 / ~515.
/// v107: each match reads its clause, the verdict hoisted once per
/// sentence and act ([forbidsEvaluations]). STATED synthesized cap shape
/// (the S8 probe): 0351 + 119 steps of ten ~1,000-character sentences.
void u6() {
  String step(String unit, String tail) {
    final one = StringBuffer();
    while (one.length + unit.length + tail.length <= 995) {
      one.write(unit);
    }
    one.write(tail);
    final b = StringBuffer();
    while (b.length + one.length + 1 <= 10000) {
      b.write('$one ');
    }
    return b.toString().trimRight();
  }

  for (final (name, unit, tail, perSentence) in [
    ('pour', 'pour off fat ', ' do not pour off fat.', 2),
    // A cut defeats the one-clause shortcut: ~77 matches in ONE clause,
    // that clause tested once (the memo) — measured, count-pinned.
    // RE-PIN (closer 1 D6): 4 → 2 — the whole verdict no longer read
    // before a cut sentence's clause (the fixer's tip: 4).
    ('pour; cut', 'pour off fat ', ' do not pour off fat; stir.', 2),
    ('wipe', 'wipe skillet ', ' do not wipe skillet.', 2),
    ('plain', 'stir the sauce well ', '.', 0),
  ]) {
    test('U6 CAP SHAPE ($name): $perSentence _forbids regex evaluations per '
        'one-clause sentence (the two readers: _panFactsOf, _panFatLines), '
        'under the backstop', () {
      final base = loadCorpusRecipe(
        '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml',
      );
      final text = step(unit, tail);
      final sentences = '. '.allMatches(text).length + 1;
      expect(sentences, 10);
      final r = base.copyWith(
        steps: [
          ...base.steps,
          for (var i = 0; i < 119; i++)
            RecipeStep(number: base.steps.length + i + 1, text: text),
        ],
      );
      forbidsEvaluations = 0;
      final sw = Stopwatch()..start();
      expect(shallowFryLinesOf(r), {20});
      expect(sw.elapsedMilliseconds, lessThan(backstopMs));
      // Base: ~77 whole-sentence scans per sentence (one per match).
      expect(forbidsEvaluations, perSentence * sentences * 119);
    });
  }

  test('U6: a many-clause sentence tests each clause once', () {
    // STATED synthesized: 39 forbidden "do not pour off fat" clauses cut by
    // ";", the real pour-off last — every match is tested, each clause
    // ONCE — never one scan per match. RE-PIN (closer 1 D6): 43 → 42 =
    // the ruled clauses + 2 (the fixer's tip 43 = clauses + 3: the pour
    // verdict read whole before the clauses). Traced: `_panFactsOf` 39
    // (its 39 negated clauses; the real one holds no negation word, no
    // regex), `_skimsFatIn` 3 (the skim and pour verdicts + one clause).
    final s =
        '${List.filled(39, 'do not pour off fat').join('; ')}; pour off fat';
    forbidsEvaluations = 0;
    expect(shallowFryLinesOf(_gravy('$s. ')), {20});
    expect(forbidsEvaluations, 42);
    // Closer 1 D6: a whole verdict already read false answers a clause
    // free — `_skimsFatIn` reads the skim verdict (false), then the first
    // skim word's clause ("Skim the fat not too hard", a negation word):
    // 3 (the skim and pour verdicts + the pour clause); re-testing that
    // clause would be 4.
    forbidsEvaluations = 0;
    shallowFryLinesOf(
      _gravy('Skim the fat not too hard; do not pour off the fat. '),
    );
    expect(forbidsEvaluations, 3);
  });
}

class _NoNet implements NutritionProvider {
  int calls = 0;
  @override
  Future<List<FdcCandidate>> search(String query) async {
    calls++;
    throw const NutritionProviderException('no net', scope: FailureScope.food);
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    calls++;
    throw const NutritionProviderException('no net', scope: FailureScope.food);
  }
}

/// U4 (LOW; S6, escalated): the held_on class's FIFTH arm — the compute's
/// DECIDED arm on a person-confirmed rule-B1 "peel plus juice" row with the
/// juice uncached took [withParts]' partial `second_food` (24 g zest only,
/// stamped, the recipe FRESH at 597.22 for 604.2), and `unholdOn` never
/// re-opened it; the same row undecided holds `food_unavailable` on the
/// juice. v107: the decided derivation fetches the rule's second record as
/// the engine arm does, so a failure holds `food_unavailable` held_on the
/// juice. 0536 Crispy Orange Beef line 3 (parts 169103 zest + 169098 juice)
/// confirmed through the real PUT. STATED synthesized (negative path, as
/// v105 U1's own pin: no code evicts fdc_food_cache): 169098 dropped from
/// both caches and a FOOD fault on it.
void u4() {
  const beef = '0536-crispy-orange-beef.yaml';
  const juice = 169098;
  test(
    'U4: a confirmed peel-plus-juice row with the juice uncached holds '
    'food_unavailable on the juice; its arrival re-opens it; 0 requests',
    () async {
      final (db, path) = a.pathDb();
      final r = loadCorpusRecipe(beef);
      await d.editAndCompute(db, _fx, r);
      await applyMatchOverride(db, _fx, r, 3, {
        'raw': nutritionLines(r)[3].raw,
        'confirmed': true,
      });
      final confirmed = d.rowOf(db, r, 3);
      expect((confirmed.status, confirmed.grams), ('confirmed', 86.0));
      expect(
        [for (final p in partsOf(confirmed.parts)) p.fdcId],
        [169103, juice],
      );
      expect(db.nutritionFor(r.id)!.caloriesPerServing, closeTo(603.92, 0.005));
      v28.dropFood(path, juice);
      final fault = v28.FoodFault(_fx, {juice}, scope: FailureScope.food);
      for (var p = 1; p <= 3; p++) {
        await matchAndCompute(db, fault, r);
      }
      final held = d.rowOf(db, r, 3);
      // Base: hold second_food, held_on null, 24.0 g, derived, FRESH.
      expect(
        (held.status, held.hold, held.heldOn, held.grams),
        ('confirmed', 'food_unavailable', juice, null),
      );
      // Held: out of the totals (base 24 g counted).
      expect(db.nutritionFor(r.id)!.caloriesPerServing, closeTo(591.13, 0.005));
      // The hold is the derived state (stamped, as the engine arm's and
      // v105 U1's): fresh, the row out of the totals until the part
      // arrives.
      expect(nutritionIsFresh(db, r), isTrue);
      // The juice arrives: the row re-opens (base: unholdOn a no-op).
      await cachedFood(db, _fx, juice);
      expect(d.rowOf(db, r, 3).derivedSeq, isNull);
      expect(nutritionIsFresh(db, r), isFalse);
      final none = _NoNet();
      await matchAndCompute(db, none, r);
      expect(none.calls, 0);
      final healed = d.rowOf(db, r, 3);
      expect(
        (healed.status, healed.hold, healed.heldOn, healed.grams),
        ('confirmed', null, null, 86.0),
      );
      expect(db.nutritionFor(r.id)!.caloriesPerServing, closeTo(603.92, 0.005));
    },
  );

  test('U4: the undecided control holds food_unavailable on the juice '
      '(unchanged)', () async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe(beef);
    await d.editAndCompute(db, _fx, r);
    v28.dropFood(path, juice);
    final fault = v28.FoodFault(_fx, {juice}, scope: FailureScope.food);
    for (var p = 1; p <= 3; p++) {
      await matchAndCompute(db, fault, r);
    }
    final held = d.rowOf(db, r, 3);
    expect(
      (held.status, held.hold, held.heldOn),
      ('auto', 'food_unavailable', juice),
    );
  });
}
