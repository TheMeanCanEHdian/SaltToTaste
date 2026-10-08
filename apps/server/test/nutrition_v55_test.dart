// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v55 (batch M56, meat records at the right animal, cut and fat
// level; matcherVersion 54; prep48 design_v2 §2 M56 with §1 Q1 (a), Q2 (i),
// Q3 (a), Q5 (a) and Q7, critic F2, F11 and F12, decided by the owner
// 2026-10-08 under the standing authorization; zero requests): R1 rank-as
// items (strip roast and boneless strip steaks → Foundation 2727572, blade
// steaks → beef 168707, beef brisket → the raw flat 0" 168743, the
// boneless center-cut pork loin roast → Foundation 2646168); R2
// `leanAndFatSibling` (a "separable lean only" top yields to its exact
// lean-and-fat sibling in the same answer); R3 `trimDepthRecords` (the
// rack 172641 → 174414 with its AH-102 row; "fat caps removed" 2727572 →
// 171751). Every row value is the v55 replay of snapshot 23 (rp43, fix55
// r1), computed here on WHOLE recipes over recorded real FDC answers
// (FixtureProvider; 28 searches and 8 foods added --from-db from snapshot
// 23, JSON-equal, 0 existing entries changed), never the network.

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

/// (rule, file, position, raw, fdc id, confidence, grams, kcal) — the v55
/// replay's row; the v54 record and kcal in the comment. Grams never move.
const List<(String, String, int, String, int, String, String, String)>
_reach = [
  // R1a: PORK 168314 4,141.29 → +599.86
  (
    'R1a',
    '0221-beef-top-loin-roast-with-potatoes.yaml',
    0,
    '1 (5- to 6-pound) boneless top loin roast',
    2727572,
    '1.000000',
    '2494.76',
    '4741.15',
  ),
  // R1b: PORK 167849 1,687.36 → −308.44
  (
    'R1b',
    '0552-stir-fried-thai-style-beef-with-chiles-and-shallots.yaml',
    5,
    '2 pounds blade steaks, halved lengthwise, trimmed, and sliced into ⅛-inch-thick slices',
    168707,
    '1.000000',
    '907.18',
    '1378.92',
  ),
  // R1b: PORK 167849 2,952.88 → −539.77
  (
    'R1b',
    '0008-our-favorite-chili.yaml',
    15,
    '3½ pounds blade steak, ¾ inch thick, trimmed and cut into ¾-inch pieces',
    168707,
    '1.000000',
    '1587.57',
    '2413.11',
  ),
  // R1c: lean-only 746759 703.07 → +158.96
  (
    'R1c',
    '0010-vietnamese-beef-pho.yaml',
    11,
    '1 (1-pound) boneless strip steak, trimmed and halved',
    2727572,
    '1.000000',
    '453.59',
    '862.03',
  ),
  // R1c: 746759 1,230.37 → +278.18
  (
    'R1c',
    '0187-pan-seared-strip-steaks.yaml',
    0,
    '2 (12- to 16-ounce) boneless strip steaks, 1½ inches thick, trimmed',
    2727572,
    '1.000000',
    '793.79',
    '1508.55',
  ),
  // R1c: 746759 1,406.14 → +317.92
  (
    'R1c',
    '0188-cast-iron-thick-cut-steaks-with-herb-butter.yaml',
    0,
    '2 (1-pound) boneless strip steaks, 1½ inches thick, trimmed',
    2727572,
    '1.000000',
    '907.18',
    '1724.06',
  ),
  // R1c: 746759 1,406.14 → +317.92
  (
    'R1c',
    '0189-pan-seared-thick-cut-steaks.yaml',
    0,
    '2 (1-pound) boneless strip steaks, each 1½ to 1¾ inches thick',
    2727572,
    '1.000000',
    '907.18',
    '1724.06',
  ),
  // R1c then Q7 (R3's second pair): 746759 1,406.14 → +145.14
  (
    'R1c+Q7',
    '0586-ultimate-charcoal-grilled-steaks.yaml',
    0,
    '2 (1-pound) boneless strip steaks, 1¾ inches thick, fat caps removed',
    171751,
    '1.000000',
    '907.18',
    '1551.28',
  ),
  // R1c: 746759 2,812.27 → +635.84
  (
    'R1c',
    '0587-grilled-argentine-steaks-with-chimichurri-sauce.yaml',
    11,
    '4 (1-pound) boneless strip steaks, 1½ inches thick, trimmed',
    2727572,
    '1.000000',
    '1814.37',
    '3448.11',
  ),
  // R1c: 746759 703.07 → +158.96
  (
    'R1c',
    '1182-new-york-strip-steaks-with-crispy-potatoes-and-parsley-sauce.yaml',
    12,
    '2 (8-ounce) boneless strip steaks, ¾ inch thick, trimmed',
    2727572,
    '1.000000',
    '453.59',
    '862.03',
  ),
  // R1d: FNDDS (cooked) 2705851 4,715.09 → −1,265.52
  (
    'R1d',
    '0090-new-englandstyle-home-corned-beef-and-cabbage.yaml',
    6,
    '1 (4- to 5-pound) beef brisket, flat cut, trimmed',
    168743,
    '1.000000',
    '2041.16',
    '3449.57',
  ),
  // R1d: 2705851 4,977.04 → −1,335.83
  (
    'R1d',
    '0091-home-corned-beef-with-vegetables.yaml',
    0,
    '1 (4½- to 5-pound) beef brisket, flat cut',
    168743,
    '1.000000',
    '2154.56',
    '3641.21',
  ),
  // R1d: 2705851 4,715.09 → −1,265.52
  (
    'R1d',
    '0223-onion-braised-beef-brisket.yaml',
    0,
    '1 (4- to 5-pound) beef brisket, preferably flat cut',
    168743,
    '1.000000',
    '2041.16',
    '3449.57',
  ),
  // R1d: 2705851 4,715.09 → −1,265.52 (flagged, Q2 (i))
  (
    'R1d',
    '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml',
    0,
    '1 (4- to 5-pound) beef brisket, flat cut, fat trimmed to ¼ inch',
    168743,
    '1.000000',
    '2041.16',
    '3449.57',
  ),
  // R1e (Q5 a): SR center RIB 167889 2,631.97 → −536.37
  (
    'R1e',
    '0240-herb-crusted-pork-roast.yaml',
    0,
    '1 (2½- to 3-pound) boneless center-cut pork loin roast',
    2646168,
    '1.000000',
    '1247.38',
    '2095.60',
  ),
  // R1e: 167889 2,631.97 → −536.37
  (
    'R1e',
    '0199-pan-seared-thick-cut-boneless-pork-chops.yaml',
    0,
    '1 (2½- to 3-pound) boneless center-cut pork loin roast, trimmed',
    2646168,
    '1.000000',
    '1247.38',
    '2095.60',
  ),
  // R1e (the third key, its own answer holding only 167889): 2,153.43 → −438.85
  (
    'R1e',
    '0241-garlic-studded-roast-pork-loin.yaml',
    5,
    '1 (2¼-pound) boneless center loin pork roast, fat trimmed to about ⅛ inch thick and roast tied at 1½-inch intervals',
    2646168,
    '1.000000',
    '1020.58',
    '1714.58',
  ),
  // R1e: 167889 2,392.70 → −487.61
  (
    'R1e',
    '0238-french-style-pot-roasted-pork-loin.yaml',
    2,
    '1 (2½-pound) boneless center-cut pork loin roast, trimmed',
    2646168,
    '1.000000',
    '1133.98',
    '1905.09',
  ),
  // R1e (the second key): 167889 2,392.70 → −487.61
  (
    'R1e',
    '0243-arista-tuscan-style-roast-pork-with-garlic-and-rosemary.yaml',
    6,
    '1 (2½-pound) center-cut boneless pork loin roast, trimmed',
    2646168,
    '1.000000',
    '1133.98',
    '1905.09',
  ),
  // R1e: 167889 2,392.70 → −487.61
  (
    'R1e',
    '0604-grilled-pork-loin-with-apple-cranberry-filling.yaml',
    10,
    '1 (2½-pound) boneless center-cut pork loin roast, trimmed',
    2646168,
    '1.000000',
    '1133.98',
    '1905.09',
  ),
  // R2: lean-only 169194 1,394.80 → +385.55 ("lean and fat only"; the top's 0.702576 kept)
  (
    'R2',
    '0239-maple-glazed-pork-roast.yaml',
    4,
    '1 (2½-pound) boneless blade-end pork loin roast, tied at 1½-inch intervals',
    168381,
    '0.702576',
    '1133.98',
    '1780.35',
  ),
  // R2: 169194 557.92 → +154.22
  (
    'R2',
    '0461-simplified-cassoulet-with-pork-and-kielbasa.yaml',
    9,
    '1 (1-pound) boneless blade-end pork loin roast, trimmed and cut into 1-inch pieces',
    168381,
    '0.702576',
    '453.59',
    '712.14',
  ),
  // R2: 169194 1,534.27 → +424.11
  (
    'R2',
    '0606-grill-roasted-pork-loin.yaml',
    1,
    '1 (2½- to 3-pound) boneless blade-end pork loin roast, trimmed and tied with kitchen twine at 1½-inch intervals',
    168381,
    '0.702576',
    '1247.38',
    '1958.38',
  ),
  // R2: 169194 2,092.19 → +578.33 (audit L137)
  (
    'R2',
    '0606-smoked-pork-loin-with-dried-fruit-chutney.yaml',
    2,
    '1 (3½- to 4-pound) blade-end boneless pork loin roast, trimmed',
    168381,
    '0.702576',
    '1700.97',
    '2670.52',
  ),
  // R2: Foundation lean-only 0" select 746760 2,213.53 → −36.29 ("lean and fat")
  (
    'R2',
    '0214-slow-roasted-beef.yaml',
    0,
    '1 (3½- to 4½-pound) boneless eye-round roast',
    171747,
    '0.927143',
    '1814.37',
    '2177.24',
  ),
  // R3: NZ 172641 2,098.49 → +844.36 (the AH-102 1364 row on 174414; the top's 0.539697 kept)
  (
    'R3',
    '0228-roast-rack-of-lamb-with-roasted-red-pepper-relish.yaml',
    0,
    '2 racks of lamb (1¾ to 2 pounds each), fat trimmed to ⅛ to ¼ inch, rib bones frenched',
    174414,
    '0.539697',
    '1241.71',
    '2942.85',
  ),
];

/// (file, position, raw, fdc id, confidence, grams, kcal) — rows the rules
/// must NOT reach, each equal to the v54 replay's.
const List<(String, int, String, int, String, String, String)> _unchanged = [
  // The 'strip steaks' rows already on 2727572.
  (
    '0463-steak-au-poivre-with-brandied-cream-sauce.yaml',
    4,
    '4 (8- to 10-ounce) strip steaks, ¾ to 1 inch thick, trimmed',
    2727572,
    '0.927143',
    '1020.58',
    '1939.56',
  ),
  (
    '0464-steak-diane.yaml',
    0,
    '4 (12-ounce) strip steaks, 1 to 1¼ inches thick, trimmed',
    2727572,
    '0.927143',
    '1360.78',
    '2586.08',
  ),
  // Top blade stays 168707; the flat-iron rank-as stays 172125 (§7 gap 4).
  (
    '0085-carbonnade-a-la-flamande-belgian-beef-beer-and-onion-stew.yaml',
    0,
    '3½ pounds top blade steaks, 1 inch thick, trimmed of gristle and fat and cut into 1-inch pieces (see below)',
    168707,
    '0.866154',
    '1587.57',
    '2413.11',
  ),
  (
    '0595-grill-smoked-herb-rubbed-flat-iron-steaks.yaml',
    5,
    '4 (6- to 8-ounce) flat-iron steaks, ¾ to 1 inch thick, trimmed',
    172125,
    '1.000000',
    '793.79',
    '1444.69',
  ),
  // Item-keyed, never title-keyed (a "Chicken-Fried" beef steak; pancetta).
  (
    '0304-chicken-fried-steaks.yaml',
    7,
    '6 (5-ounce) cube steaks, pounded ⅓ inch thick',
    2705826,
    '0.923333',
    '850.49',
    '1590.41',
  ),
  (
    '0349-rigatoni-with-beef-and-onion-ragu.yaml',
    2,
    '2 ounces pancetta, cut into ½-inch pieces',
    168277,
    '1.000000',
    '56.70',
    '222.83',
  ),
  (
    '0414-chicken-marsala.yaml',
    4,
    '2½ ounces pancetta (about 3 slices), cut into pieces 1 inch long and ⅛ inch wide',
    168277,
    '1.000000',
    '70.87',
    '278.53',
  ),
  (
    '0415-better-chicken-marsala.yaml',
    8,
    '3 ounces pancetta, cut into ½-inch pieces',
    168277,
    '1.000000',
    '85.05',
    '334.24',
  ),
  (
    '0426-beef-braised-in-barolo.yaml',
    2,
    '4 ounces pancetta (about 4 slices), cut into ¼-inch cubes (see note)',
    168277,
    '1.000000',
    '0.00',
    '0.00',
  ),
  // R2 unreached (no exact sibling cached): the shanks on lean-only 169441
  // (the AH-102 228 flag discloses it), the top-sirloin roasts on 173408.
  (
    '0007-alcatra-portuguese-style-beef-stew.yaml',
    0,
    '3 pounds boneless long-cut beef shanks',
    169441,
    '1.000000',
    '1360.78',
    '1741.79',
  ),
  (
    '1171-bulalo-hearty-beef-shank-and-vegetable-soup.yaml',
    2,
    '4 pounds beef shanks, trimmed',
    169441,
    '0.856364',
    '1106.76',
    '1416.66',
  ),
  (
    '0220-fennel-coriander-top-sirloin-roast.yaml',
    0,
    '1 (5- to 6-pound) boneless top sirloin center-cut roast, trimmed',
    173408,
    '0.553333',
    '2494.76',
    '3293.08',
  ),
  (
    '0461-beef-en-cocotte-with-mushroom-sauce.yaml',
    0,
    '1 (3- to 4-pound) top sirloin beef roast, trimmed and tied once around middle',
    173408,
    '0.870000',
    '1587.57',
    '2095.60',
  ),
  (
    '0592-inexpensive-grill-roasted-beef-with-garlic-and-rosemary.yaml',
    4,
    '1 (3- to 4-pound) top sirloin roast',
    173408,
    '0.857500',
    '1587.57',
    '2095.60',
  ),
  // R3 unreached: the same retail rack with no printed depth (Q3, F11).
  (
    '0622-grilled-rack-of-lamb.yaml',
    5,
    '2 (1½- to 1¾-pound) racks of lamb (8 ribs each), frenched and trimmed',
    172641,
    '0.539697',
    '1076.15',
    '1818.69',
  ),
  // Brisket pairs are NOT in R3 (Q2 (ii) deferred): the whole brisket stays.
  (
    '0595-barbecued-whole-beef-brisket-with-spicy-chili-rub.yaml',
    10,
    '1 (9- to 11-pound) whole beef brisket, fat trimmed to ¼ inch',
    168607,
    '0.886667',
    '4535.92',
    '7121.39',
  ),
  // "¼ inch or less" and "¼-inch thickness" on records with no pair.
  (
    '1172-multicooker-hawaiian-oxtail-soup.yaml',
    3,
    '3 pounds oxtails, fat trimmed to ¼ inch or less',
    2705843,
    '0.890000',
    '768.00',
    '1973.76',
  ),
  (
    '0607-grill-roasted-bone-in-pork-rib-roast.yaml',
    0,
    '1 (4- to 5-pound) bone-in center-cut pork rib roast, tip of chine bone removed, fat trimmed to ¼-inch thickness',
    168242,
    '0.719451',
    '1350.62',
    '2512.15',
  ),
];

/// Q2 (i) / F2: the stand-in's text, byte-equal to design_v2 §1 Q2.
const _pomegranateFlag =
    'approximate (the printed ¼-inch fat cap renders and is skimmed (step '
    '5); counted as the 0-inch trimmed flat)';

/// The rack's AH-102 row, 172641's verbatim (now keyed on 174414 too).
const _rackBasis =
    '2 × 850 g (printed 1¾–2 lb, the midpoint) × 0.73 edible · approximate '
    '(USDA AH-102 item 1364: lamb rib loin (rack), bone in, raw → lean and '
    'fat meat, slightly trimmed 73 % (61–88), as measured unfrenched; a '
    'frenched rack yields less)';

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
    expect(matcherVersion, 54);
  });

  test('R1: each rank-as item reads its named cached answer under the '
      "record's own words (design_v2 §2 M56; each confirmed as that "
      "answer's top on snapshot 23)", () {
    const strip = (
      query: 'beef short loin ny strip steak raw',
      answer: 'strip steaks',
    );
    const blade =
        'beef shoulder top blade steak boneless separable lean and fat '
        'trimmed to 0 fat choice raw';
    const loin = (
      query: 'pork loin boneless raw',
      answer: 'boneless center-cut pork loin roast',
    );
    expect(rankAsFor('boneless top loin roast'), strip);
    expect(rankAsFor('boneless strip steak'), strip);
    expect(rankAsFor('boneless strip steaks'), strip);
    expect(rankAsFor('blade steak'), (query: blade, answer: 'blade steak'));
    expect(rankAsFor('blade steaks'), (query: blade, answer: 'blade steaks'));
    expect(rankAsFor('beef brisket'), (
      query:
          'beef brisket flat half boneless separable lean and fat trimmed '
          'to 0 fat choice raw',
      answer: 'beef brisket',
    ));
    expect(rankAsFor('boneless center-cut pork loin roast'), loin);
    expect(rankAsFor('center-cut boneless pork loin roast'), loin);
    expect(rankAsFor('boneless center loin pork roast'), loin);
    // 'strip steaks' (steak-au-poivre, steak-diane) and 'top blade steaks'
    // (carbonnade) keep their own searches.
    expect(rankAsFor('strip steaks'), isNull);
    expect(rankAsFor('top blade steaks'), isNull);
  });

  test('R3: the trim pairs are keyed on the record (Q7 lives only on '
      '2727572, F12) and the rack keeps its AH-102 row on 174414', () {
    expect(
      {for (final (_, pairs) in trimDepthRecords) ...pairs},
      {172641: 174414, 2727572: 171751},
    );
    expect(ah102Meats[174414], ah102Meats[172641]);
    // Read on the search hit (no detail asked) — the rack alone.
    expect(ah102MeatsOnHit, {174414});
  });

  group('matcher v55 (batch M56)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;
    final recipes = <String, Recipe>{};

    /// [file] stored and computed whole (its sections first, as the
    /// per-recipe job does); its stored recipe.
    Future<Recipe> computed(String file) async {
      if (recipes[file] case final done?) {
        return done;
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
      return recipes[file] = db.recipeByIdOrSlug(host.id)!.recipe;
    }

    // One library: the 44 recipes computed once, in the tables' order, over
    // a cache seeded with what snapshot 23's library holds before them —
    // rule B1's cooked bacon 168322 is a hit of the deli-ham answer only
    // (the cassoulet's bacon); 'thyme leaves' splits garlic-studded's
    // section line "¾ teaspoon minced fresh thyme leaves or ¼ teaspoon dried
    // thyme" as it does there; and the details the snapshot holds for the
    // pinned records (a weight line fetches none: without them the energy
    // is the search hit's, rounded — 2727572 reads 190.0 for 190.04).
    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v55-');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath)
        ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: pendingSearches);
      for (final query in ['thin-sliced cooked deli ham', 'thyme leaves']) {
        db.fdcSearchCachePut(
          query,
          jsonEncode([
            for (final hit in await provider.search(query)) hit.toJson(),
          ]),
        );
      }
      for (final fdcId in const [
        168242, 168277, 168607, 169441, 172125, 172641, 173408, //
        2705826, 2705843, 2727572,
      ]) {
        db.fdcFoodCachePut(
          fdcId,
          jsonEncode((await provider.food(fdcId))!.toJson()),
        );
      }
      for (final (_, file, _, _, _, _, _, _) in _reach) {
        await computed(file);
      }
      for (final (file, _, _, _, _, _, _) in _unchanged) {
        await computed(file);
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    IngredientMatchRow rowOf(Recipe r, int position) => db
        .ingredientMatchesFor(r.id)
        .singleWhere((m) => m.position == position);

    /// Each [rows] entry computed in its whole recipe: the record, the
    /// confidence, the grams and the energy, an `auto` row with no hold.
    Future<void> expectRows(
      List<(String, int, String, int, String, String, String)> rows,
    ) async {
      for (final (file, position, raw, fdcId, confidence, grams, kcal)
          in rows) {
        final recipe = await computed(file);
        final line = nutritionLines(recipe)[position];
        final row = rowOf(recipe, position);
        final reason = '$file|$position';
        expect(line.raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.confidence.toStringAsFixed(6), confidence, reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(row.status, 'auto', reason: reason);
        expect(row.hold, isNull, reason: reason);
        expect(_kcalOf(db, row, line).toStringAsFixed(2), kcal, reason: reason);
      }
    }

    test('each reach row (26, design_v2 §2 M56) lands its record, '
        'confidence, grams and energy; grams never move; zero requests '
        'for the rack (174414 stays a search hit, weighed by its AH-102 '
        'row); only pomegranate|0 carries the stand-in flag', () async {
      expect(_reach, hasLength(26));
      expect(
        {for (final (rule, _, _, _, _, _, _, _) in _reach) rule},
        {'R1a', 'R1b', 'R1c', 'R1c+Q7', 'R1d', 'R1e', 'R2', 'R3'},
      );
      await expectRows([
        for (final (_, file, position, raw, fdcId, confidence, grams, kcal)
            in _reach)
          (file, position, raw, fdcId, confidence, grams, kcal),
      ]);
      String? basis(String file, int position) {
        final recipe = recipes[file]!;
        return gramBasisFor(
          db,
          nutritionLines(recipe)[position],
          rowOf(recipe, position),
          recipe: recipe,
        );
      }

      expect(
        basis(
          '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml',
          0,
        ),
        'from the printed weight (4–5 lb, the midpoint) · $_pomegranateFlag',
      );
      // R1d's 0" default (design Q2 (i)) when no depth is printed: unflagged.
      for (final (file, position) in [
        ('0090-new-englandstyle-home-corned-beef-and-cabbage.yaml', 6),
        ('0091-home-corned-beef-with-vegetables.yaml', 0),
        ('0223-onion-braised-beef-brisket.yaml', 0),
      ]) {
        expect(basis(file, position), isNot(contains('approximate')));
      }
      // The flag is keyed on the stand-in record (168743) AND the phrase
      // (V3-D1): two library lines print the phrase on other records and
      // keep their v54 bases byte for byte.
      expect(
        basis(
          '0595-barbecued-whole-beef-brisket-with-spicy-chili-rub.yaml',
          10,
        ),
        'from the printed weight (9–11 lb, the midpoint)',
      );
      expect(
        basis('1172-multicooker-hawaiian-oxtail-soup.yaml', 3),
        'from 3 pound × 0.56 edible · approximate (yield of oxtails from '
        'FDC 2705843)',
      );
      expect(
        basis('0228-roast-rack-of-lamb-with-roasted-red-pepper-relish.yaml', 0),
        _rackBasis,
      );
      expect(db.fdcFoodCacheGet(174414), isNull);
    });

    test('the rows the rules must not reach equal the v54 replay '
        '(item-keyed, record-keyed, no exact sibling, no printed depth)', () {
      return expectRows(_unchanged);
    });

    test('the sheet ranks as the compute does (candidatesForLine, Run '
        "047): its first candidate is each R2 and R3 row's record at the "
        "top's confidence", () async {
      var checked = 0;
      for (final (rule, file, position, _, fdcId, confidence, _, _) in _reach) {
        if (!const {'R2', 'R3', 'R1c+Q7'}.contains(rule)) {
          continue;
        }
        final recipe = await computed(file);
        final first = (await candidatesForLine(
          db,
          provider,
          nutritionLines(recipe)[position],
          cacheOnly: true,
        )).first;
        expect(first.candidate.fdcId, fdcId, reason: '$file|$position');
        expect(first.confidence.toStringAsFixed(6), confidence);
        checked++;
      }
      expect(checked, 7);
    });

    test('R1c runs before R2 (F12), pinned both ways: under its own words '
        "the strip line's own answer leads with Foundation lean-only "
        '746759, which R2 ALONE would move to its exact sibling 173072 (Q1 '
        "(b), declined) — where Q7's pair, keyed on 2727572, never fires; "
        "under R1c's words the 'strip steaks' answer leads with 2727572, R2 "
        'is silent and Q7 moves "fat caps removed" to 171751', () async {
      const ultimate =
          '2 (1-pound) boneless strip steaks, 1¾ inches thick, fat caps '
          'removed';
      final own = rankCandidates(
        'boneless strip steak',
        await provider.search('boneless strip steak'),
      );
      expect(own.first.candidate.fdcId, 746759);
      final alone = leanAndFatSibling(ultimate, own);
      expect(alone.first.candidate.fdcId, 173072);
      expect(alone.first.confidence, own.first.confidence);
      expect(trimDepthRecord(ultimate, alone).first.candidate.fdcId, 173072);
      final rankAs = rankAsFor('boneless strip steaks')!;
      final read = rankCandidates(
        rankAs.query,
        await provider.search(rankAs.answer),
      );
      expect(read.first.candidate.fdcId, 2727572);
      expect(identical(leanAndFatSibling(ultimate, read), read), isTrue);
      final moved = trimDepthRecord(ultimate, read);
      expect(moved.first.candidate.fdcId, 171751);
      expect(moved.first.confidence, read.first.confidence);
      expect(moved, hasLength(read.length));
      // No printed phrase, no move (the six other strip lines).
      expect(
        trimDepthRecord(
          '2 (1-pound) boneless strip steaks, 1½ inches thick, trimmed',
          read,
        ).first.candidate.fdcId,
        2727572,
      );
    });

    test('STATED synthesized negative (no corpus meat line says "lean" or '
        '"all fat", pA §3 R2): smoked-pork-loin\'s line with ", trimmed of '
        'all fat" appended keeps lean-only 169194; the real line reads '
        '168381', () async {
      final recipe = await computed(
        '0606-smoked-pork-loin-with-dried-fruit-chutney.yaml',
      );
      final line = nutritionLines(recipe)[2];
      Future<int> first(IngredientLine l) async => (await candidatesForLine(
        db,
        provider,
        l,
        cacheOnly: true,
      )).first.candidate.fdcId;
      expect(await first(line), 168381);
      expect(
        await first(line.copyWith(raw: '${line.raw}, trimmed of all fat')),
        169194,
      );
    });
  });
}
