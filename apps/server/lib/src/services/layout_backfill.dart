import 'package:logging/logging.dart';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_shared/salt_shared.dart';

final Logger _log = Logger('backfill');

/// Seeds a real layout ([SaltDatabase.seedLayout]) for every recipe
/// computed before migration 012 — stamped or holding match rows, with no
/// layout row (Run 054 H4). Its stamp named layout 0 ("never laid out"),
/// which a delete and re-create under the same id repeats, and which a
/// first layout of EDITED lines once kept (v23's no-bump branch, deleted).
/// After this every later layout bumps the seq, and a stamp always names a
/// layout drawn from the global counter.
///
/// The texts are the recipe's current lines when every row stands on its
/// line (all 1,198 of snapshot 13): what that recipe's next layout would
/// record, so an unedited recipe stays fresh and moves nothing. Otherwise
/// (a row on another text or past the last line) its old lines are not
/// known: an empty list, which the pairing reads as no texts at all
/// ([pairRowsToLines] falls back to the rows' own), and the next layout
/// records the lines and bumps.
///
/// Idempotent: a seeded recipe has a layout row. A recipe whose document
/// does not decode is skipped with a warning and retried at the next boot.
/// Returns the number seeded.
int backfillLayouts(SaltDatabase db) {
  var seeded = 0;
  for (final recipeId in db.recipesWithoutLayout()) {
    final Recipe? recipe;
    try {
      recipe = db.recipeByIdOrSlug(recipeId)?.recipe;
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      _log.warning(
        'layout backfill skipped $recipeId: its stored document does not '
        'decode ($error); retried at every boot.',
      );
      continue;
    }
    if (recipe == null) {
      continue; // Deleted between the scan and here.
    }
    final lines = [for (final line in nutritionLines(recipe)) line.raw];
    final onLines = db
        .ingredientMatchesFor(recipeId)
        .every(
          (row) =>
              row.position < lines.length && row.raw == lines[row.position],
        );
    if (db.seedLayout(recipeId, onLines ? lines : const [])) {
      seeded += 1;
    }
  }
  if (seeded > 0) {
    _log.info('layout backfill: seeded $seeded recipe layout(s)');
  }
  return seeded;
}
