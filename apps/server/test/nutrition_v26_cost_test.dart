// Run 056 I4/I5/I10 (matcher v26, RULE C at the LOOP level): a detector
// costs O(text) per recipe at the EDITOR CAPS — 400 lines × 120 steps ×
// 10,000 characters per step (recipe_edit_service.dart) — on the compute,
// the matches GET, the PUT and the apply-to-all, proven by COUNT pins: each
// memo family of the step index counts its derivations ([stepIndexCounts]
// `memo:<family>`, `hits`, `ends`, `lower`, `allSentences`), each mention
// read per detector family (`mentionVisits`), each eaten part parsed
// (`eatenParses`), each layout decoded ([SaltDatabase.layoutDecodes]).
// Every family the pins meet must have a bound here (an unknown family
// fails), so a memo deleted or keyed loosely fails a count, never only a
// clock; each time bound ([backstopMs]) is a generous backstop.
//
// Real corpus recipes (0241 Garlic-Studded Roast Pork Loin, 0148 Crispy
// Fried Chicken) with recorded FDC answers (FixtureProvider), never the
// network. Synthesized, a stated exception: the hostile lines and steps put
// in them (negative-path inputs at the caps no corpus recipe holds — the
// digests' S5/S7/S8/S9/O6/O8/O9/S10/S11/S14/O15/S23 shapes and the v26
// verifier's plus-distinct and long-lines shapes), and the typed
// sentences of the windowed-log and drained pins.
// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_cost_test.dart' show fill, readAll;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

/// The editor's caps (recipe_edit_service.dart).
const capLines = 400;
const capSteps = 120;
const capStep = 10000;
const capLine = 1000;

IngredientLine ln(String raw) {
  final p = parseIngredientLine(raw);
  return IngredientLine(
    raw: raw,
    item: p.item,
    prep: p.prep,
    amounts: p.amounts,
  );
}

/// [base] with [raws] as its lines and [steps] as its steps, within the
/// caps (asserted).
Recipe capped(Recipe base, List<String> raws, List<String> steps) {
  expect(raws.length, lessThanOrEqualTo(capLines));
  for (final r in raws) {
    expect(r.length, lessThanOrEqualTo(capLine));
  }
  expect(steps.length, lessThanOrEqualTo(capSteps));
  for (final s in steps) {
    expect(s.length, lessThanOrEqualTo(capStep));
  }
  return base.copyWith(
    ingredients: [
      IngredientGroup(items: [for (final r in raws) ln(r)]),
    ],
    steps: [
      for (final (i, s) in steps.indexed) RecipeStep(number: i + 1, text: s),
    ],
  );
}

const pork = '0241-garlic-studded-roast-pork-loin.yaml';
const chicken = '0148-crispy-fried-chicken.yaml';
const foods = [
  'garlic',
  'onion',
  'carrot',
  'celery',
  'thyme',
  'parsley',
  'leek',
  'shallot',
  'ginger',
  'fennel',
  'radish',
  'turnip',
  'potato',
  'pepper',
  'chive',
  'basil',
  'sage',
  'dill',
  'mint',
  'tarragon',
];

/// The [i]th of 400 distinct foods (a distinct head each).
String food(int i) => '${foods[i % foods.length]}${'x' * (i ~/ foods.length)}';

/// Each detector family's hostile recipe at the caps, made afresh (a cold
/// index, as a first compute or GET meets it).
final Map<String, Recipe Function()> shapes = {
  // S8: every salt line owns every written mention.
  'salt': () => capped(
    loadCorpusRecipe(pork),
    List.filled(capLines, '1 teaspoon salt'),
    List.filled(capSteps, fill('Add 1 teaspoon salt. ', capStep)),
  ),
  // Pot shares of distinct lines in cooking water, two mentions to a
  // sentence and no drain (the later-drain memo, critic 1's).
  'water': () => capped(
    loadCorpusRecipe(pork),
    [for (var i = 0; i < capLines; i++) '${i + 2} tablespoons salt'],
    List.filled(
      capSteps,
      fill(
        'Bring water to a boil with 1 teaspoon salt and 1 teaspoon salt. ',
        capStep,
      ),
    ),
  ),
  // _dissolvedWithBrineSalt: a brine by volume beside 399 small salts.
  'dissolve': () => capped(
    loadCorpusRecipe(pork),
    ['1/4 cup salt', for (var i = 1; i < capLines; i++) '1 teaspoon salt'],
    [
      'Dissolve 1/4 cup salt in 2 quarts water; submerge the pork in the brine.',
      for (var i = 1; i < capSteps; i++)
        fill('Dissolve the salt in the water. ', capStep),
    ],
  ),
  // S7/S5: written flour mentions every other line claims.
  'dredge': () => capped(
    loadCorpusRecipe(chicken),
    [
      ...List.filled(capLines - 1, '1 cup all-purpose flour'),
      '1 teaspoon salt',
    ],
    [
      'Heat the oil to 350 degrees. Dredge the pork in the flour. Fry.',
      for (var i = 1; i < capSteps; i++)
        fill('Stir 1 cup flour into the sauce. ', capStep),
    ],
  ),
  // O6/S9: sentences naming the flour, none dredging.
  'flour': () => capped(
    loadCorpusRecipe(chicken),
    List.filled(capLines, '1 cup all-purpose flour'),
    [
      'Heat the oil to 350 degrees. Fry the pork.',
      for (var i = 1; i < capSteps; i++)
        fill('Stir the flour into the sauce. ', capStep),
    ],
  ),
  // S9: 400 distinct foods, every step a brine.
  'brine': () => capped(
    loadCorpusRecipe(pork),
    [for (var i = 0; i < capLines; i++) '1 cup ${food(i)}'],
    List.filled(
      capSteps,
      '${fill('Stir the brine well. ', capStep - 40)}Submerge the pork in the brine.',
    ),
  ),
  // O8: one frying amount on 400 distinct oil lines.
  'oil': () => capped(
    loadCorpusRecipe(pork),
    [for (var i = 0; i < capLines; i++) '1/4 cup vegetable oil, part $i'],
    List.filled(capSteps, fill('Heat 1/4 cup oil to 350 degrees. ', capStep)),
  ),
  // O8/S3: identical raws, and the other frying fats.
  'oil2': () => capped(
    loadCorpusRecipe(pork),
    [
      ...List.filled(capLines - 2, '1/4 cup vegetable oil'),
      '1/4 cup shortening',
      '1/4 cup lard',
    ],
    [
      'Dredge the pork in the flour.',
      for (var i = 1; i < capSteps; i++)
        fill('Heat 1/4 cup oil to 350 degrees. ', capStep),
    ],
  ),
  // S9: a rub the last sentence rinses off.
  'cure': () => capped(
    loadCorpusRecipe(pork),
    List.filled(capLines, '1 teaspoon salt'),
    [
      for (var i = 1; i < capSteps; i++)
        fill('Rub salt over the pork. ', capStep),
      'Rinse the pork.',
    ],
  ),
  // The cheese milk: 200 milk lines beside 200 distinct foods.
  'cheese': () => capped(
    loadCorpusRecipe(pork),
    [
      for (var i = 0; i < capLines / 2; i++) '16 cups whole milk',
      for (var i = 0; i < capLines / 2; i++) '1 teaspoon ${food(i)}',
    ],
    List.filled(
      capSteps,
      fill('Heat the milk and stir until the whey separates. ', capStep),
    ),
  ),
  // S23: sugar lines beside salt lines on period-free steps.
  'sugar': () => capped(
    loadCorpusRecipe(pork),
    [
      for (var i = 0; i < capLines / 2; i++) '1 cup sugar',
      for (var i = 0; i < capLines / 2; i++) '1 teaspoon salt',
    ],
    List.filled(capSteps, '1 teaspoon salt ' * (capStep ~/ 16)),
  ),
  // The v26 verifier's D2: 400 distinct "plus" frying oils, one fry step,
  // and 32,000 sentences naming the oil with no temperature — each was a
  // full frying-heat check (~7 µs) before the three-digit prefilter.
  'plus': () => capped(
    loadCorpusRecipe(pork),
    [
      for (var i = 0; i < capLines; i++)
        '2 cups plus ${i + 1} teaspoons vegetable oil, for frying',
    ],
    [
      'Heat the oil to 350 degrees and fry the pork.',
      for (var i = 1; i < capSteps; i++)
        fill('Stir 3 teaspoons oil into the sauce. ', capStep),
    ],
  ),
  // The v26 verifier's D1: 400 distinct lines at the 1,000-character cap.
  'long-lines': () => capped(
    loadCorpusRecipe(pork),
    [
      for (var i = 0; i < capLines; i++)
        '1 cup ${food(i)}, ${fill('finely chopped and set aside ', capLine - 40)}',
    ],
    List.filled(capSteps, fill('Stir the garlic into the sauce. ', capStep)),
  ),
  // A head of other characters ("2%"), read by its own scan.
  'percent': () => capped(
    loadCorpusRecipe(pork),
    List.filled(capLines, '1 cup 2%'),
    List.filled(capSteps, fill('Whisk the 2% into the sauce. ', capStep)),
  ),
};

/// The counts of one [readAll] of a fresh [shape], and its milliseconds.
(Map<String, int>, int, Recipe) readCounts(String shape) {
  final r = shapes[shape]!();
  stepIndexCounts.clear();
  final sw = Stopwatch()..start();
  readAll(r);
  return (Map.of(stepIndexCounts), sw.elapsedMilliseconds, r);
}

void main() {
  pins();
  bounds();
  foodGated();
  fryingOils();
  eggDips();
  cutDough();
  m69Coats();
  review70();
  review71();
  group('RULE C at the loop level, every detector of every line at the caps '
      '(Run 056 S5/S7/S8/S9/O6/O8/S14/O15/S20/S23)', () {
    // Measured at 8113b24 (one readAll pass, the digests' shapes): salt
    // 159 s, dredge 100 s, oil 100 s, brine 11 s, flour 4.3 s, cure 3.9 s,
    // cheese 2.5 s, water 1.2 s; the tree 0.04–1.2 s.
    for (final shape in shapes.keys) {
      test('$shape: every family counted once per recipe, head, step, '
          'sentence or mention, within the backstop', () {
        final (counts, ms, r) = readCounts(shape);
        expectBounded(r, counts, shape);
        expect(counts['indexes'], 1);
        expect(counts['lower'], 1);
        expect(ms, lessThan(backstopMs), reason: '$shape: $counts');
      });
    }

    test('each family the shapes exercise is DERIVED (a detector that stops '
        'reading its memo fails here, as one keyed loosely fails above)', () {
      final seen = <String>{};
      for (final shape in shapes.keys) {
        seen.addAll(readCounts(shape).$1.keys);
      }
      // ('names' is process-wide, counted on its first compile only;
      // 'memo:keptOil' is the compute's, pinned below.)
      final missing = [
        for (final family in [
          'memo:fries',
          'memo:kept',
          'memo:naming',
          'memo:starter',
          'memo:dissolving',
          'memo:whey',
          'memo:dunked',
          'hits',
          'ends',
          'lower',
          'memo:drainedLater',
          'memo:braise',
          'memo:says',
          'memo:brines',
          'memo:milkStep',
          'allSentences',
          'memo:lastRinse',
          'memo:dredgeNamed',
          'memo:rinsedCure',
          'memo:amountWriters',
          'memo:eatenParts',
          'memo:namingAll',
          'memo:brineWords',
          'memo:dredged',
          'memo:parted',
          'memo:sugarBeside',
          'memo:brinedByVolume',
          'memo:dissolveIndex',
          'memo:dissolveItems',
          'memo:dissolvedWith',
          'occurrenceScans',
          'memo:firstOwn',
          'mentionVisits',
          'eatenParses',
          'heatChecks',
        ])
          if (!seen.contains(family)) family,
      ];
      expect(missing, isEmpty);
    });

    test('a line owns whole GROUPS of mentions (S8): 400 salt lines each '
        'owning all 57,000 written mentions read each mention once per '
        'detector family, never once per line', () {
      final (counts, _, _) = readCounts('salt');
      expect(counts['mentions'], greaterThan(50000));
      expect(
        counts['mentionVisits'],
        lessThanOrEqualTo(6 * counts['mentions']!),
      );
      expect(counts['lineMentions'], lessThanOrEqualTo(2 * capLines));
    });

    test('D2 (v26 verifier): a frying-heat check reads in full only a '
        'sentence carrying a three-digit run — plus\'s 35,000 "Stir 3 '
        'teaspoons oil" sentences pay none, its one fry step does (the '
        "held oils' note derives the owners)", () {
      final r = shapes['plus']!();
      stepIndexCounts.clear();
      final note = holdNoteOf(
        r,
        nutritionLines(r).first,
        'ambiguous_medium',
      );
      expect(note, contains('Heat the oil to 350 degrees'));
      expect(stepIndexCounts['sentences'], greaterThan(30000));
      expect(stepIndexCounts['memo:oilOwners'], 1);
      expect(stepIndexCounts['heatChecks'], inInclusiveRange(1, 6));
    });

    test("the eaten part (S5/S7): 36,000 written '1 cup flour' mentions "
        'every other line claims, parsed once per head and medium; no line '
        'scans the lines', () {
      final (counts, _, r) = readCounts('dredge');
      final flour = nutritionLines(r).first;
      expect(holdNoteOf(r, flour, 'coating'), isNull);
      expect(
        counts['eatenParses'],
        lessThanOrEqualTo(2 * counts['sentences']!),
      );
      expect(counts['memo:amountWriters'], lessThanOrEqualTo(3));
    });
  }, skip: skipIfNoCorpus);

  group('RULE C end to end at the caps (Run 056 I4: the compute, the '
      'matches GET, the PUT pick and confirm, the apply-to-all)', () {
    // Measured at 8113b24 on a snap13 copy: salt compute 21.5 s and GET
    // 20–26 s; water compute 2.2 s, GET 1.6 s; the tree 0.1–1.1 s.
    for (final shape in [
      'salt',
      'water',
      'dissolve',
      'dredge',
      'brine',
      'oil',
      'oil2',
      'plus',
      'long-lines',
      'cure',
      'cheese',
      'sugar',
    ]) {
      test('$shape: every path counted within its bounds, the layout '
          'decoded at most once, each under the backstop', () async {
        final r = shapes[shape]!();
        final db = wp.tempDb();
        final provider = _NoHits();
        wp.saveRecipe(db, r);
        Future<void> path(String name, Future<Object?> Function() run) async {
          stepIndexCounts.clear();
          db.layoutDecodes = 0;
          reachDecodes = 0;
          final sw = Stopwatch()..start();
          await run();
          final ms = sw.elapsedMilliseconds;
          final counts = Map.of(stepIndexCounts);
          // The request's own decode, at most one reach decode, and the
          // apply's decode of the recipe it writes: each its own index,
          // every family bounded per index.
          final indexes = counts['indexes'] ?? 0;
          expect(reachDecodes, lessThanOrEqualTo(1), reason: name);
          expect(
            indexes,
            lessThanOrEqualTo(
              1 + reachDecodes + (name == 'apply-to-all' ? 1 : 0),
            ),
            reason: name,
          );
          expectBounded(r, counts, '$shape $name', copies: indexes);
          // Once per write's layout (O9/S10: twice per ROW write at v25);
          // the apply lays out the PUT's recipe and then each it writes.
          expect(
            db.layoutDecodes,
            lessThanOrEqualTo(name == 'apply-to-all' ? 2 : 1),
            reason: '$name layouts',
          );
          expect(ms, lessThan(backstopMs), reason: '$shape $name: $counts');
        }

        Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
        Map<String, Object?> body(int i, Map<String, Object?> b) => {
          'raw': nutritionLines(r)[i].raw,
          ...b,
        };
        await path('compute', () => matchAndCompute(db, provider, stored()));
        await path('GET', () => matchesBody(db, provider, stored()));
        await path(
          'PUT pick',
          () => applyMatchOverride(
            db,
            provider,
            stored(),
            0,
            body(0, {
              'fdc_id': 173468,
            }),
          ),
        );
        await path(
          'PUT confirm',
          () => applyMatchOverride(
            db,
            provider,
            stored(),
            0,
            body(0, {
              'confirmed': true,
            }),
          ),
        );
        await path('GET decided', () => matchesBody(db, provider, stored()));
        await path(
          'apply-to-all',
          () => applyMatchOverride(
            db,
            provider,
            stored(),
            1,
            body(1, {
              'fdc_id': 173468,
              'apply_to_all': true,
            }),
          ),
        );
        await path('recompute', () => matchAndCompute(db, provider, stored()));
      });
    }
  }, skip: skipIfNoCorpus);

  group('RULE C, the two memo families no pin counted (R3, simplification '
      'ledger L8-5): the dredge set-out and the crumb coat sentence', () {
    // STATED synthesized cost inputs (cap shapes no corpus recipe holds):
    // the real 0206 Crunchy Baked Pork Chops padded to the 400-line cap with
    // its own real line [flour] under 115 × 10,000-character steps of "Stir
    // ¼ cup flour into the sauce." (every sentence holds the lead amount and
    // the head, none sets the coat out) before its own steps; the real 0416
    // Lighter Chicken Parmesan padded with its own [panko] under steps of
    // "Coat the cutlets." (every sentence opens the coat pattern, none names
    // crumbs). TRUE: the real [setOut] / [coat] sentence stays, in the last
    // steps; quiet: that one sentence reads "in a bowl" / "press both sides
    // of the chicken into the bread crumbs" — each reader scans every
    // sentence and answers false. ABBA at these caps (R3, 5 warm reps per
    // side): dropping the memos took the compute 0.9 → 5.5 s (set-out, both
    // shapes) and 0.8 → 4.9 s quiet / 13.0 s TRUE (crumb coat), the GET 0.7
    // → 5.3 s and 0.6 → 12.7 / 24.8 s.
    const flour = '¼ cup plus 6 tablespoons unbleached all-purpose flour';
    const setOut = 'Place ¼ cup of the flour in a pie plate.';
    const panko = '1½ cups panko (Japanese-style bread crumbs)';
    const coat =
        'Finally, coat both sides of the chicken with the bread crumbs.';
    for (final (name, file, line, filler, sentence, quietly, family) in [
      (
        'SET-OUT',
        '0206-crunchy-baked-pork-chops.yaml',
        flour,
        'Stir ¼ cup flour into the sauce. ',
        setOut,
        'Place ¼ cup of the flour in a bowl.',
        'memo:setsOut',
      ),
      (
        'CRUMB COAT',
        '0416-lighter-chicken-parmesan.yaml',
        panko,
        'Coat the cutlets. ',
        coat,
        'Finally, press both sides of the chicken into the bread crumbs.',
        'memo:coatsWithCrumbs',
      ),
    ]) {
      for (final loud in [false, true]) {
        test('$name (${loud ? 'TRUE' : 'quiet'}): the reader derived once '
            'per index on the compute, the GET and the recompute', () async {
          final base = loadCorpusRecipe(file);
          final own = [for (final g in base.ingredients) ...g.items];
          final r = capped(
            base,
            [
              for (final l in own) l.raw,
              for (var i = own.length; i < capLines; i++) line,
            ],
            [
              for (var i = base.steps.length; i < capSteps; i++)
                fill(filler, capStep),
              for (final st in base.steps)
                loud ? st.text : st.text.replaceFirst(sentence, quietly),
            ],
          );
          expect(
            r.steps.where((st) => st.text.contains(sentence)),
            hasLength(loud ? 1 : 0),
          );
          final db = wp.tempDb();
          final provider = FixtureProvider(pending: pendingSearches);
          wp.saveRecipe(db, r);
          Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
          // EXACTLY, each path before its clock (the count kills, never the
          // backstop): one index, the reader once — but the quiet crumb
          // coat's recompute, whose panko rows are counted (no medium read).
          Future<void> timed(
            String step,
            Future<Object?> Function() run,
          ) async {
            stepIndexCounts.clear();
            final sw = Stopwatch()..start();
            await run();
            final ms = sw.elapsedMilliseconds;
            final counts = Map.of(stepIndexCounts);
            expectBounded(r, counts, '$name $step');
            expect(
              {
                for (final k in ['indexes', family]) k: counts[k],
              },
              {
                'indexes': 1,
                family:
                    step == 'recompute' &&
                        family == 'memo:coatsWithCrumbs' &&
                        !loud
                    ? null
                    : 1,
              },
              reason: '$name $step',
            );
            expect(ms, lessThan(backstopMs), reason: '$name $step: $counts');
          }

          await timed('compute', () => matchAndCompute(db, provider, stored()));
          // The TRUE path moves the line: the set-out ¼ cup is the dredge
          // (the 6 tablespoons eaten), the crumbs the held coat's.
          expect(
            {
              for (final row in db.ingredientMatchesFor(r.id))
                if (row.raw == line)
                  (row.gramSource, row.hold, row.grams?.toStringAsFixed(2)),
            },
            switch ((family, loud)) {
              // RE-PIN (M82 batch, v84, C5a): the flour at 5 oz a cup — was
              // 30.34 and 45.42 (the counts unchanged).
              ('memo:setsOut', false) => {('discarded', null, '35.61')},
              ('memo:setsOut', true) => {('discarded', null, '53.33')},
              (_, false) => {('density', null, '88.72')},
              // RE-PIN (M88 batch, v88): the crumb coat reads FNDDS 2706442
              // — the panko shares the crumbs' own budget by its dry mass,
              // f_c (was 0.28 at the one f; the counts unchanged).
              _ => {('discarded', null, '0.20')},
            },
          );
          await timed('GET', () => matchesBody(db, provider, stored()));
          await timed('recompute', () async => recomputeTotals(db, stored()));
        });
      }
    }
  }, skip: skipIfNoCorpus);
}

void pins() {
  group('RULE C pins (Run 056 I5, critic 1, S24, S28)', () {
    test('I5 (O7/S6/S11): the window notice is logged ONCE per recipe and '
        'content — 3 decodes of a recipe of 120 period-free 9,999-character '
        'steps log one batch of 120, not 360; an edited step logs again', () {
      final base = loadCorpusRecipe(pork);
      final step = fill(
        'Stir the cornstarch into the bowl gently ',
        2 * capStep,
      ).substring(0, capStep - 1);
      final records = <String>[];
      Logger.root.level = Level.INFO;
      final sub = Logger.root.onRecord.listen((r) {
        if (r.message.contains('the nutrition rules read')) {
          records.add(r.message);
        }
      });
      addTearDown(sub.cancel);
      Recipe decode(String text) => capped(
        base,
        [for (final g in base.ingredients) ...g.items.map((l) => l.raw)],
        List.filled(capSteps, text),
      );
      final perGet = <int>[];
      for (var get = 0; get < 3; get++) {
        stepIndexCounts.clear();
        final r = decode(step);
        readAll(r);
        perGet.add(stepIndexCounts['windowLogs'] ?? 0);
      }
      expect(perGet, [capSteps, 0, 0]);
      expect(records, hasLength(capSteps));
      stepIndexCounts.clear();
      readAll(decode('${step.substring(1)}x'));
      expect(stepIndexCounts['windowLogs'], capSteps);
      // Bounded (S21/O19): past the cap the set is cleared whole, so the
      // first content logs again — never an unbounded set.
      memoCapForTest = 1;
      addTearDown(() => memoCapForTest = null);
      stepIndexCounts.clear();
      readAll(decode(step));
      expect(stepIndexCounts['windowLogs'], capSteps);
    });

    test('S24: the windowed sentence keeps its period, so the next sentence '
        "stays its own: 0024 plus a typed '<1,500 characters>. To pan-fry, "
        "increase the heat.' does not fry (the optional note 0506's "
        'shape opens its sentence)', () {
      final r = loadCorpusRecipe('0024-hearty-lentil-soup.yaml');
      final long = r.copyWith(
        steps: [
          ...r.steps,
          RecipeStep(
            number: r.steps.length + 1,
            text: '${'x' * 1500}. To pan-fry, increase the heat.',
          ),
        ],
      );
      expect(friesForTest(r), isFalse);
      expect(friesForTest(long), isFalse);
    });

    test('Opus critic 1: the later-drain memo is keyed by step AND start — '
        "0572's soda stays in cooking water with one typed step prepended "
        '(v25 keyed the start alone: every first sentence shared an '
        'answer, and the soda was counted whole)', () {
      final r = loadCorpusRecipe('0572-ultracreamy-hummus.yaml');
      final soda = nutritionLines(r).firstWhere((l) => l.raw.contains('soda'));
      DiscardedMedium? of(Recipe r, IngredientLine l) =>
          discardedMediumOf(r, l, normalizeItem(lineItemOf(l)));
      expect(of(r, soda), DiscardedMedium.cookingWater);
      final prepended = r.copyWith(
        steps: [
          const RecipeStep(
            number: 0,
            text: 'Bring 1 cup water and baking soda to boil in kettle.',
          ),
          ...r.steps,
        ],
      );
      final line = nutritionLines(prepended).firstWhere(
        (l) => l.raw.contains('soda'),
      );
      expect(of(prepended, line), DiscardedMedium.cookingWater);
    });
  }, skip: skipIfNoCorpus);

  group('normalizeItem (S28, corpus-free)', () {
    test("_withoutParens writes a space for a paren ('x(y)z' is 'x z', "
        'never xz) and never strips one across a line break, as the lazy '
        r'`\(.*?\)` it replaced never did', () {
      expect(normalizeItem('x(y)z'), 'x z');
      expect(normalizeItem('a (b\nc) d'), 'a b c d');
      expect(normalizeItem('a (b\u2028c) d'), 'a b c d');
      expect(normalizeItem('flour (sifted) cake'), 'flour cake');
    });
  });
}

void bounds() {
  group('Bounded, exact process-wide and per-request memos (Run 056 '
      'S21/O19, O16/S19)', () {
    // A memo cleared whole past its cap derives its first key again after
    // the cap's worth of others; one that never clears answers it from
    // memory (the mutant). Below the cap the memo answers (a second read
    // derives nothing).
    int twice(
      void Function() read,
      int Function() reads,
      void Function() reset,
    ) {
      reset();
      read();
      reset();
      read();
      return reads();
    }

    test('S21/O19: plusPartOf, lineKeyOf, the raw keys and the compiled '
        'head patterns each clear whole past the cap (0 here: every read) and keep '
        'below it', () {
      final r = loadCorpusRecipe(pork);
      final lines = nutritionLines(r);
      expect(lines.length, greaterThanOrEqualTo(5));
      final rows = [
        for (final (i, l) in lines.indexed)
          IngredientMatchRow(
            recipeId: r.id,
            position: i,
            raw: l.raw,
            fdcId: null,
            description: null,
            dataType: null,
            confidence: 0,
            grams: null,
            gramSource: null,
            status: 'auto',
          ),
      ];
      final families =
          <String, (void Function(), int Function(), void Function())>{
            'plusPartOf': (
              () => [for (final l in lines) plusPartOf(l.raw)],
              () => plusPartReads,
              () => plusPartReads = 0,
            ),
            'lineKeyOf': (
              () => lines.forEach(lineKeyOf),
              () => keyReads,
              () => keyReads = 0,
            ),
            // The rows' own keys ([_keyOfRaw]): no line to key, only rows.
            'rawKeys': (
              () => pairRowsToLines(rows, const []),
              () => keyReads,
              () => keyReads = 0,
            ),
            // v29 (Run 059 O9): the naming scan compiles no pattern (it
            // visits the steps' words), so the patterns are read directly
            // for every line's head of the recipe.
            '_namesOf': (
              () {
                final r = loadCorpusRecipe(chicken);
                for (final l in nutritionLines(r)) {
                  namesForTest(
                    r.steps.first.text,
                    normalizeItem(lineItemOf(l)),
                  );
                }
              },
              () => stepIndexCounts['names'] ?? 0,
              stepIndexCounts.clear,
            ),
          };
      addTearDown(() => memoCapForTest = null);
      for (final MapEntry(key: name, value: (read, reads, reset))
          in families.entries) {
        memoCapForTest = null;
        expect(twice(read, reads, reset), 0, reason: '$name keeps');
        memoCapForTest = 0;
        expect(
          twice(read, reads, reset),
          greaterThan(0),
          reason: '$name clears',
        );
      }
    });

    // Typed lines (a stated exception: no corpus key mixes a line bought in
    // the shell with a plain one — the O16/S19 verifiers surveyed all
    // 13,615), each matched by its recorded answer (mussels, FDC 2706350).
    Future<(SaltDatabase, String)> mussels([
      String tag = '',
      int? serves,
    ]) async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      for (final (id, raws) in [
        ('a', ['2 pounds mussels, scrubbed and debearded']),
        ('b', ['1 pound mussels']),
        ('c', ['3 pounds mussels', '1 pound mussels']),
        ('d', ['2 pounds mussels']),
      ]) {
        await matchAndCompute(
          db,
          provider,
          wp.saveLines(db, raws, id: '$id$tag', serves: serves),
        );
      }
      final key = db.ingredientMatchesFor('b$tag').single.itemKey!;
      return (db, key);
    }

    List<String> at(List<IngredientMatchRow> rows) => [
      for (final row in rows) '${row.recipeId}${row.position}',
    ];

    test("O16/S19: the reach memo's text answer is per RAW (a mixed reach "
        'keeps the plain lines and drops the shell line, whichever is read '
        'first), and its walks are per food and per excluded line', () async {
      final (db, key) = await mussels();
      final memo = ReachMemo();
      List<IngredientMatchRow> reach(int position, [int? fdcId]) =>
          decisionReach(
            db,
            key,
            excluding: (recipeId: 'c', position: position),
            fdcId: fdcId,
            memo: memo,
          );
      expect(at(reach(0)), ['b0', 'c1', 'd0']);
      expect(at(reach(1)), ['b0', 'c0', 'd0']);
      // The same food at 0.99 is no other food: nothing to apply.
      expect(at(reach(0, 2706350)), isEmpty);
    });

    test("S21: the reach's holds by version clear whole past the cap (1 "
        'here) and keep below it — each on its own recipes (the memo is '
        'process-wide by content hash, and a hit never clears)', () async {
      Future<int> secondRequest(String tag, int serves) async {
        // The helper's content hash is the lines' (and serves'): each
        // call its own versions.
        final (db, key) = await mussels(tag, serves);
        int request() {
          reachHoldReads = 0;
          decisionReach(
            db,
            key,
            excluding: (recipeId: 'c$tag', position: 0),
            memo: ReachMemo(),
          );
          return reachHoldReads;
        }

        expect(request(), 3);
        return request();
      }

      addTearDown(() => memoCapForTest = null);
      expect(await secondRequest('-kept', 1), 0);
      memoCapForTest = 1;
      expect(await secondRequest('-cleared', 2), 3);
    });
  }, skip: skipIfNoCorpus);
}

/// v59 (M60, verifier 2 D1/D2): the step readers a matched FOOD gates —
/// rule B1's drip on a bacon row (FDC 168277), P7a's peel on a produce
/// record (FDC 2685570) — at the caps. The end-to-end shapes above run on
/// [_NoHits], so no row sits on either food; these put every line on its
/// recorded answer (0652's bacon, 0706's butternut squash). Synthesized, a
/// stated exception: the hostile lines and steps (verifier 2's shapes).
const scallops = '0652-grilled-bacon-wrapped-scallops.yaml';
const squash =
    '0706-roasted-butternut-squash-with-browned-butter-and-hazelnuts.yaml';

final Map<String, Recipe Function()> foodShapes = {
  // D1: 98 lays of bacon a sentence over nothing (7 s a compute per bacon
  // line at v59 r1), then a lay over the loaf and a bake — the bacon
  // drips, so the GET reads the drip flag.
  'bacon-drips': () => capped(
    loadCorpusRecipe(scallops),
    List.filled(capLines, '12 slices bacon'),
    [
      ...List.filled(
        capSteps - 1,
        fill('${'lay bacon ' * 98}lay bacon. ', capStep),
      ),
      'Arrange the bacon over the loaf. Bake the loaf until crisp.',
    ],
  ),
  // D1: wraps with no bacon within three words (17 s a 20-line compute at
  // v59 r1).
  'bacon-wrap': () => capped(
    loadCorpusRecipe(scallops),
    List.filled(capLines, '12 slices bacon'),
    List.filled(capSteps, fill('${'wrap with a b c d ' * 50}bacon. ', capStep)),
  ),
  // D2: every sentence names the squash (17.7 s a compute at v59 r1 on
  // the shorter "Cut squash." sentences).
  'peel': () => capped(
    loadCorpusRecipe(squash),
    List.filled(capLines, '1 large (2½- to 3-pound) butternut squash'),
    List.filled(capSteps, fill('Cut the squash into large pieces. ', capStep)),
  ),
};

/// The lay and wrap regexes [baconLayWrapForTest]'s one pass replaced (v59
/// r1), the reference its answers are compared with.
final _layRegex = RegExp(
  r'\b(?:arrang(?:e[sd]?|ing)|lay(?:s|ing)?|drap(?:e[sd]?|ing)|'
  r'shingl(?:e[sd]?|ing))\b[^.]*?\bbacon\b[^.;]*?\bover\s+([^,.;]+)',
);

/// The v68 stir gate [stirsGibletsBackForTest]'s three finds replaced (v70,
/// Run 064's critic: two greedy `[^.]*` in sequence, cubic), the reference.
final _stirsRegex = RegExp(r'\bstir\b[^.]*\bgiblets\b[^.]*\binto\b');
final _wrapRegex = RegExp(
  r'\bwrap(?:s|ped|ping)?\b[^.]*?\b(?:with|in)\s+(?:[\w-]+\s+){0,3}?bacon\b',
);

void foodGated() {
  group('RULE C, the food-gated step readers (v59 verifier 2 D1/D2), '
      'corpus-free', () {
    test('D1: the lay and wrap readers answer as the regexes they replaced '
        '(30,000 seeded sentences over their own words) and read the cap '
        "shapes' 2,500-odd hostile sentences in one pass each (the regexes: "
        '6.9 s and 0.8 s)', () {
      const atoms = [
        'lay', 'arranging', 'bacon', 'over', 'x', 'loaf', 'towels', ';', //
        '.', ',', 'wrap', 'with', 'in', '  ', '\n',
      ];
      var over = 0;
      var wrap = 0;
      for (var seed = 0; seed < 30000; seed++) {
        final r = Random(seed);
        final b = StringBuffer();
        for (var i = 0, n = 1 + r.nextInt(14); i < n; i++) {
          b.write(atoms[r.nextInt(atoms.length)]);
          if (r.nextInt(3) > 0) {
            b.write(' ');
          }
        }
        final s = b.toString();
        final reference = (_layRegex.firstMatch(s)?[1], _wrapRegex.hasMatch(s));
        expect(baconLayWrapForTest(s), reference, reason: '"$s"');
        if (reference.$1 != null) {
          over++;
        }
        if (reference.$2) {
          wrap++;
        }
      }
      // Not vacuous: both readers fire on the fuzz.
      expect(over, greaterThan(50));
      expect(wrap, greaterThan(50));
      final hostile = [
        for (final unit in [
          '${'lay bacon ' * 98}lay bacon. ',
          '${'wrap with a b c d ' * 50}bacon. ',
        ])
          for (var i = 0; i < capSteps; i++)
            ...fill(unit, capStep).split(RegExp(r'(?<=\.)\s+')),
      ];
      expect(hostile.length, greaterThan(2400));
      final sw = Stopwatch()..start();
      for (final s in hostile) {
        expect(baconLayWrapForTest(s), (null, false));
      }
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });

  group('RULE C, the food-gated step readers at the caps (v59 verifier 2 '
      'D1/D2)', () {
    for (final shape in foodShapes.keys) {
      test(
        '$shape: the compute and the matches GET read the reader once per '
        'index, every family within its bounds, under the backstop',
        () async {
          final r = foodShapes[shape]!();
          final db = wp.tempDb();
          final provider = FixtureProvider(pending: pendingSearches);
          if (shape == 'bacon-drips') {
            // Computed first: its deli-ham line caches the one answer
            // holding 168322, the cooked bacon rule B1 writes (as
            // nutrition_v59_test).
            final ham = loadCorpusRecipe(
              '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
            );
            wp.saveRecipe(db, ham);
            await matchAndCompute(
              db,
              provider,
              db.recipeByIdOrSlug(ham.id)!.recipe,
            );
          }
          wp.saveRecipe(db, r);
          Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
          for (final (name, run) in <(String, Future<Object?> Function())>[
            ('compute', () => matchAndCompute(db, provider, stored())),
            ('GET', () => matchesBody(db, provider, stored())),
          ]) {
            stepIndexCounts.clear();
            reachDecodes = 0;
            final sw = Stopwatch()..start();
            await run();
            final ms = sw.elapsedMilliseconds;
            final counts = Map.of(stepIndexCounts);
            final indexes = counts['indexes'] ?? 1;
            expectBounded(r, counts, '$shape $name', copies: indexes);
            // The GET reads the drip only for a drip row's flag.
            final reads = [
              if (shape == 'peel') ...[
                'memo:paredIn',
                'memo:peelActs',
              ] else if (name == 'compute' || shape == 'bacon-drips') ...[
                'memo:baconDrips',
                'memo:baconKept',
              ],
            ];
            for (final family in reads) {
              expect(
                counts[family],
                inInclusiveRange(1, indexes),
                reason: '$shape $name $family',
              );
            }
            expect(ms, lessThan(backstopMs), reason: '$shape $name: $counts');
          }
          final rows = db.ingredientMatchesFor(r.id);
          expect(rows, hasLength(capLines));
          expect(
            {for (final row in rows) row.fdcId},
            {if (shape == 'peel') 2685570 else rawBaconFdcId},
          );
          // The drip read: B1's two parts, no fat kept.
          expect(
            rows.first.parts,
            shape == 'bacon-drips' ? contains('"grams":0.0') : isNull,
          );
        },
      );
    }

    test('D2: 400 distinct heads on the squash record (lineGrams), every '
        'sentence a paring one naming two of them with a smaller count — '
        "each head's reading derived once, the steps' acts once, the naming "
        'inversion once', () async {
      final record = (await FixtureProvider().food(2685570))!;
      final text = [
        for (var i = 0; i < capLines; i += 2)
          'Peel 1 ${food(i)} and 1 ${food(i + 1)}. ',
      ].join();
      final r = capped(
        loadCorpusRecipe(squash),
        [for (var i = 0; i < capLines; i++) '2 ${food(i)}'],
        List.filled(capSteps, (text * 10).substring(0, capStep)),
      );
      final db = wp.tempDb();
      stepIndexCounts.clear();
      final sw = Stopwatch()..start();
      for (final line in nutritionLines(r)) {
        expect(stepsPeelIn(r, line), isFalse);
        lineGrams(db, line, record, recipe: r);
      }
      final ms = sw.elapsedMilliseconds;
      final counts = Map.of(stepIndexCounts);
      expectBounded(r, counts, 'distinct heads');
      expect(counts['memo:paredIn'], capLines);
      expect(counts['memo:peelActs'], 1);
      expect(counts['memo:namingAll'], 1);
      expect(ms, lessThan(backstopMs), reason: '$counts');
    });
  }, skip: skipIfNoCorpus);
}

/// Recorded answers, and no search hit for the synthesized lines.
class _NoHits extends FixtureProvider {
  _NoHits() : super(pending: pendingSearches);
  @override
  Future<List<FdcCandidate>> search(String q) async => const [];
}

/// v60 (M61, verifier 2 D1): the matches GET re-ran M52's plan for EVERY
/// row, each plan weighing every frying oil — O(oils²) at the caps (a dough
/// M61 fries: 6.4 s at v59, 636 s at v60 r2; the shipped counted-pork fry
/// 818 s at both); the GET's [ResolverMemo] now holds one plan. One counted
/// line, 399 frying oils, every sentence a frying one (verifiers 1 and 2's
/// probe shapes) on 0241 with its recorded answers; the grams each oil
/// counts. Synthesized, a stated exception: the hostile lines and steps.
final Map<String, (Recipe Function(), String)> fryShapes = {
  'dough': (
    () => capped(
      loadCorpusRecipe(pork),
      [
        '4½ cups (22½ ounces) all-purpose flour',
        for (var i = 1; i < capLines; i++) '2 quarts vegetable oil for frying',
      ],
      List.filled(capSteps, fill('Fry the dough in the hot oil. ', capStep)),
    ),
    // RE-PIN (M67 batch, v66): 0.37 → a bare dough with no yeast row reads
    // B's cake doughnut, 14.15 % (23.32 before): 637.86 g × 14.15 % shared
    // by the 399 oils.
    '0.23',
  ),
  'pork-fry': (
    () => capped(
      loadCorpusRecipe(pork),
      [
        '1 pound ground pork',
        for (var i = 1; i < capLines; i++) '2 quarts vegetable oil for frying',
      ],
      List.filled(capSteps, fill('Fry the pork in the hot oil. ', capStep)),
    ),
    '0.08',
  ),
};

void fryingOils() {
  group(
    'RULE C, the frying oils at the caps (v60 verifier 2 D1)',
    () {
      for (final shape in fryShapes.keys) {
        test('$shape: the compute and the matches GET within their bounds, '
            'the GET planning M52 once; every oil confirmed, the GET once and '
            'the compute at most twice; each under the backstop', () async {
          final (make, grams) = fryShapes[shape]!;
          final r = make();
          final db = wp.tempDb();
          final provider = FixtureProvider(pending: pendingSearches);
          wp.saveRecipe(db, r);
          Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
          for (final (name, run) in <(String, Future<Object?> Function())>[
            ('compute', () => matchAndCompute(db, provider, stored())),
            ('GET', () => matchesBody(db, provider, stored())),
          ]) {
            stepIndexCounts.clear();
            reachDecodes = 0;
            m52PlanRuns = 0;
            final sw = Stopwatch()..start();
            await run();
            final ms = sw.elapsedMilliseconds;
            final counts = Map.of(stepIndexCounts);
            expectBounded(
              r,
              counts,
              '$shape $name',
              copies: counts['indexes'] ?? 1,
            );
            if (name == 'GET') {
              expect(m52PlanRuns, 1, reason: shape);
            }
            // Each oil's grams read the skin sentences once per index.
            expect(
              counts['memo:skinSentences'],
              inInclusiveRange(1, counts['indexes'] ?? 1),
              reason: '$shape $name',
            );
            expect(ms, lessThan(backstopMs), reason: '$shape $name: $counts');
          }
          final rows = db.ingredientMatchesFor(r.id);
          expect(rows, hasLength(capLines));
          expect(
            {
              for (final row in rows.skip(1)) row.grams?.toStringAsFixed(2),
            },
            {grams},
          );
          // verify3 D1 (closer 3): every oil CONFIRMED by a person — the
          // GET derived each through [_m52OnConfirm]'s own plan (v59 15.9 s,
          // v60 35.6 s on the dough). Row 1 through the real PUT, which
          // changes the status alone (the plan's grams kept); the other
          // 398 written in that state (398 PUTs would take minutes).
          await applyMatchOverride(db, provider, stored(), 1, {
            'raw': rows[1].raw,
            'confirmed': true,
          });
          final put = db.ingredientMatchesFor(r.id);
          expect(
            sameMatchRow(put[1], rows[1].copyWith(status: 'confirmed')),
            isTrue,
            reason: shape,
          );
          for (final row in put.skip(2)) {
            db.upsertIngredientMatch(
              row.copyWith(status: 'confirmed', derivedSeq: put[1].derivedSeq),
            );
          }
          stepIndexCounts.clear();
          reachDecodes = 0;
          m52PlanRuns = 0;
          final sw = Stopwatch()..start();
          final body = await matchesBody(db, provider, stored());
          final ms = sw.elapsedMilliseconds;
          final counts = Map.of(stepIndexCounts);
          expectBounded(
            r,
            counts,
            '$shape GET confirmed',
            copies: counts['indexes'] ?? 1,
          );
          expect(m52PlanRuns, 1, reason: '$shape GET confirmed');
          expect(ms, lessThan(backstopMs), reason: '$shape GET confirmed');
          final items = (body['items']! as List).cast<Map<String, Object?>>();
          expect(
            {
              for (final item in items.skip(1))
                (
                  (item['match']! as Map)['status'],
                  ((item['match']! as Map)['grams'] as num?)?.toStringAsFixed(
                    2,
                  ),
                ),
            },
            {('confirmed', grams)},
            reason: shape,
          );
          // v61 closer 1 (verify1 D1's class): the COMPUTE derived every
          // confirmed oil through its own plan (dough 34.5 s, pork-fry
          // 20.5 s, 400 plans); now from one plan while the rows key alike
          // (engine `_m52OnConfirm`'s compute memo), then the totals'.
          stepIndexCounts.clear();
          reachDecodes = 0;
          m52PlanRuns = 0;
          final computing = Stopwatch()..start();
          await matchAndCompute(db, provider, stored());
          final computeMs = computing.elapsedMilliseconds;
          final computeCounts = Map.of(stepIndexCounts);
          expectBounded(
            r,
            computeCounts,
            '$shape compute confirmed',
            copies: computeCounts['indexes'] ?? 1,
          );
          expect(
            m52PlanRuns,
            lessThanOrEqualTo(2),
            reason: '$shape compute confirmed',
          );
          expect(
            computeMs,
            lessThan(backstopMs),
            reason: '$shape compute confirmed',
          );
          expect(
            {
              for (final row in db.ingredientMatchesFor(r.id).skip(1))
                (row.status, row.grams?.toStringAsFixed(2)),
            },
            {('confirmed', grams)},
            reason: shape,
          );
        });
      }
    },
    skip: skipIfNoCorpus,
  );
}

/// v66 (M67 A2): a rolled dough the steps cut at the caps — 399 dough
/// lines (the yeasted doughnuts' real flour line) before one frying oil,
/// every step printing the sheet, the count and the round cutter: each
/// dough line a planned position (`discarded` at the cut share, 416.20 g of
/// 637.86), the sheet read once per index (`memo:cutShare`), the GET
/// planning M52 once; every dough line CONFIRMED, the GET once and the
/// compute at most twice (`_m52OnConfirm`'s memos key the mix positions).
/// Synthesized, a stated exception: the repeated lines and steps.
void cutDough() {
  group('RULE C, a cut dough at the caps (v66, M67 A2)', () {
    test('the compute and the matches GET within their bounds, the GET '
        'planning M52 once; every dough line confirmed, the GET once and the '
        'compute at most twice; each under the backstop', () async {
      const flour = '4½ cups (22½ ounces) all-purpose flour';
      final r = capped(
        loadCorpusRecipe('1105-yeasted-doughnuts.yaml'),
        [
          for (var i = 0; i < capLines - 1; i++) flour,
          '2 quarts vegetable oil for frying',
        ],
        List.filled(
          capSteps,
          fill(
            'Roll dough into 10 by 13-inch rectangle, about ½ inch thick. Using 3-inch round cutter dipped in flour, cut 12 rounds. Fry the doughnuts in the hot oil. ',
            capStep,
          ),
        ),
      );
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      wp.saveRecipe(db, r);
      Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
      Future<void> timed(
        String name,
        Future<Object?> Function() run, {
        int? plans,
      }) async {
        stepIndexCounts.clear();
        reachDecodes = 0;
        m52PlanRuns = 0;
        final sw = Stopwatch()..start();
        await run();
        final ms = sw.elapsedMilliseconds;
        final counts = Map.of(stepIndexCounts);
        final copies = counts['indexes'] ?? 1;
        expectBounded(r, counts, 'cut dough $name', copies: copies);
        expect(
          counts['memo:cutShare'],
          inInclusiveRange(1, copies),
          reason: 'cut dough $name',
        );
        if (plans != null) {
          expect(m52PlanRuns, lessThanOrEqualTo(plans), reason: name);
        }
        expect(ms, lessThan(backstopMs), reason: 'cut dough $name: $counts');
      }

      await timed('compute', () => matchAndCompute(db, provider, stored()));
      await timed('GET', () => matchesBody(db, provider, stored()), plans: 1);
      final rows = db.ingredientMatchesFor(r.id);
      expect(rows, hasLength(capLines));
      expect(
        {
          for (final row in rows.take(capLines - 1))
            (row.grams, row.gramSource),
        },
        {(416.2, 'discarded')},
      );
      // Row 0 through the real PUT; the other 398 written in that state.
      await timed(
        'PUT',
        () => applyMatchOverride(db, provider, stored(), 0, {
          'raw': flour,
          'confirmed': true,
        }),
      );
      final put = db.ingredientMatchesFor(r.id);
      expect(
        sameMatchRow(put[0], rows[0].copyWith(status: 'confirmed')),
        isTrue,
      );
      for (final row in put.skip(1).take(capLines - 2)) {
        db.upsertIngredientMatch(
          row.copyWith(status: 'confirmed', derivedSeq: put[0].derivedSeq),
        );
      }
      await timed(
        'GET confirmed',
        () => matchesBody(db, provider, stored()),
        plans: 1,
      );
      await timed(
        'compute confirmed',
        () => matchAndCompute(db, provider, stored()),
        plans: 2,
      );
      expect(
        {
          for (final row in db.ingredientMatchesFor(r.id).take(capLines - 1))
            (row.status, row.grams, row.gramSource),
        },
        {('confirmed', 416.2, 'discarded')},
      );
    });
  }, skip: skipIfNoCorpus);
}

/// v67 (M69, closer 1 — verify1 D2/D3): M69's two step readers at the
/// caps. THIN: Chicken Piccata (0418) with 389 more copies of its flour
/// line (every one a coat part at C4's one f), 115 steps of pounding
/// sentences that print no thickness before its own five (its "pound
/// cutlets to even ¼-inch thickness" in the last but two): `_poundsThin`
/// scans every sentence once per index (`memo:poundsThin`). VEGETABLE:
/// Eggplant Parmesan (0407) with 383 eggplant lines, each heavier than the
/// last (each the new largest), and 113 steps naming the eggplant before
/// its own seven: the coat sentence's naming test read once per head
/// (`memo:coatNamed`; per row it rescanned the head's sentences — 167 →
/// 2,135 ms recomputing, 440 → 4,179 ms for the GET). Each the compute, the
/// matches GET (planning M52 once) and the totals' recompute (once).
/// Synthesized, a stated exception: the repeated lines and steps.
void m69Coats() {
  group("RULE C, M69's step readers at the caps (v67)", () {
    Future<void> shape(
      String name,
      Recipe r,
      String family,
      void Function(List<IngredientMatchRow>) reached, {
      // v80 (M80, CC7): the paths that must read [family] (the others
      // never — closer 1, verify1 D2: ONION QUIET's compute and recompute).
      Set<String> reading = const {'compute', 'GET', 'recompute'},
    }) async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      wp.saveRecipe(db, r);
      Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
      Future<void> timed(
        String step,
        Future<Object?> Function() run,
        int plans,
      ) async {
        stepIndexCounts.clear();
        reachDecodes = 0;
        m52PlanRuns = 0;
        final sw = Stopwatch()..start();
        await run();
        final ms = sw.elapsedMilliseconds;
        final counts = Map.of(stepIndexCounts);
        final copies = counts['indexes'] ?? 1;
        expectBounded(r, counts, '$name $step', copies: copies);
        expect(
          counts[family] ?? 0,
          reading.contains(step) ? inInclusiveRange(1, copies) : 0,
          reason: '$name $step',
        );
        expect(m52PlanRuns, lessThanOrEqualTo(plans), reason: '$name $step');
        expect(ms, lessThan(backstopMs), reason: '$name $step: $counts');
      }

      await timed('compute', () => matchAndCompute(db, provider, stored()), 2);
      reached(db.ingredientMatchesFor(r.id));
      await timed('GET', () => matchesBody(db, provider, stored()), 1);
      await timed('recompute', () async => recomputeTotals(db, stored()), 1);
    }

    test('THIN: the pound sentence read once per index, every flour line '
        'counted at the one f; each under the backstop', () async {
      final base = loadCorpusRecipe('0418-chicken-piccata.yaml');
      final own = [for (final g in base.ingredients) ...g.items];
      const flour = '½ cup unbleached all-purpose flour';
      await shape(
        'thin',
        capped(
          base,
          [
            for (final l in own) l.raw,
            for (var i = own.length; i < capLines; i++) flour,
          ],
          [
            for (var i = base.steps.length; i < capSteps; i++)
              fill(
                'Pound the cutlets, then pound them to an even thickness. ',
                capStep,
              ),
            for (final s in base.steps) s.text,
          ],
        ),
        'memo:poundsThin',
        (rows) => expect(
          {
            for (final row in rows)
              if (row.raw == flour) (row.gramSource, row.hold),
          },
          {('discarded', null)},
        ),
      );
    });

    test("VEGETABLE: the coat sentence's naming test read once per head, "
        'the eggplant the coated food; each under the backstop', () async {
      final base = loadCorpusRecipe('0407-eggplant-parmesan.yaml');
      final own = [for (final g in base.ingredients) ...g.items];
      await shape(
        'vegetable',
        capped(
          base,
          [
            for (final l in own) l.raw,
            for (var n = 3; own.length + n - 3 < capLines; n++)
              '$n pounds globe eggplant (2 medium eggplants), cut crosswise into ¼-inch-thick rounds',
          ],
          [
            for (var i = base.steps.length; i < capSteps; i++)
              fill('Slice the eggplant. ', capStep),
            for (final s in base.steps) s.text,
          ],
        ),
        'memo:coatNamed',
        (rows) => expect(
          (rows[5].raw, rows[5].gramSource, rows[5].hold),
          (own[5].raw, 'discarded', null),
        ),
      );
    });

    // v80 (M80-1, closer CC7): 'Onions,' joins [_coatVegetables] — the TRUE
    // path (a baked coated onion budgeted at 50.53) and the QUIET one (a
    // meatless recipe with a counted onion and a frying oil whose steps coat
    // nothing: `_m52Key` reads the naming memo whatever the coats, once per
    // head). Synthesized, a stated exception: the repeated lines and steps.
    test("ONION: the coat sentence's naming test read once per head, the "
        'onion the coated food (its coat and dips budgeted); each under the '
        'backstop', () async {
      final base = loadCorpusRecipe('0315-oven-fried-onion-rings.yaml');
      final own = [for (final g in base.ingredients) ...g.items];
      // closer 1: the shape adds 390 ring lines.
      expect(own, hasLength(10));
      await shape(
        'onion',
        capped(
          base,
          [
            for (final l in own) l.raw,
            for (var n = 3; own.length + n - 3 < capLines; n++)
              '$n large yellow onions, cut into 24 large rings',
          ],
          [
            for (var i = base.steps.length; i < capSteps; i++)
              fill('Slice the onions. ', capStep),
            for (final s in base.steps) s.text,
          ],
        ),
        'memo:coatNamed',
        (rows) => expect(
          {
            for (final p in [1, 6, 7]) (rows[p].gramSource, rows[p].hold),
          },
          {('discarded', null)},
        ),
      );
    });

    test('ONION QUIET: falafel (0570, 17 lines) with 383 more onion lines '
        "under steps that coat nothing — the GET's M52 key reads the naming "
        'memo once per head (no coat sentence names the onion), the compute '
        'and the recompute never; the onions counted; each under the '
        'backstop', () async {
      final base = loadCorpusRecipe('0570-falafel.yaml');
      final own = [for (final g in base.ingredients) ...g.items];
      // closer 1 (verify1 D2): two groups, 12 + 5 — the shape adds 383.
      expect(own, hasLength(17));
      expect(own[3].raw, '½ onion, chopped fine (½ cup)');
      await shape(
        'onion quiet',
        capped(
          base,
          [
            for (final l in own) l.raw,
            for (var n = 2; own.length + n - 2 < capLines; n++)
              '$n onions, chopped fine',
          ],
          [
            for (var i = base.steps.length; i < capSteps; i++)
              fill('Chop the onions. ', capStep),
            for (final s in base.steps) s.text,
          ],
        ),
        'memo:coatNamed',
        (rows) => expect(
          {
            for (final row in rows.skip(own.length))
              (row.description, row.hold),
          },
          {('Onions, yellow, raw', null)},
        ),
        reading: const {'GET'},
      );
    });
  }, skip: skipIfNoCorpus);
}

/// v70 (review Run 063/064 F1, F2): the step readers the review timed at
/// the caps. GIBLETS (F1, Run 064 O2's shape): 0154's Giblet Pan Gravy
/// with 389 more copies of its "Reserved turkey giblets, neck, and
/// tailpiece" line (400) and 113 steps of 10,000 characters before its own
/// seven (120) — the stir gate read once per index (`memo:stirsGiblets`),
/// the bird once per section instance (`memo:hostBird`, off the host the
/// section was built from — no per-line decode: compute 32.7 s, the GET
/// 8.9 s, a freshness check 8.0 s before); LONG (Run 064's critic): the
/// same 400 lines under 120 steps of 988-character sentences naming "stir"
/// and "giblets" with no "into" (the v68 regex was cubic: 6.35 s a scan);
/// SET-ASIDE (F2, Run 063 S8's shape): 0148 with 400 "3 onions, chopped"
/// lines under 120 steps of "Set aside 2 pear halves for other use." (the
/// name test before the parse, once per head: `memo:setAsideLine`). Each
/// the compute, the matches GET, the recompute and the freshness check.
/// Synthesized, a stated exception: the repeated lines and steps.
void review70() {
  group('RULE C, the giblet stir gate (v70 verify1 D1), corpus-free', () {
    test('D1: the stir gate answers as the v68 regex it replaced (30,000 '
        "seeded sentences over its own words) and reads Run 064's critic's "
        '1,200 hostile 988-character sentences in one pass (the regex: '
        '6.2 s)', () {
      const atoms = [
        'stir', 'stirring', 'giblets', 'giblet', 'into', 'in', 'to', //
        '.', '1.5', 'x', ',', '  ', '\n', 'the',
      ];
      var hits = 0;
      for (var seed = 0; seed < 30000; seed++) {
        final r = Random(seed);
        final b = StringBuffer();
        for (var i = 0, n = 1 + r.nextInt(12); i < n; i++) {
          b.write(atoms[r.nextInt(atoms.length)]);
          if (r.nextInt(3) > 0) {
            b.write(' ');
          }
        }
        final s = b.toString();
        final reference = _stirsRegex.hasMatch(s);
        expect(stirsGibletsBackForTest(s), reference, reason: '"$s"');
        if (reference) {
          hits++;
        }
      }
      // Not vacuous: the gate fires on the fuzz.
      expect(hits, greaterThan(50));
      // The critic's input: 120 steps × 10 sentences of 988 characters
      // naming "stir" and "giblets", no "into".
      final hostile = List.filled(
        1200,
        '${('stir giblets ' * 76).substring(0, 987)}.',
      );
      final sw = Stopwatch()..start();
      for (final s in hostile) {
        expect(stirsGibletsBackForTest(s), isFalse);
      }
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });

  group(
    'RULE C, the review Run 063/064 readers at the caps (v70)',
    () {
      Future<void> shape(
        String name,
        Recipe host,
        String? section,
        List<String> families,
        void Function(SaltDatabase, String) reached,
      ) async {
        final db = wp.tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        wp.saveRecipe(db, host);
        final key = section == null ? host.id : sectionKeyOf(host.id, section);
        Recipe stored() => nutritionRecipeOf(db, key)!.recipe;
        Future<void> timed(String step, Future<Object?> Function() run) async {
          stepIndexCounts.clear();
          final sw = Stopwatch()..start();
          await run();
          final ms = sw.elapsedMilliseconds;
          final counts = Map.of(stepIndexCounts);
          final copies = counts['indexes'] ?? 1;
          expectBounded(stored(), counts, '$name $step', copies: copies);
          for (final family in families) {
            expect(
              counts[family] ?? 0,
              lessThanOrEqualTo(copies),
              reason: '$name $step $family',
            );
          }
          expect(ms, lessThan(backstopMs), reason: '$name $step: $counts');
        }

        await timed('compute', () => matchAndCompute(db, provider, stored()));
        reached(db, key);
        await timed('GET', () => matchesBody(db, provider, stored()));
        await timed('recompute', () async => recomputeTotals(db, stored()));
        await timed('fresh', () async => nutritionIsFresh(db, stored()));
      }

      Recipe gravyAtCaps(String step) {
        final host = loadCorpusRecipe('0154-classic-roast-turkey.yaml');
        return host.copyWith(
          subsections: [
            for (final s in host.subsections)
              if (s.title == 'Giblet Pan Gravy')
                s.copyWith(
                  ingredients: [
                    IngredientGroup(
                      items: [
                        for (final g in s.ingredients!) ...g.items,
                        for (var i = 0; i < 389; i++)
                          ln('Reserved turkey giblets, neck, and tailpiece'),
                      ],
                    ),
                  ],
                  steps: [
                    for (var i = s.steps!.length; i < capSteps; i++)
                      RecipeStep(number: i + 1, text: fill(step, capStep)),
                    ...s.steps!,
                  ],
                )
              else
                s,
          ],
        );
      }

      void gibletsWeighed(SaltDatabase db, String key) => expect(
        {
          for (final m in db.ingredientMatchesFor(key))
            if (m.raw.startsWith('Reserved turkey giblets'))
              (m.grams?.toStringAsFixed(2), m.gramSource),
        },
        {('291.37', 'weight')},
      );

      test('GIBLETS: the stir gate once per index, the bird once per section '
          'instance; each under the backstop', () async {
        await shape(
          'giblets',
          gravyAtCaps('stir the gravy and '),
          'Giblet Pan Gravy',
          ['memo:stirsGiblets', 'memo:hostBird'],
          gibletsWeighed,
        );
      });

      test('LONG: 988-character sentences of "stir" and "giblets" with no '
          '"into" — the gate linear; each under the backstop', () async {
        final sentence = '${'stir giblets ' * 75}stir.  ';
        expect(sentence.trim().length, lessThan(maxScannedSentence));
        final host = gravyAtCaps(sentence);
        await shape(
          'long',
          host.copyWith(
            subsections: [
              for (final s in host.subsections)
                s.title == 'Giblet Pan Gravy'
                    ? s.copyWith(
                        steps: [
                          for (var i = 0; i < capSteps; i++)
                            RecipeStep(
                              number: i + 1,
                              text: fill(sentence, capStep),
                            ),
                        ],
                      )
                    : s,
            ],
          ),
          'Giblet Pan Gravy',
          ['memo:stirsGiblets', 'memo:hostBird'],
          (db, key) => expect(
            {
              for (final m in db.ingredientMatchesFor(key))
                if (m.raw.startsWith('Reserved turkey giblets'))
                  (m.grams, m.gramSource),
            },
            {(0.0, 'unmeasured')},
          ),
        );
      });

      test('SET-ASIDE: the name test before the parse, once per head; each '
          'under the backstop', () async {
        await shape(
          'set-aside',
          capped(
            loadCorpusRecipe(chicken),
            [for (var i = 0; i < capLines; i++) '3 onions, chopped'],
            List.filled(
              capSteps,
              fill('Set aside 2 pear halves for other use. ', capStep),
            ),
          ),
          null,
          ['memo:setAsideLine'],
          (db, key) => expect(
            {for (final m in db.ingredientMatchesFor(key)) m.gramSource},
            isNot(contains('discarded')),
          ),
        );
      });
    },
    skip: skipIfNoCorpus,
  );
}

/// v61 (M62): an egg or buttermilk dip at the caps — every sentence a
/// mixing one and a dip one, 398 dip lines beside one coat: the dip lines
/// are read once per base word (engine `_dipsOf`, `memo:dips`, never a scan
/// of the earlier steps per dip sentence), the plan once per GET with every
/// dip decided (`m52PlanRuns`), a person's pick of a dip planning no other
/// dip, the coat's shape read once per recipe and coated record
/// (`memo:coatShape`), the dips a plan weighs counted (`dipsSized`). E-w
/// on 0114 (the breast's coat; each confirm), the same lines with every
/// other dip picked (each pick's plan weighs no other dip — 4.6 s of
/// per-pick plans weighing the 199 others, before), H on 0315 (no coated
/// meat: every dip held). v61 closer 1 (verify1 D1, D2): a COMPUTE with
/// every dip decided plans M52 at most twice (its confirms' one plan
/// `_m52OnConfirm` keys, and the totals') — every dip confirmed took 16.2 s
/// and 399 plans; also as v60 left the confirmed eggs (counted whole: the
/// first compute after the deploy); every dip CONFIRMED with no coat at
/// all, beside a frying oil (the D5 flag only: the GET planned once per
/// dip, 399 plans); and M58 W's batter on the same lines, every batter line
/// confirmed (its compute 44.3 s at v60, 20.8 s before this closer). Real
/// corpus lines and recipes with their recorded answers; synthesized, a
/// stated exception: the hostile steps and the repeated lines.
final Map<String, (Recipe Function(), Map<String, Object?>)> dipShapes = {
  for (final (name, decision) in [
    ('egg-dips', <String, Object?>{'confirmed': true}),
    ('egg-picks', <String, Object?>{'fdc_id': 748967}),
  ])
    name: (
      () => capped(
        loadCorpusRecipe('0114-breaded-chicken-cutlets.yaml'),
        [
          '4 (5- to 6-ounce) boneless, skinless chicken breasts, tenderloins removed and breasts trimmed',
          '¾ cup unbleached all-purpose flour',
          for (var i = 2; i < capLines; i++) '2 large eggs',
        ],
        List.filled(
          capSteps,
          fill(
            'Whisk the eggs in a pie plate. Dredge the cutlets in the flour, then dip in the egg mixture, allowing the excess to drip off. Fry the cutlets until golden. ',
            capStep,
          ),
        ),
      ),
      decision,
    ),
  'flag-dips': (
    () => capped(
      loadCorpusRecipe('0114-breaded-chicken-cutlets.yaml'),
      [
        '4 (5- to 6-ounce) boneless, skinless chicken breasts, tenderloins removed and breasts trimmed',
        '2 quarts vegetable oil, for frying',
        for (var i = 2; i < capLines; i++) '2 large eggs',
      ],
      List.filled(
        capSteps,
        fill(
          'Whisk the eggs in a pie plate. Dip the cutlets in the egg mixture, allowing the excess to drip off. Heat the oil in a Dutch oven to 350 degrees. Fry the cutlets in the oil until golden. ',
          capStep,
        ),
      ),
    ),
    {'confirmed': true},
  ),
  'w-batter': (
    () => capped(
      loadCorpusRecipe('0114-breaded-chicken-cutlets.yaml'),
      [
        '4 (5- to 6-ounce) boneless, skinless chicken breasts, tenderloins removed and breasts trimmed',
        '¾ cup unbleached all-purpose flour',
        for (var i = 2; i < capLines; i++) '2 large eggs',
      ],
      List.filled(
        capSteps,
        fill(
          'Whisk the eggs and flour into a batter. Dredge the cutlets in the flour, shaking off the excess. Dip the cutlets in the batter, allowing the excess batter to drip off. Fry the cutlets until golden. ',
          capStep,
        ),
      ),
    ),
    {'confirmed': true},
  ),
  // RE-PIN (M80 batch, v80, M80-1): a baked coated onion is budgeted at
  // 50.53 since v80, so the held shape FRIES its rings ("Fry the onion
  // rings" for "Bake the onion rings"): a fried coated onion reads no figure
  // and the coat holds with its 398 dips (M62 H at the caps, as before).
  'held-dips': (
    () => capped(
      loadCorpusRecipe('0315-oven-fried-onion-rings.yaml'),
      [
        '½ cup unbleached all-purpose flour',
        '2 large yellow onions, cut into 24 large rings',
        for (var i = 2; i < capLines; i++) '1 large egg, at room temperature',
      ],
      List.filled(
        capSteps,
        fill(
          'Place the flour in a shallow baking dish. Beat the egg and buttermilk in a medium bowl. Dredge each onion ring in the flour, shaking off the excess. Dip in the buttermilk mixture, allowing the excess to drip back into the bowl. Fry the onion rings until golden brown. ',
          capStep,
        ),
      ),
    ),
    {'fdc_id': 748967},
  ),
};

void eggDips() {
  group('RULE C, the egg dips at the caps (v61, M62)', () {
    for (final shape in dipShapes.keys) {
      test('$shape: the compute, the matches GET and, every dip decided, the '
          'GET and the compute within their bounds, the dips read once per '
          'index, the GET planning M52 once and the compute at most twice, '
          'each under the backstop', () async {
        final (make, decision) = dipShapes[shape]!;
        final r = make();
        final db = wp.tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        wp.saveRecipe(db, r);
        Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
        Future<void> timed(
          String name,
          Future<Object?> Function() run, {
          int? plans,
        }) async {
          stepIndexCounts.clear();
          reachDecodes = 0;
          m52PlanRuns = 0;
          final sw = Stopwatch()..start();
          await run();
          final ms = sw.elapsedMilliseconds;
          final counts = Map.of(stepIndexCounts);
          final copies = counts['indexes'] ?? 1;
          expectBounded(r, counts, '$shape $name', copies: copies);
          expect(
            counts['memo:dips'],
            inInclusiveRange(1, copies),
            reason: '$shape $name',
          );
          if (plans != null) {
            expect(m52PlanRuns, lessThanOrEqualTo(plans), reason: shape);
          }
          expect(ms, lessThan(backstopMs), reason: '$shape $name: $counts');
        }

        await timed('compute', () => matchAndCompute(db, provider, stored()));
        await timed('GET', () => matchesBody(db, provider, stored()), plans: 1);
        final rows = db.ingredientMatchesFor(r.id);
        expect(rows, hasLength(capLines));
        expect(
          {for (final row in rows.skip(2)) (row.grams, row.hold)},
          switch (shape) {
            'held-dips' => {(null, 'coating')},
            'flag-dips' => {(100.0, null)},
            // RE-PIN (M82 batch, v84, C5a): the batter's flour at 5 oz a cup
            // re-solves each dip — was 7.91 (the counts unchanged).
            'w-batter' => {(7.7, null)},
            // RE-PIN (v82, review Run 067/068 F4): a dip sentence is no
            // mixing sentence ("dip in the egg mixture" — "mixture" read as
            // a mix before): the 398 identical egg lines take A13's nth
            // "egg" mention, alternately the whisk's and the dip's, so half
            // are the dip's (E-w's 0.21 g each on 199) and half are counted
            // whole (100.0 g); was every line the dip's at 0.11.
            _ => {(0.21, null), (100.0, null)},
          },
          reason: shape,
        );
        // Row 2 through the real PUT; the others written in that state
        // (397 PUTs would take minutes) — for egg-picks every other one.
        await timed(
          'PUT',
          () => applyMatchOverride(db, provider, stored(), 2, {
            'raw': rows[2].raw,
            ...decision,
          }),
        );
        final put = db.ingredientMatchesFor(r.id);
        for (final row in put.skip(3)) {
          if (shape == 'egg-picks' && row.position.isOdd) {
            continue;
          }
          db.upsertIngredientMatch(
            row.copyWith(status: put[2].status, derivedSeq: put[2].derivedSeq),
          );
        }
        await timed(
          'GET decided',
          () => matchesBody(db, provider, stored()),
          plans: 1,
        );
        // v61 closer 1 (verify1 D1): the compute's confirms and picks
        // answer from one plan while the rows key alike, then its totals.
        await timed(
          'compute decided',
          () => matchAndCompute(db, provider, stored()),
          plans: 2,
        );
        if (shape == 'egg-dips') {
          // The first compute after the deploy: every confirmed egg as v60
          // left it, counted whole — each derivation rewrites its row.
          for (final row in db.ingredientMatchesFor(r.id).skip(2)) {
            db.upsertIngredientMatch(
              row.copyWith(grams: 100, gramSource: GramSource.piece.name),
            );
          }
          await timed(
            'compute after the deploy',
            () => matchAndCompute(db, provider, stored()),
            plans: 2,
          );
        }
        expect(
          {
            for (final row in db.ingredientMatchesFor(r.id).skip(2))
              (row.status, row.grams, row.hold),
          },
          switch (shape) {
            // RE-PIN (v82, F4): the dip's half at E-w's 0.21 g, the half
            // counted whole 100.0 g (above); was every confirm at 0.11.
            'egg-dips' => {
              ('confirmed', 0.21, null),
              ('confirmed', 100.0, null),
            },
            'flag-dips' => {('confirmed', 100.0, null)},
            // RE-PIN (M82 batch, v84, C5a): as above — was 7.91.
            'w-batter' => {('confirmed', 7.7, null)},
            // The picked half counted whole. RE-PIN (v82, F4): the auto half
            // — the odd lines, whose A13 mention is the dip sentence, no
            // longer the dip's — counted whole too (was E-w's 0.21 g on its
            // 199 dips): the picks are the dip's lines.
            'egg-picks' => {('overridden', 100.0, null), ('auto', 100.0, null)},
            _ => {('overridden', null, 'coating')},
          },
          reason: shape,
        );
      });
    }

    // v61 closer 1: every frying oil confirmed BETWEEN the engine's dips or
    // coat lines, which a compute rewrites as it goes (each its engine form,
    // then the totals' plan form) — the fryer block reads neither, so its
    // key holds: one plan, not one per oil (18.0 and 18.2 s at v60).
    for (final (shape, line) in [
      ('oil between dips', '2 large eggs'),
      ('oil between coats', '¾ cup unbleached all-purpose flour'),
    ]) {
      test('$shape: every oil confirmed, the compute plans M52 at most twice '
          'within its bounds, under the backstop', () async {
        const oil = '2 quarts vegetable oil, for frying';
        final dips = shape == 'oil between dips';
        final r = capped(
          loadCorpusRecipe('0114-breaded-chicken-cutlets.yaml'),
          [
            '4 (5- to 6-ounce) boneless, skinless chicken breasts, tenderloins removed and breasts trimmed',
            if (dips) '¾ cup unbleached all-purpose flour',
            for (var i = dips ? 2 : 1; i < capLines; i++)
              i.isEven == dips ? line : oil,
          ],
          List.filled(
            capSteps,
            fill(
              '${dips ? 'Whisk the eggs in a pie plate. Dredge the cutlets in the flour, then dip in the egg mixture, allowing the excess to drip off.' : 'Dredge the cutlets in the flour, shaking off the excess.'} Heat the oil in a Dutch oven to 350 degrees. Fry the cutlets in the oil until golden. ',
              capStep,
            ),
          ),
        );
        final db = wp.tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        wp.saveRecipe(db, r);
        Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
        await matchAndCompute(db, provider, stored());
        final rows = db.ingredientMatchesFor(r.id);
        final at = rows.indexWhere((row) => row.raw == oil);
        await applyMatchOverride(db, provider, stored(), at, {
          'raw': oil,
          'confirmed': true,
        });
        final put = db.ingredientMatchesFor(r.id);
        for (final row in put) {
          if (row.raw == oil) {
            db.upsertIngredientMatch(
              row.copyWith(
                status: 'confirmed',
                derivedSeq: put[at].derivedSeq,
              ),
            );
          }
        }
        Set<(String, String, double?)> shown() => {
          for (final row in db.ingredientMatchesFor(r.id).skip(1))
            (row.status, row.raw, row.grams),
        };
        final before = shown();
        // RE-PIN (v82, F4): the eggs split as in dipShapes' egg-dips — the
        // dip's half (0.42 g each) and the half counted whole (100.0 g); was
        // one egg row form (3 forms).
        expect(before, hasLength(dips ? 4 : 2), reason: '$before');
        stepIndexCounts.clear();
        reachDecodes = 0;
        m52PlanRuns = 0;
        final sw = Stopwatch()..start();
        await matchAndCompute(db, provider, stored());
        final ms = sw.elapsedMilliseconds;
        final counts = Map.of(stepIndexCounts);
        expectBounded(r, counts, shape, copies: counts['indexes'] ?? 1);
        expect(m52PlanRuns, lessThanOrEqualTo(2), reason: shape);
        expect(ms, lessThan(backstopMs), reason: '$shape: $counts');
        expect(shown(), before, reason: shape);
      });
    }

    test('the making scan: 400 distinct heads, every sentence a mixing one '
        'naming two of them beside an egg dip — the dip lines read once per '
        "index, each head's mentions once", () {
      String pair(int p) =>
          'Whisk the eggs with ${food(2 * p)} and ${food(2 * p + 1)}. Dip in '
          'the egg mixture, allowing the excess to drip off. ';
      final r = capped(
        loadCorpusRecipe('0114-breaded-chicken-cutlets.yaml'),
        [for (var i = 0; i < capLines; i++) '1 cup ${food(i)}'],
        [
          for (var k = 0; k < capSteps; k++)
            // 80 pairs fit a step; the 200 pairs cycle through the steps.
            ([for (var j = 0; j < 80; j++) pair((k * 80 + j) % 200)].join() * 2)
                .substring(0, capStep),
        ],
      );
      stepIndexCounts.clear();
      final sw = Stopwatch()..start();
      final unflagged = [
        for (final line in nutritionLines(r))
          if (m50FlagOf(r, line) == null) line.raw,
      ];
      final ms = sw.elapsedMilliseconds;
      final counts = Map.of(stepIndexCounts);
      expectBounded(r, counts, 'distinct dip heads');
      expect(counts['memo:dips'], 1);
      // Every line is named by a mixing sentence before an egg dip.
      expect(unflagged, isEmpty);
      expect(ms, lessThan(backstopMs), reason: '$counts');
    });
  }, skip: skipIfNoCorpus);
}

/// The corpus's amount-less lines the engine weighs whose search a fixture
/// records (85 of the 262 — R-H1's lines; real corpus lines).
const List<String> _amountless = [
  '2 tablespoons juice',
  'All-purpose flour',
  'Avocado, peeled, pitted, and diced fine',
  'Avocado, peeled, pitted, and diced medium',
  'Balsamic vinegar',
  'Bean sprouts',
  'Cayenne pepper',
  'Chili oil',
  'Chinese black vinegar',
  'Chopped chives',
  'Chopped fresh chives',
  'Chopped fresh cilantro leaves',
  'Chopped red onion',
  'Chopped tomato',
  'Coarsely chopped cilantro',
  'Confectioners’ sugar',
  'Confectioners’ sugar (optional)',
  'Confectioners’ sugar, for dusting',
  'Confectioners’ sugar, for dusting the cakes',
  'Cotija cheese, crumbled, or Monterey Jack cheese, diced fine',
  'Crème fraîche (optional)',
  'Diced avocado',
  'Diced tomatoes',
  'Dry-roasted peanuts, chopped coarse',
  'Extra-virgin olive oil',
  'Extra-virgin olive oil, for serving',
  'Finely chopped white onion',
  'Fresh cilantro',
  'Fresh cilantro leaves',
  'Grated Parmesan cheese',
  'Grated Parmesan cheese, for serving',
  'Grated Pecorino Romano cheese',
  'Ground white pepper',
  'Hoisin sauce',
  'Honey',
  'Hot sauce',
  'Hot sauce (optional)',
  'Jalapeño chile, minced',
  'Lemon or lime wedges (optional)',
  'Lemon wedges',
  'Lemon wedges (optional)',
  'Lemon wedges, for serving',
  'Lemon wedges, for serving (optional)',
  'Lime wedges',
  'Lime wedges, for serving',
  'Lime, orange, or lemon wedges',
  'Minced fresh chives',
  'Minced fresh cilantro leaves',
  'Minced red onion (optional)',
  'Minced white onion',
  'Mint, raspberries, confectioners’ sugar, or finely chopped pistachios, for garnish (optional)',
  'Pita, flatbread, or crusty bread',
  'Plain yogurt',
  'Queso fresco or feta cheese',
  'Red onion, diced fine',
  'Red pepper flakes',
  'Red pepper flakes, for serving',
  'Salted butter',
  'Saltines',
  'Scallions, sliced thin on bias',
  'Shredded Monterey Jack cheese',
  'Shredded iceberg lettuce',
  'Small pinch cayenne pepper',
  'Sour cream',
  'Soy sauce',
  'Sriracha (optional)',
  'Sriracha sauce',
  'Sugar',
  'Sugar stars',
  'Table alt and pepper',
  'Table salt and cayenne pepper',
  'Table salt and ground white pepper',
  'Thinly sliced onion',
  'Thinly sliced radishes',
  'Thinly sliced tomato',
  'Unbleached all-purpose flour, for the work surface',
  'Unsalted butter, as needed',
  'Unsalted butter, softened',
  'Vegetable oil',
  'Vegetable oil for brushing the tortillas',
  'Vegetable oil spray',
  'Vegetable oil, as needed',
  'Vegetable oil, for pan-frying',
  'Vegetable oil, if needed',
  '⅜-inch dice and patted dry with paper towels',
];

/// v71 (M71 R-H1): the step-amount reader at the caps. AMOUNTLESS: 0398's
/// two headed groups (DOUGH, SAUCE) of 200 amount-less corpus lines each
/// (the 85 above, cycled) under 120 steps of 10,000 characters printing
/// amounts of their heads ("Add 1 tablespoon oil, ½ teaspoon sugar, …"),
/// labelled "FOR THE DOUGH" at step 1 and "FOR THE SAUCE" at step 61, one
/// sentence multiplying — the prints and both guards' sentences read in one
/// pass per index (`memo:stepAmounts`), each scope once per heading
/// (`memo:labelScope`), and the reader's work pinned at its measured size
/// (`stepPrints`, `stepPrintsWalked`: a line walks its own group's prints
/// only). Each the compute, the matches GET, the recompute and the
/// freshness check. Synthesized, a stated exception: the repeated lines and
/// the steps.
///
/// Measured (closer 1, verify1 D1; c1/timing_final.log: 9 runs each, 6
/// interleaved base-tree-tree-base rounds against v70 8f42742): this LOUD
/// shape compute 503.0 → 551.3 ms (+9.6 %), GET 449.7 → 502.0 (+11.6 %) —
/// the reader's own per-print work, with no base equivalent (56,160 prints:
/// the `_stepAmount` matches alone ≈ 20 ms; at verify1 +12 % / +16 %, the
/// per-line walk over both groups and the guards' own passes since cut);
/// the QUIET shape (no step prints those heads) compute −0.1 %, GET
/// +0.5 %, recompute +1.2 % — within ±2 %.
void review71() {
  group("RULE C, M71's step-amount reader at the caps (v71)", () {
    test('AMOUNTLESS: the prints once per index, each scope once per '
        'heading; each under the backstop', () async {
      final base = loadCorpusRecipe('0398-ultimate-grilled-pizza.yaml');
      const sentence =
          'Add 1 tablespoon oil, ½ teaspoon sugar, 2 tablespoons vinegar, '
          '1 cup flour, ¼ cup cilantro, 1 tablespoon chives, 2 cups onion, '
          '1 teaspoon pepper flakes and 3 tablespoons cheese to the bowl. ';
      final steps = [
        for (var i = 0; i < capSteps; i++)
          RecipeStep(
            number: i + 1,
            label: i == 0
                ? 'FOR THE DOUGH'
                : i == capSteps ~/ 2
                ? 'FOR THE SAUCE'
                : null,
            text: i == 1
                ? 'Repeat with each remaining portion. '
                      '${fill(sentence, capStep - 40)}'
                : fill(sentence, capStep),
          ),
      ];
      for (final s in steps) {
        expect(s.text.length, lessThanOrEqualTo(capStep));
      }
      // Each group: one line of each head the steps print (its head its
      // own in the group — tier i passes, the reader weighs every print in
      // the group's 60 steps), then the lines of the other heads, cycled
      // (tier i turns them away; no print names them).
      const printed = {
        'oil',
        'sugar',
        'vinegar',
        'flour',
        'cilantro',
        'chive',
        'onion',
        'flake',
        'cheese',
        'pepper',
      };
      String? headOf(String raw) =>
          headNounOf(normalizeItem(lineItemOf(ln(raw))));
      final firsts = <String, String>{};
      for (final raw in _amountless) {
        if (headOf(raw) case final head? when printed.contains(head)) {
          firsts.putIfAbsent(head, () => raw);
        }
      }
      expect(firsts.keys.toSet(), printed);
      final others = [
        for (final raw in _amountless)
          if (!printed.contains(headOf(raw))) raw,
      ];
      final items = [
        ...firsts.values,
        for (var i = 0; firsts.length + i < capLines ~/ 2; i++)
          others[i % others.length],
      ];
      final r = base.copyWith(
        ingredients: [
          for (final g in ['DOUGH', 'SAUCE'])
            IngredientGroup(
              group: g,
              items: [for (final raw in items) ln(raw)],
            ),
        ],
        steps: steps,
      );
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      wp.saveRecipe(db, r);
      Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
      final seen = <String, Map<String, int>>{};
      Future<void> timed(String step, Future<Object?> Function() run) async {
        stepIndexCounts.clear();
        final sw = Stopwatch()..start();
        await run();
        final ms = sw.elapsedMilliseconds;
        final counts = seen[step] = Map.of(stepIndexCounts);
        final copies = counts['indexes'] ?? 1;
        expectBounded(stored(), counts, 'amountless $step', copies: copies);
        // The prints and both guards' sentences, one pass per index.
        expect(
          counts['memo:stepAmounts'] ?? 0,
          lessThanOrEqualTo(copies),
          reason: 'amountless $step memo:stepAmounts',
        );
        expect(
          counts['memo:labelScope'] ?? 0,
          lessThanOrEqualTo(2 * copies),
          reason: 'amountless $step memo:labelScope',
        );
        expect(ms, lessThan(backstopMs), reason: 'amountless $step: $counts');
      }

      await timed('compute', () => matchAndCompute(db, provider, stored()));
      // Not vacuous: the reader weighs every print of its group's steps
      // for the lines whose head is their own there (a line on no record —
      // an unanswered search — is weighed by no reader).
      final st = stored();
      final bases = {
        for (final m in db.ingredientMatchesFor(r.id))
          if (gramBasisFor(db, nutritionLines(st)[m.position], m, recipe: st)
              case final b? when b.contains('(no amount on the line)'))
            m.position: b,
      };
      final read = bases.keys.toSet();
      expect(read, isNotEmpty);
      // Each sums its 60 steps' 3,120 prints; its basis names eight and the
      // count, never the steps again.
      for (final b in bases.values) {
        expect(b, contains(' + … (3120 in all) (no amount on the line)'));
        expect(b.length, lessThan(1000));
      }
      expect(read.every((p) => p % (capLines ~/ 2) < printed.length), isTrue);
      await timed('GET', () => matchesBody(db, provider, stored()));
      await timed('recompute', () async => recomputeTotals(db, stored()));
      await timed('fresh', () async => nutritionIsFresh(db, stored()));
      // The reader's work at its measured size (closer 1, verify1 D1): the
      // index files every print once (9 to a sentence: 6,240 sentences,
      // 56,160 prints); a line walks only its own group's 60 steps — the
      // 3,120 prints of its head there, never the other group's (6,240
      // each before closer 1) — and walks them once. The compute weighs
      // the 20 lines whose head the steps print (10 heads × 2 groups), the
      // GET the 18 read: the prints now fetch each record's detail (the
      // M71 follow-up, verify6 D1), and the details of chives, cilantro
      // and pepper flakes carry the spoon measures their search hits did
      // not; only the red onion stays unread — its Foundation record
      // 790577 carries no cup measure (an onion of 197 g and the RACC).
      final occurrences = [
        for (final s in steps) sentence.trim().allMatches(s.text).length,
      ];
      int printsIn(Iterable<int> range) =>
          range.fold(0, (n, i) => n + occurrences[i]);
      const half = capSteps ~/ 2;
      expect(printsIn(Iterable.generate(half)), 3120);
      expect(printsIn(Iterable.generate(half, (i) => half + i)), 3120);
      expect(printsIn(Iterable.generate(capSteps)) * 9, 56160);
      // RE-PIN (M71 follow-up, verify6 D1): a compute weighs each of the 20
      // read lines TWICE — on the search hit, then on the record detail the
      // prints now fetch (as a typed line's amounts would) — while the
      // prints are walked once per line; the GET weighs the 18 read on the
      // cached detail only.
      for (final (step, weighed, walked) in [
        ('compute', 40, 20),
        ('GET', read.length, read.length),
      ]) {
        final counts = seen[step]!;
        expect(counts['stepPrints'], 56160, reason: step);
        expect(counts['memo:stepAmountGrams'], weighed, reason: step);
        expect(counts['stepPrintsWalked'], 3120 * walked, reason: step);
      }
      // RE-PIN (M71 follow-up, verify6 D1): 12 -> 18, the fetched details.
      expect(read.length, 18);
      for (final step in ['recompute', 'fresh']) {
        expect(seen[step]!['stepPrints'], isNull, reason: step);
      }
    });

    // v71 closer 1 (verify1 D2): D-E1's gate at the caps. 0235's lines
    // (the cornstarch coat held with no budget) and 387 copies of its three
    // mixture parts, under its four steps and 116 steps of its own whisk
    // sentence — 391 rows held `coating`; part |7 confirmed, then picked,
    // through the real PUT (a pick keeps the hold) and the other 389 parts
    // written in that state, so the GET and the recompute after them ask
    // the gate (`_coatOfPart`, from `derivedFor`) for 390 decided rows. The
    // mixture pass run per gate call (the first build's: the long-lines
    // PUTs 38 s) fails `coatMixLines` here (312,000 > 400) and on long-lines
    // (800 > 400); a mixing test repeated per call fails `mixTests` (one per
    // sentence, == `memo:mixes`). Synthesized, a stated exception: the
    // copied lines, the written decisions and the repeated sentence (real
    // corpus text).
    test('HELD MIXTURE: the D-E1 gate asked for every held part, each '
        'sentence tested for a mixing word once per index, the mixture '
        'pass once; each path under the backstop', () async {
      final base = loadCorpusRecipe('0235-maple-glazed-pork-tenderloin.yaml');
      final real = nutritionLines(base);
      const whisk =
          'Whisk the cornstarch, sugar, salt, and black pepper in a small '
          'bowl until combined. ';
      final r = base.copyWith(
        ingredients: [
          IngredientGroup(
            items: [
              ...real,
              for (var i = 0; real.length + i < capLines; i++)
                real[7 + i % 3].copyWith(),
            ],
          ),
        ],
        steps: [
          ...base.steps,
          for (var i = base.steps.length; i < capSteps; i++)
            RecipeStep(number: i + 1, text: fill(whisk, capStep)),
        ],
      );
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      wp.saveRecipe(db, r);
      Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
      final seen = <String, Map<String, int>>{};
      Future<void> timed(String step, Future<Object?> Function() run) async {
        stepIndexCounts.clear();
        final sw = Stopwatch()..start();
        await run();
        final ms = sw.elapsedMilliseconds;
        final counts = seen[step] = Map.of(stepIndexCounts);
        final copies = counts['indexes'] ?? 1;
        expectBounded(stored(), counts, 'held mixture $step', copies: copies);
        // Each test the first of its sentence (the memo read, never a
        // second test).
        expect(
          counts['mixTests'] ?? 0,
          counts['memo:mixes'] ?? 0,
          reason: 'held mixture $step',
        );
        expect(ms, lessThan(backstopMs), reason: 'held mixture $step: $counts');
      }

      await timed('compute', () => matchAndCompute(db, provider, stored()));
      // Not vacuous: the coat and every part held with it.
      expect(
        [
          for (final m in db.ingredientMatchesFor(r.id))
            if (m.hold == 'coating') m.position,
        ].length,
        391,
      );
      await timed('GET', () => matchesBody(db, provider, stored()));
      final part = db.ingredientMatchesFor(r.id)[7];
      Map<String, Object?> body(Map<String, Object?> b) => {
        'raw': real[7].raw,
        ...b,
      };
      await timed(
        'PUT confirm',
        () => applyMatchOverride(
          db,
          provider,
          stored(),
          7,
          body({'confirmed': true}),
        ),
      );
      await timed(
        'PUT pick',
        () => applyMatchOverride(
          db,
          provider,
          stored(),
          7,
          body({'fdc_id': part.fdcId}),
        ),
      );
      // Row 7 picked through the real PUT (a pick keeps the coat's hold);
      // the other 389 parts written in that state — 390 decided rows the
      // decided paths read through the gate, one by one.
      final put = db.ingredientMatchesFor(r.id);
      expect((put[7].hold, put[7].grams), ('coating', null));
      for (final row in put) {
        if (row.position > 7 && row.hold == 'coating') {
          db.upsertIngredientMatch(
            row.copyWith(status: put[7].status, derivedSeq: put[7].derivedSeq),
          );
        }
      }
      await timed('GET decided', () => matchesBody(db, provider, stored()));
      await timed('recompute', () async => recomputeTotals(db, stored()));
      expect(
        [
          for (final m in db.ingredientMatchesFor(r.id))
            if (m.status == put[7].status && m.hold == 'coating') m.position,
        ],
        hasLength(390),
      );
      // Not vacuous: each decided path reached the mixture pass through
      // the gate — once.
      for (final step in ['PUT confirm', 'PUT pick', 'GET decided']) {
        final counts = seen[step]!;
        expect(counts['memo:mayHoldCoat'], counts['indexes'], reason: step);
        expect(counts['memo:coatMixes'], counts['indexes'], reason: step);
        expect(
          counts['coatMixLines'],
          capLines * counts['indexes']!,
          reason: step,
        );
        expect(counts['mixTests'], greaterThan(0), reason: step);
      }
    });

    // v71 closer 2 (verify2 D1): pF R3 at the caps. 0316's real lines (the
    // potatoes, 2 quarts peanut oil, ¼ cup bacon fat, salt), its bacon-fat
    // line copied to 400 lines, under 120 steps of 10,000 characters of one
    // add sentence: OTHER adds the potatoes (no step names the oil), NAMED
    // (the potatoes and 399 bacon-fat lines, no oil line) adds the bacon
    // fat, OIL adds the bacon fat to the hot oil (each of its 35,280
    // sentences one R3 reads). Every fat line asks [_joinsFryingOil]; the
    // add-or-combine sentences of a step naming the oil are read once per
    // index (`memo:fatsIntoOil`, each counted `fatsIntoOilReads`), the oil
    // lines' frying test made once (`memo:friesOil`). At verify2 each call
    // walked every add sentence with its own pattern and scanned the whole
    // step for "oil" per sentence naming the line — NAMED compute 104 s,
    // GET 211 s (base 0.6 s / 0.4 s). Measured (closer 2, fix71/c2
    // r3time_final, vtime_final3, r3time_named9 against v70 8f42742,
    // base-tree-tree-base): OTHER compute −0.9 %, GET +0.7 %; NAMED compute
    // −0.5 %, GET +2.1 % (+0.0 / +1.9 % against this tree with R3 off); OIL
    // compute −2.4 %, GET +7.2 % — the pass's own per-sentence work (≈ 20 ms
    // per index, no base equivalent). Synthesized, a stated exception: the
    // copied line and the repeated sentences.
    for (final (shape, sentence) in [
      ('OTHER', 'Add the potatoes to the bowl. '),
      ('NAMED', 'Add the bacon fat to the bowl. '),
      ('OIL', 'Add the bacon fat to the hot oil. '),
    ]) {
      test('R3 FAT LINES $shape: the add sentences of the oil steps read '
          'once per index, whichever fat line asks; each path under the '
          'backstop', () async {
        final base = loadCorpusRecipe('0316-classic-french-fries.yaml');
        final real = nutritionLines(base);
        expect(real[2].raw, '¼ cup bacon fat, strained (optional)');
        final kept = shape == 'NAMED' ? [real[0]] : real;
        final r = base.copyWith(
          ingredients: [
            IngredientGroup(
              items: [
                ...kept,
                for (var i = kept.length; i < capLines; i++) real[2].copyWith(),
              ],
            ),
          ],
          steps: [
            for (var i = 0; i < capSteps; i++)
              RecipeStep(number: i + 1, text: fill(sentence, capStep)),
          ],
        );
        final db = wp.tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        wp.saveRecipe(db, r);
        Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
        // The sentences R3 reads: every add sentence of a step naming the
        // oil — OIL's 294 a step; none where no step names it.
        final reads = shape == 'OIL'
            ? capSteps * (capStep ~/ sentence.length)
            : 0;
        final seen = <String, Map<String, int>>{};
        Future<void> timed(String step, Future<Object?> Function() run) async {
          stepIndexCounts.clear();
          final sw = Stopwatch()..start();
          await run();
          final ms = sw.elapsedMilliseconds;
          final counts = seen[step] = Map.of(stepIndexCounts);
          final copies = counts['indexes'] ?? 1;
          final why = 'R3 $shape $step';
          expectBounded(stored(), counts, why, copies: copies);
          expect(
            counts['memo:fatsIntoOil'] ?? 0,
            lessThanOrEqualTo(copies),
            reason: why,
          );
          expect(
            counts['memo:friesOil'] ?? 0,
            lessThanOrEqualTo(copies),
            reason: why,
          );
          expect(
            counts['fatsIntoOilReads'] ?? 0,
            reads * (counts['memo:fatsIntoOil'] ?? 0),
            reason: why,
          );
          expect(ms, lessThan(backstopMs), reason: '$why: $counts');
        }

        await timed('compute', () => matchAndCompute(db, provider, stored()));
        await timed('GET', () => matchesBody(db, provider, stored()));
        await timed('recompute', () async => recomputeTotals(db, stored()));
        await timed('fresh', () async => nutritionIsFresh(db, stored()));
        // Not vacuous: the fat lines asked, the pass made once per index;
        // the oil lines' frying test made once per index where a sentence
        // adds a fat line to the oil (OIL), never where none does.
        for (final step in ['compute', 'GET']) {
          expect(
            seen[step]!['memo:fatsIntoOil'],
            seen[step]!['indexes'],
            reason: step,
          );
          expect(
            seen[step]!['memo:friesOil'] ?? 0,
            shape == 'OIL' ? seen[step]!['indexes'] : 0,
            reason: step,
          );
        }
        // Each fat line's row: joined to the frying oil (0 g) only where
        // the sentences add it to the oil; else its ¼ cup counted.
        final fats = [
          for (final (i, l) in nutritionLines(stored()).indexed)
            if (l.raw == real[2].raw) i,
        ];
        expect(fats, hasLength(shape == 'NAMED' ? 399 : 397));
        expect(
          {
            for (final m in db.ingredientMatchesFor(r.id))
              if (fats.contains(m.position))
                (m.grams?.toStringAsFixed(2), m.gramSource),
          },
          {
            if (shape == 'OIL') ('0.00', 'discarded') else ('51.60', 'portion'),
          },
        );
      });
    }

    // v71 closer 3 (verify3 D1): pF R2 at the caps. 0523 Nasi Goreng's 14
    // real lines (its sub-recipe dropped) with its "½ cup vegetable oil"
    // copied to 400 lines, under 120 steps of 10,000 characters: USED — every
    // sentence "Heat 1 teaspoon of the reserved oil." (32,400 prints, Σ past
    // the line: no read, every copy counted whole); BELOW — steps 1–23 open
    // with one such sentence, the rest "Heat the oil in the skillet." (23
    // teaspoons < ½ cup: the read fires on every copy). Every oil line asks
    // [_reservedUseOf] from each caller; the prints are found once per index
    // (`memo:reservedUse`, each counted `reservedHits`, each printed amount
    // parsed once) and summed once per scope (`memo:reservedUseIn`, each
    // hit walked `reservedHitsRead`). At verify3 each call walked and parsed
    // every print of the head — USED compute 50.8 s, GET 99.8 s (base 1.2 s
    // / 0.9 s). Measured (closer 4, fix71/c4 time3.log, the final tree,
    // against v70 8f42742 and the tree with R2 alone off, 5 reps per arm;
    // API.md states them): USED compute +0.0 %, GET +1.3 %; BELOW +0.5 % /
    // +1.1 %, recompute +71 % — the read's 387 `discarded` rows each ask
    // the shipped readers of a discarded engine row (M52's plan media, v53;
    // the F9 revert check, v70), whose detectors build once per index
    // (words, naming, fries; both readers off: 293 ms = base 289) — a
    // `portion` row asks neither. Synthesized, a stated exception: the
    // copied line and the repeated sentences.
    // v71 closer 4 (verify4 D1): MANY — every sentence "Heat 1/10000
    // teaspoon reserved oil." (33,240 prints, Σ 3.32 teaspoons < ½ cup: the
    // read fires on every copy, 15.51 g). Each row's basis named EVERY print
    // twice: one matches GET 489,617,983 characters (base 8f42742: 729,010),
    // each basis 1,263,287, matchesBody 889 → 1,378 ms, peak RSS 0.93 → 2.23
    // GB. Now at most 8 named ("+ … (n in all)", as R-H1's): each basis 509
    // characters, the GET body 922,897 — base plus the 387 read rows' own
    // basis text (BELOW, 23 prints: 407 / 883,810). Compute +1.6 %, the GET
    // +5.5 %: R2's pass (14 ms), the shipped v51 pour-off reader's
    // detectors built once per index at the GET's first `discarded` oil row
    // (30 ms) and `_m50DiscardedBasis` per read row (12 ms) — API.md.
    for (final shape in ['USED', 'BELOW', 'MANY']) {
      test('R2 RESERVED OIL $shape: the prints found once per index, their '
          'scoped sum once per scope, whichever oil line asks; each path '
          'under the backstop', () async {
        final base = loadCorpusRecipe(
          '0523-nasi-goreng-indonesian-style-fried-rice.yaml',
        );
        final real = base.ingredients.single.items;
        expect(real, hasLength(14));
        expect(real[9].raw, '½ cup vegetable oil');
        const hit = 'Heat 1 teaspoon of the reserved oil. ';
        const quiet = 'Heat the oil in the skillet. ';
        const many = 'Heat 1/10000 teaspoon reserved oil. ';
        final r = base.copyWith(
          subsections: const [],
          ingredients: [
            IngredientGroup(
              items: [
                ...real,
                for (var i = real.length; i < capLines; i++) real[9].copyWith(),
              ],
            ),
          ],
          steps: [
            for (var i = 0; i < capSteps; i++)
              RecipeStep(
                number: i + 1,
                text: shape == 'MANY'
                    ? fill(many, capStep)
                    : shape == 'USED'
                    ? fill(hit, capStep)
                    : i < 23
                    ? hit + fill(quiet, capStep - hit.length)
                    : fill(quiet, capStep),
              ),
          ],
        );
        for (final s in r.steps) {
          expect(s.text.length, lessThanOrEqualTo(capStep));
        }
        final db = wp.tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        wp.saveRecipe(db, r);
        Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
        // The prints one index finds: 270 a step in USED, 23 in BELOW.
        // MANY: 277 a step.
        final hits = shape == 'MANY'
            ? capSteps * (capStep ~/ many.length)
            : shape == 'USED'
            ? capSteps * (capStep ~/ hit.length)
            : 23;
        final seen = <String, Map<String, int>>{};
        Future<void> timed(String step, Future<Object?> Function() run) async {
          stepIndexCounts.clear();
          final sw = Stopwatch()..start();
          await run();
          final ms = sw.elapsedMilliseconds;
          final counts = seen[step] = Map.of(stepIndexCounts);
          final copies = counts['indexes'] ?? 1;
          final why = 'R2 $shape $step';
          expectBounded(stored(), counts, why, copies: copies);
          final found = counts['memo:reservedUse'] ?? 0;
          final summed = counts['memo:reservedUseIn'] ?? 0;
          expect(found, lessThanOrEqualTo(copies), reason: why);
          // One scope (one group): one sum per index that found prints.
          expect(summed, found, reason: why);
          expect(counts['reservedHits'] ?? 0, hits * found, reason: why);
          expect(counts['reservedHitsRead'] ?? 0, hits * summed, reason: why);
          expect(ms, lessThan(backstopMs), reason: '$why: $counts');
        }

        await timed('compute', () => matchAndCompute(db, provider, stored()));
        late final Map<String, Object?> body;
        await timed(
          'GET',
          () async => body = await matchesBody(db, provider, stored()),
        );
        await timed('recompute', () async => recomputeTotals(db, stored()));
        await timed('fresh', () async => nutritionIsFresh(db, stored()));
        // Not vacuous: the oil lines asked — the prints found once per
        // index on compute and GET; a recompute asks only where the rows
        // are the read's (`discarded`), a freshness check never.
        for (final step in ['compute', 'GET']) {
          expect(
            seen[step]!['memo:reservedUse'],
            seen[step]!['indexes'],
            reason: step,
          );
        }
        expect(
          seen['recompute']!['memo:reservedUse'] ?? 0,
          shape == 'USED' ? 0 : seen['recompute']!['indexes'],
        );
        expect(seen['fresh']!['memo:reservedUse'] ?? 0, 0);
        // Each oil line's row: 386 copies and the real line, counted whole
        // where the prints pass the line (USED), else the 23 teaspoons of
        // its ½ cup (112.00 g × 113.37 / 118.29 mL = 107.33 g).
        final oils = [
          for (final (i, l) in nutritionLines(stored()).indexed)
            if (l.raw == real[9].raw) i,
        ];
        expect(oils, hasLength(capLines - 13));
        expect(
          {
            for (final m in db.ingredientMatchesFor(r.id))
              if (oils.contains(m.position))
                (m.grams?.toStringAsFixed(2), m.gramSource),
          },
          {
            if (shape == 'USED')
              ('112.00', 'portion')
            else if (shape == 'MANY')
              ('15.51', 'discarded')
            else
              ('107.33', 'discarded'),
          },
        );
        if (shape == 'USED') {
          return;
        }
        // The basis names 8 prints and the count (verify4 D1); the GET body
        // within 2 % of the measured (MANY 922,897, BELOW 883,810).
        final each = shape == 'MANY' ? '1/10000 teaspoon' : '1 teaspoon';
        final named = '${List.filled(8, each).join(' + ')} + … ($hits in all)';
        final basis =
            'only $named of it used (from step 1) — the rest counted as 0 g '
            '· approximate (the steps use $named of the reserved oil; the '
            "rest is not used here — the fried aromatics' oil not counted)";
        final items = (body['items']! as List).cast<Map<String, Object?>>();
        expect(
          {
            for (final i in oils)
              (items[i]['match']! as Map<String, Object?>)['gram_basis'],
          },
          {basis},
        );
        expect(basis.length, shape == 'MANY' ? 509 : 407);
        expect(
          jsonEncode(body).length,
          lessThanOrEqualTo((shape == 'MANY' ? 922897 : 883810) * 1.02),
        );
      });
    }
  }, skip: skipIfNoCorpus);

  group("RULE C, the braised pairs' gate (v72, M72 R-E3)", () {
    final design = RegExp(
      r'\bskim\w*\b[^.]*\bfat\b|\bfat\b[^.]*\bskim\w*\b|\bfat separator\b|'
      r'\bdefatted\b|\bstrain off the fat\b',
    );

    test("the gate answers as the design's regex (30,000 seeded sentences "
        'over its own words) and reads 1,200 hostile ~1,000-character '
        'sentences of each of three shapes in one pass — "fat" with no '
        'skim, skim words with no fat word, fat words with "skim" inside a '
        "word (the regex's `[^.]*` pair is quadratic on them)", () {
      const atoms = [
        'skim', 'skimming', 'skims', 'fat', 'fats', 'separator', //
        'fat separator', 'defatted', 'strain off the fat', 'strain', 'off',
        'the', '.', '1.5', 'x', ',', '\n', 'scum',
      ];
      var hits = 0;
      var misses = 0;
      for (var seed = 0; seed < 30000; seed++) {
        final r = Random(seed);
        final b = StringBuffer();
        for (var i = 0, n = 1 + r.nextInt(12); i < n; i++) {
          b.write(atoms[r.nextInt(atoms.length)]);
          if (r.nextInt(3) > 0) {
            b.write(' ');
          }
        }
        final s = b.toString();
        final reference = design.hasMatch(s);
        expect(defatsSentence(s), reference, reason: '"$s"');
        reference ? hits++ : misses++;
      }
      // Not vacuous either way.
      expect(hits, greaterThan(1000));
      expect(misses, greaterThan(1000));
      // Three hostile shapes, 1,200 sentences each: "fat …" stops at the
      // skim substring test; the next two REACH the skim arm's finds —
      // skim words with no `\bfat\b` (the design's first `[^.]*`
      // alternative is quadratic on it) and fat words with "skim" only
      // inside a word (the second alternative's) — so restoring either
      // half of the regex fails here (verify2 D1: the first shape alone
      // bounded only the prefilter). The tree reads each shape in ≈ 9 ms
      // and a restored half in 630–760 ms: 200 ms kills it by ≥ 3×
      // (500 did by 1.3×).
      final shapes = [
        '${'fat ' * 249}x.',
        'fatty ${'skim ' * 197}x.',
        '${'fat ' * 248}xskim.',
      ];
      expect([for (final s in shapes) s.length], [998, 993, 998]);
      for (final shape in shapes) {
        final hostile = List.filled(1200, shape);
        final sw = Stopwatch()..start();
        for (final s in hostile) {
          expect(defatsSentence(s), isFalse);
        }
        expect(
          sw.elapsedMilliseconds,
          lessThan(200),
          reason: '…${shape.substring(shape.length - 10)}',
        );
      }
    });

    test('CAP SHAPE: 400 short-rib lines under 120 × 10,000-character steps '
        'naming "skim" and "fat" in separate sentences (never a skim of '
        'fat): the gate read once per index, no row deducted; each path '
        'under the backstop', () async {
      final base = loadCorpusRecipe('0087-braised-beef-short-ribs.yaml');
      final own = [for (final g in base.ingredients) ...g.items];
      const ribs = '3½ pounds boneless beef short ribs, trimmed of excess fat';
      final r = capped(
        base,
        [
          for (final l in own) l.raw,
          for (var i = own.length; i < capLines; i++) ribs,
        ],
        [
          for (var i = 0; i < capSteps; i++)
            fill('Skim the broth well. Add the fat to the pot. ', capStep),
        ],
      );
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      wp.saveRecipe(db, r);
      Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
      Future<void> timed(String step, Future<Object?> Function() run) async {
        stepIndexCounts.clear();
        final sw = Stopwatch()..start();
        await run();
        final ms = sw.elapsedMilliseconds;
        final counts = Map.of(stepIndexCounts);
        final copies = counts['indexes'] ?? 1;
        expectBounded(r, counts, 'gate $step', copies: copies);
        expect(
          counts['memo:defatsLiquid'],
          inInclusiveRange(1, copies),
          reason: 'gate $step',
        );
        expect(ms, lessThan(backstopMs), reason: 'gate $step: $counts');
      }

      await timed('compute', () => matchAndCompute(db, provider, stored()));
      final rows = db.ingredientMatchesFor(r.id);
      final ribRows = [
        for (final row in rows)
          if (row.fdcId == 170827) row,
      ];
      expect(ribRows.length, greaterThanOrEqualTo(capLines - own.length));
      for (final row in ribRows) {
        expect(braisedKeptOf(row.raw, 170827, stored()), isNull);
      }
      await timed('GET', () => matchesBody(db, provider, stored()));
      await timed('recompute', () async => recomputeTotals(db, stored()));
    });
  }, skip: skipIfNoCorpus);

  group(
    "RULE C, the step-printed trim (v74, M74, the owner's Q1 (b))",
    () {
      final design = RegExp(
        r'^\s*trim fat\b[^.]*\bbrisket\b[^.]*\bto (⅛|¼)[- ]inch\b',
      );

      test("the reader answers as the design's regex (30,000 seeded sentences "
          'over its own words) and reads 1,200 hostile ~1,000-character '
          'sentences of each of two shapes in one pass — "trim fat" then '
          '"brisket" repeated with no "to", and "brisket to ⅛ inc" repeated '
          "(the regex's `[^.]*` pair is quadratic on both)", () {
        const atoms = [
          'trim fat', 'trim', 'fat', 'fats', 'brisket', 'briskets', 'to', //
          '⅛', '¼', 'inch', '-inch', 'inches', 'to ⅛ inch', 'to ¼-inch',
          'on', '.', '1.5', 'x', ',', '\n', 'brisket to ⅛ inch',
          'brisket to ¼ inch',
        ];
        var hits = 0;
        var misses = 0;
        for (var seed = 0; seed < 30000; seed++) {
          final r = Random(seed);
          final b = StringBuffer(
            r.nextBool() ? '${r.nextBool() ? ' ' : ''}trim fat ' : '',
          );
          for (var i = 0, n = 1 + r.nextInt(10); i < n; i++) {
            b.write(atoms[r.nextInt(atoms.length)]);
            if (r.nextInt(3) > 0) {
              b.write(' ');
            }
          }
          final s = b.toString();
          final reference = design.firstMatch(s)?[1];
          expect(trimsFatSentence(s), reference, reason: '"$s"');
          reference == null ? misses++ : hits++;
        }
        // Not vacuous either way.
        expect(hits, greaterThan(1000));
        expect(misses, greaterThan(1000));
        // The tree reads each shape in ≈ 3–5 ms and the design's regex in
        // 226–308 ms (fix74/probe/hostile.dart): 100 ms kills a restored
        // regex by ≥ 2×.
        final shapes = [
          'trim fat ${'brisket ' * 123}inch.',
          'trim fat ${'brisket to ⅛ inc ' * 58}x.',
        ];
        expect([for (final s in shapes) s.length], [998, 997]);
        for (final shape in shapes) {
          final hostile = List.filled(1200, shape);
          final sw = Stopwatch()..start();
          for (final s in hostile) {
            expect(trimsFatSentence(s), isNull);
          }
          expect(
            sw.elapsedMilliseconds,
            lessThan(100),
            reason: '…${shape.substring(shape.length - 10)}',
          );
        }
      });

      for (final loud in [false, true]) {
        test('CAP SHAPE (${loud ? 'loud' : 'quiet'}): 400 flat-brisket lines '
            'under 120 × 10,000-character steps of "Trim fat on the brisket '
            'brisket brisket, about 1 inch." (every sentence read, none a '
            'printed depth)${loud ? ' after S1\'s real "Trim fat on surface of '
                      'brisket to ⅛ inch." (every flat moves to 173128 and '
                      'deducts)' : ''}: the reader once per index; each path '
            'under the backstop', () async {
          final base = loadCorpusRecipe(
            '0091-home-corned-beef-with-vegetables.yaml',
          );
          final own = [for (final g in base.ingredients) ...g.items];
          const flat = '1 (4½- to 5-pound) beef brisket, flat cut';
          const hostile =
              'Trim fat on the brisket brisket brisket, about 1 inch. ';
          final r = capped(
            base,
            [
              for (final l in own) l.raw,
              for (var i = own.length; i < capLines; i++) flat,
            ],
            [
              if (loud)
                'Trim fat on surface of brisket to ⅛ inch. '
                    '${fill(hostile, capStep - 42)}'
              else
                fill(hostile, capStep),
              for (var i = 1; i < capSteps; i++) fill(hostile, capStep),
            ],
          );
          final db = wp.tempDb();
          final provider = FixtureProvider(pending: pendingSearches);
          wp.saveRecipe(db, r);
          Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
          Future<void> timed(
            String step,
            Future<Object?> Function() run,
          ) async {
            stepIndexCounts.clear();
            final sw = Stopwatch()..start();
            await run();
            final ms = sw.elapsedMilliseconds;
            final counts = Map.of(stepIndexCounts);
            final copies = counts['indexes'] ?? 1;
            expectBounded(r, counts, 'trim $step', copies: copies);
            // The quiet recompute reads no trim: no row sits on 173128.
            expect(
              counts['memo:trimsFatTo'] ?? 0,
              inInclusiveRange(step == 'recompute' && !loud ? 0 : 1, copies),
              reason: 'trim $step',
            );
            // The quiet flats are 168743 rows, which now have a pair
            // (`braisedKept[168743]`, Q1 (a′)): M72's gate, once per index
            // (every sentence names "fat"; it skims none).
            if (!loud) {
              expect(
                counts['memo:defatsLiquid'],
                inInclusiveRange(1, copies),
                reason: 'trim $step',
              );
            }
            expect(ms, lessThan(backstopMs), reason: 'trim $step: $counts');
          }

          await timed('compute', () => matchAndCompute(db, provider, stored()));
          final flats = [
            for (final row in db.ingredientMatchesFor(r.id))
              if (row.raw == flat) row,
          ];
          expect(flats.length, greaterThanOrEqualTo(capLines - own.length));
          expect(
            {for (final row in flats) row.fdcId},
            {
              if (loud) 173128 else 168743,
            },
          );
          for (final row in flats) {
            expect(
              braisedKeptOf(row.raw, row.fdcId, stored()),
              loud ? braisedKept[173128] : isNull,
            );
          }
          await timed('GET', () => matchesBody(db, provider, stored()));
          await timed('recompute', () async => recomputeTotals(db, stored()));
        });
      }
    },
    skip: skipIfNoCorpus,
  );

  group(
    'RULE C, the yield-named own section at the caps (v73, M76 — verify3 '
    'D1, verify4 D2, verify5 D2)',
    () {
      // STATED synthesized cost inputs (a negative-path shape no corpus
      // recipe holds — the library's most is 5 subsections): the real tart
      // (1177) and its real line "1 pound pizza dough" — a distinct prep per
      // line, padded to the 1,000-character line cap — under the editor's 60
      // subsections (recipe_edit_service.dart), each listing "1 cup water".
      // quiet: no title ends in the item; tail: every title does, at MAKES
      // 2 POUNDS (share ½ — none routes); dtail: the tail at 60 DISTINCT
      // yields (MAKES 2 … 61 POUNDS); ref: marked lines ("(recipe
      // follows)") against the tail titles — the resolver's own list.
      // verify4 D2, the TRUE path: rtail — every title "Classic i Pizza
      // Dough" at MAKES 1 POUND (every line names all 60 at its yield);
      // rtail1 — ONE "Classic Pizza Dough" at MAKES 1 POUND among 59 quiet
      // titles (every line routes to it, as the tart's does). A compute
      // reads a routed line through `isReferenceIn` AND the resolver's own
      // list — six reads a line before closer 4, up to five in a GET — so the
      // mark and the share reader are memoised per recipe instance: once per
      // line and instance, a yield once per line, instance and servings
      // string. verify5 D2: in their own store, never the step index — a
      // recompute reads its STORED copy's lines, and memoising there built
      // that copy's step index (≈ +22 ms at the editor's step caps), an
      // index no base recompute builds: each step's `indexes` is pinned
      // EXACTLY at v74's (quiet, tail, dtail 1 / 2 / 1; ref, the routing
      // shapes' compute and recompute 1). Measured (fix76/closer3.md,
      // closer4.md, closer5.md; base 776456f vs the tree, compute / GET /
      // recompute): API.md's M76 cost paragraph.
      const tart = '1177-caramelized-onion-pear-and-bacon-tart.yaml';
      const capSubsections = 60;
      Recipe shape(String kind) {
        String pad(String s) => s + 'x' * (capLine - s.length);
        return loadCorpusRecipe(tart).copyWith(
          subsections: [
            for (var i = 0; i < capSubsections; i++)
              Subsection(
                title: switch (kind) {
                  'quiet' => 'Section $i Sauce',
                  'rtail1' || 'rtail2' =>
                    i == 0 ? 'Classic Pizza Dough' : 'Section $i Sauce',
                  _ => 'Classic $i Pizza Dough',
                },
                kind: 'component',
                servings: switch (kind) {
                  'dtail' => 'MAKES ${i + 2} POUNDS',
                  'rtail' || 'rtail1' || 'rtail2' => 'MAKES 1 POUND',
                  _ => 'MAKES 2 POUNDS',
                },
                ingredients: [
                  IngredientGroup(items: [ln('1 cup water')]),
                ],
              ),
          ],
          ingredients: [
            IngredientGroup(
              items: [
                for (var i = 0; i < capLines; i++)
                  ln(
                    pad(switch (kind) {
                      'ref' => '1 pound pizza dough (recipe follows), $i ',
                      // v91 (M87): the two-word arm's TRUE path — "cold
                      // pizza dough" is no tail of the title; its last two
                      // words are.
                      'rtail2' => '1 pound cold pizza dough, $i ',
                      _ => '1 pound pizza dough, $i ',
                    }),
                  ),
              ],
            ),
          ],
        );
      }

      Map<String, int> yieldCounts() => {
        for (final MapEntry(:key, :value) in stepIndexCounts.entries)
          if (key.startsWith('yield') || key.startsWith('memo:yield'))
            key: value,
      };

      test('one isReferenceIn pass over 400 lines × 60 subsections reads each '
          "line's share ONCE and a yield once per servings string, never the "
          'mark (namesOwnSection has read it); quiet titles read none — the '
          'pass under 400 ms (the pre-fix tree: 875–1,155); a second pass '
          'on the same recipe reads nothing (the per-recipe memo)', () {
        const expected = {
          'quiet': <String, int>{},
          'tail': {'memo:yieldShareReaders': 400, 'yieldServingsReads': 400},
          // The STATED residual: one yield read per (line, distinct
          // servings) — a ≤ 14-character servings string, never the raw
          // (the base normalises every title per line, the same order).
          'dtail': {
            'memo:yieldShareReaders': 400,
            'yieldServingsReads': 24000,
          },
        };
        for (final MapEntry(key: kind, value: counts) in expected.entries) {
          final warm = shape(kind); // another instance: its own memo
          for (final l in warm.ingredients.single.items) {
            isReferenceIn(warm, l);
          }
          final r = shape(kind);
          final lines = r.ingredients.single.items;
          expect(lines.map((l) => l.raw.length).toSet(), {capLine});
          expect(r.subsections, hasLength(capSubsections));
          stepIndexCounts.clear();
          final sw = Stopwatch()..start();
          for (final l in lines) {
            expect(isReferenceIn(r, l), isFalse, reason: kind);
          }
          final ms = sw.elapsedMilliseconds;
          expect(yieldCounts(), counts, reason: kind);
          expect(ms, lessThan(400), reason: kind);
          stepIndexCounts.clear();
          for (final l in lines) {
            expect(isReferenceIn(r, l), isFalse, reason: kind);
          }
          expect(yieldCounts(), isEmpty, reason: '$kind, the second pass');
        }
      });

      test("the resolver's own list on 400 marked lines × 60 tail titles "
          'reads each mark ONCE per line (memoised per recipe instance — a '
          'second resolve reads none), never a share; no tail title joins a '
          'marked line (rule PO)', () {
        final r = shape('ref');
        final db = wp.tempDb();
        final memo = ResolverMemo(db);
        stepIndexCounts.clear();
        for (var pass = 0; pass < 2; pass++) {
          for (final l in r.ingredients.single.items) {
            expect(isReferenceIn(r, l), isTrue);
            expect(resolveReference(db, r, l, memo).section, isNull);
          }
        }
        expect(yieldCounts(), {'memo:yieldMarks': 400});
      });

      Future<Map<String, Map<String, int>>> capShape(
        String kind,
        void Function(SaltDatabase db, Recipe stored) after,
      ) async {
        final r = shape(kind);
        final db = wp.tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        wp.saveRecipe(db, r);
        Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
        final seen = <String, Map<String, int>>{};
        Future<void> timed(String step, Future<Object?> Function() run) async {
          stepIndexCounts.clear();
          final sw = Stopwatch()..start();
          await run();
          final ms = sw.elapsedMilliseconds;
          final counts = Map.of(stepIndexCounts);
          expectBounded(
            r,
            counts,
            '$kind $step',
            copies: counts['indexes'] ?? 1,
          );
          seen[step] = {...yieldCounts(), 'indexes': counts['indexes'] ?? 0};
          expect(ms, lessThan(backstopMs), reason: '$kind $step: $counts');
        }

        await timed('compute', () => matchAndCompute(db, provider, stored()));
        after(db, stored());
        await timed('GET', () => matchesBody(db, provider, stored()));
        await timed('recompute', () async => recomputeTotals(db, stored()));
        return seen;
      }

      for (final kind in ['quiet', 'tail', 'dtail', 'ref']) {
        test('CAP SHAPE ($kind): compute, GET and recompute within the '
            "yield families' bounds (cost_bounds: once per line and recipe "
            'instance, a yield once per line, instance and servings string) '
            "and the backstop; each step's reads and step indexes pinned "
            "EXACTLY (indexes at v74's: no stored copy's index built — "
            'verify5 D2)', () async {
          final seen = await capShape(kind, (_, _) {});
          // Not vacuous: the tail shapes reach the share, ref the mark.
          expect(
            {
              for (final counts in seen.values)
                for (final MapEntry(:key, :value) in counts.entries)
                  if (key != 'indexes' && value > 0) key,
            },
            switch (kind) {
              'quiet' => <String>{},
              'ref' => {'memo:yieldMarks'},
              _ => {'memo:yieldShareReaders', 'yieldServingsReads'},
            },
          );
          // verify5 D2: the counts per step EXACTLY, the indexes v74's own
          // (verify5's probe of 776456f: quiet, tail, dtail 1 / 2 / 1; ref
          // 1 / 1 / 1) — the GET's second index is the base's, not a yield
          // read's (the GET reads no yield on these shapes).
          const reads = {
            'tail': {'memo:yieldShareReaders': 400, 'yieldServingsReads': 400},
            'dtail': {
              'memo:yieldShareReaders': 400,
              'yieldServingsReads': 24000,
            },
            'ref': {'memo:yieldMarks': 400},
          };
          final read = reads[kind] ?? const <String, int>{};
          expect(seen, {
            'compute': {...read, 'indexes': 1},
            'GET': {
              if (kind == 'ref') ...read,
              'indexes': kind == 'ref' ? 1 : 2,
            },
            'recompute': {...read, 'indexes': 1},
          });
        });
      }

      // verify4 D2: the TRUE path, the shape rule 1 exists for — every line
      // a reference by the yield-named tail: rtail1 routes each to its one
      // section (as the tart's line), rtail's 60 qualifying sections hold
      // each (the resolver's own list, ambiguous). v91 (batch M87): rtail2,
      // rtail1 with every line "1 pound cold pizza dough, i" — the two-word
      // arm's TRUE path (the base routes none: its first test refuses each
      // pair before any read); the same reads, once per line (fix91).
      for (final (kind, routes) in [
        ('rtail', false),
        ('rtail1', true),
        ('rtail2', true),
      ]) {
        test('ROUTING CAP SHAPE ($kind): every line names its own section at '
            'its yield (${routes ? 'routed to its one section' : 'held: 60 '
                      'own sections qualify'}); compute, GET and recompute '
            "each read a line's mark and share ONCE and its one yield once "
            '(pinned EXACTLY), within the bounds and the backstop; the '
            "recompute reads the stored copy's lines and builds no index of "
            "that copy (one, v74's — verify5 D2)", () async {
          final seen = await capShape(kind, (db, stored) {
            final memo = ResolverMemo(db);
            for (final l in nutritionLines(stored)) {
              expect(isReferenceIn(stored, l), isTrue, reason: kind);
            }
            final found = resolveReference(
              db,
              stored,
              nutritionLines(stored).first,
              memo,
            );
            expect(
              (found.kind, found.section, found.share),
              routes
                  ? (
                      ReferenceKind.routed,
                      (host: stored.id, title: 'Classic Pizza Dough'),
                      1.0,
                    )
                  : (ReferenceKind.held, null, null),
              reason: kind,
            );
          });
          const once = {
            'memo:yieldMarks': 400,
            'memo:yieldShareReaders': 400,
            'yieldServingsReads': 400,
          };
          expect(seen, {
            'compute': {...once, 'indexes': 1},
            'GET': {...once, 'indexes': 1},
            'recompute': {...once, 'indexes': 1},
          });
        });
      }
    },
    skip: skipIfNoCorpus,
  );

  group(
    "RULE C, the C4 pan fat (v75, M78, the owner's Q7 (c))",
    () {
      // STATED synthesized cost inputs (cap shapes no corpus recipe holds):
      // the real saltimbocca (0421) — its eleven lines and its real pound
      // and dredge sentences (S1, S2: C4 on a thin breast) — padded to the
      // 400-line cap with its own real line "4 tablespoons olive oil" and
      // to 120 × 10,000-character steps of "Add 1 tablespoon oil to the
      // skillet, then pour off the excess oil and wipe the pan." (every
      // sentence names the oil after the dredge and nearly matches both of
      // `_pansWiped`'s forms). quiet: no sentence pours off the fat or wipes
      // the skillet — the reader scans every sentence once and names no
      // line. loud (the TRUE path, the 2026-10-18 standing rule): the last
      // step ends with S4's real "Pour off the excess fat from the
      // skillet." — every oil line's mention lies in the window, so the
      // plan weighs all 390 oil lines at the one pan share.
      const salt = '0421-chicken-saltimbocca.yaml';
      const oil = '4 tablespoons olive oil';
      const filler =
          'Add 1 tablespoon oil to the skillet, then pour off the excess oil '
          'and wipe the pan. ';
      const pour = 'Pour off the excess fat from the skillet.';
      for (final loud in [false, true]) {
        test('CAP SHAPE (${loud ? 'loud' : 'quiet'}): 400 lines, 390 of them '
            '"$oil", under 120 × 10,000-character steps naming the oil'
            '${loud ? ' and ending in S4\'s "$pour" (every oil line a pan '
                      'line, weighed at the one share)' : ' (no pour-off, no '
                      'wipe: no pan line)'}: the reader once per index, the '
            'counts pinned EXACTLY; each path under the backstop', () async {
          final base = loadCorpusRecipe(salt);
          final own = [for (final g in base.ingredients) ...g.items];
          final r = capped(
            base,
            [
              for (final l in own) l.raw,
              for (var i = own.length; i < capLines; i++) oil,
            ],
            [
              base.steps[0].text,
              base.steps[1].text,
              for (var i = 2; i < capSteps - 1; i++) fill(filler, capStep),
              if (loud)
                '${fill(filler, capStep - pour.length)}$pour'
              else
                fill(filler, capStep),
            ],
          );
          final db = wp.tempDb();
          final provider = FixtureProvider(pending: pendingSearches);
          wp.saveRecipe(db, r);
          Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
          final seen = <String, Map<String, int>>{};
          Future<void> timed(
            String step,
            Future<Object?> Function() run,
          ) async {
            stepIndexCounts.clear();
            final sw = Stopwatch()..start();
            await run();
            final ms = sw.elapsedMilliseconds;
            final counts = Map.of(stepIndexCounts);
            final copies = counts['indexes'] ?? 1;
            expectBounded(r, counts, 'pan $step', copies: copies);
            seen[step] = counts;
            expect(ms, lessThan(backstopMs), reason: 'pan $step: $counts');
          }

          await timed('compute', () => matchAndCompute(db, provider, stored()));
          final oils = [
            for (final row in db.ingredientMatchesFor(r.id))
              if (row.raw == oil) row,
          ];
          expect(oils, hasLength(capLines - own.length + 1));
          expect(panFatLinesOf(stored()), hasLength(loud ? oils.length : 0));
          // The TRUE path: 9.918 g of fat (623.69 g of breast × 2 / 125.77)
          // over 390 × 56 g — each line 0.03 g, `discarded`; quiet: whole.
          expect(
            {for (final row in oils) (row.gramSource, row.grams)},
            {if (loud) ('discarded', 0.03) else ('portion', 56.0)},
          );
          await timed('GET', () => matchesBody(db, provider, stored()));
          await timed('recompute', () async => recomputeTotals(db, stored()));
          // EXACTLY, every path: one index, the reader once, and — on the
          // TRUE path only — each of the 391 fat lines (390 oil, |8's
          // butter) read once (quiet: no wipe, no line read).
          final once = {
            'indexes': 1,
            'memo:panFatLines': 1,
            'panFatLineReads': loud ? 391 : null,
          };
          expect(
            {
              for (final MapEntry(:key, :value) in seen.entries)
                key: {for (final k in once.keys) k: value[k]},
            },
            {'compute': once, 'GET': once, 'recompute': once},
          );
        });
      }
    },
    skip: skipIfNoCorpus,
  );

  group(
    "RULE C, the racks' dry-heat gate (v76, M79, the orchestrator's Q10 "
    '(b′))',
    () {
      final design = RegExp(r'\bpour off\b[^.]*\bfat\b');

      test("the pour-off test answers as the design's regex (30,000 seeded "
          'sentences over its own words) and reads "fat" then "pour off" '
          'repeated — no fat after any pour-off, the shape on which the '
          "regex's `[^.]*` is quadratic — at 1,000 / 10,000 / 100,000 "
          'characters a sentence in one pass each', () {
        const atoms = [
          'pour off', 'pour', 'off', 'pouring', 'poured off', 'fat', 'fats', //
          'fatty', 'pour offfat', 'off fat', 'the', '.', '1.5', 'x', ',', '\n',
          'liquid',
        ];
        var hits = 0;
        var misses = 0;
        for (var seed = 0; seed < 30000; seed++) {
          final r = Random(seed);
          final b = StringBuffer();
          for (var i = 0, n = 1 + r.nextInt(12); i < n; i++) {
            b.write(atoms[r.nextInt(atoms.length)]);
            if (r.nextInt(3) > 0) {
              b.write(' ');
            }
          }
          final s = b.toString();
          final reference = design.hasMatch(s);
          expect(pourOffFatSentence(s), reference, reason: '"$s"');
          reference ? hits++ : misses++;
        }
        // Not vacuous either way.
        expect(hits, greaterThan(1000));
        expect(misses, greaterThan(1000));
        // Measured on this loop's own shapes (warm medians, and this loop
        // run cold in a fresh process; the closer and three verifiers): the
        // tree reads one such sentence in ≈ 1–4 / 7–11 / 64–91 µs at 1k /
        // 10k / 100k characters (at most ×10 per ×10 — linear; the 1k read
        // carries the call's fixed cost) and the design's regex in
        // ≈ 249–265 µs / 21–22 ms / 1.9–2.1 s (×80–97 per ×10 —
        // quadratic). Each pass below is ≈ 1.2 MB (2 × 100k for the last):
        // ≤ 5 ms on the tree and ≥ 290 ms for a restored regex — 100 ms
        // kills it by ≥ 2.9×.
        for (final (length, count) in const [
          (1000, 1200),
          (10000, 120),
          (100000, 2),
        ]) {
          final shape = 'fat ${'pour off ' * ((length - 6) ~/ 9)}x.';
          expect(shape.length, inInclusiveRange(length - 9, length));
          final hostile = List.filled(count, shape);
          final sw = Stopwatch()..start();
          for (final s in hostile) {
            expect(pourOffFatSentence(s), isFalse);
          }
          expect(sw.elapsedMilliseconds, lessThan(100), reason: '$length');
        }
      });

      // STATED synthesized cost inputs (cap shapes no corpus recipe holds):
      // the real roast rack (0228) — its own lines — padded to the 400-line
      // cap with its own real rack line (each lands on 174377 by the
      // "trimmed" entry), under 120 × 10,000-character steps of "Trim the
      // fat, preheat grill and preheat oven, then pour off the juices."
      // (every sentence names the grill, the oven, a pour-off and fat, and
      // matches none of the three tests). quiet: no cooking answer, every
      // rack gross. The TRUE paths (the 2026-10-18 standing rule): the last
      // step ends with 0622 S1's real "Heat grill until hot, about 5
      // minutes." (broiled — the grill scan reads every sentence first) or
      // 0228 S1's and S3's real sentences (roasted — all three scans read
      // every sentence first).
      const roast =
          '0228-roast-rack-of-lamb-with-roasted-red-pepper-relish.yaml';
      const rack =
          '2 racks of lamb (1¾ to 2 pounds each), fat trimmed to ⅛ to ¼ inch, '
          'rib bones frenched';
      const filler =
          'Trim the fat, preheat grill and preheat oven, then pour off the '
          'juices. ';
      const ends = {
        'quiet': '',
        'broiled': 'Heat grill until hot, about 5 minutes.',
        'roasted':
            'Adjust oven rack to middle position and heat oven to 250 '
            'degrees. Pour off all but 1 teaspoon fat from skillet and repeat '
            'with second rack.',
      };
      for (final MapEntry(key: shape, value: end) in ends.entries) {
        test('CAP SHAPE ($shape): 400 lines, ${capLines - 9} of them the rack '
            'on 174377, under 120 × 10,000-character steps naming a grill, an '
            'oven, a pour-off and fat${end.isEmpty ? ' (no cooking: gross)' : ' and ending in "$end"'}: '
            'the gate once per index, the counts pinned EXACTLY; each path '
            'under the backstop', () async {
          final base = loadCorpusRecipe(roast);
          final own = [for (final g in base.ingredients) ...g.items];
          final r = capped(
            base,
            [
              for (final l in own) l.raw,
              for (var i = own.length; i < capLines; i++) rack,
            ],
            [
              for (var i = 0; i < capSteps - 1; i++) fill(filler, capStep),
              '${fill(filler, capStep - end.length)}$end',
            ],
          );
          final db = wp.tempDb();
          final provider = FixtureProvider(pending: pendingSearches);
          wp.saveRecipe(db, r);
          Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
          final seen = <String, Map<String, int>>{};
          Future<void> timed(
            String step,
            Future<Object?> Function() run,
          ) async {
            stepIndexCounts.clear();
            final sw = Stopwatch()..start();
            await run();
            final ms = sw.elapsedMilliseconds;
            final counts = Map.of(stepIndexCounts);
            final copies = counts['indexes'] ?? 1;
            expectBounded(r, counts, 'rack $step', copies: copies);
            seen[step] = counts;
            expect(ms, lessThan(backstopMs), reason: 'rack $step: $counts');
          }

          await timed('compute', () => matchAndCompute(db, provider, stored()));
          final racks = [
            for (final row in db.ingredientMatchesFor(r.id))
              if (row.raw == rack) row,
          ];
          expect(racks, hasLength(capLines - own.length + 1));
          expect({for (final row in racks) row.fdcId}, {174377});
          for (final row in racks) {
            expect(
              braisedKeptOf(row.raw, 174377, stored()),
              end.isEmpty ? isNull : dryHeatKept[174377]![shape],
            );
          }
          await timed('GET', () => matchesBody(db, provider, stored()));
          await timed('recompute', () async => recomputeTotals(db, stored()));
          // EXACTLY, every path and shape: one index, the gate once.
          const once = {'indexes': 1, 'memo:dryHeat': 1};
          expect(
            {
              for (final MapEntry(:key, :value) in seen.entries)
                key: {for (final k in once.keys) k: value[k]},
            },
            {'compute': once, 'GET': once, 'recompute': once},
          );
        });
      }
    },
    skip: skipIfNoCorpus,
  );
}
