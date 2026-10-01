// Matcher v22, Run 052's grams-side fixes and pins (F2, F8 O8/S7, F10, F9):
// real corpus lines; each synthesized edit is stated where it is made.
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// [recipe] with its main line reading [from] rewritten to [to] (a
/// person's edit — synthesized, the stated exception of each test).
Recipe edit(Recipe recipe, String from, String to) {
  final parsed = parseIngredientLine(to);
  var hits = 0;
  final out = recipe.copyWith(
    ingredients: [
      for (final group in recipe.ingredients)
        group.copyWith(
          items: [
            for (final item in group.items)
              if (item.raw == from && hits++ == 0)
                IngredientLine(
                  raw: to,
                  item: parsed.item,
                  amounts: parsed.amounts,
                  prep: parsed.prep,
                )
              else
                item,
          ],
        ),
    ],
  );
  expect(hits, 1, reason: from);
  return out;
}

int positionOf(Recipe recipe, String raw) =>
    nutritionLines(recipe).indexWhere((l) => l.raw == raw);

void main() {
  group('F2 (Run 052 O2/S3): an edit of the eaten "plus" part re-derives '
      'typed grams', () {
    const three =
        '1 recipe Crispy Onions, plus 3 tablespoons reserved oil (recipe '
        'follows)';
    const six =
        '1 recipe Crispy Onions, plus 6 tablespoons reserved oil (recipe '
        'follows)';

    Future<(SaltDatabase, FixtureProvider, Recipe, int)> typed25() async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final r = loadCorpusRecipe(
        '0711-mujaddara-rice-and-lentils-with-crispy-onions.yaml',
      );
      wp.saveRecipe(db, r);
      await matchAndCompute(db, provider, r);
      final at = positionOf(r, three);
      await applyMatchOverride(db, provider, r, at, {
        'raw': three,
        'confirmed': true,
        'grams': 25,
      });
      final edited = edit(r, three, six);
      wp.saveRecipe(db, edited);
      return (db, provider, edited, at);
    }

    test("0711's plus line typed 25 g, its plus part edited 3 → 6 "
        'tablespoons: the compute re-derives 84 g', () async {
      final (db, provider, edited, at) = await typed25();
      await matchAndCompute(db, provider, edited);
      final row = db.ingredientMatchesFor(edited.id)[at];
      expect(row.raw, six);
      expect(row.grams, 84);
      expect(row.gramSource, 'portion');
    }, skip: skipIfNoCorpus);

    test('… and the stale-window PUT (a skip, then the un-skip, before any '
        'compute) re-derives it too', () async {
      final (db, provider, edited, at) = await typed25();
      await applyMatchOverride(db, provider, edited, at, {
        'raw': six,
        'skipped': true,
      });
      await applyMatchOverride(db, provider, edited, at, {
        'raw': six,
        'skipped': false,
      });
      final row = db.ingredientMatchesFor(edited.id)[at];
      expect(row.raw, six);
      expect(row.grams, 84);
      expect(row.gramSource, 'portion');
    }, skip: skipIfNoCorpus);
  });

  group('F2: the eggs-plus-yolks line (the egg rule weighs both parts)', () {
    const six = '2 large eggs plus 6 large yolks';

    Future<(SaltDatabase, FixtureProvider, Recipe, int)> typed(
      String to,
    ) async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final r = loadCorpusRecipe('0324-fresh-pasta-without-a-machine.yaml');
      wp.saveRecipe(db, r);
      await matchAndCompute(db, provider, r);
      final at = positionOf(r, six);
      await applyMatchOverride(db, provider, r, at, {
        'raw': six,
        'confirmed': true,
        'grams': 300,
      });
      final edited = edit(r, six, to);
      wp.saveRecipe(db, edited);
      await matchAndCompute(db, provider, edited);
      return (db, provider, edited, at);
    }

    test(
      '6 → 8 yolks (synthesized edit): the typed 300 g is re-derived',
      () async {
        final (db, _, edited, at) = await typed(
          '2 large eggs plus 8 large yolks',
        );
        final row = db.ingredientMatchesFor(edited.id)[at];
        expect(row.raw, '2 large eggs plus 8 large yolks');
        expect(row.gramSource, isNot('override'));
        expect(row.grams, isNot(300));
      },
      skip: skipIfNoCorpus,
    );

    test('a prep-only rewrite (", room temperature", synthesized) keeps '
        'the typed 300 g', () async {
      final (db, _, edited, at) = await typed(
        '2 large eggs plus 6 large yolks, room temperature',
      );
      final row = db.ingredientMatchesFor(edited.id)[at];
      expect(row.raw, '2 large eggs plus 6 large yolks, room temperature');
      expect((row.grams, row.gramSource), (300, 'override'));
    }, skip: skipIfNoCorpus);
  });

  /// [raw] alone in a recipe, computed on the recorded answers.
  Future<IngredientMatchRow> computeAlone(String raw) async {
    final db = wp.tempDb();
    final parsed = parseIngredientLine(raw);
    final recipe = Recipe(
      id: 'r',
      title: 'r',
      slug: 'r',
      source: const RecipeSource(name: 'Test', type: 'book'),
      ingredients: [
        IngredientGroup(
          items: [
            IngredientLine(
              raw: raw,
              item: parsed.item,
              amounts: parsed.amounts,
            ),
          ],
        ),
      ],
    );
    db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h');
    await matchAndCompute(db, FixtureProvider(), recipe);
    return db.ingredientMatchesFor('r').single;
  }

  test('F8 (Run 052 O8/S7): one path per record — every instant coffee and '
      "espresso wording on 171893 weighs by the table's 0.43 g/mL (2 "
      "teaspoons: 4.24 g), never the record's loose tsp for one wording "
      '(0897 Hot Fudge Pudding Cake, 0821 Thick and Chewy Double-Chocolate '
      'Cookies, the 13 "instant espresso powder" lines at 2 tsp)', () async {
    final food = (await FixtureProvider().food(171893))!;
    final db = wp.tempDb();
    for (final raw in [
      '2 teaspoons instant coffee powder',
      '2 teaspoons instant coffee or espresso powder',
      '2 teaspoons instant espresso powder',
    ]) {
      final parsed = parseIngredientLine(raw);
      final g = lineGrams(
        db,
        IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts),
        food,
      );
      expect(g?.grams, closeTo(4.24, 0.01), reason: raw);
      expect(g?.source, GramSource.density, reason: raw);
    }
  });

  test(
    'F10: "1 sugar cube" (1155 Champagne Cocktail) is granulated sugar, never '
    '"Beef, steak, cube" — in review with no grams (the record publishes '
    'no cube portion)',
    () async {
      final row = await computeAlone('1 sugar cube');
      expect(row.fdcId, 746784);
      expect(row.description, 'Sugars, granulated');
      expect(row.grams, isNull);
      expect(
        matchBucketFor(
          status: row.status,
          fdcId: row.fdcId,
          grams: row.grams,
          confidence: row.confidence,
          hold: row.hold,
          gramSource: row.gramSource,
        ),
        MatchBucket.noAmount,
      );
    },
  );
}
