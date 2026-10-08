// Run 057 S9 (matcher v27, RULE C): every memo of the step index keyed by
// EVERY coordinate its derivation reads. A key that drops one answers a
// later caller from an earlier caller's derivation, and no COUNT pin can
// see it (a looser key derives FEWER times; 23 such mutants survived
// v26's suite). The oracle: every detector's answer for every line with
// the memos on — lines read in recipe order, then in reverse on a fresh
// index — equals its answer with every memo derived afresh
// ([memoOffForTest]). Each coordinate of each key (enumerated beside the
// key in engine.dart) is killed by a drop-one-coordinate mutant here.
//
// Real corpus recipes (all 1,198) with a recorded FDC food
// (FixtureProvider), never the network. Synthesized, a stated exception:
// the typed lines and sentences added to real recipes below, each making
// two reads of one key differ in a single coordinate — shapes no corpus
// recipe holds (named per recipe).
// ignore_for_file: lines_longer_than_80_chars
import 'dart:io';

import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

IngredientLine _p(String raw) {
  final p = parseIngredientLine(raw);
  return IngredientLine(
    raw: raw,
    item: p.item,
    prep: p.prep,
    amounts: p.amounts,
  );
}

/// [base] with [lines] added to its first group and [steps] added after
/// its steps ([first]: before them; [lead]: lines before its own); with
/// [only], [lines] and [steps] are its lines and steps.
Recipe typed(
  String base, {
  List<String> lines = const [],
  List<IngredientLine> items = const [],
  List<String> steps = const [],
  List<String> first = const [],
  bool only = false,
  List<String> lead = const [],
}) {
  final r = loadCorpusRecipe(base);
  final texts = [
    ...first,
    if (!only)
      for (final s in r.steps) s.text,
    ...steps,
  ];
  return r.copyWith(
    ingredients: [
      r.ingredients.first.copyWith(
        items: [
          for (final l in lead) _p(l),
          if (!only) ...r.ingredients.first.items,
          for (final l in lines) _p(l),
          ...items,
        ],
      ),
      if (!only) ...r.ingredients.skip(1),
    ],
    steps: [
      for (final (i, t) in texts.indexed) RecipeStep(number: i + 1, text: t),
    ],
  );
}

/// Every detector's answer for each line of [make]'s recipe, in line
/// order; read in [reversed] line order on a fresh index.
List<String> answers(
  Recipe Function() make,
  FdcFood food, {
  bool reversed = false,
  List<String> extra = const [],
}) {
  final r = make();
  // [extra]: lines read against the recipe that are not among its lines (a
  // caller's line whose names the per-recipe indexes never searched).
  final lines = [...nutritionLines(r), for (final raw in extra) _p(raw)];
  final out = List.filled(lines.length, '');
  for (final i in [
    for (var i = 0; i < lines.length; i++) reversed ? lines.length - 1 - i : i,
  ]) {
    final line = lines[i];
    final item = normalizeItem(lineItemOf(line));
    final o = engineOutcome(
      r,
      line,
      food,
      resolveGrams(
        amounts: line.amounts,
        food: food,
        normalizedItem: item,
        raw: line.raw,
      ),
      picked: true,
    );
    out[i] = [
      discardedMediumOf(r, line, item),
      discardedMediumOf(r, line, item, bySentence: false),
      heldMediumLine(r, weighedLine(r, line)),
      keptLiquidOf(r, line),
      for (final hold in ['coating', 'partial_pour_away', 'ambiguous_medium'])
        holdNoteOf(r, line, hold),
      o.grams,
      o.source,
      o.hold,
      // v59 (M60 P7a): read once per head (closer 2, verifier 2 D2).
      stepsPeelIn(r, line),
    ].join(' | ');
  }
  return out;
}

/// The oracle on [make]: the memos on (both orders) answer as the memos
/// off do.
void expectExact(
  Recipe Function() make,
  FdcFood food,
  String name, [
  List<String> extra = const [],
]) {
  memoOffForTest = true;
  final List<String> fresh;
  try {
    fresh = answers(make, food, extra: extra);
  } finally {
    memoOffForTest = false;
  }
  expect(answers(make, food, extra: extra), fresh, reason: '$name, in order');
  expect(
    answers(make, food, reversed: true, extra: extra),
    fresh,
    reason: '$name, reversed',
  );
}

Future<FdcFood> _oil() async => (await FixtureProvider().food(2710180))!;

/// The typed recipes, each named for the key coordinate it separates.
final Map<String, Recipe Function()> typedRecipes = {
  // oilOwners (head): an olive oil read before a frying lard (Run 057 S9).
  'oilOwners head': () => typed(
    '0806-pita-bread.yaml',
    lines: ['1 cup lard'],
    steps: ['Heat the lard in a large skillet to 350 degrees.'],
  ),
  // rinsedCure (head): the salt rubbed and rinsed off, the sugar not.
  'rinsedCure head': () => typed(
    '0806-pita-bread.yaml',
    lines: ['1/4 cup sugar', '1/4 cup kosher salt'],
    steps: ['Rub the pork with the salt.', 'Rinse the pork and pat it dry.'],
  ),
  // says (word): a brine step naming the salt, not the sugar.
  'says word': () => typed(
    '0806-pita-bread.yaml',
    lines: ['1/4 cup kosher salt', '1/4 cup sugar'],
    steps: ['Dissolve the salt in 2 quarts water to make a brine.'],
  ),
  // says (pattern): no brine step, a rub step naming the salt.
  'says pattern': () => typed(
    '0806-pita-bread.yaml',
    lines: ['1/4 cup kosher salt'],
    steps: ['Rub the pork with the salt.'],
  ),
  // amountWriters (head): a flour line writes the teaspoon the cornstarch
  // dredge's sauce eats.
  'amountWriters head': () => typed(
    '0148-crispy-fried-chicken.yaml',
    lines: ['1 cup cornstarch', '1 teaspoon all-purpose flour'],
    steps: [
      'Dredge the chicken in the cornstarch.',
      'Whisk 1 teaspoon cornstarch and 1 teaspoon flour into the gravy.',
    ],
  ),
  // naming (head): a head of other characters ("2%", read by its own scan)
  // beside the first word head asked (also read by its own scan, v27): the
  // garlic parted from the pasta water, the 2% named nowhere (its "%"
  // ends no word).
  'naming head': () => typed(
    _neutral,
    lines: ['1 cup garlic', '1 cup 2%'],
    steps: [
      'Whisk the garlic into the water and add the pasta. Drain the pasta and discard the water.',
    ],
    only: true,
  ),
  // lifted (step): a skimmer lifting from water, and one lifting from a
  // plate, each the step after a pot.
  'lifted step': () => typed(
    _neutral,
    lines: ['1 tablespoon sugar', '1 teaspoon salt'],
    steps: [
      'Bring 4 quarts water and 1 tablespoon sugar to a boil.',
      'Using a slotted spoon, lift the bagels from the water.',
      'Bring 2 quarts water and 1 teaspoon salt to a boil.',
      'Using a slotted spoon, transfer the chicken to a plate.',
    ],
  ),
  // parted (head): one sentence parts the sugar from the liquid, not the
  // salt it drains (a food is never parted from itself).
  'parted head': () => typed(
    _neutral,
    lines: ['1 teaspoon salt', '1 teaspoon sugar'],
    steps: [
      'Whisk 1 teaspoon salt and 1 teaspoon sugar into the water. Drain the salt and discard the water.',
    ],
  ),
  // parted (step): the salt's first mention parts nothing, its second, in
  // the next step, parts it.
  'parted step': () => typed(
    _neutral,
    lines: ['1 teaspoon salt'],
    steps: [
      'Season the beef with 1 teaspoon salt.',
      'Whisk 1 teaspoon salt into the water and add the pasta. Drain the pasta and discard the water.',
    ],
  ),
  // parted (sentence): both mentions in one step.
  'parted sentence': () => typed(
    _neutral,
    lines: ['1 teaspoon salt'],
    steps: [
      'Whisk 1 teaspoon salt into the sauce. Whisk 1 teaspoon salt into the water and add the pasta. Drain the pasta and discard the water.',
    ],
  ),
  // sugarBeside (step): 0656's salt bath, its own first mentions without
  // the sugar in a step before its dunk (one in each sentence the dunk's
  // step names the sugar in).
  'sugarBeside step': () => typed(
    '0656-grilled-cauliflower.yaml',
    first: [
      'Season the cauliflower with salt. Sprinkle the wedges with salt.',
    ],
  ),
  // sugarBeside (sentence): that mention first in the dunk's own step.
  'sugarBeside sentence': () {
    final r = loadCorpusRecipe('0656-grilled-cauliflower.yaml');
    return r.copyWith(
      steps: [
        for (final s in r.steps)
          s.text.startsWith('Whisk 2 cups water')
              ? s.copyWith(text: 'Season the cauliflower with salt. ${s.text}')
              : s,
      ],
    );
  },
  // drainedLater (step): 0572's soda, a typed boil prepended (its first
  // sentence shares the start of the soda's own, Run 056 Opus critic 1).
  'drainedLater step': () => typed(
    '0572-ultracreamy-hummus.yaml',
    first: ['Bring 1 cup water and baking soda to boil in kettle.'],
  ),
  // drainedLater (start): two sentences of one boiling step, only the
  // second naming a food drained two steps later.
  'drainedLater start': () => typed(
    _neutral,
    lines: ['1 teaspoon salt', '1 teaspoon baking soda'],
    steps: [
      'Bring water to a boil with 1 teaspoon salt. Add the chickpeas and 1 teaspoon baking soda to the water and boil.',
      'Simmer for 1 hour.',
      'Drain the chickpeas.',
    ],
  ),
  // eatenOrder (medium): the flour's written parts in one order outside
  // the dredge and another after the braise's strain.
  'eatenOrder medium': () => typed(
    _neutral,
    lines: ['1 teaspoon all-purpose flour'],
    steps: [
      'Whisk 1 tablespoon flour into the broth.',
      'Stir 1 teaspoon flour into the sauce.',
      'Strain the cooking liquid through a fine-mesh strainer; reserve 2 cups liquid.',
      'Whisk 1 teaspoon flour into the liquid. Whisk 1 tablespoon flour into the liquid.',
    ],
  ),
  // plusNamed (head): one plus amount, the salt's eaten in a rub, the
  // oil's named in no step.
  'plusNamed head': () => typed(
    _neutral,
    lines: [
      '1/4 cup plus 5 teaspoons table salt',
      '2 cups plus 5 teaspoons vegetable oil',
    ],
    steps: [
      'Dissolve 1/4 cup salt in 2 quarts water to make a brine.',
      'Heat 2 cups oil to 350 degrees and fry the chicken.',
      'Rub the chicken with the remaining 5 teaspoons salt.',
    ],
  ),
  // plusSteps (name) and dissolvingWith (own): lines read against the
  // recipe that are not its own (their names unsearched by its indexes).
  'unsearched names': () => typed(
    _neutral,
    lines: ['1/4 cup kosher salt'],
    steps: [
      'Dissolve the qx salt and 1/4 cup kosher salt in 2 quarts water to make a brine.',
      'Rub the chicken with the remaining 2 teaspoons salt.',
    ],
  ),
  // dissolvedWith (own): two small salts, one dissolved with the brine.
  'dissolvedWith own': () => typed(
    _neutral,
    lines: ['1/4 cup kosher salt', '1 teaspoon qx salt', '1 teaspoon qy salt'],
    steps: [
      'Dissolve the qx salt and 1/4 cup kosher salt in 2 quarts water to make a brine.',
      'Dissolve the qy salt in the sauce.',
    ],
  ),
  // keptOil (raw): two frying oils of one item, each its own pour-off.
  'keptOil raw': () => typed(
    _neutral,
    lines: ['3 cups vegetable oil', '4 cups vegetable oil'],
    steps: [
      'Heat 3 cups oil to 350 degrees and fry the chicken; pour off all but 2 tablespoons oil.',
      'Heat 4 cups oil to 375 degrees and fry the potatoes; pour off all but 1/4 cup oil.',
    ],
  ),
  // keptOil (item): one raw, two items (a typed item the API stores
  // beside its raw).
  'keptOil item': () => typed(
    _neutral,
    items: [
      IngredientLine(
        raw: '3 cups vegetable oil',
        item: 'vegetable oil',
        amounts: _p('3 cups vegetable oil').amounts,
      ),
      IngredientLine(
        raw: '3 cups vegetable oil',
        item: 'lard',
        amounts: _p('3 cups vegetable oil').amounts,
      ),
    ],
    steps: [
      'Heat the oil to 350 degrees and fry the chicken. Pour off all but 2 tablespoons oil.',
      'Heat the lard to 350 degrees and fry the potatoes. Pour off all but 1 tablespoon lard.',
    ],
  ),
};

/// The out-of-recipe lines each typed recipe reads ([answers]' `extra`).
const extraLines = {
  'unsearched names': [
    '1/4 cup plus 2 teaspoons table salt',
    '1/4 cup plus 3 teaspoons table salt',
    '1 teaspoon qx salt',
    '1 teaspoon qy salt',
  ],
};

/// A corpus recipe naming no salt, sugar, soda, water, flour, brine,
/// rinse, rub, drain, boil, dissolving or skimmer (1138 Stir-Fried Beef
/// and Gai Lan): the typed lines and steps alone exercise the detectors.
const _neutral = '1138-stir-fried-beef-and-gai-lan.yaml';

void main() {
  group('Memo exactness (Run 057 S9): the memos on answer as the memos '
      'off, in either line order', () {
    test('every corpus recipe', () async {
      final food = await _oil();
      final files =
          Directory(corpusRecipesDir)
              .listSync()
              .map((f) => f.path.split('/').last)
              .where((f) => f.endsWith('.yaml'))
              .toList()
            ..sort();
      expect(files, hasLength(1198));
      for (final f in files) {
        expectExact(() => loadCorpusRecipe(f), food, f);
      }
    }, timeout: const Timeout(Duration(minutes: 10)));
    for (final MapEntry(:key, :value) in typedRecipes.entries) {
      test(
        key,
        () async =>
            expectExact(value, await _oil(), key, extraLines[key] ?? const []),
      );
    }
  }, skip: skipIfNoCorpus);
}
