import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/admin_handlers.dart';
import 'package:salt_server/src/services/recipe_health.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';

/// The admin recipe-review scan (#6/#7). Real corpus recipes are clean, so the
/// defect cases introduce a single flaw into a real recipe (a real recipe minus
/// its steps, etc.) rather than fabricating a document.
void main() {
  if (!corpusAvailable) {
    test(
      'recipe-review tests (skipped: corpus absent)',
      () {},
      skip: skipIfNoCorpus,
    );
    return;
  }

  String? detailFor(String checkId, RecipeHealth health) =>
      recipeChecks.firstWhere((c) => c.id == checkId).evaluate(health);

  group('checks (a real recipe with one flaw)', () {
    late Recipe bundt; // has steps, serves, parsed amounts, no warnings

    setUpAll(() {
      bundt = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
    });

    test('no_instructions fires only when steps are empty', () {
      expect(detailFor('no_instructions', RecipeHealth(recipe: bundt)), isNull);
      expect(
        detailFor(
          'no_instructions',
          RecipeHealth(recipe: bundt.copyWith(steps: [])),
        ),
        isNotNull,
      );
    });

    test('no_servings fires only when the numeric yield is missing', () {
      expect(detailFor('no_servings', RecipeHealth(recipe: bundt)), isNull);
      expect(
        detailFor(
          'no_servings',
          RecipeHealth(recipe: bundt.copyWith(serves: null)),
        ),
        isNotNull,
      );
    });

    test('unparsed_ingredients: quantity + unit with no parsed amount', () {
      RecipeHealth withLine(String raw) => RecipeHealth(
        recipe: bundt.copyWith(
          ingredients: [
            IngredientGroup(items: [IngredientLine(raw: raw)]),
          ],
        ),
      );

      // Genuinely amountless prose is not a defect.
      expect(
        detailFor('unparsed_ingredients', withLine('Salt to taste')),
        isNull,
      );
      // A number that is NOT an amount — a dimension or equipment — is not a
      // defect either (the noise the tightened check drops).
      expect(
        detailFor('unparsed_ingredients', withLine('1- to 2-inch lengths')),
        isNull,
      );
      expect(
        detailFor(
          'unparsed_ingredients',
          withLine('2 disposable aluminum pie plates'),
        ),
        isNull,
      );
      // A quantity + measurement unit that parsed nothing IS a defect.
      final detail = detailFor(
        'unparsed_ingredients',
        withLine('2 tablespoons juice'),
      );
      expect(detail, contains('juice'));
    });

    test('extraction_warnings surfaces the recorded warnings', () {
      expect(
        detailFor('extraction_warnings', RecipeHealth(recipe: bundt)),
        isNull,
      );
      final warned = bundt.copyWith(
        extraction: const Extraction(warnings: ['duplicate step numbering']),
      );
      expect(
        detailFor('extraction_warnings', RecipeHealth(recipe: warned)),
        contains('duplicate step'),
      );
    });

    test('nutrition: none vs partial vs complete', () {
      expect(detailFor('no_nutrition', RecipeHealth(recipe: bundt)), isNotNull);
      final partial = RecipeHealth(
        recipe: bundt,
        nutrition: const NutritionSummary(
          status: 'partial',
          matched: 12,
          total: 13,
        ),
      );
      expect(detailFor('no_nutrition', partial), isNull);
      expect(detailFor('incomplete_nutrition', partial), '12 / 13 matched');
      final complete = RecipeHealth(
        recipe: bundt,
        nutrition: const NutritionSummary(
          status: 'complete',
          matched: 13,
          total: 13,
        ),
      );
      expect(detailFor('incomplete_nutrition', complete), isNull);
    });
  });

  group('scan over a seeded library', () {
    late Directory tempDir;
    late SaltDatabase db;
    late List<String> ids;

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('salt_review_test_');
      db = SaltDatabase.open('${tempDir.path}/salt.db')
        ..upsertSource(slug: 'atk', name: 'ATK', type: 'epub');
      final files =
          (Directory(corpusRecipesDir)
                  .listSync()
                  .whereType<File>()
                  .where(
                    (f) => f.path.endsWith('.yaml'),
                  )
                  .toList()
                ..sort((a, b) => a.path.compareTo(b.path)))
              .take(30);
      ids = [];
      for (final file in files) {
        final recipe = RecipeYamlCodec.decode(file.readAsStringSync()).recipe;
        db.upsertRecipe(
          recipe,
          sourceSlug: 'atk',
          contentHash: contentHashOf(recipe),
        );
        ids.add(recipe.id);
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    int count(RecipeReviewReport r, String id) =>
        r.categories.firstWhere((c) => c.id == id).count;

    test('a fresh import flags every recipe as No nutrition data', () {
      final report = buildRecipeReviewReport(db, page: 1, limit: 100);
      expect(count(report, 'no_nutrition'), 30);
      expect(
        report.total,
        30,
        reason: 'every recipe has at least the nutrition gap',
      );
      // The categories list is the full registry, in order.
      expect(
        report.categories.map((c) => c.id),
        recipeChecks.map((c) => c.id),
      );
    });

    test('computing nutrition moves a recipe out of No nutrition data', () {
      void seedNutrition(
        String id, {
        required int matched,
        required int total,
        required String status,
      }) {
        db.upsertRecipeNutrition(
          recipeId: id,
          servingBasis: 8,
          caloriesPerServing: 300,
          nutrientsJson: '{}',
          totalGrams: 1000,
          matchedCount: matched,
          totalCount: total,
          status: status,
          ingredientsHash: 'h',
        );
      }

      seedNutrition(ids[0], matched: 12, total: 13, status: 'partial');
      seedNutrition(ids[1], matched: 13, total: 13, status: 'complete');

      final report = buildRecipeReviewReport(db, page: 1, limit: 100);
      expect(
        count(report, 'no_nutrition'),
        28,
        reason: '2 now have a nutrition row',
      );
      expect(
        count(report, 'incomplete_nutrition'),
        1,
        reason: 'the partial one',
      );

      // Filtering narrows the items to the one partial recipe.
      final filtered = buildRecipeReviewReport(
        db,
        page: 1,
        limit: 100,
        issue: 'incomplete_nutrition',
      );
      expect(filtered.items, hasLength(1));
      expect(filtered.items.single.id, ids[0]);
      expect(
        filtered.items.single.issues.map((i) => i.check),
        contains('incomplete_nutrition'),
      );
      // total stays whole-library (the "need attention" number), filter or not.
      expect(filtered.total, greaterThanOrEqualTo(29));
    });

    test('pagination slices the flagged list', () {
      final p1 = buildRecipeReviewReport(db, page: 1, limit: 10);
      final p2 = buildRecipeReviewReport(db, page: 2, limit: 10);
      expect(p1.items, hasLength(10));
      expect(p2.items, hasLength(10));
      expect(
        {
          ...p1.items.map((i) => i.id),
        }.intersection({...p2.items.map((i) => i.id)}),
        isEmpty,
        reason: 'pages do not overlap',
      );
    });

    test('an unknown issue filter is a 422', () {
      expect(
        () => recipeReviewHandler(db, page: 1, limit: 10, issue: 'not_a_check'),
        throwsA(isA<ValidationException>()),
      );
    });

    // Runs last: it adds a recipe, so it must not run before the count tests.
    test('the memoized scan is invalidated by a recipe write', () {
      final before = buildRecipeReviewReport(db, page: 1, limit: 100);
      final noStepsBefore = count(before, 'no_instructions');

      // A new recipe with no steps is a fresh no_instructions flag. If the
      // scan were served from the stale cache (fingerprint ignored), neither
      // the total nor the count would move.
      final flawed = loadCorpusRecipe(
        '0857-rich-chocolate-bundt-cake.yaml',
      ).copyWith(steps: []);
      db.upsertRecipe(
        flawed,
        sourceSlug: 'atk',
        contentHash: contentHashOf(flawed),
      );

      final after = buildRecipeReviewReport(db, page: 1, limit: 100);
      expect(
        after.total,
        before.total + 1,
        reason: 'the write moved the fingerprint, so the scan re-ran',
      );
      expect(count(after, 'no_instructions'), noStepsBefore + 1);
    });
  });
}
