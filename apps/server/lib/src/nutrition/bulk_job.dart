import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/fdc_provider.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';

final Logger _log = Logger('nutrition');

bool _bulkRunning = false;

/// Whether a bulk compute is currently in flight (only one at a time).
bool get bulkJobRunning => _bulkRunning;

/// Per-recipe compute jobs currently in flight: recipe id -> job id.
/// In-memory (jobs don't outlive a restart; a rare restart mid-compute just
/// needs a re-run), and it's what lets a reopened recipe page re-attach to a
/// running compute instead of showing a stale "not computed" state.
final Map<String, int> _recipeJobs = {};

/// The running compute job id for [recipeId], or null — used by the nutrition
/// body so the client can re-attach after navigating away and back.
int? recipeComputeJobId(String recipeId) => _recipeJobs[recipeId];

/// Starts (or re-attaches to) a background compute for a single [recipe] and
/// returns the job id. Single-flight per recipe: a second request while one
/// is running returns the same job rather than double-spending FDC budget —
/// and that job computes the stored recipe again when a save cut it off.
///
/// Runs on the event loop (I/O-bound, provider-throttled) so the POST returns
/// immediately with a job id the client polls — no synchronous request left
/// hanging (and erroring) while the server keeps working.
int startRecipeComputeJob(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe recipe,
) {
  final existing = _recipeJobs[recipe.id];
  if (existing != null) {
    return existing;
  }
  final jobId = db.createNutritionJob(1);
  _recipeJobs[recipe.id] = jobId;
  unawaited(_runOne(db, provider, jobId, recipe));
  return jobId;
}

Future<void> _runOne(
  SaltDatabase db,
  NutritionProvider provider,
  int jobId,
  Recipe recipe,
) async {
  try {
    final notes = <String>[];
    await computeUntilFresh(
      db,
      // The job's outage watch, across its passes ([jobProvider]).
      jobProvider(provider),
      recipe,
      onFoodFailure: (error) => notes.add('${recipe.id}: $error'),
    );
    db.updateNutritionJob(
      jobId,
      done: 1,
      failed: 0,
      status: 'done',
      logJson: notes.isEmpty ? null : jsonEncode(notes),
    );
  } on NutritionProviderException catch (error) {
    // No key / bad key / hard rate failure — surface the reason in the log.
    db.updateNutritionJob(
      jobId,
      done: 0,
      failed: 1,
      status: 'failed',
      logJson: jsonEncode(['${recipe.id}: $error']),
    );
    // ignore: avoid_catches_without_on_clauses
  } catch (error) {
    db.updateNutritionJob(
      jobId,
      done: 0,
      failed: 1,
      status: 'failed',
      logJson: jsonEncode(['${recipe.id}: $error']),
    );
  } finally {
    _recipeJobs.remove(recipe.id);
  }
}

/// One recipe's compute, the step BOTH job loops run (the per-recipe job
/// and the bulk sweep, Run 052 S5/O5): single-flight, a request while it
/// runs re-attaches to it ([startRecipeComputeJob]), so a save that cut
/// the compute's writes off (its gate tripped, the totals stamped stale) is
/// computed again from the stored recipe — at most [maxComputePasses]
/// passes, until the STAMP is current ([nutritionStampCurrent]; Run 051
/// B5: the request was dropped and the job ended 'done' with no rows). A
/// recipe deleted meanwhile stops cleanly. Returns the passes run; still
/// stale after the last pass throws a [StateError] — both loops log it and
/// count the recipe failed (Run 053: the pass count was dropped, so a
/// recipe left stale read 'done').
///
/// Only a moved layout or hash is a reason for another pass (RULE A, v27):
/// a decided row whose derivation could not run is underived — the
/// recipe reads stale ([nutritionIsFresh]) and the next sweep derives it —
/// and a second pass would only ask FDC the same thing again (Run 057
/// S5/S16/O2/O16: 3 passes, 42 requests for 0148's 13 rows, and a
/// StateError masking the provider's reason). Its GLOBAL provider failure
/// ([FailureScope.global]: a bad key, the budget, an outage) is rethrown
/// once the pass is written, so both loops stop and say why; a FOOD one
/// (FDC failing one decided row's food, v28 — Run 058 Opus critic 1 /
/// S27: it stopped every sweep at that recipe) is that row's state, told
/// to [onFoodFailure] for the job's log, and the recipe is done.
Future<int> computeUntilFresh(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe recipe, {
  void Function(NutritionProviderException failure)? onFoodFailure,
  bool retryUnavailable = false,
}) async {
  var current = recipe;
  for (var pass = 1; ; pass++) {
    final failure = await matchAndCompute(
      db,
      provider,
      current,
      retryUnavailable: retryUnavailable && pass == 1,
    );
    if (failure != null) {
      if (failure.scope == FailureScope.global) {
        throw failure;
      }
      onFoodFailure?.call(failure);
      if (failure is DetailsSuspended) {
        return pass; // Another pass would only ask FDC again ([onePass]).
      }
    }
    final stored = db.recipeByIdOrSlug(recipe.id)?.recipe;
    if (stored == null || nutritionStampCurrent(db, stored)) {
      return pass;
    }
    if (pass == maxComputePasses) {
      throw StateError('still stale after $pass compute passes');
    }
    current = stored;
  }
}

/// The most passes [computeUntilFresh] runs for one recipe.
const int maxComputePasses = 3;

/// The FDC client a BULK job uses, as a context-provided value.
///
/// Distinct type on purpose: the interactive client (`NutritionProvider`) gives
/// up after ~30s of rate-limit waiting so a drained budget becomes an
/// explained 4xx, while the bulk client has no wait cap and rides out the
/// hour. They must be separately injectable. The bulk route used to reach for
/// bootstrap's process-wide getter directly, which no test could substitute —
/// so every HTTP test that started a bulk job was silently hitting the REAL
/// USDA API through whatever key sat in the developer's `.data`, and a test
/// that set `failWith` on the injected fixture never touched the job at all.
class BulkNutritionProvider {
  /// Wraps [provider] for `context.read<BulkNutritionProvider>()`.
  const BulkNutritionProvider(this.provider);

  /// The client bulk jobs call.
  final NutritionProvider provider;
}

/// Which recipes a bulk compute covers.
enum BulkScope {
  /// Never computed. The historical behaviour and the default.
  missing('missing'),

  /// Computed, but the ingredient lines have changed since — the results on
  /// screen are wrong and only a recompute fixes them.
  stale('stale'),

  /// Every recipe, computed or not.
  all('all');

  const BulkScope(this.wireName);

  /// The value clients send as `scope`.
  final String wireName;

  /// [BulkScope] for [name], or null when it names nothing.
  static BulkScope? fromWire(String name) {
    for (final scope in values) {
      if (scope.wireName == name) return scope;
    }
    return null;
  }
}

/// Recipe ids [scope] selects.
///
/// `stale` is the only one that cannot be a query: the staleness test is a
/// Dart-side hash (with the stamp's layout, [nutritionIsFresh]: a recipe
/// whose layout moved since its stamp is stale whatever its hash, and so is
/// one with an underived decided row — [SaltDatabase.underivedSql], RULE
/// A, the same predicate the recipe page reads), so every
/// recipe with nutrition is decoded and compared
/// (see [SaltDatabase.recipesWithNutrition] for why there is no timestamp
/// shortcut). Measured at ~110-190 ms for the whole 1,198-recipe library,
/// synchronously on the serving isolate, on admin-only endpoints (the sweep
/// itself and the `bulk/counts` preview, which is why the preview is
/// guarded against a cross-site drive).
///
/// v41 (design_v3 §2.1, F7): every scope is ordered PARENTS LAST — a recipe
/// whose main lines hold a sub-recipe reference ([readsSubRecipe]) after
/// every recipe that holds none, each side by id — keyed on the DOCUMENT, so
/// the order holds on a fresh import (no stored row names a child yet) and
/// on the first v41 sweep: a parent's composite row then reads its child's
/// new totals and stamp in the same job. One partition suffices: depth is 1
/// by rule (a child holding a reference row is held `nested_recipe`). And
/// `stale` appends every recipe holding a row whose child it selected
/// ([SaltDatabase.recipesReadingChildren]): a child stale by its hash (a
/// save, a reconciled file) moves its `computed_at` only when this sweep
/// recomputes it, after the scope is fixed — without the append its
/// parents would wait for a second sweep.
List<String> bulkScopeIds(SaltDatabase db, BulkScope scope) {
  final ids = <String>[];
  final parents = <String>{};
  Recipe read(String id, String doc) {
    final recipe = RecipeMapper.fromMap(
      jsonDecode(doc) as Map<String, dynamic>,
    );
    if (readsSubRecipe(recipe)) {
      parents.add(id);
    }
    return recipe;
  }

  switch (scope) {
    case BulkScope.missing:
    case BulkScope.all:
      final wanted = scope == BulkScope.missing
          ? db.recipeIdsWithoutNutrition().toSet()
          : null;
      for (final (:id, :doc) in db.recipeDocs()) {
        if (wanted == null || wanted.contains(id)) {
          ids.add(id);
          read(id, doc);
        }
      }
    case BulkScope.stale:
      for (final candidate in db.recipesWithNutrition()) {
        final recipe = read(candidate.id, candidate.doc);
        if (!candidate.layoutCurrent ||
            candidate.underived ||
            ingredientsHashOf(recipe) != candidate.ingredientsHash) {
          ids.add(candidate.id);
        }
      }
      final selected = ids.toSet();
      for (final parent in db.recipesReadingChildren(selected)) {
        if (selected.add(parent)) {
          ids.add(parent);
          // It reads a child by its stored row: a parent whatever its doc.
          parents.add(parent);
        }
      }
      ids.sort();
  }
  return [
    ...ids.where((id) => !parents.contains(id)),
    ...ids.where(parents.contains),
  ];
}

/// Whether [recipe]'s main lines (the ones nutrition reads) hold a
/// sub-recipe reference ([isSubRecipeReference]) — a parent, ordered after
/// every other recipe by [bulkScopeIds].
bool readsSubRecipe(Recipe recipe) => recipe.ingredients.any(
  (group) => group.items.any((line) => isSubRecipeReference(line.raw)),
);

/// Starts a background bulk compute over the recipes [scope] selects;
/// returns the job id, or null when one is already running.
///
/// Runs on the server's event loop (no isolate): the work is I/O-bound and
/// self-throttled by the provider's token bucket, so interactive requests
/// interleave freely. Progress and per-recipe failures land in the
/// `nutrition_jobs` row — silent partial failure is prohibited.
///
/// Recomputing is non-destructive, which is what makes a broad scope safe to
/// offer: the engine's writes land only where no human decision stands
/// ([SaltDatabase.upsertIngredientMatchIfUndecided]) — checked at WRITE time,
/// so a confirm made while a recipe's compute is waiting on the provider
/// survives it. A sweep re-resolves `auto`, `unmatched` and genuinely changed
/// lines and leaves confirmed/overridden/skipped ones alone.
int? startBulkJob(
  SaltDatabase db,
  NutritionProvider provider, {
  BulkScope scope = BulkScope.missing,
}) {
  if (_bulkRunning) {
    return null;
  }
  final ids = bulkScopeIds(db, scope);
  final jobId = db.createNutritionJob(ids.length);
  _bulkRunning = true;
  unawaited(
    _run(db, provider, jobId, ids, retryUnavailable: scope == BulkScope.all),
  );
  return jobId;
}

/// [retryUnavailable]: the `all` scope asks FDC again, once per recipe,
/// for every row held `food_unavailable` (v29 RULE A, Run 059 S3 — a
/// healthy food held by transient failures recovers with no person); the
/// `stale` and `missing` scopes never do (the hold is re-read from the
/// caches only).
Future<void> _run(
  SaltDatabase db,
  NutritionProvider provider,
  int jobId,
  List<String> ids, {
  bool retryUnavailable = false,
}) async {
  // ONE outage watch for the whole job (v29 RULE A, Run 059 O4/O10/S4):
  // its FOOD failures are counted across recipes ([jobProvider]), and each
  // pass suspends its details after `detailOutageAfter` failing in a row
  // ([onePass]) — so a detail outage stops the sweep after at most
  // `detailOutageAfter` + 1 requests (3 in the first recipe, 1 in the
  // next), whatever the recipes' sizes.
  final watched = jobProvider(provider);
  var done = 0;
  var failed = 0;
  final log = <String>[];
  // The bucket's tally is process-wide (interactive traffic and earlier jobs
  // too); the job's own spend is the difference.
  final tallyAtStart = provider is UsdaFdcProvider
      ? Map.of(provider.requestCounts)
      : const <String, int>{};
  try {
    for (final id in ids) {
      // Yield the event loop between recipes: fully cached computes are
      // synchronous end-to-end, and a long cached stretch would otherwise
      // starve interactive requests.
      await Future<void>.delayed(Duration.zero);
      final found = db.recipeByIdOrSlug(id);
      if (found == null) {
        done += 1;
        continue; // Deleted mid-job.
      }
      // Single-flight with the per-recipe compute: if one is already running
      // for this id, the bulk job would spend the FDC budget twice on the
      // same lines and both would write. Skip it — the running job finishes
      // it. Registering here is also what lets the recipe page and the review
      // queue see `computing_job_id` for a recipe the bulk sweep is on.
      if (_recipeJobs.containsKey(id)) {
        log.add('$id: skipped, a compute is already running');
        done += 1;
        continue;
      }
      _recipeJobs[id] = jobId;
      try {
        await computeUntilFresh(
          db,
          watched,
          found.recipe,
          retryUnavailable: retryUnavailable,
          // One food FDC fails on: that row's state (underived, held
          // `food_unavailable` after `foodUnavailableAfter` computes) — the
          // sweep moves on and the log says which.
          onFoodFailure: (error) => log.add('$id: $error'),
        );
      } on NutritionProviderException catch (error) {
        // GLOBAL — no key / bad key / the budget / an outage, a detail
        // outage escalated by the job's watch included: every remaining
        // recipe would fail identically — stop and say why. (A FOOD failure
        // never leaves a pass since v29: an engine line's is its row's
        // state like a decided row's, Run 059 Sonnet critic 1 / O3.)
        log.add('stopped at $id: $error');
        db.updateNutritionJob(
          jobId,
          done: done,
          failed: failed + 1,
          status: 'failed',
          logJson: jsonEncode(log),
        );
        return;
        // One bad recipe must not sink the batch; the log carries it.
        // ignore: avoid_catches_without_on_clauses
      } catch (error) {
        failed += 1;
        log.add('$id: $error');
      } finally {
        // Balanced on EVERY exit, including the provider-failure `return`
        // above: a registration left behind makes the per-recipe compute
        // hand back a dead job id forever and every later sweep skip the
        // recipe as "already running".
        _recipeJobs.remove(id);
      }
      done += 1;
      if (done % 10 == 0 || done == ids.length) {
        db.updateNutritionJob(
          jobId,
          done: done,
          failed: failed,
          logJson: jsonEncode(log),
        );
      }
    }
    db.updateNutritionJob(
      jobId,
      done: done,
      failed: failed,
      status: 'done',
      logJson: jsonEncode(log),
    );
    _log.info('Bulk nutrition job $jobId finished: $done done, $failed failed');
  } finally {
    _bulkRunning = false;
    // The spend split for the pause that reads it (a stopped job too).
    if (provider is UsdaFdcProvider) {
      final spent = {
        for (final MapEntry(:key, :value) in provider.requestCounts.entries)
          key: value - (tallyAtStart[key] ?? 0),
      };
      _log.info(
        'Bulk nutrition job $jobId ended; FDC requests by this job: '
        '${fdcTallyText(spent)} (process total: '
        '${provider.requestCountsText})',
      );
    }
  }
}
