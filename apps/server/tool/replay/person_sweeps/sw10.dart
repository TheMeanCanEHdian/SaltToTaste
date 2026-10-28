// fix83 sw10 (v83 F3, ledger Q14): the Confirm round-trip census. On a fresh copy of snapshot 29, every row
// whose UNGATED move inverse names another record (decisionRecordOf read as a `weight` row: the base tree's
// census, 156 rows) gets its own Confirm through the real PUT on an APFS clone; then the row is removed
// (STATED: stands in for a text edit, which re-lays the row as carried) and the recipe computed, so the
// decision lands back on its own line. Checked: the landed row == the row before (record, grams, source),
// stored == a second full matchAndCompute, calls 0 (NoNet). The selection reads `gramSource:` where the
// tree has it (tip) and calls without it otherwise (base) — the same 156 rows on both.
// closer 1 (verify1 D1): each row twice — the bare Confirm, then a Confirm with the row's own grams TYPED
// (`override`, on a fresh clone): the typed one must decide the record the bare one decides, and round-trip.
// args: <snapshot.db> <workdir>
// ignore_for_file: avoid_print, public_member_api_docs, avoid_dynamic_calls
// ignore_for_file: lines_longer_than_80_chars, cascade_invocations
// ignore_for_file: type_annotate_public_apis, avoid_catching_errors
// ignore_for_file: avoid_multiple_declarations_per_line
import 'dart:convert';
import 'dart:io';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

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

/// The ungated inverse: as a `weight` row on the tip, the base call as it is.
int? ungated(Recipe r, dynamic line, IngredientMatchRow m, SaltDatabase db) {
  final named = {#db: db, #description: m.description};
  try {
    return Function.apply(
          decisionRecordOf,
          [r, line, m.fdcId],
          {
            ...named,
            #gramSource: 'weight',
          },
        )
        as int?;
  } on NoSuchMethodError {
    return Function.apply(decisionRecordOf, [r, line, m.fdcId], named) as int?;
  }
}

Future<void> main(List<String> a) async {
  final work = a[1];
  Directory(work).createSync(recursive: true);
  final src = '$work/snap.db';
  for (final f in [src, '$src-wal', '$src-shm']) {
    if (File(f).existsSync()) File(f).deleteSync();
  }
  File(a[0]).copySync(src);
  final s = SaltDatabase.open(src);
  final census = <(String, int)>[];
  for (final id in s.allRecipeIds()..sort()) {
    final rec = nutritionRecipeOf(s, id)?.recipe;
    if (rec == null) continue;
    final lines = nutritionLines(rec);
    for (final m in s.ingredientMatchesFor(
      id,
    )..sort((x, y) => x.position.compareTo(y.position))) {
      if (m.position >= lines.length || m.fdcId == null) continue;
      if (ungated(rec, weighedLine(rec, lines[m.position]), m, s) != m.fdcId) {
        census.add((id, m.position));
      }
    }
  }
  s.dispose();
  final out = File('$work/sw10.tsv').openWrite();
  var ok = 0, bad = 0, typedOk = 0, typedBad = 0;
  final bare = <String, int?>{}, seen = <String>{};
  for (final (id, pos) in [
    for (final c in census) ...[c, c],
  ]) {
    final typed = !seen.add('$id|$pos');
    final path = '$work/db.db';
    for (final f in [path, '$path-wal', '$path-shm', '$path-journal']) {
      if (File(f).existsSync()) File(f).deleteSync();
    }
    Process.runSync('cp', ['-c', src, path]);
    var db = SaltDatabase.open(path);
    final p = NoNet();
    calls = 0;
    String verdict;
    var good = false;
    try {
      final rec = nutritionRecipeOf(db, id)!.recipe;
      final before = db
          .ingredientMatchesFor(id)
          .firstWhere((r) => r.position == pos);
      await applyMatchOverride(db, p, rec, pos, {
        'raw': nutritionLines(rec)[pos].raw,
        'confirmed': true,
        if (typed) 'grams': before.grams,
      });
      final decided = db.decisionFor(before.itemKey ?? '')?.fdcId;
      if (!typed) bare['$id|$pos'] = decided;
      db.dispose();
      raw.sqlite3.open(path)
        ..execute(
          'DELETE FROM ingredient_matches WHERE recipe_id = ? AND position = ?',
          [id, pos],
        )
        ..dispose();
      db = SaltDatabase.open(path);
      await matchAndCompute(db, p, nutritionRecipeOf(db, id)!.recipe);
      final landed = db
          .ingredientMatchesFor(id)
          .firstWhere((r) => r.position == pos);
      final stored = state(db, id);
      await matchAndCompute(db, p, nutritionRecipeOf(db, id)!.recipe);
      final again = state(db, id);
      final fails = [
        if (typed && decided != bare['$id|$pos'])
          'typed decided $decided (bare ${bare['$id|$pos']})',
        if (landed.fdcId != before.fdcId ||
            g(landed.grams) != g(before.grams) ||
            landed.gramSource != before.gramSource)
          'landed ${landed.fdcId} ${g(landed.grams)} ${landed.gramSource} (row ${before.fdcId} ${g(before.grams)} ${before.gramSource})',
        if (stored != again) 'compute',
        if (calls != 0) 'calls $calls',
      ];
      verdict =
          '${fails.isEmpty ? 'OK' : 'DIV'}\t$id|$pos\t${typed ? 'typed ' : ''}${before.gramSource}\tdecided $decided\t${fails.join('; ')}\tkcal/serving ${g(db.nutritionFor(id)?.caloriesPerServing)}';
      good = fails.isEmpty;
    } on ValidationException catch (e) {
      verdict = 'REF\t$id|$pos\t${typed ? 'typed ' : ''}${e.message}';
    } catch (e) {
      verdict = 'ERR\t$id|$pos\t${typed ? 'typed ' : ''}$e';
    }
    if (typed && good) {
      typedOk++;
    } else if (typed) {
      typedBad++;
    } else if (good) {
      ok++;
    } else {
      bad++;
    }
    db.dispose();
    out.writeln(verdict);
  }
  final summary =
      'SUMMARY census=${census.length} roundtrip=$ok divergent=$bad typed roundtrip=$typedOk typed divergent=$typedBad';
  out.writeln(summary);
  await out.close();
  print(summary);
}
