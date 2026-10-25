// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v80 (batch M80 — coats read in L50; matcherVersion 77; prep50
// design_v2 §2 M80 as the planner's report corrects it — plan_figures.md
// C10–C13 and the closer's CC1–CC4, CC7, CC10, CC11 — under the
// orchestrator's rulings Q11 (b) and the crumb-crust k 12.12; zero
// requests). M80-1 (pB R-D2): with no meat beside a held coat, a coated
// onion (`_coatVegetables` 'Onions,') baked after the coat sizes the coat
// at FNDDS 2710042 "Fried cauliflower"'s 50 g breading × 0.40 per 39.58 g
// raw cauliflower = 50.53, a flagged stand-in (oven-fried-onion-rings|0–|7,
// held `coating` before). M80-2 (pB R-F1): a C2 chicken whose budgeted
// coat parts include a `Bread,` record reads FNDDS 2706442 "Chicken or
// turkey parmigiana"'s separate breading inputs — 81 g dry crumbs and
// 31.25 g flour per 680.4 g raw chicken, 82.46 g carbohydrate = 12.12 (the
// Parmesan, input 8 after the mozzarella and the sauce, a topping) — and a
// `Nuts,` part beside the crumbs says it stands in on that crust
// (lighter-chicken-parmesan, chicken-kiev, stuffed-chicken-cutlets;
// nut-crusted flagged). R-G1 not built. REACH (the v80 replay of snapshot
// 28 vs the v79 rows): exactly these 25 rows. Every row value is the fresh
// compute of the WHOLE recipe over recorded real FDC answers
// (FixtureProvider; fixtures recorded from snapshot 28 only; this file adds
// none) and equals the replay on every pinned field. Never the network.
// Every corpus line is real. STATED constructions (no corpus line reaches
// these gates): stuffed-chicken-cutlets (0118) with its chicken line |8
// replaced by 0162's real "1 (5- to 7- pound) bone-in turkey breast" (the
// crumb arm's `chicken` gate: a C2 turkey with bread parts reads C2's
// 3.18); a person's typed grams on lighter|0's panko and on nut-crusted|2's
// almonds through the real PUT (CC11: the crust flags are read off the
// parts the budget shares, never the line list); oven-fried onion rings
// whose S3 fries the rings instead of baking them (a fried onion stays
// held: `_coatedVegetable` returns only at C2); and (closer 1, verify1 D3)
// oven-fried-chicken (0150) with its Melba toast line |8 replaced by 0116's
// real "2 cups plain dried bread crumbs" (the crumb arm sits after the legs
// arm: C2 legs with a bread part keep 3.10) and chicken-piccata (0418) with
// its flour line |3 replaced by that line and its S3's two "flour" written
// "bread crumbs" (the crumb arm is C2 only: a C4 chicken with a bread part
// keeps C4's 3.18 stand-in).

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _rings = '0315-oven-fried-onion-rings.yaml';
const _lighter = '0416-lighter-chicken-parmesan.yaml';
const _kiev = '0122-chicken-kiev.yaml';
const _stuffed = '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml';
const _nut = '0117-nut-crusted-chicken-breasts-with-lemon-and-thyme.yaml';

/// FNDDS 2706442's crust as the coat flag reads it (closer CC4's text).
const _crustRead =
    "USDA FNDDS 2706442 recipe: 112.25 g crust (81 g dry crumbs and 31.25 g flour as separate inputs; 82.46 g carbohydrate; the record's 18.75 g grated Parmesan follows its mozzarella and sauce — a topping, not read) per 680.4 g raw chicken";

/// The nut crust's stand-in clause (closer CC1).
const _nutStandIn =
    " (no record for a nut crust; read as FNDDS 2706442's crumb crust)";

/// The basis of a crumb-crust part; [nut]: nut-crusted's stand-in.
String _crumb({bool nut = false}) =>
    "discarded in cooking — only the coat on the food counted · approximation (coat: 12.12 g carbohydrate per 100 g of the raw chicken breast — $_crustRead${nut ? _nutStandIn : ''}; the dredge's excess not counted)";

/// The onion rings' coat flag (the stand-in by the first-word test).
const _ringFlag =
    "approximation (coat: 50.53 g carbohydrate per 100 g of the raw onions — USDA FNDDS 2710042 recipe: 50 g breading per 39.58 g raw cauliflower (no record for onions; read as Fried cauliflower); the dredge's excess not counted)";

/// The basis of a dip line ([dijon]: the M73 mustard stand-in first).
String _dip({bool dijon = false}) =>
    'discarded in cooking — only the dip on the food counted · ${dijon ? 'approximate (FDC holds no Dijon mustard — counted as prepared yellow mustard) · ' : ''}approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)';

/// The 25 rows M80 moves (file, position, raw, fdc id, grams, kcal, basis)
/// — the v79 replay's value in each comment.
final _reach = [
  // held `coating` (its eaten 30.16 g stored), 0 kcal.
  (
    _rings,
    0,
    '½ cup unbleached all-purpose flour',
    789890,
    '60.33',
    '220.81',
    'discarded in cooking — only the part the recipe keeps and the coat on the food counted · $_ringFlag',
  ),
  // held `coating`, no grams, 0 kcal (|1–|7).
  (
    _rings,
    1,
    '1 large egg, at room temperature',
    748967,
    '50.00',
    '74.00',
    _dip(),
  ),
  (
    _rings,
    2,
    '½ cup buttermilk, at room temperature',
    2705393,
    '122.00',
    '52.46',
    _dip(),
  ),
  (_rings, 3, '½ teaspoon table salt', 173468, '3.01', '0.00', _dip()),
  // CC10: round2(0.58 g × 2.51) = 1.46.
  (_rings, 4, '¼ teaspoon ground black pepper', 170931, '0.58', '1.46', _dip()),
  (_rings, 5, '¼ teaspoon cayenne pepper', 170932, '0.45', '1.43', _dip()),
  (
    _rings,
    6,
    '30 saltine crackers',
    2708167,
    '90.00',
    '376.20',
    'discarded in cooking — only the coat on the food counted · $_ringFlag',
  ),
  (
    _rings,
    7,
    '4 cups kettle-cooked potato chips',
    2709422,
    '100.00',
    '532.00',
    'discarded in cooking — only the coat on the food counted · $_ringFlag',
  ),
  // 15.78 g, 62.33 kcal.
  (
    _lighter,
    0,
    '1½ cups panko (Japanese-style bread crumbs)',
    174928,
    '60.16',
    '237.63',
    _crumb(),
  ),
  // 5.04 g, 21.22 kcal.
  (
    _lighter,
    2,
    '1 ounce Parmesan cheese, grated (about ½ cup), plus extra for serving',
    325036,
    '19.22',
    '80.92',
    _crumb(),
  ),
  // 10.73 g, 39.27 kcal.
  (
    _lighter,
    3,
    '½ cup unbleached all-purpose flour',
    789890,
    '40.91',
    '149.73',
    _crumb(),
  ),
  // 23.79 g, 13.08 kcal.
  (_lighter, 6, '3 large egg whites', 747997, '90.69', '49.88', _dip()),
  // 20.38 g, 54.21 kcal.
  (
    _kiev,
    7,
    '4 slices high-quality white sandwich bread, torn into quarters',
    174924,
    '77.68',
    '206.63',
    _crumb(),
  ),
  // 21.96 g, 80.37 kcal.
  (
    _kiev,
    11,
    '1 cup unbleached all-purpose flour',
    789890,
    '83.69',
    '306.31',
    _crumb(),
  ),
  // 30.67 g, 45.39 kcal.
  (_kiev, 12, '3 large eggs, beaten', 748967, '116.88', '172.98', _dip()),
  // 1.06 g, 0.65 kcal.
  (
    _kiev,
    13,
    '1 teaspoon Dijon mustard',
    326698,
    '4.03',
    '2.46',
    _dip(dijon: true),
  ),
  // 14.32 g, 52.41 kcal.
  (
    _stuffed,
    10,
    '¾ cup unbleached all-purpose flour',
    789890,
    '54.59',
    '199.80',
    _crumb(),
  ),
  // 23.26 g, 34.42 kcal.
  (_stuffed, 11, '2 large eggs', 748967, '88.67', '131.23', _dip()),
  // 17.73 g, 47.16 kcal.
  (
    _stuffed,
    13,
    '4 slices high-quality white sandwich bread, pulsed in a food processor to coarse crumbs and dried',
    174924,
    '67.57',
    '179.74',
    _crumb(),
  ),
  // 21.66 g, 125.41 kcal.
  (
    _nut,
    2,
    '1 cup almonds, chopped coarse',
    170567,
    '82.55',
    '477.96',
    _crumb(nut: true),
  ),
  // 8.96 g, 35.39 kcal.
  (
    _nut,
    5,
    '1 cup panko bread crumbs',
    174928,
    '34.14',
    '134.85',
    _crumb(nut: true),
  ),
  // 18.28 g, 66.90 kcal.
  (
    _nut,
    9,
    '1 cup unbleached all-purpose flour',
    789890,
    '69.65',
    '254.92',
    _crumb(nut: true),
  ),
  // 27.60 g, 40.85 kcal.
  (_nut, 10, '3 large eggs', 748967, '105.19', '155.68', _dip()),
  // 1.90 g, 1.16 kcal.
  (
    _nut,
    11,
    '2 teaspoons Dijon mustard',
    326698,
    '7.26',
    '4.43',
    _dip(dijon: true),
  ),
  // 0.11 g, 0.28 kcal.
  (_nut, 12, '¼ teaspoon ground black pepper', 170931, '0.41', '1.03', _dip()),
];

/// Rows M80 must not move (file, position, raw, grams, gram source, hold)
/// — each equal to the v79 replay.
const _negatives = [
  // Their own coat arms: the eggplant's batter read; the cauliflower is
  // fried (no coated vegetable) or counted.
  (
    '0407-eggplant-parmesan.yaml',
    2,
    '8 slices high-quality white sandwich bread, torn into quarters',
    '76.37',
    'discarded',
    null,
  ),
  (
    '0407-eggplant-parmesan.yaml',
    3,
    '2 ounces Parmesan cheese, grated (about 1 cup)',
    '19.33',
    'discarded',
    null,
  ),
  (
    '0672-buffalo-cauliflower-bites.yaml',
    4,
    '1–2 quarts peanut or vegetable oil',
    '73.30',
    'discarded',
    null,
  ),
  (
    '0672-buffalo-cauliflower-bites.yaml',
    5,
    '¾ cup cornstarch',
    '95.82',
    'density',
    null,
  ),
  (
    '0672-buffalo-cauliflower-bites.yaml',
    6,
    '¼ cup cornmeal',
    '39.04',
    'density',
    null,
  ),
  (
    '0672-buffalo-cauliflower-bites.yaml',
    10,
    '1 pound cauliflower florets, cut into 1½-inch pieces',
    '453.59',
    'weight',
    null,
  ),
  (
    '1093-vegan-baja-style-cauliflower-tacos.yaml',
    7,
    '1 cup panko bread crumbs',
    '59.15',
    'density',
    null,
  ),
  (
    '1093-vegan-baja-style-cauliflower-tacos.yaml',
    12,
    '½ head cauliflower (1 pound), trimmed and cut into 1-inch pieces',
    '417.30',
    'weight',
    null,
  ),
  // An Onions row beside a coated MEAT: the meat stays the coated food
  // (skillet-chicken-and-rice's thick dusting stays held — no shape).
  (
    '0077-skillet-chicken-and-rice-with-peas-and-scallions.yaml',
    2,
    '½ cup unbleached all-purpose flour',
    null,
    null,
    'coating',
  ),
  (
    '0077-skillet-chicken-and-rice-with-peas-and-scallions.yaml',
    5,
    '1 medium onion, minced',
    '110.00',
    'piece',
    null,
  ),
  (
    '0077-skillet-chicken-and-rice-with-peas-and-scallions.yaml',
    12,
    '5 scallions, sliced thin',
    '75.00',
    'piece',
    null,
  ),
  (_stuffed, 1, '1 small onion, minced', '70.00', 'piece', null),
  (
    '0288-maryland-crab-cakes.yaml',
    1,
    '4 scallions, green parts only, minced (about ½ cup)',
    '50.00',
    'portion',
    null,
  ),
  (
    '0304-chicken-fried-steaks.yaml',
    9,
    '1 medium onion, minced',
    '110.00',
    'piece',
    null,
  ),
  // C2 chicken with no crumb part: the default 3.18.
  (
    '0149-easier-fried-chicken.yaml',
    8,
    '2 cups unbleached all-purpose flour',
    '45.60',
    'discarded',
    null,
  ),
  // C4 (the shape, never C2): the stand-in 3.18.
  (
    '0415-better-chicken-marsala.yaml',
    6,
    '¾ cup all-purpose flour',
    '32.66',
    'discarded',
    null,
  ),
  (
    '0418-chicken-piccata.yaml',
    3,
    '½ cup unbleached all-purpose flour',
    '27.99',
    'discarded',
    null,
  ),
  (
    '0418-next-level-chicken-piccata.yaml',
    3,
    '¾ cup all-purpose flour',
    '32.66',
    'discarded',
    null,
  ),
  (
    '0419-parmesan-crusted-chicken-cutlets.yaml',
    2,
    '5 tablespoons unbleached all-purpose flour',
    '17.49',
    'discarded',
    null,
  ),
  (
    '0420-chicken-francese.yaml',
    9,
    '1 cup unbleached all-purpose flour',
    '25.66',
    'discarded',
    null,
  ),
  (
    '0421-chicken-saltimbocca.yaml',
    1,
    '½ cup unbleached all-purpose flour',
    '25.66',
    'discarded',
    null,
  ),
  (
    '0466-fish-meuniere-with-browned-butter-and-lemon.yaml',
    0,
    '½ cup unbleached all-purpose flour',
    '25.66',
    'discarded',
    null,
  ),
  // Their arms come first: pork 6.61, fish 7.41, legs 3.10.
  (
    '0206-crunchy-baked-pork-chops.yaml',
    2,
    '4 slices high-quality white sandwich bread, torn into 1-inch pieces',
    '74.70',
    'discarded',
    null,
  ),
  (
    '0254-crunchy-oven-fried-fish.yaml',
    0,
    '4 slices high-quality white sandwich bread, torn into quarters',
    '59.82',
    'discarded',
    null,
  ),
  (
    '0150-oven-fried-chicken.yaml',
    8,
    '1 box (about 5 ounces) plain Melba toast, crushed',
    '42.90',
    'discarded',
    null,
  ),
  // C1 crusts (fried; the arm is C2 only): 5.73.
  (
    '0042-almond-crusted-chicken-with-wilted-spinach-salad.yaml',
    2,
    '1 cup sliced almonds',
    '79.97',
    'discarded',
    null,
  ),
  (
    '0042-almond-crusted-chicken-with-wilted-spinach-salad.yaml',
    3,
    '½ cup panko (Japanese-style bread crumbs)',
    '25.71',
    'discarded',
    null,
  ),
  (
    '0114-breaded-chicken-cutlets.yaml',
    2,
    '3 slices high-quality white sandwich bread, torn into quarters',
    '26.93',
    'discarded',
    null,
  ),
  (
    '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
    0,
    '2 cups panko bread crumbs',
    '63.19',
    'discarded',
    null,
  ),
  (
    '0116-chicken-schnitzel.yaml',
    3,
    '2 cups plain dried bread crumbs',
    '48.61',
    'discarded',
    null,
  ),
  (
    '0233-pork-schnitzel-breaded-pork-cutlets.yaml',
    0,
    '7 slices high-quality white sandwich bread, crusts removed, cut into ¾-inch cubes (about 4 cups)',
    '39.27',
    'discarded',
    null,
  ),
  // A meatless recipe with a counted onion and a frying oil (CC7's `_m52Key`
  // widening reads its onion; no coat sentence names it).
  (
    '0570-falafel.yaml',
    3,
    '½ onion, chopped fine (½ cup)',
    '55.00',
    'piece',
    null,
  ),
  (
    '0570-falafel.yaml',
    11,
    '2 quarts vegetable oil for frying',
    '85.55',
    'discarded',
    null,
  ),
];

/// (file, status, per serving) after the compute — the replay's in each
/// comment (v79 → v80).
const _totals = [
  // 217.50 → 532.09 (partial 2/10 → complete).
  (_rings, 'complete', '532.09'),
  // 235.26 → 298.97 (the fresh compute's 298.93: its search-hit energies
  // differ from the library's in other rows, the rows above are equal).
  (_lighter, 'complete', '298.93'),
  // 540.19 → 667.12.
  (_kiev, 'complete', '667.05'),
  // 544.51 → 638.71.
  (_stuffed, 'complete', '638.65'),
  // 385.84 → 575.56.
  (_nut, 'complete', '575.50'),
];

/// STATED synthesized (M80-1): 0315 whose S3 FRIES the rings — its "Bake,
/// flipping the onion rings over and switching and rotating the baking
/// sheets halfway through baking," written "Fry, flipping the onion rings
/// over halfway through," — under its own id (`…-fried`). A fried coated
/// onion reads no coat figure (`_coatedVegetable` returns a vegetable only
/// at C2), so the coat holds with no budget and M62 H holds its dips: since
/// M80 the corpus holds no dip of a budget-less coat (the onion rings were
/// H's last corpus vehicle), so the owner's Q9 door is pinned on this copy
/// (here, nutrition_v61_test and nutrition_v68_test).
Recipe friedOnionRings() {
  final corpus = loadCorpusRecipe(_rings);
  const baked =
      'Bake, flipping the onion rings over and switching and rotating the '
      'baking sheets halfway through baking,';
  final s3 = corpus.steps[2].text;
  if (!s3.contains(baked)) {
    throw StateError('0315 S3 no longer prints "$baked"');
  }
  return corpus.copyWith(
    id: '${corpus.id}-fried',
    slug: '${corpus.slug}-fried',
    steps: [
      for (final (i, s) in corpus.steps.indexed)
        i == 2
            ? s.copyWith(
                text: s3.replaceFirst(
                  baked,
                  'Fry, flipping the onion rings over halfway through,',
                ),
              )
            : s,
    ],
  );
}

void main() {
  test('the matcher version carries the batch (update the literal with a '
      'bump)', () {
    expect(matcherVersion, 77);
  });

  test("the figures: 2706442's crust k from the records the coat reads (SR "
      '174928 dry crumbs 71.98 %, Foundation 789890 flour 77.3 % '
      'carbohydrate — the FNDDS inputs 18079 and 20081) per 680.4 g raw '
      "chicken = 12.12; the onion stand-in = 2710042's 50 g breading × 0.40 "
      'per 39.58 g raw cauliflower = 50.53 (STATED arithmetic: the mutants '
      'read the Parmesan in as crust 12.46, the egg in 12.26, the crust as '
      'MASS 19.25)', () async {
    final provider = FixtureProvider();
    final crumbs = (await provider.food(174928))!.nutrientsPer100g['205']!;
    final flour = (await provider.food(789890))!.nutrientsPer100g['205']!;
    final parmesan = (await provider.food(325036))!.nutrientsPer100g['205']!;
    final egg = (await provider.food(748967))!.nutrientsPer100g['205']!;
    expect((crumbs, flour), (71.98, 77.3));
    final cho = 81 * crumbs / 100 + 31.25 * flour / 100;
    expect(cho.toStringAsFixed(2), '82.46');
    expect((cho / (510.3 + 170.1) * 100).toStringAsFixed(2), '12.12');
    expect(
      ((cho + 18.75 * parmesan / 100) / 680.4 * 100).toStringAsFixed(2),
      '12.46',
    );
    expect(
      ((cho + 100 * egg / 100) / 680.4 * 100).toStringAsFixed(2),
      '12.26',
    );
    expect(
      ((81 + 31.25 + 18.75) / 680.4 * 100).toStringAsFixed(2),
      '19.25',
    );
    // The wash: 100 g egg per 82.46 g of the dredge's carbohydrate.
    expect((100 / cho).toStringAsFixed(4), '1.2127');
    expect((50 * 0.40 / 39.58 * 100).toStringAsFixed(2), '50.53');
  });

  group('matcher v80 (batch M80)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;
    final recipes = <String, Recipe>{};

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

    /// A computed copy of [corpus] under a new id (STATED synthesized).
    Future<Recipe> variant(Recipe corpus, String id) => compute(
      corpus.copyWith(id: '${corpus.id}-$id', slug: '${corpus.slug}-$id'),
    );

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v80-');
      db = SaltDatabase.open(
        ServerConfig(
          dataDir: tempDir.path,
          logLevel: Level.WARNING,
          trustProxy: false,
        ).dbPath,
      )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: {...pendingSearches});
      for (final file in {
        for (final r in _reach) r.$1,
        for (final r in _negatives) r.$1,
      }) {
        recipes[file] = await compute(loadCorpusRecipe(file));
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    IngredientMatchRow rowIn(String id, int position) =>
        db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

    IngredientMatchRow rowOf(String file, int position) =>
        rowIn(recipes[file]!.id, position);

    String kcalOf(IngredientMatchRow row) {
      final food = knownFood(db, nutrientSiblings[row.fdcId] ?? row.fdcId!)!;
      return (kcalPer100g(food) * (row.grams ?? 0) / 100).toStringAsFixed(2);
    }

    String? basisOf(Recipe recipe, int position) => gramBasisFor(
      db,
      nutritionLines(recipe)[position],
      rowIn(recipe.id, position),
      recipe: recipe,
    );

    test('the 25 rows: record, grams, energy, status, hold and basis (the '
        'stand-ins flagged — the onion by its read food, nut-crusted by '
        'its nut crust)', () {
      expect(_reach, hasLength(25));
      for (final (file, position, raw, fdcId, grams, kcal, basis) in _reach) {
        final recipe = recipes[file]!;
        final row = rowOf(file, position);
        final reason = '$file|$position';
        expect(nutritionLines(recipe)[position].raw, raw, reason: reason);
        expect(
          (row.fdcId, row.status, row.hold, row.gramSource),
          (fdcId, 'auto', null, 'discarded'),
          reason: reason,
        );
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(kcalOf(row), kcal, reason: reason);
        expect(basisOf(recipe, position), basis, reason: reason);
      }
    });

    test('the totals: the onion rings turn complete (10 of 10); the four '
        'crumb crusts stay complete; per serving', () {
      for (final (file, status, perServing) in _totals) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        expect(
          (n.status, n.caloriesPerServing?.toStringAsFixed(2)),
          (status, perServing),
          reason: file,
        );
      }
      final rings = db.nutritionFor(recipes[_rings]!.id)!;
      expect((rings.matchedCount, rings.totalCount), (10, 10));
    });

    test("the onion rings' split is the engine's (the margins disclosed): "
        'B = 50.53 × 300 g / 100 = 151.59 g; the dredge parts |0 (its '
        "flour's ¼ cup to the dish, the eaten ¼ cup S1 whisks into the "
        'dip on top — never a dip line), |6, |7 carry 143.72 g < B → f = 1 '
        '(margin 5.5 %); the dips |1–|5 weigh 176.04 g whole < W = 1.173 × '
        'B = 177.82 g → share 1 (margin 1.0 %): every line whole', () async {
      final r = recipes[_rings]!;
      final onion = rowOf(_rings, 8);
      expect((onion.fdcId, onion.grams), (790646, 300.0));
      final b = 50.53 * onion.grams! / 100;
      expect(b.toStringAsFixed(2), '151.59');
      double cho(int id) => knownFood(db, id)!.nutrientsPer100g['205']! / 100;
      final eaten = rowOf(_rings, 0).grams! - 30.17;
      expect(eaten.toStringAsFixed(2), '30.16');
      final dredge =
          30.17 * cho(789890) +
          rowOf(_rings, 6).grams! * cho(2708167) +
          rowOf(_rings, 7).grams! * cho(2709422);
      expect(dredge.toStringAsFixed(2), '143.72');
      expect(dredge < b, isTrue);
      final dips = [for (var i = 1; i <= 5; i++) rowOf(_rings, i).grams!];
      final whole = dips.fold<double>(0, (n, g) => n + g);
      expect(whole.toStringAsFixed(2), '176.04');
      final wet = (15 + 120) / (287 * 0.401) * b;
      expect(wet.toStringAsFixed(2), '177.82');
      expect(whole < wet, isTrue);
      // Every line at its whole weight: the dips' and the parts' own grams.
      for (var i = 0; i <= 7; i++) {
        final line = nutritionLines(r)[i];
        final row = rowOf(_rings, i);
        expect(
          lineGrams(
            db,
            line,
            knownFood(db, row.fdcId!),
            recipe: r,
          )!.grams.toStringAsFixed(2),
          row.grams!.toStringAsFixed(2),
          reason: '|$i',
        );
      }
      // The onion and the oil keep their rows.
      expect(rowOf(_rings, 9).grams, 84.0);
      expect(basisOf(r, 8), isNot(contains('coat')));
    });

    test(
      'the negatives keep their v79 rows: the eggplant and cauliflower '
      'coats, an onion beside a coated meat, the C2 chicken with no crumb '
      'part, the C4 dustings, the pork / fish / legs arms, the C1 crusts',
      () {
        for (final (file, position, raw, grams, source, hold) in _negatives) {
          final recipe = recipes[file]!;
          final row = rowOf(file, position);
          final reason = '$file|$position';
          expect(nutritionLines(recipe)[position].raw, raw, reason: reason);
          expect(
            (row.grams?.toStringAsFixed(2), row.gramSource, row.hold),
            (grams, source, hold),
            reason: reason,
          );
          final basis = basisOf(recipe, position) ?? '';
          expect(basis, isNot(contains('2706442')), reason: reason);
          expect(basis, isNot(contains('raw onions')), reason: reason);
        }
      },
    );

    test(
      'the GET shows the row basis (the plan read once per request)',
      () async {
        for (final (file, position, basis) in [
          (
            _rings,
            6,
            'discarded in cooking — only the coat on the food counted · $_ringFlag',
          ),
          (_kiev, 7, _crumb()),
          (_nut, 2, _crumb(nut: true)),
        ]) {
          m52PlanRuns = 0;
          final items =
              ((await matchesBody(db, provider, recipes[file]!))['items']!
                      as List)
                  .cast<Map<String, Object?>>();
          expect(m52PlanRuns, 1, reason: file);
          final item = items.singleWhere((i) => i['position'] == position);
          expect(
            (item['match']! as Map<String, Object?>)['gram_basis'],
            basis,
            reason: '$file|$position',
          );
        }
      },
    );

    test("CC7 — the M52 key's coated food: with no meat, `_m52Key` reads the "
        "coated vegetable whatever the coats — 0315's onion |8; falafel "
        '(0570: a counted onion, a frying oil, no sentence coating the onion) '
        'keys none', () {
      String head(String file) => m52KeyOf(
        recipes[file]!,
        db.ingredientMatchesFor(recipes[file]!.id),
      ).split('\n').first;
      expect(head(_rings), '8 300.0 Onions, yellow, raw');
      expect(head('0570-falafel.yaml'), 'null null null');
    });

    // closer 1 (verify1 D1): CC7's census measured — over the library's
    // 1,342 keys (a fresh recipe instance per path: the step index lives on
    // the instance), `memo:coatNamed` is newly read by 4 GETs (the onion
    // rings, falafel, pakoras, crispy tempeh), 1 compute and 1 recompute
    // (the onion rings), each once; the 122 "meatless groups with a counted
    // onion" were candidates — `_m52Key` runs only through `_m52Stored` and
    // the confirm path. Pinned here on the two such keys this file holds.
    test("CC7's census: the naming memo once on the onion rings' GET, "
        "recompute and compute; once on falafel's GET, never on its "
        'recompute or compute', () async {
      Future<int> reads(
        String file,
        Future<Object?> Function(Recipe) run,
      ) async {
        final fresh = db.recipeByIdOrSlug(recipes[file]!.id)!.recipe;
        stepIndexCounts.clear();
        await run(fresh);
        return stepIndexCounts['memo:coatNamed'] ?? 0;
      }

      for (final (file, counts) in [
        (_rings, (1, 1, 1)),
        ('0570-falafel.yaml', (1, 0, 0)),
      ]) {
        expect(
          (
            await reads(file, (r) => matchesBody(db, provider, r)),
            await reads(file, (r) async => recomputeTotals(db, r)),
            await reads(file, (r) => matchAndCompute(db, provider, r)),
          ),
          counts,
          reason: file,
        );
      }
    });

    /// [corpus] with its line [position] replaced by the real corpus line
    /// [raw] of [from] (STATED synthesized).
    Recipe withLine(Recipe corpus, int position, String from, String raw) {
      final line = nutritionLines(
        loadCorpusRecipe(from),
      ).firstWhere((l) => l.raw == raw);
      var i = -1;
      return corpus.copyWith(
        ingredients: [
          for (final g in corpus.ingredients)
            g.copyWith(
              items: [
                for (final l in g.items)
                  if (++i == position) line else l,
              ],
            ),
        ],
      );
    }

    test("the crumb arm's `chicken` gate — STATED synthesized: 0118 whose "
        'chicken line |8 is 0162\'s real "1 (5- to 7- pound) bone-in turkey '
        'breast" (C2, bread and flour parts, a turkey coated) reads C2\'s '
        '3.18, not the parmigiana crust', () async {
      const turkey = '1 (5- to 7- pound) bone-in turkey breast';
      final corpus = loadCorpusRecipe(_stuffed);
      expect(
        nutritionLines(corpus)[8].raw,
        startsWith('4 (5- to 6-ounce) boneless, skinless chicken breasts'),
      );
      final copy = await variant(
        withLine(
          corpus,
          8,
          '0162-roast-whole-turkey-breast-with-gravy.yaml',
          turkey,
        ),
        'turkey',
      );
      expect(nutritionLines(copy)[8].raw, turkey);
      expect(rowIn(copy.id, 8).description, startsWith('Turkey,'));
      for (final position in [10, 13]) {
        final row = rowIn(copy.id, position);
        expect(row.gramSource, 'discarded', reason: '|$position');
        final basis = basisOf(copy, position)!;
        expect(
          basis,
          contains(
            'coat: 3.18 g carbohydrate per 100 g of the raw turkey — USDA '
            'FNDDS 2705980',
          ),
          reason: '|$position',
        );
        expect(basis, isNot(contains('2706442')), reason: '|$position');
      }
    });

    // closer 1 (verify1 D3 (a)): the crumb arm's place AFTER the legs arm.
    test('the crumb arm sits after the legs arm — STATED synthesized: 0150 '
        'whose Melba toast line |8 is 0116\'s real "2 cups plain dried bread '
        'crumbs" (C2, chicken legs coated, a `Bread,` part) reads the legs\' '
        '3.10, not the parmigiana crust', () async {
      const crumbs = '2 cups plain dried bread crumbs';
      final corpus = loadCorpusRecipe('0150-oven-fried-chicken.yaml');
      expect(
        nutritionLines(corpus)[8].raw,
        '1 box (about 5 ounces) plain Melba toast, crushed',
      );
      final copy = await variant(
        withLine(corpus, 8, '0116-chicken-schnitzel.yaml', crumbs),
        'crumbs',
      );
      expect(nutritionLines(copy)[8].raw, crumbs);
      final row = rowIn(copy.id, 8);
      // The crumbs are a budgeted part — the arm's `crumbCrust` reached.
      expect(
        (row.fdcId, row.description, row.gramSource, row.hold),
        (174928, 'Bread, crumbs, dry, grated, plain', 'discarded', null),
      );
      expect(rowIn(copy.id, 6).description, contains(', leg,'));
      final basis = basisOf(copy, 8)!;
      expect(
        basis,
        contains(
          'coat: 3.10 g carbohydrate per 100 g of the raw chicken legs — USDA '
          'FNDDS 2705998',
        ),
      );
      expect(basis, isNot(contains('2706442')));
    });

    // closer 1 (verify1 D3 (b)): the crumb arm's C2 shape (a C5 chicken
    // cannot exist — `_shapeOf` reads C5 only on a `Fish,` or shrimp record —
    // so C4 is the one other shape a chicken with a crumb part reaches).
    test('the crumb arm is C2 only — STATED synthesized: 0418 whose flour '
        'line |3 is 0116\'s real "2 cups plain dried bread crumbs" and whose S3 '
        'sets out and coats with "bread crumbs" for "flour" (C4, a thin '
        "chicken breast sautéed, a `Bread,` part) reads C4's 3.18 stand-in, "
        'not the parmigiana crust', () async {
      const crumbs = '2 cups plain dried bread crumbs';
      final corpus = loadCorpusRecipe('0418-chicken-piccata.yaml');
      expect(
        nutritionLines(corpus)[3].raw,
        '½ cup unbleached all-purpose flour',
      );
      final s3 = corpus.steps[2].text;
      expect('flour'.allMatches(s3), hasLength(2));
      final lined = withLine(corpus, 3, '0116-chicken-schnitzel.yaml', crumbs);
      final copy = await variant(
        lined.copyWith(
          steps: [
            for (final (i, s) in lined.steps.indexed)
              i == 2
                  ? s.copyWith(text: s3.replaceAll('flour', 'bread crumbs'))
                  : s,
          ],
        ),
        'crumbs',
      );
      expect(nutritionLines(copy)[3].raw, crumbs);
      final row = rowIn(copy.id, 3);
      expect(
        (row.fdcId, row.description, row.gramSource, row.hold),
        (174928, 'Bread, crumbs, dry, grated, plain', 'discarded', null),
      );
      final basis = basisOf(copy, 3)!;
      expect(
        basis,
        contains(
          'coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — '
          'USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken '
          'breast (no record for a sautéed flour dusting;',
        ),
      );
      expect(basis, isNot(contains('2706442')));
    });

    test('CC11 — the crust flags are read off the parts the budget shares, '
        "never the line list: a person's typed grams on lighter|0's panko "
        '(the real PUT) leave no crumb part — the flour and Parmesan read '
        "C2's 3.18; typed on nut-crusted|2's almonds, the crumbs stay (12.12) "
        'and no nut stands in', () async {
      final lighter = await variant(loadCorpusRecipe(_lighter), 'typed');
      await applyMatchOverride(db, provider, lighter, 0, {
        'raw': nutritionLines(lighter)[0].raw,
        'grams': 60,
      });
      expect(
        (rowIn(lighter.id, 0).grams, rowIn(lighter.id, 0).gramSource),
        (60.0, 'override'),
      );
      for (final position in [2, 3]) {
        final basis = basisOf(lighter, position)!;
        expect(
          basis,
          contains(
            'coat: 3.18 g carbohydrate per 100 g of the raw chicken '
            'breast — USDA FNDDS 2705980',
          ),
          reason: '|$position',
        );
      }
      final nut = await variant(loadCorpusRecipe(_nut), 'typed');
      await applyMatchOverride(db, provider, nut, 2, {
        'raw': nutritionLines(nut)[2].raw,
        'grams': 80,
      });
      for (final position in [5, 9]) {
        expect(basisOf(nut, position), _crumb(), reason: '|$position');
      }
    });

    test('the onion arm is C2 only — STATED synthesized: the fried copy '
        '([friedOnionRings]) keeps its coat and dips held `coating` (M62 H) '
        'with no grams, as v79 held the corpus rings', () async {
      final fried = await compute(friedOnionRings());
      for (var position = 0; position <= 7; position++) {
        final row = rowIn(fried.id, position);
        expect(row.hold, 'coating', reason: '|$position');
        expect(
          row.grams?.toStringAsFixed(2),
          position == 0 ? '30.16' : null,
          reason: '|$position',
        );
      }
      expect(db.nutritionFor(fried.id)!.status, 'partial');
    });

    test('a second recompute writes nothing — rows and totals', () {
      for (final recipe in recipes.values) {
        List<(int, double?, String?, String?, String?)> rows() => [
          for (final r in db.ingredientMatchesFor(recipe.id))
            (r.position, r.grams, r.gramSource, r.hold, r.updatedAt),
        ];
        expect(recomputeTotals(db, recipe), isTrue, reason: recipe.slug);
        final before = rows();
        final totals = batchTotalsOf(db.nutritionFor(recipe.id)!);
        expect(recomputeTotals(db, recipe), isTrue, reason: recipe.slug);
        expect(rows(), before, reason: recipe.slug);
        expect(batchTotalsOf(db.nutritionFor(recipe.id)!), totals);
      }
    });
  });
}
