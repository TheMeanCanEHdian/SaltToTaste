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

/// Matcher v38: the v37 request groups after the owner's live step
/// (2026-10-04: 21 details and 5 searches), each rule enabled only where its
/// check passed on the record's real portions. Each row is a real corpus
/// line at the record, grams, bucket and basis the cache-only replay of
/// snapshot 16 derives at v38; the answers are copied from that snapshot
/// (tool/record_fdc_fixtures.dart --from-db), never live.
void main() {
  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v38');
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

  test('every enabled v38 rule lands its corpus line on its record, grams, '
      'bucket and basis', () async {
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

  test('the enabled tables are exactly the checked ones', () {
    expect(rankAsKeys, containsAll(_enabled));
    expect(rankAsKeys, isNot(anyElement(isIn(_dry))));
    expect(approximationRecords['ya cai'], 169891);
    // RE-PIN (M65 batch, v64, F5): R05 enabled — 167769, flagged.
    expect(approximationRecords['jarred morello cherries'], 167769);
    for (final item in ['fennel fronds', 'xanthan gum']) {
      expect(approximationRecords, isNot(contains(item)), reason: item);
    }
    expect(volumeSiblings[2747664], 168564);
    expect(volumeSiblings[2685573], 169986);
    expect(volumeSiblings[2644288], 173801);
    expect(volumeSiblings, isNot(contains(2515374)));
    // Whole farro keeps its v21 words (FDC's only farro is pearled).
    expect(rankAsFor('whole farro'), (
      query: 'farro dry',
      answer: 'whole farro',
    ));
  });

  test('each check gates its rule: a record without the portion sizes '
      'nothing, the checked record does', () async {
    Future<GramResolution?> on(String raw, int fdcId) async {
      final parsed = parseIngredientLine(raw);
      return resolveGrams(
        amounts: parsed.amounts,
        food: await FixtureProvider().food(fdcId),
        normalizedItem: normalizeItem(parsed.item ?? raw),
        raw: raw,
      );
    }

    // Bulgur: 2710820 publishes a 45 g racc only; 170688 a 140 g cup.
    expect(await on('1 cup medium-grind bulgur', 2710820), isNull);
    expect(
      (await on('1 cup medium-grind bulgur', 170688))?.grams,
      closeTo(140, 1e-9),
    );
    // A sibling sizes the volume only through its published cup: the
    // Foundation records alone weigh none.
    expect(await on('1 cup chopped Chioggia radicchio', 2747664), isNull);
    expect(
      (await on('1 cup chopped Chioggia radicchio', 168564))?.grams,
      closeTo(40, 1e-9),
    );
    expect(await on('⅔ cup canned chickpeas, rinsed', 2644288), isNull);
    expect(
      (await on('⅔ cup canned chickpeas, rinsed', 173801))?.grams,
      closeTo(101.333, 1e-3),
    );
  });

  test('the failed checks: each dry record publishes no portion its line '
      'needs (the portions FDC answered, snapshot 16)', () async {
    Future<List<(String?, String?, double)>> portions(int fdcId) async => [
      for (final p in (await FixtureProvider().food(fdcId))!.portions)
        (p.unit, p.description, p.gramWeight),
    ];
    // Pectin: no tsp/tbsp/cup.
    expect(await portions(168821), [(null, 'package (1.75 oz)', 50.0)]);
    // Fennel bulb: no tbsp/cup for fronds.
    expect(await portions(2709779), [
      (null, '1 fennel bulb', 235.0),
      (null, 'Quantity not specified', 25.0),
    ]);
    // Xanthan's stand-in and raw cashews: an ounce only.
    expect(await portions(169045), [(null, 'oz', 28.35)]);
    expect(await portions(170162), [(null, 'oz', 28.35)]);
    // Parsnips: no piece for "4 parsnips".
    expect(await portions(170417), [(null, 'cup slices', 133.0)]);
    // Kiwi: no 'large' for "2 large kiwis".
    expect(
      (await portions(2709239)).map((p) => p.$2),
      ['1 cup', '1 slice', '1 fruit', 'Quantity not specified'],
    );
    // Malted milk powder: a heaping-teaspoon serving, no level tbsp.
    expect(await portions(173220), [
      (null, 'serving (3 heaping tsp or 1 envelope)', 21.0),
    ]);
    // Nori: no sheet.
    expect(
      (await portions(2709988)).map((p) => p.$2),
      ['1 cup', '1 strip', 'Quantity not specified'],
    );
    // FDC has no freekeh and no candied ginger; its only farro is pearled.
    final provider = FixtureProvider();
    expect(await provider.search('freekeh'), isEmpty);
    expect(
      (await provider.search('candied ginger')).where(
        (c) =>
            c.description.toLowerCase().contains('ginger') &&
            RegExp(
              'candied|crystallized',
            ).hasMatch(c.description.toLowerCase()),
      ),
      isEmpty,
    );
    expect(
      [for (final c in await provider.search('farro')) c.fdcId],
      [2710828],
    );
  });
}

const List<String> _enabled = [
  'medium-grind bulgur',
  'medium-grain bulgur',
  'fine-grind bulgur',
  'diastatic malt powder',
  'roasted with salt pepitas',
  'oreo cookies',
  'turnip',
  'romaine lettuce leaves',
  'frisee',
  'cremini mushrooms',
  'ya cai',
  // RE-PIN (M65 batch, v64, F5): R05 enabled.
  'jarred morello cherries',
  // RE-PIN (M70 batch, v69, pF F1 / Q11): R02 enabled — the grams from the
  // Sure-Jell label (grams.dart 'fruit pectin', 'sure-jell';
  // nutrition_v69_test).
  'low- or no-sugar-needed fruit pectin',
  'sure-jell for low-sugar recipes',
  'sure-jell for less or no sugar needed recipes',
];

const List<String> _dry = [
  // RE-PIN (M70 batch, v69): R02's three pectin keys moved to [_enabled].
  'fennel fronds',
  // RE-PIN (M65 batch, v64, F5): 'jarred morello cherries' moved to
  // [_enabled] (grams `_fromContainers` skips the jar weight).
  'xanthan gum',
  'parsnips',
  'kiwis',
  'malted milk powder',
  'nori',
  'gim',
  'crystallized ginger',
  'cracked freekeh',
];

/// (corpus file, position, raw, fdc id, grams, bucket, basis).
const List<(String, int, String, int?, String?, String, String?)> _rows = [
  (
    '1176-red-lentil-kibbeh.yaml',
    7,
    '1 cup medium-grind bulgur',
    170688,
    '140.00',
    'counted',
    '1 cup · USDA portion',
  ),
  (
    '0793-authentic-baguettes-at-home.yaml',
    3,
    '1 teaspoon diastatic malt powder (optional)',
    169740,
    '3.38',
    'counted',
    '1 teaspoon · USDA portion',
  ),
  (
    '1071-watermelon-salad-with-cotija-and-serrano-chiles.yaml',
    8,
    '5 tablespoons chopped roasted, salted pepitas, divided',
    169415,
    '36.88',
    'counted',
    '5 tablespoon · USDA portion',
  ),
  (
    '0992-chocolate-cream-pie-with-oreo-cookie-crust.yaml',
    0,
    '16 Oreo cookies, broken into rough pieces',
    172718,
    '192.00',
    'counted',
    '16 × 12 g each',
  ),
  (
    '0030-farmhouse-vegetable-and-barley-soup.yaml',
    16,
    '1 turnip, peeled and cut into ¾-inch pieces',
    2709809,
    '120.00',
    'counted',
    '1 · USDA per-item weight',
  ),
  (
    '0487-chicken-enchiladas-with-red-chile-sauce.yaml',
    19,
    '5 romaine lettuce leaves, shredded',
    169247,
    '30.00',
    'counted',
    '5 · USDA per-item weight',
  ),
  (
    '0290-crab-towers-with-avocado-and-gazpacho-salsas.yaml',
    24,
    '1 cup frisée',
    168412,
    '50.00',
    'counted',
    '1 cup · USDA portion',
  ),
  (
    '0434-salade-lyonnaise.yaml',
    5,
    '1 head frisée (6 ounces), torn into bite-size pieces',
    168412,
    '170.10',
    'counted',
    'from 6 ounce',
  ),
  (
    '0654-grilled-shrimp-and-vegetable-kebabs.yaml',
    4,
    '24 cremini mushrooms, trimmed',
    168434,
    '480.00',
    'counted',
    "24 × 20 g each · approximate (FDC's 'piece whole' portion read as one cremini)",
  ),
  (
    '0017-mushroom-bisque.yaml',
    1,
    '8 ounces cremini mushrooms, trimmed',
    168434,
    '226.80',
    'counted',
    'from 8 ounce',
  ),
  (
    '1087-dan-dan-mian-sichuan-noodles-with-chili-sauce-and-pork.yaml',
    16,
    '⅓ cup ya cai',
    169891,
    '42.67',
    'counted',
    '1/3 cup · USDA portion · approximation (counted as Cabbage, mustard, salted)',
  ),
  (
    '1073-wheat-berry-salad-with-radicchio-dried-cherries-and-pecans.yaml',
    6,
    '1 cup chopped Chioggia radicchio',
    2747664,
    '40.00',
    'counted',
    '1 cup · USDA portion of "Radicchio, raw"',
  ),
  (
    '1121-hearty-green-salad-with-chickpeas-pickled-cauliflower-and-seared-halloumi.yaml',
    3,
    '2 cups (1-inch) cauliflower florets',
    2685573,
    '214.00',
    'counted',
    '2 cup · USDA portion of "Cauliflower, raw"',
  ),
  (
    '1121-hearty-green-salad-with-chickpeas-pickled-cauliflower-and-seared-halloumi.yaml',
    8,
    '⅔ cup canned chickpeas, rinsed',
    2644288,
    '101.33',
    'counted',
    '2/3 cup · USDA portion of "Chickpeas (garbanzo beans, bengal gram), mature seeds, canned, drained, rinsed in tap water"',
  ),
];
