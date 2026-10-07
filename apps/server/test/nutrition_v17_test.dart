// Real corpus lines wrap across adjacent literals; the C3/C4 tables keep
// each corpus line verbatim, one literal per entry.
// ignore_for_file: no_adjacent_strings_in_list, lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Matcher v17: checkpoint 8's approved requests — rewrites of names FDC
/// spells another way (each target searched live ONCE, recorded from
/// snapshot 13), rewrites to answers snapshot 12 already holds, an
/// unasked 'liquid' docked as a modified form, and eight SR volume
/// siblings whose detail is fetched once. Real corpus lines (recipe named on
/// each, pinnedCorpusText proves each exists); FDC answers recorded from
/// sweep snapshots 12 and 13 (tool/record_fdc_fixtures.dart --from-db).
void main() {
  final provider = FixtureProvider(pending: pendingSearches);

  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v17');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    db.upsertSource(slug: 'src', name: 'Test', type: 'book');
    return db;
  }

  Recipe recipeOf(SaltDatabase db, List<String> raws) {
    final recipe = Recipe(
      id: 'r',
      title: 'r',
      slug: 'r',
      source: const RecipeSource(name: 'Test', type: 'book'),
      ingredients: [
        IngredientGroup(items: [for (final raw in raws) lineOf(raw)]),
      ],
    );
    db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'hr');
    return recipe;
  }

  // A corpus line as its file stores it: the St. Louis racks keep 'racks'
  // as the count's unit, not in the item, as parseIngredientLine would
  // (C5 proves every table line equals its corpus line).
  IngredientLine corpusLine(String raw) {
    if (!raw.contains('racks St. Louis')) {
      return lineOf(raw);
    }
    return IngredientLine(
      raw: raw,
      item: '(2 1/2- to 3-pound) St. Louis–style spareribs',
      amounts: const [
        Amount(
          measure: Measure.count,
          quantity: '2',
          unit: 'racks',
          primary: true,
        ),
      ],
    );
  }

  // One corpus line alone, computed on the recorded answers.
  Future<IngredientMatchRow> computeLine(String raw) async {
    final db = tempDb();
    final recipe = Recipe(
      id: 'r',
      title: 'r',
      slug: 'r',
      source: const RecipeSource(name: 'Test', type: 'book'),
      ingredients: [
        IngredientGroup(items: [corpusLine(raw)]),
      ],
    );
    db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'hr');
    await matchAndCompute(db, FixtureProvider(), recipe);
    return db.ingredientMatchesFor('r').single;
  }

  // (corpus file, line, normalized item, query). One line per rewrite key.
  const rewrites = <(String, String, String, String)>[
    (
      '0401-cheesy-garlic-bread.yaml',
      '1 (18- to 20-inch) baguette, sliced in half horizontally',
      'baguette',
      'french bread',
    ),
    (
      '0708-best-summer-tomato-gratin.yaml',
      '6 ounces crusty baguette, cut into ¾-inch cubes (4 cups)',
      'crusty baguette',
      'french bread',
    ),
    (
      '0345-orecchiette-with-broccoli-rabe-and-sausage.yaml',
      '1 bunch broccoli rabe (about 1 pound), washed, trimmed, and cut into '
          '1½-inch pieces',
      'broccoli rabe',
      'broccoli raab',
    ),
    (
      '0986-strawberry-rhubarb-pie.yaml',
      '3 tablespoons instant tapioca',
      'instant tapioca',
      'tapioca pearl dry',
    ),
    (
      '0458-slow-cooker-beef-burgundy.yaml',
      '3 tablespoons Minute tapioca',
      'minute tapioca',
      'tapioca pearl dry',
    ),
    (
      '0614-memphis-style-barbecued-spareribs.yaml',
      '2 (2½- to 3-pound) racks St. Louis–style spareribs, trimmed',
      'st louis style spareribs',
      'pork spareribs raw',
    ),
    (
      '0613-kansas-city-sticky-ribs.yaml',
      '2 (2½- to 3-pound) full racks pork spareribs, trimmed of any large '
          'pieces of fat and membrane removed',
      'full racks pork spareribs',
      'pork spareribs raw',
    ),
    (
      '0718-barley-salad-with-pomegranate-pistachios-and-feta.yaml',
      '½ cup pomegranate seeds',
      'pomegranate seeds',
      'pomegranate raw',
    ),
    (
      '1168-milk-chocolate-cremeux-tart.yaml',
      '12 ounces milk chocolate, chopped fine',
      'milk chocolate',
      'milk chocolate candy',
    ),
    (
      '1114-browned-butter-blondies.yaml',
      '½ cup (3 ounces) milk chocolate chips',
      'milk chocolate chips',
      'milk chocolate candy',
    ),
    (
      '0198-sauteed-pork-cutlets-with-mustard-cider-sauce.yaml',
      '1½ pounds boneless country-style pork spareribs, trimmed',
      'boneless country-style pork spareribs',
      'pork spareribs or country-style ribs or beef short ribs',
    ),
    (
      '0173-turkey-breast-en-cocotte-with-pan-gravy.yaml',
      '1 (6- to 7-pound) whole bone-in turkey breast',
      'whole bone-in turkey breast',
      'bone-in turkey breast',
    ),
    (
      '0172-braised-turkey.yaml',
      '1 (5- to 7-pound) whole bone-in, skin-on turkey breast, trimmed',
      'whole bone-in skin-on turkey breast',
      'bone-in turkey breast',
    ),
    (
      '0053-crispy-thai-eggplant-salad.yaml',
      '½ red Thai chile, seeded and sliced thin',
      'red thai chile',
      'jarred hot cherry peppers',
    ),
    (
      '1142-grilled-chicken-with-adobo-and-sazon.yaml',
      '4 teaspoons granulated garlic',
      'granulated garlic',
      'garlic powder',
    ),
    (
      '0270-pan-seared-swordfish-steaks.yaml',
      '2 pounds skinless swordfish steaks, ¾ to 1 inch thick',
      'skinless swordfish steaks',
      'swordfish raw',
    ),
    (
      '0271-pan-seared-sesame-crusted-tuna-steaks.yaml',
      '4 (8-ounce) tuna steaks, preferably yellowfin, about 1 inch thick',
      'tuna steaks',
      'tuna raw',
    ),
    (
      '0626-grilled-glazed-boneless-skinless-chicken-breasts.yaml',
      '2 teaspoons nonfat dry milk powder',
      'nonfat dry milk powder',
      'milk dry nonfat regular',
    ),
    (
      '0915-spiced-pumpkin-cheesecake.yaml',
      '1 (15-ounce) can pumpkin puree',
      'pumpkin puree',
      'pumpkin canned without salt',
    ),
    (
      '0784-pumpkin-bread.yaml',
      '1 (15-ounce) can unsweetened pumpkin puree',
      'unsweetened pumpkin puree',
      'pumpkin canned without salt',
    ),
    (
      '1207-nutella-tart.yaml',
      '1¼ cups Nutella',
      'nutella',
      'chocolate hazelnut spread',
    ),
    (
      '0513-sung-choy-bao-chicken-lettuce-wraps.yaml',
      '½ cup water chestnuts, cut into ¼-inch pieces',
      'water chestnuts',
      'waterchestnuts chinese raw',
    ),
    (
      '0750-easy-buttermilk-waffles.yaml',
      '½ cup dried buttermilk powder',
      'dried buttermilk powder',
      'milk buttermilk dried',
    ),
    (
      '0868-carrot-layer-cake.yaml',
      '⅓ cup buttermilk powder',
      'buttermilk powder',
      'milk buttermilk dried',
    ),
  ];

  test("R1: each v17 rewrite searches its target, and FDC's answer to it "
      '(live, snapshot 13; or cached, snapshot 12) ranks the named record '
      'first, over the gate', () async {
    const top = {
      'french bread': 2707610,
      'broccoli raab': 170381,
      'tapioca pearl dry': 169717,
      'pork spareribs raw': 167853,
      'pomegranate raw': 2709267,
      'milk chocolate candy': 167587,
      'swordfish raw': 173703,
      'tuna raw': 2706308,
      'milk dry nonfat regular': 172195,
      'pumpkin canned without salt': 168450,
      'chocolate hazelnut spread': 2710289,
      'waterchestnuts chinese raw': 170066,
      'milk buttermilk dried': 171274,
      'pork spareribs or country-style ribs or beef short ribs': 167895,
      'bone-in turkey breast': 171093,
      'jarred hot cherry peppers': 2709798,
      'garlic powder': 171325,
    };
    for (final (_, raw, item, target) in rewrites) {
      expect(searchQueryFor(item), target, reason: item);
      expect(pendingSearches, isNot(contains(target)), reason: item);
      // Ranked as the engine ranks the line: a whole bone-in breast is
      // skin-on ([impliesSkinOn]).
      final ranked = rankCandidates(
        target,
        await provider.search(target),
        skinOn: impliesSkinOn(raw, item),
      ).first;
      expect(ranked.candidate.fdcId, top[target], reason: item);
      expect(belowConfidenceGate(ranked.confidence), isFalse, reason: item);
    }
  });

  test('R2: each corpus line derives that item and searches that target '
      '(lineSearchFor on an empty cache: no answer read, none invented)', () {
    final db = tempDb();
    for (final (file, raw, item, target) in rewrites) {
      final recipe = loadCorpusRecipe(file);
      final line = nutritionLines(
        recipe,
      ).firstWhere((l) => l.raw == raw, orElse: () => fail('$file: $raw'));
      final eaten = weighedLine(recipe, line);
      final normalized = normalizeItem(lineItemOf(eaten));
      expect(normalized, item, reason: raw);
      expect(
        lineSearchFor(db, normalized, lineKeyOf(eaten)).query,
        target,
        reason: raw,
      );
    }
  }, skip: skipIfNoCorpus);

  test("R3: what is deliberately NOT mapped — 'thai red chile' (Panang Beef "
      "Curry: the piece table's 'thai chile' misses it, so its count would "
      "read the record's whole pepper) and 'milk chocolate chip', whose "
      "'milk chocolate' answer leads with the drink", () {
    expect(searchQueryFor('thai red chile'), 'thai red chile');
    expect(searchQueryFor('milk chocolate chip'), 'milk chocolate chip');
  });

  test(
    'L1: an unasked "liquid" docks as a modified form — "6 ounces '
    'unsweetened chocolate, chopped fine" (Classic Brownies, 0843) takes '
    'the solid squares (167568, 642 kcal) over the tied liquid record '
    '(167567, 472); the clam juice target asks for liquid and keeps it',
    () async {
      final chocolate = rankCandidates(
        'unsweetened chocolate',
        await provider.search('unsweetened chocolate'),
      );
      final ids = [for (final r in chocolate) r.candidate.fdcId];
      expect(ids.first, 167568);
      expect(ids.indexOf(167567), greaterThan(0));
      const clam = 'mollusks clam canned liquid';
      final juice = rankCandidates(clam, await provider.search(clam));
      expect(juice.first.candidate.fdcId, 171977);
    },
  );

  test(
    'L2: the "liquid" dock reads the record\'s own FORM segment only — '
    "FDC's canned wording, \"solids and liquids\" (whole tomatoes, "
    '2685578) and "(liquid expressed …)" (canned coconut milk, 170173), '
    'keeps its record undocked, first at 0.86 as in v16',
    () async {
      for (final (query, fdcId) in const [
        ('whole tomatoes', 2685578),
        ('canned coconut milk', 170173),
      ]) {
        final top = rankCandidates(query, await provider.search(query)).first;
        expect(top.candidate.fdcId, fdcId, reason: query);
        expect(top.confidence, closeTo(0.86, 1e-9), reason: query);
      }
    },
  );

  test(
    'G1: a bare-count baguette on "Bread, French or Vienna" (2707610) '
    "weighs the record's own '1 baguette (about 22 in. long)', 324 g, past "
    'the 250 g cap; a small one the "1 mini baguette" 152 g; an SR bare '
    'noun stays capped ("roast" 625 g never sizes Beef Wellington\'s '
    '"… roast, 3 pounds trimmed weight")',
    () async {
      final db = tempDb();
      final bread = (await provider.food(2707610))!;
      for (final (raw, grams) in const [
        ('1 baguette', 324.0), // 0450
        ('1 (18- to 20-inch) baguette, sliced in half horizontally', 324.0),
        ('1 large baguette, halved horizontally', 324.0), // 0467
        ('1 small baguette, cut on the bias into ½-inch slices', 152.0),
      ]) {
        expect(lineGrams(db, lineOf(raw), bread)?.grams, grams, reason: raw);
      }
      const wellington =
          '1 center-cut beef tenderloin roast, 3 pounds trimmed weight, 12 to '
          '13 inches long and 4 to 4½ inches in diameter';
      final roast = (await provider.food(171748))!;
      expect(roast.portions.map((p) => p.gramWeight), contains(625.0));
      // The 625 g 'roast' stays capped; since matcher v37 the line reads
      // the weight it prints in its comma clause instead (3 pounds).
      final printed = lineGrams(db, lineOf(wellington), roast)!;
      expect(printed.source, GramSource.weight);
      expect(printed.grams, closeTo(3 * 453.592, 1e-9));
    },
  );

  test(
    'G1: only a portion that names the ITEM passes the 250 g cap — a heavy '
    'numbered portion naming something else ("1 submarine" 360 g, the '
    'serving of "Crab cake sandwich", 2707022) never sizes a bare count of '
    'crab cakes, while one that names the item ("1 heart") does',
    () {
      // Synthesized records (stated exception): 2707022's own "1 submarine"
      // portion alone, so no smaller portion outranks it — the shape the
      // cap guards against (a wrong-food prepared-dish serving) — and the
      // same weight as "1 heart" for the own-noun side.
      FdcFood onlyPortion(String description) => FdcFood(
        fdcId: 0,
        description: 'synthesized: Crab cake sandwich',
        dataType: 'Survey (FNDDS)',
        nutrientsPer100g: const {'208': 100},
        portions: [FdcPortion(gramWeight: 360, description: description)],
      );
      final db = tempDb();
      expect(
        lineGrams(db, lineOf('2 crab cakes'), onlyPortion('1 submarine')),
        isNull,
      );
      expect(
        lineGrams(
          db,
          lineOf('2 romaine hearts'),
          onlyPortion('1 heart'),
        )?.grams,
        720,
      );
    },
  );

  // (Foundation record, SR sibling, a corpus volume line on it, its grams
  // in snapshot 13 — the live run that fetched each sibling once; v19, Run
  // 050: a shred on the sibling's 'cup, shredded' 70 g / 'cup grated' 110 g,
  // not the medians' 79.5 g / 122 g).
  const siblings = <(int, int, String, double)>[
    (2346395, 170182, '2 cups raw pecan halves', 198), // 0719
    (1104647, 169230, '1 teaspoon garlic, minced to paste', 2.8), // 0504
    (2346407, 169975, '3 cups thinly sliced green cabbage', 210), // 0542
    (2258586, 170393, '2⅔ cups shredded carrots (4 carrots)', 293.33), // 0868
    (2346405, 169988, '2 tablespoons minced celery', 15), // 0292
    (1999632, 168462, '1 cup baby spinach', 30), // 0603
    (2346388, 169248, '2 cups shredded iceberg lettuce', 144), // 1185
    (
      2727583,
      169979,
      '6 cups napa cabbage, sliced crosswise into ½-inch strips', // 0520
      456,
    ),
  ];

  test(
    'S1: the eight v17 volume siblings — a volume line on the '
    'portion-less Foundation record asks FDC for exactly its SR '
    "sibling's detail, once, and is sized on the sibling's portions",
    () async {
      for (final (foundation, sibling, raw, grams) in siblings) {
        expect(volumeSiblings[foundation], sibling, reason: raw);
        final food = (await provider.food(foundation))!;
        final line = lineOf(raw);
        final db = tempDb()
          ..fdcFoodCachePut(foundation, jsonEncode(food.toJson()));
        // The record's own detail sizes nothing: only the sibling can.
        expect(lineGrams(db, line, food), isNull, reason: raw);
        final fixtures = FixtureProvider();
        final (_, sized) = await gramsFor(db, fixtures, food, line);
        expect(sized?.grams, closeTo(grams, 0.005), reason: raw);
        expect(fixtures.foodCalls, 1, reason: raw);
        await gramsFor(db, fixtures, food, line);
        expect(fixtures.foodCalls, 1, reason: raw);
      }
    },
  );

  test('S2: each sibling line computed end to end stays on its Foundation '
      "record and counts at the sibling's grams", () async {
    for (final (foundation, _, raw, grams) in siblings) {
      final row = await computeLine(raw);
      expect(row.fdcId, foundation, reason: raw);
      expect(row.grams, closeTo(grams, 0.005), reason: raw);
      expect(belowConfidenceGate(row.confidence), isFalse, reason: raw);
    }
  });

  test('C1: rewrites to cached answers, computed with no live request — '
      'granulated garlic on "Spices, garlic powder" (1142), boneless '
      "country-style spareribs on the loin's country-style ribs (0198), a "
      'whole bone-in turkey breast on 171093 over the gate (0173), a red '
      'Thai chile on the fresh hot pepper (0053)', () async {
    final db = tempDb();
    final fixtures = FixtureProvider(pending: pendingSearches);
    await matchAndCompute(
      db,
      fixtures,
      recipeOf(db, [
        '4 teaspoons granulated garlic',
        '1½ pounds boneless country-style pork spareribs, trimmed',
        '1 (6- to 7-pound) whole bone-in turkey breast',
        '½ red Thai chile, seeded and sliced thin',
      ]),
    );
    final rows = db.ingredientMatchesFor('r');
    expect(
      [for (final r in rows) (r.fdcId, r.grams?.toStringAsFixed(2))],
      [
        (171325, '12.40'),
        (167895, '680.39'),
        // v39 (Y1): the turkey-parts class yield (gross until v38).
        // RE-PIN (M48): 1932.00 → 1794.00 g, the printed 6–7 lb range at its
        // midpoint (was its top); the basis names the range.
        (171093, '1794.00'),
        (2709798, '1.00'),
      ],
    );
    for (final r in rows) {
      expect(belowConfidenceGate(r.confidence), isFalse, reason: r.raw);
    }
  });

  test('C2: milk chocolate never lands on the chocolate-MILK drink '
      '(2705467): the line asks only "milk chocolate candy", whose answer '
      'leads with "Candies, milk chocolate" (167587, 535 kcal / 100 g) '
      '(1168)', () async {
    final db = tempDb();
    final fixtures = FixtureProvider();
    await matchAndCompute(
      db,
      fixtures,
      recipeOf(db, ['12 ounces milk chocolate, chopped fine']),
    );
    final row = db.ingredientMatchesFor('r').single;
    expect(row.fdcId, 167587);
    expect(fixtures.searchCalls, 1);
    expect(db.fdcSearchCacheGet('milk chocolate'), isNull);
    final hit = (await fixtures.search('milk chocolate candy')).first;
    expect((hit.fdcId, hit.nutrientsPer100g?['208']), (167587, 535));
  });

  // (corpus file, line, FDC record, grams — null: none). Every line the
  // v17 plan said its 13 live searches would move, as snapshot 13 stored
  // it, recomputed here one line at a time on the recorded answers.
  const moved = <(String, String, int, double?)>[
    // french bread
    (
      '0401-cheesy-garlic-bread.yaml',
      '1 (18- to 20-inch) baguette, sliced in half horizontally',
      2707610,
      324.0,
    ),
    ('0450-chicken-bouillabaisse.yaml', '1 baguette', 2707610, 324.0),
    (
      '0432-classic-french-onion-soup.yaml',
      '1 small baguette, cut on the bias into ½-inch slices',
      2707610,
      152.0,
    ),
    (
      '0194-flank-steak-and-arugula-sandwiches-with-red-onion.yaml',
      '1 baguette, cut into four 5-inch lengths, each piece split into top and bottom pieces',
      2707610,
      324.0,
    ),
    (
      '0467-pan-bagnat-provencal-tuna-sandwich.yaml',
      '1 large baguette, halved horizontally',
      2707610,
      324.0,
    ),
    (
      '0279-garlicky-shrimp-with-buttered-bread-crumbs.yaml',
      '1 (3-inch) piece baguette, cut into small pieces',
      2707610,
      // Since matcher v37 by its printed length at 2707610's own 14.73 g
      // an inch (no grams until then).
      44.19,
    ),
    (
      '0708-best-summer-tomato-gratin.yaml',
      '6 ounces crusty baguette, cut into ¾-inch cubes (4 cups)',
      2707610,
      170.1,
    ),
    // broccoli raab
    (
      '0345-orecchiette-with-broccoli-rabe-and-sausage.yaml',
      '1 bunch broccoli rabe (about 1 pound), washed, trimmed, and cut into 1½-inch pieces',
      170381,
      453.59,
    ),
    (
      '1132-orecchiette-with-broccoli-rabe-and-sausage.yaml',
      '1 pound broccoli rabe, trimmed and cut into 1½-inch pieces',
      170381,
      453.59,
    ),
    (
      '1190-ricotta-calzones-with-sausage-and-broccoli-rabe.yaml',
      '12 ounces trimmed broccoli rabe, cut into 1-inch pieces',
      170381,
      340.19,
    ),
    // tapioca pearl dry
    (
      '0979-blueberry-pie.yaml',
      '2 tablespoons instant tapioca, ground',
      169717,
      19.0,
    ),
    (
      '0986-strawberry-rhubarb-pie.yaml',
      '3 tablespoons instant tapioca',
      169717,
      28.5,
    ),
    (
      '1204-triple-berry-slab-pie-with-ginger-lemon-streusel.yaml',
      '6 tablespoons instant tapioca, ground',
      169717,
      57.0,
    ),
    (
      '0458-slow-cooker-beef-burgundy.yaml',
      '3 tablespoons Minute tapioca',
      169717,
      28.5,
    ),
    (
      '0088-slow-cooker-beer-braised-short-ribs.yaml',
      '2 tablespoons Minute tapioca',
      169717,
      19.0,
    ),
    // pork spareribs raw
    (
      '0538-chinese-style-barbecued-spareribs.yaml',
      '2 (2½- to 3-pound) racks St. Louis–style spareribs, cut into individual ribs',
      167853,
      // v43 (Y10: spareribs × 0.58 (AH-102 item 1925)).
      // RE-PIN (M48): 1578.50 → 1446.96 g, the printed 2½–3 lb range at its
      // midpoint (was its top); the basis names the range.
      1446.96,
    ),
    (
      '0614-memphis-style-barbecued-spareribs.yaml',
      '2 (2½- to 3-pound) racks St. Louis–style spareribs, trimmed',
      167853,
      // v43 (Y10: spareribs × 0.58 (AH-102 item 1925)).
      // RE-PIN (M48): 1578.50 → 1446.96 g, the printed 2½–3 lb range at its
      // midpoint (was its top); the basis names the range.
      1446.96,
    ),
    (
      '0615-oven-barbecued-spareribs.yaml',
      '2 (2½- to 3-pound) racks St. Louis–style spareribs, trimmed, membrane removed, and each rack cut in half',
      167853,
      // v43 (Y10: spareribs × 0.58 (AH-102 item 1925)).
      // RE-PIN (M48): 1578.50 → 1446.96 g, the printed 2½–3 lb range at its
      // midpoint (was its top); the basis names the range.
      1446.96,
    ),
    (
      '0611-rosticciana-tuscan-grilled-pork-ribs.yaml',
      '2 (2½- to 3-pound) racks St. Louis–style spareribs, trimmed, membrane removed, and each rack cut into 2-rib sections',
      167853,
      // v43 (Y10: spareribs × 0.58 (AH-102 item 1925)).
      // RE-PIN (M48): 1578.50 → 1446.96 g, the printed 2½–3 lb range at its
      // midpoint (was its top); the basis names the range.
      1446.96,
    ),
    (
      '0613-kansas-city-sticky-ribs.yaml',
      '2 (2½- to 3-pound) full racks pork spareribs, trimmed of any large pieces of fat and membrane removed',
      167853,
      // v43 (Y10: spareribs × 0.58 (AH-102 item 1925)).
      // RE-PIN (M48): 1578.50 → 1446.96 g, the printed 2½–3 lb range at its
      // midpoint (was its top); the basis names the range.
      1446.96,
    ),
    // pomegranate raw
    (
      '0718-barley-salad-with-pomegranate-pistachios-and-feta.yaml',
      '½ cup pomegranate seeds',
      2709267,
      87.5,
    ),
    (
      '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml',
      '1 cup pomegranate seeds',
      2709267,
      175.0,
    ),
    // milk chocolate candy
    (
      '0889-chocolate-sheet-cake-with-easy-chocolate-frosting.yaml',
      '10 ounces milk chocolate, chopped',
      167587,
      283.5,
    ),
    (
      '0885-fluffy-yellow-layer-cake-with-milk-chocolate-frosting.yaml',
      '8 ounces milk chocolate, melted and cooled slightly',
      167587,
      226.8,
    ),
    (
      '1168-milk-chocolate-cremeux-tart.yaml',
      '12 ounces milk chocolate, chopped fine',
      167587,
      340.19,
    ),
    (
      '0890-simple-chocolate-sheet-cake-with-milk-chocolate-frosting.yaml',
      '1 pound milk chocolate, chopped',
      167587,
      453.59,
    ),
    (
      '1114-browned-butter-blondies.yaml',
      '½ cup (3 ounces) milk chocolate chips',
      167587,
      85.05,
    ),
    // swordfish raw
    (
      '0270-pan-seared-swordfish-steaks.yaml',
      '2 pounds skinless swordfish steaks, ¾ to 1 inch thick',
      173703,
      907.18,
    ),
    (
      '0649-grilled-fish-tacos.yaml',
      '2 pounds skinless swordfish steaks, 1 inch thick, cut lengthwise into 1-inch-wide strips',
      173703,
      907.18,
    ),
    (
      '0654-grilled-swordfish-skewers-with-tomato-scallion-caponata.yaml',
      '1½ pounds skinless swordfish steaks, 1¼ to 1½ inches thick, cut into 1¼-inch pieces',
      173703,
      680.39,
    ),
    // tuna raw
    (
      '0271-pan-seared-sesame-crusted-tuna-steaks.yaml',
      '4 (8-ounce) tuna steaks, preferably yellowfin, about 1 inch thick',
      2706308,
      907.18,
    ),
    (
      '0647-grilled-tuna-steaks-with-vinaigrette.yaml',
      '6 (8-ounce) tuna steaks, 1 inch thick',
      2706308,
      1360.78,
    ),
    // milk dry nonfat regular
    (
      '0778-mexican-hot-chocolate.yaml',
      '½ cup (1½ ounces) nonfat dry milk powder',
      172195,
      42.52,
    ),
    (
      '0801-cinnamon-swirl-bread.yaml',
      '¾ cup (2¾ ounces) nonfat dry milk powder',
      172195,
      77.96,
    ),
    // pumpkin canned without salt
    ('0987-pumpkin-pie.yaml', '1 (15-ounce) can pumpkin puree', 168450, 425.24),
    (
      '0784-pumpkin-bread.yaml',
      '1 (15-ounce) can unsweetened pumpkin puree',
      168450,
      425.24,
    ),
    // chocolate hazelnut spread
    (
      '0923-chocolate-hazelnut-slow-cooker-bread-pudding.yaml',
      '1 cup Nutella',
      2710289,
      320.0,
    ),
    ('1207-nutella-tart.yaml', '1¼ cups Nutella', 2710289, 400.0),
  ];

  test('C3: every line the 13 live searches moved counts on its record, '
      'over the gate, at the grams snapshot 13 stored (the small piece of '
      'baguette, none on the bread then, by its length since v37)', () async {
    for (final (_, raw, fdcId, grams) in moved) {
      final row = await computeLine(raw);
      expect(row.fdcId, fdcId, reason: raw);
      expect(belowConfidenceGate(row.confidence), isFalse, reason: raw);
      expect(
        row.grams,
        grams == null ? isNull : closeTo(grams, 0.005),
        reason: raw,
      );
    }
  });

  // (corpus file, line, FDC record): volume lines whose grams snapshot 13
  // stored from the density table's substring keys — 'milk' and
  // 'buttermilk' 1.03 g/mL, 'water' 1.0 — which resolveGrams reads BEFORE
  // the record's own "cup" portions (120 g, "cup slices" 124 g/cup): ½ cup
  // (1½ ounces) of the same powder weighs 42.5 g in 0778, the table 122 g.
  // A defect reported with this batch, fixed by matcher v18's density guard
  // (their grams: nutrition_v18_test D1): now the record's own portion.
  const densityRead = <(String, String, int)>[
    (
      '0626-grilled-glazed-boneless-skinless-chicken-breasts.yaml',
      '2 teaspoons nonfat dry milk powder',
      172195,
    ),
    (
      '1114-sweet-cream-ice-cream.yaml',
      '½ cup plus ⅓ cup nonfat dry milk powder',
      172195,
    ),
    (
      '0508-shu-mai-steamed-chinese-dumplings.yaml',
      '¼ cup chopped water chestnuts',
      170066,
    ),
    (
      '0513-sung-choy-bao-chicken-lettuce-wraps.yaml',
      '½ cup water chestnuts, cut into ¼-inch pieces',
      170066,
    ),
    (
      '0750-easy-buttermilk-waffles.yaml',
      '½ cup dried buttermilk powder',
      171274,
    ),
    ('0868-carrot-layer-cake.yaml', '⅓ cup buttermilk powder', 171274),
  ];

  test('C4: the dry-milk, buttermilk-powder and water-chestnut volume lines '
      "land on their records, weighed on the record's own portion "
      '(matcher v18; see densityRead)', () async {
    for (final (_, raw, fdcId) in densityRead) {
      final row = await computeLine(raw);
      expect(row.fdcId, fdcId, reason: raw);
      expect(row.gramSource, 'portion', reason: raw);
    }
  });

  test('C5: every C3 and C4 line is its corpus line — the same raw text, '
      'item and amounts as the corpus file stores', () {
    for (final (file, raw) in [
      for (final (file, raw, _, _) in moved) (file, raw),
      for (final (file, raw, _) in densityRead) (file, raw),
    ]) {
      final recipe = loadCorpusRecipe(file);
      final stored = [
        for (final g in recipe.ingredients) ...g.items,
      ].firstWhere((l) => l.raw == raw, orElse: () => fail('$file: $raw'));
      final line = corpusLine(raw);
      expect(line.item, stored.item, reason: raw);
      expect(line.amounts, stored.amounts, reason: raw);
    }
  }, skip: skipIfNoCorpus);
}
