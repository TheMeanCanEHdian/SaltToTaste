// Real corpus lines wrap across adjacent literals.
// ignore_for_file: no_adjacent_strings_in_list

import 'dart:convert';
import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/fdc_fixtures.dart';

/// Answers the napa sibling's detail (169979) with its recorded search hit
/// — FDC's own values for it, from Chinese black vinegar's recorded answer
/// (no snapshot cached the detail) — and counts the fetches.
class _SiblingProvider implements NutritionProvider {
  _SiblingProvider(this.inner, this.sibling);
  final FixtureProvider inner;
  final FdcFood sibling;
  final List<int> fetched = [];
  @override
  Future<List<FdcCandidate>> search(String query) => inner.search(query);
  @override
  Future<FdcFood?> food(int fdcId) async {
    fetched.add(fdcId);
    return fdcId == sibling.fdcId ? sibling : inner.food(fdcId);
  }
}

/// Matcher v11 (the checkpoint-6 review, M1–M13): every mechanism pinned
/// WITHOUT the corpus — real corpus lines and steps as strings (recipe
/// named on each), FDC answers from the recorded fixtures (sweep snapshots
/// 8 and 9).
void main() {
  final provider = FixtureProvider();
  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v11');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    db.upsertSource(slug: 'src', name: 'Test', type: 'book');
    return db;
  }

  Recipe recipeOf(
    SaltDatabase db,
    String id,
    List<String> raws, {
    List<String> steps = const [],
    List<Subsection> subsections = const [],
  }) {
    final recipe = Recipe(
      id: id,
      title: id,
      slug: id,
      source: const RecipeSource(name: 'Test', type: 'book'),
      ingredients: [
        IngredientGroup(items: [for (final raw in raws) lineOf(raw)]),
      ],
      steps: [
        for (final (i, text) in steps.indexed)
          RecipeStep(number: i + 1, text: text),
      ],
      subsections: subsections,
    );
    db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h$id');
    return recipe;
  }

  MatchBucket bucketOf(IngredientMatchRow row) => matchBucketFor(
    status: row.status,
    fdcId: row.fdcId,
    grams: row.grams,
    confidence: row.confidence,
    hold: row.hold,
    gramSource: row.gramSource,
  );

  DiscardedMedium? mediumOf(Recipe recipe, int position) {
    final line = nutritionLines(recipe)[position];
    return discardedMediumOf(recipe, line, normalizeItem(lineItemOf(line)));
  }

  IngredientMatchRow rowOf(SaltDatabase db, String id, [int position = 0]) =>
      db.ingredientMatchesFor(id).firstWhere((r) => r.position == position);

  Future<void> skipUnskip(SaltDatabase db, Recipe r, [int position = 0]) async {
    await applyMatchOverride(db, provider, r, position, {'skipped': true});
    await applyMatchOverride(db, provider, r, position, {'skipped': false});
  }

  group('M1: an un-skip never clears a LINE hold', () {
    // Paella on the Grill (0106), Cioppino (0108), Linguine allo Scoglio
    // (0348); Cioppino's mussels.
    // Since v40 (E2) the clams are counted on SR 174214's shell yield: the
    // held lines are the mussels and Garlicky Shrimp, Tomato, and White
    // Bean Stew's (0429) shell-on shrimp.
    const mussels = '1 pound mussels, scrubbed and debearded';
    const shrimp =
        '1 pound large shell-on shrimp (26 to 30 per pound), peeled, '
        'deveined (see this page), and tails removed, shells reserved';
    // Skillet-Roasted Chicken in Lemon Sauce (0142): 4 teaspoons of zest,
    // over the citrus rule's tablespoon — held second_food.
    const heldZest =
        '4 teaspoons grated lemon zest plus ¼ cup juice (2 lemons)';
    // Sesame Noodles with Shredded Chicken (0519).
    const noodleWater =
        'Bring 6 quarts water to a boil in a large pot. Add the noodles and '
        'salt and cook, stirring often, until tender, about 4 minutes for '
        'fresh and 10 minutes for dried. Drain the noodles, rinse them under '
        'cold running water until cold, then toss them with the sesame oil.';

    test(
      'in_shell: a decision inherited from another recipe, skipped then '
      'un-skipped, stays held (the fleets: 1,814 g of mussels counted, '
      "0294); an engine row too; the person's own confirm clears it",
      () async {
        final db = tempDb();
        final a = recipeOf(db, 'ra', [mussels]);
        final b = recipeOf(db, 'rb', [mussels]);
        final c = recipeOf(db, 'rc', [shrimp]);
        for (final r in [a, b, c]) {
          await matchAndCompute(db, provider, r);
        }
        await applyMatchOverride(db, provider, a, 0, {'confirmed': true});
        await matchAndCompute(db, provider, b);
        var row = rowOf(db, 'rb');
        expect(
          (row.status, row.confidence, row.hold),
          ('auto', 1.0, 'in_shell'),
        );
        await skipUnskip(db, b);
        row = rowOf(db, 'rb');
        expect((row.status, row.hold), ('auto', 'in_shell'));
        expect(bucketOf(row), MatchBucket.check);
        expect(db.nutritionFor('rb')!.status, 'partial');
        // An engine row (0.99) the same.
        expect(rowOf(db, 'rc').confidence, lessThan(1));
        await skipUnskip(db, c);
        expect(rowOf(db, 'rc').hold, 'in_shell');
        // Only a confirm or a pick on the line clears it.
        await applyMatchOverride(db, provider, b, 0, {'confirmed': true});
        row = rowOf(db, 'rb');
        expect((row.status, row.hold), ('confirmed', null));
        expect(bucketOf(row), MatchBucket.counted);
      },
    );

    test('second_food and discarded_medium: an inherited decision, skipped '
        'then un-skipped, keeps them', () async {
      final db = tempDb();
      final a = recipeOf(db, 'ra', [heldZest, '1 teaspoon table salt']);
      final b = recipeOf(
        db,
        'rb',
        [
          heldZest,
          '1 tablespoon table salt',
        ],
        steps: [noodleWater],
      );
      for (final r in [a, b]) {
        await matchAndCompute(db, provider, r);
      }
      await applyMatchOverride(db, provider, a, 0, {'fdc_id': 167749});
      await applyMatchOverride(db, provider, a, 1, {'confirmed': true});
      await matchAndCompute(db, provider, b);
      for (final (position, hold) in [
        (0, 'second_food'),
        (1, 'discarded_medium'),
      ]) {
        var row = rowOf(db, 'rb', position);
        expect((row.confidence, row.hold), (1.0, hold), reason: hold);
        await skipUnskip(db, b, position);
        row = rowOf(db, 'rb', position);
        expect((row.status, row.hold), ('auto', hold), reason: hold);
        expect(bucketOf(row), MatchBucket.check, reason: hold);
      }
    });
  });

  group('M2/M3: shellfish bought in the shell', () {
    test('every line of the library the rule holds — the peeled shell-on '
        'shrimp too (Garlicky Shrimp, Tomato, and White Bean Stew, 0429): '
        'its pound is weighed with the shells', () {
      for (final raw in [
        // Paella on the Grill (0106), Cioppino (0108), Linguine allo
        // Scoglio (0348); Indoor Clambake (0295); Cataplana (1120); New
        // England Clam Chowder (0034).
        '1 pound littleneck clams, scrubbed',
        '2 pounds small littleneck or cherrystone clams, scrubbed',
        '3 pounds littleneck or Manila clams, scrubbed',
        '7 pounds medium-size hard-shell clams, such as cherrystones, '
            'washed and scrubbed clean',
        // Paella (0105); Cioppino, Linguine allo Scoglio, Caldo de Siete
        // Mares (1207); Indoor Clambake; Oven-Steamed Mussels (0294).
        '1 dozen mussels, scrubbed and debearded',
        '1 pound mussels, scrubbed and debearded',
        '2 pounds mussels, scrubbed and debearded',
        '4 pounds mussels, scrubbed and debearded',
        // Roasted Oysters on the Half Shell with Mustard Butter (1184).
        '24 oysters, 2½ to 3 inches long, well scrubbed',
        // Indoor Clambake; Flambéed Pan-Roasted Lobster (0291). (New
        // England Lobster Roll's "4 (1¼-pound) live lobsters", 0292, is a
        // subsection's line: never matched.)
        '2 (1½-pound) live lobsters',
        '2 (1½- to 2-pound) live lobsters',
        // Crispy Salt-and-Pepper Shrimp (0279); Garlicky Roasted Shrimp
        // with Parsley and Anise (0280).
        '1½ pounds shell-on shrimp (31 to 40 per pound)',
        '2 pounds shell-on jumbo shrimp (16 to 20 per pound)',
        // Garlicky Shrimp, Tomato, and White Bean Stew (0429): bought in
        // the shell, peeled by the cook (the user's ruling holds it).
        '1 pound large shell-on shrimp (26 to 30 per pound), peeled, '
            'deveined (see this page), and tails removed, shells reserved',
      ]) {
        expect(boughtInShell(raw), isTrue, reason: raw);
      }
      // Peeled shrimp the line never says were bought shell-on (Brazilian
      // Shrimp and Fish Stew, 0284) are not held.
      expect(
        boughtInShell(
          '1 pound large shrimp (26 to 30 per pound), peeled, deveined (see '
          'this page), and tails removed',
        ),
        isFalse,
      );
    });

    test('a fresh engine match holds an amount-less line and a counted line '
        'in the shell, never 0 g counted: Paella (0105)', () async {
      final db = tempDb();
      // No corpus line buys shellfish without an amount: synthesized (a
      // stated exception) from Paella on the Grill's clams. (Roasted
      // Oysters' line (1184) left this pin in v13: its pick is "Oysters,
      // raw" (2706351), whose detail no snapshot holds — pending one live
      // fetch; its ranking is pinned in nutrition_v13_test.)
      final r = recipeOf(db, 'r1', [
        'littleneck clams, scrubbed',
        '1 dozen mussels, scrubbed and debearded',
      ]);
      await matchAndCompute(db, provider, r);
      final clams = rowOf(db, 'r1');
      expect(clams.fdcId, isNotNull);
      expect(clams.hold, 'in_shell');
      expect(bucketOf(clams), MatchBucket.check);
      expect(clams.grams, isNull);
      // v39 (Y2): the dozen mussels are 12 × FNDDS's "1 mussel" 15 g of
      // meat — a per-item read needs no shell yield, so it is counted.
      final mussels = rowOf(db, 'r1', 1);
      expect((mussels.fdcId, mussels.hold), (2706350, null));
      expect((mussels.grams, mussels.gramSource), (180, 'piece'));
      expect(bucketOf(mussels), MatchBucket.counted);
      // The decided path the same: never 0 g.
      final line = nutritionLines(r).first;
      final decided = engineOutcome(
        r,
        line,
        (await provider.food(2706338))!,
        null,
        decided: true,
      );
      expect((decided.grams, decided.hold), (null, 'in_shell'));
    });
  });

  group('M4–M7: the water and dissolve rules', () {
    // Classic Spaghetti and Meatballs for a Crowd (0358): steps 3, 4, 6, 7.
    const meatballs =
        'Mix the ground beef, ground pork, prosciutto, eggs, Parmesan, '
        'parsley, garlic, salt, pepper, and gelatin mixture into the '
        'bread-crumb mixture using your hands. Pinch off and roll the mixture '
        'into 2-inch meatballs (about 40 meatballs total) and arrange on the '
        'prepared sheets. Bake until well browned, about 30 minutes, '
        'switching and rotating the sheets halfway through baking.';
    const sauce =
        'While the meatballs bake, heat the oil in a Dutch oven over medium '
        'heat until shimmering. Add the onion and cook until softened and '
        'lightly browned, 5 to 7 minutes. Stir in the garlic, oregano, and '
        'red pepper flakes and cook until fragrant, about 30 seconds. Stir in '
        'the crushed tomatoes, tomato juice, wine, 1½ teaspoons salt, and ¼ '
        'teaspoon pepper, bring to a simmer, and cook until thickened '
        'slightly, about 15 minutes.';
    const pasta =
        'Meanwhile, bring 10 quarts water to boil in a 12-quart pot. Add the '
        'pasta and salt and cook, stirring often, until al dente. Reserve ½ '
        'cup of the cooking water, then drain the pasta and return it to the '
        'pot.';
    const season =
        'Gently stir the basil and parsley into the sauce and season with '
        'sugar, salt, and pepper to taste. Add 2 cups of the sauce (without '
        'meatballs) to the pasta and toss to combine, adding the reserved '
        'cooking water to adjust the consistency as needed. Serve, topping '
        'individual portions with more tomato sauce and several meatballs '
        'and passing the Parmesan separately.';

    test('M4: a dissolve makes a brine only of the salt it dissolves, in a '
        'step that submerges the food — Grilled Glazed Baby Back Ribs (0617) '
        'stays one', () {
      final db = tempDb();
      Recipe one(String id, String step) =>
          recipeOf(db, id, ['1 tablespoon salt'], steps: [step]);
      final ribs = recipeOf(
        db,
        'ribs',
        ['2 tablespoons salt'],
        steps: [
          'Dissolve salt in 2½ quarts water in Dutch oven; place ribs in pot '
              'so they are fully submerged. Bring to simmer over high heat.',
        ],
      );
      expect(mediumOf(ribs, 0), DiscardedMedium.brine);
      // No corpus line has these shapes: synthesized (stated exceptions).
      // The salt after the dissolve's "in 2 quarts" is not its object.
      expect(
        mediumOf(
          one(
            'object',
            'Dissolve the sugar in 2 quarts cold water, then stir in the salt '
                'and submerge the pork.',
          ),
          0,
        ),
        isNull,
      );
      // A dough's salt dissolved in measured water is eaten: no submerge.
      expect(
        mediumOf(
          one(
            'dough',
            'Dissolve salt in 2 tablespoons warm water. Add to flour and '
                'knead into a dough.',
          ),
          0,
        ),
        isNull,
      );
      // Sonnet's reproduction: neither clause holds.
      expect(
        mediumOf(
          one(
            'yeast',
            'Dissolve sugar in 2 cups warm water, then whisk in the salt and '
                'yeast until smooth.',
          ),
          0,
        ),
        isNull,
      );
      // The dissolve in a LATER sentence of the step is read in its own
      // sentence (no corpus salt is dissolved past a step's first sentence
      // under the volume threshold: synthesized, a stated exception).
      expect(
        mediumOf(
          one(
            'later',
            'Place the ribs in a Dutch oven. Dissolve salt in 2½ quarts water '
                'and pour it over the ribs so they are fully submerged.',
          ),
          0,
        ),
        DiscardedMedium.brine,
      );
      // The salt BEFORE the dissolve is not its object either, though an
      // "in 2 quarts" follows it (the verb-before-the-mention clause).
      expect(
        mediumOf(
          one(
            'before',
            'Season the pork with the salt, then dissolve the sugar in 2 '
                'quarts cold water and submerge the pork.',
          ),
          0,
        ),
        isNull,
      );
    });

    test('M5: Classic Macaroni and Cheese (0300) holds its pasta-water salt '
        'with the eaten "remaining 1 teaspoon" as its grams; a confirm '
        'counts that part', () async {
      final db = tempDb();
      final r = recipeOf(
        db,
        'r1',
        ['1 tablespoon plus 1 teaspoon table salt'],
        steps: [
          'Adjust an oven rack to the lower-middle position and heat the '
              'broiler. Bring 4 quarts water to a rolling boil in a large pot. '
              'Add 1 tablespoon of the salt and the macaroni and stir to '
              'separate the noodles. Cook until tender, drain, and set aside.',
          'In the now-empty pot, melt the butter over medium-high heat. Add '
              'the flour, mustard, cayenne (if using), and remaining 1 '
              'teaspoon salt and whisk well to combine.',
        ],
      );
      expect(mediumOf(r, 0), DiscardedMedium.cookingWater);
      await matchAndCompute(db, provider, r);
      var row = rowOf(db, 'r1');
      expect((row.hold, row.gramSource), ('discarded_medium', 'discarded'));
      expect(row.grams, closeTo(6.01, 0.01));
      expect(bucketOf(row), MatchBucket.check);
      expect(
        gramBasisFor(db, nutritionLines(r).single, row),
        'discarded in cooking — only "plus 1 teaspoon table salt" counted',
      );
      await applyMatchOverride(db, provider, r, 0, {'confirmed': true});
      row = rowOf(db, 'r1');
      expect((row.hold, bucketOf(row)), (null, MatchBucket.counted));
      expect(row.grams, closeTo(6.01, 0.01));
    });

    test('M5: a "plus" line that is no medium counts in full though a step '
        'eats its second part — Homemade Naan (0562), Best Almond Cake '
        '(0870)', () async {
      final db = tempDb();
      final naan = recipeOf(
        db,
        'naan',
        ['3 tablespoons plus 1 teaspoon vegetable oil'],
        steps: [
          'Using fork, poke entire surface of round 20 to 25 times. Heat '
              'remaining 1 teaspoon oil in 12-inch cast-iron skillet over '
              'medium heat until shimmering.',
        ],
      );
      final cake = recipeOf(
        db,
        'cake',
        ['1¼ cups (8¾ ounces) plus 2 tablespoons sugar'],
        steps: [
          'Using your fingers, combine remaining 2 tablespoons sugar and '
              'remaining ½ teaspoon lemon zest in small bowl until fragrant, '
              '5 to 10 seconds. Sprinkle top of cake evenly with remaining ⅓ '
              'cup almonds followed by sugar-zest mixture.',
        ],
      );
      for (final (r, grams) in [(naan, 46.53), (cake, 273.20)]) {
        expect(mediumOf(r, 0), isNull, reason: r.id);
        await matchAndCompute(db, provider, r);
        final row = rowOf(db, r.id);
        expect(row.grams, closeTo(grams, 0.01), reason: r.id);
        expect(row.gramSource, isNot('discarded'), reason: r.id);
      }
    });

    test('M6: a bare salt in cooking water is the one salt line no step '
        'names with its amount — 0358 and Simplified Cassoulet (0461) — never '
        "a brine's (Herbed Roast Turkey, 0170)", () {
      final db = tempDb();
      final spaghetti = recipeOf(
        db,
        'spaghetti',
        [
          '1½ teaspoons table salt',
          'Table salt and ground black pepper',
          '2 tablespoons table salt',
        ],
        steps: [meatballs, sauce, pasta, season],
      );
      expect(mediumOf(spaghetti, 2), DiscardedMedium.cookingWater);
      expect(mediumOf(spaghetti, 0), isNull);
      final cassoulet = recipeOf(
        db,
        'cassoulet',
        ['½ cup table salt', '1 teaspoon table salt'],
        steps: [
          'Dissolve the sugar and salt in 1 quart cold water in a gallon-size '
              'zipper-lock bag. Add the chicken, pressing out as much air as '
              'possible, seal the bag, and refrigerate for 1 hour. Remove the '
              'chicken from the brine, rinse, and pat dry with paper towels. '
              'Refrigerate until ready to use.',
          'Bring the beans, the peeled onion, head of garlic, salt, ¼ teaspoon '
              'pepper, and 8 cups water to a boil in a large Dutch oven over '
              'high heat. Cover, reduce the heat to medium-low, and simmer '
              'until the beans are almost tender, 1¼ to 1½ hours. Drain the '
              'beans; discard the onion and garlic.',
        ],
      );
      expect(mediumOf(cassoulet, 0), DiscardedMedium.brine);
      expect(mediumOf(cassoulet, 1), DiscardedMedium.cookingWater);
      final turkey = recipeOf(
        db,
        'turkey',
        ['2 cups table salt', '¾ teaspoon table salt'],
        steps: [
          'Dissolve the salt in 2 gallons cold water in a large container. '
              'Submerge the turkey in the brine, cover, and refrigerate or '
              'store in a very cool spot (40 degrees or less) for 4 to 6 '
              'hours.',
          'Pulse the parsley, thyme, sage, rosemary, shallot, garlic, lemon '
              'zest, salt, and pepper together in a food processor until a '
              'coarse paste is formed, 10 pulses.',
        ],
      );
      expect(mediumOf(turkey, 0), DiscardedMedium.brine);
      expect(mediumOf(turkey, 1), isNull);
    });

    test("M7: a subsection's steps never make a main line a medium — no "
        'corpus recipe has the shape: a synthesized subsection (a stated '
        "exception) of 0358's own pasta pot", () {
      final db = tempDb();
      final r = recipeOf(
        db,
        'r1',
        ['1½ teaspoons table salt'],
        steps: [sauce],
        subsections: [
          const Subsection(
            title: 'For the pasta',
            kind: 'component',
            ingredients: [
              IngredientGroup(
                items: [IngredientLine(raw: 'Salt', item: 'Salt')],
              ),
            ],
            steps: [RecipeStep(number: 1, text: pasta)],
          ),
        ],
      );
      expect(mediumOf(r, 0), isNull);
      // The same pot in the recipe's own steps is its cooking water.
      final own = recipeOf(
        db,
        'r2',
        ['1½ teaspoons table salt'],
        steps: [pasta],
      );
      expect(mediumOf(own, 0), DiscardedMedium.cookingWater);
    });
  });

  group("M8: the approximate label is the line's, never the cache's", () {
    const approximate = '· approximate (gross weight, no USDA refuse portion)';

    test('a counted weight line on an FNDDS hit whose detail no compute '
        'fetches: Braised Oxtails (0089)', () async {
      final db = tempDb();
      final r = recipeOf(db, 'r1', ['4 pounds oxtails, trimmed']);
      await matchAndCompute(db, provider, r);
      final row = rowOf(db, 'r1');
      expect((row.fdcId, row.hold), (2705843, null));
      expect(bucketOf(row), MatchBucket.counted);
      // v39 (Y1): the record's own "1 oz yields 16 g", read from the class
      // table — no detail fetched.
      expect(row.grams, closeTo(4 * 453.592 * 16 / 28.349523125, 0.01));
      expect(db.fdcFoodCacheGet(2705843), isNull);
      expect(
        gramBasisFor(db, nutritionLines(r).single, row),
        'from 4 pound × 0.56 edible · approximate (yield of oxtails from FDC '
        '2705843)',
      );
    });

    // Matcher v30 moved the first pins (Barbecued Pulled Pork's Boston butt
    // now reads its record's refuse, Braised Turkey's drumsticks an SR
    // record); v32 moved the fresh ham (0249) onto its rank-as item, whose
    // compute fetches 168226 (no refuse yield: approximate). No corpus line
    // of the v32 replay is an SR hit left unfetched, so the "no yield read"
    // label is pinned on the ham's own search hit (168226 with no portions,
    // as a compute holds it before its detail is fetched); Hearty Chicken
    // Noodle Soup's breast halves (0002) stay a Foundation hit.
    test(
      'an SR hit never fetched says no yield was read — Roast Fresh Ham '
      "(0249)'s search hit; its fetched detail publishes none, so the "
      'compute says approximate; a Foundation or FNDDS hit with no '
      'portions is approximate — Hearty Chicken Noodle Soup (0002)',
      () async {
        const hamLine =
            '1 (6- to 8-pound) bone-in fresh half ham with skin, preferably '
            'shank end, rinsed';
        final hit = (await provider.search(
          'bone-in half ham with skin',
        )).firstWhere((c) => c.fdcId == 168226);
        final parsed = parseIngredientLine(hamLine);
        expect(
          resolveGrams(
            amounts: parsed.amounts,
            food: FdcFood(
              fdcId: hit.fdcId,
              description: hit.description,
              dataType: hit.dataType,
              nutrientsPer100g: hit.nutrientsPer100g!,
              portions: const [],
            ),
            normalizedItem: normalizeItem(parsed.item ?? hamLine),
            raw: hamLine,
          )?.basis,
          'from the printed weight · no edible yield read',
        );
        final db = tempDb();
        final r = recipeOf(db, 'r1', [
          hamLine,
          '2 (12-ounce) bone-in, skin-on chicken breast halves, cut in half '
              'crosswise',
        ]);
        await matchAndCompute(db, provider, r);
        final lines = nutritionLines(r);
        final ham = rowOf(db, 'r1');
        expect((ham.fdcId, ham.dataType), (168226, 'SR Legacy'));
        expect(db.fdcFoodCacheGet(168226), isNotNull);
        // v39 (Y1): approximate at its class yield (gross until v38); v43
        // (Y10): the shank half's derived AH-102 yield.
        expect(
          gramBasisFor(db, lines[0], ham),
          'from the printed weight × 0.78 edible · approximate (derived from '
          'USDA AH-102 item 1930: fresh ham shank half, raw → bones 22 %, so '
          'lean and fat meat 78 % (the printed row also trims the fat 18: '
          'lean 60 %))',
        );
        final breast = rowOf(db, 'r1', 1);
        expect((breast.fdcId, breast.dataType), (2727569, 'Foundation'));
        expect(db.fdcFoodCacheGet(2727569), isNull);
        expect(
          gramBasisFor(db, lines[1], breast),
          // v43 (Y1): AH-102 item 584, the breast's meat and skin.
          '2 × 340 g (printed weight) × 0.74 edible · approximate (USDA '
          'AH-102 item 584: chicken breast, raw → meat and skin 74 % (59–84))',
        );
      },
    );

    test("a person's confirm counts a line in the shell at its gross weight: "
        'labelled approximate (Cioppino, 0108)', () async {
      final db = tempDb();
      final r = recipeOf(db, 'r1', ['1 pound mussels, scrubbed and debearded']);
      await matchAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 0, {'confirmed': true});
      final row = rowOf(db, 'r1');
      expect((row.status, row.hold), ('confirmed', null));
      expect(
        gramBasisFor(db, nutritionLines(r).single, row),
        'from 1 pound $approximate',
      );
    });
  });

  group('M9–M12: ties, lime peel, the napa sibling, staleness', () {
    test(
      'M9: a tie goes to the lean-and-fat record and the record of no '
      "cooking, whatever FDC's order — Sweet and Tangy Grilled "
      'Country-Style Pork Ribs (0612), French-Style Pork Stew (0462)',
      () async {
        final ribs = searchQueryFor(
          normalizeItem(
            lineItemOf(
              lineOf('4 pounds bone-in country-style pork ribs, trimmed'),
            ),
          ),
        );
        expect(ribs, 'pork spareribs or country-style ribs or beef short ribs');
        for (final (query, winner, loser) in [
          (ribs, 167895, 168305), // separable lean and fat / lean only
          ('kielbasa', 173879, 173877), // fully cooked, unheated / grilled
        ]) {
          final answer = await provider.search(query);
          for (final order in [answer, answer.reversed.toList()]) {
            final ranked = rankCandidates(query, order);
            expect(ranked.first.candidate.fdcId, winner, reason: query);
            final tied = ranked.firstWhere((c) => c.candidate.fdcId == loser);
            expect(tied.confidence, ranked.first.confidence, reason: query);
            expect(
              belowConfidenceGate(tied.confidence),
              isFalse,
              reason: query,
            );
          }
        }
      },
    );

    test('M10: lime zest counts as "Lemon peel, raw" — a flagged '
        'approximation (FDC has no lime peel), in either answer order: Thai '
        'Chicken Curry (0550), Jerk Chicken (0632), Key Lime Bars (0849); the '
        'Fresh Margaritas (0470) line stays held by the zest cap', () async {
      expect(searchQueryFor('lime zest'), 'lemon zest');
      final answer = await provider.search('lemon zest');
      for (final order in [answer, answer.reversed.toList()]) {
        final ranked = rankCandidates('lemon zest', order);
        expect(ranked.first.candidate.fdcId, 167749);
        expect(ranked.first.confidence, closeTo(0.887, 0.001));
        expect(ranked[1].confidence, lessThan(ranked.first.confidence));
      }
      final db = tempDb();
      final r = recipeOf(db, 'r1', [
        '2 teaspoons grated lime zest',
        '2 tablespoons finely grated lime zest (3 limes), plus lime wedges '
            'for serving',
        '1 tablespoon grated zest from 1 lime',
        '4 teaspoons grated zest plus ½ cup juice from 4 limes',
      ]);
      await matchAndCompute(db, provider, r);
      final rows = db.ingredientMatchesFor('r1');
      for (final row in rows.take(3)) {
        expect(row.fdcId, 167749, reason: row.raw);
        expect(bucketOf(row), MatchBucket.counted, reason: row.raw);
      }
      expect((rows.last.fdcId, rows.last.hold), (167749, 'second_food'));
    });

    test('M11: Pork and Cabbage Dumplings (0506) napa alone fetches its '
        'sibling once and counts; hand-entered grams still name it', () async {
      final hit = (await provider.search(
        'chinese black vinegar',
      )).firstWhere((c) => c.fdcId == 169979);
      final sibling = _SiblingProvider(provider, hit.toFood());
      final db = tempDb();
      final r = recipeOf(db, 'r1', [
        '12 ounces napa cabbage (½ medium head), cored and minced',
      ]);
      await matchAndCompute(db, sibling, r);
      expect(sibling.fetched.where((id) => id == 169979), hasLength(1));
      final stored = db.nutritionFor('r1')!;
      expect(stored.status, 'complete');
      final energy = (jsonDecode(stored.nutrientsJson) as Map)['energy'] as Map;
      expect(energy['amount'], closeTo(340.19 * 16 / 100, 0.01));
      await applyMatchOverride(db, sibling, r, 0, {'grams': 400});
      expect(sibling.fetched.where((id) => id == 169979), hasLength(1));
      expect(
        gramBasisFor(db, nutritionLines(r).single, rowOf(db, 'r1')),
        'entered by hand · nutrients of "Cabbage, chinese (pe-tsai), raw"',
      );
    });

    test('M12: a steps-only or title-only edit makes the recipe stale (the '
        "critic's noodles, Sesame Noodles 0519)", () async {
      final db = tempDb();
      const drained =
          'Bring 6 quarts water to a boil in a large pot. Add the noodles and '
          'salt and cook, stirring often, until tender, about 4 minutes for '
          'fresh and 10 minutes for dried. Drain the noodles, rinse them '
          'under cold running water until cold, then toss them with the '
          'sesame oil.';
      final r = recipeOf(
        db,
        'r1',
        ['1 tablespoon table salt'],
        steps: [drained],
      );
      await matchAndCompute(db, provider, r);
      final stored = db.nutritionFor('r1')!.ingredientsHash;
      expect(stored, ingredientsHashOf(r, ResolverMemo(db)));
      // No drain: synthesized (the critic's reproduction).
      final undrained = r.copyWith(
        steps: const [
          RecipeStep(number: 1, text: 'Serve the noodles in their broth.'),
        ],
      );
      expect(ingredientsHashOf(undrained, ResolverMemo(db)), isNot(stored));
      expect(
        ingredientsHashOf(r.copyWith(title: 'Noodles'), ResolverMemo(db)),
        isNot(stored),
      );
    });
  });
}
