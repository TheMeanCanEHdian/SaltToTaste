// Real corpus lines and steps wrap across adjacent literals.
// ignore_for_file: no_adjacent_strings_in_list

import 'dart:convert';
import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/fdc_fixtures.dart';

/// Matcher v14, fixer B (the checkpoint-8 fixes B2–B5 and the user's ruling
/// Q2 of 2026-09-28): every mechanism pinned WITHOUT the corpus — real
/// corpus lines and step texts as strings (recipe named on each), FDC
/// answers recorded from sweep snapshot 12. A guard no corpus line
/// exercises is pinned on a synthesized input, said so where it is.
void main() {
  final provider = FixtureProvider();

  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v14b');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    return db;
  }

  /// [raw]'s grams on [fdcId] as the engine sizes them ([lineGrams]) and
  /// the `gram_basis` an auto row of them reads.
  Future<(double?, String?, String?)> sized(String raw, int fdcId) async {
    final db = tempDb();
    final food = (await provider.food(fdcId))!;
    // As the engine leaves it: the picked food's detail cached.
    db.fdcFoodCachePut(fdcId, jsonEncode(food.toJson()));
    final line = lineOf(raw);
    final grams = lineGrams(db, line, food);
    final row = IngredientMatchRow(
      recipeId: 'r',
      position: 0,
      raw: raw,
      fdcId: fdcId,
      description: food.description,
      dataType: food.dataType,
      confidence: 0.9,
      grams: grams?.grams,
      gramSource: grams?.source.name,
      status: 'auto',
    );
    return (grams?.grams, grams?.source.name, gramBasisFor(db, line, row));
  }

  group('B5 + Q2: a fresh herb on its dried spice record', () {
    test(
      'a fresh volume counts one third, flagged: "1 tablespoon minced '
      'fresh oregano" (Acquacotta, 0405) is 1 g of the 3 g tablespoon',
      () async {
        final (grams, source, basis) = await sized(
          '1 tablespoon minced fresh oregano',
          171328,
        );
        expect(grams, closeTo(1.0, 0.001));
        expect(source, 'portion');
        expect(
          basis,
          '1 tablespoon · USDA portion × ⅓ (a fresh volume on the dried '
          'record) · approximate (dried herb record for a fresh herb)',
        );
      },
    );

    test('the dried amount the line offers wins: Simple Italian-Style Meat '
        'Sauce (0353) and Albóndigas en Chipotle (1208) are 1 g', () async {
      for (final raw in [
        '1 tablespoon minced fresh oregano leaves or 1 teaspoon dried oregano',
        '1 tablespoon minced fresh oregano or 1 teaspoon dried',
      ]) {
        final (grams, _, basis) = await sized(raw, 171328);
        expect(grams, closeTo(1.0, 0.001), reason: raw);
        expect(
          basis,
          'the dried amount the line offers: 1 teaspoon · USDA portion · '
          'approximate (dried herb record for a fresh herb)',
          reason: raw,
        );
      }
    });

    test('fresh leaves by count are 0 g unmeasured, like a sprig: Chicken '
        'Canzanese (0422) and Pan-Roasted Chicken Breasts with '
        'Sage-Vermouth Sauce (0132)', () async {
      for (final (raw, n) in [
        ('12 whole fresh sage leaves', 12),
        ('4 medium fresh sage leaves, each leaf torn in half', 4),
      ]) {
        final (grams, source, basis) = await sized(raw, 170935);
        expect((grams, source), (0.0, 'unmeasured'), reason: raw);
        // No "approximate" suffix: a 0 g leaf counts nothing (Run 047).
        expect(
          basis,
          '$n leaves — a fresh leaf is not measured, counted as 0 g',
        );
      }
    });

    test('a sprig stays 0 g and its plus volume is a third: Shrimp Salad '
        '(0286)', () async {
      final (grams, _, _) = await sized(
        '3 sprigs fresh tarragon plus 1 teaspoon minced fresh tarragon leaves',
        170937,
      );
      expect(grams, closeTo(0.2, 0.001));
      final (sprig, source, _) = await sized('1 sprig fresh tarragon', 170937);
      expect((sprig, source), (0.0, 'unmeasured'));
    });

    test('a fresh weight is not a volume: kept as written (no corpus herb '
        'line prints a weight: "1 ounce fresh sage leaves" is synthesized, '
        'a stated exception)', () async {
      final (grams, source, _) = await sized(
        '1 ounce fresh sage leaves',
        170935,
      );
      expect(grams, closeTo(28.35, 0.01));
      expect(source, 'weight');
    });

    test('a dried line on the record is not a fresh herb: "½ teaspoon dried '
        'oregano" reads its own portion, unflagged', () async {
      final (grams, _, basis) = await sized('½ teaspoon dried oregano', 171328);
      expect(basis, isNot(contains('approximate')));
      expect(basis, isNot(contains('⅓')));
      expect(grams, greaterThan(0));
    });
  });

  group('B3: the cached portions the grams code missed (checkpoint 8)', () {
    Future<(double?, String?)> on(String raw, int fdcId, {int? sibling}) async {
      final db = tempDb();
      if (sibling != null) {
        db.fdcFoodCachePut(
          sibling,
          jsonEncode((await provider.food(sibling))!.toJson()),
        );
      }
      final grams = lineGrams(db, lineOf(raw), await provider.food(fdcId));
      return (grams?.grams, grams?.basis);
    }

    void sizedAs((double?, String?) got, double grams, String basis) {
      expect(got.$1, closeTo(grams, 0.01));
      expect(got.$2, basis);
    }

    test(
      'an SR portion written as amount 1 and a bare noun is one item: '
      '"shell" 12.9 g of "Taco shells, baked" (Ground Beef Tacos, 0478), '
      '"leaf" 48 g of Swiss chard (Hearty Chicken Noodle Soup, 0002)',
      () async {
        sizedAs(
          await on('8 Home-Fried Taco Shells (recipe follows)', 172800),
          103.2,
          '8 · USDA per-item weight',
        );
        // Since v15 the line's printed "(about 2 cups)" wins over 5 whole
        // leaves (Run 047, E7): 2 × the record's cup, 72 g, not 5 × 48 g.
        final (chard, _) = await on(
          '4–6 Swiss chard leaves, ribs removed, torn into 1-inch pieces '
          '(about 2 cups; optional)',
          169991,
        );
        expect(chard, closeTo(72, 0.001));
      },
    );

    test('of several portions the item names, the medium one: "4 leaves Bibb '
        'lettuce" (Crispy Fish Sandwiches with Tartar Sauce, 1081) is 4 × '
        '"leaf, medium" 7.5 g, not the first-listed "leaf, large"', () async {
      final (grams, _) = await on('4 leaves Bibb lettuce', 168429);
      expect(grams, closeTo(30, 0.001));
    });

    test('a bare count reads the "medium" portion: "1 Bosc pear" (Caramelized '
        'Onion, Pear, and Bacon Tart) 179 g; a dried chile its "pepper" '
        'portion ("2 dried ancho chiles", Best Vegetarian Chili)', () async {
      final (pear, _) = await on(
        '1 Bosc pear, quartered, cored, and sliced ¼ inch thick, divided',
        167778,
      );
      expect(pear, closeTo(179, 0.001));
      final (ancho, _) = await on('2 dried ancho chiles', 169396);
      expect(ancho, closeTo(34, 0.001));
    });

    test('a sub-gram "pepper" portion weighs only a small chile: on 168570 '
        '"Peppers, hot chile, sun-dried" (0.5 g a pepper) "2 dried New '
        'Mexican chiles" (Best Vegetarian Chili) has no grams — a pod is ~7 g '
        'by the corpus\'s own "(about ¾ ounce)" for 3 — while "10 dried '
        'arbol chiles" (Tacos al Pastor) reads 10 × 0.5 g', () async {
      final (newMexican, _) = await on('2 dried New Mexican chiles', 168570);
      expect(newMexican, isNull);
      final (chipotle, _) = await on(
        '½ dried chipotle chile, stemmed, seeded, and torn into ½-inch '
        'pieces (scant tablespoon)',
        168570,
      );
      expect(chipotle, isNull);
      final (arbol, _) = await on(
        '10 dried arbol chiles, stemmed, halved lengthwise, and seeds reserved',
        168570,
      );
      expect(arbol, closeTo(5, 0.001));
      final (smallRed, _) = await on(
        '8 small whole dried red chiles (optional)',
        168570,
      );
      expect(smallRed, closeTo(4, 0.001));
    });

    test('a bare noun that is neither the item nor a size or a whole fruit '
        'is no item: "2 red plums" (Sweet Cherry Pie) read 2 × "fruit" '
        '66 g, never "NLEA serving" 151 g; "4 whole chicken legs" (Oven-Fried '
        'Chicken) no "drumstick"; "8 whole black peppercorns" (Indian '
        'Curry) no "dash"', () async {
      final (plums, _) = await on('2 red plums, halved and pitted', 169949);
      expect(plums, closeTo(132, 0.001));
      final (legs, _) = await on(
        '4 whole chicken legs, separated into drumsticks and thighs and skin '
        'removed',
        173619,
      );
      expect(legs, isNull);
      final (peppercorns, _) = await on('8 whole black peppercorns', 170931);
      expect(peppercorns, isNull);
    });

    test('a unit named by a bare SR noun: "4 sticks unsalted butter" '
        '(Classic Yellow Layer Cake, 0884) is 4 × "stick" 113 g', () async {
      sizedAs(
        await on(
          '4 sticks unsalted butter, cut into chunks and softened',
          173430,
        ),
        452,
        '4 stick · USDA portion',
      );
    });

    test('a weight written in the item: "1 5-pound boneless pork butt roast" '
        '(Indoor Pulled Pork with Sweet and Tangy Barbecue Sauce)', () async {
      sizedAs(
        await on(
          '1 5-pound boneless pork butt roast, cut in half horizontally',
          167849,
        ),
        5 * 453.592,
        'from the printed weight',
      );
    });

    test('a paren volume on a count unit: "1 (750-ml) bottle red Burgundy or '
        'Pinot Noir" (Modern Beef Burgundy) is 750 mL on the fl oz '
        'portion', () async {
      sizedAs(
        await on('1 (750-ml) bottle red Burgundy or Pinot Noir', 174835),
        750 * 29.4 / 29.5735,
        '750 ml · USDA portion',
      );
    });

    test('whole raw almonds read their SR sibling\'s volume: "1¼ cups whole '
        'almonds" (Almond Biscotti) on "cup, whole" 143 g', () async {
      sizedAs(
        await on(
          '1¼ cups whole almonds, lightly toasted',
          2346393,
          sibling: 170567,
        ),
        1.25 * 143,
        '1 1/4 cup · USDA portion of "Nuts, almonds"',
      );
    });

    test('Ground Beef Tacos (0478): the bare count of the taco shells counts '
        'on "Taco shells, baked" at 103.2 g, no longer the sub-recipe '
        'row', () async {
      final db = tempDb()
        ..upsertSource(slug: 'src', name: 'Test', type: 'book');
      const raw = '8 Home-Fried Taco Shells (recipe follows)';
      final recipe = Recipe(
        id: 'r',
        title: 'Ground Beef Tacos',
        slug: 'r',
        source: const RecipeSource(name: 'Test', type: 'book'),
        ingredients: [
          IngredientGroup(items: [lineOf(raw)]),
        ],
        subsections: [
          Subsection(
            title: 'Home-Fried Taco Shells',
            kind: 'variation',
            ingredients: [
              IngredientGroup(
                items: [
                  lineOf('¾ cup corn oil, vegetable oil, or canola oil'),
                  lineOf('8 (6-inch) corn tortillas'),
                ],
              ),
            ],
          ),
        ],
      );
      db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h');
      await matchAndCompute(db, provider, recipe);
      final row = db.ingredientMatchesFor('r').single;
      expect(
        (row.fdcId, row.gramSource, row.status),
        (172800, 'piece', 'auto'),
      );
      expect(row.grams, closeTo(103.2, 0.001));
    });
  });

  group('B4: the poured-away detectors (checkpoint 8)', () {
    Recipe recipeOf(
      List<String> raws, {
      List<String> steps = const [],
      String title = 'r',
    }) => Recipe(
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
    );

    DiscardedMedium? mediumOf(Recipe r, int i) {
      final line = nutritionLines(r)[i];
      return discardedMediumOf(r, line, normalizeItem(lineItemOf(line)));
    }

    test('baking soda a food sits in and is rinsed of is held a salt bath: '
        'the rinse in the next step (Sichuan Stir-Fried Pork in Garlic '
        'Sauce, 0540) or the same one (Thai-Style Stir-Fried Noodles with '
        'Chicken and Broccolini, 0553; Vietnamese-Style Caramel Chicken '
        'with Broccoli, 0558)', () {
      for (final r in [
        recipeOf(
          [
            '1 teaspoon baking soda',
          ],
          steps: [
            'Cut pork into 2-inch lengths, then cut each length into ¼-inch '
                'matchsticks. Combine pork with ½ cup cold water and baking '
                'soda '
                'in bowl. Let sit at room temperature for 15 minutes.',
            'Rinse pork in cold water. Drain well and pat dry with paper '
                'towels. Whisk rice wine and cornstarch together in bowl. Add '
                'pork and toss to coat.',
          ],
        ),
        recipeOf(
          [
            '1 teaspoon baking soda',
          ],
          steps: [
            'Combine chicken with 2 tablespoons water and baking soda in '
                'bowl. Let sit at room temperature for 15 minutes. Rinse '
                'chicken '
                'in cold water and drain well.',
          ],
        ),
        recipeOf(
          [
            '1 tablespoon baking soda',
          ],
          steps: [
            'Combine baking soda and 1¼ cups cold water in large bowl. Add '
                'chicken and toss to coat. Let stand at room temperature for '
                '15 '
                'minutes. Rinse chicken in cold water and drain well.',
          ],
        ),
      ]) {
        expect(mediumOf(r, 0), DiscardedMedium.saltBath);
      }
    });

    test('a later step that drains the boiled food drains its soda: '
        'Ultracreamy Hummus (0572), two steps on', () {
      final r = recipeOf(
        [
          '2 (15-ounce) cans chickpeas, rinsed',
          '½ teaspoon baking soda',
        ],
        steps: [
          'Combine chickpeas, baking soda, and 6 cups water in medium '
              'saucepan and bring to boil over high heat. Reduce heat and '
              'simmer, stirring occasionally, until chickpea skins begin to '
              'float to surface and chickpeas are creamy and very soft, 20 to '
              '25 minutes.',
          'While chickpeas cook, mince garlic using garlic press or '
              'rasp-style grater. Measure out 1 tablespoon garlic and set '
              'aside; discard remaining garlic. Whisk lemon juice, salt, and '
              'reserved garlic together in small bowl and let sit for 10 '
              'minutes. Strain garlic-lemon mixture through fine-mesh strainer '
              'set over bowl, pressing on solids to extract as much liquid as '
              'possible; discard solids.',
          'Drain chickpeas in colander and return to saucepan. Fill '
              'saucepan with cold water and gently swish chickpeas with your '
              'fingers to release skins. Pour off most of water into colander '
              'to collect skins, leaving chickpeas behind in saucepan. Repeat '
              'filling, swishing, and draining 3 or 4 times until most skins '
              'have been removed (this should yield about ¾ cup skins); '
              'discard '
              'skins. Transfer chickpeas to colander to drain.',
        ],
      );
      expect(mediumOf(r, 1), DiscardedMedium.cookingWater);
    });

    test("Shrimp Salad's (0286) court-bouillon: its lemon juice and sugar "
        'are drained off the shrimp with the discarded aromatics, held as '
        'cooking water — the juice storing its eaten "plus 1 tablespoon"; '
        'the shrimp drained, and the sprig lines (0 g), are none', () async {
      final r = recipeOf(
        [
          '1 pound extra-large shrimp (21 to 25 per pound), peeled and '
              'deveined (see this page)',
          '¼ cup plus 1 tablespoon juice from 2 to 3 lemons, spent halves '
              'reserved',
          '5 sprigs fresh parsley plus 1 teaspoon minced fresh parsley '
              'leaves',
          '3 sprigs fresh tarragon plus 1 teaspoon minced fresh tarragon '
              'leaves',
          '1 teaspoon whole black peppercorns plus ground black pepper',
          '1 tablespoon sugar',
          'Table salt',
        ],
        steps: [
          'Combine the shrimp, ¼ cup of the lemon juice, the reserved lemon '
              'halves, parsley sprigs, tarragon sprigs, whole peppercorns, '
              'sugar, and 1 teaspoon salt with 2 cups cold water in a medium '
              'saucepan. Place the saucepan over medium heat and cook the '
              'shrimp, stirring several times, until pink, firm to the touch, '
              'and the centers are no longer translucent, 8 to 10 minutes (the '
              'water should be just bubbling around the edge of the pan and '
              'register 165 degrees on an instant-read thermometer). Remove '
              'the '
              'pan from the heat, cover, and let the shrimp sit in the broth '
              'for 2 minutes.',
          'Meanwhile, fill a medium bowl with ice water. Drain the shrimp '
              'into a colander and discard the lemon halves, herbs, and '
              'spices. '
              'Immediately transfer the shrimp to the ice water to stop the '
              'cooking and chill thoroughly, about 3 minutes. Remove the '
              'shrimp '
              'from the ice water and pat dry with paper towels.',
          'Whisk together the mayonnaise, celery, shallot, remaining 1 '
              'tablespoon lemon juice, the minced parsley, and minced tarragon '
              'in a medium bowl. Cut the shrimp in half lengthwise and then '
              'each half into thirds; add the shrimp to the mayonnaise mixture '
              'and toss to combine. Season with salt and pepper to taste and '
              'serve.',
        ],
      );
      expect(
        [for (var i = 0; i < 6; i++) mediumOf(r, i)],
        [
          null,
          DiscardedMedium.cookingWater,
          null,
          null,
          null,
          DiscardedMedium.cookingWater,
        ],
      );
      final line = nutritionLines(r)[1];
      final lemon = (await provider.food(167747))!;
      final out = engineOutcome(
        r,
        line,
        lemon,
        lineGrams(tempDb(), line, lemon),
        picked: true,
      );
      expect(out.hold, 'discarded_medium');
      expect(out.grams, closeTo(15.23, 0.01));
    });

    test('a milk dip the squid drips back into is held a salt bath, milk '
        "and salt, never the flour mixture's pepper (Rhode Island-Style "
        'Fried Calamari, 1084)', () {
      final r = recipeOf(
        [
          '½ cup milk',
          '1 teaspoon table salt',
          '1½ cups all-purpose flour',
          '1 tablespoon baking powder',
          '½ teaspoon pepper',
        ],
        steps: [
          'Whisk milk and salt together in medium bowl. Combine flour, '
              'baking powder, and pepper in second medium bowl. Add squid to '
              'milk mixture and toss to coat. Using your hands or slotted '
              'spoon, remove half of squid, allowing excess milk mixture to '
              'drip back into bowl, and add to bowl with flour mixture. Using '
              'your hands, toss to coat evenly. Gently shake off excess flour '
              'and place coated squid in single layer on unlined rack. Repeat '
              'with remaining squid. Add 1 cup banana peppers to flour mixture '
              'and toss with your hands to coat evenly. Gently shake off '
              'excess '
              'flour mixture and sprinkle peppers evenly among squid. Let sit '
              'for 10 minutes.',
        ],
      );
      expect(
        [for (var i = 0; i < 5; i++) mediumOf(r, i)],
        [DiscardedMedium.saltBath, DiscardedMedium.saltBath, null, null, null],
      );
    });

    test('a quick pickle drained off its slaw is held a salt bath — the '
        'second vinegar and salt lines by the nth mention, never the '
        "braise's (Carne Deshebrada, 0481)", () {
      final r = recipeOf(
        [
          '½ cup cider vinegar',
          'Salt and pepper',
          '1 cup cider vinegar',
          '1 tablespoon sugar',
          '1½ teaspoons salt',
        ],
        steps: [
          'Adjust oven rack to lower-middle position and heat oven to 325 '
              'degrees. Combine beer, vinegar, anchos, tomato paste, garlic, '
              'bay leaves, cumin, oregano, 2 teaspoons salt, ½ teaspoon '
              'pepper, '
              'cloves, and cinnamon in Dutch oven. Arrange onion rounds in '
              'single layer on bottom of pot. Place beef on top of onion '
              'rounds '
              'in single layer. Cover and cook until meat is well browned and '
              'tender, 2½ to 3 hours.',
          'While beef cooks, whisk vinegar, water, sugar, and salt in large '
              'bowl until sugar is dissolved. Add cabbage, onion, carrot, '
              'jalapeño, and oregano and toss to combine. Cover and '
              'refrigerate '
              'for at least 1 hour or up to 24 hours. Drain slaw and stir in '
              'cilantro right before serving.',
          'Using two forks, shred beef into bite-size pieces. Bring sauce '
              'to simmer over medium heat. Add shredded beef and stir to coat. '
              'Season with salt to taste. (Beef can be refrigerated for up to '
              '2 '
              'days; gently reheat before serving.)',
        ],
      );
      expect(
        [for (var i = 0; i < 5; i++) mediumOf(r, i)],
        [
          null,
          null,
          DiscardedMedium.saltBath,
          DiscardedMedium.saltBath,
          DiscardedMedium.saltBath,
        ],
      );
    });

    test('a brine the food poaches in is its cooking liquid for its salt '
        'too, held like its soy sauce (Perfect Poached Chicken Breasts, '
        '0112); the same brine under another title stays a brine', () {
      final poached = recipeOf(
        [
          '½ cup soy sauce',
          '¼ cup salt',
          '2 tablespoons sugar',
          '6 garlic cloves, smashed and peeled',
        ],
        steps: [
          'Cover chicken breasts with plastic wrap and pound thick ends '
              'gently with meat pounder until ¾ inch thick. Whisk 4 quarts '
              'water, soy sauce, salt, sugar, and garlic in Dutch oven until '
              'salt and sugar are dissolved. Arrange breasts, skinned side up, '
              'in steamer basket, making sure not to overlap them. Submerge '
              'steamer basket in brine and let sit at room temperature for 30 '
              'minutes.',
        ],
        title: 'Perfect Poached Chicken Breasts',
      );
      expect(mediumOf(poached, 1), DiscardedMedium.cookingWater);
      final brined = Recipe(
        id: 'r',
        title: 'r',
        slug: 'r',
        source: poached.source,
        ingredients: poached.ingredients,
        steps: poached.steps,
      );
      expect(mediumOf(brined, 1), DiscardedMedium.brine);
    });

    test("a dunk's sugar follows its salt: Grilled Cauliflower (0656)", () {
      final r = recipeOf(
        [
          '¼ cup salt',
          '2 tablespoons sugar',
        ],
        steps: [
          'Whisk 2 cups water, salt, and sugar in medium bowl until salt '
              'and sugar dissolve. Holding wedges by core, gently dunk in '
              'salt-sugar mixture until evenly moistened (do not dry—residual '
              'water will help cauliflower steam). Transfer wedges, rounded '
              'side down, to large plate and cover with inverted large bowl. '
              'Microwave until cauliflower is translucent and tender and '
              'paring '
              'knife inserted in thickest stem of florets (not into core) '
              'meets '
              'no resistance, 14 to 16 minutes.',
        ],
      );
      expect(mediumOf(r, 0), DiscardedMedium.saltBath);
      expect(mediumOf(r, 1), DiscardedMedium.saltBath);
    });

    test("a salt bath's sugar only when the bath's own sentence names it: "
        "Sesame-Lemon Cucumber Salad's (0052) rinsed salt leaves the "
        "dressing's sugar counted", () {
      final r = recipeOf(
        [
          '1 tablespoon table salt',
          '2 teaspoons sugar',
        ],
        steps: [
          'Toss the cucumbers with the salt in a colander set over a large '
              'bowl. Weight the cucumbers with a gallon-sized zipper-lock bag '
              'filled with water; drain for 1 to 3 hours. Rinse and pat dry.',
          'Whisk the remaining ingredients together in a medium bowl. Add '
              'the cucumbers; toss to coat. Serve chilled or at room '
              'temperature.',
        ],
      );
      expect(mediumOf(r, 0), DiscardedMedium.saltBath);
      expect(mediumOf(r, 1), isNull);
    });

    test('none of the shapes that combine and drain something else: a drain '
        'with no discard (Banh Xeo, 0560: "stir to combine", then the '
        'batter "will drain"; Shrimp Pad Thai, 0554; Modern Cauliflower '
        'Gratin, 0673) and a drain after an "add" that tosses nothing '
        '(Spaghetti Puttanesca, 0331)', () {
      for (final r in [
        recipeOf(
          [
            '⅓ cup canned coconut milk',
          ],
          steps: [
            'Heat 1 teaspoon oil in 12-inch nonstick skillet over medium-high '
                'heat until shimmering. Add pork and onion and cook, stirring '
                'occasionally, until pork is no longer pink and onion is '
                'softened, 5 to 7 minutes. Add shrimp and remaining ¼ teaspoon '
                'salt and continue to cook, stirring occasionally, until '
                'shrimp '
                'just begin to turn pink, about 2 minutes longer. Transfer '
                'mixture to second bowl. Wipe skillet clean with paper towels. '
                'Add coconut milk and 2 teaspoons oil to crepe batter and '
                'stir to '
                'combine.',
            'Heat 2 teaspoons oil in now-empty skillet over medium-high heat '
                'until just smoking. Add one-third of pork mixture and heat '
                'through until sizzling, about 30 seconds. Spread pork mixture '
                'over half of skillet. Pour ½ cup batter evenly over entire '
                'skillet. (Batter poured over filling will drain to skillet '
                'surface. If needed, tilt skillet gently to fill gaps.) '
                'Spread 1 '
                'cup bean sprouts over filling. Cook until crepe loosens '
                'completely from bottom of skillet with gentle shake, 4 to 5 '
                'minutes. Reduce heat to medium-low and continue to cook, '
                'shaking '
                'skillet occasionally, until edges of crepe are lacy and crisp '
                'and underside is golden brown, 2 to 4 minutes longer.',
          ],
        ),
        recipeOf(
          [
            '⅓ cup distilled white vinegar',
          ],
          steps: [
            'Combine vinegar and chile in bowl and let stand at room '
                'temperature for at least 15 minutes.',
            'Combine ¼ cup water, ½ teaspoon salt, and ¼ teaspoon sugar in '
                'small bowl. Microwave until steaming, about 30 seconds. Add '
                'radishes and let stand for 15 minutes. Drain and pat dry with '
                'paper towels.',
          ],
        ),
        recipeOf(
          [
            '8 tablespoons unsalted butter',
          ],
          steps: [
            'Combine sliced stems and cores, 2 cups florets, 3 cups water, '
                'and 6 tablespoons butter in Dutch oven and bring to boil over '
                'high heat. Place remaining florets in steamer basket (do not '
                'rinse bowl). Once mixture is boiling, place steamer basket in '
                'pot, cover, and reduce heat to medium. Steam florets in '
                'basket '
                'until translucent and stem ends can be easily pierced with '
                'paring knife, 10 to 12 minutes. Remove steamer basket and '
                'drain '
                'florets. Re-cover pot, reduce heat to low, and continue to '
                'cook '
                'stem mixture until very soft, about 10 minutes longer. '
                'Transfer '
                'drained florets to now-empty bowl.',
          ],
        ),
        recipeOf(
          [
            '3 medium garlic cloves, minced or pressed through a garlic press '
                '(about 1 tablespoon)',
          ],
          steps: [
            'Combine the garlic with 1 tablespoon water in a small bowl; set '
                'aside. Bring 4 quarts water to a boil in a large pot. Add 1 '
                'tablespoon salt and the pasta to the boiling water and cook, '
                'stirring often, until al dente. Reserve ½ cup of the cooking '
                'water then drain the pasta and return it to the pot. Add ¼ '
                'cup '
                'of the reserved tomato juice and toss to combine.',
          ],
        ),
      ]) {
        expect(
          mediumOf(r, 0),
          isNull,
          reason: r.ingredients.first.items.first.raw,
        );
      }
    });
  });

  test('B2: each checkpoint-8 rewrite searches a cached answer whose top '
      'record, over the gate, is the right one (answers recorded from '
      'snapshot 12; normalized items of the corpus lines, e.g. "3 slices '
      'thick-cut bacon", "1½ tablespoons whole-grain mustard", "2 teaspoons '
      'Shaoxing wine or dry sherry", "⅓ cup (2 ounces) white baking '
      'chips")', () async {
    for (final (item, target, fdcId) in const <(String, String, int)>[
      ('thick-cut bacon', 'pork cured bacon unprepared', 168277),
      ('cilantro leaves and stems', 'cilantro', 2709782),
      ('cilantro leaves and tender stems', 'cilantro', 2709782),
      ('thai chile', 'jarred hot cherry peppers', 2709798),
      ('thai chiles', 'jarred hot cherry peppers', 2709798),
      ('green or red thai chiles', 'jarred hot cherry peppers', 2709798),
      ('elbow macaroni', 'pasta dry enriched', 169736),
      ('no-boil lasagna noodles', 'pasta dry enriched', 169736),
      ('80 percent lean ground chuck', '80 percent lean ground beef', 2514744),
      ('light or mild molasses', 'molasses', 168820),
      ('oyster-flavored sauce', 'oyster sauce', 2707150),
      (
        'shaoxing wine or dry sherry',
        'dry sherry or chinese rice wine',
        2710691,
      ),
      ('dried new mexican chiles', 'mild dried chile', 168570),
      ('flake sea salt', 'salt table', 173468),
      ('sea salt', 'salt table', 173468),
      ('whole grain mustard', 'mustard prepared', 326698),
      ('whole-grain mustard', 'mustard prepared', 326698),
      ('beef tenderloin center-cut chateaubriand', 'beef tenderloin', 2727573),
      ('center-cut filet mignon', 'beef tenderloin', 2727573),
      ('center-cut filets mignons', 'beef tenderloin', 2727573),
      ('kale or collard greens', 'kale', 323505),
      ('broccoli florets', 'broccoli', 747447),
      ('stone-ground cornmeal', 'cornmeal', 169697),
      ('baby back or loin back ribs', 'pork backribs raw', 168299),
      ('ripe but firm bosc pears', 'bosc pear', 167778),
      ('white baking chips', 'white chocolate', 167571),
    ]) {
      expect(searchQueryFor(item), target, reason: item);
      final top = rankCandidates(target, await provider.search(target)).first;
      expect(top.candidate.fdcId, fdcId, reason: item);
      expect(belowConfidenceGate(top.confidence), isFalse, reason: item);
    }
  });
}
