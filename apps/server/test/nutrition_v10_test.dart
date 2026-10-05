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
import 'package:salt_server/src/services/decision_rekey.dart';
import 'package:salt_server/src/services/item_key_backfill.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/fdc_fixtures.dart';

/// Matcher v10 (checkpoint 6, B1–B13): every mechanism pinned WITHOUT the
/// corpus — real corpus lines as strings (recipe named on each), FDC answers
/// from the recorded fixtures (sweep snapshot 8's cache).
void main() {
  final provider = FixtureProvider();
  Future<List<RankedCandidate>> rank(String query) async =>
      rankCandidates(query, await provider.search(query));
  Future<FdcFood> food(int id) async => (await provider.food(id))!;

  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  GramResolution? gramsOf(String raw, FdcFood? on) {
    final line = lineOf(raw);
    return resolveGrams(
      amounts: line.amounts,
      food: on,
      normalizedItem: normalizeItem(lineItemOf(line)),
      raw: raw,
    );
  }

  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v10');
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
    List<IngredientLine>? lines,
    String? servings,
  }) {
    final recipe = Recipe(
      id: id,
      title: id,
      slug: id,
      source: const RecipeSource(name: 'Test', type: 'book'),
      servings: servings,
      serves: parseServings(servings),
      ingredients: [
        IngredientGroup(items: lines ?? [for (final raw in raws) lineOf(raw)]),
      ],
      steps: [
        for (final (i, text) in steps.indexed)
          RecipeStep(number: i + 1, text: text),
      ],
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

  group('B1/B11: the bucket rule', () {
    test('a confirm on a line with no grams keeps it in no_grams and its '
        'recipe partial: "1 lemon twist" (Champagne Cocktail, 1155) on '
        '"Lemon peel, raw" (167749), which weighs no twist', () async {
      // Was "½ cup pecan halves" on 2346395 until matcher v17 fetched its SR
      // volume sibling (170182, "1 cup, halves" 99 g): it counts now; then
      // "1½ cups frozen pearl onions, thawed" (0005) on 170412 until matcher
      // v37 sized it by ATK's printed 8 ounces ≈ 2 cups.
      final db = tempDb();
      final r = recipeOf(db, 'r1', ['1 lemon twist']);
      await matchAndCompute(db, provider, r);
      final before = db.ingredientMatchesFor('r1').single;
      expect((before.fdcId, before.grams), (167749, null));
      expect(bucketOf(before), MatchBucket.noAmount);
      final totals = db.nutritionFor('r1')!;
      await applyMatchOverride(db, provider, r, 0, {'confirmed': true});
      final after = db.ingredientMatchesFor('r1').single;
      expect(
        (after.status, after.fdcId, after.grams),
        ('confirmed', 167749, null),
      );
      expect(bucketOf(after), MatchBucket.noAmount);
      expect(db.nutritionReviewCounts()['no_grams'], 1);
      final recomputed = db.nutritionFor('r1')!;
      expect(recomputed.status, 'partial');
      expect(recomputed.nutrientsJson, totals.nutrientsJson);
      // Confirmed water — no food — stays resolved.
      expect(
        matchBucketFor(
          status: 'confirmed',
          fdcId: null,
          grams: null,
          confidence: 1,
        ),
        MatchBucket.counted,
      );
    });

    test('the gate compares with a tolerance: a score a float drift puts '
        'a hair under 0.5 counts — Dart bucket and totals alike '
        '(scores synthesized: negative path)', () async {
      MatchBucket at(double confidence) => matchBucketFor(
        status: 'auto',
        fdcId: 1,
        grams: 10,
        confidence: confidence,
      );
      expect(at(0.5 - 1e-12), MatchBucket.counted);
      expect(at(0.4999), MatchBucket.check);
      expect(belowConfidenceGate(0.5 - 1e-12), isFalse);
      expect(belowConfidenceGate(0.4999), isTrue);
      // "3 tablespoons lard or extra-virgin olive oil" sat exactly at 0.500
      // (checkpoint 6); its row a drift below counts in the totals.
      final db = tempDb();
      const raw = '¼ teaspoon ground allspice';
      final r = recipeOf(db, 'r1', [raw]);
      await matchAndCompute(db, provider, r);
      final row = db.ingredientMatchesFor('r1').single;
      db.upsertIngredientMatch(row.copyWith(confidence: 0.5 - 1e-12));
      recomputeTotals(db, r);
      expect(db.nutritionFor('r1')!.status, 'complete');
      expect(db.nutritionReviewCounts()['counted'], 1);
    });
  });

  group('B11: every gate call site takes the tolerance', () {
    // No real (query, record) pair ranks in the drift window [0.5 − 1e-9,
    // 0.5): 328,461 random pairings of the snapshot-8 keys and answers found
    // none. The answer below is SYNTHESIZED (negative path): a Branded
    // description that ranks 0.49999999999999994 for the real key.
    Future<FdcCandidate> drifted(String description, String query) async {
      final allspice = await food(171315);
      final candidate = FdcCandidate(
        fdcId: 171315,
        description: description,
        dataType: 'Branded',
        nutrientsPer100g: allspice.nutrientsPer100g,
      );
      final score = rankCandidates(query, [candidate]).single.confidence;
      expect(score, allOf(lessThan(0.5), greaterThan(confidenceGateFloor)));
      return candidate;
    }

    test('the fetch gate: a pick a drift under 0.5 still fetches its '
        'portions — "¼ teaspoon ground allspice" (Stuffed Pork Chops, '
        '0207)', () async {
      final stub = _Answering(provider, {
        'ground allspice': [
          await drifted(
            'ground, allspice, leaves, white, fresh',
            'ground '
                'allspice',
          ),
        ],
      });
      final db = tempDb();
      final r = recipeOf(db, 'r1', ['¼ teaspoon ground allspice']);
      await matchAndCompute(db, stub, r);
      // Its detail is asked for: the tsp needs the record's portions.
      expect(stub.foods, [171315]);
    });

    test('the split guard: with no answer for the whole phrase, A a drift '
        'under 0.5 still replaces it — "⅓ cup apple cider or apple juice" '
        '(Cider-Glazed Pork Chops, 0204)', () async {
      final db = tempDb();
      final cider = await drifted(
        'apple, salted, cider, leaves, white',
        'apple cider',
      );
      db.fdcSearchCachePut('apple cider', jsonEncode([cider.toJson()]));
      const item = 'apple cider or apple juice';
      expect(lineSearchFor(db, item, itemKeyFor(item)).query, 'apple cider');
    });

    test('the decision reach: a same-food row a drift under 0.5 is counted, '
        'not reached; one at 0.4999 is — "¼ teaspoon ground allspice" '
        '(0207) and "½ teaspoon ground allspice" (Cincinnati Chili, 0303) '
        '(scores synthesized: negative path)', () async {
      final db = tempDb();
      final a = recipeOf(db, 'ra', ['¼ teaspoon ground allspice']);
      final b = recipeOf(db, 'rb', ['½ teaspoon ground allspice']);
      for (final r in [a, b]) {
        await matchAndCompute(db, provider, r);
      }
      final row = db.ingredientMatchesFor('rb').single;
      List<IngredientMatchRow> reach() => decisionReach(
        db,
        row.itemKey!,
        excluding: (recipeId: 'ra', position: 0),
        fdcId: row.fdcId,
      );
      db.upsertIngredientMatch(row.copyWith(confidence: 0.5 - 1e-12));
      expect(reach(), isEmpty);
      db.upsertIngredientMatch(row.copyWith(confidence: 0.4999));
      expect([for (final hit in reach()) hit.recipeId], ['rb']);
    });
  });

  group('B2: the two lost-grams regressions', () {
    test('Blueberry Pancakes (0745): "1 cup fresh or frozen blueberries" '
        'on Foundation 2346411 reads its sibling "Blueberries, frozen" '
        '(2709277): 150 g', () async {
      final db = tempDb();
      final r = recipeOf(db, 'r1', [
        '1 cup fresh or frozen blueberries, preferably wild, rinsed and dried',
      ]);
      await matchAndCompute(db, provider, r);
      final row = db.ingredientMatchesFor('r1').single;
      expect((row.fdcId, row.grams), (2346411, 150));
      expect(bucketOf(row), MatchBucket.counted);
      final basis = gramBasisFor(db, nutritionLines(r).single, row);
      expect(basis, contains('"Blueberries, frozen"'));
      expect(volumeSiblings[2346411], 2709277);
    });

    test('Grilled Hamburgers (0576): "4 hamburger rolls" are 4 × 44 g on '
        '172796 (its "roll 1 serving"); buns on the same record keep 52 g '
        '(Smashed Burgers, 0311)', () async {
      final rolls = await food(172796);
      expect(gramsOf('4 hamburger rolls, toasted', rolls)!.grams, 176);
      expect(
        gramsOf('2 hamburger buns, toasted if desired', rolls)!.grams,
        104,
      );
    });
  });

  group('B3/B4/B12: rewrites, each ranked on its recorded answer', () {
    test("country-style ribs: FDC answers the lines' own words with "
        'cooked records only; the rewrite ranks the raw 167895 first and '
        'the bone-in line reads its 0.65 refuse yield', () async {
      final own = await provider.search('bone-in country-style pork ribs');
      expect(own, isNotEmpty);
      expect(own.every((hit) => hit.description.contains('cooked')), isTrue);
      // Sweet-and-Tangy Grilled Country-Style Ribs (0612); Goi Cuon (0510).
      const boneIn = '4 pounds bone-in country-style pork ribs, trimmed';
      const boneless = '10 ounces boneless country-style pork ribs, trimmed';
      for (final raw in [boneIn, boneless]) {
        final target = searchQueryFor(normalizeItem(lineItemOf(lineOf(raw))));
        final top = (await rank(target)).first;
        expect(top.candidate.fdcId, 167895, reason: raw);
        expect(belowConfidenceGate(top.confidence), isFalse, reason: raw);
      }
      final raw = await food(167895);
      final bone = gramsOf(boneIn, raw)!;
      expect(bone.grams, closeTo(4 * 453.592 * 128 / 196, 0.01));
      expect(bone.basis, endsWith('× 0.65 edible (USDA refuse)'));
      expect(gramsOf(boneless, raw)!.grams, closeTo(283.495, 0.001));
    });

    test('variety words FDC files under another name, and the flagged '
        'approximations', () async {
      final expected = <String, int>{
        // Creamy Baked Four-Cheese Pasta (0366).
        '3 ounces Gorgonzola cheese, crumbled (about ¾ cup)': 172175,
        // Super Greens Soup (0021); Paella (0105).
        '⅓ cup Arborio rice': 168931,
        '2 cups Valencia or Arborio rice': 168931,
        // Skillet Tamale Pie (0072).
        '1 pound 90 percent lean ground sirloin': 2514743,
        // Chicken and Sausage Gumbo (0028).
        '8 ounces andouille sausage, sliced into ¼-inch thick half-moons':
            174584,
        // French-Style Pork Stew (0462): "Kielbasa, fully cooked,
        // unheated" — tied with "…, grilled", the tie goes to the record of
        // no cooking (v11).
        '12 ounces kielbasa sausage, halved lengthwise and sliced ½ inch '
                'thick':
            173879,
        // APPROXIMATIONS: Skillet Chicken, Broccoli, and Ziti (0069);
        // Alcatra (0007); Jerk Chicken (0632).
        '1 ounce Asiago cheese, grated (about ½ cup), plus extra for '
                'serving':
            325036,
        '5 allspice berries': 171315,
        '1 tablespoon whole allspice berries': 171315,
      };
      for (final MapEntry(key: raw, value: id) in expected.entries) {
        final line = lineOf(raw);
        final normalized = normalizeItem(lineItemOf(line));
        final target = searchQueryFor(normalized);
        expect(target, isNot(normalized), reason: raw);
        final top = (await rank(target)).first;
        expect(top.candidate.fdcId, id, reason: raw);
        expect(belowConfidenceGate(top.confidence), isFalse, reason: raw);
        // Under the line's own words the recorded answer is dishes below
        // the gate.
        final own = await provider.search(normalized);
        if (own.isNotEmpty) {
          expect(
            belowConfidenceGate(
              rankCandidates(normalized, own).first.confidence,
            ),
            isTrue,
            reason: raw,
          );
        }
      }
    });

    test('B12: lime zest searches the peel — Thai Chicken Curry (0550), '
        'Jerk Chicken (0632), Key Lime Bars (0849): as lemon zest since v11 '
        '(see nutrition_v11_test.dart for the pick)', () {
      for (final raw in [
        '2 teaspoons grated lime zest',
        '2 tablespoons finely grated lime zest (3 limes), plus lime wedges '
            'for serving',
        '1 tablespoon grated zest from 1 lime',
      ]) {
        final normalized = normalizeItem(lineItemOf(lineOf(raw)));
        expect(normalized, 'lime zest', reason: raw);
        expect(searchQueryFor(normalized), 'lemon zest', reason: raw);
      }
      expect(pendingSearches, isNot(contains('lemon zest')));
      // Lemon's own answer already holds its peel.
      expect(searchQueryFor('lemon zest'), 'lemon zest');
    });
  });

  group('B5: salt or baking soda in drained cooking water', () {
    // Chocolate-Hazelnut Spread (0778).
    const skinning =
        'Fill large bowl halfway with ice and water. Bring 4 cups water to '
        'boil. Add hazelnuts and baking soda and boil for 3 minutes. Transfer '
        'nuts to ice bath with slotted spoon, drain, and slip skins off with '
        'dish towel.';
    // Sesame Noodles with Shredded Chicken (0519).
    const noodleWater =
        'Bring 6 quarts water to a boil in a large pot. Add the noodles and '
        'salt and cook, stirring often, until tender, about 4 minutes for '
        'fresh and 10 minutes for dried.';
    const drained =
        ' Drain the noodles, rinse them under cold running water until cold, '
        'then toss them with the sesame oil.';

    test('the hazelnut skinning bath (0778) and the noodle water (0519) '
        "are held for review, storing no grams (v14, B6); the spread's own "
        'salt counts', () async {
      final db = tempDb();
      final spread = recipeOf(
        db,
        'spread',
        ['6 tablespoons baking soda', '⅛ teaspoon salt'],
        steps: [
          skinning,
          'Add sugar, cocoa, oil, vanilla, and salt and process until fully '
              'incorporated, about 2 minutes.',
        ],
      );
      expect(mediumOf(spread, 0), DiscardedMedium.cookingWater);
      expect(mediumOf(spread, 1), isNull);
      expect(DiscardedMedium.cookingWater.followsPolicy, isFalse);
      final noodles = recipeOf(
        db,
        'noodles',
        ['1 tablespoon table salt'],
        steps: ['$noodleWater$drained'],
      );
      expect(mediumOf(noodles, 0), DiscardedMedium.cookingWater);
      await matchAndCompute(db, provider, noodles);
      final row = db.ingredientMatchesFor('noodles').single;
      expect((row.hold, row.grams), ('discarded_medium', null));
      expect(bucketOf(row), MatchBucket.check);
    });

    test('RULE: salt counts in full unless a drain follows its water — '
        'water the food absorbs (Stovetop Rice Pudding, 0923), a pot no '
        'step drains (0519 without its drain sentence: synthesized '
        'negative path), salt measured apart from the pot (Ultimate Veggie '
        'Burgers, 1186), another amount (Turkey Tetrazzini, 0303), salt '
        'pork (Beef Burgundy, 0457)', () {
      final db = tempDb();
      final pudding = recipeOf(
        db,
        'pudding',
        ['¼ teaspoon table salt'],
        steps: [
          'Bring 2 cups water to boil in a large saucepan. Stir in the rice '
              'and salt, cover, and simmer over low heat, stirring once or '
              'twice, until the water is almost fully absorbed, 15 to 20 '
              'minutes.',
        ],
      );
      final undrained = recipeOf(
        db,
        'undrained',
        ['1 tablespoon table salt'],
        steps: [noodleWater],
      );
      final burgers = recipeOf(
        db,
        'burgers',
        ['1 teaspoon table salt, plus salt for cooking lentils and bulgur'],
        steps: [
          'Bring 3 cups water, lentils, and 1 teaspoon salt to boil in medium '
              'saucepan over high heat. Reduce heat to medium-low and simmer '
              'gently, stirring occasionally, until lentils are just '
              'beginning to fall apart, about 25 minutes. Drain lentils.',
        ],
      );
      final tetrazzini = recipeOf(
        db,
        'tetrazzini',
        ['Pinch table salt'],
        steps: [
          'Meanwhile, bring 4 quarts water to a boil in a large pot. Add 1 '
              'tablespoon salt and the pasta and cook until al dente. '
              'Reserve ¼ cup cooking water, drain the pasta, and return to '
              'the pot with the reserved liquid.',
        ],
      );
      final burgundy = recipeOf(
        db,
        'burgundy',
        ['½ teaspoon table salt'],
        steps: [
          'Bring the salt pork, reserved salt pork rind, and 3 cups water to '
              'a boil in a medium saucepan over high heat. Boil for 2 '
              'minutes, then drain well.',
        ],
      );
      for (final r in [pudding, undrained, burgers, tetrazzini, burgundy]) {
        expect(mediumOf(r, 0), isNull, reason: r.id);
      }
    });

    test('"dissolve salt in 2½ quarts water … submerged" is a brine at any '
        'volume (Grilled Glazed Baby Back Ribs, 0617): zero', () {
      final db = tempDb();
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
      final line = nutritionLines(ribs).single;
      expect(volumeMlOf(line.amounts)! < 44, isTrue, reason: 'under 3 tbsp');
    });

    test('the dissolve verb is what makes a measured "in" a brine: Popovers '
        '(1109) whisks its salt "in 8-cup liquid measuring cup"', () {
      final db = tempDb();
      final popovers = recipeOf(
        db,
        'popovers',
        ['¾ teaspoon table salt'],
        steps: [
          'Whisk together flour and salt in 8-cup liquid measuring cup or '
              'medium bowl. Add milk and eggs and whisk until mostly smooth '
              '(some small lumps are OK). Distribute batter evenly among '
              'prepared cups in popover pan. Bake until popovers are lofty '
              'and deep golden brown all over, 40 to 45 minutes. Serve hot, '
              'passing butter separately.',
        ],
      );
      expect(mediumOf(popovers, 0), isNull);
    });

    // EXCEPTION to the real-data rule, stated on purpose: the corpus holds
    // no dough whose yeast dissolves in measured water one sentence away
    // from its salt, and no salt seasoned onto meat before a later, drained
    // pasta pot — yet both guards protect other libraries. The two inputs
    // are synthesized (review Run 043; the user decides whether they stay).
    test("the dissolve must be in the salt's own sentence, and the water "
        'must be named before the end of it', () {
      final db = tempDb();
      final dough = recipeOf(
        db,
        'dough',
        ['1 teaspoon salt'],
        steps: [
          'Dissolve yeast in 2 tablespoons warm water. Stir in flour and '
              'salt until a shaggy dough forms.',
        ],
      );
      expect(
        mediumOf(dough, 0),
        isNull,
        reason: 'the yeast dissolved, not the salt',
      );
      final chops = recipeOf(
        db,
        'chops',
        ['1 teaspoon salt'],
        steps: [
          'Season pork with salt and pepper. Meanwhile, bring 4 quarts water '
              'to boil in large pot; cook pasta until al dente, then drain.',
        ],
      );
      expect(mediumOf(chops, 0), isNull, reason: 'the salt is on the pork');
    });

    test('each clause of the rule, on its own corpus recipe', () {
      final db = tempDb();
      // The water must BOIL: a velveting soak is no pot (Sichuan Stir-Fried
      // Pork in Garlic Sauce, 0540) — its rinsed-off soda is held a salt
      // bath instead since v14 (checkpoint 8).
      final velvet = recipeOf(
        db,
        'velvet',
        ['1 teaspoon baking soda'],
        steps: [
          'Cut pork into 2-inch lengths, then cut each length into ¼-inch '
              'matchsticks. Combine pork with ½ cup cold water and baking '
              'soda in bowl. Let sit at room temperature for 15 minutes.',
          'Rinse pork in cold water. Drain well and pat dry with paper '
              'towels. Whisk rice wine and cornstarch together in bowl. Add '
              'pork and toss to coat.',
        ],
      );
      expect(mediumOf(velvet, 0), DiscardedMedium.saltBath);
      // The drain may come in the NEXT step (Boiled Potatoes with Black
      // Olive Tapenade, 0703; Shrimp Cocktail, 0285).
      final potatoes = recipeOf(
        db,
        'potatoes',
        ['1 tablespoon salt'],
        steps: [
          'Bring 6 cups water, potatoes, and salt to boil in large saucepan '
              'over medium-high heat. Reduce heat to medium-low and simmer '
              'until potatoes are just tender when pierced with knife, 10 to '
              '15 minutes.',
          'Reserve ¼ cup cooking water. Drain potatoes and return them to '
              'pan.',
        ],
      );
      final cocktail = recipeOf(
        db,
        'cocktail',
        ['1 teaspoon table salt', 'Table salt and ground black pepper'],
        steps: [
          'Bring the reserved shells, 3 cups water, and salt to a boil in a '
              'medium saucepan over medium-high heat; reduce the heat to low, '
              'cover, and simmer until fragrant, about 20 minutes. Strain the '
              'stock through a fine-mesh strainer, pressing on the shells to '
              'extract all the liquid.',
          'Bring the stock and remaining ingredients except the shrimp to a '
              'boil in a 3- or 4-quart saucepan over high heat; boil for 2 '
              'minutes. Turn off the heat and stir in the shrimp; cover and '
              'let stand until the shrimp are firm and pink, 8 to 10 minutes. '
              'Meanwhile, fill a large bowl with ice water. Drain the shrimp, '
              'reserving the stock for another use.',
        ],
      );
      expect(mediumOf(potatoes, 0), DiscardedMedium.cookingWater);
      expect(mediumOf(cocktail, 0), DiscardedMedium.cookingWater);
      // The water may be named anywhere earlier in the step: Foolproof
      // Spaghetti Carbonara (0362) boils it two sentences before the salt.
      final carbonara = recipeOf(
        db,
        'carbonara',
        ['1 teaspoon salt'],
        steps: [
          'Meanwhile, bring 2 quarts water to boil in Dutch oven. Set colander '
              'in large bowl. Add spaghetti and salt to pot; cook, stirring '
              'frequently, until al dente. Drain spaghetti in colander set in '
              'bowl, reserving cooking water. Pour 1 cup cooking water into '
              'liquid measuring cup and discard remainder. Return spaghetti to '
              'now-empty bowl.',
        ],
      );
      expect(mediumOf(carbonara, 0), DiscardedMedium.cookingWater);
      // ... or later in the salt's own sentence: "Add yuca and salt to
      // boiling water" (Fried Yuca, 1098).
      final yuca = recipeOf(
        db,
        'yuca',
        ['1 teaspoon table salt'],
        steps: [
          'Add yuca and salt to boiling water and cook, adjusting heat to '
              'maintain vigorous simmer, until yuca is tender and mostly '
              'translucent, 20 to 25 minutes. While yuca is cooking, place '
              'wire cooling rack in rimmed baking sheet. Drain yuca well in '
              'colander. Spread on wire rack.',
        ],
      );
      expect(mediumOf(yuca, 0), DiscardedMedium.cookingWater);
      // ... but it must be WATER: Saag Paneer's (0563) curds drain from a
      // boiled pot, and its salt went in the milk — no cooking water; the
      // user's ruling R2 (2026-09-28) holds it with the cheese milk.
      final saag = recipeOf(
        db,
        'saag',
        ['3 quarts whole milk', '1 tablespoon salt', 'Salt and pepper'],
        steps: [
          'Line colander with triple layer of cheesecloth and set in sink. '
              'Bring milk to boil in Dutch oven over medium-high heat. Whisk '
              'in buttermilk and salt, turn off heat, and let stand for 1 '
              'minute. Pour milk mixture through cheesecloth and let curds '
              'drain for 15 minutes.',
        ],
      );
      expect(mediumOf(saag, 1), DiscardedMedium.cheeseMilk);
      // "do not drain" keeps the water (Black Bean Soup, 0474).
      final soup = recipeOf(
        db,
        'soup',
        ['⅛ teaspoon baking soda'],
        steps: [
          'Place the beans, ham, bay leaves, water, and baking soda in a '
              'large saucepan with a tight-fitting lid. Bring to a boil over '
              'medium-high heat; using a large spoon, skim the foam as it '
              'rises to the surface. Stir in the salt, reduce the heat to '
              'low, cover, and simmer briskly until the beans are tender, 1¼ '
              'to 1½ hours (if necessary, add 1 cup more water and continue '
              'to simmer until the beans are tender); do not drain the '
              'beans.',
        ],
      );
      expect(mediumOf(soup, 0), isNull);
      // A bare "salt" is a line's own only when it is the recipe's single
      // salt line: the brine's "Dissolve the salt in 2 gallons" is the
      // 2 cups', never the herb paste's ¾ teaspoon (Herbed Roast Turkey,
      // 0170).
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
      // A brine by sentence needs "dissolve … in N": a pickle whisked in
      // vinegar is none (Bulgogi, 1078).
      final bulgogi = recipeOf(
        db,
        'bulgogi',
        ['1½ teaspoons table salt'],
        steps: [
          'Whisk vinegar, sugar, and salt together in medium bowl. Add daikon '
              'and toss to combine. Gently press on daikon to submerge. Cover '
              'and refrigerate for at least 30 minutes or up to 24 hours.',
        ],
      );
      expect(mediumOf(bulgogi, 0), isNull);
      // ... and a MEASURED volume: salt dissolved in "remaining 2
      // tablespoons warm water" is the dough's (Easy Sandwich Bread, 0807).
      final bread = recipeOf(
        db,
        'bread',
        ['¾ teaspoon salt'],
        steps: [
          'Adjust oven rack to lower-middle position and heat oven to 375 '
              'degrees. Spray 8½ by 4½-inch loaf pan with vegetable oil spray. '
              'Dissolve salt in remaining 2 tablespoons warm water. When '
              'batter has doubled, attach bowl and paddle to mixer. Add '
              'salt-water mixture and mix on low speed until water is mostly '
              'incorporated, about 40 seconds.',
        ],
      );
      expect(mediumOf(bread, 0), isNull);
      // The drain must come AFTER the salt: rice drained before the pot is
      // filled leaves the pot's salt in the porridge (Congee, 1150).
      final congee = recipeOf(
        db,
        'congee',
        [
          '¾ cup long-grain white rice',
          '1 cup chicken broth',
          '¾ teaspoon '
              'table salt',
        ],
        steps: [
          'Place rice in fine-mesh strainer and rinse under cold running '
              'water until water runs clear. Drain well and transfer to Dutch '
              'oven. Add broth, salt, and 9 cups water and bring to boil over '
              'high heat. Reduce heat to maintain vigorous simmer.',
        ],
      );
      expect(mediumOf(congee, 2), isNull);
      // "1 teaspoon of the salt" is a written amount, not a bare salt: the
      // blanching water takes part of the line (Cincinnati Chili, 0303) —
      // counted in full until the user's ruling R2 (2026-09-28) held that
      // written pot share with the rest as its grams (nutrition_v13_test).
      final chili = recipeOf(
        db,
        'chili',
        ['2 teaspoons table salt, plus more to taste'],
        steps: [
          'Bring 2 quarts water and 1 teaspoon of the salt to a boil in a '
              'large saucepan. Add the ground chuck, stirring vigorously to '
              'separate the meat into individual strands. As soon as the foam '
              'from the meat rises to the top (this takes about 30 seconds) '
              'and before the water returns to a boil, drain the meat into a '
              'strainer and set it aside.',
        ],
      );
      expect(mediumOf(chili, 0), DiscardedMedium.cookingWater);
    });
  });

  group('B6: shellfish bought in the shell', () {
    // Paella on the Grill (0106), Cioppino (0108), Linguine allo Scoglio
    // (0348): the three littleneck lines; Cioppino's mussels; Indoor
    // Clambake's lobsters (0295); Crispy Salt-and-Pepper Shrimp (0279).
    const clams = '1 pound littleneck clams, scrubbed';
    const mussels = '1 pound mussels, scrubbed and debearded';

    test('held in_shell with their grams; meat, juice and shucked are '
        'not', () async {
      for (final raw in [
        clams,
        mussels,
        '2 (1½-pound) live lobsters',
        '1½ pounds shell-on shrimp (31 to 40 per pound)',
      ]) {
        expect(boughtInShell(raw), isTrue, reason: raw);
      }
      for (final raw in [
        // New England Lobster Roll (0292); Skillet Jambalaya (0079).
        '1 pound lobster meat, tail meat cut into ½-inch pieces and claw '
            'meat cut into 1-inch pieces',
        '1 (8-ounce) bottle clam juice',
        // Scrubbed, but no bivalve: American Potato Salad (0055).
        '2 pounds red potatoes (about 6 medium), scrubbed',
        // No corpus line buys shucked shellfish: synthesized (negative path).
        '1 pint shucked oysters, drained',
      ]) {
        expect(boughtInShell(raw), isFalse, reason: raw);
      }
      expect(
        buysRefuse('1 pound lobster meat, tail meat cut into ½-inch pieces'),
        isFalse,
      );
      // Best Prime Rib (0222) still buys its bones: "meat removed" is prep.
      expect(
        buysRefuse(
          '1 (7-pound) first-cut beef standing rib roast (3 bones), meat '
          'removed from bones, bones reserved',
        ),
        isTrue,
      );
      final db = tempDb();
      // Since v40 (E2) the clams are counted on SR 174214's shell yield,
      // so the held line here is the mussels' (174216 publishes none).
      final a = recipeOf(db, 'ra', [mussels]);
      final b = recipeOf(db, 'rb', [mussels, clams]);
      for (final r in [a, b]) {
        await matchAndCompute(db, provider, r);
      }
      for (final row in [
        ...db.ingredientMatchesFor('ra'),
        db.ingredientMatchesFor('rb').first,
      ]) {
        expect(row.hold, 'in_shell');
        expect(row.grams, closeTo(453.6, 0.1));
        expect(bucketOf(row), MatchBucket.check);
      }
      final shucked = db.ingredientMatchesFor('rb').last;
      expect((shucked.fdcId, shucked.hold, shucked.grams), (174214, null, 68));
      expect(bucketOf(shucked), MatchBucket.counted);
      // A LINE hold: each held line is a group of one in the queue, a
      // decision on the key reaches no other in-shell line, and a decision
      // that lands keeps the hold.
      final groups = db
          .nutritionReviewGroups(limit: 50, offset: 0)
          .where((group) => group.itemKey == 'mussel')
          .toList();
      expect([for (final group in groups) group.lines], [1, 1]);
      final offer = await matchesBody(db, provider, a);
      final item = (offer['items']! as List).single as Map;
      expect((item['others'], item['others_lines']), (0, 0));
      final line = nutritionLines(a).single;
      final decided = engineOutcome(
        a,
        line,
        await food(2706350),
        gramsOf(mussels, null),
        decided: true,
      );
      expect(decided.hold, 'in_shell');
      // A person's own confirm on the line clears it; the other recipe's
      // line keeps its hold, and its group is never badged decided.
      await applyMatchOverride(db, provider, a, 0, {'confirmed': true});
      expect(db.ingredientMatchesFor('ra').single.hold, isNull);
      expect(db.ingredientMatchesFor('rb').first.hold, 'in_shell');
      expect(db.decisionFor('mussel'), isNotNull);
      final held = db
          .nutritionReviewGroups(limit: 50, offset: 0)
          .singleWhere((group) => group.itemKey == 'mussel');
      expect((held.match.recipeId, held.decided), ('rb', false));
    });
  });

  group('B7: gross weight on a record with no refuse portion', () {
    test('counted, labelled approximate — since v39 (Y1, revising CP6 #11 '
        'and #5) at its class yield: a whole turkey (Classic Roast Turkey, '
        '0154, the chicken figure, interim), a Foundation chicken part '
        '(Chicken Teriyaki, 1178), a lamb shoulder chop (Irish Stew, '
        '1070); an SR hit whose detail was never fetched says only that '
        'no yield was read', () async {
      const approximate =
          '· approximate (gross weight, no USDA refuse portion)';
      const poultry = 276 / 453.59237;
      final turkey = gramsOf(
        '1 (12- to 14-pound) turkey; giblets, neck, and tailpiece removed and '
        'reserved for gravy',
        await food(171081),
      )!;
      expect(turkey.grams, closeTo(14 * 453.592 * poultry, 0.01));
      expect(
        turkey.basis,
        endsWith(
          '· approximate (yield of a whole turkey (interim: the chicken '
          'figure) from FDC 171447)',
        ),
      );
      final thighs = gramsOf(
        '1½–2 pounds bone-in chicken thighs',
        await food(2727567),
      )!;
      expect(thighs.grams, closeTo(1.75 * 453.592 * poultry, 0.01));
      expect(
        thighs.basis,
        endsWith('· approximate (yield of chicken parts from FDC 171447)'),
      );
      const chops = '4½ pounds lamb shoulder chops, each 1 to 1½ inches thick';
      final lamb = await food(174875);
      final counted = gramsOf(chops, lamb)!;
      expect(
        counted.grams,
        closeTo(4.5 * 453.592 * (128 / 196 + 133 / 201) / 2, 0.01),
      );
      expect(
        counted.basis,
        endsWith(
          '· approximate (yield of bony beef, lamb and veal from FDC 167895 '
          'and 168242 (the median))',
        ),
      );
      final hit = gramsOf(
        chops,
        FdcFood(
          fdcId: lamb.fdcId,
          description: lamb.description,
          dataType: lamb.dataType,
          nutrientsPer100g: lamb.nutrientsPer100g,
          portions: const [],
        ),
      )!;
      expect(hit.basis, endsWith('· no edible yield read'));
      // Shellfish in the shell is held, labelled approximate like any
      // gross weight — what a person's confirm counts (v11).
      expect(
        gramsOf(
          '1 pound mussels, scrubbed and debearded',
          await food(2706350),
        )!.basis,
        endsWith(approximate),
      );
    });
  });

  group("B8: a record whose nutrients are its sibling's", () {
    test('Pork and Cabbage Dumplings (0506): napa on Foundation 2727583 (no '
        "energy) counts with SR 169979's nutrients, its own food and "
        'grams kept; the basis names the sibling', () async {
      final db = tempDb();
      // Chinese black vinegar's recorded answer holds 169979's hit (Pai
      // Huang Gua, 0504), as the sweep's cache did.
      final r = recipeOf(db, 'r1', [
        '4 teaspoons Chinese black vinegar',
        '12 ounces napa cabbage (½ medium head), cored and minced',
      ]);
      await matchAndCompute(db, provider, r);
      final napa = db.ingredientMatchesFor('r1').last;
      expect((napa.fdcId, napa.hold), (2727583, null));
      expect(napa.grams, closeTo(340.2, 0.1));
      expect(bucketOf(napa), MatchBucket.counted);
      expect(nutrientSiblings[2727583], 169979);
      final basis = gramBasisFor(db, nutritionLines(r).last, napa);
      expect(
        basis,
        endsWith(' · nutrients of "Cabbage, chinese (pe-tsai), raw"'),
      );
      final energy =
          (jsonDecode(db.nutritionFor('r1')!.nutrientsJson) as Map)['energy']
              as Map;
      // 16 kcal per 100 g of 169979; since matcher v31 (Q7, ruled) the
      // vinegar line counts too, on "Vinegar, balsamic" (172241, 88 kcal),
      // flagged — until v30 it was held in check.
      final vinegar = db.ingredientMatchesFor('r1').first;
      expect(vinegar.fdcId, 172241);
      expect(
        energy['amount'],
        closeTo(napa.grams! * 16 / 100 + vinegar.grams! * 88 / 100, 0.01),
      );
    });
  });

  group('B9: the second-food tail', () {
    test('a juice range: Classic Guacamole (0471) counts 1¾ tablespoons on '
        'lime juice', () async {
      final db = tempDb();
      final r = recipeOf(db, 'r1', [
        '¼ teaspoon grated lime zest plus 1½–2 tablespoons juice',
      ]);
      await matchAndCompute(db, provider, r);
      final row = db.ingredientMatchesFor('r1').single;
      expect((row.fdcId, row.hold), (168156, null));
      final line = nutritionLines(r).single;
      expect(gramBasisFor(db, line, row), contains('juice only'));
      final juice = plusPartOf(line.raw)!.amount;
      expect(volumeMlOf([juice]), closeTo(1.75 * 14.7868, 0.01));
      // A mixed-number HIGH bound: "3–3½ cups" (French-Style Chicken and
      // Stuffing in a Pot, 0454) is 3¼ cups.
      final cup = volumeMlOf(lineOf('1 cup chicken broth').amounts)!;
      expect(
        volumeMlOf(lineOf('3–3½ cups low-sodium chicken broth').amounts),
        closeTo(3.25 * cup, 0.01),
      );
    });

    test('a zest in counted strips with a juice volume counts the juice '
        'only: Avgolemono (0005), Moroccan Chicken (0100), Baklava (0851); a '
        'strip line that gives the peel a volume stays held (Crispy Orange '
        'Beef, 0536)', () async {
      final lemon = await food(167747);
      final lines = {
        '12 (3-inch) strips lemon zest plus 6 tablespoons juice, plus extra '
                'juice for seasoning (3 lemons)':
            6.0,
        '3 (2-inch) strips zest plus 3 tablespoons juice from 1 lemon': 3.0,
        '1 tablespoon lemon juice from 1 lemon, plus 3 strips zest, removed '
                'in large strips with vegetable peeler':
            1.0,
      };
      for (final MapEntry(key: raw, value: tablespoons) in lines.entries) {
        final rule = secondFoodRuleOf(lineOf(raw));
        expect(rule?.fdcId, 167747, reason: raw);
        final grams = rule!.gramsOn(lemon)!;
        expect(
          grams.grams,
          closeTo(
            gramsOf('$tablespoons tablespoons lemon juice', lemon)!.grams,
            0.01,
          ),
          reason: raw,
        );
      }
      expect(
        secondFoodRuleOf(
          lineOf(
            '10 (3-inch) strips orange peel, sliced thin lengthwise (¼ cup), '
            'plus ¼ cup juice (2 oranges)',
          ),
        ),
        isNull,
      );
    });

    test("a bare zest takes the line's fruit in the search too: Key Lime "
        'Pie (0989), Bananas Foster (0959) — the corpus items', () {
      const pie = IngredientLine(
        raw: '4 teaspoons grated zest plus ½ cup juice from 3 or 4 limes',
        item: 'grated zest plus 1/2 cup juice',
        prep: 'from 3 or 4 limes',
        amounts: [
          Amount(
            measure: Measure.volume,
            quantity: '4',
            unit: 'teaspoon',
            primary: true,
          ),
        ],
      );
      expect(normalizeItem(lineItemOf(pie)), 'lime zest');
      expect(lineKeyOf(pie), 'lime zest plus juice');
      const foster = IngredientLine(
        raw: '1 (2-inch) strip zest from 1 lemon',
        item: '(2-inch) zest',
        prep: 'from 1 lemon',
        amounts: [
          Amount(
            measure: Measure.count,
            quantity: '1',
            unit: 'strip',
            primary: true,
          ),
        ],
      );
      expect(normalizeItem(lineItemOf(foster)), 'lemon zest');
      expect(lineKeyOf(foster), 'lemon zest');

      // The only key v10 changes in the library: a v9 decision on 0959's
      // line follows it at boot, decisions before rows.
      final db = tempDb();
      final r = recipeOf(db, 'r0959', const [], lines: const [foster]);
      db
        ..upsertIngredientMatch(
          IngredientMatchRow(
            recipeId: r.id,
            position: 0,
            raw: foster.raw,
            itemKey: 'zest',
            fdcId: 167749,
            description: 'Lemon peel, raw',
            dataType: 'SR Legacy',
            confidence: 1,
            grams: null,
            gramSource: null,
            status: 'confirmed',
          ),
        )
        ..insertDecision(
          const IngredientDecisionRow(
            itemKey: 'zest',
            item: '(2-inch) zest',
            fdcId: 167749,
            description: 'Lemon peel, raw',
            dataType: 'SR Legacy',
            decidedBy: null,
            decidedAt: '2026-09-27 00:00:00',
          ),
        )
        ..setSetting(decisionRekeySetting, '9')
        ..setSetting(itemKeyBackfillSetting, '9');
      rekeyAfterMatcherChange(db);
      expect(db.decisionFor('lemon zest')?.fdcId, 167749);
      expect(db.decisionFor('zest'), isNull);
      expect(db.matchesForItemKey('lemon zest'), hasLength(1));
    });
  });

  group('B10: skinless fish', () {
    test('"skinless" leaves the denominator of a record of the fish: cod '
        '(Butter-Basted Fish Fillets, 0266), halibut (Cioppino, 0108), '
        'salmon (Sesame-Crusted Salmon, 0261) cross the gate on the raw '
        'fish', () async {
      final cod = (await rank('skinless cod fillets')).first;
      expect(cod.candidate.fdcId, 2684444);
      expect(belowConfidenceGate(cod.confidence), isFalse);
      final salmon = await rank('skinless salmon fillets');
      expect(salmon.first.candidate.description, 'Fish, salmon, raw');
      expect(belowConfidenceGate(salmon.first.confidence), isFalse);
      // "Lomi salmon" and "Salmon salad" are dishes of it.
      for (final dish in ['Lomi salmon', 'Salmon salad']) {
        final ranked = salmon.firstWhere(
          (c) => c.candidate.description == dish,
        );
        expect(ranked.docked, isTrue, reason: dish);
      }
    });

    test('a line that names no species keeps "skinless" uncredited: white '
        'fish (Poached Fish Fillets, 0265) stays below the gate on "Fish, '
        'sucker, white, raw"', () async {
      final white = (await rank('skinless white fish fillets')).first;
      expect(white.candidate.description, 'Fish, sucker, white, raw');
      expect(belowConfidenceGate(white.confidence), isTrue);
    });
  });

  group('B13: the basis flag', () {
    test('per_batch when the basis is 1 — the whole batch; a basis above 1 '
        'divides it, whether by a serves count or a MAKES yield', () async {
      final db = tempDb();
      const salt = '¼ teaspoon ground allspice';
      // Sandwich Bread (MAKES 1 LOAF); Chicago-Style Deep-Dish Pizza (MAKES
      // TWO 9-INCH PIZZAS: a basis of 2 is one pizza, not the batch);
      // Chocolate Chip Cookies (MAKES 16 COOKIES); Avgolemono (SERVES 6 TO
      // 8).
      final cases = {
        'MAKES 1 LOAF': 'per_batch',
        'MAKES TWO 9-INCH PIZZAS': 'per_serving',
        'MAKES 16 COOKIES': 'per_serving',
        'SERVES 6 TO 8': 'per_serving',
      };
      for (final (i, MapEntry(key: servings, value: kind))
          in cases.entries.indexed) {
        final r = recipeOf(db, 'r$i', [salt], servings: servings);
        await matchAndCompute(db, provider, r);
        final body = nutritionBody(db, r, forAdmin: false);
        expect(body['basis_kind'], kind, reason: servings);
      }
      final pizza = nutritionBody(
        db,
        recipeOf(db, 'r1', [salt], servings: 'MAKES TWO 9-INCH PIZZAS'),
        forAdmin: false,
      );
      expect(pizza['serving_basis'], 2);
      final none = recipeOf(db, 'none', [salt]);
      await matchAndCompute(db, provider, none);
      expect(nutritionBody(db, none, forAdmin: false)['serving_basis'], 1);
      expect(
        nutritionBody(db, none, forAdmin: false)['basis_kind'],
        'per_batch',
      );
      // An admin's basis of 1 on a serves count is the batch too.
      final serves = recipeOf(db, 'r3', [salt], servings: 'SERVES 6 TO 8');
      recomputeTotals(db, serves, servingBasis: 1);
      expect(
        nutritionBody(db, serves, forAdmin: false)['basis_kind'],
        'per_batch',
      );
    });
  });
}

/// [inner]'s recorded answers, except the searches [answers] names; counts
/// the food details asked for.
class _Answering implements NutritionProvider {
  _Answering(this.inner, this.answers);

  final NutritionProvider inner;
  final Map<String, List<FdcCandidate>> answers;
  final List<int> foods = [];

  @override
  Future<List<FdcCandidate>> search(String query) async =>
      answers[query] ?? await inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) {
    foods.add(fdcId);
    return inner.food(fdcId);
  }
}
