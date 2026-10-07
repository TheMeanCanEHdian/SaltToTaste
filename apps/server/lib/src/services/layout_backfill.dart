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
      recipe = nutritionRecipeOf(db, recipeId)?.recipe;
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

/// Migration 014's backfill (RULE A, v27), once — while its marker
/// ([SaltDatabase.derivedSeqBackfillSetting]) is set: a recipe whose stamp
/// is current ([nutritionStampCurrent], after [backfillLayouts] seeded its
/// layout) has its decided rows marked derived for that stamp
/// ([derivedKeyOf]) — the derivation that stamp was computed with — so it
/// stays fresh; a stale recipe's stay null (underived) and the next stale
/// sweep derives them. A recipe whose document does not decode is left
/// underived (stale, the safe side). Returns the recipes marked, or null
/// when nothing was owed.
int? backfillDerivedSeq(SaltDatabase db) {
  if (db.getSetting(SaltDatabase.derivedSeqBackfillSetting) == null) {
    return null;
  }
  final keys = <String, String>{};
  final memo = ResolverMemo(db);
  for (final candidate in db.recipesWithNutrition()) {
    final Recipe? recipe;
    try {
      // A section's stamp carries its host's doc (v44).
      recipe = nutritionRecipeFromDoc(candidate.id, candidate.doc);
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      _log.warning(
        'derived_seq backfill left ${candidate.id} underived: its stored '
        'document does not decode ($error).',
      );
      continue;
    }
    if (recipe != null && nutritionStampCurrent(db, recipe, null, memo)) {
      keys[candidate.id] = derivedKeyOf(
        db.layoutSeqOf(candidate.id),
        candidate.ingredientsHash,
      );
    }
  }
  db.finishDerivedSeqBackfill(keys);
  _log.info('derived_seq backfill: ${keys.length} fresh recipe(s) marked');
  return keys.length;
}
