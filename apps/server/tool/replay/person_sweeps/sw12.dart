// sw12 (fix104, v104 U7 GATE-P): the decision's reach vs the compute's decided arm. For every item key
// holding a row `decisionReach` EXCLUDES as shellfish bought in the shell (`boughtInShell`) or a held
// medium (`_heldMediumNow`, read as: not reached, not a second food, not a shell line, and not reached
// with `asPicked` either — the F10 left-on-its-record rows are reached there), one combo per distinct
// food on the key's undecided auto rows (the first row of that food): PUT {fdc_id: its own food,
// apply_to_all: true} on it under NoNet, then every same-key row's STORED row (and its recipe's
// freshness, nutritionIsFresh) vs the row the NEXT compute writes. Row classes: 'defect' = moved by the compute but
// not by the apply (stored == before, compute differs: the U7 class); 'apply-ne-compute' = moved by
// the apply to something the compute moves again; 'both' = moved by both, stored == compute; 'none' =
// untouched by both. Each row line names its reach class (reached / shell / medium / second / left).
// args: settle <snap> <out-db> | sweep <settled-db> <workdir> <shard> <nshards>
// ignore_for_file: avoid_print, public_member_api_docs, lines_longer_than_80_chars
// ignore_for_file: cascade_invocations, curly_braces_in_flow_control_structures
// ignore_for_file: type_annotate_public_apis, avoid_multiple_declarations_per_line, strict_raw_type
import 'dart:io';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';

var calls = 0;

class NoNet implements NutritionProvider {
  @override
  Future<List<FdcCandidate>> search(String q) async {
    calls++;
    throw const NutritionProviderException('nn', scope: FailureScope.food);
  }

  @override
  Future<FdcFood?> food(int id) async {
    calls++;
    throw const NutritionProviderException('nn', scope: FailureScope.food);
  }
}

/// The row's text class: shell-bought, an M52 plan row, or plain.
String textClass(IngredientMatchRow r) => boughtInShell(r.raw)
    ? 'shell'
    : r.gramSource == 'discarded' && r.hold == null
    ? 'plan'
    : 'plain';

String g(double? x) => x?.toStringAsFixed(2) ?? '-';
String rowText(IngredientMatchRow? r) => r == null
    ? 'none'
    : '${r.fdcId}:${g(r.grams)}:${r.gramSource}:${r.hold}:${r.status}';

/// item key -> its rows across the library (recipe id, position order).
Map<String, List<IngredientMatchRow>> byKey(SaltDatabase db) {
  final out = <String, List<IngredientMatchRow>>{};
  for (final id in db.allRecipeIds()..sort()) {
    for (final r in db.ingredientMatchesFor(
      id,
    )..sort((a, b) => a.position.compareTo(b.position))) {
      final k = r.itemKey;
      if (k != null && k.isNotEmpty) out.putIfAbsent(k, () => []).add(r);
    }
  }
  return out;
}

/// The reach class of every same-key row against the decision on [x].
Map<(String, int), String> reachClasses(
  SaltDatabase db,
  String key,
  IngredientMatchRow x,
  int? food,
) {
  final ex = (recipeId: x.recipeId, position: x.position);
  final reached = {
    for (final r in decisionReach(db, key, excluding: ex, fdcId: food))
      (r.recipeId, r.position),
  };
  final picked = {
    for (final r in decisionReach(
      db,
      key,
      excluding: ex,
      fdcId: food,
      asPicked: true,
    ))
      (r.recipeId, r.position),
  };
  final out = <(String, int), String>{};
  for (final r in db.undecidedMatchesForItemKey(
    key,
    excluding: ex,
    fdcId: food,
    belowConfidence: confidenceGateFloor,
  )) {
    final at = (r.recipeId, r.position);
    out[at] = reached.contains(at)
        ? 'reached'
        : namesSecondFood(r.raw)
        ? 'second'
        : boughtInShell(r.raw)
        ? 'shell'
        : picked.contains(at)
        ? 'left'
        : 'medium';
  }
  return out;
}

/// (key, deciding row) combos: one per distinct food on the key's undecided
/// auto rows, for a key holding a shell-bought or an M52 plan row; the sweep decides each on its own
/// food and on another candidate whose detail a cache holds (the fleet's
/// pairs: paella-on-the-grill|14 → 171977, chicken-katsu|0 → 174924).
List<(String, String, int)> plan(SaltDatabase db) {
  final out = <(String, String, int)>[];
  final keys = byKey(db);
  for (final key in keys.keys.toList()..sort()) {
    if (db.decisionFor(key) != null) continue;
    final seen = <int>{};
    for (final x in keys[key]!) {
      if (x.status != 'auto' || x.fdcId == null || x.hold != null) continue;
      if (x.childRecipeId != null || !seen.add(x.fdcId!)) continue;
      // Tree-independent (the same plan at the base and the tip): a key
      // holding a shell-bought row or an M52 plan row (`discarded`, no
      // hold) — the two classes the base's reach excluded.
      if (keys[key]!.any(
        (r) =>
            r != x &&
            (boughtInShell(r.raw) ||
                (r.gramSource == 'discarded' && r.hold == null)),
      )) {
        out.add((key, x.recipeId, x.position));
      }
    }
  }
  return out;
}

Future<void> main(List<String> a) async {
  if (a[0] == 'settle') {
    File(a[1]).copySync(a[2]);
    final db = SaltDatabase.open(a[2]);
    final keys = byKey(db);
    final ids = <String>{
      for (final (key, _, _) in plan(db))
        for (final r in keys[key]!) r.recipeId,
    }.toList()..sort();
    for (var pass = 0; pass < 2; pass++) {
      for (final id in ids) {
        await matchAndCompute(db, NoNet(), nutritionRecipeOf(db, id)!.recipe);
      }
    }
    stdout.writeln(
      'settled ${ids.length} recipes; ${plan(db).length} combos; calls $calls',
    );
    db.dispose();
    return;
  }
  final src = a[1], work = a[2], shard = int.parse(a[3]), n = int.parse(a[4]);
  final probePath = '$work/probe_$shard.db';
  Process.runSync('cp', ['-c', src, probePath]);
  final probe = SaltDatabase.open(probePath);
  final combos = plan(probe);
  probe.dispose();
  File(probePath).deleteSync();
  final out = File('$work/sw_$shard.tsv').openWrite();
  var k = -1, done = 0, defect = 0, errs = 0;
  for (final (key, id, pos) in combos) {
    for (final variant in const ['own', 'other']) {
      k++;
      if (k % n != shard) continue;
      final path = '$work/db_$shard.db';
      for (final f in [path, '$path-wal', '$path-shm', '$path-journal']) {
        if (File(f).existsSync()) File(f).deleteSync();
      }
      Process.runSync('cp', ['-c', src, path]);
      final db = SaltDatabase.open(path);
      calls = 0;
      var tag = '$key|$id|$pos|$variant';
      try {
        final x = db
            .ingredientMatchesFor(id)
            .firstWhere((r) => r.position == pos);
        final recipe = nutritionRecipeOf(db, id)!.recipe;
        var food = x.fdcId;
        if (variant == 'other') {
          final body = await matchesBody(db, NoNet(), recipe);
          final it = (body['items']! as List).cast<Map>().firstWhere(
            (i) => i['position'] == pos,
          );
          food = null;
          for (final c in (it['candidates'] as List? ?? const []).cast<Map>()) {
            if (c['fdc_id'] != x.fdcId &&
                db.fdcFoodCacheGet(c['fdc_id'] as int) != null) {
              food = c['fdc_id'] as int;
              break;
            }
          }
          if (food == null) {
            out.writeln('NOOTHER\t$tag');
            db.dispose();
            continue;
          }
        }
        tag = '$tag|$food';
        final cls = reachClasses(db, key, x, food);
        final rows = byKey(db)[key]!;
        final before = {for (final r in rows) (r.recipeId, r.position): r};
        calls = 0;
        await applyMatchOverride(db, NoNet(), recipe, pos, {
          'raw': nutritionLines(recipe)[pos].raw,
          'fdc_id': food,
          'apply_to_all': true,
        });
        IngredientMatchRow? now(String rid, int p) => db
            .ingredientMatchesFor(rid)
            .where((r) => r.position == p)
            .firstOrNull;
        final stored = {for (final at in before.keys) at: now(at.$1, at.$2)};
        final stale = <String, String>{
          for (final at in before.keys)
            at.$1: nutritionIsFresh(db, nutritionRecipeOf(db, at.$1)!.recipe)
                ? 'fresh'
                : 'stale',
        };
        // Every OTHER row of a touched recipe too (the coat partner the
        // plan re-splits): stored after the PUT vs the next compute.
        final partners = {
          for (final rid in stale.keys)
            for (final r in db.ingredientMatchesFor(rid))
              if (r.itemKey != key) (rid, r.position): rowText(r),
        };
        for (final rid in stale.keys) {
          await matchAndCompute(
            db,
            NoNet(),
            nutritionRecipeOf(db, rid)!.recipe,
          );
        }
        out.writeln('COMBO\t$tag\tcalls=$calls');
        for (final MapEntry(key: at, value: s) in partners.entries) {
          final c = rowText(now(at.$1, at.$2));
          if (s != c) {
            defect++;
            out.writeln(
              'PARTNER\t$tag\t${at.$1}|${at.$2}\tpartner-ne-compute\n  STO  $s\n  CMP  $c',
            );
          }
        }
        for (final at in before.keys) {
          if (at == (id, pos)) continue;
          final b = rowText(before[at]), s = rowText(stored[at]);
          final c = rowText(now(at.$1, at.$2));
          final row = s == c
              ? (b == s ? 'none' : 'both')
              : (b == s ? 'defect' : 'apply-ne-compute');
          if (row == 'defect' || row == 'apply-ne-compute') defect++;
          out.writeln(
            'ROW\t$tag\t${at.$1}|${at.$2}\t${cls[at] ?? 'decided-or-gated'}/${textClass(before[at]!)}\t$row\tstale=${stale[at.$1]}\n  BEF  $b\n  STO  $s\n  CMP  $c',
          );
        }
      } catch (e) {
        errs++;
        out.writeln('ERR\t$tag\t$e');
      }
      db.dispose();
      done++;
    }
  }
  out.writeln('SUMMARY shard=$shard done=$done divergent=$defect errors=$errs');
  await out.close();
}
