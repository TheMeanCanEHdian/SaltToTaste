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

/// A provider that fails for one food, as FDC does out of budget.
class _FailsFood implements NutritionProvider {
  _FailsFood(this.inner, this.failing);

  final FixtureProvider inner;
  final int failing;

  @override
  Future<List<FdcCandidate>> search(String query) => inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) async => fdcId == failing
      ? throw const NutritionProviderException('budget used up')
      : inner.food(fdcId);
}

/// Matcher v9 (checkpoint 5 review, both fleets): every mechanism pinned
/// WITHOUT the corpus — real corpus lines as strings (recipe named on each),
/// FDC answers from the recorded fixtures (sweep snapshot 7's cache).
void main() {
  final provider = FixtureProvider();
  Future<List<RankedCandidate>> rank(String query) async =>
      rankCandidates(query, await provider.search(query));
  Future<FdcFood> food(int id) async => (await provider.food(id))!;

  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  GramResolution? gramsOf(String raw, FdcFood on) {
    final line = lineOf(raw);
    return resolveGrams(
      amounts: line.amounts,
      food: on,
      normalizedItem: normalizeItem(lineItemOf(line)),
      raw: raw,
    );
  }

  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v9');
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
  }) {
    final recipe = Recipe(
      id: id,
      title: id,
      slug: id,
      source: const RecipeSource(name: 'Test', type: 'book'),
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

  Future<Map<dynamic, dynamic>> matchOf(
    SaltDatabase db,
    Recipe recipe,
    int position,
  ) async {
    final items = (await matchesBody(db, provider, recipe))['items']! as List;
    return items[position] as Map;
  }

  // Italian-Style Grilled Chicken (0423): the citrus rule counts it.
  const lemon = '1 teaspoon grated lemon zest plus 2 tablespoons juice';
  // Skillet-Roasted Chicken in Lemon Sauce (0142): 4 teaspoons of zest,
  // over the rule's tablespoon — held second_food.
  const heldZest = '4 teaspoons grated lemon zest plus ¼ cup juice (2 lemons)';
  // Avgolemono (0005): the egg rule counts it on the whole egg.
  const eggsYolks = '2 large eggs plus 2 large yolks';
  // Crisp-Skin High-Roast Butterflied Turkey (0165): its brine.
  const turkeyBrine =
      'Dissolve the salt and sugar in 2 gallons cold water in a large '
      'container. Submerge the turkey in the brine and refrigerate or store '
      'in a very cool spot (40 degrees or less) for 4 to 6 hours.';

  group('M1/M12: the offer and the apply reach the same rows', () {
    test("a confirm on 0142's held zest line offers 0 and applies 0: the "
        "citrus rule's rows are not the key's to move", () async {
      final db = tempDb();
      final a = recipeOf(db, 'ra', [heldZest]);
      final ruled = [
        recipeOf(db, 'rb', [lemon]),
        recipeOf(db, 'rc', [lemon]),
      ];
      for (final r in [a, ...ruled]) {
        await matchAndCompute(db, provider, r);
      }
      expect(db.ingredientMatchesFor('ra').single.hold, 'second_food');
      for (final r in ruled) {
        final row = db.ingredientMatchesFor(r.id).single;
        expect((row.fdcId, row.hold), (167747, null));
      }
      await applyMatchOverride(db, provider, a, 0, {'confirmed': true});
      final item = await matchOf(db, a, 0);
      expect((item['others'], item['others_lines']), (0, 0));
      final applied = await applyMatchOverride(db, provider, a, 0, {
        'confirmed': true,
        'apply_to_all': true,
      });
      expect((applied!.recipes, applied.lines), (0, 0));
      for (final r in ruled) {
        final row = db.ingredientMatchesFor(r.id).single;
        expect((row.fdcId, row.hold, row.confidence < 1), (167747, null, true));
      }
    });

    test('a pick of "Eggs, egg yolk" (748236) on 0005 pos 9 offers 0 and '
        'applies 0: the egg rule rows stay on the whole egg', () async {
      final db = tempDb();
      final a = recipeOf(db, 'ra', [eggsYolks]);
      // Bran Muffins (0762) and Pumpkin Pie (0987).
      final others = [
        recipeOf(db, 'rb', ['1 large whole egg plus 1 large egg yolk']),
        recipeOf(db, 'rc', ['3 large whole eggs plus 2 large egg yolks']),
      ];
      for (final r in [a, ...others]) {
        await matchAndCompute(db, provider, r);
      }
      await applyMatchOverride(db, provider, a, 0, {'fdc_id': 748236});
      final item = await matchOf(db, a, 0);
      expect((item['others'], item['others_lines']), (0, 0));
      final applied = await applyMatchOverride(db, provider, a, 0, {
        'fdc_id': 748236,
        'apply_to_all': true,
      });
      expect((applied!.recipes, applied.lines), (0, 0));
      for (final r in others) {
        final row = db.ingredientMatchesFor(r.id).single;
        expect((row.fdcId, row.hold), (748967, null));
      }
    });

    test("M12: 0218's unmatched cornichon-plus-brine line in two recipes "
        '(real line, duplicated): a pick on one neither offers nor writes '
        'the other', () async {
      final db = tempDb();
      // Beef Tenderloin with Smoky Potatoes and Persillade Relish (0218):
      // FDC's recorded answer for 'cornichons' is empty.
      const cornichon = '6 tablespoons minced cornichons plus 1 teaspoon brine';
      final a = recipeOf(db, 'ra', [cornichon]);
      final b = recipeOf(db, 'rb', [cornichon]);
      for (final r in [a, b]) {
        await matchAndCompute(db, provider, r);
      }
      expect(db.ingredientMatchesFor('rb').single.status, 'unmatched');
      final applied = await applyMatchOverride(db, provider, a, 0, {
        'fdc_id': 2710078, // Pickles, dill
        'apply_to_all': true,
      });
      expect((applied!.recipes, applied.lines), (0, 0));
      expect((await matchOf(db, a, 0))['others'], 0);
      final row = db.ingredientMatchesFor('rb').single;
      expect((row.status, row.fdcId, row.hold), ('unmatched', null, null));
    });

    test('M12: an unmatched brine sugar (no-hit state seeded: negative path) '
        'is neither offered nor written by a Sugar confirm', () async {
      final db = tempDb();
      final meatballs = recipeOf(db, 'meatballs', ['Sugar']);
      final turkey = recipeOf(
        db,
        'turkey',
        ['1 cup table salt', '1 cup sugar'],
        steps: [turkeyBrine],
      );
      for (final r in [meatballs, turkey]) {
        await matchAndCompute(db, provider, r);
      }
      final brine = db.ingredientMatchesFor('turkey')[1];
      db.upsertIngredientMatch(
        IngredientMatchRow(
          recipeId: 'turkey',
          position: 1,
          raw: brine.raw,
          itemKey: brine.itemKey,
          fdcId: null,
          description: 'No FoodData Central match',
          dataType: null,
          confidence: 0,
          grams: null,
          gramSource: null,
          status: 'unmatched',
        ),
      );
      expect((await matchOf(db, meatballs, 0))['others'], 0);
      final applied = await applyMatchOverride(db, provider, meatballs, 0, {
        'confirmed': true,
        'apply_to_all': true,
      });
      expect(applied!.lines, 0);
      expect(db.ingredientMatchesFor('turkey')[1].status, 'unmatched');
    });
  });

  group('the reach leaves out what a confirm cannot move', () {
    test("Chinese Pork Dumplings' (0506) amount-less 'Chili oil' is counted "
        "at 0 g below the gate: a confirm of Pork and Cabbage Dumplings' "
        "(also 0506) teaspoon offers and applies only Hot and Sour Soup's "
        '(0518) two teaspoons', () async {
      final db = tempDb();
      final teaspoon = recipeOf(db, 'cabbage', [
        '1 teaspoon chili oil (optional)',
      ]);
      final amountless = recipeOf(db, 'dumplings', ['Chili oil']);
      final soup = recipeOf(db, 'soup', ['2 teaspoons chili oil']);
      for (final r in [teaspoon, amountless, soup]) {
        await matchAndCompute(db, provider, r);
      }
      final zero = db.ingredientMatchesFor('dumplings').single;
      expect(zero.confidence, lessThan(lowConfidence));
      expect(bucketOf(zero), MatchBucket.counted);
      await applyMatchOverride(db, provider, teaspoon, 0, {'confirmed': true});
      final item = await matchOf(db, teaspoon, 0);
      expect((item['others'], item['others_lines']), (1, 1));
      final applied = await applyMatchOverride(db, provider, teaspoon, 0, {
        'confirmed': true,
        'apply_to_all': true,
      });
      expect((applied!.recipes, applied.lines), (1, 1));
      expect(
        db.ingredientMatchesFor('dumplings').single.confidence,
        zero.confidence,
      );
    });
  });

  group('M2: a line-held row is a group of one', () {
    test('two brine sugars and two held zest lines: four groups of one, '
        'never badged decided', () async {
      final db = tempDb();
      final turkeys = [
        for (final id in ['t1', 't2'])
          recipeOf(
            db,
            id,
            ['1 cup table salt', '1 cup sugar'],
            steps: [turkeyBrine],
          ),
      ];
      final zests = [
        recipeOf(db, 'z1', [heldZest]),
        recipeOf(db, 'z2', [heldZest]),
      ];
      final meatballs = recipeOf(db, 'meatballs', ['Sugar']);
      for (final r in [...turkeys, ...zests, meatballs]) {
        await matchAndCompute(db, provider, r);
      }
      // A decision on 'sugar' exists: it clears none of the brine sugars.
      await applyMatchOverride(db, provider, meatballs, 0, {'confirmed': true});
      expect(db.decisionFor('sugar'), isNotNull);
      final groups = db.nutritionReviewGroups(limit: 100, offset: 0);
      final held = [
        for (final g in groups)
          if (g.match.hold == 'discarded_medium' ||
              g.match.hold == 'second_food')
            (g.itemKey, g.lines, g.recipes, g.decided),
      ];
      expect(held, hasLength(4));
      expect(held.every((g) => g.$2 == 1 && g.$3 == 1 && !g.$4), isTrue);
      expect(
        {for (final g in held) g.$1},
        {'sugar', 'lemon zest plus juice'},
        reason: 'each still reports its own key',
      );
    });
  });

  group('M3: an un-skip re-derives the row as a compute would', () {
    test("0142: a person's pick on the held zest line, skipped then "
        'un-skipped, is not re-held second_food', () async {
      final db = tempDb();
      final r = recipeOf(db, 'r1', [heldZest]);
      await matchAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 0, {'fdc_id': 167749});
      await applyMatchOverride(db, provider, r, 0, {'skipped': true});
      await applyMatchOverride(db, provider, r, 0, {'skipped': false});
      final row = db.ingredientMatchesFor('r1').single;
      expect((row.status, row.fdcId, row.hold), ('auto', 167749, null));
      expect(bucketOf(row), MatchBucket.counted);
    });

    test(
      '0423: an engine row a v7 compute left held on "Lemon peel, raw", '
      'skipped, is un-skipped onto the rule record with the rule grams',
      () async {
        final db = tempDb();
        final r = recipeOf(db, 'r1', [lemon]);
        final peel = await food(167749);
        db.upsertIngredientMatch(
          IngredientMatchRow(
            recipeId: 'r1',
            position: 0,
            raw: lemon,
            itemKey: lineKeyOf(lineOf(lemon)),
            fdcId: peel.fdcId,
            description: peel.description,
            dataType: peel.dataType,
            confidence: 0.8,
            grams: null,
            gramSource: null,
            status: 'skipped',
            hold: 'second_food',
          ),
        );
        await applyMatchOverride(db, provider, r, 0, {'skipped': false});
        final row = db.ingredientMatchesFor('r1').single;
        expect((row.status, row.fdcId, row.hold), ('auto', 167747, null));
        expect(row.grams, closeTo(2 * 14.7868 * 1.03, 0.01));
        // What a fresh compute writes.
        final fresh = tempDb();
        final again = recipeOf(fresh, 'r1', [lemon]);
        await matchAndCompute(fresh, provider, again);
        final computed = fresh.ingredientMatchesFor('r1').single;
        expect(
          (row.grams, row.gramSource, row.confidence),
          (computed.grams, computed.gramSource, computed.confidence),
        );
      },
    );
  });

  group('M4/M13: second-food keys', () {
    // Key Lime Pie (0989), as the corpus parses it: the fruit only in the
    // prep.
    final keyLime = IngredientLine(
      raw: '4 teaspoons grated zest plus ½ cup juice from 3 or 4 limes',
      item: 'grated zest plus 1/2 cup juice',
      amounts: parseIngredientLine(
        '4 teaspoons grated zest plus ½ cup juice from 3 or 4 limes',
      ).amounts,
    );

    test('0989 keys "lime zest plus juice" — parsed from its raw text too '
        '("3 or 4 limes" moves to the front) — and only the 1-tablespoon '
        'cap holds it', () {
      expect(lineKeyOf(keyLime), 'lime zest plus juice');
      final parsed = lineOf(keyLime.raw);
      expect(parsed.item, contains('from 3 or 4 limes'));
      expect(lineKeyOf(parsed), 'lime zest plus juice');
      for (final line in [keyLime, parsed]) {
        expect(secondFoodRuleOf(line), isNull);
        expect(volumeMlOf(line.amounts), greaterThan(14.7868));
      }
    });

    test('egg parts key food first: 0878, 0841 and 0994', () {
      expect(
        [
          // Coconut Layer Cake (0878), part first.
          '5 large egg whites plus 1 large egg, at room temperature',
          // Almond Biscotti (0841), food first.
          '2 large eggs, plus 1 large white beaten with pinch salt',
          // Lemon Tart (0994), yolks first, "whole" on the second part.
          '7 large egg yolks plus 2 large whole eggs',
          // Avgolemono (0005).
          eggsYolks,
          // Chilled Lemon Soufflé (0937): whites before yolks.
          '5 large egg whites plus 2 large egg yolks, at room temperature',
        ].map((raw) => lineKeyOf(lineOf(raw))),
        [
          'egg plus white',
          'egg plus white',
          'egg plus yolk',
          'egg plus yolk',
          'egg yolk plus white',
        ],
      );
    });
  });

  group('M5/M9: coverage credits and count nouns on recorded answers', () {
    test(
      "1005's McIntosh apples: Fuji and Gala name their own variety, so "
      "'mcintosh' leaves no denominator and neither crosses the gate",
      () async {
        final ranked = await rank('mcintosh apples');
        expect(ranked.first.candidate.fdcId, 1750340);
        expect(ranked.first.confidence, lessThan(lowConfidence));
      },
    );

    test("0977's firm McIntosh apples: tofu carries no apple, takes no "
        'credit, and stays under "Apple, raw"', () async {
      final ranked = await rank('firm mcintosh apples');
      expect(ranked.first.candidate.fdcId, 2709215);
      final tofu = ranked.firstWhere((c) => c.candidate.fdcId == 172475);
      expect(tofu.confidence, lessThan(ranked.first.confidence));
    });

    test(
      'Panang Beef Curry (0551) and Crispy Thai Eggplant Salad (0053): a '
      "Thai red chile is the hot chile record, not FNDDS's bell pepper",
      () async {
        for (final query in [
          'thai red chile',
          'red thai chile',
          'green or red thai chiles',
        ]) {
          expect(
            (await rank(query)).first.candidate.fdcId,
            168570,
            reason: query,
          );
        }
      },
    );

    test('Garlic-Studded Roast Pork Loin (0241): "¼ teaspoon ground cloves or '
        'allspice" counts the cloves', () async {
      final db = tempDb();
      for (final query in ['ground cloves or allspice', 'ground cloves']) {
        db.fdcSearchCachePut(
          query,
          jsonEncode([
            for (final c in await provider.search(query)) c.toJson(),
          ]),
        );
      }
      final line = lineOf('¼ teaspoon ground cloves or allspice');
      final search = lineSearchFor(
        db,
        normalizeItem(lineItemOf(line)),
        lineKeyOf(line),
      );
      expect(search.answer, 'ground cloves');
      expect(
        (await rank(search.query)).first.candidate.description,
        'Spices, cloves, ground',
      );
    });

    test('Pan-Roasted Sea Bass (1183), "½ cup toasted slivered almonds": a '
        'toasted bread covers "toasted" but carries no almond — no credit '
        'for "slivered"', () async {
      final bread = (await rank('toasted slivered almonds')).firstWhere(
        (c) => c.candidate.fdcId == 172674,
      );
      expect(bread.confidence, closeTo(0.0333, 1e-4));
    });

    test('P2(a): "white" is docked on an egg record the query does not name '
        'it on: "Eggs, Grade A, Large, egg white" for eggs', () async {
      final white = (await rank('eggs')).firstWhere(
        (c) => c.candidate.fdcId == 747997,
      );
      expect(white.confidence, closeTo(0.84, 1e-9));
    });
  });

  group('M6/M10/P3: grams', () {
    test(
      'whole birds: the weighed bird of Chicken with 40 Cloves of Garlic '
      '(0452) and the whole chicken whose breast is set aside (0002) take '
      'the yield; leg quarters (Barbecued Pulled Chicken, 0634) do not',
      () async {
        final chicken = await food(171447);
        const fortyCloves =
            '1 (3½- to 4-pound) chicken, cut into 8 pieces (4 breast '
            'pieces, 2 thighs, 2 drumsticks; see this page) and trimmed';
        const noodleSoup =
            '1 (4-pound) whole chicken, breast removed, split, and reserved; '
            'remaining chicken cut into 2-inch pieces';
        for (final raw in [fortyCloves, noodleSoup]) {
          final grams = gramsOf(raw, chicken)!;
          expect(grams.grams, closeTo(1104, 0.5), reason: raw);
          expect(grams.basis, contains('0.61 edible'), reason: raw);
        }
        final quarters = gramsOf(
          '8 (14-ounce) chicken leg quarters, trimmed',
          chicken,
        )!;
        expect(quarters.grams, closeTo(8 * 14 * 28.3495, 0.1));
        expect(
          quarters.basis,
          endsWith('approximate (gross weight, no part yield)'),
        );
        // "whole" before a part is the part's, not a bird's: the corpus's
        // only such line (0150, "4 whole chicken legs, separated") is a bare
        // count, so a weighed one is synthesized (negative path).
        final wings = gramsOf(
          '1 (2-pound) whole chicken wings, wingtips removed',
          chicken,
        )!;
        expect(wings.grams, closeTo(2 * 453.592, 0.1));
        expect(wings.basis, isNot(contains('edible')));
      },
    );

    test(
      'a fine cut reads the chopped portion: "¼ cup grated onion" (0329) '
      'weighs per mL what "2 tablespoons grated onion" (0203) does',
      () async {
        final onion = await food(170000);
        final cup = gramsOf('¼ cup grated onion', onion)!;
        final tablespoons = gramsOf('2 tablespoons grated onion', onion)!;
        expect(cup.grams, closeTo(40, 1e-9));
        expect(tablespoons.grams, closeTo(20, 1e-9));
        expect(cup.grams / 4, closeTo(tablespoons.grams / 2, 1e-9));
      },
    );

    test('P3: with no named portion the whole form is read: "1 cup almonds, '
        'chopped coarse" (Nut-Crusted Chicken Breasts, 0117) is "cup, '
        'whole" 143 g', () async {
      // "Nuts, almonds" (170567): no chopped portion; whole 143 g, sliced,
      // slivered and ground lighter.
      final almonds = gramsOf(
        '1 cup almonds, chopped coarse',
        await food(170567),
      )!;
      expect(almonds.grams, 143);
    });

    test("P2(g): a rule record's row whose grams are not the rule's (v7 "
        "counted 0423 on lemon juice at the zest's teaspoon) never reads "
        'the rule basis', () async {
      final db = tempDb();
      final juice = await food(167747);
      db.fdcFoodCachePut(juice.fdcId, jsonEncode(juice.toJson()));
      final line = lineOf(lemon);
      IngredientMatchRow row(double grams) => IngredientMatchRow(
        recipeId: 'r1',
        position: 0,
        raw: lemon,
        fdcId: juice.fdcId,
        description: juice.description,
        dataType: juice.dataType,
        confidence: 1,
        grams: grams,
        gramSource: 'density',
        status: 'auto',
      );
      final byRule = secondFoodRuleOf(line)!.gramsOn(juice)!;
      expect(gramBasisFor(db, line, row(byRule.grams)), byRule.basis);
      // v7's grams: the line's own first amount (the zest's teaspoon) on
      // the juice record.
      final zestGrams = gramsOf(lemon, juice)!.grams;
      expect(zestGrams, lessThan(byRule.grams - 0.05));
      expect(
        gramBasisFor(db, line, row(zestGrams)),
        isNot(contains('juice only')),
      );
    });
  });

  group('M7/M8: keys a comma list reads, and decisions that follow them', () {
    test('an identity participle leading a comma list stays with its food; a '
        'prep one goes: roasted pepitas (1071), unsweetened coconut (0831), '
        'hazelnuts (Paris-Brest, 0908), pepperoncini (Penne Arrabbiata, '
        '0334)', () {
      expect(
        [
          '5 tablespoons chopped roasted, salted pepitas, divided',
          '3 cups unsweetened, shredded, desiccated (dried) coconut',
          '2 tablespoons toasted, skinned, and chopped hazelnuts',
          '¼ cup stemmed, patted dry, and minced pepperoncini',
        ].map((raw) => lineKeyOf(lineOf(raw))),
        [
          'roasted with salt pepita',
          'unsweetened desiccated coconut',
          'hazelnut',
          'pepperoncini',
        ],
      );
    });

    test('every identity participle keeps its food: a real line with a comma '
        'after the word (a comma list a recipe may type) keys as the line '
        'does', () {
      // word → the real corpus line that puts it before its food.
      const lines = {
        'roasted': '½ cup roasted red peppers, chopped fine', // Paella, 0106
        // Caramel-Espresso Yule Log (1160)
        'unsweetened': '½ cup (1 ounce) unsweetened cocoa powder',
        'sweetened': '2 cups sweetened shredded coconut', // Coconut Layer Cake
        // Spanish Migas with Fried Eggs (1099)
        'smoked': '1 teaspoon smoked paprika, divided',
        'dried': '1 teaspoon dried oregano', // Gluten-Free Pizza, 0393
        'cooked': '2¾ cups cooked wheat berries', // Broccoli Salad, 1073
        // Classic Green Bean Casserole (0179)
        'canned': '3 cups canned fried onions (about 6 ounces)',
        'pickled': '4 pickled hot cherry peppers (3 ounces)', // Moqueca, 0284
        // Struffoli (1163)
        'candied': '2 tablespoons candied orange peel, chopped fine (optional)',
        // Triple Berry Slab Pie (1204)
        'crystallized': '½ cup crystallized ginger, chopped fine',
        // Chocolate-Espresso Dacquoise (0906)
        'blanched': '¾ cup blanched sliced almonds, toasted',
        // Crispy Thai Eggplant Salad (0053)
        'fried': '½ cup Fried Shallots (recipe follows)',
        'unseasoned': '2 tablespoons unseasoned rice vinegar',
        // Lemon Layer Cake (0881)
        'powdered': '1 teaspoon powdered gelatin',
        // Antipasto Pasta Salad (0060)
        'aged': '4 ounces aged provolone cheese, grated (about 1 cup)',
        // Alcatra (0007)
        'cracked':
            '1 tablespoon cracked black peppercorns, plus extra for '
            'serving',
      };
      for (final MapEntry(key: word, value: raw) in lines.entries) {
        final at = raw.toLowerCase().indexOf('$word ') + word.length;
        final listed = '${raw.substring(0, at)},${raw.substring(at)}';
        final key = lineKeyOf(lineOf(listed));
        expect(key, lineKeyOf(lineOf(raw)), reason: listed);
        expect(key, contains(word), reason: listed);
      }
    });

    for (final (rowsFirst, order) in [
      (false, 'decisions re-keyed first'),
      (
        true,
        "the match rows re-keyed first (boot's order; a DB that booted v8)",
      ),
    ]) {
      for (final (rowFood, onFood) in [
        (170581, 'the row on the decided food'),
        // A person picked 170581 on one recipe, later 170582 on another with
        // the same line (rewriting the decision), then deleted that recipe:
        // this row still holds their first pick (refix round 2).
        (170582, 'the row overridden to another food'),
      ]) {
        test(
          'a v7 decision under a key no line produces follows its line '
          '(Paris-Brest, 0908), its item text too; one with no line left '
          'keeps its item key — $order, $onFood',
          () {
            final db = tempDb();
            const hazelnuts =
                '2 tablespoons toasted, skinned, and chopped hazelnuts';
            final r = recipeOf(db, 'paris-brest', [hazelnuts]);
            // As v7 stored them: the key and item text of v7's decisionItemOf,
            // and the decided row under that key.
            db
              ..upsertIngredientMatch(
                IngredientMatchRow(
                  recipeId: r.id,
                  position: 0,
                  raw: hazelnuts,
                  itemKey: 'toasted skinned and hazelnut',
                  fdcId: rowFood,
                  description: 'Nuts, hazelnuts or filberts',
                  dataType: 'SR Legacy',
                  confidence: 1,
                  grams: 17,
                  gramSource: 'density',
                  status: rowFood == 170581 ? 'confirmed' : 'overridden',
                ),
              )
              ..insertDecision(
                const IngredientDecisionRow(
                  itemKey: 'toasted skinned and hazelnut',
                  item: 'toasted skinned and chopped hazelnuts',
                  fdcId: 170581,
                  description: 'Nuts, hazelnuts or filberts',
                  dataType: 'SR Legacy',
                  decidedBy: null,
                  decidedAt: '2026-09-20 00:00:00',
                ),
              )
              ..insertDecision(
                const IngredientDecisionRow(
                  itemKey: 'stemmed patted dry and pepperoncini',
                  item: 'stemmed patted dry and minced pepperoncini',
                  fdcId: 170581,
                  description: 'stand-in',
                  dataType: 'SR Legacy',
                  decidedBy: null,
                  decidedAt: '2026-09-20 00:00:00',
                ),
              )
              ..setSetting(decisionRekeySetting, '7');
            if (rowsFirst) {
              expect(backfillItemKeys(db), 1);
              expect(db.matchesForItemKey('hazelnut'), hasLength(1));
            }
            expect(rekeyDecisions(db), 1);
            final moved = db.decisionFor('hazelnut')!;
            expect(moved.fdcId, 170581);
            expect(decisionKeyFor(moved.item), 'hazelnut');
            expect(db.decisionFor('toasted skinned and hazelnut'), isNull);
            // No row carries the pepperoncini key: its item text keys it.
            expect(
              db.decisionFor('stemmed patted dry and pepperoncini'),
              isNotNull,
            );
            // The next re-key with the line gone keys the moved decision where
            // the line did (its item text moved with it).
            db
              ..deleteIngredientMatchesFrom(r.id, 0)
              ..setSetting(decisionRekeySetting, '8');
            expect(rekeyDecisions(db), 0);
            expect(db.decisionFor('hazelnut')?.fdcId, 170581);
          },
        );
      }
    }

    test('boot re-keys decisions BEFORE rows: a v8 pick on Key Lime Pie '
        '(0989) "4 teaspoons grated zest plus ½ cup juice from 3 or 4 limes" '
        'follows its line to "lime zest plus juice"', () {
      // The v8 key and item text of a pick on this line. Under v9 the line
      // keys 'lime zest plus juice' and its prep-kept reading moves the fruit
      // to the front, so the old-key row is the only example that finds it.
      const raw = '4 teaspoons grated zest plus ½ cup juice from 3 or 4 limes';
      final line = lineOf(raw);
      expect(lineKeyOf(line), 'lime zest plus juice');
      SaltDatabase seeded() {
        final db = tempDb();
        final r = recipeOf(db, 'r0989', [raw]);
        db
          ..upsertIngredientMatch(
            IngredientMatchRow(
              recipeId: r.id,
              position: 0,
              raw: raw,
              itemKey: 'zest plus juice',
              fdcId: 168156,
              description: 'Lime juice, raw',
              dataType: 'SR Legacy',
              confidence: 1,
              grams: 122,
              gramSource: 'volume',
              status: 'overridden',
            ),
          )
          ..insertDecision(
            const IngredientDecisionRow(
              itemKey: 'zest plus juice',
              item: 'grated zest plus 1/2 cup juice',
              fdcId: 168156,
              description: 'Lime juice, raw',
              dataType: 'SR Legacy',
              decidedBy: null,
              decidedAt: '2026-09-20 00:00:00',
            ),
          )
          ..setSetting(decisionRekeySetting, '8')
          ..setSetting(itemKeyBackfillSetting, '8');
        return db;
      }

      // Boot's order.
      final booted = seeded();
      rekeyAfterMatcherChange(booted);
      expect(booted.decisionFor('lime zest plus juice')?.fdcId, 168156);
      expect(booted.decisionFor('zest plus juice'), isNull);
      expect(
        booted.matchesForItemKey('lime zest plus juice'),
        hasLength(1),
        reason: 'the row was re-keyed too',
      );
      // Rows first would strand the decision: nothing then carries its old
      // key, and its item text reads nowhere under v9.
      final rowsFirst = seeded();
      backfillItemKeys(rowsFirst);
      rekeyDecisions(rowsFirst);
      expect(rowsFirst.decisionFor('lime zest plus juice'), isNull);
    });

    test('a stale row — its recipe line edited since the compute — is no '
        'example: the v7 hazelnut decision (0908) never follows the line now '
        "at that position (Penne Arrabbiata's pepperoncini, 0334)", () {
      final db = tempDb();
      final r = recipeOf(db, 'paris-brest', [
        '¼ cup stemmed, patted dry, and minced pepperoncini',
      ]);
      db
        ..upsertIngredientMatch(
          IngredientMatchRow(
            recipeId: r.id,
            position: 0,
            raw: '2 tablespoons toasted, skinned, and chopped hazelnuts',
            itemKey: 'toasted skinned and hazelnut',
            fdcId: 170581,
            description: 'Nuts, hazelnuts or filberts',
            dataType: 'SR Legacy',
            confidence: 1,
            grams: 17,
            gramSource: 'density',
            status: 'confirmed',
          ),
        )
        ..insertDecision(
          const IngredientDecisionRow(
            itemKey: 'toasted skinned and hazelnut',
            item: 'toasted skinned and chopped hazelnuts',
            fdcId: 170581,
            description: 'Nuts, hazelnuts or filberts',
            dataType: 'SR Legacy',
            decidedBy: null,
            decidedAt: '2026-09-20 00:00:00',
          ),
        )
        ..setSetting(decisionRekeySetting, '7');
      expect(rekeyDecisions(db), 0);
      expect(db.decisionFor('pepperoncini'), isNull);
      expect(db.decisionFor('toasted skinned and hazelnut')?.fdcId, 170581);
    });
  });

  group('M11/P1/P2: failures and guards', () {
    test("M11: Pan-Seared Thick-Cut Pork Chops (0201): the chops' yield "
        'detail failing fails the compute — never 1,361 g counted with the '
        'hash current', () async {
      final db = tempDb();
      const chops =
          '4 (12-ounce) bone-in rib loin pork chops, about 1½ inches thick, '
          'trimmed of excess fat';
      final r = recipeOf(db, 'r1', [chops]);
      final failing = _FailsFood(provider, 168242);
      await expectLater(
        matchAndCompute(db, failing, r),
        throwsA(isA<NutritionProviderException>()),
      );
      expect(db.nutritionFor('r1'), isNull);
      final counted = db
          .ingredientMatchesFor('r1')
          .where((row) => bucketOf(row) == MatchBucket.counted);
      expect(counted, isEmpty);
      // A person's pick of the cached hit needs the same detail: the PUT
      // fails (the route's 422) with nothing written — v8 stored it
      // overridden at 1,361 g.
      final line = nutritionLines(r).single;
      expect(knownFood(db, 168242, line: line), isNotNull);
      final unmatched = IngredientMatchRow(
        recipeId: 'r1',
        position: 0,
        raw: chops,
        itemKey: lineKeyOf(line),
        fdcId: null,
        description: null,
        dataType: null,
        confidence: 0,
        grams: null,
        gramSource: null,
        status: 'unmatched',
      );
      db.upsertIngredientMatch(unmatched);
      await expectLater(
        applyMatchOverride(db, failing, r, 0, {'fdc_id': 168242}),
        throwsA(isA<NutritionProviderException>()),
      );
      final after = db.ingredientMatchesFor('r1').single;
      expect(
        (after.status, after.fdcId, after.grams),
        ('unmatched', null, null),
      );
    });

    test('P1: Classic Guacamole (0471): a juice range has no volume, so the '
        'citrus rule leaves the line held on its own pick', () async {
      final db = tempDb();
      final r = recipeOf(db, 'r1', [
        '¼ teaspoon grated lime zest plus 1½–2 tablespoons juice',
      ]);
      await matchAndCompute(db, provider, r);
      final row = db.ingredientMatchesFor('r1').single;
      expect((row.fdcId, row.hold), (2709170, 'second_food'));
    });

    test('a rule fires only on a line the reach leaves out: a counted extra '
        'cut into wedges names no second food, so no rule counts it '
        '(line synthesized: negative path — the corpus has no counted '
        'wedge extra a rule reads)', () {
      const raw =
          '2 large hard-cooked eggs plus 2 large yolks, cut into wedges';
      expect(namesSecondFood(raw), isFalse);
      expect(secondFoodRuleOf(lineOf(raw)), isNull);
      // Its wedge-free twin is a rule line, and one the reach leaves out.
      const eggs = '2 large hard-cooked eggs plus 2 large yolks';
      expect(namesSecondFood(eggs), isTrue);
      expect(secondFoodRuleOf(lineOf(eggs))?.fdcId, 748967);
    });

    test('P2(c): a dissolve sentence naming only the line itself is no brine '
        "beside another salt: 0091's curing salt dissolved alone (steps "
        'synthesized: negative path)', () {
      final db = tempDb();
      final r = recipeOf(
        db,
        'corned',
        ['¾ cup salt', '2 teaspoons pink curing salt #1'],
        steps: [
          'Dissolve curing salt in ¼ cup water and rub it over the brisket.',
          'Combine the salt with 4 quarts water to make a brine.',
        ],
      );
      final line = nutritionLines(r).last;
      expect(
        discardedMediumOf(r, line, normalizeItem(lineItemOf(line))),
        isNull,
      );
    });

    test(
      'P2(f): a sibling that takes the decided food but stays no_grams is '
      'offered and applied — the decision reached it: 2 bunches of '
      'scallions (Pork Lo Mein, 0540)',
      () async {
        final db = tempDb();
        const scallions =
            '2 bunches scallions, whites sliced thin, greens cut into 1-inch '
            'pieces';
        final a = recipeOf(db, 'ra', [scallions]);
        final b = recipeOf(db, 'rb', [scallions]);
        for (final r in [a, b]) {
          await matchAndCompute(db, provider, r);
        }
        final yellow = await food(790646);
        final before = db.ingredientMatchesFor('rb').single;
        db.upsertIngredientMatch(
          before.copyWith(
            fdcId: yellow.fdcId,
            description: yellow.description,
            dataType: yellow.dataType,
            confidence: 0.6,
            clearGrams: true,
            clearHold: true,
          ),
        );
        expect(
          bucketOf(db.ingredientMatchesFor('rb').single),
          MatchBucket.noAmount,
        );
        await applyMatchOverride(db, provider, a, 0, {
          'fdc_id': 2709794, // Onions, green, raw
        });
        expect((await matchOf(db, a, 0))['others_lines'], 1);
        final applied = await applyMatchOverride(db, provider, a, 0, {
          'fdc_id': 2709794,
          'apply_to_all': true,
        });
        final after = db.ingredientMatchesFor('rb').single;
        expect((after.fdcId, bucketOf(after)), (2709794, MatchBucket.noAmount));
        expect(applied!.lines, 1);
      },
    );
  });

  group('M15: fixture fidelity', () {
    test('an unrecorded answer throws, never a silent 404 or empty answer '
        '(queries synthesized: negative path)', () async {
      final strict = FixtureProvider();
      await expectLater(
        strict.search('a query nobody recorded'),
        throwsA(isA<UnrecordedAnswer>()),
      );
      await expectLater(strict.food(1), throwsA(isA<UnrecordedAnswer>()));
      final named = FixtureProvider(pending: {'a query nobody recorded'});
      expect(await named.search('a query nobody recorded'), isEmpty);
      await expectLater(
        named.search('another'),
        throwsA(isA<UnrecordedAnswer>()),
      );
      await expectLater(named.food(1), throwsA(isA<UnrecordedAnswer>()));
      expect(await FixtureProvider(superseded: {170567}).food(170567), isNull);
    });
  });
}
