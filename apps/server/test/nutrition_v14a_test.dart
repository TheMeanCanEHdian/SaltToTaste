// Real corpus lines and steps wrap across adjacent literals.
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

/// Matcher v14, fixer A (the Run 045 union, the checkpoint-8 fixes B1, B6
/// and B7, the user's rulings Q1, Q3 and Q4 of 2026-09-28): every mechanism
/// pinned WITHOUT the corpus — real corpus lines and step texts as strings
/// (recipe named on each), FDC answers recorded from sweep snapshot 12. A
/// guard no corpus line exercises is pinned on a synthesized input, said so
/// where it is.
void main() {
  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v14a');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    db.upsertSource(slug: 'src', name: 'Test', type: 'book');
    return db;
  }

  Recipe recipeOf(
    List<String> raws, {
    List<String> steps = const [],
    String title = 'r',
    List<Subsection> subsections = const [],
    SaltDatabase? db,
  }) {
    final recipe = Recipe(
      id: 'r',
      title: title,
      slug: 'r',
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
    db?.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h');
    return recipe;
  }

  Subsection subsectionOf(String title, List<String> raws) => Subsection(
    title: title,
    kind: 'variation',
    ingredients: [
      IngredientGroup(items: [for (final raw in raws) lineOf(raw)]),
    ],
  );

  MatchBucket bucketOf(IngredientMatchRow row) => matchBucketFor(
    status: row.status,
    fdcId: row.fdcId,
    grams: row.grams,
    confidence: row.confidence,
    hold: row.hold,
    gramSource: row.gramSource,
  );

  // Curry Deviled Eggs with Easy-Peel Hard-Cooked Eggs (0731).
  const deviledLine = '1 recipe Easy-Peel Hard-Cooked Eggs (recipe follows)';
  final easyPeel = subsectionOf('Easy-Peel Hard-Cooked Eggs', [
    '6 large eggs',
  ]);

  group('B1: the engine rewrites its own rule rows', () {
    test('a v13 sub-recipe row of Curry Deviled Eggs (0731) is rewritten '
        'to its counted eggs; a changes() of 0 no longer blocks it', () async {
      final db = tempDb();
      final recipe = recipeOf(db: db, [deviledLine], subsections: [easyPeel]);
      // What v13 stored: the engine's own confirmed note on no food.
      db.upsertIngredientMatch(
        IngredientMatchRow(
          recipeId: 'r',
          position: 0,
          raw: deviledLine,
          itemKey: 'easy-peel hard-cooked egg',
          fdcId: null,
          description: subRecipeNote,
          dataType: null,
          confidence: 1,
          grams: 0,
          gramSource: 'unmeasured',
          status: 'confirmed',
        ),
      );
      await matchAndCompute(db, FixtureProvider(), recipe);
      final row = db.ingredientMatchesFor('r').single;
      expect(
        (row.fdcId, row.grams, row.gramSource, row.status),
        (173424, 300, 'piece', 'auto'),
      );
    });

    test('a v13 sub-recipe row MOVED by an edit above it is re-derived at '
        'its new position, never carried (0731, "8 cups water" put above it: '
        'a synthesized edit, a stated exception)', () async {
      final db = tempDb();
      final recipe = recipeOf(
        db: db,
        ['8 cups water', deviledLine],
        subsections: [easyPeel],
      );
      db.upsertIngredientMatch(
        IngredientMatchRow(
          recipeId: 'r',
          position: 0,
          raw: deviledLine,
          itemKey: 'easy-peel hard-cooked egg',
          fdcId: null,
          description: subRecipeNote,
          dataType: null,
          confidence: 1,
          grams: 0,
          gramSource: 'unmeasured',
          status: 'confirmed',
        ),
      );
      await matchAndCompute(db, FixtureProvider(), recipe);
      final row = db
          .ingredientMatchesFor('r')
          .singleWhere(
            (row) => row.position == 1,
          );
      expect((row.fdcId, row.grams), (173424, 300));
    });

    test("the guard: a rule row is rewritable, a person's confirm of a food "
        'or of any other note is not', () {
      final db = tempDb();
      recipeOf(db: db, [deviledLine]);
      IngredientMatchRow rowOf(int? fdcId, String description) =>
          IngredientMatchRow(
            recipeId: 'r',
            position: 0,
            raw: deviledLine,
            fdcId: fdcId,
            description: description,
            dataType: null,
            confidence: 1,
            grams: 0,
            gramSource: 'unmeasured',
            status: 'confirmed',
          );
      final engine = rowOf(173424, 'Egg, whole, cooked, hard-boiled').copyWith(
        status: 'auto',
      );
      for (final note in engineRuleNotes) {
        db.upsertIngredientMatch(rowOf(null, note));
        expect(db.upsertIngredientMatchIfUndecided(engine), isTrue);
      }
      for (final person in [
        rowOf(173424, 'Egg, whole, cooked, hard-boiled'),
        rowOf(null, 'No FoodData Central match'),
      ]) {
        db.upsertIngredientMatch(person);
        expect(db.upsertIngredientMatchIfUndecided(engine), isFalse);
      }
    });
  });

  group('the sub-recipe rule (Q1, Q4, B7; Run 045 A1, A4, A5)', () {
    test('Q1: "1 recipe Easy-Peel Hard-Cooked Eggs" is the subsection\'s "6 '
        'large eggs" on the line\'s own pick — 300 g of "Egg, whole, cooked, '
        'hard-boiled" (Curry Deviled Eggs, 0731)', () async {
      final db = tempDb();
      final recipe = recipeOf(db: db, [deviledLine], subsections: [easyPeel]);
      final line = nutritionLines(recipe).single;
      expect(line.raw, deviledLine);
      expect(countOf(line.amounts), 6);
      expect(identical(line, nutritionLines(recipe).single), isTrue);
      await matchAndCompute(db, FixtureProvider(), recipe);
      final row = db.ingredientMatchesFor('r').single;
      expect(
        (row.fdcId, row.grams, row.gramSource, row.itemKey),
        (173424, 300, 'piece', 'easy-peel hard-cooked egg'),
      );
      expect(bucketOf(row), MatchBucket.counted);
      expect(gramBasisFor(db, line, row), isNotNull);
    });

    test('Q1: every other "1 recipe X" stays 0 g — Salade Lyonnaise\'s (0434) '
        '"1 recipe Perfect Poached Eggs" names three foods, and is a '
        'sub-recipe with no mark at all (B7)', () async {
      final db = tempDb();
      final fixtures = FixtureProvider();
      const raw = '1 recipe Perfect Poached Eggs';
      final recipe = recipeOf(
        db: db,
        [raw],
        subsections: [
          subsectionOf('Perfect Poached Eggs', [
            '4 large eggs',
            '1 tablespoon distilled white vinegar',
            'Table salt for poaching eggs',
          ]),
        ],
      );
      expect(nutritionLines(recipe).single.amounts.single.unit, 'recipe');
      await matchAndCompute(db, fixtures, recipe);
      final row = db.ingredientMatchesFor('r').single;
      expect(
        (row.fdcId, row.grams, row.status, row.description),
        (null, 0, 'confirmed', subRecipeNote),
      );
      expect(fixtures.searchCalls, 0);
    });

    test('Q1 needs the subsection: the same line with none stays 0 g, and a '
        '"½ recipe" is no yield of it (a synthesized quantity: a stated '
        'exception — every corpus "recipe" line is "1 recipe")', () async {
      for (final (raw, subs) in [
        (deviledLine, const <Subsection>[]),
        ('½ recipe Easy-Peel Hard-Cooked Eggs (recipe follows)', [easyPeel]),
      ]) {
        final db = tempDb();
        final recipe = recipeOf(db: db, [raw], subsections: subs);
        await matchAndCompute(db, FixtureProvider(), recipe);
        final row = db.ingredientMatchesFor('r').single;
        expect((row.fdcId, row.grams), (null, 0), reason: raw);
      }
    });

    test('Q4: a sub-recipe offering a store-bought alternative with its own '
        'amount stays 0 g — "1 recipe Green Curry Paste (recipe follows) or 2 '
        'tablespoons store-bought green curry paste" (Thai Green Curry with '
        'Chicken, Broccoli, and Mushrooms, 0548)', () async {
      final db = tempDb();
      final fixtures = FixtureProvider();
      await matchAndCompute(
        db,
        fixtures,
        recipeOf(db: db, [
          '1 recipe Green Curry Paste (recipe follows) or 2 tablespoons '
              'store-bought green curry paste',
        ]),
      );
      final row = db.ingredientMatchesFor('r').single;
      expect((row.fdcId, row.grams, row.description), (null, 0, subRecipeNote));
      expect(fixtures.searchCalls, 0);
    });

    test('B7: Mujaddara\'s (0711) "plus 3 tablespoons reserved oil" is eaten: '
        'the Crispy Onions\' own "1½ cups vegetable oil", counted at 3 '
        'tablespoons on "Vegetable oil, NFS"; the onions stay out', () async {
      final db = tempDb();
      const raw =
          '1 recipe Crispy Onions, plus 3 tablespoons reserved oil (recipe '
          'follows)';
      final recipe = recipeOf(
        db: db,
        [raw],
        subsections: [
          subsectionOf('Crispy Onions', [
            '2 pounds onions, halved and sliced crosswise into ¼-inch-thick '
                'pieces',
            '2 teaspoons salt',
            '1½ cups vegetable oil',
          ]),
        ],
      );
      final plus = subRecipePlusLine(recipe, nutritionLines(recipe).single)!;
      expect(
        (plus.raw, plus.item, countOf(plus.amounts)),
        ('3 tablespoons reserved oil', 'vegetable oil', null),
      );
      await matchAndCompute(db, FixtureProvider(), recipe);
      final row = db.ingredientMatchesFor('r').single;
      expect((row.raw, row.fdcId, row.status), (raw, 2710180, 'auto'));
      expect(row.grams, closeTo(336 / 24 * 3, 0.01));
      expect(
        gramBasisFor(db, nutritionLines(recipe).single, row, recipe: recipe),
        '3 tablespoon · USDA portion',
      );
      expect(bucketOf(row), MatchBucket.counted);
      // With no subsection holding the oil, the line is the sub-recipe.
      final bare = tempDb();
      await matchAndCompute(bare, FixtureProvider(), recipeOf(db: bare, [raw]));
      expect(bare.ingredientMatchesFor('r').single.description, subRecipeNote);
    });

    test('A1: an amount edit never re-attaches a food to a line the rule '
        'zeroes — "4 Easy-Peel Hard-Cooked Eggs (this page), halved '
        'lengthwise" (Gado-Gado, 1192) confirmed on the egg, then edited to '
        'the "1 recipe" line (0731\'s, with no subsection)', () async {
      final db = tempDb();
      const counted =
          '4 Easy-Peel Hard-Cooked Eggs (this page), halved lengthwise';
      final fixtures = FixtureProvider();
      final before = recipeOf(db: db, [counted]);
      await matchAndCompute(db, fixtures, before);
      expect(db.ingredientMatchesFor('r').single.grams, 200);
      await applyMatchOverride(db, fixtures, before, 0, {'confirmed': true});
      expect(lineKeyOf(lineOf(deviledLine)), lineKeyOf(lineOf(counted)));
      final after = recipeOf(db: db, [deviledLine]);
      await matchAndCompute(db, fixtures, after);
      final row = db.ingredientMatchesFor('r').single;
      expect(
        (row.raw, row.fdcId, row.grams, row.description),
        (deviledLine, null, 0, subRecipeNote),
      );
    });

    test('A1 (critic): a decision reused from another recipe on a marked '
        "count's key never leaves a no-grams row — a decided food that "
        'cannot weigh "8 Home-Fried Taco Shells (recipe follows)" (Ground '
        'Beef Tacos, 0478) makes it the sub-recipe (the decided food, '
        '"Vegetable oil, NFS", is synthesized to be one no count sizes: a '
        'stated exception)', () async {
      final db = tempDb();
      const raw = '8 Home-Fried Taco Shells (recipe follows)';
      db.putDecision(
        itemKey: lineKeyOf(lineOf(raw)),
        item: decisionItemOf(lineOf(raw)),
        fdcId: 2710180,
        description: 'Vegetable oil, NFS',
        dataType: 'Survey (FNDDS)',
        decidedBy: null,
      );
      final fixtures = FixtureProvider();
      await matchAndCompute(db, fixtures, recipeOf(db: db, [raw]));
      final row = db.ingredientMatchesFor('r').single;
      expect((row.fdcId, row.grams, row.description), (null, 0, subRecipeNote));
      expect(fixtures.searchCalls, 0);
    });

    test('A1: an amount edit re-attaching a food that cannot weigh a marked '
        'count makes it the sub-recipe — "8 Home-Fried Taco Shells (recipe '
        'follows)" (0478) picked by a person as "Vegetable oil, NFS", then '
        'edited to 10 (the pick and the edit are synthesized: a stated '
        'exception)', () async {
      final db = tempDb();
      final fixtures = FixtureProvider();
      const raw = '8 Home-Fried Taco Shells (recipe follows)';
      final before = recipeOf(db: db, [raw]);
      await matchAndCompute(db, fixtures, before);
      // The pick itself is gated since v15 (Run 047, E9): a food no count
      // sizes, with no grams typed, stores the sub-recipe.
      await applyMatchOverride(db, fixtures, before, 0, {'fdc_id': 2710180});
      final picked = db.ingredientMatchesFor('r').single;
      expect(
        (picked.fdcId, picked.grams, picked.description),
        (null, 0, subRecipeNote),
      );
      // A person's pick as v14 stored it: overridden, no grams.
      db.upsertIngredientMatch(
        picked.copyWith(
          fdcId: 2710180,
          description: 'Vegetable oil, NFS',
          dataType: 'Survey (FNDDS)',
          clearGrams: true,
          clearGramSource: true,
          status: 'overridden',
        ),
      );
      final after = recipeOf(db: db, [
        '10 Home-Fried Taco Shells (recipe follows)',
      ]);
      await matchAndCompute(db, fixtures, after);
      final row = db.ingredientMatchesFor('r').single;
      expect((row.fdcId, row.grams, row.description), (null, 0, subRecipeNote));
    });

    test('A5: a marked count whose pick is below the gate was never fetched, '
        'so it is HELD in check on the pick, never zeroed as a confirmed '
        'sub-recipe ("6 red plums (see this page)" on "Plums, raw" at 0.4999: '
        'no corpus marked count picks below the gate — a synthesized line, a '
        'stated exception)', () async {
      final db = tempDb();
      const raw = '6 red plums (see this page)';
      expect(isSubRecipeReference(raw), isTrue);
      final fixtures = FixtureProvider();
      await matchAndCompute(db, fixtures, recipeOf(db: db, [raw]));
      final row = db.ingredientMatchesFor('r').single;
      expect(row.description, 'Plums, raw');
      expect((row.grams, row.status), (null, 'auto'));
      expect(belowConfidenceGate(row.confidence), isTrue);
      expect(bucketOf(row), MatchBucket.check);
      expect(fixtures.foodCalls, 0);
    });

    test('A4: "every amount unit-less" — a count with a weight is no count of '
        'the food (no corpus reference line pairs a count with a weight: '
        "Gado-Gado's (1192) line given one, a stated exception)", () {
      final line = lineOf(
        '4 Easy-Peel Hard-Cooked Eggs (about 8 ounces) (this page), halved '
        'lengthwise',
      );
      expect(line.amounts.map((a) => a.unit), contains(isNull));
      expect(line.amounts.map((a) => a.unit), contains(isNotNull));
      expect(subRecipeCountsItsFood(line), isFalse);
    });
  });

  group('Run 045 media, grams and guards (A2, A3, A6, A8, A9, A11, A13)', () {
    final provider = FixtureProvider();

    DiscardedMedium? mediumOf(Recipe recipe, int i) {
      final line = nutritionLines(recipe)[i];
      return discardedMediumOf(recipe, line, normalizeItem(lineItemOf(line)));
    }

    Future<double?> keptOf(Recipe r, int i, int fdcId) async {
      final food = (await provider.food(fdcId))!;
      final line = nutritionLines(r)[i];
      return engineOutcome(
        r,
        line,
        food,
        lineGrams(tempDb(), line, food),
        picked: true,
      ).grams;
    }

    // Home-Corned Beef with Vegetables (0091): its first step.
    const brineStep =
        'Trim fat on surface of brisket to ⅛ inch. Dissolve salt, sugar, and '
        'curing salt in 4 quarts water in large container. Add brisket, 3 '
        'garlic cloves, 4 bay leaves, allspice berries, 1 tablespoon '
        'peppercorns, and coriander seeds to brine. Weigh brisket down with '
        'plate, cover, and refrigerate for 6 days.';
    const cornedLines = [
      '¾ cup salt',
      '6 garlic cloves, peeled',
      '6 bay leaves',
      '2 tablespoons peppercorns',
    ];

    test('A2: without its cheesecloth step the written brine share is still '
        "the part zeroed and the rest counted (0091's recipe with its second "
        'step dropped: a stated exception — the bundle was the only corpus '
        'rest)', () async {
      final r = recipeOf(cornedLines, steps: [brineStep]);
      expect(await keptOf(r, 1, 1104647), closeTo(9, 0.01));
      expect(await keptOf(r, 2, 170917), closeTo(0.4, 0.01));
      expect(await keptOf(r, 3, 170931), closeTo(8.72, 0.01));
    });

    test('A11: a pick on a line with nothing searchable in a recipe that '
        'brines no longer crashes — "(about ¾ cup)" (Hearty Minestrone, '
        "0028) beside Ultimate Shrimp Scampi's (0428) brine step (the pair "
        'is synthesized: a stated exception)', () async {
      final db = tempDb();
      final r = recipeOf(
        db: db,
        ['(about ¾ cup)', '3 tablespoons salt'],
        steps: [
          'Dissolve salt and sugar in 1 quart cold water in large container. '
              'Submerge shrimp in brine, cover, and refrigerate for 15 '
              'minutes.',
        ],
      );
      expect(mediumOf(r, 0), isNull);
      await applyMatchOverride(db, provider, r, 0, {'fdc_id': 173424});
      final row = db
          .ingredientMatchesFor('r')
          .firstWhere(
            (row) => row.position == 0,
          );
      expect((row.fdcId, row.status), (173424, 'overridden'));
    });

    // Cuban Shredded Beef's (0226) first two steps, its salt written as a
    // line (its own line is "Kosher salt and pepper"): stated exceptions.
    const beefSteps = [
      'Bring beef, 2 cups water, and 1¼ teaspoons salt to boil in 12-inch '
          'nonstick skillet over medium-high heat. Reduce heat to low, cover, '
          'and gently simmer until beef is very tender, about 1 hour 45 '
          'minutes.',
      'Remove lid from skillet, increase heat to medium, and simmer until '
          'water evaporates and beef starts to sizzle, 3 to 8 minutes. Using '
          'slotted spoon, transfer beef to rimmed baking sheet.',
    ];

    test('A6: a pot simmered dry before the slotted spoon leaves its salt on '
        'the food; the same steps with the water left drain it', () {
      expect(
        mediumOf(recipeOf(['1¼ teaspoons salt'], steps: beefSteps), 0),
        isNull,
      );
      final wet = [
        beefSteps[0],
        beefSteps[1].replaceFirst(
          'simmer until water evaporates and beef starts to sizzle',
          'simmer in the water',
        ),
      ];
      expect(
        mediumOf(recipeOf(['1¼ teaspoons salt'], steps: wet), 0),
        DiscardedMedium.cookingWater,
      );
    });

    test('A6: a liquid kept after the skimmer — reserved, or ladled over — '
        "leaves its salt with the food (Thick-Cut Sweet Potato Fries' (0318) "
        'step with a clause put in: a stated exception)', () {
      const step =
          'Bring 2 quarts water, 1 teaspoon salt, and baking soda to boil in '
          'Dutch oven. Add potatoes and return to boil. Reduce heat to simmer '
          'and cook until exteriors turn slightly mushy, 3 to 5 minutes. '
          'Using wire skimmer or slotted spoon, transfer potatoes to bowl';
      for (final (tail, medium) in [
        ('.', DiscardedMedium.cookingWater),
        (', reserving cooking liquid.', null),
        ('. Ladle 1 cup cooking liquid over potatoes.', null),
      ]) {
        final r = recipeOf(['1 teaspoon salt'], steps: ['$step$tail']);
        expect(mediumOf(r, 0), medium, reason: tail);
      }
    });

    test("A9: a slotted spoon alone empties the pot like a skimmer (0318's "
        'step with "wire skimmer or" taken out: no corpus pot names the '
        'spoon alone — a stated exception)', () {
      final r = recipeOf(
        ['Kosher salt', '1 teaspoon baking soda'],
        steps: [
          'Bring 2 quarts water, ¼ cup salt, and baking soda to boil in Dutch '
              'oven. Add potatoes and return to boil. Reduce heat to simmer '
              'and cook until exteriors turn slightly mushy, 3 to 5 minutes. '
              'Using slotted spoon, transfer potatoes to bowl with slurry.',
        ],
      );
      expect(mediumOf(r, 1), DiscardedMedium.cookingWater);
    });

    test('A13: bare salts pair by list order, never by text — Biang Biang '
        "Mian's (0376) steps reversed pair them crosswise, the documented "
        'assumption (a synthesized order: a stated exception)', () {
      final r = recipeOf(
        ['¾ teaspoon salt', '1 tablespoon table salt'],
        steps: [
          'Meanwhile, bring water and salt to boil in large pot. Add half of '
              'noodles to water and cook. Using wire skimmer, transfer '
              'noodles to bowl with chili vinaigrette.',
          'Whisk flour and salt together in bowl of stand mixer.',
        ],
      );
      expect(
        [mediumOf(r, 0), mediumOf(r, 1)],
        [DiscardedMedium.cookingWater, null],
      );
    });

    test('A8: "⅔ cup crushed saltines (about 16) or quick oatmeal or 1⅓ '
        'cups fresh bread crumbs" (Meatloaf with Brown Sugar-Ketchup Glaze, '
        '0306) is the saltines, 16 crackers, 48 g — it read 192 g of dry '
        'bread crumbs by the salt density', () async {
      const raw =
          '⅔ cup crushed saltines (about 16) or quick oatmeal or 1⅓ cups '
          'fresh bread crumbs';
      final db = tempDb()
        ..fdcSearchCachePut(
          'saltines',
          jsonEncode([
            for (final hit in await provider.search('saltines')) hit.toJson(),
          ]),
        );
      expect(
        lineSearchFor(db, normalizeItem(lineItemOf(lineOf(raw))), '').query,
        'saltines',
      );
      await matchAndCompute(db, FixtureProvider(), recipeOf(db: db, [raw]));
      final row = db.ingredientMatchesFor('r').single;
      expect((row.fdcId, row.gramSource), (2708167, 'portion'));
      expect(row.grams, closeTo(48, 0.01));
      // One "or" before a longer food is still the adjective reading.
      expect(
        leftAlternative('chicken or vegetable broth', (_) => true),
        isNull,
      );
    });

    test('A9: the cracker count is for CRUSHED saltines — "⅔ cup saltines" '
        "reads the record's whole-cracker cup (a synthesized line: no corpus "
        'volume of saltines is uncrushed, a stated exception)', () async {
      final saltines = (await provider.food(2708167))!;
      final whole = lineGrams(tempDb(), lineOf('⅔ cup saltines'), saltines);
      expect(whole?.basis, '2/3 cup · USDA portion');
      expect(whole?.grams, isNot(closeTo(48, 0.01)));
    });

    test('A3: a twin whose cached detail cannot size the line is no twin '
        "(the pomegranate answer, the twin's portions stripped: a stated "
        'exception)', () async {
      final food = (await provider.food(2709267))!;
      final db = tempDb()
        ..fdcFoodCachePut(
          2709267,
          jsonEncode(
            FdcFood(
              fdcId: food.fdcId,
              description: food.description,
              dataType: food.dataType,
              nutrientsPer100g: food.nutrientsPer100g,
              portions: const [],
            ).toJson(),
          ),
        );
      final ranked = rankCandidates(
        'pomegranate seeds',
        await provider.search('pomegranate seeds'),
      );
      expect(
        belowGateSizedTwin(
          db,
          lineOf('½ cup pomegranate seeds'),
          'pomegranate seeds',
          ranked,
          ranked.first,
        ),
        isNull,
      );
    });
  });

  group('the rulings Q3 and the checkpoint-8 fixes B6, B7', () {
    final provider = FixtureProvider();

    DiscardedMedium? mediumOf(Recipe recipe, int i) {
      final line = nutritionLines(recipe)[i];
      return discardedMediumOf(recipe, line, normalizeItem(lineItemOf(line)));
    }

    // Eggplant Parmesan (0407): its salt lines and its first two steps.
    const eggplantLines = [
      '2 pounds globe eggplant (2 medium eggplants), cut crosswise into '
          '¼-inch-thick rounds',
      '1 tablespoon kosher salt (see note)',
      'Table salt and ground black pepper',
      'Table salt and ground black pepper',
    ];
    const eggplantSteps = [
      'Toss half of the eggplant slices and 1½ teaspoons of the kosher salt '
          'in a large bowl until combined; transfer the salted eggplant to a '
          'large colander set over a bowl. Repeat with the remaining eggplant '
          'and kosher salt, placing the second batch on top of the first. Let '
          'stand until the eggplant releases about 2 tablespoons liquid, 30 '
          'to 45 minutes. Spread the eggplant slices on a triple thickness of '
          'paper towels; cover with another triple thickness of paper towels. '
          'Press firmly on each slice to remove as much liquid as possible, '
          'then wipe off the excess salt.',
      'While the eggplant is draining, adjust the oven racks to the '
          'upper-middle and lower-middle positions, place a rimmed baking '
          'sheet on each rack, and heat the oven to 425 degrees. Process the '
          'bread in a food processor to fine, even crumbs, about 20 to 30 '
          'seconds. Transfer the crumbs to a pie plate and stir in the '
          'Parmesan, ¼ teaspoon table salt, and ½ teaspoon pepper; set aside.',
    ];

    test("Q3a: Eggplant Parmesan's (0407) degorging salt, wiped off, is held "
        'beside its seasoning lines, stored with no grams', () async {
      final r = recipeOf(eggplantLines, steps: eggplantSteps);
      expect(mediumOf(r, 1), DiscardedMedium.saltBath);
      final salt = (await provider.food(173468))!;
      final line = nutritionLines(r)[1];
      final out = engineOutcome(
        r,
        line,
        salt,
        lineGrams(tempDb(), line, salt),
        picked: true,
      );
      expect(
        (out.grams, out.source, out.hold),
        (null, null, 'discarded_medium'),
      );
    });

    test('Q3b: food lifted out of a discarded marinade leaves it COUNTED — '
        "Skillet Chicken Fajitas' (0070) marinade lines", () {
      final r = recipeOf(
        [
          '¼ cup vegetable oil',
          '2 tablespoons lime juice',
          '4 garlic cloves, peeled and smashed',
          '1½ teaspoons smoked paprika',
          '1 teaspoon sugar',
          '1 teaspoon salt',
          '½ teaspoon ground cumin',
          '½ teaspoon pepper',
          '¼ teaspoon cayenne pepper',
        ],
        steps: [
          'Whisk 3 tablespoons oil, lime juice, garlic, paprika, sugar, salt, '
              'cumin, pepper, and cayenne together in bowl. Add chicken and '
              'toss to coat. Cover and let stand at room temperature for at '
              'least 30 minutes or up to 1 hour.',
          'Remove chicken from marinade and wipe off excess. Heat remaining 1 '
              'tablespoon oil in now-empty skillet over high heat until just '
              'smoking.',
        ],
      );
      expect([
        for (var i = 0; i < 9; i++) mediumOf(r, i),
      ], List.filled(9, null));
    });

    // Perfect Poached Chicken Breasts (0112) and Sesame-Lemon Cucumber
    // Salad (0052).
    const poached = (
      lines: [
        '4 (6- to 8-ounce) boneless, skinless chicken breasts, trimmed',
        '½ cup soy sauce',
      ],
      title: 'Perfect Poached Chicken Breasts',
      steps: [
        'Cover chicken breasts with plastic wrap and pound thick ends gently '
            'with meat pounder until ¾ inch thick. Whisk 4 quarts water, soy '
            'sauce, salt, sugar, and garlic in Dutch oven until salt and sugar '
            'are dissolved. Arrange breasts, skinned side up, in steamer '
            'basket, making sure not to overlap them. Submerge steamer basket '
            'in brine and let sit at room temperature for 30 minutes.',
      ],
      position: 1,
      fdcId: 2707442,
    );
    const cucumbers = (
      lines: ['1 tablespoon table salt'],
      title: 'Sesame-Lemon Cucumber Salad',
      steps: [
        'Toss the cucumbers with the salt in a colander set over a large '
            'bowl. Weight the cucumbers with a gallon-sized zipper-lock bag '
            'filled with water; drain for 1 to 3 hours. Rinse and pat dry.',
      ],
      position: 0,
      fdcId: 173468,
    );

    Future<(SaltDatabase, Recipe)> heldRow(
      ({
        List<String> lines,
        String title,
        List<String> steps,
        int position,
        int fdcId,
      })
      c,
    ) async {
      final db = tempDb();
      final r = recipeOf(db: db, c.lines, title: c.title, steps: c.steps);
      final food = (await provider.food(c.fdcId))!;
      final line = nutritionLines(r)[c.position];
      final out = engineOutcome(
        r,
        line,
        food,
        lineGrams(db, line, food),
        picked: true,
      );
      expect((out.grams, out.hold), (null, 'discarded_medium'));
      db.upsertIngredientMatch(
        IngredientMatchRow(
          recipeId: 'r',
          position: c.position,
          raw: line.raw,
          fdcId: c.fdcId,
          description: food.description,
          dataType: food.dataType,
          confidence: 0.9,
          grams: out.grams,
          gramSource: out.source,
          status: 'auto',
          hold: out.hold,
        ),
      );
      return (db, r);
    }

    for (final c in [poached, cucumbers]) {
      test('B6: a held medium stores no grams, and a Confirm writes 0 g '
          '"poured away" — typed grams count instead (${c.title})', () async {
        final (db, r) = await heldRow(c);
        await applyMatchOverride(db, provider, r, c.position, {
          'confirmed': true,
        });
        final row = db
            .ingredientMatchesFor('r')
            .singleWhere(
              (row) => row.position == c.position,
            );
        expect(
          (row.grams, row.gramSource, row.status, row.hold),
          (0, 'discarded', 'confirmed', null),
        );
        expect(bucketOf(row), MatchBucket.counted);
        expect(
          gramBasisFor(db, nutritionLines(r)[c.position], row),
          'poured away — counted as 0 g',
        );
        final (typed, typedRecipe) = await heldRow(c);
        await applyMatchOverride(typed, provider, typedRecipe, c.position, {
          'confirmed': true,
          'grams': 5,
        });
        final kept = typed
            .ingredientMatchesFor('r')
            .singleWhere(
              (row) => row.position == c.position,
            );
        expect((kept.grams, kept.gramSource), (5, 'override'));
      });
    }

    test('B6: a row written before v14 with the whole poured-away line — '
        "0112's soy at 137 g — confirms to 0 g too; a pick of another food "
        'on it is poured away as well', () async {
      final (db, r) = await heldRow(poached);
      final row = db.ingredientMatchesFor('r').single;
      db.upsertIngredientMatch(
        row.copyWith(grams: 137.22104, gramSource: 'density'),
      );
      await applyMatchOverride(db, provider, r, 1, {'confirmed': true});
      expect(db.ingredientMatchesFor('r').single.grams, 0);
      final (picked, pickedRecipe) = await heldRow(poached);
      await applyMatchOverride(picked, provider, pickedRecipe, 1, {
        'fdc_id': 2707442,
      });
      final after = picked.ingredientMatchesFor('r').single;
      expect(
        (after.grams, after.gramSource, after.status),
        (0, 'discarded', 'overridden'),
      );
    });

    test('B7: Roast Fresh Ham (0249) takes the fresh shank half (168226) from '
        'its own answer over the cured rump — still below the gate, for a '
        'person', () async {
      final db = tempDb();
      const raw =
          '1 (6- to 8-pound) bone-in fresh half ham with skin, preferably '
          'shank end, rinsed';
      await matchAndCompute(db, FixtureProvider(), recipeOf(db: db, [raw]));
      final row = db.ingredientMatchesFor('r').single;
      expect(row.fdcId, 168226);
      expect(row.hold, isNull);
      expect(belowConfidenceGate(row.confidence), isTrue);
      expect(bucketOf(row), MatchBucket.check);
      // A line not asking for fresh keeps the ranker's order.
      final ranked = rankCandidates(
        'bone-in half ham with skin',
        await provider.search('bone-in half ham with skin'),
      );
      expect(
        identical(freshOverCured('bone-in half ham', ranked), ranked),
        isTrue,
      );
      // Another cured record and a docked one sharing more of the line's
      // words never take it (two synthesized records: a stated exception).
      RankedCandidate hit(int id, String description, {bool docked = false}) =>
          RankedCandidate(
            candidate: FdcCandidate(
              fdcId: id,
              description: description,
              dataType: 'SR Legacy',
            ),
            confidence: 0.2,
            docked: docked,
          );
      final withDecoys = [
        ranked.first,
        hit(1, 'Pork, cured, ham, shank half, bone-in, with skin, rinsed'),
        hit(2, 'Ham, fresh, shank half, bone-in, with skin', docked: true),
        ...ranked.skip(1),
      ];
      expect(
        freshOverCured(raw, withDecoys).first.candidate.fdcId,
        168226,
      );
    });
  });
}
