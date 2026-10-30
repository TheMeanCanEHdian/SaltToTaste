// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v81 — the fixes of dual-fleet review Run 065/066 (pair A, the
// catch-up review of v47–v54 at 86eca67): F1–F14 (union_A.md). Every row
// value is the fresh compute of the WHOLE recipe over recorded real FDC
// answers (FixtureProvider; this file adds no fixture) and equals the v81
// replay of snapshot 29 on every pinned field. Never the network. Every
// corpus line is real. STATED constructions (no corpus line reaches these
// paths): F1 none (the barolo pancetta is real); F2 / F3 / F4 / F10 / F13
// the editor-cap cost shapes (a real corpus line repeated, filler steps —
// the house's cap-shape exception); F3's fuzz (corpus sentences with the
// stop arms' own words spliced in); F6 0790 with its kept-cooked sentence
// printing its weight (closer 2: the note still folds — the gate reads the
// note alone), 0857's note edited (a note no reader reads) and 0393's flour
// blend note edited (closer 3: its 2 routed parents re-derive); F7 0254 with its cod line written zucchini, an
// onion line and an onion-buttering step appended (the fleet's probe); F9
// 0005 cut to 8 lines and with its line 0 dropped (an admin's save, never
// recomputed); F11 chraime's Tabil emptied through the real edit path,
// and (closer 3) cut to ONE of its real lines (no routed corpus section
// prints fewer than 2);
// F12 (closer 4, verify4 D1) 0031's Garlic Croutons line 1 rewritten to
// print each whole-part word alone;
// F14 hostile digit runs (the critic's lines) and (closer 5, verify5 D2)
// 0031's Garlic Croutons line 0 printing a 10-digit quantity; and (closer
// 4, the Opus critics F15–F17) F15 0978|0 written with no amount (no
// corpus WB line routes to a library recipe) and edited so after a pick,
// F16 a provider whose radish (or chicken) search throws, F17 0972
// retitled to a tie and given a new sibling section under a closer title;
// and (closer 5, verify5 D3) F17's PROSE cap shape (lemon-meringue-pie's
// real line 0 repeated to 400 lines), 0972's Basic Single-Crust line "4–6
// tablespoons ice water" written as a reference (a nested base) and
// lemon's line 0 written "½ recipe …" / "2 cups …" (every corpus PV line
// prints "1 recipe").
// And (closer 6, verify6 D1 / D2) F17's two hash pins: lemon with real
// 0983's line 0 appended (two prose sections of two hosts) beside real
// 0972 + 0976, and 0976 given a sibling "Whole-Wheat Dough for
// Double-Crust Pie" with its own lines; lemon's line 0 written "2 cups …"
// and 0972's Basic Single-Crust yield written "MAKES ABOUT 4 CUPS".
// And (closer 7, verify7 D1) the memo key's host-and-title pin: lemon's
// real line 0 copied with its title written "Hand Mixed Basic
// Double-Crust Pie Dough" (two prose sections of ONE host, 0972) and 0972
// given a sibling "Hand Mixed Double-Crust Pie Dough" with its own lines.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_server/src/services/library_scan.dart';
import 'package:salt_server/src/services/nutrition_composite.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_cost_test.dart' show fill;
import 'nutrition_v25_cost_test.dart' as v25 show readAll;
import 'nutrition_v26_cost_test.dart' show capStep, capSteps, capped, pork;
import 'nutrition_v26_cost_test.dart' as v26 show shapes;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

IngredientLine _ln(String raw) {
  final p = parseIngredientLine(raw);
  return IngredientLine(
    raw: raw,
    item: p.item,
    prep: p.prep,
    amounts: p.amounts,
  );
}

({SaltDatabase db, ServerConfig config}) _store() {
  final dir = Directory.systemTemp.createTempSync('salt-v81-');
  final config = ServerConfig(
    dataDir: dir.path,
    logLevel: Level.WARNING,
    trustProxy: false,
  );
  final db = SaltDatabase.open(config.dbPath)
    ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
  addTearDown(() {
    db.dispose();
    dir.deleteSync(recursive: true);
  });
  return (db: db, config: config);
}

SaltDatabase _db() => _store().db;

FixtureProvider _fdc() => FixtureProvider(pending: {...pendingSearches});

/// [r] stored and computed (its section children first).
Future<Recipe> _compute(SaltDatabase db, FixtureProvider fdc, Recipe r) async {
  db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
  final stored = db.recipeByIdOrSlug(r.id)!.recipe;
  for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
    expect(
      await matchAndCompute(db, fdc, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }
  expect(await matchAndCompute(db, fdc, stored), isNull);
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

IngredientMatchRow _row(SaltDatabase db, String id, int position) =>
    db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

double _energy(SaltDatabase db, String id) =>
    ((jsonDecode(db.nutritionFor(id)!.totalsJson!) as Map)['energy'] as num)
        .toDouble();

String _sig(IngredientMatchRow r) =>
    '${r.status}|${r.fdcId}|${r.grams}|${r.gramSource}|${r.hold}|${r.parts}|${r.childRecipeId}';

/// STATED synthesized (F16, closer 4): the recorded fixtures, but a search
/// whose query holds [word] throws [failure] — a failing compute no recorded
/// answer produces.
class _FailingSearch extends FixtureProvider {
  _FailingSearch(this.word, this.failure)
    : super(pending: {...pendingSearches});

  final String word;
  final Object failure;

  @override
  Future<List<FdcCandidate>> search(String query) =>
      query.contains(word) ? Future.error(failure) : super.search(query);
}

/// A bulk sweep of [scope], run to its end; the job's row.
Future<Map<String, Object?>> _sweep(
  SaltDatabase db,
  NutritionProvider fdc,
  BulkScope scope,
) async {
  final job = startBulkJob(db, fdc, scope: scope)!;
  while (bulkJobRunning) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return db.nutritionJob(job)!;
}

void main() {
  group('v81 (review Run 065/066 fixes)', skip: skipIfNoCorpus, () {
    writes();
    readers();
    numerics();
    critics();
  });
  group('v81 cost (RULE C at the caps)', skip: skipIfNoCorpus, costShapes);
}

/// F1 (un-skip derives as the compute), F5 (the offer is the write), F6
/// (the prep note hashed where read), F9 (the stored position never read),
/// F11 (a picked section emptied).
void writes() {
  test('F1: skip then un-skip through the real PUT returns every parts, '
      "alcohol, discarded and coating row to the COMPUTE's row and energy — "
      "beef-braised-in-barolo|2's v50 discarded pancetta stays 0 g (was "
      '63.22 g rendered by rule B1, +406.55 kcal)', () async {
    final db = _db();
    final fdc = _fdc();
    // The deli-ham line caches the one answer holding 168322, the cooked
    // bacon rule B1 renders on (nutrition_v41_test's order).
    await _compute(
      db,
      fdc,
      loadCorpusRecipe(
        '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
      ),
    );
    var swept = 0;
    for (final file in [
      '0426-beef-braised-in-barolo.yaml',
      '0040-wilted-spinach-salad-with-warm-bacon-dressing.yaml',
      '0142-skillet-roasted-chicken-in-lemon-sauce.yaml',
      '0235-maple-glazed-pork-tenderloin.yaml',
    ]) {
      final recipe = await _compute(db, fdc, loadCorpusRecipe(file));
      for (final r0 in db.ingredientMatchesFor(recipe.id)) {
        if (r0.status == 'skipped' ||
            r0.childRecipeId != null ||
            !(r0.parts != null ||
                (r0.fdcId != null && alcoholRecords.containsKey(r0.fdcId)) ||
                r0.gramSource == 'discarded' ||
                r0.hold == 'coating')) {
          continue;
        }
        final raw = nutritionLines(recipe)[r0.position].raw;
        final before = (_sig(r0), _energy(db, recipe.id).toStringAsFixed(4));
        for (final skipped in [true, false]) {
          await applyMatchOverride(
            db,
            fdc,
            db.recipeByIdOrSlug(recipe.id)!.recipe,
            r0.position,
            {'skipped': skipped, 'raw': raw},
          );
        }
        expect(
          (
            _sig(_row(db, recipe.id, r0.position)),
            _energy(db, recipe.id).toStringAsFixed(4),
          ),
          before,
          reason: '$file|${r0.position} "$raw"',
        );
        swept++;
      }
    }
    expect(swept, 17);
    final barolo = loadCorpusRecipe('0426-beef-braised-in-barolo.yaml').id;
    expect(
      _sig(_row(db, barolo, 2)),
      'auto|168277|0.0|discarded|null|null|null',
    );
  });

  test('F5: the matches GET offers what the PUT apply_to_all writes on the '
      "v49 twin move's canned beans (chana-masala|11 on 175206 decides "
      '2644288; best-ground-beef-chili|17 on 175201 decides 2644292)', () async {
    for (final (file, position, others) in [
      (
        '1096-chana-masala.yaml',
        11,
        [
          '0026-harira-moroccan-lentil-and-chickpea-soup.yaml',
          '1075-espinacas-con-garbanzos-andalusian-spinach-and-chickpeas.yaml',
          '0340-pasta-e-ceci-pasta-with-chickpeas.yaml',
          '0572-ultracreamy-hummus.yaml',
        ],
      ),
      (
        '0009-best-ground-beef-chili.yaml',
        17,
        [
          '0315-pinto-beanbeet-burgers.yaml',
          '1133-paniscia-red-wine-risotto-with-beans.yaml',
        ],
      ),
    ]) {
      final db = _db();
      final fdc = _fdc();
      for (final o in others) {
        await _compute(db, fdc, loadCorpusRecipe(o));
      }
      final recipe = await _compute(db, fdc, loadCorpusRecipe(file));
      final item =
          ((await matchesBody(db, fdc, recipe))['items']! as List)[position]
              as Map;
      final applied = await applyMatchOverride(db, fdc, recipe, position, {
        'raw': item['raw'],
        'confirmed': true,
        'apply_to_all': true,
      });
      expect(
        (item['others'], item['others_lines']),
        (applied?.recipes ?? 0, applied?.lines ?? 0),
        reason: '$file|$position',
      );
    }
  });

  test('F6: a prep-note edit stales a recipe whose note a reader reads — '
      "0790's potato cooked kind (the note's \"(½ pound)\") and 0279's shell "
      'reader ("eaten shell and all") — and the stale scope selects it; a '
      'note no reader reads stays fresh (STATED: 0857 edited; 0790 with its '
      'kept-cooked sentence printing the weight)', () async {
    final (:db, :config) = _store();
    final fdc = _fdc();
    Future<({bool fresh, String stale})> editNote(
      Recipe r,
      String from,
      String to,
    ) async {
      final note = r.prepNotes!;
      expect(note, contains(from), reason: r.slug);
      updateRecipe(db, config, r.id, {'prep_notes': note.replaceAll(from, to)});
      final now = nutritionRecipeOf(db, r.id)!.recipe;
      return (
        fresh: nutritionIsFresh(db, now),
        stale: bulkScopeIds(db, BulkScope.stale).join(','),
      );
    }

    final buns = await _compute(
      db,
      fdc,
      loadCorpusRecipe('0790-potato-burger-buns.yaml'),
    );
    expect(_row(db, buns.id, 0).grams!.toStringAsFixed(2), '256.10');
    expect(
      await editNote(buns, '(½ pound)', '(1 pound)'),
      (fresh: false, stale: buns.id),
    );
    await matchAndCompute(db, fdc, nutritionRecipeOf(db, buns.id)!.recipe);
    expect(_row(db, buns.id, 0).grams!.toStringAsFixed(2), '367.41');
    final shrimp = await _compute(
      db,
      fdc,
      loadCorpusRecipe('0279-crispy-salt-and-pepper-shrimp.yaml'),
    );
    expect(
      await editNote(shrimp, 'eaten shell and all', 'eaten whole'),
      (fresh: false, stale: shrimp.id),
    );
    await matchAndCompute(db, fdc, nutritionRecipeOf(db, shrimp.id)!.recipe);
    expect(
      (
        _row(db, shrimp.id, 0).grams!.toStringAsFixed(2),
        _row(db, shrimp.id, 7).grams!.toStringAsFixed(2),
      ),
      ('551.11', '57.21'),
    );
    final cake = await _compute(
      db,
      fdc,
      loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml'),
    );
    final cakeNote = cake.prepNotes!;
    expect(
      await editNote(cake, cakeNote, '$cakeNote Serve warm.'),
      (fresh: true, stale: ''),
    );
    // RE-PIN (closer 2, verify2 D1): the gate reads the NOTE alone, never a
    // step — a kept-cooked sentence printing its weight no longer leaves a
    // note printing "cup (" unread: its edit stales (a re-stamp on
    // identical rows, the superset; STATED synthesized step).
    final printed = await _compute(
      db,
      fdc,
      loadCorpusRecipe('0790-potato-burger-buns.yaml').copyWith(
        id: 'v81-buns-printed',
        slug: 'v81-buns-printed',
        steps: [
          for (final s in loadCorpusRecipe(
            '0790-potato-burger-buns.yaml',
          ).steps)
            s.copyWith(
              text: s.text.replaceAll(
                'Measure 1 very firmly packed cup potatoes',
                'Measure 1 very firmly packed cup (½ pound) potatoes',
              ),
            ),
        ],
      ),
    );
    expect(
      await editNote(printed, '(½ pound)', '(1 pound)'),
      (fresh: false, stale: printed.id),
    );
    await matchAndCompute(db, fdc, nutritionRecipeOf(db, printed.id)!.recipe);
    // closer 1 (verify1 D3): the note's own gate — the kind reads a note's
    // "cup (…)" only, so a note printing none is unread whatever the steps
    // say (STATED synthesized: 0790's note with "packed cup (½ pound)"
    // written "packed cup, ½ pound,"; its real kept-cooked sentence kept) —
    // its edit stays fresh.
    final real = loadCorpusRecipe('0790-potato-burger-buns.yaml');
    final unread = await _compute(
      db,
      fdc,
      real.copyWith(
        id: 'v81-buns-unread',
        slug: 'v81-buns-unread',
        prepNotes: real.prepNotes!.replaceAll(
          'packed cup (½ pound)',
          'packed cup, ½ pound,',
        ),
      ),
    );
    expect(unread.prepNotes, isNot(contains('cup (')));
    expect(
      await editNote(unread, 'cooking water', 'cooking liquid'),
      (fresh: true, stale: ''),
    );
  });

  test('F6 (closer 2, verify2 D1): the hash folds a note by its own text — '
      'on the corpus exactly the 6 recipes and 1 section whose note a reader '
      "can read (0279's shell; the 6 notes printing \"cup(s) (\" — 5 recipes', "
      "1 section's), beside "
      'the reference holders; every other note edit moves no hash', () {
    final (:db, config: _) = _store();
    final memo = ResolverMemo(db);
    final folded = <String>[];
    for (final f in Directory(corpusRecipesDir).listSync().whereType<File>()) {
      if (f.path.endsWith('.yaml')) {
        final host = loadCorpusRecipe(f.uri.pathSegments.last);
        for (final r in [
          host,
          for (final sub in host.subsections)
            if (sectionOf(host, sectionKeyOf(host.id, sub.title!))
                case final section?)
              section,
        ]) {
          if (r.prepNotes == null ||
              nutritionLines(r).any((l) => isReferenceIn(r, l))) {
            continue;
          }
          // Both copies: a section's copy reads its host off the DB alone
          // (the giblets' bird, [hostWeighedGiblets]) — the same on both.
          final same = r.copyWith(prepNotes: r.prepNotes);
          final edited = r.copyWith(prepNotes: '${r.prepNotes} Serve warm.');
          if (ingredientsHashOf(edited, memo) !=
              ingredientsHashOf(same, memo)) {
            folded.add(r.id);
          }
        }
      }
    }
    expect(folded..sort(), [
      'atk-tv-2023-0279-crispy-salt-and-pepper-shrimp',
      'atk-tv-2023-0365-potato-gnocchi-with-browned-butter-and-sage-sauce',
      'atk-tv-2023-0393-the-best-gluten-free-pizza#The America’s Test Kitchen All-Purpose Gluten-Free Flour Blend',
      'atk-tv-2023-0783-best-drop-biscuits',
      'atk-tv-2023-0790-potato-burger-buns',
      'atk-tv-2023-0958-skillet-apple-pie',
      'atk-tv-2023-1086-pasta-with-burst-cherry-tomato-sauce-and-fried-caper-crumbs',
    ]);
  });

  test("F6's section fold re-derives its routed parents (closer 3, verify3 "
      "D1 — the deploy's 9 keys: the 7 re-hashed + the section's 2 "
      "parents): the flour blend's note edited (a STATED edit; its real "
      'note prints "cup (") stales the section AND 0393 and 0819, which '
      'route to it; one zero-request stale sweep re-derives all 3 — the '
      "parents' hashes and every total unchanged", () async {
    final (:db, :config) = _store();
    final fdc = _fdc();
    const blend =
        'The America’s Test Kitchen All-Purpose Gluten-Free Flour Blend';
    final pizza = await _compute(
      db,
      fdc,
      loadCorpusRecipe('0393-the-best-gluten-free-pizza.yaml'),
    );
    final cookies = await _compute(
      db,
      fdc,
      loadCorpusRecipe('0819-gluten-free-chocolate-chip-cookies.yaml'),
    );
    final key = sectionKeyOf(pizza.id, blend);
    expect(_row(db, pizza.id, 0).childRecipeId, key);
    expect(_row(db, cookies.id, 0).childRecipeId, key);
    Future<void> staleSweep() async {
      startBulkJob(db, fdc, scope: BulkScope.stale);
      while (bulkJobRunning) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    // 0819's compute re-derived the shared section: 0393 reads it once.
    await staleSweep();
    expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
    final ids = [key, pizza.id, cookies.id];
    final before = {
      for (final id in ids)
        id: (db.nutritionFor(id)!.ingredientsHash, _energy(db, id)),
    };
    updateRecipe(db, config, pizza.id, {
      'subsections': [
        for (final sub in pizza.subsections)
          (sub.title == blend
                  ? sub.copyWith(prepNotes: '${sub.prepNotes} Serve warm.')
                  : sub)
              .toMap(),
      ],
    });
    // Both readers of freshness: the sweep's scope (the parents appended,
    // [SaltDatabase.recipesReadingChildren]) and the page's
    // ([staleSectionsReadBy]).
    expect(bulkScopeIds(db, BulkScope.stale).toSet(), ids.toSet());
    expect(
      [
        for (final id in ids)
          nutritionIsFresh(db, nutritionRecipeOf(db, id)!.recipe),
      ],
      [false, false, false],
    );
    await staleSweep();
    expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
    final after = {
      for (final id in ids)
        id: (db.nutritionFor(id)!.ingredientsHash, _energy(db, id)),
    };
    expect(after[key]!.$1, isNot(before[key]!.$1));
    expect(after[key]!.$2, before[key]!.$2);
    expect(after[pizza.id], before[pizza.id]);
    expect(after[cookies.id], before[cookies.id]);
  });

  test('F9: the matches GET reads the line it pairs, never the stored row '
      "position — 0005 cut to 8 lines (an admin's save, no compute) answers "
      "200 (lines[8] threw); with only line 0 dropped the wine's flag is the "
      "fresh compute's (STATED edits)", () async {
    final db = _db();
    final fdc = _fdc();
    final host = await _compute(
      db,
      fdc,
      loadCorpusRecipe('0005-best-beef-stew.yaml'),
    );
    final lines = nutritionLines(host);
    expect(lines[8].raw, '2 cups red wine');
    String? wineFlag(Map<String, Object?> body) => [
      for (final item in (body['items']! as List).cast<Map<String, Object?>>())
        if (item['raw'] == '2 cups red wine')
          (item['match'] as Map?)?['flag'] as String?,
    ].single;
    final fresh = wineFlag(await matchesBody(db, fdc, host));
    expect(fresh, contains('USDA retention'));
    for (final kept in [
      [for (var i = 1; i <= 8; i++) lines[i]],
      [for (var i = 1; i < lines.length; i++) lines[i]],
    ]) {
      final edited = host.copyWith(ingredients: [IngredientGroup(items: kept)]);
      db.upsertRecipe(edited, sourceSlug: _source, contentHash: 'v81-$kept');
      final now = db.recipeByIdOrSlug(host.id)!.recipe;
      final body = await matchesBody(db, fdc, now);
      final flag = wineFlag(body);
      // The edit's own compute writes the same flag.
      final db2 = _db();
      final computed = await _compute(
        db2,
        _fdc(),
        edited.copyWith(id: 'v81-${kept.length}', slug: 'v81-${kept.length}'),
      );
      expect(flag, isNotNull);
      expect(flag, wineFlag(await matchesBody(db2, _fdc(), computed)));
    }
  });

  test("F11: a person's pick of a section its host then empties (the real "
      "edit path) reads as the engine's no_ingredients rule row — the "
      "roast's label lists it partial (not_routed, no_ingredients), never "
      "included complete at 0 g — and its parent reads as the engine's own "
      'route of the SAME emptied section reads chraime (R1 parity; closer 1, '
      'verify1 D2): partial, the line neither matched nor accounted', () async {
    final (:db, :config) = _store();
    final fdc = _fdc();
    const chraimeFile = '1208-chraime.yaml';
    const roastFile = '0214-roast-beef-tenderloin.yaml';
    await _compute(db, fdc, loadCorpusRecipe(chraimeFile));
    await _compute(db, fdc, loadCorpusRecipe(roastFile));
    Recipe stored(String f) =>
        nutritionRecipeOf(db, loadCorpusRecipe(f).id)!.recipe;
    Future<void> sweep(BulkScope scope) async {
      startBulkJob(db, fdc, scope: scope);
      while (bulkJobRunning) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    await applyMatchOverride(db, fdc, stored(roastFile), 5, {
      'raw': nutritionLines(stored(roastFile))[5].raw,
      'child': stored(chraimeFile).slug,
      'section': 'Tabil',
    });
    Map<String, Object?> label() =>
        nutritionBody(db, stored(roastFile), forAdmin: true);
    expect(
      (label()['includes']! as List).single,
      containsPair('section', 'Tabil'),
    );
    final chraime = stored(chraimeFile);
    updateRecipe(db, config, chraime.id, {
      'subsections': [
        for (final sub in chraime.subsections)
          (sub.title == 'Tabil'
                  ? sub.copyWith(ingredients: <IngredientGroup>[])
                  : sub)
              .toMap(),
      ],
    });
    await sweep(BulkScope.stale);
    await sweep(BulkScope.all);
    final body = label();
    expect(body['includes'], isEmpty);
    expect(body['partial'], [
      {
        'position': 5,
        'kind': 'not_routed',
        'name': 'flavored butter',
        'title': 'Tabil',
        'matched': null,
        'total': null,
        'reason': 'no_ingredients',
      },
    ]);
    // The pick stays the person's: the section is still a child.
    expect(
      _row(db, stored(roastFile).id, 5).childRecipeId,
      sectionKeyOf(chraime.id, 'Tabil'),
    );
    // R1 parity (closer 1, verify1 D2): the engine's own route of the same
    // emptied section — chraime|7's real reference — is the rule row (0 g,
    // the sub-recipe note), its label the same not_routed entry; the parent
    // of either reads partial, the line neither matched nor accounted.
    final c = stored(chraimeFile);
    expect(nutritionLines(c)[7].raw, '1 tablespoon tabil (recipe follows)');
    final rule = _row(db, c.id, 7);
    expect(
      (
        rule.status,
        rule.fdcId,
        rule.grams,
        rule.childRecipeId,
        rule.description,
      ),
      ('confirmed', null, 0.0, null, subRecipeNote),
    );
    final own = nutritionBody(db, c, forAdmin: true);
    expect(own['includes'], isEmpty);
    expect(own['partial'], [
      {
        'position': 7,
        'kind': 'not_routed',
        'name': 'tabil',
        'title': 'Tabil',
        'matched': null,
        'total': null,
        'reason': 'no_ingredients',
      },
    ]);
    (String, int, int) parent(String id) {
      final n = db.nutritionFor(id)!;
      return (n.status, n.matchedCount, n.totalCount);
    }

    expect(parent(c.id), ('partial', 15, 16));
    expect(parent(stored(roastFile).id), ('partial', 5, 6));
    expect((own['status'], body['status']), ('partial', 'partial'));
    // The gate (verify1 D4 v13): a SECTION its host emptied — never a
    // library recipe, one printing no lines included (0929 latin-flan, real).
    final flan = loadCorpusRecipe('0929-latin-flan.yaml');
    db.upsertRecipe(
      flan,
      sourceSlug: _source,
      contentHash: contentHashOf(flan),
    );
    expect(nutritionLines(db.recipeByIdOrSlug(flan.id)!.recipe), isEmpty);
    final memo = ResolverMemo(db);
    expect(emptiedSectionChild(sectionKeyOf(c.id, 'Tabil'), memo), isTrue);
    expect(emptiedSectionChild(flan.id, memo), isFalse);
    expect(emptiedSectionChild(stored(roastFile).id, memo), isFalse);
  });

  test("F11's gate is EMPTY, not short (closer 3, verify3 D2): chraime's "
      'Tabil edited to ONE of its real lines (a STATED edit — no corpus '
      'section routed prints fewer than 2 lines) is no emptied section — '
      "the roast's pick and chraime's own route both stay routed and "
      'complete (16 of 16, 6 of 6), Tabil included', () async {
    final (:db, :config) = _store();
    final fdc = _fdc();
    const chraimeFile = '1208-chraime.yaml';
    const roastFile = '0214-roast-beef-tenderloin.yaml';
    await _compute(db, fdc, loadCorpusRecipe(chraimeFile));
    await _compute(db, fdc, loadCorpusRecipe(roastFile));
    Recipe stored(String f) =>
        nutritionRecipeOf(db, loadCorpusRecipe(f).id)!.recipe;
    Future<void> sweep(BulkScope scope) async {
      startBulkJob(db, fdc, scope: scope);
      while (bulkJobRunning) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    await applyMatchOverride(db, fdc, stored(roastFile), 5, {
      'raw': nutritionLines(stored(roastFile))[5].raw,
      'child': stored(chraimeFile).slug,
      'section': 'Tabil',
    });
    final chraime = stored(chraimeFile);
    final key = sectionKeyOf(chraime.id, 'Tabil');
    updateRecipe(db, config, chraime.id, {
      'subsections': [
        for (final sub in chraime.subsections)
          (sub.title == 'Tabil'
                  ? sub.copyWith(
                      ingredients: [
                        IngredientGroup(
                          group: sub.ingredients!.first.group,
                          items: [sub.ingredients!.first.items.first],
                        ),
                      ],
                    )
                  : sub)
              .toMap(),
      ],
    });
    await sweep(BulkScope.stale);
    await sweep(BulkScope.all);
    final c = stored(chraimeFile);
    expect(
      nutritionLines(sectionOf(c, key)!).map((l) => l.raw),
      ['3½ tablespoons coriander seeds'],
    );
    expect(emptiedSectionChild(key, ResolverMemo(db)), isFalse);
    (String, int, int) parent(String id) {
      final n = db.nutritionFor(id)!;
      return (n.status, n.matchedCount, n.totalCount);
    }

    expect(parent(c.id), ('complete', 16, 16));
    expect(parent(stored(roastFile).id), ('complete', 6, 6));
    for (final body in [
      nutritionBody(db, c, forAdmin: true),
      nutritionBody(db, stored(roastFile), forAdmin: true),
    ]) {
      expect(body['status'], 'complete');
      expect(body['partial'], isEmpty);
      expect(
        (body['includes']! as List).single,
        containsPair('section', 'Tabil'),
      );
    }
    expect(_row(db, stored(roastFile).id, 5).childRecipeId, key);
    expect(_row(db, c.id, 7).childRecipeId, key);
  });

  test('F9: a handed line of no recipe reads no reading — never the line at '
      "the row's position (closer 1, verify1 D4 v11: the equal-recipe "
      "fallback's raw gate; 0007's real Chianti line, a STATED row and "
      'STATED handed lines)', () {
    final tuscan = loadCorpusRecipe('0007-tuscan-style-beef-stew.yaml');
    final lines = nutritionLines(tuscan);
    expect(lines[3].raw, '1 (750-ml) bottle Chianti');
    final row = IngredientMatchRow(
      recipeId: tuscan.id,
      position: 3,
      raw: lines[3].raw,
      fdcId: 2710688,
      description: 'Wine, red',
      dataType: 'survey_fndds_food',
      confidence: 1,
      grams: 750,
      gramSource: 'volume',
      status: 'confirmed',
    );
    final reading = alcoholRetentionOf(tuscan, lines[3], row);
    expect(reading, isNotNull);
    // An equal recipe's line (the totals' stored `now`, decoded apart): read
    // at the row's position by its text.
    final equal = RecipeMapper.fromMap(tuscan.toMap());
    expect(identical(nutritionLines(equal)[3], lines[3]), isFalse);
    expect(alcoholRetentionOf(equal, lines[3], row), reading);
    // A line of no recipe: none.
    expect(
      alcoholRetentionOf(tuscan, _ln('1 cup dry white wine'), row),
      isNull,
    );
    expect(alcoholRetentionOf(equal, _ln('1 cup dry white wine'), row), isNull);
  });
}

/// F15–F17: the Opus critics of Run 066 (closer 4, under R3–R5).
void critics() {
  const beansFile = '0712-red-beans-and-rice.yaml';
  const riceFile = '0521-fried-rice-with-shrimp-pork-and-shiitakes.yaml';
  const doughs = [
    '0973-all-butter-double-crust-pie-dough.yaml',
    '0972-basic-double-crust-pie-dough.yaml',
    '0974-foolproof-double-crust-pie-dough.yaml',
  ];
  const blueberry = '0979-blueberry-pie.yaml';
  const deepDish = '0978-deep-dish-apple-pie.yaml';
  const pies = [
    blueberry,
    '0977-classic-apple-pie.yaml',
    deepDish,
    '0981-sweet-cherry-pie.yaml',
  ];
  // STATED synthesized: deep-dish-apple-pie|0 "1 recipe double-crust pie
  // dough" written with no amount (no corpus WB line routes to a library
  // recipe — the three route to sections).
  const amountless = 'Double-Crust Pie Dough (this page)';
  Recipe withLine0(Recipe r, String raw) => r.copyWith(
    ingredients: [
      for (final (i, g) in r.ingredients.indexed)
        IngredientGroup(
          group: g.group,
          items: [
            for (final (j, l) in g.items.indexed)
              i == 0 && j == 0 ? _ln(raw) : l,
          ],
        ),
    ],
  );
  Future<FixtureProvider> piesLibrary(SaltDatabase db, {String? line0}) async {
    // nutrition_v41_api_test's library: Sweet Cherry Pie's cherry line asks
    // a search no snapshot holds (answered as FDC's no hits).
    final fdc = FixtureProvider(
      pending: {...pendingSearches, 'sweet cherries or frozen cherries'},
    );
    for (final f in [...doughs, ...pies]) {
      final r = loadCorpusRecipe(f);
      final stored = f == deepDish && line0 != null ? withLine0(r, line0) : r;
      db.upsertRecipe(
        stored,
        sourceSlug: _source,
        contentHash: contentHashOf(stored),
      );
    }
    for (final f in [...doughs, ...pies]) {
      expect(
        await matchAndCompute(
          db,
          fdc,
          db.recipeByIdOrSlug(loadCorpusRecipe(f).id)!.recipe,
        ),
        isNull,
      );
    }
    return fdc;
  }

  Recipe stored(SaltDatabase db, String f) =>
      nutritionRecipeOf(db, loadCorpusRecipe(f).id)!.recipe;

  test(
    "F15: a person's recipe pick of an amount-less reference reads the "
    'share the route reads — red-beans-and-rice|14 "Basic White Rice (this '
    "page)\" (rule WB: 0521's section at 1.0, 402.2 g): the section, or its "
    'host, picked with no share is stored at 1.0, never refused "No share '
    "the yield can read\" (the Opus critic); the fix sheet's candidate "
    "offers the same share (240.45 kcal a serving, the routed row's)",
    () async {
      final db = _db();
      final fdc = _fdc();
      for (final f in [beansFile, riceFile]) {
        final r = loadCorpusRecipe(f);
        db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
      }
      expect((await _sweep(db, fdc, BulkScope.all))['failed'], 0);
      final rice = stored(db, riceFile);
      final key = sectionKeyOf(rice.id, 'Basic White Rice');
      final line = nutritionLines(stored(db, beansFile))[14];
      expect(line.raw, 'Basic White Rice (this page)');
      expect(line.amounts, isEmpty);
      IngredientMatchRow row() => _row(db, stored(db, beansFile).id, 14);
      expect(
        (row().childRecipeId, row().childShare, row().grams, row().status),
        (key, 1.0, 402.2, 'auto'),
      );
      final sheet = referenceChildJson(
        db,
        stored(db, beansFile),
        14,
        line,
        row(),
        ResolverMemo(db),
      )!;
      // RE-PIN (M86 batch, v90, 958: the section's 2512381 rice): was 240.45.
      expect(sheet['kcal_per_serving'], 247.78);
      final candidate = (sheet['candidates']! as List).single as Map;
      expect(
        (
          candidate['section'],
          candidate['kcal'],
          candidate['kcal_per_serving'],
          candidate['pickable'],
        ),
        // RE-PIN (M86 batch, v90, 958: 2512381 rice): was 1442.71, 240.45.
        ('Basic White Rice', 1486.68, 247.78, true),
      );
      await applyMatchOverride(db, fdc, stored(db, beansFile), 14, {
        'raw': line.raw,
        'child': rice.slug,
        'section': 'Basic White Rice',
      });
      expect(
        (row().status, row().childRecipeId, row().childShare, row().grams),
        ('overridden', key, 1.0, 402.2),
      );
      await applyMatchOverride(db, fdc, stored(db, beansFile), 14, {
        'raw': line.raw,
        'child': rice.slug,
      });
      // RE-PIN (M87 batch, v91, Q1 (b′)) — STATED FOR THE RULING (fix91
      // D1): 0521|9 now names its own Basic White Rice, so the host is itself
      // made from a recipe and a pick of the whole host is held
      // `nested_recipe` at 0 g, its share kept (`_childRowOf`, the shipped
      // depth-1 rule) — was ('overridden', rice.id, 1.0, the host's total
      // grams), hold null.
      expect(
        (
          row().status,
          row().childRecipeId,
          row().childShare,
          row().grams,
          row().hold,
        ),
        ('overridden', rice.id, 1.0, 0.0, nestedRecipeHold),
      );
      // RE-PIN (M82 batch, v84, C3a): 0521's garlic |8 at its printed 2
      // teaspoons (6.00 → 5.60 g): was 1791.6.
      // RE-PIN (M87 batch, v91): the host's total grams, no longer the row's
      // (|9's 790.00 g cooked rice → the section's 402.20 g raw): was
      // `row().grams` 1791.2.
      expect(db.nutritionFor(rice.id)!.totalGrams, 1403.4);
    },
  );

  test("F15: rule WB's whole batch reaches every share reader beside the "
      "route (STATED synthesized: 0978's line 0 written \"$amountless\", "
      "routed at 1.0 to 0973 by the pies' note): the fix sheet's library "
      "candidates offer it a serving, a recipe decision's reach takes the "
      'line and its apply writes it at 1.0', () async {
    final db = _db();
    final fdc = await piesLibrary(db, line0: amountless);
    final basic = stored(db, doughs[1]);
    final deep = stored(db, deepDish);
    expect(nutritionLines(deep)[0].amounts, isEmpty);
    expect(
      (
        _row(db, deep.id, 0).childRecipeId,
        _row(db, deep.id, 0).childShare,
        _row(db, deep.id, 0).grams,
      ),
      // RE-PIN (M90 batch, v89, sugar): the doughs' sugar at the print — was 642.9.
      (stored(db, doughs[0]).id, 1.0, 642.7),
    );
    final sheet = referenceChildJson(
      db,
      deep,
      0,
      nutritionLines(deep)[0],
      _row(db, deep.id, 0),
      ResolverMemo(db),
    )!;
    // RE-PIN (M90 batch, v89, sugar): the doughs' sugar at the print — was
    // 382.09; 3056.69, 382.09; 3519.96, 440.0; 3649.32, 456.17.
    // RE-PIN (M86 batch, v90, 958: the dough's 2346387 sour cream): was
    // 382.01.
    expect(sheet['kcal_per_serving'], 381.81);
    expect(
      [
        for (final c
            in (sheet['candidates']! as List).cast<Map<String, Object?>>())
          (c['group'], c['title'], c['kcal'], c['kcal_per_serving']),
      ],
      [
        // RE-PIN (M86 batch, v90, 958: 2346387 sour cream): was 3056.05,
        // 382.01.
        ('note_named', 'All-Butter Double-Crust Pie Dough', 3054.47, 381.81),
        ('note_named', 'Basic Double-Crust Pie Dough', 3518.69, 439.84),
        ('note_named', 'Foolproof Double-Crust Pie Dough', 3648.05, 456.01),
      ],
    );
    final source = stored(db, blueberry);
    expect(
      {
        for (final r in recipeReach(
          db,
          _row(db, source.id, 0).itemKey!,
          childId: basic.id,
          excluding: (recipeId: source.id, position: 0),
          memo: ResolverMemo(db),
        ))
          (r.recipeId, r.position),
      },
      {
        for (final f in pies.skip(1)) (stored(db, f).id, 0),
      },
    );
    final applied = await applyMatchOverride(db, fdc, source, 0, {
      'raw': nutritionLines(source)[0].raw,
      'child': basic.slug,
      'apply_to_all': true,
    });
    expect(applied!.lines, 3);
    final row = _row(db, deep.id, 0);
    expect(
      (row.status, row.childRecipeId, row.childShare, row.grams),
      // RE-PIN (M90 batch, v89, sugar): the doughs' sugar at the print — was 658.2.
      ('overridden', basic.id, 1.0, 657.9),
    );
  });

  test("F15: a decided child row re-reads the route's share when its line's "
      "amount moves — 0978's real \"1 recipe double-crust pie dough\" picked "
      '0972 (1.0, 657.9 g), then written "$amountless" through the real '
      'updateRecipe (STATED synthesized edit): still 1.0 and 657.9 g after the '
      'stale sweep, never a 0 g person row showing share 1.0', () async {
    final (:db, :config) = _store();
    final fdc = await piesLibrary(db);
    final basic = stored(db, doughs[1]);
    final deep = stored(db, deepDish);
    expect(nutritionLines(deep)[0].raw, '1 recipe double-crust pie dough');
    await applyMatchOverride(db, fdc, deep, 0, {
      'raw': nutritionLines(deep)[0].raw,
      'child': basic.slug,
    });
    String sig() {
      final row = _row(db, deep.id, 0);
      return '${row.raw}|${row.status}|${row.childRecipeId}|'
          '${row.childShare}|${row.grams}';
    }

    expect(
      sig(),
      // RE-PIN (M90 batch, v89, sugar): the doughs' sugar at the print — was 658.2.
      '1 recipe double-crust pie dough|overridden|${basic.id}|1.0|657.9',
    );
    updateRecipe(db, config, deep.id, {
      'ingredients': [
        for (final g in withLine0(deep, amountless).ingredients) g.toMap(),
      ],
    });
    expect((await _sweep(db, fdc, BulkScope.stale))['failed'], 0);
    // RE-PIN (M90 batch, v89, sugar): the doughs' sugar at the print — was 658.2.
    expect(sig(), '$amountless|overridden|${basic.id}|1.0|657.9');
    expect(nutritionIsFresh(db, stored(db, deepDish)), isTrue);
  });

  test(
    "F15's served-with gate: an amount-less line a served-with marker "
    'reads takes no whole batch (rule SW: the route never reads it) — '
    "spanish-tortilla|8's real \"Garlic Mayonnaise (optional) (recipe "
    'follows)" picked as a recipe with no share is refused, as before',
    () async {
      final db = _db();
      final fdc = _fdc();
      const tortillaFile =
          '0738-spanish-tortilla-with-roasted-red-peppers-and-peas.yaml';
      final tortilla = await _compute(db, fdc, loadCorpusRecipe(tortillaFile));
      final steaks = await _compute(
        db,
        fdc,
        loadCorpusRecipe('0184-pan-seared-steaks.yaml'),
      );
      final line = nutritionLines(tortilla)[8];
      expect(line.raw, 'Garlic Mayonnaise (optional) (recipe follows)');
      expect(line.amounts, isEmpty);
      expect(servedWithMarked(tortilla, line), isTrue);
      expect(routeShareOf(tortilla, line, steaks), isNull);
      await expectLater(
        applyMatchOverride(db, fdc, tortilla, 8, {
          'raw': line.raw,
          'child': steaks.slug,
        }),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            noShareMessage,
          ),
        ),
      );
      expect(_row(db, tortilla.id, 8).childRecipeId, isNull);
    },
  );

  test(
    "F15's A9 gate reads a SECTION's bare count only (closer 5, verify5 D1): "
    "vegan-baja-style-cauliflower-tacos|14's real \"1 Vegan Cilantro Sauce\" "
    '(A9: its own section at 1.0, 120.8 g) picked as the LIBRARY recipe 0521 '
    'with no share is refused "No share the yield can read", as before — '
    'a bare count of 1 reads one batch of a section, never of a recipe whose '
    'yield reads no share of it',
    () async {
      final db = _db();
      final fdc = _fdc();
      const tacosFile = '1093-vegan-baja-style-cauliflower-tacos.yaml';
      for (final f in [tacosFile, riceFile]) {
        final r = loadCorpusRecipe(f);
        db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
      }
      expect((await _sweep(db, fdc, BulkScope.all))['failed'], 0);
      final tacos = stored(db, tacosFile);
      final rice = stored(db, riceFile);
      final key = sectionKeyOf(tacos.id, 'Vegan Cilantro Sauce');
      final line = nutritionLines(tacos)[14];
      expect(line.raw, '1 Vegan Cilantro Sauce');
      expect(
        [for (final a in line.amounts) (a.quantity, a.unit)],
        [
          ('1', null),
        ],
      );
      String sig() {
        final row = _row(db, tacos.id, 14);
        return '${row.status}|${row.childRecipeId}|${row.childShare}|'
            '${row.grams}';
      }

      expect(sig(), 'auto|$key|1.0|120.8');
      expect(
        routeShareOf(tacos, line, nutritionRecipeOf(db, key)!.recipe),
        1.0,
      );
      expect(rice.servings, 'SERVES 4 TO 6');
      expect(routeShareOf(tacos, line, rice), isNull);
      await expectLater(
        applyMatchOverride(db, fdc, tacos, 14, {
          'raw': line.raw,
          'child': rice.slug,
        }),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            noShareMessage,
          ),
        ),
      );
      expect(sig(), 'auto|$key|1.0|120.8');
    },
  );

  test("F16: a child section's failure in a job is the SECTION's — its log "
      'line names it "{host slug} · {title}", never the recipe\'s id, and it '
      "moves no count (a job's total, done and failed count recipes; its "
      'parent fails with it, still stale) — skillet-chicken-fajitas (real) '
      'and its own "Spicy Pickled Radishes" (STATED synthesized: the radish '
      'search throws — a StateError, and a provider failure that stops the '
      'sweep), in the bulk sweep and the per-recipe job; a failure of the '
      "recipe's own compute after its section is still the recipe's", () async {
    const fajitas = '0070-skillet-chicken-fajitas.yaml';
    final id = loadCorpusRecipe(fajitas).id;
    const section = 'skillet-chicken-fajitas · Spicy Pickled Radishes';
    Future<(Map<String, Object?>, Map<String, Object?>)> jobs(
      String word,
      Object failure,
    ) async {
      // Each job on a library of its own: the per-recipe job computes the
      // section first (no stamp), then the recipe.
      SaltDatabase library() {
        final db = _db();
        final r = loadCorpusRecipe(fajitas);
        db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
        expect(
          sectionChildKeysOf(
            db,
            nutritionRecipeOf(db, id)!.recipe,
            ResolverMemo(db),
          ),
          {sectionKeyOf(id, 'Spicy Pickled Radishes')},
        );
        return db;
      }

      final fdc = _FailingSearch(word, failure);
      final bulk = await _sweep(library(), fdc, BulkScope.all);
      final db = library();
      final job = startRecipeComputeJob(
        db,
        fdc,
        nutritionRecipeOf(db, id)!.recipe,
      );
      while (recipeComputeJobId(id) != null) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return (bulk, db.nutritionJob(job)!);
    }

    List<Object?> counts(Map<String, Object?> j) => [
      j['status'],
      j['total'],
      j['done'],
      j['failed'],
    ];
    List<Object?> log(Map<String, Object?> j) => j['log']! as List<Object?>;

    final (bulk, one) = await jobs('radish', StateError('boom'));
    expect(counts(bulk), ['done', 1, 1, 1]);
    expect(log(bulk), [
      '$section: Bad state: boom',
      '$id: Bad state: still stale after 3 compute passes',
    ]);
    expect(counts(one), ['failed', 1, 0, 1]);
    expect(log(one), ['$section: Bad state: boom']);

    final (stopped, stoppedOne) = await jobs(
      'radish',
      const NutritionProviderException('FDC is down'),
    );
    expect(counts(stopped), ['failed', 1, 0, 0]);
    expect(log(stopped), ['stopped at $section: FDC is down']);
    expect(counts(stoppedOne), ['failed', 1, 0, 1]);
    expect(log(stoppedOne), ['$section: FDC is down']);

    final (_, own) = await jobs('chicken', StateError('boom'));
    expect(counts(own), ['failed', 1, 0, 1]);
    expect(log(own), ['$id: Bad state: boom']);
  });

  for (final (edit, base) in [
    ('the host retitled to a tie', 'the host'),
    ('a new sibling with lines under a closer title', 'the new section'),
  ]) {
    test("F17: rule PV's choice of base is hashed — lemon-meringue-pie|0's "
        "prose \"Single-Crust Pie Dough for Custard Pies\" counts 0972's "
        'Basic Single-Crust Pie Dough (4 shared words; real, beside '
        "pumpkin-pie|0's own route to it); 0972 edited through the real "
        'updateRecipe (STATED synthesized: $edit) moves PV to $base — '
        'lemon reads stale at once, the stale sweep selects it and ONE '
        'sweep re-routes it (was: fresh on the old base through every '
        'sweep, the Opus critic)', () async {
      final (:db, :config) = _store();
      final fdc = _fdc();
      const lemonFile = '0989-lemon-meringue-pie.yaml';
      const doughFile = '0972-basic-double-crust-pie-dough.yaml';
      const pumpkinFile = '0987-pumpkin-pie.yaml';
      for (final f in [lemonFile, doughFile, pumpkinFile]) {
        final r = loadCorpusRecipe(f);
        db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
      }
      expect((await _sweep(db, fdc, BulkScope.all))['failed'], 0);
      Recipe stored(String f) =>
          nutritionRecipeOf(db, loadCorpusRecipe(f).id)!.recipe;
      final dough = stored(doughFile);
      final single = sectionKeyOf(dough.id, 'Basic Single-Crust Pie Dough');
      expect(_row(db, stored(pumpkinFile).id, 0).childRecipeId, single);
      final lemonId = stored(lemonFile).id;
      expect(
        (_row(db, lemonId, 0).childRecipeId, _row(db, lemonId, 0).grams),
        // RE-PIN (M90 batch, v89, sugar): the doughs' sugar at the print — was 302.1.
        (single, 301.9),
      );
      final String moved;
      final double grams;
      if (base == 'the host') {
        updateRecipe(db, config, dough.id, {
          'title': 'Basic Single-Crust and Double-Crust Pie Dough',
        });
        // RE-PIN (M90 batch, v89, sugar): the doughs' sugar at the print — was 658.2.
        (moved, grams) = (dough.id, 657.9);
      } else {
        const title = 'Single-Crust Pie Dough for Custard Tarts';
        updateRecipe(db, config, dough.id, {
          'subsections': [
            for (final sub in dough.subsections) sub.toMap(),
            dough.subsections
                .firstWhere((s) => s.title == 'Basic Single-Crust Pie Dough')
                .copyWith(title: title)
                .toMap(),
          ],
        });
        // RE-PIN (M90 batch, v89, sugar): the doughs' sugar at the print — was 302.1.
        (moved, grams) = (sectionKeyOf(dough.id, title), 301.9);
      }
      expect(
        resolveReference(
          db,
          stored(lemonFile),
          nutritionLines(stored(lemonFile))[0],
          ResolverMemo(db),
        ).childId,
        moved,
      );
      expect(nutritionIsFresh(db, stored(lemonFile)), isFalse);
      expect(bulkScopeIds(db, BulkScope.stale), contains(lemonId));
      expect((await _sweep(db, fdc, BulkScope.stale))['failed'], 0);
      expect(
        (_row(db, lemonId, 0).childRecipeId, _row(db, lemonId, 0).grams),
        (moved, grams),
      );
      expect(nutritionIsFresh(db, stored(lemonFile)), isTrue);
      expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
      // pumpkin-pie keeps its own route.
      expect(_row(db, stored(pumpkinFile).id, 0).childRecipeId, single);
    });
  }

  test("F17's choice keeps PV's nested gate (closer 5, verify5 D3: the choice "
      'read once per prose section): a base made from a recipe is no base — '
      "STATED synthesized: 0972's Basic Single-Crust Pie Dough with its real "
      '"4–6 tablespoons ice water" written "1 recipe Foolproof Single-Crust '
      'Pie Dough (this page)": lemon-meringue-pie|0 keeps the prose '
      "section's `no_ingredients` answer (routed to the real section "
      "before), and lemon's hash moves with PV's answer", () {
    final db = _db();
    final lemon = loadCorpusRecipe('0989-lemon-meringue-pie.yaml');
    final dough = loadCorpusRecipe('0972-basic-double-crust-pie-dough.yaml');
    for (final r in [lemon, dough]) {
      db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
    }
    final line = nutritionLines(lemon)[0];
    ReferenceResolution route() =>
        resolveReference(db, lemon, line, ResolverMemo(db));
    final prose = sectionKeyOf(
      dough.id,
      'Single-Crust Pie Dough for Custard Pies',
    );
    expect(proseSectionsReadBy(lemon, ResolverMemo(db)), [prose]);
    expect(
      (route().kind, route().childId),
      (
        ReferenceKind.routed,
        sectionKeyOf(dough.id, 'Basic Single-Crust Pie Dough'),
      ),
    );
    final before = ingredientsHashOf(lemon, ResolverMemo(db));
    final nested = dough.copyWith(
      subsections: [
        for (final sub in dough.subsections)
          sub.title != 'Basic Single-Crust Pie Dough'
              ? sub
              : sub.copyWith(
                  ingredients: [
                    IngredientGroup(
                      items: [
                        for (final l in sub.ingredients!.single.items)
                          l.raw == '4–6 tablespoons ice water'
                              ? _ln(
                                  '1 recipe Foolproof Single-Crust Pie Dough '
                                  '(this page)',
                                )
                              : l,
                      ],
                    ),
                  ],
                ),
      ],
    );
    expect(
      nested.subsections
          .firstWhere((s) => s.title == 'Basic Single-Crust Pie Dough')
          .ingredients!
          .single
          .items
          .map((l) => l.raw),
      contains('1 recipe Foolproof Single-Crust Pie Dough (this page)'),
    );
    db.upsertRecipe(
      nested,
      sourceSlug: _source,
      contentHash: contentHashOf(nested),
    );
    final r = route();
    expect(
      (r.kind, r.childId, r.noIngredients),
      (
        ReferenceKind.section,
        null,
        true,
      ),
    );
    expect(proseSectionsReadBy(lemon, ResolverMemo(db)), [prose]);
    expect(ingredientsHashOf(lemon, ResolverMemo(db)), isNot(before));
  });

  test(
    "F17's per-line tail reads the line's own share of PV's base (closer "
    '5, verify5 D3) — STATED synthesized: lemon-meringue-pie|0 written '
    "\"½ recipe …\" routes to 0972's Basic Single-Crust Pie Dough at 0.5, "
    'written "2 cups …" reads no share and keeps the prose section\'s '
    '`no_ingredients` answer (every corpus PV line prints "1 recipe": 1.0)',
    () {
      final db = _db();
      final lemon = loadCorpusRecipe('0989-lemon-meringue-pie.yaml');
      final dough = loadCorpusRecipe('0972-basic-double-crust-pie-dough.yaml');
      for (final r in [lemon, dough]) {
        db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
      }
      final real = nutritionLines(lemon)[0].raw;
      expect(
        real,
        startsWith('1 recipe Single-Crust Pie Dough for Custard Pies'),
      );
      ReferenceResolution route(String raw) {
        final r = withLine0(lemon, raw);
        return resolveReference(db, r, nutritionLines(r)[0], ResolverMemo(db));
      }

      final base = sectionKeyOf(dough.id, 'Basic Single-Crust Pie Dough');
      final real1 = route(real);
      expect(
        (real1.kind, real1.childId, real1.share),
        (
          ReferenceKind.routed,
          base,
          1.0,
        ),
      );
      final half = route(real.replaceFirst('1 recipe', '½ recipe'));
      expect(
        (half.kind, half.childId, half.share),
        (
          ReferenceKind.routed,
          base,
          0.5,
        ),
      );
      final cups = route(real.replaceFirst('1 recipe', '2 cups'));
      expect(
        (cups.kind, cups.childId, cups.share, cups.noIngredients),
        (
          ReferenceKind.section,
          null,
          null,
          true,
        ),
      );
    },
  );

  test(
    "F17's choice is read per PROSE SECTION — each prose section hashes its "
    "own base (closer 6, verify6 D1: the choice memo's key) — STATED "
    "synthesized: lemon-meringue-pie with fresh-plum-ginger-pie|0's real "
    'line "1 recipe Foolproof Whole-Wheat Dough for Double-Crust Pie (this '
    'page)" appended to its first group (two prose sections of two hosts), '
    'beside real 0972 and 0976; 0976 then given a sibling "Whole-Wheat '
    'Dough for Double-Crust Pie" with its own lines (the real updateRecipe) '
    "moves PV's answer for the SECOND prose section alone — lemon reads "
    'stale at once and ONE sweep re-routes |1 to the new section (1.0, '
    '668.8 g)',
    () async {
      final (:db, :config) = _store();
      final fdc = _fdc();
      final appended = loadCorpusRecipe(
        '0983-fresh-plum-ginger-pie-with-whole-wheat-lattice-top-crust.yaml',
      ).ingredients.first.items.first;
      expect(
        appended.raw,
        '1 recipe Foolproof Whole-Wheat Dough for Double-Crust Pie (this '
        'page)',
      );
      final real = loadCorpusRecipe('0989-lemon-meringue-pie.yaml');
      final lemon = real.copyWith(
        ingredients: [
          for (final (i, g) in real.ingredients.indexed)
            i == 0
                ? IngredientGroup(group: g.group, items: [...g.items, appended])
                : g,
        ],
      );
      final dough = loadCorpusRecipe('0972-basic-double-crust-pie-dough.yaml');
      final butter = loadCorpusRecipe(
        '0976-foolproof-all-butter-dough-for-double-crust-pie.yaml',
      );
      for (final r in [lemon, dough, butter]) {
        db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
      }
      expect((await _sweep(db, fdc, BulkScope.all))['failed'], 0);
      Recipe stored(String id) => nutritionRecipeOf(db, id)!.recipe;
      final p = nutritionLines(
        stored(lemon.id),
      ).indexWhere((l) => l.raw == appended.raw);
      expect(p, 1);
      expect(proseSectionsReadBy(stored(lemon.id), ResolverMemo(db)), [
        sectionKeyOf(dough.id, 'Single-Crust Pie Dough for Custard Pies'),
        sectionKeyOf(
          butter.id,
          'Foolproof Whole-Wheat Dough for Double-Crust Pie',
        ),
      ]);
      final single = sectionKeyOf(dough.id, 'Basic Single-Crust Pie Dough');
      (String?, double?, double?) routed(int at) {
        final m = _row(db, lemon.id, at);
        return (m.childRecipeId, m.childShare, m.grams);
      }

      // RE-PIN (M90 batch, v89, sugar): the doughs' sugar at the print — was 302.1.
      expect(routed(0), (single, 1.0, 301.9));
      // RE-PIN (M90 batch, v89, sugar): the doughs' sugar at the print — was 669.1.
      expect(routed(p), (butter.id, 1.0, 668.8));
      final before = ingredientsHashOf(stored(lemon.id), ResolverMemo(db));
      final host = stored(butter.id);
      updateRecipe(db, config, butter.id, {
        'subsections': [
          for (final sub in host.subsections) sub.toMap(),
          {
            'title': 'Whole-Wheat Dough for Double-Crust Pie',
            'ingredients': [for (final g in host.ingredients) g.toMap()],
          },
        ],
      });
      final added = sectionKeyOf(
        butter.id,
        'Whole-Wheat Dough for Double-Crust Pie',
      );
      final r = resolveReference(
        db,
        stored(lemon.id),
        nutritionLines(stored(lemon.id))[p],
        ResolverMemo(db),
      );
      expect((r.kind, r.childId, r.share), (ReferenceKind.routed, added, 1.0));
      expect(
        ingredientsHashOf(stored(lemon.id), ResolverMemo(db)),
        isNot(before),
      );
      expect(nutritionIsFresh(db, stored(lemon.id)), isFalse);
      expect(
        bulkScopeIds(db, BulkScope.stale),
        unorderedEquals([added, lemon.id]),
      );
      expect((await _sweep(db, fdc, BulkScope.stale))['failed'], 0);
      // RE-PIN (M90 batch, v89, sugar): the doughs' sugar at the print — was 669.1.
      expect(routed(p), (added, 1.0, 668.8));
      // RE-PIN (M90 batch, v89, sugar): the doughs' sugar at the print — was 302.1.
      expect(routed(0), (single, 1.0, 301.9));
      expect(nutritionIsFresh(db, stored(lemon.id)), isTrue);
      expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
    },
  );

  test(
    "F17's choice is read per prose section of ONE host — the memo keys the "
    'host AND the title (closer 7, verify7 D1) — STATED synthesized: '
    "lemon-meringue-pie|0's real line copied with its title written \"Hand "
    'Mixed Basic Double-Crust Pie Dough" (0972\'s real prose section) and '
    'appended to its first group (two prose sections of ONE host), beside '
    'real 0972; 0972 then given a sibling "Hand Mixed Double-Crust Pie '
    'Dough" with the host\'s own lines (the real updateRecipe) moves PV\'s '
    'answer for the SECOND prose section alone — lemon reads stale at once '
    'and ONE sweep re-routes |1 to the new section (1.0, 657.9 g)',
    () async {
      final (:db, :config) = _store();
      final fdc = _fdc();
      final real = loadCorpusRecipe('0989-lemon-meringue-pie.yaml');
      final raw = nutritionLines(real)[0].raw;
      expect(
        raw,
        startsWith('1 recipe Single-Crust Pie Dough for Custard Pies'),
      );
      final appended = _ln(
        raw.replaceFirst(
          'Single-Crust Pie Dough for Custard Pies',
          'Hand Mixed Basic Double-Crust Pie Dough',
        ),
      );
      expect(
        appended.raw,
        '1 recipe Hand Mixed Basic Double-Crust Pie Dough (this page), fitted '
        'into a 9-inch pie plate and chilled',
      );
      final lemon = real.copyWith(
        ingredients: [
          for (final (i, g) in real.ingredients.indexed)
            i == 0
                ? IngredientGroup(group: g.group, items: [...g.items, appended])
                : g,
        ],
      );
      final dough = loadCorpusRecipe('0972-basic-double-crust-pie-dough.yaml');
      for (final r in [lemon, dough]) {
        db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
      }
      expect((await _sweep(db, fdc, BulkScope.all))['failed'], 0);
      Recipe stored(String id) => nutritionRecipeOf(db, id)!.recipe;
      final p = nutritionLines(
        stored(lemon.id),
      ).indexWhere((l) => l.raw == appended.raw);
      expect(p, 1);
      expect(proseSectionsReadBy(stored(lemon.id), ResolverMemo(db)), [
        sectionKeyOf(dough.id, 'Single-Crust Pie Dough for Custard Pies'),
        sectionKeyOf(dough.id, 'Hand Mixed Basic Double-Crust Pie Dough'),
      ]);
      final single = sectionKeyOf(dough.id, 'Basic Single-Crust Pie Dough');
      (String?, double?, double?) routed(int at) {
        final m = _row(db, lemon.id, at);
        return (m.childRecipeId, m.childShare, m.grams);
      }

      // RE-PIN (M90 batch, v89, sugar): the doughs' sugar at the print — was 302.1.
      expect(routed(0), (single, 1.0, 301.9));
      // RE-PIN (M90 batch, v89, sugar): the doughs' sugar at the print — was 658.2.
      expect(routed(p), (dough.id, 1.0, 657.9));
      final before = ingredientsHashOf(stored(lemon.id), ResolverMemo(db));
      final host = stored(dough.id);
      updateRecipe(db, config, dough.id, {
        'subsections': [
          for (final sub in host.subsections) sub.toMap(),
          {
            'title': 'Hand Mixed Double-Crust Pie Dough',
            'ingredients': [for (final g in host.ingredients) g.toMap()],
          },
        ],
      });
      final added = sectionKeyOf(dough.id, 'Hand Mixed Double-Crust Pie Dough');
      (ReferenceKind, String?, double?) resolved(int at) {
        final r = resolveReference(
          db,
          stored(lemon.id),
          nutritionLines(stored(lemon.id))[at],
          ResolverMemo(db),
        );
        return (r.kind, r.childId, r.share);
      }

      expect(resolved(p), (ReferenceKind.routed, added, 1.0));
      expect(resolved(0), (ReferenceKind.routed, single, 1.0));
      expect(
        ingredientsHashOf(stored(lemon.id), ResolverMemo(db)),
        isNot(before),
      );
      expect(nutritionIsFresh(db, stored(lemon.id)), isFalse);
      expect(
        bulkScopeIds(db, BulkScope.stale),
        unorderedEquals([added, lemon.id]),
      );
      expect((await _sweep(db, fdc, BulkScope.stale))['failed'], 0);
      // RE-PIN (M90 batch, v89, sugar): the doughs' sugar at the print — was 658.2.
      expect(routed(p), (added, 1.0, 657.9));
      // RE-PIN (M90 batch, v89, sugar): the doughs' sugar at the print — was 302.1.
      expect(routed(0), (single, 1.0, 301.9));
      expect(nutritionIsFresh(db, stored(lemon.id)), isTrue);
      expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
    },
  );

  test(
    "F17's hash folds each line's OWN share of PV's base (closer 6, verify6 "
    'D2: the per-line tail) — STATED synthesized: lemon-meringue-pie|0 '
    'written "2 cups …" reads no share of 0972\'s Basic Single-Crust Pie '
    'Dough ("MAKES ENOUGH FOR ONE 9-INCH PIE": unmeasured, 0 g); that '
    'section\'s yield then written "MAKES ABOUT 4 CUPS" (the real '
    'updateRecipe) — the line reads ½: lemon reads stale at once and ONE '
    'sweep routes |0 at 0.5 (150.95 g)',
    () async {
      final (:db, :config) = _store();
      final fdc = _fdc();
      final real = loadCorpusRecipe('0989-lemon-meringue-pie.yaml');
      final raw = nutritionLines(real)[0].raw;
      expect(
        raw,
        startsWith('1 recipe Single-Crust Pie Dough for Custard Pies'),
      );
      final lemon = withLine0(real, raw.replaceFirst('1 recipe', '2 cups'));
      final dough = loadCorpusRecipe('0972-basic-double-crust-pie-dough.yaml');
      for (final r in [lemon, dough]) {
        db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
      }
      expect((await _sweep(db, fdc, BulkScope.all))['failed'], 0);
      Recipe stored(String id) => nutritionRecipeOf(db, id)!.recipe;
      const title = 'Basic Single-Crust Pie Dough';
      final single = sectionKeyOf(dough.id, title);
      final host = stored(dough.id);
      expect(
        host.subsections.singleWhere((s) => s.title == title).servings,
        'MAKES ENOUGH FOR ONE 9-INCH PIE',
      );
      (String?, double?, double?, String?) row0() {
        final m = _row(db, lemon.id, 0);
        return (m.childRecipeId, m.childShare, m.grams, m.gramSource);
      }

      expect(row0(), (null, null, 0.0, 'unmeasured'));
      final before = ingredientsHashOf(stored(lemon.id), ResolverMemo(db));
      updateRecipe(db, config, dough.id, {
        'subsections': [
          for (final sub in host.subsections)
            (sub.title == title
                    ? sub.copyWith(servings: 'MAKES ABOUT 4 CUPS')
                    : sub)
                .toMap(),
        ],
      });
      final r = resolveReference(
        db,
        stored(lemon.id),
        nutritionLines(stored(lemon.id))[0],
        ResolverMemo(db),
      );
      expect((r.kind, r.childId, r.share), (ReferenceKind.routed, single, 0.5));
      expect(
        ingredientsHashOf(stored(lemon.id), ResolverMemo(db)),
        isNot(before),
      );
      expect(nutritionIsFresh(db, stored(lemon.id)), isFalse);
      expect(
        bulkScopeIds(db, BulkScope.stale),
        unorderedEquals([single, lemon.id]),
      );
      expect((await _sweep(db, fdc, BulkScope.stale))['failed'], 0);
      // RE-PIN (M90 batch, v89, sugar): the doughs' sugar at the print — was 151.05.
      expect(row0(), (single, 0.5, 150.95, 'recipe'));
      expect(nutritionIsFresh(db, stored(lemon.id)), isTrue);
      expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
    },
  );
}

/// v54's stop regex (`_alcoholStops`), the reference [alcoholStopsForTest]
/// reads as (F3).
final RegExp _v54Stops = RegExp(
  r'(?<final>\bserve\b)|'
  r'(?<removal>\boff (the )?heat\b|\bremove\b[^.;]*\bfrom (the )?'
  r'(heat|oven|grill)\b)|'
  r'(?<wait>\b(let|allow)\b[^.;]*\b(cool|stand|rest|sit|settle)\b|'
  r'\bcool (for|slightly|completely|to)\b|^cool\b|\brefrigerat\w*|'
  r'\bchill\b|\bfreez\w*|\bset aside\b|\bkeep warm\b)|'
  r'(?<out>\bstrain\b|\bthrough (a )?fine-mesh\b|'
  r'\btransfer (the )?(sauce|mixture|liquid|braising liquid|stock|broth|'
  r'gravy|soup|reduction|syrup|glaze)\b[^.;]* to (a |the )?([\w-]+ )*?'
  '(bowl|container|measuring cup|jar|fat separator|serving|platter|'
  r'gravy boat|pitcher|blender)\b|'
  r'\b(transfer|place|stack)\b[^.;]*\b(to|on|onto) (a |the )?([\w-]+ )*'
  '(wire rack|paper towels?|paper bag|(?<!pie )plate|platter|cutting board|'
  'carving board))',
);

List<(int, int, String)> _v54(String s) => [
  for (final m in _v54Stops.allMatches(s))
    (
      m.start,
      m.end,
      m.namedGroup('final') != null
          ? 'final'
          : m.namedGroup('removal') != null
          ? 'removal'
          : m.namedGroup('wait') != null
          ? 'wait'
          : 'out',
    ),
];

/// Every corpus step sentence, lower-cased.
final List<String> _corpusSentences = () {
  final out = <String>[];
  for (final f
      in Directory(corpusRecipesDir).listSync().whereType<File>().where(
        (f) => f.path.endsWith('.yaml'),
      )) {
    for (final step in loadCorpusRecipe(f.uri.pathSegments.last).steps) {
      out.addAll(step.text.toLowerCase().split(RegExp(r'(?<=\.)\s+')));
    }
  }
  return out..sort();
}();

final RegExp _alcoholWord = RegExp(
  r'\b(wine|beer|sherry|brandy|vodka|rum|bourbon|cognac|vermouth|sake|'
  'mirin|liqueur|whiskey|tequila|marsala|port|madeira|ale|stout|kirsch|'
  r'calvados|amaretto)\b',
);

void readers() {
  test("F3: the stop reader answers as v54's regex — start, end and kind — "
      'on 120,000 sentences (every third a corpus sentence as written, the '
      "rest one with 1–8 of the arms' own words spliced in, one in four "
      'joined with no spaces), and reads the cubic shapes at 1,000 / 10,000 '
      '/ 100,000 characters in one pass each', () {
    expect(_corpusSentences.length, greaterThan(20000));
    const atoms = [
      'transfer', 'the', 'sauce', 'braising liquid', 'liquid', 'to', 'a', //
      'large', 'bowl', 'bowls', 'serving', 'platter', 'place', 'stack', 'on',
      'onto', 'into', 'wire rack', 'paper towel', 'paper towels', 'pie plate',
      'plate', 'plates', 'cutting board', 'remove', 'from', 'heat', 'oven',
      'grill', 'let', 'allow', 'cool', 'stand', 'rest', 'sit', 'settle', 'for',
      'slightly', 'serve', 'served', 'off', 'chill', 'freeze', 'refrigerate',
      'set aside', 'keep warm', 'strain', 'strainer', 'through', 'fine-mesh',
      'measuring cup', 'fat separator', 'gravy boat', '.', ';', ',',
      'sautéed', 'big-old', '-', 'x', '  ', 'pitcher', 'jar', 'blender',
      'container', 'stock',
    ];
    var hits = 0;
    final arms = <String, int>{};
    for (var seed = 0; seed < 120000; seed++) {
      final r = Random(seed);
      final base = _corpusSentences[r.nextInt(_corpusSentences.length)];
      String s;
      if (seed % 3 == 0) {
        s = base;
      } else {
        final words = base.split(' ');
        for (var k = 0, n = 1 + r.nextInt(8); k < n; k++) {
          words.insert(
            r.nextInt(words.length + 1),
            atoms[r.nextInt(atoms.length)],
          );
        }
        s = r.nextInt(4) == 0 ? words.join() : words.join(' ');
      }
      final reference = _v54(s);
      expect(
        [for (final m in alcoholStopsForTest(s)) (m.start, m.end, m.kind)],
        reference,
        reason: '"$s"',
      );
      if (reference.isNotEmpty) {
        hits++;
      }
      for (final (start, end, kind) in reference) {
        final text = s.substring(start, end);
        final surface = RegExp(
          '(wire rack|paper towels?|paper bag|plate|cutting board|'
          r'carving board)$',
        ).hasMatch(text);
        final arm = text.startsWith('transfer') && kind == 'out'
            ? (surface ? 'place' : 'transfer')
            : text.startsWith('remove')
            ? 'remove'
            : text.startsWith('let') || text.startsWith('allow')
            ? 'let'
            : text.startsWith('place') || text.startsWith('stack')
            ? 'place'
            : kind;
        arms[arm] = (arms[arm] ?? 0) + 1;
      }
    }
    // Not vacuous: every greedy arm met, thousands of times.
    expect(hits, greaterThan(30000));
    for (final arm in ['transfer', 'place', 'remove', 'let']) {
      expect(arms[arm], greaterThan(1000), reason: '$arm: $arms');
    }
    // The cubic shapes, in one pass a length: v54's regex read one
    // 1,000-character sentence of these in ≈ 35 ms (Opus Run 066: 8× per
    // doubling), so 1,200 of them took ≈ 42 s; linear, each pass is
    // ≈ 1.2 MB of text.
    for (final unit in [
      'transfer sauce to ',
      'place to the ',
      'remove the pot ',
      'let it ',
    ]) {
      for (final (length, count) in const [
        (1000, 1200),
        (10000, 120),
        (100000, 12),
      ]) {
        final shape = unit * (length ~/ unit.length);
        final sw = Stopwatch()..start();
        for (var i = 0; i < count; i++) {
          alcoholStopsForTest(shape);
        }
        expect(
          sw.elapsedMilliseconds,
          lessThan(1000),
          reason: '"$unit" $length',
        );
      }
    }
  });

  test('F2: every alcohol reading answers as the memos off — each corpus '
      'line naming an alcohol on every alcohol record, in line order and '
      'reversed, on the real recipes and on a STATED copy of each with its '
      'alcohol lines tripled (the runs that share a later state read it '
      'once)', () {
    List<String> readAll(Recipe r, {bool reversed = false}) {
      final lines = nutritionLines(r);
      final ps = [
        for (var p = 0; p < lines.length; p++)
          if (_alcoholWord.hasMatch(lines[p].raw.toLowerCase())) p,
      ];
      final out = <String, String>{};
      for (final p in reversed ? ps.reversed : ps) {
        for (final id in alcoholRecords.keys) {
          final a = alcoholReadingOf(r, p, id);
          out['$p|$id'] = '${a.kept}|${a.code}|${a.rule}|${a.flag}';
        }
      }
      return [for (final k in out.keys.toList()..sort()) '$k ${out[k]}'];
    }

    Recipe tripled(Recipe r) => r.copyWith(
      ingredients: [
        IngredientGroup(
          items: [
            for (final l in nutritionLines(r))
              ...(_alcoholWord.hasMatch(l.raw.toLowerCase()) ? [l, l, l] : [l]),
          ],
        ),
      ],
    );

    var recipes = 0;
    var shared = 0;
    for (final f in [
      for (final f in Directory(corpusRecipesDir).listSync())
        f.uri.pathSegments.last,
    ]..sort()) {
      if (!f.endsWith('.yaml') ||
          !nutritionLines(
            loadCorpusRecipe(f),
          ).any((l) => _alcoholWord.hasMatch(l.raw.toLowerCase()))) {
        continue;
      }
      for (final make in [
        () => loadCorpusRecipe(f),
        () => tripled(loadCorpusRecipe(f)),
      ]) {
        memoOffForTest = true;
        final List<String> fresh;
        try {
          fresh = readAll(make());
        } finally {
          memoOffForTest = false;
        }
        stepIndexCounts.clear();
        expect(readAll(make()), fresh, reason: f);
        shared += stepIndexCounts['alcoholRunsShared'] ?? 0;
        expect(readAll(make(), reversed: true), fresh, reason: '$f reversed');
        recipes++;
      }
    }
    expect((recipes, shared), (530, 11996));
  }, timeout: const Timeout(Duration(minutes: 10)));

  test(
    'F7: a coating sentence sizes a coat from a vegetable only when it '
    "coats it WITH the coat (a coat line named): the fleet's 0254 copy "
    '(STATED: zucchini for the cod, an onion line and "Toss the onions '
    'with 1 tablespoon of the butter to coat …" appended) holds its coat '
    'as its control does; the onion rings and the eggplant unchanged',
    () async {
      final db = _db();
      final fdc = _fdc();
      final fish = loadCorpusRecipe('0254-crunchy-oven-fried-fish.yaml');
      Recipe probe({required bool onion}) {
        var k = 0;
        return fish.copyWith(
          id: '${fish.id}-v81-${onion ? 'onion' : 'control'}',
          slug: '${fish.slug}-v81-${onion ? 'onion' : 'control'}',
          ingredients: [
            for (final (gi, g) in fish.ingredients.indexed)
              IngredientGroup(
                group: g.group,
                items: [
                  for (final l in g.items)
                    if (k++ == 11)
                      _ln('1¼ pounds zucchini, cut into 4 pieces')
                    else
                      l,
                  if (onion && gi == fish.ingredients.length - 1)
                    _ln('2 large yellow onions, sliced thin'),
                ],
              ),
          ],
          steps: [
            ...fish.steps,
            RecipeStep(
              number: fish.steps.length + 1,
              text:
                  'Toss the onions with 1 tablespoon of the butter to coat and '
                  'scatter around the zucchini before baking.',
            ),
          ],
        );
      }

      final onion = await _compute(db, fdc, probe(onion: true));
      final control = await _compute(db, fdc, probe(onion: false));
      for (final position in [0, 5]) {
        final a = _row(db, onion.id, position);
        final b = _row(db, control.id, position);
        expect(
          (a.grams, a.gramSource, a.hold),
          (b.grams, b.gramSource, b.hold),
          reason: '|$position',
        );
      }
      expect(_row(db, onion.id, 0).hold, 'coating');
      final rings = await _compute(
        db,
        fdc,
        loadCorpusRecipe('0315-oven-fried-onion-rings.yaml'),
      );
      expect(
        [
          for (var p = 0; p < 8; p++)
            _row(db, rings.id, p).grams!.toStringAsFixed(2),
        ],
        // RE-PIN (M82 batch, v84, C5a): the flour |0 at 5 oz a cup (the v84
        // replay's row): was 60.33.
        ['70.87', '50.00', '122.00', '3.01', '0.58', '0.45', '90.00', '100.00'],
      );
      final eggplant = await _compute(
        db,
        fdc,
        loadCorpusRecipe('0407-eggplant-parmesan.yaml'),
      );
      expect(
        [
          for (final p in [2, 3, 5, 6])
            _row(db, eggplant.id, p).grams!.toStringAsFixed(2),
        ],
        // RE-PIN (M82 batch, v84, C1 + C5a): the coat parts re-solve on the
        // 45.36 g slice and the 5 oz flour (the v84 replay's rows): was 76.37,
        // 19.33, 41.14.
        // RE-PIN (M85 batch, v87): the Parmesan part on SR 170848 — the three
        // parts re-solve (the v87 replay's rows): was 88.21, 13.78, 34.46.
        ['89.79', '14.03', '35.07', '84.39'],
      );
    },
  );

  test("F8: a stock's aromatics strained out and discarded stay discarded "
      'when the soup re-adds the same vegetable — the strain reads only the '
      'mentions no line owns; the 6 rows of the v81 replay (each 0 g, '
      "strained), the soup's own lines counted, 0415's porcini (the shared "
      'tail after the strain) unchanged', () async {
    final db = _db();
    final fdc = _fdc();
    const strained =
        'discarded in cooking — counted as 0 g · approximate (strained out '
        'and discarded — what it gives the liquid is not counted)';
    for (final (file, discarded, counted) in [
      ('0002-classic-chicken-noodle-soup.yaml', [2], {7: '110.00'}),
      (
        '0002-hearty-chicken-noodle-soup.yaml',
        [2, 3, 4],
        <int, String>{},
      ),
      (
        '0230-roast-butterflied-leg-of-lamb-with-coriander-cumin-and-mustard-seeds.yaml',
        [3],
        <int, String>{},
      ),
      ('0517-thai-style-chicken-soup.yaml', [3], <int, String>{}),
      ('0415-better-chicken-marsala.yaml', <int>[], {2: '28.35'}),
    ]) {
      final recipe = await _compute(db, fdc, loadCorpusRecipe(file));
      for (final p in discarded) {
        final row = _row(db, recipe.id, p);
        expect(
          (row.grams, row.gramSource),
          (0.0, 'discarded'),
          reason: '$file|$p',
        );
        expect(
          gramBasisFor(db, nutritionLines(recipe)[p], row, recipe: recipe),
          strained,
          reason: '$file|$p',
        );
      }
      for (final MapEntry(key: p, value: grams) in counted.entries) {
        expect(
          _row(db, recipe.id, p).grams!.toStringAsFixed(2),
          grams,
          reason: '$file|$p',
        );
      }
    }
  });

  test('F12: a line cut fine WHOLE, the only line of its head, is removed by '
      "a discard naming its food — 0031's Garlic Croutons garlic, strained "
      'out of the oil and discarded ("Discard the garlic.") — while every '
      'gate keeps a cut line counted: a whole part printed (0018|4, 0103|6, '
      '0422|9, 0491|1, 0491|2), another line of its head (0481|18, 0103|14), a '
      'plus part (0346|2: its row is the 5 minced cloves, 15 g)', () async {
    DiscardedMedium? medium(Recipe r, int p) {
      final line = nutritionLines(r)[p];
      return discardedMediumOf(r, line, normalizeItem(lineItemOf(line)));
    }

    final gazpacho = loadCorpusRecipe('0031-classic-gazpacho.yaml');
    final croutons = sectionOf(
      gazpacho,
      sectionKeyOf(gazpacho.id, 'Garlic Croutons'),
    )!;
    expect(
      nutritionLines(croutons)[1].raw,
      '3 medium garlic cloves, minced or pressed through a garlic press '
      '(about 1 tablespoon)',
    );
    expect(medium(croutons, 1), DiscardedMedium.removedAromatic);
    for (final (file, p, raw) in [
      (
        '0018-wild-rice-and-mushroom-soup.yaml',
        4,
        '5 garlic cloves, peeled (1 whole, 4 minced)',
      ),
      (
        '0103-cuban-style-black-beans-and-rice.yaml',
        6,
        '1 head garlic, 5 medium cloves minced or pressed through a garlic press (about 5 teaspoons), remaining head halved at equator with skin left intact',
      ),
      (
        '0103-cuban-style-black-beans-and-rice.yaml',
        14,
        '2 scallions, sliced thin, for serving',
      ),
      (
        '0422-chicken-canzanese.yaml',
        9,
        '1 (4-inch) sprig fresh rosemary, leaves removed and minced fine (about ½ teaspoon), stem reserved',
      ),
      (
        '0481-carne-deshebrada-shredded-beef-tacos.yaml',
        18,
        '1 onion, sliced thin',
      ),
      (
        '0491-spicy-mexican-shredded-pork-tostadas.yaml',
        1,
        '2 medium onions, 1 quartered and 1 chopped fine',
      ),
      (
        '0491-spicy-mexican-shredded-pork-tostadas.yaml',
        2,
        '5 medium garlic cloves, 3 peeled and smashed and 2 minced or pressed through a garlic press (about 2 teaspoons)',
      ),
      (
        '0346-garlicky-shrimp-pasta.yaml',
        2,
        '5 medium garlic cloves, minced or pressed through a garlic press (about 5 teaspoons), plus 4 medium garlic cloves, smashed',
      ),
    ]) {
      final r = loadCorpusRecipe(file);
      expect(nutritionLines(r)[p].raw, raw, reason: '$file|$p');
      expect(medium(r, p), isNull, reason: '$file|$p');
    }
    final db = _db();
    final pasta = await _compute(
      db,
      _fdc(),
      loadCorpusRecipe('0346-garlicky-shrimp-pasta.yaml'),
    );
    final row = _row(db, pasta.id, 2);
    // RE-PIN (M82 batch, v84, C3a): the cloves' printed 5 teaspoons on SR
    // 169230 (the v84 replay's row): was 15.00, '5 × 3 g each'.
    expect(row.grams!.toStringAsFixed(2), '14.00');
    expect(
      gramBasisFor(db, nutritionLines(pasta)[2], row, recipe: pasta),
      '5 teaspoon · USDA portion of "Garlic, raw"',
    );
  });

  test('F4: the fried-food answer is per class — two classes in one recipe '
      'each read their own word (closer 1, verify1 D4 v06; STATED '
      'synthesized: 0241 with three real lines — a frying oil, a fries cut '
      'of russets, an eggplant cut — and a frying sentence naming the '
      "potatoes only): the oil takes the potatoes' uptake alone, in either "
      'line order', () async {
    final db = _db();
    final fdc = _fdc();
    const oil = '2 quarts vegetable oil for frying';
    const fries =
        '3 pounds russet potatoes (about 4 large potatoes), peeled, ends and '
        'sides squared off, and cut lengthwise into ½-inch by ½-inch fries';
    const eggplant = '1½ pounds eggplant, cut into ½-inch pieces';
    const steps = [
      'Fry the potatoes in the hot oil until golden, about 5 minutes.',
      'Sprinkle the eggplant with salt.',
    ];
    Future<String> oilGrams(String id, List<String> raws) async {
      final r = capped(loadCorpusRecipe(pork), raws, steps).copyWith(
        id: id,
        slug: id,
      );
      stepIndexCounts.clear();
      final computed = await _compute(db, fdc, r);
      expect(stepIndexCounts['memo:friedNamed'], raws.length - 1, reason: id);
      return _row(db, computed.id, 0).grams!.toStringAsFixed(2);
    }

    final alone = await oilGrams('v81-fry-alone', [oil, fries]);
    expect(alone, isNot('0.00'));
    expect(await oilGrams('v81-fry-first', [oil, fries, eggplant]), alone);
    expect(await oilGrams('v81-fry-second', [oil, eggplant, fries]), alone);
  });

  test("F13: whether a can is added with its liquid is per head — 0009's "
      'real tomatoes can (|12, never "and their liquid") and pinto beans can '
      '(|17, "beans and their liquid") each answer their own, in either '
      'order (closer 1, verify1 D4 v16)', () {
    final chili = loadCorpusRecipe('0009-best-ground-beef-chili.yaml');
    final lines = nutritionLines(chili);
    expect(lines[12].raw, '1 (14.5-ounce) can whole peeled tomatoes');
    expect(lines[17].raw, '1 (15-ounce) can pinto beans');
    for (final (k, order) in [
      [12, 17],
      [17, 12],
    ].indexed) {
      final r = chili.copyWith(id: '${chili.id}-v81-$k');
      final own = nutritionLines(r);
      expect(
        {
          for (final p in order) p: canLiquidEatenIn(r, own[p]),
        },
        {12: false, 17: true},
      );
    }
  });

  test('F12: the cut-whole arm keeps its gates (closer 1, verify1 D4) — a '
      'line ground or a paste is never removed by name (v14; STATED '
      "synthesized: 0031's Garlic Croutons with its garlic \"minced to a "
      "paste\"), and a cut line a bundle's tying sentence names is never a "
      "bundle's (v15; STATED synthesized: 0030's farmhouse soup with its "
      'thyme sprigs written minced; the real sprigs stay removed)', () {
    DiscardedMedium? medium(Recipe r, int p) {
      final line = nutritionLines(r)[p];
      return discardedMediumOf(r, line, normalizeItem(lineItemOf(line)));
    }

    Recipe withLine(Recipe r, int p, String raw) => r.copyWith(
      id: '${r.id}-v81-$p',
      ingredients: [
        for (final g in r.ingredients)
          IngredientGroup(
            group: g.group,
            items: [
              for (final l in g.items)
                if (identical(l, nutritionLines(r)[p])) _ln(raw) else l,
            ],
          ),
      ],
    );

    final gazpacho = loadCorpusRecipe('0031-classic-gazpacho.yaml');
    final croutons = sectionOf(
      gazpacho,
      sectionKeyOf(gazpacho.id, 'Garlic Croutons'),
    )!;
    expect(medium(croutons, 1), DiscardedMedium.removedAromatic);
    expect(
      medium(
        withLine(croutons, 1, '3 medium garlic cloves, minced to a paste'),
        1,
      ),
      isNull,
    );
    final soup = loadCorpusRecipe(
      '0030-farmhouse-vegetable-and-barley-soup.yaml',
    );
    expect(nutritionLines(soup)[2].raw, '4 sprigs fresh thyme');
    expect(medium(soup, 2), DiscardedMedium.removedAromatic);
    expect(
      medium(withLine(soup, 2, '1 tablespoon minced fresh thyme'), 2),
      isNull,
    );
  });

  test('F12: every whole-part word of the cut-whole gate keeps a cut line '
      "counted, each alone (closer 4, verify4 D1; STATED synthesized: 0031's "
      'Garlic Croutons with its real line 1 rewritten to print one whole part '
      "— no corpus line reaches the arm with one of them alone, verify4's "
      "media census): the croutons' \"Discard "
      'the garlic." never zeroes a line that keeps a part whole', () {
    DiscardedMedium? medium(Recipe r, int p) {
      final line = nutritionLines(r)[p];
      return discardedMediumOf(r, line, normalizeItem(lineItemOf(line)));
    }

    final gazpacho = loadCorpusRecipe('0031-classic-gazpacho.yaml');
    final croutons = sectionOf(
      gazpacho,
      sectionKeyOf(gazpacho.id, 'Garlic Croutons'),
    )!;
    final lines = nutritionLines(croutons);
    expect(medium(croutons, 1), DiscardedMedium.removedAromatic);
    expect(croutons.ingredients, hasLength(1));
    for (final (word, raw) in [
      ('crushed', '3 medium garlic cloves, 1 crushed and 2 minced'),
      ('halved', '3 medium garlic cloves, 1 halved and 2 minced'),
      ('halves', '4 medium garlic cloves, 2 minced and 2 cut into halves'),
      ('quarters', '4 medium garlic cloves, 1 minced and 3 cut into quarters'),
      ('remaining', '3 medium garlic cloves, 1 minced and the remaining 2'),
      ('reserved', '3 medium garlic cloves, 1 minced and 2 reserved'),
      ('stem', '3 medium garlic cloves, minced, green stem left on'),
      ('stems', '3 medium garlic cloves, minced, green stems left on'),
    ]) {
      final r = croutons.copyWith(
        id: '${croutons.id}-v81-$word',
        ingredients: [
          IngredientGroup(
            group: croutons.ingredients.first.group,
            items: [
              for (final (i, l) in lines.indexed) i == 1 ? _ln(raw) : l,
            ],
          ),
        ],
      );
      expect(medium(r, 1), isNull, reason: word);
    }
  });
}

/// F14: the bounded numerics (the Sonnet critic and survivor 9).
void numerics() {
  test('F14: the editor refuses a quantity printing a number of 10 or more '
      'digits (a 422), and the compute and the matches GET read the '
      "critic's hostile lines as unmeasured rows, never a crash (STATED "
      'synthesized lines on 0857)', () async {
    final (:db, :config) = _store();
    final cake = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
    db.upsertRecipe(
      cake,
      sourceSlug: _source,
      contentHash: contentHashOf(cake),
    );
    final stored = db.recipeByIdOrSlug(cake.id)!.recipe;
    Map<String, Object?> withLine(String raw) => {
      'ingredients': [
        IngredientGroup(items: [_ln(raw), ...nutritionLines(stored)]).toMap(),
      ],
    };
    expect(
      () => updateRecipe(
        db,
        config,
        stored.id,
        withLine('99999999999999999999 1/2 cups all-purpose flour'),
      ),
      throwsA(
        isA<ValidationException>().having((e) => e.message, 'message', _f14),
      ),
    );
    // The boundary (closer 1, verify1 D4 v17): ten digits refused, nine
    // accepted.
    expect(
      () => updateRecipe(
        db,
        config,
        stored.id,
        withLine('1000000000 cups sugar'),
      ),
      throwsA(
        isA<ValidationException>().having((e) => e.message, 'message', _f14),
      ),
    );
    updateRecipe(db, config, stored.id, withLine('999999999 cups sugar'));
    for (final raw in [
      '1 cup all-purpose flour (${'9' * 400} grams)',
      '${'9' * 400} cups all-purpose flour',
      '99999999999999999999 1/2 cups all-purpose flour',
      '18 medium-large shrimp (99999999999999999999 to 40 per pound)',
      '18 medium-large shrimp (0 to 0 per pound)',
      '3 (99999999999999999999-ml) bottles Chianti',
    ]) {
      final r = cake.copyWith(
        id: 'v81-${raw.hashCode}',
        slug: 'v81-${raw.hashCode}',
        ingredients: [
          IngredientGroup(items: [_ln(raw), ...nutritionLines(cake)]),
        ],
      );
      final fdc = FixtureProvider(
        pending: {...pendingSearches, 'shrimp', 'chianti'},
      );
      final computed = await _compute(db, fdc, r);
      jsonEncode(await matchesBody(db, fdc, computed));
      final row = _row(db, computed.id, 0);
      expect(row.grams == null || row.grams!.isFinite, isTrue, reason: raw);
    }
    // The alcohol reader's bottle count (Sonnet survivor 9): 0007's real
    // "1 (750-ml) bottle Chianti" read; its 20-digit count reads no volume.
    final tuscan = loadCorpusRecipe('0007-tuscan-style-beef-stew.yaml');
    final lines = nutritionLines(tuscan);
    expect(lines[3].raw, '1 (750-ml) bottle Chianti');
    expect(alcoholReadingOf(tuscan, 3, 2710688).kept, greaterThan(0));
    final hostile = tuscan.copyWith(
      ingredients: [
        IngredientGroup(
          items: [
            for (final (i, l) in lines.indexed)
              i == 3 ? _ln('99999999999999999999 (750-ml) bottles Chianti') : l,
          ],
        ),
      ],
    );
    expect(alcoholReadingOf(hostile, 3, 2710688).kept, greaterThan(0));
  });

  test("F14's refusal reads as API.md quotes it (closer 5, verify5 D2) — a "
      "subsection's line through the editor, the import and the library "
      "rescan (STATED synthesized: 0031's real Garlic Croutons line 0 with "
      'its quantity written 1000000000): the 422 "$_f14", the import counts '
      'the file failed, the rescan skips it with reason "fails validation: '
      '$_f14" and keeps the stored version', () {
    final dir = Directory.systemTemp.createTempSync('salt-v81-f14-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final config = ServerConfig(
      dataDir: '${dir.path}/data',
      logLevel: Level.WARNING,
      trustProxy: false,
    );
    Directory(config.dataDir).createSync(recursive: true);
    final db = SaltDatabase.open(config.dbPath);
    addTearDown(db.dispose);
    final gazpacho = loadCorpusRecipe('0031-classic-gazpacho.yaml');
    String croutonQuantity(Recipe r) => r.subsections
        .firstWhere((sub) => sub.title == 'Garlic Croutons')
        .ingredients!
        .first
        .items
        .first
        .amounts
        .first
        .quantity;
    Recipe hostile(Recipe r) => r.copyWith(
      subsections: [
        for (final sub in r.subsections)
          sub.title != 'Garlic Croutons'
              ? sub
              : sub.copyWith(
                  ingredients: [
                    for (final (i, g) in sub.ingredients!.indexed)
                      i != 0
                          ? g
                          : IngredientGroup(
                              group: g.group,
                              items: [
                                for (final (j, l) in g.items.indexed)
                                  j != 0
                                      ? l
                                      : l.copyWith(
                                          amounts: [
                                            for (final (k, a)
                                                in l.amounts.indexed)
                                              k == 0
                                                  ? a.copyWith(
                                                      quantity: '1000000000',
                                                    )
                                                  : a,
                                          ],
                                        ),
                              ],
                            ),
                  ],
                ),
      ],
    );
    expect(croutonQuantity(gazpacho), '3');
    expect(croutonQuantity(hostile(gazpacho)), '1000000000');
    final src = Directory('${dir.path}/src/recipes')
      ..createSync(recursive: true);
    File('$corpusRoot/source.yaml').copySync('${dir.path}/src/source.yaml');
    final file = File('${src.path}/0031-classic-gazpacho.yaml')
      ..writeAsStringSync(RecipeYamlCodec.encode(hostile(gazpacho)));
    var summary = importSourceRoot(
      sourceRootPath: '${dir.path}/src',
      db: db,
      config: config,
    );
    expect((summary.imported, summary.failed), (0, 1));
    expect(summary.warnings, [
      '0031-classic-gazpacho.yaml: AppException(422 validation): $_f14',
    ]);
    file.writeAsStringSync(RecipeYamlCodec.encode(gazpacho));
    summary = importSourceRoot(
      sourceRootPath: '${dir.path}/src',
      db: db,
      config: config,
    );
    expect((summary.imported, summary.failed), (1, 0));
    final stored = db.recipeByIdOrSlug(gazpacho.id)!.recipe;
    Directory(config.libraryDir)
        .listSync(recursive: true)
        .whereType<File>()
        .singleWhere((f) => f.path.endsWith('-0031-classic-gazpacho.yaml'))
        .writeAsStringSync(RecipeYamlCodec.encode(hostile(stored)));
    final report = scanLibrary(db: db, config: config);
    expect(
      [for (final s in report.skipped) s.reason],
      [
        'fails validation: $_f14',
      ],
    );
    expect(report.updatedFromDisk, isEmpty);
    expect(croutonQuantity(db.recipeByIdOrSlug(gazpacho.id)!.recipe), '3');
    expect(
      () => updateRecipe(db, config, gazpacho.id, {
        'subsections': [
          for (final sub in hostile(stored).subsections) sub.toMap(),
        ],
      }),
      throwsA(
        isA<ValidationException>().having((e) => e.message, 'message', _f14),
      ),
    );
    expect(croutonQuantity(db.recipeByIdOrSlug(gazpacho.id)!.recipe), '3');
  });
}

/// F14's 422 message as API.md quotes it (closer 5, verify5 D2).
const _f14 = "'amount quantity' must print numbers of at most 9 digits.";

/// The cap shapes (STATED synthesized: a real corpus line repeated to the
/// 400-line cap, filler steps at 120 × 10,000 characters — the house's
/// cap-shape exception), each read by the compute, the matches GET and the
/// recompute: every family within its bound, the readers' counts pinned
/// EXACTLY (the maps below), each path under the backstop. A QUIET shape (the
/// reader's predicate never true) and a TRUE one per reader.
void costShapes() {
  Future<({Map<String, Map<String, int?>> seen, SaltDatabase db})> shape(
    String name,
    Recipe r,
    List<String> families, {
    NutritionProvider? fdc,
    bool fresh = false,
    List<Recipe> library = const [],
  }) async {
    final db = wp.tempDb();
    final provider = fdc ?? FixtureProvider(pending: pendingSearches);
    for (final l in library) {
      wp.saveRecipe(db, l);
    }
    wp.saveRecipe(db, r);
    Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
    final seen = <String, Map<String, int?>>{};
    for (final (step, run) in <(String, Future<Object?> Function())>[
      ('compute', () => matchAndCompute(db, provider, stored())),
      ('GET', () => matchesBody(db, provider, stored())),
      ('recompute', () async => recomputeTotals(db, stored())),
      // closer 2 (verify2 D1): the recipe nutrition GET — one freshness
      // check, member-readable.
      if (fresh)
        (
          'nutrition GET',
          () async => nutritionBody(db, stored(), forAdmin: false),
        ),
    ]) {
      stepIndexCounts.clear();
      reachDecodes = 0;
      m52PlanRuns = 0;
      final sw = Stopwatch()..start();
      await run();
      final ms = sw.elapsedMilliseconds;
      final counts = Map.of(stepIndexCounts);
      expectBounded(r, counts, '$name $step', copies: counts['indexes'] ?? 1);
      expect(ms, lessThan(backstopMs), reason: '$name $step: $counts');
      seen[step] = {for (final f in families) f: counts[f]};
    }
    return (seen: seen, db: db);
  }

  const wine = '2¼ cups dry white wine';
  for (final (name, steps) in [
    // The Opus shape: the wine named in every sentence — 400 runs, each
    // from its own use (the k-th line reads the k-th), sharing what follows
    // the first step boundary.
    (
      'ALCOHOL TRUE',
      List.filled(
        capSteps,
        fill('Add wine and simmer for 20 minutes. ', capStep),
      ),
    ),
    // The Sonnet shape: named once, then heat text — 400 runs from one use.
    (
      'ALCOHOL ONCE',
      [
        'Add the wine to the pot.',
        ...List.filled(
          capSteps - 1,
          fill('Stir and simmer the sauce for 10 minutes. ', capStep),
        ),
      ],
    ),
    // QUIET: the wine never named (the reader's fallback, no run).
    (
      'ALCOHOL QUIET',
      List.filled(
        capSteps,
        fill('Add stock and simmer for 20 minutes. ', capStep),
      ),
    ),
  ]) {
    test('$name: 400 lines "$wine" (0007\'s real line) under 120 × '
        '10,000-character steps: the texts and the recipe read once per '
        'index, the runs counted exactly', () async {
      final r = capped(
        loadCorpusRecipe('0007-alcatra-portuguese-style-beef-stew.yaml'),
        List.filled(400, wine),
        steps,
      );
      final (:seen, :db) = await shape(name, r, _alcoholFamilies);
      expect(seen, _alcoholCounts[name], reason: name);
      // The predicate's answer: the TRUE runs cook the wine (5 %), QUIET's
      // never named it (100 %, no reduction).
      expect(
        alcoholReadingOf(r, 399, 2710689).kept,
        name == 'ALCOHOL QUIET' ? 100 : 5,
      );
      expect(db.ingredientMatchesFor(r.id), hasLength(400));
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  // closer 1 (verify1 D1): lines whose trails differ — each line printing
  // its own word (STATED synthesized: 0007's wine as a bottle count, a
  // unique made-up word before it; every search answered as "dry white
  // wine"'s, [_WineAs]). UNIQUE: the steps never print those words — each
  // line's vocabulary narrowed to the sentences' words is one, and the
  // runs share as ALCOHOL TRUE's (v81 before: 13,264,077 run sentences, 0
  // shared, 10.9 s a compute). OWN-NAMED: a last step prints them all — no
  // two lines read one vocabulary, no run shares: the RESIDUAL, count-pinned
  // here on 120 steps of a tenth of the cap's characters (it scales with
  // lines × sentences: at the caps 13,312,877 run sentences, 10.5 / 10.2 /
  // 9.9 s, max RSS 1.0 GB against UNIQUE's 0.41 GB).
  for (final (name, chars, named) in [
    ('ALCOHOL UNIQUE', capStep, false),
    ('ALCOHOL OWN-NAMED', capStep ~/ 10, true),
  ]) {
    test('$name: 400 lines "1 (750-ml) bottle <own word> dry white wine" '
        'under 120 steps of "Add wine and simmer for 20 minutes." '
        '(${named ? 'the words printed last' : 'the words never printed'}): '
        'the runs counted exactly', () async {
      final words = [for (var i = 0; i < 400; i++) _uniqueWord(i)];
      final r = capped(
        loadCorpusRecipe('0007-alcatra-portuguese-style-beef-stew.yaml'),
        [for (final w in words) '1 (750-ml) bottle $w dry white wine'],
        [
          ...List.filled(
            named ? capSteps - 1 : capSteps,
            fill('Add wine and simmer for 20 minutes. ', chars),
          ),
          if (named) [for (final w in words) 'Garnish with the $w.'].join(' '),
        ],
      );
      final (:seen, :db) = await shape(
        name,
        r,
        _alcoholFamilies,
        fdc: _WineAs(_fdc()),
      );
      expect(seen, _alcoholCounts[name], reason: name);
      expect(alcoholReadingOf(r, 399, 2710689).kept, 5);
      expect(
        {for (final m in db.ingredientMatchesFor(r.id)) m.fdcId},
        {2710689},
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  // closer 1 (verify1 D3) / closer 2 (verify2 D1): the hash gate on the
  // editor caps (STATED synthesized steps: 119 of a hostile text and
  // 0790's real kept-cooked sentence) — "Transfer 1 cup (warm " (v81's
  // first gate scanned every unclosed "(" to the step's end, 9.8 s a hash)
  // and "transfer 1" + 50 spaces (closer 1's linear scan backtracked the
  // amount run, 733 ms a hash and a recipe nutrition GET 13–19 → 729–746
  // ms). The gate reads the NOTE alone: TRUE and SPACES (0790's real lines
  // and note, "packed cup (½ pound)") fold it once per hash
  // (`prepNoteFolds`) on every path — the recipe nutrition GET's one
  // freshness check too; QUIET (0857's real lines and note, no "cup (")
  // never.
  for (final (name, file, filler) in [
    ('PREP NOTE TRUE', '0790-potato-burger-buns.yaml', 'Transfer 1 cup (warm '),
    (
      'PREP NOTE SPACES',
      '0790-potato-burger-buns.yaml',
      'transfer 1${' ' * 50}',
    ),
    (
      'PREP NOTE QUIET',
      '0857-rich-chocolate-bundt-cake.yaml',
      'Transfer 1 cup (warm ',
    ),
  ]) {
    test("$name: $file's real lines and note under 119 × 10,000 characters "
        "of a hostile text and 0790's kept-cooked sentence: the hash gate "
        'reads no step, its folds counted exactly on every path', () async {
      final base = loadCorpusRecipe(file);
      final r = capped(
        base,
        [for (final l in nutritionLines(base)) l.raw],
        [
          ...List.filled(capSteps - 1, fill(filler, capStep)),
          'Measure 1 very firmly packed cup potatoes and transfer to bowl.',
        ],
      );
      final (:seen, :db) = await shape(name, r, [
        'indexes',
        'prepNoteFolds',
      ], fresh: true);
      expect(seen, _prepNoteCounts[name], reason: name);
      final memo = ResolverMemo(db);
      final edited = r.copyWith(prepNotes: '${r.prepNotes} Serve warm.');
      expect(
        ingredientsHashOf(edited, memo) != ingredientsHashOf(r, memo),
        name != 'PREP NOTE QUIET',
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  // closer 2 (verify2 D3, F7): v80's v26 ONION shape (0315's real lines,
  // 390 more "<n> large yellow onions, cut into 24 large rings", 110 steps
  // of "Slice the onions." before its own) — the coat-line sentences read
  // each line's medium by the coat arms ALONE (`discardedMediumOf`'s
  // `coatOnly`): the recompute never runs the oil, set-aside or bundle
  // passes (F7 as first built asked the whole detector of every line:
  // reservedUse / fryVerbAt / bundles / oilOwners 0 → 1, setAsideLine 3 →
  // 4, foodNaming 1 → 2, +62 %). MEASURED = base (cae00d4) on every family
  // but `memo:coatLineSentences` (1, the reader itself) and the GET's
  // `memo:named` (8 → 9: the flour's naming, read once).
  test("ONION (v80's v26 shape): the coat-line sentences read the coat arms "
      'alone — every other family as at v80', () async {
    final base = loadCorpusRecipe('0315-oven-fried-onion-rings.yaml');
    final own = [for (final g in base.ingredients) ...g.items];
    expect(own, hasLength(10));
    final r = capped(
      base,
      [
        for (final l in own) l.raw,
        for (var n = 3; own.length + n - 3 < 400; n++)
          '$n large yellow onions, cut into 24 large rings',
      ],
      [
        for (var i = base.steps.length; i < capSteps; i++)
          fill('Slice the onions. ', capStep),
        for (final s in base.steps) s.text,
      ],
    );
    final (:seen, db: _) = await shape('ONION', r, _onionFamilies);
    expect(seen, _onionCounts);
  }, timeout: const Timeout(Duration(minutes: 5)));

  // closer 2 (verify2 D3, F12): v26's long-lines shape (400 distinct "1 cup
  // <food>, finely chopped and set aside …" lines, 120 steps "Stir the
  // garlic into the sauce.") — a line cut whole reaches the by-name scan
  // only where a discard clause names its head: none here, so no head's
  // naming and no bundle is read (F12 as first built: memo:foodNaming 0 →
  // 15, memo:bundles 0 → 1, +14 % end to end). MEASURED = base.
  test('long-lines (v26): a cut line no discard clause names reads no '
      'mention — the by-name scan and the bundle as at v80', () {
    final r = v26.shapes['long-lines']!();
    stepIndexCounts.clear();
    v25.readAll(r);
    expect(
      {
        for (final f in ['memo:discards', 'memo:foodNaming', 'memo:bundles'])
          f: stepIndexCounts[f],
      },
      {'memo:discards': 1, 'memo:foodNaming': null, 'memo:bundles': null},
    );
  });

  for (final (name, filler) in [
    // The Opus shape: the potatoes named, never with a fry verb or the oil.
    ('FRY QUIET', 'Peel the potatoes. Fry in the hot oil. '),
    ('FRY TRUE', 'Fry the potatoes in the hot oil. '),
  ]) {
    test('$name: an oil line and 399 counted potato lines under 120 × '
        '10,000-character steps of "$filler": the fried-food scan once per '
        'word and index (`memo:friedNamed`)', () async {
      final r = capped(
        loadCorpusRecipe(pork),
        [
          '2 quarts vegetable oil for frying',
          for (var i = 0; i < 399; i++) '2 pounds russet potatoes',
        ],
        List.filled(capSteps, fill(filler, capStep)),
      );
      final (:seen, :db) = await shape(name, r, [
        'indexes',
        'memo:friedNamed',
      ]);
      expect(seen, _friedCounts[name], reason: name);
      // The predicate's answer: TRUE fries the potatoes (the oil takes
      // their uptake), QUIET never does.
      expect(
        db.ingredientMatchesFor(r.id).first.grams!.toStringAsFixed(2),
        _friedOil[name],
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  for (final (name, filler) in [
    ('ZEST QUIET', 'Stir the mixture. '),
    ('ZEST TRUE', 'Stir the lemon zest mixture and strain it. '),
  ]) {
    test("$name: 400 lines of 0142's real zest-plus-juice line under 120 × "
        '10,000-character steps: whether the steps strain the zest read '
        'once per index (`memo:zestStrained`)', () async {
      final r = capped(
        loadCorpusRecipe(pork),
        List.filled(
          400,
          '4 teaspoons grated lemon zest plus ¼ cup juice (2 lemons)',
        ),
        List.filled(capSteps, fill(filler, capStep)),
      );
      final (:seen, db: _) = await shape(name, r, [
        'indexes',
        'memo:zestStrained',
      ]);
      expect(seen, _zestCounts[name], reason: name);
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  for (final (name, filler) in [
    ('CAN QUIET', 'Stir the mixture. '),
    ('CAN TRUE', 'Stir the chickpeas and their liquid into the pot. '),
  ]) {
    test("$name: 400 lines of 1075's real can line under 120 × "
        "10,000-character steps: whether a can's head is added with its "
        'liquid read once per head and index (`memo:canLiquid`)', () async {
      final can = nutritionLines(
        loadCorpusRecipe(
          '1075-espinacas-con-garbanzos-andalusian-spinach-and-chickpeas.yaml',
        ),
      )[1].raw;
      final r = capped(
        loadCorpusRecipe(pork),
        List.filled(400, can),
        List.filled(capSteps, fill(filler, capStep)),
      );
      final (:seen, db: _) = await shape(name, r, [
        'indexes',
        'memo:canLiquid',
      ]);
      expect(seen, _canCounts[name], reason: name);
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  test("PROSE (closer 5, verify5 D3): 400 lines of lemon-meringue-pie's "
      'real line 0 — its prose "Single-Crust Pie Dough for Custard Pies" '
      "(this page), which rule PV routes to 0972's Basic Single-Crust Pie "
      "Dough — beside real 0972, on lemon's real steps: every hash reads PV's "
      'choice of base once per prose section (`proseChoices`), each line '
      'only its own share of it (`proseShares`, the residual)', () async {
    final lemon = loadCorpusRecipe('0989-lemon-meringue-pie.yaml');
    final line0 = nutritionLines(lemon)[0].raw;
    expect(
      line0,
      startsWith('1 recipe Single-Crust Pie Dough for Custard Pies'),
    );
    final r = capped(lemon, List.filled(400, line0), [
      for (final step in lemon.steps) step.text,
    ]);
    final (:seen, :db) = await shape(
      'PROSE',
      r,
      ['indexes', 'proseChoices', 'proseShares'],
      fresh: true,
      library: [loadCorpusRecipe('0972-basic-double-crust-pie-dough.yaml')],
    );
    expect(seen, _proseCounts, reason: 'PROSE');
    final rows = db.ingredientMatchesFor(r.id);
    expect(rows, hasLength(400));
    expect(
      {for (final row in rows) row.childRecipeId},
      {
        sectionKeyOf(
          loadCorpusRecipe('0972-basic-double-crust-pie-dough.yaml').id,
          'Basic Single-Crust Pie Dough',
        ),
      },
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// MEASURED on this tree (closer 5): PV's choice once per prose section and
/// hash, each line's share once per hash (the residual) — the compute hashes
/// twice, the recompute once, the nutrition GET three times (its freshness
/// checks), the matches GET never. Before closer 5 every hash read the
/// choice per line (+81 % a hash at this shape).
const Map<String, Map<String, int?>> _proseCounts = {
  'compute': {'indexes': 1, 'proseChoices': 2, 'proseShares': 800},
  'GET': {'indexes': 1, 'proseChoices': null, 'proseShares': null},
  'recompute': {'indexes': 1, 'proseChoices': 1, 'proseShares': 400},
  'nutrition GET': {'indexes': null, 'proseChoices': 3, 'proseShares': 1200},
};

const _alcoholFamilies = [
  'indexes',
  'memo:alcoholTexts',
  'memo:alcoholRecipe',
  'alcoholTexts',
  'alcoholRecipeReads',
  'alcoholRunsShared',
  'alcoholRunSentences',
  'memo:alcohol',
];

/// MEASURED on this tree (the residual the run memo leaves, count-pinned).
const Map<String, Map<String, Map<String, int?>>> _alcoholCounts = {
  // 400 runs: the first reads every sentence (32,400 filler + 1); each
  // later one reads to its first step boundary and takes the rest (399
  // shared) — v54 read 400 × the text (≈ 13 million sentence reads).
  'ALCOHOL TRUE': {
    'compute': {
      'indexes': 1,
      'memo:alcoholTexts': 1,
      'memo:alcoholRecipe': 1,
      'alcoholTexts': 3,
      'alcoholRecipeReads': 7,
      'alcoholRunsShared': 399,
      'alcoholRunSentences': 98553,
      'memo:alcohol': 400,
    },
    'GET': {
      'indexes': 1,
      'memo:alcoholTexts': 1,
      'memo:alcoholRecipe': 1,
      'alcoholTexts': 3,
      'alcoholRecipeReads': 7,
      'alcoholRunsShared': 399,
      'alcoholRunSentences': 98553,
      'memo:alcohol': 400,
    },
    'recompute': {
      'indexes': 1,
      'memo:alcoholTexts': 1,
      'memo:alcoholRecipe': 1,
      'alcoholTexts': 3,
      'alcoholRecipeReads': 7,
      'alcoholRunsShared': 399,
      'alcoholRunSentences': 98553,
      'memo:alcohol': 400,
    },
  },
  // 400 runs from one use: the first reads every sentence, the others to
  // the first boundary.
  'ALCOHOL ONCE': {
    'compute': {
      'indexes': 1,
      'memo:alcoholTexts': 1,
      'memo:alcoholRecipe': 1,
      'alcoholTexts': 4,
      'alcoholRecipeReads': 7,
      'alcoholRunsShared': 399,
      'alcoholRunSentences': 28841,
      'memo:alcohol': 400,
    },
    'GET': {
      'indexes': 1,
      'memo:alcoholTexts': 1,
      'memo:alcoholRecipe': 1,
      'alcoholTexts': 4,
      'alcoholRecipeReads': 7,
      'alcoholRunsShared': 399,
      'alcoholRunSentences': 28841,
      'memo:alcohol': 400,
    },
    'recompute': {
      'indexes': 1,
      'memo:alcoholTexts': 1,
      'memo:alcoholRecipe': 1,
      'alcoholTexts': 4,
      'alcoholRecipeReads': 7,
      'alcoholRunsShared': 399,
      'alcoholRunSentences': 28841,
      'memo:alcohol': 400,
    },
  },
  // closer 1 (verify1 D1): 400 lines each printing its own word, never in
  // the steps — one narrowed vocabulary, ALCOHOL TRUE's counts exactly.
  'ALCOHOL UNIQUE': {
    'compute': {
      'indexes': 1,
      'memo:alcoholTexts': 1,
      'memo:alcoholRecipe': 1,
      'alcoholTexts': 3,
      'alcoholRecipeReads': 7,
      'alcoholRunsShared': 399,
      'alcoholRunSentences': 98553,
      'memo:alcohol': 400,
    },
    'GET': {
      'indexes': 1,
      'memo:alcoholTexts': 1,
      'memo:alcoholRecipe': 1,
      'alcoholTexts': 3,
      'alcoholRecipeReads': 7,
      'alcoholRunsShared': 399,
      'alcoholRunSentences': 98553,
      'memo:alcohol': 400,
    },
    'recompute': {
      'indexes': 1,
      'memo:alcoholTexts': 1,
      'memo:alcoholRecipe': 1,
      'alcoholTexts': 3,
      'alcoholRecipeReads': 7,
      'alcoholRunsShared': 399,
      'alcoholRunSentences': 98553,
      'memo:alcohol': 400,
    },
  },
  // The RESIDUAL: every line's own word printed (a last step of 400
  // "Garnish with the <word>." sentences) — no two narrowed vocabularies
  // meet, no run shares: each reads from its use to the end. On 120 steps
  // of 1,000 characters (at the caps: 13,312,877 run sentences, as v81
  // before the narrowing on the UNIQUE shape).
  'ALCOHOL OWN-NAMED': {
    'compute': {
      'indexes': 1,
      'memo:alcoholTexts': 1,
      'memo:alcoholRecipe': 1,
      'alcoholTexts': 403,
      'alcoholRecipeReads': 7,
      'alcoholRunsShared': null,
      'alcoholRunSentences': 1410235,
      'memo:alcohol': 400,
    },
    'GET': {
      'indexes': 1,
      'memo:alcoholTexts': 1,
      'memo:alcoholRecipe': 1,
      'alcoholTexts': 403,
      'alcoholRecipeReads': 7,
      'alcoholRunsShared': null,
      'alcoholRunSentences': 1410235,
      'memo:alcohol': 400,
    },
    'recompute': {
      'indexes': 1,
      'memo:alcoholTexts': 1,
      'memo:alcoholRecipe': 1,
      'alcoholTexts': 403,
      'alcoholRecipeReads': 7,
      'alcoholRunsShared': null,
      'alcoholRunSentences': 1410235,
      'memo:alcohol': 400,
    },
  },
  // The wine never named: no run.
  'ALCOHOL QUIET': {
    'compute': {
      'indexes': 1,
      'memo:alcoholTexts': 1,
      'memo:alcoholRecipe': 1,
      'alcoholTexts': 2,
      'alcoholRecipeReads': 2,
      'alcoholRunsShared': null,
      'alcoholRunSentences': null,
      'memo:alcohol': 400,
    },
    'GET': {
      'indexes': 1,
      'memo:alcoholTexts': 1,
      'memo:alcoholRecipe': 1,
      'alcoholTexts': 2,
      'alcoholRecipeReads': 2,
      'alcoholRunsShared': null,
      'alcoholRunSentences': null,
      'memo:alcohol': 400,
    },
    'recompute': {
      'indexes': 1,
      'memo:alcoholTexts': 1,
      'memo:alcoholRecipe': 1,
      'alcoholTexts': 2,
      'alcoholRecipeReads': 2,
      'alcoholRunsShared': null,
      'alcoholRunSentences': null,
      'memo:alcohol': 400,
    },
  },
};
const Map<String, Map<String, Map<String, int?>>> _friedCounts = {
  'FRY QUIET': {
    'compute': {'indexes': 1, 'memo:friedNamed': 1},
    'GET': {'indexes': 1, 'memo:friedNamed': 1},
    'recompute': {'indexes': 1, 'memo:friedNamed': 1},
  },
  'FRY TRUE': {
    'compute': {'indexes': 1, 'memo:friedNamed': 1},
    'GET': {'indexes': 1, 'memo:friedNamed': 1},
    'recompute': {'indexes': 1, 'memo:friedNamed': 1},
  },
};

/// The oil line's grams in each fry shape (measured).
const Map<String, String> _friedOil = {
  'FRY QUIET': '0.00',
  'FRY TRUE': '1741.29',
};
const Map<String, Map<String, Map<String, int?>>> _zestCounts = {
  // The recompute weighs no line (its rows are stored): no read.
  'ZEST QUIET': {
    'compute': {'indexes': 1, 'memo:zestStrained': 1},
    'GET': {'indexes': 1, 'memo:zestStrained': 1},
    'recompute': {'indexes': 1, 'memo:zestStrained': null},
  },
  'ZEST TRUE': {
    'compute': {'indexes': 1, 'memo:zestStrained': 1},
    'GET': {'indexes': 1, 'memo:zestStrained': 1},
    'recompute': {'indexes': 1, 'memo:zestStrained': null},
  },
};
const Map<String, Map<String, Map<String, int?>>> _canCounts = {
  'CAN QUIET': {
    'compute': {'indexes': 1, 'memo:canLiquid': 1},
    'GET': {'indexes': 1, 'memo:canLiquid': 1},
    'recompute': {'indexes': 1, 'memo:canLiquid': null},
  },
  'CAN TRUE': {
    'compute': {'indexes': 1, 'memo:canLiquid': 1},
    'GET': {'indexes': 1, 'memo:canLiquid': 1},
    'recompute': {'indexes': 1, 'memo:canLiquid': null},
  },
};

/// A made-up word, unique per [i] (closer 1's alcohol shapes).
String _uniqueWord(int i) {
  const a = 'bcdfghjklmnpqrstvwxz';
  return 'q${a[i % 20]}${a[(i ~/ 20) % 20]}${a[(i ~/ 400) % 20]}x';
}

/// Answers a search no fixture records with "dry white wine"'s (closer 1:
/// the alcohol shapes' made-up words; every line is that wine).
class _WineAs implements NutritionProvider {
  _WineAs(this.f);
  final FixtureProvider f;
  @override
  Future<List<FdcCandidate>> search(String query) async {
    try {
      return await f.search(query);
    } on Object {
      return f.search('dry white wine');
    }
  }

  @override
  Future<FdcFood?> food(int fdcId) => f.food(fdcId);
}

/// MEASURED on this tree (closer 2): the hash gate's folds — the note read
/// by its own text, no step scanned (closer 1's `prepNoteScans` is gone).
const Map<String, Map<String, Map<String, int?>>> _prepNoteCounts = {
  // The compute hashes twice (its inputs, its stamp), the recompute once
  // (the stamp kept), the recipe nutrition GET once (its freshness check);
  // the matches GET hashes none.
  'PREP NOTE TRUE': _prepNoteFolded,
  'PREP NOTE SPACES': _prepNoteFolded,
  'PREP NOTE QUIET': {
    'compute': {'indexes': 1, 'prepNoteFolds': null},
    'GET': {'indexes': 1, 'prepNoteFolds': null},
    'recompute': {'indexes': 1, 'prepNoteFolds': null},
    'nutrition GET': {'indexes': null, 'prepNoteFolds': null},
  },
};
const Map<String, Map<String, int?>> _prepNoteFolded = {
  'compute': {'indexes': 1, 'prepNoteFolds': 2},
  'GET': {'indexes': 1, 'prepNoteFolds': null},
  'recompute': {'indexes': 1, 'prepNoteFolds': 1},
  'nutrition GET': {'indexes': null, 'prepNoteFolds': 1},
};

/// The families closer 2's ONION shape pins (verify2 D3).
const List<String> _onionFamilies = [
  'memo:coatLineSentences',
  'memo:named',
  'memo:reservedUse',
  'memo:fryVerbAt',
  'memo:bundles',
  'memo:oilOwners',
  'memo:setAsideLine',
  'memo:foodNaming',
];

/// MEASURED on this tree (closer 2) — base's counts on every family but
/// the reader's own and the GET's one more naming.
const Map<String, Map<String, int?>> _onionCounts = {
  'compute': {
    'memo:coatLineSentences': 1,
    'memo:named': 12,
    'memo:reservedUse': 1,
    'memo:fryVerbAt': 1,
    'memo:bundles': 1,
    'memo:oilOwners': 1,
    'memo:setAsideLine': 4,
    'memo:foodNaming': 2,
  },
  'GET': {
    'memo:coatLineSentences': 1,
    'memo:named': 9,
    'memo:reservedUse': 1,
    'memo:fryVerbAt': 1,
    'memo:bundles': 1,
    'memo:oilOwners': 1,
    'memo:setAsideLine': 4,
    'memo:foodNaming': 2,
  },
  'recompute': {
    'memo:coatLineSentences': 1,
    'memo:named': 9,
    'memo:reservedUse': null,
    'memo:fryVerbAt': null,
    'memo:bundles': null,
    'memo:oilOwners': null,
    'memo:setAsideLine': 3,
    'memo:foodNaming': 1,
  },
};
