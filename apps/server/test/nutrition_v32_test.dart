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

/// Matcher v32: the live step's rules, enabled (12 details and 2 searches
/// recorded 2026-10-03). Each row is a real corpus line at the record,
/// grams, bucket and basis the cache-only replay of the live-step copy
/// derives at v32; the answers are recorded from that copy
/// (tool/record_fdc_fixtures.dart --from-db), never live.
void main() {
  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v32');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    return db;
  }

  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  Future<void> expectRows(
    List<(String, int, String, int?, String?, String, String?)> rows,
  ) async {
    for (final (file, _, raw, fdcId, grams, bucket, basis) in rows) {
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
  }

  test('every enabled live-step rule lands its corpus line on its record, '
      'grams, bucket and basis', () async {
    await expectRows(_rows);
  });

  test('every row is a real corpus line at its position', () {
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

  test('the enabled tables are exactly the checked ones: the tamarind and '
      'egg siblings, the chorizo stand-in and the wheat-berry flag', () {
    expect(volumeSiblings[2709269], 167763);
    expect(volumeSiblings[748967], 171287);
    expect(rankAsKeys, containsAll(_enabled));
    expect(approximationRecords['cooked wheat berries'], 169744);
    expect(approximationRecords['spanish-style chorizo'], 174603);
    expect(approximationRecords['spanish-style chorizo sausage'], 174603);
    // Light sour cream is not flagged (light ≈ low-fat; the plan did not).
    expect(approximationRecords, isNot(contains('low-fat sour cream')));
  });

  test('each check gates its rule: a sibling sizes the volume only through '
      "its published volume portion; the portobello cap's Foundation "
      'detail publishes no per-item portion (v35 sizes it on 169255) — and '
      'the brioche buns count by the piece figure read from their '
      '"1 piece"', () async {
    Future<GramResolution?> on(String raw, int fdcId) async {
      final parsed = parseIngredientLine(raw);
      return resolveGrams(
        amounts: parsed.amounts,
        food: await FixtureProvider().food(fdcId),
        normalizedItem: normalizeItem(parsed.item ?? raw),
        raw: raw,
      );
    }

    // The FNDDS records alone weigh no volume; their siblings do.
    expect(await on('2 tablespoons tamarind paste', 2709269), isNull);
    expect(
      (await on('2 tablespoons tamarind paste', 167763))?.grams,
      closeTo(15, 1e-3),
    );
    expect(await on('2 tablespoons beaten egg', 748967), isNull);
    expect(
      (await on('2 tablespoons beaten egg', 171287))?.grams,
      closeTo(30.375, 1e-3),
    );
    // 2003598 publishes a racc portion only (v35: the cap ranks as 169255
    // and its '1 piece whole' piece figure); 2707682 "1 piece" 77 g and
    // "Quantity not specified" 70 g — the finder reads neither as one bun,
    // so the bun is the 'brioche bun' piece figure (77 g).
    expect(
      [
        for (final p in (await FixtureProvider().food(2003598))!.portions)
          (p.unit, p.description, p.gramWeight),
      ],
      [('racc', null, 85.0)],
    );
    final buns = await on('4 brioche buns, toasted', 2707682);
    expect(buns?.grams, closeTo(308, 1e-9));
    expect(
      buns?.basis,
      "4 × 77 g each · approximate (FDC's 1-piece portion read as one bun)",
    );
  });
}

const List<String> _enabled = [
  'chicken leg quarters',
  'bone-in chicken leg quarters',
  'oil-packed tuna',
  'sweetened cranberry juice',
  'dried onions',
  'bone-in half ham with skin',
  'cooked wheat berries',
  'jarred pimentos',
  'low-fat sour cream',
  'brioche buns',
  'spanish-style chorizo',
  'spanish-style chorizo sausage',
];

/// (corpus file, position, raw, fdc id, grams, bucket, basis).
const List<(String, int, String, int?, String?, String, String?)> _rows = [
  (
    '1081-crispy-fish-sandwiches-with-tartar-sauce.yaml',
    13,
    '4 brioche buns, toasted',
    2707682,
    '308.00',
    'counted',
    "4 × 77 g each · approximate (FDC's 1-piece portion read as one bun)",
  ),
  // v39 (Y1): this and 0454's leg quarters read the chicken-parts class
  // yield here, a line alone; in their recipes the steps discard the skin,
  // and Y3 moves both to 173619 (nutrition_v39_meat_test).
  (
    '0634-barbecued-pulled-chicken.yaml',
    3,
    '8 (14-ounce) chicken leg quarters, trimmed',
    172378,
    '1932.00',
    'counted',
    '8 × 397 g (printed weight) × 0.61 edible · approximate (yield of chicken parts from FDC 171447)',
  ),
  (
    '0454-french-style-chicken-and-stuffing-in-a-pot.yaml',
    16,
    '2 (12-ounce) bone-in chicken leg quarters, trimmed',
    172378,
    '414.00',
    'counted',
    '2 × 340 g (printed weight) × 0.61 edible · approximate (yield of chicken parts from FDC 171447)',
  ),
  (
    '0467-pan-bagnat-provencal-tuna-sandwich.yaml',
    14,
    '2 (6½-ounce) jars oil-packed tuna, drained',
    175157,
    '368.54',
    'counted',
    '2 × 184 g (printed weight)',
  ),
  (
    '0553-pad-thai.yaml',
    1,
    '2 tablespoons tamarind paste',
    2709269,
    '15.00',
    'counted',
    '2 tablespoon · USDA portion of "Tamarinds, raw"',
  ),
  (
    '0261-herb-crusted-salmon.yaml',
    4,
    '2 tablespoons beaten egg',
    748967,
    '30.38',
    'counted',
    '2 tablespoon · USDA portion of "Egg, whole, raw, fresh"',
  ),
  (
    '1181-jellied-cranberry-sauce.yaml',
    0,
    '4 cups sweetened cranberry juice',
    171903,
    '1012.00',
    'counted',
    '4 cup · USDA portion',
  ),
  (
    '0035-vegetable-broth-base.yaml',
    4,
    '3 tablespoons dried minced onions',
    170002,
    '15.00',
    'counted',
    '3 tablespoon · USDA portion',
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
    '1073-wheat-berry-salad-with-radicchio-dried-cherries-and-pecans.yaml',
    5,
    '2¾ cups cooked wheat berries',
    169744,
    '473.00',
    'counted',
    '2 3/4 cup · USDA portion · approximation (counted as Wheat, khorasan, cooked)',
  ),
  (
    '0101-arroz-con-pollo-latin-style-chicken-and-rice.yaml',
    16,
    '½ cup jarred pimentos, cut into 2 by ¼-inch strips',
    168559,
    '96.00',
    'counted',
    '1/2 cup · USDA portion',
  ),
  (
    '0846-fudgy-low-fat-brownies.yaml',
    7,
    '2 tablespoons low-fat sour cream',
    173443,
    '28.69',
    'counted',
    '2 tablespoon ≈ 30 mL',
  ),
  (
    '0033-caldo-verde.yaml',
    1,
    '12 ounces Spanish-style chorizo sausage, cut into ½-inch pieces',
    174603,
    '340.19',
    'counted',
    'from 12 ounce · approximation (counted as Salami, Italian, pork)',
  ),
  (
    '0106-paella-on-the-grill.yaml',
    15,
    '1 pound Spanish-style chorizo, cut into ½-inch pieces',
    174603,
    '453.59',
    'counted',
    'from 1 pound · approximation (counted as Salami, Italian, pork)',
  ),
];
