// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v49 (batch M47, records and published figures; matcherVersion
// 48; prep47 design_v2 §1 (B) and §2 "M47", decided under the owner's
// 2026-10-07 standing authorization; zero requests): shell-on shrimp at
// AH-102 item 2333 and mussels by weight on raw SR 174216 at item 1531;
// kiwi 75 g a fruit (FNDDS 2709239); a zest over a tablespoon plus juice as
// two parts unless a step strains it, a zest plus a COUNT of lemons the
// fruit; canned beans whose liquid is eaten on their solids-and-liquids
// records; jarred hot cherry peppers pickled, herbes de Provence on dried
// thyme and halloumi on Monterey (flagged), frozen raspberries on 2709282,
// red curry paste and Old Bay `no_match` with no record; tapioca starch at
// ATK's 3 ounces per ¾ cup; the pasta, leek and rhubarb nutrient siblings;
// the pasta e fagioli line on SR 169736 by rank-as (the owner's ruling).
// Every value is the v49 replay's row (rp43 on snapshot 21), each line
// computed ALONE in its recipe (steps and prep notes kept) on recorded real
// FDC answers (FixtureProvider; entries added --from-db from snapshot 21),
// never the network.

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/services/nutrition_composite.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

const _shrimpOn =
    'from 1 pound × 0.81 edible · approximate (USDA AH-102 item 2333: shrimp, headless, in shell → shelled, deveined 81 % (77–82))';
const _musselOn =
    ' × 0.29 edible · approximate (USDA AH-102 item 1531: mussels, whole → drained solids, raw 29 % (25–33); the liquor in the pot is not counted)';

/// (file, section index or null, position, raw, fdc id, grams, basis,
/// parts as "fdc:grams|…" or '').
typedef _Pin = (
  String file,
  int? section,
  int position,
  String raw,
  int fdcId,
  String grams,
  String basis,
  String parts,
);

const List<_Pin> _pins = [
  // 1. SHELLFISH (Q11).
  (
    '0429-garlicky-shrimp-tomato-and-white-bean-stew.yaml',
    null,
    2,
    '1 pound large shell-on shrimp (26 to 30 per pound), peeled, deveined (see this page), and tails removed, shells reserved',
    175179,
    '367.41',
    _shrimpOn,
    '',
  ),
  (
    '0280-garlicky-roasted-shrimp-with-parsley-and-anise.yaml',
    null,
    1,
    '2 pounds shell-on jumbo shrimp (16 to 20 per pound)',
    175179,
    '734.82',
    'from 2 pound × 0.81 edible · approximate (USDA AH-102 item 2333: shrimp, headless, in shell → shelled, deveined 81 % (77–82))',
    '',
  ),
  (
    '0294-oven-steamed-mussels.yaml',
    null,
    6,
    '4 pounds mussels, scrubbed and debearded',
    174216,
    '526.17',
    'from 4 pound$_musselOn',
    '',
  ),
  // Eaten shell and all (its prep note, v39): gross, no AH-102 row.
  (
    '0279-crispy-salt-and-pepper-shrimp.yaml',
    null,
    0,
    '1½ pounds shell-on shrimp (31 to 40 per pound)',
    175179,
    '680.39',
    'from 1 1/2 pound · approximate (gross weight, no USDA refuse portion)',
    '',
  ),
  // A count: the FNDDS meat portion, never moved.
  (
    '0105-paella.yaml',
    null,
    14,
    '1 dozen mussels, scrubbed and debearded',
    2706350,
    '180.00',
    '12 · USDA per-item weight',
    '',
  ),
  // 2. KIWI (Q12): unsized unflagged; "large" flagged.
  (
    '0940-pavlova-with-fruit-and-whipped-cream.yaml',
    1,
    1,
    '2 kiwis, peeled, quartered lengthwise, and sliced crosswise ¼ inch thick (about 1 cup)',
    2710831,
    '150.00',
    '2 × 75 g each',
    '',
  ),
  (
    '0997-fresh-fruit-tart-with-pastry-cream.yaml',
    null,
    9,
    '2 large kiwis, peeled, halved lengthwise, and sliced ⅜ inch thick',
    2710831,
    '150.00',
    '2 × 75 g each · approximate (one fruit, FNDDS 2709239: 75 g; no large size published)',
    '',
  ),
  // 3. CITRUS (Q6): over a tablespoon, two parts unless a step strains it.
  (
    '0536-crispy-orange-beef.yaml',
    null,
    3,
    '10 (3-inch) strips orange peel, sliced thin lengthwise (¼ cup), plus ¼ cup juice (2 oranges)',
    169103,
    '86.00',
    'zest 1/4 cup · USDA portion + juice 1/4 cup · USDA portion',
    '169103:24.00|169098:62.00',
  ),
  (
    '0142-skillet-roasted-chicken-in-lemon-sauce.yaml',
    null,
    8,
    '4 teaspoons grated lemon zest plus ¼ cup juice (2 lemons)',
    167749,
    '68.92',
    'zest 4 teaspoon · USDA portion + juice 1/4 cup ≈ 59 mL',
    '167749:8.00|167747:60.92',
  ),
  // "Immediately pour the mixture through a fine-mesh strainer": juice only.
  (
    '0994-lemon-tart.yaml',
    null,
    4,
    '¼ cup grated zest plus ⅔ cup juice from 4 to 5 lemons',
    167747,
    '162.46',
    '2/3 cup ≈ 158 mL · juice only (the zest is strained out)',
    '',
  ),
  // S7 widened [F17]: a zest plus a COUNT of lemons reads the fruit.
  (
    '0654-grilled-swordfish-skewers-with-tomato-scallion-caponata.yaml',
    null,
    7,
    '1 tablespoon grated lemon zest, plus 2 lemons, halved',
    2709168,
    '116.00',
    '2 × 58 g each · the fruit only (the zest is dropped)',
    '',
  ),
  (
    '0680-fava-beans-with-artichokes-asparagus-and-peas.yaml',
    null,
    0,
    '2 teaspoons grated lemon zest, plus 1 lemon',
    2709168,
    '58.00',
    '1 × 58 g each · the fruit only (the zest is dropped)',
    '',
  ),
  // At most a tablespoon: the checkpoint-5 rule, unchanged.
  (
    '0021-super-greens-soup-with-lemon-tarragon-cream.yaml',
    null,
    3,
    '¼ teaspoon finely grated lemon zest plus ½ teaspoon juice',
    167747,
    '2.54',
    '1/2 teaspoon ≈ 2 mL · juice only (the zest is dropped)',
    '',
  ),
  (
    '0005-avgolemono-greek-chicken-and-rice-soup-with-egg-and-lemon.yaml',
    null,
    2,
    '12 (3-inch) strips lemon zest plus 6 tablespoons juice, plus extra juice for seasoning (3 lemons)',
    167747,
    '91.38',
    '6 tablespoon ≈ 89 mL · juice only (the zest is dropped)',
    '',
  ),
  // 4. CANNED BEANS (Q14, Q14b).
  (
    '0340-pasta-e-ceci-pasta-with-chickpeas.yaml',
    null,
    10,
    '2 (15-ounce) cans chickpeas (do not drain)',
    175206,
    '850.49',
    '2 × 425 g (printed weight)',
    '',
  ),
  (
    '1096-chana-masala.yaml',
    null,
    11,
    '2 (15-ounce) cans chickpeas, undrained',
    175206,
    '850.49',
    '2 × 425 g (printed weight)',
    '',
  ),
  (
    '1075-espinacas-con-garbanzos-andalusian-spinach-and-chickpeas.yaml',
    null,
    1,
    '2 (15-ounce) cans chickpeas (1 can drained, 1 can undrained)',
    2644288,
    '665.50',
    "2 × 425 g (printed weight) × 0.565 drained on half the cans · approximate (drained weight: FDC's canned chickpea pair, 253 g of 448 g) · the undrained can on its solids-and-liquids record",
    '2644288:240.26|175206:425.24',
  ),
  (
    '0009-best-ground-beef-chili.yaml',
    null,
    17,
    '1 (15-ounce) can pinto beans',
    175201,
    '425.24',
    'from the printed weight (the steps add the beans and their liquid)',
    '',
  ),
  // Navy: no solids-and-liquids detail cached — the whole can on the
  // drained record, said.
  (
    '0029-soupe-au-pistou-provencal-vegetable-soup.yaml',
    null,
    14,
    '1 (15-ounce) can cannellini or navy beans',
    2644286,
    '425.24',
    'from the printed weight (the steps add the beans and their liquid) · approximate (no solids-and-liquids record for this bean: the drained-and-rinsed record for the whole can)',
    '',
  ),
  // Cannellini: no twin — the half rule and the reserved liquid unchanged.
  (
    '0429-garlicky-shrimp-tomato-and-white-bean-stew.yaml',
    null,
    8,
    '2 (15-ounce) cans cannellini beans (1 can drained and rinsed, 1 can left undrained)',
    2644287,
    '684.64',
    "2 × 425 g (printed weight) × 0.610 drained on half the cans · approximate (drained weight: the median of FDC's three canned-bean pairs, 0.610)",
    '',
  ),
  (
    '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml',
    null,
    9,
    '2 (15-ounce) cans cannellini beans, drained with liquid reserved, rinsed',
    2644287,
    '850.49',
    '2 × 425 g (printed weight)',
    '',
  ),
  // 5. RECORDS (Q15 i–iii, Q26).
  (
    '0066-pasta-frittata-with-sausage-and-hot-peppers.yaml',
    null,
    3,
    '3 tablespoons coarsely chopped jarred hot cherry peppers',
    2710095,
    '28.13',
    '3 tablespoon · USDA portion',
    '',
  ),
  // The Thai chiles still read the raw hot pepper (rank-as since v49).
  (
    '0510-goi-cuo-n-vietnamese-summer-rolls.yaml',
    null,
    0,
    '1 Thai chile, sliced thin',
    2709798,
    '2.00',
    '1 × 2 g each',
    '',
  ),
  (
    '0455-chicken-provencal.yaml',
    null,
    13,
    '1 teaspoon herbes de Provence (optional)',
    170938,
    '1.00',
    '1 teaspoon · USDA portion · approximation (counted as Spices, thyme, dried)',
    '',
  ),
  (
    '0925-panna-cotta.yaml',
    0,
    0,
    '24 ounces (about 5 cups) frozen raspberries',
    2709282,
    '680.39',
    'from 24 ounce',
    '',
  ),
  (
    '1174-seared-halloumi-and-vegetable-salad-bowl.yaml',
    null,
    5,
    '6 ounces halloumi cheese, sliced into ½-inch-thick slabs',
    2705720,
    '170.10',
    'from 6 ounce · approximation (counted as Cheese, Monterey)',
    '',
  ),
  (
    '1121-hearty-green-salad-with-chickpeas-pickled-cauliflower-and-seared-halloumi.yaml',
    null,
    5,
    '4 ounces halloumi cheese, cut into 4 slices',
    2705720,
    '113.40',
    'from 4 ounce · approximation (counted as Cheese, Monterey)',
    '',
  ),
  // 6. TAPIOCA (Q5): by volume at ATK's print; the weighed blend line and
  // instant tapioca unchanged.
  (
    '0788-pao-de-queijo-brazilian-cheese-bread.yaml',
    null,
    0,
    '3 cups tapioca starch',
    169717,
    '340.19',
    "3 cup ≈ 710 mL · approximate (ATK's printed 3 ounces per ¾ cup) · approximation (counted as Tapioca, pearl, dry)",
    '',
  ),
  (
    '0393-the-best-gluten-free-pizza.yaml',
    0,
    3,
    '3 ounces (¾ cup) tapioca starch',
    169717,
    '85.05',
    'from 3 ounce · approximation (counted as Tapioca, pearl, dry)',
    '',
  ),
  (
    '0979-blueberry-pie.yaml',
    null,
    5,
    '2 tablespoons instant tapioca, ground',
    169717,
    '19.00',
    '2 tablespoon · USDA portion',
    '',
  ),
  // 7. PASTA (Q15 iv, the owner's 2026-10-07 ruling): a rank-as onto SR
  // 169736 itself (the Foundation record's sibling), grams unchanged.
  (
    '0404-pasta-e-fagioli-italian-pasta-and-bean-soup.yaml',
    null,
    14,
    '8 ounces small pasta such as ditalini, tubetini, conchiglietti, or orzo',
    169736,
    '226.80',
    'from 8 ounce',
    '',
  ),
  // 8. NUTRIENT SIBLINGS (Q13): grams unchanged.
  (
    '0021-rustic-potato-leek-soup.yaml',
    null,
    1,
    '4–5 pounds leeks, white and light green parts only, halved lengthwise, sliced crosswise 1 inch thick, and rinsed thoroughly (about 11 cups)',
    2709935,
    '898.11',
    'from 4–5 pound (the midpoint) × 0.44 edible · approximate (USDA AH-102 item 1412: leeks, raw → bulb and lower leaf 44 % (35–58)) · nutrients of "Leeks, (bulb and lower leaf-portion), raw"',
    '',
  ),
  (
    '0966-rhubarb-fool.yaml',
    null,
    0,
    '2¼ pounds rhubarb, trimmed and cut into 6-inch lengths',
    2709268,
    '1020.58',
    'from 2 1/4 pound · nutrients of "Rhubarb, raw"',
    '',
  ),
];

/// Q23 (a): the curry paste and Old Bay lines — no_match, no record.
const List<(String, int?, int, String)> _vetoed = [
  (
    '0517-thai-style-chicken-soup.yaml',
    null,
    11,
    '2 teaspoons Thai red curry paste',
  ),
  (
    '0601-grilled-glazed-pork-tenderloin-roast.yaml',
    2,
    1,
    '1 tablespoon red curry paste',
  ),
  ('0288-maryland-crab-cakes.yaml', null, 3, '1½ teaspoons Old Bay seasoning'),
  (
    '0657-grilled-corn-with-flavored-butter.yaml',
    4,
    3,
    '1½ teaspoons Old Bay seasoning',
  ),
];

void main() {
  group('matcher v49 (batch M47)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('salt-v49-');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath)
        ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider();
    });

    tearDown(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    Recipe stored(String file) {
      final recipe = loadCorpusRecipe(file);
      db.upsertRecipe(recipe, sourceSlug: _source, contentHash: recipe.id);
      return db.recipeByIdOrSlug(recipe.id)!.recipe;
    }

    var alones = 0;

    /// [file]'s line at [position] — of its section number [section], else
    /// a main line — ALONE in its recipe (its steps and prep notes kept; a
    /// section line under the section's own key), computed on the
    /// fixtures; its one row, the recipe it was computed in and the line.
    Future<(IngredientMatchRow, Recipe, IngredientLine)> at(
      String file,
      int? section,
      int position,
    ) async {
      final host = stored(file);
      final from = section == null
          ? host
          : sectionOf(
              host,
              sectionKeyOf(host.id, host.subsections[section].title ?? ''),
            )!;
      final line = nutritionLines(from)[position];
      final id = 'r${alones++}';
      final one = section == null
          ? host.copyWith(
              id: id,
              slug: id,
              ingredients: [
                IngredientGroup(items: [line]),
              ],
            )
          : from.copyWith(
              ingredients: [
                IngredientGroup(items: [line]),
              ],
            );
      if (section == null) {
        db.upsertRecipe(one, sourceSlug: _source, contentHash: id);
      }
      expect(await matchAndCompute(db, provider, one), isNull);
      return (db.ingredientMatchesFor(one.id).single, one, line);
    }

    String partsText(IngredientMatchRow row) => [
      for (final p in partsOf(row.parts))
        '${p.fdcId}:${p.grams.toStringAsFixed(2)}',
    ].join('|');

    test('each line lands its ruled record, grams, basis and parts, '
        'counted (computed alone)', () async {
      for (final (file, section, position, raw, fdcId, grams, basis, parts)
          in _pins) {
        final (row, one, line) = await at(file, section, position);
        final reason = '$file|$section|$position';
        expect(line.raw, raw, reason: reason);
        expect(
          (row.fdcId, row.grams?.toStringAsFixed(2), row.status, row.hold),
          (fdcId, grams, 'auto', null),
          reason: reason,
        );
        expect(gramBasisFor(db, line, row, recipe: one), basis, reason: reason);
        expect(partsText(row), parts, reason: reason);
        // Counted (closer round 1, D1: the halloumi rank-as's whole effect
        // — off 0.465 below the gate — was unpinned; closer round 4: the
        // pasta's rank-as, off 0.0125).
        expect(bucketOf(row), MatchBucket.counted, reason: reason);
      }
    });

    test('Q15 i (closer round 1, D3): a live search on a Thai chile row or '
        'the jarred pepper row asks the very answer the row reads (the '
        "matches GET's candidates_query) — jarred hot cherry peppers read "
        'the pickled answer by rank-as, never a rewrite key', () async {
      for (final (file, position, answer) in [
        (
          '0510-goi-cuo-n-vietnamese-summer-rolls.yaml',
          0,
          'jarred hot cherry peppers',
        ),
        (
          '0066-pasta-frittata-with-sausage-and-hot-peppers.yaml',
          3,
          'pickled hot cherry peppers',
        ),
      ]) {
        final (_, _, line) = await at(file, null, position);
        final read = lineSearchFor(
          db,
          normalizeItem(lineItemOf(line)),
          lineKeyOf(line),
        ).answer;
        expect(read, answer, reason: file);
        final body = await foodSearchBody(db, provider, read);
        expect(body['query'], read, reason: file);
      }
      for (final item in [
        'thai',
        'green thai',
        'thai chile',
        'thai chiles',
        'green or red thai chiles',
        'red thai chile',
        'jarred hot cherry peppers',
      ]) {
        final read = rankAsFor(item)!.answer;
        expect(searchQueryFor(normalizeItem(read)), read, reason: item);
      }
    });

    // STATED SYNTHESIZED negative (closer round 1, D2): Best Ground Beef
    // Chili's (0009) real can line with its real step's head noun swapped
    // — "Add remaining 2 cups water, tomatoes and their liquid, …" — adds
    // some OTHER food's liquid: the can stays on the drained share (v48's
    // 266.63 g on 2644292), never the whole can on 175201.
    test("Q14 i: the step read needs the line's own head noun", () async {
      final real = stored('0009-best-ground-beef-chili.yaml');
      final line = nutritionLines(real)[17];
      expect(line.raw, '1 (15-ounce) can pinto beans');
      expect(canLiquidEatenIn(real, line), isTrue);
      final swapped = real.copyWith(
        id: 'r-swap',
        slug: 'r-swap',
        ingredients: [
          IngredientGroup(items: [line]),
        ],
        steps: [
          for (final step in real.steps)
            step.copyWith(
              text: step.text.replaceFirst(
                'beans and their liquid',
                'tomatoes and their liquid',
              ),
            ),
        ],
      );
      expect(
        swapped.steps.where(
          (s) => s.text.contains('tomatoes and their liquid'),
        ),
        hasLength(1),
      );
      expect(canLiquidEatenIn(swapped, line), isFalse);
      db.upsertRecipe(swapped, sourceSlug: _source, contentHash: 'r-swap');
      expect(await matchAndCompute(db, provider, swapped), isNull);
      final row = db.ingredientMatchesFor('r-swap').single;
      expect(
        (row.fdcId, row.grams?.toStringAsFixed(2)),
        (2644292, '266.63'),
      );
    });

    test('Q23 (a): red curry paste and Old Bay land no_match with no record '
        'and send no search', () async {
      for (final (file, section, position, raw) in _vetoed) {
        final before = provider.searchCalls;
        final (row, _, line) = await at(file, section, position);
        final reason = '$file|$section|$position';
        expect(line.raw, raw, reason: reason);
        expect(
          (row.fdcId, row.description, row.status, row.grams),
          (null, 'No FoodData Central match', 'unmatched', null),
          reason: reason,
        );
        expect(provider.searchCalls, before, reason: reason);
        expect(
          bucketOf(row),
          MatchBucket.noMatch,
          reason: reason,
        );
      }
      expect(noFdcRecordItems, {
        'red curry paste',
        'thai red curry paste',
        'old bay seasoning',
      });
    });

    test(
      "Q15 iv (the owner's 2026-10-07 ruling): the pasta line reads its own "
      "cached answer under the record's words — SR 169736 counted (226.80 g, "
      '841.42 kcal), the recipe 17 of 18; one corpus line; the Foundation '
      "record's sibling kept",
      () async {
        const file = '0404-pasta-e-fagioli-italian-pasta-and-bean-soup.yaml';
        final (row, one, _) = await at(file, null, 14);
        // Over the gate (was 0.0125 on 2758998).
        expect(row.confidence, greaterThanOrEqualTo(0.5));
        expect(bucketOf(row), MatchBucket.counted);
        expect(
          (row.fdcId, row.grams?.toStringAsFixed(2), row.hold),
          (169736, '226.80', null),
        );
        final energy =
            (jsonDecode(db.nutritionFor(one.id)!.totalsJson!) as Map)['energy']
                as num;
        expect(energy, closeTo(841.42, 0.01)); // 226.8 × 371 / 100
        // The whole recipe: 17 of 18 (the Parmesan rind stays in check).
        // RE-PIN (M70 batch, v69, pF F3): 18 of 18, complete — the rind
        // now counts 0 g on 170848, discarded whole (nutrition_v69_test).
        final whole = stored(file);
        expect(await matchAndCompute(db, provider, whole), isNull);
        final n = db.nutritionFor(whole.id)!;
        expect((n.matchedCount, n.totalCount, n.status), (18, 18, 'complete'));
        // Another line could still land the Foundation record.
        expect(nutrientSiblings[2758998], 169736);
        expect(rankAsFor('pasta such as ditalini'), (
          query: 'pasta dry enriched',
          answer: 'pasta such as ditalini',
        ));
        // The record is the food: no approximation flag.
        expect(approximationRecords['pasta such as ditalini'], isNull);
        // The reach: exactly one corpus line carries the key.
        final reach = <String>[];
        for (final f in Directory(corpusRecipesDir).listSync()) {
          if (f is! File || !f.path.endsWith('.yaml')) continue;
          final recipe = loadCorpusRecipe(f.uri.pathSegments.last);
          for (final (where, from) in [
            ('', recipe),
            for (final sub in recipe.subsections)
              (sub.title ?? '', sectionRecipeOf(recipe, sub)),
          ]) {
            for (final line in nutritionLines(from)) {
              if (normalizeItem(lineItemOf(line)) == 'pasta such as ditalini') {
                reach.add('${recipe.slug}|$where|${line.raw}');
              }
            }
          }
        }
        expect(reach, [
          'pasta-e-fagioli-italian-pasta-and-bean-soup||8 ounces small pasta such as ditalini, tubetini, conchiglietti, or orzo',
        ]);
      },
    );

    test('Q13: the leek and rhubarb rows count their raw siblings per 100 g '
        "(61, 21 kcal); napa's sibling unchanged", () async {
      for (final (file, position, kcal) in [
        ('0021-rustic-potato-leek-soup.yaml', 1, 61.0),
        ('0966-rhubarb-fool.yaml', 0, 21.0),
      ]) {
        final (row, one, _) = await at(file, null, position);
        final n = db.nutritionFor(one.id)!;
        final energy = (jsonDecode(n.totalsJson!) as Map)['energy'] as num;
        expect(energy / row.grams! * 100, closeTo(kcal, 1e-6), reason: file);
      }
      expect(nutrientSiblings[2727583], 169979);
      expect(nutrientSiblings[2709935], 169246);
      expect(nutrientSiblings[2709268], 167758);
    });

    test('Q11: the shell move names the record bought; a count and a shell '
        'eaten whole never move', () async {
      final (mussels, steamed, musselLine) = await at(
        '0294-oven-steamed-mussels.yaml',
        null,
        6,
      );
      expect(mussels.fdcId, 174216);
      expect(decisionRecordOf(steamed, musselLine, 174216), 2706350);
      expect(
        shellCounted(
          steamed,
          lineGrams(db, musselLine, knownFood(db, 174216), recipe: steamed),
        ),
        isTrue,
      );
      final (_, paella, dozen) = await at('0105-paella.yaml', null, 14);
      // A count reads the FNDDS meat portion: no move, its own record.
      expect(decisionRecordOf(paella, dozen, 2706350), 2706350);
      final crispy = loadCorpusRecipe(
        '0279-crispy-salt-and-pepper-shrimp.yaml',
      );
      expect(shellEatenIn(crispy), isTrue);
      expect(ah102Shells.keys, {175179, 174216});
    });

    test('Q11 (closer round 2, D1): skip then un-skip returns a shell row '
        'counted, as the compute writes it', () async {
      // The 0034 clams carry v40's FDC shell yield; the mussels and the
      // shrimp their AH-102 rows. The un-skip re-derives the hold from the
      // stored grams' basis — once basis-less, it held them `in_shell`.
      for (final (file, position, fdcId, grams) in [
        ('0294-oven-steamed-mussels.yaml', 6, 174216, '526.17'),
        (
          '0429-garlicky-shrimp-tomato-and-white-bean-stew.yaml',
          2,
          175179,
          '367.41',
        ),
        ('0034-new-england-clam-chowder.yaml', 0, 174214, '476.00'),
      ]) {
        final (row, one, line) = await at(file, null, position);
        final reason = '$file|$position';
        expect(boughtInShell(line.raw), isTrue, reason: reason);
        // Alone, the line is the recipe's position 0.
        for (final skipped in [true, false]) {
          await applyMatchOverride(db, provider, one, 0, {
            'raw': row.raw,
            'skipped': skipped,
          });
        }
        final back = db.ingredientMatchesFor(one.id).single;
        expect(
          (back.status, back.fdcId, back.grams?.toStringAsFixed(2), back.hold),
          ('auto', fdcId, grams, null),
          reason: reason,
        );
        expect(bucketOf(back), MatchBucket.counted, reason: reason);
        expect(db.nutritionFor(one.id)!.status, 'complete', reason: reason);
        // And a compute leaves it as it is.
        expect(await matchAndCompute(db, provider, one), isNull);
        final again = db.ingredientMatchesFor(one.id).single;
        expect(
          (again.status, again.fdcId, again.grams, again.hold),
          (back.status, back.fdcId, back.grams, back.hold),
          reason: reason,
        );
      }
    });

    // STATED SYNTHESIZED steps: the corpus prints no strain before a zest's
    // first mention (0142, 0536, 0860, 0861 and 0989 strain nothing; the
    // juice-only recipes strain after the zest), so one step is added.
    test("Q6 (closer round 3, D1): only a strain at or after the zest's "
        'first mention drops the zest', () async {
      final host = stored('0142-skillet-roasted-chicken-in-lemon-sauce.yaml');
      final line = nutritionLines(host)[8];
      expect(
        line.raw,
        '4 teaspoons grated lemon zest plus ¼ cup juice (2 lemons)',
      );
      const strain = RecipeStep(
        number: 0,
        text: 'Strain the broth through a fine-mesh strainer.',
      );
      for (final (label, steps, fdcId, grams, basis, parts) in [
        (
          'before',
          [strain, ...host.steps],
          167749,
          '68.92',
          'zest 4 teaspoon · USDA portion + juice 1/4 cup ≈ 59 mL',
          '167749:8.00|167747:60.92',
        ),
        (
          'after',
          [...host.steps, strain],
          167747,
          '60.92',
          '1/4 cup ≈ 59 mL · juice only (the zest is strained out)',
          '',
        ),
      ]) {
        final id = 'strain-$label';
        final one = host.copyWith(
          id: id,
          slug: id,
          steps: steps,
          ingredients: [
            IngredientGroup(items: [line]),
          ],
        );
        db.upsertRecipe(one, sourceSlug: _source, contentHash: id);
        expect(await matchAndCompute(db, provider, one), isNull);
        final row = db.ingredientMatchesFor(id).single;
        expect(
          (
            row.status,
            row.fdcId,
            row.grams?.toStringAsFixed(2),
            row.hold,
            partsText(row),
            gramBasisFor(db, line, row, recipe: one),
          ),
          ('auto', fdcId, grams, null, parts, basis),
          reason: label,
        );
      }
    });

    test("Q6 / Q14 ii (closer round 3, D2): a person's pick of the row's "
        'own record undoes a two-part rule — one record, no parts', () async {
      for (final (file, position, raw, fdcId, before, after) in [
        (
          '0536-crispy-orange-beef.yaml',
          3,
          '10 (3-inch) strips orange peel, sliced thin lengthwise (¼ cup), plus ¼ cup juice (2 oranges)',
          169103,
          '86.00',
          '24.00',
        ),
        (
          '1075-espinacas-con-garbanzos-andalusian-spinach-and-chickpeas.yaml',
          1,
          '2 (15-ounce) cans chickpeas (1 can drained, 1 can undrained)',
          2644288,
          '665.50',
          '665.50',
        ),
      ]) {
        final (row, one, line) = await at(file, null, position);
        final reason = '$file|$position';
        expect(line.raw, raw, reason: reason);
        expect(
          (row.status, row.fdcId, row.grams?.toStringAsFixed(2)),
          ('auto', fdcId, before),
          reason: reason,
        );
        expect(partsOf(row.parts), hasLength(2), reason: reason);
        // Alone, the line is the recipe's position 0.
        await applyMatchOverride(db, provider, one, 0, {'fdc_id': fdcId});
        final picked = db.ingredientMatchesFor(one.id).single;
        expect(
          (
            picked.status,
            picked.fdcId,
            picked.grams?.toStringAsFixed(2),
            picked.hold,
            picked.parts,
          ),
          ('overridden', fdcId, after, null, null),
          reason: reason,
        );
      }
    });

    test('Q14 ii: a kept-liquid can names the drained record bought; the '
        "parts' roles on the wire; no rendered-bacon flag", () async {
      final (ceci, pasta, can) = await at(
        '0340-pasta-e-ceci-pasta-with-chickpeas.yaml',
        null,
        10,
      );
      expect(ceci.fdcId, 175206);
      expect(decisionRecordOf(pasta, can, 175206), 2644288);
      final (two, espinacas, cans) = await at(
        '1075-espinacas-con-garbanzos-andalusian-spinach-and-chickpeas.yaml',
        null,
        1,
      );
      expect(
        [for (final p in partsJson(db, two)) p['role']],
        [
          'drained',
          'undrained',
        ],
      );
      expect(
        compositeFlagOf(db, espinacas, cans, two, ResolverMemo(db)),
        isNull,
      );
      final (orange, beef, peel) = await at(
        '0536-crispy-orange-beef.yaml',
        null,
        3,
      );
      expect(
        [for (final p in partsJson(db, orange)) p['role']],
        [
          'zest',
          'juice',
        ],
      );
      expect(compositeFlagOf(db, beef, peel, orange, ResolverMemo(db)), isNull);
      expect(cannedBeanLiquids, {
        2644288: 175206,
        2644292: 175201,
        2644289: 175195,
      });
    });

    // STATED SYNTHESIZED negatives: inputs the corpus cannot supply.
    test('the boundaries: a zest over a tablespoon read with no recipe is '
        'held as before; a drain word beats the step read; a lime count; '
        'the starch figure', () {
      IngredientLine lineOf(String raw) {
        final parsed = parseIngredientLine(raw);
        return IngredientLine(
          raw: raw,
          item: parsed.item,
          amounts: parsed.amounts,
        );
      }

      // 0142's line, no recipe at hand (the steps decide strained or not).
      expect(
        secondFoodRuleOf(
          lineOf('4 teaspoons grated lemon zest plus ¼ cup juice (2 lemons)'),
        ),
        isNull,
      );
      // No corpus line counts limes after a zest (synthesized).
      expect(
        secondFoodRuleOf(
          lineOf('1 teaspoon grated lime zest plus 2 limes'),
        )?.fdcId,
        168155,
      );
      // A can line that drains keeps its share whatever the steps say
      // (synthesized: the four step-read recipes print no drain word).
      expect(
        keepsWholeCan(
          '1 (15-ounce) can pinto beans, drained',
          liquidEaten: true,
        ),
        isFalse,
      );
      expect(
        keepsWholeCan('1 (15-ounce) can pinto beans', liquidEaten: true),
        isTrue,
      );
      expect(
        densityOf('tapioca starch'),
        closeTo(3 * 28.3495 / (0.75 * 236.588), 1e-9),
      );
      // A size word after the first comma sizes the cut, not the fruit
      // (synthesized: the corpus's two kiwi lines print none there).
      const cut = '2 kiwis, peeled and cut into large pieces';
      final kiwis = resolveGrams(
        amounts: parseIngredientLine(cut).amounts,
        food: null,
        normalizedItem: 'kiwis',
        raw: cut,
      )!;
      expect((kiwis.grams, kiwis.basis), (150.0, '2 × 75 g each'));
    });
  });
}

MatchBucket bucketOf(IngredientMatchRow row) => matchBucketFor(
  status: row.status,
  fdcId: row.fdcId,
  grams: row.grams,
  confidence: row.confidence,
  hold: row.hold,
  gramSource: row.gramSource,
);
