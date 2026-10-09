// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v58 (batch M59, the frying oil the steps keep or rinse off, and a
// battered vegetable's uptake; matcherVersion 57; prep48 design_v2 §2 M59
// C + F1 + D, the owner's Q13 (b), critic F1, F9 and F12; decided
// 2026-10-08 under the standing authorization; zero requests;
// step-reading, pre-Q18): "After frying, reserve 2 tablespoons frying oil"
// is a frying oil's kept part when a later sentence heats the reserved oil
// (engine `_Fat.reserveFrying`), the uptake on top; a frying oil's part a
// sentence tosses with a food is not eaten when later sentences of the same
// step drain and rinse (`_rinsedOff`; no food is matched — the step stands
// in for the tossed one); the fried cauliflower's read u
// scales to its group's batter carbohydrate against FNDDS 2710042's (c_b
// 0.40), flagged "derived". Every row value is the v58 replay of snapshot
// 23 (rp43, fix58 r1), computed here on WHOLE recipes over recorded real
// FDC answers (FixtureProvider), never the network. Synthesized, STATED
// (no corpus recipe holds them): the step orders and sentences the pure
// pins below put into real recipes.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

/// (file, position, raw, fdc id, confidence, grams, kcal, basis) — the v58
/// replay's row; kcal is grams × the record's energy.
typedef _Row = (String, int, String, int?, String, String?, String, String?);

const _saltPepper = '0279-crispy-salt-and-pepper-shrimp.yaml';
const _orangeBeef = '0536-crispy-orange-beef.yaml';
const _fishChips = '0255-fish-and-chips.yaml';
const _cauliflower = '0672-buffalo-cauliflower-bites.yaml';
const _horseradish = '0215-horseradish-crusted-beef-tenderloin.yaml';
const _sesameNoodles = '0519-sesame-noodles-with-shredded-chicken.yaml';
const _thaiNoodles =
    '0553-thai-style-stir-fried-noodles-with-chicken-and-broccolini.yaml';
const _padThai = '0554-shrimp-pad-thai.yaml';
const _tempura = '0511-shrimp-tempura.yaml';
const _sandwiches = '1081-crispy-fish-sandwiches-with-tartar-sauce.yaml';
const _buffaloWings = '0151-buffalo-wings.yaml';
const _almond = '0042-almond-crusted-chicken-with-wilted-spinach-salad.yaml';

/// M59's reach (design_v2 §2 M59, exactly these 4 rows; −578.07 kcal per
/// batch): C's two reserved 2 tablespoons (28.00 g, 14.00 g a tablespoon on
/// 2710180's portion) on top of the uptake; F1's rinsed ¼ cup (56.00 g)
/// off fish-and-chips' oil — 170.78 at full precision (15.38 % × 680.39 g
/// cod + 6.0 % × 1,102.23 g potatoes = 170.7776; §2's 170.77 / −504.09 were
/// 226.78 − 56.01 on rounded figures); D's cauliflower at 16.16 % (30.32 ×
/// 122.16 / 229.20 — C at full precision; §2's 122.17 summed the rounded
/// grams).
const List<_Row> _reach = [
  // v57: 36.06 g, 324.54 kcal
  (
    _saltPepper,
    7,
    '4 cups vegetable oil',
    2710180,
    '0.923333',
    '64.06',
    '576.54',
    'discarded in cooking — only the part the recipe keeps and the oil the fried food absorbs counted · approximation (frying oil absorbed: 5.3 % of the raw shrimp\'s weight — derived from USDA SR Legacy 171982 "Mollusks, squid, mixed species, cooked, fried")',
  ),
  // v57: 67.29 g, 605.61 kcal
  (
    _orangeBeef,
    8,
    '3 cups vegetable oil',
    2710180,
    '0.923333',
    '95.29',
    '857.61',
    "discarded in cooking — only the part the recipe keeps and the oil the fried food absorbs counted · approximation (frying oil absorbed: 9.89 % of the raw beef's weight — USDA FNDDS 2705842 recipe: 9 g oil per 90.99 g raw beef steak (no record for beef; read as Beef, steak, country fried))",
  ),
  // v57: 226.78 g. The replay reads 2710187 (0.990000, 1,537.02 kcal);
  // a fresh compute reads 172336 (as v57's test states) — grams and basis
  // equal.
  (
    _fishChips,
    1,
    '3 quarts plus ¼ cup peanut oil or canola oil',
    172336,
    '0.683333',
    '170.78',
    '1509.70',
    'discarded in cooking — only the oil the fried food absorbs counted ("plus ¼ cup peanut oil or canola oil": the steps rinse it off) · approximation (frying oil absorbed: 15.38 % of the raw cod\'s weight — USDA FNDDS 2706244 recipe: 10 g oil per 65 g raw cod; 6.0 % of the raw potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil")',
  ),
  // v57: 137.53 g, 1,237.77 kcal
  (
    _cauliflower,
    4,
    '1–2 quarts peanut or vegetable oil',
    2710187,
    '0.673333',
    '73.30',
    '659.70',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed — derived: 16.16 % of the raw cauliflower's weight — USDA FNDDS 2710042 recipe: 12 g oil per 39.58 g raw cauliflower, scaled to the recipe's batter (122.16 g of 229.20 g carbohydrate))",
  ),
];

/// Rows M59 must not move (each equal to v57): the shipped reserve form
/// (horseradish), the sesame oil beside 0536's reserve, the noodle oils
/// the steps rinse THEN oil (`portion` rows outside `_Fat`'s reach), the
/// uptakes D leaves at their read figure (O2s, O2, the wing, the breast)
/// and the cauliflower group's four batter rows C sums.
const List<_Row> _kept = [
  (
    _horseradish,
    3,
    '1 cup plus 2 teaspoons vegetable oil',
    2710180,
    '0.923333',
    '38.09',
    '342.81',
    'discarded in cooking — only "plus 2 teaspoons vegetable oil", the 1 tablespoon the steps keep and the oil the fried food absorbs counted · approximation (frying oil absorbed: 10.9 % of the raw potatoes\' weight — derived from USDA SR Legacy 19411 "Snacks, potato chips, plain, salted")',
  ),

  (
    _orangeBeef,
    7,
    '1½ teaspoons toasted sesame oil',
    2710190,
    '0.673333',
    '6.80',
    '60.13',
    '1 1/2 teaspoon ≈ 7 mL',
  ),

  (
    _sesameNoodles,
    11,
    '2 tablespoons toasted sesame oil',
    2710190,
    '0.673333',
    '28.00',
    '247.52',
    '2 tablespoon · USDA portion',
  ),

  (
    _thaiNoodles,
    5,
    '¼ cup vegetable oil',
    2710180,
    '0.923333',
    '56.00',
    '504.00',
    '1/4 cup · USDA portion',
  ),

  (
    _padThai,
    6,
    '3 tablespoons plus 2 teaspoons vegetable oil',
    2710180,
    '0.923333',
    '51.07',
    '459.62',
    '3 tablespoon · USDA portion + 2 teaspoons vegetable oil',
  ),

  (
    _tempura,
    0,
    '3 quarts peanut or vegetable oil',
    2710187,
    '0.673333',
    '104.64',
    '941.76',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 15.38 % of the raw shrimp's weight — USDA FNDDS 2706364 recipe: 10 g oil per 65 g raw shrimp)",
  ),

  (
    _sandwiches,
    11,
    '2 quarts peanut or vegetable oil for frying',
    2710187,
    '0.500000',
    '87.20',
    '784.80',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 15.38 % of the raw haddock's weight — USDA FNDDS 2706258 recipe: 10 g oil per 65 g raw haddock)",
  ),

  (
    _buffaloWings,
    5,
    '1–2 quarts peanut oil, for frying',
    2710187,
    '0.990000',
    '44.97',
    '404.73',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.61 % of the raw chicken wings' weight — USDA FNDDS 2706065 recipe: 7 g oil per 105.96 g raw chicken wing)",
  ),

  (
    _almond,
    7,
    '¾ cup plus 2 tablespoons vegetable oil',
    2710180,
    '0.923333',
    '69.66',
    '626.94',
    'discarded in cooking — only "plus 2 tablespoons vegetable oil" and the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast\'s weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)',
  ),

  (
    _cauliflower,
    5,
    '¾ cup cornstarch',
    169698,
    '1.000000',
    '95.82',
    '365.07',
    '3/4 cup ≈ 177 mL',
  ),

  (
    _cauliflower,
    6,
    '¼ cup cornmeal',
    169697,
    '0.870000',
    '39.04',
    '141.31',
    '1/4 cup ≈ 59 mL',
  ),

  (
    _cauliflower,
    8,
    '⅔ cup canned coconut milk',
    170173,
    '0.860000',
    '162.46',
    '320.04',
    '2/3 cup ≈ 158 mL',
  ),

  (
    _cauliflower,
    9,
    '1 tablespoon hot sauce',
    2710093,
    '0.923333',
    '16.00',
    '1.92',
    '1 tablespoon · USDA portion',
  ),
];

/// The row's energy, as the totals read it (the record's first energy
/// number, else its Atwater sum): grams × kcal per 100 g.
double _kcalOf(SaltDatabase db, IngredientMatchRow row, IngredientLine line) {
  final grams = row.grams ?? 0;
  if (grams <= 0) {
    return 0;
  }
  expect(nutrientSiblings[row.fdcId], isNull);
  final food = knownFood(db, row.fdcId!, line: line)!;
  for (final number in nutrientDefs.first.fdcNumbers) {
    if (food.nutrientsPer100g[number] case final per100?) {
      return per100 * grams / 100;
    }
  }
  return kcalPer100g(food) * grams / 100;
}

void main() {
  test('the matcher version carries the batch (update the literal with a '
      'bump)', () {
    // RE-PIN (M60 batch, v59): matcherVersion 58 (was 57).
    // RE-PIN (M61 batch, v60): matcherVersion 59 (was 58).
    // RE-PIN (M62 batch, v61): matcherVersion 60 (was 59).
    // RE-PIN (M63 batch, v62): matcherVersion 61 (was 60).
    // RE-PIN (M64 batch, v63): matcherVersion 62 (was 61).
    // RE-PIN (M65 batch, v64): matcherVersion 63 (was 62).
    expect(matcherVersion, 63);
  });

  group('matcher v58 (batch M59)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v58-');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath)
        ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: pendingSearches);
      // Each recipe stored and computed whole, its sections first (the
      // cauliflower's Ranch Dressing), as the replay does.
      for (final (file, _, _, _, _, _, _, _) in [..._reach, ..._kept]) {
        if (recipes.containsKey(file)) {
          continue;
        }
        final host = loadCorpusRecipe(file);
        db.upsertRecipe(host, sourceSlug: _source, contentHash: host.id);
        final stored = db.recipeByIdOrSlug(host.id)!.recipe;
        for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
          expect(
            await matchAndCompute(
              db,
              provider,
              nutritionRecipeOf(db, key)!.recipe,
            ),
            isNull,
          );
        }
        expect(await matchAndCompute(db, provider, stored), isNull);
        recipes[file] = db.recipeByIdOrSlug(host.id)!.recipe;
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    IngredientMatchRow rowOf(String file, int position) => db
        .ingredientMatchesFor(recipes[file]!.id)
        .singleWhere((m) => m.position == position);

    String? basisOf(String file, int position) => gramBasisFor(
      db,
      nutritionLines(recipes[file]!)[position],
      rowOf(file, position),
      recipe: recipes[file],
    );

    /// Each [rows] entry computed in its whole recipe: the record, the
    /// confidence, the grams, the energy and the basis; no hold.
    void expectRows(List<_Row> rows) {
      for (final (file, position, raw, fdcId, confidence, grams, kcal, basis)
          in rows) {
        final line = nutritionLines(recipes[file]!)[position];
        final row = rowOf(file, position);
        final reason = '$file|$position';
        expect(line.raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.confidence.toStringAsFixed(6), confidence, reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(row.status, 'auto', reason: reason);
        expect(row.hold, isNull, reason: reason);
        expect(_kcalOf(db, row, line).toStringAsFixed(2), kcal, reason: reason);
        expect(basisOf(file, position), basis, reason: reason);
      }
    }

    /// What the engine keeps of [file]'s frying-oil line [position] before
    /// any uptake ([engineOutcome]'s eaten part), on [recipe] — the real
    /// one unless a synthesized variant is given.
    double? keptOf(String file, int position, [Recipe? recipe]) {
      final real = recipes[file]!;
      final line = nutritionLines(real)[position];
      final food = knownFood(db, rowOf(file, position).fdcId!, line: line)!;
      final on = recipe ?? real;
      return engineOutcome(
        on,
        line,
        food,
        lineGrams(db, line, food, recipe: on),
        decided: true,
      ).grams;
    }

    test('M59 reaches exactly its 4 rows (design_v2 §2 M59)', () {
      expect(_reach, hasLength(4));
      expectRows(_reach);
      String g(String file, int position) =>
          rowOf(file, position).grams!.toStringAsFixed(2);
      expect(g(_saltPepper, 7), '64.06');
      expect(g(_orangeBeef, 8), '95.29');
      expect(g(_fishChips, 1), '170.78');
      expect(g(_cauliflower, 4), '73.30');
      expect(basisOf(_fishChips, 1), contains('the steps rinse it off'));
      // F12: C_recipe, the group's batter carbohydrate, in the flag.
      expect(
        basisOf(_cauliflower, 4),
        contains(
          "scaled to the recipe's batter (122.16 g of 229.20 g "
          'carbohydrate))',
        ),
      );
    });

    test('the rows M59 must not move equal v57', () {
      expectRows(_kept);
    });

    test('C: the reserved 2 tablespoons are kept (28.00 g) only because a '
        'LATER sentence heats the reserved oil — STATED synthesized: 0279 '
        'without its step 6 keeps none', () {
      expect(keptOf(_saltPepper, 7)?.toStringAsFixed(2), '28.00');
      expect(keptOf(_orangeBeef, 8)?.toStringAsFixed(2), '28.00');
      final shrimp = recipes[_saltPepper]!;
      expect(
        shrimp.steps.last.text,
        startsWith('Heat reserved oil in 12-inch skillet'),
      );
      final noHeat = shrimp.copyWith(steps: [...shrimp.steps]..removeLast());
      expect(keptOf(_saltPepper, 7, noHeat)?.toStringAsFixed(2), '0.00');
    });

    test('F1: the ¼ cup tossed with the fries is rinsed off (0 g) — STATED '
        'synthesized pair: rinsed BEFORE the toss, or drained and never '
        'rinsed, rinsed undrained, or poured on untossed, the part is kept', () {
      final chips = recipes[_fishChips]!;
      final step1 = chips.steps.first;
      const drainRinse =
          'Carefully pull back the plastic wrap from the side farthest from '
          'you and drain the potatoes into a large mesh strainer set over a '
          'sink. Rinse well under cold running water. ';
      expect(step1.text, contains(drainRinse));
      Recipe withStep1(String text) => chips.copyWith(
        steps: [
          step1.copyWith(text: text),
          ...chips.steps.skip(1),
        ],
      );
      // The ¼ cup on the fresh compute's 172336 weighs 54.42 g (56.00 g on
      // the replay's 2710187).
      expect(keptOf(_fishChips, 1)?.toStringAsFixed(2), '0.00');
      expect(
        keptOf(
          _fishChips,
          1,
          withStep1(drainRinse + step1.text.replaceFirst(drainRinse, '')),
        )?.toStringAsFixed(2),
        '54.42',
      );
      expect(
        keptOf(
          _fishChips,
          1,
          withStep1(
            step1.text.replaceFirst(
              'Rinse well under cold running water. ',
              '',
            ),
          ),
        )?.toStringAsFixed(2),
        '54.42',
      );
      // Nor one rinsed with no drain.
      expect(
        keptOf(
          _fishChips,
          1,
          withStep1(
            step1.text.replaceFirst(
              'Carefully pull back the plastic wrap from the side farthest '
                  'from you and drain the potatoes into a large mesh strainer '
                  'set over a sink. ',
              '',
            ),
          ),
        )?.toStringAsFixed(2),
        '54.42',
      );
      // Nor a part the sentence pours over the fries without tossing them.
      const toss = 'toss with ¼ cup of the oil';
      expect(step1.text, contains(toss));
      expect(
        keptOf(
          _fishChips,
          1,
          withStep1(
            step1.text.replaceFirst(toss, 'drizzle with ¼ cup of the oil'),
          ),
        )?.toStringAsFixed(2),
        '54.42',
      );
    });

    test('F1 matches no food (closer 1, V1-D1): the step stands in for the '
        'tossed one — STATED synthesized: 0255 draining and rinsing canned '
        'chickpeas after the toss rinses the ¼ cup off too', () {
      final chips = recipes[_fishChips]!;
      final step1 = chips.steps.first;
      const drainRinse =
          'Carefully pull back the plastic wrap from the side farthest from '
          'you and drain the potatoes into a large mesh strainer set over a '
          'sink. Rinse well under cold running water. ';
      expect(step1.text, contains(drainRinse));
      final chickpeas = chips.copyWith(
        steps: [
          step1.copyWith(
            text: step1.text.replaceFirst(
              drainRinse,
              'Drain the canned chickpeas in a colander and rinse the '
              'chickpeas under cold running water. ',
            ),
          ),
          ...chips.steps.skip(1),
        ],
      );
      expect(keptOf(_fishChips, 1, chickpeas)?.toStringAsFixed(2), '0.00');
    });

    test('F1 names what it counts (closer 1, V1-D2) — STATED synthesized: '
        '0215 draining and rinsing its oiled bread crumbs in step 2 counts '
        'the step-3 tablespoon and the uptake, never the rinsed 2 teaspoons, '
        'and its basis says so', () async {
      final real = recipes[_horseradish]!;
      final step2 = real.steps[1];
      const toss =
          'Toss the bread crumbs with 2 teaspoons of the oil, ¼ teaspoon '
          'salt, and ¼ teaspoon of the pepper in a 10-inch nonstick skillet. ';
      expect(step2.text, startsWith(toss));
      final variant = real.copyWith(
        id: '${real.id}-rinsed',
        slug: '${real.slug}-rinsed',
        steps: [
          real.steps.first,
          step2.copyWith(
            text: step2.text.replaceFirst(
              toss,
              '${toss}Drain the bread crumbs in a strainer. Rinse them under '
              'cold water. ',
            ),
          ),
          ...real.steps.skip(2),
        ],
      );
      db.upsertRecipe(variant, sourceSlug: _source, contentHash: variant.id);
      final stored = db.recipeByIdOrSlug(variant.id)!.recipe;
      expect(await matchAndCompute(db, provider, stored), isNull);
      final line = nutritionLines(stored)[3];
      expect(line.raw, '1 cup plus 2 teaspoons vegetable oil');
      final row = db
          .ingredientMatchesFor(stored.id)
          .singleWhere((m) => m.position == 3);
      // 14.00 g kept (step 3) + 15.02 g uptake; the real row's 38.09 less
      // the rinsed 2 teaspoons (9.07 g).
      expect(row.grams?.toStringAsFixed(2), '29.02');
      expect(
        gramBasisFor(db, line, row, recipe: stored),
        'discarded in cooking — only the 1 tablespoon the steps keep and the '
        'oil the fried food absorbs counted ("plus 2 teaspoons vegetable '
        'oil": the steps rinse it off) · approximation (frying oil absorbed: '
        "10.9 % of the raw potatoes' weight — derived from USDA SR Legacy "
        '19411 "Snacks, potato chips, plain, salted")',
      );
      // No uptake flag (STATED synthesized row: grams the plan did not
      // write, so M52 reads none): the kept tablespoon alone is named.
      expect(
        gramBasisFor(db, line, row.copyWith(grams: 14), recipe: stored),
        'discarded in cooking — only the 1 tablespoon the steps keep counted '
        '("plus 2 teaspoons vegetable oil": the steps rinse it off)',
      );
      // Nor, with nothing kept and no uptake flag (STATED synthesized: the
      // real fish-and-chips|1 row at grams the plan did not write), is the
      // rinsed ¼ cup named as counted.
      expect(
        gramBasisFor(
          db,
          nutritionLines(recipes[_fishChips]!)[1],
          rowOf(_fishChips, 1).copyWith(grams: 14),
          recipe: recipes[_fishChips],
        ),
        'discarded in cooking — only the part the recipe keeps counted',
      );
    });

    test('D by hand (F12): C = the CAULIFLOWER group rows |5 |6 |8 |9 × '
        "their records' carbohydrate (the Ranch Dressing |11 and the unweighed "
        'salt |7 out); K = 50 × 0.40 / 39.58 × the cauliflower |10; the oil '
        '|4 = 30.32 % × C / K × |10', () {
      final lines = nutritionLines(recipes[_cauliflower]!);
      double grams(int p) => rowOf(_cauliflower, p).grams!;
      double cho(int p) => knownFood(
        db,
        rowOf(_cauliflower, p).fdcId!,
        line: lines[p],
      )!.nutrientsPer100g['205']!;
      final c = [5, 6, 8, 9].fold<double>(
        0,
        (n, p) => n + grams(p) * cho(p) / 100,
      );
      final k = 50 * 0.40 / 39.58 * grams(10);
      expect(c.toStringAsFixed(2), '122.16');
      expect(k.toStringAsFixed(2), '229.20');
      expect(
        grams(4).toStringAsFixed(2),
        (30.32 * c / k * grams(10) / 100).toStringAsFixed(2),
      );
    });

    test(
      'D reads a batter left in the bowl whole on every path (closer 2, '
      "V2-D1) — STATED synthesized: 0511 Shrimp Tempura with 0672's real "
      'cauliflower line in its group, fried in the remaining batter; a '
      'compute and a recompute agree and the GET basis keeps the flag',
      () async {
        final tempura = recipes[_tempura]!;
        final cauliflower = nutritionLines(
          recipes[_cauliflower]!,
        ).singleWhere((l) => l.raw.startsWith('1 pound cauliflower'));
        expect(
          cauliflower.raw,
          '1 pound cauliflower florets, cut into 1½-inch pieces',
        );
        final group = tempura.ingredients.first;
        final last = tempura.steps.last;
        final variant = tempura.copyWith(
          id: '${tempura.id}-cauliflower',
          slug: '${tempura.slug}-cauliflower',
          ingredients: [
            group.copyWith(items: [...group.items, cauliflower]),
            ...tempura.ingredients.skip(1),
          ],
          steps: [
            ...tempura.steps.take(tempura.steps.length - 1),
            last.copyWith(
              text:
                  '${last.text} Submerge the cauliflower in the remaining '
                  'batter, then fry it in the oil until golden, 3 to 4 minutes.',
            ),
          ],
        );
        db.upsertRecipe(variant, sourceSlug: _source, contentHash: variant.id);
        final stored = db.recipeByIdOrSlug(variant.id)!.recipe;
        expect(await matchAndCompute(db, provider, stored), isNull);
        final line = nutritionLines(stored)[0];
        IngredientMatchRow oil() => db
            .ingredientMatchesFor(stored.id)
            .singleWhere((m) => m.position == 0);
        List<(int, double?, String?)> rows() => [
          for (final r in db.ingredientMatchesFor(stored.id))
            (r.position, r.grams, r.updatedAt),
        ];
        // The batter (|2–|6, M58 W) read at its whole grams on every path:
        // C = flour 212.62 g × 77.3 % + cornstarch 63.89 × 91.27 + egg 50 ×
        // 0.96 = 223.14 g (the plan counts 46.9 % of it on the shrimp);
        // K = 50 × 0.40 / 39.58 × 453.59 = 229.20; u = 30.32 × C / K =
        // 29.52 %, beside the shrimp's 15.38 %.
        expect(oil().grams?.toStringAsFixed(2), '238.53');
        final basis = gramBasisFor(db, line, oil(), recipe: stored);
        expect(
          basis,
          contains(
            'approximation (frying oil absorbed — derived: 15.38 % of the '
            "raw shrimp's weight",
          ),
        );
        expect(
          basis,
          contains(
            "29.52 % of the raw cauliflower's weight — USDA FNDDS 2710042 "
            'recipe: 12 g oil per 39.58 g raw cauliflower, scaled to the '
            "recipe's batter (223.14 g of 229.20 g carbohydrate))",
          ),
        );
        expect(
          db.nutritionFor(stored.id)!.caloriesPerServing?.toStringAsFixed(2),
          '446.29',
        );
        final before = rows();
        final kcal = db.nutritionFor(stored.id)!.caloriesPerServing;
        // Two recomputes on the stored rows (the batter now `discarded`).
        for (var i = 0; i < 2; i++) {
          expect(recomputeTotals(db, stored), isTrue);
          expect(rows(), before);
          expect(db.nutritionFor(stored.id)!.caloriesPerServing, kcal);
          expect(gramBasisFor(db, line, oil(), recipe: stored), basis);
        }
      },
    );

    test('the four recipes move kcal per serving only (statuses complete)', () {
      (String, String) of(String file) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        return (n.status, n.caloriesPerServing!.toStringAsFixed(2));
      }

      expect(of(_saltPepper), ('complete', '366.34')); // v57 303.34
      // crispy-orange-beef (replay 599.09, v57 536.09): its beef |0 reads
      // its energy off another answer in a fresh compute (952.54 for the
      // replay's 953.52) — the status only.
      expect(of(_orangeBeef).$1, 'complete');
      // buffalo-cauliflower-bites (replay 616.15, v57 760.67, −578.07 / 4):
      // its cauliflower |10 reads 125.19 kcal off the fixture's detail in a
      // fresh compute (the replay's 125.16), +0.01 a serving.
      expect(of(_cauliflower), ('complete', '616.16'));
      // fish-and-chips (replay 855.40, v57 981.40): its oil |1 reads another
      // record in a fresh compute than in snapshot 23 — the status only.
      expect(of(_fishChips).$1, 'complete');
    });

    test('a second recompute writes nothing', () {
      for (final file in const [
        _saltPepper,
        _orangeBeef,
        _fishChips,
        _cauliflower,
      ]) {
        final recipe = recipes[file]!;
        final before = [
          for (final r in db.ingredientMatchesFor(recipe.id))
            (r.position, r.grams, r.updatedAt),
        ];
        expect(recomputeTotals(db, recipe), isTrue, reason: file);
        expect(
          [
            for (final r in db.ingredientMatchesFor(recipe.id))
              (r.position, r.grams, r.updatedAt),
          ],
          before,
          reason: file,
        );
      }
    });
  });
}
