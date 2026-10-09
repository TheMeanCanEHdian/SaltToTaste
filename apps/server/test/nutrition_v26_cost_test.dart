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
          'Place the flour in a shallow baking dish. Beat the egg and buttermilk in a medium bowl. Dredge each onion ring in the flour, shaking off the excess. Dip in the buttermilk mixture, allowing the excess to drip back into the bowl. Bake the onion rings until golden brown. ',
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
          {
            switch (shape) {
              'held-dips' => (null, 'coating'),
              'flag-dips' => (100.0, null),
              'w-batter' => (7.91, null),
              _ => (0.11, null),
            },
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
            'egg-dips' => {('confirmed', 0.11, null)},
            'flag-dips' => {('confirmed', 100.0, null)},
            'w-batter' => {('confirmed', 7.91, null)},
            // The picked half counted whole; the auto half at E-w's grams
            // on its 199 dips.
            'egg-picks' => {('overridden', 100.0, null), ('auto', 0.21, null)},
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
        expect(before, hasLength(dips ? 3 : 2), reason: '$before');
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
