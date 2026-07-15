import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';

final Logger _log = Logger('nutrition');

bool _bulkRunning = false;

/// Whether a bulk compute is currently in flight (only one at a time).
bool get bulkJobRunning => _bulkRunning;

/// Starts a background bulk compute over every recipe without stored
/// nutrition; returns the job id, or null when one is already running.
///
/// Runs on the server's event loop (no isolate): the work is I/O-bound and
/// self-throttled by the provider's token bucket, so interactive requests
/// interleave freely. Progress and per-recipe failures land in the
/// `nutrition_jobs` row — silent partial failure is prohibited.
int? startBulkJob(SaltDatabase db, NutritionProvider provider) {
  if (_bulkRunning) {
    return null;
  }
  final ids = db.recipeIdsWithoutNutrition();
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
