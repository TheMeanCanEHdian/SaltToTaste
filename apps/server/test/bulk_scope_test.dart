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

import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart'
    show manualSourceSlug;
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';

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

    test('the prefilter compares timestamps that are NOT the same format', () {
      // recipes.updated_at is SQLite datetime('now') -- "2026-07-16 02:07:09".
      // recipe_nutrition.computed_at is Dart toIso8601String() --
      // "2026-07-16T02:11:15.849334Z". A raw >= compares ' ' (0x20) against
      // 'T' (0x54) at the eleventh character and answers false for every
      // same-day pair whatever the real times are, so the prefilter would
      // select nothing and `stale` would silently be a no-op. This is the
      // regression that caught me writing it.
      markComputed(alpha);
      store(alpha.copyWith(title: 'touched after its compute'));
      final candidates = db.recipesPossiblyStaleNutrition();
      expect(
        candidates.map((c) => c.id),
        contains(alpha.id),
        reason: 'a recipe updated after its compute must reach the hash check',
      );
    });
  });
}
