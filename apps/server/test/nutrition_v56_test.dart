// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v56 (batch M57, a strain of "the liquid" whose solids nothing
// uses; matcherVersion 55; prep48 design_v2 §2 M57 S1, critic F4 and F14,
// the owner's Q19 NO — prunes are not a strained head; decided 2026-10-08
// under the standing authorization; zero requests; pre-Q18): engine
// `_strainAt` also reads "strain (the) (braising|cooking|poaching) liquid"
// when no sentence from it to the end names solids, vegetables, a blender,
// a food processor or a purée; a rejected one continues the scan. Every
// row value is the v56 replay of snapshot 23 (rp43, fix56 r1), computed
// here on WHOLE recipes over recorded real FDC answers (FixtureProvider; 3
// searches and 1 food added --from-db from snapshot 23, JSON-equal, 0
// existing entries changed), never the network.

import 'dart:convert';
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

/// M50 D1's shipped strained-solid basis, byte for byte (S1 adds no text).
const _flag =
    'discarded in cooking — counted as 0 g · approximate (strained out and '
    'discarded — what it gives the liquid is not counted)';

/// (file, position, raw, fdc id, confidence, grams, kcal, basis) — the v56
/// replay's row (a water rule row: no record, no grams).
typedef _Row = (String, int, String, int?, String, String?, String, String?);

const _ribs = '0088-slow-cooker-beer-braised-short-ribs.yaml';
const _confit = '1077-turkey-thigh-confit-with-citrus-mustard-sauce.yaml';

/// S1's reach (design_v2 §2 M57, exactly these four; −591.09 kcal): "…
/// strain the liquid through a fine-mesh strainer into a bowl" (the ribs,
/// step 3) and "Strain liquid through fine-mesh strainer into large bowl"
/// (the confit, step 5), no later sentence naming solids, vegetables, a
/// blender, a processor or a purée.
const List<_Row> _reach = [
  // v55: 1,360.78 g, 517.09 kcal
  (
    _ribs,
    4,
    '3 pounds yellow onions (about 6 medium), halved and sliced thin',
    790646,
    '1.000000',
    '0.00',
    '0.00',
    _flag,
  ),
  // v55: 0.40 g, 1.25 kcal
  (_ribs, 10, '2 bay leaves', 170917, '0.866667', '0.00', '0.00', _flag),
  // v55: 50.00 g, 71.50 kcal
  (
    _confit,
    7,
    '1 garlic head, halved crosswise',
    1104647,
    '0.970000',
    '0.00',
    '0.00',
    _flag,
  ),
  // v55: 0.40 g, 1.25 kcal
  (_confit, 8, '2 bay leaves', 170917, '0.866667', '0.00', '0.00', _flag),
];

/// The same two strains, kept by what ships: the prunes (Q19 NO — not a
/// strained head; "melted into the sauce"), the thyme and parsley named
/// after the strain ("remaining 1 teaspoon thyme", "Sprinkle with the
/// parsley"), the confit's onions processed in the food processor (the
/// vessel guard). Each equals v55.
const List<_Row> _kept = [
  (
    _ribs,
    7,
    '12 pitted prunes',
    2709211,
    '0.830000',
    '96.00',
    '230.40',
    '12 · USDA per-item weight',
  ),
  (
    _ribs,
    11,
    '2 teaspoons minced fresh thyme leaves',
    173470,
    '0.900000',
    '1.60',
    '1.62',
    '2 teaspoon · USDA portion',
  ),
  (
    _ribs,
    13,
    '2 tablespoons minced fresh parsley leaves',
    2709796,
    '0.910000',
    '7.50',
    '2.70',
    '2 tablespoon · USDA portion',
  ),
  (
    _confit,
    0,
    '3 large onions, chopped coarse (4¾ cups)',
    790646,
    '0.936667',
    '450.00',
    '171.00',
    '3 × 150 g each',
  ),
];

/// The later-use guard's negatives (each equals v55): the arm matches, and
/// a later sentence blends the vegetables (the pot roasts: "vegetables",
/// "blender"), returns the solids (the oxtails: "return solids to
/// now-empty pot") or blends the remaining solids (carne deshebrada:
/// "Transfer remaining solids to blender") — eaten, so the scan continues
/// and finds no strain. Measured with the guard dropped (fix56, replay):
/// twelve of these zero — the pot roasts' seven, the oxtails' three,
/// carne's |4 garlic and its slaw's |19 carrot (and carne |7 |18 |21 |22,
/// not pinned here); carne's |2 anchos and |20 jalapeño stay either way.
const List<_Row> _guarded = [
  (
    '0083-old-fashioned-pot-roast.yaml',
    3,
    '2 medium onions, halved and sliced thin (about 2 cups)',
    790646,
    '0.936667',
    '220.00',
    '83.60',
    '2 × 110 g each',
  ),
  (
    '0083-old-fashioned-pot-roast.yaml',
    4,
    '1 large carrot, peeled and chopped medium (about 1 cup)',
    2258586,
    '0.936667',
    '72.00',
    '34.55',
    '1 × 72 g each',
  ),
  (
    '0083-old-fashioned-pot-roast.yaml',
    5,
    '1 celery rib, chopped medium (about ¾ cup)',
    2346405,
    '0.970000',
    '40.00',
    '6.68',
    '1 × 40 g each',
  ),
  (
    '0083-old-fashioned-pot-roast.yaml',
    6,
    '2 medium garlic cloves, minced or pressed through a garlic press (about 2 teaspoons)',
    1104647,
    '0.970000',
    '6.00',
    '8.58',
    '2 × 3 g each',
  ),
  (
    '0083-pressure-cooker-pot-roast.yaml',
    3,
    '1 onion, sliced thick',
    790646,
    '0.936667',
    '110.00',
    '41.80',
    '1 × 110 g each',
  ),
  (
    '0083-pressure-cooker-pot-roast.yaml',
    4,
    '1 celery rib, sliced thick',
    2346405,
    '0.970000',
    '40.00',
    '6.68',
    '1 × 40 g each',
  ),
  (
    '0083-pressure-cooker-pot-roast.yaml',
    5,
    '1 carrot, peeled and sliced thick',
    2258586,
    '0.936667',
    '61.00',
    '29.27',
    '1 × 61 g each',
  ),
  (
    '0089-braised-oxtails-with-white-beans-tomatoes-and-aleppo-pepper.yaml',
    4,
    '1 onion, chopped fine',
    790646,
    '0.936667',
    '110.00',
    '41.80',
    '1 × 110 g each',
  ),
  (
    '0089-braised-oxtails-with-white-beans-tomatoes-and-aleppo-pepper.yaml',
    5,
    '1 carrot, peeled and chopped fine',
    2258586,
    '0.936667',
    '61.00',
    '29.27',
    '1 × 61 g each',
  ),
  (
    '0089-braised-oxtails-with-white-beans-tomatoes-and-aleppo-pepper.yaml',
    6,
    '6 garlic cloves, minced',
    1104647,
    '0.970000',
    '18.00',
    '25.74',
    '6 × 3 g each',
  ),
  (
    '0481-carne-deshebrada-shredded-beef-tacos.yaml',
    2,
    '2 ounces (4 to 6) dried ancho chiles, stemmed, seeded, and torn into 1-inch pieces',
    169396,
    '0.933333',
    '56.70',
    '159.32',
    'from 2 ounce',
  ),
  (
    '0481-carne-deshebrada-shredded-beef-tacos.yaml',
    4,
    '6 garlic cloves, lightly crushed and peeled',
    1104647,
    '0.970000',
    '18.00',
    '25.74',
    '6 × 3 g each',
  ),
  (
    '0481-carne-deshebrada-shredded-beef-tacos.yaml',
    19,
    '1 large carrot, peeled and shredded',
    2258586,
    '0.936667',
    '72.00',
    '34.55',
    '1 × 72 g each',
  ),
  (
    '0481-carne-deshebrada-shredded-beef-tacos.yaml',
    20,
    '1 jalapeño chile, stemmed, seeded, and minced',
    2747661,
    '0.920000',
    '14.00',
    '3.38',
    '1 × 14 g each',
  ),
];

/// F14: daube's porcini soak ("Strain the liquid through a fine-mesh
/// strainer lined with a paper towel into a medium bowl", step 1) is the
/// arm's and nothing later names solids, so `_strainAt` now returns it —
/// every row stays v55's byte for byte through the shipped per-line guards
/// (the porcini named again after it; every other strained head first
/// named after it).
const List<_Row> _daube = [
  (
    '0456-daube-provencal.yaml',
    0,
    '¾ ounce dried porcini mushrooms, rinsed',
    168436,
    '0.616667',
    '21.26',
    '62.94',
    'from 3/4 ounce',
  ),
  (
    '0456-daube-provencal.yaml',
    1,
    '1 (3½-pound) boneless beef chuck-eye roast, trimmed and cut into 2-inch chunks',
    168661,
    '0.896923',
    '1587.57',
    '2937.01',
    'from the printed weight',
  ),
  (
    '0456-daube-provencal.yaml',
    2,
    '1½ teaspoons table salt',
    173468,
    '1.000000',
    '9.02',
    '0.00',
    '1 1/2 teaspoon ≈ 7 mL',
  ),
  (
    '0456-daube-provencal.yaml',
    3,
    '1 teaspoon ground black pepper',
    170931,
    '1.000000',
    '2.32',
    '5.81',
    '1 teaspoon ≈ 5 mL',
  ),
  (
    '0456-daube-provencal.yaml',
    4,
    '4 tablespoons olive oil',
    2710186,
    '0.990000',
    '56.00',
    '504.00',
    '4 tablespoon · USDA portion',
  ),
  (
    '0456-daube-provencal.yaml',
    5,
    '5 ounces salt pork, rind removed',
    168287,
    '0.920000',
    '0.00',
    '0.00',
    'removed and discarded (step 4) — counted as 0 g',
  ),
  (
    '0456-daube-provencal.yaml',
    6,
    '2 medium onions, halved pole to pole and cut into ⅛-inch-thick slices (about 4 cups)',
    790646,
    '0.936667',
    '220.00',
    '83.60',
    '2 × 110 g each',
  ),
  (
    '0456-daube-provencal.yaml',
    7,
    '4 large carrots, peeled and cut into 1-inch-thick rounds (about 2 cups)',
    2258586,
    '0.936667',
    '288.00',
    '138.21',
    '4 × 72 g each',
  ),
  (
    '0456-daube-provencal.yaml',
    8,
    '2 tablespoons tomato paste',
    2685580,
    '0.856667',
    '32.53',
    '33.92',
    '2 tablespoon ≈ 30 mL',
  ),
  (
    '0456-daube-provencal.yaml',
    9,
    '4 medium garlic cloves, peeled and sliced thin',
    1104647,
    '0.970000',
    '12.00',
    '17.16',
    '4 × 3 g each',
  ),
  (
    '0456-daube-provencal.yaml',
    10,
    '⅓ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '40.22',
    '147.21',
    '1/3 cup ≈ 79 mL',
  ),
  (
    '0456-daube-provencal.yaml',
    11,
    '1 (750-milliliter) bottle bold red wine',
    2710688,
    '0.673333',
    '750.00',
    '637.50',
    '1 bottle · USDA portion',
  ),
  (
    '0456-daube-provencal.yaml',
    12,
    '1 cup low-sodium chicken broth',
    171609,
    '0.873333',
    '236.59',
    '37.85',
    '1 cup ≈ 237 mL',
  ),
  (
    '0456-daube-provencal.yaml',
    13,
    '1 cup water',
    null,
    '1.000000',
    null,
    '0.00',
    null,
  ),
  (
    '0456-daube-provencal.yaml',
    14,
    '1 cup pitted niçoise olives, drained well',
    2710090,
    '0.990000',
    '135.00',
    '156.60',
    '1 cup · USDA portion · approximation (counted as Olives, black)',
  ),
  (
    '0456-daube-provencal.yaml',
    15,
    '4 strips zest from 1 orange, each strip about 3 inches long, removed with a vegetable peeler, cleaned of white pith, and cut lengthwise into thin strips',
    169103,
    '0.886667',
    '9.60',
    '9.31',
    '4 strip × 3 inch × 0.8 g per inch · approximate (ATK: 10 (3-inch) strips orange peel ≈ ¼ cup)',
  ),
  (
    '0456-daube-provencal.yaml',
    16,
    '2 anchovy fillets, minced (about 1 teaspoon)',
    2706232,
    '0.890000',
    '8.00',
    '16.80',
    '2 · USDA per-item weight',
  ),
  (
    '0456-daube-provencal.yaml',
    17,
    '5 sprigs fresh thyme, tied together with kitchen twine',
    173470,
    '0.900000',
    '0.00',
    '0.00',
    'removed and discarded (step 4) — counted as 0 g',
  ),
  (
    '0456-daube-provencal.yaml',
    18,
    '2 bay leaves',
    170917,
    '0.866667',
    '0.00',
    '0.00',
    'removed and discarded (step 4) — counted as 0 g',
  ),
  (
    '0456-daube-provencal.yaml',
    19,
    '1 (14.5-ounce) can whole tomatoes, drained and cut into ½-inch cubes',
    2685578,
    '0.860000',
    '221.98',
    '49.89',
    'from the printed weight × 0.54 drained · approximate (ATK: 2 (28-ounce) cans whole tomatoes, drained, give 3 cups juice)',
  ),
  (
    '0456-daube-provencal.yaml',
    20,
    '2 tablespoons minced fresh parsley leaves',
    2709796,
    '0.910000',
    '7.50',
    '2.70',
    '2 tablespoon · USDA portion',
  ),
];

/// The arm's noun is "liquid" alone (design_v2 §2 M57: the reach is EXACTLY
/// the four rows): a strain of "sauce" is not the arm's, so these rows stay
/// v55's byte for byte. Each recipe's own trigger sentence (asserted below)
/// is a real corpus strain of the sauce with no pressing or discarding of
/// solids; an arm widened to "sauce" zeroes the aromatics (closer 1,
/// verifier V1-D1: the mutant passed every other pin).
const Map<String, String> _sauceStrainOf = {
  '0007-tuscan-style-beef-stew.yaml':
      'Strain sauce through fine-mesh strainer into fat separator.',
  '0535-chinese-braised-beef.yaml':
      'Strain sauce through fine-mesh strainer into fat separator.',
  '0223-onion-braised-beef-brisket.yaml':
      'set a mesh strainer over the bowl and strain the sauce over the brisket.',
  '0137-one-hour-broiled-chicken-and-pan-sauce.yaml':
      'Strain sauce through fine-mesh strainer and season with salt and pepper to taste.',
};

const List<_Row> _sauceStrains = [
  (
    '0007-tuscan-style-beef-stew.yaml',
    5,
    '4 shallots, halved lengthwise',
    170499,
    '0.920000',
    '120.00',
    '86.40',
    '4 × 30 g each',
  ),
  (
    '0007-tuscan-style-beef-stew.yaml',
    6,
    '2 carrots, peeled and halved lengthwise',
    2258586,
    '0.936667',
    '122.00',
    '58.55',
    '2 × 61 g each',
  ),
  (
    '0007-tuscan-style-beef-stew.yaml',
    7,
    '1 garlic head, cloves separated, unpeeled, and crushed',
    1104647,
    '0.970000',
    '50.00',
    '71.50',
    '1 × 50 g each',
  ),
  (
    '0007-tuscan-style-beef-stew.yaml',
    8,
    '4 sprigs fresh rosemary',
    173473,
    '0.900000',
    '0.00',
    '0.00',
    '4 sprig — a sprig is not measured, counted as 0 g',
  ),
  (
    '0007-tuscan-style-beef-stew.yaml',
    9,
    '2 bay leaves',
    170917,
    '0.866667',
    '0.40',
    '1.25',
    // RE-PIN (M64 batch, v63, R4b): a sub-gram piece prints its figure
    // (was '2 × 0 g each'); the row's grams unchanged.
    '2 × 0.2 g each',
  ),
  (
    '0535-chinese-braised-beef.yaml',
    7,
    '1 (2-inch) piece ginger, peeled, halved lengthwise, and crushed',
    169231,
    '0.886667',
    '16.00',
    '12.80',
    '1 piece × 2 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '0535-chinese-braised-beef.yaml',
    8,
    '4 garlic cloves, peeled and smashed',
    1104647,
    '0.970000',
    '12.00',
    '17.16',
    '4 × 3 g each',
  ),
  (
    '0223-onion-braised-beef-brisket.yaml',
    5,
    '3 medium garlic cloves, minced or pressed through a garlic press (about 1 tablespoon)',
    1104647,
    '0.970000',
    '9.00',
    '12.87',
    '3 × 3 g each',
  ),
  (
    '0223-onion-braised-beef-brisket.yaml',
    12,
    '3 bay leaves',
    170917,
    '0.866667',
    '0.00',
    '0.00',
    'removed and discarded (step 5) — counted as 0 g',
  ),
  (
    '0223-onion-braised-beef-brisket.yaml',
    13,
    '3 sprigs fresh thyme',
    173470,
    '0.900000',
    '0.00',
    '0.00',
    'removed and discarded (step 5) — counted as 0 g',
  ),
  (
    '0137-one-hour-broiled-chicken-and-pan-sauce.yaml',
    3,
    '4 sprigs fresh thyme',
    173470,
    '0.900000',
    '0.00',
    '0.00',
    '4 sprig — a sprig is not measured, counted as 0 g',
  ),
  (
    '0137-one-hour-broiled-chicken-and-pan-sauce.yaml',
    4,
    '1 garlic clove, peeled and crushed',
    1104647,
    '0.970000',
    '3.00',
    '4.29',
    '1 × 3 g each',
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
    // RE-PIN (M58 batch, v57): matcherVersion 56 (was 55).
    // RE-PIN (M59 batch, v58): matcherVersion 57 (was 56).
    // RE-PIN (M60 batch, v59): matcherVersion 58 (was 57).
    // RE-PIN (M61 batch, v60): matcherVersion 59 (was 58).
    // RE-PIN (M62 batch, v61): matcherVersion 60 (was 59).
    // RE-PIN (M63 batch, v62): matcherVersion 61 (was 60).
    // RE-PIN (M64 batch, v63): matcherVersion 62 (was 61).
    // RE-PIN (M65 batch, v64): matcherVersion 63 (was 62).
    // RE-PIN (M66 batch, v65): matcherVersion 64 (was 63).
    // RE-PIN (M67 batch, v66): matcherVersion 65 (was 64).
    // RE-PIN (M68 batch, v67): matcherVersion 66 (was 65).
    expect(matcherVersion, 66);
  });

  group('matcher v56 (batch M57)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v56-');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath)
        ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: pendingSearches);
      // The detail snapshot 23 holds for daube's drained tomatoes (a weight
      // line fetches none: without it the energy is the search hit's
      // rounded 22.5 for 22.4763 — 49.94 kcal for the replay's 49.89).
      db.fdcFoodCachePut(
        2685578,
        jsonEncode((await provider.food(2685578))!.toJson()),
      );
      // Each recipe stored and computed whole (no sections among them).
      for (final (file, _, _, _, _, _, _, _) in [
        ..._reach,
        ..._guarded,
        ..._daube,
        ..._sauceStrains,
      ]) {
        if (recipes.containsKey(file)) {
          continue;
        }
        final host = loadCorpusRecipe(file);
        db.upsertRecipe(host, sourceSlug: _source, contentHash: host.id);
        final stored = db.recipeByIdOrSlug(host.id)!.recipe;
        expect(sectionChildKeysOf(db, stored, ResolverMemo(db)), isEmpty);
        expect(await matchAndCompute(db, provider, stored), isNull);
        recipes[file] = db.recipeByIdOrSlug(host.id)!.recipe;
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    /// Each [rows] entry computed in its whole recipe: the record, the
    /// confidence, the grams, the energy and the basis; no hold.
    void expectRows(List<_Row> rows) {
      for (final (file, position, raw, fdcId, confidence, grams, kcal, basis)
          in rows) {
        final recipe = recipes[file]!;
        final line = nutritionLines(recipe)[position];
        final row = db
            .ingredientMatchesFor(recipe.id)
            .singleWhere((m) => m.position == position);
        final reason = '$file|$position';
        expect(line.raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.confidence.toStringAsFixed(6), confidence, reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(row.status, fdcId == null ? 'confirmed' : 'auto');
        expect(row.hold, isNull, reason: reason);
        expect(_kcalOf(db, row, line).toStringAsFixed(2), kcal, reason: reason);
        expect(
          gramBasisFor(db, line, row, recipe: recipe),
          basis,
          reason: reason,
        );
      }
    }

    test('S1 reaches exactly its four rows: 0 g with the shipped '
        'strained-solid basis (design_v2 §2 M57)', () {
      expect(_reach, hasLength(4));
      expectRows(_reach);
    });

    test('the same strains keep the prunes (Q19 NO), the thyme and parsley '
        'named after them and the processor onions (the vessel guard)', () {
      expectRows(_kept);
    });

    test('the later-use guard: a strain of the liquid whose solids a later '
        'sentence blends or returns zeroes nothing (equal to v55)', () {
      expect(_guarded, hasLength(14));
      expectRows(_guarded);
    });

    test('F14: daube-provencal, every row equal to v55 (its porcini soak is '
        "now the recipe's strain; the per-line guards keep each line)", () {
      expect(
        _daube,
        hasLength(nutritionLines(recipes[_daube.first.$1]!).length),
      );
      expectRows(_daube);
    });

    test('a strain of the SAUCE is not the arm (its noun is "liquid" '
        'alone): every row the "sauce" widening would zero equals v55', () {
      expect(_sauceStrains, hasLength(12));
      for (final MapEntry(key: file, value: sentence)
          in _sauceStrainOf.entries) {
        expect(
          recipes[file]!.steps.any((s) => s.text.contains(sentence)),
          isTrue,
          reason: file,
        );
      }
      expectRows(_sauceStrains);
    });

    test('STATED synthesized (no corpus arm sentence names one): the arm has '
        "no purée/soup skip of its own (§2 M57) — the ribs' strain of the "
        'liquid sent "into the soup" still zeroes the onions', () {
      final ribs = loadCorpusRecipe(_ribs);
      final onions = nutritionLines(ribs)[4];
      expect(onions.raw, _reach.first.$3);
      final step3 = ribs.steps[2];
      final text = step3.text.replaceFirst(
        'strain the liquid through a fine-mesh strainer into a bowl.',
        'strain the liquid through a fine-mesh strainer into the soup.',
      );
      expect(text, isNot(step3.text));
      final synthesized = ribs.copyWith(
        steps: [...ribs.steps]..[2] = step3.copyWith(text: text),
      );
      expect(
        discardedMediumOf(
          synthesized,
          onions,
          normalizeItem(lineItemOf(onions)),
        ),
        DiscardedMedium.strainedSolid,
      );
    });

    test('F14, STATED synthesized pair (no corpus recipe holds one): the '
        "ribs' own strain of the liquid, then a pressing strain appended — "
        'the first is now guarded (a later sentence names solids) and the '
        'scan CONTINUES to the second, which zeroes the onions; with a later '
        '"return the solids" instead, nothing is strained', () {
      final ribs = loadCorpusRecipe(_ribs);
      final onions = nutritionLines(ribs)[4];
      expect(onions.raw, _reach.first.$3);
      DiscardedMedium? onionsWith(String text) {
        final synthesized = ribs.copyWith(
          steps: [
            ...ribs.steps,
            ribs.steps.last.copyWith(number: 5, text: text),
          ],
        );
        return discardedMediumOf(
          synthesized,
          onions,
          normalizeItem(lineItemOf(onions)),
        );
      }

      // The real recipe: the arm's strain (step 3) zeroes them.
      expect(
        discardedMediumOf(ribs, onions, normalizeItem(lineItemOf(onions))),
        DiscardedMedium.strainedSolid,
      );
      // Synthesized: a pressing strain after it — found past the guarded
      // arm (a guarded match returning null would leave the onions counted).
      expect(
        onionsWith(
          'Strain the sauce through a fine-mesh strainer into a bowl, '
          'pressing on the solids.',
        ),
        DiscardedMedium.strainedSolid,
      );
      // Synthesized: the solids returned — the guard rejects the arm and no
      // other strain follows.
      expect(onionsWith('Return the solids to the sauce.'), isNull);
    });
  });
}
