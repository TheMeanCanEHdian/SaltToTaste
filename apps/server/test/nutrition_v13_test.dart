// Real corpus lines and steps wrap across adjacent literals.
// ignore_for_file: no_adjacent_strings_in_list

import 'dart:convert';
import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/fdc_fixtures.dart';

/// Matcher v13 (the checkpoint-7 review and the user's rulings R2–R4 of
/// 2026-09-28): every mechanism pinned WITHOUT the corpus — real corpus
/// lines and step texts as strings (recipe named on each), FDC answers
/// recorded from sweep snapshot 11. A guard no corpus line exercises is
/// pinned on a synthesized line, said so where it is.
void main() {
  final provider = FixtureProvider();
  Future<List<RankedCandidate>> rank(String query) async =>
      rankCandidates(query, await provider.search(query));

  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v13');
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
    );
    db?.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h');
    return recipe;
  }

  DiscardedMedium? mediumOf(Recipe recipe, int i) {
    final line = nutritionLines(recipe)[i];
    return discardedMediumOf(recipe, line, normalizeItem(lineItemOf(line)));
  }

  MatchBucket bucketOf(IngredientMatchRow row) => matchBucketFor(
    status: row.status,
    fdcId: row.fdcId,
    grams: row.grams,
    confidence: row.confidence,
    hold: row.hold,
    gramSource: row.gramSource,
  );

  group('E1: the oyster-mushroom dock (_varietyHosts)', () {
    test('"24 oysters, 2½ to 3 inches long, well scrubbed" (Roasted Oysters '
        'on the Half Shell, 1184) ranks "Oysters, raw" first on the recorded '
        'answer; both mushroom records are docked', () async {
      final ranked = await rank('oysters');
      expect(ranked.first.candidate.fdcId, 2706351);
      expect(ranked.first.confidence, closeTo(0.91, 0.001));
      for (final id in [1999627, 2003599]) {
        final mushroom = ranked.firstWhere((c) => c.candidate.fdcId == id);
        expect(mushroom.docked, isTrue, reason: '$id');
        expect(mushroom.confidence, lessThan(ranked.first.confidence));
      }
    });

    test('a line asking for the mushroom keeps it: "oyster mushrooms"', () {
      final ranked = rankCandidates('oyster mushrooms', const [
        FdcCandidate(
          fdcId: 1999627,
          description: 'Mushroom, oyster',
          dataType: 'Foundation',
        ),
        FdcCandidate(
          fdcId: 2706351,
          description: 'Oysters, raw',
          dataType: 'Survey (FNDDS)',
        ),
      ]);
      expect(ranked.first.candidate.fdcId, 1999627);
      expect(ranked.first.docked, isFalse);
    });

    test('with no record filing oysters first nothing is docked (the '
        'recorded answer less every record whose first segment names an '
        'oyster: a synthesized negative path)', () async {
      final hits = [
        for (final hit in await provider.search('oysters'))
          if (!hit.description
              .split(',')
              .first
              .toLowerCase()
              .contains('oyster'))
            hit,
      ];
      final mushroom = rankCandidates(
        'oysters',
        hits,
      ).firstWhere((c) => c.candidate.fdcId == 1999627);
      expect(mushroom.docked, isFalse);
      expect(mushroom.confidence, closeTo(0.95, 0.001));
    });
  });

  group('E2: the stem and the dangling connector match their docs', () {
    // No corpus line or cached record has an x/z "-es" plural or ends in
    // "or": both are synthesized (stated exceptions).
    test('"-xes" loses its "es": "cake mixes" scores "Cake mix, dry" as '
        '"cake mix" does', () {
      const mix = FdcCandidate(
        fdcId: 1,
        description: 'Cake mix, dry',
        dataType: 'SR Legacy',
      );
      final plural = rankCandidates('cake mixes', [mix]).single.confidence;
      final singular = rankCandidates('cake mix', [mix]).single.confidence;
      expect(plural, singular);
      expect(plural, greaterThan(0.9));
    });

    test('"-zes" loses its "s" alone: "glazes" keeps the record\'s '
        '"glaze" token (refix 2: a synthesized line — the corpus has no '
        '"-zes" ingredient; stripping "es" would stem it "glaz")', () {
      const glaze = FdcCandidate(
        fdcId: 1,
        description: 'Glaze, chocolate',
        dataType: 'SR Legacy',
      );
      // The stem shares the record's 'glaze' token; with the z strip it was
      // 'glaz' and the record scored 0.
      final plural = rankCandidates('glazes', [glaze]).single.confidence;
      expect(plural, greaterThan(0.5));
    });

    test('a dangling "or" is cut like "and": "lime zest or" is lime zest', () {
      expect(normalizeItem('grated fresh lime zest or'), 'lime zest');
      expect(normalizeItem('grated fresh lime zest and'), 'lime zest');
    });
  });

  test('E3: "6 (6- to 8-ounce) center-cut skin-on salmon fillets" '
      '(Grill-Smoked Salmon, 0646) takes the salmon rewrite and ranks "Fish, '
      'salmon, raw" over the gate', () async {
    final line = lineOf('6 (6- to 8-ounce) center-cut skin-on salmon fillets');
    final query = searchQueryFor(normalizeItem(lineItemOf(line)));
    expect(query, 'skinless salmon fillet');
    final top = (await rank(query)).first;
    expect(top.candidate.description, 'Fish, salmon, raw');
    expect(belowConfidenceGate(top.confidence), isFalse);
  });

  test('E4: the prune lines count on "Prune, dried" (2709211, recorded from '
      'snapshot 11) with its portions: "12 pitted prunes" (Slow-Cooker '
      "Beer-Braised Short Ribs, 0088) and Chicken Marbella's (0124) two "
      '"⅓ cup pitted prunes" lines', () async {
    final db = tempDb();
    final fixtures = FixtureProvider();
    final r = recipeOf(db: db, [
      '12 pitted prunes',
      '⅓ cup pitted prunes',
      '⅓ cup pitted prunes, chopped coarse',
    ]);
    await matchAndCompute(db, fixtures, r);
    final rows = db.ingredientMatchesFor('r');
    expect([for (final row in rows) row.fdcId], [2709211, 2709211, 2709211]);
    expect(
      [for (final row in rows) row.gramSource],
      [
        'piece',
        'portion',
        'portion',
      ],
    );
    expect(rows[0].grams, closeTo(96, 0.01));
    expect(rows[1].grams, closeTo(53.33, 0.01));
    expect(rows[2].grams, closeTo(53.33, 0.01));
    for (final row in rows) {
      expect(bucketOf(row), MatchBucket.counted);
    }
  });

  group("E5: a dozen is the leading number's", () {
    Future<double?> gramsOf(String raw, List<Amount> amounts) async =>
        resolveGrams(
          amounts: amounts,
          food: await provider.food(2706350),
          normalizedItem: 'mussels',
          raw: raw,
        )?.grams;
    Amount count(String quantity) =>
        Amount(measure: Measure.count, quantity: quantity, primary: true);

    test('"1 dozen mussels, scrubbed and debearded" (Paella, 0105) is 12 '
        'mussels, 180 g', () async {
      expect(
        await gramsOf('1 dozen mussels, scrubbed and debearded', [count('1')]),
        closeTo(180, 0.01),
      );
    });

    // No corpus line has a second count or a dozen past its leading
    // number: synthesized (stated exceptions).
    test('a second bare count on the line is no dozen, and a dozen not at '
        'the front multiplies nothing', () async {
      expect(
        await gramsOf('1 dozen mussels plus 3 clams', [count('3')]),
        closeTo(45, 0.01),
      );
      expect(
        await gramsOf('1 lemon plus 1 dozen mussels', [count('1')]),
        closeTo(15, 0.01),
      );
      expect(
        await gramsOf('2 dozen mussels', [count('2')]),
        closeTo(360, 0.01),
      );
      expect(
        await gramsOf('half dozen mussels', [count('1')]),
        closeTo(15, 0.01),
      );
    });
  });

  group('E6: a below-gate pick takes its sized, cached twin '
      '(belowGateSizedTwin)', () {
    const seeds = '½ cup pomegranate seeds';

    test('since matcher v17 "½ cup pomegranate seeds" (Barley Salad with '
        "Pomegranate, 0718) searches `pomegranate raw`: FDC's answer (live, "
        'snapshot 13) puts FNDDS "Pomegranate, raw" (2709267) first, tied '
        'at 1.0 with SR 169134 — counted at 87.5 g on its own cup (175 g), '
        'over the gate, and SR 169134 is never fetched', () async {
      final db = tempDb();
      final fixtures = FixtureProvider();
      final r = recipeOf(db: db, [seeds]);
      await matchAndCompute(db, fixtures, r);
      final row = db.ingredientMatchesFor('r').single;
      expect((row.fdcId, row.grams), (2709267, 87.5));
      expect(row.confidence, closeTo(1, 1e-9));
      expect(bucketOf(row), MatchBucket.counted);
      expect(fixtures.searchCalls, 1);
      expect(fixtures.foodCalls, 1);
      final ranked = rankCandidates(
        'pomegranate raw',
        await fixtures.search('pomegranate raw'),
      );
      expect([for (final c in ranked) c.candidate.fdcId], [2709267, 169134]);
      expect(ranked[1].confidence, closeTo(1, 1e-9));
    });
  });

  group('E6 guards, on the recorded pomegranate answer (the weight line, '
      'the scores and the stripped record are synthesized: stated '
      'exceptions — no corpus line reaches them)', () {
    Future<(SaltDatabase, List<RankedCandidate>)> setUp() async {
      final food = (await provider.food(2709267))!;
      final db = tempDb()..fdcFoodCachePut(2709267, jsonEncode(food.toJson()));
      return (db, await rank('pomegranate seeds'));
    }

    test('the real case takes the twin', () async {
      final (db, ranked) = await setUp();
      final twin = belowGateSizedTwin(
        db,
        lineOf('½ cup pomegranate seeds'),
        'pomegranate seeds',
        ranked,
        ranked.first,
      );
      expect(twin?.candidate.candidate.fdcId, 2709267);
    });

    test('a pick at the gate, a cached pick, a weight line, a pick with no '
        'same-food twin and a twin without macros take none', () async {
      final (db, ranked) = await setUp();
      final best = ranked.first;
      final seeds = lineOf('½ cup pomegranate seeds');
      RankedCandidate scored(double confidence) => RankedCandidate(
        candidate: best.candidate,
        confidence: confidence,
      );
      expect(
        belowGateSizedTwin(db, seeds, 'pomegranate seeds', ranked, scored(0.5)),
        isNull,
      );
      expect(
        belowGateSizedTwin(
          db,
          lineOf('8 ounces pomegranate seeds'),
          'pomegranate seeds',
          ranked,
          best,
        ),
        isNull,
      );
      final other = [
        best,
        for (final c in ranked.skip(1))
          if (c.candidate.fdcId == 2709267)
            RankedCandidate(
              candidate: FdcCandidate(
                fdcId: 2709267,
                description: 'Pomegranate juice',
                dataType: c.candidate.dataType,
              ),
              confidence: c.confidence,
            ),
      ];
      expect(
        belowGateSizedTwin(db, seeds, 'pomegranate seeds', other, best),
        isNull,
      );
      final bare = (await provider.food(2709267))!;
      db.fdcFoodCachePut(
        2709267,
        jsonEncode(
          FdcFood(
            fdcId: bare.fdcId,
            description: bare.description,
            dataType: bare.dataType,
            nutrientsPer100g: const {},
            portions: bare.portions,
          ).toJson(),
        ),
      );
      expect(
        belowGateSizedTwin(db, seeds, 'pomegranate seeds', ranked, best),
        isNull,
      );
      db
        ..fdcFoodCachePut(2709267, jsonEncode(bare.toJson()))
        ..fdcFoodCachePut(best.candidate.fdcId, jsonEncode(bare.toJson()));
      expect(
        belowGateSizedTwin(db, seeds, 'pomegranate seeds', ranked, best),
        isNull,
      );
    });
  });

  group('E8: sub-recipe reference lines stay out of the totals', () {
    test('isSubRecipeReference: the ruled marks, and what is not one', () {
      for (final raw in [
        // Lighter Chicken Parmesan (0416), Rainbow Cake (1201), Broccoli-
        // Cheese Soup, Buffalo Wings, Restaurant-Style Herb Sauce, Pan-
        // Roasted Halibut Steaks, Wilted Spinach Salad (0040), Grilled Pork
        // Chops (0598), Mujaddara, Maryland Crab Cakes.
        '1 recipe Simple Tomato Sauce (recipe follows), warmed (see note)',
        '10 cups Vanilla Frosting (recipe follows)',
        '1 recipe Buttery Croutons (this page)',
        '1 recipe Rich and Creamy Blue Cheese Dressing (see this page)',
        '¼ cup Sauce Base (½ recipe; recipe follows)',
        '1 recipe flavored butter or vinaigrette (recipes follow)',
        '3 hard-cooked eggs (recipe follows), peeled and quartered',
        '1 recipe Basic Spice Rub for Pork Chops (recipe follows) or 2 '
            'teaspoons pepper',
        '1 recipe Crispy Onions, plus 3 tablespoons reserved oil (recipe '
            'follows)',
        'Sweet and Tangy Tartar Sauce (this page), Creamy Chipotle Chile '
            'Sauce (recipe follows), or lemon wedges',
        // v14 (checkpoint 8, B7): a line that opens "<n> recipe" is one
        // with no mark (Salade Lyonnaise, 0434; the pie-dough lines).
        '1 recipe double-crust pie dough',
        '1 recipe Perfect Poached Eggs',
      ]) {
        expect(isSubRecipeReference(raw), isTrue, reason: raw);
      }
      for (final raw in [
        // A food offered first (Crunchy Kettle Potato Chips, German Apple
        // Pancake); a technique pointer after the food (Shrimp Scampi 0428,
        // Classic Greek Salad, Classic Roast Stuffed Turkey).
        '½ teaspoon table salt or 1 recipe topping (recipes follow)',
        'Maple syrup or Caramel Sauce (recipe follows), for serving',
        '2 pounds extra-large shrimp (21 to 25 per pound), peeled and '
            'deveined (see this page)',
        '1 medium cucumber, peeled, halved lengthwise, seeded, and sliced ⅛ '
            'inch thick (see this page)',
        '1 (12- to 14-pound) turkey; giblets, neck, and tailpiece removed '
            'and reserved for gravy (see this page)',
      ]) {
        expect(isSubRecipeReference(raw), isFalse, reason: raw);
      }
    });

    test("Lighter Chicken Parmesan's (0416) sauce line is stored on no food, "
        '0 g unmeasured with its note, counted as resolved — it read "Tomato '
        'products, canned, sauce" at 123 g', () async {
      final db = tempDb();
      final fixtures = FixtureProvider();
      const raw =
          '1 recipe Simple Tomato Sauce (recipe follows), warmed (see note)';
      final r = recipeOf(db: db, [raw]);
      await matchAndCompute(db, fixtures, r);
      final row = db.ingredientMatchesFor('r').single;
      expect(
        (row.fdcId, row.grams, row.gramSource, row.status, row.description),
        (null, 0, 'unmeasured', 'confirmed', subRecipeNote),
      );
      expect(bucketOf(row), MatchBucket.counted);
      expect(fixtures.searchCalls, 0);
      expect(
        gramBasisFor(db, lineOf(raw), row),
        'a sub-recipe — counted as 0 g',
      );
    });

    test('a count of the food itself counts on it: "3 hard-cooked eggs (see '
        'this page), …" (American Potato Salad, 0055) is 150 g of '
        '"Egg, whole, cooked, hard-boiled", as before v13', () async {
      final db = tempDb();
      const raw =
          '3 hard-cooked eggs (see this page), peeled and cut into ½-inch '
          'pieces';
      expect(isSubRecipeReference(raw), isTrue);
      expect(subRecipeCountsItsFood(lineOf(raw)), isTrue);
      await matchAndCompute(db, FixtureProvider(), recipeOf(db: db, [raw]));
      final row = db.ingredientMatchesFor('r').single;
      expect(
        (row.fdcId, row.grams, row.gramSource, row.status),
        (173424, 150, 'piece', 'auto'),
      );
      expect(bucketOf(row), MatchBucket.counted);
    });

    test('a batch, a "1 recipe" line or no amount stays 0 g and is never '
        'searched: Rainbow Cake (1201), Curry Deviled Eggs (0731), Rosé '
        'Sangria, Panna Cotta', () async {
      for (final raw in [
        '10 cups Vanilla Frosting (recipe follows)',
        '1 recipe Easy-Peel Hard-Cooked Eggs (recipe follows)',
        '4 ounces Simple Syrup (recipe follows)',
        'Raspberry Coulis (recipe follows)',
      ]) {
        expect(subRecipeCountsItsFood(lineOf(raw)), isFalse, reason: raw);
        final db = tempDb();
        final fixtures = FixtureProvider();
        await matchAndCompute(db, fixtures, recipeOf(db: db, [raw]));
        final row = db.ingredientMatchesFor('r').single;
        expect(
          (row.fdcId, row.grams, row.description),
          (
            null,
            0,
            subRecipeNote,
          ),
          reason: raw,
        );
        expect(fixtures.searchCalls, 0, reason: raw);
      }
    });

    test('a count its pick weighs counts: "8 Home-Fried Taco Shells (recipe '
        'follows)" (Ground Beef Tacos, 0478) on "Taco shells, baked", whose '
        '"shell" portion v14 reads (B3; v13 stored the sub-recipe row for '
        'want of grams)', () async {
      final db = tempDb();
      final fixtures = FixtureProvider();
      const raw = '8 Home-Fried Taco Shells (recipe follows)';
      expect(subRecipeCountsItsFood(lineOf(raw)), isTrue);
      await matchAndCompute(db, fixtures, recipeOf(db: db, [raw]));
      final row = db.ingredientMatchesFor('r').single;
      expect(
        (row.fdcId, row.grams, row.gramSource, row.status),
        (172800, 103.2, 'piece', 'auto'),
      );
      expect(fixtures.searchCalls, 1);
    });

    test('white chocolate chips (Low-Fat Chocolate Mousse, 0933; Blondies) '
        'search the white chocolate answer, where a coated record is a '
        'composite: "Candies, white chocolate" (167571) ranks first', () async {
      expect(searchQueryFor('white chocolate chips'), 'white chocolate');
      final ranked = await rank('white chocolate');
      expect(ranked.first.candidate.fdcId, 167571);
      expect(belowConfidenceGate(ranked.first.confidence), isFalse);
      final pretzels = ranked.firstWhere((c) => c.candidate.fdcId == 2708261);
      expect(pretzels.docked, isTrue);
      // The coated granola bar falls under the gate for milk chocolate
      // chips (Browned Butter Blondies): it counted 85 g at 0.87.
      final milk = (await rank('milk chocolate chips')).first;
      expect(milk.candidate.description, startsWith('Snacks, granola bars'));
      expect(belowConfidenceGate(milk.confidence), isTrue);
    });
  });

  group("R3: a submerge brine's sugar and aromatics are zero, like its salt "
      '(_brineCoSolute, brineSugar under the policy)', () {
    test('"½ cup sugar" in Perfect Roast Chicken\'s (0134) brine is zeroed, '
        'no longer held', () async {
      final r = recipeOf(
        ['½ cup table salt', '½ cup sugar'],
        steps: [
          'Dissolve the salt and sugar in 2 quarts cold water in a large '
              'container. Submerge the chicken in the brine, cover, and '
              'refrigerate for 1 hour.',
        ],
      );
      expect(mediumOf(r, 1), DiscardedMedium.brineSugar);
      expect(DiscardedMedium.brineSugar.followsPolicy, isTrue);
      final out = engineOutcome(
        r,
        nutritionLines(r)[1],
        (await provider.food(746784))!,
        const GramResolution(grams: 94, source: GramSource.portion),
        picked: true,
      );
      expect((out.grams, out.source, out.hold), (0, 'discarded', null));
    });

    test('"2 tablespoons sugar" under the ¼-cup threshold, dissolved with '
        'the salt (Ultimate Shrimp Scampi, 0428)', () {
      final r = recipeOf(
        ['3 tablespoons salt', '2 tablespoons sugar'],
        steps: [
          'Dissolve salt and sugar in 1 quart cold water in large container. '
              'Submerge shrimp in brine, cover, and refrigerate for 15 '
              'minutes. Remove shrimp from brine and pat dry with paper '
              'towels.',
        ],
      );
      expect(mediumOf(r, 1), DiscardedMedium.brineSugar);
    });

    // Crispy Fried Chicken (0148).
    final fried = recipeOf(
      [
        '½ cup table salt',
        '¼ cup sugar',
        '2 tablespoons paprika',
        '7 cups buttermilk',
        '3 medium garlic heads, cloves separated and smashed',
        '3 bay leaves, crumbled',
        '4 pounds bone-in, skin-on chicken pieces (split breasts cut in half, '
            'drumsticks, and/or thighs), trimmed',
      ],
      steps: [
        'Dissolve the salt, sugar, and paprika in the buttermilk in a large '
            'container. Add the garlic and bay leaves, submerge the chicken '
            'in the brine, cover, and refrigerate for 2 to 3 hours.',
      ],
    );

    test('the paprika, garlic and bay leaves of Crispy Fried Chicken (0148) '
        'are brine; the submerged chicken is not', () {
      expect(
        [
          for (final i in [2, 4, 5, 6]) mediumOf(fried, i),
        ],
        [
          DiscardedMedium.brine,
          DiscardedMedium.brine,
          DiscardedMedium.brine,
          null,
        ],
      );
    });

    test('the submerged food is never its own brine, even named in an "add" '
        'sentence before the submerge (a synthesized negative path: no '
        "corpus brine step names its food so; Perfect Roast Chicken's (0134) "
        'step with an "Add the chicken" put in)', () {
      final r = recipeOf(
        ['½ cup table salt', '1 (3½- to 4-pound) whole chicken'],
        steps: [
          'Dissolve the salt and sugar in 2 quarts cold water in a large '
              'container. Add the chicken; submerge the chicken in the '
              'brine, cover, and refrigerate for 1 hour.',
        ],
      );
      expect(mediumOf(r, 1), isNull);
    });

    test('a brine whose salt is no line of its own zeroes its sugar (Garlicky '
        'Shrimp, Tomato, and White Bean Stew, 0429); what a sentence adds TO '
        'the brine is the food (Roasted Mushrooms with Parmesan and Pine '
        'Nuts, 0688)', () {
      final stew = recipeOf(
        ['2 tablespoons sugar', 'Salt and pepper'],
        steps: [
          'Dissolve sugar and 1 tablespoon salt in 1 quart cold water in '
              'large container. Submerge shrimp in brine, cover, and '
              'refrigerate for 15 minutes. Remove shrimp from brine and pat '
              'dry with paper towels.',
        ],
      );
      expect(mediumOf(stew, 0), DiscardedMedium.brineSugar);
      final mushrooms = recipeOf(
        [
          '1½ pounds cremini mushrooms, trimmed and left whole if small, '
              'halved if medium, or quartered if large',
        ],
        steps: [
          'Adjust oven rack to lowest position and heat oven to 450 degrees. '
              'Dissolve 5 teaspoons salt in 2 quarts room-temperature water '
              'in large container. Add cremini mushrooms and shiitake '
              'mushrooms to brine, cover with plate or bowl to submerge, and '
              'let stand for 10 minutes.',
        ],
      );
      expect(mediumOf(mushrooms, 0), isNull);
    });

    test(
      'Roast Fresh Ham (0249): the crushed peppercorns and the first '
      "garlic go in the brine; the rub's garlic and ground pepper do not",
      () {
        final ham = recipeOf(
          [
            '3 cups packed brown sugar',
            '2 cups table salt',
            '2 heads garlic, cloves separated, lightly crushed and peeled',
            '½ cup black peppercorns, crushed',
            '8 medium garlic cloves, peeled',
            '½ tablespoon ground black pepper',
          ],
          steps: [
            'In a large container, dissolve the brown sugar and salt in 2 '
                'gallons cold water. Add the garlic, bay leaves, and crushed '
                'peppercorns. Submerge the ham in the brine and refrigerate '
                'for '
                '8 to 24 hours.',
          ],
        );
        expect(
          [
            for (final i in [0, 2, 3, 4, 5]) mediumOf(ham, i),
          ],
          [
            DiscardedMedium.brineSugar,
            DiscardedMedium.brine,
            DiscardedMedium.brine,
            null,
            null,
          ],
        );
      },
    );

    test('what a step names only after its submerge is the next dish (Pinchos '
        "Morunos, 1141: the marinade's lemon juice and garlic), and a "
        'submerge in no brine is none (Best Summer Tomato Gratin, 0708)', () {
      final pinchos = recipeOf(
        [
          '2 tablespoons lemon juice, plus lemon wedges for serving',
          '6 garlic cloves, minced',
        ],
        steps: [
          'Dissolve 3 tablespoons salt in 1½ quarts cold water in large '
              'container. Submerge ribs in brine and let stand at room '
              'temperature for 30 minutes. Meanwhile, whisk oil, lemon juice, '
              'garlic, ginger, 1 teaspoon oregano, paprika, coriander, salt, '
              'cumin, pepper, and cayenne in small bowl until combined.',
        ],
      );
      expect([mediumOf(pinchos, 0), mediumOf(pinchos, 1)], [null, null]);
      final gratin = recipeOf(
        ['2 teaspoons sugar'],
        steps: [
          'Return now-empty skillet to low heat and add remaining 2 '
              'tablespoons oil and garlic. Cook, stirring constantly, until '
              'garlic is golden at edges, 30 to 60 seconds. Add tomatoes, '
              'sugar, salt, and pepper and stir to combine. Increase heat to '
              'medium-high and cook, stirring occasionally, until tomatoes '
              'have started to break down and have released enough juice to '
              'be mostly submerged, 8 to 10 minutes.',
        ],
      );
      expect(mediumOf(gratin, 0), isNull);
    });

    test('a dunk that leaves the liquid on the food is no submerge brine: '
        "Grilled Cauliflower's (0656) salt held — and its sugar with it "
        'since v14 (checkpoint 8), never zeroed as brine sugar', () {
      final r = recipeOf(
        ['¼ cup salt', '2 tablespoons sugar'],
        steps: [
          'Whisk 2 cups water, salt, and sugar in medium bowl until salt and '
              'sugar dissolve. Holding wedges by core, gently dunk in '
              'salt-sugar mixture until evenly moistened (do not '
              'dry—residual water will help cauliflower steam).',
        ],
      );
      expect(
        [mediumOf(r, 0), mediumOf(r, 1)],
        [DiscardedMedium.saltBath, DiscardedMedium.saltBath],
      );
    });
  });

  group('R2: poured-away media the rules could not see are held', () {
    test('a brine the food then poaches in holds its soy sauce, sugar and '
        'garlic (Perfect Poached Chicken Breasts, 0112) — and its salt '
        'since v14 (checkpoint 8: v13 zeroed it as brine)', () {
      final r = recipeOf(
        [
          '4 (6- to 8-ounce) boneless, skinless chicken breasts, trimmed',
          '½ cup soy sauce',
          '¼ cup salt',
          '2 tablespoons sugar',
          '6 garlic cloves, smashed and peeled',
        ],
        title: 'Perfect Poached Chicken Breasts',
        steps: [
          'Cover chicken breasts with plastic wrap and pound thick ends '
              'gently with meat pounder until ¾ inch thick. Whisk 4 quarts '
              'water, soy sauce, salt, sugar, and garlic in Dutch oven until '
              'salt and sugar are dissolved. Arrange breasts, skinned side '
              'up, in steamer basket, making sure not to overlap them. '
              'Submerge steamer basket in brine and let sit at room '
              'temperature for 30 minutes.',
        ],
      );
      expect(
        [
          for (final i in [0, 1, 2, 3, 4]) mediumOf(r, i),
        ],
        [
          null,
          DiscardedMedium.cookingWater,
          DiscardedMedium.cookingWater,
          DiscardedMedium.cookingWater,
          DiscardedMedium.cookingWater,
        ],
      );
    });

    test('salt tossed with a vegetable in a colander and rinsed off is held '
        '(Sesame-Lemon Cucumber Salad, 0052), and so is one wiped off '
        '(Eggplant Parmesan, 0407); tossed in a bowl and not rinsed it stays '
        '(Bread-and-Butter Pickles, 0664)', () {
      final cucumbers = recipeOf(
        ['1 tablespoon table salt'],
        steps: [
          'Toss the cucumbers with the salt in a colander set over a large '
              'bowl. Weight the cucumbers with a gallon-sized zipper-lock bag '
              'filled with water; drain for 1 to 3 hours. Rinse and pat dry.',
        ],
      );
      expect(mediumOf(cucumbers, 0), DiscardedMedium.saltBath);
      final pickles = recipeOf(
        ['2 tablespoons canning and pickling salt'],
        steps: [
          'Toss cucumbers, onion, and bell pepper with salt in large bowl '
              'and refrigerate for 3 hours. Drain vegetables in colander (do '
              'not rinse), then pat dry with paper towels.',
        ],
      );
      expect(mediumOf(pickles, 0), isNull);
      // Salted in a colander, pressed and the excess salt wiped off:
      // Eggplant Parmesan's (0407) degorging salt is held too (the user's
      // ruling Q3, 2026-09-28; v13 counted it).
      final eggplant = recipeOf(
        ['1 tablespoon kosher salt (see note)'],
        steps: [
          'Toss half of the eggplant slices and 1½ teaspoons of the kosher '
              'salt in a large bowl until combined; transfer the salted '
              'eggplant to a large colander set over a bowl. Repeat with the '
              'remaining eggplant and kosher salt, placing the second batch '
              'on top of the first. Let stand until the eggplant releases '
              'about 2 tablespoons liquid, 30 to 45 minutes. Spread the '
              'eggplant slices on a triple thickness of paper towels; cover '
              'with another triple thickness of paper towels. Press firmly on '
              'each slice to remove as much liquid as possible, then wipe off '
              'the excess salt.',
        ],
      );
      expect(mediumOf(eggplant, 0), DiscardedMedium.saltBath);
    });

    test('a salt in no colander is no rinsed salt: Skillet-Charred Green '
        'Beans (0682) salts its panko, then rinses the beans', () {
      final r = recipeOf(
        ['¾ teaspoon kosher salt'],
        steps: [
          'Process panko in spice grinder or mortar and pestle until '
              'uniformly ground to medium-fine consistency that resembles '
              'couscous. Transfer panko to 12-inch skillet, add 1 tablespoon '
              'oil, and stir to combine. Cook over medium-low heat, stirring '
              'frequently, until light golden brown, 5 to 7 minutes. Remove '
              'skillet from heat; add salt, pepper, and pepper flakes; and '
              'stir to combine. Transfer panko mixture to bowl and set aside. '
              'Wash out skillet thoroughly and dry with paper towels.',
          'Rinse green beans but do not dry. Place in medium bowl, cover, and '
              'microwave until tender, 6 to 12 minutes, stirring every 3 '
              'minutes. Using tongs, transfer green beans to paper '
              'towel–lined plate and let drain.',
        ],
      );
      expect(mediumOf(r, 0), isNull);
    });

    test("a cheese milk's salt, acid and buttermilk are held with it; a "
        "second buttermilk line is the sauce's (Saag Paneer, 0563; "
        'Homemade Ricotta, 0380)', () {
      final saag = recipeOf(
        [
          '3 quarts whole milk',
          '3 cups buttermilk',
          '1 tablespoon salt',
          '1 cup buttermilk',
        ],
        steps: [
          'Line colander with triple layer of cheesecloth and set in sink. '
              'Bring milk to boil in Dutch oven over medium-high heat. Whisk '
              'in buttermilk and salt, turn off heat, and let stand for 1 '
              'minute. Pour milk mixture through cheesecloth and let curds '
              'drain for 15 minutes.',
        ],
      );
      // Only the step that first names the milk: the sauce's spices
      // (step 4) are eaten.
      final spiced = recipeOf(
        ['3 quarts whole milk', '1 tablespoon salt', '1 teaspoon paprika'],
        steps: [
          'Line colander with triple layer of cheesecloth and set in sink. '
              'Bring milk to boil in Dutch oven over medium-high heat. Whisk '
              'in buttermilk and salt, turn off heat, and let stand for 1 '
              'minute. Pour milk mixture through cheesecloth and let curds '
              'drain for 15 minutes.',
          'Meanwhile, melt butter in 12-inch skillet over medium-high heat. '
              'Add cumin seeds, coriander, paprika, cardamom, and cinnamon and '
              'cook until fragrant, about 30 seconds.',
        ],
      );
      expect(mediumOf(spiced, 2), isNull);
      // No cheese milk, no co-line: Albóndigas en Chipotle (1208) mashes
      // its bread in milk.
      final albondigas = recipeOf(
        [
          '2 slices hearty white sandwich bread, torn into 1-inch pieces',
          '½ cup whole milk',
        ],
        steps: [
          'Mash bread and milk to paste with fork in large bowl. Add '
              'parcooked rice, chorizo, beef, pepper, and salt and mix with '
              'your hands until thoroughly combined.',
        ],
      );
      expect(mediumOf(albondigas, 0), isNull);
      expect(
        [
          for (final i in [0, 1, 2, 3]) mediumOf(saag, i),
        ],
        [
          DiscardedMedium.cheeseMilk,
          DiscardedMedium.cheeseMilk,
          DiscardedMedium.cheeseMilk,
          null,
        ],
      );
      final ricotta = recipeOf(
        [
          '⅓ cup lemon juice (2 lemons)',
          '¼ cup distilled white vinegar, plus extra as needed',
          '1 gallon pasteurized (not ultrapasteurized or UHT) whole milk',
          '2 teaspoons salt',
        ],
        steps: [
          'Line colander with butter muslin or triple layer of cheesecloth '
              'and place in sink. Combine lemon juice and vinegar in liquid '
              'measuring cup; set aside. Heat milk and salt in Dutch oven '
              'over medium-high heat, stirring frequently with rubber spatula '
              'to prevent scorching, until milk registers 185 degrees.',
          'Remove pot from heat and slowly stir in lemon juice mixture until '
              'fully incorporated and mixture curdles, about 15 seconds. Let '
              'sit undisturbed until mixture fully separates into solid '
              'curds and translucent whey, 5 to 10 minutes.',
        ],
      );
      expect(
        [
          for (final i in [0, 1, 2, 3]) mediumOf(ricotta, i),
        ],
        [
          DiscardedMedium.cheeseMilk,
          DiscardedMedium.cheeseMilk,
          DiscardedMedium.cheeseMilk,
          DiscardedMedium.cheeseMilk,
        ],
      );
    });

    test('a pot emptied with a skimmer: Biang Biang Mian (0376) pairs its two '
        "bare salts in order — the dough's ¾ teaspoon eaten, the pot's "
        "tablespoon held; Thick-Cut Sweet Potato Fries' (0318) baking soda "
        'held', () {
      final biang = recipeOf(
        ['¾ teaspoon salt', '1 tablespoon table salt'],
        steps: [
          'Whisk flour and salt together in bowl of stand mixer. Add water '
              'and oil.',
          'Meanwhile, bring water and salt to boil in large pot; reduce heat '
              'to low and cover to keep hot.',
          'Return water to boil over high heat. Add half of noodles to water '
              'and cook, stirring occasionally, until noodles float and turn '
              'chewy-tender, 45 to 60 seconds. Using wire skimmer, transfer '
              'noodles to bowl with chili vinaigrette; toss to combine.',
        ],
      );
      expect(
        [mediumOf(biang, 0), mediumOf(biang, 1)],
        [null, DiscardedMedium.cookingWater],
      );
      final fries = recipeOf(
        ['Kosher salt', '1 teaspoon baking soda'],
        steps: [
          'Bring 2 quarts water, ¼ cup salt, and baking soda to boil in Dutch '
              'oven. Add potatoes and return to boil. Reduce heat to simmer '
              'and cook until exteriors turn slightly mushy (centers will '
              'remain firm), 3 to 5 minutes. Whisk cornstarch slurry to '
              'recombine. Using wire skimmer or slotted spoon, transfer '
              'potatoes to bowl with slurry.',
        ],
      );
      expect(mediumOf(fries, 1), DiscardedMedium.cookingWater);
    });

    test('bare salts pair with bare mentions only when they are as many: a '
        'third bare "salt" leaves Biang Biang Mian\'s pot unpaired (its '
        'steps with a sentence put in: a synthesized negative path)', () {
      final r = recipeOf(
        ['¾ teaspoon salt', '1 tablespoon table salt'],
        steps: [
          'Whisk flour and salt together in bowl of stand mixer.',
          'Meanwhile, bring water and salt to boil in large pot; reduce heat '
              'to low and cover to keep hot.',
          'Add half of noodles to water and cook until noodles float. Using '
              'wire skimmer, transfer noodles to bowl. Sprinkle with salt.',
        ],
      );
      expect(mediumOf(r, 1), isNull);
    });

    test("a next step's slotted spoon lifting food from no water drains "
        'nothing: Vegetable Bibimbap (0512) cooks its rice in its salted '
        'water', () {
      final r = recipeOf(
        ['1½ teaspoons salt', '¾ teaspoon salt'],
        steps: [
          'Whisk vinegar, sugar, and salt together in medium bowl. Add '
              'cucumber and bean sprouts and toss to combine. Gently press on '
              'vegetables to submerge. Cover and refrigerate for at least 30 '
              'minutes or up to 24 hours.',
          'Bring rice, water, and salt to boil in medium saucepan over high '
              'heat. Cover, reduce heat to low, and cook for 7 minutes. Remove '
              'rice from heat and let sit, covered, until tender, about 15 '
              'minutes.',
          'Heat 1 teaspoon oil in Dutch oven over high heat until '
              'shimmering. Add carrots and stir until coated. Add ⅓ cup '
              'scallion mixture and cook, stirring frequently, until carrots '
              'are slightly softened and moisture has evaporated, 1 to 2 '
              'minutes. Using slotted spoon, transfer carrots to small bowl.',
        ],
      );
      expect(mediumOf(r, 1), isNull);
    });

    // No corpus line has either shape: synthesized (stated exceptions).
    test("a written amount another salt line starts with is that line's, "
        'and one larger than the line is no share of it', () {
      const step =
          'Bring 2 quarts water and 1 teaspoon salt to a boil in a large '
          'saucepan. Add the broccoli and cook until crisp-tender, about 3 '
          'minutes. Drain the broccoli.';
      final two = recipeOf(
        ['2 teaspoons table salt, divided', '1 teaspoon salt'],
        steps: [step],
      );
      expect(
        [mediumOf(two, 0), mediumOf(two, 1)],
        [null, DiscardedMedium.cookingWater],
      );
      final small = recipeOf(
        ['½ teaspoon table salt, divided'],
        steps: [step],
      );
      expect(mediumOf(small, 0), isNull);
    });

    test('the WRITTEN pot share of a divided salt is held, the rest its '
        'grams: Stovetop Macaroni and Cheese (0301) ½ of 2 teaspoons, '
        'Cincinnati Chili (0303) 1 of 2, Broccoli Salad (1073) ¾ of '
        '1¼', () async {
      final salt = (await provider.food(173468))!;
      Future<void> check(Recipe r, int i, double grams) async {
        expect(mediumOf(r, i), DiscardedMedium.cookingWater);
        final line = nutritionLines(r)[i];
        final out = engineOutcome(
          r,
          line,
          salt,
          lineGrams(tempDb(), line, salt),
          picked: true,
        );
        expect(out.grams, closeTo(grams, 0.01), reason: line.raw);
        expect((out.source, out.hold), ('discarded', 'discarded_medium'));
      }

      await check(
        recipeOf(
          ['Table salt', '2 teaspoons table salt'],
          steps: [
            'Mix the eggs, 1 cup of the evaporated milk, ½ teaspoon of the '
                'salt, the pepper, mustard mixture, and hot sauce in a small '
                'bowl; set aside.',
            'Meanwhile, bring 2 quarts water to a boil in a large '
                'heavy-bottomed saucepan or Dutch oven. Add the remaining 1½ '
                'teaspoons salt and the macaroni; cook until almost tender but '
                'still a little firm to the bite. Drain and return to the pan '
                'over low heat. Add the butter; toss to melt.',
          ],
        ),
        1,
        3.01,
      );
      await check(
        recipeOf(
          ['2 teaspoons table salt, plus more to taste'],
          steps: [
            'Bring 2 quarts water and 1 teaspoon of the salt to a boil in a '
                'large saucepan. Add the ground chuck, stirring vigorously to '
                'separate the meat into individual strands. As soon as the '
                'foam from the meat rises to the top (this takes about 30 '
                'seconds) and before the water returns to a boil, drain the '
                'meat into a strainer and set it aside.',
          ],
        ),
        0,
        6.01,
      );
      await check(
        recipeOf(
          ['1¼ teaspoons table salt, divided'],
          steps: [
            'Bring water and ½ teaspoon salt to boil in large saucepan over '
                'high heat. Add broccoli stalks, then place florets on top of '
                'stalks so that they sit just above water. Cover and cook '
                'until broccoli is bright green and crisp-tender, about 3 '
                'minutes. Meanwhile, fill large bowl halfway with ice and '
                'water. Drain broccoli well, transfer to ice water, and let '
                'sit until just cool, about 2 minutes.',
          ],
        ),
        0,
        4.51,
      );
    });

    test("a next step's slotted spoon with no water in its sentences drains "
        "nothing: Beef Burgundy's (0457) ½ teaspoon stays counted", () {
      final r = recipeOf(
        ['Table salt and ground black pepper', '½ teaspoon table salt'],
        steps: [
          'Melt the butter in the skillet over medium heat. Whisk in the '
              'flour and cook, stirring constantly, until light brown, about '
              '5 minutes. Gradually whisk in the chicken broth and the '
              'remaining 1½ cups water. Increase the heat to medium-high and '
              'bring to a simmer, stirring frequently, until thickened; add '
              'the mixture to the pot. Add 3 cups of the wine and the tomato '
              'paste to the pot and season with salt and pepper to taste; '
              'stir to combine. Set the pot over high heat and bring to a '
              'boil; cover and place in the oven.',
          'Remove the pot from the oven and transfer the vegetable and herb '
              'pouch to a mesh strainer; set the strainer over the pot. With '
              'a slotted spoon, transfer the beef to a medium bowl; set '
              'aside.',
        ],
      );
      expect(mediumOf(r, 1), isNull);
    });
  });

  group('R4: fresh herbs FDC has no fresh record of count on the dried '
      'spice (a flagged approximation)', () {
    test(
      "freshHerbOnSpiceRecord names the five herbs' spice records only",
      () {
        for (final d in [
          'Spices, oregano, dried',
          'Spices, sage, ground',
          'Spices, tarragon, dried',
          'Spices, marjoram, dried',
          'Spices, chervil, dried',
        ]) {
          expect(freshHerbOnSpiceRecord(d), isTrue, reason: d);
        }
        for (final d in ['Spices, thyme, dried', 'Spices, basil, dried']) {
          expect(freshHerbOnSpiceRecord(d), isFalse, reason: d);
        }
      },
    );

    test('the count noun leaves the query for them: tarragon, marjoram and '
        'chervil leaves cross the gate ("½ teaspoon minced fresh tarragon '
        'leaves", Chicken Kiev; "1 tablespoon minced fresh marjoram leaves", '
        'Old-Fashioned Stuffed Turkey; "1 tablespoon minced fresh chervil '
        'leaves", French Potato Salad)', () async {
      for (final (query, description) in [
        ('tarragon leaves', 'Spices, tarragon, dried'),
        ('marjoram leaves', 'Spices, marjoram, dried'),
        ('chervil leaves', 'Spices, chervil, dried'),
      ]) {
        final top = (await rank(query)).first;
        expect(top.candidate.description, description);
        expect(belowConfidenceGate(top.confidence), isFalse, reason: query);
      }
    });

    test(
      'an engine pick of one is never held dried_for_fresh: "1 tablespoon '
      'minced fresh oregano or 1 teaspoon dried" (Albóndigas en Chipotle)',
      () async {
        final r = recipeOf([
          '1 tablespoon minced fresh oregano or 1 teaspoon dried',
        ]);
        final out = engineOutcome(
          r,
          nutritionLines(r).single,
          (await provider.food(171328))!,
          const GramResolution(grams: 3, source: GramSource.portion),
          picked: true,
          confidence: 0.81,
        );
        expect(out.hold, isNull);
      },
    );
  });

  group('v13 refix', () {
    /// What an engine write stores for line [i] of [r] on [fdcId], sized as
    /// the engine sizes it, and the `gram_basis` that row reads.
    Future<(double?, String?, String?, String?)> storedOf(
      Recipe r,
      int i,
      int fdcId,
    ) async {
      final db = tempDb();
      final food = (await provider.food(fdcId))!;
      final line = nutritionLines(r)[i];
      final out = engineOutcome(
        r,
        line,
        food,
        lineGrams(db, line, food),
        picked: true,
      );
      final row = IngredientMatchRow(
        recipeId: 'r',
        position: i,
        raw: line.raw,
        fdcId: fdcId,
        description: food.description,
        dataType: food.dataType,
        confidence: 0.9,
        grams: out.grams,
        gramSource: out.source,
        status: 'auto',
        hold: out.hold,
      );
      return (out.grams, out.source, out.hold, gramBasisFor(db, line, row));
    }

    test("the basis of a divided salt's pot share names the part kept: "
        'Stovetop Macaroni and Cheese (0301)', () async {
      final r = recipeOf(
        ['Table salt', '2 teaspoons table salt'],
        steps: [
          'Meanwhile, bring 2 quarts water to a boil in a large '
              'heavy-bottomed saucepan or Dutch oven. Add the remaining 1½ '
              'teaspoons salt and the macaroni; cook until almost tender but '
              'still a little firm to the bite. Drain and return to the pan '
              'over low heat. Add the butter; toss to melt.',
        ],
      );
      final (grams, source, hold, basis) = await storedOf(r, 1, 173468);
      expect(grams, closeTo(3.01, 0.01));
      expect((source, hold), ('discarded', 'discarded_medium'));
      expect(
        basis,
        'discarded in cooking — only the part the recipe keeps counted',
      );
    });

    test("New York Bagels' (0810) pot sugar leaves with the water the "
        'skimmer lifts the bagels from: held with its soda (R2), storing no '
        'grams — none of it is eaten (v14, B6)', () async {
      final r = recipeOf(
        [
          '2 teaspoons salt',
          '¼ cup (1¾ ounces) sugar',
          '1 tablespoon baking soda',
        ],
        steps: [
          'Add salt to dough and process, stopping processor and '
              'redistributing dough as needed, until dough forms shaggy mass '
              'that clears sides of workbowl (dough may not form one single '
              'mass), 45 to 90 seconds.',
          'Bring 4 quarts water, sugar, and baking soda to boil in large '
              'Dutch oven. Set wire rack in rimmed baking sheet and spray '
              'rack with vegetable oil spray.',
          'Transfer 4 bagels to boiling water and cook for 20 seconds. Using '
              'wire skimmer or slotted spoon, flip bagels over and cook 20 '
              'seconds longer. Using wire skimmer or slotted spoon, transfer '
              'bagels to prepared wire rack, with cornmeal side facing down. '
              'Repeat with remaining 4 bagels.',
        ],
      );
      expect(
        [
          for (final i in [0, 1, 2]) mediumOf(r, i),
        ],
        [null, DiscardedMedium.cookingWater, DiscardedMedium.cookingWater],
      );
      final (grams, source, hold, _) = await storedOf(r, 1, 746784);
      expect((grams, source, hold), (null, null, 'discarded_medium'));
    });

    test('a drain after a pot sugar keeps it: Austrian-Style Potato Salad '
        '(0056) reserves its cooking liquid', () {
      final r = recipeOf(
        ['1 tablespoon sugar'],
        steps: [
          'Bring 1 cup water, the potatoes, broth, 1 tablespoon of the '
              'vinegar, the sugar, and 1 teaspoon salt to a boil in a 12-inch '
              'skillet over high heat. Reduce the heat to medium-low, cover, '
              'and cook until the potatoes are tender (a paring knife can be '
              'slipped in and out of the potatoes with little resistance), 15 '
              'to 17 minutes. Remove the cover, increase the heat to high, '
              'and cook until the liquid has reduced, about 2 minutes.',
          'Drain the potatoes in a colander set over a large bowl, reserving '
              'the cooking liquid. Set the potatoes aside. Pour off all but ½ '
              'cup cooking liquid (if ½ cup liquid does not remain, add water '
              'to make this amount).',
        ],
      );
      expect(mediumOf(r, 0), isNull);
    });

    // Oven-Roasted Pork Chops (0202).
    final chops = recipeOf(
      [
        '¾ cup (5¼ ounces) dark brown sugar',
        '¼ cup table salt',
        '10 medium garlic cloves, crushed',
        '4 bay leaves, crumbled',
        '8 whole cloves',
        '3 tablespoons whole black peppercorns, crushed',
        '4 (12-ounce) bone-in rib loin pork chops, about 1½ inches thick, '
            'trimmed of excess fat',
      ],
      steps: [
        'Dissolve the sugar and salt in 6 cups cold water in a large bowl or '
            'container. Add the garlic, bay leaves, cloves, and peppercorns. '
            'Submerge the chops in the brine, cover with plastic wrap, and '
            'refrigerate for 1 hour. Remove the chops from the brine, rinse, '
            'and pat dry with paper towels.',
      ],
    );

    test('"8 whole cloves", with no head noun, are brine by their last word '
        '(Oven-Roasted Pork Chops, 0202): zero, like the garlic', () async {
      expect(headNounOf(normalizeItem('whole cloves')), isNull);
      expect(
        [
          for (final i in [2, 3, 4, 5, 6]) mediumOf(chops, i),
        ],
        [...List.filled(4, DiscardedMedium.brine), null],
      );
      final (grams, source, hold, basis) = await storedOf(chops, 4, 171321);
      expect((grams, source, hold), (0, 'discarded', null));
      expect(basis, 'discarded in cooking — counted as 0 g');
    });

    test('"garlic cloves" in a brine never name the spice (a synthesized '
        "negative path: 0202's step with the garlic written as cloves — no "
        'corpus brine names both)', () {
      final r = recipeOf(
        ['¼ cup table salt', '10 medium garlic cloves, crushed', '8 cloves'],
        steps: [
          'Dissolve the salt in 6 cups cold water in a large bowl or '
              'container. Add the garlic cloves and bay leaves. Submerge the '
              'chops in the brine, cover with plastic wrap, and refrigerate '
              'for 1 hour.',
        ],
      );
      expect(mediumOf(r, 1), DiscardedMedium.brine);
      expect(mediumOf(r, 2), isNull);
    });

    // Home-Corned Beef with Vegetables (0091).
    final corned = recipeOf(
      [
        '1 (4½- to 5-pound) beef brisket, flat cut',
        '¾ cup salt',
        '½ cup packed brown sugar',
        '2 teaspoons pink curing salt #1',
        '6 garlic cloves, peeled',
        '6 bay leaves',
        '5 allspice berries',
        '2 tablespoons peppercorns',
        '1 tablespoon coriander seeds',
      ],
      steps: [
        'Trim fat on surface of brisket to ⅛ inch. Dissolve salt, sugar, and '
            'curing salt in 4 quarts water in large container. Add brisket, '
            '3 garlic cloves, 4 bay leaves, allspice berries, 1 tablespoon '
            'peppercorns, and coriander seeds to brine. Weigh brisket down '
            'with plate, cover, and refrigerate for 6 days.',
        'Adjust oven rack to middle position and heat oven to 275 degrees. '
            'Remove brisket from brine, rinse, and pat dry with paper towels. '
            'Cut 8-inch square triple thickness of cheesecloth. Place '
            'remaining 3 garlic cloves, remaining 2 bay leaves, and remaining '
            '1 tablespoon peppercorns in center of cheesecloth and tie into '
            'bundle with kitchen twine. Place brisket, spice bundle, and 2 '
            'quarts water in Dutch oven.',
      ],
    );

    test(
      'a brisket weighed down in its brine is submerged: the aromatics '
      'added to the brine before are zero — and the rest of each goes in a '
      'cheesecloth bundle, lifted out too (v14, Run 045: v13 counted the '
      'rest), so the whole lines are zero (Home-Corned Beef with '
      'Vegetables, 0091)',
      () async {
        expect(
          [
            for (final i in [0, 4, 5, 6, 7, 8]) mediumOf(corned, i),
          ],
          [null, ...List.filled(5, DiscardedMedium.brine)],
        );
        final kept = [
          for (final (i, id) in [
            (4, 1104647),
            (5, 170917),
            (6, 171315),
            (7, 170931),
            (8, 170922),
          ])
            await storedOf(corned, i, id),
        ];
        // 3 of 6 cloves, 4 of 6 leaves, 1 of 2 tablespoons in the brine;
        // the rest tied into cheesecloth.
        expect([for (final k in kept) k.$1], [0, 0, 0, 0, 0]);
        expect({for (final k in kept) (k.$2, k.$3)}, {('discarded', null)});
        expect(kept.first.$4, 'discarded in cooking — counted as 0 g');
      },
    );

    test(
      'a written brine share at or over the line zeroes the whole line, '
      "never below it (a synthesized negative path: 0091's step with 8 "
      'garlic cloves written — no corpus brine over-writes a line)',
      () async {
        final r = recipeOf(
          ['¾ cup salt', '6 garlic cloves, peeled'],
          steps: [
            'Dissolve salt in 4 quarts water in large container. Add brisket '
                'and 8 garlic cloves to brine. Weigh brisket down with plate, '
                'cover, and refrigerate for 6 days.',
          ],
        );
        expect(mediumOf(r, 1), DiscardedMedium.brine);
        final (grams, source, _, _) = await storedOf(r, 1, 1104647);
        expect((grams, source), (0, 'discarded'));
      },
    );

    test('"⅔ cup crushed saltines" (Glazed All-Beef Meatloaf, 0305) is 16 '
        "crackers, the corpus's own count (0306: \"⅔ cup crushed saltines "
        '(about 16)"), on the record\'s 3 g cracker', () async {
      final line = lineOf('⅔ cup crushed saltines');
      final saltines = (await provider.food(2708167))!;
      final grams = lineGrams(tempDb(), line, saltines);
      expect(grams?.grams, closeTo(48, 0.01));
      expect(grams?.basis, '2/3 cup ≈ 16 crackers · USDA cracker portion');
    });

    test('the cracker count is for crushed SALTINES only: "4 Carr\u2019s Whole '
        'Wheat Crackers, crushed fine (about \u00bc cup)" (Berry Fool, 0965, '
        'pos 7) stays on its record\'s "cup, crushed" portion', () async {
      final line = lineOf(
        '4 Carr\u2019s Whole Wheat Crackers, crushed fine (about \u00bc cup)',
      );
      final crackers = (await provider.food(172749))!;
      final grams = lineGrams(tempDb(), line, crackers);
      expect(grams?.grams, closeTo(23.5, 0.01));
      expect(grams?.basis, '1/4 cup · USDA portion');
    });

    test('"18 medium-large shrimp (31 to 40 per pound)" (Vietnamese Summer '
        'Rolls, 0510) is sized by its own count per pound', () async {
      final line = lineOf(
        '18 medium-large shrimp (31 to 40 per pound), peeled, deveined, and '
        'tails removed',
      );
      final grams = lineGrams(tempDb(), line, await provider.food(175179));
      expect(grams?.grams, closeTo(18 * 453.592 / 35.5, 0.01));
      expect(grams?.basis, '18 × 13 g each (31 to 40 per pound)');
    });
  });
}
