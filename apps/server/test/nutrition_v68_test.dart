// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v68 (batch M69 — sautéed and vegetable coats; matcherVersion 67;
// prep49 design_v2 §2 M69, the owner's Q4 ruling (b) of 2026-10-09 and Q6
// (a); zero requests; reach PRE-Q18 — the thin trigger reads steps): R1 — a
// held flour dredge on a THIN piece that neither fries nor bakes after the
// coat (a step pounds it ⅛–½ inch thick, or its line prints the thickness)
// is C4 and counts at C2's read 3.18 (FNDDS 2705980) as the stand-in, the
// flag naming the unused Veal Marsala read 7.82; R2 — with no meat beside a
// held coat, a coated EGGPLANT sizes the coat at 7.93 read from FNDDS
// 2710050's batter; the onion rings stay held. Every row value is the fresh
// compute of the WHOLE recipe (sections first) over recorded real FDC
// answers (FixtureProvider), equal to the v68 replay of snapshot 26 (rp43,
// fix68 r1) on every pinned field and, on every row M69 must not move, to
// the v67 rows; never the network.
// Synthesized, STATED (no corpus recipe carries them): a meunière copy whose
// fish line drops "⅜ inch thick" and a piccata copy whose pound sentence
// says "press" — each to show its trigger alone reaches the row; and an
// eggplant-parmesan copy whose S4 fries the breaded slices in a skillet and
// whose S6 does not bake (closer 2, verify2 D1) — a fried coated eggplant
// stays held; and an eggplant-parmesan copy whose S3 whisks the flour and
// eggs into a batter, still baked (closer 3, verify3 D1) — the flag names
// the read a batter once.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

/// (file, section title, position, raw, fdc id, description, confidence,
/// grams, status, hold, kcal, basis) — a row of the fresh compute.
typedef _Row = (
  String,
  String?,
  int,
  String,
  int?,
  String,
  String,
  String?,
  String,
  String?,
  String?,
  String?,
);

const _piccata = '0418-chicken-piccata.yaml';
const _nextLevel = '0418-next-level-chicken-piccata.yaml';
const _marsala = '0415-better-chicken-marsala.yaml';
const _francese = '0420-chicken-francese.yaml';
const _saltimbocca = '0421-chicken-saltimbocca.yaml';
const _meuniere = '0466-fish-meuniere-with-browned-butter-and-lemon.yaml';
const _parmesanCrusted = '0419-parmesan-crusted-chicken-cutlets.yaml';
const _eggplant = '0407-eggplant-parmesan.yaml';
const _onionRings = '0315-oven-fried-onion-rings.yaml';
const _salmon = '0257-pan-seared-salmon-steaks.yaml';
const _maple = '0235-maple-glazed-pork-tenderloin.yaml';
const _skillet = '0077-skillet-chicken-and-rice-with-peas-and-scallions.yaml';
const _chickenMarsala = '0414-chicken-marsala.yaml';
const _francese2 = '1133-chicken-francese.yaml';
const _tacos = '1093-vegan-baja-style-cauliflower-tacos.yaml';

const String _coatOn =
    'discarded in cooking — only the coat on the food counted · ';

/// C4's flag (the owner's ruling (b)): C2's read as the stand-in, the
/// unused Veal Marsala read named.
String _c4(String food) =>
    '${_coatOn}approximation (coat: 3.18 g carbohydrate per 100 g of the raw '
    '$food — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw '
    'chicken breast (no record for a sautéed flour dusting; read as the '
    'baked breaded breast, the lightest coat USDA prints; FNDDS 2706416 Veal '
    "Marsala's 62.5 g flour per 617.60 g raw veal, 7.82, counts the dish's "
    "whole flour, sauce included, and is not read); the dredge's excess not "
    'counted)';
final String _c4Breast = _c4('chicken breast');
final String _c4Sole = _c4('flatfish');

/// R2's flag: FNDDS 2710050's batter, listed, with its water.
const String _eggplantCoat =
    '${_coatOn}approximation (coat: 7.93 g carbohydrate per 100 g of the raw '
    'eggplant — USDA FNDDS 2710050 recipe: 13.2 g batter (4 g flour, 0.5 g '
    'dried egg, 8.3 g water, 0.3 g dry milk, 0.1 g baking powder; 3.28 g '
    'carbohydrate) per 41.4 g raw eggplant (a crumb coat read on a batter '
    'figure; 8.3 g of the 13.2 g batter is water and carries no '
    "carbohydrate); the dredge's excess not counted)";

/// R2's flag when the eggplant's coat parts include a batter left in the bowl
/// (closer 3, verify3 D1): the read IS a batter — no crumb clause, no
/// "batter read on a breading figure"; the water clause stays.
const String _eggplantBatter =
    '${_coatOn}approximation (coat: 7.93 g carbohydrate per 100 g of the raw '
    'eggplant — USDA FNDDS 2710050 recipe: 13.2 g batter (4 g flour, 0.5 g '
    'dried egg, 8.3 g water, 0.3 g dry milk, 0.1 g baking powder; 3.28 g '
    'carbohydrate) per 41.4 g raw eggplant (8.3 g of the 13.2 g batter is '
    "water and carries no carbohydrate); the batter's excess not counted)";

/// M62 E-w's dip basis (unchanged; the dips of a coat M69 budgets).
const String _dipBasis =
    'discarded in cooking — only the dip on the food counted · approximation '
    "(dip: 1.17 g per g of the coat's carbohydrate — USDA FNDDS 2710785 "
    '"Breading or batter as ingredient in food": 15 g egg and 120 g water in '
    "287 g at 40.1 g carbohydrate per 100 g; the dip's excess not counted)";

/// The 15 rows M69 moves (fix68 r1 vs the v67 rows; all `auto`, held
/// `coating` 0 g → counted `discarded`): R1's 11 (C4 at 3.18) and R2's 4
/// (the eggplant at 7.93).
final List<_Row> _reach = [
  (
    _piccata,
    null,
    3,
    '½ cup unbleached all-purpose flour',
    789890,
    'Flour, wheat, all-purpose, enriched, bleached',
    '0.950000',
    '27.99',
    'auto',
    null,
    '102.44',
    _c4Breast,
  ),
  (
    _nextLevel,
    null,
    3,
    '¾ cup all-purpose flour',
    789890,
    'Flour, wheat, all-purpose, enriched, bleached',
    '0.950000',
    '32.66',
    'auto',
    null,
    '119.54',
    _c4Breast,
  ),
  (
    _marsala,
    null,
    6,
    '¾ cup all-purpose flour',
    789890,
    'Flour, wheat, all-purpose, enriched, bleached',
    '0.950000',
    '32.66',
    'auto',
    null,
    '119.54',
    _c4Breast,
  ),
  (
    _francese,
    null,
    9,
    '1 cup unbleached all-purpose flour',
    789890,
    'Flour, wheat, all-purpose, enriched, bleached',
    '0.950000',
    '25.66',
    'auto',
    null,
    '93.92',
    _c4Breast,
  ),
  (
    _francese,
    null,
    10,
    '2 large eggs',
    748967,
    'Eggs, Grade A, Large, egg whole',
    '0.920000',
    '17.83',
    'auto',
    null,
    '26.39',
    _dipBasis,
  ),
  (
    _francese,
    null,
    11,
    '2 tablespoons milk',
    2705385,
    'Milk, whole',
    '0.910000',
    '5.43',
    'auto',
    null,
    '3.31',
    _dipBasis,
  ),
  (
    _saltimbocca,
    null,
    1,
    '½ cup unbleached all-purpose flour',
    789890,
    'Flour, wheat, all-purpose, enriched, bleached',
    '0.950000',
    '25.66',
    'auto',
    null,
    '93.92',
    _c4Breast,
  ),
  (
    _meuniere,
    null,
    0,
    '½ cup unbleached all-purpose flour',
    789890,
    'Flour, wheat, all-purpose, enriched, bleached',
    '0.950000',
    '25.66',
    'auto',
    null,
    '93.92',
    _c4Sole,
  ),
  (
    _parmesanCrusted,
    null,
    2,
    '5 tablespoons unbleached all-purpose flour',
    789890,
    'Flour, wheat, all-purpose, enriched, bleached',
    '0.950000',
    '17.49',
    'auto',
    null,
    '64.01',
    _c4Breast,
  ),
  (
    _parmesanCrusted,
    null,
    4,
    '3 large egg whites',
    747997,
    'Eggs, Grade A, Large, egg white',
    '0.950000',
    '14.96',
    'auto',
    null,
    '8.23',
    _dipBasis,
  ),
  (
    _parmesanCrusted,
    null,
    5,
    '2 tablespoons minced fresh chives (optional)',
    169994,
    'Chives, raw',
    '0.920000',
    '0.91',
    'auto',
    null,
    '0.27',
    _dipBasis,
  ),
  (
    _eggplant,
    null,
    2,
    '8 slices high-quality white sandwich bread, torn into quarters',
    174924,
    'Bread, white, commercially prepared (includes soft bread crumbs)',
    '0.914286',
    '76.37',
    'auto',
    null,
    '203.14',
    _eggplantCoat,
  ),
  (
    _eggplant,
    null,
    3,
    '2 ounces Parmesan cheese, grated (about 1 cup)',
    325036,
    'Cheese, parmesan, grated',
    '0.983333',
    '19.33',
    'auto',
    null,
    '81.38',
    _eggplantCoat,
  ),
  (
    _eggplant,
    null,
    5,
    '1 cup unbleached all-purpose flour',
    789890,
    'Flour, wheat, all-purpose, enriched, bleached',
    '0.950000',
    '41.14',
    'auto',
    null,
    '150.57',
    _eggplantCoat,
  ),
  (
    _eggplant,
    null,
    6,
    '4 large eggs',
    748967,
    'Eggs, Grade A, Large, egg whole',
    '0.920000',
    '84.39',
    'auto',
    null,
    '124.90',
    _dipBasis,
  ),
];

/// Rows M69 must not move, equal to the v67 rows: the thick pieces' and the
/// sugar-dusted tenderloin's dredges (no pound-thin print), the onion rings
/// (no sourced figure — held), parmesan-crusted's cheese crust (Q5), the
/// fried twin's flour (C1), 0414's whole flour (no excess printed, no hold),
/// and H2's cauliflower tacos (its coat counted, never read by the plan).
const List<_Row> _negatives = [
  (
    _salmon,
    null,
    2,
    '¼ cup cornstarch',
    169698,
    'Cornstarch',
    '1.000000',
    null,
    'auto',
    'coating',
    null,
    null,
  ),
  (
    _maple,
    null,
    6,
    '¼ cup cornstarch',
    169698,
    'Cornstarch',
    '1.000000',
    null,
    'auto',
    'coating',
    null,
    null,
  ),
  (
    _skillet,
    null,
    2,
    '½ cup unbleached all-purpose flour',
    789890,
    'Flour, wheat, all-purpose, enriched, bleached',
    '0.950000',
    null,
    'auto',
    'coating',
    null,
    null,
  ),
  (
    _onionRings,
    null,
    0,
    '½ cup unbleached all-purpose flour',
    789890,
    'Flour, wheat, all-purpose, enriched, bleached',
    '0.950000',
    '30.16',
    'auto',
    'coating',
    null,
    'discarded in cooking — only the part the recipe keeps counted',
  ),
  (
    _onionRings,
    null,
    1,
    '1 large egg, at room temperature',
    748967,
    'Eggs, Grade A, Large, egg whole',
    '0.920000',
    null,
    'auto',
    'coating',
    null,
    null,
  ),
  (
    _onionRings,
    null,
    2,
    '½ cup buttermilk, at room temperature',
    2705393,
    'Buttermilk',
    '0.990000',
    null,
    'auto',
    'coating',
    null,
    null,
  ),
  (
    _onionRings,
    null,
    3,
    '½ teaspoon table salt',
    173468,
    'Salt, table',
    '1.000000',
    null,
    'auto',
    'coating',
    null,
    null,
  ),
  (
    _onionRings,
    null,
    4,
    '¼ teaspoon ground black pepper',
    170931,
    'Spices, pepper, black',
    '1.000000',
    null,
    'auto',
    'coating',
    null,
    null,
  ),
  (
    _onionRings,
    null,
    5,
    '¼ teaspoon cayenne pepper',
    170932,
    'Spices, pepper, red or cayenne',
    '1.000000',
    null,
    'auto',
    'coating',
    null,
    null,
  ),
  (
    _onionRings,
    null,
    6,
    '30 saltine crackers',
    2708167,
    'Crackers, saltine',
    '0.990000',
    null,
    'auto',
    'coating',
    null,
    null,
  ),
  (
    _onionRings,
    null,
    7,
    '4 cups kettle-cooked potato chips',
    2709422,
    'Potato chips, plain',
    '0.990000',
    null,
    'auto',
    'coating',
    null,
    null,
  ),
  (
    _parmesanCrusted,
    null,
    3,
    '¼ cup grated Parmesan cheese plus 6 ounces, shredded (about 2 cups; see note)',
    325036,
    'Cheese, parmesan, grated',
    '0.983333',
    null,
    'auto',
    'coating',
    null,
    null,
  ),
  (
    _francese2,
    null,
    5,
    '¾ cup all-purpose flour, divided',
    789890,
    'Flour, wheat, all-purpose, enriched, bleached',
    '0.950000',
    '61.35',
    'auto',
    null,
    '224.54',
    "discarded in cooking — only the part the recipe keeps and the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    _chickenMarsala,
    null,
    1,
    '1 cup unbleached all-purpose flour',
    789890,
    'Flour, wheat, all-purpose, enriched, bleached',
    '0.950000',
    '120.66',
    'auto',
    null,
    '441.62',
    '1 cup ≈ 237 mL',
  ),
  (
    _tacos,
    null,
    0,
    '3 cups (7½ ounces) coleslaw mix',
    2346407,
    'Cabbage, green, raw',
    '1.000000',
    '212.62',
    'auto',
    null,
    '66.76', // replay 66.82: the fresh compute reads the search hit's energy
    'from 7 1/2 ounce',
  ),
  (
    _tacos,
    null,
    1,
    '½ mango, peeled and cut into ¼-inch pieces (¾ cup)',
    169910,
    'Mangos, raw',
    '0.920000',
    '123.75',
    'auto',
    null,
    '74.25',
    '3/4 cup · USDA portion',
  ),
  (
    _tacos,
    null,
    2,
    '1 tablespoon chopped fresh cilantro',
    2709782,
    'Cilantro, raw',
    '0.910000',
    '1.00',
    'auto',
    null,
    '0.23',
    '1 tablespoon · USDA portion',
  ),
  (
    _tacos,
    null,
    3,
    '2 tablespoons lime juice',
    168156,
    'Lime juice, raw',
    '0.953333',
    '30.46',
    'auto',
    null,
    '7.62',
    '2 tablespoon ≈ 30 mL',
  ),
  (
    _tacos,
    null,
    4,
    '1 tablespoon minced jalapeño chile',
    2747661,
    'Peppers, jalapeno, seeded, raw',
    '0.920000',
    '9.38',
    'auto',
    null,
    '2.26',
    '1 tablespoon · USDA portion of "Peppers, jalapenos"',
  ),
  (
    _tacos,
    null,
    6,
    '1 cup unsweetened shredded coconut',
    170170,
    'Nuts, coconut meat, dried (desiccated), not sweetened',
    '0.734524',
    '93.00',
    'auto',
    null,
    '613.80',
    '1 cup · USDA portion of "Nuts, coconut meat, dried (desiccated), sweetened, shredded"',
  ),
  (
    _tacos,
    null,
    7,
    '1 cup panko bread crumbs',
    174928,
    'Bread, crumbs, dry, grated, plain',
    '0.563333',
    '59.15',
    'auto',
    null,
    '233.63',
    '1 cup ≈ 237 mL',
  ),
  (
    _tacos,
    null,
    8,
    '1 cup canned coconut milk',
    170173,
    'Nuts, coconut milk, canned (liquid expressed from grated meat and water)',
    '0.860000',
    '243.69',
    'auto',
    null,
    '480.06',
    '1 cup ≈ 237 mL',
  ),
  (
    _tacos,
    null,
    9,
    '1 teaspoon garlic powder',
    171325,
    'Spices, garlic powder',
    '0.933333',
    '3.11',
    'auto',
    null,
    '10.28',
    '1 teaspoon ≈ 5 mL',
  ),
  (
    _tacos,
    null,
    10,
    '1 teaspoon ground cumin',
    170923,
    'Spices, cumin seed',
    '0.933333',
    '2.12',
    'auto',
    null,
    '7.95',
    '1 teaspoon ≈ 5 mL',
  ),
  (
    _tacos,
    null,
    11,
    '¼ teaspoon cayenne',
    170932,
    'Spices, pepper, red or cayenne',
    '1.000000',
    '0.46',
    'auto',
    null,
    '1.45',
    '1/4 teaspoon ≈ 1 mL',
  ),
  (
    _tacos,
    null,
    12,
    '½ head cauliflower (1 pound), trimmed and cut into 1-inch pieces',
    2685573,
    'Cauliflower, raw',
    '0.970000',
    '417.30',
    'auto',
    null,
    '115.18', // replay 115.14 (as |0)
    'from 1 pound × 0.92 edible · approximate (USDA AH-102 item 499: cauliflower, raw whole head → fully trimmed, head or flowerbud 92 % (83–100))',
  ),
  (
    _tacos,
    null,
    13,
    '8–12 (6-inch) corn tortillas, warmed',
    2707823,
    'Tortilla, corn',
    '0.990000',
    '260.00',
    'auto',
    null,
    '566.80',
    '8–12 × 26 g each',
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
    expect(matcherVersion, 67);
  });

  group('matcher v68 (batch M69)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;
    final recipes = <String, Recipe>{};

    /// [recipe] stored and computed whole, its sections first, as the
    /// replay does; the stored recipe.
    Future<Recipe> compute(Recipe recipe) async {
      db.upsertRecipe(recipe, sourceSlug: _source, contentHash: recipe.id);
      final stored = db.recipeByIdOrSlug(recipe.id)!.recipe;
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
      return db.recipeByIdOrSlug(recipe.id)!.recipe;
    }

    /// A computed copy of [corpus] under a new id.
    Future<Recipe> variant(Recipe corpus, String id) => compute(
      corpus.copyWith(id: '${corpus.id}-$id', slug: '${corpus.slug}-$id'),
    );

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v68-');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath)
        ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: pendingSearches);
      for (final (file, _, _, _, _, _, _, _, _, _, _, _) in [
        ..._reach,
        ..._negatives,
      ]) {
        if (!recipes.containsKey(file)) {
          recipes[file] = await compute(loadCorpusRecipe(file));
        }
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    IngredientMatchRow rowIn(Recipe recipe, int position) => db
        .ingredientMatchesFor(recipe.id)
        .singleWhere((m) => m.position == position);

    IngredientMatchRow rowOf(String file, int position) =>
        rowIn(recipes[file]!, position);

    String? basisIn(Recipe recipe, int position) => gramBasisFor(
      db,
      nutritionLines(recipe)[position],
      rowIn(recipe, position),
      recipe: recipe,
    );

    /// Each [rows] entry in its whole recipe: the record, the description,
    /// the confidence, the grams, the status, the hold, the energy and the
    /// basis.
    void expectRows(List<_Row> rows) {
      for (final (
            file,
            _,
            position,
            raw,
            fdcId,
            description,
            confidence,
            grams,
            status,
            hold,
            kcal,
            basis,
          )
          in rows) {
        final line = nutritionLines(recipes[file]!)[position];
        final row = rowOf(file, position);
        final reason = '$file|$position';
        expect(line.raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.description, description, reason: reason);
        expect(row.confidence.toStringAsFixed(6), confidence, reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(row.status, status, reason: reason);
        expect(row.hold, hold, reason: reason);
        if (kcal != null) {
          expect(
            _kcalOf(db, row, line).toStringAsFixed(2),
            kcal,
            reason: reason,
          );
        }
        expect(basisIn(recipes[file]!, position), basis, reason: reason);
      }
    }

    String g2(double v) => v.toStringAsFixed(2);

    test('M69 reaches exactly its 15 rows, each `discarded` (design_v2 §2 '
        'M69 at the ruling (b); the onion rings not reached)', () {
      expect(_reach, hasLength(15));
      expectRows(_reach);
      for (final (file, _, position, _, _, _, _, _, _, _, _, _) in _reach) {
        expect(
          rowOf(file, position).gramSource,
          'discarded',
          reason: '$file|$position',
        );
      }
    });

    (double, FdcFood) whole(String file, int p) {
      final recipe = recipes[file]!;
      final line = nutritionLines(recipe)[p];
      final food = knownFood(db, rowIn(recipe, p).fdcId!, line: line)!;
      return (lineGrams(db, line, food, recipe: recipe)!.grams, food);
    }

    double cho(FdcFood food) => food.nutrientsPer100g['205']! / 100;

    // The plan's f figures (0.463952, 0.360852, 0.463947, f_w 0.178330 /
    // 0.151070; the eggplant's B 71.9394, f 0.340942, f_w 0.421934) are on
    // the coated food's grams ROUNDED to 2 dp; the engine reads the stored
    // unrounded grams (680.388 …, 907.1847): the 6th decimal moves, no
    // row's grams do.
    test('R1 by hand at 3.18 (B = 3.18 × the coated food / 100; f = B / the '
        "flour's carbohydrate): piccata f 0.463950 → 27.99; next-level and "
        'marsala f 0.360850 → 32.66; francese f 0.212644 → 25.66; '
        'saltimbocca and the sole f 0.425288 → 25.66; parmesan-crusted f '
        '0.463949 → 17.49; the dips f_w 0.178329 (francese) and 0.151071', () {
      for (final (file, coated, flour, f, grams) in const [
        (_piccata, 1, 3, '0.463950', '27.99'),
        (_nextLevel, 0, 3, '0.360850', '32.66'),
        (_marsala, 3, 6, '0.360850', '32.66'),
        (_francese, 7, 9, '0.212644', '25.66'),
        (_saltimbocca, 0, 1, '0.425288', '25.66'),
        (_meuniere, 1, 0, '0.425288', '25.66'),
        (_parmesanCrusted, 0, 2, '0.463949', '17.49'),
      ]) {
        final b = 3.18 * rowOf(file, coated).grams! / 100;
        final (dredge, food) = whole(file, flour);
        final share = b / (dredge * cho(food));
        expect(share.toStringAsFixed(6), f, reason: file);
        expect(g2(share * dredge), grams, reason: file);
        expect(g2(rowOf(file, flour).grams!), grams, reason: file);
      }
      // The dips: W = 1.1730256 × B over the dip lines' whole grams.
      const wet = (15 + 120) / (287 * 0.401);
      final franceseW = wet * 3.18 * rowOf(_francese, 7).grams! / 100;
      final franceseDips = whole(_francese, 10).$1 + whole(_francese, 11).$1;
      expect((franceseW / franceseDips).toStringAsFixed(6), '0.178329');
      final parmW = wet * 3.18 * rowOf(_parmesanCrusted, 0).grams! / 100;
      final parmDips =
          whole(_parmesanCrusted, 4).$1 + whole(_parmesanCrusted, 5).$1;
      expect((parmW / parmDips).toStringAsFixed(6), '0.151071');
      // The fried twin's C1 (the stated ceiling) and the unused read:
      // 5.73 = 15 × 0.40 / 104.76 × 100; 7.82 = 62.5 × 0.773 / 617.6018 ×
      // 100 (the cooked veal 453.6 g to raw by protein, 29.75 / 21.85).
      expect((15 * 0.40 / 104.76 * 100).toStringAsFixed(2), '5.73');
      expect((10 * 0.40 / 125.77 * 100).toStringAsFixed(2), '3.18');
      const veal = 453.6 * 29.75 / 21.85;
      expect(veal.toStringAsFixed(2), '617.60');
      expect((62.5 * 0.773 / veal * 100).toStringAsFixed(2), '7.82');
    });

    test('R2 by hand at 7.93 (FNDDS 2710050: 3.28499 g batter carbohydrate '
        'per 41.4 g raw eggplant): B 71.9397 on the 907.18 g eggplant, the '
        "three parts' carbohydrate 211.0016 (the bread at the piece table's "
        '28 g a slice), f 0.340944; the eggs f_w 0.421936', () {
      const k =
          (4 * 0.773 + 0.5 * 0.0187 + 0.3 * 0.5198 + 0.1 * 0.277) / 41.4 * 100;
      expect(k.toStringAsFixed(2), '7.93');
      expect(rowOf(_eggplant, 0).description, 'Eggplant, raw');
      final b = 7.93 * rowOf(_eggplant, 0).grams! / 100;
      expect(b.toStringAsFixed(4), '71.9397');
      expect(g2(whole(_eggplant, 2).$1), '224.00');
      var carbs = 0.0;
      for (final p in [2, 3, 5]) {
        final (dredge, food) = whole(_eggplant, p);
        carbs += dredge * cho(food);
      }
      expect(carbs.toStringAsFixed(4), '211.0016');
      final f = b / carbs;
      expect(f.toStringAsFixed(6), '0.340944');
      for (final (p, grams) in const [
        (2, '76.37'),
        (3, '19.33'),
        (5, '41.14'),
      ]) {
        expect(g2(f * whole(_eggplant, p).$1), grams, reason: '$p');
      }
      const wet = (15 + 120) / (287 * 0.401);
      final share = wet * b / whole(_eggplant, 6).$1;
      expect(share.toStringAsFixed(6), '0.421936');
      expect(g2(share * 200), '84.39');
    });

    test("R2 only at C2, the eggplant's one `_coatFigure` arm: a STATED "
        'synthesized copy of 0407 that FRIES the breaded slices with no bake '
        'after (C1) keeps |2 |3 |5 |6 held `coating`, no grams — never the '
        "fried chicken breast's 5.73 (closer 2, verify2 D1)", () async {
      final corpus = loadCorpusRecipe(_eggplant);
      expect(corpus.steps[3].text, startsWith('Remove the preheated baking'));
      expect(corpus.steps[5].text, startsWith('Spread 1 cup of the tomato'));
      final fried = await variant(
        corpus.copyWith(
          steps: [
            for (final (i, s) in corpus.steps.indexed)
              i == 3
                  ? s.copyWith(
                      text:
                          'Heat 3 tablespoons of the vegetable oil in a '
                          '12-inch skillet over medium-high heat until '
                          'shimmering. Fry half of the breaded eggplant '
                          'slices until well browned and crisp, about 4 '
                          'minutes per side; repeat with the remaining oil '
                          'and eggplant.',
                    )
                  : i == 5
                  ? s.copyWith(
                      text:
                          'Layer the eggplant slices with the sauce and the '
                          'mozzarella in a serving dish, sprinkle with the '
                          'Parmesan, scatter the basil over the top, and '
                          'serve.',
                    )
                  : s,
          ],
        ),
        'fried',
      );
      expect(rowIn(fried, 0).grams, rowOf(_eggplant, 0).grams);
      for (final p in const [2, 3, 5, 6]) {
        final row = rowIn(fried, p);
        expect((row.hold, row.grams), ('coating', null), reason: '$p');
        expect(basisIn(fried, p), isNull, reason: '$p');
        expect(rowOf(_eggplant, p).hold, isNull, reason: '$p');
      }
    });

    test("R2's flag on a BATTERED eggplant: a STATED synthesized copy of "
        '0407 whose S3 whisks the flour and eggs into a batter (S4 and S6 '
        'still bake: C2) names the read a batter once — neither "a crumb '
        'coat read on a batter figure" nor "a batter read on a breading '
        'figure"; the water clause stays (closer 3, verify3 D1)', () async {
      final corpus = loadCorpusRecipe(_eggplant);
      expect(corpus.steps[2].text, startsWith('Combine the flour and 1 '));
      final battered = await variant(
        corpus.copyWith(
          steps: [
            for (final (i, s) in corpus.steps.indexed)
              i == 2
                  ? s.copyWith(
                      text:
                          'Whisk the flour, eggs, and 1 teaspoon pepper in a '
                          'medium bowl until smooth. Place 8 to 10 eggplant '
                          'slices in the batter and turn to coat the slices, '
                          'allowing the excess batter to drip off. Dredge the '
                          'slices in the bread-crumb mixture, shaking off the '
                          'excess crumbs; set the breaded slices on a wire '
                          'rack set over a baking sheet. Repeat with the '
                          'remaining eggplant.',
                    )
                  : s,
          ],
        ),
        'battered',
      );
      for (final (p, grams) in const [
        (3, '39.90'),
        (5, '84.92'),
        (6, '140.75'),
      ]) {
        final row = rowIn(battered, p);
        expect(
          (row.hold, row.grams?.toStringAsFixed(2), row.gramSource),
          (null, grams, 'discarded'),
          reason: '$p',
        );
        expect(basisIn(battered, p), _eggplantBatter, reason: '$p');
      }
    });

    test('the thin trigger: the sole by its LINE (no step pounds it), the '
        'piccata by its pound sentence — a STATED synthesized copy of each '
        'without its print keeps the dredge held', () async {
      final sole = loadCorpusRecipe(_meuniere);
      final fish = sole.ingredients.first.items[1];
      expect(
        fish.raw,
        '4 (5- to 6-ounce) sole or flounder fillets, ⅜ inch thick (see note)',
      );
      expect(
        sole.steps.any((s) => s.text.toLowerCase().contains('pound')),
        isFalse,
      );
      final thick = await variant(
        sole.copyWith(
          ingredients: [
            sole.ingredients.first.copyWith(
              items: [
                sole.ingredients.first.items.first,
                fish.copyWith(
                  raw: '4 (5- to 6-ounce) sole or flounder fillets (see note)',
                  prep: '(see note)',
                ),
                ...sole.ingredients.first.items.skip(2),
              ],
            ),
            ...sole.ingredients.skip(1),
          ],
        ),
        'no-thickness',
      );
      expect(rowIn(thick, 1).grams, rowOf(_meuniere, 1).grams);
      expect((rowIn(thick, 0).hold, rowIn(thick, 0).grams), ('coating', null));
      expect(g2(rowOf(_meuniere, 0).grams!), '25.66');

      final piccata = loadCorpusRecipe(_piccata);
      const pound = 'pound cutlets to even ¼-inch thickness';
      final at = piccata.steps.indexWhere(
        (s) => s.text.toLowerCase().contains(pound),
      );
      expect(at, isNot(-1));
      final pressed = await variant(
        piccata.copyWith(
          steps: [
            for (final (i, s) in piccata.steps.indexed)
              i == at
                  ? s.copyWith(
                      text: s.text.replaceFirst(
                        RegExp('[Pp]ound(?= cutlets to even)'),
                        'press',
                      ),
                    )
                  : s,
          ],
        ),
        'pressed',
      );
      expect(
        (rowIn(pressed, 3).hold, rowIn(pressed, 3).grams),
        ('coating', null),
      );
    });

    test("holds: francese|10's dip is counted (`holdNoteOf` null, no longer "
        "the dip sentence); parmesan-crusted|3's cheese crust stays held "
        '(Q5) — its note null, as in v67', () async {
      final francese = recipes[_francese]!;
      final dip = rowOf(_francese, 10);
      expect(dip.hold, isNull);
      expect(
        holdNoteOf(francese, nutritionLines(francese)[10], dip.hold),
        isNull,
      );
      final crusted = recipes[_parmesanCrusted]!;
      final crust = rowOf(_parmesanCrusted, 3);
      expect((crust.hold, crust.grams), ('coating', null));
      final note = holdNoteOf(
        crusted,
        nutritionLines(crusted)[3],
        crust.hold,
      );
      // No dip sentence and no part written outside the dredge: the engine
      // gives the crust no note (v67 the same — the row is unchanged).
      expect(note, isNull);
      final items =
          (await matchesBody(db, provider, crusted))['items']!
              as List<Map<String, Object?>>;
      expect((items[3]['match']! as Map)['hold_note'], note);
    });

    test('the rows M69 must not reach equal v67 (27 rows): the thick '
        "pieces' and the tenderloin's dredges, the 8 onion-ring rows "
        "(|0's 30.16 g eaten part kept), parmesan-crusted|3, the fried "
        "twin's C1 flour, 0414's whole flour, H2's tacos", () {
      expect(_negatives, hasLength(27));
      expectRows(_negatives);
      expect(g2(rowOf(_francese2, 5).grams!), '61.35');
      expect(g2(rowOf(_chickenMarsala, 1).grams!), '120.66');
      for (final p in [0, 1, 2, 3, 4, 5, 6, 7]) {
        expect(rowOf(_onionRings, p).hold, 'coating', reason: '$p');
      }
    });

    test(
      'per serving: the 8 recipes move (6 turn complete; parmesan-crusted '
      'and the eggplant stay partial on |3 and |1); the others equal v67',
      () {
        (String, String) of(String file) {
          final n = db.nutritionFor(recipes[file]!.id)!;
          return (n.status, n.caloriesPerServing!.toStringAsFixed(2));
        }

        // A fresh compute here; the replay's v67 → v68 in the comment. A
        // chicken, pork or vegetable line counted on a search hit reads
        // FDC's rounded energy here (the v61 note): the fresh figures sit
        // within 0.07 of the replay's, each recipe moving by its M69 rows.
        expect(of(_piccata), ('complete', '425.39')); // replay 399.84 → 425.45
        expect(of(_nextLevel), (
          'complete',
          '472.45',
        )); // replay 442.64 → 472.52
        expect(of(_marsala), ('complete', '734.28')); // replay 704.46 → 734.35
        expect(of(_francese), ('complete', '438.29')); // replay 407.44 → 438.34
        expect(of(_saltimbocca), (
          'complete',
          '511.50',
        )); // replay 488.08 → 511.56
        expect(of(_meuniere), ('complete', '349.73')); // replay 326.25 → 349.73
        expect(of(_parmesanCrusted), (
          'partial',
          '171.63',
        )); // replay 153.54 → 171.67
        expect(of(_eggplant), ('partial', '453.68')); // replay 360.33 → 453.66
        // Unmoved (replay v67 = v68).
        expect(of(_onionRings), ('partial', '217.50')); // = replay
        expect(of(_salmon), ('partial', '542.67')); // = replay
        expect(of(_maple), ('partial', '462.34')); // = replay
        expect(of(_skillet), ('partial', '695.99')); // replay 696.06
        expect(of(_chickenMarsala), ('complete', '662.00')); // replay 662.07
        expect(of(_francese2), ('complete', '376.78')); // replay 376.82
        expect(of(_tacos), ('complete', '609.06')); // replay 609.07
      },
    );

    test('a second recompute writes nothing', () {
      for (final recipe in recipes.values) {
        List<(int, double?, String?, String?, String?)> rows() => [
          for (final r in db.ingredientMatchesFor(recipe.id))
            (r.position, r.grams, r.gramSource, r.hold, r.updatedAt),
        ];
        final before = rows();
        expect(recomputeTotals(db, recipe), isTrue, reason: recipe.slug);
        expect(rows(), before, reason: recipe.slug);
      }
    });

    test('the matches GET plans M52 once per request and every line shows '
        "the memo-free per-row plan's basis", () async {
      for (final MapEntry(key: file, value: recipe) in recipes.entries) {
        m52PlanRuns = 0;
        final items =
            (await matchesBody(db, provider, recipe))['items']!
                as List<Map<String, Object?>>;
        expect(m52PlanRuns, lessThanOrEqualTo(1), reason: file);
        for (final (position, line) in nutritionLines(recipe).indexed) {
          final match = items[position]['match'] as Map<String, Object?>?;
          expect(
            match?['gram_basis'],
            match == null
                ? null
                : gramBasisFor(
                    db,
                    line,
                    rowIn(recipe, position),
                    recipe: recipe,
                  ),
            reason: '$file|$position',
          );
        }
      }
    });

    // Last: it writes person decisions (on computed copies).
    test("Q7 (the owner's one-way door, accepted): a person's CONFIRM "
        "through the real PUT reads the plan's share — eggplant|6's eggs "
        '84.39 g `discarded` (v61 H: 0 g poured away), piccata|3 27.99; the '
        "onion rings' held dip still 0 g poured away — and a recompute keeps "
        'each', () async {
      Future<IngredientMatchRow> confirm(Recipe recipe, int position) async {
        await applyMatchOverride(db, provider, recipe, position, {
          'raw': nutritionLines(recipe)[position].raw,
          'confirmed': true,
        });
        final row = rowIn(recipe, position);
        expect(recomputeTotals(db, recipe), isTrue);
        expect(sameMatchRow(rowIn(recipe, position), row), isTrue);
        return row;
      }

      final eggplant = await variant(loadCorpusRecipe(_eggplant), 'confirm');
      final eggs = await confirm(eggplant, 6);
      expect(
        (eggs.status, eggs.grams, eggs.gramSource, eggs.hold),
        ('confirmed', 84.39, 'discarded', null),
      );
      expect(basisIn(eggplant, 6), _dipBasis);
      final piccata = await variant(loadCorpusRecipe(_piccata), 'confirm');
      final flour = await confirm(piccata, 3);
      expect(
        (flour.status, flour.grams, flour.gramSource, flour.hold),
        ('confirmed', 27.99, 'discarded', null),
      );
      expect(basisIn(piccata, 3), _c4Breast);
      // The onion rings stay H (no sourced figure): a Confirm of a held dip
      // there is still 0 g poured away (M62 H's door, the v61 pin's path).
      final rings = await variant(loadCorpusRecipe(_onionRings), 'confirm');
      final egg = await confirm(rings, 1);
      expect(
        (egg.status, egg.grams, egg.gramSource, egg.hold),
        ('confirmed', 0.0, 'discarded', null),
      );
      expect(basisIn(rings, 1), 'poured away — counted as 0 g');
    });
  });
}
