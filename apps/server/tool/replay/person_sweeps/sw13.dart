// sw13 (fix106, v106 U9 GATE-P): the two person arms sw3–sw12 never ran.
// (a) THE RECIPE-PICK APPLY (`applyRecipeToOthers`, v105 U3; U8's imported class): for every routed item key
//     (a row with child_recipe_id, its first main-recipe row), PUT {raw, child[, section], apply_to_all: true}
//     ('pick') and the same with share 0.5 ('share') — the body keys the handler reads (nutrition_handlers.dart
//     `child` / `section` / `share`) — under NoNet; then for EVERY target recipe (each recipe holding a row of the
//     key, sections included): its STORED state vs `recomputeTotals` vs a fresh `matchAndCompute` vs the GET's
//     rows. Classes: 'recompute-ne-stored', 'compute-ne-stored', 'get-ne-stored'.
// (b) THE DECIDED MULTI-PART HOLD (v104 U6 / v105 U1): for each auto row with `parts`, per part: PUT {raw,
//     confirmed: true} (its own food), drop the part from both caches (sw9's form: the detail row deleted, the
//     part stripped from every search answer) so NoNet's FOOD fault forms a hold, compute ×3 ('held'); restore both
//     caches (the part served) and compute ('served'); compute again ('again'). Per pass: hold, held_on,
//     derived_seq set, fresh, E. Classes: 'held-on-ne-part' (a no-record hold not naming the dropped part — null when it is the row's own food), 'not-healed'
//     (served: hold or held_on left, underived, or freshness unlike the decided pass's), 'again-moved' (the third compute writes).
// (b′) v107 U4 — THE PAIR RULE'S DECIDED PARTIAL: for each auto row whose parts are rule B1's peel plus juice (a part
//     with role 'juice'), its juice: (b)'s sequence, but the juice ARRIVES through `cachedFood` (the real re-open
//     path, `unholdOn`) and the row is read before the next compute ('arrived'). Extra classes: 'held-not-no-record'
//     (the held pass holds no `food_unavailable` / `food_gone` — the base's partial `second_food`), 'not-reopened'
//     (arrived still derived and fresh). Tags 'P|…'; the (b) combos are unchanged.
// Base vs tip: the COMBO / ROW lines are diffed (run.sh on each tree). args: settle <snap> <out-db> |
// sweep <settled-db> <workdir> <shard> <nshards>
// ignore_for_file: avoid_print, public_member_api_docs, lines_longer_than_80_chars
// ignore_for_file: cascade_invocations, curly_braces_in_flow_control_structures
// ignore_for_file: type_annotate_public_apis, avoid_multiple_declarations_per_line, strict_raw_type
import 'dart:convert';
import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
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

String g(double? x) => x?.toStringAsFixed(2) ?? '-';

String rowText(IngredientMatchRow r) =>
    '${r.position}:${r.fdcId}:${g(r.grams)}:${r.gramSource}:${r.hold}:${r.status}:${r.childRecipeId}:${g(r.childShare)}';

/// Every row and the totals of recipe [id] (sw9's `state`, + the counts).
String state(SaltDatabase db, String id) {
  final rows = db.ingredientMatchesFor(id)
    ..sort((a, b) => a.position.compareTo(b.position));
  final n = db.nutritionFor(id);
  final t = n?.totalsJson;
  final e = t == null
      ? null
      : ((jsonDecode(t) as Map)['energy'] as num?)?.toDouble();
  return [
    for (final r in rows) rowText(r),
    'E=${g(e)} kcal=${g(n?.caloriesPerServing)} ${n?.matchedCount}/${n?.totalCount}',
  ].join(' ');
}

/// The GET's rows of recipe [id]: position, food, grams, the child's state.
Future<String> getRows(SaltDatabase db, String id) async {
  final body = await matchesBody(
    db,
    NoNet(),
    nutritionRecipeOf(db, id)!.recipe,
  );
  return [
    for (final i in (body['items']! as List).cast<Map>())
      if (i['match'] case final Map m)
        '${i['position']}:${m['fdc_id']}:${g((m['grams'] as num?)?.toDouble())}:${(m['child'] as Map?)?['state']}',
  ].join(' ');
}

/// The stored rows in the GET's shape (the comparison's other side).
String storedRows(SaltDatabase db, String id) {
  final rows = db.ingredientMatchesFor(id)
    ..sort((a, b) => a.position.compareTo(b.position));
  return [
    for (final r in rows) '${r.position}:${r.fdcId}:${g(r.grams)}',
  ].join(' ');
}

String getShape(String get) => [
  for (final t in get.split(' '))
    if (t.isNotEmpty) t.split(':').take(3).join(':'),
].join(' ');

/// Positions where the GET's (food, grams) differ from the stored row's.
List<String> getDiff(String get, String stored) {
  final s = {for (final t in stored.split(' ')) t.split(':').first: t};
  return [
    for (final t in getShape(get).split(' '))
      if (t.isNotEmpty && s[t.split(':').first] != t)
        '$t!=${s[t.split(':').first]}',
  ];
}

/// item key -> its rows across the library (recipe id, position order).
Map<String, List<IngredientMatchRow>> byKey(SaltDatabase db) {
  final out = <String, List<IngredientMatchRow>>{};
  for (final id in bulkScopeIds(db, BulkScope.all)) {
    for (final r in db.ingredientMatchesFor(
      id,
    )..sort((a, b) => a.position.compareTo(b.position))) {
      final k = r.itemKey;
      if (k != null && k.isNotEmpty) out.putIfAbsent(k, () => []).add(r);
    }
  }
  return out;
}

/// (a) one combo per routed key: its first routed row on a main recipe.
List<(String, String, int, String)> applyPlan(SaltDatabase db) {
  final out = <(String, String, int, String)>[];
  final keys = byKey(db);
  for (final key in keys.keys.toList()..sort()) {
    for (final x in keys[key]!) {
      if (x.childRecipeId == null || hostOf(x.recipeId) != x.recipeId) continue;
      out.add((key, x.recipeId, x.position, x.childRecipeId!));
      break;
    }
  }
  return out;
}

/// (b) one combo per (auto row with parts, part).
List<(String, int, int)> holdPlan(SaltDatabase db) => [
  for (final id in bulkScopeIds(db, BulkScope.all))
    for (final r in db.ingredientMatchesFor(
      id,
    )..sort((a, b) => a.position.compareTo(b.position)))
      if (r.status == 'auto' && r.parts != null)
        for (final p in partsOf(r.parts)) (id, r.position, p.fdcId),
];

/// (b′) one combo per (auto row with a 'juice' part, that part).
List<(String, int, int)> pairPlan(SaltDatabase db) => [
  for (final id in bulkScopeIds(db, BulkScope.all))
    for (final r in db.ingredientMatchesFor(
      id,
    )..sort((a, b) => a.position.compareTo(b.position)))
      if (r.status == 'auto' && r.parts != null)
        for (final p in (jsonDecode(r.parts!) as List).cast<Map>())
          if (p['role'] == 'juice') (id, r.position, p['fdc_id'] as int),
];

/// Serves the saved detail [json] — the part's arrival (b′).
class Serve implements NutritionProvider {
  Serve(this.json);
  final String json;
  @override
  Future<List<FdcCandidate>> search(String q) async =>
      throw const NutritionProviderException('serve', scope: FailureScope.food);

  @override
  Future<FdcFood?> food(int id) async =>
      FdcFood.fromJson(jsonDecode(json) as Map<String, dynamic>);
}

Set<String> settleIds(SaltDatabase db) {
  final keys = byKey(db);
  return {
    for (final (key, _, _, _) in applyPlan(db))
      for (final r in keys[key]!) r.recipeId,
    for (final (id, _, _) in holdPlan(db)) id,
  };
}

Future<void> main(List<String> a) async {
  if (a[0] == 'settle') {
    File(a[1]).copySync(a[2]);
    final db = SaltDatabase.open(a[2]);
    // The bulk order (children before parents).
    final wanted = settleIds(db);
    final ids = [
      for (final id in bulkScopeIds(db, BulkScope.all))
        if (wanted.contains(id)) id,
    ];
    var moved = <String>[];
    for (var pass = 0; pass < 2; pass++) {
      final before = {for (final id in ids) id: state(db, id)};
      for (final id in ids) {
        await matchAndCompute(db, NoNet(), nutritionRecipeOf(db, id)!.recipe);
      }
      moved = [
        for (final id in ids)
          if (state(db, id) != before[id]) id,
      ];
    }
    stdout.writeln(
      'settled ${ids.length} recipes; apply combos ${applyPlan(db).length * 2}; hold combos ${holdPlan(db).length}; pair combos ${pairPlan(db).length}; second pass moved ${moved.length} $moved; calls $calls',
    );
    db.dispose();
    return;
  }
  final src = a[1], work = a[2], shard = int.parse(a[3]), n = int.parse(a[4]);
  final probePath = '$work/probe_$shard.db';
  Process.runSync('cp', ['-c', src, probePath]);
  final probe = SaltDatabase.open(probePath);
  final applies = applyPlan(probe);
  final holds = [
    for (final (id, pos, part) in holdPlan(probe)) (id, pos, part, false),
    for (final (id, pos, part) in pairPlan(probe)) (id, pos, part, true),
  ];
  probe.dispose();
  File(probePath).deleteSync();
  final out = File('$work/sw_$shard.tsv').openWrite();
  var k = -1, done = 0, div = 0, errs = 0, refused = 0;
  SaltDatabase fresh() {
    final path = '$work/db_$shard.db';
    for (final f in [path, '$path-wal', '$path-shm', '$path-journal']) {
      if (File(f).existsSync()) File(f).deleteSync();
    }
    Process.runSync('cp', ['-c', src, path]);
    return SaltDatabase.open(path);
  }

  // (a) the recipe-pick apply.
  for (final (key, id, pos, child) in applies) {
    for (final variant in const ['pick', 'share']) {
      k++;
      if (k % n != shard) continue;
      final db = fresh();
      final tag = 'A|$key|$id|$pos|$variant|$child';
      try {
        final recipe = nutritionRecipeOf(db, id)!.recipe;
        final cut = child.indexOf('#');
        calls = 0;
        AppliedToOthers? applied;
        try {
          applied = await applyMatchOverride(db, NoNet(), recipe, pos, {
            'raw': nutritionLines(recipe)[pos].raw,
            'child': cut < 0 ? child : child.substring(0, cut),
            if (cut >= 0) 'section': child.substring(cut + 1),
            if (variant == 'share') 'share': 0.5,
            'apply_to_all': true,
          });
        } on Exception catch (e) {
          refused++;
          out.writeln('REFUSED\t$tag\t$e');
          db.dispose();
          continue;
        }
        final putCalls = calls;
        final targets = {
          id,
          for (final r in byKey(db)[key] ?? const <IngredientMatchRow>[])
            r.recipeId,
        }.toList()..sort();
        final bad = <String>[];
        for (final t in targets) {
          final s = state(db, t);
          final get = await getRows(db, t);
          final gd = getDiff(get, storedRows(db, t));
          if (gd.isNotEmpty) bad.add('get-ne-stored $t ${gd.join(',')}');
          recomputeTotals(db, nutritionRecipeOf(db, t)!.recipe);
          final r = state(db, t);
          if (r != s) bad.add('recompute-ne-stored $t\n  STO  $s\n  REC  $r');
        }
        for (final t in targets) {
          final s = state(db, t);
          await matchAndCompute(db, NoNet(), nutritionRecipeOf(db, t)!.recipe);
          final c = state(db, t);
          if (c != s) bad.add('compute-ne-stored $t\n  STO  $s\n  CMP  $c');
        }
        out.writeln(
          'COMBO\t$tag\ttargets=${targets.length}\tapplied=${applied?.recipes}/${applied?.lines}\tcalls=$putCalls/$calls',
        );
        for (final t in targets) {
          out.writeln('ROW\t$tag\t$t\t${state(db, t)}');
        }
        if (bad.isNotEmpty) {
          div++;
          out.writeln('DIV\t$tag\t${bad.join('\n  ')}');
        }
      } catch (e) {
        errs++;
        out.writeln('ERR\t$tag\t$e');
      }
      db.dispose();
      done++;
    }
  }

  // (b) the decided multi-part hold; (b′) the pair rule's.
  for (final (id, pos, part, pair) in holds) {
    k++;
    if (k % n != shard) continue;
    var db = fresh();
    final path = '$work/db_$shard.db';
    final tag = '${pair ? 'P' : 'B'}|$id|$pos|$part';
    try {
      final recipe = nutritionRecipeOf(db, id)!.recipe;
      calls = 0;
      await applyMatchOverride(db, NoNet(), recipe, pos, {
        'raw': nutritionLines(recipe)[pos].raw,
        'confirmed': true,
      });
      String pass(String name) {
        final r = db
            .ingredientMatchesFor(id)
            .firstWhere((m) => m.position == pos);
        return '$name:${r.status}:${r.hold}:${r.heldOn}:${r.derivedSeq != null}:'
            '${nutritionIsFresh(db, nutritionRecipeOf(db, id)!.recipe) ? 'fresh' : 'stale'}';
      }

      final decided = pass('decided');
      // `_heldOnOf` names a part other than the row's own food; null else.
      final own = db
          .ingredientMatchesFor(id)
          .firstWhere((m) => m.position == pos)
          .fdcId;
      // Drop the part from both caches (sw9's form), keeping what restores it.
      db.dispose();
      final c = raw.sqlite3.open(path);
      final detail = c.select('SELECT * FROM fdc_food_cache WHERE fdc_id = ?', [
        part,
      ]);
      final searches = [
        for (final row in c.select(
          'SELECT query, response FROM fdc_search_cache',
        ))
          if ((jsonDecode(row['response'] as String) as List).cast<Map>().any(
            (h) => h['fdc_id'] == part,
          ))
            (row['query'] as String, row['response'] as String),
      ];
      c.execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [part]);
      for (final (q, resp) in searches) {
        c.execute('UPDATE fdc_search_cache SET response = ? WHERE query = ?', [
          jsonEncode([
            for (final h in (jsonDecode(resp) as List).cast<Map>())
              if (h['fdc_id'] != part) h,
          ]),
          q,
        ]);
      }
      c.dispose();
      db = SaltDatabase.open(path);
      // Three computes: a hold forms on the repeated FOOD fault (the v104 U6 /
      // v105 U1 pins' own sequence).
      for (var p = 0; p < 3; p++) {
        await matchAndCompute(db, NoNet(), nutritionRecipeOf(db, id)!.recipe);
      }
      final held = pass('held');
      final heldE = state(db, id);
      // Serve the part again: both caches restored as they were.
      db.dispose();
      final c2 = raw.sqlite3.open(path);
      // (b′) restores the detail through cachedFood below instead.
      for (final row in pair ? const <Map<String, Object?>>[] : detail) {
        final cols = row.keys.toList();
        c2.execute(
          'INSERT INTO fdc_food_cache (${cols.join(', ')}) VALUES (${[for (final _ in cols) '?'].join(', ')})',
          [for (final col in cols) row[col]],
        );
      }
      for (final (q, resp) in searches) {
        c2.execute('UPDATE fdc_search_cache SET response = ? WHERE query = ?', [
          resp,
          q,
        ]);
      }
      c2.dispose();
      db = SaltDatabase.open(path);
      var arrived = '';
      if (pair) {
        // (b′): the detail arrives through the real path (unholdOn).
        await cachedFood(db, Serve(detail.first['response'] as String), part);
        arrived = pass('arrived');
      }
      await matchAndCompute(db, NoNet(), nutritionRecipeOf(db, id)!.recipe);
      final served = pass('served');
      final servedS = state(db, id);
      await matchAndCompute(db, NoNet(), nutritionRecipeOf(db, id)!.recipe);
      final again = state(db, id);
      final h = held.split(':'), d = decided.split(':');
      final bad = <String>[
        if ((h[2] == 'food_unavailable' || h[2] == 'food_gone') &&
            h[3] != (part == own ? 'null' : '$part'))
          'held-on-ne-part',
        if (!served.endsWith(':null:null:true:${d[5]}')) 'not-healed',
        if (again != servedS) 'again-moved',
        if (pair && h[2] != 'food_unavailable' && h[2] != 'food_gone')
          'held-not-no-record',
        if (pair && arrived.endsWith(':true:fresh')) 'not-reopened',
      ];
      out.writeln(
        'COMBO\t$tag\t$decided\t$held${pair ? '\t$arrived' : ''}\t$served\tcalls=$calls',
      );
      out.writeln('ROW\t$tag\theld\t$heldE');
      out.writeln('ROW\t$tag\tserved\t$servedS');
      if (bad.isNotEmpty) {
        div++;
        out.writeln('DIV\t$tag\t${bad.join(',')}');
      }
    } catch (e) {
      errs++;
      out.writeln('ERR\t$tag\t$e');
    }
    db.dispose();
    done++;
  }
  out.writeln(
    'SUMMARY shard=$shard done=$done divergent=$div refused=$refused errors=$errs',
  );
  await out.close();
}
