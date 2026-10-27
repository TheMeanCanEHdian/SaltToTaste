// v43/v44 cache-only replay — rp41 EXTENDED for "sections as children"
// (matcher v44, a18da27). REBUILT 2026-10-15 from the archived TSVs (the
// original source was lost with the scratchpad); every column below was
// inferred from .claude/diag/2026-10-09/v69_*.tsv and the older v44/v45
// TSVs, and confirmed by byte-equality on snapshots 26 and 27 — EXCEPT the
// columns CONSTANT in v69_* (byte-equality cannot tell their readings
// apart): rows 22 (all 0), recs 7 and 14 (all 0), sections 4 (all
// 'variation'), 9 (all 1) and 11 (all ''). Those are pinned only by the
// v44/v45 archives (.claude/diag/2026-10-06/v44_*: col 22 = 1 on exactly the
// 17 engineUnavailableNote rows; sections fresh 0 = exactly the 13 with
// calls) and by rp41's conventions. Usage:
//   dart --packages=<repo>/.dart_tool/package_config.json rp43.dart <db-copy> \
//     <rows.tsv> <recs.tsv> <sections.tsv> [--calls=<calls.tsv>]
//     [--reverse-parents] [--no-rekey] [--id-order] [--dry-run=<calls.tsv>]
//     [--append-check] [--notes=<notes.tsv>]
// Computes with a provider that records every call and THROWS it
// FOOD-scoped (the Recorder: only the snapshot's caches answer; a miss lands
// a line with no row unmatched + engineUnavailableNote — a row already
// carrying a food is kept, engine v36 — and the pass goes on) in the
// ENGINE's order, bulkScopeIds(all) = [child section keys, non-parents,
// parents]; --reverse-parents computes the parents in reverse (the
// order-independence proof: byte-identical TSVs); --id-order computes ORDER
// BY id only, no section key (rp41's check that order matters: the sections'
// readers go stale). Two loops: compute every id, THEN
// dump every recipe ORDER BY id, each followed by its stamped sections in
// subsection order. Prints (stdout) a `SECTION STALE AFTER: <host
// slug>::<title>` line per stale section and a `KCAL CHECK: <slug or
// host::title> rows <Σ col 17 %.2f> stored <stored batch kcal %.2f>` line
// per recipe/section whose rows' gross sum differs from its stored totals by
// > 0.01 (alcohol, the braised share: deducted at the totals), then
//   calls=<raw calls> searches=<n> foods=<n> callsNotInDryRun=<n> (the last
//     three over the calls DISTINCT by (kind, query), as calls.tsv)
//   pending=<computes that threw> subsProblem=<rows not
//     a line of their recipe/section> orphans=<stamped section keys outside
//     the child set or whose host lost the title>
//   staleAfter=<recipes not fresh> sectionsStale=<sections not fresh>
//     kcalCheck=<KCAL CHECK lines>
//   sections=<sections dumped>
// rows TSV (22 cols): 1-19 rp41's (1 the HOST slug for a section's row; 14
// a section child's HOST slug); 20 "<subsection index>:<title>" on a
// section's row, '' on a main row; 21 the child section's title on a row
// routed to a section, else ''; 22 blocked: 1 when the row is the engine's
// "FoodData Central could not serve this food" (engineUnavailableNote — the
// v44 replay's 17 rows waiting on option A), else 0.
// recs TSV (14 cols): 1-11 rp41's (9 includes = routed RECIPE children
// only); 12 "<complete>/<stamped>" over the recipe's OWN stamped sections;
// 13 the section children its rows route to, "<host slug>::<title>" in row
// order, ','-joined; 14 blocked rows (col 22) over its own sections. Then
// the lines staleAfter=<n> and sectionsStale=<n>.
// sections TSV (11 cols): host slug, subsection index, title, kind, lines
// (nutritionLines), status, total grams %.2f, batch kcal %.2f (totals
// energy), fresh 1/0, the parents routed to it (slugs, sorted, ','),
// the provider calls its compute made (raw, "kind:query", ' | ').
// calls TSV: "kind\tquery\t<label>" DISTINCT by (kind, query), the first
// asking key kept, joined by '\n' (no trailing newline; 0 bytes when none).
// notes TSV (R0 of the simplification series, 2026-10-27; GATE-N): one
// line per row whose hold carries a note — host slug, position, col 20's
// section, hold, holdNoteOf(recipe, line, hold) — in rows order; the rows
// TSV never carries the note, so this dump is what pins it (17 rows on
// snapshot 29 at v82: ambiguous_medium 2, partial_pour_away 15; the six
// coating-held rows' notes are null — no dip sentence, no eaten part).
// --append-check (after the dumps), each swap then ONE stale sweep (the
// bulk job's loop: computeUntilFresh per bulkScopeIds(stale) id): (a)
// chraime's Tabil lines 0/1, (b) basic-double-crust-pie-dough's "Basic
// Single-Crust Pie Dough" lines 0/1, (c) rp41's graham-cracker-crust lines
// 1/2; prints `appendCheck(x)=<stale labels>` after the swap and
// `afterSweep(x)=<stale labels> calls=<n>` after the sweep (expect empty).
// ignore_for_file: avoid_print, public_member_api_docs
// ignore_for_file: prefer_const_constructors, cascade_invocations
// ignore_for_file: avoid_multiple_declarations_per_line, strict_raw_type
// ignore_for_file: prefer_if_elements_to_conditional_expressions
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: cast_nullable_to_non_nullable, type_annotate_public_apis
// ignore_for_file: unused_element, unused_local_variable, prefer_int_literals
// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';
import 'dart:io';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/decision_rekey.dart';
import 'package:salt_shared/salt_shared.dart';

class NoNetwork implements NutritionProvider {
  final List<({String kind, String query, String label})> calls = [];
  String label = '';
  @override
  Future<List<FdcCandidate>> search(String query) async {
    calls.add((kind: 'search', query: query, label: label));
    throw NutritionProviderException(
      'no network: search "$query"',
      scope: FailureScope.food,
    );
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    calls.add((kind: 'food', query: '$fdcId', label: label));
    throw NutritionProviderException(
      'no network: food $fdcId',
      scope: FailureScope.food,
    );
  }
}

String clean(Object? v) =>
    v == null ? '' : '$v'.replaceAll('\t', ' ').replaceAll('\n', ' ');

const recipeHolds = {'choose_recipe', 'nested_recipe'};

/// kcal of [grams] of [fdcId], as recomputeTotals reads the record.
double kcalOf(SaltDatabase db, int fdcId, double grams, IngredientLine? line) {
  final own = knownFood(db, fdcId, line: line);
  final sibling = nutrientSiblings[fdcId];
  final record = sibling == null || own == null ? own : knownFood(db, sibling);
  if (record == null) return 0;
  for (final number in nutrientDefs.first.fdcNumbers) {
    final per100 = record.nutrientsPer100g[number];
    if (per100 != null) return per100 * grams / 100;
  }
  return kcalPer100g(record) * grams / 100;
}

/// A parts array as stored: [{"fdc_id": int, "grams": num}, ...].
List<({int fdc, double grams})> partsOfRow(String? json) => json == null
    ? const []
    : [
        for (final p in jsonDecode(json) as List)
          (
            fdc: (p as Map)['fdc_id'] as int,
            grams: (p['grams'] as num).toDouble(),
          ),
      ];

/// The child's whole-batch kcal (its totals JSON, else per-serving x basis).
double? childKcal(SaltDatabase db, String childId) {
  final n = db.nutritionFor(childId);
  if (n == null) return null;
  final totals = n.totalsJson;
  if (totals != null) {
    return ((jsonDecode(totals) as Map)['energy'] as num?)?.toDouble() ?? 0;
  }
  return (n.caloriesPerServing ?? 0) * (n.servingBasis ?? 1);
}

/// The row's contribution to its recipe's kcal (recomputeTotals' arms).
double contribution(
  SaltDatabase db,
  IngredientMatchRow r,
  IngredientLine? line,
) {
  if (line == null || r.status == 'skipped') return 0;
  if (r.childRecipeId != null) {
    if (recipeHolds.contains(r.hold) || r.childShare == null) return 0;
    return (childKcal(db, r.childRecipeId!) ?? 0) * r.childShare!;
  }
  if (r.parts != null && r.gramSource != 'override') {
    return partsOfRow(
      r.parts,
    ).fold(0.0, (sum, p) => sum + kcalOf(db, p.fdc, p.grams, line));
  }
  final grams = r.grams;
  if (r.fdcId == null || grams == null || grams <= 0) return 0;
  if (r.status == 'auto' &&
      (belowConfidenceGate(r.confidence) || r.hold != null)) {
    return 0;
  }
  if (noRecordHolds.contains(r.hold)) return 0;
  return kcalOf(db, r.fdcId!, grams, line);
}

String kindOf(IngredientMatchRow r) => r.parts != null
    ? 'parts'
    : r.childRecipeId != null || r.gramSource == 'recipe'
    ? 'recipe'
    : isEngineRuleRow(r)
    ? 'rule'
    : 'food';

String? argOf(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('--$name=')) return a.substring(name.length + 3);
  }
  return null;
}

Future<void> main(List<String> args) async {
  final db = SaltDatabase.open(args[0]);
  if (!args.contains('--no-rekey')) {
    rekeyAfterMatcherChange(db);
  }
  final provider = NoNetwork();
  String slugOf(String id) =>
      nutritionRecipeOf(db, hostOf(id))?.recipe.slug ?? id;
  String titleOf(String key) => key.substring(hostOf(key).length + 1);
  String labelOf(String id) =>
      hostOf(id) == id ? slugOf(id) : '${slugOf(id)}::${titleOf(id)}';
  final (:ids, :children) = bulkScope(db, BulkScope.all);
  final idOrder = args.contains('--id-order');
  final keys = idOrder ? <String>[] : ids.where((id) => hostOf(id) != id);
  final mains = idOrder
      ? db.allRecipeIds()
      : ids.where((id) => hostOf(id) == id).toList();
  final parents = {
    for (final id in mains)
      if (readsSubRecipe(nutritionRecipeOf(db, id)!.recipe)) id,
  };
  final order = args.contains('--reverse-parents')
      ? [
          ...keys,
          ...mains.where((id) => !parents.contains(id)),
          ...mains.where(parents.contains).toList().reversed,
        ]
      : [...keys, ...mains];
  var pending = 0;
  final threw = <String>{};
  final callsOf = <String, List<String>>{};
  for (final id in order) {
    final recipe = nutritionRecipeOf(db, id)!.recipe;
    provider.label = labelOf(id);
    final before = provider.calls.length;
    try {
      // A returned (food) failure is the row's state, not `pending` (rp41:
      // computes that threw; the original printed pending=0 on 13 of them).
      final failure = await matchAndCompute(db, provider, recipe);
      if (failure != null) {
        stderr.writeln('COMPUTE FAILED: ${provider.label}: $failure');
      }
    } catch (e) {
      threw.add(id);
      pending++;
      stderr.writeln('COMPUTE THREW: ${provider.label}: $e');
    }
    callsOf[id] = [
      for (final c in provider.calls.skip(before)) '${c.kind}:${c.query}',
    ];
  }
  final rows = StringBuffer();
  final recs = StringBuffer();
  final notes = StringBuffer();
  var noteCount = 0;
  final out = StringBuffer();
  var subsProblem = 0;
  var staleAfter = 0;
  var sectionsStale = 0;
  var kcalCheck = 0;
  final flagMemo = ResolverMemo(db);
  final parentsOf = <String, Set<String>>{};
  final sectionLines = <({String key, List<Object> cols})>[];

  /// Dumps [recipe]'s rows (under [hostSlug], col 20 [section]); returns
  /// the Σ col 17, its routed recipe children, its routed sections and
  /// its blocked rows.
  ({double kcal, List<String> includes, List<String> sections, int blocked})
  dump(Recipe recipe, String hostSlug, String section) {
    final lines = nutritionLines(recipe);
    var kcal = 0.0;
    var blocked = 0;
    final includes = <String>[];
    final sections = <String>[];
    for (final r in db.ingredientMatchesFor(recipe.id)) {
      if (r.position >= lines.length || lines[r.position].raw != r.raw) {
        subsProblem++;
        stderr.writeln('ROW NOT A LINE: ${recipe.id} ${r.position} ${r.raw}');
      }
      final line = r.position < lines.length ? lines[r.position] : null;
      final note = line == null ? null : holdNoteOf(recipe, line, r.hold);
      if (note != null) {
        noteCount++;
        notes.writeln(
          [
            hostSlug,
            r.position,
            clean(section),
            clean(r.hold),
            clean(note),
          ].join('\t'),
        );
      }
      final basis = line == null
          ? ''
          : gramBasisFor(db, line, r, recipe: recipe);
      final child = r.childRecipeId;
      final childIsSection = child != null && hostOf(child) != child;
      final childOk = child == null
          ? ''
          : r.childStamp != null &&
                r.childStamp == db.nutritionFor(child)?.computedAt
          ? '1'
          : '0';
      if (child != null && !recipeHolds.contains(r.hold)) {
        if (childIsSection) {
          sections.add('${slugOf(child)}::${titleOf(child)}');
          (parentsOf[child] ??= {}).add(hostSlug);
        } else {
          includes.add(slugOf(child));
        }
      }
      final isBlocked = r.description == engineUnavailableNote;
      if (isBlocked) blocked++;
      final k = contribution(db, r, line);
      kcal += k;
      rows.writeln(
        [
          hostSlug, r.position, clean(r.raw), clean(r.fdcId),
          clean(r.description), r.confidence.toStringAsFixed(6),
          r.grams?.toStringAsFixed(2) ?? '', clean(r.gramSource), r.status,
          clean(r.hold), clean(r.itemKey), clean(basis),
          // v41 appended columns 13-19.
          kindOf(r), child == null ? '' : slugOf(child),
          r.childShare?.toStringAsFixed(6) ?? '', childOk, k.toStringAsFixed(2),
          partsOfRow(
            r.parts,
          ).map((p) => '${p.fdc}:${p.grams.toStringAsFixed(2)}').join('|'),
          line == null
              ? ''
              : clean(compositeFlagOf(db, recipe, line, r, flagMemo)),
          // v43 appended columns 20-22.
          clean(section), childIsSection ? clean(titleOf(child)) : '',
          isBlocked ? 1 : 0,
        ].join('\t'),
      );
    }
    return (
      kcal: kcal,
      includes: includes,
      sections: sections,
      blocked: blocked,
    );
  }

  void checkKcal(String label, String id, double kcal) {
    final stored = db.nutritionFor(id) == null ? null : childKcal(db, id);
    if (stored != null && (kcal - stored).abs() > 0.01) {
      kcalCheck++;
      out.writeln(
        'KCAL CHECK: $label rows ${kcal.toStringAsFixed(2)} '
        'stored ${stored.toStringAsFixed(2)}',
      );
    }
  }

  for (final id in db.allRecipeIds()) {
    final recipe = nutritionRecipeOf(db, id)!.recipe;
    final main = dump(recipe, recipe.slug, '');
    final n = db.nutritionFor(recipe.id);
    final fresh = nutritionIsFresh(db, recipe, n);
    if (!fresh) {
      staleAfter++;
      out.writeln('STALE AFTER: ${recipe.slug}');
    }
    checkKcal(recipe.slug, recipe.id, main.kcal);
    var own = 0;
    var ownComplete = 0;
    var ownBlocked = 0;
    for (final (i, sub) in recipe.subsections.indexed) {
      final title = sub.title;
      if (title == null) continue;
      final key = sectionKeyOf(recipe.id, title);
      final sn = db.nutritionFor(key);
      if (sn == null) continue;
      final section = nutritionRecipeOf(db, key)!.recipe;
      final label = '${recipe.slug}::$title';
      final s = dump(section, recipe.slug, '$i:$title');
      own++;
      if (sn.status == 'complete') ownComplete++;
      ownBlocked += s.blocked;
      final sFresh = nutritionIsFresh(db, section, sn);
      if (!sFresh) {
        sectionsStale++;
        out.writeln('SECTION STALE AFTER: $label');
      }
      checkKcal(label, key, s.kcal);
      sectionLines.add((
        key: key,
        cols: [
          recipe.slug,
          i,
          clean(title),
          clean(sub.kind),
          nutritionLines(section).length,
          sn.status,
          sn.totalGrams?.toStringAsFixed(2) ?? '',
          childKcal(db, key)!.toStringAsFixed(2),
          sFresh ? 1 : 0,
        ],
      ));
    }
    recs.writeln(
      [
        recipe.slug, n?.status ?? '',
        n?.caloriesPerServing?.toStringAsFixed(2) ?? '',
        n?.servingBasis ?? '', n?.matchedCount ?? '', n?.totalCount ?? '',
        threw.contains(id) ? 1 : 0,
        // v41 appended columns 8-11.
        fresh ? 1 : 0, main.includes.join(','),
        n?.totalGrams?.toStringAsFixed(2) ?? '',
        db.hasUnderivedRows(recipe.id) ? 1 : 0,
        // v43 appended columns 12-14.
        '$ownComplete/$own', main.sections.join(','), ownBlocked,
      ].join('\t'),
    );
  }
  recs
    ..writeln('staleAfter=$staleAfter')
    ..writeln('sectionsStale=$sectionsStale');
  final sections = StringBuffer();
  for (final (:key, :cols) in sectionLines) {
    sections.writeln(
      [
        ...cols,
        ((parentsOf[key] ?? const <String>{}).toList()..sort()).join(','),
        (callsOf[key] ?? const []).join(' | '),
      ].join('\t'),
    );
  }
  final stamped = db.sectionKeysWithNutrition();
  final orphans = stamped
      .where((k) => !children.contains(k) || nutritionRecipeOf(db, k) == null)
      .length;
  File(args[1]).writeAsStringSync(rows.toString());
  File(args[2]).writeAsStringSync(recs.toString());
  File(args[3]).writeAsStringSync(sections.toString());
  final notesPath = argOf(args, 'notes');
  if (notesPath != null) {
    File(notesPath).writeAsStringSync(notes.toString());
  }
  // Distinct by (kind, query), the first asking key kept (the original's
  // v44_calls.tsv: food:2710205 asked by two sections, listed once).
  final distinct = <String, String>{};
  for (final c in provider.calls) {
    distinct.putIfAbsent('${c.kind}\t${c.query}', () => c.label);
  }
  final callsPath = argOf(args, 'calls');
  if (callsPath != null) {
    File(callsPath).writeAsStringSync(
      distinct.entries.map((e) => '${e.key}\t${e.value}').join('\n'),
    );
  }
  final dryPath = argOf(args, 'dry-run');
  final dry = dryPath == null
      ? const <String>{}
      : {
          for (final l in File(dryPath).readAsLinesSync())
            if (l.isNotEmpty) l.split('\t').take(2).join('\t'),
        };
  stdout.write(out);
  final searches = distinct.keys.where((k) => k.startsWith('search\t')).length;
  print(
    'calls=${provider.calls.length} searches=$searches '
    'foods=${distinct.length - searches} callsNotInDryRun='
    '${distinct.keys.where((k) => !dry.contains(k)).length}',
  );
  print('pending=$pending subsProblem=$subsProblem orphans=$orphans');
  print(
    'staleAfter=$staleAfter sectionsStale=$sectionsStale kcalCheck=$kcalCheck',
  );
  print('sections=${sectionLines.length} notes=$noteCount');
  if (args.contains('--append-check')) {
    String stale() => bulkScopeIds(db, BulkScope.stale).map(labelOf).join(',');
    List<IngredientGroup> swap(List<IngredientGroup> groups, int a, int b) {
      final items = [...groups.first.items];
      final one = items[a];
      items[a] = items[b];
      items[b] = one;
      return [groups.first.copyWith(items: items), ...groups.skip(1)];
    }

    // (a) / (b) a section's lines, (c) rp41's crust: each swap, then ONE
    // stale sweep (the bulk job's loop) — the stale set must come back empty.
    for (final (tag, slug, title, a, b) in [
      ('a', 'chraime', 'Tabil', 0, 1),
      (
        'b',
        'basic-double-crust-pie-dough',
        'Basic Single-Crust Pie Dough',
        0,
        1,
      ),
      ('c', 'graham-cracker-crust', null, 1, 2),
    ]) {
      final found = db.recipeByIdOrSlug(slug)!;
      final recipe = found.recipe;
      db.upsertRecipe(
        title == null
            ? recipe.copyWith(ingredients: swap(recipe.ingredients, a, b))
            : recipe.copyWith(
                subsections: [
                  for (final sub in recipe.subsections)
                    sub.title == title
                        ? sub.copyWith(
                            ingredients: swap(sub.ingredients!, a, b),
                          )
                        : sub,
                ],
              ),
        sourceSlug: found.sourceSlug,
        contentHash: 'rp43-append-check-$tag',
      );
      print('appendCheck($tag)=${stale()}');
      final before = provider.calls.length;
      final (:ids, :children) = bulkScope(db, BulkScope.stale);
      db.collectSectionGarbage(children);
      for (final id in ids) {
        final found = nutritionRecipeOf(db, id);
        if (found == null) continue;
        provider.label = labelOf(id);
        try {
          await computeUntilFresh(db, provider, found.recipe);
        } catch (e) {
          stderr.writeln('SWEEP THREW: ${provider.label}: $e');
        }
      }
      print(
        'afterSweep($tag)=${stale()} calls=${provider.calls.length - before}',
      );
    }
  }
  db.dispose();
}
