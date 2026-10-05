// Matcher v41, step 1 (design_v3 §2.1): migration 018's composite columns
// as STORAGE — the child-stamp arm of `underivedSql`, the row identity over
// the four columns, the food reach's partition by `gram_source 'recipe'`,
// and `bulkScopeIds`' parents-last order with the stale append.
//
// Real corpus recipes over the recorded real FDC answers (FixtureProvider,
// copied --from-db from snapshot 17), never the network. Step 1 changes no
// engine behaviour, so the composite rows these pins read are written by
// [route] in the shape design_v3 §2.2 item 3 gives the engine's routed row
// (`auto`, no food, no description, confidence 1, `gram_source 'recipe'`,
// grams = the child's `total_grams` x share, the child's id, share and
// `computed_at`) on the real reference line — the engine's own routing
// (step 2) writes the same row, and every assertion here holds for it.

import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

void main() {
  late Directory tempDir;
  late ServerConfig config;
  late SaltDatabase db;
  late FixtureProvider provider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('salt-v41-storage-');
    config = ServerConfig(
      dataDir: tempDir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    );
    db = SaltDatabase.open(config.dbPath)
      ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
    provider = FixtureProvider();
  });

  tearDown(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  /// Stores the corpus recipe [fileName] as the importer does.
  Recipe store(String fileName) {
    final recipe = loadCorpusRecipe(fileName);
    db.upsertRecipe(
      recipe,
      sourceSlug: _source,
      contentHash: contentHashOf(recipe),
    );
    return recipe;
  }

  Recipe stored(Recipe recipe) => db.recipeByIdOrSlug(recipe.id)!.recipe;

  bool fresh(Recipe recipe) => nutritionIsFresh(db, stored(recipe));

  /// Writes [parent]'s reference line at [position] as a row routed to
  /// [child] (design_v3 §2.2 item 3's shape), stamped with the child's
  /// current `computed_at`.
  IngredientMatchRow route(Recipe parent, int position, Recipe child) {
    final line = nutritionLines(parent)[position];
    expect(isSubRecipeReference(line.raw), isTrue, reason: line.raw);
    final at = db
        .ingredientMatchesFor(parent.id)
        .singleWhere((row) => row.position == position);
    final nutrition = db.nutritionFor(child.id)!;
    final row = IngredientMatchRow(
      recipeId: parent.id,
      position: position,
      raw: at.raw,
      fdcId: null,
      description: null,
      dataType: null,
      confidence: 1,
      grams: nutrition.totalGrams,
      gramSource: SaltDatabase.recipeGramSource,
      status: 'auto',
      itemKey: at.itemKey,
      childRecipeId: child.id,
      childShare: 1,
      childStamp: nutrition.computedAt,
    );
    db.upsertIngredientMatch(row);
    return db
        .ingredientMatchesFor(parent.id)
        .singleWhere((row) => row.position == position);
  }

  /// ONE bulk sweep of [scope], run to its end.
  Future<void> sweep(BulkScope scope) async {
    final job = startBulkJob(db, provider, scope: scope);
    expect(job, isNotNull);
    while (bulkJobRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(db.nutritionJob(job!)!['status'], 'done');
  }

  /// [recipe] with its first group's lines [a] and [b] swapped, saved
  /// through the recipe edit service (the recipe PUT's own path): its own
  /// text, reordered — the lines are hashed in order.
  void reorder(Recipe recipe, int a, int b) {
    final group = stored(recipe).ingredients.first;
    final items = [...group.items];
    final first = items[a];
    items[a] = items[b];
    items[b] = first;
    final edited = stored(recipe).copyWith(
      ingredients: [
        group.copyWith(items: items),
        ...stored(recipe).ingredients.skip(1),
      ],
    );
    final result = updateRecipe(db, config, recipe.id, {
      'ingredients': edited.toMap()['ingredients'],
    });
    expect(result.changed, isTrue);
  }

  int calls() => provider.searchCalls + provider.foodCalls;

  group('the composite row in storage', skip: skipIfNoCorpus, () {
    late Recipe dough;
    late Recipe blueberry;

    setUp(() async {
      dough = store('0973-all-butter-double-crust-pie-dough.yaml');
      blueberry = store('0979-blueberry-pie.yaml');
      await matchAndCompute(db, provider, dough);
      await matchAndCompute(db, provider, blueberry);
    });

    test('a routed row round-trips its four columns; a malformed one is '
        'refused', () {
      final row = route(blueberry, 0, dough);
      expect(row.raw, '1 recipe double-crust pie dough');
      expect(row.childRecipeId, dough.id);
      expect(row.childShare, 1);
      expect(row.childStamp, db.nutritionFor(dough.id)!.computedAt);
      expect(row.gramSource, 'recipe');
      expect(row.grams, db.nutritionFor(dough.id)!.totalGrams);
      expect(row.parts, isNull);
      // parts beside a child: the CHECK refuses it (the write path).
      expect(
        () => db.upsertIngredientMatch(row.copyWith(parts: '[]')),
        throwsA(isA<Exception>()),
      );
      expect(row.copyWith(clearChild: true).childRecipeId, isNull);
      expect(row.copyWith(clearChild: true).childStamp, isNull);
      expect(row.copyWith(clearChildStamp: true).childRecipeId, dough.id);
    });

    test(
      'identity reads all four columns, in Dart and in the SQL guard',
      () async {
        final row = route(blueberry, 0, dough);
        final before = row.childStamp!;
        // A real child write moves its stamp: the child recomputed.
        await matchAndCompute(db, provider, dough);
        final after = db.nutritionFor(dough.id)!.computedAt!;
        expect(after, isNot(before));
        final restamped = row.copyWith(childStamp: after);
        expect(sameMatchRow(row, restamped), isFalse);
        expect(sameMatchRow(row, row.copyWith(childShare: 0.5)), isFalse);
        expect(
          sameMatchRow(row, row.copyWith(childRecipeId: blueberry.id)),
          isFalse,
        );
        expect(
          sameMatchRow(
            row.copyWith(clearChild: true),
            row.copyWith(clearChild: true, parts: '[]'),
          ),
          isFalse,
        );
        expect(sameMatchRow(row, row.copyWith()), isTrue);
        // The stored row re-stamped: a guard over the OLD stamp misses it.
        db.upsertIngredientMatch(restamped);
        final layout = db.layoutOf(blueberry.id).seq;
        expect(
          db.markDerivedIfUnchanged(row, derivedSeq: 'x', layoutSeq: layout),
          isFalse,
        );
        expect(
          db.markDerivedIfUnchanged(
            restamped,
            derivedSeq: 'x',
            layoutSeq: layout,
          ),
          isTrue,
        );
      },
    );

    test('the child-stamp arm: fresh, a child write, the child gone', () async {
      route(blueberry, 0, dough);
      expect(db.hasUnderivedRows(blueberry.id), isFalse);
      expect(fresh(blueberry), isTrue);
      await matchAndCompute(db, provider, dough);
      expect(db.hasUnderivedRows(blueberry.id), isTrue);
      expect(fresh(blueberry), isFalse);
      expect(bulkScopeIds(db, BulkScope.stale), [blueberry.id]);
      deleteRecipe(db, config, dough.id);
      expect(db.nutritionFor(dough.id), isNull);
      expect(db.hasUnderivedRows(blueberry.id), isTrue);
    });
  });

  test(
    'parents last on the DOCUMENT in every scope: cheesy-nachos after '
    'chunky-guacamole in missing, all and stale',
    skip: skipIfNoCorpus,
    () async {
      // By id the parent (0471, line 6 "1 recipe Chunky Guacamole (see this
      // page)") sorts before its child (0472).
      final nachos = store('0471-cheesy-nachos-with-guacamole-and-salsa.yaml');
      final guacamole = store('0472-chunky-guacamole.yaml');
      final crust = store('0977-graham-cracker-crust.yaml');
      expect(nachos.id.compareTo(guacamole.id), lessThan(0));
      void parentsLast(List<String> ids) {
        expect(ids, containsAll([nachos.id, guacamole.id]));
        expect(ids.indexOf(nachos.id), greaterThan(ids.indexOf(guacamole.id)));
        expect(ids.last, nachos.id);
      }

      // A fresh import: no stored row names a child yet.
      parentsLast(bulkScopeIds(db, BulkScope.missing));
      parentsLast(bulkScopeIds(db, BulkScope.all));
      for (final recipe in [nachos, guacamole, crust]) {
        await matchAndCompute(db, provider, recipe);
      }
      expect(bulkScopeIds(db, BulkScope.missing), isEmpty);
      parentsLast(bulkScopeIds(db, BulkScope.all));
      reorder(nachos, 0, 1);
      reorder(guacamole, 0, 1);
      expect(bulkScopeIds(db, BulkScope.stale), [guacamole.id, nachos.id]);
    },
  );

  group('one stale sweep closes a child change', skip: skipIfNoCorpus, () {
    late Recipe crust;
    late List<Recipe> parents;

    setUp(() async {
      crust = store('0977-graham-cracker-crust.yaml');
      parents = [
        store('0980-summer-berry-pie.yaml'),
        store('0989-key-lime-pie.yaml'),
        store('0991-coconut-cream-pie.yaml'),
      ];
      for (final recipe in [crust, ...parents]) {
        await matchAndCompute(db, provider, recipe);
      }
      for (final (parent, position) in [
        (parents[0], 7),
        (parents[1], 3),
        (parents[2], 9),
      ]) {
        route(parent, position, crust);
      }
      for (final recipe in [crust, ...parents]) {
        expect(fresh(recipe), isTrue, reason: recipe.slug);
      }
    });

    test(
      'the arm by a real action: a serving-basis rebase of the crust',
      () async {
        // The shipped PUT …/nutrition {serving_basis} writes rebaseNutrition:
        // the crust's computed_at moves, its totals do not.
        rebaseNutrition(db, crust.id, 4);
        expect(fresh(crust), isTrue);
        for (final parent in parents) {
          expect(fresh(parent), isFalse, reason: '${parent.slug} at once');
        }
        expect(
          bulkScopeIds(db, BulkScope.stale),
          [for (final parent in parents) parent.id]..sort(),
        );
        final before = calls();
        await sweep(BulkScope.stale);
        expect(calls(), before, reason: 'cache-only: 0 FDC calls');
        for (final recipe in [crust, ...parents]) {
          expect(fresh(recipe), isTrue, reason: recipe.slug);
        }
        expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
      },
    );

    test("the stale append by a real hash edit: the crust's own lines 1 and "
        '2 reordered', () async {
      reorder(crust, 1, 2);
      // At scope time only the crust is stale (its hash); its parents still
      // hold its OLD computed_at and read fresh — the append brings them.
      expect(fresh(crust), isFalse);
      for (final parent in parents) {
        expect(fresh(parent), isTrue, reason: parent.slug);
      }
      expect(bulkScopeIds(db, BulkScope.stale), [
        crust.id,
        ...[for (final parent in parents) parent.id]..sort(),
      ]);
      final before = calls();
      await sweep(BulkScope.stale);
      expect(calls(), before, reason: 'cache-only: 0 FDC calls');
      for (final recipe in [crust, ...parents]) {
        expect(fresh(recipe), isTrue, reason: recipe.slug);
      }
    });
  });

  test(
    'a food decision never reaches a recipe row: the real "barbecue sauce" '
    'collision',
    skip: skipIfNoCorpus,
    () {
      // brisket|12 "3 cups barbecue sauce, warmed" is a food (auto, 174523 on
      // snapshot 17); indoor-pulled-chicken|7 and barbecued-pulled-pork|4
      // are reference lines on the same key, held choose_recipe in v41
      // (design_v3 §2.0 S18): the row shape §2.2 item 3 gives a held line.
      final brisket = store(
        '0595-barbecued-whole-beef-brisket-with-spicy-chili-rub.yaml',
      );
      for (final (fileName, position) in [
        ('0129-indoor-pulled-chicken.yaml', 7),
        ('0609-barbecued-pulled-pork.yaml', 4),
      ]) {
        final recipe = store(fileName);
        final raw = nutritionLines(recipe)[position].raw;
        expect(isSubRecipeReference(raw), isTrue, reason: raw);
        db.upsertIngredientMatch(
          IngredientMatchRow(
            recipeId: recipe.id,
            position: position,
            raw: raw,
            fdcId: null,
            description: null,
            dataType: null,
            confidence: 1,
            grams: 0,
            gramSource: SaltDatabase.recipeGramSource,
            status: 'auto',
            itemKey: 'barbecue sauce',
            hold: 'choose_recipe',
          ),
        );
      }
      expect(
        db.undecidedMatchesForItemKey(
          'barbecue sauce',
          excluding: (recipeId: brisket.id, position: 12),
          belowConfidence: confidenceGateFloor,
          fdcId: 174523,
        ),
        isEmpty,
      );
      expect(
        db.undecidedMatchesForItemKey(
          'barbecue sauce',
          excluding: (recipeId: brisket.id, position: 12),
          belowConfidence: confidenceGateFloor,
        ),
        isEmpty,
      );
    },
  );
}
