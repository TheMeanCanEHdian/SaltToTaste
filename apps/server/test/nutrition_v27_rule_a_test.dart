// RULE A as a ROW fact (matcher v27, brief I1 — Run 057 S1/S15/O1/O15,
// S5/S16/O2/O16, Opus critics 1-3, O3, O17): every decided row records
// what its derived fields were computed for (`derived_seq`, migration
// 014); freshness is the stamp AND no decided row underived — ONE SQL
// predicate ([SaltDatabase.underivedSql]) read by `nutritionIsFresh`, the
// stale scope and the recipe page, over the rows as they are when read.
// A food FDC answers "no such food" for (no cache holding it) is the
// `food_gone` HOLD, derived; an outage leaves the row underived and costs
// one request per underived row per pass; the totals are cache-only; the
// job loops stop on a provider failure with its own reason.
//
// Real corpus recipes (0129 Indoor Pulled Chicken, 0148 Crispy Fried
// Chicken, 0857 Rich Chocolate Bundt Cake, 0279 Crispy Salt-and-Pepper
// Shrimp, 0288 Maryland Crab Cakes) and recorded FDC answers (FixtureProvider), never the network.
// Synthesized, each a stated exception: the interleavings (a person's PUT
// run inside a compute's first search, as a provider wrapper), the outage
// (a provider that throws NutritionProviderException, the bad key's
// message), FDC's "no such food" (FixtureProvider.superseded with the
// food's cache rows deleted), 0148's 13 decided rows on one retired food
// id (999000111 — Run 057 S5's hostile cost shape: no real row can name
// it), an engine row's `no_nutrients` hold on 0288's Old Bay (O3:
// the hold as the engine writes it on other foods), a title edit (stale),
// and the pre-014 database (the column dropped, user_version 13). Also
// stated (v28, Run 058 S26): the b/c apply-to-all recipes assembled from
// real corpus lines (wp.saveLines), the typed grams a person enters (250 g,
// 77 g — any positive amount; the corpus has no person's grams), and
// 0288's "1½ teaspoons" edited to "2 teaspoons Old Bay seasoning" (an
// amount edit as the editor makes one; `threeTsp`). Since matcher v37 the
// below-gate vehicle is 0288's Old Bay (no FDC record; its pick's detail
// never fetched): 0279's Sichuan peppercorns count as black pepper.
// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart' as frog;
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/decision_rekey.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../routes/api/v1/recipes/[id]/nutrition/index.dart' as basis_route;
import 'nutrition_v23_writepath_test.dart' as v23;
import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Runs [during] inside the first search the wrapped compute makes (a
/// person's PUT landing while a compute awaits FDC).
class PutDuringFirstSearch implements NutritionProvider {
  PutDuringFirstSearch(this.inner, this.during);

  final NutritionProvider inner;
  Future<void> Function()? during;

  @override
  Future<List<FdcCandidate>> search(String query) async {
    final hook = during;
    during = null;
    if (hook != null) {
      await hook();
    }
    return inner.search(query);
  }

  @override
  Future<FdcFood?> food(int fdcId) => inner.food(fdcId);
}

/// Counts food requests; answers "no such food" or throws
/// [failWith] (an outage, a bad key) for every one.
class Retired implements NutritionProvider {
  Retired({this.failWith});

  final String? failWith;
  int foodCalls = 0;

  @override
  Future<List<FdcCandidate>> search(String query) async => const [];

  @override
  Future<FdcFood?> food(int fdcId) async {
    foodCalls += 1;
    final failure = failWith;
    if (failure != null) {
      throw NutritionProviderException(failure);
    }
    return null;
  }
}

/// Runs [save] inside the first food request (a save landing while a
/// person's PUT awaits FDC).
class SaveOnFirstFood implements NutritionProvider {
  SaveOnFirstFood(this.inner, this.save);

  final NutritionProvider inner;
  void Function()? save;

  @override
  Future<List<FdcCandidate>> search(String query) => inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) {
    final hook = save;
    save = null;
    hook?.call();
    return inner.food(fdcId);
  }
}

/// Waits for the running bulk job (or [recipeId]'s compute job) to end.
Future<void> settle({String? recipeId}) async {
  while (recipeId == null
      ? bulkJobRunning
      : recipeComputeJobId(recipeId) != null) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// 0279's Sichuan peppercorns (D11's pick of 168317 from their answer).
const peppercorns0279 = '2 teaspoons Sichuan peppercorns';

/// 0288's Old Bay with its amount edited (the closer's D2/D7).
const threeTsp = a.twoTspOldBay;

/// [r]'s current key ([derivedKeyOf]).
String keyOf(SaltDatabase db, Recipe r) =>
    derivedKeyOf(db.layoutSeqOf(r.id), ingredientsHashOf(r));

void main() {
  group(
    'the row fact: a writer that stamps never decides "derived"',
    () {
      test("S15/O1: a person's confirm of 0129's divided liquid smoke during "
          "an outage, landing inside a compute's first search — the row is "
          'stored UNDERIVED, the compute stamps its inputs and the recipe '
          'still reads stale (in the stale scope); the next pass derives it '
          "and it reads fresh, the confirm's 4.73 g", () async {
        final (db, path) = a.pathDb();
        final fixture = FixtureProvider(pending: pendingSearches);
        final r = loadCorpusRecipe('0129-indoor-pulled-chicken.yaml');
        wp.saveRecipe(db, r);
        await matchAndCompute(db, fixture, r);
        expect(nutritionIsFresh(db, r), isTrue);
        final i = d.at(r, d.smoke0129);
        sqlite3.open(path)
          ..execute('DELETE FROM fdc_search_cache')
          ..dispose();
        final outage = a.Outage(fixture)..down = true;
        var putFresh = true;
        final compute = PutDuringFirstSearch(fixture, () async {
          await applyMatchOverride(db, outage, r, i, {
            'raw': d.smoke0129,
            'confirmed': true,
          });
          putFresh = nutritionIsFresh(db, r);
        });
        // The racing compute through the job step: ONE pass — an underived
        // row is no reason for another (only a moved layout or hash is).
        expect(await computeUntilFresh(db, compute, r), 1);
        expect(outage.failed, greaterThan(0), reason: 'the PUT met the outage');
        expect(putFresh, isFalse);
        final row = d.rowOf(db, r, i);
        expect(row.status, 'confirmed');
        expect(row.derivedSeq, isNull);
        expect(nutritionStampCurrent(db, r), isTrue, reason: 'stamped');
        expect(nutritionIsFresh(db, r), isFalse, reason: 'the row says no');
        expect(nutritionBody(db, r, forAdmin: true)['status'], 'stale');
        expect(bulkScopeIds(db, BulkScope.stale), contains(r.id));
        expect(await computeUntilFresh(db, fixture, r), 1);
        expect(nutritionIsFresh(db, r), isTrue);
        final derived = d.rowOf(db, r, i);
        expect(derived.derivedSeq, keyOf(db, r));
        expect(
          d.shape(derived),
          d.shape(await d.freshWrite(r, i, {'confirmed': true})),
        );
        expect(derived.grams, closeTo(4.73, 0.01));
      });
    },
    skip: skipIfNoCorpus,
  );

  // v28 (RULE C, Run 058 O6/S11: [onePass]): the 13 rows share ONE food,
  // so a pass asks for it ONCE (v27: once per row, 13).
  group('S5/S16/O2/O16: one request per underived FOOD per pass; the job '
      "stops with the provider's reason", () {
    /// 0148 computed with nothing matched, then its 13 lines decided on one
    /// retired food (999000111, Run 057 S5's shape), underived.
    Future<(SaltDatabase, Recipe)> retired() async {
      final r = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
      final db = wp.tempDb();
      wp.saveRecipe(db, r);
      await matchAndCompute(db, Retired(), r);
      final lines = nutritionLines(r);
      expect(lines, hasLength(13));
      for (final (i, line) in lines.indexed) {
        db.upsertIngredientMatch(
          IngredientMatchRow(
            recipeId: r.id,
            position: i,
            raw: line.raw,
            fdcId: 999000111,
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
      expect(nutritionIsFresh(db, r), isFalse);
      return (db, r);
    }

    test('FDC answers "no such food": ONE pass, 1 request (not 42), every '
        'row derived to food_gone, the recipe held — fresh, partial, out of '
        'the stale scope — and a second compute asks nothing', () async {
      final (db, r) = await retired();
      final gone = Retired();
      expect(await computeUntilFresh(db, gone, r), 1);
      expect(gone.foodCalls, 1);
      for (final row in db.ingredientMatchesFor(r.id)) {
        expect(
          (row.hold, row.grams, row.derivedSeq),
          (
            'food_gone',
            null,
            keyOf(db, r),
          ),
        );
      }
      expect(nutritionIsFresh(db, r), isTrue);
      expect(db.nutritionFor(r.id)!.status, 'partial');
      expect(bulkScopeIds(db, BulkScope.stale), isNot(contains(r.id)));
      await computeUntilFresh(db, gone, r);
      expect(gone.foodCalls, 1, reason: 'derived to the hold: not re-asked');
    });

    test('an outage: ONE pass, 1 request, the provider failure thrown with '
        'its own message (no StateError), the rows underived and the recipe '
        'in the stale scope; FDC back, one pass derives them', () async {
      final (db, r) = await retired();
      final down = Retired(failWith: 'FDC unavailable');
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
      expect(down.foodCalls, 1);
      expect(
        db.ingredientMatchesFor(r.id).map((row) => row.derivedSeq).toSet(),
        {null},
      );
      expect(bulkScopeIds(db, BulkScope.stale), contains(r.id));
      final back = Retired();
      expect(await computeUntilFresh(db, back, r), 1);
      expect(back.foodCalls, 1);
      expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
    });

    test(
      "both job loops stop on a bad key with ITS message (_run's arm), "
      'having asked once per underived food; a 404 sweep then converges '
      '(done, the stale scope empty, the next sweep selects nothing)',
      () async {
        final (db, r) = await retired();
        const reason = 'FoodData Central rejected the API key';
        final bad = Retired(failWith: reason);
        final job = startBulkJob(db, bad, scope: BulkScope.stale)!;
        await settle();
        final row = db.nutritionJob(job)!;
        expect(row['status'], 'failed');
        expect(row['log'], contains('stopped at ${r.id}: $reason'));
        expect(bad.foodCalls, 1);
        final one = startRecipeComputeJob(db, bad, r);
        await settle(recipeId: r.id);
        expect(db.nutritionJob(one)!['status'], 'failed');
        expect(db.nutritionJob(one)!['log'], ['${r.id}: $reason']);
        expect(bad.foodCalls, 2);
        final gone = Retired();
        final sweep = startBulkJob(db, gone, scope: BulkScope.stale)!;
        await settle();
        expect(db.nutritionJob(sweep)!['status'], 'done');
        expect(db.nutritionJob(sweep)!['failed'], 0);
        expect(gone.foodCalls, 1);
        expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
      },
    );
  }, skip: skipIfNoCorpus);

  group('the other writers: apply-to-all, typed grams, the basis route, a '
      'pick (Opus critics 1-3, O3)', () {
    test("critic 1: an apply-to-all during an outage — c's amount-less oil "
        "(no portions) written, its '¼ cup' (portions) and b's not: 2 "
        "`unavailable`, never `failed`; c's totals recomputed and stale, b "
        'stale with no write — no fresh stamp over old totals', () async {
      final db = wp.tempDb();
      final fixture = FixtureProvider(pending: pendingSearches);
      final b = wp.saveLines(db, [v23.quarter], id: 'b');
      await matchAndCompute(db, fixture, b);
      final c = wp.saveLines(db, [
        'Extra-virgin olive oil',
        v23.quarter,
      ], id: 'c');
      await matchAndCompute(db, fixture, c);
      final before = db.ingredientMatchesFor('c');
      expect(nutritionIsFresh(db, c), isTrue);
      final outage = a.Outage(fixture)..down = true;
      final res = await v23.applyOil(db, outage);
      expect(
        (res.lines, res.recipes, res.unavailable, res.failed),
        (1, 1, 2, 0),
      );
      expect(res.failedLines, 0);
      // The route's wire (the closer's D6: the golden carries 0).
      expect(appliedJson(res)['unavailable'], 2);
      expect(appliedJson(res)['failed'], 0);
      final after = db.ingredientMatchesFor('c');
      expect(after[0].fdcId, 173468, reason: 'the amount-less target written');
      expect(d.shape(after[1]), d.shape(before[1]), reason: 'not written');
      expect(nutritionIsFresh(db, c), isFalse);
      expect(nutritionIsFresh(db, b), isFalse);
      expect(bulkScopeIds(db, BulkScope.stale), containsAll(['b', 'c']));
      // v29 (Run 059 O23): nothing changed — a decision is waiting on USDA,
      // never "Ingredients changed".
      for (final r in [b, c]) {
        expect(
          nutritionBody(db, r, forAdmin: true)['stale_reason'],
          'underived',
          reason: r.id,
        );
      }
    });

    test("critic 2: 0857's flour confirmed with 250 g typed, its food then "
        'in no cache and FDC answering no such food — derived to the '
        'food_gone hold (typed grams kept, the decision kept), out of the '
        'totals, the recipe held; a pick of another food or a skip finishes '
        'it', () async {
      final (db, path) = a.pathDb();
      final fixture = FixtureProvider(pending: pendingSearches);
      final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
      await d.editAndCompute(db, fixture, r);
      final i = d.at(r, a.flour0857);
      await applyMatchOverride(db, fixture, r, i, {
        'raw': a.flour0857,
        'confirmed': true,
        'grams': 250,
      });
      final full = db.nutritionFor(r.id)!.totalGrams!;
      final id = d.rowOf(db, r, i).fdcId!;
      sqlite3.open(path)
        ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [id])
        ..execute(
          'DELETE FROM fdc_search_cache '
          "WHERE response LIKE '%\"fdc_id\":' || ? || ',%'",
          [id],
        )
        ..dispose();
      final gone = FixtureProvider(pending: pendingSearches, superseded: {id});
      await matchAndCompute(db, gone, r);
      expect(gone.foodCalls, 1);
      final row = d.rowOf(db, r, i);
      expect(d.shape(row), ('confirmed', id, 250, 'override', 'food_gone'));
      expect(row.derivedSeq, keyOf(db, r));
      expect(nutritionIsFresh(db, r), isTrue, reason: 'derived, to a hold');
      final n = db.nutritionFor(r.id)!;
      expect(n.status, 'partial');
      expect(n.totalGrams, closeTo(full - 250, 0.2));
      expect(
        matchBucketFor(
          status: row.status,
          fdcId: row.fdcId,
          grams: row.grams,
          confidence: row.confidence,
          hold: row.hold,
          gramSource: row.gramSource,
        ),
        MatchBucket.check,
      );
      expect(db.nutritionReviewCounts()['check'], greaterThan(0));
      // A skip finishes it.
      await applyMatchOverride(db, gone, r, i, {
        'raw': a.flour0857,
        'skipped': true,
      });
      expect(d.rowOf(db, r, i).hold, isNull);
      expect(nutritionIsFresh(db, r), isTrue);
    });

    test('critic 3: a serving-basis PUT during an outage on 0857 (fresh, '
        'complete) — 200, the totals unchanged but for the divisor, the '
        'stamp unchanged, no request', () async {
      final db = wp.tempDb();
      final fixture = FixtureProvider(pending: pendingSearches);
      final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
      await d.editAndCompute(db, fixture, r);
      final i = d.at(r, a.flour0857);
      await applyMatchOverride(db, fixture, r, i, {
        'raw': a.flour0857,
        'confirmed': true,
      });
      final before = db.nutritionFor(r.id)!;
      expect(nutritionIsFresh(db, r), isTrue);
      final outage = a.Outage(fixture)..down = true;
      final (code, body) = await putBasis(db, outage, r.slug, {
        'serving_basis': before.servingBasis! + 1,
      });
      expect(code, HttpStatus.ok, reason: '$body');
      expect(outage.failed, 0);
      final after = db.nutritionFor(r.id)!;
      expect(after.servingBasis, before.servingBasis! + 1);
      expect(after.totalGrams, before.totalGrams);
      expect(after.status, before.status);
      expect(
        after.caloriesPerServing,
        closeTo(
          before.caloriesPerServing! *
              before.servingBasis! /
              (before.servingBasis! + 1),
          0.01,
        ),
      );
      expect(
        (after.ingredientsHash, after.layoutSeq),
        (before.ingredientsHash, before.layoutSeq),
      );
      expect(nutritionIsFresh(db, r), isTrue);
    });

    test("O3: a pick during an outage on 0288's Old Bay, an engine "
        '`no_nutrients` hold on the old row — the pick stores no food hold '
        '(LINE holds only), underived; FDC back, derived', () async {
      final (db, fixture, r) = await d.computed(
        '0288-maryland-crab-cakes.yaml',
      );
      final i = d.at(r, a.oldBay0288);
      db.upsertIngredientMatch(
        d.rowOf(db, r, i).copyWith(hold: 'no_nutrients'),
      );
      final outage = a.Outage(fixture)..down = true;
      // "Spices, bay leaf" (170917), a hit in the line's own answer whose
      // detail no line of the recipe fetched.
      await applyMatchOverride(db, outage, r, i, {
        'raw': a.oldBay0288,
        'fdc_id': 170917,
      });
      final stored = d.rowOf(db, r, i);
      expect(
        (stored.status, stored.fdcId, stored.hold),
        (
          'overridden',
          170917,
          null,
        ),
      );
      expect(stored.derivedSeq, isNull);
      expect(nutritionIsFresh(db, r), isFalse);
      outage.down = false;
      await computeUntilFresh(db, outage, r);
      expect(nutritionIsFresh(db, r), isTrue);
      expect(d.rowOf(db, r, i).derivedSeq, keyOf(db, r));
    });

    test('a pick of another food during an outage finishes `food_gone`: '
        "0288's Old Bay confirmed and held food_gone (synthesized, as "
        'a 404 derives it), then 170917 picked while FDC is out — stored '
        'with no hold, underived', () async {
      final (db, fixture, r) = await d.computed(
        '0288-maryland-crab-cakes.yaml',
      );
      final i = d.at(r, a.oldBay0288);
      db.upsertIngredientMatch(
        d.rowOf(db, r, i).copyWith(status: 'confirmed', hold: 'food_gone'),
      );
      final outage = a.Outage(fixture)..down = true;
      await applyMatchOverride(db, outage, r, i, {
        'raw': a.oldBay0288,
        'fdc_id': 170917,
      });
      final stored = d.rowOf(db, r, i);
      expect((stored.fdcId, stored.hold), (170917, null));
      expect(stored.derivedSeq, isNull);
    });
  }, skip: skipIfNoCorpus);

  test(
    "the compute fetches what the cache-only totals read: 0506's napa "
    'line alone (its answer holds no hit of 169979, the nutrient sibling '
    'of 2727583) — the sibling fetched by the compute, counted, fresh',
    () async {
      final db = wp.tempDb();
      final r = wp.saveLines(db, [
        '12 ounces napa cabbage (½ medium head), cored and minced',
      ]);
      expect(knownFood(db, 169979), isNull);
      await matchAndCompute(db, FixtureProvider(pending: pendingSearches), r);
      final napa = db.ingredientMatchesFor(r.id).single;
      expect(napa.fdcId, 2727583);
      expect(knownFood(db, 169979), isNotNull);
      expect(nutritionIsFresh(db, r), isTrue);
      expect(db.nutritionFor(r.id)!.status, 'complete');
    },
    skip: skipIfNoCorpus,
  );

  group('migration 014: derived_seq upgraded and backfilled once', () {
    test('a database at version 13 (0129 fresh with a confirm; 0857 with a '
        'confirm, then its title edited — stale): the upgrade and the boot '
        'mark the fresh recipe derived (still fresh) and leave the stale '
        "one's decided rows underived; re-opened, the backfill never runs "
        'again (an underived write is not healed by a restart)', () async {
      final (db0, path) = v23.fileDb();
      var db = db0;
      final fixture = FixtureProvider(pending: pendingSearches);
      final fresh = loadCorpusRecipe('0129-indoor-pulled-chicken.yaml');
      final cake = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
      for (final r in [fresh, cake]) {
        wp.saveRecipe(db, r);
        await matchAndCompute(db, fixture, r);
      }
      await applyMatchOverride(db, fixture, fresh, d.at(fresh, d.smoke0129), {
        'raw': d.smoke0129,
        'confirmed': true,
      });
      await applyMatchOverride(db, fixture, cake, d.at(cake, a.flour0857), {
        'raw': a.flour0857,
        'confirmed': true,
      });
      final stale = cake.copyWith(title: '${cake.title} (edited)');
      wp.saveRecipe(db, stale);
      db.dispose();
      v23.downgrade(path, 13);
      db = SaltDatabase.open(path);
      expect(
        db.getSetting(SaltDatabase.derivedSeqBackfillSetting),
        'pending',
      );
      // Before the boot pass every decided row reads underived.
      expect(nutritionIsFresh(db, fresh), isFalse);
      rekeyAfterMatcherChange(db);
      expect(db.getSetting(SaltDatabase.derivedSeqBackfillSetting), isNull);
      expect(nutritionIsFresh(db, fresh), isTrue);
      final smoke = d.rowOf(db, fresh, d.at(fresh, d.smoke0129));
      expect(smoke.derivedSeq, keyOf(db, fresh));
      final flour = d.rowOf(db, stale, d.at(stale, a.flour0857));
      expect(flour.derivedSeq, isNull);
      expect(nutritionIsFresh(db, stale), isFalse);
      // An underived write after the upgrade: re-open and boot again — it
      // stays underived (the marker is gone).
      db
        ..clearDerivedSeq(fresh.id, [smoke.position])
        ..dispose();
      db = SaltDatabase.open(path);
      addTearDown(db.dispose);
      rekeyAfterMatcherChange(db);
      expect(d.rowOf(db, fresh, smoke.position).derivedSeq, isNull);
      expect(nutritionIsFresh(db, fresh), isFalse);
      expect(
        db.getSetting(SaltDatabase.derivedSeqBackfillSetting),
        isNull,
      );
      // The stale recipe's next compute derives it: fresh.
      await computeUntilFresh(db, fixture, stale);
      expect(nutritionIsFresh(db, stale), isTrue);
    }, skip: skipIfNoCorpus);

    // A sweep snapshot (key-stripped, read through a temp copy) when
    // SALT_REVIEW_SNAPSHOT names one (snapshot 13: computed at an older
    // matcher, so every stamp is stale and nothing is marked).
    final snapshot = Platform.environment['SALT_REVIEW_SNAPSHOT'];
    test(
      'on a real snapshot: 014 runs on open, the boot marks only fresh '
      "recipes' decided rows, and a re-open changes nothing",
      skip: snapshot == null || !File(snapshot).existsSync()
          ? 'set SALT_REVIEW_SNAPSHOT to a sweep snapshot to run'
          : null,
      () {
        final dir = Directory.systemTemp.createTempSync('salt-v27-014');
        addTearDown(() => dir.deleteSync(recursive: true));
        final path = '${dir.path}/snap.db';
        File(snapshot!).copySync(path);
        sqlite3.open(path)
          ..execute('PRAGMA journal_mode=DELETE')
          ..dispose();
        var db = SaltDatabase.open(path);
        rekeyAfterMatcherChange(db);
        List<Object?> state() => [
          for (final row
              in sqlite3
                  .open(path)
                  .select(
                    'SELECT recipe_id, position, derived_seq FROM ingredient_matches '
                    "WHERE status IN ('confirmed', 'overridden', 'skipped') "
                    'ORDER BY recipe_id, position',
                  ))
            '${row['recipe_id']}#${row['position']}=${row['derived_seq']}',
        ];
        final first = state();
        expect(first, isNotEmpty);
        // Every decided row: its recipe's key when the stamp is current,
        // else null.
        var marked = 0;
        for (final id in db.allRecipeIds()) {
          final r = db.recipeByIdOrSlug(id)!.recipe;
          final current = nutritionStampCurrent(db, r);
          for (final row in db.ingredientMatchesFor(id).where(isDecidedRow)) {
            expect(
              row.derivedSeq,
              current ? keyOf(db, r) : isNull,
              reason: '$id#${row.position}',
            );
            if (current) {
              marked += 1;
            }
          }
        }
        // ignore: avoid_print
        print('snapshot: ${first.length} decided rows, $marked marked');
        db.dispose();
        db = SaltDatabase.open(path);
        rekeyAfterMatcherChange(db);
        db.dispose();
        expect(state(), first);
      },
    );
  });

  test('O17: a fixture miss is an Error, never an outage — a decided '
      "row's derivation on an unrecorded food throws it", () async {
    expect(
      UnrecordedAnswer('food 1'),
      isNot(isA<NutritionProviderException>()),
    );
    final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
    final db = wp.tempDb();
    wp.saveRecipe(db, r);
    final line = nutritionLines(r).first;
    final row = IngredientMatchRow(
      recipeId: r.id,
      position: 0,
      raw: line.raw,
      fdcId: 170155, // a real candidate food foods.json does not record
      description: 'picked',
      dataType: 'SR Legacy',
      confidence: 1,
      grams: null,
      gramSource: null,
      status: 'overridden',
      itemKey: lineKeyOf(line),
    );
    await expectLater(
      derivedFor(db, FixtureProvider(), r, 0, line, row),
      throwsA(isA<UnrecordedAnswer>()),
    );
  }, skip: skipIfNoCorpus);

  test('food_gone buckets `check` in the SQL queue as in Dart, on every '
      'decided status but a skip', () {
    final db = wp.tempDb();
    final r = wp.saveLines(db, ['1 cup sugar', '2 cups sugar', '3 cups sugar']);
    for (final (i, status) in ['confirmed', 'overridden', 'skipped'].indexed) {
      db.upsertIngredientMatch(
        IngredientMatchRow(
          recipeId: r.id,
          position: i,
          raw: nutritionLines(r)[i].raw,
          fdcId: 169655,
          description: 'gone',
          dataType: 'SR Legacy',
          confidence: 1,
          grams: 10,
          gramSource: 'override',
          status: status,
          hold: 'food_gone',
        ),
      );
    }
    final dart = <String, int>{};
    for (final m in db.ingredientMatchesFor(r.id)) {
      final b = matchBucketFor(
        status: m.status,
        fdcId: m.fdcId,
        grams: m.grams,
        confidence: m.confidence,
        hold: m.hold,
        gramSource: m.gramSource,
      ).wire;
      dart[b] = (dart[b] ?? 0) + 1;
    }
    expect(dart, {'check': 2, 'skipped': 1});
    expect(db.nutritionReviewCounts(), dart);
    expect(
      SaltDatabase.engineRuleNotesSql,
      engineRuleNotes.map((n) => "'$n'").join(', '),
    );
  });
  group("the closer's pins (the verifier's D1, D2, D4, D5, D7 — Run 057 "
      'Opus critics 2 #2 and 3 as written)', () {
    test('D1 / critic 3 as written (zz_c3): 0857 confirmed and computed, '
        "the flour's food in NO cache (food and search rows deleted), FDC "
        'out, basis 12 -> 13: 200, no request, every row untouched, the '
        'totals divided anew — fresh, complete, the same grams; a row '
        'written before migration 015 (no stored totals) divides its label '
        'back', () async {
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
      final rows = [for (final m in db.ingredientMatchesFor(r.id)) d.shape(m)];
      final keys = [
        for (final m in db.ingredientMatchesFor(r.id)) m.derivedSeq,
      ];
      expect(nutritionIsFresh(db, r), isTrue);
      expect((before.status, before.servingBasis), ('complete', 12));
      final id = d.rowOf(db, r, i).fdcId!;
      sqlite3.open(path)
        ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [id])
        ..execute(
          'DELETE FROM fdc_search_cache '
          "WHERE response LIKE '%\"fdc_id\":' || ? || ',%'",
          [id],
        )
        ..dispose();
      expect(knownFood(db, id, line: nutritionLines(r)[i]), isNull);
      final outage = a.Outage(fixture)..down = true;
      final (code, body) = await putBasis(db, outage, r.slug, {
        'serving_basis': 13,
      });
      expect(code, HttpStatus.ok, reason: '$body');
      expect(outage.failed, 0);
      expect(body['status'], 'complete');
      final after = db.nutritionFor(r.id)!;
      expect(after.servingBasis, 13);
      expect(
        (after.status, after.totalGrams, after.matchedCount),
        (before.status, before.totalGrams, before.matchedCount),
      );
      expect(
        (after.ingredientsHash, after.layoutSeq),
        (before.ingredientsHash, before.layoutSeq),
      );
      expect(
        after.caloriesPerServing,
        closeTo(before.caloriesPerServing! * 12 / 13, 0.01),
      );
      expect([for (final m in db.ingredientMatchesFor(r.id)) d.shape(m)], rows);
      expect([
        for (final m in db.ingredientMatchesFor(r.id)) m.derivedSeq,
      ], keys);
      expect(nutritionIsFresh(db, r), isTrue);
      // A pre-015 row: its label times its basis stands in for the totals.
      sqlite3.open(path)
        ..execute('UPDATE recipe_nutrition SET totals = NULL')
        ..dispose();
      final (back, _) = await putBasis(db, outage, r.slug, {
        'serving_basis': 12,
      });
      expect(back, HttpStatus.ok);
      expect(
        db.nutritionFor(r.id)!.caloriesPerServing,
        closeTo(before.caloriesPerServing!, 0.01),
      );
      expect(db.nutritionFor(r.id)!.totalsJson, isNotNull);
      expect(outage.failed, 0);
    });

    /// 0288's Old Bay typed 77 g, skipped, the line's amount edited and
    /// saved, its food's detail in no cache (the search hit kept), FDC
    /// out. (171331's detail recorded from the snapshot-15 cache for FDC's
    /// answer once it is back.)
    Future<(SaltDatabase, a.Outage, Recipe, int, double?)> skipEdited() async {
      final (db, path) = a.pathDb();
      final fixture = FixtureProvider(pending: pendingSearches);
      final r = loadCorpusRecipe('0288-maryland-crab-cakes.yaml');
      await d.editAndCompute(db, fixture, r);
      final i = d.at(r, a.oldBay0288);
      await applyMatchOverride(db, fixture, r, i, {
        'raw': a.oldBay0288,
        'grams': 77,
      });
      await applyMatchOverride(db, fixture, r, i, {
        'raw': a.oldBay0288,
        'skipped': true,
      });
      await matchAndCompute(db, fixture, r);
      final skippedTotal = db.nutritionFor(r.id)!.totalGrams;
      final e = a.rewritten(r, a.oldBay0288, threeTsp);
      wp.saveRecipe(db, e);
      final id = d.rowOf(db, e, i).fdcId!;
      sqlite3.open(path)
        ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [id])
        ..dispose();
      return (db, a.Outage(fixture)..down = true, e, i, skippedTotal);
    }

    test("D2 / Opus critic 2 #2 (zz_c2b): an un-skip of 0288's amount-edited "
        'Old Bay (typed 77 g for "1½ teaspoons", now "2 '
        'teaspoons") during an outage keeps NO grams — never the old '
        "amount's 77 g under the new text, never counted; FDC back, the "
        'new amount is derived', () async {
      final (db, outage, e, i, skippedTotal) = await skipEdited();
      await applyMatchOverride(db, outage, e, i, {
        'raw': threeTsp,
        'skipped': false,
      });
      expect(outage.failed, greaterThan(0), reason: 'the outage was met');
      final row = d.rowOf(db, e, i);
      expect(row.status, isNot('skipped'));
      expect((row.grams, row.gramSource), (null, null));
      expect(row.derivedSeq, isNull);
      expect(db.nutritionFor(e.id)!.totalGrams, skippedTotal);
      expect(nutritionIsFresh(db, e), isFalse);
      outage.down = false;
      await computeUntilFresh(db, outage, e);
      expect(nutritionIsFresh(db, e), isTrue);
      final derived = d.rowOf(db, e, i);
      expect(derived.raw, threeTsp);
      expect(derived.grams, isNot(77));
    });

    test(
      'D7: a SKIP is in the predicate — its derivation carries the row '
      "to its line's new text (the layout pairs by it), so a skip an "
      'amount edit left underived (FDC out at the compute) keeps the '
      'recipe stale, in the stale scope, until a compute re-texts it',
      () async {
        final (db, outage, e, i, _) = await skipEdited();
        final failure = await matchAndCompute(db, outage, e);
        expect(failure, isNotNull);
        final row = d.rowOf(db, e, i);
        expect(row.status, 'skipped');
        expect(row.raw, a.oldBay0288, reason: 'not re-texted');
        expect(nutritionStampCurrent(db, e), isTrue);
        expect(nutritionIsFresh(db, e), isFalse);
        expect(bulkScopeIds(db, BulkScope.stale), contains(e.id));
        outage.down = false;
        expect(await computeUntilFresh(db, outage, e), 1);
        expect(d.rowOf(db, e, i).raw, threeTsp);
        expect(nutritionIsFresh(db, e), isTrue);
      },
    );

    test("D4 (zz_a03): the predicate's KEY half — 0129's liquid smoke "
        'confirmed (derived for the old inputs, its key set), its detail '
        'evicted, the title edited, a compute during an outage: the row '
        'keeps the OLD key (not null) and the recipe is NOT fresh', () async {
      final (db, path) = a.pathDb();
      final fixture = FixtureProvider(pending: pendingSearches);
      final r = loadCorpusRecipe('0129-indoor-pulled-chicken.yaml');
      await d.editAndCompute(db, fixture, r);
      final i = d.at(r, d.smoke0129);
      await applyMatchOverride(db, fixture, r, i, {
        'raw': d.smoke0129,
        'confirmed': true,
      });
      final old = d.rowOf(db, r, i).derivedSeq;
      expect(old, keyOf(db, r));
      final id = d.rowOf(db, r, i).fdcId!;
      sqlite3.open(path)
        ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [id])
        ..dispose();
      final t = d.retitled(r);
      wp.saveRecipe(db, t);
      final outage = a.Outage(fixture)..down = true;
      expect(await matchAndCompute(db, outage, t), isNotNull);
      expect(d.rowOf(db, t, i).derivedSeq, old);
      expect(old, isNot(keyOf(db, t)));
      expect(nutritionStampCurrent(db, t), isTrue);
      expect(nutritionIsFresh(db, t), isFalse);
    });

    test(
      "D11's one hash per PUT is the PUT's own only while the stored "
      'recipe still equals what it hashed: 0279 fresh, a pick of 168317 '
      'whose food request a title save races — the recompute hashes the '
      'saved recipe and the stamp names no hash, never the old one',
      () async {
        final (db, fixture, r) = await d.computed(
          '0279-crispy-salt-and-pepper-shrimp.yaml',
        );
        expect(nutritionIsFresh(db, r), isTrue);
        final i = d.at(r, peppercorns0279);
        final racing = SaveOnFirstFood(
          fixture,
          () => wp.saveRecipe(db, d.retitled(r)),
        );
        await applyMatchOverride(db, racing, r, i, {
          'raw': peppercorns0279,
          'fdc_id': 168317,
        });
        expect(racing.save, isNull, reason: 'the save raced the PUT');
        expect(db.nutritionFor(r.id)!.ingredientsHash, '');
      },
    );

    test("D5 (zz_a08): the orphan branch writes its key — 0129's confirmed "
        'smoke with its amount edited to 2 tablespoons, one healthy '
        'computeUntilFresh: one pass, the row carries the new key, '
        'fresh', () async {
      final (db, fixture, r) = await d.computed(
        '0129-indoor-pulled-chicken.yaml',
      );
      final i = d.at(r, d.smoke0129);
      await applyMatchOverride(db, fixture, r, i, {
        'raw': d.smoke0129,
        'confirmed': true,
      });
      const twoTbsp = '2 tablespoons liquid smoke, divided';
      final e = a.rewritten(r, d.smoke0129, twoTbsp);
      wp.saveRecipe(db, e);
      expect(d.rowOf(db, e, i).raw, d.smoke0129, reason: 'an orphan');
      expect(await computeUntilFresh(db, fixture, e), 1);
      final row = d.rowOf(db, e, i);
      expect((row.raw, row.status), (twoTbsp, 'confirmed'));
      expect(row.derivedSeq, keyOf(db, e));
      expect(nutritionIsFresh(db, e), isTrue);
    });
  }, skip: skipIfNoCorpus);
  // @@MORE@@
}

/// PUTs [body] to the serving-basis route of [slug] through the real
/// pipeline, as a signed-in admin, with [provider] the context's FDC client
/// (the route must never read it); returns the status and decoded body.
Future<(int, Map<String, dynamic>)> putBasis(
  SaltDatabase db,
  NutritionProvider provider,
  String slug,
  Map<String, Object?> body,
) async {
  final adminId =
      db.userByUsername('admin')?.id ??
      db.createUser(username: 'admin', passwordHash: 'unused', role: 'admin');
  final pipeline =
      ((frog.RequestContext context) => basis_route.onRequest(context, slug))
          .use(
            frog.provider<AuthUser?>(
              (_) => AuthUser(
                id: adminId,
                username: 'admin',
                role: 'admin',
                mustChangePassword: false,
                scope: 'full',
                via: 'session',
              ),
            ),
          )
          .use(frog.provider<NutritionProvider>((_) => provider))
          .use(frog.provider<SaltDatabase>((_) => db))
          .use(errorHandler())
          .use(requestIdProvider());
  final server = await frog.serve(pipeline, InternetAddress.loopbackIPv4, 0);
  final client = HttpClient();
  try {
    final request = await client.open('PUT', '127.0.0.1', server.port, '/');
    request.headers
      ..contentType = ContentType.json
      ..set('X-Requested-With', csrfHeaderValue);
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return (response.statusCode, jsonDecode(text) as Map<String, dynamic>);
  } finally {
    client.close();
    await server.close(force: true);
  }
}
