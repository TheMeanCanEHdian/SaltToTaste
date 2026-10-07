// Real corpus lines wrap across adjacent literals; the table keeps each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Matcher v43, the produce and meat half of the USDA Agriculture Handbook
/// 102 yields (the owner's 2026-10-06 rulings Y8–Y11): a produce weight
/// printed in the line's head with a prep word in its tail counts the
/// handbook's paring/trimming yield ([produceYields]), a counted scallion
/// its part words ([scallionPartOf]), a bone-in beef/pork/lamb cut the
/// handbook names its boning yield ([ah102Meats]). Each row is a real
/// corpus line at the record, grams and basis the cache-only replay of
/// snapshot 19 derives at v43 — the moved rows and the rows pinned NOT to
/// move ("unpeeled", a trailing prepared weight, the peels veto, "trimmed"
/// carrots, dried apples, a head with no prep word, a cup of scallion
/// greens, "white and light green" / "dark green parts only", and the
/// records whose FDC refuse portions stay: chops, butt, country ribs,
/// oxtails, baby backs, picnic).
void main() {
  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v43q');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    return db;
  }

  /// [file]'s line at [position], alone in a recipe with its steps and prep
  /// notes, matched and computed on the fixtures.
  Future<(SaltDatabase, Recipe)> computed(String file, int position) async {
    final from = loadCorpusRecipe(file);
    final db = tempDb()..upsertSource(slug: 'src', name: 'Test', type: 'book');
    final recipe = Recipe(
      id: 'r',
      title: 'r',
      slug: 'r',
      source: const RecipeSource(name: 'Test', type: 'book'),
      prepNotes: from.prepNotes,
      steps: from.steps,
      ingredients: [
        IngredientGroup(items: [nutritionLines(from)[position]]),
      ],
    );
    db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'hr');
    await matchAndCompute(db, FixtureProvider(), recipe);
    return (db, recipe);
  }

  group('in their recipes', skip: skipIfNoCorpus, () {
    test('each produce, scallion and meat line at its record, grams and '
        'basis', () async {
      for (final (file, position, raw, fdcId, grams, basis) in _pins) {
        final (db, recipe) = await computed(file, position);
        final line = recipe.ingredients.single.items.single;
        expect(line.raw, raw, reason: file);
        final row = db.ingredientMatchesFor('r').single;
        expect(row.fdcId, fdcId, reason: raw);
        expect(row.status, 'auto', reason: raw);
        expect(row.hold, isNull, reason: raw);
        expect(row.grams?.toStringAsFixed(2), grams, reason: raw);
        expect(
          gramBasisFor(db, line, row, recipe: recipe),
          basis,
          reason: raw,
        );
      }
    });
  });

  test('Y10: the seven cuts AH-102 names left the borrowed class table; '
      "FDC's own refuse classes stay", () {
    expect(ah102Meats.keys.toSet(), {
      167853,
      168675,
      169441,
      172641,
      172513,
      169177,
      168226,
    });
    for (final id in ah102Meats.keys) {
      expect(boneInClassYields.containsKey(id), isFalse, reason: '$id');
    }
    expect(boneInClassYields[167822]!.share, 133 / 201);
    expect(boneInClassYields[168299]!.share, 128 / 196);
    expect(boneInClassYields[168367]!.share, 288 / 380);
    expect(boneInClassYields[2705843]!.share, 16 / 28.349523125);
  });
}

/// (file, position, raw, fdc id, grams, basis) — every value from the v43
/// replay of snapshot 19 (fix43/rq/rows.tsv).
const _pins = [
  (
    '0955-skillet-apple-brown-betty.yaml',
    9,
    '1½ pounds Golden Delicious apples (about 3 large), peeled, cored, and cut into ½-inch cubes (about 4 cups)',
    168202,
    '530.70',
    'from 1 1/2 pound × 0.78 edible · approximate (USDA AH-102 item 17: apples, all cultivars, raw whole → flesh, pared and cored 78 % (60–87))',
  ),
  (
    '0664-simple-applesauce.yaml',
    0,
    '4 pounds apples (about 10 medium), preferably Jonagold, Pink Lady, Jonathan, or Macoun, unpeeled, cored, and cut into rough 1½-inch pieces',
    2709215,
    '1632.93',
    'from 4 pound × 0.90 edible · approximate (USDA AH-102 item 30: apples, all cultivars, raw whole → cored only 90 % (84–94))',
  ),
  (
    '0002-hearty-chicken-noodle-soup.yaml',
    15,
    '1 medium russet potato (about 8 ounces), peeled and cut into ¾-inch cubes',
    2346401,
    '183.70',
    'from 8 ounce × 0.81 edible · approximate (USDA AH-102 item 2018: potatoes, raw whole, all samples → pared 81 % (61–94))',
  ),
  (
    '0021-rustic-potato-leek-soup.yaml',
    4,
    '1¾ pounds red potatoes (about 5 medium), peeled and cut into ¾-inch chunks',
    2346402,
    '642.97',
    'from 1 3/4 pound × 0.81 edible · approximate (USDA AH-102 item 2018: potatoes, raw whole, all samples → pared 81 % (61–94))',
  ),
  (
    '0021-rustic-potato-leek-soup.yaml',
    1,
    '4–5 pounds leeks, white and light green parts only, halved lengthwise, sliced crosswise 1 inch thick, and rinsed thoroughly (about 11 cups)',
    2709935,
    '898.11',
    // RE-PIN (M48): the basis names the range (4–5 pound, already read at its
    // midpoint; grams unchanged).
    'from 4–5 pound (the midpoint) × 0.44 edible · approximate (USDA AH-102 item 1412: leeks, raw → bulb and lower leaf 44 % (35–58))',
  ),
  (
    '0181-candied-sweet-potato-casserole.yaml',
    1,
    '5 pounds sweet potatoes (about 8 medium), peeled and cut into 1-inch cubes',
    168482,
    '1814.37',
    'from 5 pound × 0.80 edible · approximate (USDA AH-102 item 2496: sweetpotatoes, raw whole → hand or machine pared 80 % (69–91))',
  ),
  (
    '0963-pear-crisp.yaml',
    12,
    '3 pounds pears, peeled, halved, cored, each half quartered lengthwise, and each quarter cut in half crosswise',
    746773,
    '1061.41',
    'from 3 pound × 0.78 edible · approximate (USDA AH-102 item 1734: pears, raw whole → pared, cored flesh 78 % (40–88))',
  ),
  (
    '0964-roasted-pears-with-dried-apricots-and-pistachios.yaml',
    1,
    '4 ripe but firm Bosc pears (6 to 7 ounces each), peeled, halved, and cored',
    167778,
    '574.93',
    // RE-PIN (M48): the basis names the range (6–7 oz, already read at its
    // midpoint; grams unchanged).
    '4 × 184 g (printed 6–7 oz, the midpoint) × 0.78 edible · approximate (USDA AH-102 item 1734: pears, raw whole → pared, cored flesh 78 % (40–88))',
  ),
  (
    '0015-carrot-ginger-soup.yaml',
    7,
    '2 pounds carrots, peeled and sliced ¼ inch thick',
    2258586,
    '743.89',
    'from 2 pound × 0.82 edible · approximate (USDA AH-102 item 481: carrots without tops, raw → hand-scraped root 82 % (58–93))',
  ),
  (
    '0867-light-carrot-cake.yaml',
    11,
    '1 pound carrots (about 6 medium), peeled and grated (about 3 cups)',
    2258586,
    '371.95',
    'from 1 pound × 0.82 edible · approximate (USDA AH-102 item 481: carrots without tops, raw → hand-scraped root 82 % (58–93))',
  ),
  (
    '0473-tortilla-soup.yaml',
    5,
    '1 very large white onion (about 1 pound), peeled and quartered',
    1104962,
    '408.23',
    'from 1 pound × 0.90 edible · approximate (USDA AH-102 item 1568: onions, mature, all samples, raw whole → peeled 90 % (50–99))',
  ),
  (
    '1171-savoy-cabbage-soup-with-ham-rye-bread-and-fontina.yaml',
    7,
    '1 head savoy cabbage (1½ pounds), cored and cut into 1-inch pieces',
    170388,
    '632.76',
    'from 1 1/2 pound × 0.93 edible · approximate (USDA AH-102 item 440: cabbage, whole head, green, red or white (savoy not printed), raw → ready to cook, without core 93 % (91–96))',
  ),
  (
    '0568-indian-style-curry-with-potatoes-cauliflower-peas-and-chickpeas.yaml',
    10,
    '1¼ pounds cauliflower (½ medium head), trimmed, cored, and cut into 1-inch florets',
    2685573,
    '521.63',
    'from 1 1/4 pound × 0.92 edible · approximate (USDA AH-102 item 499: cauliflower, raw whole head → fully trimmed, head or flowerbud 92 % (83–100))',
  ),
  (
    '0412-butternut-squash-risotto.yaml',
    1,
    '1 medium butternut squash (about 2 pounds), peeled, seeded (reserve fibers and seeds), and cut into ½-inch cubes (about 3½ cups; see note)',
    2685570,
    '762.03',
    'from 2 pound × 0.84 edible · approximate (USDA AH-102 item 2459: butternut squash, raw whole → flesh 84 % (75–88))',
  ),
  (
    '0440-summer-vegetable-gratin.yaml',
    1,
    '1 pound zucchini, ends trimmed and cut crosswise into ¼-inch-thick slices',
    2685568,
    '421.84',
    'from 1 pound × 0.93 edible · approximate (USDA AH-102 item 2446: zucchini, raw whole → flesh and skin 93 % (86–98; ends 7))',
  ),
  (
    '0440-summer-vegetable-gratin.yaml',
    2,
    '1 pound yellow summer squash, ends trimmed and cut crosswise into ¼-inch-thick slices',
    2685569,
    '430.91',
    'from 1 pound × 0.95 edible · approximate (USDA AH-102 item 2444: summer squash, all samples, raw whole → flesh and skin 95 % (84–99))',
  ),
  (
    '0965-berry-fool.yaml',
    0,
    '2 quarts strawberries (about 2 pounds), washed, dried, and stemmed',
    2346409,
    '852.75',
    'from 2 pound × 0.94 edible · approximate (USDA AH-102 item 2473: strawberries, good quality, raw → flesh 94 % (86–99))',
  ),
  (
    '1172-nikujaga-beef-and-potato-stew.yaml',
    7,
    '1½ pounds Yukon Gold potatoes, unpeeled, cut into 1½-inch pieces',
    2346403,
    '680.39',
    'from 1 1/2 pound',
  ),
  (
    '0035-vegetable-broth-base.yaml',
    0,
    '2 leeks, white and light green parts only, chopped and washed thoroughly (2½ cups or 5 ounces)',
    2709935,
    '141.75',
    'from the printed weight',
  ),
  (
    '0035-vegetable-broth-base.yaml',
    1,
    '2 carrots, peeled and cut into ½-inch pieces (⅔ cup or 3 ounces)',
    2258586,
    '85.05',
    'from the printed weight',
  ),
  (
    '0020-sweet-potato-soup.yaml',
    4,
    '2 pounds sweet potatoes, peeled, halved lengthwise, and sliced ¼ inch thick, ¼ of peels reserved',
    168482,
    '907.18',
    'from 2 pound',
  ),
  // The line's own second clause eats the dark green parts: the whole leek
  // counts, no part yield (closer 2's veto).
  (
    '0339-spring-vegetable-pasta.yaml',
    0,
    '1½ pounds leeks, white and light green parts halved lengthwise, sliced ½ inch thick, and washed; 3 cups coarsely chopped dark green parts, washed',
    2709935,
    '680.39',
    'from 1 1/2 pound',
  ),
  (
    '0051-chopped-carrot-salad-with-fennel-orange-and-hazelnuts.yaml',
    7,
    '1 pound carrots, trimmed and cut into 1-inch pieces',
    2258586,
    '453.59',
    'from 1 pound',
  ),
  (
    '0862-applesauce-snack-cake.yaml',
    1,
    '¾ cup (2 ounces) dried apples, cut into ½-inch pieces',
    2709196,
    '56.70',
    'from 2 ounce',
  ),
  (
    '0017-creamy-cauliflower-soup.yaml',
    0,
    '1 head cauliflower (2 pounds)',
    2685573,
    '907.18',
    'from 2 pound',
  ),
  (
    '0684-creamy-herbed-spinach-dip.yaml',
    3,
    '3 scallions, white parts only, sliced thin',
    2709794,
    '16.65',
    '3 × 15 g each × 0.37 edible · approximate (USDA AH-102 item 1575: white part 37 % (22–50) of the whole scallion with rootlets)',
  ),
  (
    '0094-shepherds-pie.yaml',
    8,
    '8 scallions, green parts only, sliced thin',
    2709794,
    '70.80',
    '8 × 15 g each × 0.59 edible · approximate (derived from USDA AH-102 items 1573 and 1575: green tops and rootlets 63 % (50–78) less rootlets 4 % = 59 % of the whole scallion with rootlets)',
  ),
  (
    '0288-maryland-crab-cakes.yaml',
    1,
    '4 scallions, green parts only, minced (about ½ cup)',
    2709794,
    '50.00',
    '1/2 cup · USDA portion',
  ),
  (
    '0528-gongbao-jiding-sichuan-kung-pao-chicken.yaml',
    15,
    '5 scallions, white and light green parts only, cut into ½-inch pieces',
    2709794,
    '75.00',
    '5 × 15 g each',
  ),
  (
    '1078-bulgogi-korean-marinated-beef.yaml',
    4,
    '4 scallions, white and light green parts only, minced',
    2709794,
    '60.00',
    '4 × 15 g each',
  ),
  (
    '1078-bulgogi-korean-marinated-beef.yaml',
    21,
    '4 scallions, dark green parts only, cut into 1½-inch pieces',
    2709794,
    '60.00',
    '4 × 15 g each',
  ),
  (
    '0222-best-prime-rib.yaml',
    0,
    '1 (7-pound) first-cut beef standing rib roast (3 bones), meat removed from bones, bones reserved',
    168675,
    '2603.62',
    'from the printed weight × 0.82 edible · approximate (USDA AH-102 item 238: beef rib, retail ribs 11–12, raw → lean and fat meat 82 % (78–86; bones 18))',
  ),
  (
    '0538-chinese-style-barbecued-spareribs.yaml',
    9,
    '2 (2½- to 3-pound) racks St. Louis–style spareribs, cut into individual ribs',
    167853,
    // RE-PIN (M48): 1578.50 → 1446.96 g, the printed 2½–3 lb range at its
    // midpoint (was its top); the basis names the range.
    '1446.96',
    '2 × 1247 g (printed 2½–3 lb, the midpoint) × 0.58 edible · approximate (USDA AH-102 item 1925: pork spareribs, raw → lean and fat meat 58 % (43–71; bones 42))',
  ),
  (
    '0249-roast-fresh-ham.yaml',
    0,
    '1 (6- to 8-pound) bone-in fresh half ham with skin, preferably shank end, rinsed',
    168226,
    // RE-PIN (M48): 2830.41 → 2476.61 g, the printed 6–8 lb range at its
    // midpoint (was its top); the basis names the range.
    '2476.61',
    'from the printed weight (6–8 lb, the midpoint) × 0.78 edible · approximate (derived from USDA AH-102 item 1930: fresh ham shank half, raw → bones 22 %, so lean and fat meat 78 % (the printed row also trims the fat 18: lean 60 %))',
  ),
  (
    '0251-glazed-spiral-sliced-ham.yaml',
    0,
    '1 (7- to 10-pound) spiral-sliced bone-in half ham',
    169177,
    // RE-PIN (M48): 3175.14 → 2698.87 g, the printed 7–10 lb range at its
    // midpoint (was its top); the basis names the range.
    '2698.87',
    'from the printed weight (7–10 lb, the midpoint) × 0.70 edible · approximate (USDA AH-102 item 1937: cured ham, bone-in, rind-on, raw → lean and fat meat 70 % (60–78); the figure also removes rind 5 and excess fat 15 a spiral-sliced ham may no longer carry)',
  ),
  (
    '0228-roast-rack-of-lamb-with-roasted-red-pepper-relish.yaml',
    0,
    '2 racks of lamb (1¾ to 2 pounds each), fat trimmed to ⅛ to ¼ inch, rib bones frenched',
    172641,
    // RE-PIN (M48): 1324.49 → 1241.71 g, the printed 1¾–2 lb range at its
    // midpoint (was its top); the basis names the range.
    '1241.71',
    '2 × 850 g (printed 1¾–2 lb, the midpoint) × 0.73 edible · approximate (USDA AH-102 item 1364: lamb rib loin (rack), bone in, raw → lean and fat meat, slightly trimmed 73 % (61–88), as measured unfrenched; a frenched rack yields less)',
  ),
  (
    '0622-grilled-rack-of-lamb.yaml',
    5,
    '2 (1½- to 1¾-pound) racks of lamb (8 ribs each), frenched and trimmed',
    172641,
    // RE-PIN (M48): 1158.93 → 1076.15 g, the printed 1½–1¾ lb range at its
    // midpoint (was its top); the basis names the range.
    '1076.15',
    '2 × 737 g (printed 1½–1¾ lb, the midpoint) × 0.73 edible · approximate (USDA AH-102 item 1364: lamb rib loin (rack), bone in, raw → lean and fat meat, slightly trimmed 73 % (61–88), as measured unfrenched; a frenched rack yields less)',
  ),
  (
    '1192-braised-lamb-shanks-with-red-wine-and-herbes-de-provence.yaml',
    0,
    '6 (12- to 16-ounce) lamb shanks, trimmed',
    172513,
    // RE-PIN (M48): 1905.09 → 1666.95 g, the printed 12–16 oz range at its
    // midpoint (was its top); the basis names the range.
    '1666.95',
    '6 × 397 g (printed 12–16 oz, the midpoint) × 0.70 edible · approximate (USDA AH-102 item 1339: lamb foreleg (shank), choice, raw → lean and fat meat 70 % (bones 30; limited data))',
  ),
  (
    '1171-bulalo-hearty-beef-shank-and-vegetable-soup.yaml',
    2,
    '4 pounds beef shanks, trimmed',
    169441,
    '1106.76',
    'from 4 pound × 0.61 edible · approximate (USDA AH-102 item 228: beef shank, fore, raw → lean and fat meat 61 % (59–62; bones 39); weighed on a lean-only record)',
  ),
  (
    '0203-skillet-barbecued-pork-chops.yaml',
    1,
    '4 (8- to 10-ounce) bone-in rib loin pork chops, ¾ to 1 inch thick, trimmed of excess fat',
    168242,
    // RE-PIN (M48): 750.34 → 675.31 g, the printed 8–10 oz range at its
    // midpoint (was its top); the basis names the range.
    '675.31',
    '4 × 255 g (printed 8–10 oz, the midpoint) × 0.66 edible (USDA refuse)',
  ),
  (
    '0246-slow-roasted-pork-shoulder-with-peach-sauce.yaml',
    0,
    '1 (6- to 8-pound) bone-in pork butt',
    167849,
    // RE-PIN (M48): 2750.20 → 2406.42 g, the printed 6–8 lb range at its
    // midpoint (was its top); the basis names the range.
    '2406.42',
    'from the printed weight (6–8 lb, the midpoint) × 0.76 edible (USDA refuse)',
  ),
  (
    '0352-pasta-and-slow-simmered-tomato-sauce-with-meat.yaml',
    1,
    '1½ pounds pork spareribs or country-style ribs or beef short ribs, trimmed of fat',
    167895,
    '444.34',
    'from 1 1/2 pound × 0.65 edible (USDA refuse)',
  ),
  (
    '0089-braised-oxtails-with-white-beans-tomatoes-and-aleppo-pepper.yaml',
    0,
    '4 pounds oxtails, trimmed',
    2705843,
    '1024.00',
    'from 4 pound × 0.56 edible · approximate (yield of oxtails from FDC 2705843)',
  ),
  (
    '0616-barbecued-baby-back-ribs.yaml',
    2,
    '2 (2-pound) racks baby back or loin back ribs, trimmed, membrane removed',
    168299,
    '1184.89',
    '2 × 907 g (printed weight) × 0.65 edible · approximate (yield of pork ribs from FDC 167895)',
  ),
  (
    '0023-hearty-ham-and-split-pea-soup-with-potatoes.yaml',
    0,
    '1 (2½-pound) smoked bone-in picnic ham',
    168367,
    '859.44',
    'from the printed weight × 0.76 edible · approximate (yield of a bone-in pork roast from FDC 167849)',
  ),
  (
    '0273-braised-halibut-with-leeks-and-mustard.yaml',
    3,
    '1 pound leeks, white and light green parts only, halved lengthwise, sliced thin, and washed thoroughly',
    2709935,
    '199.58',
    'from 1 pound × 0.44 edible · approximate (USDA AH-102 item 1412: leeks, raw → bulb and lower leaf 44 % (35–58))',
  ),
];
