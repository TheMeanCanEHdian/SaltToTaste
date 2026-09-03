import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_server/src/services/item_key_backfill.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:test/test.dart';
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Cross-recipe reuse of human match decisions (review R1), over three real
/// corpus recipes that share ingredient items — the Bundt cake, the
/// whole-wheat pancakes and the caramel cake all carry `baking soda` and
/// `eggs` — and the recorded real FDC payloads.
///
/// The rule under test: a person's `confirmed`/`overridden` food on an item
/// in one recipe is inherited by every other recipe's line of that item at
/// compute time (most recent wins; skips never travel; a decision on the
/// inheriting line itself stands), and `apply_to_all` lands it on the other
/// recipes' undecided lines right away.
void main() {
  group('cross-recipe reuse of match decisions', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late ServerConfig config;
    late SaltDatabase db;
    late FixtureProvider provider;
    late Recipe bundt;
    late Recipe pancakes;
    late Recipe caramel;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-reuse-test');
      config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath);
      final sourceRoot = Directory('${tempDir.path}/source')
        ..createSync(recursive: true);
      Directory('${sourceRoot.path}/recipes').createSync();
      for (final name in [
        '0857-rich-chocolate-bundt-cake.yaml',
        '0747-100-percent-whole-wheat-pancakes.yaml',
        '0879-easy-caramel-cake.yaml',
      ]) {
        File(
          '$corpusRecipesDir/$name',
        ).copySync('${sourceRoot.path}/recipes/$name');
      }
      importSourceRoot(sourceRootPath: sourceRoot.path, db: db, config: config);
      provider = FixtureProvider();
      bundt = db.recipeByIdOrSlug('rich-chocolate-bundt-cake')!.recipe;
      pancakes = db
          .recipeByIdOrSlug('100-percent-whole-wheat-pancakes')!
          .recipe;
      caramel = db.recipeByIdOrSlug('easy-caramel-cake')!.recipe;
      for (final recipe in [bundt, pancakes, caramel]) {
        await matchAndCompute(db, provider, recipe);
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    int positionOf(Recipe recipe, String key) => nutritionLines(
      recipe,
    ).indexWhere((line) => normalizeItem(line.item ?? line.raw) == key);

    IngredientMatchRow rowOf(Recipe recipe, String key) {
      final position = positionOf(recipe, key);
      expect(position, isNonNegative, reason: '$key must be a real line');
      return db
          .ingredientMatchesFor(recipe.id)
          .firstWhere((row) => row.position == position);
    }

    /// A recorded, fetchable food other than [notThis] — the food a person
    /// would re-pick to. Preferably one of the line's own recorded candidates;
    /// the fixtures only hold the foods the engine fetched, so when a query
    /// recorded a single fetchable hit, any other recorded food stands in
    /// (the override endpoint accepts any food FDC can serve).
    Future<int> otherFoodFor(
      Recipe recipe,
      String key,
      Set<int> notThis,
    ) async {
      final line = nutritionLines(recipe)[positionOf(recipe, key)];
      final candidates = await candidatesForLine(
        db,
        provider,
        line,
        cacheOnly: true,
      );
      for (final candidate in candidates) {
        final id = candidate.candidate.fdcId;
        if (!notThis.contains(id) && await provider.food(id) != null) {
          return id;
        }
      }
      final recorded =
          jsonDecode(File('test/fixtures/fdc/foods.json').readAsStringSync())
              as Map<String, dynamic>;
      for (final id in recorded.keys.map(int.parse)) {
        if (!notThis.contains(id)) {
          return id;
        }
      }
      fail('no recorded food beyond $notThis');
    }

    Future<double?> ownGrams(Recipe recipe, String key, int fdcId) async {
      final line = nutritionLines(recipe)[positionOf(recipe, key)];
      return resolveGrams(
        amounts: line.amounts,
        food: await provider.food(fdcId),
        normalizedItem: key,
        raw: line.raw,
      )?.grams;
    }

    late int bakingSodaAlt;

    test('every engine row carries its item key', () {
      for (final recipe in [bundt, pancakes, caramel]) {
        final lines = nutritionLines(recipe);
        for (final row in db.ingredientMatchesFor(recipe.id)) {
          final line = lines[row.position];
          expect(row.itemKey, normalizeItem(line.item ?? line.raw));
        }
      }
    });

    test(
      "a person's decision on one recipe is inherited by another recipe's "
      'line of the same item at compute time, with its own grams',
      () async {
        final auto = rowOf(pancakes, 'baking soda');
        expect(auto.status, 'auto');
        bakingSodaAlt = await otherFoodFor(bundt, 'baking soda', {
          auto.fdcId!,
        });

        final applied = await applyMatchOverride(
          db,
          provider,
          bundt,
          positionOf(bundt, 'baking soda'),
          {'fdc_id': bakingSodaAlt},
        );
        expect(applied, isNull, reason: 'no apply_to_all asked for');
        await matchAndCompute(db, provider, pancakes);

        final inherited = rowOf(pancakes, 'baking soda');
        expect(inherited.fdcId, bakingSodaAlt);
        expect(
          inherited.status,
          'auto',
          reason: 'an engine write, not a decision',
        );
        expect(inherited.confidence, 1);
        expect(inherited.itemKey, 'baking soda');
        expect(
          inherited.grams,
          await ownGrams(pancakes, 'baking soda', bakingSodaAlt),
          reason: "grams come from THIS line's amounts, not the source line",
        );
      },
    );

    test('a skip does not travel', () async {
      await applyMatchOverride(db, provider, bundt, positionOf(bundt, 'eggs'), {
        'skipped': true,
      });
      await matchAndCompute(db, provider, pancakes);
      expect(rowOf(pancakes, 'eggs').status, isNot('skipped'));
    });

    test('the most recent decision wins', () async {
      final alt2 = await otherFoodFor(caramel, 'baking soda', {bakingSodaAlt});
      await applyMatchOverride(
        db,
        provider,
        caramel,
        positionOf(caramel, 'baking soda'),
        {'fdc_id': alt2},
      );
      await matchAndCompute(db, provider, pancakes);
      expect(rowOf(pancakes, 'baking soda').fdcId, alt2);
    });

    test('a decision on the inheriting line itself stands', () async {
      await applyMatchOverride(
        db,
        provider,
        pancakes,
        positionOf(pancakes, 'baking soda'),
        {'fdc_id': bakingSodaAlt},
      );
      final alt3 = await otherFoodFor(bundt, 'baking soda', {bakingSodaAlt});
      await applyMatchOverride(
        db,
        provider,
        bundt,
        positionOf(bundt, 'baking soda'),
        {'fdc_id': alt3},
      );
      await matchAndCompute(db, provider, pancakes);
      final own = rowOf(pancakes, 'baking soda');
      expect(own.fdcId, bakingSodaAlt);
      expect(own.status, 'overridden');
    });

    test(
      "apply_to_all lands on the other recipes' undecided lines only, "
      'reports what it reached, and `others` counts them beforehand',
      () async {
        // Reset the skip from above so the Bundt cake's eggs are undecided,
        // and bless the pancakes' eggs so they are a decision to be left alone.
        final eggsPos = positionOf(bundt, 'eggs');
        await applyMatchOverride(db, provider, bundt, eggsPos, {
          'skipped': false,
        });
        await applyMatchOverride(
          db,
          provider,
          pancakes,
          positionOf(pancakes, 'eggs'),
          {'confirmed': true},
        );
        final pancakesEggsBefore = rowOf(pancakes, 'eggs');

        final before = await matchesBody(db, provider, bundt);
        final eggsItem = (before['items']! as List)[eggsPos] as Map;
        expect(
          eggsItem['others'],
          1,
          reason: 'only the caramel cake is undecided',
        );

        final eggsAlt = await otherFoodFor(bundt, 'eggs', {
          rowOf(bundt, 'eggs').fdcId ?? -1,
        });
        final applied = await applyMatchOverride(db, provider, bundt, eggsPos, {
          'fdc_id': eggsAlt,
          'apply_to_all': true,
        });
        expect(applied, (recipes: 1, lines: 1));

        final caramelEggs = rowOf(caramel, 'eggs');
        expect(caramelEggs.fdcId, eggsAlt);
        expect(caramelEggs.status, 'overridden');
        expect(caramelEggs.confidence, 1);
        expect(caramelEggs.grams, await ownGrams(caramel, 'eggs', eggsAlt));
        expect(db.nutritionFor(caramel.id), isNotNull);

        final pancakesEggs = rowOf(pancakes, 'eggs');
        expect(pancakesEggs.fdcId, pancakesEggsBefore.fdcId);
        expect(pancakesEggs.status, 'confirmed', reason: 'a decision stands');

        final after = await matchesBody(db, provider, bundt);
        expect(((after['items']! as List)[eggsPos] as Map)['others'], 0);
        expect(
          ((after['items']! as List)[eggsPos] as Map)['others'],
          isA<int>(),
        );
      },
    );

    test('apply_to_all needs a food decision, and a boolean', () async {
      final position = positionOf(bundt, 'baking soda');
      await expectLater(
        applyMatchOverride(db, provider, bundt, position, {
          'skipped': true,
          'apply_to_all': true,
        }),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        applyMatchOverride(db, provider, bundt, position, {
          'confirmed': true,
          'apply_to_all': 'yes',
        }),
        throwsA(isA<ValidationException>()),
      );
      // Leave the line decided again for any later test.
      await applyMatchOverride(db, provider, bundt, position, {
        'skipped': false,
      });
    });

    test('the boot-time backfill keys pre-009 rows from their recipes', () {
      sqlite3.open(config.dbPath)
        ..execute('UPDATE ingredient_matches SET item_key = NULL')
        ..execute('DELETE FROM settings WHERE key = ?', [
          itemKeyBackfillSetting,
        ])
        ..dispose();
      expect(db.recipesWithUnkeyedMatches(), hasLength(3));

      final keyed = backfillItemKeys(db);

      expect(keyed, greaterThan(0));
      expect(db.getSetting(itemKeyBackfillSetting), isNotNull);
      for (final recipe in [bundt, pancakes, caramel]) {
        final lines = nutritionLines(recipe);
        for (final row in db.ingredientMatchesFor(recipe.id)) {
          final line = lines[row.position];
          final expected = normalizeItem(line.item ?? line.raw);
          expect(row.itemKey, expected.isEmpty ? isNull : expected);
        }
      }
      expect(backfillItemKeys(db), 0, reason: 'guarded by the marker');
    });
  });
}
