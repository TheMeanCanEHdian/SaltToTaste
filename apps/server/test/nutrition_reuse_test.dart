import 'dart:async';
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
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_server/src/services/item_key_backfill.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:test/test.dart';
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Cross-recipe reuse of human match decisions (review R1), over real
/// corpus recipes that share ingredient items — the Bundt cake, the
/// whole-wheat pancakes and the caramel cake all carry `baking soda` and
/// `eggs`; the caramel cake lists `table salt` twice — and the recorded real
/// FDC payloads.
///
/// The rules: a person's `confirmed`/`overridden` food on an item travels to
/// every other line of that item at compute time (most recent wins; skips
/// never travel; a decision on the inheriting line itself stands), and
/// `apply_to_all` lands it right away — as machine propagation (`auto`),
/// so a wrong pick is corrected the same way it was made. The second half
/// pins what two review fleets found unpinned: stale targets, the backfill's
/// guards, the `others` count, a food-less decision, a provider failure
/// part-way through a sweep, the guarded write's truthfulness, and the
/// fixed-width timestamp that "most recent" relies on.
/// Parks one food lookup on a gate, so a test can act while a sweep waits.
class _GatedFoodProvider implements NutritionProvider {
  _GatedFoodProvider(this._inner, this.gateFor);

  final NutritionProvider _inner;
  final int gateFor;
  final Completer<void> reached = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<List<FdcCandidate>> search(String query) => _inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) async {
    if (fdcId == gateFor) {
      if (!reached.isCompleted) {
        reached.complete();
      }
      await release.future;
    }
    return _inner.food(fdcId);
  }
}

class _FailingFoodProvider implements NutritionProvider {
  _FailingFoodProvider(this._inner, this.failFor);

  final NutritionProvider _inner;
  final int failFor;

  @override
  Future<List<FdcCandidate>> search(String query) => _inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) async {
    if (fdcId == failFor) {
      throw const NutritionProviderException('FDC budget drained mid-sweep');
    }
    return _inner.food(fdcId);
  }
}

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

    List<int> positionsOf(Recipe recipe, String key) => [
      for (final (index, line) in nutritionLines(recipe).indexed)
        if (normalizeItem(line.item ?? line.raw) == key) index,
    ];

    int positionOf(Recipe recipe, String key) {
      final positions = positionsOf(recipe, key);
      expect(positions, isNotEmpty, reason: '$key must be a real line');
      return positions.first;
    }

    IngredientMatchRow rowAt(Recipe recipe, int position) => db
        .ingredientMatchesFor(recipe.id)
        .firstWhere((row) => row.position == position);

    IngredientMatchRow rowOf(Recipe recipe, String key) =>
        rowAt(recipe, positionOf(recipe, key));

    /// A recorded, fetchable food other than [notThis] — what a person would
    /// re-pick to. Preferably one of the line's own recorded candidates; the
    /// fixtures only hold the foods the engine fetched, so when a query
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

    Future<double?> ownGrams(Recipe recipe, int position, int fdcId) async {
      final line = nutritionLines(recipe)[position];
      return resolveGrams(
        amounts: line.amounts,
        food: await provider.food(fdcId),
        normalizedItem: normalizeItem(line.item ?? line.raw),
        raw: line.raw,
      )?.grams;
    }

    Future<int> othersOf(Recipe recipe, int position) async {
      final body = await matchesBody(db, provider, recipe);
      return ((body['items']! as List)[position] as Map)['others']! as int;
    }

    Future<AppliedToOthers?> put(
      Recipe recipe,
      int position,
      Map<String, Object?> body,
    ) => applyMatchOverride(db, provider, recipe, position, body);

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

    test('the timestamp writer pads a zero microsecond component', () {
      expect(
        fixedWidthUtcIso(DateTime.utc(2026, 9, 3, 1, 2, 3, 1)),
        '2026-09-03T01:02:03.001000Z',
      );
      expect(
        fixedWidthUtcIso(DateTime.utc(2026, 9, 3, 1, 2, 3, 1, 5)),
        '2026-09-03T01:02:03.001005Z',
      );
      expect(
        '2026-09-03T01:02:03.001000Z'.compareTo('2026-09-03T01:02:03.001005Z'),
        lessThan(0),
        reason: 'padded, the older write sorts first',
      );
    });

    test('updated_at is fixed-width, so "most recent" sorts as text', () {
      // toIso8601String drops to three fractional digits when the
      // microseconds are zero, and '...001Z' sorts AFTER '...001005Z'.
      for (final row in db.ingredientMatchesFor(bundt.id)) {
        expect(
          row.updatedAt,
          matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$')),
        );
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

        final applied = await put(bundt, positionOf(bundt, 'baking soda'), {
          'fdc_id': bakingSodaAlt,
        });
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
          await ownGrams(
            pancakes,
            positionOf(pancakes, 'baking soda'),
            bakingSodaAlt,
          ),
          reason: "grams come from THIS line's amounts, not the source line",
        );
      },
    );

    test(
      'a skip does not travel: the other line keeps its own match',
      () async {
        final before = rowOf(pancakes, 'eggs');
        expect(before.status, 'auto');
        expect(
          before.confidence,
          lessThan(1),
          reason:
              'a travelling decision would arrive at confidence 1 — the '
              'pin needs the own match to be distinguishable from it',
        );
        await put(bundt, positionOf(bundt, 'eggs'), {'skipped': true});
        await matchAndCompute(db, provider, pancakes);
        final after = rowOf(pancakes, 'eggs');
        expect(after.status, 'auto');
        expect(after.fdcId, before.fdcId);
        expect(after.confidence, before.confidence);
      },
    );

    test('the most recent decision wins', () async {
      final alt2 = await otherFoodFor(caramel, 'baking soda', {bakingSodaAlt});
      await put(caramel, positionOf(caramel, 'baking soda'), {'fdc_id': alt2});
      await matchAndCompute(db, provider, pancakes);
      expect(rowOf(pancakes, 'baking soda').fdcId, alt2);
    });

    test('two decisions in the same millisecond still order by time', () {
      // The raw shape the old writer produced: the older write with a zero
      // microsecond component came out three digits SHORTER and sorted last.
      final older = positionOf(bundt, 'baking soda');
      final newer = positionOf(caramel, 'baking soda');
      sqlite3.open(config.dbPath)
        ..execute(
          'UPDATE ingredient_matches SET updated_at = ? '
          'WHERE recipe_id = ? AND position = ?',
          ['2026-09-03T01:02:03.001000Z', bundt.id, older],
        )
        ..execute(
          'UPDATE ingredient_matches SET updated_at = ? '
          'WHERE recipe_id = ? AND position = ?',
          ['2026-09-03T01:02:03.001005Z', caramel.id, newer],
        )
        ..dispose();
      final winner = db.decidedMatchForItemKey(
        'baking soda',
        excluding: (recipeId: pancakes.id, position: 0),
      );
      expect(winner!.recipeId, caramel.id, reason: 'the later microsecond');
    });

    test('a decision on the inheriting line itself stands', () async {
      await put(pancakes, positionOf(pancakes, 'baking soda'), {
        'fdc_id': bakingSodaAlt,
      });
      final alt3 = await otherFoodFor(bundt, 'baking soda', {bakingSodaAlt});
      await put(bundt, positionOf(bundt, 'baking soda'), {'fdc_id': alt3});
      await matchAndCompute(db, provider, pancakes);
      final own = rowOf(pancakes, 'baking soda');
      expect(own.fdcId, bakingSodaAlt);
      expect(own.status, 'overridden');
    });

    test('a decided row with no food is never inherited (and never crashes '
        'the compute)', () async {
      // Confirming an unmatched line leaves status confirmed with fdc_id
      // NULL — a shape the override endpoint produces. Another recipe's
      // line of that item must fall through to its own search.
      final position = positionOf(bundt, 'baking soda');
      sqlite3.open(config.dbPath)
        ..execute(
          'UPDATE ingredient_matches SET fdc_id = NULL, status = ? '
          'WHERE recipe_id = ? AND position = ?',
          ['confirmed', bundt.id, position],
        )
        ..dispose();
      final caramelPos = positionOf(caramel, 'baking soda');
      await put(caramel, caramelPos, {'skipped': true}); // no other source
      await put(pancakes, positionOf(pancakes, 'baking soda'), {
        'skipped': false, // back to the engine's own triage
      });
      await matchAndCompute(db, provider, pancakes);
      final own = rowOf(pancakes, 'baking soda');
      expect(own.status, 'auto');
      expect(own.fdcId, isNotNull, reason: 'its own search, not a null food');
      expect(own.confidence, lessThan(1));
      // Put the sources back for the tests below.
      await put(bundt, position, {'fdc_id': bakingSodaAlt});
      await put(caramel, caramelPos, {'skipped': false});
    });

    test(
      'apply_to_all lands on the other undecided lines of the item as `auto` '
      '(machine propagation), leaves decisions alone, reports what it wrote, '
      'and `others` counts what it would change',
      () async {
        final eggsPos = positionOf(bundt, 'eggs');
        await put(bundt, eggsPos, {'skipped': false});
        await put(pancakes, positionOf(pancakes, 'eggs'), {'confirmed': true});
        final pancakesEggsBefore = rowOf(pancakes, 'eggs');
        // Every eggs line is on the same auto food, so nothing would change.
        expect(await othersOf(bundt, eggsPos), 0);

        // The review flow: re-pick on this line, then the count says how
        // many other recipes are not on that food yet, then apply.
        final eggsAlt = await otherFoodFor(bundt, 'eggs', {
          rowOf(bundt, 'eggs').fdcId ?? -1,
        });
        await put(bundt, eggsPos, {'fdc_id': eggsAlt});
        expect(await othersOf(bundt, eggsPos), 1, reason: 'the caramel cake');

        final applied = await put(bundt, eggsPos, {
          'fdc_id': eggsAlt,
          'apply_to_all': true,
        });
        expect(applied, (recipes: 1, lines: 1, failed: 0));

        final caramelEggs = rowOf(caramel, 'eggs');
        expect(caramelEggs.fdcId, eggsAlt);
        expect(caramelEggs.status, 'auto', reason: 'no human saw that line');
        expect(caramelEggs.confidence, 1);
        expect(
          caramelEggs.grams,
          await ownGrams(caramel, positionOf(caramel, 'eggs'), eggsAlt),
        );
        expect(db.nutritionFor(caramel.id), isNotNull);

        final pancakesEggs = rowOf(pancakes, 'eggs');
        expect(pancakesEggs.fdcId, pancakesEggsBefore.fdcId);
        expect(pancakesEggs.status, 'confirmed', reason: 'a decision stands');

        expect(
          await othersOf(bundt, eggsPos),
          0,
          reason: 'nothing left that this food would change',
        );
      },
    );

    test(
      'a wrong pick applied library-wide is corrected the same way',
      () async {
        // The whole point of `auto`: the rows the first apply_to_all wrote are
        // reached by the second, and a sweep re-inherits the correction.
        final eggsPos = positionOf(bundt, 'eggs');
        final wrong = rowOf(bundt, 'eggs').fdcId!;
        final right = await otherFoodFor(bundt, 'eggs', {wrong});
        final applied = await put(bundt, eggsPos, {
          'fdc_id': right,
          'apply_to_all': true,
        });
        expect(applied, (recipes: 1, lines: 1, failed: 0));
        expect(rowOf(caramel, 'eggs').fdcId, right);

        // A sweep over the caramel cake keeps the correction (most recent).
        await matchAndCompute(db, provider, caramel);
        expect(rowOf(caramel, 'eggs').fdcId, right);
      },
    );

    test("the same recipe's other line of the item is reached too", () async {
      final salts = positionsOf(caramel, 'table salt');
      expect(salts, hasLength(2), reason: 'the caramel cake salts twice');
      final first = rowAt(caramel, salts[0]);
      expect(first.status, 'auto');
      final alt = await otherFoodFor(caramel, 'table salt', {first.fdcId!});

      // Re-picked, the count includes the sibling: one recipe (the same one).
      await put(caramel, salts[0], {'fdc_id': alt});
      expect(await othersOf(caramel, salts[0]), greaterThanOrEqualTo(1));

      final applied = await put(caramel, salts[0], {
        'fdc_id': alt,
        'apply_to_all': true,
      });
      expect(applied!.lines, greaterThanOrEqualTo(1));
      final sibling = rowAt(caramel, salts[1]);
      expect(sibling.fdcId, alt);
      expect(sibling.status, 'auto');

      // And inheritance at compute time reads the sibling as a source.
      sqlite3.open(config.dbPath)
        ..execute(
          "UPDATE ingredient_matches SET status = 'auto', confidence = 0.4 "
          'WHERE recipe_id = ? AND position = ?',
          [caramel.id, salts[1]],
        )
        ..dispose();
      await matchAndCompute(db, provider, caramel);
      expect(
        rowAt(caramel, salts[1]).fdcId,
        alt,
        reason: 'from line ${salts[0]}',
      );
      expect(rowAt(caramel, salts[1]).confidence, 1);
    });

    test('`others` counts recipes, not rows', () async {
      // Two undecided table-salt lines in the caramel cake are ONE recipe.
      final bundtSalt = positionOf(bundt, 'table salt');
      final salts = positionsOf(caramel, 'table salt');
      sqlite3.open(config.dbPath)
        ..execute(
          "UPDATE ingredient_matches SET status = 'auto', fdc_id = NULL "
          'WHERE recipe_id = ? AND position IN (?, ?)',
          [caramel.id, salts[0], salts[1]],
        )
        ..dispose();
      expect(await othersOf(bundt, bundtSalt), 1);
    });

    test('apply_to_all needs a food decision in the request, not a status; '
        'a refusal writes nothing', () async {
      final position = positionOf(bundt, 'baking soda');
      final before = rowAt(bundt, position);
      for (final body in <Map<String, Object?>>[
        {'skipped': true, 'apply_to_all': true},
        {'grams': 7, 'apply_to_all': true}, // the engine's guess, not a pick
        {'confirmed': true, 'apply_to_all': 'yes'},
      ]) {
        await expectLater(
          put(bundt, position, body),
          throwsA(isA<ValidationException>()),
          reason: '$body',
        );
        final after = rowAt(bundt, position);
        expect(after.status, before.status, reason: 'nothing written: $body');
        expect(after.grams, before.grams);
      }
    });

    test('a target whose line text changed, or which is past the end, '
        'is skipped — counted by `others`, not by `applied`', () async {
      final eggsPos = positionOf(bundt, 'eggs');
      final caramelEggs = positionOf(caramel, 'eggs');
      final pancakesEggs = positionOf(pancakes, 'eggs');
      final lineCount = nutritionLines(caramel).length;
      sqlite3.open(config.dbPath)
        // The caramel row's text no longer matches its line (an edit).
        ..execute(
          "UPDATE ingredient_matches SET status = 'auto', fdc_id = NULL, "
          "raw = raw || ' (edited)' WHERE recipe_id = ? AND position = ?",
          [caramel.id, caramelEggs],
        )
        // The pancakes row sits past the end of a shortened recipe.
        ..execute(
          "UPDATE ingredient_matches SET status = 'auto', fdc_id = NULL, "
          'position = ? WHERE recipe_id = ? AND position = ?',
          [lineCount + 5, pancakes.id, pancakesEggs],
        )
        ..dispose();
      expect(await othersOf(bundt, eggsPos), 2, reason: 'an upper bound');

      final food = rowOf(bundt, 'eggs').fdcId!;
      final applied = await put(bundt, eggsPos, {
        'fdc_id': food,
        'apply_to_all': true,
      });
      expect(applied, (recipes: 0, lines: 0, failed: 0));
      expect(rowAt(caramel, caramelEggs).fdcId, isNull, reason: 'stale text');

      // Restore: a compute rewrites the rows from the real lines.
      sqlite3.open(config.dbPath)
        ..execute(
          'DELETE FROM ingredient_matches WHERE recipe_id = ? AND position = ?',
          [pancakes.id, lineCount + 5],
        )
        ..dispose();
      await matchAndCompute(db, provider, caramel);
      await matchAndCompute(db, provider, pancakes);
    });

    test('a provider failure part-way through a sweep is counted, not '
        'reported as a refusal; what landed stays', () async {
      // Recompute of the caramel cake's totals needs its OTHER lines' foods;
      // evict one from the cache and make the provider fail on it.
      final eggsPos = positionOf(bundt, 'eggs');
      final caramelEggs = positionOf(caramel, 'eggs');
      final victim = db
          .ingredientMatchesFor(caramel.id)
          .firstWhere((r) => r.fdcId != null && r.position != caramelEggs)
          .fdcId!;
      sqlite3.open(config.dbPath)
        ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [victim])
        ..execute(
          "UPDATE ingredient_matches SET status = 'auto', fdc_id = NULL "
          'WHERE recipe_id = ? AND position = ?',
          [caramel.id, caramelEggs],
        )
        ..dispose();
      final food = rowOf(bundt, 'eggs').fdcId!;
      final applied = await applyMatchOverride(
        db,
        _FailingFoodProvider(provider, victim),
        bundt,
        eggsPos,
        {'fdc_id': food, 'apply_to_all': true},
      );
      expect(applied, (recipes: 0, lines: 0, failed: 1));
      expect(rowOf(bundt, 'eggs').fdcId, food, reason: 'the source stayed');
      // The line itself landed before its recipe's totals failed.
      expect(rowAt(caramel, caramelEggs).fdcId, food);
      // Heal the cache for later tests.
      await matchAndCompute(db, provider, caramel);
    });

    test('a target decided WHILE the sweep runs is left alone and not '
        'counted', () async {
      // The sweep awaits each recipe's recompute; a person can decide a
      // later target line in that gap. The SQL guard stops the write, and
      // the counts must say so — the query result is stale by then.
      final eggsPos = positionOf(bundt, 'eggs');
      final targets = [pancakes, caramel]
        ..sort((a, b) => a.id.compareTo(b.id)); // the sweep's order
      final first = targets[0];
      final second = targets[1];
      final firstEggs = positionOf(first, 'eggs');
      final secondEggs = positionOf(second, 'eggs');
      sqlite3.open(config.dbPath)
        ..execute(
          "UPDATE ingredient_matches SET status = 'auto', fdc_id = NULL "
          'WHERE (recipe_id = ? AND position = ?) '
          'OR (recipe_id = ? AND position = ?)',
          [first.id, firstEggs, second.id, secondEggs],
        )
        ..dispose();
      // Park the first recipe's recompute on one of its OTHER foods.
      final parkOn = db
          .ingredientMatchesFor(first.id)
          .firstWhere((r) => r.fdcId != null && r.position != firstEggs)
          .fdcId!;
      sqlite3.open(config.dbPath)
        ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [parkOn])
        ..dispose();
      final gated = _GatedFoodProvider(provider, parkOn);
      final food = rowOf(bundt, 'eggs').fdcId!;
      final sweep = applyMatchOverride(db, gated, bundt, eggsPos, {
        'fdc_id': food,
        'apply_to_all': true,
      });
      await gated.reached.future;
      // While the sweep waits: a person confirms the second target's line.
      await put(second, secondEggs, {'confirmed': true});
      gated.release.complete();
      final applied = await sweep;

      expect(applied, (recipes: 1, lines: 1, failed: 0));
      final decided = rowAt(second, secondEggs);
      expect(decided.status, 'confirmed');
      expect(decided.fdcId, isNull, reason: 'the guard held the write off');
      await matchAndCompute(db, provider, first); // heal the cache
    });

    test('the guarded write says whether it wrote', () async {
      final position = positionOf(pancakes, 'baking soda');
      await put(pancakes, position, {'confirmed': true});
      final decided = rowAt(pancakes, position);
      expect(decided.status, 'confirmed');
      expect(
        db.upsertIngredientMatchIfUndecided(
          decided.copyWith(confidence: 0.1, status: 'auto'),
        ),
        isFalse,
        reason: 'a decision with the same text stands',
      );
      final auto = rowOf(pancakes, 'eggs');
      expect(db.upsertIngredientMatchIfUndecided(auto), isTrue);
    });

    test('the boot-time backfill keys pre-009 rows from their recipes, leaves '
        'a stale row unkeyed, and withholds its marker while a recipe will '
        'not decode', () {
      final caramelEggs = positionOf(caramel, 'eggs');
      final original =
          sqlite3.open(config.dbPath).select(
                'SELECT doc FROM recipes WHERE id = ?',
                [bundt.id],
              ).first['doc']
              as String;
      sqlite3.open(config.dbPath)
        ..execute('UPDATE ingredient_matches SET item_key = NULL')
        ..execute(
          "UPDATE ingredient_matches SET raw = raw || ' (edited)' "
          'WHERE recipe_id = ? AND position = ?',
          [caramel.id, caramelEggs],
        )
        ..execute('UPDATE recipes SET doc = ? WHERE id = ?', [
          '{"title": ',
          bundt.id,
        ])
        ..execute('DELETE FROM settings WHERE key = ?', [
          itemKeyBackfillSetting,
        ])
        ..dispose();
      expect(db.recipesWithUnkeyedMatches(), hasLength(3));

      // First pass: the Bundt cake will not decode.
      expect(backfillItemKeys(db), greaterThan(0));
      expect(db.getSetting(itemKeyBackfillSetting), isNull, reason: 'retry');
      expect(
        db.ingredientMatchesFor(bundt.id).every((r) => r.itemKey == null),
        isTrue,
      );
      expect(rowAt(caramel, caramelEggs).itemKey, isNull, reason: 'stale raw');
      final salts = positionsOf(caramel, 'table salt');
      expect(rowAt(caramel, salts[0]).itemKey, 'table salt');

      // Fix the document: the next boot completes the pass.
      sqlite3.open(config.dbPath)
        ..execute('UPDATE recipes SET doc = ? WHERE id = ?', [
          original,
          bundt.id,
        ])
        ..dispose();
      expect(backfillItemKeys(db), greaterThan(0));
      expect(db.getSetting(itemKeyBackfillSetting), isNotNull);
      for (final row in db.ingredientMatchesFor(bundt.id)) {
        final line = nutritionLines(bundt)[row.position];
        final expected = normalizeItem(line.item ?? line.raw);
        expect(row.itemKey, expected.isEmpty ? isNull : expected);
      }
      expect(backfillItemKeys(db), 0, reason: 'guarded by the marker');
    });
  });
}
