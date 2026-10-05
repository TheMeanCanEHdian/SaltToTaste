// RULE A, matcher v28 (brief I1 + I2 server side — Run 058 O1/S1, Sonnet
// critic 2, S2/S3, Opus critic 1 / S27, Opus critic 3, O10, S12, O7/S13,
// Opus critic 2, O8, Sonnet critics 1 & 3, O13, O15/S17): "derived for"
// names EVERY input a derivation reads — the recipe's inputs (the key) AND
// the food caches (a `food_gone` row re-read cache-only on every compute)
// AND the food's nutrient record (its sibling, resolved where the food is);
// a provider failure has TWO classes (GLOBAL stops the job, FOOD is the
// row's: underived, counted, held `food_unavailable`); a pass that throws
// leaves no row marked derived; one ACTION TABLE per hold family
// (salt_shared `holdActions`) read by the PUT's gate and the queue's SQL.
//
// Real corpus recipes (0857 Rich Chocolate Bundt Cake, 0148 Crispy Fried
// Chicken, 0129 Indoor Pulled Chicken, 0506's napa line) and recorded FDC
// answers (FixtureProvider), never the network. Synthesized, each a stated
// exception: FDC's "no such food" (FixtureProvider.superseded, cache rows
// deleted), an outage or a per-food failure (provider wrappers that throw
// NutritionProviderException with the scope FdcProvider gives it), the
// retired id 999000111 (Run 057 S5's: no real row names it), a title edit
// (stale), a hand-set hold on a stored row for the SQL parity table, and
// interleavings run inside a provider call.
// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'nutrition_v23_writepath_test.dart' as v23;
import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'nutrition_v27_rule_a_test.dart' as ra;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// 0506's napa line: its record 2727583 reads its nutrients from 169979.
const napa = '12 ounces napa cabbage (½ medium head), cored and minced';
const napaId = 2727583;
const napaSibling = 169979;

/// Run 057 S5's retired id: no real row can name it (a stated exception).
const poisoned = 999000111;

/// Wraps [inner]; food requests for [ids] answer "no such food" (`gone`)
/// or throw [failWith] with [scope]. Counts the requests for [ids].
class FoodFault implements NutritionProvider {
  FoodFault(
    this.inner,
    this.ids, {
    this.gone = false,
    this.failWith = 'FoodData Central error 500.',
    this.scope = FailureScope.global,
  });

  final NutritionProvider inner;
  final Set<int> ids;
  bool gone;
  bool up = false;
  final String failWith;
  final FailureScope scope;
  int asked = 0;

  @override
  Future<List<FdcCandidate>> search(String query) => inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) async {
    if (!ids.contains(fdcId) || up) {
      return inner.food(fdcId);
    }
    asked += 1;
    if (gone) {
      return null;
    }
    throw NutritionProviderException(failWith, scope: scope);
  }
}

/// Deletes [id] from every cache of the database at [path]; returns the
/// search answers that held it (to put back).
List<Map<String, Object?>> dropFood(String path, int id) {
  final raw = sqlite3.open(path);
  final answers = [
    for (final row in raw.select(
      'SELECT query, response FROM fdc_search_cache WHERE response LIKE '
      "'%\"fdc_id\":' || ? || ',%'",
      [id],
    ))
      {'query': row['query'], 'response': row['response']},
  ];
  raw
    ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [id])
    ..execute(
      "DELETE FROM fdc_search_cache WHERE response LIKE '%\"fdc_id\":' || ? || ',%'",
      [id],
    )
    ..dispose();
  return answers;
}

/// Puts [answers] back into the search cache at [path], raw (a writer the
/// triggers of migration 016 see like any other).
void putBack(String path, List<Map<String, Object?>> answers) {
  final raw = sqlite3.open(path);
  for (final row in answers) {
    raw.execute(
      'INSERT OR REPLACE INTO fdc_search_cache (query, response) VALUES (?, ?)',
      [row['query'], row['response']],
    );
  }
  raw.dispose();
}

/// The matches GET's view of [position].
Future<Map<String, Object?>> getOf(
  SaltDatabase db,
  Recipe r,
  int position,
) async =>
    ((await matchesBody(
                  db,
                  FixtureProvider(pending: pendingSearches),
                  r,
                ))['items']!
                as List)
            .cast<Map<String, Object?>>()[position]['match']!
        as Map<String, Object?>;

/// Runs [onFood] for every food request (it throws or returns normally to
/// fall through to [inner]).
class _OnFood implements NutritionProvider {
  _OnFood(this.onFood, this.inner);
  final void Function(int fdcId) onFood;
  final NutritionProvider inner;

  @override
  Future<List<FdcCandidate>> search(String query) => inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) async {
    onFood(fdcId);
    return inner.food(fdcId);
  }
}

/// Every search fails (an outage of the search endpoint alone).
class _SearchDown implements NutritionProvider {
  _SearchDown(this.inner);
  final NutritionProvider inner;

  @override
  Future<List<FdcCandidate>> search(String query) =>
      throw const NutritionProviderException('outage (search)');

  @override
  Future<FdcFood?> food(int fdcId) => inner.food(fdcId);
}

void main() {
  group(
    'I1(a) O1/S1: a food_gone row is re-read from the caches on every compute',
    () {
      test(
        "0857's confirmed flour: gone (404, no cache) → a search answer lists "
        'it again → the next compute counts it (248 g), the GET and the row '
        'agree, at most one request; with no cache holding it, none',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
          await d.editAndCompute(db, fixture, r);
          final i = d.at(r, a.flour0857);
          await applyMatchOverride(db, fixture, r, i, {
            'raw': a.flour0857,
            'confirmed': true,
          });
          final id = d.rowOf(db, r, i).fdcId!;
          final answers = dropFood(path, id);
          expect(answers, isNotEmpty, reason: 'a search answer held the flour');
          final gone = FixtureProvider(
            pending: pendingSearches,
            superseded: {id},
          );
          await matchAndCompute(db, gone, r);
          expect(d.rowOf(db, r, i).hold, foodGoneHold);
          expect(nutritionIsFresh(db, r), isTrue);
          // No cache holds it: the next compute asks nothing (the shortcut).
          var calls = gone.foodCalls;
          await matchAndCompute(db, gone, r);
          expect(gone.foodCalls - calls, 0);
          expect(d.rowOf(db, r, i).hold, foodGoneHold);
          // A search answer lists it again (another line's search, a fresh
          // search): the next compute derives it — cache-only.
          putBack(path, answers);
          final get = await getOf(db, r, i);
          expect(get['hold'], isNull);
          expect(get['grams']! as double, closeTo(248.06, 0.01));
          calls = gone.foodCalls;
          await matchAndCompute(db, gone, r);
          expect(gone.foodCalls - calls, lessThanOrEqualTo(1));
          final row = d.rowOf(db, r, i);
          expect(row.hold, isNull);
          expect(row.grams, closeTo(248.06, 0.01));
          expect(row.grams, get['grams']);
          expect(nutritionIsFresh(db, r), isTrue);
          expect(db.nutritionFor(r.id)!.status, 'complete');
        },
      );
    },
    skip: skipIfNoCorpus,
  );

  group(
    'I1(b) Sonnet critic 2 / S2 / S3 / O13: the nutrient sibling is resolved inside the derivation',
    () {
      test('a decided napa row (2727583) whose sibling 169979 FDC retired: '
          'food_gone on the compute, never "3 passes"', () async {
        final (db, path) = a.pathDb();
        final fixture = FixtureProvider(pending: pendingSearches);
        final r = wp.saveLines(db, [napa]);
        await applyMatchOverride(db, fixture, r, 0, {
          'raw': napa,
          'fdc_id': napaId,
        });
        expect(d.rowOf(db, r, 0).hold, isNull);
        // The sibling leaves every cache; FDC answers "no such food".
        dropFood(path, napaSibling);
        final retired = FoodFault(fixture, {napaSibling}, gone: true);
        expect(await computeUntilFresh(db, retired, r), 1);
        expect(retired.asked, 1);
        final row = d.rowOf(db, r, 0);
        expect(row.status, 'overridden');
        expect(row.hold, foodGoneHold);
        expect(nutritionIsFresh(db, r), isTrue);
        // Held: the next compute asks nothing.
        await computeUntilFresh(db, retired, r);
        expect(retired.asked, 1);
      });

      test(
        'an ENGINE napa row whose sibling FDC retired is re-matched (the '
        'candidate passed over), never "still stale after 3 compute passes"',
        () async {
          final db = wp.tempDb();
          final retired = FoodFault(
            FixtureProvider(pending: pendingSearches),
            {napaSibling},
            gone: true,
          );
          final r = wp.saveLines(db, [napa]);
          expect(await computeUntilFresh(db, retired, r), 1);
          expect(d.rowOf(db, r, 0).fdcId, isNot(napaId));
          expect(nutritionIsFresh(db, r), isTrue);
        },
      );

      test('O13: the sibling fetch failing (an outage) on an engine row: the '
          "provider's reason after ONE request, never a StateError", () async {
        final db = wp.tempDb();
        final down = FoodFault(FixtureProvider(pending: pendingSearches), {
          napaSibling,
        }, failWith: 'FDC unavailable');
        final r = wp.saveLines(db, [napa]);
        await expectLater(
          computeUntilFresh(db, down, r),
          throwsA(
            isA<NutritionProviderException>().having(
              (e) => e.message,
              'message',
              'FDC unavailable',
            ),
          ),
        );
        expect(down.asked, 1);
      });

      test('S3: a PUT pick of napa with its sibling in no cache fetches it — '
          'counted and fresh; in an outage the row is underived, then derived '
          'when FDC is back', () async {
        final (db, path) = a.pathDb();
        final fixture = FixtureProvider(pending: pendingSearches);
        final r = wp.saveLines(db, [napa]);
        await matchAndCompute(db, fixture, r);
        dropFood(path, napaSibling);
        final down = FoodFault(fixture, {napaSibling});
        await applyMatchOverride(db, down, r, 0, {
          'raw': napa,
          'fdc_id': napaId,
        });
        expect(down.asked, greaterThanOrEqualTo(1));
        expect(d.rowOf(db, r, 0).derivedSeq, isNull, reason: 'underived');
        expect(nutritionIsFresh(db, r), isFalse);
        down.up = true;
        expect(await computeUntilFresh(db, down, r), 1);
        expect(d.rowOf(db, r, 0).derivedSeq, isNotNull);
        expect(nutritionIsFresh(db, r), isTrue);
        expect(db.nutritionFor(r.id)!.matchedCount, 1);
        // With FDC up all along: the PUT alone counts it.
        final (db2, path2) = a.pathDb();
        final r2 = wp.saveLines(db2, [napa]);
        await matchAndCompute(db2, fixture, r2);
        dropFood(path2, napaSibling);
        await applyMatchOverride(db2, fixture, r2, 0, {
          'raw': napa,
          'fdc_id': napaId,
        });
        expect(nutritionIsFresh(db2, r2), isTrue);
        expect(db2.nutritionFor(r2.id)!.matchedCount, 1);
      });

      test('a PUT on a decided napa row whose sibling FDC retired derives '
          'food_gone, and apply_to_all on it is refused (422)', () async {
        final (db, path) = a.pathDb();
        final fixture = FixtureProvider(pending: pendingSearches);
        final r = wp.saveLines(db, [napa]);
        await matchAndCompute(db, fixture, r);
        dropFood(path, napaSibling);
        final retired = FoodFault(fixture, {napaSibling}, gone: true);
        await expectLater(
          applyMatchOverride(db, retired, r, 0, {
            'raw': napa,
            'fdc_id': napaId,
            'apply_to_all': true,
          }),
          throwsA(isA<ValidationException>()),
        );
        await applyMatchOverride(db, retired, r, 0, {
          'raw': napa,
          'fdc_id': napaId,
        });
        expect(d.rowOf(db, r, 0).hold, foodGoneHold);
        expect(
          db.decisionFor(lineKeyOf(nutritionLines(r).single)),
          isNull,
          reason: 'a food with no record is never decided library-wide',
        );
      });
    },
    skip: skipIfNoCorpus,
  );

  group('I1(c) Opus critic 1 / S27: two failure classes', () {
    /// a and b stale, a's one decided row on [poisoned] (the retired id),
    /// grams typed (10 g, kept as the decision when held).
    Future<(SaltDatabase, Recipe, Recipe)> twoStale() async {
      final db = wp.tempDb();
      final fixture = FixtureProvider(pending: pendingSearches);
      var a0 = wp.saveLines(db, [v23.quarter], id: 'a');
      await matchAndCompute(db, fixture, a0);
      var b0 = wp.saveLines(db, [v23.quarter], id: 'b');
      await matchAndCompute(db, fixture, b0);
      final line = nutritionLines(a0).single;
      db.upsertIngredientMatch(
        IngredientMatchRow(
          recipeId: 'a',
          position: 0,
          raw: line.raw,
          fdcId: poisoned,
          description: 'Retired food',
          dataType: 'SR Legacy',
          confidence: 1,
          grams: 10,
          gramSource: 'override',
          status: 'overridden',
          itemKey: lineKeyOf(line),
        ),
        layoutSeq: db.layoutSeqOf('a'),
      );
      a0 = wp.saveLines(db, [v23.quarter, '1 teaspoon table salt'], id: 'a');
      b0 = wp.saveLines(db, [v23.quarter, '1 teaspoon table salt'], id: 'b');
      return (db, a0, b0);
    }

    Future<Map<String, Object?>> sweep(
      SaltDatabase db,
      NutritionProvider p,
    ) async {
      final job = startBulkJob(db, p, scope: BulkScope.stale)!;
      await ra.settle();
      return db.nutritionJob(job)!;
    }

    test("a FOOD failure on a's decided row: every sweep computes b, a's row "
        'is underived then held food_unavailable at the third, the job done '
        "with a's reason logged", () async {
      final (db, ra0, rb0) = await twoStale();
      final p = FoodFault(
        FixtureProvider(pending: pendingSearches),
        {poisoned},
        failWith: 'FoodData Central error 400.',
        scope: FailureScope.food,
      );
      expect(bulkScopeIds(db, BulkScope.stale), ['a', 'b']);
      for (var n = 1; n <= 4; n++) {
        final job = await sweep(db, p);
        expect(job['status'], 'done', reason: 'sweep $n');
        expect(job['failed'], 0, reason: "a's row's state, never a failure");
        expect(
          nutritionIsFresh(db, rb0),
          isTrue,
          reason: 'b computed, sweep $n',
        );
        final row = d.rowOf(db, ra0, 0);
        if (n < foodUnavailableAfter) {
          expect(row.derivedSeq, isNull, reason: 'underived, sweep $n');
          expect(row.hold, isNull);
          expect(job['log'], contains('a: FoodData Central error 400.'));
          expect(bulkScopeIds(db, BulkScope.stale), ['a']);
        } else {
          expect(row.hold, foodUnavailableHold, reason: 'held, sweep $n');
          expect(nutritionIsFresh(db, ra0), isTrue);
          expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
        }
      }
      expect(p.asked, foodUnavailableAfter, reason: 'held: never asked again');
      expect(db.nutritionFor('a')!.status, 'partial');
    });

    test('a GLOBAL failure (a bad key) still stops at the first recipe with '
        'its message', () async {
      final (db, _, rb0) = await twoStale();
      final p = FoodFault(
        FixtureProvider(pending: pendingSearches),
        {poisoned},
        failWith: 'FoodData Central rejected the API key.',
      );
      final job = await sweep(db, p);
      expect(job['status'], 'failed');
      expect(
        job['log'],
        contains('stopped at a: FoodData Central rejected the API key.'),
      );
      expect(nutritionIsFresh(db, rb0), isFalse, reason: 'stopped before b');
    });
  });

  group(
    'I1(d) Opus critic 3: a pass that throws leaves the recipe stale (v29: '
    'its in-progress marker)',
    () {
      test("0129: the confirmed smoke derived, a later engine line's search "
          'failing — not fresh, in the stale scope; FDC back → fresh, the '
          'clean compute', () async {
        final (db, path) = a.pathDb();
        final fixture = FixtureProvider(pending: pendingSearches);
        final r = loadCorpusRecipe('0129-indoor-pulled-chicken.yaml');
        wp.saveRecipe(db, r);
        await matchAndCompute(db, fixture, r);
        final i = d.at(r, d.smoke0129);
        final lines = nutritionLines(r);
        final raw = sqlite3.open(path);
        addTearDown(raw.dispose);
        raw.execute('DELETE FROM fdc_food_cache');
        final outage = a.Outage(fixture)..down = true;
        await applyMatchOverride(db, outage, r, i, {
          'raw': d.smoke0129,
          'confirmed': true,
        });
        expect(d.rowOf(db, r, i).derivedSeq, isNull);
        expect(nutritionStampCurrent(db, r), isTrue);
        // The answer of the last engine line after the smoke leaves the cache.
        var dropped = false;
        for (var p = lines.length - 1; p > i && !dropped; p--) {
          final m = db.ingredientMatchesFor(r.id).where((x) => x.position == p);
          if (m.isEmpty || m.single.status != 'auto') continue;
          final w = weighedLine(r, lines[p]);
          final s = lineSearchFor(
            db,
            normalizeItem(lineItemOf(w)),
            lineKeyOf(w),
          );
          raw.execute('DELETE FROM fdc_search_cache WHERE query = ?', [
            s.answer,
          ]);
          dropped = raw.updatedRows > 0;
        }
        expect(dropped, isTrue);
        final searchDown = _SearchDown(fixture);
        await expectLater(
          computeUntilFresh(db, searchDown, r),
          throwsA(isA<NutritionProviderException>()),
        );
        // v29 (Run 059 Opus critic 1): ONE mechanism — the thrown pass
        // releases its own in-progress mark and clears the stamp, so the
        // recipe reads stale whatever the pass marked derived.
        expect(d.rowOf(db, r, i).derivedSeq, isNotNull, reason: 'marked');
        expect(db.nutritionFor(r.id)!.computing, 0);
        expect(
          db.nutritionFor(r.id)!.ingredientsHash,
          startsWith(SaltDatabase.interruptedStamp),
        );
        expect(nutritionIsFresh(db, r), isFalse);
        expect(bulkScopeIds(db, BulkScope.stale), contains(r.id));
        await computeUntilFresh(db, fixture, r);
        expect(nutritionIsFresh(db, r), isTrue);
        final kcal = db.nutritionFor(r.id)!.caloriesPerServing;
        await matchAndCompute(db, fixture, r);
        expect(db.nutritionFor(r.id)!.caloriesPerServing, kcal);
        expect(d.rowOf(db, r, i).grams, isNotNull);
      });
    },
    skip: skipIfNoCorpus,
  );

  group(
    'I1(e) O10: markDerivedIfUnchanged writes only over the row it read',
    () {
      test("0129's confirmed smoke, a title edit, the caches emptied: a "
          "person's typed grams during the compute's first search stay "
          'UNDERIVED (the guard), the recipe not fresh', () async {
        final (db, path) = a.pathDb();
        final fixture = FixtureProvider(pending: pendingSearches);
        final r = loadCorpusRecipe('0129-indoor-pulled-chicken.yaml');
        wp.saveRecipe(db, r);
        await matchAndCompute(db, fixture, r);
        final i = d.at(r, d.smoke0129);
        await applyMatchOverride(db, fixture, r, i, {
          'raw': d.smoke0129,
          'confirmed': true,
        });
        await matchAndCompute(db, fixture, r);
        final edited = r.copyWith(title: '${r.title} (edited)');
        wp.saveRecipe(db, edited);
        final fdc = d.rowOf(db, edited, i).fdcId!;
        sqlite3.open(path)
          ..execute('DELETE FROM fdc_search_cache')
          ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [fdc])
          ..dispose();
        final outage = a.Outage(fixture)..down = true;
        final compute = ra.PutDuringFirstSearch(fixture, () async {
          await applyMatchOverride(db, outage, edited, i, {
            'raw': d.smoke0129,
            'grams': 5,
          });
        });
        await matchAndCompute(db, compute, edited);
        final row = d.rowOf(db, edited, i);
        expect(row.grams, 5);
        expect(row.derivedSeq, isNull);
        expect(nutritionIsFresh(db, edited), isFalse);
      });
    },
    skip: skipIfNoCorpus,
  );

  group('I2: ONE action table per hold family (salt_shared holdActions)', () {
    test(
      "the queue's SQL reads the table: for EVERY hold, the bucket equals "
      "matchBucketFor's and `finishes` (per line, per group, finishable) "
      'equals "a confirm finishes it" — a food with no record never',
      () async {
        // v41: the queue's finishes read the confirm-cannot-finish list,
        // which now holds the reference lines no recipe counts beside the
        // food with no record (noRecordHoldsSql keeps the `check` arm).
        expect(
          SaltDatabase.noConfirmHoldsSql,
          [for (final h in holdsAConfirmCannotFinish) "'$h'"].join(', '),
        );
        final db = wp.tempDb();
        final fixture = FixtureProvider(pending: pendingSearches);
        // v41: the reference holds (HoldKind.recipe) sit on no-food rows of
        // their own bucket, `choose_recipe` — step 3's queue pins read them;
        // every FOOD-row hold is judged here as before.
        final holds = [
          null,
          ...holdActions.keys.where(
            (h) => holdActionsOf(h).kind != HoldKind.recipe,
          ),
        ];
        final expected = <String, bool>{};
        for (final (n, hold) in holds.indexed) {
          final r = wp.saveLines(db, [v23.quarter], id: 'h$n');
          await matchAndCompute(db, fixture, r);
          final row = db.ingredientMatchesFor(r.id).single;
          // Synthesized (stated): the hold set by hand on a real row, as the
          // engine (auto) or a person's derivation (confirmed) stores it.
          final noRecord = holdsAConfirmCannotFinish.contains(hold);
          final held = row.copyWith(
            status: noRecord ? 'confirmed' : 'auto',
            hold: hold,
            clearHold: hold == null,
            confidence: hold == null ? 0.3 : 1,
            grams: 10,
            gramSource: noRecord ? 'override' : 'volume',
          );
          db.upsertIngredientMatch(held, layoutSeq: db.layoutSeqOf(r.id));
          final bucket = matchBucketFor(
            status: held.status,
            fdcId: held.fdcId,
            grams: held.grams,
            confidence: held.confidence,
            hold: held.hold,
            gramSource: held.gramSource,
          );
          expect(bucket, MatchBucket.check, reason: '$hold');
          expected[r.id] = holdActionsOf(hold).finishes.contains(
            HoldDecision.confirm,
          );
        }
        final lines = db.nutritionReviewLines(limit: 1000, offset: 0);
        final groups = db.nutritionReviewGroups(limit: 1000, offset: 0);
        for (final MapEntry(key: id, value: finishes) in expected.entries) {
          final line = lines.singleWhere((l) => l.match.recipeId == id);
          expect(line.bucket, 'check', reason: id);
          expect(
            line.finishes == 1,
            finishes,
            reason: '$id ${line.match.hold}',
          );
          expect(
            groups.any((g) => g.finishesRecipes.any((f) => f.id == id)),
            finishes,
            reason: '$id: a group names it finished',
          );
        }
        expect(
          db.nutritionReviewFinishable().finishable,
          expected.values.where((f) => f).length,
        );
        expect(expected.values.where((f) => !f), hasLength(2));
      },
    );
  });

  group(
    'I2: the PUT gate reads the table (O7/S13, Opus critic 2)',
    () {
      test(
        "0148's 13 rows derived food_gone, the key decided 173468 elsewhere: "
        'a confirm or typed grams on line 0 is a 422 that asks FDC nothing '
        'and leaves the library decision 173468; a skip and a pick are '
        'accepted',
        () async {
          final r = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
          final db = wp.tempDb();
          wp.saveRecipe(db, r);
          await matchAndCompute(db, ra.Retired(), r);
          final lines = nutritionLines(r);
          for (final (i, line) in lines.indexed) {
            db.upsertIngredientMatch(
              IngredientMatchRow(
                recipeId: r.id,
                position: i,
                raw: line.raw,
                fdcId: poisoned,
                description: 'Retired food',
                dataType: 'SR Legacy',
                confidence: 1,
                grams: 10,
                gramSource: 'weight',
                status: 'confirmed',
                itemKey: lineKeyOf(line),
              ),
              layoutSeq: db.layoutSeqOf(r.id),
            );
          }
          final gone = ra.Retired();
          await computeUntilFresh(db, gone, r);
          expect(d.rowOf(db, r, 0).hold, foodGoneHold);
          final key = lineKeyOf(lines[0]);
          db.putDecision(
            itemKey: key,
            item: decisionItemOf(lines[0]),
            fdcId: 173468,
            description: 'Oil, olive, salad or cooking',
            dataType: 'SR Legacy',
            decidedBy: null,
          );
          final calls = gone.foodCalls;
          for (final body in [
            {'confirmed': true},
            {'grams': 50},
            {'confirmed': true, 'grams': 50},
            {'confirmed': true, 'apply_to_all': true},
          ]) {
            await expectLater(
              applyMatchOverride(db, gone, r, 0, {
                'raw': lines[0].raw,
                ...body,
              }),
              throwsA(
                isA<ValidationException>().having(
                  (e) => e.message,
                  'message',
                  noRecordMessage,
                ),
              ),
              reason: '$body',
            );
          }
          expect(gone.foodCalls, calls, reason: 'refused before any request');
          expect(db.decisionFor(key)!.fdcId, 173468);
          expect(d.rowOf(db, r, 0).hold, foodGoneHold);
          await applyMatchOverride(db, gone, r, 1, {
            'raw': lines[1].raw,
            'skipped': true,
          });
          expect(d.rowOf(db, r, 1).status, 'skipped');
          await applyMatchOverride(db, FixtureProvider(), r, 0, {
            'raw': lines[0].raw,
            'fdc_id': 173468,
          });
          expect(d.rowOf(db, r, 0).hold, isNull, reason: 'a pick answers it');
        },
      );

      test('0857: a confirm whose derivation finds its food gone stores the '
          'decision held, never as the library decision', () async {
        final (db, path) = a.pathDb();
        final fixture = FixtureProvider(pending: pendingSearches);
        final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
        await d.editAndCompute(db, fixture, r);
        final i = d.at(r, a.flour0857);
        final id = d.rowOf(db, r, i).fdcId!;
        final key = lineKeyOf(nutritionLines(r)[i]);
        db.putDecision(
          itemKey: key,
          item: decisionItemOf(nutritionLines(r)[i]),
          fdcId: 168913,
          description: 'Wheat flour, white, bread, enriched',
          dataType: 'SR Legacy',
          decidedBy: null,
        );
        dropFood(path, id);
        final gone = FixtureProvider(
          pending: pendingSearches,
          superseded: {id},
        );
        await applyMatchOverride(db, gone, r, i, {
          'raw': a.flour0857,
          'confirmed': true,
        });
        expect(d.rowOf(db, r, i).hold, foodGoneHold);
        expect(db.decisionFor(key)!.fdcId, 168913);
      });
    },
    skip: skipIfNoCorpus,
  );

  group('S17/O15: failed_lines subtracts the lines settled before a throw', () {
    test(
      "c [¼ cup oil, ¼ cup oil]: the first target's weigh unavailable "
      '(FDC down), the second throwing an unexpected error — the recipe '
      'failed with ONE failed line (the unavailable one counted once)',
      () async {
        final (db, path) = a.pathDb();
        final fixture = FixtureProvider(pending: pendingSearches);
        await matchAndCompute(
          db,
          fixture,
          wp.saveLines(db, [v23.quarter, v23.quarter], id: 'c'),
        );
        dropFood(path, 173468);
        // Synthesized (stated): an outage, then an unexpected exception
        // (not a provider failure) on the next request. (An Error is never
        // counted `failed` since v29 — it propagates, Run 059 S29.)
        var calls = 0;
        final provider = _OnFood((id) {
          calls += 1;
          if (calls == 1) {
            throw const NutritionProviderException('outage');
          }
          throw const FormatException('unexpected');
        }, fixture);
        final res = await v23.applyOil(db, provider);
        expect(
          (res.unavailable, res.failed, res.failedLines, res.lines),
          (1, 1, 1, 0),
        );
      },
    );
  });

  group(
    "migration 016's search-cache food index (kept by triggers, backfilled once)",
    () {
      /// The ids a cached answer lists, by the old whole-cache scan.
      List<String> scanned(Database raw, int id) => [
        for (final row in raw.select(
          'SELECT query FROM fdc_search_cache WHERE instr(response, ?) > 0 '
          'ORDER BY rowid',
          ['{"fdc_id":$id,'],
        ))
          row['query'] as String,
      ];
      List<String> indexed(Database raw, int id) => [
        for (final row in raw.select(
          'SELECT f.query FROM fdc_search_cache_foods f JOIN fdc_search_cache c '
          'ON c.query = f.query WHERE f.fdc_id = ? ORDER BY c.rowid',
          [id],
        ))
          row['query'] as String,
      ];

      test('every writer keeps it equal to the scan: the put, a replacing '
          'put, a raw delete and a raw insert-or-replace; an upgrade from 15 '
          'backfills it', () async {
        final (db, path) = a.pathDb();
        final fixture = FixtureProvider();
        Future<String> answer(String q) async => jsonEncode([
          for (final hit in await fixture.search(q)) hit.toJson(),
        ]);
        final queries = [
          'garlic cloves',
          'sour cream',
          'butter',
          'vegetable oil',
        ];
        for (final q in queries) {
          db.fdcSearchCachePut(q, await answer(q));
        }
        final ids = {
          for (final q in queries)
            for (final hit in await fixture.search(q)) hit.fdcId,
        };
        final raw = sqlite3.open(path);
        addTearDown(raw.dispose);
        void same() {
          for (final id in ids) {
            expect(indexed(raw, id), scanned(raw, id), reason: '$id');
            expect(
              db.fdcSearchCacheHolding(id),
              [
                for (final q in scanned(raw, id)) db.fdcSearchCacheGet(q),
              ],
            );
          }
        }

        same();
        final garlic = (await fixture.search('garlic cloves')).first.fdcId;
        expect(indexed(raw, garlic), contains('garlic cloves'));
        db.fdcSearchCachePut('garlic cloves', '[]'); // a fresh answer drops it
        expect(indexed(raw, garlic), isNot(contains('garlic cloves')));
        same();
        raw.execute("DELETE FROM fdc_search_cache WHERE query = 'sour cream'");
        same();
        raw.execute(
          'INSERT OR REPLACE INTO fdc_search_cache (query, response) VALUES (?, ?)',
          ['garlic cloves', await answer('garlic cloves')],
        );
        expect(indexed(raw, garlic), contains('garlic cloves'));
        same();
        // Malformed JSON never fails a write (it indexes nothing).
        db.fdcSearchCachePut('broken', '{not json');
        same();
        // The upgrade: 016's (and 017's, 018's) objects dropped, back to 15,
        // reopened.
        db.dispose();
        raw
          ..execute('ALTER TABLE ingredient_matches DROP COLUMN parts')
          ..execute('ALTER TABLE ingredient_matches DROP COLUMN child_stamp')
          ..execute('ALTER TABLE ingredient_matches DROP COLUMN child_share')
          ..execute(
            'ALTER TABLE ingredient_matches DROP COLUMN child_recipe_id',
          )
          ..execute('DROP INDEX ingredient_matches_no_record')
          ..execute('ALTER TABLE recipe_nutrition DROP COLUMN computing')
          ..execute('DROP TRIGGER fdc_search_cache_foods_insert')
          ..execute('DROP TRIGGER fdc_search_cache_foods_update')
          ..execute('DROP TRIGGER fdc_search_cache_foods_delete')
          ..execute('DROP TABLE fdc_search_cache_foods')
          ..execute('ALTER TABLE ingredient_matches DROP COLUMN retry_count')
          ..execute('PRAGMA user_version = 15');
        final reopened = SaltDatabase.open(path);
        addTearDown(reopened.dispose);
        for (final id in ids) {
          expect(indexed(raw, id), scanned(raw, id), reason: 'backfill $id');
        }
      });
    },
  );

  group(
    'I1(b) more paths: a plain recompute, the prior decision, apply-to-all',
    () {
      test(
        "S2 → v29 S13: 0857's flour leaves every cache, FDC up: a PUT on "
        'the unrelated baking soda asks FDC NOTHING for it (a PUT resolves '
        'its own line only) — the flour underived, the recipe stale as '
        'waiting on USDA; the next compute derives it (one request): 248 g, '
        'complete and fresh',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
          await d.editAndCompute(db, fixture, r);
          final i = d.at(r, a.flour0857);
          await applyMatchOverride(db, fixture, r, i, {
            'raw': a.flour0857,
            'confirmed': true,
          });
          await matchAndCompute(db, fixture, r);
          final before = db.nutritionFor(r.id)!;
          expect(before.status, 'complete');
          final flour = d.rowOf(db, r, i).fdcId!;
          dropFood(path, flour);
          final asked = <int>[];
          final counting = _OnFood(asked.add, fixture);
          const soda = '1 teaspoon baking soda';
          await applyMatchOverride(db, counting, r, d.at(r, soda), {
            'raw': soda,
            'confirmed': true,
          });
          expect(asked, isNot(contains(flour)));
          expect(d.rowOf(db, r, i).derivedSeq, isNull);
          expect(nutritionIsFresh(db, r), isFalse);
          expect(
            nutritionBody(db, r, forAdmin: true)['stale_reason'],
            'underived',
          );
          await matchAndCompute(db, counting, r);
          expect(asked.where((id) => id == flour), hasLength(1));
          final after = db.nutritionFor(r.id)!;
          expect(after.status, 'complete');
          expect(after.totalGrams, closeTo(before.totalGrams!, 0.2));
          expect(nutritionIsFresh(db, r), isTrue);
        },
      );

      test(
        "the key's PRIOR decision on napa whose sibling FDC retired: the line "
        'is matched by search, never stale for 3 passes',
        () async {
          final db = wp.tempDb();
          final retired = FoodFault(
            FixtureProvider(pending: pendingSearches),
            {napaSibling},
            gone: true,
          );
          final r = wp.saveLines(db, [napa]);
          final line = nutritionLines(r).single;
          db.putDecision(
            itemKey: lineKeyOf(line),
            item: decisionItemOf(line),
            fdcId: napaId,
            description: 'Cabbage, napa',
            dataType: 'Foundation',
            decidedBy: null,
          );
          expect(await computeUntilFresh(db, retired, r), 1);
          expect(d.rowOf(db, r, 0).fdcId, isNot(napaId));
          expect(nutritionIsFresh(db, r), isTrue);
        },
      );

      test(
        'apply-to-all of napa whose sibling FDC retired: every target '
        '`unavailable`, none written on a food that cannot be counted',
        () async {
          final db = wp.tempDb();
          final retired = FoodFault(
            FixtureProvider(pending: pendingSearches),
            {napaSibling},
            gone: true,
          );
          for (final id in ['b', 'c']) {
            await matchAndCompute(
              db,
              retired,
              wp.saveLines(db, [napa], id: id),
            );
          }
          final before = db.ingredientMatchesFor('b').single.fdcId;
          expect(before, isNot(napaId));
          final res = await applyDecisionToOthers(
            db,
            retired,
            itemKey: lineKeyOf(
              nutritionLines(wp.saveLines(db, [napa], id: 'a')).single,
            ),
            decided: (await FixtureProvider().food(napaId))!,
            excluding: (recipeId: 'a', position: 0),
          );
          expect((res.unavailable, res.lines), (2, 0));
          expect(db.ingredientMatchesFor('b').single.fdcId, before);
        },
      );
    },
    skip: skipIfNoCorpus,
  );

  group(
    'O9/S16: the food_gone shortcut is keyed on the derivation key',
    () {
      test(
        "0857's flour held food_gone, then the title edited: the next compute "
        're-reads the hold from the caches for the new key (v29, Run 059 '
        'S2: NO request — a held row is not re-asked after an edit) — fresh, '
        'held, never stale forever',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
          await d.editAndCompute(db, fixture, r);
          final i = d.at(r, a.flour0857);
          await applyMatchOverride(db, fixture, r, i, {
            'raw': a.flour0857,
            'confirmed': true,
          });
          final id = d.rowOf(db, r, i).fdcId!;
          dropFood(path, id);
          final gone = FixtureProvider(
            pending: pendingSearches,
            superseded: {id},
          );
          await matchAndCompute(db, gone, r);
          expect(d.rowOf(db, r, i).hold, foodGoneHold);
          final edited = d.retitled(r);
          wp.saveRecipe(db, edited);
          expect(nutritionIsFresh(db, edited), isFalse);
          final calls = gone.foodCalls;
          expect(await computeUntilFresh(db, gone, edited), 1);
          expect(gone.foodCalls - calls, 0);
          expect(d.rowOf(db, edited, i).hold, foodGoneHold);
          expect(d.rowOf(db, edited, i).derivedSeq, ra.keyOf(db, edited));
          expect(nutritionIsFresh(db, edited), isTrue);
        },
      );
    },
    skip: skipIfNoCorpus,
  );

  group(
    'the v28 closer (D6): every RULE A arm pinned by name',
    () {
      /// 0857's flour confirmed, its food then in no cache and its detail
      /// failing FOOD (a 500 after the retries): held `food_unavailable` at
      /// the third compute. Returns what the pins read.
      Future<
        ({
          SaltDatabase db,
          String path,
          Recipe r,
          int i,
          int id,
          FixtureProvider fixture,
          FoodFault fault,
          List<Map<String, Object?>> answers,
        })
      >
      flourUnavailable({bool hold = true}) async {
        final (db, path) = a.pathDb();
        final fixture = FixtureProvider(pending: pendingSearches);
        final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
        await d.editAndCompute(db, fixture, r);
        final i = d.at(r, a.flour0857);
        await applyMatchOverride(db, fixture, r, i, {
          'raw': a.flour0857,
          'confirmed': true,
        });
        final id = d.rowOf(db, r, i).fdcId!;
        final answers = dropFood(path, id);
        final fault = FoodFault(
          fixture,
          {id},
          scope: FailureScope.food,
        );
        if (hold) {
          for (var n = 1; n <= 3; n++) {
            await matchAndCompute(db, fault, r);
          }
          expect(d.rowOf(db, r, i).hold, foodUnavailableHold);
        }
        return (
          db: db,
          path: path,
          r: r,
          i: i,
          id: id,
          fixture: fixture,
          fault: fault,
          answers: answers,
        );
      }

      test(
        'A2: a food_unavailable row is derived again, cache-only, once '
        "fdc_food_cache holds its detail (API.md) — 0857's flour counted "
        '248 g with no request; while no cache holds it, not asked',
        () async {
          final f = await flourUnavailable();
          // Held, nothing cached: the next compute asks nothing.
          var asked = f.fault.asked;
          await matchAndCompute(f.db, f.fault, f.r);
          expect(f.fault.asked, asked);
          expect(d.rowOf(f.db, f.r, f.i).hold, foodUnavailableHold);
          // FDC serves the detail to someone (cached), still failing here.
          await cachedFood(f.db, f.fixture, f.id);
          asked = f.fault.asked;
          await matchAndCompute(f.db, f.fault, f.r);
          expect(f.fault.asked, asked, reason: 'cache-only');
          final row = d.rowOf(f.db, f.r, f.i);
          expect(row.hold, isNull);
          expect(row.grams, closeTo(248.06, 0.01));
          expect(nutritionIsFresh(f.db, f.r), isTrue);
        },
      );

      test('A25: a pick on a food_unavailable row clears that hold even when '
          "the pick's derivation cannot run (napa re-picked, its nutrient "
          'record still failing: the row underived and unheld — never the '
          "old failure's hold kept on the decision)", () async {
        final (db, path) = a.pathDb();
        final fixture = FixtureProvider(pending: pendingSearches);
        final r = wp.saveLines(db, [napa]);
        await applyMatchOverride(db, fixture, r, 0, {
          'raw': napa,
          'fdc_id': napaId,
        });
        dropFood(path, napaSibling);
        final fault = FoodFault(
          fixture,
          {napaSibling},
          scope: FailureScope.food,
        );
        for (var n = 1; n <= 3; n++) {
          await matchAndCompute(db, fault, r);
        }
        expect(d.rowOf(db, r, 0).hold, foodUnavailableHold);
        await applyMatchOverride(db, fault, r, 0, {
          'raw': napa,
          'fdc_id': napaId,
        });
        final row = d.rowOf(db, r, 0);
        expect(row.status, 'overridden');
        expect(row.hold, isNull);
        expect(row.derivedSeq, isNull, reason: 'underived');
        expect(nutritionIsFresh(db, r), isFalse);
      });

      test('A28: a derivation that writes only derived_seq resets '
          'retry_count — food_unavailable needs three failing computes IN A '
          'ROW (fail, derive, fail, fail: not held; a third: held)', () async {
        final f = await flourUnavailable(hold: false);
        await matchAndCompute(f.db, f.fault, f.r);
        f.fault.up = true;
        await matchAndCompute(f.db, f.fault, f.r);
        expect(d.rowOf(f.db, f.r, f.i).grams, closeTo(248.06, 0.01));
        sqlite3.open(f.path)
          ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [f.id])
          ..dispose();
        f.fault.up = false;
        for (var n = 1; n <= 2; n++) {
          await matchAndCompute(f.db, f.fault, f.r);
          expect(d.rowOf(f.db, f.r, f.i).hold, isNull, reason: 'fail $n');
        }
        await matchAndCompute(f.db, f.fault, f.r);
        expect(d.rowOf(f.db, f.r, f.i).hold, foodUnavailableHold);
      });

      test('A9: typed grams on napa whose nutrient sibling no cache holds '
          'resolve the sibling (one request) — counted and fresh, never left '
          'underived every compute', () async {
        final (db, path) = a.pathDb();
        final fixture = FixtureProvider(pending: pendingSearches);
        final r = wp.saveLines(db, [napa]);
        await applyMatchOverride(db, fixture, r, 0, {
          'raw': napa,
          'fdc_id': napaId,
        });
        await applyMatchOverride(db, fixture, r, 0, {
          'raw': napa,
          'grams': 100,
        });
        expect(d.rowOf(db, r, 0).gramSource, 'override');
        dropFood(path, napaSibling);
        var siblingAsks = 0;
        final asks = _OnFood((id) {
          if (id == napaSibling) siblingAsks++;
        }, fixture);
        await matchAndCompute(db, asks, r);
        expect(siblingAsks, 1);
        expect(d.rowOf(db, r, 0).derivedSeq, isNotNull);
        expect(nutritionIsFresh(db, r), isTrue);
        expect(db.nutritionFor(r.id)!.matchedCount, 1);
        await matchAndCompute(db, asks, r);
        expect(siblingAsks, 1, reason: 'cached now');
      });

      test("A12 → v29: an ENGINE line whose candidate's nutrient record fails "
          "FOOD is that LINE's state (a row, counted) — the recipe computed "
          'and its failure logged, the sweep computing the next (never '
          '"stopped at", never `failed`)', () async {
        final (db, path) = a.pathDb();
        final fixture = FixtureProvider(pending: pendingSearches);
        final ra0 = wp.saveLines(db, [napa], id: 'a');
        await matchAndCompute(db, fixture, ra0);
        final rb0 = wp.saveLines(db, [v23.quarter], id: 'b');
        await matchAndCompute(db, fixture, rb0);
        dropFood(path, napaSibling);
        wp.saveRecipe(db, d.retitled(ra0));
        final rb1 = d.retitled(rb0);
        wp.saveRecipe(db, rb1);
        expect(bulkScopeIds(db, BulkScope.stale), ['a', 'b']);
        // The candidate's nutrient record (its sibling): a detail.
        final p = FoodFault(
          fixture,
          {napaSibling},
          failWith: 'FoodData Central error 400.',
          scope: FailureScope.food,
        );
        final job = startBulkJob(db, p, scope: BulkScope.stale)!;
        await ra.settle();
        final row = db.nutritionJob(job)!;
        expect(row['status'], 'done');
        expect(row['failed'], 0);
        expect(row['log'], contains('a: FoodData Central error 400.'));
        expect(nutritionIsFresh(db, rb1), isTrue);
        expect(p.asked, 1);
        // v36 (Run 060 S4): the line's auto row carries a food, so it is
        // KEPT (counted, underived) — never overwritten by the unmatched
        // row ([engineUnavailableNote] only for a line with no food).
        final a0 = d.rowOf(db, ra0, 0);
        expect((a0.status, a0.fdcId, a0.hold), ('auto', napaId, null));
        expect(nutritionIsFresh(db, d.retitled(ra0)), isFalse);
      });

      test('A29: stale_reason says why — `underived` (a decision waiting on '
          'USDA, the stamp current) vs `inputs` (the recipe edited)', () async {
        final (db, path) = a.pathDb();
        final fixture = FixtureProvider(pending: pendingSearches);
        final r = wp.saveLines(db, [napa]);
        await matchAndCompute(db, fixture, r);
        dropFood(path, napaSibling);
        await applyMatchOverride(db, FoodFault(fixture, {napaSibling}), r, 0, {
          'raw': napa,
          'fdc_id': napaId,
        });
        var body = nutritionBody(db, r, forAdmin: true);
        expect(body['status'], 'stale');
        expect(body['stale_reason'], 'underived');
        final edited = d.retitled(r);
        wp.saveRecipe(db, edited);
        body = nutritionBody(db, edited, forAdmin: true);
        expect(body['stale_reason'], 'inputs');
      });

      test('A32: food_unavailable after THREE failing computes (API.md)', () {
        expect(foodUnavailableAfter, 3);
      });
    },
    skip: skipIfNoCorpus,
  );

  group(
    "the v28 closer (D3): the PUT's gate reads the STORED hold first",
    () {
      test(
        "0148's line 0 edited ('½ cup table salt' → '5 cup table salt', "
        'synthesized), its food_gone row carried: a confirm or typed grams is '
        'a 422 that asks FDC NOTHING (v28: one request, then the 422)',
        () async {
          final r = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
          final db = wp.tempDb();
          wp.saveRecipe(db, r);
          final gone = ra.Retired();
          await matchAndCompute(db, gone, r);
          final lines = nutritionLines(r);
          expect(lines[0].raw, '½ cup table salt');
          for (final (i, line) in lines.indexed) {
            db.upsertIngredientMatch(
              IngredientMatchRow(
                recipeId: r.id,
                position: i,
                raw: line.raw,
                fdcId: poisoned,
                description: 'Retired food',
                dataType: 'SR Legacy',
                confidence: 1,
                grams: 10,
                gramSource: 'weight',
                status: 'confirmed',
                itemKey: lineKeyOf(line),
              ),
              layoutSeq: db.layoutSeqOf(r.id),
            );
          }
          await computeUntilFresh(db, gone, r);
          expect(d.rowOf(db, r, 0).hold, foodGoneHold);
          final edited = a.rewritten(r, '½ cup table salt', '5 cup table salt');
          wp.saveRecipe(db, edited);
          final calls = gone.foodCalls;
          for (final body in [
            {'confirmed': true},
            {'grams': 50},
          ]) {
            await expectLater(
              applyMatchOverride(db, gone, edited, 0, {
                'raw': '5 cup table salt',
                ...body,
              }),
              throwsA(isA<ValidationException>()),
              reason: '$body',
            );
          }
          expect(gone.foodCalls, calls, reason: '0 requests before the 422');
        },
      );
    },
    skip: skipIfNoCorpus,
  );

  group(
    "the v28 closer (D3): a carried row's DERIVED hold is gated too",
    () {
      test(
        "0857's confirmed flour, its amount edited (synthesized: '2 cups (10 "
        "ounces)'), its food then gone (404, no cache): the carried row's "
        'derivation finds it food_gone, so a confirm is the same 422 — one '
        'request (the derivation that found it), the row never confirmed '
        'onto a gone food',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
          await d.editAndCompute(db, fixture, r);
          final i = d.at(r, a.flour0857);
          await applyMatchOverride(db, fixture, r, i, {
            'raw': a.flour0857,
            'confirmed': true,
          });
          final id = d.rowOf(db, r, i).fdcId!;
          expect(d.rowOf(db, r, i).hold, isNull);
          dropFood(path, id);
          const edited = '2 cups (10 ounces) unbleached all-purpose flour';
          final r2 = a.rewritten(r, a.flour0857, edited);
          wp.saveRecipe(db, r2);
          final gone = FixtureProvider(
            pending: pendingSearches,
            superseded: {id},
          );
          await expectLater(
            applyMatchOverride(db, gone, r2, i, {
              'raw': edited,
              'confirmed': true,
            }),
            throwsA(
              isA<ValidationException>().having(
                (e) => e.message,
                'message',
                noRecordMessage,
              ),
            ),
          );
          expect(gone.foodCalls, 1);
        },
      );
    },
    skip: skipIfNoCorpus,
  );

  group(
    "the v28 closer (D8), as the owner ruled on Run 059 O11: one recipe's "
    'detail failures never escalate, and every one is counted',
    () {
      /// [ids.length] lines of a, each decided on its own retired id
      /// (synthesized, the 999000111 family), typed 10 g; b one plain line.
      Future<(SaltDatabase, String, Recipe, Recipe)> outage(
        List<int?> ids,
      ) async {
        final (db, path) = a.pathDb();
        final fixture = FixtureProvider(pending: pendingSearches);
        const raws = [
          '1 teaspoon table salt',
          '1 cup sugar',
          '2 tablespoons unsalted butter',
          '1 cup whole milk',
          '2 large eggs',
          '1 cup all-purpose flour',
        ];
        var ra0 = wp.saveLines(db, raws.sublist(0, ids.length), id: 'a');
        await matchAndCompute(db, fixture, ra0);
        final rb0 = wp.saveLines(db, [v23.quarter], id: 'b');
        await matchAndCompute(db, fixture, rb0);
        for (final (i, line) in nutritionLines(ra0).indexed) {
          final id = ids[i];
          if (id == null) continue;
          db.upsertIngredientMatch(
            IngredientMatchRow(
              recipeId: 'a',
              position: i,
              raw: line.raw,
              fdcId: id,
              description: 'Retired food',
              dataType: 'SR Legacy',
              confidence: 1,
              grams: 10,
              gramSource: 'override',
              status: 'overridden',
              itemKey: lineKeyOf(line),
            ),
            layoutSeq: db.layoutSeqOf('a'),
          );
        }
        // Both stale (a title edit), so the sweep visits both.
        ra0 = d.retitled(ra0);
        wp.saveRecipe(db, ra0);
        final rb1 = d.retitled(rb0);
        wp.saveRecipe(db, rb1);
        return (db, path, ra0, rb1);
      }

      int retries(String path) {
        final raw = sqlite3.open(path);
        final n =
            raw
                    .select(
                      'SELECT SUM(retry_count) AS n FROM ingredient_matches',
                    )
                    .first['n']
                as int? ??
            0;
        raw.dispose();
        return n;
      }

      Future<Map<String, Object?>> sweep(
        SaltDatabase db,
        NutritionProvider p,
      ) async {
        final job = startBulkJob(db, p, scope: BulkScope.stale)!;
        await ra.settle();
        return db.nutritionJob(job)!;
      }

      final failing = [for (var k = 0; k < 5; k++) poisoned + k];
      FoodFault down(NutritionProvider inner) => FoodFault(
        inner,
        failing.toSet(),
        failWith:
            'FoodData Central is unavailable (HTTP 503); try again '
            'later.',
        scope: FailureScope.food,
      );

      test('5 decided rows of ONE recipe whose details all 503: an outage '
          'spans two recipes, so none escalates — and the PASS suspends its '
          "details at the third failure in a row (the owner's ruling on Run "
          '059 O10): sweeps 1-3 ask and count the first three (held at the '
          'third), lines 4-5 left underived and uncounted; sweeps 4-6 ask '
          'the last two (the held three re-read from the caches, no request), '
          'held at the sixth (a fresh); the seventh asks nothing. b computed every '
          'sweep', () async {
        final (db, path, ra0, rb0) = await outage(failing);
        final p = down(FixtureProvider(pending: pendingSearches));
        for (var n = 1; n <= 6; n++) {
          final job = await sweep(db, p);
          expect(job['status'], 'done', reason: 'sweep $n');
          expect('${job['log']}', isNot(contains('stopped at')));
          final asked = n <= 3 ? 3 * n : 9 + 2 * (n - 3);
          expect(p.asked, asked, reason: 'sweep $n');
          expect(retries(path), asked, reason: 'sweep $n');
          expect(
            db.ingredientMatchesFor('a').where((m) => m.hold != null),
            hasLength(n < 3 ? 0 : (n < 6 ? 3 : 5)),
            reason: 'sweep $n',
          );
          expect(nutritionIsFresh(db, ra0), n == 6, reason: 'sweep $n');
          expect(nutritionIsFresh(db, rb0), isTrue, reason: 'sweep $n');
        }
        await sweep(db, p);
        expect(p.asked, 15);
        expect(nutritionIsFresh(db, ra0), isTrue);
      });

      test('TWO distinct failures in a row stay FOOD (counted, the sweep goes '
          'on); a detail answered between failures resets the run', () async {
        final (db, path, _, rb0) = await outage([failing[0], failing[1]]);
        final p = down(FixtureProvider(pending: pendingSearches));
        final job = await sweep(db, p);
        expect(job['status'], 'done');
        expect(retries(path), 2);
        expect(nutritionIsFresh(db, rb0), isTrue);
        // fail, answer (789890's detail, uncached), fail, fail: never three
        // in a row.
        final (db2, path2, _, rb2) = await outage([
          failing[0],
          789890,
          failing[1],
          failing[2],
        ]);
        sqlite3.open(path2)
          ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = 789890')
          ..dispose();
        final job2 = await sweep(db2, p);
        expect(job2['status'], 'done');
        expect(retries(path2), 3);
        expect(nutritionIsFresh(db2, rb2), isTrue);
      });
    },
    skip: skipIfNoCorpus,
  );
}
