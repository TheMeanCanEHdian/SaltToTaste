// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v57 (batch M58, a batter left in the bowl joins the coat budget;
// matcherVersion 56; prep48 design_v2 §2 M58 W + S + the negimaki flag, the
// owner's Q8 and Q10, critic F10; decided 2026-10-08 under the standing
// authorization; zero requests; step-reading, pre-Q18): engine `_m52Plan`
// counts the lines a batter leaves in the bowl (`_batterInBowl`) as coat
// parts at the coat's one f = min(1, B / Σ carbohydrate), never off a C5
// budget; battered shrimp is C5 on FNDDS 2706364, a battered haddock C5 on
// 2706258; the coat flag says "the batter's excess", names a figure read
// on another food as a stand-in and a batter read on a C1/C2 breading
// figure; negimaki's glaze states its printed split, counted whole. Every
// row value is the v57 replay of snapshot 23 (rp43, fix57 r1), computed
// here on WHOLE recipes over recorded real FDC answers (FixtureProvider; 3
// searches and 1 food added --from-db from snapshot 23, JSON-equal, 0
// existing entries changed), never the network.

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

/// (file, position, raw, fdc id, confidence, grams, kcal, basis) — the v57
/// replay's row; kcal is grams × the record's energy (before any Q25
/// alcohol factor, as the replay's column reads it).
typedef _Row = (String, int, String, int?, String, String?, String, String?);

const _tempura = '0511-shrimp-tempura.yaml';
const _fishChips = '0255-fish-and-chips.yaml';
const _sandwiches = '1081-crispy-fish-sandwiches-with-tartar-sauce.yaml';
const _wings = '0526-dakgangjeong-korean-fried-chicken-wings.yaml';
const _negimakiFile =
    '0516-negimaki-japanese-grilled-steak-and-scallion-rolls.yaml';

/// W's reach (design_v2 §2 M58, exactly these 17 rows; −1,376.44 kcal per
/// batch at the Q25 factor): tempura (B = 15.38 × 680.39 g shrimp, f
/// 0.4690), the sandwiches (B on 566.99 g haddock, f 0.7795), dakgangjeong
/// (C1 wing 5.66, f 0.3345) and fish-and-chips (C5 cod, f 0.4924 — its
/// flour |2, already a coat part, rises as the starch and beer leave B's
/// subtraction). fish-and-chips |3 and |10 read 31.45 and 167.52 at full
/// precision (the design's hand f on rounded grams: 31.46, 167.51).
const List<_Row> _reach = [
  // v56: 212.62 g, 778.19 kcal
  (
    _tempura,
    2,
    '1½ cups (7½ ounces) unbleached all-purpose flour',
    789890,
    '0.950000',
    '99.71',
    '364.94',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw shrimp — USDA FNDDS 2706364 recipe: 25 g breading per 65 g raw shrimp; the batter's excess not counted)",
  ),
  // v56: 63.88 g, 243.38 kcal
  (
    _tempura,
    3,
    '½ cup cornstarch',
    169698,
    '1.000000',
    '29.96',
    '114.15',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw shrimp — USDA FNDDS 2706364 recipe: 25 g breading per 65 g raw shrimp; the batter's excess not counted)",
  ),
  // v56: 224.00 g, 517.44 kcal
  (
    _tempura,
    4,
    '1 cup vodka',
    2710704,
    '0.990000',
    '105.05',
    '242.67',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw shrimp — USDA FNDDS 2706364 recipe: 25 g breading per 65 g raw shrimp; the batter's excess not counted)",
  ),
  // v56: 50.00 g, 74.00 kcal
  (
    _tempura,
    5,
    '1 large egg',
    748967,
    '0.920000',
    '23.45',
    '34.71',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw shrimp — USDA FNDDS 2706364 recipe: 25 g breading per 65 g raw shrimp; the batter's excess not counted)",
  ),
  // v56: 236.59 g, 0.00 kcal
  (
    _tempura,
    6,
    '1 cup seltzer water',
    2710539,
    '0.923333',
    '110.95',
    '0.00',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw shrimp — USDA FNDDS 2706364 recipe: 25 g breading per 65 g raw shrimp; the batter's excess not counted)",
  ),
  // v56: 60.33 g, 220.81 kcal
  (
    _sandwiches,
    6,
    '½ cup all-purpose flour',
    789890,
    '0.950000',
    '47.03',
    '172.13',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw haddock — USDA FNDDS 2706258 recipe: 25 g breading per 65 g raw haddock; the batter's excess not counted)",
  ),
  // v56: 63.88 g, 243.38 kcal
  (
    _sandwiches,
    7,
    '½ cup cornstarch',
    169698,
    '1.000000',
    '49.79',
    '189.70',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw haddock — USDA FNDDS 2706258 recipe: 25 g breading per 65 g raw haddock; the batter's excess not counted)",
  ),
  // v56: 2.27 g, 1.16 kcal
  (
    _sandwiches,
    9,
    '½ teaspoon baking powder',
    172804,
    '0.850000',
    '1.77',
    '0.90',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw haddock — USDA FNDDS 2706258 recipe: 25 g breading per 65 g raw haddock; the batter's excess not counted)",
  ),
  // v56: 180.00 g, 77.40 kcal
  (
    _sandwiches,
    10,
    '¾ cup beer',
    2710616,
    '0.990000',
    '140.31',
    '60.33',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw haddock — USDA FNDDS 2706258 recipe: 25 g breading per 65 g raw haddock; the batter's excess not counted)",
  ),
  // v56: 120.66 g, 441.62 kcal
  (
    _wings,
    8,
    '1 cup all-purpose flour',
    789890,
    '0.950000',
    '40.36',
    '147.72',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.66 g carbohydrate per 100 g of the raw chicken wings — USDA FNDDS 2706065 recipe: 15 g breading per 105.96 g raw chicken wing (a batter read on a breading figure); the batter's excess not counted)",
  ),
  // v56: 23.95 g, 91.27 kcal
  (
    _wings,
    9,
    '3 tablespoons cornstarch',
    169698,
    '1.000000',
    '8.01',
    '30.52',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.66 g carbohydrate per 100 g of the raw chicken wings — USDA FNDDS 2706065 recipe: 15 g breading per 105.96 g raw chicken wing (a batter read on a breading figure); the batter's excess not counted)",
  ),
  // v56: 59.95 g, 219.42 kcal
  (
    _fishChips,
    2,
    '1½ cups unbleached all-purpose flour',
    789890,
    '0.950000',
    '89.12',
    '326.18',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading per 65 g raw cod; the batter's excess not counted)",
  ),
  // v56: 63.88 g, 243.38 kcal
  (
    _fishChips,
    3,
    '½ cup cornstarch',
    169698,
    '1.000000',
    '31.45',
    '119.82',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading per 65 g raw cod; the batter's excess not counted)",
  ),
  // v56: 0.90 g, 2.86 kcal
  (
    _fishChips,
    4,
    '½ teaspoon cayenne pepper',
    170932,
    '1.000000',
    '0.44',
    '1.40',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading per 65 g raw cod; the batter's excess not counted)",
  ),
  // v56: 1.16 g, 3.27 kcal
  (
    _fishChips,
    5,
    '½ teaspoon paprika',
    171329,
    '0.900000',
    '0.57',
    '1.61',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading per 65 g raw cod; the batter's excess not counted)",
  ),
  // v56: 4.53 g, 2.31 kcal
  (
    _fishChips,
    8,
    '1 teaspoon baking powder',
    172804,
    '0.850000',
    '2.23',
    '1.14',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading per 65 g raw cod; the batter's excess not counted)",
  ),
  // v56: 340.19 g, 146.28 kcal
  (
    _fishChips,
    10,
    '1½ cups (12 ounces) cold beer',
    2710616,
    '0.565000',
    '167.52',
    '72.03',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading per 65 g raw cod; the batter's excess not counted)",
  ),
];

/// S (flag only, 0 kcal): a coat figure read on another food says it stands
/// in, as the uptake clause on the same recipes does — chicken on the
/// country-fried steak (C1d), pork and crab on the fried breast (C1).
const List<_Row> _standIns = [
  // v56: the same grams; the flag moved
  (
    '0148-crispy-fried-chicken.yaml',
    8,
    '4 cups (20 ounces) unbleached all-purpose flour',
    789890,
    '0.950000',
    '144.06',
    '527.26',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 8.79 g carbohydrate per 100 g of the raw chicken — USDA FNDDS 2705842 recipe: 20 g breading per 90.99 g raw beef steak (no record for chicken; read as Beef, steak, country fried); the dredge's excess not counted)",
  ),
  // v56: the same grams; the flag moved
  (
    '0198-crispy-pan-fried-pork-chops.yaml',
    0,
    '⅔ cup cornstarch',
    169698,
    '1.000000',
    '49.83',
    '189.85',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
  // v56: the same grams; the flag moved
  (
    '0233-pork-schnitzel-breaded-pork-cutlets.yaml',
    0,
    '7 slices high-quality white sandwich bread, crusts removed, cut into ¾-inch cubes (about 4 cups)',
    174924,
    '0.914286',
    '39.27',
    '104.46',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
  // v56: the same grams; the flag moved
  (
    '0233-pork-schnitzel-breaded-pork-cutlets.yaml',
    1,
    '½ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '16.92',
    '61.93',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
  // v56: the same grams; the flag moved
  (
    '0288-maryland-crab-cakes.yaml',
    8,
    '¼ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '30.16',
    '110.39',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw crab — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for crab; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
];

/// Q10 (flag only, 0 kcal): negimaki's glaze, counted whole, states the
/// printed split ("Divide evenly between two bowls … set aside for
/// serving"; "Discard remaining glaze"). Its flank steak has no coat shape
/// (grilled), so the glaze never reaches W.
const List<_Row> _negimaki = [
  // v56: the same grams; the flag moved
  (
    _negimakiFile,
    1,
    '⅓ cup soy sauce',
    2707442,
    '0.990000',
    '91.48',
    '48.48',
    '1/3 cup ≈ 79 mL · approximate (the steps divide the glaze evenly between two bowls — one half served, the other brushed on and its rest discarded; counted whole)',
  ),
  // v56: the same grams; the flag moved
  (
    _negimakiFile,
    2,
    '3 tablespoons sugar',
    746784,
    '0.950000',
    '37.71',
    '145.17',
    '3 tablespoon ≈ 44 mL · approximate (the steps divide the glaze evenly between two bowls — one half served, the other brushed on and its rest discarded; counted whole)',
  ),
  // v56: the same grams; the flag moved
  (
    _negimakiFile,
    3,
    '2 tablespoons mirin',
    2710692,
    '0.990000',
    '30.00',
    '48.00',
    '2 tablespoon · USDA portion · approximation (counted as Wine, dessert, sweet) · approximate (the steps divide the glaze evenly between two bowls — one half served, the other brushed on and its rest discarded; counted whole)',
  ),
  // v56: the same grams; the flag moved
  (
    _negimakiFile,
    4,
    '2 tablespoons sake',
    167723,
    '0.790000',
    '29.10',
    '38.99',
    '2 tablespoon · USDA portion · approximate (the steps divide the glaze evenly between two bowls — one half served, the other brushed on and its rest discarded; counted whole)',
  ),
];

/// Equal to v56: three of the recipes' frying oils (tempura's uptake stays
/// O2s 15.38 — C5 is not C3; fish-and-chips' oil, unmoved by W, reads
/// another peanut-oil record in a fresh compute than in snapshot 23 and is
/// pinned there by nutrition_v53_test);
/// the dips W does not read — a dough (the scones), a rolled cocoa coat
/// (the truffles), egg washes (E is M62's: katsu, lighter parmesan) — and
/// the floured shrimp with no batter sentence, still C3.
const List<_Row> _kept = [
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
    _wings,
    7,
    '2 quarts vegetable oil',
    2710180,
    '0.923333',
    '44.97',
    '404.73',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.61 % of the raw chicken wings' weight — USDA FNDDS 2706065 recipe: 7 g oil per 105.96 g raw chicken wing)",
  ),
  (
    '0758-british-style-currant-scones.yaml',
    0,
    '3 cups (15 ounces) all-purpose flour',
    789890,
    '0.950000',
    '425.24',
    '1556.39',
    'from 15 ounce · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0852-chocolate-truffles.yaml',
    6,
    '1 cup (3 ounces) Dutch-processed cocoa',
    169594,
    '0.623214',
    '85.05',
    '187.11',
    'from 3 ounce · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0279-crispy-salt-and-pepper-shrimp.yaml',
    8,
    '5 tablespoons cornstarch',
    169698,
    '1.000000',
    '39.92',
    '152.10',
    'discarded in cooking — only the part the recipe keeps and the coat on the food counted · approximation (coat: 3.94 g carbohydrate per 100 g of the raw shrimp — derived from USDA SR Legacy 171982 "Mollusks, squid, mixed species, cooked, fried"; the dredge\'s excess not counted)',
  ),
  (
    '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
    1,
    '2 large eggs',
    748967,
    '0.920000',
    '100.00',
    '148.00',
    '2 × 50 g each · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0416-lighter-chicken-parmesan.yaml',
    6,
    '3 large egg whites',
    747997,
    '0.950000',
    '99.00',
    '54.45',
    '3 × 33 g each · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
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
    // RE-PIN (M59 batch, v58): matcherVersion 57 (was 56).
    // RE-PIN (M60 batch, v59): matcherVersion 58 (was 57).
    expect(matcherVersion, 58);
  });

  group('matcher v57 (batch M58)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v57-');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath)
        ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: pendingSearches);
      // The detail snapshot 23 holds for dakgangjeong's wings (a weight
      // line fetches none: without it the energy is the search hit's
      // rounded 168 for 167.55 — 513.72 kcal per serving for the replay's
      // 512.96).
      db.fdcFoodCachePut(
        2727568,
        jsonEncode((await provider.food(2727568))!.toJson()),
      );
      // Each recipe stored and computed whole — lighter-chicken-parmesan's
      // one section (its Simple Tomato Sauce) computed first, as the replay
      // does.
      for (final (file, _, _, _, _, _, _, _) in [
        ..._reach,
        ..._standIns,
        ..._negimaki,
        ..._kept,
      ]) {
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

    test(
      'W reaches exactly its 17 rows: each batter line a coat part at '
      "the coat's one f, `discarded`, the batter flag (design_v2 §2 M58)",
      () {
        expect(_reach, hasLength(17));
        expectRows(_reach);
        for (final (file, position, _, _, _, _, _, _) in _reach) {
          expect(
            rowOf(file, position).gramSource,
            'discarded',
            reason: '$file|$position',
          );
        }
        // The design's named pins, read off the tuples above.
        String g(String file, int position) =>
            rowOf(file, position).grams!.toStringAsFixed(2);
        expect(g(_tempura, 2), '99.71');
        expect(g(_tempura, 4), '105.05');
        expect(g(_fishChips, 2), '89.12');
        expect(g(_sandwiches, 7), '49.79');
        expect(g(_wings, 8), '40.36');
        expect(
          basisOf(_sandwiches, 7),
          contains(
            'USDA FNDDS 2706258 recipe: 25 g breading per 65 g raw '
            'haddock',
          ),
        );
        expect(
          basisOf(_wings, 8),
          contains(
            'raw chicken wing (a batter read on a breading figure); '
            "the batter's excess not counted)",
          ),
        );
        expect(
          basisOf(_tempura, 2),
          contains(
            'USDA FNDDS 2706364 recipe: 25 g breading per 65 g raw '
            "shrimp; the batter's excess not counted)",
          ),
        );
      },
    );

    test("Q25 rides on W's grams: tempura's vodka keeps its 85 % flag at "
        '105.05 g, the beers theirs', () {
      String? retention(String file, int position) => alcoholRetentionOf(
        recipes[file]!,
        nutritionLines(recipes[file]!)[position],
        rowOf(file, position),
      )?.flag;
      expect(
        retention(_tempura, 4),
        'approximate (USDA retention: alcohol cooked 2 min keeps 85 %, the '
        'stirred-into-hot-liquid figure)',
      );
      expect(retention(_fishChips, 10), contains('keeps 85 %'));
      expect(retention(_sandwiches, 10), contains('keeps 85 %'));
    });

    test(
      'S: a coat figure read on another food names the stand-in (five '
      'rows, grams unmoved); a same-family figure and a derived C3 do not',
      () {
        expect(_standIns, hasLength(5));
        expectRows(_standIns);
        // Same family (chicken on the breast, pork on the pork chop, beef on
        // the country-fried steak) or derived (C3): no suffix.
        expect(
          db
              .ingredientMatchesFor(recipes[_fishChips]!.id)
              .where((r) => r.gramSource == 'discarded')
              .map((r) => basisOf(_fishChips, r.position)!)
              .where((b) => b.contains('no record for')),
          isEmpty,
        );
        expect(
          basisOf('0279-crispy-salt-and-pepper-shrimp.yaml', 8),
          isNot(contains('no record for')),
        );
      },
    );

    test("Q10: negimaki's glaze states the printed split, counted whole "
        '(0 kcal)', () {
      expect(_negimaki, hasLength(4));
      expectRows(_negimaki);
    });

    test('the frying oils and the dips W does not read equal v56 (the '
        'scones, the truffles, the egg washes, the C3 shrimp)', () {
      expectRows(_kept);
    });

    test('the four recipes move kcal per serving only: statuses unchanged '
        '(tempura partial on its 0 g dipping-sauce reference)', () {
      (String, String) of(String file) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        return (n.status, n.caloriesPerServing!.toStringAsFixed(2));
      }

      expect(of(_tempura), ('partial', '280.02')); // v56 381.94
      expect(of(_wings), ('complete', '512.96')); // v56 601.62
      expect(of(_sandwiches), ('complete', '1028.23')); // v56 1,057.75
      // fish-and-chips (replay 981.40, v56 1,003.49): its oil |1 reads
      // 172336 in a fresh compute, 2710187 in snapshot 23 (above) — the
      // status only.
      expect(of(_fishChips).$1, 'complete');
    });

    test('a second recompute writes nothing: the batter lines, written '
        "`discarded`, are parts again and never come off C5's B", () {
      for (final file in const [_tempura, _wings, _sandwiches, _fishChips]) {
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

    test("a person's CONFIRM of a batter line keeps the budget's grams the "
        'GET showed (verify2 D1, as for a coat): tempura|2 99.71, the '
        'totals unmoved', () async {
      final tempura = recipes[_tempura]!;
      final line = nutritionLines(tempura)[2];
      final basis = basisOf(_tempura, 2);
      final before = db.nutritionFor(tempura.id)!;
      await applyMatchOverride(db, provider, tempura, 2, {
        'raw': line.raw,
        'confirmed': true,
      });
      final row = rowOf(_tempura, 2);
      expect(
        (row.status, row.grams!.toStringAsFixed(2), row.gramSource),
        ('confirmed', '99.71', 'discarded'),
      );
      expect(basisOf(_tempura, 2), basis);
      final shown = [
        for (final item
            in (await matchesBody(db, provider, tempura))['items']! as List)
          if ((item as Map<String, Object?>)['position'] == 2)
            (
              ((item['match']! as Map)['grams']! as double).toStringAsFixed(
                2,
              ),
              (item['match']! as Map)['gram_basis'],
            ),
      ];
      expect(shown, [('99.71', basis)]);
      final after = db.nutritionFor(tempura.id)!;
      expect(
        (after.status, after.caloriesPerServing!.toStringAsFixed(2)),
        (before.status, before.caloriesPerServing!.toStringAsFixed(2)),
      );
    });
  });
}
