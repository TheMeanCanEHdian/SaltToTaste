import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
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

  group('rankCandidates concentrate penalty', () {
    FdcCandidate food(String description, String dataType) => FdcCandidate(
      fdcId: description.hashCode,
      description: description,
      dataType: dataType,
    );

    test('a broth prefers the ready liquid over a dry cube', () {
      // Real FDC descriptions. "cubes" is the case the plural stemmer mangles
      // to "cub", so a token-set penalty would have missed it — hence the
      // substring marker.
      final ranked = rankCandidates('chicken broth', [
        food('Soup, chicken broth cubes, dry', 'SR Legacy'),
        food('Soup, chicken broth, ready-to-serve', 'SR Legacy'),
      ]);
      expect(
        ranked.first.candidate.description,
        'Soup, chicken broth, ready-to-serve',
        reason: 'a dry bouillon cube is not 8 cups of ready broth',
      );
    });

    test('the penalty is gated by the query naming the form', () {
      final bouillon = food(
        'Soup, chicken broth or bouillon, dry',
        'SR Legacy',
      );
      final named = rankCandidates('chicken bouillon', [bouillon]).first;
      final unnamed = rankCandidates('chicken broth', [bouillon]).first;
      expect(
        named.confidence,
        greaterThan(unnamed.confidence),
        reason: 'naming "bouillon" keeps the concentrate penalty off',
      );
    });

    test('a dry-only food (cocoa powder) is not sunk below the gate', () {
      // Cocoa only exists as a dry powder — the penalty must NOT touch it, or
      // it stops counting toward the label (the < 0.5 gate).
      final ranked = rankCandidates('natural cocoa powder', [
        food('Cocoa, dry powder, unsweetened', 'SR Legacy'),
      ]);
      expect(
        ranked.first.candidate.description,
        'Cocoa, dry powder, unsweetened',
      );
      expect(ranked.first.confidence, greaterThanOrEqualTo(0.5));
    });
  });

  group('rankCandidates meat-analog / dish penalty', () {
    FdcCandidate food(String description, String dataType) => FdcCandidate(
      fdcId: description.hashCode,
      description: description,
      dataType: dataType,
    );

    test('a meat analog loses to the real meat', () {
      final ranked = rankCandidates('bacon', [
        food('Bacon, meatless', 'SR Legacy'),
        food('Pork, cured, bacon, unprepared', 'SR Legacy'),
      ]);
      expect(
        ranked.first.candidate.description,
        'Pork, cured, bacon, unprepared',
        reason: '"bacon" is pork, not a soy analog',
      );
    });

    test('a prepared dish loses to the raw ingredient', () {
      final ranked = rankCandidates('ginger', [
        food('Tea, ginger', 'Survey (FNDDS)'),
        food('Ginger root, raw', 'SR Legacy'),
      ]);
      expect(ranked.first.candidate.description, 'Ginger root, raw');
    });

    test('the penalty is gated when the query names the analog', () {
      final analog = food('Hot dog, vegetarian', 'Survey (FNDDS)');
      final named = rankCandidates('vegetarian hot dog', [analog]).first;
      final unnamed = rankCandidates('hot dog', [analog]).first;
      expect(
        named.confidence,
        greaterThan(unnamed.confidence),
        reason: 'naming "vegetarian" keeps the analog penalty off',
      );
    });

    test(
      'an FDC category word that files real ingredients is not penalized',
      () {
        // "graham cracker crust" → "Pie crust, …": `pie` is deliberately NOT a
        // marker (it files real crusts/shells), so the only good match keeps its
        // full score instead of being demoted below the review gate.
        final ranked = rankCandidates('graham cracker crust', [
          food(
            'Pie Crust, Cookie-type, Graham Cracker, Ready Crust',
            'SR Legacy',
          ),
        ]);
        expect(ranked.first.confidence, greaterThanOrEqualTo(0.75));
      },
    );
  });

  group('rankCandidates added meat-qualifier penalty', () {
    FdcCandidate food(String description, String dataType) => FdcCandidate(
      fdcId: description.hashCode,
      description: description,
      dataType: dataType,
    );

    test('a deli/lunchmeat cut loses to the raw cut', () {
      final ranked = rankCandidates('chicken breast', [
        food('Lunchmeat, chicken breast, sliced', 'Foundation'),
        food('Chicken, breast, boneless, skinless, raw', 'Foundation'),
      ]);
      expect(
        ranked.first.candidate.description,
        'Chicken, breast, boneless, skinless, raw',
        reason: '"chicken breast" wants the raw cut, not sliced deli meat',
      );
    });

    test('an added species loses to the default for a generic query', () {
      final ranked = rankCandidates('sausage', [
        food('Sausage, turkey, breakfast links', 'SR Legacy'),
        food('Pork sausage', 'SR Legacy'),
      ]);
      expect(ranked.first.candidate.description, 'Pork sausage');
    });

    test('the species penalty is gated when the query names it', () {
      final turkey = food('Sausage, turkey, links', 'SR Legacy');
      final named = rankCandidates('turkey sausage', [turkey]).first.confidence;
      final unnamed = rankCandidates('sausage', [turkey]).first.confidence;
      expect(
        named,
        greaterThan(unnamed),
        reason: 'naming "turkey" keeps the added-species penalty off',
      );
    });

    test('breakfast sausage beats a turkey link and a breakfast biscuit', () {
      // Real FDC results for "breakfast sausage": a raw turkey link (which also
      // takes the +raw form bonus) and a composite egg-and-cheese breakfast
      // biscuit both out-ranked the actual (pre-cooked) breakfast sausage. The
      // species dock must outweigh the raw/cooked swing, and the biscuit must
      // take the dish dock.
      final ranked = rankCandidates('breakfast sausage', [
        food('Sausage, turkey, breakfast links, mild, raw', 'Foundation'),
        food('Sausage, egg and cheese breakfast biscuit', 'SR Legacy'),
        food(
          'Sausage, breakfast sausage, beef, pre-cooked, unprepared',
          'Foundation',
        ),
      ]);
      expect(
        ranked.first.candidate.description,
        'Sausage, breakfast sausage, beef, pre-cooked, unprepared',
      );
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

  group(
    'match override keeps the printed parenthetical weight (review B3)',
    skip: skipIfNoCorpus,
    () {
      late Directory tempDir;
      late SaltDatabase db;
      late FixtureProvider provider;
      late Recipe chili;
      late int tomatoPosition;

      setUpAll(() async {
        tempDir = Directory.systemTemp.createTempSync('salt-override-test');
        final config = ServerConfig(
          dataDir: tempDir.path,
          logLevel: Level.WARNING,
          trustProxy: false,
        );
        db = SaltDatabase.open(config.dbPath);
        final sourceRoot = Directory('${tempDir.path}/source')
          ..createSync(recursive: true);
        Directory('${sourceRoot.path}/recipes').createSync();
        const name = '0009-best-ground-beef-chili.yaml';
        File(
          '$corpusRecipesDir/$name',
        ).copySync('${sourceRoot.path}/recipes/$name');
        importSourceRoot(
          sourceRootPath: sourceRoot.path,
          db: db,
          config: config,
        );
        provider = FixtureProvider();
        chili = db.recipeByIdOrSlug('best-ground-beef-chili')!.recipe;
        tomatoPosition = nutritionLines(
          chili,
        ).indexWhere((line) => line.raw.contains('(14.5-ounce) can'));
        expect(tomatoPosition, greaterThanOrEqualTo(0));
      });

      tearDownAll(() {
        db.dispose();
        tempDir.deleteSync(recursive: true);
      });

      test(
        're-picking a food must not lose the printed-weight grams',
        () async {
          // "1 (14.5-ounce) can whole peeled tomatoes": the printed weight is
          // the gold-standard gram source, and it only resolves when the raw
          // line is passed through. The auto-match path and the gram_basis
          // display path both pass it; the override path once did not, so an
          // admin re-picking a better food silently dropped the grams.
          await applyMatchOverride(db, provider, chili, tomatoPosition, {
            'fdc_id': 746784, // any cached real FDC food; grams come from raw
          });
          final row = db
              .ingredientMatchesFor(chili.id)
              .singleWhere((match) => match.position == tomatoPosition);
          expect(row.status, 'overridden');
          expect(row.gramSource, 'weight');
          expect(row.grams, closeTo(14.5 * 28.3495, 0.1));
        },
      );

      test(
        'un-skip returns the line to automatic triage (review B7)',
        () async {
          // skipped:false must NOT bless the line as confirmed — that would
          // hide whatever match it had from the review queue as resolved.
          await applyMatchOverride(db, provider, chili, tomatoPosition, {
            'skipped': true,
          });
          expect(
            db
                .ingredientMatchesFor(chili.id)
                .singleWhere((match) => match.position == tomatoPosition)
                .status,
            'skipped',
          );
          await applyMatchOverride(db, provider, chili, tomatoPosition, {
            'skipped': false,
          });
          expect(
            db
                .ingredientMatchesFor(chili.id)
                .singleWhere((match) => match.position == tomatoPosition)
                .status,
            'auto',
          );
        },
      );
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

  // Slice 2: counted whole items resolve from the food's own portions (or a
  // table backfill), so "1 leek" / "6 ears corn" stop contributing nothing.
  group('count → whole-item portions', () {
    const nutrients = {'208': 20.0};

    GramResolution resolve(
      List<FdcPortion> portions,
      Amount amount, {
      String item = 'no-table-entry item',
    }) => resolveGrams(
      amounts: [amount],
      food: FdcFood(
        fdcId: 1,
        description: 'synthetic',
        dataType: 'Survey (FNDDS)',
        nutrientsPer100g: nutrients,
        portions: portions,
      ),
      normalizedItem: item,
      raw: 'x',
    )!;

    test("the amount's own unit matches the food portion (ears of corn)", () {
      final r = resolve(
        const [FdcPortion(gramWeight: 105, description: '1 regular ear')],
        const Amount(quantity: '6', unit: 'ear', measure: Measure.count),
      );
      expect(r.source, GramSource.piece);
      expect(r.grams, closeTo(630, 0.5)); // 6 × 105
    });

    test('a bare count prefers the medium whole-item portion', () {
      // Real FDC tortilla shape: several sizes plus a volume serving.
      final r = resolve(
        const [
          FdcPortion(gramWeight: 18, description: '1 small'),
          FdcPortion(gramWeight: 28, description: '1 medium'),
          FdcPortion(gramWeight: 44, description: '1 large'),
          FdcPortion(gramWeight: 150, description: '1 cup'),
        ],
        const Amount(quantity: '2', measure: Measure.count),
      );
      expect(r.grams, closeTo(56, 0.5)); // 2 × the "1 medium", not cup/large
    });

    test('a bare count skips the volume serving portions (leek)', () {
      final r = resolve(
        const [
          FdcPortion(gramWeight: 85, description: '1 whole'),
          FdcPortion(gramWeight: 170, description: '1 cup'),
          FdcPortion(gramWeight: 7, description: '1 slice'),
        ],
        const Amount(quantity: '2', measure: Measure.count),
      );
      expect(r.grams, closeTo(170, 0.5)); // 2 × "1 whole", never the cup
    });

    test('a Foundation reference-serving portion is NOT a whole item', () {
      // "amount=1, unit=racc, description=null" is a ~85 g serving weight, not
      // one cucumber — must fall through (here: to null, no table entry).
      final r = resolveGrams(
        amounts: const [Amount(quantity: '1', measure: Measure.count)],
        food: const FdcFood(
          fdcId: 1,
          description: 'synthetic',
          dataType: 'Foundation',
          nutrientsPer100g: nutrients,
          portions: [FdcPortion(gramWeight: 85, amount: 1, unit: 'racc')],
        ),
        normalizedItem: 'no-table-entry item',
      );
      expect(r, isNull);
    });

    test('the piece table backfills a portion-less food (fennel bulb)', () {
      final r = resolveGrams(
        amounts: const [Amount(quantity: '1', measure: Measure.count)],
        food: const FdcFood(
          fdcId: 1,
          description: 'Fennel, bulb, raw',
          dataType: 'Foundation',
          nutrientsPer100g: nutrients,
          portions: [],
        ),
        normalizedItem: 'fennel bulb',
      )!;
      expect(r.source, GramSource.piece);
      expect(r.grams, closeTo(200, 0.5));
      expect(r.basis, '1 × 200 g each');
    });

    test(
      'a container-unit count does not borrow a table whole-item weight',
      () {
        // "1 can diced tomatoes" must NOT resolve to one 123 g tomato — a can's
        // weight comes from its printed size, else the line is left for review.
        final r = resolveGrams(
          amounts: const [
            Amount(quantity: '1', unit: 'can', measure: Measure.count),
          ],
          food: null,
          normalizedItem: 'diced tomatoes',
        );
        expect(r, isNull);
      },
    );

    test('a multi-unit or dish-serving portion is left null', () {
      // "10 sprigs" (count > 1) and a large "1 piece"/"1 serving" dish serving
      // on a wrong-food match are all rejected as "one item".
      for (final portions in const [
        [FdcPortion(gramWeight: 10, description: '10 sprigs')],
        [
          FdcPortion(gramWeight: 256, description: '1 piece'),
          FdcPortion(gramWeight: 227, description: '1 serving'),
        ],
      ]) {
        final r = resolveGrams(
          amounts: const [Amount(quantity: '1', measure: Measure.count)],
          food: FdcFood(
            fdcId: 1,
            description: 'wrong-food match',
            dataType: 'Survey (FNDDS)',
            nutrientsPer100g: nutrients,
            portions: portions,
          ),
          normalizedItem: 'no-table-entry item',
        );
        expect(r, isNull);
      }
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

  // Workstream A slice 1: use the weight printed in a raw parenthetical that
  // the amount parse dropped — a big chunk of the "matched but no grams" lines.
  group('resolveGrams parenthetical weight', () {
    GramResolution resolve(String raw, String qty) => resolveGrams(
      amounts: [Amount(measure: Measure.count, quantity: qty)],
      food: null,
      normalizedItem: 'x',
      raw: raw,
    )!;

    test('a per-unit weight scales by the count', () {
      final r = resolve('4 (5 to 6-ounce) skinless chicken breasts', '4');
      expect(r.source, GramSource.weight);
      expect(r.grams, closeTo(4 * 5.5 * 28.3495, 1)); // 623.7 g
    });

    test('a single item uses the parenthetical as the total', () {
      final r = resolve('1 medium russet potato (about 8 ounces), peeled', '1');
      expect(r.grams, closeTo(8 * 28.3495, 1)); // 226.8 g
    });

    test('a can size scales by the number of cans', () {
      final r = resolve('2 (15-ounce) cans cannellini beans, drained', '2');
      expect(r.grams, closeTo(2 * 15 * 28.3495, 1)); // 850.5 g
      // The count reads as a plain integer, not "2.0".
      expect(r.basis, '2 × 425 g (printed weight)');
    });

    test('a trailing total on a counted line is NOT scaled by the count', () {
      // Real corpus line: "(9 ounces)" is the TOTAL weight of the 5 slices, not
      // per slice. Scaling by the count read it as 5× (~1276 g, a real bug).
      final r = resolve(
        '5 (¾-inch-thick) slices rustic, crusty bread (9 ounces), cubed',
        '5',
      );
      expect(r.grams, closeTo(9 * 28.3495, 1)); // 255 g total, not 5 × 255
      expect(r.basis, 'from the printed weight');
    });

    test('an explicit per-item "(… each)" still scales', () {
      final r = resolve('4 chicken thighs (6 ounces each), trimmed', '4');
      expect(r.grams, closeTo(4 * 6 * 28.3495, 1)); // 680.4 g
    });

    test('no parenthetical weight falls through to the estimate paths', () {
      final r = resolveGrams(
        amounts: const [Amount(measure: Measure.count, quantity: '1')],
        food: null,
        normalizedItem: 'unknown item with no table entry',
        raw: '1 whatever, chopped',
      );
      expect(r, isNull);
    });
  });

  group('resolveGrams ground-spice densities', () {
    // FDC files spices as "Spices, X" with tsp/tbsp portions, but their measure
    // unit is "undetermined" and the unit sits in an amount-less description,
    // so the portion matcher can't use them — a volume spice line resolved to
    // nothing. The density table now covers them (values back-derived from
    // FDC's own 1-tsp gram weight, so these reproduce it).
    double? g(String unit, String item) => resolveGrams(
      amounts: [Amount(quantity: '1', unit: unit, measure: Measure.volume)],
      food: null,
      normalizedItem: normalizeItem(item),
      raw: '1 $unit $item',
    )?.grams;

    test('common ground spices resolve to ~their FDC 1-tsp weight', () {
      expect(g('teaspoon', 'ground cinnamon'), closeTo(2.6, 0.15));
      expect(g('teaspoon', 'ground cumin'), closeTo(2.1, 0.15));
      expect(g('teaspoon', 'cayenne pepper'), closeTo(1.8, 0.15));
      expect(g('teaspoon', 'paprika'), closeTo(2.3, 0.15));
      expect(g('teaspoon', 'ground black pepper'), closeTo(2.3, 0.15));
      expect(g('teaspoon', 'garlic powder'), closeTo(3.1, 0.2));
      expect(g('tablespoon', 'chili powder'), closeTo(8.0, 0.3));
    });

    test('a dried herb keys off "dried"; a fresh sprig is left alone', () {
      expect(g('teaspoon', 'dried oregano'), closeTo(1.0, 0.1));
      // Fresh oregano has no key (would be wrong at the dried density), so it
      // stays unresolved rather than mis-sized.
      expect(g('tablespoon', 'chopped fresh oregano'), isNull);
    });

    test('ground ginger does not borrow the fresh-ginger density', () {
      // fresh 'ginger' is 0.54; ground is lighter (0.37).
      final fresh = g('tablespoon', 'grated fresh ginger')!;
      final ground = g('tablespoon', 'ground ginger')!;
      expect(ground, lessThan(fresh));
      expect(ground, closeTo(14.79 * 0.37, 0.3));
    });

    test('dry mustard does not borrow the prepared-mustard density', () {
      // prepared 'mustard' is 1.05 (a liquid); dry powder is 0.41.
      expect(g('teaspoon', 'Dijon mustard'), closeTo(4.929 * 1.05, 0.3));
      expect(g('teaspoon', 'dry mustard'), closeTo(4.929 * 0.41, 0.3));
    });
  });

  group('resolveGrams rustic bread (count-only)', () {
    // Real corpus items (rustic/country/crusty loaves) FDC gives no usable
    // per-slice/loaf portion for, counted with no printed weight — so they
    // resolved to nothing before. Slice ≈ 50 g, whole loaf ≈ 454 g.
    GramResolution? resolve(String qty, String? unit, String item) =>
        resolveGrams(
          amounts: [
            Amount(
              quantity: qty,
              unit: unit,
              measure: Measure.count,
              primary: true,
            ),
          ],
          food: null,
          normalizedItem: normalizeItem(item),
          raw: '$qty ${unit ?? ''} $item',
        );

    test('thick slices resolve at ~50 g each', () {
      expect(resolve('8', 'slice', 'country white bread')!.grams, 400);
      expect(resolve('4', 'slice', 'rustic white bread')!.grams, 200);
      final thick = resolve('10', 'slices', 'thick-crusted country bread');
      expect(thick!.grams, 500);
    });

    test('a whole loaf resolves at ~1 lb', () {
      expect(resolve('1', 'loaf', 'crusty bread')!.grams, 454);
      expect(resolve('1', 'loaf', 'country bread')!.grams, 454);
    });

    test('soft sandwich bread keeps its own 28 g/slice table entry', () {
      expect(resolve('6', 'slice', 'sandwich bread')!.grams, closeTo(168, 0.5));
    });

    test('a plain (non-rustic) bread is not over-applied', () {
      expect(resolve('2', 'slice', 'white bread'), isNull);
    });

    test('a real FDC slice portion still wins over the estimate', () {
      // If the matched food carries a "1 slice" portion, that authoritative
      // value is used, not the 50 g fallback.
      final r = resolveGrams(
        amounts: const [
          Amount(quantity: '4', unit: 'slice', measure: Measure.count),
        ],
        food: const FdcFood(
          fdcId: 1,
          description: 'Bread, rustic',
          dataType: 'SR Legacy',
          nutrientsPer100g: {'208': 250},
          portions: [FdcPortion(gramWeight: 40, description: '1 slice')],
        ),
        normalizedItem: 'rustic bread',
        raw: '4 slices rustic bread',
      );
      expect(r!.grams, closeTo(160, 0.5)); // 4 × 40, not 4 × 50
    });
  });

  // Lever 5: a likely-wrong low-confidence auto match must not silently feed
  // the label. No corpus needed — a synthetic recipe + a cached food.
  group('recomputeTotals holds low-confidence auto matches', () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;

    Recipe recipe() => const Recipe(
      id: 'r1',
      title: 'Test',
      slug: 'test',
      source: RecipeSource(name: 'Test', type: 'book'),
      ingredients: [
        IngredientGroup(
          items: [
            IngredientLine(raw: 'a', item: 'a'),
            IngredientLine(raw: 'b', item: 'b'),
          ],
        ),
      ],
    );

    IngredientMatchRow match(int pos, double conf, String status) =>
        IngredientMatchRow(
          recipeId: 'r1',
          position: pos,
          raw: pos == 0 ? 'a' : 'b',
          fdcId: 111,
          description: 'Food',
          dataType: 'SR Legacy',
          confidence: conf,
          grams: 100,
          gramSource: 'weight',
          status: status,
        );

    Future<void> recompute() =>
        recomputeTotals(db, provider, recipe(), servingBasis: 1);

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('salt-gate-test');
      db = SaltDatabase.open('${tempDir.path}/salt.db');
      provider = FixtureProvider();
      db.upsertSource(slug: 'src', name: 'Test', type: 'book');
      db.upsertRecipe(recipe(), sourceSlug: 'src', contentHash: 'h');
      // A cached food so the recompute never calls the provider.
      const food = FdcFood(
        fdcId: 111,
        description: 'Food',
        dataType: 'SR Legacy',
        nutrientsPer100g: {'203': 10, '204': 5, '205': 20, '208': 100},
        portions: [],
      );
      db.fdcFoodCachePut(111, jsonEncode(food.toJson()));
    });

    tearDown(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('a <0.5 auto match is held out until a human confirms it', () async {
      db.upsertIngredientMatch(match(0, 0.4, 'auto')); // held
      db.upsertIngredientMatch(match(1, 0.8, 'auto')); // counts
      await recompute();
      var row = db.nutritionFor('r1')!;
      expect(row.matchedCount, 1, reason: 'the 0.4 auto line is held out');
      expect(row.totalGrams, 100);
      expect(row.status, 'partial', reason: 'a held line leaves it incomplete');

      // Confirming it (status leaves 'auto') opts it back into the totals.
      db.upsertIngredientMatch(match(0, 0.4, 'confirmed'));
      await recompute();
      row = db.nutritionFor('r1')!;
      expect(row.matchedCount, 2);
      expect(row.totalGrams, 200);
      expect(row.status, 'complete');
    });
  });
}
