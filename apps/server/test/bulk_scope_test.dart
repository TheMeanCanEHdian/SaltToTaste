// Which recipes a bulk nutrition compute covers (review R2).
//
// Before this, the job could only ever compute a recipe ONCE: its selection
// was `LEFT JOIN recipe_nutrition WHERE recipe_id IS NULL`, so a recipe whose
// ingredients were edited after its compute kept serving results the UI itself
// labels "stale", and the only way to refresh it was one recipe at a time by
// hand. With 1,198 of them that is a permanent manual chore.
//
// The trap these guard: `recipe_nutrition.status` has 'stale' in its CHECK
// constraint but NOTHING EVER WRITES IT — staleness is derived at read time by
// comparing `ingredients_hash` against a Dart-computed hash. So the obvious
// implementation, `WHERE n.status = 'stale'`, compiles, runs, and matches zero
// rows forever. Every test here therefore drives real edits through the real
// upsert path rather than asserting on that column.

import 'dart:async';
import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart'
    show manualSourceSlug;
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

void main() {
  late Directory tempDir;
  late SaltDatabase db;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('salt-bulk-scope-');
    db = SaltDatabase.open('${tempDir.path}/salt.db');
  });

  tearDown(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  test('every wire name maps to a scope, and nothing else does', () {
    // The route refuses an unknown scope rather than defaulting, so this is
    // the whole accepted vocabulary. No corpus needed.
    for (final scope in BulkScope.values) {
      expect(BulkScope.fromWire(scope.wireName), scope);
    }
    expect(BulkScope.fromWire('everything'), isNull);
    expect(BulkScope.fromWire(''), isNull);
    expect(BulkScope.fromWire('MISSING'), isNull, reason: 'case-sensitive');
  });

  group('scope selection over real recipes', skip: skipIfNoCorpus, () {
    late Recipe alpha;
    late Recipe beta;

    /// Stores [recipe] the way the importer does, so `updated_at` moves
    /// exactly as it does in production.
    void store(Recipe recipe) {
      db.upsertRecipe(
        recipe,
        sourceSlug: manualSourceSlug,
        contentHash: contentHashOf(recipe),
      );
    }

    /// Writes a nutrition row whose stored hash matches [recipe] as it is
    /// now — i.e. a fresh, non-stale compute.
    void markComputed(Recipe recipe) {
      db.upsertRecipeNutrition(
        recipeId: recipe.id,
        servingBasis: 4,
        caloriesPerServing: 100,
        nutrientsJson: '{}',
        totalGrams: 500,
        matchedCount: 1,
        totalCount: 1,
        status: 'complete',
        ingredientsHash: ingredientsHashOf(recipe),
      );
    }

    setUp(() {
      // recipes.source_slug is a foreign key; the library dir these are
      // filed under has to exist before anything can reference it.
      db.upsertSource(
        slug: manualSourceSlug,
        name: 'My recipes',
        type: 'manual',
      );
      alpha = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
      beta = loadCorpusRecipe('0093-cuban-style-picadillo.yaml');
      store(alpha);
      store(beta);
    });

    test('missing selects only what was never computed', () {
      expect(
        bulkScopeIds(db, BulkScope.missing),
        unorderedEquals([
          alpha.id,
          beta.id,
        ]),
      );
      markComputed(alpha);
      expect(bulkScopeIds(db, BulkScope.missing), [beta.id]);
    });

    test('all selects everything, computed or not', () {
      markComputed(alpha);
      expect(
        bulkScopeIds(db, BulkScope.all),
        unorderedEquals([
          alpha.id,
          beta.id,
        ]),
      );
    });

    test('stale selects a recipe whose INGREDIENTS changed, and only it', () {
      markComputed(alpha);
      markComputed(beta);
      expect(
        bulkScopeIds(db, BulkScope.stale),
        isEmpty,
        reason: 'nothing edited yet',
      );

      // A real ingredient edit through the real upsert path.
      final firstGroup = alpha.ingredients.first;
      final edited = alpha.copyWith(
        ingredients: [
          firstGroup.copyWith(
            items: [
              firstGroup.items.first.copyWith(raw: 'a different ingredient'),
              ...firstGroup.items.skip(1),
            ],
          ),
          ...alpha.ingredients.skip(1),
        ],
      );
      store(edited);

      expect(
        bulkScopeIds(db, BulkScope.stale),
        [alpha.id],
        reason: 'the edited recipe is stale; the untouched one is not',
      );
    });

    test('an edit that leaves the ingredients alone is NOT stale', () {
      // The prefilter is `updated_at >= computed_at`, which a title change
      // also satisfies — the Dart hash is what stops it becoming a recompute.
      // This matters: a false positive spends real FDC budget.
      markComputed(alpha);
      store(alpha.copyWith(title: '${alpha.title} (renamed)'));
      expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
    });

    test('the stored hash is the engine own, not a reimplementation', () {
      // If these two ever diverge, `stale` silently selects the wrong set.
      markComputed(alpha);
      final stored = db.nutritionFor(alpha.id)!;
      final reloaded = db.recipeByIdOrSlug(alpha.id)!.recipe;
      expect(stored.ingredientsHash, ingredientsHashOf(reloaded));
    });

    test('an edit that lands DURING a compute is still found stale', () async {
      // The third trap. A timestamp prefilter (updated_at >= computed_at)
      // was tried and is wrong by construction: computed_at is stamped when
      // the ROW is written, at the END of a compute, but the stored hash
      // describes the recipe as it was when the compute STARTED. An edit
      // that lands while the compute waits on the provider therefore has
      // updated_at < computed_at with a hash that no longer matches -- the
      // UI says stale, `missing` skips it (row exists), and a prefiltered
      // `stale` skipped it too. Only hashing every row is correct.
      final provider = FixtureProvider();
      final gate = Completer<void>();
      provider.gate = gate;
      final compute = matchAndCompute(db, provider, alpha);
      while (provider.searchCalls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      // The compute is now parked on the provider. Edit underneath it.
      final g = alpha.ingredients.first;
      store(
        alpha.copyWith(
          ingredients: [
            g.copyWith(
              items: [
                g.items.first.copyWith(raw: 'edited while computing'),
                ...g.items.skip(1),
              ],
            ),
            ...alpha.ingredients.skip(1),
          ],
        ),
      );
      // Let the provider "answer" in a LATER second than the edit. Both
      // timestamps truncate to seconds, so an edit and a completion inside
      // the same second look simultaneous and a `>=` prefilter would keep
      // the row by coincidence -- this test then pins nothing. Spanning a
      // second boundary is what makes the window observable.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      gate.complete();
      await compute;

      final reloaded = db.recipeByIdOrSlug(alpha.id)!.recipe;
      expect(
        db.nutritionFor(alpha.id)!.ingredientsHash,
        isNot(ingredientsHashOf(reloaded)),
        reason: 'sanity: the UI would label this stale',
      );
      expect(
        bulkScopeIds(db, BulkScope.stale),
        contains(alpha.id),
        reason: 'a recipe the UI labels stale must be in the stale sweep',
      );
    });

    test('a human decision made DURING a compute survives it', () async {
      // The "non-destructive" promise a broad scope rests on. matchAndCompute
      // snapshots the existing rows at entry and used to write `auto`
      // unconditionally at the end, so a confirm made through the review UI
      // while the compute waited on the provider was erased -- job done,
      // zero failures, nothing logged. The guard now sits in the statement,
      // against the row as it is at WRITE time.
      final provider = FixtureProvider();
      await matchAndCompute(db, provider, alpha); // first pass: rows exist
      final target = db
          .ingredientMatchesFor(alpha.id)
          .firstWhere((m) => m.position > 0 && m.status == 'auto');

      final gate = Completer<void>();
      provider.gate = gate;
      final sweep = matchAndCompute(db, provider, alpha);
      while (provider.searchCalls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      // The admin confirms this line while the sweep is parked.
      db.upsertIngredientMatch(
        IngredientMatchRow(
          recipeId: alpha.id,
          position: target.position,
          raw: target.raw,
          fdcId: target.fdcId,
          description: target.description,
          dataType: target.dataType,
          confidence: 1,
          grams: target.grams,
          gramSource: target.gramSource,
          status: 'confirmed',
        ),
      );
      gate.complete();
      await sweep;

      final after = db
          .ingredientMatchesFor(alpha.id)
          .firstWhere((m) => m.position == target.position);
      expect(after.status, 'confirmed', reason: 'the decision must stand');
    });

    test('an unmatched line IS retried by a sweep', () async {
      // `unmatched` is the engine's own "FDC had nothing", not a decision.
      // It used to be preserved forever alongside confirmed/overridden/
      // skipped, so a sweep re-ranked the lines that already matched and
      // never retried the ones that did not -- the lines a sweep exists for.
      final provider = FixtureProvider();
      await matchAndCompute(db, provider, alpha);
      final matched = db
          .ingredientMatchesFor(alpha.id)
          .firstWhere((m) => m.status == 'auto' && m.fdcId != null);
      // Overwrite it as if FDC had returned nothing last time.
      db.upsertIngredientMatch(
        IngredientMatchRow(
          recipeId: alpha.id,
          position: matched.position,
          raw: matched.raw,
          fdcId: null,
          description: 'No FoodData Central match',
          dataType: null,
          confidence: 0,
          grams: null,
          gramSource: null,
          status: 'unmatched',
        ),
      );
      await matchAndCompute(db, provider, alpha);
      final after = db
          .ingredientMatchesFor(alpha.id)
          .firstWhere((m) => m.position == matched.position);
      expect(after.fdcId, matched.fdcId, reason: 'the retry must re-match it');
      expect(after.status, 'auto');
    });
  });
  group('bulk job bookkeeping', skip: skipIfNoCorpus, () {
    test(
      'a sweep that stops on a provider failure unregisters its recipe',
      () async {
        // _run registers each recipe in the per-recipe job table for the
        // duration of its compute (single-flight with the per-recipe route,
        // and what surfaces computing_job_id). The provider-failure path
        // `return`s out of the loop; without a finally the registration stayed
        // behind, so the per-recipe compute handed back a dead job id forever
        // and every later sweep skipped the recipe as "already running".
        db.upsertSource(
          slug: manualSourceSlug,
          name: 'My recipes',
          type: 'manual',
        );
        final recipe = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
        db.upsertRecipe(
          recipe,
          sourceSlug: manualSourceSlug,
          contentHash: contentHashOf(recipe),
        );
        final provider = FixtureProvider()..failWith = 'budget exhausted';
        final jobId = startBulkJob(db, provider);
        expect(jobId, isNotNull);
        while (bulkJobRunning) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(db.nutritionJob(jobId!)!['status'], 'failed');
        expect(
          recipeComputeJobId(recipe.id),
          isNull,
          reason: 'the failed sweep must not leave the recipe registered',
        );
      },
    );
  });
}
