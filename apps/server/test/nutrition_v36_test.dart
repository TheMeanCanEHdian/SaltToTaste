// Matcher v36 — Run 060 S4: an ENGINE line whose food FDC fails (FOOD)
// keeps the row it already had. Real corpus: 0857 Rich Chocolate Bundt
// Cake (line 0, the butter, auto on 173430) and 0506's napa line. The FOOD
// fault is the existing v28 FoodFault (the stated negative-path exception:
// a synthesized FDC failure over real recorded answers).
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'nutrition_v27_rule_a_test.dart' as ra;
import 'nutrition_v28_rule_a_test.dart' as v28;
import 'nutrition_v29_rule_a_test.dart' as v29;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

void main() {
  group(
    'v36 (Run 060 S4): an engine line keeps what it had',
    () {
      test(
        "E1/E3: 0857's butter (auto, a food) failing FOOD is KEPT — food, "
        'grams, status — underived, retry 1, the recipe stale (underived), '
        'the pass going on; FDC back: one request, fresh, 13/13 at the '
        'kcal it had. Three failures hold it food_unavailable WITH its '
        'food; a stale pass asks nothing; the `all` scope asks once and '
        'recovers it',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
          await d.editAndCompute(db, fixture, r);
          final before = db.nutritionFor(r.id)!;
          expect((before.status, before.matchedCount), ('complete', 13));
          expect(before.caloriesPerServing, closeTo(464.8, 0.05));
          final rows = db.ingredientMatchesFor(r.id);
          final row0 = rows.firstWhere((x) => x.position == 0);
          expect((row0.status, row0.fdcId), ('auto', 173430));
          final grams = row0.grams!;

          v28.dropFood(path, 173430);
          final fault = v28.FoodFault(
            fixture,
            {173430},
            scope: FailureScope.food,
          );
          final failure = await matchAndCompute(db, fault, r);
          expect(failure?.scope, FailureScope.food);
          expect(fault.asked, 1);
          final kept = d.rowOf(db, r, 0);
          expect(
            (kept.status, kept.fdcId, kept.description, kept.hold),
            ('auto', 173430, row0.description, null),
          );
          expect(kept.grams, grams);
          expect(kept.derivedSeq, isNull);
          expect(v29.retryOf(path, r.id, 0), 1);
          // The pass went on: every other line as it was.
          for (final other in rows.where((x) => x.position > 0)) {
            final now = d.rowOf(db, r, other.position);
            expect(
              (now.status, now.fdcId, now.grams),
              (other.status, other.fdcId, other.grams),
              reason: 'line ${other.position}',
            );
          }
          expect(nutritionIsFresh(db, r), isFalse);
          final body = nutritionBody(db, r, forAdmin: true);
          expect(
            (body['status'], body['stale_reason']),
            (
              'stale',
              'underived',
            ),
          );

          // FDC back: one request, the row derived again, fresh.
          fault.up = true;
          final asks = v29.Asks(fault);
          await matchAndCompute(db, asks, r);
          expect(asks.ids, [173430]);
          final back = d.rowOf(db, r, 0);
          expect(
            (back.status, back.fdcId, back.grams),
            ('auto', 173430, grams),
          );
          expect(v29.retryOf(path, r.id, 0), 0);
          expect(nutritionIsFresh(db, r), isTrue);
          final after = db.nutritionFor(r.id)!;
          expect((after.status, after.matchedCount), ('complete', 13));
          expect(after.caloriesPerServing, before.caloriesPerServing);

          // Three failures: held food_unavailable, the food kept.
          fault.up = false;
          v28.dropFood(path, 173430);
          for (var pass = 1; pass <= 3; pass++) {
            await matchAndCompute(db, fault, r);
            final row = d.rowOf(db, r, 0);
            expect((row.status, row.fdcId), ('auto', 173430), reason: '$pass');
            expect(v29.retryOf(path, r.id, 0), pass, reason: 'pass $pass');
            expect(
              row.hold,
              pass == 3 ? foodUnavailableHold : null,
              reason: 'pass $pass',
            );
          }
          expect(d.rowOf(db, r, 0).description, row0.description);
          // A held row is not asked again outside the `all` scope.
          final asked = fault.asked;
          await matchAndCompute(db, fault, r);
          expect(fault.asked, asked);
          expect(d.rowOf(db, r, 0).hold, foodUnavailableHold);
          // The `all` scope asks once more; FDC back: recovered.
          fault.up = true;
          final all = v29.Asks(fault);
          await matchAndCompute(db, all, r, retryUnavailable: true);
          expect(all.ids, [173430]);
          final healed = d.rowOf(db, r, 0);
          expect(
            (healed.status, healed.fdcId, healed.grams, healed.hold),
            ('auto', 173430, grams, null),
          );
          expect(v29.retryOf(path, r.id, 0), 0);
          expect(nutritionIsFresh(db, r), isTrue);
          expect(
            db.nutritionFor(r.id)!.caloriesPerServing,
            before.caloriesPerServing,
          );
        },
      );

      // Verifier D2: a HELD kept row is keyed by derived_seq as a decided
      // row is — an edit re-stamps it (no request, fresh), and a cache
      // that gains its food (another recipe's healthy compute) re-opens it:
      // stale (underived), in the stale scope, and the stale sweep derives
      // it from the cache with no request back to 13/13 at 464.8.
      test(
        "D2: 0857's held kept butter re-stamped by an edit, re-opened by a "
        'cache gain, recovered by a stale sweep with no request',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
          await d.editAndCompute(db, fixture, r);
          final before = db.nutritionFor(r.id)!;
          expect(before.caloriesPerServing, closeTo(464.8, 0.05));
          final grams = d.rowOf(db, r, 0).grams!;
          v28.dropFood(path, 173430);
          final fault = v28.FoodFault(
            fixture,
            {173430},
            scope: FailureScope.food,
          );
          for (var pass = 1; pass <= 3; pass++) {
            await matchAndCompute(db, fault, r);
          }
          final held = d.rowOf(db, r, 0);
          expect(
            (held.status, held.fdcId, held.hold),
            ('auto', 173430, foodUnavailableHold),
          );
          expect(held.derivedSeq, isNotNull);
          expect(nutritionIsFresh(db, r), isTrue);

          // An edit: stale by its stamp, re-stamped by the compute from
          // the caches alone — fresh again, still held, nothing asked.
          final edited = d.retitled(r);
          final asked = fault.asked;
          await d.editAndCompute(db, fault, edited);
          expect(fault.asked, asked);
          final restamped = d.rowOf(db, edited, 0);
          expect(restamped.hold, foodUnavailableHold);
          expect(restamped.derivedSeq, isNot(held.derivedSeq));
          expect(v29.retryOf(path, r.id, 0), 3);
          expect(nutritionIsFresh(db, edited), isTrue);
          expect(db.nutritionFor(r.id)!.matchedCount, 12);

          // Another recipe's healthy compute caches 173430.
          final other = wp.saveLines(db, [held.raw]);
          final oa = v29.Asks(FixtureProvider(pending: pendingSearches));
          await matchAndCompute(db, oa, other);
          expect(oa.ids, contains(173430));
          expect(nutritionIsFresh(db, edited), isFalse);
          expect(
            nutritionBody(db, edited, forAdmin: true)['stale_reason'],
            'underived',
          );
          expect(bulkScopeIds(db, BulkScope.stale), contains(r.id));

          // The stale sweep, FDC still failing: derived from the cache.
          final job = startBulkJob(db, fault, scope: BulkScope.stale)!;
          await ra.settle();
          expect(db.nutritionJob(job)!['done'], 1);
          expect(fault.asked, asked);
          final back = d.rowOf(db, edited, 0);
          expect(
            (back.status, back.fdcId, back.hold, back.grams),
            ('auto', 173430, null, grams),
          );
          expect(nutritionIsFresh(db, edited), isTrue);
          final after = db.nutritionFor(r.id)!;
          expect((after.status, after.matchedCount), ('complete', 13));
          expect(after.caloriesPerServing, before.caloriesPerServing);
        },
      );

      test(
        'E4: in a stale sweep the kept row is a FOOD failure of the job '
        "watch's — the job done, nothing failed, the error logged, the row "
        'kept and counted',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
          await d.editAndCompute(db, fixture, r);
          v28.dropFood(path, 173430);
          final edited = d.retitled(r);
          wp.saveRecipe(db, edited);
          final fault = v28.FoodFault(
            fixture,
            {173430},
            scope: FailureScope.food,
          );
          final job = startBulkJob(db, fault, scope: BulkScope.stale)!;
          await ra.settle();
          final run = db.nutritionJob(job)!;
          expect((run['status'], run['failed']), ('done', 0));
          expect(run['log'], ['${r.id}: FoodData Central error 500.']);
          expect(fault.asked, 1);
          final kept = d.rowOf(db, edited, 0);
          expect((kept.status, kept.fdcId), ('auto', 173430));
          expect(v29.retryOf(path, r.id, 0), 1);
          expect(nutritionIsFresh(db, edited), isFalse);
        },
      );

      test(
        "E2: a line with NO row with a food (0506's napa, first compute; "
        'then its own unmatched row) still gets the unmatched row (v29)',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final fault = v28.FoodFault(
            fixture,
            {v28.napaSibling},
            scope: FailureScope.food,
          );
          final r = wp.saveLines(db, [v28.napa]);
          for (var pass = 1; pass <= 2; pass++) {
            await matchAndCompute(db, fault, r);
            final row = d.rowOf(db, r, 0);
            expect(
              (row.status, row.description, row.fdcId, row.hold),
              ('unmatched', engineUnavailableNote, null, null),
              reason: 'pass $pass',
            );
            expect(v29.retryOf(path, r.id, 0), pass);
          }
        },
      );

      // Verifier D1: a kept row that carries its OWN hold (0042's almonds,
      // `coating`; 0129's broth, `partial_pour_away`) reads stale too, and
      // the next stale sweep asks again; the third failure holds it
      // food_unavailable (the hold that stops the asking), and the `all`
      // scope's recovery re-derives the line's own hold.
      for (final (file, position, fdcId, hold) in [
        (
          '0042-almond-crusted-chicken-with-wilted-spinach-salad.yaml',
          2,
          170567,
          'coating',
        ),
        ('0129-indoor-pulled-chicken.yaml', 0, 174536, 'partial_pour_away'),
      ]) {
        test(
          'D1: $file line $position (auto $fdcId, held $hold) failing FOOD '
          'reads stale (underived), a stale sweep asks again (retry 2), '
          'the third holds it food_unavailable with its food, `all` '
          'recovers it with its own hold',
          () async {
            final (db, path) = a.pathDb();
            final fixture = FixtureProvider(pending: pendingSearches);
            final r = loadCorpusRecipe(file);
            await d.editAndCompute(db, fixture, r);
            final row0 = d.rowOf(db, r, position);
            expect((row0.status, row0.fdcId, row0.hold), ('auto', fdcId, hold));
            expect(nutritionIsFresh(db, r), isTrue);
            final before = db.nutritionFor(r.id)!;

            v28.dropFood(path, fdcId);
            final fault = v28.FoodFault(
              fixture,
              {fdcId},
              scope: FailureScope.food,
            );
            final failure = await matchAndCompute(db, fault, r);
            expect(failure?.scope, FailureScope.food);
            expect(fault.asked, 1);
            final kept = d.rowOf(db, r, position);
            expect(
              (kept.status, kept.fdcId, kept.hold, kept.grams),
              ('auto', fdcId, hold, row0.grams),
            );
            expect(v29.retryOf(path, r.id, position), 1);
            expect(nutritionIsFresh(db, r), isFalse);
            final body = nutritionBody(db, r, forAdmin: true);
            expect(
              (body['status'], body['stale_reason']),
              ('stale', 'underived'),
            );

            // The next stale sweep asks again (v35 did; v36's first cut
            // read the recipe fresh and never asked).
            final job = startBulkJob(db, fault, scope: BulkScope.stale)!;
            await ra.settle();
            // v44: the recipe's child sections with no stamp yet join the
            // stale scope first (0129's "1 recipe barbecue sauce (recipes
            // follow)" lists its three sauces, rule PO) — v47 (F12): they
            // are computed but counted apart, `total` and `done` count the
            // recipe alone.
            final children = sectionChildKeysOf(db, r, ResolverMemo(db));
            expect(db.nutritionJob(job)!['total'], 1);
            expect(db.nutritionJob(job)!['done'], 1);
            for (final key in children) {
              expect(db.nutritionFor(key), isNotNull, reason: key);
            }
            expect(fault.asked, 2);
            expect(v29.retryOf(path, r.id, position), 2);
            expect(d.rowOf(db, r, position).hold, hold);
            expect(nutritionIsFresh(db, r), isFalse);

            // The third: held food_unavailable, the food kept; no longer
            // underived (the hold stops the asking).
            await matchAndCompute(db, fault, r);
            final held = d.rowOf(db, r, position);
            expect(
              (held.status, held.fdcId, held.hold),
              ('auto', fdcId, foodUnavailableHold),
            );
            expect(v29.retryOf(path, r.id, position), 3);
            expect(nutritionIsFresh(db, r), isTrue);
            final asked = fault.asked;
            final quiet = startBulkJob(db, fault, scope: BulkScope.stale)!;
            await ra.settle();
            final run = db.nutritionJob(quiet)!;
            expect((run['status'], run['done']), ('done', 0));
            expect(fault.asked, asked);

            // `all` with FDC back: one request, the line's own hold again.
            fault.up = true;
            final all = v29.Asks(fault);
            await matchAndCompute(db, all, r, retryUnavailable: true);
            expect(all.ids, [fdcId]);
            final healed = d.rowOf(db, r, position);
            expect(
              (healed.status, healed.fdcId, healed.hold, healed.grams),
              ('auto', fdcId, hold, row0.grams),
            );
            expect(v29.retryOf(path, r.id, position), 0);
            expect(nutritionIsFresh(db, r), isTrue);
            expect(
              db.nutritionFor(r.id)!.caloriesPerServing,
              before.caloriesPerServing,
            );
          },
        );
      }
    },
    skip: skipIfNoCorpus,
  );
}
