import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/services/decision_rekey.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_server/src/services/item_key_backfill.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// A human food decision has a row of its own (`ingredient_decisions`,
/// migration 010), keyed by the ingredient, so it outlives the recipe and
/// the line it was made on. Before, every other line BORROWED the decision
/// from that one row: delete the recipe or edit that line and every
/// borrower reverted at its next compute (design review D3, 2026-09-07).
/// Real corpus recipes that share `eggs` and `baking soda`, recorded FDC
/// payloads.
void main() {
  group('ingredient decisions', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late ServerConfig config;
    late SaltDatabase db;
    late FixtureProvider provider;
    late Recipe bundt;
    late Recipe pancakes;
    late Recipe caramel;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-decisions-test');
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

    int positionOf(Recipe recipe, String word) {
      final position = nutritionLines(
        recipe,
      ).indexWhere((l) => l.raw.contains(word));
      expect(position, isNonNegative, reason: '$word must be a real line');
      return position;
    }

    IngredientMatchRow rowAt(Recipe recipe, int position) => db
        .ingredientMatchesFor(recipe.id)
        .firstWhere((row) => row.position == position);

    Future<int> otherFoodFor(Recipe recipe, int position, int notThis) async {
      final candidates = await candidatesForLine(
        db,
        provider,
        nutritionLines(recipe)[position],
        cacheOnly: true,
      );
      for (final candidate in candidates) {
        if (candidate.candidate.fdcId != notThis &&
            await cachedFood(db, provider, candidate.candidate.fdcId) != null) {
          return candidate.candidate.fdcId;
        }
      }
      fail('no other recorded food for the line');
    }

    late int eggsAlt;

    test('rows carry the singular key, and no decision exists yet', () {
      expect(rowAt(bundt, positionOf(bundt, 'eggs')).itemKey, 'egg');
      expect(db.decisionFor('egg'), isNull);
      expect(db.decisionFor('eggs'), isNull, reason: 'never a plural key');
    });

    test(
      'a re-pick writes the ingredient decision; a confirm of a food does '
      'too; a grams-only edit and a skip do not',
      () async {
        final position = positionOf(bundt, 'eggs');
        final auto = rowAt(bundt, position);
        expect(auto.status, 'auto');
        // Grams only: a decision about the amount, not the food.
        await applyMatchOverride(db, provider, bundt, position, {
          'grams': 120,
        });
        expect(rowAt(bundt, position).status, 'overridden');
        expect(db.decisionFor('egg'), isNull, reason: 'grams decide no food');
        // Skip: per line, never an ingredient decision.
        await applyMatchOverride(db, provider, bundt, position, {
          'skipped': true,
        });
        expect(db.decisionFor('egg'), isNull);
        await applyMatchOverride(db, provider, bundt, position, {
          'skipped': false,
        });
        // Confirm of the food the line has: a decision.
        await applyMatchOverride(db, provider, bundt, position, {
          'confirmed': true,
        });
        var decision = db.decisionFor('egg')!;
        expect(decision.fdcId, auto.fdcId);
        expect(decision.item, 'large eggs', reason: 'the parsed item');
        expect(decision.description, auto.description);
        expect(
          decision.decidedAt,
          matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$')),
        );
        // Re-pick: the newest decision replaces it.
        eggsAlt = await otherFoodFor(bundt, position, auto.fdcId!);
        await applyMatchOverride(db, provider, bundt, position, {
          'fdc_id': eggsAlt,
        });
        decision = db.decisionFor('egg')!;
        expect(decision.fdcId, eggsAlt);
      },
    );

    test(
      'another recipe inherits the decision at its compute, as `auto` at '
      'confidence 1 with its own grams',
      () async {
        await matchAndCompute(db, provider, pancakes);
        final row = rowAt(pancakes, positionOf(pancakes, 'eggs'));
        expect(row.fdcId, eggsAlt);
        expect(row.status, 'auto');
        expect(row.confidence, 1);
        expect(row.itemKey, 'egg');
      },
    );

    test(
      'the decision survives an edit of the line it was made on: the edited '
      'line and every other line still get the food',
      () async {
        final position = positionOf(bundt, 'eggs');
        final lines = nutritionLines(bundt);
        final old = lines[position];
        expect(old.raw, contains('5 large'));
        final edited = bundt.copyWith(
          ingredients: [
            IngredientGroup(
              items: [
                for (final (i, line) in lines.indexed)
                  i == position
                      ? IngredientLine(
                          raw: old.raw.replaceFirst('5 large', '6 large'),
                          item: old.item,
                          prep: old.prep,
                          amounts: old.amounts,
                        )
                      : line,
              ],
            ),
          ],
        );
        db.upsertRecipe(
          edited,
          sourceSlug: db.recipeByIdOrSlug(bundt.id)!.sourceSlug,
          contentHash: 'edited-eggs',
        );
        final reloaded = db.recipeByIdOrSlug(bundt.id)!.recipe;
        await matchAndCompute(db, provider, reloaded);
        expect(rowAt(reloaded, position).fdcId, eggsAlt, reason: 'edited');
        expect(db.decisionFor('egg')!.fdcId, eggsAlt);
        await matchAndCompute(db, provider, pancakes);
        expect(rowAt(pancakes, positionOf(pancakes, 'eggs')).fdcId, eggsAlt);
      },
    );

    test(
      'a body mixing `skipped` with a food verb is refused and writes '
      'nothing — the gate keys on what landed, not on the request',
      () async {
        final position = positionOf(pancakes, 'baking soda');
        final before = rowAt(pancakes, position);
        expect(db.decisionFor('baking soda'), isNull);
        for (final body in [
          {'skipped': true, 'confirmed': true},
          {'skipped': false, 'fdc_id': before.fdcId},
          {'skipped': true, 'fdc_id': before.fdcId, 'apply_to_all': true},
        ]) {
          await expectLater(
            applyMatchOverride(db, provider, pancakes, position, body),
            throwsA(isA<ValidationException>()),
            reason: '$body',
          );
        }
        expect(db.decisionFor('baking soda'), isNull);
        expect(rowAt(pancakes, position).status, before.status);
      },
    );

    test('a decision with no food is not inherited', () async {
      db.putDecision(
        itemKey: 'baking soda',
        item: 'baking soda',
        fdcId: null,
        description: null,
        dataType: null,
        decidedBy: null,
      );
      await matchAndCompute(db, provider, pancakes);
      final row = rowAt(pancakes, positionOf(pancakes, 'baking soda'));
      expect(row.status, 'auto');
      expect(row.fdcId, isNotNull, reason: 'its own search');
      expect(row.confidence, lessThan(1));
      db.deleteDecision('baking soda');
    });

    test(
      'a matcher-version change re-keys decisions from their item text; on '
      'a collision the newer decision wins',
      () {
        // The shapes older matchers left behind: an accent split into an
        // orphan letter, and a plural key beside its singular.
        db
          ..putDecision(
            itemKey: 'jalape o chile',
            item: 'jalapeño chiles',
            fdcId: eggsAlt,
            description: 'stand-in',
            dataType: 'SR Legacy',
            decidedBy: null,
          )
          ..putDecision(
            itemKey: 'onions',
            item: 'onions',
            fdcId: eggsAlt,
            description: 'older',
            dataType: 'SR Legacy',
            decidedBy: null,
          )
          ..putDecision(
            itemKey: 'onion',
            item: 'onion',
            fdcId: eggsAlt,
            description: 'newer',
            dataType: 'SR Legacy',
            decidedBy: null,
          )
          ..setSetting(decisionRekeySetting, '1');
        expect(rekeyDecisions(db), 2, reason: 'one moved, one collision');
        expect(db.decisionFor('jalape o chile'), isNull);
        expect(db.decisionFor('jalapeno chile')!.item, 'jalapeño chiles');
        expect(db.decisionFor('onions'), isNull);
        expect(db.decisionFor('onion')!.description, 'newer');
        expect(db.getSetting(decisionRekeySetting), '$matcherVersion');
        expect(rekeyDecisions(db), 0, reason: 'guarded by the marker');

        // A chain: X moves INTO the key Y is moving OUT of. Collisions are
        // judged on final keys, so nothing is lost (Opus fleet, 2026-09-07).
        db
          ..deleteDecision('onion')
          ..putDecision(
            itemKey: 'stale-key-for-eggs',
            item: 'eggs',
            fdcId: eggsAlt,
            description: 'X',
            dataType: 'SR Legacy',
            decidedBy: null,
          )
          ..putDecision(
            itemKey: 'egg',
            item: 'onions',
            fdcId: eggsAlt,
            description: 'Y',
            dataType: 'SR Legacy',
            decidedBy: null,
          )
          ..setSetting(decisionRekeySetting, '1');
        expect(rekeyDecisions(db), 2, reason: 'both moved, none dropped');
        expect(db.decisionFor('egg')!.description, 'X');
        expect(db.decisionFor('onion')!.description, 'Y');
        expect(db.decisionFor('stale-key-for-eggs'), isNull);
      },
    );

    test('a matcher-version change re-keys every match row too', () {
      final position = positionOf(pancakes, 'eggs');
      db
        ..setMatchItemKey(pancakes.id, position, 'eggs')
        ..setSetting(itemKeyBackfillSetting, '2026-09-03T00:00:00.000Z');
      expect(backfillItemKeys(db), greaterThan(0));
      expect(rowAt(pancakes, position).itemKey, 'egg');
      expect(db.getSetting(itemKeyBackfillSetting), '$matcherVersion');
      expect(backfillItemKeys(db), 0);
    });

    test('the decision outlives the recipe it was made in', () async {
      // Made on the Bundt cake; the cake goes; the others still inherit.
      expect(db.deleteRecipe(bundt.id), isTrue);
      expect(db.decisionFor('egg')!.fdcId, eggsAlt);
      await applyMatchOverride(
        db,
        provider,
        pancakes,
        positionOf(pancakes, 'eggs'),
        {'skipped': false},
      );
      await matchAndCompute(db, provider, pancakes);
      expect(rowAt(pancakes, positionOf(pancakes, 'eggs')).fdcId, eggsAlt);
      await matchAndCompute(db, provider, caramel);
      expect(rowAt(caramel, positionOf(caramel, 'eggs')).fdcId, eggsAlt);
    });
  });
}
