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

/// Matcher v39, the produce half of edible yields part 1 (the owner's
/// ruling 2026-10-05 on prep39/plan.md Q6, Q8, Q9): D1 canned coconut milk
/// on SR 170173 (rank-as), C1 small/large onions, carrots and round
/// tomatoes on their SR size portions, C3 the plum tomato at 62 g, A3 the
/// banana's "Peeled" portion and T1 drained canned tomatoes × 0.54 — the
/// two prep-loss shapes, read only on a printed weight with the word after
/// the first top-level comma. Each row is a real corpus line at the record,
/// grams, bucket and basis the cache-only replay of snapshot 16 derives at
/// v39; the answers are copied from snapshot 16
/// (tool/record_fdc_fixtures.dart --from-db).
void main() {
  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v39p');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    return db;
  }

  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  test('D1, C1, C3, A3, T1 and their non-trips, line by line', () async {
    for (final (file, _, raw, fdcId, grams, bucket, basis) in _single) {
      final line = lineOf(raw);
      final db = tempDb()
        ..upsertSource(slug: 'src', name: 'Test', type: 'book');
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
      final row = db.ingredientMatchesFor('r').single;
      expect(row.fdcId, fdcId, reason: '$file: $raw');
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

  test(
    'every row is a real corpus line at its position',
    skip: skipIfNoCorpus,
    () {
      for (final (file, position, raw, _, _, _, _) in _single) {
        final line = nutritionLines(loadCorpusRecipe(file))[position];
        expect(line.raw, raw, reason: file);
        expect(lineOf(raw).amounts, line.amounts, reason: raw);
      }
    },
  );

  test(
    'a prep-loss word in the head names a prepared product: no loss',
    () async {
      // No corpus banana or drained-can line puts its word before the first
      // comma: both are synthesized (a stated negative-path exception) from
      // ultimate-banana-bread|3 and hearty-lentil-soup|4.
      final provider = FixtureProvider();
      Future<GramResolution> read(String raw, int fdcId) async {
        final parsed = parseIngredientLine(raw);
        return resolveGrams(
          amounts: parsed.amounts,
          food: await provider.food(fdcId),
          normalizedItem: normalizeItem(parsed.item ?? raw),
          raw: raw,
        )!;
      }

      final banana = await read(
        '6 peeled large very ripe bananas (about 2¼ pounds)',
        1105314,
      );
      expect(banana.grams.toStringAsFixed(2), '1020.58');
      expect(banana.source, GramSource.weight);
      final tomatoes = await read(
        '1 (14.5-ounce) can drained diced tomatoes',
        333281,
      );
      expect(tomatoes.grams.toStringAsFixed(2), '411.07');
      // The share ATK prints: 2 (28-ounce) cans whole tomatoes, drained, 3
      // cups juice reserved.
      expect(drainedTomatoShare, 0.54);
    },
  );

  test('D1 reads only the coconut-milk items it names', () {
    // "¼ cup heavy cream or coconut milk" (0568|15, its first option) and
    // "1 cup cream of coconut" (0831|0) are other items: unchanged in the
    // replay (2346386 59.74 g; 2707571 240 g).
    for (final item in [
      'coconut milk',
      'unsweetened coconut milk',
      'regular or light coconut milk',
    ]) {
      expect(rankAsFor(item)?.answer, 'canned coconut milk', reason: item);
    }
    expect(rankAsFor('heavy cream or coconut milk'), isNull);
    expect(rankAsFor('cream of coconut'), isNull);
    expect(rankAsFor('canned coconut milk'), isNull);
  });
}

/// (corpus file, position, raw, fdc id, grams, bucket, basis).
const List<(String, int, String, int?, String?, String, String?)> _single = [
  // D1
  (
    '0548-thai-green-curry-with-chicken-broccoli-and-mushrooms.yaml',
    0,
    '2 (14-ounce) cans unsweetened coconut milk, not shaken',
    170173,
    '793.79',
    'counted',
    '2 × 397 g (printed weight)',
  ),
  // D1
  (
    '0621-grilled-beef-satay.yaml',
    0,
    '¾ cup regular or light coconut milk',
    170173,
    '182.76',
    'counted',
    '3/4 cup ≈ 177 mL',
  ),
  // D1n
  (
    '0560-banh-xeo-sizzling-vietnamese-crepes.yaml',
    18,
    '⅓ cup canned coconut milk',
    170173,
    '81.23',
    'counted',
    '1/3 cup ≈ 79 mL',
  ),
  // D1n
  // D1n
  (
    '0831-triple-coconut-macaroons.yaml',
    0,
    '1 cup cream of coconut',
    2707571,
    '240.00',
    'counted',
    '1 cup · USDA portion',
  ),
  // C1
  (
    '0446-potato-casserole-with-bacon-and-caramelized-onion.yaml',
    1,
    '1 large onion, halved and sliced thin',
    790646,
    '150.00',
    'counted',
    '1 × 150 g each',
  ),
  // C1
  (
    '0474-black-bean-soup.yaml',
    9,
    '1 large carrot, chopped',
    2258586,
    '72.00',
    'counted',
    '1 × 72 g each',
  ),
  // C1
  (
    '0557-bo-luc-lac-shaking-beef.yaml',
    12,
    '1 small red onion, sliced thin',
    790577,
    '70.00',
    'counted',
    '1 × 70 g each',
  ),
  // C1
  (
    '0082-simple-pot-roast.yaml',
    4,
    '1 small carrot, chopped medium',
    2258586,
    '50.00',
    'counted',
    '1 × 50 g each',
  ),
  // C1
  (
    '1146-pa-amb-tomaquet-catalan-tomato-bread.yaml',
    0,
    '2 large ripe tomatoes, halved through equator',
    170457,
    '364.00',
    'counted',
    '2 × 182 g each',
  ),
  // C3
  (
    '0471-classic-guacamole.yaml',
    5,
    '1 plum tomato, cored, seeded, and cut into ⅛-inch dice',
    2709719,
    '62.00',
    'counted',
    '1 × 62 g each',
  ),
  // C3
  (
    '1075-espinacas-con-garbanzos-andalusian-spinach-and-chickpeas.yaml',
    11,
    '2 small plum tomatoes, halved lengthwise, flesh shredded on large holes of box grater and skins discarded',
    2709719,
    '124.00',
    'counted',
    '2 × 62 g each',
  ),
  // C1n
  (
    '0496-white-chicken-chili.yaml',
    6,
    '2 medium onions, cut into large pieces (about 2 cups)',
    790646,
    '220.00',
    'counted',
    '2 × 110 g each',
  ),
  // C1n
  (
    '0082-simple-pot-roast.yaml',
    5,
    '1 small celery rib, chopped medium',
    2346405,
    '40.00',
    'counted',
    '1 × 40 g each',
  ),
  // C1n
  (
    '0000-italian-style-turkey-meatballs.yaml',
    9,
    '1 large egg, lightly beaten',
    748967,
    '50.00',
    'counted',
    '1 × 50 g each',
  ),
  // C1n
  (
    '0079-skillet-jambalaya.yaml',
    11,
    '1 pound large shrimp (31 to 40 per pound), peeled and deveined (see this page)',
    175179,
    '453.59',
    'counted',
    'from 1 pound',
  ),
  // C1n
  (
    '0028-hearty-minestrone.yaml',
    9,
    '½ small head green cabbage, halved, cored, and cut into ½-inch pieces (about 2 cups)',
    2346407,
    '159.00',
    'counted',
    '2 cup · USDA portion of "Cabbage, raw"',
  ),
  // A3
  (
    '0754-ultimate-banana-bread.yaml',
    3,
    '6 large very ripe bananas (about 2¼ pounds), peeled',
    1105314,
    '690.00',
    'counted',
    '6 × 115 g (USDA "Peeled" portion)',
  ),
  // A3
  (
    '0027-mulligatawny-soup.yaml',
    14,
    '1 medium very ripe banana (about 5 ounces), peeled, or 1 medium red potato (about 5 ounces), peeled and cut into 1-inch chunks',
    1105314,
    '115.00',
    'counted',
    '1 × 115 g (USDA "Peeled" portion)',
  ),
  // A3n
  (
    '0753-classic-banana-bread.yaml',
    4,
    '3 very ripe bananas, mashed well (about 1½ cups)',
    1105314,
    '354.00',
    'counted',
    '3 × 118 g each',
  ),
  // A3n
  (
    '0959-bananas-foster.yaml',
    5,
    '2 large, firm, ripe bananas, peeled and quartered',
    1105314,
    '236.00',
    'counted',
    '2 × 118 g each',
  ),
  // A3n
  (
    '1104-banana-muffins-with-coconut-and-macadamia.yaml',
    6,
    '4–5 very ripe large bananas, peeled and mashed (2 cups)',
    1105314,
    '531.00',
    'counted',
    '4–5 × 118 g each',
  ),
  // T1
  (
    '0024-hearty-lentil-soup.yaml',
    4,
    '1 (14.5-ounce) can diced tomatoes, drained',
    333281,
    '221.98',
    'counted',
    'from the printed weight × 0.54 drained · approximate (ATK: 2 (28-ounce) cans whole tomatoes, drained, give 3 cups juice)',
  ),
  // T1n
  (
    '0398-ultimate-grilled-pizza.yaml',
    6,
    '1 (14-ounce) can whole peeled plum tomatoes, drained, juice reserved',
    2685578,
    '396.89',
    'counted',
    'from the printed weight',
  ),
];
