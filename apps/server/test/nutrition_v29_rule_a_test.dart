// RULE A, matcher v29 (brief I1 — Run 059 O1/S1/S6/S27, Sonnet critic 1 /
// O3 / Opus critic 3, O4/O10/S4/O11, Opus critic 1, Opus critics 2-3, S13,
// S2/S3, S7/S8 and the gap pins S16-S21, O13-O21, O23, S29): a hold is
// RE-READ before it is enforced (one reader, `knownFood`, through a
// cache-only derivation — the compute, the PUT's gate and the GET), for
// EVERY line kind (an engine line's FOOD failure is its row's state),
// counted in the JOB's units (the outage watch spans the sweep), and a pass
// is visible as IN PROGRESS until its totals are written (migration 017);
// a pass suspends its details after three failing in a row (the owner's
// ruling on Run 059 O10: an outage costs at most four requests a sweep).
//
// Real corpus recipes (0857 Rich Chocolate Bundt Cake, 0148 Crispy Fried
// Chicken, 0129 Indoor Pulled Chicken, 0506's napa line) and recorded FDC
// answers (FixtureProvider), never the network. Synthesized, each a stated
// exception: FDC failures (provider wrappers throwing the scope FdcProvider
// gives: FOOD for one food's detail, GLOBAL otherwise), FDC's "no such
// food" (cache rows deleted, FixtureProvider.superseded), the retired id
// 999000111 and the broken ids 900000001.. (no real row names them), a
// provider future that never completes (a process dying at an await), a
// title edit (stale), raw SQL single-field edits of a stored row (the
// guard's fields), the 400-line recipe of S13 (real corpus lines,
// repeated), rows deleted so a pass must re-match them, and a boot in a
// process of its own (a temp DATA_DIR, its two-line entrypoint written
// there).
// ignore_for_file: lines_longer_than_80_chars
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'nutrition_v27_rule_a_test.dart' as ra;
import 'nutrition_v28_rule_a_test.dart' as v28;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Counts every food request by id, then asks [inner].
class Asks implements NutritionProvider {
  Asks(this.inner);
  final NutritionProvider inner;
  final List<int> ids = [];

  @override
  Future<List<FdcCandidate>> search(String query) => inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) {
    ids.add(fdcId);
    return inner.food(fdcId);
  }
}

/// Every food request fails with [scope] (a detail outage); counts them.
class DetailDown implements NutritionProvider {
  DetailDown(this.inner, {this.scope = FailureScope.food});
  final NutritionProvider inner;
  final FailureScope scope;
  final List<int> ids = [];

  @override
  Future<List<FdcCandidate>> search(String query) => inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) async {
    ids.add(fdcId);
    throw NutritionProviderException(
      'FoodData Central is unavailable (HTTP 503); try again later.',
      scope: scope,
    );
  }
}

/// A food request that never answers (a process dying at the await).
class Hangs implements NutritionProvider {
  Hangs(this.inner);
  final NutritionProvider inner;
  bool hang = true;

  @override
  Future<List<FdcCandidate>> search(String query) => inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) =>
      hang ? Completer<FdcFood?>().future : inner.food(fdcId);
}

/// The raw `retry_count` of [recipeId]'s row at [position].
int retryOf(String path, String recipeId, int position) {
  final raw = sqlite3.open(path);
  try {
    return raw.select(
          'SELECT retry_count FROM ingredient_matches '
          'WHERE recipe_id = ? AND position = ?',
          [recipeId, position],
        ).first['retry_count']
        as int;
  } finally {
    raw.dispose();
  }
}

/// Saves [id] on the real lines [raws], computes it, then puts a person's
/// typed 10 g on a broken record at each position of [broken] (position →
/// a synthesized id no FDC record holds, stated) — underived, so the
/// recipe is stale.
Future<Recipe> withBroken(
  SaltDatabase db,
  NutritionProvider fixture,
  String id,
  List<String> raws,
  Map<int, int> broken,
) async {
  final r = wp.saveLines(db, raws, id: id);
  await matchAndCompute(db, fixture, r);
  final lines = nutritionLines(r);
  for (final MapEntry(key: position, value: fdcId) in broken.entries) {
    db.upsertIngredientMatch(
      IngredientMatchRow(
        recipeId: id,
        position: position,
        raw: lines[position].raw,
        fdcId: fdcId,
        description: 'Broken record',
        dataType: 'SR Legacy',
        confidence: 1,
        grams: 10,
        gramSource: 'override',
        status: 'overridden',
        itemKey: lineKeyOf(lines[position]),
      ),
      layoutSeq: db.layoutSeqOf(id),
    );
  }
  return r;
}

/// 0857's thirteen lines repeated to the editor cap (400, a stated
/// exception: real lines, synthesized repetition), every row a
/// person's confirm, underived, on a food no cache holds.
Future<(SaltDatabase, String, Recipe)> underived400() async {
  final (db, path) = a.pathDb();
  final fixture = FixtureProvider(pending: pendingSearches);
  final corpus = nutritionLines(
    loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml'),
  );
  final r = wp.saveLines(db, [
    for (var n = 0; n < 400; n++) corpus[n % corpus.length].raw,
  ]);
  await matchAndCompute(db, fixture, r);
  sqlite3.open(path)
    ..execute(
      "UPDATE ingredient_matches SET status = 'confirmed', "
      'derived_seq = NULL WHERE fdc_id IS NOT NULL',
    )
    ..execute('DELETE FROM fdc_food_cache')
    ..execute('DELETE FROM fdc_search_cache')
    ..dispose();
  expect(nutritionIsFresh(db, r), isFalse);
  return (db, path, r);
}

/// A food request for [id] runs [onAsk] first (a save arriving while the
/// request is out); counts them.
class OnAsk implements NutritionProvider {
  OnAsk(this.inner, this.id, this.onAsk);
  final NutritionProvider inner;
  final int id;
  final void Function() onAsk;
  int asks = 0;

  @override
  Future<List<FdcCandidate>> search(String query) => inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) {
    if (fdcId == id) {
      asks += 1;
      onAsk();
    }
    return inner.food(fdcId);
  }
}

/// Records, at every row write, the in-progress count of the row's recipe
/// (a test instrument, synthesized: a table and two triggers).
void recordMarks(String path) => sqlite3.open(path)
  ..execute('CREATE TABLE marks_seen (recipe_id TEXT, computing INT)')
  ..execute(_recordMark('INSERT'))
  ..execute(_recordMark('UPDATE'))
  ..dispose();

String _recordMark(String verb) =>
    'CREATE TRIGGER marks_seen_${verb.toLowerCase()} BEFORE $verb ON '
    'ingredient_matches BEGIN INSERT INTO marks_seen SELECT NEW.recipe_id, '
    'COALESCE((SELECT computing FROM recipe_nutrition WHERE recipe_id = '
    'NEW.recipe_id), 0); END';

/// What [recordMarks] saw: (recipe, count) per row write.
List<(String, int)> marksSeen(String path) {
  final raw = sqlite3.open(path);
  try {
    return [
      for (final row in raw.select('SELECT * FROM marks_seen'))
        (row['recipe_id'] as String, row['computing'] as int),
    ];
  } finally {
    raw.dispose();
  }
}

/// 0857's flour confirmed, then held `food_unavailable` by three FOOD
/// failures of its detail (every cache lost it). Returns the search
/// answers that listed it (to put back) and the failing provider.
Future<
  ({
    SaltDatabase db,
    String path,
    Recipe r,
    int i,
    int id,
    List<Map<String, Object?>> answers,
    v28.FoodFault fault,
  })
>
heldFlour() async {
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
  final answers = v28.dropFood(path, id);
  final fault = v28.FoodFault(fixture, {id}, scope: FailureScope.food);
  for (var n = 1; n <= 3; n++) {
    await matchAndCompute(db, fault, r);
  }
  expect(d.rowOf(db, r, i).hold, foodUnavailableHold);
  return (
    db: db,
    path: path,
    r: r,
    i: i,
    id: id,
    answers: answers,
    fault: fault,
  );
}

void main() {
  group(
    '(1) O1/S1/S6/S27: a stored no-record hold is re-read before it is '
    'enforced — one reader (knownFood) for the compute, the gate, the GET',
    () {
      test(
        "0857's flour held food_unavailable; a search answer lists it again: "
        'the PUT accepts a confirm at once (its gate re-reads, no request), '
        'and the GET and the row agree on 248 g',
        () async {
          final h = await heldFlour();
          v28.putBack(h.path, h.answers);
          final asked = h.fault.asked;
          await applyMatchOverride(h.db, h.fault, h.r, h.i, {
            'raw': a.flour0857,
            'confirmed': true,
          });
          expect(h.fault.asked, asked, reason: 'no request');
          final row = d.rowOf(h.db, h.r, h.i);
          expect(row.hold, isNull);
          expect(row.grams, closeTo(248.06, 0.01));
          final get = await v28.getOf(h.db, h.r, h.i);
          expect((get['hold'], get['grams']), (null, row.grams));
        },
      );

      test(
        "0857's flour held food_unavailable; a search answer lists it again: "
        'the cache write schedules the re-read (stale), the NEXT compute '
        'derives it cache-only (no request) — fresh, complete, the row and '
        'the GET agreeing',
        () async {
          final h = await heldFlour();
          expect(nutritionIsFresh(h.db, h.r), isTrue);
          // The answer comes back through the engine's own cache write (a
          // person's live search): it re-opens the held row — stale,
          // `underived` — before any compute.
          final query = h.answers.first['query']! as String;
          await searchCandidates(
            h.db,
            FixtureProvider(pending: pendingSearches),
            query,
            fresh: true,
          );
          expect(knownFood(h.db, h.id), isNotNull);
          expect(nutritionIsFresh(h.db, h.r), isFalse);
          expect(bulkScopeIds(h.db, BulkScope.stale), [h.r.id]);
          expect(
            nutritionBody(h.db, h.r, forAdmin: true)['stale_reason'],
            'underived',
          );
          final asked = h.fault.asked;
          await matchAndCompute(h.db, h.fault, h.r);
          expect(h.fault.asked, asked, reason: 'no request');
          final row = d.rowOf(h.db, h.r, h.i);
          expect(row.hold, isNull);
          expect(row.grams, closeTo(248.06, 0.01));
          final get = await v28.getOf(h.db, h.r, h.i);
          expect((get['hold'], get['grams']), (null, row.grams));
          expect(nutritionIsFresh(h.db, h.r), isTrue);
          expect(h.db.nutritionFor(h.r.id)!.status, 'complete');
        },
      );

      test(
        "0506's napa picked while its nutrient record's detail fails FOOD: "
        "held at the third compute; another recipe's fetch caches the "
        'record — the next compute derives it (no request), the GET agrees, '
        'a confirm is accepted',
        () async {
          final (db, _) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final fault = v28.FoodFault(
            fixture,
            {v28.napaSibling},
            scope: FailureScope.food,
          );
          final r = wp.saveLines(db, [v28.napa]);
          await matchAndCompute(db, fault, r);
          await applyMatchOverride(db, fault, r, 0, {
            'raw': v28.napa,
            'fdc_id': v28.napaId,
          });
          for (var n = 1; n <= 3; n++) {
            await matchAndCompute(db, fault, r);
          }
          expect(d.rowOf(db, r, 0).hold, foodUnavailableHold);
          fault.up = true;
          await matchAndCompute(
            db,
            fault,
            wp.saveLines(db, [v28.napa], id: 'other'),
          );
          fault.up = false;
          // Its record's cache write re-opened the held row (scheduled):
          // stale until the next compute re-reads it.
          expect(nutritionIsFresh(db, r), isFalse);
          final asked = fault.asked;
          await matchAndCompute(db, fault, r);
          expect(fault.asked, asked, reason: 'no request');
          final row = d.rowOf(db, r, 0);
          expect(row.hold, isNull);
          expect(row.grams, closeTo(340.19, 0.01));
          final get = await v28.getOf(db, r, 0);
          expect((get['hold'], get['grams']), (null, row.grams));
          expect(nutritionIsFresh(db, r), isTrue);
          expect(db.nutritionFor(r.id)!.status, 'complete');
          await applyMatchOverride(db, fault, r, 0, {
            'raw': v28.napa,
            'confirmed': true,
          });
          expect(d.rowOf(db, r, 0).status, 'confirmed');
        },
      );
    },
    skip: skipIfNoCorpus,
  );

  group(
    '(2) Sonnet critic 1 / O3 / Opus critic 3: an ENGINE line whose food '
    "FDC fails is its row's state — counted, held, the pass going on",
    () {
      test(
        "[0506's napa (engine), 0857's flour] with napa's nutrient record "
        'failing FOOD, six passes: the flour row on pass 1; the napa row '
        'retry 1, 2, then held food_unavailable — the recipe stale until '
        'then, fresh and partial after; one request per pass, then none; '
        'the `all` scope asks once more and FDC back matches it',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final fault = v28.FoodFault(
            fixture,
            {v28.napaSibling},
            scope: FailureScope.food,
          );
          final r = wp.saveLines(db, [v28.napa, a.flour0857]);
          for (var pass = 1; pass <= 6; pass++) {
            final asked = fault.asked;
            final failure = await matchAndCompute(db, fault, r);
            final napa = d.rowOf(db, r, 0);
            expect(d.rowOf(db, r, 1).fdcId, isNotNull, reason: 'pass $pass');
            expect(
              (napa.status, napa.description, napa.fdcId),
              ('unmatched', engineUnavailableNote, null),
              reason: 'pass $pass',
            );
            expect(
              retryOf(path, r.id, 0),
              pass <= 3 ? pass : 3,
              reason: 'pass $pass',
            );
            expect(
              napa.hold,
              pass >= 3 ? foodUnavailableHold : null,
              reason: 'pass $pass',
            );
            expect(fault.asked - asked, pass <= 3 ? 1 : 0, reason: '$pass');
            expect(failure?.scope, pass <= 3 ? FailureScope.food : null);
            expect(nutritionIsFresh(db, r), pass >= 3, reason: 'pass $pass');
            expect(db.nutritionFor(r.id)!.status, 'partial');
          }
          expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
          // The `all` scope's pass asks once more; FDC back: matched.
          fault.up = true;
          await matchAndCompute(db, fault, r, retryUnavailable: true);
          final napa = d.rowOf(db, r, 0);
          expect((napa.fdcId, napa.hold), (v28.napaId, null));
          expect(retryOf(path, r.id, 0), 0);
          expect(db.nutritionFor(r.id)!.status, 'complete');
          expect(nutritionIsFresh(db, r), isTrue);
        },
      );

      test(
        'a decided row failing FOOD beside an engine line failing FOOD: '
        'both counted every pass (the engine line no longer throws the '
        "pass away, O3), both held at the third — a's later lines computed",
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = wp.saveLines(db, [a.flour0857, v28.napa]);
          await matchAndCompute(db, fixture, r);
          final flourId = d.rowOf(db, r, 0).fdcId!;
          await applyMatchOverride(db, fixture, r, 0, {
            'raw': a.flour0857,
            'confirmed': true,
          });
          sqlite3.open(path)
            ..execute('DELETE FROM fdc_food_cache')
            ..execute('DELETE FROM fdc_search_cache')
            ..execute('UPDATE ingredient_matches SET derived_seq = NULL')
            ..dispose();
          final fault = v28.FoodFault(
            fixture,
            {flourId, v28.napaSibling},
            scope: FailureScope.food,
          );
          for (var pass = 1; pass <= 3; pass++) {
            await matchAndCompute(db, fault, r);
          }
          expect(d.rowOf(db, r, 0).hold, foodUnavailableHold);
          expect(d.rowOf(db, r, 1).hold, foodUnavailableHold);
          expect(nutritionIsFresh(db, r), isTrue);
        },
      );
    },
    skip: skipIfNoCorpus,
  );

  /// 0857's volume lines, each a recipe of its own (six distinct foods
  /// whose grams need FDC's household portions — a DETAIL).
  const volumeLines = [
    '1 cup sour cream, at room temperature',
    '1 teaspoon baking soda',
    '1 tablespoon vanilla extract',
    '¾ cup natural cocoa powder, plus 1 tablespoon for the pan',
    '1 teaspoon instant espresso powder (optional)',
    '1 teaspoon table salt',
  ];

  group(
    "(3) O4/O10/S4/O11: the outage escalation counted in the JOB's units",
    () {
      test(
        'a `missing` sweep over six recipes, every detail failing (FOOD, as '
        'a 503 after the retries is classed): at most three requests across '
        "the recipes, the job stopped with the provider's reason",
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          for (final (n, raw) in volumeLines.indexed) {
            await matchAndCompute(
              db,
              fixture,
              wp.saveLines(db, [raw], id: 'r$n'),
            );
          }
          sqlite3.open(path)
            ..execute('DELETE FROM recipe_nutrition')
            ..execute('DELETE FROM ingredient_matches')
            ..execute('DELETE FROM fdc_food_cache')
            ..dispose();
          final down = DetailDown(fixture);
          final job = startBulkJob(db, down)!;
          await ra.settle();
          final row = db.nutritionJob(job)!;
          expect(down.ids.length, lessThanOrEqualTo(detailOutageAfter));
          expect(down.ids.toSet(), hasLength(down.ids.length));
          expect(row['status'], 'failed');
          expect(
            row['log'],
            contains(
              startsWith('stopped at r2: FoodData Central is unavailable'),
            ),
          );
          // The owner's ruling (i): escalation never discards a count —
          // each engine row FDC failed carries it, the tipping one (r2)
          // included; r3 was never swept.
          for (final id in ['r0', 'r1', 'r2']) {
            expect(retryOf(path, id, 0), 1, reason: id);
          }
          expect(db.ingredientMatchesFor('r3'), isEmpty);
        },
      );

      test(
        "O4's shape — six recipes on 0506's napa, its record's detail "
        'failing FOOD: ONE request for the job (a food that failed is not '
        're-asked in it), no outage (one id), every recipe computed with '
        'its row counted',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final ids = ['a', 'b', 'c', 'd', 'e', 'f'];
          for (final id in ids) {
            await matchAndCompute(
              db,
              fixture,
              wp.saveLines(db, [v28.napa], id: id),
            );
          }
          v28.dropFood(path, v28.napaSibling);
          for (final id in ids) {
            wp.saveRecipe(
              db,
              d.retitled(db.recipeByIdOrSlug(id)!.recipe),
            );
          }
          final down = DetailDown(fixture);
          final job = startBulkJob(db, down, scope: BulkScope.stale)!;
          await ra.settle();
          final row = db.nutritionJob(job)!;
          expect(down.ids, [v28.napaSibling]);
          expect((row['status'], row['done'], row['failed']), ('done', 6, 0));
          for (final id in ids) {
            expect(retryOf(path, id, 0), 1, reason: id);
          }
        },
      );

      test(
        "O11's shape — three broken records (typed 10 g each) among healthy "
        'details in one recipe: no stop in three stale sweeps, the three rows '
        'held at the third with their typed grams kept (O13/S19), the recipe '
        'after it computed',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = wp.saveLines(db, volumeLines.sublist(0, 5), id: 'a');
          await matchAndCompute(db, fixture, r);
          final b = wp.saveLines(db, [volumeLines[5]], id: 'b');
          await matchAndCompute(db, fixture, b);
          final lines = nutritionLines(r);
          const broken = [900000001, 900000002, 900000003];
          for (final (k, position) in [0, 2, 4].indexed) {
            db.upsertIngredientMatch(
              IngredientMatchRow(
                recipeId: 'a',
                position: position,
                raw: lines[position].raw,
                fdcId: broken[k],
                description: 'Broken record',
                dataType: 'SR Legacy',
                confidence: 1,
                grams: 10,
                gramSource: 'override',
                status: 'overridden',
                itemKey: lineKeyOf(lines[position]),
              ),
              layoutSeq: db.layoutSeqOf('a'),
            );
          }
          final healthy = [
            d.rowOf(db, r, 1).fdcId!,
            d.rowOf(db, r, 3).fdcId!,
          ];
          wp.saveRecipe(db, d.retitled(b));
          final fault = v28.FoodFault(
            fixture,
            broken.toSet(),
            scope: FailureScope.food,
          );
          for (var sweep = 1; sweep <= 3; sweep++) {
            // Synthesized (stated): the healthy details leave the cache, so
            // each sweep asks FDC for them between the broken ones.
            sqlite3.open(path)
              ..execute(
                'DELETE FROM fdc_food_cache WHERE fdc_id IN (?, ?)',
                healthy,
              )
              ..dispose();
            final job = startBulkJob(db, fault, scope: BulkScope.stale)!;
            await ra.settle();
            final row = db.nutritionJob(job)!;
            expect(row['status'], 'done', reason: 'sweep $sweep');
            expect('${row['log']}', isNot(contains('stopped at')));
            for (final position in [0, 2, 4]) {
              final held = d.rowOf(db, r, position);
              expect(
                held.hold,
                sweep == 3 ? foodUnavailableHold : null,
                reason: 'sweep $sweep, line $position',
              );
              expect((held.grams, held.gramSource), (10, 'override'));
            }
          }
          expect(nutritionIsFresh(db, d.retitled(b)), isTrue);
          expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
        },
      );

      test(
        'O11 as the owner ruled — three broken records in ONE recipe, every '
        'other food cached (nothing answered between): one recipe never '
        'escalates — sweep 1 counts the three rows (retry 1) with no stop '
        'and computes the recipe after; sweep 3 holds them; then nothing is '
        'stale and nothing asked',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          const broken = {0: 900000001, 2: 900000002, 4: 900000003};
          final r = await withBroken(
            db,
            fixture,
            'a',
            volumeLines.sublist(0, 5),
            broken,
          );
          final b = wp.saveLines(db, [volumeLines[5]], id: 'b');
          await matchAndCompute(db, fixture, b);
          wp.saveRecipe(db, d.retitled(b));
          final asks = Asks(
            v28.FoodFault(
              fixture,
              broken.values.toSet(),
              scope: FailureScope.food,
            ),
          );
          for (var sweep = 1; sweep <= 3; sweep++) {
            final job = startBulkJob(db, asks, scope: BulkScope.stale)!;
            await ra.settle();
            final row = db.nutritionJob(job)!;
            expect(row['status'], 'done', reason: 'sweep $sweep');
            expect('${row['log']}', isNot(contains('stopped at')));
            for (final position in broken.keys) {
              expect(
                (retryOf(path, 'a', position), d.rowOf(db, r, position).hold),
                (sweep, sweep == 3 ? foodUnavailableHold : null),
                reason: 'sweep $sweep, line $position',
              );
            }
            expect(nutritionIsFresh(db, d.retitled(b)), isTrue);
          }
          expect(asks.ids, hasLength(9));
          expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
          startBulkJob(db, asks, scope: BulkScope.stale);
          await ra.settle();
          expect(asks.ids, hasLength(9));
        },
      );

      test(
        'the same three, and a FOURTH broken record in the NEXT recipe: the '
        'outage spans two recipes — it escalates there and stops the sweep '
        '(the recipe after never swept), yet all four rows carry their '
        'counts, held at the third sweep; the fourth sweep asks nothing and '
        'computes the rest',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          const broken = {0: 900000001, 2: 900000002, 4: 900000003};
          final r = await withBroken(
            db,
            fixture,
            'a',
            volumeLines.sublist(0, 5),
            broken,
          );
          final b = await withBroken(
            db,
            fixture,
            'b',
            [volumeLines[5]],
            {
              0: 900000004,
            },
          );
          final c = wp.saveLines(db, [volumeLines[1]], id: 'c');
          await matchAndCompute(db, fixture, c);
          final edited = d.retitled(c);
          wp.saveRecipe(db, edited);
          final asks = Asks(
            v28.FoodFault(fixture, {
              ...broken.values,
              900000004,
            }, scope: FailureScope.food),
          );
          for (var sweep = 1; sweep <= 3; sweep++) {
            final job = startBulkJob(db, asks, scope: BulkScope.stale)!;
            await ra.settle();
            final row = db.nutritionJob(job)!;
            expect(row['status'], 'failed', reason: 'sweep $sweep');
            expect(
              row['log'],
              contains(startsWith('stopped at b: FoodData Central error')),
            );
            final held = sweep == 3 ? foodUnavailableHold : null;
            for (final position in broken.keys) {
              expect(
                (retryOf(path, 'a', position), d.rowOf(db, r, position).hold),
                (sweep, held),
                reason: 'sweep $sweep, a line $position',
              );
            }
            expect(
              (retryOf(path, 'b', 0), d.rowOf(db, b, 0).hold),
              (sweep, held),
              reason: 'sweep $sweep, b',
            );
            expect(nutritionIsFresh(db, edited), isFalse, reason: 'c');
          }
          expect(asks.ids, hasLength(12));
          final job = startBulkJob(db, asks, scope: BulkScope.stale)!;
          await ra.settle();
          expect(db.nutritionJob(job)!['status'], 'done');
          expect(asks.ids, hasLength(12));
          expect(nutritionIsFresh(db, edited), isTrue);
          expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
        },
      );

      test(
        'a detail FDC ANSWERS between failures resets the run: three broken '
        'records one per recipe (p, q, r), q asking a healthy detail after '
        'its broken one — no escalation, the sweep done, each row counted',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          await withBroken(
            db,
            fixture,
            'p',
            [volumeLines[0]],
            {
              0: 900000001,
            },
          );
          final q = await withBroken(
            db,
            fixture,
            'q',
            [volumeLines[1], volumeLines[2]],
            {0: 900000002},
          );
          await withBroken(
            db,
            fixture,
            'r',
            [volumeLines[3]],
            {
              0: 900000003,
            },
          );
          final healthy = d.rowOf(db, q, 1).fdcId!;
          // Synthesized (stated): the healthy detail leaves the cache, so
          // q's compute asks FDC for it after its broken record.
          sqlite3.open(path)
            ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [healthy])
            ..dispose();
          final asks = Asks(
            v28.FoodFault(fixture, {
              900000001,
              900000002,
              900000003,
            }, scope: FailureScope.food),
          );
          final job = startBulkJob(db, asks, scope: BulkScope.stale)!;
          await ra.settle();
          final row = db.nutritionJob(job)!;
          expect(asks.ids, [900000001, 900000002, healthy, 900000003]);
          expect((row['status'], row['done']), ('done', 3));
          expect('${row['log']}', isNot(contains('stopped at')));
          for (final id in ['p', 'q', 'r']) {
            expect(retryOf(path, id, 0), 1, reason: id);
          }
        },
      );

      test(
        'O10 as the owner ruled — the PASS suspends its details: a `missing` '
        'sweep whose first recipe has five lines each needing a detail, '
        'every detail failing FOOD: three requests in that recipe and it '
        'suspends (no escalation, one recipe), ONE in the next (the outage '
        'spans two recipes there: the job stops with the reason) — '
        'detailOutageAfter + 1 in all; the three failed rows counted, the '
        'last two lines asked nothing and counted nothing, the recipe stale',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final ra0 = wp.saveLines(db, volumeLines.sublist(0, 5), id: 'a');
          await matchAndCompute(db, fixture, ra0);
          await matchAndCompute(
            db,
            fixture,
            wp.saveLines(db, [volumeLines[5]], id: 'b'),
          );
          sqlite3.open(path)
            ..execute('DELETE FROM recipe_nutrition')
            ..execute('DELETE FROM ingredient_matches')
            ..execute('DELETE FROM fdc_food_cache')
            ..dispose();
          final down = DetailDown(fixture);
          final job = startBulkJob(db, down)!;
          await ra.settle();
          final row = db.nutritionJob(job)!;
          expect(down.ids, hasLength(detailOutageAfter + 1));
          expect(down.ids.toSet(), hasLength(down.ids.length));
          expect((row['status'], row['done']), ('failed', 1));
          expect(
            row['log'],
            containsAll([
              startsWith('a: FoodData Central is unavailable'),
              startsWith('stopped at b: FoodData Central is unavailable'),
            ]),
          );
          for (final position in [0, 1, 2]) {
            expect(retryOf(path, 'a', position), 1, reason: 'a $position');
          }
          expect(
            db.ingredientMatchesFor('a').where((m) => m.position > 2),
            isEmpty,
          );
          expect(nutritionIsFresh(db, ra0), isFalse);
          // Nothing changed: waiting on USDA, never `inputs` (O23).
          expect(
            nutritionBody(db, ra0, forAdmin: true)['stale_reason'],
            'underived',
          );
          expect(bulkScopeIds(db, BulkScope.stale), contains('a'));
          expect(retryOf(path, 'b', 0), 1);
        },
      );

      test(
        'the bound whatever the recipe size — the 400-decided-row recipe '
        '(S13), every detail failing FOOD: its pass asks three details and '
        'suspends — one pass (no second pass re-asking), the rows on the '
        'three failed foods counted, every other row underived and '
        'uncounted, the recipe stale',
        () async {
          final (db, path, r) = await underived400();
          final down = DetailDown(FixtureProvider(pending: pendingSearches));
          final passes = await computeUntilFresh(db, jobProvider(down), r);
          expect(passes, 1);
          expect(down.ids, hasLength(detailOutageAfter));
          final failed = down.ids.toSet();
          expect(failed, hasLength(detailOutageAfter));
          final raw = sqlite3.open(path);
          final rows = raw.select(
            'SELECT fdc_id, retry_count, derived_seq FROM ingredient_matches '
            "WHERE recipe_id = ? AND status = 'confirmed' "
            'AND fdc_id IS NOT NULL',
            [r.id],
          );
          raw.dispose();
          expect(rows, hasLength(greaterThan(300)));
          for (final row in rows) {
            expect(
              (row['retry_count'], row['derived_seq']),
              failed.contains(row['fdc_id']) ? (1, null) : (0, null),
              reason: 'food ${row['fdc_id']}',
            );
          }
          expect(nutritionIsFresh(db, r), isFalse);
          expect(
            nutritionBody(db, r, forAdmin: true)['stale_reason'],
            'underived',
          );
          expect(bulkScopeIds(db, BulkScope.stale), contains(r.id));
        },
      );

      test(
        'O11 K=3 under the suspension — three broken records IN A ROW at the '
        "head of one recipe, its other lines' details cached: sweep 1 "
        'suspends after the three (no other request) yet re-matches the '
        'cached lines from the caches on pass 1 (the suspension stops only '
        'further DETAILS); the three held at the third sweep; nothing stale',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          const broken = {0: 900000001, 1: 900000002, 2: 900000003};
          final r = await withBroken(
            db,
            fixture,
            'a',
            volumeLines.sublist(0, 5),
            broken,
          );
          String shape(IngredientMatchRow m) =>
              '${m.status} ${m.fdcId} ${m.grams} ${m.gramSource}';
          final before = [
            for (final p in [3, 4]) shape(d.rowOf(db, r, p)),
          ];
          // Synthesized (stated): the two cached lines' rows removed, so
          // pass 1 must match them again — from the caches alone.
          sqlite3.open(path)
            ..execute(
              'DELETE FROM ingredient_matches '
              "WHERE recipe_id = 'a' AND position > 2",
            )
            ..dispose();
          final asks = Asks(
            v28.FoodFault(
              fixture,
              broken.values.toSet(),
              scope: FailureScope.food,
            ),
          );
          for (var sweep = 1; sweep <= 3; sweep++) {
            final job = startBulkJob(db, asks, scope: BulkScope.stale)!;
            await ra.settle();
            final row = db.nutritionJob(job)!;
            expect(row['status'], 'done', reason: 'sweep $sweep');
            expect('${row['log']}', isNot(contains('stopped at')));
            expect(asks.ids, hasLength(3 * sweep), reason: 'sweep $sweep');
            for (final position in broken.keys) {
              expect(
                (retryOf(path, 'a', position), d.rowOf(db, r, position).hold),
                (sweep, sweep == 3 ? foodUnavailableHold : null),
                reason: 'sweep $sweep, line $position',
              );
            }
            expect(
              [
                for (final p in [3, 4]) shape(d.rowOf(db, r, p)),
              ],
              before,
              reason: 'sweep $sweep',
            );
          }
          expect(asks.ids.toSet(), broken.values.toSet());
          expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
        },
      );

      test(
        'a failure the JOB already holds costs no request and does not '
        "count toward a pass's suspension: b's three lines on the three "
        'records that failed in a (answered from the job, no request), then '
        'a healthy uncached detail — b asks it (no suspension) and its line '
        'is matched',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          const broken = {0: 900000001, 1: 900000002, 2: 900000003};
          await withBroken(
            db,
            fixture,
            'a',
            volumeLines.sublist(0, 3),
            broken,
          );
          final b = await withBroken(
            db,
            fixture,
            'b',
            volumeLines.sublist(0, 4),
            broken,
          );
          final healthy = d.rowOf(db, b, 3).fdcId!;
          // Synthesized (stated): the healthy detail leaves the cache.
          sqlite3.open(path)
            ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [healthy])
            ..dispose();
          final asks = Asks(
            v28.FoodFault(
              fixture,
              broken.values.toSet(),
              scope: FailureScope.food,
            ),
          );
          final job = startBulkJob(db, asks, scope: BulkScope.stale)!;
          await ra.settle();
          expect(db.nutritionJob(job)!['status'], 'done');
          expect(asks.ids, [...broken.values, healthy]);
          expect(d.rowOf(db, b, 3).fdcId, healthy);
          expect(db.fdcFoodCacheGet(healthy), isNotNull);
          for (final position in broken.keys) {
            expect(retryOf(path, 'b', position), 1, reason: 'b $position');
          }
        },
      );

      test(
        "a detail FDC ANSWERS between failures resets the PASS's run: "
        'broken, healthy (uncached), broken, broken, broken in ONE recipe — '
        'no suspension: every detail asked, the four broken rows counted',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          const broken = {
            0: 900000001,
            2: 900000002,
            3: 900000003,
            4: 900000004,
          };
          final r = await withBroken(
            db,
            fixture,
            'a',
            volumeLines.sublist(0, 5),
            broken,
          );
          final healthy = d.rowOf(db, r, 1).fdcId!;
          // Synthesized (stated): the healthy detail leaves the cache.
          sqlite3.open(path)
            ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [healthy])
            ..dispose();
          final asks = Asks(
            v28.FoodFault(
              fixture,
              broken.values.toSet(),
              scope: FailureScope.food,
            ),
          );
          final failure = await matchAndCompute(db, jobProvider(asks), r);
          expect(failure, isNot(isA<DetailsSuspended>()));
          expect(asks.ids, [
            900000001,
            healthy,
            900000002,
            900000003,
            900000004,
          ]);
          for (final position in broken.keys) {
            expect(retryOf(path, 'a', position), 1, reason: 'line $position');
          }
        },
      );
    },
    skip: skipIfNoCorpus,
  );

  group(
    '(4) Opus critic 1: a pass is IN PROGRESS until its totals are written '
    '— an OWNED count, each writer releasing only its own mark',
    () {
      test(
        "[0857's flour (a person's confirm, underived by an outage), 0506's "
        "napa]: a pass marks the flour derived, then waits on napa's record "
        'forever (a process dying at the await) — the recipe reads stale, '
        '`interrupted`, in the stale scope, after a reopen too; the boot '
        'clears its stamp and resets the count; the next compute repairs it',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = wp.saveLines(db, [a.flour0857, v28.napa]);
          await matchAndCompute(db, fixture, r);
          expect(db.nutritionFor(r.id)!.computing, 0);
          final flour = d.rowOf(db, r, 0).fdcId!;
          final answers = v28.dropFood(path, flour);
          final outage = a.Outage(fixture)..down = true;
          await applyMatchOverride(db, outage, r, 0, {
            'raw': a.flour0857,
            'confirmed': true,
          });
          expect(d.rowOf(db, r, 0).derivedSeq, isNull);
          v28.putBack(path, answers);
          v28.dropFood(path, v28.napaSibling);
          final hangs = Hangs(fixture);
          unawaited(matchAndCompute(db, hangs, r));
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(d.rowOf(db, r, 0).derivedSeq, ra.keyOf(db, r));
          expect(nutritionStampCurrent(db, r), isTrue);
          expect(db.nutritionFor(r.id)!.computing, 1);
          expect(nutritionIsFresh(db, r), isFalse);
          expect(
            nutritionBody(db, r, forAdmin: true)['stale_reason'],
            'interrupted',
          );
          expect(bulkScopeIds(db, BulkScope.stale), [r.id]);
          // A restart: the mark outlives the process — stale on reopen;
          // the boot's reconciliation clears the stamp and the count.
          final reopened = SaltDatabase.open(path);
          addTearDown(reopened.dispose);
          expect(nutritionIsFresh(reopened, r), isFalse);
          expect(reopened.resetInterruptedComputes(), 1);
          final reset = reopened.nutritionFor(r.id)!;
          expect(reset.computing, 0);
          expect(
            reset.ingredientsHash,
            startsWith(SaltDatabase.interruptedStamp),
          );
          expect(nutritionIsFresh(reopened, r), isFalse);
          expect(
            nutritionBody(reopened, r, forAdmin: true)['stale_reason'],
            'interrupted',
          );
          expect(bulkScopeIds(reopened, BulkScope.stale), [r.id]);
          expect(reopened.resetInterruptedComputes(), 0);
          await computeUntilFresh(reopened, fixture, r);
          expect(reopened.nutritionFor(r.id)!.computing, 0);
          expect(nutritionIsFresh(reopened, r), isTrue);
          expect(reopened.nutritionFor(r.id)!.status, 'complete');
        },
      );

      test(
        "a writer's totals release ITS mark only (two marks, one released: "
        'still stale); a writer that took none releases nothing; a thrown '
        'pass releases its own and clears the stamp (stale, `interrupted`)',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = wp.saveLines(db, [a.flour0857]);
          await matchAndCompute(db, fixture, r);
          expect(db.markComputing('no-such-recipe'), isFalse);
          expect(db.markComputing(r.id), isTrue);
          expect(db.markComputing(r.id), isTrue);
          expect(nutritionIsFresh(db, r), isFalse);
          expect(recomputeTotals(db, r), isTrue);
          expect(db.nutritionFor(r.id)!.computing, 2);
          expect(recomputeTotals(db, r, ending: true), isTrue);
          expect(db.nutritionFor(r.id)!.computing, 1);
          expect(nutritionIsFresh(db, r), isFalse);
          expect(recomputeTotals(db, r, ending: true), isTrue);
          expect(db.nutritionFor(r.id)!.computing, 0);
          expect(nutritionIsFresh(db, r), isTrue);
          final edited = d.retitled(r);
          wp.saveRecipe(db, edited);
          sqlite3.open(path)
            ..execute('DELETE FROM fdc_search_cache')
            ..dispose();
          await expectLater(
            matchAndCompute(db, a.Outage(fixture)..down = true, edited),
            throwsA(isA<NutritionProviderException>()),
          );
          final row = db.nutritionFor(r.id)!;
          expect(row.computing, 0);
          expect(
            row.ingredientsHash,
            startsWith(SaltDatabase.interruptedStamp),
          );
          expect(nutritionIsFresh(db, edited), isFalse);
          expect(
            nutritionBody(db, edited, forAdmin: true)['stale_reason'],
            'interrupted',
          );
        },
      );

      test(
        'a writer that took NO mark (its recipe had no stamp then: a '
        "person's write on a recipe never computed) releases nothing at its "
        "throw — another writer's mark, taken after a compute stamped the "
        'recipe meanwhile, stands (the calls in the order that interleaving '
        'makes them)',
        () async {
          final (db, _) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = wp.saveLines(db, [a.flour0857]);
          final first = db.markComputing(r.id);
          expect(first, isFalse);
          await matchAndCompute(db, fixture, r);
          expect(db.markComputing(r.id), isTrue);
          db.releaseComputing(r.id, owned: first, stale: true);
          expect(db.nutritionFor(r.id)!.computing, 1);
          expect(nutritionIsFresh(db, r), isFalse);
          db.releaseComputing(r.id, owned: true, stale: false);
          expect(db.nutritionFor(r.id)!.computing, 0);
        },
      );

      test(
        "the BOOT runs the reconciliation: a db left with a writer's mark "
        '(computing 1), booted through initServer in a process of its own '
        '(DATA_DIR a temp dir), reads the count reset and the stamp '
        '`interrupted:` — stale, `interrupted`',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = wp.saveLines(db, [a.flour0857]);
          await matchAndCompute(db, fixture, r);
          expect(db.markComputing(r.id), isTrue);
          final dataDir = File(path).parent.path;
          final boot = File('$dataDir/boot.dart')
            ..writeAsStringSync(
              "import 'dart:io';\n"
              "import 'package:salt_server/src/bootstrap.dart';\n"
              'void main() {\n'
              '  initServer();\n'
              '  disposeServer();\n'
              '  exit(0);\n'
              '}\n',
            );
          final packages = await Isolate.packageConfig;
          final run = await Process.run(
            Platform.resolvedExecutable,
            ['--packages=${packages!.toFilePath()}', boot.path],
            environment: {'DATA_DIR': dataDir},
          );
          expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
          final row = db.nutritionFor(r.id)!;
          expect(row.computing, 0);
          expect(
            row.ingredientsHash,
            startsWith(SaltDatabase.interruptedStamp),
          );
          expect(nutritionIsFresh(db, r), isFalse);
          expect(
            nutritionBody(db, r, forAdmin: true)['stale_reason'],
            'interrupted',
          );
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        "a person's PUT during a pass that has not reached its totals: the "
        'PUT marks BEFORE its row write (both counts held: 2), and its '
        "totals release only its own — the pass's mark stands (stale)",
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = wp.saveLines(db, [a.flour0857, v28.napa]);
          await matchAndCompute(db, fixture, r);
          v28.dropFood(path, v28.napaSibling);
          unawaited(matchAndCompute(db, Hangs(fixture), r));
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(db.nutritionFor(r.id)!.computing, 1);
          recordMarks(path);
          await applyMatchOverride(db, fixture, r, 0, {
            'raw': a.flour0857,
            'confirmed': true,
          });
          expect(marksSeen(path).toSet(), {(r.id, 2)});
          expect(d.rowOf(db, r, 0).status, 'confirmed');
          expect(db.nutritionFor(r.id)!.computing, 1);
          expect(nutritionIsFresh(db, r), isFalse);
        },
      );

      test(
        'an apply-to-all target marks BEFORE its row write and its totals '
        "release it: [0857's flour] in two recipes, a pick of olive oil "
        '(173468) applied to all — every row write under a mark, both '
        'counts back to 0',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = wp.saveLines(db, [a.flour0857], id: 'a');
          await matchAndCompute(db, fixture, r);
          await matchAndCompute(
            db,
            fixture,
            wp.saveLines(db, [a.flour0857], id: 'b'),
          );
          recordMarks(path);
          final applied = await applyMatchOverride(db, fixture, r, 0, {
            'raw': a.flour0857,
            'fdc_id': 173468,
            'apply_to_all': true,
          });
          expect((applied!.recipes, applied.lines), (1, 1));
          expect(marksSeen(path).toSet(), {('a', 1), ('b', 1)});
          expect(db.nutritionFor('a')!.computing, 0);
          expect(db.nutritionFor('b')!.computing, 0);
        },
      );
    },
    skip: skipIfNoCorpus,
  );

  group(
    '(5) Opus critics 2/3: the PUT gate reads EVERY verb the body carries',
    () {
      test(
        "0148's rows held food_gone: {skipped: true, grams} and {skipped: "
        'true, confirmed: true} are 422 "one decision per request" with '
        "nothing written; a confirm alone is the hold's own 422",
        () async {
          final r = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
          final db = wp.tempDb();
          wp.saveRecipe(db, r);
          await matchAndCompute(db, ra.Retired(), r);
          final lines = nutritionLines(r);
          db.upsertIngredientMatch(
            IngredientMatchRow(
              recipeId: r.id,
              position: 0,
              raw: lines[0].raw,
              fdcId: v28.poisoned,
              description: 'Retired food',
              dataType: 'SR Legacy',
              confidence: 1,
              grams: 10,
              gramSource: 'weight',
              status: 'confirmed',
              itemKey: lineKeyOf(lines[0]),
            ),
            layoutSeq: db.layoutSeqOf(r.id),
          );
          final gone = ra.Retired();
          await computeUntilFresh(db, gone, r);
          final before = d.rowOf(db, r, 0);
          expect(before.hold, foodGoneHold);
          for (final body in <Map<String, Object?>>[
            {'skipped': true, 'grams': 50},
            {'skipped': true, 'confirmed': true},
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
                  oneDecisionMessage,
                ),
              ),
              reason: '$body',
            );
            expect(d.shape(d.rowOf(db, r, 0)), d.shape(before));
          }
          await expectLater(
            applyMatchOverride(db, gone, r, 0, {
              'raw': lines[0].raw,
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
          // A pick puts another food on the line: grams with it are the
          // new food's, accepted (the combined change-match + amount).
          final oil = (await FixtureProvider().food(173468))!;
          await applyMatchOverride(
            db,
            FixtureProvider(pending: pendingSearches),
            r,
            0,
            {
              'raw': lines[0].raw,
              'fdc_id': oil.fdcId,
              'grams': 50,
            },
          );
          expect(
            (d.rowOf(db, r, 0).fdcId, d.rowOf(db, r, 0).grams),
            (173468, 50),
          );
        },
      );

      test(
        "an un-skip of 0857's flour typed 250 g BEFORE its food went: "
        're-derived like any decision — held food_gone, the typed grams '
        'kept as the decision, never counted unheld; the GET agrees',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
          await d.editAndCompute(db, fixture, r);
          final i = d.at(r, a.flour0857);
          await applyMatchOverride(db, fixture, r, i, {
            'raw': a.flour0857,
            'grams': 250,
          });
          await applyMatchOverride(db, fixture, r, i, {
            'raw': a.flour0857,
            'skipped': true,
          });
          final id = d.rowOf(db, r, i).fdcId!;
          v28.dropFood(path, id);
          final gone = FixtureProvider(
            pending: pendingSearches,
            superseded: {id},
          );
          await applyMatchOverride(db, gone, r, i, {
            'raw': a.flour0857,
            'skipped': false,
          });
          final row = d.rowOf(db, r, i);
          expect(
            (row.status, row.hold, row.grams, row.gramSource),
            ('overridden', foodGoneHold, 250, 'override'),
          );
          final get = await v28.getOf(db, r, i);
          expect(get['hold'], foodGoneHold);
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
        },
      );
    },
    skip: skipIfNoCorpus,
  );

  group(
    "(6) S13: a PUT resolves ONLY its own line's food and nutrient record",
    () {
      test(
        '400 underived rows on uncached foods: a typed-grams PUT on one line '
        'asks at most two foods (its own), in milliseconds — the others stay '
        'underived and the recipe stale',
        () async {
          final (db, _, r) = await underived400();
          final asks = Asks(FixtureProvider(pending: pendingSearches));
          final position = d.at(r, '1 teaspoon baking soda');
          final own = d.rowOf(db, r, position).fdcId!;
          final clock = Stopwatch()..start();
          await applyMatchOverride(db, asks, r, position, {
            'raw': '1 teaspoon baking soda',
            'grams': 5,
          });
          clock.stop();
          // ignore: avoid_print
          print(
            'PUT on 1 of 400 underived rows: ${clock.elapsedMilliseconds} '
            'ms, ${asks.ids.length} requests',
          );
          expect(asks.ids.toSet(), foodsOf(own));
          expect(asks.ids.length, lessThanOrEqualTo(2));
          expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
          final rows = db.ingredientMatchesFor(r.id);
          expect(
            rows.where((m) => m.fdcId != null && m.derivedSeq == null),
            hasLength(greaterThan(300)),
          );
          expect(nutritionIsFresh(db, r), isFalse);
        },
      );

      test(
        "a GLOBAL failure stops the PUT's resolution at once: one request",
        () async {
          final (db, _, r) = await underived400();
          final down = DetailDown(
            FixtureProvider(pending: pendingSearches),
            scope: FailureScope.global,
          );
          final position = d.at(r, '1 teaspoon baking soda');
          await applyMatchOverride(db, down, r, position, {
            'raw': '1 teaspoon baking soda',
            'grams': 5,
          });
          expect(down.ids, hasLength(1));
          expect(d.rowOf(db, r, position).grams, 5);
          expect(nutritionIsFresh(db, r), isFalse);
        },
      );

      test(
        "the GLOBAL stop with BOTH of the line's foods missing (Run 059 "
        "A26): 0506's napa picked on one line, its nutrient record 169979 "
        'picked on another (a person can), neither cached, FDC down — a '
        'typed PUT on the napa line asks ONE food, never the record after',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          const salt = '1 teaspoon table salt';
          final r = wp.saveLines(db, [v28.napa, salt]);
          await matchAndCompute(db, fixture, r);
          await applyMatchOverride(db, fixture, r, 0, {
            'raw': v28.napa,
            'fdc_id': v28.napaId,
          });
          await applyMatchOverride(db, fixture, r, 1, {
            'raw': salt,
            'fdc_id': v28.napaSibling,
          });
          v28.dropFood(path, v28.napaId);
          v28.dropFood(path, v28.napaSibling);
          final down = DetailDown(fixture, scope: FailureScope.global);
          await applyMatchOverride(db, down, r, 0, {
            'raw': v28.napa,
            'grams': 50,
          });
          expect(foodsOf(v28.napaId), {v28.napaId, v28.napaSibling});
          expect(down.ids, [v28.napaId]);
          expect(d.rowOf(db, r, 0).grams, 50);
        },
      );
    },
    skip: skipIfNoCorpus,
  );

  group(
    '(7) S2/S3: the held write keeps its count; the `all` scope asks once',
    () {
      test(
        "0857's flour held food_unavailable, FDC still failing, the title "
        'edited: the next compute asks nothing, the row stays held with its '
        'count (S2: never re-staled); a confirm is the 422 "USDA could not '
        'serve this food"',
        () async {
          final h = await heldFlour();
          expect(retryOf(h.path, h.r.id, h.i), 3);
          final edited = d.retitled(h.r);
          wp.saveRecipe(h.db, edited);
          final asked = h.fault.asked;
          await matchAndCompute(h.db, h.fault, edited);
          expect(h.fault.asked, asked);
          expect(d.rowOf(h.db, edited, h.i).hold, foodUnavailableHold);
          expect(retryOf(h.path, h.r.id, h.i), 3);
          expect(nutritionIsFresh(h.db, edited), isTrue);
          await expectLater(
            applyMatchOverride(h.db, h.fault, edited, h.i, {
              'raw': a.flour0857,
              'confirmed': true,
            }),
            throwsA(
              isA<ValidationException>().having(
                (e) => e.message,
                'message',
                unavailableMessage,
              ),
            ),
          );
        },
      );

      test(
        "0857's flour held by three TRANSIENT failures, FDC healthy again: "
        'a stale sweep never asks (nothing stale); an `all` sweep asks once '
        'and the row recovers — 248 g, complete, fresh; the next `all` '
        'sweep asks nothing',
        () async {
          final h = await heldFlour();
          h.fault.up = true;
          final asks = Asks(h.fault);
          startBulkJob(h.db, asks, scope: BulkScope.stale);
          await ra.settle();
          expect(asks.ids, isEmpty);
          startBulkJob(h.db, asks, scope: BulkScope.all);
          await ra.settle();
          expect(asks.ids, [h.id]);
          final row = d.rowOf(h.db, h.r, h.i);
          expect(row.hold, isNull);
          expect(row.grams, closeTo(248.06, 0.01));
          expect(retryOf(h.path, h.r.id, h.i), 0);
          expect(h.db.nutritionFor(h.r.id)!.status, 'complete');
          expect(nutritionIsFresh(h.db, h.r), isTrue);
          startBulkJob(h.db, asks, scope: BulkScope.all);
          await ra.settle();
          expect(asks.ids, [h.id]);
        },
      );

      test(
        'the stale scope NEVER asks a held row (Run 059 A30): its recipe '
        'stale (the title edited), FDC healthy again — the sweep re-reads '
        'the hold from the caches, no request, the row still held',
        () async {
          final h = await heldFlour();
          h.fault.up = true;
          final edited = d.retitled(h.r);
          wp.saveRecipe(h.db, edited);
          expect(bulkScopeIds(h.db, BulkScope.stale), [h.r.id]);
          final asks = Asks(h.fault);
          startBulkJob(h.db, asks, scope: BulkScope.stale);
          await ra.settle();
          expect(asks.ids, isNot(contains(h.id)));
          expect(d.rowOf(h.db, edited, h.i).hold, foodUnavailableHold);
          expect(nutritionIsFresh(h.db, edited), isTrue);
        },
      );

      test(
        'the `all` scope asks ONCE per sweep, on its first pass (Run 059 '
        'A31): a save while that request is out runs a second pass, which '
        're-reads the hold from the caches — one request in all',
        () async {
          final h = await heldFlour();
          var saved = false;
          final saves = OnAsk(h.fault, h.id, () {
            if (!saved) {
              saved = true;
              wp.saveRecipe(h.db, d.retitled(h.r));
            }
          });
          final passes = await computeUntilFresh(
            h.db,
            saves,
            h.r,
            retryUnavailable: true,
          );
          expect(passes, 2);
          expect(saves.asks, 1);
          expect(d.rowOf(h.db, h.r, h.i).hold, foodUnavailableHold);
        },
      );

      test(
        'an `all` sweep while FDC still fails: one request, the row held '
        'again at once with its count running on — a row v28 held (its held '
        'write reset the count to 0) too',
        () async {
          final h = await heldFlour();
          sqlite3.open(h.path)
            ..execute('UPDATE ingredient_matches SET retry_count = 0')
            ..dispose();
          final edited = d.retitled(h.r);
          wp.saveRecipe(h.db, edited);
          final asked = h.fault.asked;
          startBulkJob(h.db, h.fault, scope: BulkScope.all);
          await ra.settle();
          expect(h.fault.asked - asked, 1);
          expect(d.rowOf(h.db, h.r, h.i).hold, foodUnavailableHold);
          expect(retryOf(h.path, h.r.id, h.i), 1);
          expect(nutritionIsFresh(h.db, edited), isTrue);
        },
      );
    },
    skip: skipIfNoCorpus,
  );

  group(
    'the I1 gap pins (S16, S18, S20/O15, S21/O16, O18, O19, S29)',
    () {
      test(
        'S16: the GET of a row held food_unavailable whose food no cache '
        "holds shows the hold (derivedFor's unavailable arm keeps it)",
        () async {
          final h = await heldFlour();
          final get = await v28.getOf(h.db, h.r, h.i);
          expect((get['hold'], get['grams']), (foodUnavailableHold, null));
        },
      );

      test(
        'S18: recomputeTotals(missing:) names a missing nutrient RECORD — '
        "0506's napa (picked) with 169979 in no cache: the sibling, not the "
        'food, and nothing written',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = wp.saveLines(db, [v28.napa, '1 teaspoon table salt']);
          await matchAndCompute(db, fixture, r);
          await applyMatchOverride(db, fixture, r, 0, {
            'raw': v28.napa,
            'fdc_id': v28.napaId,
          });
          v28.dropFood(path, v28.napaSibling);
          final missing = <int>{};
          expect(recomputeTotals(db, r, missing: missing), isFalse);
          expect(missing, {v28.napaSibling});
        },
      );

      test(
        'S20/O15: the guard of markDerivedIfUnchanged and '
        'countFoodFailureIfUnchanged compares EVERY one of its eight fields',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = wp.saveLines(db, [a.flour0857]);
          await matchAndCompute(db, fixture, r);
          await applyMatchOverride(db, fixture, r, 0, {
            'raw': a.flour0857,
            'confirmed': true,
          });
          final over = d.rowOf(db, r, 0);
          final seq = db.layoutSeqOf(r.id);
          const changes = {
            'raw': "raw || ' (edited)'",
            'status': "'overridden'",
            'fdc_id': '1',
            'confidence': '0.5',
            'grams': '1',
            'gram_source': "'override'",
            'hold': "'coating'",
            'description': "'another food'",
          };
          final raw = sqlite3.open(path);
          addTearDown(raw.dispose);
          for (final MapEntry(key: field, value: value) in changes.entries) {
            final was = raw.select(
              'SELECT $field AS v FROM ingredient_matches WHERE recipe_id = ?',
              [r.id],
            ).first['v'];
            raw.execute(
              'UPDATE ingredient_matches SET $field = $value WHERE recipe_id = ?',
              [r.id],
            );
            expect(
              db.markDerivedIfUnchanged(over, derivedSeq: 'x', layoutSeq: seq),
              isFalse,
              reason: field,
            );
            expect(
              db.countFoodFailureIfUnchanged(over, layoutSeq: seq),
              isNull,
              reason: field,
            );
            raw.execute(
              'UPDATE ingredient_matches SET $field = ? WHERE recipe_id = ?',
              [was, r.id],
            );
          }
          expect(db.countFoodFailureIfUnchanged(over, layoutSeq: seq), 1);
          expect(
            db.markDerivedIfUnchanged(over, derivedSeq: 'x', layoutSeq: seq),
            isTrue,
          );
        },
      );

      test(
        "S21/O16: every write resets the row's retry_count but the held "
        'write and the held re-mark (S2), which keep it',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = wp.saveLines(db, [a.flour0857, '1 teaspoon table salt']);
          await matchAndCompute(db, fixture, r);
          final raw = sqlite3.open(path);
          addTearDown(raw.dispose);
          void two() =>
              raw.execute('UPDATE ingredient_matches SET retry_count = 2');
          final seq = db.layoutSeqOf(r.id);
          // A person's write (_upsertMatch).
          two();
          db.upsertIngredientMatch(
            d.rowOf(db, r, 0).copyWith(status: 'confirmed'),
            layoutSeq: seq,
          );
          expect(retryOf(path, r.id, 0), 0, reason: "a person's write");
          // The engine's write over its own row (_upsertIfUndecided).
          two();
          db.upsertIngredientMatchIfUndecided(
            d.rowOf(db, r, 1),
            layoutSeq: seq,
          );
          expect(retryOf(path, r.id, 1), 0, reason: "the engine's write");
          // A derivation's mark resets; a held re-mark keeps.
          two();
          final over = d.rowOf(db, r, 0);
          db.markDerivedIfUnchanged(over, derivedSeq: 'k', layoutSeq: seq);
          expect(retryOf(path, r.id, 0), 0, reason: 'a derivation');
          two();
          db.markDerivedIfUnchanged(
            over,
            derivedSeq: 'k2',
            layoutSeq: seq,
            keepRetryCount: true,
          );
          expect(retryOf(path, r.id, 0), 2, reason: 'a held re-mark');
          // The replace resets unless it is the held write.
          db.replaceIngredientMatchIfUnchanged(
            over.copyWith(hold: foodUnavailableHold),
            over: over,
            layoutSeq: seq,
            keepRetryCount: true,
          );
          expect(retryOf(path, r.id, 0), 2, reason: 'the held write');
          final held = d.rowOf(db, r, 0);
          db.replaceIngredientMatchIfUnchanged(
            held.copyWith(clearHold: true),
            over: held,
            layoutSeq: seq,
          );
          expect(retryOf(path, r.id, 0), 0, reason: 'a replace');
        },
      );

      test(
        "O18: 0506's napa record 169979 known only from a cached search "
        'answer (none in fdc_food_cache): a derivation reads it there — no '
        "request (_siblingGone's cache arm)",
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = wp.saveLines(db, [v28.napa]);
          await matchAndCompute(db, fixture, r);
          await applyMatchOverride(db, fixture, r, 0, {
            'raw': v28.napa,
            'fdc_id': v28.napaId,
          });
          v28.dropFood(path, v28.napaSibling);
          // A recorded answer that lists 169979 (a real FDC search).
          await searchCandidates(db, fixture, 'chinese black vinegar');
          expect(knownFood(db, v28.napaSibling), isNotNull);
          final edited = d.retitled(r);
          wp.saveRecipe(db, edited);
          final asks = Asks(fixture);
          await matchAndCompute(db, asks, edited);
          expect(asks.ids, isEmpty);
          expect(nutritionIsFresh(db, edited), isTrue);
          expect(d.rowOf(db, edited, 0).hold, isNull);
        },
      );

      test(
        "O19: migration 016's index loses a deleted answer's rows and a "
        "replaced answer's dropped ids (read directly, never through a JOIN)",
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          await searchCandidates(db, fixture, 'chinese black vinegar');
          final raw = sqlite3.open(path);
          addTearDown(raw.dispose);
          int indexed(int id) =>
              raw.select(
                    'SELECT COUNT(*) AS n FROM fdc_search_cache_foods '
                    'WHERE fdc_id = ?',
                    [id],
                  ).first['n']
                  as int;
          expect(indexed(v28.napaSibling), greaterThan(0));
          final query =
              raw.select(
                    'SELECT query FROM fdc_search_cache_foods WHERE fdc_id = ?',
                    [v28.napaSibling],
                  ).first['query']
                  as String;
          raw.execute(
            'INSERT OR REPLACE INTO fdc_search_cache (query, response) '
            'VALUES (?, ?)',
            [query, '[]'],
          );
          expect(indexed(v28.napaSibling), 0, reason: 'replaced');
          await searchCandidates(
            db,
            fixture,
            'chinese black vinegar',
            fresh: true,
          );
          expect(indexed(v28.napaSibling), greaterThan(0));
          raw.execute('DELETE FROM fdc_search_cache');
          expect(
            raw
                .select('SELECT COUNT(*) AS n FROM fdc_search_cache_foods')
                .first['n'],
            0,
            reason: 'deleted',
          );
        },
      );

      test(
        'S29: an Error a provider throws inside an apply-to-all target '
        'propagates — never counted `failed`',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          await matchAndCompute(
            db,
            fixture,
            wp.saveLines(db, ['¼ cup extra-virgin olive oil'], id: 'b'),
          );
          v28.dropFood(path, 173468);
          await expectLater(
            applyDecisionToOthers(
              db,
              _Throws(fixture),
              itemKey: lineKeyOf(wp.lineOf('¼ cup extra-virgin olive oil')),
              decided: (await fixture.food(173468))!,
              excluding: (recipeId: 'a', position: 0),
            ),
            throwsA(isA<StateError>()),
          );
        },
      );

      test(
        "O17: 0857's sour cream (a volume line) confirmed, held "
        'food_unavailable, then a search answer lists its food again: the '
        're-read needs the DETAIL (household portions), so it stays held with '
        'no request on every compute — only the `all` scope asks',
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          const cream = '1 cup sour cream, at room temperature';
          final r = wp.saveLines(db, [cream]);
          await matchAndCompute(db, fixture, r);
          await applyMatchOverride(db, fixture, r, 0, {
            'raw': cream,
            'confirmed': true,
          });
          final id = d.rowOf(db, r, 0).fdcId!;
          final answers = v28.dropFood(path, id);
          final fault = v28.FoodFault(fixture, {id}, scope: FailureScope.food);
          for (var n = 1; n <= 3; n++) {
            await matchAndCompute(db, fault, r);
          }
          expect(d.rowOf(db, r, 0).hold, foodUnavailableHold);
          v28.putBack(path, answers);
          expect(knownFood(db, id), isNotNull);
          final asked = fault.asked;
          for (var n = 1; n <= 3; n++) {
            await matchAndCompute(db, fault, r);
          }
          expect(fault.asked, asked);
          expect(d.rowOf(db, r, 0).hold, foodUnavailableHold);
          await matchAndCompute(db, fault, r, retryUnavailable: true);
          expect(fault.asked, asked + 1);
        },
      );

      test(
        "S24: 0148's dredge flour (held `coating`) with typed grams, its food "
        'in no cache: the next compute derives it (FDC) — typed grams answer '
        "every hold, the hold dropped (keepsHold's !keepTyped)",
        () async {
          final (db, path) = a.pathDb();
          final fixture = FixtureProvider(pending: pendingSearches);
          final r = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
          await d.editAndCompute(db, fixture, r);
          final coated = db
              .ingredientMatchesFor(r.id)
              .firstWhere((m) => m.hold == 'coating');
          final raw = nutritionLines(r)[coated.position].raw;
          await applyMatchOverride(db, fixture, r, coated.position, {
            'raw': raw,
            'grams': 50,
          });
          expect(d.rowOf(db, r, coated.position).hold, isNull);
          v28.dropFood(path, coated.fdcId!);
          final edited = d.retitled(r);
          await d.editAndCompute(db, fixture, edited);
          final row = d.rowOf(db, r, coated.position);
          expect((row.status, row.grams, row.hold), ('overridden', 50, null));
        },
      );
    },
    skip: skipIfNoCorpus,
  );
}

/// Every food request throws an Error (a programming fault).
class _Throws implements NutritionProvider {
  _Throws(this.inner);
  final NutritionProvider inner;

  @override
  Future<List<FdcCandidate>> search(String query) => inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) async => throw StateError('unexpected');
}
