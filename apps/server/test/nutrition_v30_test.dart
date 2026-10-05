// Real corpus lines wrap across adjacent literals; the table keeps each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Matcher v30: the rulings already made. Q7 (2026-10-01): bone-in parts
/// on their raw record at the printed gross weight, labelled approximate
/// (18 rank-as items; flap meat and turkey drumsticks/thighs and leg
/// quarters flagged approximations; "rib slabs" buys bone). Q6: the dried
/// New Mexican and guajillo pods at ATK's printed 7.1 g, flagged. Every
/// row is a real corpus line at the record, grams, bucket and basis the
/// cache-only replay of snapshot 13 derives; the answers are recorded from
/// snapshot 13 (tool/record_fdc_fixtures.dart --from-db), never live.
void main() {
  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v30');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    return db;
  }

  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  // One line alone, computed on the recorded answers in a fresh database.
  Future<(SaltDatabase, IngredientMatchRow)> computeLine(
    IngredientLine line,
  ) async {
    final db = tempDb()..upsertSource(slug: 'src', name: 'Test', type: 'book');
    final recipe = Recipe(
      id: 'r',
      title: 'r',
      slug: 'r',
      source: const RecipeSource(name: 'Test', type: 'book'),
      ingredients: [
        IngredientGroup(items: [line]),
      ],
    );
    db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'hr');
    await matchAndCompute(db, FixtureProvider(), recipe);
    return (db, db.ingredientMatchesFor('r').single);
  }

  test('every ruled line lands on its record, grams, bucket and basis; the '
      'fresh ham (counted since v32), the arbol chile (0.5 g) and the '
      'mild dried chile (an inch figure, not ruled) do not move', () async {
    for (final (_, _, raw, fdcId, grams, bucket, basis) in _rows) {
      final line = lineOf(raw);
      final (db, row) = await computeLine(line);
      expect(row.fdcId, fdcId, reason: raw);
      expect(row.grams?.toStringAsFixed(2), grams, reason: raw);
      expect(
        matchBucketFor(
          status: row.status,
          fdcId: row.fdcId,
          grams: row.grams,
          confidence: row.confidence,
          hold: row.hold,
          gramSource: row.gramSource,
        ).wire,
        bucket,
        reason: raw,
      );
      expect(gramBasisFor(db, line, row), basis, reason: raw);
    }
  });

  test('every row is a real corpus line at its position, parsed as the '
      'corpus stores it', () {
    for (final (file, position, raw, _, _, _, _) in _rows) {
      final line = nutritionLines(loadCorpusRecipe(file))[position];
      expect(line.raw, raw, reason: file);
      expect(lineOf(raw).amounts, line.amounts, reason: raw);
      expect(
        normalizeItem(lineItemOf(lineOf(raw))),
        normalizeItem(lineItemOf(line)),
        reason: raw,
      );
    }
  }, skip: skipIfNoCorpus);

  test('the Q7 bone-in items are rank-as items; the fresh ham too since '
      'v32', () {
    expect(rankAsKeys, containsAll(_boneInItems));
    expect(rankAsKeys, contains('bone-in half ham with skin'));
    expect(
      {
        for (final item in _boneInItems)
          if (approximationRecords.containsKey(item))
            item: approximationRecords[item],
      },
      {
        'beef flap meat': 2727574,
        'turkey drumsticks and thighs': 171533,
        'turkey leg quarters': 171533,
      },
    );
  });

  test('"rib slabs" buys bone (Q7: the rib-slab line says approximate)', () {
    expect(
      buysRefuse(
        '3–4 beef rib slabs (3 to 4 ribs per slab, about 5 pounds total), '
        'trimmed',
      ),
      isTrue,
    );
  });
}

const List<String> _boneInItems = [
  '7-pound first-cut beef standing rib roast',
  'first-cut beef standing rib roast',
  'beef flap meat',
  'beef rib slabs',
  'bone-in boston butt roast',
  'boneless pork butt roast with at least 1 4-inch-thick fat cap',
  'bone-in chicken parts',
  'bone-in skin-on chicken parts',
  'boneless long-cut beef shanks',
  'butterflied leg of lamb',
  'shank end boneless leg of lamb',
  'cod or other thick whitefish fillets',
  'flat-iron steaks',
  'frozen butterball or kosher turkey',
  'salmon steaks',
  'skin-on side of salmon',
  'turkey drumsticks and thighs',
  'turkey leg quarters',
];

/// (corpus file, position, raw, fdc id, grams, bucket, basis) — the
/// cache-only replay of snapshot 13 at v30, every line verbatim.
const List<(String, int, String, int, String?, String, String?)> _rows = [
  (
    '1080-sous-vide-prime-rib-with-mint-persillade.yaml',
    0,
    '1 7-pound first-cut beef standing rib roast (3 bones)',
    168675,
    '2406.42',
    'counted',
    'from the printed weight × 0.76 edible · approximate (yield of a bone-in roast (the pork butt figure) from FDC 167849)',
  ),
  (
    '0222-best-prime-rib.yaml',
    0,
    '1 (7-pound) first-cut beef standing rib roast (3 bones), meat removed from bones, bones reserved',
    168675,
    '2406.42',
    'counted',
    'from the printed weight × 0.76 edible · approximate (yield of a bone-in roast (the pork butt figure) from FDC 167849)',
  ),
  (
    '0536-crispy-orange-beef.yaml',
    0,
    '1½ pounds beef flap meat, trimmed',
    2727574,
    '680.39',
    'counted',
    'from 1 1/2 pound · approximation (counted as Beef, top sirloin steak, raw)',
  ),
  (
    '0618-texas-style-barbecued-beef-ribs.yaml',
    17,
    '3–4 beef rib slabs (3 to 4 ribs per slab, about 5 pounds total), trimmed',
    173405,
    '1490.90',
    'counted',
    'from the printed weight × 0.66 edible · approximate (yield of bony beef, lamb and veal from FDC 167895 and 168242 (the median))',
  ),
  (
    '0609-barbecued-pulled-pork.yaml',
    0,
    '1 (6- to 8-pound) bone-in Boston butt roast',
    167849,
    '2750.20',
    'counted',
    'from the printed weight × 0.76 edible (USDA refuse)',
  ),
  (
    '1147-fresh-bulk-sausage.yaml',
    0,
    '2 pounds boneless pork butt roast with at least ¼-inch-thick fat cap',
    167849,
    '907.18',
    'counted',
    'from 2 pound',
  ),
  (
    '0633-smoked-chicken.yaml',
    2,
    '6 pounds bone-in chicken parts (breasts, thighs, and/or drumsticks), trimmed',
    171447,
    '1656.00',
    'counted',
    'from 6 pound × 0.61 edible · approximate (yield of chicken parts from FDC 171447)',
  ),
  (
    '0149-easier-fried-chicken.yaml',
    7,
    '3½ pounds bone-in, skin-on chicken parts (breasts, thighs, and drumsticks, or a mix, with breasts cut in half), trimmed of excess fat',
    171447,
    '966.00',
    'counted',
    'from 3 1/2 pound × 0.61 edible · approximate (yield of chicken parts from FDC 171447)',
  ),
  (
    '0131-spice-rubbed-picnic-chicken.yaml',
    0,
    '5 pounds bone-in, skin-on chicken parts (split breasts, thighs, drumsticks, or a mix, with breasts cut into 3 pieces or halved if small), trimmed of excess fat and skin',
    171447,
    '1380.00',
    'counted',
    'from 5 pound × 0.61 edible · approximate (yield of chicken parts from FDC 171447)',
  ),
  (
    '0007-alcatra-portuguese-style-beef-stew.yaml',
    0,
    '3 pounds boneless long-cut beef shanks',
    169441,
    '1360.78',
    'counted',
    'from 3 pound',
  ),
  (
    '0230-roast-butterflied-leg-of-lamb-with-coriander-cumin-and-mustard-seeds.yaml',
    0,
    '1 (6- to 8-pound) butterflied leg of lamb',
    174315,
    '3628.74',
    'counted',
    'from the printed weight',
  ),
  (
    '0620-grilled-lamb-kebabs.yaml',
    1,
    '1 (2¼-pound) shank end boneless leg of lamb, trimmed and cut into 1-inch chunks',
    174315,
    '1020.58',
    'counted',
    'from the printed weight',
  ),
  (
    '0255-fish-and-chips.yaml',
    9,
    '1½ pounds cod or other thick whitefish fillets, such as hake or haddock, cut into eight 3-ounce pieces about 1 inch thick',
    2684444,
    '680.39',
    'counted',
    'from 1 1/2 pound',
  ),
  (
    '0595-grill-smoked-herb-rubbed-flat-iron-steaks.yaml',
    5,
    '4 (6- to 8-ounce) flat-iron steaks, ¾ to 1 inch thick, trimmed',
    172125,
    '907.18',
    'counted',
    '4 × 227 g (printed weight)',
  ),
  (
    '0155-roast-turkey-for-a-crowd.yaml',
    6,
    '1 (18- to 22-pound) frozen Butterball or kosher turkey, fully thawed; giblets, neck, and tailpiece removed and reserved for gravy',
    171081,
    '6072.00',
    'counted',
    'from the printed weight × 0.61 edible · approximate (yield of a whole turkey (interim: the chicken figure) from FDC 171447)',
  ),
  (
    '0257-pan-seared-salmon-steaks.yaml',
    1,
    '4 (8- to 10-ounce) salmon steaks, ¾ to 1 inch thick',
    2706284,
    '1133.98',
    'counted',
    '4 × 283 g (printed weight)',
  ),
  (
    '0264-roasted-whole-side-of-salmon.yaml',
    0,
    '1 (4-pound) skin-on side of salmon, pin bones removed and belly fat trimmed',
    2706284,
    '1814.37',
    'counted',
    'from the printed weight',
  ),
  (
    '0172-braised-turkey.yaml',
    3,
    '4 pounds turkey drumsticks and thighs, trimmed',
    171533,
    '1104.00',
    'counted',
    'from 4 pound × 0.61 edible · approximate (yield of turkey parts (the chicken figure) from FDC 171447) · approximation (counted as Turkey, retail parts, thigh, meat and skin, raw)',
  ),
  (
    '0162-slow-roasted-turkey-with-gravy.yaml',
    7,
    '4 pounds turkey drumsticks and thighs, trimmed',
    171533,
    '1104.00',
    'counted',
    'from 4 pound × 0.61 edible · approximate (yield of turkey parts (the chicken figure) from FDC 171447) · approximation (counted as Turkey, retail parts, thigh, meat and skin, raw)',
  ),
  (
    '0163-turkey-and-gravy-for-a-crowd.yaml',
    12,
    '4 (1½- to 2-pound) turkey leg quarters, trimmed',
    171533,
    '2208.00',
    'counted',
    '4 × 907 g (printed weight) × 0.61 edible · approximate (yield of turkey parts (the chicken figure) from FDC 171447) · approximation (counted as Turkey, retail parts, thigh, meat and skin, raw)',
  ),
  (
    '0249-roast-fresh-ham.yaml',
    0,
    '1 (6- to 8-pound) bone-in fresh half ham with skin, preferably shank end, rinsed',
    168226,
    '2750.20',
    'counted',
    'from the printed weight × 0.76 edible · approximate (yield of a bone-in pork roast from FDC 167849)',
  ),
  (
    '0490-spicy-pork-tacos-al-pastor.yaml',
    0,
    '10 large dried guajillo chiles, wiped clean',
    168570,
    '71.00',
    'counted',
    '10 × 7.1 g each · approximate (ATK: 4 large dried guajillo chiles ≈ 1 ounce)',
  ),
  (
    '0498-best-vegetarian-chili.yaml',
    3,
    '2 dried New Mexican chiles',
    168570,
    '14.20',
    'counted',
    '2 × 7.1 g each · approximate (ATK: 3 medium New Mexican pods ≈ ¾ ounce)',
  ),
  (
    '0550-thai-chicken-curry-with-potatoes-and-peanuts.yaml',
    0,
    '6 dried New Mexican chiles',
    168570,
    '42.60',
    'counted',
    '6 × 7.1 g each · approximate (ATK: 3 medium New Mexican pods ≈ ¾ ounce)',
  ),
  (
    '0587-grilled-steak-with-new-mexican-chile-rub.yaml',
    6,
    '2 dried New Mexican chiles, stemmed, seeded, and flesh torn into ½-inch pieces',
    168570,
    '14.20',
    'counted',
    '2 × 7.1 g each · approximate (ATK: 3 medium New Mexican pods ≈ ¾ ounce)',
  ),
  (
    '1095-goan-pork-vindaloo.yaml',
    0,
    '4 large dried guajillo chiles, wiped clean, stemmed, seeded, and torn into 1-inch pieces (about 1 ounce)',
    168570,
    '28.35',
    'counted',
    'from 1 ounce',
  ),
  (
    '0008-our-favorite-chili.yaml',
    3,
    '2–4 dried de árbol chiles, stemmed, seeded, and split into 2 pieces',
    168570,
    '1.50',
    'counted',
    '2–4 · USDA per-item weight',
  ),
  (
    '0281-spanish-style-garlic-shrimp.yaml',
    5,
    '1 (2-inch) piece mild dried chile, such as New Mexico, roughly broken, seeds included',
    168570,
    null,
    'no_grams',
    null,
  ),
];
