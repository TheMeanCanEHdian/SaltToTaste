import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/recipe_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/fdc_provider.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

void main() {
  group('normalizeItem', () {
    test('strips noise from real corpus items', () {
      expect(
        normalizeItem('(1 1/2 sticks) unsalted butter'),
        'without salt butter',
        reason: "FDC's salt-state vocabulary",
      );
      expect(
        normalizeItem('unbleached all-purpose flour'),
        'all-purpose flour',
      );
      expect(
        normalizeItem('instant espresso powder (optional)'),
        'instant espresso powder',
      );
      expect(normalizeItem('Confectioners’ sugar'), 'powdered sugar');
      expect(normalizeItem('bittersweet chocolate'), 'dark chocolate');
    });

    test('water never costs an FDC request', () {
      expect(isWaterLike(normalizeItem('boiling water')), isTrue);
      expect(isWaterLike(normalizeItem('milk')), isFalse);
    });

    test('strips preparation words so the food noun leads the query', () {
      // These are the real wrong-match culprits: the prep token was matching
      // a different food ("minced" -> Ham, "chopped ... " deflating the score).
      expect(normalizeItem('minced fresh oregano'), 'oregano');
      expect(normalizeItem('chopped fresh chives'), 'chives');
      expect(normalizeItem('sliced almonds'), 'almonds');
      // size/vessel + prep all drop, leaving the food (the leading count digit
      // is harmless — search ignores it).
      expect(normalizeItem('1 large onion, chopped coarse'), '1 onion');
      expect(normalizeItem('1 small head escarole'), '1 escarole');
    });

    test('keeps identity-changing words (not every adjective is prep)', () {
      // "leaves"/"cut"/"cooked" stay — dropping them changes the food.
      expect(normalizeItem('bay leaves'), 'bay leaves');
      expect(normalizeItem('cooked ham'), 'cooked ham');
    });
  });

  group('rankCandidates form-change penalty', () {
    FdcCandidate food(String description, String dataType) => FdcCandidate(
      fdcId: description.hashCode,
      description: description,
      dataType: dataType,
    );

    test('a base-form change loses to the whole food', () {
      final ranked = rankCandidates('almonds', [
        food('Flour, almond', 'Foundation'),
        food('Nuts, almonds, whole, raw', 'SR Legacy'),
      ]);
      expect(
        ranked.first.candidate.description,
        'Nuts, almonds, whole, raw',
        reason: '"almonds" is not "almond flour"',
      );
    });

    test('the form still wins when the query asks for it', () {
      final ranked = rankCandidates('almond flour', [
        food('Flour, almond', 'Foundation'),
        food('Nuts, almonds, whole, raw', 'SR Legacy'),
      ]);
      expect(ranked.first.candidate.description, 'Flour, almond');
    });
  });

  group('resolveGrams on real corpus lines', skip: skipIfNoCorpus, () {
    late Recipe bundt;

    setUpAll(() {
      bundt = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
    });

    IngredientLine line(String contains) =>
        nutritionLines(bundt).firstWhere((line) => line.raw.contains(contains));

    test('dual-amount flour uses the printed weight directly', () {
      final resolution = resolveGrams(
        amounts: line('all-purpose flour').amounts,
        food: null,
        normalizedItem: 'all-purpose flour',
      )!;
      expect(resolution.source, GramSource.weight);
      expect(resolution.grams, closeTo(8.75 * 28.3495, 0.1)); // 248.06 g
    });

    test('dual-amount brown sugar uses the printed weight directly', () {
      final resolution = resolveGrams(
        amounts: line('light brown sugar').amounts,
        food: null,
        normalizedItem: 'packed light brown sugar',
      )!;
      expect(resolution.source, GramSource.weight);
      expect(resolution.grams, closeTo(14 * 28.3495, 0.1)); // 396.9 g
    });

    test('sour cream volume falls back to the density table', () {
      final resolution = resolveGrams(
        amounts: line('sour cream').amounts,
        food: null,
        normalizedItem: 'sour cream',
      )!;
      expect(resolution.source, GramSource.density);
      expect(resolution.grams, closeTo(236.588 * 0.97, 1));
    });

    test('five large eggs resolve by piece weight', () {
      final resolution = resolveGrams(
        amounts: line('large eggs').amounts,
        food: null,
        normalizedItem: 'large eggs',
      )!;
      expect(resolution.source, GramSource.piece);
      expect(resolution.grams, 250);
    });

    test('amount-less garnish resolves to nothing', () {
      expect(
        resolveGrams(
          amounts: line('Confectioners').amounts,
          food: null,
          normalizedItem: 'powdered sugar',
        ),
        isNull,
      );
    });
  });

  group(
    'end-to-end compute against recorded real FDC data',
    skip: skipIfNoCorpus,
    () {
      late Directory tempDir;
      late ServerConfig config;
      late SaltDatabase db;
      late FixtureProvider provider;
      late Recipe bundt;

      setUpAll(() async {
        tempDir = Directory.systemTemp.createTempSync('salt-nutrition-test');
        config = ServerConfig(
          dataDir: tempDir.path,
          logLevel: Level.WARNING,
          trustProxy: false,
        );
        db = SaltDatabase.open(config.dbPath);
        // Seed the two fixture recipes through the real import path.
        final sourceRoot = Directory('${tempDir.path}/source')
          ..createSync(recursive: true);
        Directory('${sourceRoot.path}/recipes').createSync();
        for (final name in [
          '0857-rich-chocolate-bundt-cake.yaml',
          '0747-100-percent-whole-wheat-pancakes.yaml',
        ]) {
          File(
            '$corpusRecipesDir/$name',
          ).copySync('${sourceRoot.path}/recipes/$name');
        }
        importSourceRoot(
          sourceRootPath: sourceRoot.path,
          db: db,
          config: config,
        );
        provider = FixtureProvider();
        bundt = db.recipeByIdOrSlug('rich-chocolate-bundt-cake')!.recipe;
        await matchAndCompute(db, provider, bundt);
      });

      tearDownAll(() {
        db.dispose();
        tempDir.deleteSync(recursive: true);
      });

      test(
        'the Bundt cake label is plausible; the review flow completes it',
        () async {
          var row = db.nutritionFor(bundt.id)!;
          // Honestly partial out of the box: the amount-less garnish line
          // needs a human decision — the match-transparency badge the design
          // promises ("12/13 matched — review").
          expect(row.status, 'partial');
          expect(row.servingBasis, 12, reason: 'SERVES 12');
          expect(row.totalCount, 13);
          expect(row.matchedCount, 12, reason: 'espresso now has a density');

          // The review flow: skip the garnish, hand-set the espresso grams.
          final matches = db.ingredientMatchesFor(bundt.id);
          final garnish = matches.firstWhere(
            (match) => match.raw.contains('Confectioners'),
          );
          db.upsertIngredientMatch(garnish.copyWith(status: 'skipped'));
          final espresso = matches.firstWhere(
            (match) => match.raw.contains('espresso'),
          );
          db.upsertIngredientMatch(
            espresso.copyWith(
              grams: 2,
              gramSource: 'override',
              status: 'overridden',
            ),
          );
          await recomputeTotals(db, provider, bundt);
          row = db.nutritionFor(bundt.id)!;
          expect(row.status, 'complete');
          expect(row.matchedCount, 12);

          // A 1/12 slice of a rich chocolate bundt cake: the ballpark is
          // 350–650 kcal. Tighter bounds would pin FDC data, not our math.
          final calories = row.caloriesPerServing;
          expect(calories, isNotNull);
          expect(calories, greaterThan(350));
          expect(calories, lessThan(650));

          final perServing =
              jsonDecode(row.nutrientsJson) as Map<String, dynamic>;
          final fat = perServing['fat'] as Map<String, dynamic>;
          final carbs = perServing['carbs'] as Map<String, dynamic>;
          expect((fat['amount'] as num).toDouble(), greaterThan(10));
          expect((carbs['amount'] as num).toDouble(), greaterThan(30));
          expect(fat['dv_percent'], isNotNull);
          expect(perServing['sodium'], isNotNull);
          expect(perServing['protein'], isNotNull);
        },
      );

      test('flour and sugar matched by their printed weights (P6 gate)', () {
        final matches = db.ingredientMatchesFor(bundt.id);
        final flour = matches.firstWhere(
          (row) => row.raw.contains('all-purpose flour'),
        );
        expect(flour.gramSource, 'weight');
        expect(flour.grams, closeTo(248.06, 0.1));
        expect(flour.description, contains('Flour, wheat, all-purpose'));

        final sugar = matches.firstWhere(
          (row) => row.raw.contains('light brown sugar'),
        );
        expect(sugar.gramSource, 'weight');
        expect(sugar.grams, closeTo(396.9, 0.1));
        expect(sugar.description, contains('Sugars, brown'));
      });

      test('boiling water was matched locally, costing no request', () {
        final matches = db.ingredientMatchesFor(bundt.id);
        final water = matches.firstWhere(
          (row) => row.raw.contains('boiling water'),
        );
        expect(water.fdcId, isNull);
        expect(water.status, 'confirmed');
        expect(water.description, contains('Water'));
      });

      test('user overrides survive a full re-match', () async {
        await matchAndCompute(db, provider, bundt);
        final after = db
            .ingredientMatchesFor(bundt.id)
            .firstWhere((row) => row.raw.contains('espresso'));
        expect(
          after.status,
          'overridden',
          reason: 'the review decision from the previous test stands',
        );
        expect(after.grams, 2);
        final garnish = db
            .ingredientMatchesFor(bundt.id)
            .firstWhere((row) => row.raw.contains('Confectioners'));
        expect(garnish.status, 'skipped');
      });

      test('search cache makes the second compute request-free', () async {
        final callsBefore = provider.searchCalls;
        final pancakes = db
            .recipeByIdOrSlug('100-percent-whole-wheat-pancakes')!
            .recipe;
        await matchAndCompute(db, provider, pancakes);
        final callsAfterFirst = provider.searchCalls;
        expect(callsAfterFirst, greaterThan(callsBefore));

        // Force re-resolution of auto rows: statuses stay auto, so a second
        // pass re-ranks — but every search must come from the cache.
        await matchAndCompute(db, provider, pancakes);
        expect(provider.searchCalls, callsAfterFirst);
      });

      test('serving basis change recomputes instantly and rescales', () async {
        final before = db.nutritionFor(bundt.id)!;
        await recomputeTotals(db, provider, bundt, servingBasis: 6);
        final after = db.nutritionFor(bundt.id)!;
        expect(after.servingBasis, 6);
        expect(
          after.caloriesPerServing,
          closeTo(before.caloriesPerServing! * 2, 1),
        );
        await recomputeTotals(db, provider, bundt, servingBasis: 12);
      });

      test(
        'the calories: search filter and ordering go live (P6 gate)',
        () async {
          final pancakes = db
              .recipeByIdOrSlug('100-percent-whole-wheat-pancakes')!
              .recipe;
          final bundtCalories = db.nutritionFor(bundt.id)!.caloriesPerServing!;
          final pancakeCalories = db
              .nutritionFor(pancakes.id)!
              .caloriesPerServing!;
          expect(
            pancakeCalories,
            lessThan(bundtCalories),
            reason: 'a pancake serving beats a bundt slice',
          );

          // Between the two values: exactly one hit.
          final threshold = (bundtCalories + pancakeCalories) / 2;
          final below = await listRecipes(
            db,
            page: 1,
            limit: 24,
            query: 'calories:<${threshold.round()}',
          );
          expect(below['total'], 1);

          // Everything computed, ordered ascending by calories.
          final all = await listRecipes(
            db,
            page: 1,
            limit: 24,
            query: 'calories:<100000',
          );
          expect(all['total'], 2);
          final items = (all['items']! as List).cast<Map<String, dynamic>>();
          expect(items.first['slug'], '100-percent-whole-wheat-pancakes');
          expect(
            (items.first['calories_per_serving'] as num).toDouble(),
            closeTo(pancakeCalories, 0.01),
          );

          // Combined with a text term.
          final combined = await listRecipes(
            db,
            page: 1,
            limit: 24,
            query: 'chocolate and calories:<100000',
          );
          expect(combined['total'], 1);

          // Stale detection: dropping a line changes the ingredients hash.
          final trimmedGroup = IngredientGroup(
            items: bundt.ingredients.first.items.sublist(0, 5),
          );
          final edited = bundt.copyWith(ingredients: [trimmedGroup]);
          expect(
            ingredientsHashOf(edited) == ingredientsHashOf(bundt),
            isFalse,
          );
        },
      );

      test('text-only search results still carry the calorie badge', () async {
        final result = await listRecipes(
          db,
          page: 1,
          limit: 24,
          query: 'chocolate',
        );
        final items = (result['items']! as List).cast<Map<String, dynamic>>();
        final hit = items.singleWhere(
          (item) => item['slug'] == 'rich-chocolate-bundt-cake',
        );
        expect(
          hit['calories_per_serving'],
          isNotNull,
          reason: 'no calories: filter, but the tile badge needs the value',
        );
      });

      test('cache-only candidates never touch the provider', () async {
        final flourLine = nutritionLines(
          bundt,
        ).firstWhere((line) => line.raw.contains('all-purpose flour'));
        final callsBefore = provider.searchCalls;
        final candidates = await candidatesForLine(
          db,
          provider,
          flourLine,
          cacheOnly: true,
        );
        expect(candidates, isNotEmpty, reason: 'compute cached this search');
        expect(provider.searchCalls, callsBefore);
      });

      test('a recompute after an ingredient edit keeps reporting stale '
          '(review HIGH)', () async {
        // The admin deletes the last ingredient line, then changes the
        // serving basis WITHOUT recomputing: the label must stay stale and
        // the orphaned match row must not contribute.
        final storedBefore = db.nutritionFor(bundt.id)!;
        final items = bundt.ingredients.first.items;
        final edited = bundt.copyWith(
          ingredients: [
            IngredientGroup(items: items.sublist(0, items.length - 1)),
          ],
        );
        await recomputeTotals(db, provider, edited, servingBasis: 12);
        final after = db.nutritionFor(bundt.id)!;
        expect(after.totalCount, items.length - 1);
        expect(
          after.matchedCount,
          lessThanOrEqualTo(after.totalCount),
          reason: 'the orphaned row must not count (no "13/12 matched")',
        );
        expect(
          after.ingredientsHash,
          storedBefore.ingredientsHash,
          reason: 'only a full re-match may clear staleness',
        );
        expect(after.ingredientsHash, isNot(ingredientsHashOf(edited)));

        // A real recompute clears it and drops the orphan row.
        await matchAndCompute(db, provider, edited);
        final fresh = db.nutritionFor(bundt.id)!;
        expect(fresh.ingredientsHash, ingredientsHashOf(edited));
        expect(
          db.ingredientMatchesFor(bundt.id).length,
          items.length - 1,
        );
      });
    },
  );

  group('TokenBucket', () {
    test('a capped wait gives up fast once the budget is drained', () async {
      final bucket = TokenBucket(capacity: 1);
      expect(await bucket.acquire(maxWait: const Duration(seconds: 5)), isTrue);
      final watch = Stopwatch()..start();
      final granted = await bucket.acquire(
        maxWait: const Duration(milliseconds: 100),
      );
      expect(granted, isFalse);
      expect(
        watch.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason: 'must not wait out the hour-long window',
      );
    });

    test('an uncapped wait rides out the window (bulk behavior)', () async {
      final bucket = TokenBucket(
        capacity: 1,
        window: const Duration(milliseconds: 150),
      );
      expect(await bucket.acquire(), isTrue);
      expect(
        await bucket.acquire(),
        isTrue,
        reason: 'waits ~150ms for the window to roll, then succeeds',
      );
    });
  });

  group('portion description matching', () {
    // Synthesized provider data (negative path): a portion whose measure
    // unit is undetermined, where FDC packs the amount into the free-text
    // description — and one where no amount exists at all.
    const nutrients = {'208': 400.0};

    test('a parseable leading amount scales the weight', () {
      const food = FdcFood(
        fdcId: 1,
        description: 'synthetic',
        dataType: 'SR Legacy',
        nutrientsPer100g: nutrients,
        portions: [
          FdcPortion(gramWeight: 60, description: '0.25 cup, sifted'),
        ],
      );
      final resolution = resolveGrams(
        amounts: const [
          Amount(quantity: '1', unit: 'cup', measure: Measure.volume),
        ],
        food: food,
        normalizedItem: 'no-density-entry item',
      )!;
      expect(resolution.source, GramSource.portion);
      expect(
        resolution.grams,
        closeTo(240, 0.01),
        reason: '60 g per quarter cup → 240 g per cup',
      );
    });

    test('no parseable amount → the portion is not trusted', () {
      const food = FdcFood(
        fdcId: 2,
        description: 'synthetic',
        dataType: 'SR Legacy',
        nutrientsPer100g: nutrients,
        portions: [
          FdcPortion(gramWeight: 60, description: 'cup, sifted'),
        ],
      );
      final resolution = resolveGrams(
        amounts: const [
          Amount(quantity: '1', unit: 'cup', measure: Measure.volume),
        ],
        food: food,
        normalizedItem: 'no-density-entry item',
      );
      expect(
        resolution,
        isNull,
        reason: 'gramWeight-per-unknown-amount is a guess, not data',
      );
    });
  });

  // The admin's manual escape hatch when the matcher searched the wrong words
  // and every auto-found candidate is wrong. Needs no corpus — just the
  // recorded real FDC responses.
  group('searchCandidates (admin manual re-pick)', () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('salt-fdc-search-test');
      db = SaltDatabase.open('${tempDir.path}/salt.db');
      provider = FixtureProvider();
    });

    tearDown(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('ranks recorded real FDC results for a typed term', () async {
      final results = await searchCandidates(db, provider, 'sour cream');
      expect(results, isNotEmpty);
      expect(results.length, lessThanOrEqualTo(8), reason: 'top 8 only');
      for (var i = 1; i < results.length; i++) {
        expect(
          results[i - 1].confidence,
          greaterThanOrEqualTo(results[i].confidence),
          reason: 'ranked best-first',
        );
      }
      expect(
        results.first.candidate.description.toLowerCase(),
        contains('cream'),
      );
    });

    test(
      'a repeated term is served from the cache, spending no FDC budget',
      () async {
        await searchCandidates(db, provider, 'sour cream');
        final calls = provider.searchCalls;
        expect(calls, greaterThan(0));
        await searchCandidates(db, provider, 'sour cream');
        expect(
          provider.searchCalls,
          calls,
          reason: 'the second search must hit fdc_search_cache',
        );
      },
    );

    test('a blank term never reaches the provider', () async {
      final calls = provider.searchCalls;
      expect(await searchCandidates(db, provider, '   '), isEmpty);
      expect(provider.searchCalls, calls);
    });
  });

  // Lets a reviewer verify a volume/piece estimate ran against the right
  // amount. Pure resolver math — no corpus, no DB.
  group('GramResolution.basis', () {
    test('a volume density estimate reports the volume it ran against', () {
      final resolution = resolveGrams(
        amounts: const [
          Amount(measure: Measure.volume, quantity: '1/2', unit: 'cup'),
        ],
        food: null,
        normalizedItem: 'oil',
      )!;
      expect(resolution.source, GramSource.density);
      expect(resolution.basis, '1/2 cup ≈ 118 mL');
    });

    test('a direct weight reports the weight used', () {
      final resolution = resolveGrams(
        amounts: const [
          Amount(measure: Measure.weight, quantity: '8', unit: 'oz'),
        ],
        food: null,
        normalizedItem: 'anything',
      )!;
      expect(resolution.source, GramSource.weight);
      expect(resolution.basis, 'from 8 oz');
    });
  });
}
