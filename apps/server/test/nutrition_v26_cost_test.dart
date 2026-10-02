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
            '_namesOf': (
              () => readAll(loadCorpusRecipe(chicken)),
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

/// Recorded answers, and no search hit for the synthesized lines.
class _NoHits extends FixtureProvider {
  _NoHits() : super(pending: pendingSearches);
  @override
  Future<List<FdcCandidate>> search(String q) async => const [];
}
