// verify3 own F7 sweep. args: <snapshot> <workdir> <shard> <nshards> [<combo-filter file>]
// ignore_for_file: avoid_print, public_member_api_docs
// ignore_for_file: prefer_const_constructors, cascade_invocations
// ignore_for_file: avoid_multiple_declarations_per_line, strict_raw_type
// ignore_for_file: prefer_if_elements_to_conditional_expressions
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: cast_nullable_to_non_nullable, type_annotate_public_apis
// ignore_for_file: unused_element, unused_local_variable, prefer_int_literals
// ignore_for_file: lines_longer_than_80_chars, unawaited_futures
import 'dart:convert';
import 'dart:io';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';

var calls = 0;

class NoNet implements NutritionProvider {
  @override
  Future<List<FdcCandidate>> search(String q) async {
    calls++;
    throw NutritionProviderException('nn', scope: FailureScope.food);
  }

  @override
  Future<FdcFood?> food(int id) async {
    calls++;
    throw NutritionProviderException('nn', scope: FailureScope.food);
  }
}

bool m52(IngredientMatchRow r) =>
    r.childRecipeId == null &&
    (r.gramSource == 'discarded' ||
        const {
          'coating',
          'discarded_medium',
          'partial_pour_away',
        }.contains(r.hold));

String state(SaltDatabase db, String id) {
  final rows = db.ingredientMatchesFor(id)
    ..sort((a, b) => a.position.compareTo(b.position));
  final t = db.nutritionFor(id)?.totalsJson;
  final e = t == null
      ? null
      : ((jsonDecode(t) as Map)['energy'] as num?)?.toStringAsFixed(2);
  return [
    for (final r in rows)
      '${r.position}:${r.fdcId}:${r.grams?.toStringAsFixed(2)}:${r.gramSource}:${r.hold}:${r.status}',
    'E=$e',
  ].join(' ');
}

Future<void> main(List<String> a) async {
  final snap = a[0], work = a[1], shard = int.parse(a[2]), n = int.parse(a[3]);
  final only = a.length > 4 ? File(a[4]).readAsLinesSync().toSet() : null;
  final out = File('$work/sw_$shard.tsv').openWrite();
  final probe = SaltDatabase.openReadOnly(snap);
  final plan = <(String, int, int)>[];
  final ids = probe.allRecipeIds()..sort();
  for (final id in ids) {
    final rows = probe.ingredientMatchesFor(id)
      ..sort((x, y) => x.position.compareTo(y.position));
    final ms = rows.where((r) => r.status == 'auto' && m52(r)).take(2).toList();
    if (ms.isEmpty) continue;
    final foods =
        rows
            .where(
              (r) =>
                  r.status == 'auto' &&
                  !m52(r) &&
                  r.hold == null &&
                  r.grams != null &&
                  r.fdcId != null &&
                  r.childRecipeId == null,
            )
            .toList()
          ..sort((x, y) => y.grams!.compareTo(x.grams!));
    if (foods.isEmpty) continue;
    for (final m in ms) plan.add((id, m.position, foods.first.position));
  }
  probe.dispose();
  const verbs = ['skip', 'unskip', 'pickSame', 'pickOther', 'typed', 'confirm'];
  var k = -1, done = 0, div = 0, refused = 0;
  for (final (id, mp, fp) in plan) {
    for (final verb in verbs) {
      for (final order in ['A', 'B']) {
        k++;
        if (k % n != shard) continue;
        final tag = '$id|$mp|$fp|$verb|$order';
        if (only != null && !only.contains(tag)) continue;
        final path = '$work/db_$shard.db';
        for (final f in [path, '$path-wal', '$path-shm', '$path-journal']) {
          if (File(f).existsSync()) File(f).deleteSync();
        }
        Process.runSync('cp', ['-c', snap, path]);
        final db = SaltDatabase.open(path);
        final p = NoNet();
        calls = 0;
        String? err;
        try {
          Recipe rec() => nutritionRecipeOf(db, id)!.recipe;
          Future<void> put(int pos, Map<String, Object?> b) async {
            final raw = nutritionLines(rec())[pos].raw;
            await applyMatchOverride(db, p, rec(), pos, {'raw': raw, ...b});
          }

          Future<void> food() async {
            final row = db
                .ingredientMatchesFor(id)
                .firstWhere((r) => r.position == fp);
            switch (verb) {
              case 'skip':
                await put(fp, {'skipped': true});
              case 'unskip':
                await put(fp, {'skipped': true});
                await put(fp, {'skipped': false});
              case 'pickSame':
                await put(fp, {'fdc_id': row.fdcId});
              case 'pickOther':
                final body = await matchesBody(db, p, rec());
                final item = (body['items'] as List)[fp] as Map;
                final other =
                    [
                          for (final c in (item['candidates'] as List))
                            (c as Map)['fdc_id'] as int,
                        ]
                        .where(
                          (x) =>
                              x != row.fdcId && db.fdcFoodCacheGet(x) != null,
                        )
                        .firstOrNull;
                if (other == null) {
                  err = 'no-other';
                  return;
                }
                await put(fp, {'fdc_id': other});
              case 'typed':
                await put(fp, {'grams': 123.0});
              case 'confirm':
                await put(fp, {'confirmed': true});
            }
          }

          final pre = await matchAndCompute(db, p, rec());
          if (pre != null || calls != 0) {
            err = 'pre-compute $pre';
          }
          if (err != null) {
          } else if (order == 'A') {
            await put(mp, {'confirmed': true});
            await food();
          } else {
            await food();
            await put(mp, {'confirmed': true});
          }
          if (err == null) {
            final sPut = state(db, id);
            final body = await matchesBody(db, p, rec());
            final get = [
              for (final (i, it) in (body['items'] as List).indexed)
                if ((it as Map)['match'] != null)
                  '$i:${((it['match'] as Map)['grams'] as num?)?.toStringAsFixed(2)}:${(it['match'] as Map)['hold']}',
            ].join(' ');
            recomputeTotals(db, rec());
            final sRec = state(db, id);
            final e = await matchAndCompute(db, p, rec());
            final sFull = state(db, id);
            final getRows = [
              for (final r in db.ingredientMatchesFor(
                id,
              )..sort((x, y) => x.position.compareTo(y.position)))
                '${r.position}:${r.grams?.toStringAsFixed(2)}:${r.hold}',
            ].join(' ');
            final ok =
                sPut == sRec &&
                sRec == sFull &&
                get == getRows &&
                calls == 0 &&
                e == null;
            if (!ok) div++;
            out.writeln(
              '$tag\t${ok ? 'OK' : 'DIV'}\tcalls=$calls\te=$e\n  PUT  $sPut\n  REC  $sRec\n  FULL $sFull\n  GET  $get\n  GETR $getRows',
            );
          } else {
            refused++;
            out.writeln('$tag\tSKIP\t$err');
          }
        } catch (x) {
          refused++;
          out.writeln('$tag\tERR\t$x');
        }
        db.dispose();
        for (final f in [path, '$path-wal', '$path-shm', '$path-journal']) {
          if (File(f).existsSync()) File(f).deleteSync();
        }
        done++;
      }
    }
  }
  out.writeln('# shard $shard: combos $done divergent $div refused $refused');
  await out.close();
}
