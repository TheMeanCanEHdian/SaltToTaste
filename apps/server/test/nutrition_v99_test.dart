// Matcher v99 (batch M96; matcherVersion 93 — the sweet-potato fries' uptake
// from FNDDS 2709712; FNDDS 2710048 read and rejected; zero requests, both
// records fetched at live step L53, 2026-11-02). The O4 uptake of fried
// sweet potato read the potato's FNDDS 2709458 as a stand-in (12.51 %); it
// now READS its own record, FNDDS 2709712 "Sweet potato fries, from fresh"
// (`_sweetFries`, engine.dart): its inputFoods (.claude/diag/2026-11-02/
// live53_raw/2709712.json) list, per 100 g of fries, 100 g 99997340 "Sweet
// potato, cooked, as ingredient", 10 g "Vegetable oil, NFS" and 0.4 g salt.
// The cooked input is brought to raw by carbohydrate on two cached hits,
// FNDDS 2710794 "Sweet potato, cooked, as ingredient" 18.05 over SR 168482
// "Sweet potato, raw, unprepared" 20.1: r = 89.80 g, 10 / 89.80 = 11.14 %.
// FNDDS 2710048 "Fried eggplant" (live53_raw/2710048.json) is BREADED — 50 g
// breading or batter and 38 g cooked eggplant per 100.5 g, 12 g oil — so the
// bare fried eggplant keeps the potato's record as its stand-in.
// REACH (fix99 gate1, the v98 rows of snapshot 31): exactly ONE row,
// thick-cut-sweet-potato-fries|4 (136.19 → 121.27 g), and its total. Every
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
const _sweet = '0318-thick-cut-sweet-potato-fries.yaml';
const _eggplant = '0053-crispy-thai-eggplant-salad.yaml';
const _shallots = 'Fried Shallots and Fried Shallot Oil';

const _absorbs =
    'discarded in cooking — only the oil the fried food absorbs counted';

/// thick-cut-sweet-potato-fries|4's basis (the fix99 gate1 row, verbatim):
/// its own record, its tracer pair, no stand-in.
const _sweetBasis =
    '$_absorbs · approximation (frying oil absorbed: 11.14 % of the raw '
    "sweet potatoes' weight — USDA FNDDS 2709712 recipe: 10 g oil per 89.80 "
    'g raw sweet potatoes (its cooked sweet potato brought to raw by '
    'carbohydrate on FNDDS 2710794 / SR 168482))';

/// crispy-thai-eggplant-salad|10's basis — the v98 row, unchanged: the
/// potato's record, read as a stand-in.
const _eggplantBasis =
    '$_absorbs · approximation (frying oil absorbed: 12.51 % of the raw '
    "eggplant's weight — USDA FNDDS 2709458 recipe: 15 g oil per 119.89 g "
    'raw potatoes (its baked potato brought to raw by carbohydrate on SR '
    '170030 / 170027 (russet, a stand-in for the generic baked potato) and '
    'SR 170033 / Foundation 2346401) (no record for eggplant; read as '
    'Potato, french fries, from fresh, fried))';

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
  final dir = Directory.systemTemp.createTempSync('salt-v99-');
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
  test(
    "matcherVersion 94 (v99 set it to 93, batch M96: the sweet-potato fries' "
    'uptake)',
    () {
      // RE-PIN (M97 batch, v100): matcherVersion 94 (was 93).
      expect(matcherVersion, 94);
    },
  );

  test("the engine's own figure (`uptakeFigureForTest` on each REAL row's "
      'record): the sweet potato reads FNDDS 2709712, 10 / 89.80 exactly, '
      'printed 11.14, no stand-in (was 2709458 as a stand-in, 12.51); the '
      'eggplant keeps 2709458 as a stand-in (2710048 is breaded) — the '
      'converse; the potato unchanged', () {
    final sweet = uptakeFigureForTest(
      "Sweet potato, raw, unprepared (Includes foods for USDA's Food "
          'Distribution Program)',
      'sweet potatoes',
    )!;
    expect(
      (sweet.value, sweet.id, sweet.oilPerRaw, sweet.standIn),
      ('11.14', 2709712, 10 / 89.80, false),
    );
    // The printed figure IS the tuple's o / r (a value or an r alone
    // changed fails here); the no-tracer form (10 g per 100 g) is not built.
    expect((sweet.oilPerRaw! * 100).toStringAsFixed(2), sweet.value);
    expect(sweet.oilPerRaw!.toStringAsFixed(6), '0.111359');
    expect(sweet.oilPerRaw, isNot(10 / 100));
    for (final (description, item, standIn) in const [
      ('Eggplant, raw', 'japanese eggplants', true),
      ('Potatoes, russet, without skin, raw', 'russet potatoes', false),
    ]) {
      final f = uptakeFigureForTest(description, item)!;
      expect(
        (f.value, f.id, f.oilPerRaw, f.standIn),
        ('12.51', 2709458, 15 / 119.89, standIn),
        reason: item,
      );
    }
  });

  test('the tracer pair on the fixtures (carbohydrate, 205): FNDDS 2710794 '
      '"Sweet potato, cooked, as ingredient" 18.05 (a hit in "sweet '
      'potatoes") over SR 168482 "Sweet potato, raw, unprepared" 20.1 (a '
      "hit in 'sweet potato raw unprepared') — 100 × 18.05 / 20.1 = 89.80 g "
      "raw, the r the engine reads; 2709712's profile = its inputs ÷ 110.4 "
      "g (carbohydrate 18.05 / 1.104 = its hit's 16.35); its detail's 16.4 "
      'is not the tracer', () async {
    final fdc = FixtureProvider();
    Future<FdcCandidate> hit(String query, int fdcId) async =>
        (await fdc.search(query)).singleWhere((h) => h.fdcId == fdcId);
    final cooked = await hit('sweet potatoes', 2710794);
    final raw = await hit('sweet potato raw unprepared', 168482);
    expect(
      [cooked.description, raw.description],
      [
        'Sweet potato, cooked, as ingredient',
        "Sweet potato, raw, unprepared (Includes foods for USDA's Food Distribution Program)",
      ],
    );
    final c = cooked.nutrientsPer100g!['205']!;
    final k = raw.nutrientsPer100g!['205']!;
    expect((c, k), (18.05, 20.1));
    final r = (100 * c / k).toStringAsFixed(2);
    expect(r, '89.80');
    expect(
      uptakeFigureForTest(raw.description, 'sweet potatoes')!.oilPerRaw,
      10 / double.parse(r),
    );
    final fries = await hit('sweet potatoes', 2709712);
    expect(fries.description, 'Sweet potato fries, from fresh');
    expect(
      [
        for (final n in ['208', '203', '204', '205'])
          fries.nutrientsPer100g![n],
      ],
      [156.0, 1.49, 9.42, 16.35],
    );
    // The identity (a check, not a figure): 100 g cooked + 10 g oil + 0.4 g
    // salt = 110.4 g; carbohydrate and fat both reproduce the record's.
    expect((100 * c / 110.4).toStringAsFixed(2), '16.35');
    expect(
      ((10 + cooked.nutrientsPer100g!['204']!) / 1.104).toStringAsFixed(2),
      '9.42',
    );
    final detail = (await fdc.food(2709712))!;
    expect(detail.nutrientsPer100g['205'], 16.4);
  });

  group('matcher v99 (batch M96)', skip: skipIfNoCorpus, () {
    late SaltDatabase db;
    late FixtureProvider fdc;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      db = _db();
      fdc = FixtureProvider(pending: {...pendingSearches});
      for (final file in [_sweet, _eggplant]) {
        recipes[file] = await _compute(db, fdc, loadCorpusRecipe(file));
      }
    });

    IngredientMatchRow rowIn(String id, int position) =>
        db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

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

    test('the one row at its own record: thick-cut-sweet-potato-fries|4 '
        "136.19 → 121.27 g (1,225.71 → 1,091.43 kcal) = 11.14 % of |3's "
        '1,088.62 g raw sweet potato (SR 168482), the basis verbatim — no '
        '2709458, no stand-in', () {
      final recipe = recipes[_sweet]!;
      final row = rowIn(recipe.id, 4);
      expect(nutritionLines(recipe)[4].raw, '3 cups peanut oil');
      expect(
        (
          row.fdcId,
          row.status,
          row.hold,
          row.gramSource,
          row.grams?.toStringAsFixed(2),
          kcalOf(row),
        ),
        (2710187, 'auto', null, 'discarded', '121.27', '1091.43'),
      );
      final potatoes = rowIn(recipe.id, 3);
      expect(
        (potatoes.fdcId, potatoes.grams?.toStringAsFixed(2)),
        (168482, '1088.62'),
      );
      // The printed figure times the fried food's grams (the shipped
      // `uOf`): 1,088.62 × 11.14 / 100 = 121.27 (o / r unrounded: 121.23).
      expect(
        row.grams!.toStringAsFixed(2),
        (potatoes.grams! * 11.14 / 100).toStringAsFixed(2),
      );
      final basis = basisOf(recipe, 4);
      expect(basis, _sweetBasis);
      expect(basis, isNot(contains('2709458')));
      expect(basis, isNot(contains('no record')));
    });

    test("the converse: crispy-thai-eggplant-salad|10 keeps the potato's "
        'record as a stand-in (85.12 g, 766.08 kcal; the basis names 2709458 '
        "and the stand-in), its Fried Shallots oil its printed yield's "
        '56.00 g', () {
      final recipe = recipes[_eggplant]!;
      final row = rowIn(recipe.id, 10);
      expect(nutritionLines(recipe)[10].raw, '2 cups vegetable oil');
      expect(
        (
          row.fdcId,
          row.status,
          row.hold,
          row.gramSource,
          row.grams?.toStringAsFixed(2),
          kcalOf(row),
        ),
        (2710180, 'auto', null, 'discarded', '85.12', '766.08'),
      );
      expect(basisOf(recipe, 10), _eggplantBasis);
      expect(basisOf(recipe, 10), isNot(contains('2710048')));
      final section = nutritionRecipeOf(
        db,
        sectionKeyOf(recipe.id, _shallots),
      )!.recipe;
      final oil = rowIn(section.id, 1);
      expect(nutritionLines(section)[1].raw, '2 cups vegetable oil');
      expect(
        (oil.fdcId, oil.gramSource, oil.grams?.toStringAsFixed(2), kcalOf(oil)),
        (2710180, 'discarded', '56.00', '504.00'),
      );
    });

    test('the two totals: status and per serving', () {
      expect(
        [
          for (final file in [_sweet, _eggplant])
            (
              db.nutritionFor(recipes[file]!.id)!.status,
              db
                  .nutritionFor(recipes[file]!.id)!
                  .caloriesPerServing
                  ?.toStringAsFixed(2),
            ),
        ],
        [
          // replay 594.49 → 560.92 (−33.57 × 4 = −134.28; partial: its
          // baking soda weighs nothing); the fixtures equal it.
          ('partial', '560.92'),
          // replay 690.62 unchanged; the fixtures' standing +0.15.
          ('complete', '690.77'),
        ],
      );
    });

    test('the GET shows the new basis (sweet|4) and the unchanged one '
        '(eggplant|10)', () async {
      for (final (file, position, basis) in [
        (_sweet, 4, _sweetBasis),
        (_eggplant, 10, _eggplantBasis),
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

    test('a second compute writes nothing: every row and total of the two '
        'recipes as the first compute left it', () async {
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
