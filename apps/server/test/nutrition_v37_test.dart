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

import 'nutrition_v25_decided_test.dart' as d;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Matcher v37, the queue sweep part 1 (the planners' zero-request rows;
/// the owner's "go with your recommendations", 2026-10-04): the Z groups
/// and the C food-only fixes. Each row is a real corpus line at the record,
/// grams, bucket and basis the cache-only replay of snapshot 15 derives at
/// v37 (the line alone; its answers recorded from snapshot 15 with
/// tool/record_fdc_fixtures.dart --from-db).
void main() {
  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v37');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    return db;
  }

  IngredientLine lineOf(String raw) {
    // The corpus parse of the monkfish strips (an older extraction) left
    // "strips" in the item with no unit — the row v37's strip reader is
    // for; today's parser reads the unit. The library's line is pinned.
    if (raw == _monkfishZest) {
      return const IngredientLine(
        raw: _monkfishZest,
        item: '(2-inch) strips orange zest',
        amounts: [Amount(measure: Measure.count, quantity: '3', primary: true)],
      );
    }
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  test('each group lands its line on the record, grams, bucket and basis '
      'v37 derives', () async {
    for (final (file, _, raw, fdcId, grams, bucket, basis) in [
      ..._rows,
      ..._rowsS,
    ]) {
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
      if (fdcId == null) {
        expect(row.description, engineRuleNotes[4], reason: raw);
        expect(isEngineRuleRow(row), isTrue, reason: raw);
      }
    }
  });

  test('every row is a real corpus line at its position', () {
    for (final (file, position, raw, _, _, _, _) in [..._rows, ..._rowsS]) {
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

  // S11's key reaches the held `second_food` lines whose first food is the
  // chipotle (as v31's 'cornichons' reaches 0218's held line): the row moves
  // off the "Adobo, with noodles" dish onto the flagged stand-in and STAYS
  // held — the stand-in never counts a "plus … adobo sauce" line.
  test('S11 on the held second_food chipotle lines: the stand-in, '
      'still held, still out of the totals', () async {
    for (final (file, position, raw, grams) in _heldChipotle) {
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
      expect(row.fdcId, 171186, reason: raw);
      expect(row.status, 'auto', reason: raw);
      expect(row.hold, 'second_food', reason: raw);
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
        'check',
        reason: raw,
      );
      if (corpusAvailable) {
        final corpus = nutritionLines(loadCorpusRecipe(file))[position];
        expect(corpus.raw, raw, reason: file);
      }
    }
  });

  test('the flavourings class: each listed item counts 0 g on no food, '
      'an engine rule row', () async {
    for (final (_, _, raw) in _flavourings) {
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
      expect(row.fdcId, isNull, reason: raw);
      expect(row.description, engineRuleNotes[5], reason: raw);
      expect(row.status, 'confirmed', reason: raw);
      expect(row.grams, 0, reason: raw);
      expect(row.gramSource, 'unmeasured', reason: raw);
      expect(isEngineRuleRow(row), isTrue, reason: raw);
      expect(
        matchBucketFor(
          status: row.status,
          fdcId: row.fdcId,
          grams: row.grams,
          confidence: row.confidence,
          hold: row.hold,
          gramSource: row.gramSource,
        ).wire,
        'counted',
        reason: raw,
      );
      expect(
        gramBasisFor(db, line, row),
        'flavouring, no nutrients — counted as 0 g',
        reason: raw,
      );
    }
  });

  test('the flavourings class reaches exactly its 14 library lines; the '
      'held liquid smoke stays held (census of the corpus)', () {
    final reached = <String>[];
    final held = <String>[];
    for (final file in Directory(
      corpusRecipesDir,
    ).listSync().whereType<File>()) {
      if (!file.path.endsWith('.yaml')) {
        continue;
      }
      final recipe = RecipeYamlCodec.decode(file.readAsStringSync()).recipe;
      for (final (position, line) in nutritionLines(recipe).indexed) {
        final eaten = weighedLine(recipe, line);
        if (!isZeroNutrientFlavouring(normalizeItem(lineItemOf(eaten)))) {
          continue;
        }
        final name = file.uri.pathSegments.last;
        (heldMediumLine(recipe, eaten) ? held : reached).add(
          '$name|$position',
        );
      }
    }
    expect(
      reached..sort(),
      [
        for (final (file, position, _) in _flavourings) '$file|$position',
      ]..sort(),
    );
    // Indoor Pulled Chicken's "1 tablespoon liquid smoke, divided" is held
    // partial_pour_away (a person's call) — the class rule yields to it.
    expect(held, ['0129-indoor-pulled-chicken.yaml|3']);
    for (final (file, position, raw) in _flavourings) {
      expect(
        nutritionLines(loadCorpusRecipe(file))[position].raw,
        raw,
        reason: file,
      );
    }
  }, skip: skipIfNoCorpus);

  test(
    "the flavourings class yields to a held medium: 0129's divided "
    'liquid smoke, computed with its recipe, stays held on its record',
    () async {
      final (db, _, r) = await d.computed('0129-indoor-pulled-chicken.yaml');
      final row = d.rowOf(db, r, d.at(r, d.smoke0129));
      expect(
        (row.fdcId, row.status, row.hold),
        (
          167682,
          'auto',
          'partial_pour_away',
        ),
      );
    },
    skip: skipIfNoCorpus,
  );

  test('the request groups whose check failed on the live step stay dry '
      '(v38 enabled the rest: nutrition_v38_test.dart)', () {
    const dryRankAs = [
      'low- or no-sugar-needed fruit pectin',
      'sure-jell for low-sugar recipes',
      'sure-jell for less or no sugar needed recipes',
      'fennel fronds',
      'jarred morello cherries',
      'xanthan gum',
      'parsnips',
      'kiwis',
      'malted milk powder',
      'nori',
      'gim',
      'crystallized ginger',
      'cracked freekeh',
    ];
    for (final item in dryRankAs) {
      expect(rankAsFor(item), isNull, reason: item);
      expect(approximationRecords[item], isNull, reason: item);
    }
    // The v21 entry the farro search would replace, unchanged.
    expect(rankAsFor('whole farro'), (
      query: 'farro dry',
      answer: 'whole farro',
    ));
    expect(volumeSiblings[2515374], isNull);
  });

  test('the narrow readers reach only the lines they were built for '
      '(census of the corpus)', () {
    final clauseWeights = <String>[];
    final fragments = <String>[];
    for (final file in Directory(
      corpusRecipesDir,
    ).listSync().whereType<File>()) {
      if (!file.path.endsWith('.yaml')) {
        continue;
      }
      final recipe = RecipeYamlCodec.decode(file.readAsStringSync()).recipe;
      for (final line in nutritionLines(recipe)) {
        final eaten = weighedLine(recipe, line);
        final item = normalizeItem(lineItemOf(eaten));
        if (isContinuationFragment(
          line.raw,
          hasAmounts: line.amounts.isNotEmpty,
          normalizedItem: item,
        )) {
          fragments.add(line.raw);
        }
        // A weight read with no food, no weight amount, no paren and no
        // hyphenated "4-pound" (an older reader's) is the comma clause's.
        final grams = resolveGrams(
          amounts: line.amounts,
          food: null,
          normalizedItem: item,
          raw: line.raw,
        );
        if (grams?.source == GramSource.weight &&
            line.amounts.every((a) => a.measure != Measure.weight) &&
            !line.raw.contains('(') &&
            !RegExp(r'\d-(pound|ounce)').hasMatch(line.raw)) {
          clauseWeights.add(line.raw);
        }
      }
    }
    expect(fragments..sort(), [
      '(about ¾ cup)',
      'lengthwise, seeded, and sliced thin on bias',
    ]);
    expect(clauseWeights..sort(), [
      '1 center-cut beef tenderloin roast, 3 pounds trimmed weight, 12 to 13 inches long and 4 to 4½ inches in diameter',
      '1 whole side salmon fillet, about 3½ pounds, white belly fat trimmed',
    ]);
  }, skip: skipIfNoCorpus);
}

const String _monkfishZest = '3 (2-inch) strips orange zest, divided';

/// (corpus file, position, raw, fdc id, grams, bucket, basis).
const List<(String, int, String, int?, String?, String, String?)> _rows = [
  // Z1: today's right record, lifted over the gate.
  (
    '0963-caramelized-pears-with-blue-cheese-and-black-peppercaramel-sauce.yaml',
    2,
    '3 ripe, firm pears, halved, cored, and ¼ inch trimmed off the bottom',
    169118,
    '534.00',
    'counted',
    '3 · USDA per-item weight',
  ),
  // Z2: the record lifted, the comma clause's printed weight read.
  (
    '0258-broiled-salmon-with-mustard-and-crisp-dilled-crust.yaml',
    3,
    '1 whole side salmon fillet, about 3½ pounds, white belly fat trimmed',
    2706284,
    '1587.57',
    'counted',
    'from the printed weight',
  ),
  // Z3: rank-as onto right cached records.
  (
    '0775-almond-granola-with-dried-fruit.yaml',
    7,
    '2 cups raisins or other dried fruit, chopped',
    2709212,
    '320.00',
    'counted',
    '2 cup · USDA portion',
  ),
  (
    '0299-classic-grilled-cheese-sandwiches.yaml',
    0,
    '3 ounces cheese (preferably mild cheddar) or a combination of cheeses, shredded on the large holes of a box grater (about ¾ cup)',
    328637,
    '85.05',
    'counted',
    'from 3 ounce',
  ),
  (
    '0245-slow-cooker-pork-loin-with-cranberries-and-orange.yaml',
    5,
    '½ cup juice and 3 (3-inch-long) strips zest from 1 orange',
    169098,
    '124.00',
    'counted',
    '1/2 cup · USDA portion',
  ),
  // The strip the corpus left in the item reaches the v31 strip figure.
  (
    '1184-monkfish-tagine.yaml',
    0,
    _monkfishZest,
    169103,
    '4.80',
    'counted',
    '3 × 2 inch × 0.8 g per inch · approximate (ATK: 10 (3-inch) strips orange peel ≈ ¼ cup)',
  ),
  // Z4 (the owner's answer): table salt, counted.
  (
    '0664-bread-and-butter-pickles.yaml',
    3,
    '2 tablespoons canning and pickling salt',
    173468,
    '36.08',
    'counted',
    '2 tablespoon ≈ 30 mL',
  ),
  // Z5: densities ATK prints, labelled.
  (
    '0005-best-beef-stew.yaml',
    14,
    '1½ cups frozen pearl onions, thawed',
    170412,
    '170.10',
    'counted',
    '1 1/2 cup ≈ 355 mL · approximate (ATK: 8 ounces frozen pearl onions ≈ 2 cups)',
  ),
  (
    '0026-harira-moroccan-lentil-and-chickpea-soup.yaml',
    15,
    '1 cup brown lentils, picked over and rinsed',
    2644283,
    '198.45',
    'counted',
    '1 cup ≈ 237 mL · approximate (ATK: 1 cup lentils = 7 ounces)',
  ),
  (
    '0776-strawberries-and-grapes-with-balsamic-and-red-wine-reduction.yaml',
    7,
    '1 quart strawberries, hulled and halved lengthwise (about 4 cups)',
    2346409,
    '566.99',
    'counted',
    '1 quart ≈ 946 mL · approximate (ATK: 8 cups strawberries = 40 ounces)',
  ),
  (
    '0044-mediterranean-chopped-salad.yaml',
    1,
    '1 pint grape tomatoes, quartered (about 1½ cups)',
    321360,
    '272.16',
    'counted',
    '1 pint ≈ 473 mL · approximate (ATK: 12 ounces cherry or grape tomatoes ≈ 2½ cups)',
  ),
  // A record with a cup of its own keeps it: the v37 'lentil' figure is a
  // fallback only (the first replay moved this line to 148.83 g).
  (
    '1176-red-lentil-kibbeh.yaml',
    9,
    '¾ cup dried red lentils, picked over and rinsed',
    174284,
    '144.00',
    'counted',
    '3/4 cup · USDA portion',
  ),
  // Z6: ATK densities, flagged.
  (
    '0303-turkey-tetrazzini.yaml',
    17,
    '4 cups leftover cooked boneless turkey or chicken meat, cut into ¼-inch pieces',
    331960,
    '680.39',
    'counted',
    '4 cup ≈ 946 mL · approximate (ATK: 6 ounces cooked chicken, torn = 1 cup)',
  ),
  (
    '0777-classic-strawberry-jam.yaml',
    2,
    '1¼ cups peeled and shredded Granny Smith apple (1 large apple)',
    1750342,
    '283.49',
    'counted',
    '1 1/4 cup ≈ 296 mL · approximate (ATK: 1½ pounds Granny Smith apples, peeled, cored, shredded = 3 cups)',
  ),
  // Z7: ATK's printed equivalences.
  (
    '0394-pepperoni-pan-pizza.yaml',
    4,
    '1 envelope instant yeast',
    2710005,
    '7.10',
    'counted',
    '1 envelope ≈ 2.25 teaspoon (ATK: 1 envelope = 2¼ teaspoons) · 2.25 teaspoon ≈ 11 mL',
  ),
  // The volume amount wins where the line prints one, as before.
  (
    '0809-multigrain-bread.yaml',
    6,
    '1 envelope (2¼ teaspoons) instant or rapid-rise yeast',
    2710005,
    '7.10',
    'counted',
    '2 1/4 teaspoon ≈ 11 mL',
  ),
  (
    '0331-spaghetti-puttanesca.yaml',
    5,
    '4 teaspoons minced anchovy fillets (about 8 fillets)',
    2706232,
    '32.00',
    'counted',
    '(about 8 fillets) · 8 · USDA per-item weight',
  ),
  (
    '1129-beef-wellington.yaml',
    0,
    '1 center-cut beef tenderloin roast, 3 pounds trimmed weight, 12 to 13 inches long and 4 to 4½ inches in diameter',
    171748,
    '1360.78',
    'counted',
    'from the printed weight',
  ),
  // Z8, Z9 (the owner's 34.0 g), Z13: piece figures, flagged.
  (
    '1155-champagne-cocktail.yaml',
    0,
    '1 sugar cube',
    746784,
    '2.20',
    'counted',
    '1 × 2.2 g each · approximate (ATK: ¾ cup sugar makes 64 cubes)',
  ),
  (
    '0652-grilled-bacon-wrapped-scallops.yaml',
    1,
    '24 large sea scallops, tendons removed',
    2747667,
    '816.00',
    'counted',
    '24 × 34 g each · approximate (ATK: 1½ pounds large sea scallops ≈ 16 to 24)',
  ),
  (
    '0506-pork-and-cabbage-dumplingswor-tip.yaml',
    16,
    '24 round gyoza wrappers',
    172802,
    '192.00',
    'counted',
    "24 round × 8.0 g each · approximate (FDC's 3½-inch square wonton wrapper, ATK's substitute)",
  ),
  // Z10: FDC's own portions — a volume sibling, a baguette's inch.
  (
    '0093-cuban-style-picadillo.yaml',
    17,
    '½ cup pimento-stuffed green olives, chopped coarse',
    332791,
    '67.50',
    'counted',
    '1/2 cup · USDA portion of "Olives, green"',
  ),
  (
    '1093-vegan-baja-style-cauliflower-tacos.yaml',
    4,
    '1 tablespoon minced jalapeño chile',
    2747661,
    '9.38',
    'counted',
    '1 tablespoon · USDA portion of "Peppers, jalapenos"',
  ),
  (
    '0279-garlicky-shrimp-with-buttered-bread-crumbs.yaml',
    0,
    '1 (3-inch) piece baguette, cut into small pieces',
    2707610,
    '44.19',
    'counted',
    '1 piece × 3 inch × 14.73 g per inch · approximate (FDC: 1 baguette (about 22" long) = 324 g)',
  ),
  // Z11, Z15: FDC densities on stand-in records, flagged.
  (
    '0729-shakshuka-eggs-in-spicy-tomato-and-roasted-red-pepper-sauce.yaml',
    2,
    '3 cups jarred roasted red peppers, divided',
    2258590,
    '576.00',
    'counted',
    '3 cup ≈ 710 mL · approximate (pimento density, FDC 168559 cup 192 g)',
  ),
  (
    '0495-chili-con-carne.yaml',
    11,
    '1 cup canned crushed tomatoes or plain tomato sauce',
    2685581,
    '245.00',
    'counted',
    '1 cup ≈ 237 mL · approximate (tomato sauce density, FDC 170054 cup 245 g)',
  ),
  // Z12: parse fixes onto the existing small-measure path.
  (
    '0149-easier-fried-chicken.yaml',
    2,
    'Dash of hot sauce',
    2710093,
    '0.33',
    'counted',
    'dash ≈ 1/16 tsp (USDA tbsp portion)',
  ),
  (
    '1075-espinacas-con-garbanzos-andalusian-spinach-and-chickpeas.yaml',
    10,
    '1 small pinch saffron',
    170934,
    '0.04',
    'counted',
    '1 pinch ≈ 1/16 tsp (USDA tsp portion)',
  ),
  // Z14: a split line's tail, counted with the line above.
  (
    '0028-hearty-minestrone.yaml',
    5,
    '(about ¾ cup)',
    null,
    null,
    'counted',
    null,
  ),
  (
    '0559-bun-cha.yaml',
    3,
    'lengthwise, seeded, and sliced thin on bias',
    null,
    null,
    'counted',
    null,
  ),
  // C: 0 g lines, the food right.
  (
    '0284-brazilian-shrimp-and-fish-stew-moqueca.yaml',
    8,
    'Table alt and pepper',
    173468,
    '0.00',
    'counted',
    'no amount on the line — counted as 0 g',
  ),
  (
    '1133-chicken-francese.yaml',
    8,
    '⅓ cup extra-virgin olive oil for frying',
    748608,
    '0.00',
    'counted',
    'discarded in cooking — counted as 0 g',
  ),
  (
    '0582-tacos-al-carbon-grilled-steak-tacos.yaml',
    10,
    'Mexican crema',
    2346387,
    '0.00',
    'counted',
    'no amount on the line — counted as 0 g · approximation (counted as Cream, sour, full fat)',
  ),
  (
    '0492-carnitas-mexican-pulled-pork.yaml',
    11,
    'Minced white or red onion',
    1104962,
    '0.00',
    'counted',
    'no amount on the line — counted as 0 g',
  ),
  (
    '0422-chicken-canzanese.yaml',
    10,
    '12 whole fresh sage leaves',
    170935,
    '0.00',
    'counted',
    '12 leaves — a fresh leaf is not measured, counted as 0 g',
  ),
  // The lemon twist's food is the peel; no printed size, so it stays in
  // review.
  (
    '1155-champagne-cocktail.yaml',
    3,
    '1 lemon twist',
    167749,
    null,
    'no_grams',
    null,
  ),
];

/// v37 S groups: one real line per flagged stand-in (and per rank-as key),
/// at the record, grams, bucket and basis the replay of snapshot 15
/// derives.
const List<(String, int, String, int?, String?, String, String?)> _rowsS = [
  // S1 mirin on the sweet dessert wine.
  (
    '0259-miso-marinated-salmon.yaml',
    3,
    '3 tablespoons mirin',
    2710692,
    '45.00',
    'counted',
    '3 tablespoon · USDA portion · approximation (counted as Wine, dessert, sweet)',
  ),
  // S2 gochujang (and the paste line) on sriracha.
  (
    '0512-vegetable-bibimbap-with-nurungji.yaml',
    5,
    '¼ cup gochujang',
    171186,
    '78.00',
    'counted',
    '1/4 cup · USDA portion · approximation (counted as Sauce, hot chile, sriracha)',
  ),
  (
    '1094-kimchi-bokkeumbap-kimchi-fried-rice.yaml',
    8,
    '4 teaspoons gochujang paste',
    171186,
    '26.00',
    'counted',
    '4 teaspoon · USDA portion · approximation (counted as Sauce, hot chile, sriracha)',
  ),
  // S3 doenjang on SR miso (never FNDDS 2707439, which has no detail).
  (
    '1078-bulgogi-korean-marinated-beef.yaml',
    5,
    '¼ cup doenjang',
    172442,
    '68.75',
    'counted',
    '1/4 cup · USDA portion · approximation (counted as Miso)',
  ),
  // S4 galangal on ginger root, at ginger's per-inch figure.
  (
    '0011-guay-tiew-tom-yum-goong-thai-hot-and-sour-noodle-soup-with-shrimp.yaml',
    5,
    '1 (2-inch) piece fresh galangal, peeled and sliced into ¼-inch-thick rounds',
    169231,
    '16.00',
    'counted',
    "1 piece × 2 inch × 8 g per inch · approximate (ginger's figure (ATK's substitute for galangal)) · approximation (counted as Ginger root, raw)",
  ),
  // S5 culantro on cilantro; S6 alcaparrado on green olives.
  (
    '1123-pastelon-puerto-rican-sweet-plantain-and-picadillo-casserole.yaml',
    3,
    '¼ cup fresh culantro, chopped coarse',
    169997,
    '4.00',
    'counted',
    '1/4 cup · USDA portion · approximation (counted as Coriander (cilantro) leaves, raw)',
  ),
  (
    '1123-pastelon-puerto-rican-sweet-plantain-and-picadillo-casserole.yaml',
    13,
    '2 tablespoons pitted alcaparrado',
    2710089,
    '16.88',
    'counted',
    '2 tablespoon · USDA portion · approximation (counted as Olives, green)',
  ),
  // S7 nonpareils on granulated sugar, by sugar's own portion.
  (
    '1163-struffoli-neapolitan-honey-balls.yaml',
    9,
    '2 tablespoons multicolored nonpareils, plus extra for garnish',
    746784,
    '23.75',
    'counted',
    '2 tablespoon · USDA portion · approximation (counted as Sugars, granulated)',
  ),
  // S8 five-spice (both keys) on pumpkin pie spice.
  (
    '0538-chinese-barbecued-pork.yaml',
    6,
    '1 teaspoon Chinese five-spice powder',
    171332,
    '1.70',
    'counted',
    '1 teaspoon · USDA portion · approximation (counted as Spices, pumpkin pie spice)',
  ),
  (
    '0522-fried-brown-rice-with-pork-and-shrimp.yaml',
    5,
    '⅛ teaspoon five-spice powder',
    171332,
    '0.21',
    'counted',
    '1/8 teaspoon · USDA portion · approximation (counted as Spices, pumpkin pie spice)',
  ),
  // S9 garam masala on curry powder.
  (
    '1096-chana-masala.yaml',
    12,
    '1½ teaspoons garam masala',
    170924,
    '3.00',
    'counted',
    '1 1/2 teaspoon · USDA portion · approximation (counted as Spices, curry powder)',
  ),
  // S10 Sichuan and pink peppercorns on black pepper.
  (
    '0534-mapo-tofu-sichuan-braised-tofu-with-beef.yaml',
    0,
    '1 tablespoon Sichuan peppercorns',
    170931,
    '8.72',
    'counted',
    '1 tablespoon ≈ 15 mL · approximation (counted as Spices, pepper, black)',
  ),
  (
    '0651-grilled-scallops-with-fennel-and-orange-salad-for-two.yaml',
    6,
    '2 teaspoons pink peppercorns, crushed',
    170931,
    '5.82',
    'counted',
    '2 teaspoon ≈ 10 mL · approximation (counted as Spices, pepper, black)',
  ),
  // S11 chipotle in adobo on sriracha; the count line gets the food only.
  (
    '1208-albondigas-en-chipotle.yaml',
    10,
    '1 tablespoon minced canned chipotle chile in adobo sauce',
    171186,
    '19.50',
    'counted',
    '1 tablespoon · USDA portion · approximation (counted as Sauce, hot chile, sriracha)',
  ),
  (
    '0473-tortilla-soup.yaml',
    11,
    '1 chipotle chile in adobo sauce, plus up to 1 tablespoon adobo sauce',
    171186,
    null,
    'no_grams',
    null,
  ),
  // S12 white fish fillets on Atlantic cod, the printed weight.
  (
    '0274-pan-roasted-thick-cut-fish-fillets.yaml',
    0,
    '4 (6 to 8-ounce) skinless white fish fillets, 1 to 1½ inches thick',
    2684444,
    '793.79',
    'counted',
    // RE-PIN (M48): the basis names the range (6–8 oz, already read at its
    // midpoint; grams unchanged).
    '4 × 198 g (printed 6–8 oz, the midpoint) · approximation (counted as Fish, cod, Atlantic, wild caught, raw)',
  ),
  // S13 mixed fresh herbs (both keys) on fresh parsley.
  (
    '0288-maryland-crab-cakes.yaml',
    2,
    '1 tablespoon chopped fresh herb, such as cilantro, dill, basil, or parsley',
    170416,
    '3.75',
    'counted',
    '1 tablespoon · USDA portion · approximation (counted as Parsley, fresh)',
  ),
  (
    '0716-quinoa-pilaf-with-herbs-and-lemon.yaml',
    5,
    '3 tablespoons chopped fresh herbs',
    170416,
    '11.25',
    'counted',
    '3 tablespoon · USDA portion · approximation (counted as Parsley, fresh)',
  ),
  // S14 crème fraîche on heavy cream at its 1.01 g/mL; the tartiflette's
  // amount-less line (C) on the same record.
  (
    '0127-coq-au-riesling.yaml',
    14,
    '¼ cup crème fraîche',
    2346386,
    '59.74',
    'counted',
    '1/4 cup ≈ 59 mL · approximate (heavy cream density) · approximation (counted as Cream, heavy)',
  ),
  (
    '1134-tartiflette-french-potato-and-cheese-gratin.yaml',
    10,
    'Crème fraîche (optional)',
    2346386,
    '0.00',
    'counted',
    'no amount on the line — counted as 0 g · approximation (counted as Cream, heavy)',
  ),
];

/// The class ruling's 14 library lines (corpus file, position, raw).
/// The held `second_food` lines S11's key reaches (D1 of the v37 verify):
/// (file, position, raw, grams).
const List<(String, int, String, String)> _heldChipotle = [
  (
    '0582-tacos-al-carbon-grilled-steak-tacos.yaml',
    1,
    '2 teaspoons minced canned chipotle chile in adobo sauce, plus 1 teaspoon adobo sauce, divided',
    '13.00',
  ),
  (
    '0482-tinga-de-pollo-shredded-chicken-tacos.yaml',
    7,
    '2 tablespoons minced canned chipotle chile in adobo sauce plus 2 teaspoons adobo sauce',
    '39.00',
  ),
];

const List<(String, int, String)> _flavourings = [
  ('0203-skillet-barbecued-pork-chops.yaml', 15, '1 teaspoon liquid smoke'),
  ('0493-sous-vide-cochinita-pibil.yaml', 10, '1 teaspoon liquid smoke'),
  (
    '0246-indoor-pulled-pork-with-sweet-and-tangy-barbecue-sauce.yaml',
    2,
    '3 tablespoons plus 2 teaspoons liquid smoke',
  ),
  ('0613-kansas-city-sticky-ribs.yaml', 19, '¼ teaspoon liquid smoke'),
  ('0540-pork-lo-mein.yaml', 6, '¼ teaspoon liquid smoke (optional)'),
  (
    '0538-chinese-style-barbecued-spareribs.yaml',
    7,
    '1 teaspoon red food coloring (optional)',
  ),
  ('1198-meringue-christmas-trees.yaml', 4, '8–10 drops green food coloring'),
  ('0664-bread-and-butter-pickles.yaml', 11, '½ teaspoon Ball Pickle Crisp'),
  ('1155-champagne-cocktail.yaml', 1, '¼ teaspoon Angostura bitters'),
  ('0927-classic-creme-brulee.yaml', 3, '1 vanilla bean, halved lengthwise'),
  ('0925-panna-cotta.yaml', 3, '1 vanilla bean, halved lengthwise'),
  (
    '0926-buttermilk-vanilla-panna-cotta-with-berries-and-honey.yaml',
    4,
    '1 vanilla bean',
  ),
  ('0942-homemade-vanilla-ice-cream.yaml', 0, '1 vanilla bean'),
  ('0928-sous-vide-creme-brulee.yaml', 0, '½ vanilla bean'),
];
