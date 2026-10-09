// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v51 (batch M49, the bacon package and fat poured off;
// matcherVersion 50; prep47 design_v2 §1 Q4 (b) and Q19 (a), §2 "M49",
// decided under the owner's 2026-10-07 standing authorization, re-ruling
// Y11's 0.403 and v40's "the wider bacon lines a person's"; zero
// requests): rule B1's cooked yield is USDA AH-102 item 1981 (33 %) and
// its rendered fat 0.2555 g a raw gram by the same fat balance; a bacon
// slice weighs 168277's 28 g, a thick-cut one the corpus's printed 35.44 g
// (flagged), a Canadian one 167869's 28.5 g; an oil browned in a pan the
// steps pour down to a printed part counts at most that part (P1 D3a), in
// rule B1's pan its R / (R + O) share of it (P4 §4); a frying oil's
// "reserve N … discard the remainder" is its kept part, counted with its
// part used outside the fry, and MARKED with the food it fried (critic
// F13: M52 adds that food's uptake). Every row value is the v51 replay's
// (rp43 on snapshot 21); the rows compute each WHOLE recipe on recorded
// real FDC answers (FixtureProvider; 13 searches and 4 foods added
// --from-db from snapshot 21, JSON-equal), never the network.

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

const String _ah102 =
    'approximate (USDA AH-102 item 1981: bacon, sliced, all methods → cooked 33 % (18–43))';

/// (file, section title or null, position, raw, fdc id, grams, hold, parts
/// as "id:g|id:g", basis, the composite flag) — each the v51 replay's row.
const List<
  (
    String,
    String?,
    int,
    String,
    int?,
    String?,
    String?,
    String?,
    String?,
    String?,
  )
>
_rows = [
  // Yield (+ thick-cut slice): 6 × 35.44 = 212.64 raw → 70.17 + 25.80 (audit L153 83.8 → 95.97, auditors 104)
  (
    '1134-tartiflette-french-potato-and-cheese-gratin.yaml',
    null,
    2,
    '6 slices thick-cut bacon, cut into ½-inch pieces',
    168277,
    '95.97',
    null,
    '168322:70.17|172345:25.80',
    '213 g raw → 70 g cooked bacon + 26 g bacon grease kept in the pan',
    _ah102,
  ),
  // Yield: 453.59 × 0.33 = 149.69 + the stated 3 tablespoons 38.70 (audit L040 221.5 → 188.39, auditors 187)
  (
    '0158-classic-roast-stuffed-turkey.yaml',
    'Bread Stuffing with Bacon, Apples, Sage, and Caramelized Onions',
    0,
    '1 pound bacon, cut crosswise into ¼-inch strips',
    168277,
    '188.39',
    null,
    '168322:149.69|172345:38.70',
    '454 g raw → 150 g cooked bacon + 39 g bacon grease kept in the pan',
    _ah102,
  ),
  // its parent re-reads the section
  (
    '0158-classic-roast-stuffed-turkey.yaml',
    null,
    7,
    '1 recipe Bread Stuffing with Bacon, Apples, Sage, and Caramelized Onions (recipe follows)',
    null,
    '3088.50',
    null,
    null,
    'from the recipe Bread Stuffing with Bacon, Apples, Sage, and Caramelized Onions: 3089 g, 5,465 kcal',
    null,
  ),
  // Yield + slice: 6 × 28 = 168 raw → 55.44 + 25.80
  (
    '0685-braised-greens-with-bacon-and-onion.yaml',
    null,
    0,
    '6 slices bacon, cut into ¼-inch pieces',
    168277,
    '81.24',
    null,
    '168322:55.44|172345:25.80',
    '168 g raw → 55 g cooked bacon + 26 g bacon grease kept in the pan',
    _ah102,
  ),
  // Yield + slice: the stated ¼ cup (51.60 g) now binds below 224 × 0.2555 = 57.23
  (
    '1177-caramelized-onion-pear-and-bacon-tart.yaml',
    null,
    0,
    '8 slices bacon, chopped fine',
    168277,
    '125.52',
    null,
    '168322:73.92|172345:51.60',
    '224 g raw → 74 g cooked bacon + 52 g bacon grease kept in the pan',
    _ah102,
  ),
  // Yield only, unchanged in kind (no oil in its pan)
  (
    '0040-wilted-spinach-salad-with-warm-bacon-dressing.yaml',
    null,
    5,
    '10 ounces (about 8 slices) thick-cut bacon, cut into ½-inch pieces',
    168277,
    '132.25',
    null,
    '168322:93.55|172345:38.70',
    '284 g raw → 94 g cooked bacon + 39 g bacon grease kept in the pan',
    _ah102,
  ),
  // Slice (the v40 amendment: raw-counted rows weigh the sourced slice)
  // RE-PIN (M60 batch, v59): the scallops' bacon, wrapped round them and
  // grilled, now drips (P7b): 336 g raw → B1's cooked part, no fat kept.
  (
    '0652-grilled-bacon-wrapped-scallops.yaml',
    null,
    0,
    '12 slices bacon',
    168277,
    '110.88',
    null,
    '168322:110.88|172345:0.00',
    '336 g raw → 111 g cooked bacon + 0.0 g bacon grease kept in the pan',
    'approximate (USDA AH-102 item 1981: bacon, sliced, all methods → cooked 33 % (18–43); the fat drips off the food)',
  ),
  (
    '0733-oven-fried-bacon.yaml',
    null,
    0,
    '12 slices bacon',
    168277,
    '336.00',
    null,
    null,
    '12 slice × 28 g each',
    null,
  ),
  // Thick-cut (flagged)
  (
    '1099-spanish-migas-with-fried-eggs.yaml',
    null,
    7,
    '2 slices thick-cut bacon, cut into ½-inch pieces',
    168277,
    '70.88',
    null,
    null,
    "2 slice × 35.44 g each · approximate (the corpus's printed thick-cut slice, median of three)",
    null,
  ),
  // Canadian bacon on 167869's own slice
  (
    '0729-eggs-benedict-with-perfect-poached-eggs-and-foolproof-hollandaise.yaml',
    null,
    10,
    '8 slices Canadian bacon',
    167869,
    '228.00',
    null,
    null,
    '8 slice × 28.5 g each',
    null,
  ),
  // Kept cap (D3a): "Heat the oil" (step 1) … "Pour off all but 1 teaspoon fat" (step 2)
  (
    '0088-slow-cooker-beer-braised-short-ribs.yaml',
    null,
    2,
    '2 tablespoons vegetable oil',
    2710180,
    '4.53',
    null,
    null,
    '1 teaspoon kept (the steps pour off the rest)',
    null,
  ),
  (
    '0126-pollo-en-pepitoria-spanish-braised-chicken-with-sherry-and-saffron.yaml',
    null,
    2,
    '1 tablespoon extra-virgin olive oil',
    748608,
    '9.07',
    null,
    null,
    '2 teaspoons kept (the steps pour off the rest)',
    null,
  ),
  // NOT cut: only "2 teaspoons of the oil" is in the pan (kept 2 teaspoons);
  // the remaining 3 teaspoons go in after the pour-off
  (
    '0079-skillet-jambalaya.yaml',
    null,
    2,
    '5 teaspoons vegetable oil',
    2710180,
    '22.67',
    null,
    null,
    '5 teaspoon ≈ 25 mL',
    null,
  ),
  // Reserve (frying oil): 2 teaspoons tossed with the crumbs + the 1 tablespoon reserved
  // — RE-PIN (M52 batch, v53, critic F13): the MARK's food takes its uptake on top,
  // 23.07 + 137.78 g of grated potato × O4c 10.9 % (derived, SR 19411) = 38.09
  (
    '0215-horseradish-crusted-beef-tenderloin.yaml',
    null,
    3,
    '1 cup plus 2 teaspoons vegetable oil',
    2710180,
    '38.09',
    null,
    null,
    'discarded in cooking — only "plus 2 teaspoons vegetable oil", the 1 tablespoon the steps keep and the oil the fried food absorbs counted · approximation (frying oil absorbed: 10.9 % of the raw potatoes\' weight — derived from USDA SR Legacy 19411 "Snacks, potato chips, plain, salted")',
    null,
  ),
  // Split (P4 §4): kept K, R the rendered fat, O the oil — K × R/(R+O) and K × O/(R+O)
  (
    '0332-pasta-with-tomato-bacon-and-onion.yaml',
    null,
    0,
    '2 tablespoons extra-virgin olive oil',
    748608,
    '9.93',
    null,
    null,
    '2 tablespoons kept with the bacon grease (the steps pour off the rest)',
    null,
  ),
  (
    '0332-pasta-with-tomato-bacon-and-onion.yaml',
    null,
    1,
    '6 ounces pancetta or bacon, sliced ¼ inch thick and cut into strips 1 inch long and ¼ inch wide',
    168277,
    '72.00',
    null,
    '168322:56.13|172345:15.87',
    '170 g raw → 56 g cooked bacon + 16 g bacon grease kept in the pan, sharing the 2 tablespoons kept with the oil',
    _ah102,
  ),
  (
    '0434-salade-lyonnaise.yaml',
    null,
    0,
    '1 (½-inch-thick) slice pancetta (about 5 ounces)',
    168277,
    '61.51',
    null,
    '168322:46.78|172345:14.73',
    '142 g raw → 47 g cooked bacon + 15 g bacon grease kept in the pan, sharing the 2 tablespoons kept with the oil · approximation (counted as Pork, cured, bacon, unprepared)',
    _ah102,
  ),
  (
    '0434-salade-lyonnaise.yaml',
    null,
    1,
    '2 tablespoons extra-virgin olive oil',
    748608,
    '11.07',
    null,
    null,
    '2 tablespoons kept with the bacon grease (the steps pour off the rest)',
    null,
  ),
  // gricia: the ⅓ cup kept (68.80 g) is now below R + O (57.95 + 13.60)
  (
    '0333-pasta-alla-gricia-rigatoni-with-pancetta-and-pecorino-romano.yaml',
    null,
    0,
    '8 ounces pancetta, sliced ¼ inch thick',
    168277,
    '130.56',
    null,
    '168322:74.84|172345:55.72',
    '227 g raw → 75 g cooked bacon + 56 g bacon grease kept in the pan, sharing the ⅓ cup kept with the oil · approximation (counted as Pork, cured, bacon, unprepared)',
    _ah102,
  ),
  (
    '0333-pasta-alla-gricia-rigatoni-with-pancetta-and-pecorino-romano.yaml',
    null,
    1,
    '1 tablespoon extra-virgin olive oil',
    748608,
    '13.08',
    null,
    null,
    '⅓ cup kept with the bacon grease (the steps pour off the rest)',
    null,
  ),
  // NOT cut, each stated: Chicken Marbella's "Heat oil" names neither of its
  // two oil lines (the paste's, the chicken's); the crispy-skinned breasts'
  // oil goes into the skillet in step 3, two steps before the pour-off —
  // outside the design's window (the pour-off step or the one before).
  // RE-PIN (M64 batch, v63, F9): the window is now any earlier sentence —
  // the crispy-skinned breasts' oil IS cut (2 teaspoons kept, 9.07 g; was
  // 28.00 whole); Marbella's stays uncut (its binder, C1).
  (
    '0124-chicken-marbella.yaml',
    null,
    2,
    '3 tablespoons extra-virgin olive oil',
    748608,
    '40.81',
    null,
    null,
    '3 tablespoon ≈ 44 mL',
    null,
  ),
  (
    '0124-chicken-marbella.yaml',
    null,
    12,
    '2 teaspoons olive oil',
    2710186,
    '9.07',
    null,
    null,
    '2 teaspoon ≈ 10 mL',
    null,
  ),
  (
    '0121-crispy-skinned-chicken-breasts-with-vinegar-pepper-pan-sauce.yaml',
    null,
    2,
    '2 tablespoons vegetable oil',
    2710180,
    '9.07',
    null,
    null,
    '2 teaspoons kept (the steps pour off the rest)',
    null,
  ),
  // Byte-equal: the shipped kept frying oil; the lamb's oil (1 teaspoon,
  // kept 1 teaspoon) and its relish's (mixed in a bowl, never the pan's)
  (
    '1193-crispy-tempeh-with-sambal-sauce.yaml',
    null,
    5,
    '1 cup vegetable oil',
    2710180,
    '28.00',
    null,
    null,
    'discarded in cooking — only the part the recipe keeps counted',
    null,
  ),
  (
    '0228-roast-rack-of-lamb-with-roasted-red-pepper-relish.yaml',
    null,
    3,
    '1 teaspoon vegetable oil',
    2710180,
    '4.53',
    null,
    null,
    '1 teaspoon ≈ 5 mL',
    null,
  ),
  (
    '0228-roast-rack-of-lamb-with-roasted-red-pepper-relish.yaml',
    null,
    6,
    '¼ cup extra-virgin olive oil',
    748608,
    '54.42',
    null,
    null,
    '1/4 cup ≈ 59 mL',
    null,
  ),
  // The four cured-pork rows M50 settled: byte-equal to M50's landing
  (
    '0426-beef-braised-in-barolo.yaml',
    null,
    2,
    '4 ounces pancetta (about 4 slices), cut into ¼-inch cubes (see note)',
    168277,
    '0.00',
    null,
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted) · approximation (counted as Pork, cured, bacon, unprepared)',
    null,
  ),
  (
    '0127-coq-au-riesling.yaml',
    null,
    2,
    '2 slices bacon, chopped',
    168277,
    '0.00',
    null,
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
    null,
  ),
  (
    '0211-french-style-pork-chops-with-apples-and-calvados.yaml',
    null,
    3,
    '2 slices bacon, cut into ½-inch pieces',
    168277,
    null,
    'discarded_medium',
    null,
    null,
    null,
  ),
  (
    '0023-modern-ham-and-split-pea-soup.yaml',
    null,
    6,
    '3 slices thick-cut bacon',
    168277,
    null,
    'discarded_medium',
    null,
    null,
    null,
  ),
];

/// (file, position, raw, grams with no food, the basis) — the piece table's
/// key precedence both ways: a thick-cut or Canadian slice never reads the
/// plain one, a plain slice never reads either.
const List<(String, int, String, String, String)> _slices = [
  (
    '1099-spanish-migas-with-fried-eggs.yaml',
    7,
    '2 slices thick-cut bacon, cut into ½-inch pieces',
    '70.88',
    "2 slice × 35.44 g each · approximate (the corpus's printed thick-cut slice, median of three)",
  ),
  (
    '0023-modern-ham-and-split-pea-soup.yaml',
    6,
    '3 slices thick-cut bacon',
    '106.32',
    "3 slice × 35.44 g each · approximate (the corpus's printed thick-cut slice, median of three)",
  ),
  (
    '0729-eggs-benedict-with-perfect-poached-eggs-and-foolproof-hollandaise.yaml',
    10,
    '8 slices Canadian bacon',
    '228.00',
    '8 slice × 28.5 g each',
  ),
  (
    '0194-pub-style-steak-and-ale-pie.yaml',
    5,
    '2 slices bacon, chopped',
    '56.00',
    '2 slice × 28 g each',
  ),
  (
    '0652-grilled-bacon-wrapped-scallops.yaml',
    0,
    '12 slices bacon',
    '336.00',
    '12 slice × 28 g each',
  ),
];

void main() {
  test('the matcher version carries the batch (update the literal with a '
      'bump)', () {
    // RE-PIN (M52 batch, v53): matcherVersion 52 (was 51; M51's v52 re-pin
    // was 50 → 51).
    // RE-PIN (Q25 batch, v54): matcherVersion 53 (was 52).
    // RE-PIN (M57 batch, v56): matcherVersion 55 (was 54).
    // RE-PIN (M58 batch, v57): matcherVersion 56 (was 55).
    // RE-PIN (M59 batch, v58): matcherVersion 57 (was 56).
    // RE-PIN (M60 batch, v59): matcherVersion 58 (was 57).
    // RE-PIN (M61 batch, v60): matcherVersion 59 (was 58).
    // RE-PIN (M62 batch, v61): matcherVersion 60 (was 59).
    // RE-PIN (M63 batch, v62): matcherVersion 61 (was 60).
    // RE-PIN (M64 batch, v63): matcherVersion 62 (was 61).
    expect(matcherVersion, 62);
  });

  test(
    'rule B1: AH-102 item 1981 and the fat balance on the two records '
    'the row is counted on (168277 raw 37.13 g fat, 168322 cooked 35.1 g)',
    () async {
      final provider = FixtureProvider();
      final raw = (await provider.food(rawBaconFdcId))!;
      expect(raw.description, 'Pork, cured, bacon, unprepared');
      final cooked = (await provider.search(
        'thin-sliced cooked deli ham',
      )).singleWhere((c) => c.fdcId == cookedBaconFdcId);
      expect(baconCookedYield, 0.33);
      // 0.3713 − 0.33 × 0.351 = 0.25547 → 0.2555.
      final rendered =
          raw.nutrientsPer100g['204']! / 100 -
          baconCookedYield * cooked.nutrientsPer100g!['204']! / 100;
      expect(rendered.toStringAsFixed(4), '0.2555');
      expect(baconRenderedPerGram, 0.2555);
      // The protein balance given up, disclosed: 0.33 × 33.9 of 13.66.
      expect(
        (1 -
                baconCookedYield *
                    cooked.nutrientsPer100g!['203']! /
                    raw.nutrientsPer100g['203']!)
            .toStringAsFixed(3),
        '0.181',
      );
      expect(baconYieldFlag, _ah102);
      // The slice is the record's own portion.
      expect(
        raw.portions
            .singleWhere((p) => p.description == 'slice raw')
            .gramWeight,
        28,
      );
    },
  );

  group('matcher v51 (batch M49)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('salt-v51-');
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

    test('the slice weights: thick-cut and Canadian before bacon, bacon '
        'never either (the key precedence both ways)', () {
      for (final (file, position, raw, grams, basis) in _slices) {
        final line = nutritionLines(loadCorpusRecipe(file))[position];
        expect(line.raw, raw, reason: file);
        final weighed = resolveGrams(
          amounts: line.amounts,
          food: null,
          normalizedItem: normalizeItem(lineItemOf(line)),
          raw: line.raw,
        )!;
        expect(weighed.grams.toStringAsFixed(2), grams, reason: file);
        expect(weighed.basis, basis, reason: file);
      }
      expect(pieceWeightOf('bacon'), 28);
      expect(pieceWeightOf('thick-cut bacon'), 35.44);
      expect(pieceWeightOf('canadian bacon'), 28.5);
    });

    test('the MARK (critic F13): a frying oil whose pour-off step fries a '
        'named food before it says which — M52 adds its uptake', () {
      final horseradish = loadCorpusRecipe(
        '0215-horseradish-crusted-beef-tenderloin.yaml',
      );
      final oil = nutritionLines(horseradish)[3];
      expect(oil.raw, '1 cup plus 2 teaspoons vegetable oil');
      expect(
        discardedMediumOf(horseradish, oil, normalizeItem(lineItemOf(oil))),
        DiscardedMedium.fryingOil,
      );
      expect(keptOilFries(horseradish, oil), 'potato');
      expect(
        nutritionLines(horseradish)[10].raw,
        '1 small russet potato (about 6 ounces), peeled and grated on the large holes of a box grater',
      );
      // The tempeh fries a step before its pour-off: no mark.
      final tempeh = loadCorpusRecipe(
        '1193-crispy-tempeh-with-sambal-sauce.yaml',
      );
      final tempehOil = nutritionLines(tempeh)[5];
      expect(tempehOil.raw, '1 cup vegetable oil');
      expect(keptOilFries(tempeh, tempehOil), isNull);
      // A browning oil (no frying medium) carries none.
      final ribs = loadCorpusRecipe(
        '0088-slow-cooker-beer-braised-short-ribs.yaml',
      );
      expect(keptOilFries(ribs, nutritionLines(ribs)[2]), isNull);
    });

    test('a STATED synthesized negative (no corpus pour-off has one): an oil '
        'whose last mention before the pour-off is mixed in a bowl, not put in '
        'a pan, is never cut', () async {
      final ribs = loadCorpusRecipe(
        '0088-slow-cooker-beer-braised-short-ribs.yaml',
      );
      final line = nutritionLines(ribs)[2];
      expect(line.raw, '2 tablespoons vegetable oil');
      final food = (await provider.food(2710180))!;
      final normalized = normalizeItem(lineItemOf(line));
      final resolved = resolveGrams(
        amounts: line.amounts,
        food: food,
        normalizedItem: normalized,
      );
      // The real recipe: "Heat the oil in a 12-inch skillet …" (step 1),
      // "Pour off all but 1 teaspoon fat from the skillet" (step 2).
      expect(
        engineOutcome(ribs, line, food, resolved).grams?.toStringAsFixed(2),
        '4.53',
      );
      // Synthesized: step 1's heat sentence made a bowl's.
      final first = ribs.steps.first;
      final bowl = ribs.copyWith(
        steps: [
          first.copyWith(
            text: first.text.replaceFirst(
              'Heat the oil in a 12-inch skillet over medium-high heat until '
                  'just smoking.',
              'Whisk the oil and the salt together in a small bowl.',
            ),
          ),
          ...ribs.steps.skip(1),
        ],
      );
      expect(bowl.steps.first.text, contains('Whisk the oil'));
      expect(
        engineOutcome(bowl, line, food, resolved).grams?.toStringAsFixed(2),
        '28.00',
      );
    });

    test('each line computed in its WHOLE recipe lands its record, grams, '
        'hold, parts, basis and flag (its sections first, as the per-recipe '
        'job does)', () async {
      // The cooked bacon is a search hit only (snapshot 21 holds no detail):
      // the deli-ham answer cached first, as a library does.
      db.fdcSearchCachePut(
        'thin-sliced cooked deli ham',
        jsonEncode([
          for (final c in await provider.search('thin-sliced cooked deli ham'))
            c.toJson(),
        ]),
      );
      final computed = <String>{};
      for (final (
            file,
            section,
            position,
            raw,
            fdcId,
            grams,
            hold,
            parts,
            basis,
            flag,
          )
          in _rows) {
        final host = loadCorpusRecipe(file);
        if (computed.add(file)) {
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
        }
        final stored = db.recipeByIdOrSlug(host.id)!.recipe;
        final recipe = section == null
            ? stored
            : nutritionRecipeOf(db, sectionKeyOf(stored.id, section))!.recipe;
        final line = nutritionLines(recipe)[position];
        final row = db
            .ingredientMatchesFor(recipe.id)
            .singleWhere((r) => r.position == position);
        final reason = '$file|$section|$position';
        expect(line.raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.status, 'auto', reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(row.hold, hold, reason: reason);
        expect(
          row.parts == null
              ? null
              : [
                  for (final p in partsOf(row.parts))
                    '${p.fdcId}:${p.grams.toStringAsFixed(2)}',
                ].join('|'),
          parts,
          reason: reason,
        );
        expect(
          gramBasisFor(db, line, row, recipe: recipe),
          basis,
          reason: reason,
        );
        expect(
          compositeFlagOf(db, recipe, line, row, ResolverMemo(db)),
          flag,
          reason: reason,
        );
      }
    });
  });
}
