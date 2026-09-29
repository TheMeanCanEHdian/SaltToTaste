// Real corpus lines wrap across adjacent literals.
// ignore_for_file: no_adjacent_strings_in_list

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
/// spells another way (each target pending ONE live search, never an
/// invented answer), rewrites to answers snapshot 12 already holds, an
/// unasked 'liquid' docked as a modified form, and eight SR volume
/// siblings whose detail is fetched once. Real corpus lines (recipe named on
/// each, pinnedCorpusText proves each exists); FDC answers recorded from
/// sweep snapshot 12 (tool/record_fdc_fixtures.dart --from-db).
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

  test('R1: each v17 rewrite searches its target — a name FDC spells '
      'another way is PENDING one live search (answered as no hits, never '
      'invented); a target snapshot 12 holds ranks the named record first, '
      'over the gate', () async {
    const cached = {
      'pork spareribs or country-style ribs or beef short ribs': 167895,
      'bone-in turkey breast': 171093,
      'jarred hot cherry peppers': 2709798,
      'garlic powder': 171325,
    };
    for (final (_, raw, item, target) in rewrites) {
      expect(searchQueryFor(item), target, reason: item);
      final fdcId = cached[target];
      if (fdcId == null) {
        expect(pendingSearches, contains(target), reason: item);
        expect(await provider.search(target), isEmpty, reason: item);
        continue;
      }
      // Ranked as the engine ranks the line: a whole bone-in breast is
      // skin-on ([impliesSkinOn]).
      final top = rankCandidates(
        target,
        await provider.search(target),
        skinOn: impliesSkinOn(raw, item),
      ).first;
      expect(top.candidate.fdcId, fdcId, reason: item);
      expect(belowConfidenceGate(top.confidence), isFalse, reason: item);
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
      expect(lineGrams(db, lineOf(wellington), roast), isNull);
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

  test(
    'S1: the eight v17 volume siblings — a volume line on the '
    'portion-less Foundation record asks FDC for exactly its SR '
    "sibling's detail, once (unrecorded: the approved fetch is pending)",
    () async {
      // (Foundation record, SR sibling, a corpus volume line on it).
      const siblings = <(int, int, String)>[
        (2346395, 170182, '2 cups raw pecan halves'), // 0719
        (1104647, 169230, '1 teaspoon garlic, minced to paste'), // 0504
        (2346407, 169975, '3 cups thinly sliced green cabbage'), // 0542
        (2258586, 170393, '2⅔ cups shredded carrots (4 carrots)'), // 0868
        (2346405, 169988, '2 tablespoons minced celery'), // 0292
        (1999632, 168462, '1 cup baby spinach'), // 0603
        (2346388, 169248, '2 cups shredded iceberg lettuce'), // 1185
        (
          2727583,
          169979,
          '6 cups napa cabbage, sliced crosswise into ½-inch strips', // 0520
        ),
      ];
      for (final (foundation, sibling, raw) in siblings) {
        expect(volumeSiblings[foundation], sibling, reason: raw);
        final food = (await provider.food(foundation))!;
        final line = lineOf(raw);
        final db = tempDb();
        // The record's own detail sizes nothing: only the sibling can.
        expect(lineGrams(db, line, food), isNull, reason: raw);
        await expectLater(
          gramsFor(db, provider, food, line),
          throwsA(
            isA<UnrecordedAnswer>().having(
              (e) => e.message,
              'message',
              contains('food $sibling'),
            ),
          ),
          reason: raw,
        );
      }
    },
  );

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
        (171093, '3175.14'),
        (2709798, '1.00'),
      ],
    );
    for (final r in rows) {
      expect(belowConfidenceGate(r.confidence), isFalse, reason: r.raw);
    }
  });

  test('C2: milk chocolate never lands on the chocolate-MILK drink '
      '(2705467): the line asks "milk chocolate candy" — pending its one '
      'live search, it is unmatched, not the drink (1168)', () async {
    final db = tempDb();
    final fixtures = FixtureProvider(pending: pendingSearches);
    await matchAndCompute(
      db,
      fixtures,
      recipeOf(db, ['12 ounces milk chocolate, chopped fine']),
    );
    final row = db.ingredientMatchesFor('r').single;
    expect(row.fdcId, isNull);
    expect(fixtures.searchCalls, 1);
    expect(db.fdcSearchCacheGet('milk chocolate candy'), '[]');
    expect(db.fdcSearchCacheGet('milk chocolate'), isNull);
  });
}
