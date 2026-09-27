import 'package:logging/logging.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';

final Logger _log = Logger('backfill');

/// Settings key holding the [matcherVersion] the decision keys were derived
/// under.
const String decisionRekeySetting = 'decisions.matcher_version';

/// Re-derives every decision's key from its stored item text after a
/// [matcherVersion] change — a stored key cannot be re-normalized from
/// itself ('gruy re cheese' has lost its letter), which is why the item text
/// is kept. Collisions are judged on the FINAL keys of the whole pass (a
/// row that is itself moving away frees its key — review, 2026-09-07): when
/// two decisions end under one key the newer wins and the loser is logged
/// and dropped; a key that becomes empty is dropped too. Movers are deleted
/// and re-inserted with their stamps intact, so no rename can collide with a
/// row that has not moved yet. Returns the number of decisions moved or
/// dropped (0 when already at this version).
int rekeyDecisions(SaltDatabase db) {
  if (db.getSetting(decisionRekeySetting) == '$matcherVersion') {
    return 0;
  }
  final all = db.allDecisions();
  final byFinalKey = <String, List<IngredientDecisionRow>>{};
  for (final decision in all) {
    byFinalKey
        .putIfAbsent(decisionKeyFor(decision.item), () => [])
        .add(decision);
  }
  var changed = 0;
  final movers = <(IngredientDecisionRow, String)>[];
  for (final entry in byFinalKey.entries) {
    final key = entry.key;
    final rows = entry.value;
    if (key.isEmpty) {
      for (final row in rows) {
        _log.warning(
          'decision re-key dropped "${row.item}": nothing searchable '
          'remains under the current matcher.',
        );
        db.deleteDecision(row.itemKey);
        changed += 1;
      }
      continue;
    }
    // Newest wins; allDecisions() is oldest-first.
    final winner = rows.last;
    for (final loser in rows.sublist(0, rows.length - 1)) {
      _log.warning(
        'decision re-key: "${loser.item}" and "${winner.item}" are both '
        '"$key" now; keeping the newer (${winner.description}).',
      );
      db.deleteDecision(loser.itemKey);
      changed += 1;
    }
    if (winner.itemKey != key) {
      movers.add((winner, key));
    }
  }
  for (final (row, _) in movers) {
    db.deleteDecision(row.itemKey);
  }
  for (final (row, key) in movers) {
    db.insertDecision(
      IngredientDecisionRow(
        itemKey: key,
        item: row.item,
        fdcId: row.fdcId,
        description: row.description,
        dataType: row.dataType,
        decidedBy: row.decidedBy,
        decidedAt: row.decidedAt,
      ),
    );
    changed += 1;
  }
  db.setSetting(decisionRekeySetting, '$matcherVersion');
  if (changed > 0) {
    _log.info('decision re-key: $changed decision(s) moved or dropped');
  }
  return changed;
}
