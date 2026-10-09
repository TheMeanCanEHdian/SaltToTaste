// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v64 (batch M65 — matcher landings with the record already cached;
// matcherVersion 63; prep49 design_v2 §2 M65 and the owner's Q14 under the
// standing authorization; zero requests; no step is read, so no reach here
// is pre-Q18): a volume line bought "from N (W-ounce) jars|cans" weighs its
// volume (grams `_fromContainers`) and the jarred Morellos land on SR 167769
// "Cherries, sour, canned, water pack, drained" (v38's R05, flagged); dried
// corn husks are a wrapper (`isNonFood`); gel food dye is a zero flavouring
// (`_zeroNutrientFlavourings`); the kombu line shows FNDDS 2709988
// "Seaweed, dried" (`_rankAs`, flagged; still strained out at 0 g); ricotta
// salata counts as SR 173420 "Cheese, feta", a flagged stand-in whose
// sodium and fat `trimStandInFlagOf` states. Every row value is the fresh
// compute of the WHOLE recipe (sections first) over recorded real FDC
// answers (FixtureProvider; 39 searches and 10 foods added --from-db from
// snapshot 25, JSON-equal, 0 existing entries changed — five of the
// searches are the answers the six lines read before M65, 'dried corn
// husks', 'square piece kombu', 'gel food dye', 'ricotta salata' and
// 'jarred morello cherries', recorded so a mutant reverting a landing fails
// on its old record, not on an unrecorded answer), equal to the v64
// replay of snapshot 25 (rp43, fix64 r1) on every pinned field and, on
// every row M65 must not move, to the v63 rows; never the network.
// Synthesized, STATED (no corpus line holds it): the count-first container
// line the guard test passes to `resolveGrams` on the real 167769 record,
// and the plain-feta line `trimStandInFlagOf` is asked about.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
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

const _cobbler = '0949-sour-cherry-cobbler.yaml';
const _tamales = '0475-tamales.yaml';
const _nikujaga = '1172-nikujaga-beef-and-potato-stew.yaml';
const _rainbow = '1201-rainbow-cake.yaml';
const _brussels =
    '0050-brussels-sprout-salad-with-warm-mustard-vinaigrette.yaml';
const _norma = '0335-pasta-alla-norma.yaml';
const _carbonnade =
    '0085-carbonnade-a-la-flamande-belgian-beef-beer-and-onion-stew.yaml';

const String _fetaFlag =
    'approximate (FDC holds no ricotta salata — a stand-in by class; '
    "feta's sodium (1,139 mg per 100 g) and fat (21.49 g per 100 g) counted)";

/// The six rows M65 moves (fix64 r1 vs the v63 rows): F5, F4, F7, F8 and
/// F2's two.
const List<_Row> _reach = [
  (
    _cobbler,
    null,
    7,
    '8 cups jarred Morello cherries from 4 (24-ounce) jars, drained, 2 cups juice reserved',
    167769,
    'Cherries, sour, canned, water pack, drained',
    '1.000000',
    '1344.00',
    'auto',
    null,
    '564.48',
    '8 cup · USDA portion · approximation (counted as Cherries, sour, canned, water pack, drained)',
  ),
  (
    _tamales,
    null,
    3,
    '20 large dried corn husks',
    null,
    'Equipment — not food, counts as zero',
    '1.000000',
    null,
    'confirmed',
    null,
    null,
    null,
  ),
  (
    _nikujaga,
    null,
    1,
    '1 (4-inch) square piece kombu',
    2709988,
    'Seaweed, dried',
    '0.990000',
    '0.00',
    'auto',
    null,
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted) · approximation (counted as Seaweed, dried)',
  ),
  (
    _rainbow,
    null,
    8,
    'Gel food dye (red, orange, yellow, green, blue, and purple)',
    null,
    'Flavouring — no nutrients, counts as zero',
    '1.000000',
    '0.00',
    'confirmed',
    null,
    null,
    'flavouring, no nutrients — counted as 0 g',
  ),
  (
    _brussels,
    null,
    10,
    '4 ounces ricotta salata, shaved into thin strips using vegetable peeler',
    173420,
    'Cheese, feta',
    '1.000000',
    '113.40',
    'auto',
    null,
    '300.50',
    'from 4 ounce · approximation (counted as Cheese, feta) · $_fetaFlag',
  ),
  (
    _norma,
    null,
    9,
    '3 ounces ricotta salata, shredded (1 cup)',
    173420,
    'Cheese, feta',
    '1.000000',
    '85.05',
    'auto',
    null,
    '225.38',
    'from 3 ounce · approximation (counted as Cheese, feta) · $_fetaFlag',
  ),
];

/// The rows M65 must not move, equal to the v63 rows (fix64 fx/family.txt):
/// every other cherry, husk, seaweed, dye/coloring and ricotta row of the
/// library (41) less three — 38 — plus two other volume-first lines a
/// container paren weighs (pasta-with-creamy-tomato-sauce|10 "(from one
/// 28-ounce can)", campanelle|0's 8½-ounce jar: outside the guard's words,
/// a gap left) and a feta line on 173420 (the stand-in suffix is keyed to a
/// ricotta salata line, never to feta's record alone). Left out, each
/// byte-equal in the replay: the sub-recipe row "1 recipe Port Wine–Cherry
/// Sauce" (its section is byte-identical), indoor-clambake|0's cherrystone
/// clams, the-best-gluten-free-pizza|2 "1½ tablespoons powdered psyllium
/// husk" (169656 below the gate; its 12.00 g reads a detail the sweep
/// cached and a fresh compute never fetches; its item stays food —
/// `isNonFood` below), and two "A or B" lines whose record follows what the
/// cache holds — quinoa-and-vegetable-stew|14 "queso fresco or feta" and
/// carbonnade|9's 12-ounce bottle of "dark beer or stout" (its grams are
/// pinned below).
const List<_Row> _negatives = [
  (
    '0178-baked-bread-stuffing-with-sausage-dried-cherries-and-pecans.yaml',
    null,
    13,
    '1 cup dried cherries',
    2709199,
    'Cherries, dried',
    '0.990000',
    '160.00',
    'auto',
    null,
    '532.80',
    '1 cup · USDA portion',
  ),
  (
    '0368-baked-manicotti.yaml',
    null,
    6,
    '3 cups part-skim ricotta cheese',
    171248,
    'Cheese, ricotta, part skim milk',
    '0.960000',
    '741.00',
    'auto',
    null,
    '1022.58',
    '3 cup · USDA portion',
  ),
  (
    '0676-boiled-corn.yaml',
    null,
    0,
    '6 ears corn, husks and silk removed',
    2709783,
    'Corn, raw',
    '0.910000',
    '630.00',
    'auto',
    null,
    '541.80',
    '6 ear · USDA portion',
  ),
  (
    '1171-bulalo-hearty-beef-shank-and-vegetable-soup.yaml',
    null,
    9,
    '2 ears corn, husks and silk removed, cut into 1-inch lengths',
    2709783,
    'Corn, raw',
    '0.910000',
    '210.00',
    'auto',
    null,
    '180.60',
    '2 ear · USDA portion',
  ),
  (
    '1207-caldo-de-siete-mares.yaml',
    null,
    13,
    '2 ears corn, husks and silk removed, cut into 1-inch rounds',
    2709783,
    'Corn, raw',
    '0.910000',
    '210.00',
    'auto',
    null,
    '180.60',
    '2 ear · USDA portion',
  ),
  (
    '0951-cherry-clafouti.yaml',
    null,
    0,
    '1½ pounds fresh sweet cherries, pitted and halved',
    171719,
    'Cherries, sweet, raw',
    '0.953333',
    '680.39',
    'auto',
    null,
    '428.64',
    'from 1 1/2 pound',
  ),
  (
    '0497-chile-verde-con-cerdo-green-chili-with-pork.yaml',
    null,
    3,
    '1½ pounds tomatillos, husks and stems removed, rinsed well and dried',
    168566,
    'Tomatillos, raw',
    '0.920000',
    '680.39',
    'auto',
    null,
    '217.72',
    'from 1 1/2 pound',
  ),
  (
    '0061-chilled-soba-noodles-with-cucumber-snow-peas-and-radishes.yaml',
    null,
    1,
    '1 (8-inch square) sheet nori (optional)',
    null,
    'No FoodData Central match',
    '0.000000',
    null,
    'unmatched',
    null,
    null,
    null,
  ),
  (
    '0538-chinese-style-barbecued-spareribs.yaml',
    null,
    7,
    '1 teaspoon red food coloring (optional)',
    null,
    'Flavouring — no nutrients, counts as zero',
    '1.000000',
    '0.00',
    'confirmed',
    null,
    null,
    'flavouring, no nutrients — counted as 0 g',
  ),
  (
    '1206-chocolate-cherry-pie-pops.yaml',
    null,
    0,
    '1 cup cherry preserves',
    169641,
    'Jams and preserves',
    '1.000000',
    '320.00',
    'auto',
    null,
    '889.60',
    '1 cup · USDA portion',
  ),
  (
    '0828-chocolate-chunk-oatmeal-cookies-with-pecans-and-dried-cherries.yaml',
    null,
    6,
    '1 cup dried sour cherries, chopped coarse',
    2709199,
    'Cherries, dried',
    '0.673333',
    '160.00',
    'auto',
    null,
    '532.80',
    '1 cup · USDA portion',
  ),
  (
    '0483-chorizo-and-potato-tacos.yaml',
    null,
    14,
    '8 ounces tomatillos, husks and stems removed, rinsed well and dried, and cut into 1-inch pieces',
    168566,
    'Tomatillos, raw',
    '0.920000',
    '226.80',
    'auto',
    null,
    '72.57',
    'from 8 ounce',
  ),
  (
    '0674-corn-fritters.yaml',
    null,
    0,
    '4 ears corn, husks and silk removed',
    2709783,
    'Corn, raw',
    '0.910000',
    '420.00',
    'auto',
    null,
    '361.20',
    '4 ear · USDA portion',
  ),
  (
    '0409-eggplant-involtini.yaml',
    null,
    8,
    '8 ounces (1 cup) whole-milk ricotta cheese',
    746766,
    'Cheese, ricotta, whole milk',
    '1.000000',
    '226.80',
    'auto',
    null,
    '356.07',
    'from 8 ounce',
  ),
  (
    '0488-enchiladas-verdes.yaml',
    null,
    6,
    '1½ pounds tomatillos (16 to 20 medium), husks and stems removed, rinsed well and dried',
    168566,
    'Tomatillos, raw',
    '0.920000',
    '680.39',
    'auto',
    null,
    '217.72',
    'from 1 1/2 pound',
  ),
  (
    '1189-erbazzone-swiss-chard-pie.yaml',
    null,
    10,
    '6 ounces (¾ cup) whole-milk ricotta cheese (optional)',
    746766,
    'Cheese, ricotta, whole milk',
    '1.000000',
    '170.10',
    'auto',
    null,
    '267.05',
    'from 6 ounce',
  ),
  (
    '0372-four-cheese-lasagna.yaml',
    null,
    2,
    '1½ cups part-skim ricotta cheese',
    171248,
    'Cheese, ricotta, part skim milk',
    '0.960000',
    '370.50',
    'auto',
    null,
    '511.29',
    '1 1/2 cup · USDA portion',
  ),
  (
    '1166-fruit-hand-pies.yaml',
    'Cherry Hand Pie Filling',
    0,
    '10 ounces frozen cherries, thawed, juice reserved, cut into approximate ½-inch pieces',
    2709233,
    'Cherries, frozen',
    '0.990000',
    '283.50',
    'auto',
    null,
    '201.28',
    'from 10 ounce',
  ),
  (
    '0328-fusilli-with-ricotta-and-spinach.yaml',
    null,
    0,
    '11 ounces (1⅓ cups) whole-milk ricotta cheese',
    746766,
    'Cheese, ricotta, whole milk',
    '1.000000',
    '311.84',
    'auto',
    null,
    '489.60',
    'from 11 ounce',
  ),
  (
    '0251-glazed-spiral-sliced-ham.yaml',
    'Cherry-Port Glaze',
    1,
    '½ cup cherry preserves',
    169641,
    'Jams and preserves',
    '1.000000',
    '160.00',
    'auto',
    null,
    '444.80',
    '1/2 cup · USDA portion',
  ),
  (
    '0657-grilled-corn-with-flavored-butter.yaml',
    null,
    2,
    '8 ears corn, husks and silk removed',
    2709783,
    'Corn, raw',
    '0.910000',
    '840.00',
    'auto',
    null,
    '722.40',
    '8 ear · USDA portion',
  ),
  (
    '0295-indoor-clambake.yaml',
    null,
    4,
    '6 medium ears corn, silk and all but the last layer of husk removed',
    2709783,
    'Corn, raw',
    '0.910000',
    '630.00',
    'auto',
    null,
    '541.80',
    '6 · USDA per-item weight',
  ),
  (
    '0374-lasagna-with-hearty-tomato-meat-sauce.yaml',
    null,
    9,
    '1¾ cups whole-milk or part-skim ricotta cheese',
    171248,
    'Cheese, ricotta, part skim milk',
    '0.791667',
    '432.25',
    'auto',
    null,
    '596.50',
    '1 3/4 cup · USDA portion',
  ),
  (
    '0746-lemon-ricotta-pancakes.yaml',
    null,
    3,
    '8 ounces (1 cup) whole-milk ricotta cheese',
    746766,
    'Cheese, ricotta, whole milk',
    '1.000000',
    '226.80',
    'auto',
    null,
    '356.07',
    'from 8 ounce',
  ),
  (
    '0034-lighter-corn-chowder.yaml',
    null,
    0,
    '8 ears corn, husks and silk removed',
    2709783,
    'Corn, raw',
    '0.910000',
    '840.00',
    'auto',
    null,
    '722.40',
    '8 ear · USDA portion',
  ),
  (
    '1198-meringue-christmas-trees.yaml',
    null,
    4,
    '8–10 drops green food coloring',
    null,
    'Flavouring — no nutrients, counts as zero',
    '1.000000',
    '0.00',
    'confirmed',
    null,
    null,
    'flavouring, no nutrients — counted as 0 g',
  ),
  (
    '0658-mexican-style-grilled-corn.yaml',
    null,
    11,
    '6 ears corn, husks and silk removed',
    2709783,
    'Corn, raw',
    '0.910000',
    '630.00',
    'auto',
    null,
    '541.80',
    '6 ear · USDA portion',
  ),
  (
    '0234-pan-seared-oven-roasted-pork-tenderloin.yaml',
    'Dried Cherry–Port Sauce with Onions and Marmalade',
    3,
    '¾ cup dried cherries',
    2709199,
    'Cherries, dried',
    '0.990000',
    '120.00',
    'auto',
    null,
    '399.60',
    '3/4 cup · USDA portion',
  ),
  (
    '1190-ricotta-calzones-with-sausage-and-broccoli-rabe.yaml',
    null,
    11,
    '16 ounces whole-milk ricotta (2 cups)',
    746766,
    'Cheese, ricotta, whole milk',
    '1.000000',
    '453.59',
    'auto',
    null,
    '712.14',
    'from 16 ounce',
  ),
  (
    '0489-roasted-poblano-and-black-bean-enchiladas.yaml',
    null,
    0,
    '1 pound tomatillos, husks and stems removed, rinsed well, dried, and halved',
    168566,
    'Tomatillos, raw',
    '0.920000',
    '453.59',
    'auto',
    null,
    '145.15',
    'from 1 pound',
  ),
  (
    '0067-skillet-lasagna.yaml',
    null,
    12,
    '1 cup ricotta cheese',
    2705750,
    'Cheese, Ricotta',
    '0.990000',
    '246.00',
    'auto',
    null,
    '364.08',
    '1 cup · USDA portion',
  ),
  (
    '0244-slow-roasted-bone-in-pork-rib-roast.yaml',
    'Port Wine–Cherry Sauce',
    1,
    '1 cup dried cherries',
    2709199,
    'Cherries, dried',
    '0.990000',
    '160.00',
    'auto',
    null,
    '532.80',
    '1 cup · USDA portion',
  ),
  (
    '0606-smoked-pork-loin-with-dried-fruit-chutney.yaml',
    null,
    7,
    '½ cup dried cherries',
    2709199,
    'Cherries, dried',
    '0.990000',
    '80.00',
    'auto',
    null,
    '266.40',
    '1/2 cup · USDA portion',
  ),
  (
    '1088-spinach-and-ricotta-gnudi-with-tomato-butter-sauce.yaml',
    null,
    0,
    '12 ounces (1½ cups) whole-milk ricotta cheese',
    746766,
    'Cheese, ricotta, whole milk',
    '1.000000',
    '340.19',
    'auto',
    null,
    '534.10',
    'from 12 ounce',
  ),
  (
    '1163-struffoli-neapolitan-honey-balls.yaml',
    null,
    12,
    '8 candied cherries (optional)',
    167563,
    'Candies, TWIZZLERS CHERRY BITES',
    '0.000000',
    null,
    'auto',
    null,
    null,
    null,
  ),
  (
    '0981-sweet-cherry-pie.yaml',
    null,
    3,
    '6 cups (about 2 pounds) pitted sweet cherries or 6 cups pitted frozen cherries, halved',
    171719,
    'Cherries, sweet, raw',
    '0.953333',
    '907.18',
    'auto',
    null,
    '571.53',
    'from 2 pound',
  ),
  (
    '0385-thin-crust-whole-wheat-pizza-with-garlic-oil-three-cheeses-and-basil.yaml',
    null,
    17,
    '6 ounces (¾ cup) whole-milk ricotta cheese',
    746766,
    'Cheese, ricotta, whole milk',
    '1.000000',
    '170.10',
    'auto',
    null,
    '267.05',
    'from 6 ounce',
  ),
  (
    '1073-wheat-berry-salad-with-radicchio-dried-cherries-and-pecans.yaml',
    null,
    9,
    '¼ cup dried cherries',
    2709199,
    'Cherries, dried',
    '0.990000',
    '40.00',
    'auto',
    null,
    '133.20',
    '1/4 cup · USDA portion',
  ),
  (
    '0326-pasta-with-creamy-tomato-sauce.yaml',
    null,
    10,
    '2 cups plus 2 tablespoons crushed tomatoes (from one 28-ounce can)',
    2685581,
    'Tomatoes, crushed, canned',
    '0.923333',
    '793.79',
    'auto',
    null,
    // 300.65 in the replay (2685581's cached detail); a fresh compute
    // counts on its search hit, whose energy FDC rounds — not pinned here.
    null,
    'from the printed weight',
  ),
  (
    '0337-campanelle-with-arugula-goat-cheese-and-sun-dried-tomato-pesto.yaml',
    null,
    0,
    '1 cup oil-packed sun-dried tomatoes (one 8½-ounce jar), drained, rinsed, patted dry, and chopped coarse',
    169384,
    'Tomatoes, sun-dried, packed in oil, drained',
    '0.942857',
    '240.97',
    'auto',
    null,
    '513.27',
    'from the printed weight',
  ),
  (
    '0718-barley-salad-with-pomegranate-pistachios-and-feta.yaml',
    null,
    9,
    '3 ounces feta cheese, cut into ½-inch cubes (¾ cup)',
    173420,
    'Cheese, feta',
    '1.000000',
    '85.05',
    'auto',
    null,
    '225.38',
    'from 3 ounce',
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
    expect(matcherVersion, 63);
  });

  test('the five entries, by item (the shipped classes)', () {
    // F4: a husk wrapper is equipment; the psyllium husk and the ears of
    // corn are food.
    expect(isNonFood('dried corn husks'), isTrue);
    expect(isNonFood('powdered psyllium husk'), isFalse);
    expect(isNonFood('ears corn'), isFalse);
    // F8: the dye is a zero flavouring, as the colorings are.
    expect(isZeroNutrientFlavouring('gel food dye'), isTrue);
    expect(isZeroNutrientFlavouring('red food coloring'), isTrue);
    // F5, F7, F2: each reads a cached answer under the record's words, and
    // each record is a flagged approximation.
    for (final (item, answer, words, fdcId) in const [
      (
        'jarred morello cherries',
        'dried sour cherries',
        'cherries sour canned water pack drained',
        167769,
      ),
      ('square piece kombu', 'dried mint', 'seaweed dried', 2709988),
      ('ricotta salata', 'feta cheese', 'cheese feta', 173420),
    ]) {
      expect(rankAsFor(item), (query: words, answer: answer), reason: item);
      expect(approximationRecords[item], fdcId, reason: item);
    }
  });

  test('the feta stand-in suffix is keyed on 173420 and a line naming '
      'ricotta salata (the plain-feta line STATED synthesized)', () {
    const salata =
        '4 ounces ricotta salata, shaved into thin strips using vegetable peeler';
    expect(trimStandInFlagOf(salata, 173420), _fetaFlag);
    expect(trimStandInFlagOf('4 ounces feta cheese, crumbled', 173420), isNull);
    expect(trimStandInFlagOf(salata, 746766), isNull);
    expect(trimStandInFlagOf(salata, null), isNull);
  });

  group('matcher v64 (batch M65)', skip: skipIfNoCorpus, () {
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

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v64-');
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
        (_carbonnade, null, 0, '', null, '', '', null, '', null, null, null),
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

    /// [file]'s stored recipe, or its [section]'s (by title).
    Recipe recipeIn(String file, String? section) => section == null
        ? recipes[file]!
        : nutritionRecipeOf(
            db,
            sectionKeyOf(recipes[file]!.id, section),
          )!.recipe;

    IngredientMatchRow rowIn(String file, int position, {String? section}) => db
        .ingredientMatchesFor(recipeIn(file, section).id)
        .singleWhere((m) => m.position == position);

    String? basisIn(String file, int position, {String? section}) =>
        gramBasisFor(
          db,
          nutritionLines(recipeIn(file, section))[position],
          rowIn(file, position, section: section),
          recipe: recipeIn(file, section),
        );

    /// Each [rows] entry in its whole recipe (or its section): the record,
    /// the description, the confidence, the grams, the status, the hold,
    /// the energy and the basis.
    void expectRows(List<_Row> rows) {
      for (final (
            file,
            section,
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
        final line = nutritionLines(recipeIn(file, section))[position];
        final row = rowIn(file, position, section: section);
        final reason = '$file|${section ?? ''}|$position';
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
        expect(
          basisIn(file, position, section: section),
          basis,
          reason: reason,
        );
      }
    }

    String g2(double v) => v.toStringAsFixed(2);

    test('M65 reaches exactly its 6 rows (design_v2 §2 M65)', () {
      expect(_reach, hasLength(6));
      expectRows(_reach);
    });

    test("F5: the Morellos weigh their 8 cups on 167769's 'cup' 168 g "
        '(1,344.00 g, 42 kcal per 100 g: 564.48), not one 24-ounce jar '
        '(680.39 g)', () {
      final cherries = knownFood(db, 167769)!;
      expect(
        [
          for (final p in cherries.portions)
            if (p.description == 'cup') p.gramWeight,
        ],
        [168.0],
      );
      final row = rowIn(_cobbler, 7);
      expect(g2(row.grams!), g2(8 * 168.0));
      expect(row.gramSource, 'portion');
      expect(cherries.nutrientsPer100g['208'], 42.0);
      expect(g2(8 * 168 * 42 / 100), '564.48');
      expect(g2(24 * 28.349523125), '680.39');
    });

    test('F5 needs the volume FIRST: a count-first line bought "from 1 '
        '(12-ounce) jar" still reads its container (STATED synthesized line '
        'on the real 167769 record)', () {
      const raw = '2 jarred roasted red peppers from 1 (12-ounce) jar';
      final parsed = parseIngredientLine(raw);
      expect(parsed.amounts.first.measure, Measure.count);
      final grams = resolveGrams(
        amounts: parsed.amounts,
        food: knownFood(db, 167769),
        normalizedItem: normalizeItem(parsed.item ?? raw),
        raw: raw,
      )!;
      expect(grams.basis, 'from the printed weight');
      expect(g2(grams.grams), '340.19');
    });

    test("F2: the feta flag's figures are 173420's own (265 kcal, Na 1,139 "
        'mg, fat 21.49 g per 100 g) and the two lines count their printed '
        'weights', () async {
      // The detail snapshot 25 caches (recorded --from-db); a fresh compute
      // here counts on the search hit, whose figures FDC rounds (1,140 mg,
      // 21.5 g) — the energy, 265, is the same.
      final feta = (await provider.food(173420))!;
      expect(feta.description, 'Cheese, feta');
      expect(feta.nutrientsPer100g['208'], 265.0);
      expect(feta.nutrientsPer100g['307'], 1139.0);
      expect(feta.nutrientsPer100g['204'], 21.49);
      // The engine prices the stored 4 oz (113.398 g): 300.50, not the
      // design's 300.51 on the rounded 113.40.
      expect(g2(4 * 28.349523125 * 2.65), '300.50');
      expect(g2(3 * 28.349523125 * 2.65), '225.38');
    });

    test('carbonnade|9 "1½ cups (12-ounce bottle or can) dark beer or '
        'stout" still weighs its bottle (340.19 g, from the printed weight): '
        'no "from N (W-ounce)" words', () {
      final row = rowIn(
        _carbonnade,
        9,
      );
      expect(g2(row.grams!), '340.19');
      expect(row.gramSource, 'weight');
      expect(
        basisIn(
          _carbonnade,
          9,
        ),
        startsWith('from the printed weight'),
      );
    });

    test('the rows M65 must not reach equal v63', () {
      expect(_negatives, hasLength(41));
      expectRows(_negatives);
    });

    test('the matches GET shows each reach basis', () async {
      for (final (file, _, position, _, _, _, _, _, _, _, _, basis) in _reach) {
        final items =
            (await matchesBody(db, provider, recipes[file]!))['items']!
                as List<Map<String, Object?>>;
        final match = items[position]['match'] as Map<String, Object?>?;
        expect(match?['gram_basis'], basis, reason: '$file|$position');
      }
    });

    test('four recipes complete; nikujaga stays partial, the rainbow cake '
        'complete', () {
      (String, String) of(String file) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        return (n.status, n.caloriesPerServing!.toStringAsFixed(2));
      }

      // A fresh compute here; the replay's v63 → v64 in the comment (the
      // absolute figures can differ by the energies the fixtures' search
      // hits round, as M63's note says).
      expect(of(_cobbler), ('complete', '297.32')); // partial 250.28 → 297.32
      expect(of(_brussels), ('complete', '290.37')); // partial 240.27 → 290.36
      expect(of(_norma), ('complete', '480.96')); // partial 443.35 → 480.91
      expect(of(_tamales), ('complete', '719.31')); // partial 719.39 → 719.39
      expect(of(_nikujaga).$1, 'partial'); // its unmatched katsuobushi
      expect(of(_rainbow).$1, 'complete');
    });

    test('a second recompute writes nothing', () {
      for (final file in const [
        _cobbler,
        _tamales,
        _nikujaga,
        _rainbow,
        _brussels,
        _norma,
      ]) {
        final recipe = recipes[file]!;
        List<(int, double?, String?)> rows() => [
          for (final r in db.ingredientMatchesFor(recipe.id))
            (r.position, r.grams, r.updatedAt),
        ];
        final before = rows();
        expect(recomputeTotals(db, recipe), isTrue, reason: file);
        expect(rows(), before, reason: file);
      }
    });
  });
}
