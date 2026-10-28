// fix83 sw9 (v83 F2, ledger Q13): the cold-cache apply. Every key holding a Rule B1 row (a row with
// `parts`; on snapshot 29: bacon, thick-cut bacon, pancetta, pancetta or bacon, lemon / lime zest plus
// juice, orange peel plus juice, chickpea), applied from EACH of its lines: on an APFS clone of the settled
// copy, the key's part records that no row of the library counts as its food (a record a row counts is
// cached by that row's own compute — no library holds it uncached; on snapshot 29: 168322 for the four
// bacon keys, none for the other four) are evicted from both caches (the food cache row deleted, every
// cached answer rewritten without its hit) and served by the provider (its cached detail, else its hit;
// every other request throws, NoNet); then the line is picked on another cached record (its ranked
// candidates, its own answer, the key's own answer, every answer holding its record — the first with a
// cached detail) and then on its own record, each apply_to_all (the second apply rebuilds every target
// through `withParts`); the rewritten answers are put back. Checked on every recipe holding the key: stale_reason
// null, stored == a full matchAndCompute (0 requests), and the requests == the evicted parts the key's rows
// read, each once. A line with no other cached record is skipped (counted).
// closer 1 (verify1 D3): the library is bulkScopeIds(all) — the child sections with the recipes, in the bulk
// job's order (sections first) — so a section's B1 rows (0158's "Bread Stuffing with Bacon, …"|0) are applied
// from, settled and checked too (a section line's PUT is the `?section=` route's: the section recipe's own).
// args: settle <snap> <out-db> | sweep <settled-db> <workdir> <shard> <nshards>
// ignore_for_file: avoid_print, public_member_api_docs, avoid_dynamic_calls
// ignore_for_file: lines_longer_than_80_chars, cascade_invocations
// ignore_for_file: type_annotate_public_apis, avoid_multiple_declarations_per_line
// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:convert';
import 'dart:io';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
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

/// Serves the evicted records, counting each request; NoNet otherwise.
class Served extends NoNet {
  Served(this.foods);
  final Map<int, FdcFood> foods;
  final asked = <int>[];
  @override
  Future<FdcFood?> food(int id) async {
    if (foods[id] case final f?) {
      asked.add(id);
      return f;
    }
    return super.food(id);
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
      '${r.position}:${r.fdcId}:${g(r.grams)}:${r.gramSource}:${r.hold}:${r.status}:${r.parts}',
    'E=${g(e)}',
  ].join(' ');
}

Set<String> b1Keys(SaltDatabase db, List<String> all) => {
  for (final id in all)
    for (final r in db.ingredientMatchesFor(id))
      if (r.parts != null && r.itemKey != null) r.itemKey!,
};

List<String> holding(SaltDatabase db, List<String> all, String key) => [
  for (final id in all)
    if (db.ingredientMatchesFor(id).any((r) => r.itemKey == key)) id,
];

Set<int> partIds(Iterable<IngredientMatchRow> rows) => {
  for (final r in rows)
    for (final p in partsOf(r.parts)) p.fdcId,
};

Future<void> main(List<String> a) async {
  if (a[0] == 'settle') {
    File(a[1]).copySync(a[2]);
    final db = SaltDatabase.open(a[2]);
    final all = bulkScopeIds(db, BulkScope.all);
    final keys = b1Keys(db, all);
    final held = {for (final k in keys) ...holding(db, all, k)};
    final ids = [
      for (final id in all)
        if (held.contains(id)) id,
    ];
    for (var pass = 0; pass < 2; pass++) {
      final before = {for (final id in ids) id: state(db, id)};
      for (final id in ids) {
        await matchAndCompute(db, NoNet(), nutritionRecipeOf(db, id)!.recipe);
      }
      if (pass == 1) {
        final moved = ids.where((id) => state(db, id) != before[id]).toList();
        print(
          'settled ${ids.length} recipes of keys ${keys.toList()..sort()}; second pass moved ${moved.length} $moved; calls $calls',
        );
      }
    }
    db.dispose();
    return;
  }
  final src = a[1], work = a[2], shard = int.parse(a[3]), n = int.parse(a[4]);
  final probePath = '$work/probe_$shard.db';
  Process.runSync('cp', ['-c', src, probePath]);
  final probe = SaltDatabase.open(probePath);
  final all = bulkScopeIds(probe, BulkScope.all);
  final rowFoods = {
    for (final id in all)
      for (final r in probe.ingredientMatchesFor(id))
        if (r.fdcId != null) r.fdcId!,
  };
  // (key, recipe, position, own record, other record, evicted, recipes holding the key)
  final plan = <(String, String, int, int, int?, Set<int>, List<String>)>[];
  for (final key in b1Keys(probe, all).toList()..sort()) {
    final ids = holding(probe, all, key);
    final rows = [
      for (final id in ids)
        ...probe.ingredientMatchesFor(id).where((r) => r.itemKey == key),
    ];
    final evicted = partIds(rows).difference(rowFoods);
    for (final r
        in rows..sort(
          (x, y) => '${x.recipeId}|${x.position}'.compareTo(
            '${y.recipeId}|${y.position}',
          ),
        )) {
      if (r.status != 'auto' ||
          r.fdcId == null ||
          r.hold != null ||
          r.childRecipeId != null)
        continue;
      final rec = nutritionRecipeOf(probe, r.recipeId)!.recipe;
      final line = weighedLine(rec, nutritionLines(rec)[r.position]);
      // Another cached record a person can pick (a manual search): the line's ranked candidates, then
      // its own cached answer, then the answer cached under the key's own words, then every cached answer
      // holding its record, each in FDC's order (chili-con-carne|7 searches 'pork cured bacon unprepared',
      // 168277 alone; the 'bacon' answer holds 167869, pF's pick).
      List<int> hits(String? answer) => answer == null
          ? const []
          : [
              for (final h
                  in (jsonDecode(answer) as List).cast<Map<String, dynamic>>())
                h['fdc_id'] as int,
            ];
      final other =
          [
                for (final c in await candidatesForLine(
                  probe,
                  NoNet(),
                  line,
                  cacheOnly: true,
                  recipe: rec,
                ))
                  c.candidate.fdcId,
                ...hits(
                  probe.fdcSearchCacheGet(
                    lineSearchFor(
                      probe,
                      normalizeItem(lineItemOf(line)),
                      lineKeyOf(line),
                    ).answer,
                  ),
                ),
                ...hits(probe.fdcSearchCacheGet(key)),
                for (final answer in probe.fdcSearchCacheHolding(r.fdcId!))
                  ...hits(answer),
              ]
              .where(
                (id) =>
                    id != r.fdcId &&
                    !evicted.contains(id) &&
                    probe.fdcFoodCacheGet(id) != null,
              )
              .firstOrNull;
      plan.add((key, r.recipeId, r.position, r.fdcId!, other, evicted, ids));
    }
  }
  probe.dispose();
  for (final f in [probePath, '$probePath-wal', '$probePath-shm']) {
    if (File(f).existsSync()) File(f).deleteSync();
  }
  final out = File('$work/sw_$shard.tsv').openWrite();
  var done = 0, div = 0, refused = 0, skipped = 0;
  for (final (k, (key, id, pos, own, other, evicted, ids)) in plan.indexed) {
    if (k % n != shard) continue;
    final tag = '$key|$id|$pos';
    if (other == null) {
      skipped++;
      out.writeln('SKIP\t$tag\tno other cached record');
      continue;
    }
    final path = '$work/db_$shard.db';
    for (final f in [path, '$path-wal', '$path-shm', '$path-journal']) {
      if (File(f).existsSync()) File(f).deleteSync();
    }
    Process.runSync('cp', ['-c', src, path]);
    // Evict: both caches; the served copies kept.
    final served = <int, FdcFood>{};
    final answers = <String, String>{};
    final c = raw.sqlite3.open(path);
    for (final p in evicted) {
      final detail = c.select(
        'SELECT response FROM fdc_food_cache WHERE fdc_id = ?',
        [p],
      );
      for (final row in c.select(
        'SELECT c.query, c.response FROM fdc_search_cache_foods f JOIN fdc_search_cache c ON c.query = f.query WHERE f.fdc_id = ?',
        [p],
      )) {
        final q = row['query'] as String,
            resp = answers[q] ?? row['response'] as String;
        answers[q] = resp;
        final hits = (jsonDecode(resp) as List).cast<Map<String, dynamic>>();
        served[p] ??= detail.isNotEmpty
            ? FdcFood.fromJson(
                jsonDecode(detail.first['response'] as String)
                    as Map<String, dynamic>,
              )
            : FdcCandidate.fromJson(
                hits.firstWhere((h) => h['fdc_id'] == p),
              ).toFood();
      }
      if (detail.isNotEmpty && served[p] == null) {
        served[p] = FdcFood.fromJson(
          jsonDecode(detail.first['response'] as String)
              as Map<String, dynamic>,
        );
      }
      c.execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [p]);
    }
    for (final MapEntry(key: q, value: resp) in answers.entries) {
      final kept = [
        for (final h in (jsonDecode(resp) as List).cast<Map<String, dynamic>>())
          if (!evicted.contains(h['fdc_id'])) h,
      ];
      c.execute('UPDATE fdc_search_cache SET response = ? WHERE query = ?', [
        jsonEncode(kept),
        q,
      ]);
    }
    c.dispose();
    final db = SaltDatabase.open(path);
    final p = Served(served);
    calls = 0;
    try {
      final cold = [
        for (final e in evicted)
          if (knownFood(db, e) != null) e,
      ];
      for (final pick in [other, own]) {
        final rec = nutritionRecipeOf(db, id)!.recipe;
        await applyMatchOverride(db, p, rec, pos, {
          'raw': nutritionLines(rec)[pos].raw,
          'fdc_id': pick,
          'apply_to_all': true,
        });
      }
      final putCalls = calls;
      // The answers put back: the compute reads the snapshot's own.
      final back = raw.sqlite3.open(path);
      for (final MapEntry(key: q, value: resp) in answers.entries) {
        back.execute(
          'UPDATE fdc_search_cache SET response = ? WHERE query = ?',
          [resp, q],
        );
      }
      back.dispose();
      final read = partIds([
        for (final r in ids)
          ...db.ingredientMatchesFor(r).where((m) => m.itemKey == key),
      ]).intersection(evicted);
      final bad = <String>[
        if (cold.isNotEmpty) 'not evicted $cold',
        if (putCalls != 0) 'unserved requests $putCalls',
        if ((p.asked.toList()..sort()).join(',') !=
            (read.toList()..sort()).join(','))
          'requests ${p.asked} (parts read $read)',
      ];
      for (final r in ids) {
        final rec = nutritionRecipeOf(db, r)!.recipe;
        final reason = staleReasonOf(
          db,
          rec,
          db.nutritionFor(r)!,
          ResolverMemo(db),
        );
        final s1 = state(db, r);
        final before = calls;
        await matchAndCompute(db, p, rec);
        if (reason != null) bad.add('$r stale $reason');
        if (state(db, r) != s1) bad.add('$r stored != compute');
        if (calls != before) bad.add('$r compute requests ${calls - before}');
      }
      if (bad.isEmpty) {
        out.writeln(
          'OK\t$tag\tpicked $other then $own\tevicted $evicted\tasked ${p.asked}',
        );
      } else {
        div++;
        out.writeln('DIV\t$tag\tevicted $evicted\t${bad.join('; ')}');
      }
    } on ValidationException catch (e) {
      refused++;
      out.writeln('REF\t$tag\t${e.message}');
    } catch (e) {
      div++;
      out.writeln('ERR\t$tag\t$e');
    }
    db.dispose();
    done++;
  }
  out.writeln(
    'SUMMARY shard=$shard done=$done div=$div refused=$refused skipped=$skipped',
  );
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
