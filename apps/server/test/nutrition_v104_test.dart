// Matcher v104 (batch fix104 at the base 9836d4e; matcherVersion 96 → 97) —
// the fixes of dual-fleet review Run 077/078 over v98–v103, union U1–U25
// (.claude/diag/2026-11-06/review077/union_R.md; the rulings in
// fix104/brief.md). Every pin is a real corpus recipe through the real
// compute / PUT on the recorded fixtures or a snapshot-32 record; each
// STATED synthesized input names its exception and its corpus source.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'nutrition_v25_cost_test.dart' show fill;
import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_cost_test.dart' show capLines, capStep, capSteps, capped;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'nutrition_v28_rule_a_test.dart' as v28;
import 'nutrition_v29_rule_a_test.dart' as v29;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _nachos = '0471-cheesy-nachos-with-guacamole-and-salsa.yaml';
const _guac = '0472-chunky-guacamole.yaml';
const _carnitas = '0492-carnitas-mexican-pulled-pork.yaml';
const _bulalo = '1171-bulalo-hearty-beef-shank-and-vegetable-soup.yaml';
const _herb = '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml';

final _fx = FixtureProvider(pending: pendingSearches);

({SaltDatabase db, ServerConfig config}) _open() {
  final dir = Directory.systemTemp.createTempSync('salt-v104-');
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

SaltDatabase _db() => _open().db;

Recipe _store(SaltDatabase db, Recipe r) {
  db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

/// [r] stored and computed (its section children first); the stored copy.
Future<Recipe> _compute(
  SaltDatabase db,
  NutritionProvider fdc,
  Recipe r,
) async {
  final stored = _store(db, r);
  for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
    expect(
      await matchAndCompute(db, fdc, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }
  expect(await matchAndCompute(db, fdc, stored), isNull);
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

Recipe _rec(SaltDatabase db, String id) => nutritionRecipeOf(db, id)!.recipe;

IngredientMatchRow _row(SaltDatabase db, String id, int position) =>
    db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

/// [r] with its main line [position]'s raw text replaced and its amounts
/// set to [amounts].
Recipe _withLine(Recipe r, int position, String raw, List<Amount> amounts) {
  var at = 0;
  return r.copyWith(
    ingredients: [
      for (final g in r.ingredients)
        g.copyWith(
          items: [
            for (final l in g.items)
              (at++ == position) ? l.copyWith(raw: raw, amounts: amounts) : l,
          ],
        ),
    ],
  );
}

Future<Map<String, Object?>> _child(
  SaltDatabase db,
  NutritionProvider fdc,
  String id,
  int at,
) async {
  final body = await matchesBody(db, fdc, _rec(db, id));
  jsonEncode(body);
  final item = (body['items']! as List)
      .cast<Map<String, Object?>>()
      .singleWhere(
        (i) => i['position'] == at,
      );
  return (item['match']! as Map<String, Object?>)['child']!
      as Map<String, Object?>;
}

void main() {
  group('v104 (fix104: Run 077/078 U1–U25)', skip: skipIfNoCorpus, () {
    u3();
    u4();
    u5();
    u6();
    u7();
    u8();
    u9();
    u10();
    u11();
    u12();
    u13to17();
  });
}

/// U3 (LOW; S1): `yieldMeasureOf` returned quantity 0 for "MAKES 0 CUPS",
/// so the matches GET offered `{unit: cup, per_recipe: 0}` and the app's
/// share divided to Infinity. v104: the measure is null unless finite and
/// above 0. STATED synthesized edit of a real child: 0472 Chunky
/// Guacamole's real yield "MAKES 2½ TO 3 CUPS" (the control, cup 3) saved
/// as "MAKES 0 CUPS" through the real edit service; 0471 nachos line 6
/// "1 recipe Chunky Guacamole (see this page)" is its real parent line.
void u3() {
  test('U3: a child yield of "MAKES 0 CUPS" offers no cup unit', () async {
    final (:db, :config) = _open();
    final guac = _store(db, loadCorpusRecipe(_guac));
    expect(await matchAndCompute(db, _fx, guac), isNull);
    final nachos = await _compute(db, _fx, loadCorpusRecipe(_nachos));
    expect(guac.servings, 'MAKES 2½ TO 3 CUPS');
    expect((await _child(db, _fx, nachos.id, 6))['yield_units'], [
      {'unit': 'recipe', 'per_recipe': 1},
      {'unit': 'cup', 'per_recipe': 3.0},
    ]);
    updateRecipe(db, config, guac.id, {'servings': 'MAKES 0 CUPS'});
    expect((await _child(db, _fx, nachos.id, 6))['yield_units'], [
      {'unit': 'recipe', 'per_recipe': 1},
    ]);
    expect(_row(db, nachos.id, 6).childShare, 1.0);
  });
}

/// U4 (LOW; S2): an AMOUNT-LESS reference line whose written share is
/// outside (0, 100] got null from the written arm and fell through to the
/// rule-WB whole-batch arm — routed at 1.0. v104: the WB arm never fires
/// on a line that writes its own share ([writesShare]). STATED synthesized
/// (negative path: no corpus line writes 0 or more than 100 recipes — the
/// fleet's probe): 0184 Herb Sauce line 3 "¼ cup Sauce Base (½ recipe;
/// recipe follows)" edited to the amount-less texts.
void u4() {
  for (final edit in [
    'Sauce Base (0 recipe; recipe follows)',
    'Sauce Base (500000 recipes; recipe follows)',
  ]) {
    test(
      'U4: amount-less "$edit" reads not_routed no_share, no share',
      () async {
        final db = _db();
        final real = loadCorpusRecipe(_herb);
        expect(
          nutritionLines(real)[3].raw,
          '¼ cup Sauce Base (½ recipe; recipe follows)',
        );
        final stored = await _compute(db, _fx, _withLine(real, 3, edit, []));
        final row = _row(db, stored.id, 3);
        // The sub-recipe rule row a `noShare` reference stores (base: auto,
        // child_share 1.0, grams 1,456.7 — the fleet's probe).
        expect(
          (row.status, row.hold, row.childShare, row.grams, row.gramSource),
          ('confirmed', null, null, 0.0, 'unmeasured'),
        );
        final child = await _child(db, _fx, stored.id, 3);
        // A line that writes its own share and reads none keeps `no_share`
        // ([resolveReference], closer 1 D1: the brief's ruling — the share
        // the person must set), never v52's amount-less `no_amount`.
        expect((child['state'], child['reason']), ('not_routed', 'no_share'));
      },
    );
  }

  test('U4: the amount-less "(½ recipe" control reads 0.5', () async {
    final db = _db();
    final stored = await _compute(
      db,
      _fx,
      _withLine(
        loadCorpusRecipe(_herb),
        3,
        'Sauce Base (½ recipe; recipe follows)',
        [],
      ),
    );
    expect(_row(db, stored.id, 3).childShare, 0.5);
  });
}

/// [corpus] with its one step sentence [sentence] replaced by [to].
Recipe _stepEdited(Recipe corpus, String sentence, String to) {
  var hits = 0;
  final steps = [
    for (final s in corpus.steps)
      s.text.contains(sentence)
          ? (() {
              hits++;
              return s.copyWith(text: s.text.replaceFirst(sentence, to));
            })()
          : s,
  ];
  expect(hits, 1, reason: sentence);
  return corpus.copyWith(steps: steps);
}

/// U5 (LOW; O2): `_skimsFat` had no `_negatesSkim` guard (v101 U7 guarded
/// `defatsSentence` only) — 0492 carnitas S2.1 "… (do not skim the fat
/// from the liquid)" read as a skim for `_fatSkimmed` and `_fatLinesOf`.
/// v104: `_skimsFatIn`, the one guard both read. Corpus reach 0 (0492 has
/// no fat line; no other step negates a skim).
void u5() {
  test("U5: 0492's real negated skim is no skim; bulalo's real skim is", () {
    final carnitas = loadCorpusRecipe(_carnitas);
    expect(
      carnitas.steps.any(
        (s) => s.text.contains('(do not skim the fat from the liquid)'),
      ),
      isTrue,
    );
    expect(fatSkimmedOf(carnitas), isFalse);
    expect(fatSkimmedOf(loadCorpusRecipe(_bulalo)), isTrue);
  });

  // The `_fatLinesOf` caller: STATED synthesized (0492 holds no fat line,
  // so its reader cannot show it) — bulalo's real K1 skim "Using wide,
  // shallow spoon, skim excess fat from surface of broth." negated in
  // 0492's words; its browning fat line |0 is no longer skimmed.
  test('U5: a negated skim names no browning fat line', () {
    final real = loadCorpusRecipe(_bulalo);
    expect(browningFatLinesOf(real), contains(0));
    final negated = _stepEdited(
      real,
      'Using wide, shallow spoon, skim excess fat from surface of broth.',
      'Using wide, shallow spoon, remove the bones (do not skim the fat from the broth).',
    );
    expect(browningFatLinesOf(negated), isEmpty);
    expect(fatSkimmedOf(negated), isFalse);
  });
}

class _NoNet implements NutritionProvider {
  int calls = 0;
  @override
  Future<List<FdcCandidate>> search(String query) async {
    calls++;
    throw const NutritionProviderException('no net', scope: FailureScope.food);
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    calls++;
    throw const NutritionProviderException('no net', scope: FailureScope.food);
  }
}

/// U6 (MED; Opus C3): `held_on` named the FIRST uncached part of a
/// two-part row and the cache-only arm wrote only `derived_seq`, so once
/// that part was cached and the other was not, the hold kept naming the
/// cached one — the OTHER part's arrival re-opened nothing (0040|5 stayed
/// held at 78.12 kcal, 8/9, fresh). v104: the cache-only arm re-stamps
/// `held_on` ([SaltDatabase.markDerivedIfUnchanged]'s heldOn). The critic's
/// sequence on v103 U5's shape: 0040 line 5 (v41's rendered bacon, row
/// food 168277, parts 168322 + 172345) computed after 0118. STATED
/// synthesized (negative path, as v103 U5's own pin): both parts dropped
/// from the caches and a FOOD fault on both.
void u6() {
  test(
    'U6: the hold follows the part still uncached; its arrival re-opens '
    'the row; a cache-only compute restores 9/9 at 274.36, 0 requests',
    () async {
      final (db, path) = a.pathDb();
      final r = loadCorpusRecipe(
        '0040-wilted-spinach-salad-with-warm-bacon-dressing.yaml',
      );
      final ham = loadCorpusRecipe(
        '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
      );
      await d.editAndCompute(db, _fx, ham);
      await d.editAndCompute(db, _fx, r);
      expect(db.nutritionFor(r.id)!.caloriesPerServing, closeTo(274.36, 0.005));
      v28.dropFood(path, 168322);
      v28.dropFood(path, 172345);
      final fault = v28.FoodFault(
        _fx,
        {168322, 172345},
        scope: FailureScope.food,
      );
      for (var p = 1; p <= 3; p++) {
        await matchAndCompute(db, fault, r);
      }
      final held = d.rowOf(db, r, 5);
      expect(
        (held.fdcId, held.hold, held.heldOn),
        (
          168277,
          'food_unavailable',
          168322,
        ),
      );
      // 0118's compute caches 168322: the row re-opens (v103 U5).
      await matchAndCompute(db, v29.Asks(_fx), ham);
      expect(knownFood(db, 168322), isNotNull);
      expect(d.rowOf(db, r, 5).derivedSeq, isNull);
      final none = _NoNet();
      await matchAndCompute(db, none, r);
      expect(none.calls, 0);
      final still = d.rowOf(db, r, 5);
      // The re-stamp (base: held_on stayed 168322, the cached part).
      expect((still.hold, still.heldOn), ('food_unavailable', 172345));
      expect(still.derivedSeq, isNotNull);
      expect(nutritionIsFresh(db, r), isTrue);
      // The held_on-only arm (closer 1, D2): derived_seq current, held_on
      // naming a CACHED part — the re-stamp still fires. STATED synthesized
      // (negative path: no corpus run leaves held_on on a cached part under
      // a current derived_seq, the state the disjunct repairs): held_on
      // UPDATEd raw onto 168322, the part 0118's compute cached above.
      sqlite3.open(path)
        ..execute(
          'UPDATE ingredient_matches SET held_on = ? '
          'WHERE recipe_id = ? AND position = ?',
          [168322, r.id, 5],
        )
        ..dispose();
      expect(
        (d.rowOf(db, r, 5).heldOn, d.rowOf(db, r, 5).derivedSeq),
        (168322, still.derivedSeq),
      );
      final restamp = _NoNet();
      await matchAndCompute(db, restamp, r);
      expect(restamp.calls, 0);
      expect(
        (d.rowOf(db, r, 5).heldOn, d.rowOf(db, r, 5).derivedSeq),
        (172345, still.derivedSeq),
      );
      await cachedFood(db, _fx, 172345);
      expect(d.rowOf(db, r, 5).derivedSeq, isNull);
      expect(nutritionIsFresh(db, r), isFalse);
      final again = _NoNet();
      await matchAndCompute(db, again, r);
      expect(again.calls, 0);
      final m = db.nutritionFor(r.id)!;
      expect((m.matchedCount, m.totalCount), (9, 9));
      expect(m.caloriesPerServing, closeTo(274.36, 0.005));
      expect((d.rowOf(db, r, 5).hold, d.rowOf(db, r, 5).heldOn), (null, null));
    },
  );
}

String _rowText(IngredientMatchRow r) =>
    '${r.fdcId}:${r.grams?.toStringAsFixed(2)}:${r.gramSource}:${r.hold}:${r.status}';

/// U7 (LOW; O4): `decisionReach` excluded shellfish bought in the shell
/// and the M52 plan rows (a coat the plan counts: `discarded`, no hold,
/// read as a held medium), but the next compute APPLIES the decided record
/// to them — stored != compute under a stamp that reads fresh. v104 (sw12
/// measured: base 3 shell + 6 plan rows + 5 coat partners divergent, tip
/// 0): both are reached (a weighed shell line the shell move puts back on
/// its own record excepted) and a held target is written as the compute's
/// decided arm writes it (`decidedKeyRowFor`); the totals' plan re-splits
/// the coat. The fleet's two pairs, real corpus lines on the fixtures.
void u7() {
  for (final (from, at, food, to, rows, figures) in [
    // paella-on-the-grill|14 "… littleneck clams, scrubbed" → 171977;
    // cioppino|11 bought in the shell.
    (
      '0106-paella-on-the-grill.yaml',
      14,
      171977,
      '0108-cioppino.yaml',
      [11],
      {11: '171977:453.59:weight:in_shell:auto'},
    ),
    // chicken-katsu|0 panko → 174924; nut-crusted|5 the coat and |2 its
    // partner the plan re-splits.
    (
      '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
      0,
      174924,
      '0117-nut-crusted-chicken-breasts-with-lemon-and-thyme.yaml',
      [5, 2],
      {
        5: '174924:30.44:discarded:null:auto',
        2: '170567:73.60:discarded:null:auto',
      },
    ),
  ]) {
    test('U7: $from|$at → $food reaches $to $rows; stored == the next '
        'compute, 0 requests; the offer counts the rows that change', () async {
      final db = _db();
      final source = await _compute(db, _fx, loadCorpusRecipe(from));
      final target = await _compute(db, _fx, loadCorpusRecipe(to));
      // The decided record's detail cached, as snapshot 32 holds it (the
      // sweep's NoNet world).
      await cachedFood(db, _fx, food);
      final key = _row(db, source.id, at).itemKey!;
      final before = {
        for (final p in rows) p: _rowText(_row(db, target.id, p)),
      };
      final offered = decisionReach(
        db,
        key,
        excluding: (recipeId: source.id, position: at),
        fdcId: food,
      );
      expect(
        offered.map((r) => (r.recipeId, r.position)),
        [(target.id, rows.first)],
      );
      final none = _NoNet();
      final result = await applyMatchOverride(
        db,
        none,
        _rec(db, source.id),
        at,
        {
          'raw': nutritionLines(_rec(db, source.id))[at].raw,
          'fdc_id': food,
          'apply_to_all': true,
        },
      );
      expect(none.calls, 0);
      expect(result.toString(), contains('lines: 1,'));
      final stored = {
        for (final p in rows) p: _rowText(_row(db, target.id, p)),
      };
      expect(stored[rows.first], isNot(before[rows.first]));
      expect(_row(db, target.id, rows.first).fdcId, food);
      expect(nutritionIsFresh(db, _rec(db, target.id)), isTrue);
      final again = _NoNet();
      expect(await matchAndCompute(db, again, _rec(db, target.id)), isNull);
      expect(again.calls, 0);
      expect({
        for (final p in rows) p: _rowText(_row(db, target.id, p)),
      }, stored);
      // Base (9836d4e, the fleet's figures): cioppino|11 stayed 174214
      // 68.00 g; nut-crusted|5 174928 27.65 g, |2 66.85 g.
      expect(stored, figures);
    });
  }

  // The shell lines a decision does not move are not reached — three arms:
  // no food decided (the GET's offer on a line with no food), the line
  // already on the decided record (it stays as held), and a weighed line
  // the shell move puts back on its own record (a decision on the BOUGHT
  // record of `_shellRecords`, 2706350 "Mussels" → 174216). Real lines:
  // 0106 paella-on-the-grill|14 and cioppino|11 littleneck clams (both
  // 174214); 0105 paella|14 mussels (2706350, counted) and cioppino|14 "…
  // mussels, scrubbed and debearded" (174216, weighed).
  test('U7: a shell line the decision does not move is not reached', () async {
    final db = _db();
    final grill = await _compute(
      db,
      _fx,
      loadCorpusRecipe('0106-paella-on-the-grill.yaml'),
    );
    final paella = await _compute(
      db,
      _fx,
      loadCorpusRecipe('0105-paella.yaml'),
    );
    final cioppino = await _compute(
      db,
      _fx,
      loadCorpusRecipe('0108-cioppino.yaml'),
    );
    List<IngredientMatchRow> reach(Recipe from, int at, int? food) =>
        decisionReach(
          db,
          _row(db, from.id, at).itemKey!,
          excluding: (recipeId: from.id, position: at),
          fdcId: food,
        ).where((r) => r.recipeId == cioppino.id).toList();
    expect(_row(db, cioppino.id, 11).fdcId, 174214);
    expect(reach(grill, 14, null), isEmpty);
    expect(reach(grill, 14, 174214), isEmpty);
    expect(reach(grill, 14, 171977), hasLength(1));
    expect(_row(db, paella.id, 14).fdcId, 2706350);
    final mussel = _row(db, cioppino.id, 14);
    expect((mussel.fdcId, mussel.gramSource), (174216, 'weight'));
    expect(reach(paella, 14, 2706350), isEmpty);
  });
}

/// U8 (LOW; S4): which library recipe or section a reference line resolves
/// to was no hash term — a library recipe gaining a same-titled section
/// (or one titled like a held reference) left the parent fresh while a
/// recompute moved its row. v104: each reference line's resolved identity
/// joins `ingredientsHashOf` (the `routes` term, read in the pass of the
/// resolver the hash already makes). STATED synthesized library additions
/// on real parents (the fleet's probe): a second copy of 0972 (its real
/// "Basic Single-Crust Pie Dough" section) under a new id, and 0039's real
/// salad saved under the held title "Rich and Creamy Blue Cheese Dressing".
void u8() {
  test('U8: a second host of the routed section stales pumpkin-pie; the '
      'recompute holds choose_recipe', () async {
    final db = _db();
    final dough = await _compute(
      db,
      _fx,
      loadCorpusRecipe('0972-basic-double-crust-pie-dough.yaml'),
    );
    final pie = await _compute(
      db,
      _fx,
      loadCorpusRecipe('0987-pumpkin-pie.yaml'),
    );
    final row = _row(db, pie.id, 0);
    expect(
      row.childRecipeId,
      sectionKeyOf(dough.id, 'Basic Single-Crust Pie Dough'),
    );
    expect(nutritionIsFresh(db, _rec(db, pie.id)), isTrue);
    _store(db, dough.copyWith(id: '${dough.id}-u8', slug: '${dough.slug}-u8'));
    expect(nutritionIsFresh(db, _rec(db, pie.id)), isFalse);
    expect(await matchAndCompute(db, _fx, _rec(db, pie.id)), isNull);
    final moved = _row(db, pie.id, 0);
    expect((moved.hold, moved.childRecipeId), ('choose_recipe', null));
  });

  test('U8: a library recipe of the held title stales buffalo-wings; the '
      'recompute routes |13', () async {
    final db = _db();
    final wings = await _compute(
      db,
      _fx,
      loadCorpusRecipe('0151-buffalo-wings.yaml'),
    );
    final held = _row(db, wings.id, 13);
    expect(
      held.raw,
      '1 recipe Rich and Creamy Blue Cheese Dressing (see this page)',
    );
    expect(held.childRecipeId, isNull);
    expect(nutritionIsFresh(db, _rec(db, wings.id)), isTrue);
    final salad = loadCorpusRecipe(
      '0039-leafy-green-salad-with-rich-and-creamy-blue-cheese-dressing.yaml',
    );
    final dressing = _store(
      db,
      salad.copyWith(
        id: '${salad.id}-u8',
        slug: 'rich-and-creamy-blue-cheese-dressing-u8',
        title: 'Rich and Creamy Blue Cheese Dressing',
      ),
    );
    expect(nutritionIsFresh(db, _rec(db, wings.id)), isFalse);
    expect(await matchAndCompute(db, _fx, _rec(db, wings.id)), isNull);
    final routed = _row(db, wings.id, 13);
    // Routed at one whole batch (the child not computed yet: no grams —
    // the parent's row reads its recipe stale until its stamp lands).
    expect(
      (routed.hold, routed.childRecipeId, routed.childShare),
      (
        null,
        dressing.id,
        1.0,
      ),
    );
  });
}

/// U9 (MED; O1): `_mainRecipePartNote` decoded the whole host document for
/// EVERY amounted "reserved <mixture>" line of a section compute (403
/// decodes, 3.48 s at the cap). v104: the host once per index
/// (`memo:host`, the sibling `hostWeighedGiblets`' form; RULE C). STATED
/// synthesized cap shape (the fleet's probe): 0591's real section line "1
/// teaspoon reserved spice rub" ×400 in its Mustard Glaze section, the
/// host's steps padded to 120 × ~9,900 characters (the editor caps).
void u9() {
  test('U9: 400 reserved-mixture lines decode the host at most 4 times, '
      'every row the reserved-mixture rule row, under the backstop', () async {
    final base = loadCorpusRecipe('0591-grill-roasted-beef-short-ribs.yaml');
    final glaze = base.subsections.first;
    final reserved = glaze.ingredients!
        .expand((g) => g.items)
        .firstWhere((l) => l.raw == '1 teaspoon reserved spice rub');
    final big = '${'Stir well. ' * 900}x';
    final r = base.copyWith(
      steps: [
        for (var i = 0; i < 120; i++) RecipeStep(number: i + 1, text: big),
      ],
      subsections: [
        glaze.copyWith(
          ingredients: [IngredientGroup(items: List.filled(400, reserved))],
        ),
        ...base.subsections.skip(1),
      ],
    );
    validateRecipeDocument(r);
    final db = _db();
    _store(db, r);
    final key = sectionKeyOf(r.id, glaze.title!);
    hostDecodes = 0;
    stepIndexCounts.clear();
    final clock = Stopwatch()..start();
    expect(
      await matchAndCompute(db, _fx, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
    clock.stop();
    final section = nutritionRecipeOf(db, key)!.recipe;
    // Base 9836d4e: 403 (lines + 3); the tip: the compute's own 3 + the
    // memo's 1.
    expect(hostDecodes, 4);
    final counts = Map.of(stepIndexCounts)..remove('names');
    expectBounded(
      section,
      counts,
      'U9 reserved ×400 compute',
      copies: counts['indexes'] ?? 1,
    );
    expect(counts['memo:host'], counts['indexes']);
    final rows = db.ingredientMatchesFor(key);
    expect(rows, hasLength(400));
    expect(
      rows.map((m) => m.description).toSet(),
      {
        'Reserved from the main recipe — counted in the main recipe’s spice rub',
      },
    );
    expect(clock.elapsedMilliseconds, lessThan(backstopMs));
  });
}

/// U10 (LOW/MED; O5 + S5): `_madeFromRecipe(child)` rescanned the child's
/// lines on EVERY resolve (1,600 calls = 9.9 s of a 10.2 s matches GET at
/// the caps), and `_childRowOf` decoded the child per DECIDED row (401
/// decodes) then rescanned its lines; `recomputeParentsOf` the same. v104:
/// the scan once per child on the ResolverMemo (`madeFromScans`), the
/// child through `childRecipeOf`. STATED synthesized cap shapes (the
/// fleets' probes): 0972 Basic Double-Crust Pie Dough re-lined with its own
/// real lines to 400 and 120 × 10,000-char steps of its own step 1; 0977
/// Classic Apple Pie re-lined with 400 × its real line 0 "1 recipe
/// double-crust pie dough"; decided = every row confirmed.
void u10() {
  // closer 1 (D3): recomputeParentsOf's two sites by count — the real
  // corpus parents of 0972's "Basic Single-Crust Pie Dough" section
  // (quiche-lorraine|0, pumpkin-pie|0, pecan-pie|0 on v103_rows.tsv).
  test('U10: recomputeParentsOf decodes the section host once and scans '
      'the child once for its three real parents', () async {
    final db = _db();
    final dough = await _compute(
      db,
      _fx,
      loadCorpusRecipe('0972-basic-double-crust-pie-dough.yaml'),
    );
    final key = sectionKeyOf(dough.id, 'Basic Single-Crust Pie Dough');
    final parents = [
      for (final f in [
        '0742-quiche-lorraine.yaml',
        '0987-pumpkin-pie.yaml',
        '0988-pecan-pie.yaml',
      ])
        await _compute(db, _fx, loadCorpusRecipe(f)),
    ];
    for (final pie in parents) {
      expect(_row(db, pie.id, 0).childRecipeId, key);
    }
    hostDecodes = 0;
    madeFromScans = 0;
    await recomputeParentsOf(db, _fx, key);
    // (hostDecodes, madeFromScans), measured: the loop's one memo reads
    // (4, 1) — each parent once + the section's host once, the child
    // scanned once — and each parent's own totals recompute
    // (recomputeTotalsResolving, a memo of its own) (2, 1), so 4 + 3 × 2 =
    // 10 and 1 + 3 × 1 = 4. Mutants: the memo back inside the loop reads
    // (12, 6); [_childRowOf]'s nested scan unmemoised reads (10, 3). The
    // parent read through nutritionRecipeOf instead is EQUIVALENT, stated:
    // each parent id is read once per call either way (no other read of it
    // shares the loop's memo).
    expect((hostDecodes, madeFromScans), (10, 4));
  });

  for (final decided in [false, true]) {
    test('U10: 400 lines routed to a capped child (decided $decided) — '
        'hostDecodes and madeFromScans exact, under the backstop', () async {
      final db = wp.tempDb();
      final dough = loadCorpusRecipe('0972-basic-double-crust-pie-dough.yaml');
      final own = nutritionLines(dough);
      final child = capped(
        dough,
        [for (var i = 0; i < capLines; i++) own[i % own.length].raw],
        [
          for (var i = 0; i < capSteps; i++)
            fill('${dough.steps[0].text} ', capStep),
        ],
      );
      wp.saveRecipe(db, child);
      await matchAndCompute(db, _fx, db.recipeByIdOrSlug(child.id)!.recipe);
      final pie = loadCorpusRecipe('0977-classic-apple-pie.yaml');
      final line = nutritionLines(pie)[0];
      expect(line.raw, '1 recipe double-crust pie dough');
      wp.saveRecipe(
        db,
        pie.copyWith(
          ingredients: [IngredientGroup(items: List.filled(capLines, line))],
        ),
      );
      Recipe stored() => db.recipeByIdOrSlug(pie.id)!.recipe;
      await matchAndCompute(db, _fx, stored());
      final rows = db.ingredientMatchesFor(pie.id);
      expect(rows.where((m) => m.childRecipeId == child.id), hasLength(400));
      if (decided) {
        await applyMatchOverride(db, _fx, stored(), 0, {
          'raw': rows[0].raw,
          'confirmed': true,
        });
        final put = db.ingredientMatchesFor(pie.id);
        for (final row in put.skip(1)) {
          db.upsertIngredientMatch(
            row.copyWith(status: 'confirmed', derivedSeq: put[0].derivedSeq),
          );
        }
      }
      final seen = <String>[];
      for (final (step, run) in <(String, Future<Object?> Function())>[
        ('GET', () => matchesBody(db, _fx, stored())),
        ('compute', () => matchAndCompute(db, _fx, stored())),
        ('recompute', () async => recomputeTotals(db, stored())),
      ]) {
        hostDecodes = 0;
        madeFromScans = 0;
        final clock = Stopwatch()..start();
        await run();
        final ms = clock.elapsedMilliseconds;
        seen.add('$step $hostDecodes $madeFromScans');
        expect(ms, lessThan(backstopMs), reason: '$step: ${ms}ms');
      }
      // (step, hostDecodes, madeFromScans) — base 9836d4e (the fleets'
      // measures): undecided GET 10.2 s on 1,600 scans; decided GET 401 /
      // compute 402 decodes.
      expect(
        seen,
        decided
            ? ['GET 1 1', 'compute 2 1', 'recompute 2 1']
            : ['GET 2 1', 'compute 2 1', 'recompute 2 1'],
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}

/// U11 (LOW; S6): 24 of `_birdWords`' 28 entries had no pin. One skin
/// sentence per word on 0148 Crispy Fried Chicken (its line 6 skin-on, the
/// v103 U14 form): each word trips the skin-off read; an entry deleted
/// reads the sentence as another food's skin ("fromOther") and trips
/// nothing. The corpus sentence for "chicken" (0002 Hearty Chicken Noodle
/// Soup S4 "Meanwhile, remove the skin and bones from the reserved cooked
/// chicken and discard."); STATED synthesized for the other 27 (no corpus
/// step takes a skin "from" them alone — the nearest real form is 0002's),
/// "Remove the skin from the <word>."
void u11() {
  // The 18 entries a "from" object reaches. The other 10 — breast(s),
  // thigh(s), leg(s), wing(s), drumstick(s) — are EQUIVALENT: `_skinPart`
  // reads the same three-word window after "from" and, matching any of
  // them (no trailing \b: the plurals too), answers by the part before
  // `fromOther` is read (`_skinOffFor`) — deleting one changes no answer.
  const words = [
    'chicken', 'chickens', 'turkey', 'turkeys', 'duck', 'ducks', 'bird', //
    'birds', 'hen', 'hens', 'poultry', 'piece', 'pieces', 'half', //
    'halves', 'quarter', 'quarters', 'meat', //
  ];
  test('U11: every reachable _birdWords entry trips the skin read (18)', () {
    final real = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
    final line = nutritionLines(real)[6];
    expect(line.raw, contains('skin-on'));
    bool trips(String sentence) => skinDiscarded(
      real.copyWith(
        steps: [
          ...real.steps,
          RecipeStep(number: real.steps.length + 1, text: sentence),
        ],
      ),
      line,
    );
    expect(trips('Remove the skin from the roasted peppers.'), isFalse);
    expect(
      trips(
        'Meanwhile, remove the skin and bones from the reserved cooked '
        'chicken and discard.',
      ),
      isTrue,
      reason: '0002',
    );
    for (final word in words) {
      expect(trips('Remove the skin from the $word.'), isTrue, reason: word);
    }
  });
}

/// U12 (LOW; S7): `_yieldTailOf`'s 1e-4 tolerance widened to 1e-1 survived
/// every test. STATED synthesized servings (the v101 U15 form): 0521's
/// REAL "Basic White Rice" and its real line |9 "5 cups cold cooked white
/// rice, …" against MAKES ABOUT 5½ CUPS — a share of 0.909, not the whole.
void u12() {
  test('U12: a 0.9 yield does not read as the whole', () {
    final real = loadCorpusRecipe(
      '0521-fried-rice-with-shrimp-pork-and-shiitakes.yaml',
    );
    final sub = real.subsections.singleWhere(
      (s) => s.title == 'Basic White Rice',
    );
    final line = nutritionLines(real)[9];
    expect(line.raw, startsWith('5 cups cold cooked white rice'));
    final item = referenceItemOf(line);
    expect(yieldNamesOwnSection(line, item, sub), isTrue);
    expect(
      yieldNamesOwnSection(
        line,
        item,
        sub.copyWith(servings: 'MAKES ABOUT 5½ CUPS'),
      ),
      isFalse,
    );
  });
}

/// A provider whose searches answer nothing (no fixture lookups: a line
/// the engine searches comes back unmatched by value).
class _NoHits extends FixtureProvider {
  _NoHits() : super(pending: pendingSearches);
  @override
  Future<List<FdcCandidate>> search(String q) async => const [];
}

/// U14 (LOW; S9): `_lineRuleRow`'s continuation arm had no value pin. The
/// real corpus continuation line 0028 Hearty Minestrone |5 "(about ¾ cup)"
/// (v103_rows.tsv: confirmed, no food, the note), computed on a provider
/// answering no search (the arm dropped, the line is searched: unmatched).
/// U16 (LOW; O7): the un-skip's `heldOn: _heldOnOf` was unpinned — a PUT
/// {skipped: false} on an AUTO row with parts (the handler does not check
/// status) whose food and first part no cache holds stores held_on = that
/// part. STATED synthesized cache state (as v103 U5): 0040|5 (v41's
/// rendered bacon, food 168277, parts 168322 + 172345) with 168277 and
/// 168322 dropped from the caches.
/// U17 (LOW; O8): v98 P4's `_repeatRoundsIn` — six mutants survived; the
/// corpus prints digit counts only ("remaining 6 pitas in 3 batches",
/// "remaining 8 sandwiches in 2 batches"), so each pin is a STATED
/// synthesized step text in those sentences' form.
void u13to17() {
  test('U14: the continuation rule rows by value — 0559 bun-cha|3 and '
      '0028|5', () async {
    for (final (file, at, raw) in [
      // The arm alone answers it (its item normalizes to words).
      ('0559-bun-cha.yaml', 3, 'lengthwise, seeded, and sliced thin on bias'),
      // Nothing searchable either: the arm names the note.
      ('0028-hearty-minestrone.yaml', 5, '(about ¾ cup)'),
    ]) {
      final db = _db();
      final r = await _compute(db, _NoHits(), loadCorpusRecipe(file));
      final row = _row(db, r.id, at);
      expect(
        (row.raw, row.status, row.fdcId, row.grams, row.gramSource),
        (raw, 'confirmed', null, null, null),
        reason: file,
      );
      expect(row.description, 'Continues the line above — counted with it');
    }
  });

  test('U16: an un-skip of an AUTO row with parts holds on its uncached '
      'part', () async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe(
      '0040-wilted-spinach-salad-with-warm-bacon-dressing.yaml',
    );
    await d.editAndCompute(
      db,
      _fx,
      loadCorpusRecipe(
        '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
      ),
    );
    await d.editAndCompute(db, _fx, r);
    final auto = d.rowOf(db, r, 5);
    expect((auto.status, auto.fdcId, auto.hold), ('auto', 168277, null));
    v28.dropFood(path, 168277);
    v28.dropFood(path, 168322);
    final none = _NoNet();
    await applyMatchOverride(db, none, r, 5, {
      'raw': auto.raw,
      'skipped': false,
    });
    final row = d.rowOf(db, r, 5);
    expect(
      (row.status, row.fdcId, row.hold, row.heldOn),
      (
        'auto',
        168277,
        'food_unavailable',
        168322,
      ),
    );
  });

  test("U17: the counted repeat's word numbers, batch tails and guards", () {
    List<int> rounds(String step) =>
        repeatRoundsForTest(step).whereType<int>().toList();
    // `_countedPieces`' word count: the first pass "two patties".
    expect(
      rounds('Lay two patties in skillet. Repeat with remaining 4 patties.'),
      [2],
    );
    // `_inBatches`' word count and its singular "batch".
    expect(rounds('Repeat with remaining 8 sandwiches in two batches.'), [2]);
    expect(rounds('Repeat with remaining 4 sandwiches in 1 batch.'), [1]);
    // `_repeatWith`'s "three".
    expect(rounds('Repeat with remaining three crusts.'), [3]);
    // The `m > 0` guard: "in 0 batches" reads no batches (N, one a round).
    expect(rounds('Repeat with remaining 4 patties in 0 batches.'), [4]);
    // The `count > 0` guard: a zero first pass is no pass.
    expect(
      rounds('Lay 0 patties in skillet. Repeat with remaining 4 patties.'),
      [4],
    );
  });
}
