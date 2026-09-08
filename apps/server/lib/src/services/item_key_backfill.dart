import 'package:logging/logging.dart';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';

final Logger _log = Logger('backfill');

/// Settings key holding the [matcherVersion] every match row's item_key was
/// derived under. Any other value (an older version, or the completion
/// timestamp the first backfill wrote) means every row is re-keyed at boot.
const String itemKeyBackfillSetting = 'backfill.item_key';

/// Keys every match row with the matcher's decision key ([itemKeyFor]) —
/// first for rows written before migration 009, and again whenever
/// [matcherVersion] changes what the key is (a singular form, a folded
/// accent), so cross-recipe reuse keeps finding decisions.
///
/// The key comes from the recipe's PARSED line (`item`, falling back to the
/// raw text), so it is derived here rather than in SQL. A row whose position
/// no longer exists, or whose raw text differs from the line — a stale row an
/// edit left behind — is left as it is; the next compute replaces it.
///
/// Runs until every recipe's rows are keyed: a recipe whose stored document
/// does not decode is skipped with a warning and the marker is NOT set, so the
/// pass retries at every boot (as the FTS reindex does). Returns the number of
/// rows keyed (0 when already at this matcher version).
int backfillItemKeys(SaltDatabase db) {
  if (db.getSetting(itemKeyBackfillSetting) == '$matcherVersion') {
    return 0;
  }
  var keyed = 0;
  var failed = 0;
  for (final recipeId in db.recipesWithMatches()) {
    final ({Recipe recipe, String sourceSlug})? found;
    try {
      found = db.recipeByIdOrSlug(recipeId);
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      failed += 1;
      _log.warning(
        'item-key backfill skipped $recipeId: its stored document does not '
        'decode ($error). Its match decisions stay invisible to other '
        'recipes until it is deleted or re-imported; retried at every boot.',
      );
      continue;
    }
    if (found == null) {
      continue; // Deleted between the id scan and here (rows cascade away).
    }
    final lines = nutritionLines(found.recipe);
    for (final row in db.ingredientMatchesFor(recipeId)) {
      if (row.position >= lines.length) {
        continue;
      }
      final line = lines[row.position];
      if (line.raw != row.raw) {
        continue;
      }
      final key = itemKeyFor(line.item ?? line.raw);
      if (key.isEmpty || key == row.itemKey) {
        continue;
      }
      db.setMatchItemKey(recipeId, row.position, key);
      keyed += 1;
    }
  }
  if (failed == 0) {
    db.setSetting(itemKeyBackfillSetting, '$matcherVersion');
  }
  if (keyed > 0 || failed > 0) {
    final retry = failed > 0
        ? '; $failed recipe(s) skipped, will retry at next boot'
        : '';
    _log.info('item-key backfill: keyed $keyed match row(s)$retry');
  }
  return keyed;
}
