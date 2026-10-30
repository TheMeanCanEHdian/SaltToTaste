// Matcher v97 (batch M95; matcherVersion 92 — the fries' uptake from FNDDS
// 2709458; prep51 design_v2 §1 Q9 / §2 M95, ruled by the owner 2026-10-29;
// zero requests). The O4 uptake of a fried potato (and the sweet-potato and
// eggplant stand-ins that read it) was 6.0 % of the raw weight, DERIVED from
// analytical SR 170698 "Fast foods, potato, french fried in vegetable oil";
// it is now READ from FNDDS 2709458 "Potato, french fries, from fresh,
// fried" (`_friesFried`, engine.dart): its inputFoods (live step L51 #2,
// .claude/diag/2026-10-29/live51_raw/2709458.json) list, per 100 g of
// fries, 50 g 11674 "Potatoes, baked, flesh and skin, without salt", 50 g
// 11363 "Potatoes, baked, flesh, without salt", 15 g "Vegetable oil, NFS"
// and 0.4 g salt. The baked potato is brought to raw by carbohydrate on two
// cached pairs: 11674 is not cached, so its half reads the RUSSET pair
// (a stand-in by cultivar — SR 170030 is NDB 11356, L52's raw_170030.json)
// 170030 21.4 / 170027 18.1 → 59.12 g; the flesh half is 11363 itself, SR
// 170033 21.6 over the raw flesh the fries lines land on, Foundation
// 2346401 17.77125 → 60.77 g; r = 119.89 g, 15 / 119.89 = 12.51 %. The
// split over the fryers (M83's B4) and the cap are unchanged.
// REACH (fix97 gate1, the v96 rows of snapshot 30): exactly the 10 rows of
// classic- / easier-french-fries (|1 |2), fish-and-chips|1 (the chips' part
// of the oil; the cod's 15.38 % unchanged), steak-fries|1, steak-frites|9,
// patatas-bravas|12, thick-cut-sweet-potato-fries|4 (the stand-in) and
// crispy-thai-eggplant-salad|10 (the stand-in), and their 8 totals. Every
// whole-recipe figure is a fresh compute on the recorded fixtures
// (FixtureProvider) — the replay's in each comment. Never the network.
// Every corpus line is real; nothing is synthesized.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _classic = '0316-classic-french-fries.yaml';
const _easier = '0317-easier-french-fries.yaml';
const _fishChips = '0255-fish-and-chips.yaml';
const _steakFries = '0316-steak-fries.yaml';
const _steakFrites = '0464-steak-frites.yaml';
const _bravas = '0690-patatas-bravas.yaml';
const _sweet = '0318-thick-cut-sweet-potato-fries.yaml';
const _eggplant = '0053-crispy-thai-eggplant-salad.yaml';
const _chips = '0319-crunchy-kettle-potato-chips.yaml';
const _shallots = 'Fried Shallots and Fried Shallot Oil';

const _absorbs =
    'discarded in cooking — only the oil the fried food absorbs counted';

/// The fries' clause on the raw [food] (the fix97 gate1 rows, verbatim).
String _clause(String food, {bool standIn = false}) =>
    "12.51 % of the raw ${food.endsWith('s') ? "$food'" : "$food's"} weight "
    '— USDA FNDDS 2709458 recipe: 15 g oil per 119.89 g raw potatoes (its '
    'baked potato brought to raw by carbohydrate on SR 170030 / 170027 '
    '(russet, a stand-in for the generic baked potato) and SR 170033 / '
    'Foundation 2346401)'
    "${standIn ? ' (no record for $food; read as Potato, french fries, from fresh, fried)' : ''}";

String _basis(String food, {bool standIn = false}) =>
    '$_absorbs · approximation (frying oil absorbed: '
    '${_clause(food, standIn: standIn)})';

/// fish-and-chips|1: the cod's read clause (no tracer — the clause is the
/// fries' figure's alone) and the chips'.
final _fishBasis =
    '$_absorbs ("plus ¼ cup peanut oil or canola oil": the steps rinse it '
    "off) · approximation (frying oil absorbed: 15.38 % of the raw cod's "
    'weight — USDA FNDDS 2706244 recipe: 10 g oil per 65 g raw cod; '
    "${_clause('potatoes')})";

/// The 10 rows (file, position, raw, record, grams, kcal, basis) — the
/// v96 → v97 replay's grams / kcal in each comment. Each oil is `auto`,
/// `discarded`, no hold.
final _reach = [
  // 53.53 → 111.60 g, 481.77 → 1,004.40 kcal (2710187 peanut oil, 900).
  (
    _classic,
    1,
    '2 quarts peanut oil',
    2710187,
    '111.60',
    '1004.40',
    _basis('potatoes'),
  ),
  // 1.59 → 3.31 g, 14.26 → 29.69 (SR 172345 bacon grease, 897).
  (
    _classic,
    2,
    '¼ cup bacon fat, strained (optional)',
    172345,
    '3.31',
    '29.69',
    _basis('potatoes'),
  ),
  // 65.52 → 136.62 g, 589.68 → 1,229.58.
  (
    _easier,
    1,
    '6 cups peanut oil',
    2710187,
    '136.62',
    '1229.58',
    _basis('potatoes'),
  ),
  // 2.52 → 5.25 g, 22.60 → 47.09.
  (
    _easier,
    2,
    '¼ cup bacon fat, strained (optional)',
    172345,
    '5.25',
    '47.09',
    _basis('potatoes'),
  ),
  // 170.78 → 242.53 g, 1,537.02 → 2,182.77 kcal (2710187 peanut oil, 900 —
  // this suite's compute lands the line on the replay's record; v58's and
  // v71's suites land it on 172336 "Oil, canola", 884: 2,143.97 — the grams
  // and basis equal).
  (
    _fishChips,
    1,
    '3 quarts plus ¼ cup peanut oil or canola oil',
    2710187,
    '242.53',
    '2182.77',
    _fishBasis,
  ),
  // 68.04 → 141.86 g, 612.36 → 1,276.74.
  (
    _steakFries,
    1,
    '2 quarts peanut oil',
    2710187,
    '141.86',
    '1276.74',
    _basis('potatoes'),
  ),
  // 68.04 → 141.86 g, 612.36 → 1,276.74.
  (
    _steakFrites,
    9,
    '3 quarts peanut oil',
    2710187,
    '141.86',
    '1276.74',
    _basis('potatoes'),
  ),
  // 49.60 → 103.42 g, 446.40 → 930.78 (2710180 vegetable oil, 900).
  (
    _bravas,
    12,
    '3 cups vegetable oil',
    2710180,
    '103.42',
    '930.78',
    _basis('potatoes'),
  ),
  // 65.32 → 136.19 g, 587.88 → 1,225.71 — the sweet-potato stand-in.
  (
    _sweet,
    4,
    '3 cups peanut oil',
    2710187,
    '136.19',
    '1225.71',
    _basis('sweet potatoes', standIn: true),
  ),
  // 40.82 → 85.12 g, 367.38 → 766.08 — the eggplant stand-in.
  (
    _eggplant,
    10,
    '2 cups vegetable oil',
    2710180,
    '85.12',
    '766.08',
    _basis('eggplant', standIn: true),
  ),
];

/// The fried food's row each recipe's uptake is sized on (file, position,
/// raw grams) — the v96 rows', unchanged.
const _fried = [
  (_classic, 0, '918.52'),
  (_easier, 0, '1133.98'),
  (_fishChips, 0, '1102.23'),
  (_steakFries, 0, '1133.98'),
  (_steakFrites, 7, '1133.98'),
  (_bravas, 9, '826.67'),
  (_sweet, 3, '1088.62'),
  (_eggplant, 8, '680.39'),
];

/// (file, status, per serving) after the compute — the replay's v96 → v97
/// per serving in each comment, then the fixtures' (a fresh compute here on
/// the base tree, 6b4df1e, and on this one). The fixtures sit above the
/// replay by a standing offset the batch does not touch (their cached hits'
/// rounded figures — e.g. the Foundation potatoes' 958 HIT against the
/// snapshot's DETAIL): each move equals the replay's to the cent of rounding.
const _totals = [
  // replay 309.90 → 444.41 (+134.51); fixtures 310.01 → 444.52 (+134.51).
  (_classic, 'complete', '444.52'),
  // replay 355.98 → 522.08 (+166.10); fixtures 356.05 → 522.15 (+166.10).
  (_easier, 'complete', '522.15'),
  // replay 856.27 → 1,017.71 (+161.44); fixtures 856.44 → 1,017.88 (+161.44).
  (_fishChips, 'complete', '1017.88'),
  // replay 382.59 → 548.68 (+166.09); fixtures 382.72 → 548.82 (+166.10).
  (_steakFries, 'complete', '548.82'),
  // replay 1,079.57 → 1,245.66 (+166.09); fixtures 1,079.70 → 1,245.80
  // (+166.10).
  (_steakFrites, 'complete', '1245.80'),
  // replay 423.36 → 544.45 (+121.09; partial: its baking soda weighs
  // nothing); fixtures 423.45 → 544.55 (+121.10).
  (_bravas, 'partial', '544.55'),
  // replay 435.03 → 594.49 (+159.46; partial); the fixtures equal it.
  (_sweet, 'partial', '594.49'),
  // replay 491.27 → 690.62 (+199.35, 2 servings); fixtures 491.42 → 690.77.
  (_eggplant, 'complete', '690.77'),
];

/// [r] stored and computed (its section children first).
Future<Recipe> _compute(
  SaltDatabase db,
  NutritionProvider fdc,
  Recipe r,
) async {
  db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
  final stored = db.recipeByIdOrSlug(r.id)!.recipe;
  for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
    expect(
      await matchAndCompute(db, fdc, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }
  expect(await matchAndCompute(db, fdc, stored), isNull);
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

SaltDatabase _db() {
  final dir = Directory.systemTemp.createTempSync('salt-v97-');
  final db = SaltDatabase.open(
    ServerConfig(
      dataDir: dir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    ).dbPath,
  )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
  addTearDown(() {
    db.dispose();
    dir.deleteSync(recursive: true);
  });
  return db;
}

void main() {
  test("matcherVersion 92 (v97, batch M95: the fries' uptake)", () {
    expect(matcherVersion, 92);
  });

  test("the engine's own figure (`uptakeFigureForTest`, the class "
      "`_friedClassOf` returns on each REAL row's record): FNDDS 2709458, "
      "15 / 119.89 exactly, printed 12.51 (was SR 170698's derived 6.0) — "
      'the potato, and the sweet-potato and eggplant stand-ins', () {
    for (final (description, item, standIn) in const [
      ('Potatoes, russet, without skin, raw', 'russet potatoes', false),
      ('Potatoes, gold, without skin, raw', 'yukon gold potatoes', false),
      (
        "Sweet potato, raw, unprepared (Includes foods for USDA's Food "
            'Distribution Program)',
        'sweet potatoes',
        true,
      ),
      ('Eggplant, raw', 'japanese eggplants', true),
    ]) {
      final f = uptakeFigureForTest(description, item)!;
      expect(
        (f.value, f.id, f.oilPerRaw, f.standIn),
        ('12.51', 2709458, 15 / 119.89, standIn),
        reason: item,
      );
      // The printed figure IS the tuple's o / r (a value or an r alone
      // changed fails here).
      expect((f.oilPerRaw! * 100).toStringAsFixed(2), f.value, reason: item);
      expect(f.oilPerRaw!.toStringAsFixed(4), '0.1251', reason: item);
    }
    // The other uncoated classes keep their own figures (the REAL rows'
    // records: platanos-maduros|1 on 2710817, fried-yuca|0 on 169985).
    expect(
      uptakeFigureForTest('Plantains, ripe, raw', 'very ripe black plantains'),
      (value: '5.5', id: 168200, oilPerRaw: null, standIn: false),
    );
    expect(
      uptakeFigureForTest('Cassava, raw', 'yuca roots'),
      (value: '15.00', id: 2709565, oilPerRaw: 15 / 100, standIn: false),
    );
  });

  test('the tracer pairs on the fixtures (carbohydrate, 205): SR 170030 '
      '"Potatoes, Russet, flesh and skin, baked" 21.4 / SR 170027 "…, russet, '
      'flesh and skin, raw" 18.1 (the stand-in by cultivar for 11674) and SR '
      '170033 "Potatoes, baked, flesh, without salt" 21.6 / Foundation '
      '2346401 "Potatoes, russet, without skin, raw" 17.77125 — 50 × 21.4 / '
      '18.1 + 50 × 21.6 / 17.77125 = 119.89 g raw, the r the engine reads; '
      "2709458's own hit (E 198, P 1.93, F 13.1, C 18.5)", () async {
    final fdc = FixtureProvider();
    Future<FdcCandidate> hit(String query, int fdcId) async =>
        (await fdc.search(query)).singleWhere((h) => h.fdcId == fdcId);
    final skinBaked = await hit('russet potato', 170030);
    final skinRaw = await hit('russet potato', 170027);
    final fleshBaked = await hit('cold without salt butter', 170033);
    final fleshRaw = (await fdc.food(2346401))!;
    expect(
      [
        skinBaked.description,
        skinRaw.description,
        fleshBaked.description,
        fleshRaw.description,
      ],
      [
        'Potatoes, Russet, flesh and skin, baked',
        "Potatoes, russet, flesh and skin, raw (Includes foods for USDA's Food Distribution Program)",
        'Potatoes, baked, flesh, without salt',
        'Potatoes, russet, without skin, raw',
      ],
    );
    final a = skinBaked.nutrientsPer100g!['205']!;
    final b = skinRaw.nutrientsPer100g!['205']!;
    final c = fleshBaked.nutrientsPer100g!['205']!;
    final d = fleshRaw.nutrientsPer100g['205']!;
    expect((a, b, c, d), (21.4, 18.1, 21.6, 17.77125));
    final r = (50 * a / b + 50 * c / d).toStringAsFixed(2);
    expect(r, '119.89');
    expect(
      uptakeFigureForTest(fleshRaw.description, 'russet potatoes')!.oilPerRaw,
      15 / double.parse(r),
    );
    // Not built: both halves on the russet pair (118.23 g, 12.69 %).
    expect((100 * a / b).toStringAsFixed(2), '118.23');
    final fries = await hit('home-fried taco shells', 2709458);
    expect(fries.description, 'Potato, french fries, from fresh, fried');
    expect(
      [
        for (final n in ['208', '203', '204', '205'])
          fries.nutrientsPer100g![n],
      ],
      [198.0, 1.93, 13.1, 18.5],
    );
  });

  group('matcher v97 (batch M95)', skip: skipIfNoCorpus, () {
    late SaltDatabase db;
    late FixtureProvider fdc;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      db = _db();
      fdc = FixtureProvider(pending: {...pendingSearches});
      for (final file in {for (final r in _reach) r.$1, _chips}) {
        recipes[file] = await _compute(db, fdc, loadCorpusRecipe(file));
      }
    });

    IngredientMatchRow rowIn(String id, int position) =>
        db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

    double gramsAt(String file, int position) =>
        rowIn(recipes[file]!.id, position).grams!;

    String? basisOf(Recipe recipe, int position) => gramBasisFor(
      db,
      nutritionLines(recipe)[position],
      rowIn(recipe.id, position),
      recipe: recipe,
    );

    String kcalOf(IngredientMatchRow row) =>
        (kcalPer100g(
                  knownFood(db, nutrientSiblings[row.fdcId] ?? row.fdcId!)!,
                ) *
                row.grams! /
                100)
            .toStringAsFixed(2);

    /// The whole grams of [file]'s line [position] on its own record.
    double wholeOf(String file, int position) {
      final recipe = recipes[file]!;
      return lineGrams(
        db,
        nutritionLines(recipe)[position],
        knownFood(db, rowIn(recipe.id, position).fdcId!),
        recipe: recipe,
      )!.grams;
    }

    test('the 10 rows at the read figure: record, status, source, grams, '
        'energy, the basis verbatim (FNDDS 2709458, the tracer pairs, the '
        'stand-ins) — no row prints SR 170698', () {
      for (final (file, position, raw, fdcId, grams, kcal, basis) in _reach) {
        final recipe = recipes[file]!;
        final row = rowIn(recipe.id, position);
        final reason = '$file|$position';
        expect(nutritionLines(recipe)[position].raw, raw, reason: reason);
        expect(
          (
            row.fdcId,
            row.status,
            row.hold,
            row.gramSource,
            row.grams?.toStringAsFixed(2),
            kcalOf(row),
          ),
          (fdcId, 'auto', null, 'discarded', grams, kcal),
          reason: reason,
        );
        expect(basisOf(recipe, position), basis, reason: reason);
        expect(basisOf(recipe, position), isNot(contains('170698')));
      }
    });

    test("each uptake = 12.51 % of its fried food's raw grams, by hand: "
        "the one fryer whole; classic / easier split by the fryers' whole "
        'grams (B4: 114.91 = 111.60 + 3.31, 141.87 = 136.62 + 5.25; was '
        '53.53 + 1.59 and 65.52 + 2.52 at 6.0 %); fish-and-chips|1 = the '
        "cod's 15.38 % (104.64 g, unchanged) + the chips' 12.51 % (137.89 g, "
        'was 66.13)', () {
      for (final (file, position, grams) in _fried) {
        expect(gramsAt(file, position).toStringAsFixed(2), grams, reason: file);
      }
      String g2(double v) => v.toStringAsFixed(2);
      for (final (file, fryers, sum) in const [
        (_classic, (1, 2), '114.91'),
        (_easier, (1, 2), '141.87'),
      ]) {
        final uptake = gramsAt(file, 0) * 12.51 / 100;
        final (a, b) = (wholeOf(file, fryers.$1), wholeOf(file, fryers.$2));
        expect(g2(gramsAt(file, fryers.$1)), g2(uptake * a / (a + b)));
        expect(g2(gramsAt(file, fryers.$2)), g2(uptake * b / (a + b)));
        expect(
          g2(gramsAt(file, fryers.$1) + gramsAt(file, fryers.$2)),
          sum,
          reason: file,
        );
      }
      for (final (file, position, food) in const [
        (_steakFries, 1, 0),
        (_steakFrites, 9, 7),
        (_bravas, 12, 9),
        (_sweet, 4, 3),
        (_eggplant, 10, 8),
      ]) {
        expect(
          g2(gramsAt(file, position)),
          g2(gramsAt(file, food) * 12.51 / 100),
          reason: file,
        );
      }
      final cod = gramsAt(_fishChips, 9) * 15.38 / 100;
      final fries = gramsAt(_fishChips, 0) * 12.51 / 100;
      expect((g2(cod), g2(fries)), ('104.64', '137.89'));
      expect(g2(gramsAt(_fishChips, 0) * 6.0 / 100), '66.13');
      expect(g2(gramsAt(_fishChips, 1)), g2(cod + fries));
    });

    test('the converses keep their v96 rows: the chips arm (the potato '
        "site's other branch) at SR 19411's 10.9 %, and the eggplant "
        "salad's Fried Shallots oil at its printed yield (the shallots' own "
        'figure)', () {
      final chips = recipes[_chips]!;
      final row = rowIn(chips.id, 0);
      expect(
        nutritionLines(chips)[0].raw,
        '2 quarts vegetable oil, for frying',
      );
      expect(
        (row.fdcId, row.gramSource, row.grams?.toStringAsFixed(2), kcalOf(row)),
        (2710180, 'discarded', '49.44', '444.96'),
      );
      expect(
        basisOf(chips, 0),
        '$_absorbs · approximation (frying oil absorbed: 10.9 % of the raw '
        "potatoes' weight — derived from USDA SR Legacy 19411 \"Snacks, "
        'potato chips, plain, salted")',
      );
      final section = nutritionRecipeOf(
        db,
        sectionKeyOf(recipes[_eggplant]!.id, _shallots),
      )!.recipe;
      final oil = rowIn(section.id, 1);
      expect(nutritionLines(section)[1].raw, '2 cups vegetable oil');
      expect(
        (oil.fdcId, oil.gramSource, oil.grams?.toStringAsFixed(2), kcalOf(oil)),
        (2710180, 'discarded', '56.00', '504.00'),
      );
      expect(basisOf(section, 1), isNot(contains('2709458')));
    });

    test('the eight totals: status and per serving', () {
      expect(
        [
          for (final (file, _, _) in _totals)
            (
              file,
              db.nutritionFor(recipes[file]!.id)!.status,
              db
                  .nutritionFor(recipes[file]!.id)!
                  .caloriesPerServing
                  ?.toStringAsFixed(2),
            ),
        ],
        [
          for (final (file, status, perServing) in _totals)
            (file, status, perServing),
        ],
      );
    });

    test('the GET shows the new basis (classic|2, the sweet-potato '
        'stand-in |4)', () async {
      for (final (file, position, basis) in [
        (_classic, 2, _basis('potatoes')),
        (_sweet, 4, _basis('sweet potatoes', standIn: true)),
      ]) {
        final items =
            ((await matchesBody(db, fdc, recipes[file]!))['items']! as List)
                .cast<Map<String, Object?>>();
        final item = items.singleWhere((i) => i['position'] == position);
        expect(
          (item['match']! as Map<String, Object?>)['gram_basis'],
          basis,
          reason: '$file|$position',
        );
      }
    });

    test('a second compute writes nothing: every row and total of the '
        'computed recipes as the first compute left it', () async {
      for (final file in recipes.keys) {
        final id = recipes[file]!.id;
        List<Object?> rowsOf() => [
          for (final m in db.ingredientMatchesFor(id))
            (
              m.position,
              m.fdcId,
              m.confidence,
              m.grams,
              m.gramSource,
              m.status,
              m.hold,
            ),
        ];
        final rows = rowsOf();
        final totals = db.nutritionFor(id)!.totalsJson;
        expect(
          await matchAndCompute(db, fdc, nutritionRecipeOf(db, id)!.recipe),
          isNull,
        );
        expect(rowsOf(), rows, reason: file);
        expect(db.nutritionFor(id)!.totalsJson, totals, reason: file);
      }
    });
  });
}
