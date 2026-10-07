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
    // The job's outage watch, across its passes ([jobProvider]).
    final watched = jobProvider(provider);
    // v44 (P1 §3.4): the sections this recipe's lines make children, each
    // not fresh, computed first (0–5 passes) — a section has no compute of
    // its own — so the recipe's rows read their new totals and stamps.
    for (final key in sectionChildKeysOf(db, recipe, ResolverMemo(db))) {
      final section = nutritionRecipeOf(db, key)?.recipe;
      if (section == null ||
          _recipeJobs.containsKey(key) ||
          nutritionIsFresh(db, section)) {
        continue;
      }
      _recipeJobs[key] = jobId;
      try {
        await computeUntilFresh(
          db,
          watched,
          section,
          onFoodFailure: (error) => notes.add('${jobLogName(db, key)}: $error'),
        );
      } finally {
        _recipeJobs.remove(key);
      }
    }
    await computeUntilFresh(
      db,
      watched,
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
    final stored = nutritionRecipeOf(db, recipe.id)?.recipe;
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
/// shortcut). Synchronous on the serving isolate, on admin-only endpoints
/// (the sweep itself and the `bulk/counts` preview, which is why the
/// preview is guarded against a cross-site drive).
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
List<String> bulkScopeIds(SaltDatabase db, BulkScope scope) =>
    bulkScope(db, scope).ids;

/// [bulkScopeIds] with the library-wide CHILD SET it was ordered by (v44,
/// design_v2 §2 v44.3; P1 §3.3): every section key a main line of ANY
/// recipe makes a child ([routedSectionKeysOf], one [ResolverMemo] for
/// the whole library) and v47 (F1) every section a person's row picks
/// ([pickedSectionKeysOf]; the two halves of [sectionChildKeysOf]) —
/// never the scope's selection (F5: a `stale` sweep of a few recipes would
/// otherwise collect every other live section). The set needs the whole
/// library decoded in EVERY scope (N3: `missing` decoded only its wanted
/// docs, `stale` only the stamped ones): one pass over
/// [SaltDatabase.recipeDocs], every scope reading its recipes from it
/// ([bulkScopes]: the three scopes from ONE such read).
///
/// The order is [child section keys, non-parents, parents]: a section is a
/// recipe the sweep computes before any parent (a child section is never a
/// parent — depth 1), so a parent routed to its own or another recipe's
/// section reads that section's new totals in the same job whatever the
/// ids' order. `all` takes every child; `missing` the children with no
/// stamp; `stale` the stale ones AND those with no stamp (a section has no
/// compute of its own: without them the first v44 stale sweep would route
/// every parent to a section never computed). A stamped section key
/// outside the set is not selected — [startBulkJob] collects it.
({List<String> ids, Set<String> children}) bulkScope(
  SaltDatabase db,
  BulkScope scope,
) {
  final library = _libraryOf(db);
  return (ids: _selectionOf(db, library, scope), children: library.children);
}

/// Every scope's [bulkScopeIds] from ONE library read and ONE child set
/// (v47, F10 — Run 061 S9 / Run 062 O6: the `bulk/counts` preview read the
/// library and resolved the child set once per scope, three times).
Map<BulkScope, List<String>> bulkScopes(SaltDatabase db) {
  final library = _libraryOf(db);
  return {
    for (final scope in BulkScope.values)
      scope: _selectionOf(db, library, scope),
  };
}

/// The `GET /nutrition/bulk/counts` body: each scope's RECIPES and, apart,
/// its `sections` (v47, F12) — from ONE library read ([bulkScopes], F10).
Map<String, Object> bulkCountsBody(SaltDatabase db) {
  final scopes = bulkScopes(db);
  return {
    for (final MapEntry(key: scope, value: ids) in scopes.entries)
      scope.wireName: recipeCountOf(ids),
    'sections': {
      for (final MapEntry(key: scope, value: ids) in scopes.entries)
        scope.wireName: ids.length - recipeCountOf(ids),
    },
  };
}

/// How many of a scope's [ids] are RECIPES (v47, F12): a job's `total`
/// and `done` and the `bulk/counts` figures count recipes; the sections
/// a scope selects are computed first and counted apart.
int recipeCountOf(Iterable<String> ids) =>
    ids.where((id) => hostOf(id) == id).length;

/// How a job's log names [id] (v47, F12; Run 062 critic): a recipe by its
/// id, as ever; a section key — storage only, never on the wire — as
/// "{host slug} · {title}" (its host's id when the host is gone).
String jobLogName(SaltDatabase db, String id) {
  final host = hostOf(id);
  if (host == id) {
    return id;
  }
  final slug = nutritionRecipeOf(db, host)?.recipe.slug ?? host;
  return '$slug · ${id.substring(host.length + 1)}';
}

typedef _Library = ({
  Map<String, Recipe> docs,
  Set<String> children,
  Set<String> parents,
  ResolverMemo memo,
});

_Library _libraryOf(SaltDatabase db) {
  final docs = <String, Recipe>{
    for (final (:id, :doc) in db.recipeDocs())
      id: RecipeMapper.fromMap(jsonDecode(doc) as Map<String, dynamic>),
  };
  final memo = ResolverMemo(db);
  final children = <String>{
    for (final recipe in docs.values)
      if (readsSubRecipe(recipe)) ...routedSectionKeysOf(db, recipe, memo),
    ...pickedSectionKeysOf(db),
  };
  return (
    docs: docs,
    children: children,
    parents: {
      for (final MapEntry(:key, :value) in docs.entries)
        if (readsSubRecipe(value)) key,
    },
    memo: memo,
  );
}

List<String> _selectionOf(
  SaltDatabase db,
  _Library library,
  BulkScope scope,
) {
  final (:docs, :children, parents: libraryParents, :memo) = library;
  final ids = <String>[];
  final keys = <String>[];
  final parents = {...libraryParents};
  switch (scope) {
    case BulkScope.missing:
    case BulkScope.all:
      final wanted = scope == BulkScope.missing
          ? db.recipeIdsWithoutNutrition().toSet()
          : null;
      final stamped = scope == BulkScope.missing
          ? db.sectionKeysWithNutrition().toSet()
          : const <String>{};
      keys.addAll(children.where((key) => !stamped.contains(key)));
      ids.addAll(docs.keys.where((id) => wanted?.contains(id) ?? true));
    case BulkScope.stale:
      final stamped = <String>{};
      for (final candidate in db.recipesWithNutrition()) {
        final key = candidate.id != hostOf(candidate.id);
        if (key) {
          stamped.add(candidate.id);
          if (!children.contains(candidate.id)) {
            continue;
          }
        }
        final recipe = key
            ? sectionOf(docs[hostOf(candidate.id)]!, candidate.id)!
            : docs[candidate.id]!;
        if (!candidate.layoutCurrent ||
            candidate.underived ||
            ingredientsHashOf(recipe, memo) != candidate.ingredientsHash) {
          (key ? keys : ids).add(candidate.id);
        }
      }
      keys.addAll(children.where((key) => !stamped.contains(key)));
      final selected = {...ids, ...keys};
      for (final parent in db.recipesReadingChildren(selected)) {
        if (!selected.add(parent)) {
          continue;
        }
        if (parent != hostOf(parent)) {
          // A section's own (nested) reference row: a child, or collected.
          if (children.contains(parent)) keys.add(parent);
        } else {
          ids.add(parent);
          // It reads a child by its stored row: a parent whatever its doc.
          parents.add(parent);
        }
      }
  }
  ids.sort();
  keys.sort();
  return [
    ...keys,
    ...ids.where((id) => !parents.contains(id)),
    ...ids.where(parents.contains),
  ];
}

/// Whether [recipe]'s main lines (the ones nutrition reads) hold a
/// sub-recipe reference ([isReferenceIn]: a marked one, or v44's A9 line
/// naming its own section) — a parent, ordered after every other recipe by
/// [bulkScopeIds].
bool readsSubRecipe(Recipe recipe) => recipe.ingredients.any(
  (group) => group.items.any((line) => isReferenceIn(recipe, line)),
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
  final (:ids, :children) = bulkScope(db, scope);
  // v44 (F5, R21): stamps and engine rows of the section keys no main line
  // makes a child any more — never a decided row; here, not in the scope
  // (the counts preview reads the scope and must write nothing).
  db.collectSectionGarbage(children);
  final jobId = db.createNutritionJob(recipeCountOf(ids));
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
  // v47 (F12): `total` and `done` count RECIPES; a section key (computed
  // first, its parents' input) moves neither, and the log names it by its
  // host and title ([jobLogName]) — a key never reaches the wire.
  final total = recipeCountOf(ids);
  try {
    for (final id in ids) {
      // Yield the event loop between recipes: fully cached computes are
      // synchronous end-to-end, and a long cached stretch would otherwise
      // starve interactive requests.
      await Future<void>.delayed(Duration.zero);
      final step = hostOf(id) == id ? 1 : 0;
      late final name = jobLogName(db, id);
      final found = nutritionRecipeOf(db, id);
      if (found == null) {
        done += step;
        continue; // Deleted mid-job.
      }
      // Single-flight with the per-recipe compute: if one is already running
      // for this id, the bulk job would spend the FDC budget twice on the
      // same lines and both would write. Skip it — the running job finishes
      // it. Registering here is also what lets the recipe page and the review
      // queue see `computing_job_id` for a recipe the bulk sweep is on.
      if (_recipeJobs.containsKey(id)) {
        log.add('$name: skipped, a compute is already running');
        done += step;
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
          onFoodFailure: (error) => log.add('$name: $error'),
        );
      } on NutritionProviderException catch (error) {
        // GLOBAL — no key / bad key / the budget / an outage, a detail
        // outage escalated by the job's watch included: every remaining
        // recipe would fail identically — stop and say why. (A FOOD failure
        // never leaves a pass since v29: an engine line's is its row's
        // state like a decided row's, Run 059 Sonnet critic 1 / O3.)
        log.add('stopped at $name: $error');
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
        log.add('$name: $error');
      } finally {
        // Balanced on EVERY exit, including the provider-failure `return`
        // above: a registration left behind makes the per-recipe compute
        // hand back a dead job id forever and every later sweep skip the
        // recipe as "already running".
        _recipeJobs.remove(id);
      }
      if (step == 0) {
        continue;
      }
      done += 1;
      if (done % 10 == 0 || done == total) {
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
