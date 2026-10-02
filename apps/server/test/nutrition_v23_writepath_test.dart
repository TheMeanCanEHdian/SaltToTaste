// Run 053's write-path fixes (matcher v23): the first layout after an
// upgrade from before migration 012 (G1, S2/S18, Opus critic 2) and
// migration 013's backfill and counter seed (S12/O15); the plain recompute
// computing on the STORED recipe at stamp time (G2, O4); the stamp-time
// re-check (O10/S6); apply-to-all's receipt (O5/S3, O12/S8, Opus critic 3)
// and its identity lookup (O11, S10); sameMatchRow's fields (S11/O16); the
// pass cap (both job loops); the GET's carried-row fallbacks (S15); the
// drift term's abs() (S14). Real corpus lines (0405 Acquacotta's oil, onion
// and celery; 0148 Crispy Fried Chicken; the onion lines O4 names),
// recorded FDC answers (FixtureProvider), never the network. Synthesized,
// a stated exception: the small test recipes holding corpus lines, the
// edits each test names, the saves and deletes a test makes during an await
// (a gated provider), the schema downgrades that impersonate a database at
// version 11 or 12 (the real migrations then run on open), and one
// undecodable stored doc (a negative-path input).
// ignore_for_file: lines_longer_than_80_chars
import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/layout_backfill.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const quarter = '¼ cup extra-virgin olive oil';

/// A database file in a temp dir (removed after the test) and its path.
(SaltDatabase, String) fileDb() {
  final dir = Directory.systemTemp.createTempSync('salt-v23');
  addTearDown(() => dir.deleteSync(recursive: true));
  final path = '${dir.path}/salt.db';
  return (
    SaltDatabase.open(path)
      ..upsertSource(slug: 'src', name: 'Test', type: 'book'),
    path,
  );
}

/// Puts the closed database at [path] back to schema [version] (11: before
/// migration 012 — no layout table; 12: before 013 — no stamp layout, no
/// global counter), with [seqs] as recipe_layout's per-recipe seqs at 12.
void downgrade(String path, int version, {Map<String, int> seqs = const {}}) {
  final raw = sqlite3.open(path);
  if (version == 11) {
    raw.execute('DROP TABLE recipe_layout');
  }
  for (final MapEntry(:key, :value) in seqs.entries) {
    raw.execute('UPDATE recipe_layout SET seq = ? WHERE recipe_id = ?', [
      value,
      key,
    ]);
  }
  raw
    ..execute('DROP TABLE layout_counter')
    ..execute('ALTER TABLE recipe_nutrition DROP COLUMN layout_seq')
    ..execute('PRAGMA user_version = $version')
    ..dispose();
}

/// A portion-less stand-in for 173468 (olive oil): the apply fetches its
/// detail for a volume line, an await a test lands a write in.
Future<FdcFood> standIn() async {
  final f = (await FixtureProvider().food(173468))!;
  return FdcFood(
    fdcId: f.fdcId,
    description: f.description,
    dataType: f.dataType,
    nutrientsPer100g: f.nutrientsPer100g,
    portions: const [],
  );
}

Future<
  ({
    int recipes,
    int lines,
    int failed,
    int completed,
    List<String> completedRecipes,
    int moved,
    int decided,
    int gone,
    int failedLines,
  })
>
applyOil(SaltDatabase db, NutritionProvider provider, [FdcFood? food]) async =>
    applyDecisionToOthers(
      db,
      provider,
      itemKey: lineKeyOf(wp.lineOf(quarter)),
      decided: food ?? await standIn(),
      excluding: (recipeId: 'a', position: 0),
    );

void main() {
  group('G1: the first layout after an upgrade from before migration 012', () {
    test('S2/S18: [½ cup oil, onion, celery] (0405) computed, the database '
        'put back to version 11 and opened (012 and 013 run) — the '
        'unedited recipe stays fresh through an apply-to-all reaching its '
        "oil line and a person's confirm of its onion, and is never in the "
        'stale scope', () async {
      var (db, path) = fileDb();
      final provider = FixtureProvider(pending: pendingSearches);
      await matchAndCompute(
        db,
        provider,
        wp.saveLines(db, [wp.oil, wp.onion, wp.celery]),
      );
      db.dispose();
      downgrade(path, 11);
      db = SaltDatabase.open(path);
      addTearDown(db.dispose);
      final r = db.recipeByIdOrSlug('r')!.recipe;
      expect(db.nutritionFor('r')!.layoutSeq, 0);
      expect(db.layoutOf('r').texts, isNull);
      // v24 (Run 054 H4): the boot's layout backfill seeds a real layout
      // (a counter seq, the recipe's lines) and moves the stamp onto it.
      expect(backfillLayouts(db), 1);
      final seeded = db.layoutOf('r').seq;
      expect(seeded, greaterThan(0));
      expect(db.nutritionFor('r')!.layoutSeq, seeded);
      expect(db.layoutOf('r').lines, [wp.oil, wp.onion, wp.celery]);
      expect(nutritionIsFresh(db, r), isTrue);
      expect(backfillLayouts(db), 0);

      final o = wp.saveLines(db, [wp.oil], id: 'o');
      await matchAndCompute(db, provider, o);
      final applied = await applyMatchOverride(db, provider, o, 0, {
        'raw': wp.oil,
        'fdc_id': 173468,
        'apply_to_all': true,
      });
      expect(applied!.lines, 1);
      expect(db.ingredientMatchesFor('r').first.fdcId, 173468);
      // The layout found the seeded texts: nothing moved, nothing bumped.
      expect(db.layoutOf('r').seq, seeded);
      expect(db.layoutOf('r').lines, [wp.oil, wp.onion, wp.celery]);
      expect(nutritionIsFresh(db, r), isTrue);

      await applyMatchOverride(db, provider, r, 1, {
        'raw': wp.onion,
        'confirmed': true,
      });
      expect(db.ingredientMatchesFor('r')[1].status, 'confirmed');
      expect(nutritionIsFresh(db, r), isTrue);
      expect(nutritionBody(db, r, forAdmin: true)['status'], 'complete');
      expect(bulkScopeIds(db, BulkScope.stale), isNot(contains('r')));
    });

    test('a first layout that changes something still draws a new seq: an '
        'amount edit (oil ½ → ¼ cup, the row still on the old text) after '
        'the upgrade, and a recipe with no rows yet', () async {
      var (db, path) = fileDb();
      final provider = FixtureProvider(pending: pendingSearches);
      await matchAndCompute(db, provider, wp.saveLines(db, [wp.oil, wp.onion]));
      db.dispose();
      downgrade(path, 11);
      db = SaltDatabase.open(path);
      addTearDown(db.dispose);
      layoutMatchRows(db, wp.saveLines(db, [quarter, wp.onion]));
      expect(db.layoutOf('r').seq, greaterThan(0));
      final fresh = wp.saveLines(db, [wp.onion], id: 'n');
      layoutMatchRows(db, fresh);
      expect(db.layoutOf('n').seq, greaterThan(db.layoutOf('r').seq));
    });
  });

  test('S12/O15: migration 013 on a database at version 12 with layouts — '
      "each stamp takes its recipe's layout seq (0 with none), the global "
      'counter starts at the highest, and every stamp stays fresh', () async {
    var (db, path) = fileDb();
    final provider = FixtureProvider(pending: pendingSearches);
    for (final (id, raw) in [
      ('a', wp.oil),
      ('b', wp.onion),
      ('c', wp.celery),
    ]) {
      await matchAndCompute(db, provider, wp.saveLines(db, [raw], id: id));
    }
    db.dispose();
    downgrade(path, 12, seqs: {'a': 5, 'b': 2});
    sqlite3.open(path)
      ..execute("DELETE FROM recipe_layout WHERE recipe_id = 'c'")
      ..dispose();
    db = SaltDatabase.open(path);
    addTearDown(db.dispose);
    expect(
      [
        for (final id in ['a', 'b', 'c']) db.nutritionFor(id)!.layoutSeq,
      ],
      [5, 2, 0],
    );
    for (final id in ['a', 'b', 'c']) {
      expect(
        nutritionIsFresh(db, db.recipeByIdOrSlug(id)!.recipe),
        isTrue,
        reason: id,
      );
    }
    // The next layout draws the counter's next: above every stored seq.
    layoutMatchRows(db, wp.saveLines(db, [wp.onion], id: 'd'));
    expect(db.layoutOf('d').seq, 6);
  });

  group('G2 (O4): a plain recompute computes on the STORED recipe at stamp '
      'time', () {
    const lb = '2 pounds onions, chopped fine';

    test("an apply-to-all target: during the apply's await on 'b' (lb "
        'onions, large onion), b is saved with celery added and computed — '
        "the totals stamped fresh are the 3-line recipe's, never the "
        '2-line Recipe the apply read', () async {
      final db = wp.tempDb();
      final provider = wp.Gated(FixtureProvider(pending: pendingSearches));
      await matchAndCompute(
        db,
        provider,
        wp.saveLines(db, [wp.onion], id: 'a'),
      );
      await matchAndCompute(
        db,
        provider,
        wp.saveLines(db, [lb, wp.onion], id: 'b'),
      );
      const hit = FdcFood(
        fdcId: 173468,
        description: 'hit',
        dataType: 'SR Legacy',
        nutrientsPer100g: {},
        portions: [],
      );
      late Recipe b2;
      provider.onCall = () async {
        b2 = wp.saveLines(db, [lb, wp.onion, wp.celery], id: 'b');
        await matchAndCompute(db, provider, b2);
      };
      final before = await () async {
        final ref = wp.tempDb();
        final r = wp.saveLines(ref, [lb, wp.onion, wp.celery], id: 'b');
        await matchAndCompute(
          ref,
          FixtureProvider(pending: pendingSearches),
          r,
        );
        return nutritionBody(ref, r, forAdmin: true);
      }();
      await applyDecisionToOthers(
        db,
        provider,
        itemKey: lineKeyOf(wp.lineOf(wp.onion)),
        decided: hit,
        excluding: (recipeId: 'a', position: 0),
      );
      final body = nutritionBody(db, b2, forAdmin: true);
      expect(nutritionIsFresh(db, b2), isTrue);
      expect(body['total_count'], 3);
      expect(body['calories_per_serving'], before['calories_per_serving']);
    });

    test('the serving-basis POST with the Recipe it read before a save and '
        'compute landed: the 3-line totals under the fresh stamp', () async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final b1 = wp.saveLines(db, [lb, wp.onion], id: 'b');
      await matchAndCompute(db, provider, b1);
      final b2 = wp.saveLines(db, [lb, wp.onion, wp.celery], id: 'b');
      await matchAndCompute(db, provider, b2);
      final kcal = db.nutritionFor('b')!.caloriesPerServing!;
      await recomputeTotals(db, provider, b1, servingBasis: 2);
      expect(nutritionIsFresh(db, b2), isTrue);
      expect(db.nutritionFor('b')!.totalCount, 3);
      expect(db.nutritionFor('b')!.caloriesPerServing, closeTo(kcal / 2, 0.01));
    });

    test('its own await: the food cache emptied, a save and a compute land '
        "during the recompute's fetch — the rows it re-reads after, never "
        'those it read before', () async {
      final (db, path) = fileDb();
      addTearDown(db.dispose);
      final inner = FixtureProvider(pending: pendingSearches);
      final b1 = wp.saveLines(db, [lb, wp.onion], id: 'b');
      await matchAndCompute(db, inner, b1);
      sqlite3.open(path)
        ..execute('DELETE FROM fdc_food_cache')
        ..execute('DELETE FROM fdc_search_cache')
        ..dispose();
      final provider = wp.Gated(inner);
      late Recipe b2;
      provider.onCall = () async {
        b2 = wp.saveLines(db, [lb, wp.onion, wp.celery], id: 'b');
        await matchAndCompute(db, inner, b2);
      };
      await recomputeTotals(db, provider, b1);
      expect(nutritionIsFresh(db, b2), isTrue);
      expect(db.nutritionFor('b')!.totalCount, 3);
      expect(db.nutritionFor('b')!.status, 'complete');
    });
  });

  test('O10/S6: the stamp-time re-check — 0148 Crispy Fried Chicken first '
      'computed with no steps (the dredge flour counted, the brine lines '
      'counted), then the real recipe saved; during its compute a title '
      'edit lands (the gate trips, the writes stop) and the real recipe is '
      'saved back (an ABA with no layout): the stamp is never fresh over '
      'rows that compute did not write', () async {
    final (db, path) = fileDb();
    addTearDown(db.dispose);
    final a = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
    final noSteps = a.copyWith(steps: const []);
    void save(Recipe r, String hash) =>
        db.upsertRecipe(r, sourceSlug: 'src', contentHash: hash);
    save(noSteps, 'hp');
    await matchAndCompute(
      db,
      FixtureProvider(pending: pendingSearches),
      noSteps,
    );
    sqlite3.open(path)
      ..execute('DELETE FROM fdc_search_cache')
      ..execute('DELETE FROM fdc_food_cache')
      ..dispose();
    save(a, 'ha');
    final hooks = <void Function()>[
      () => save(a.copyWith(title: '${a.title} (b)'), 'hb'),
      () {},
      () => save(a, 'ha2'),
    ];
    final provider = _Hooked(FixtureProvider(pending: pendingSearches), hooks);
    await matchAndCompute(db, provider, a);
    expect(hooks, isEmpty);
    // The flour row is still the step-less compute's (counted, no hold).
    expect(db.ingredientMatchesFor(a.id)[8].hold, isNull);
    expect(nutritionIsFresh(db, a), isFalse);
    expect(bulkScopeIds(db, BulkScope.stale), contains(a.id));
  }, skip: skipIfNoCorpus);

  group("apply-to-all's receipt: every offered line in the bucket of its "
      'real reason (O5/S3, O12/S8)', () {
    test(
      'S3/O5 case 1: twins [¼ cup oil, ¼ cup oil] in c; a person skips '
      "c's line 0 during b's portion fetch — decided 1, never moved, and "
      "twin 1 written (the row at its own position, not its twin's)",
      () async {
        final db = wp.tempDb();
        final provider = wp.Gated(FixtureProvider(pending: pendingSearches));
        await matchAndCompute(
          db,
          provider,
          wp.saveLines(db, [quarter], id: 'b'),
        );
        final c = wp.saveLines(db, [quarter, quarter], id: 'c');
        await matchAndCompute(db, provider, c);
        provider.onCall = () async {
          await applyMatchOverride(db, FixtureProvider(), c, 0, {
            'raw': quarter,
            'skipped': true,
          });
        };
        final res = await applyOil(db, provider);
        expect((res.lines, res.decided, res.moved, res.gone), (2, 1, 0, 0));
        final rows = db.ingredientMatchesFor('c');
        expect(
          [rows[0].status, rows[1].status, rows[1].confidence],
          ['skipped', 'auto', 1.0],
        );
        expect(appliedJson(res), {
          'recipes': 2,
          'lines': 2,
          'failed': 0,
          'completed': 0,
          'completed_recipes': <String>[],
          'moved': 0,
          'decided': 1,
          'gone': 0,
          'failed_lines': 0,
        });
      },
    );

    test('O5 case 2: c [¼ cup oil] computed, saved as [onion, ¼ cup oil]; a '
        "person skips the oil (its PUT lays the row out to 1) during b's "
        'fetch — decided 1, never moved', () async {
      final db = wp.tempDb();
      final provider = wp.Gated(FixtureProvider(pending: pendingSearches));
      await matchAndCompute(db, provider, wp.saveLines(db, [quarter], id: 'b'));
      await matchAndCompute(db, provider, wp.saveLines(db, [quarter], id: 'c'));
      final c2 = wp.saveLines(db, [wp.onion, quarter], id: 'c');
      provider.onCall = () async {
        await applyMatchOverride(db, FixtureProvider(), c2, 1, {
          'raw': quarter,
          'skipped': true,
        });
      };
      final res = await applyOil(db, provider);
      expect((res.lines, res.decided, res.moved, res.gone), (1, 1, 0, 0));
    });

    test(
      "O5 case 3: c's oil line saved as 0405's other line and laid out "
      "during b's fetch (the oil row dropped) — gone 1, never moved",
      () async {
        final db = wp.tempDb();
        final provider = wp.Gated(FixtureProvider(pending: pendingSearches));
        await matchAndCompute(
          db,
          provider,
          wp.saveLines(db, [quarter], id: 'b'),
        );
        await matchAndCompute(
          db,
          provider,
          wp.saveLines(db, [quarter], id: 'c'),
        );
        provider.onCall = () async {
          layoutMatchRows(db, wp.saveLines(db, [wp.celery], id: 'c'));
        };
        final res = await applyOil(db, provider);
        expect((res.lines, res.decided, res.moved, res.gone), (1, 0, 0, 1));
      },
    );

    test("O12/S8 P3: c deleted during b's fetch — gone 1", () async {
      final db = wp.tempDb();
      final provider = wp.Gated(FixtureProvider(pending: pendingSearches));
      await matchAndCompute(db, provider, wp.saveLines(db, [quarter], id: 'b'));
      await matchAndCompute(db, provider, wp.saveLines(db, [quarter], id: 'c'));
      provider.onCall = () async => db.deleteRecipe('c');
      final res = await applyOil(db, provider);
      expect((res.lines, res.gone, res.moved), (1, 1, 0));
    });

    test("O12/S8 P4: c's stored doc will not decode (synthesized) — failed 1, "
        'its line in failed_lines', () async {
      final (db, path) = fileDb();
      addTearDown(db.dispose);
      final provider = FixtureProvider(pending: pendingSearches);
      await matchAndCompute(db, provider, wp.saveLines(db, [quarter], id: 'b'));
      await matchAndCompute(db, provider, wp.saveLines(db, [quarter], id: 'c'));
      sqlite3.open(path)
        ..execute("UPDATE recipes SET doc = '{' WHERE id = 'c'")
        ..dispose();
      final res = await applyOil(db, provider, await provider.food(173468));
      expect((res.lines, res.failed, res.failedLines), (1, 1, 1));
    });
  });

  test("O5's class, the other side: c [¼ cup oil, ¼ cup oil] with line 0 "
      "skipped BEFORE the apply; during b's fetch c's line 1 is edited to "
      '½ cup and computed (its row rewritten) — moved 1, never decided: the '
      'skip stood at the reach', () async {
    final db = wp.tempDb();
    final provider = wp.Gated(FixtureProvider(pending: pendingSearches));
    await matchAndCompute(db, provider, wp.saveLines(db, [quarter], id: 'b'));
    final c = wp.saveLines(db, [quarter, quarter], id: 'c');
    await matchAndCompute(db, provider, c);
    await applyMatchOverride(db, FixtureProvider(), c, 0, {
      'raw': quarter,
      'skipped': true,
    });
    provider.onCall = () async {
      await matchAndCompute(
        db,
        FixtureProvider(pending: pendingSearches),
        wp.saveLines(db, [quarter, wp.oil], id: 'c'),
      );
    };
    final res = await applyOil(db, provider);
    expect((res.lines, res.decided, res.moved, res.gone), (1, 0, 1, 0));
  });

  test("one decision meanwhile is counted once: c's twins, a person skips "
      "line 0 and line 1 is edited to ½ cup and computed during b's fetch — "
      'decided 1, moved 1', () async {
    final db = wp.tempDb();
    final provider = wp.Gated(FixtureProvider(pending: pendingSearches));
    await matchAndCompute(db, provider, wp.saveLines(db, [quarter], id: 'b'));
    final c = wp.saveLines(db, [quarter, quarter], id: 'c');
    await matchAndCompute(db, provider, c);
    provider.onCall = () async {
      await applyMatchOverride(db, FixtureProvider(), c, 0, {
        'raw': quarter,
        'skipped': true,
      });
      await matchAndCompute(
        db,
        FixtureProvider(pending: pendingSearches),
        wp.saveLines(db, [quarter, wp.oil], id: 'c'),
      );
    };
    final res = await applyOil(db, provider);
    expect((res.lines, res.decided, res.moved), (1, 1, 1));
  });

  test(
    'failed_lines counts only the lines not settled before the failure: '
    "c [¼ cup oil, ¼ cup oil, celery], line 0 skipped during b's fetch "
    "(decided), and c's totals cannot recompute (celery's detail gone "
    'from the cache, FDC failing) — failed 1, failed_lines 1, decided 1',
    () async {
      final (db, path) = fileDb();
      addTearDown(db.dispose);
      final inner = FixtureProvider(pending: pendingSearches);
      await matchAndCompute(db, inner, wp.saveLines(db, [quarter], id: 'b'));
      final c = wp.saveLines(db, [quarter, quarter, wp.celery], id: 'c');
      await matchAndCompute(db, inner, c);
      final celery = db.ingredientMatchesFor('c')[2].fdcId!;
      final provider = wp.Gated(_FailFood(inner, celery))
        ..onCall = () async {
          await applyMatchOverride(db, inner, c, 0, {
            'raw': quarter,
            'skipped': true,
          });
          sqlite3.open(path)
            ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [celery])
            ..execute('DELETE FROM fdc_search_cache')
            ..dispose();
        };
      final res = await applyOil(db, provider);
      expect(
        (res.lines, res.decided, res.failed, res.failedLines),
        (1, 1, 1, 1),
      );
    },
  );

  group('Opus critic 3: a line hold read from the recipe now, never the '
      "row's stored hold", () {
    const tbsp = '3 tablespoons all-purpose flour'; // 0006's
    Future<FdcFood> breadFlour() async {
      final f = (await FixtureProvider().food(168913))!;
      return FdcFood(
        fdcId: f.fdcId,
        description: f.description,
        dataType: f.dataType,
        nutrientsPer100g: f.nutrientsPer100g,
        portions: const [],
      );
    }

    Future<(SaltDatabase, Recipe)> stepless() async {
      final db = wp.tempDb();
      final a = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
      final noSteps = a.copyWith(steps: const []);
      db.upsertRecipe(noSteps, sourceSlug: 'src', contentHash: 'hp');
      await matchAndCompute(
        db,
        FixtureProvider(pending: pendingSearches),
        noSteps,
      );
      expect(db.ingredientMatchesFor(a.id)[8].hold, isNull); // counted
      return (db, a);
    }

    test('0148 computed with no steps (the dredge flour counted, hold '
        'null), then saved with its steps (stale): a decision on '
        'all-purpose flour does not reach line 8 — the detector holds it '
        '`coating` now', () async {
      final (db, a) = await stepless();
      db.upsertRecipe(a, sourceSlug: 'src', contentHash: 'ha');
      final reach = decisionReach(
        db,
        'all-purpose flour',
        excluding: (recipeId: 'zz', position: 0),
        fdcId: 168913,
      );
      expect([
        for (final r in reach) '${r.recipeId}:${r.position}',
      ], isNot(contains('${a.id}:8')));
    }, skip: skipIfNoCorpus);

    test('reached on the step-less recipe, 0148 saved with its steps during '
        "an earlier target's portion fetch: line 8 is held at its turn — "
        'not written, counted moved (left for its compute)', () async {
      final (db, a) = await stepless();
      final provider = wp.Gated(FixtureProvider(pending: pendingSearches));
      await matchAndCompute(db, provider, wp.saveLines(db, [tbsp], id: '0000'));
      provider.onCall = () async {
        db.upsertRecipe(a, sourceSlug: 'src', contentHash: 'ha');
      };
      final res = await applyDecisionToOthers(
        db,
        provider,
        itemKey: 'all-purpose flour',
        decided: await breadFlour(),
        excluding: (recipeId: 'zz', position: 0),
      );
      expect((res.lines, res.moved, res.decided, res.gone), (1, 1, 0, 0));
      expect(db.ingredientMatchesFor(a.id)[8].fdcId, 789890);
      expect(db.ingredientMatchesFor('0000').single.fdcId, 168913);
    }, skip: skipIfNoCorpus);
  });

  group("apply-to-all's identity lookup (O11, S10)", () {
    test(
      'O11: c [¼ cup oil, onion] saved as [onion, ¼ cup oil] and laid out '
      "during b's fetch: the oil row is found by identity at 1, never the "
      "onion row standing at the oil's old position — written, not gone",
      () async {
        final db = wp.tempDb();
        final provider = wp.Gated(FixtureProvider(pending: pendingSearches));
        await matchAndCompute(
          db,
          provider,
          wp.saveLines(db, [quarter], id: 'b'),
        );
        await matchAndCompute(
          db,
          provider,
          wp.saveLines(db, [quarter, wp.onion], id: 'c'),
        );
        provider.onCall = () async {
          layoutMatchRows(db, wp.saveLines(db, [wp.onion, quarter], id: 'c'));
        };
        final res = await applyOil(db, provider);
        expect((res.lines, res.gone, res.moved), (2, 0, 0));
        expect(db.ingredientMatchesFor('c')[1].fdcId, 173468);
      },
    );

    test('S10: twins [¼ cup oil, ¼ cup oil] in c, saved as [onion, oil, oil] '
        "and laid out during b's fetch (both rows shifted): each twin takes "
        'its own row — both written, none twice', () async {
      final db = wp.tempDb();
      final provider = wp.Gated(FixtureProvider(pending: pendingSearches));
      await matchAndCompute(db, provider, wp.saveLines(db, [quarter], id: 'b'));
      await matchAndCompute(
        db,
        provider,
        wp.saveLines(db, [quarter, quarter], id: 'c'),
      );
      provider.onCall = () async {
        layoutMatchRows(
          db,
          wp.saveLines(db, [wp.onion, quarter, quarter], id: 'c'),
        );
      };
      final res = await applyOil(db, provider);
      expect((res.lines, res.gone, res.moved), (3, 0, 0));
      expect(
        [for (final r in db.ingredientMatchesFor('c')) r.fdcId],
        [173468, 173468],
      );
      expect(
        [for (final r in db.ingredientMatchesFor('c')) r.position],
        [1, 2],
      );
    });
  });

  test("S11/O16: sameMatchRow is the whole identity — 0405's oil row as "
      'computed differs from itself rewritten with only its status, '
      'confidence, gram source, hold or description changed', () async {
    final db = wp.tempDb();
    await matchAndCompute(
      db,
      FixtureProvider(pending: pendingSearches),
      wp.saveLines(db, [wp.oil]),
    );
    final row = wp.row(db);
    expect(row.hold, isNull);
    expect(sameMatchRow(row, row.copyWith()), isTrue);
    for (final (what, other) in [
      ('status', row.copyWith(status: 'confirmed')),
      ('confidence', row.copyWith(confidence: row.confidence + 0.01)),
      (
        'gramSource',
        row.copyWith(
          gramSource: row.gramSource == 'weight' ? 'portion' : 'weight',
        ),
      ),
      ('hold', row.copyWith(hold: 'coating')),
      ('description', row.copyWith(description: '${row.description} (b)')),
    ]) {
      expect(sameMatchRow(row, other), isFalse, reason: what);
      expect(sameMatchRow(other, row), isFalse, reason: what);
    }
  });

  test(
    'S14: the drift term is a distance — twins [¼ cup oil, ¼ cup oil] '
    'computed, saved as [onion, celery, ¼ cup oil] (two lines inserted, '
    'one twin deleted): the kept line takes the NEAREST twin (row 1, '
    'one away), never row 0 (two away), whose signed drift is smaller',
    () async {
      final db = wp.tempDb();
      await matchAndCompute(
        db,
        FixtureProvider(pending: pendingSearches),
        wp.saveLines(db, [quarter, quarter]),
      );
      final paired = pairRowsToLines(
        db.ingredientMatchesFor('r'),
        [
          for (final raw in [wp.onion, wp.celery, quarter]) wp.lineOf(raw),
        ],
        laidOut: db.layoutOf('r').lines,
      );
      expect([for (final row in paired) row?.position], [null, null, 1]);
    },
  );

  group("S15: the matches GET's carried-row fallbacks and hold_note", () {
    Map<String, Object?>? matchOf(Map<String, Object?> body, int at) =>
        ((body['items']! as List<Object?>)[at]!
                as Map<String, Object?>)['match']
            as Map<String, Object?>?;

    test("a confirmed '½ cup oil' edited to ¼ cup, the caches emptied (its "
        "grams need a fetch a GET never makes): shown as the person's "
        'confirm with NO grams, carried from the old text', () async {
      final (db, path) = fileDb();
      addTearDown(db.dispose);
      final provider = FixtureProvider(pending: pendingSearches);
      final r = wp.saveLines(db, [wp.oil]);
      await matchAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 0, {
        'raw': wp.oil,
        'confirmed': true,
      });
      expect(wp.row(db).grams, isNotNull);
      final edited = wp.saveLines(db, [quarter]);
      sqlite3.open(path)
        ..execute('DELETE FROM fdc_food_cache')
        ..execute('DELETE FROM fdc_search_cache')
        ..dispose();
      final match = matchOf(await matchesBody(db, provider, edited), 0)!;
      expect(match['status'], 'confirmed');
      expect(match['fdc_id'], wp.row(db).fdcId);
      expect(match['grams'], isNull);
      expect(match['gram_source'], isNull);
      expect(match['carried_from'], wp.oil);
    });

    test("an engine row of another text (the '½ cup oil' auto row, the line "
        'edited to ¼ cup, not computed) is shown as no match', () async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      await matchAndCompute(db, provider, wp.saveLines(db, [wp.oil]));
      expect(wp.row(db).status, 'auto');
      final edited = wp.saveLines(db, [quarter]);
      expect(matchOf(await matchesBody(db, provider, edited), 0), isNull);
    });

    test(
      'hold_note is the kept liquid of a HELD partial pour-away only: '
      "0129 Mahogany's soy sauce, then skipped (no hold) — no note",
      () async {
        final db = wp.tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        final a = loadCorpusRecipe('0129-mahogany-chicken-thighs.yaml');
        db.upsertRecipe(a, sourceSlug: 'src', contentHash: 'h');
        await matchAndCompute(db, provider, a);
        final held = matchOf(await matchesBody(db, provider, a), 1)!;
        expect(held['hold'], 'partial_pour_away');
        expect(held['hold_note'], isNotNull);
        await applyMatchOverride(db, provider, a, 1, {
          'raw': '1 cup soy sauce',
          'skipped': true,
        });
        final skipped = matchOf(await matchesBody(db, provider, a), 1)!;
        expect(skipped['hold'], isNull);
        expect(skipped['hold_note'], isNull);
      },
      skip: skipIfNoCorpus,
    );

    test('a row stored with an EMPTY key still fits its own line by its '
        "text's key (0405's oil row, its item_key blanked)", () async {
      final db = wp.tempDb();
      await matchAndCompute(
        db,
        FixtureProvider(pending: pendingSearches),
        wp.saveLines(db, [wp.oil]),
      );
      final blank = wp.row(db).copyWith(itemKey: '');
      final paired = pairRowsToLines([blank], [wp.lineOf(quarter)]);
      expect(paired.single?.position, 0);
    });
  });

  group('the pass cap in both job loops: a recipe still stale after '
      'maxComputePasses is logged and counted failed, never done', () {
    // Each search saves the recipe with a new line (synthesized words FDC
    // answers with no hits), so every pass's stamp is stale (as the v22 cap
    // pin).
    (SaltDatabase, NutritionProvider) restless() {
      final db = wp.tempDb();
      final inner = FixtureProvider(pending: <String>{'zqa'});
      var saves = 0;
      final provider = _OnSearch(inner, () {
        saves++;
        final word = 'zq${String.fromCharCode(97 + saves)}';
        inner.pending.add(word);
        wp.saveLines(db, ['½ teaspoon table salt', '1 cup $word']);
      });
      wp.saveLines(db, ['½ teaspoon table salt', '1 cup zqa']);
      return (db, provider);
    }

    Future<Map<String, Object?>> settled(SaltDatabase db, int jobId) async {
      for (var i = 0; i < 200; i++) {
        final job = db.nutritionJob(jobId)!;
        if (job['status'] != 'running') {
          return job;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('job $jobId never settled');
    }

    test("the recipe's own compute job", () async {
      final (db, provider) = restless();
      final job = await settled(
        db,
        startRecipeComputeJob(db, provider, db.recipeByIdOrSlug('r')!.recipe),
      );
      expect((job['status'], job['done'], job['failed']), ('failed', 0, 1));
      expect(job['log'], [
        'r: Bad state: still stale after $maxComputePasses compute passes',
      ]);
    });

    test('the bulk sweep', () async {
      final (db, provider) = restless();
      final job = await settled(db, startBulkJob(db, provider)!);
      expect((job['status'], job['done'], job['failed']), ('done', 1, 1));
      expect(job['log'], [
        'r: Bad state: still stale after $maxComputePasses compute passes',
      ]);
    });
  });
}

/// A provider that runs the next of [hooks] before each call.
class _Hooked implements NutritionProvider {
  _Hooked(this.inner, this.hooks);
  final NutritionProvider inner;
  final List<void Function()> hooks;
  void _fire() {
    if (hooks.isNotEmpty) {
      hooks.removeAt(0)();
    }
  }

  @override
  Future<List<FdcCandidate>> search(String query) async {
    _fire();
    return inner.search(query);
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    _fire();
    return inner.food(fdcId);
  }
}

/// A provider whose detail of [failing] throws (FDC failing).
class _FailFood implements NutritionProvider {
  _FailFood(this.inner, this.failing);
  final NutritionProvider inner;
  final int failing;

  @override
  Future<List<FdcCandidate>> search(String query) => inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) =>
      fdcId == failing ? throw StateError('FDC failing') : inner.food(fdcId);
}

/// A provider that runs [onSearch] before each search.
class _OnSearch implements NutritionProvider {
  _OnSearch(this.inner, this.onSearch);
  final NutritionProvider inner;
  final void Function() onSearch;

  @override
  Future<List<FdcCandidate>> search(String query) {
    onSearch();
    return inner.search(query);
  }

  @override
  Future<FdcFood?> food(int fdcId) => inner.food(fdcId);
}
