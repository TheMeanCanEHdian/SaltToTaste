import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
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
/// is running returns the same job rather than double-spending FDC budget.
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
    await matchAndCompute(db, provider, recipe);
    db.updateNutritionJob(jobId, done: 1, failed: 0, status: 'done');
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
/// Dart-side hash, so every recipe with nutrition is decoded and compared
/// (see [SaltDatabase.recipesWithNutrition] for why there is no timestamp
/// shortcut). Measured at ~110-190 ms for the whole 1,198-recipe library,
/// synchronously on the serving isolate, on admin-only endpoints (the sweep
/// itself and the `bulk/counts` preview, which is why the preview is
/// guarded against a cross-site drive).
List<String> bulkScopeIds(SaltDatabase db, BulkScope scope) {
  switch (scope) {
    case BulkScope.missing:
      return db.recipeIdsWithoutNutrition();
    case BulkScope.all:
      return db.allRecipeIds();
    case BulkScope.stale:
      final ids = <String>[];
      for (final candidate in db.recipesWithNutrition()) {
        final recipe = RecipeMapper.fromMap(
          jsonDecode(candidate.doc) as Map<String, dynamic>,
        );
        if (ingredientsHashOf(recipe) != candidate.ingredientsHash) {
          ids.add(candidate.id);
        }
      }
      return ids;
  }
}

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
  unawaited(_run(db, provider, jobId, ids));
  return jobId;
}

Future<void> _run(
  SaltDatabase db,
  NutritionProvider provider,
  int jobId,
  List<String> ids,
) async {
  var done = 0;
  var failed = 0;
  final log = <String>[];
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
        await matchAndCompute(db, provider, found.recipe);
      } on NutritionProviderException catch (error) {
        // No key / bad key / hard rate failure: every remaining recipe
        // would fail identically — stop and say why.
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
  }
}
