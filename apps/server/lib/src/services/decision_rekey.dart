import 'package:logging/logging.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/services/item_key_backfill.dart';
import 'package:salt_server/src/services/layout_backfill.dart';
import 'package:salt_shared/salt_shared.dart';

final Logger _log = Logger('backfill');

/// Settings key holding the [matcherVersion] the decision keys were derived
/// under.
const String decisionRekeySetting = 'decisions.matcher_version';

/// Re-derives every decision's key after a [matcherVersion] change — a
/// stored key cannot be re-normalized from itself ('gruy re cheese' has lost
/// its letter). The key is read from an EXAMPLE line, keyed through
/// [lineKeyOf] — which follows every key change, one in [lineItemOf]'s
/// reading of the line included ("toasted, skinned, and chopped hazelnuts"
/// is 'hazelnut' since v8, but its v7 item text re-keys to the old
/// 'toasted skinned and hazelnut': checkpoint 5 review). An example is a
/// match row still carrying the decision's old key (the person's own row
/// first) or, with none left (a DB that booted an intermediate version has
/// its rows on that version's keys already), a row on ANY food whose line
/// reads as the item text with its prep kept (the v7 reading). The old
/// key's rows are the reliable example — a line's prep-kept reading can
/// itself change between versions (v9 moves the fruit of "grated zest plus
/// ½ cup juice from 3 or 4 limes" to the front, so the v8 item text of Key
/// Lime Pie's decision reads nowhere) — which is why boot re-keys DECISIONS
/// BEFORE ROWS ([rekeyAfterMatcherChange]; review Run 042). A row whose
/// recipe line was edited since its compute is no example: its raw text
/// must still be the line's. A decision that follows
/// its line takes the line's item text too, so a later re-key with no line
/// left keys it where the line did. With no example the item text is
/// re-keyed ([decisionKeyFor]). Collisions are judged on the
/// FINAL keys of the whole pass (a row that is itself moving away frees its
/// key — review, 2026-09-07): when
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
  final recipes = <String, List<IngredientLine>?>{};
  IngredientLine? lineOf(IngredientMatchRow row) {
    final lines = recipes.putIfAbsent(row.recipeId, () {
      try {
        final found = db.recipeByIdOrSlug(row.recipeId);
        return found == null ? null : nutritionLines(found.recipe);
        // A document that will not decode is no example.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        return null;
      }
    });
    return lines != null &&
            row.position < lines.length &&
            lines[row.position].raw == row.raw
        ? lines[row.position]
        : null;
  }

  // Every row's line by its prep-kept reading, built once when a decision's
  // old key has no row.
  Map<String, List<(int?, IngredientLine)>>? byReading;
  // [decision]'s example lines, the person's own first.
  List<IngredientLine> examplesOf(IngredientDecisionRow decision) {
    final byKey = [
      for (final row in db.matchesForItemKey(
        decision.itemKey,
        fdcId: decision.fdcId,
      ))
        ?lineOf(row),
    ];
    if (byKey.isNotEmpty) {
      return byKey;
    }
    // Only the prep-kept reading is looked up: a line whose CURRENT reading
    // is the item text keys the item text's own key ([lineKeyOf] is
    // [decisionKeyFor] of that reading), so it could only keep a decision
    // where its item text keys it — which it keeps with no example. It would
    // decide only for an item text that is one line's current reading and
    // another's v7 reading; no corpus line is (2 lines read differently with
    // their prep kept, 0334/2 and 0908/13, and neither reading is any line's
    // current one).
    final reading = byReading ??= () {
      final map = <String, List<(int?, IngredientLine)>>{};
      for (final recipeId in db.recipesWithMatches()) {
        for (final row in db.ingredientMatchesFor(recipeId)) {
          if (lineOf(row) case final line?) {
            map
                .putIfAbsent(decisionItemOf(line, dropPrep: false), () => [])
                .add((row.fdcId, line));
          }
        }
      }
      return map;
    }();
    // In row order: no ordering by food is observable (a reading is one
    // line's in this library; review Run 042 proved a decided-food-first
    // order changes nothing), and none is promised.
    return [
      for (final (_, line)
          in reading[decision.item] ?? const <(int?, IngredientLine)>[])
        line,
    ];
  }

  final byFinalKey = <String, List<(IngredientDecisionRow, String item)>>{};
  for (final decision in all) {
    // The item text's key stands while a line still produces it; a key no
    // line produces follows the line (its own first), item text included.
    final byItem = decisionKeyFor(decision.item);
    final examples = examplesOf(decision);
    final keys = [for (final line in examples) lineKeyOf(line)];
    var (key, item) = (byItem, decision.item);
    if (examples.isNotEmpty && !keys.contains(byItem)) {
      (key, item) = (keys.first, decisionItemOf(examples.first));
      _log.info(
        'decision re-key: "${decision.item}" follows its line to "$key" '
        '(its item text keys "$byItem", which no line produces).',
      );
    }
    byFinalKey.putIfAbsent(key, () => []).add((decision, item));
  }
  var changed = 0;
  final movers = <(IngredientDecisionRow, String key, String item)>[];
  for (final MapEntry(key: key, value: rows) in byFinalKey.entries) {
    if (key.isEmpty) {
      for (final (row, _) in rows) {
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
    final (winner, item) = rows.last;
    for (final (loser, _) in rows.sublist(0, rows.length - 1)) {
      _log.warning(
        'decision re-key: "${loser.item}" and "${winner.item}" are both '
        '"$key" now; keeping the newer (${winner.description}).',
      );
      db.deleteDecision(loser.itemKey);
      changed += 1;
    }
    // A decision already under its line's key keeps its item text: no line
    // keeps its key while its v7 item text re-keys elsewhere (corpus scan:
    // 0 lines; the 2 whose v7 item re-keys moved key too).
    if (winner.itemKey != key) {
      movers.add((winner, key, item));
    }
  }
  for (final (row, _, _) in movers) {
    db.deleteDecision(row.itemKey);
  }
  for (final (row, key, item) in movers) {
    db.insertDecision(
      IngredientDecisionRow(
        itemKey: key,
        item: item,
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

/// Boot's re-key after a [matcherVersion] change, in the one order that
/// works: decisions first, while every match row still carries the OLD key
/// a decision was stored under (the reliable example, see [rekeyDecisions]),
/// then the rows ([backfillItemKeys]). Rows first strands a decision whose
/// line's prep-kept reading changed too. Each pass is a one-shot data fix
/// that must never keep the server from booting.
void rekeyAfterMatcherChange(SaltDatabase db) {
  try {
    rekeyDecisions(db);
    // ignore: avoid_catches_without_on_clauses
  } catch (error, stackTrace) {
    _log.severe('Decision re-key failed', error, stackTrace);
  }
  try {
    backfillItemKeys(db);
    // ignore: avoid_catches_without_on_clauses
  } catch (error, stackTrace) {
    _log.severe('Item-key backfill failed', error, stackTrace);
  }
  // Every boot, not only after a matcher change: a database upgraded from
  // before migration 012 is seeded once, then finds nothing.
  try {
    backfillLayouts(db);
    // ignore: avoid_catches_without_on_clauses
  } catch (error, stackTrace) {
    _log.severe('Layout backfill failed', error, stackTrace);
  }
}
