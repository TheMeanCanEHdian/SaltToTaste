// closer4: verify4's sw4.dart extended — the plan-row PICK takes every food verb, and order C (food skip, plan-row op, food un-skip) on every spec. args: settle <snap> <out-db> | sweep <settled-db> <workdir> <shard> <nshards>
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
import 'package:salt_server/src/exceptions.dart';
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
String g(double? x) => x?.toStringAsFixed(2) ?? '-';
String state(SaltDatabase db, String id) {
  final rows = db.ingredientMatchesFor(id)
    ..sort((a, b) => a.position.compareTo(b.position));
  final t = db.nutritionFor(id)?.totalsJson;
  final e = t == null
      ? null
      : ((jsonDecode(t) as Map)['energy'] as num?)?.toDouble();
  return [
    for (final r in rows)
      '${r.position}:${r.fdcId}:${g(r.grams)}:${r.gramSource}:${r.hold}:${r.status}',
    'E=${g(e)}',
  ].join(' ');
}

List<String> planned(SaltDatabase db) {
  final out = <String>[];
  for (final id in db.allRecipeIds()..sort()) {
    if (db.ingredientMatchesFor(id).any((r) => r.status == 'auto' && m52(r)))
      out.add(id);
  }
  return out;
}

Future<void> main(List<String> a) async {
  if (a[0] == 'settle') {
    File(a[1]).copySync(a[2]);
    final db = SaltDatabase.open(a[2]);
    final ids = planned(db);
    for (final id in ids) {
      await matchAndCompute(db, NoNet(), nutritionRecipeOf(db, id)!.recipe);
    }
    // a second pass must write the same
    final before = {for (final id in ids) id: state(db, id)};
    for (final id in ids) {
      await matchAndCompute(db, NoNet(), nutritionRecipeOf(db, id)!.recipe);
    }
    final moved = ids.where((id) => state(db, id) != before[id]).toList();
    stdout.writeln(
      'settled ${ids.length} recipes; second pass moved ${moved.length} $moved; calls $calls',
    );
    db.dispose();
    return;
  }
  final src = a[1], work = a[2], shard = int.parse(a[3]), n = int.parse(a[4]);
  // closer4: each shard reads its own clone (six shards opening one file raced on its WAL pragma: 'database is locked').
  final probePath = '$work/probe_$shard.db';
  for (final f in [probePath, '$probePath-wal', '$probePath-shm']) {
    if (File(f).existsSync()) File(f).deleteSync();
  }
  Process.runSync('cp', ['-c', src, probePath]);
  final probe = SaltDatabase.open(probePath);
  final plan = <(String, String, int)>[]; // (id, m52 spec, food pos)
  for (final id in planned(probe)) {
    final rows = probe.ingredientMatchesFor(id)
      ..sort((x, y) => x.position.compareTo(y.position));
    final ms = rows.where((r) => r.status == 'auto' && m52(r)).toList();
    final foods =
        rows
            .where(
              (r) =>
                  r.status == 'auto' &&
                  !m52(r) &&
                  r.hold == null &&
                  (r.grams ?? 0) > 0 &&
                  r.fdcId != null &&
                  r.childRecipeId == null,
            )
            .toList()
          ..sort((x, y) => y.grams!.compareTo(x.grams!));
    for (final f in foods.take(2)) {
      for (final m in ms) {
        plan.add((id, 'c${m.position}', f.position));
        plan.add((id, 'p${m.position}', f.position));
      }
      plan.add((id, 'all', f.position));
    }
  }
  probe.dispose();
  for (final f in [probePath, '$probePath-wal', '$probePath-shm']) {
    if (File(f).existsSync()) File(f).deleteSync();
  }
  const verbs = ['skip', 'unskip', 'pickSame', 'typed', 'confirm'];
  final out = File('$work/sw_$shard.tsv').openWrite();
  var k = -1, done = 0, div = 0, refused = 0;
  for (final (id, spec, fp) in plan) {
    for (final verb in verbs) {
      for (final order in ['A', 'B', 'C']) {
        if (order == 'C' && verb != 'unskip') continue;
        k++;
        if (k % n != shard) continue;
        final tag = '$id|$spec|$fp|$verb|$order';
        final path = '$work/db_$shard.db';
        for (final f in [path, '$path-wal', '$path-shm', '$path-journal']) {
          if (File(f).existsSync()) File(f).deleteSync();
        }
        Process.runSync('cp', ['-c', src, path]);
        final db = SaltDatabase.open(path);
        final p = NoNet();
        calls = 0;
        String? err;
        try {
          Recipe rec() => nutritionRecipeOf(db, id)!.recipe;
          IngredientMatchRow row(int pos) =>
              db.ingredientMatchesFor(id).firstWhere((r) => r.position == pos);
          Future<void> put(int pos, Map<String, Object?> b) async {
            await applyMatchOverride(db, p, rec(), pos, {
              'raw': nutritionLines(rec())[pos].raw,
              ...b,
            });
          }

          Future<void> m52op() async {
            if (spec == 'all') {
              for (final r
                  in db
                      .ingredientMatchesFor(id)
                      .where((r) => r.status == 'auto' && m52(r))
                      .toList()) {
                await put(r.position, {'confirmed': true});
              }
            } else if (spec.startsWith('c')) {
              await put(int.parse(spec.substring(1)), {'confirmed': true});
            } else {
              final pos = int.parse(spec.substring(1));
              await put(pos, {'fdc_id': row(pos).fdcId});
            }
          }

          Future<void> foodop() async {
            switch (verb) {
              case 'skip':
                await put(fp, {'skipped': true});
              case 'unskip':
                await put(fp, {'skipped': true});
                await put(fp, {'skipped': false});
              case 'pickSame':
                await put(fp, {'fdc_id': row(fp).fdcId});
              case 'typed':
                await put(fp, {'grams': 77.0});
              case 'confirm':
                await put(fp, {'confirmed': true});
            }
          }

          if (order == 'A') {
            await m52op();
            await foodop();
          } else if (order == 'B') {
            await foodop();
            await m52op();
          } else {
            await put(fp, {'skipped': true});
            await m52op();
            await put(fp, {'skipped': false});
          }
          final s1 = state(db, id);
          final body = await matchesBody(db, p, rec());
          final getRows = <String>[];
          for (final it in (body['items'] as List).cast<Map>()) {
            final m = it['match'] as Map?;
            if (m == null) continue;
            getRows.add(
              '${it['position']}:${g((m['grams'] as num?)?.toDouble())}:${m['hold']}',
            );
          }
          final stored = [
            for (final r in db.ingredientMatchesFor(
              id,
            )..sort((x, y) => x.position.compareTo(y.position)))
              '${r.position}:${g(r.grams)}:${r.hold}',
          ];
          recomputeTotals(db, rec());
          final s2 = state(db, id);
          await matchAndCompute(db, p, rec());
          final s3 = state(db, id);
          final bad = <String>[
            if (s1 != s2) 'recompute',
            if (s1 != s3) 'compute',
            if (getRows.join(' ') != stored.join(' ')) 'get',
            if (calls != 0) 'calls',
          ];
          if (bad.isNotEmpty) {
            div++;
            out.writeln(
              'DIV\t$tag\t${bad.join(',')}\n  PUT  $s1\n  REC  $s2\n  CMP  $s3\n  GET  ${getRows.join(' ')}\n  STO  ${stored.join(' ')}',
            );
          } else {
            out.writeln('OK\t$tag');
          }
        } on ValidationException catch (e) {
          refused++;
          err = e.message;
          out.writeln('REF\t$tag\t$err');
        } catch (e) {
          div++;
          out.writeln('ERR\t$tag\t$e');
        }
        db.dispose();
        done++;
      }
    }
  }
  out.writeln('SUMMARY shard=$shard done=$done div=$div refused=$refused');
  await out.close();
  for (final f in [
    '$work/db_$shard.db',
    '$work/db_$shard.db-wal',
    '$work/db_$shard.db-shm',
    '$work/db_$shard.db-journal',
  ]) {
    if (File(f).existsSync()) File(f).deleteSync();
  }
}
