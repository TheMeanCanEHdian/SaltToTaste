import 'package:logging/logging.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/matcher.dart';

final Logger _log = Logger('backfill');

/// Settings key holding the [matcherVersion] the decision keys were derived
/// under.
const String decisionRekeySetting = 'decisions.matcher_version';

/// Re-derives every decision's key from its stored item text after a
/// [matcherVersion] change — a stored key cannot be re-normalized from
/// itself ('gruy re cheese' has lost its letter), which is why the item text
/// is kept. When two decisions collapse into one key, the newer decision
/// wins and the loser is logged and dropped; a key that becomes empty is
/// dropped too. Returns the number of decisions moved or dropped (0 when
/// already at this version).
int rekeyDecisions(SaltDatabase db) {
  if (db.getSetting(decisionRekeySetting) == '$matcherVersion') {
    return 0;
  }
  var changed = 0;
  // Oldest first, so on a collision the row already under the new key is
  // the older one and the newcomer (newer) replaces it.
  for (final decision in db.allDecisions()) {
    final key = itemKeyFor(decision.item);
    if (key == decision.itemKey) {
      continue;
    }
    if (key.isEmpty) {
      _log.warning(
        'decision re-key dropped "${decision.item}": nothing searchable '
        'remains under the current matcher.',
      );
      db.deleteDecision(decision.itemKey);
      changed += 1;
      continue;
    }
    final holder = db.decisionFor(key);
    if (holder != null) {
      final newer = decision.decidedAt.compareTo(holder.decidedAt) > 0;
      _log.warning(
        'decision re-key: "${decision.item}" and "${holder.item}" are now '
        'both "$key"; keeping the newer '
        '(${newer ? decision.description : holder.description}).',
      );
      if (!newer) {
        db.deleteDecision(decision.itemKey);
        changed += 1;
        continue;
      }
      db.deleteDecision(holder.itemKey);
    }
    db.renameDecision(decision.itemKey, key);
    changed += 1;
  }
  db.setSetting(decisionRekeySetting, '$matcherVersion');
  if (changed > 0) {
    _log.info('decision re-key: $changed decision(s) moved or dropped');
  }
  return changed;
}
