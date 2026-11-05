// Matcher v102 (batch M98 at the base 78e9aad; matcherVersion 95 unchanged —
// a write-path batch moves no corpus row). The spec:
// .claude/diag/2026-11-04/m98/design/design_v2.md §2. R1: a PUT that stores
// a key's decision settles its OWN recipe — every other undecided line of
// the key written as the compute's decided branch writes it
// ([settleKeyInRecipe] over [decidedKeyRowFor], the un-skip's decided-key
// arm moved), before the PUT's one totals write. R2: an un-skip whose
// decided-key derivation FDC cannot serve reads the totals underived. Every
// pin is a real corpus recipe through the real PUT ([applyMatchOverride]) on
// the recorded fixtures, then a full NoNet compute that must change nothing
// ([_settled]). STATED synthesized negative paths (named at each, with the
// exception and its corpus source): a real row set `food_unavailable`, a
// deleted cache row, a provider that fails one real record or writes a
// person's skip during its await.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _classic = '0002-classic-chicken-noodle-soup.yaml';
const _hearty = '0002-hearty-chicken-noodle-soup.yaml';
const _doughnuts = '1105-yeasted-doughnuts.yaml';

final _fx = FixtureProvider(pending: pendingSearches);

({SaltDatabase db, String path}) _open() {
  final dir = Directory.systemTemp.createTempSync('salt-v102-');
  final path = ServerConfig(
    dataDir: dir.path,
    logLevel: Level.WARNING,
    trustProxy: false,
  ).dbPath;
  final db = SaltDatabase.open(path)
    ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
  addTearDown(() {
    db.dispose();
    dir.deleteSync(recursive: true);
  });
  return (db: db, path: path);
}

SaltDatabase _db() => _open().db;

/// [file] stored and computed on the fixtures (its section children
/// first); its id.
Future<String> _compute(SaltDatabase db, String file) async {
  final r = loadCorpusRecipe(file);
  db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
  final stored = db.recipeByIdOrSlug(r.id)!.recipe;
  for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
    expect(
      await matchAndCompute(db, _fx, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }
  expect(await matchAndCompute(db, _fx, stored), isNull);
  return stored.id;
}

Recipe _rec(SaltDatabase db, String id) => nutritionRecipeOf(db, id)!.recipe;

IngredientMatchRow _row(SaltDatabase db, String id, int position) =>
    db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

/// The real PUT at [position] (the line text the client saw).
Future<AppliedToOthers?> _put(
  SaltDatabase db,
  NutritionProvider p,
  String id,
  int position,
  Map<String, Object?> body,
) {
  final r = _rec(db, id);
  return applyMatchOverride(db, p, r, position, {
    'raw': nutritionLines(r)[position].raw,
    ...body,
  });
}

String _energy(SaltDatabase db, String id) =>
    ((jsonDecode(db.nutritionFor(id)!.totalsJson!) as Map)['energy'] as num)
        .toStringAsFixed(2);

String _g(double? x) => x?.toStringAsFixed(2) ?? '-';

/// One row as the pins compare it. `derived_seq` where freshness reads it
/// ([SaltDatabase.underivedSql]: a decided row, a held `food_unavailable`
/// one) — an unheld `auto` row's is never read (an un-skip's touched row
/// carries the PUT's, the compute writes none: base behaviour, not M98's).
String _shape(IngredientMatchRow r) =>
    '${r.fdcId}|${_g(r.grams)}|${r.gramSource}|${r.hold}|${r.status}|'
    '${r.confidence.toStringAsFixed(4)}|${r.description}|'
    '${isDecidedRow(r) || r.hold == 'food_unavailable' ? r.derivedSeq : '·'}';

/// A provider that answers nothing and counts every ask (NoNet).
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

/// The fixtures, counting every ask; [onFood] runs before a detail is
/// answered (or throws in its place).
class _Count implements NutritionProvider {
  _Count({this.onFood});
  final Future<void> Function(int fdcId)? onFood;
  final asked = <String>[];
  @override
  Future<List<FdcCandidate>> search(String query) {
    asked.add('search:$query');
    return _fx.search(query);
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    asked.add('food:$fdcId');
    await onFood?.call(fdcId);
    return _fx.food(fdcId);
  }
}

/// THE helper (design_v2 §2.8): every row of [id] and its totals as the
/// PUTs left them, the recipe fresh, then a full NoNet compute — which must
/// change nothing and ask nothing. Returns the stored rows by position.
Future<Map<int, String>> _settled(SaltDatabase db, String id) async {
  final before = {
    for (final r in db.ingredientMatchesFor(id)) r.position: _shape(r),
  };
  final totals = db.nutritionFor(id)!.totalsJson;
  expect(nutritionIsFresh(db, _rec(db, id)), isTrue, reason: 'fresh');
  final none = _NoNet();
  expect(await matchAndCompute(db, none, _rec(db, id)), isNull);
  expect({
    for (final r in db.ingredientMatchesFor(id)) r.position: _shape(r),
  }, before);
  expect(db.nutritionFor(id)!.totalsJson, totals);
  expect(none.calls, 0);
  return before;
}

Future<Map<String, Object?>> _item(SaltDatabase db, String id, int at) async {
  final body = await matchesBody(db, _NoNet(), _rec(db, id));
  return (body['items']! as List).cast<Map<String, Object?>>().singleWhere(
    (i) => i['position'] == at,
  );
}

void main() {
  group(
    'v102 (M98: a food decision settles its own recipe)',
    skip: skipIfNoCorpus,
    () {
      picks();
      confirms();
      knockOn();
      lineHeld();
      shared();
      leftAlone();
      ruleRow();
      receipts();
      unskip();
      unskipAlone();
      requests();
      arms();
      race();
    },
  );
}

/// P1 (pC c1/c7/c8/c13; critic 2 K1–K3): a pick settles the recipe's other
/// undecided line of its key in the PUT itself (base: the sibling kept its
/// engine row under a fresh stamp; the next compute moved it).
void picks() {
  for (final (file, at, food, sib, grams, energy) in [
    (_classic, 7, 170000, 2, '0.00', '3145.66'),
    ('0249-roast-fresh-ham.yaml', 11, 746775, 2, '0.00', '5372.14'),
    (
      '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml',
      0,
      748608,
      20,
      '11.19',
      '7272.38',
    ),
    ('0402-italian-wedding-soup.yaml', 15, 170000, 0, '0.00', '1774.88'),
  ]) {
    test('P1: $file|$at pick $food → |$sib $food $grams g, confidence 1, '
        'E $energy in the PUT (mutants m1, m6)', () async {
      final db = _db();
      final id = await _compute(db, file);
      await cachedFood(db, _fx, food);
      final key = lineKeyOf(nutritionLines(_rec(db, id))[at]);
      expect(lineKeyOf(nutritionLines(_rec(db, id))[sib]), key);
      expect(_row(db, id, sib).fdcId, isNot(food));
      await _put(db, _NoNet(), id, at, {'fdc_id': food});
      final s = _row(db, id, sib);
      expect(
        (s.fdcId, _g(s.grams), s.status, s.confidence),
        (food, grams, 'auto', 1.0),
      );
      expect(_energy(db, id), energy);
      await _settled(db, id);
    });
  }
}

/// P2 (pC c2/c14; critic 2 K4): a Confirm decides the food — the same-food
/// sibling takes confidence 1 in the PUT (base: .9367; m3, m4).
void confirms() {
  for (final (file, at, sib, energy) in [
    (_classic, 2, 7, '3143.46'),
    (_hearty, 2, 12, '2005.15'),
  ]) {
    test('P2: $file|$at Confirm → |$sib 790646 confidence .9367 → 1, E '
        '$energy (mutants m3, m4)', () async {
      final db = _db();
      final id = await _compute(db, file);
      expect(
        (
          _row(db, id, sib).fdcId,
          _row(db, id, sib).confidence.toStringAsFixed(4),
        ),
        (790646, '0.9367'),
      );
      await _put(db, _NoNet(), id, at, {'confirmed': true});
      final s = _row(db, id, sib);
      expect((s.fdcId, s.status, s.confidence), (790646, 'auto', 1.0));
      expect(_energy(db, id), energy);
      await _settled(db, id);
    });
  }
}

/// P3 (pC c6, F3; critic 2 K5): the settle lands BEFORE the PUT's one
/// totals write — the knock-on of a settled sibling on a NON-key line
/// (1105|7's frying oil reads the doughnuts' fat) is in the PUT's own
/// totals (m2: 139.50 g / E 5193.05).
void knockOn() {
  test('P3: 1105|10 pick 746775 → |5 173468 5.89 g → 746775 5.97 g; the '
      "non-key |7 'vegetable oil for frying' 139.50 → 139.52 g, E 5193.05 → "
      '5193.23 in the PUT (mutant m2)', () async {
    final db = _db();
    final id = await _compute(db, _doughnuts);
    await cachedFood(db, _fx, 746775);
    expect(
      (_row(db, id, 5).fdcId, _g(_row(db, id, 5).grams)),
      (173468, '5.89'),
    );
    await _put(db, _NoNet(), id, 10, {'fdc_id': 746775});
    expect(
      (_row(db, id, 5).fdcId, _g(_row(db, id, 5).grams)),
      (746775, '5.97'),
    );
    expect(_g(_row(db, id, 7).grams), '139.52');
    expect(_energy(db, id), '5193.23');
    await _settled(db, id);
  });
}

/// P4 (critic B13/B14, pC c10–c12; critic 2 K6): a LINE-held sibling takes
/// the food and KEEPS its hold, as the compute's decided branch does
/// ([engineOutcome] `decided`); the apply's reach skips it (m3, m7).
void lineHeld() {
  for (final (file, at, sib, energy) in [
    ('0510-goi-cuo-n-vietnamese-summer-rolls.yaml', 2, 10, '2639.47'),
    (
      '0358-classic-spaghetti-and-meatballs-for-a-crowd.yaml',
      11,
      26,
      '11248.44',
    ),
  ]) {
    test('P4: $file|$at pick 746775 → |$sib 746775, `discarded_medium` '
        'kept, no grams, E $energy (mutants m3, m7)', () async {
      final db = _db();
      final id = await _compute(db, file);
      await cachedFood(db, _fx, 746775);
      expect(_row(db, id, sib).hold, 'discarded_medium');
      expect(_row(db, id, sib).fdcId, isNot(746775));
      await _put(db, _NoNet(), id, at, {'fdc_id': 746775});
      final s = _row(db, id, sib);
      expect(
        (s.fdcId, s.hold, s.grams, s.status, s.confidence),
        (746775, 'discarded_medium', null, 'auto', 1.0),
      );
      expect(_energy(db, id), energy);
      await _settled(db, id);
    });
  }
  test('P4: 0510|2 pick 746775 + apply_to_all → applied 0 / 0 (the reach '
      'skips the LINE-held |10), |10 settled by the PUT', () async {
    final db = _db();
    final id = await _compute(
      db,
      '0510-goi-cuo-n-vietnamese-summer-rolls.yaml',
    );
    await cachedFood(db, _fx, 746775);
    final applied = await _put(db, _NoNet(), id, 2, {
      'fdc_id': 746775,
      'apply_to_all': true,
    });
    expect((applied!.lines, applied.recipes), (0, 0));
    expect(
      (_row(db, id, 10).fdcId, _row(db, id, 10).hold),
      (746775, 'discarded_medium'),
    );
    await _settled(db, id);
  });
}

/// P5 (critic B8; pA W5): a later Confirm on another line of a settled key
/// confirms the decided food, and the earlier-touched row (`auto` after its
/// un-skip) is settled too (base: |7 stored 170000, the compute 790646).
void shared() {
  test('P5: 0002|7 pick 170000, skip |7, un-skip |7, Confirm |2 → |2 '
      '`confirmed` 170000, |7 `auto` 170000, E 3145.66 (mutant m1)', () async {
    final db = _db();
    final id = await _compute(db, _classic);
    await cachedFood(db, _fx, 170000);
    final none = _NoNet();
    await _put(db, none, id, 7, {'fdc_id': 170000});
    await _put(db, none, id, 7, {'skipped': true});
    await _put(db, none, id, 7, {'skipped': false});
    await _put(db, none, id, 2, {'confirmed': true});
    expect(
      (_row(db, id, 2).fdcId, _row(db, id, 2).status),
      (170000, 'confirmed'),
    );
    expect((_row(db, id, 7).fdcId, _row(db, id, 7).status), (170000, 'auto'));
    expect(_energy(db, id), '3145.66');
    expect(none.calls, 0);
    await _settled(db, id);
  });
}

/// P6 (green on both trees — critic B5/B6/B9, critic 2 K8/K14): a person's
/// row of the key is never touched by the settle (the RULE; the guard's own
/// pin is P12).
void leftAlone() {
  for (final (name, ops, sib, expected)
      in <(String, List<(int, Map<String, Object?>)>, int, String)>[
        (
          'skip |7, pick |2 170000',
          [
            (7, {'skipped': true}),
            (2, {'fdc_id': 170000}),
          ],
          7,
          '790646|skipped',
        ),
        (
          'Confirm |2, pick |7 170000',
          [
            (2, {'confirmed': true}),
            (7, {'fdc_id': 170000}),
          ],
          2,
          '790646|confirmed',
        ),
        (
          'pick |7 170000, skip |2, un-skip |2',
          [
            (7, {'fdc_id': 170000}),
            (2, {'skipped': true}),
            (2, {'skipped': false}),
          ],
          2,
          '170000|auto',
        ),
        (
          'pick |7 170000, pick |2 790577',
          [
            (7, {'fdc_id': 170000}),
            (2, {'fdc_id': 790577}),
          ],
          7,
          '170000|overridden',
        ),
      ]) {
    test('P6: 0002 $name → |$sib stays $expected', () async {
      final db = _db();
      final id = await _compute(db, _classic);
      await cachedFood(db, _fx, 170000);
      await cachedFood(db, _fx, 790577);
      for (final (at, body) in ops) {
        await _put(db, _NoNet(), id, at, body);
      }
      final s = _row(db, id, sib);
      expect('${s.fdcId}|${s.status}', expected);
      await _settled(db, id);
    });
  }
}

/// P7 (green on both trees — C2-D5, K7): an engine RULE ROW sibling stays
/// the rule row — the rule order inside the settle (m7, m8).
void ruleRow() {
  test("P7: 0072|14 '¾ teaspoon table salt' pick 746775 → |3 'Table salt' "
      'stays the seasoning rule row (mutants m7, m8)', () async {
    final db = _db();
    final id = await _compute(db, '0072-skillet-tamale-pie.yaml');
    await cachedFood(db, _fx, 746775);
    final before = _row(db, id, 3);
    expect(nutritionLines(_rec(db, id))[14].raw, '¾ teaspoon table salt');
    expect(nutritionLines(_rec(db, id))[3].raw, 'Table salt');
    expect(
      (before.status, before.fdcId, isEngineRuleRow(before)),
      ('confirmed', null, true),
    );
    await _put(db, _NoNet(), id, 14, {'fdc_id': 746775});
    expect(_shape(_row(db, id, 3)), _shape(before));
    await _settled(db, id);
  });
}

/// P8 (critic B1/B2; critic 2 K10/K11): the receipts after the settle — an
/// own-recipe-only key offers nothing (base: `others` 1 / 1); with another
/// recipe, `others` and `applied` count the OTHER recipe only (base: the
/// apply counted the own |2, 3 / 2) (m1, m12).
void receipts() {
  test('P8: 0002|7 pick 170000 → the matches body |7 `others` 0 / '
      '`others_lines` 0 (mutant m1)', () async {
    final db = _db();
    final id = await _compute(db, _classic);
    await cachedFood(db, _fx, 170000);
    await _put(db, _NoNet(), id, 7, {'fdc_id': 170000});
    final item = await _item(db, id, 7);
    expect((item['others'], item['others_lines']), (0, 0));
  });
  test(
    'P8: with 0002-hearty in the DB, 0002|7 pick 170000 → `others` 1 / '
    '`others_lines` 2; pick + apply_to_all → applied lines 2 / recipes 1 '
    '(hearty only), the own |2 settled by the PUT (mutants m1, m12)',
    () async {
      for (final apply in [false, true]) {
        final db = _db();
        final id = await _compute(db, _classic);
        final hearty = await _compute(db, _hearty);
        await cachedFood(db, _fx, 170000);
        final applied = await _put(db, _NoNet(), id, 7, {
          'fdc_id': 170000,
          if (apply) 'apply_to_all': true,
        });
        expect(_row(db, id, 2).fdcId, 170000);
        if (apply) {
          expect((applied!.lines, applied.recipes), (2, 1));
          expect(
            [_row(db, hearty, 2).fdcId, _row(db, hearty, 12).fdcId],
            [170000, 170000],
          );
        } else {
          final item = await _item(db, id, 7);
          expect((item['others'], item['others_lines']), (1, 2));
        }
      }
    },
  );
}

/// P9 (R2; critic's cold case): an un-skip whose decided-key derivation
/// FDC cannot serve (170000 never cached, NoNet) reads the totals
/// underived — the next compute asks again (base: fresh with |7 on no
/// grams, E 3101.66) (m11).
void unskip() {
  test(
    'P9: 0002|7 pick 170000 uncached, skip, un-skip → stale '
    '`underived`, |7 `auto` 170000 no grams, |2 790646 (mutant m11)',
    () async {
      final db = _db();
      final id = await _compute(db, _classic);
      expect(db.fdcFoodCacheGet(170000), isNull);
      final none = _NoNet();
      await _put(db, none, id, 7, {'fdc_id': 170000});
      await _put(db, none, id, 7, {'skipped': true});
      await _put(db, none, id, 7, {'skipped': false});
      final s = _row(db, id, 7);
      expect((s.fdcId, s.grams, s.status), (170000, null, 'auto'));
      expect(_row(db, id, 2).fdcId, 790646);
      expect(_energy(db, id), '3101.66');
      expect(nutritionIsFresh(db, _rec(db, id)), isFalse);
      expect(
        staleReasonOf(db, _rec(db, id), db.nutritionFor(id)!, ResolverMemo(db)),
        'underived',
      );
    },
  );
}

/// P9b (R2 alone): the same un-skip with the sibling |2 a person's row
/// first (skipped — the settle leaves it, so no settle arm stamps the
/// totals): only R2 reads them underived (base, and R2's callback dropped:
/// fresh) (m11).
void unskipAlone() {
  test('P9b: 0002 skip |2, pick |7 170000 uncached, skip |7, un-skip |7 → '
      'stale `underived` by the un-skip alone (mutant m11)', () async {
    final db = _db();
    final id = await _compute(db, _classic);
    expect(db.fdcFoodCacheGet(170000), isNull);
    final none = _NoNet();
    await _put(db, none, id, 2, {'skipped': true});
    await _put(db, none, id, 7, {'fdc_id': 170000});
    await _put(db, none, id, 7, {'skipped': true});
    expect(nutritionIsFresh(db, _rec(db, id)), isTrue);
    await _put(db, none, id, 7, {'skipped': false});
    final s = _row(db, id, 7);
    expect((s.fdcId, s.grams, s.status), (170000, null, 'auto'));
    expect(_row(db, id, 2).status, 'skipped');
    expect(nutritionIsFresh(db, _rec(db, id)), isFalse);
    expect(
      staleReasonOf(db, _rec(db, id), db.nutritionFor(id)!, ResolverMemo(db)),
      'underived',
    );
  });
}

/// P10 (critic G4; critic 2 K9): the request bound — a decision PUT asks at
/// most one request per distinct record the touched row and its settled
/// siblings land on (v29 S13's ≤ 2 unchanged).
void requests() {
  test('P10: 1105|10 pick 746775 uncached → 1 request (food:746775), the '
      'sibling |5 settled on it', () async {
    final db = _db();
    final id = await _compute(db, _doughnuts);
    expect(db.fdcFoodCacheGet(746775), isNull);
    final counting = _Count();
    await _put(db, counting, id, 10, {'fdc_id': 746775});
    expect(counting.asked, ['food:746775']);
    expect(_row(db, id, 5).fdcId, 746775);
    await _settled(db, id);
  });
}

/// The settle called as the PUT calls it, on the stored recipe.
Future<({Set<int> foods, bool unavailable})> _settle(
  SaltDatabase db,
  NutritionProvider p,
  String id,
  int position,
) {
  final r = _rec(db, id);
  final seq = db.layoutSeqOf(id);
  return settleKeyInRecipe(
    db,
    p,
    r,
    position: position,
    itemKey: lineKeyOf(nutritionLines(r)[position]),
    seq: seq,
    derivedSeq: derivedKeyOf(seq, ingredientsHashOf(r, ResolverMemo(db))),
  );
}

/// [fdcId] in no cache: its detail row and every search answer holding it.
void _uncache(String path, int fdcId) {
  sqlite3.open(path)
    ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [fdcId])
    ..execute(
      'DELETE FROM fdc_search_cache '
      "WHERE response LIKE '%\"fdc_id\":' || ? || ',%'",
      [fdcId],
    )
    ..dispose();
}

/// The decision [fdcId] stored for [id]'s line [at] (as the PUT's
/// `putDecision` stores a pick).
void _decide(SaltDatabase db, String id, int at, int fdcId, String desc) {
  final line = nutritionLines(_rec(db, id))[at];
  db.putDecision(
    itemKey: lineKeyOf(line),
    item: decisionItemOf(line),
    fdcId: fdcId,
    description: desc,
    dataType: 'SR Legacy',
    decidedBy: null,
  );
}

/// P11 — RULE A and the compute's failure arms in the settle (design_v2
/// §2.3a). STATED synthesized negative paths (corpus lines and rows real —
/// 0002|2/|7 'onion', 0767's four 'table salt' lines; snapshot 32 holds 0
/// `food_unavailable` and 0 counted rows, so no corpus state reaches an
/// arm): a real row set `food_unavailable`, a deleted cache row, a provider
/// failing one real record.
void arms() {
  test(
    'P11a1: 0002|2 held `food_unavailable` (STATED synthesized: the real '
    'row with the hold set), pick |7 170000 through the PUT → |2 derived '
    'through cacheOnly to 170000 0 g / 1, no settle request (mutant m1)',
    () async {
      final db = _db();
      final id = await _compute(db, _classic);
      final two = _row(db, id, 2);
      db.upsertIngredientMatch(
        two.copyWith(
          hold: 'food_unavailable',
          clearGrams: true,
          clearGramSource: true,
        ),
        layoutSeq: db.layoutSeqOf(id),
      );
      final counting = _Count();
      await _put(db, counting, id, 7, {'fdc_id': 170000});
      expect(counting.asked, ['food:170000']);
      final s = _row(db, id, 2);
      expect(
        (s.fdcId, _g(s.grams), s.gramSource, s.hold, s.confidence),
        (170000, '0.00', 'discarded', null, 1.0),
      );
      await _settled(db, id);
    },
  );

  test('P11a2 (arm 1): 0002|2 held `food_unavailable` with a stale '
      '`derived_seq`, the decision 170000 in no cache (STATED synthesized) '
      '→ the settle asks nothing, leaves |2, marks it derived for these '
      'inputs, `unavailable` false — and the compute leaves |2 the same '
      '(mutants m10, m14, m16)', () async {
    final o = _open();
    final db = o.db;
    final id = await _compute(db, _classic);
    db.upsertIngredientMatch(
      _row(db, id, 2).copyWith(hold: 'food_unavailable', derivedSeq: 'stale'),
      layoutSeq: db.layoutSeqOf(id),
    );
    _decide(db, id, 7, 170000, 'Onions, raw');
    _uncache(o.path, 170000);
    final before = _shape(_row(db, id, 2));
    final counting = _Count();
    final settled = await _settle(db, counting, id, 7);
    expect(counting.asked, isEmpty);
    expect(settled.unavailable, isFalse);
    final r = _rec(db, id);
    final key = derivedKeyOf(
      db.layoutSeqOf(id),
      ingredientsHashOf(r, ResolverMemo(db)),
    );
    final after = _row(db, id, 2);
    expect(after.derivedSeq, key);
    expect(_shape(after.copyWith(derivedSeq: 'stale')), before);
    await matchAndCompute(db, _NoNet(), r);
    expect(_shape(_row(db, id, 2)), _shape(after));
  });

  test('P11b (arm 5): 0002|2 plain, the decision 170000 in no cache, a '
      'provider failing it FOOD (STATED synthesized) → |2 unwritten, '
      '`unavailable` true (mutant m13, the function half)', () async {
    final o = _open();
    final db = o.db;
    final id = await _compute(db, _classic);
    _decide(db, id, 7, 170000, 'Onions, raw');
    _uncache(o.path, 170000);
    final before = _shape(_row(db, id, 2));
    final none = _NoNet();
    final settled = await _settle(db, none, id, 7);
    expect(settled.unavailable, isTrue);
    expect(settled.foods, isEmpty);
    expect(_shape(_row(db, id, 2)), before);
    expect(none.calls, 1);
  });

  for (final global in [false, true]) {
    test('P11c (arm ${global ? 4 : 5}): 0767 table salt |3 decided 746775 '
        'in no cache, a provider failing it ${global ? 'GLOBAL' : 'FOOD'} '
        '(STATED synthesized) → ${global ? 'the settle stops after one ask' : 'the pass goes on: one ask per sibling'}, '
        '|11/|15/|20 unwritten, `unavailable` true', () async {
      final o = _open();
      final db = o.db;
      final id = await _compute(db, _stickyBuns);
      _decide(db, id, 3, 746775, 'Salt, table, iodized');
      _uncache(o.path, 746775);
      final before = [
        for (final at in [11, 15, 20]) _shape(_row(db, id, at)),
      ];
      final failing = _Failing(
        global ? FailureScope.global : FailureScope.food,
      );
      final settled = await _settle(db, failing, id, 3);
      expect(settled.unavailable, isTrue);
      expect(failing.calls, global ? 1 : 3);
      expect([
        for (final at in [11, 15, 20]) _shape(_row(db, id, at)),
      ], before);
    });
  }

  // closer 3 (verify3 D2): the `failed` shape's OTHER disjunct — the
  // compute's own RULE A note row ([engineUnavailableNote], `unmatched`, no
  // food, its raw the line's: engineUnavailable's `over`), held
  // `food_unavailable` by countFoodFailure. STATED synthesized: snapshot 32
  // holds 0 `food_unavailable` and 0 retry_count > 0 rows; the line 0002|2
  // 'onion' and its key real, the row built as engineUnavailable builds it.
  test(
    'P11a3 (arm 1, the note row): 0002|2 the `unmatched` '
    '[engineUnavailableNote] row held `food_unavailable`, stale '
    '`derived_seq`, 170000 in no cache (STATED synthesized) → derived '
    'through cacheOnly: no ask, |2 left and marked derived (mutant o24)',
    () async {
      final o = _open();
      final db = o.db;
      final id = await _compute(db, _classic);
      final line = nutritionLines(_rec(db, id))[2];
      db.upsertIngredientMatch(
        IngredientMatchRow(
          recipeId: id,
          position: 2,
          raw: line.raw,
          itemKey: lineKeyOf(line),
          fdcId: null,
          description: engineUnavailableNote,
          dataType: null,
          confidence: 0,
          grams: null,
          gramSource: null,
          status: 'unmatched',
          hold: 'food_unavailable',
          derivedSeq: 'stale',
        ),
        layoutSeq: db.layoutSeqOf(id),
      );
      _decide(db, id, 7, 170000, 'Onions, raw');
      _uncache(o.path, 170000);
      final before = _shape(_row(db, id, 2));
      final counting = _Count();
      final settled = await _settle(db, counting, id, 7);
      expect(counting.asked, isEmpty);
      expect(settled.unavailable, isFalse);
      final after = _row(db, id, 2);
      expect(
        after.derivedSeq,
        derivedKeyOf(
          db.layoutSeqOf(id),
          ingredientsHashOf(_rec(db, id), ResolverMemo(db)),
        ),
      );
      expect(_shape(after.copyWith(derivedSeq: 'stale')), before);
    },
  );

  // closer 3 (verify3 D1): a sibling whose decided-key derivation is null
  // is LEFT and the pass goes on (design_v2 §2.2). STATED synthesized: a
  // provider answering "no such food" for 746775 once, then the fixture
  // record — it stands in for the per-line null ([_decidedLineRow] through
  // the line's own carriedFoodOf move or _siblingGone), which no snapshot-32
  // line reaches; 0767's four 'table salt' lines and rows real (all `auto`
  // 173468 on snapshot 32, P12).
  test("P11d: 0767 'table salt' |3 decided 746775 in no cache, the first "
      'ask answered null (STATED synthesized) → |11 left 173468, |15 and '
      '|20 → 746775 / 1 (mutant o29)', () async {
    final o = _open();
    final db = o.db;
    final id = await _compute(db, _stickyBuns);
    _decide(db, id, 3, 746775, 'Salt, table, iodized');
    _uncache(o.path, 746775);
    final once = _NullOnce(746775);
    final settled = await _settle(db, once, id, 3);
    expect(once.asked, ['food:746775', 'food:746775']);
    expect(settled.unavailable, isFalse);
    expect(
      (_row(db, id, 11).fdcId, _row(db, id, 11).status),
      (173468, 'auto'),
    );
    for (final at in [15, 20]) {
      final s = _row(db, id, at);
      expect((s.fdcId, s.status, s.confidence), (746775, 'auto', 1.0));
    }
  });
}

const _stickyBuns = '0767-sticky-buns-with-pecans.yaml';

/// "No such food" for [fdcId] on the first ask, the fixtures after
/// (P11d's STATED synthesized per-line null).
class _NullOnce implements NutritionProvider {
  _NullOnce(this.fdcId);
  final int fdcId;
  final asked = <String>[];
  @override
  Future<List<FdcCandidate>> search(String query) {
    asked.add('search:$query');
    return _fx.search(query);
  }

  @override
  Future<FdcFood?> food(int id) async {
    asked.add('food:$id');
    if (id == fdcId && asked.where((a) => a == 'food:$id').length == 1) {
      return null;
    }
    return _fx.food(id);
  }
}

class _Failing implements NutritionProvider {
  _Failing(this.scope);
  final FailureScope scope;
  int calls = 0;
  @override
  Future<List<FdcCandidate>> search(String query) async {
    calls++;
    throw NutritionProviderException('down', scope: scope);
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    calls++;
    throw NutritionProviderException('down', scope: scope);
  }
}

/// P12 (C2-D2): the race — a person's skip lands on a sibling during the
/// settle's await; the guarded write refuses it under the unmoved layout
/// and the pass goes ON. STATED synthesized: 746775's cache row deleted and
/// a provider that writes the skip (through the store, as a PUT does)
/// before answering; 0767's four 'table salt' lines and rows real (all
/// `auto` 173468 on snapshot 32) (mutants m5, m15).
void race() {
  test(
    "P12: 0767 'table salt' |3 decided 746775; a skip on |11 during the "
    'first ask → |11 stays `skipped`, |15 and |20 → 746775 / 1, one ask',
    () async {
      final o = _open();
      final db = o.db;
      final id = await _compute(db, _stickyBuns);
      final lines = nutritionLines(_rec(db, id));
      expect(lines[3].raw, '1¼ teaspoons table salt');
      for (final at in [11, 15, 20]) {
        expect(lines[at].raw, 'Pinch table salt');
        expect(lineKeyOf(lines[at]), lineKeyOf(lines[3]));
        expect(
          (_row(db, id, at).fdcId, _row(db, id, at).status),
          (173468, 'auto'),
        );
      }
      _decide(db, id, 3, 746775, 'Salt, table, iodized');
      await cachedFood(db, _fx, 746775);
      db.upsertIngredientMatch(
        _row(db, id, 3).copyWith(
          fdcId: 746775,
          description: 'Salt, table, iodized',
          confidence: 1,
          status: 'overridden',
        ),
        layoutSeq: db.layoutSeqOf(id),
      );
      _uncache(o.path, 746775);
      var skipped = false;
      final hook = _Count(
        onFood: (fdcId) async {
          if (!skipped && fdcId == 746775) {
            skipped = true;
            db.upsertIngredientMatch(
              _row(db, id, 11).copyWith(status: 'skipped'),
              layoutSeq: db.layoutSeqOf(id),
            );
          }
        },
      );
      final settled = await _settle(db, hook, id, 3);
      expect(hook.asked, ['food:746775']);
      expect(settled.unavailable, isFalse);
      expect(
        (_row(db, id, 11).fdcId, _row(db, id, 11).status),
        (173468, 'skipped'),
      );
      for (final at in [15, 20]) {
        final s = _row(db, id, at);
        expect((s.fdcId, s.status, s.confidence), (746775, 'auto', 1.0));
      }
    },
  );
}
