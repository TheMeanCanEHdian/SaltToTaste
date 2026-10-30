// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v90 (batch M86; matcherVersion 85 — prep51 design_v2 §1 Q2
// option (b), ruled by the owner 2026-10-29; ALONE, a one-way door; zero
// requests): a Foundation record's energy is its Atwater SPECIFIC figure
// (FDC 958) before its Atwater GENERAL one (957) — the energy def's
// `fdcNumbers` ['208', '957', '958'] → ['208', '958', '957'], the one list
// every energy reader walks (`kcalPer100g`, the totals' `add`, the
// braised-share arm, `ethanolKcalPer100g`; the replay's `kcalOf`). Only
// Foundation records publish 957 / 958 and never beside 208 (snapshot 30:
// 186 publish both, 24 957 only), so SR Legacy and FNDDS rows, a
// Foundation record publishing 208 and a 957-only record count as before;
// grams, basis, gram source, status and hold never move. Every pinned row
// is a fresh compute on the fixtures and equals the v90 replay of snapshot
// 30 (fix90 gate1) except where the compute reads a search hit's rounded
// nutrients — 2685575 Brussels sprouts (958 48.8) and 2747662 poblano (957
// 28.0): 448.24, 127.01 and a6 R23's 137.71 here against the replay's
// 448.04, 126.96 and 137.67, each stated beside its pin. v89's figure in
// each comment. Never the network. Every corpus line is real.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

const _brussels = '0669-roasted-brussels-sprouts.yaml';
const _tomatoSoup = '0013-ultimate-cream-of-tomato-soup.yaml';
const _pho = '0010-vietnamese-beef-pho.yaml';
const _fajitas = '0070-skillet-chicken-fajitas.yaml';
const _meatballs = '0000-italian-style-turkey-meatballs.yaml';
const _onionRings = '0315-oven-fried-onion-rings.yaml';

/// (file, position, raw, record, gram source, grams, kcal, basis) — the
/// fresh compute's row (the v90 replay's, or a search hit's where stated).
typedef _Row = (String, int, String, int, String, String, String, String);

const List<_Row> _rows = [
  // a6 R23: the fixtures record 2685575 as the 'brussels sprouts' search
  // hit (958 48.8, 957 59.5 — FDC's rounded figures): 448.24 here, 546.52
  // at 957. The v90 replay reads the snapshot's detail (958 48.7787, 957
  // 59.485): 546.38 → 448.04.
  (
    _brussels,
    0,
    '2¼ pounds Brussels sprouts, trimmed and halved',
    2685575,
    'weight',
    '918.52',
    '448.24',
    'from 2 1/4 pound × 0.90 edible · approximate (USDA AH-102 item 423: Brussels sprouts, raw, untrimmed, good quality → trimmed, ready to cook 90 % (88–92; outer leaves 10))',
  ),
  // The largest record move (146 rows): 958 335.89, not 343.31 (v89:
  // 410.18).
  (
    _tomatoSoup,
    8,
    '½ cup heavy cream',
    2346386,
    'density',
    '119.48',
    '401.32',
    '1/2 cup ≈ 118 mL',
  ),
  // The converses, unmoved. A Foundation record publishing 208: M90's sugar
  // on 746784 (385 kcal), its grams M90's print.
  (
    _pho,
    6,
    '2 tablespoons sugar, plus extra for seasoning',
    746784,
    'density',
    '24.81',
    '95.50',
    '2 tablespoon ≈ 30 mL · approximate (ATK: 1 cup sugar = 7 ounces)',
  ),
  // A Foundation record publishing 957 only: it falls back to 957 — the
  // 'poblano chiles' hit's 28.0 here (the replay's detail 27.9906: 126.96,
  // unmoved).
  (
    _fajitas,
    10,
    '1 pound (3 to 4) poblano chiles, stemmed, halved, and seeded',
    2747662,
    'weight',
    '453.59',
    '127.01',
    'from 1 pound',
  ),
  // SR Legacy (208 392): byte-unchanged.
  (
    _meatballs,
    3,
    '1 ounce Parmesan cheese, grated (½ cup), plus extra for serving',
    170848,
    'weight',
    '28.35',
    '111.13',
    'from 1 ounce',
  ),
];

/// The calibration recipes' (status, kcal per serving) — the fresh compute
/// on the recorded fixtures; the replay's in the comment.
const Map<String, (String, String)> _totals = {
  // a6 R23 on the search hit's 48.8 (the v90 replay's detail: 154.06 →
  // 137.67; calibrator 2's own 958 re-hand 137.67, audit 6).
  _brussels: ('complete', '137.71'),
  _onionRings: ('complete', '541.73'), // a6 R03, no 958 row: v89 541.73
};

void main() {
  test('matcherVersion 91 (v90 set it to 85, batch M86: rows move)', () {
    // RE-PIN (M87 batch, v91): matcherVersion 86 (was 85).
    // RE-PIN (M89 batch, v92): matcherVersion 87 (was 86).
    // RE-PIN (M91 batch, v93): matcherVersion 88 (was 87).
    // RE-PIN (M92 batch, v94): matcherVersion 89 (was 88).
    // RE-PIN (M93 batch, v95): matcherVersion 90 (was 89).
    // RE-PIN (M94 batch, v96): matcherVersion 91 (was 90).
    expect(matcherVersion, 91);
  });

  test('the energy def reads 208, then 958 (Specific Atwater), then 957 '
      '(General)', () async {
    expect(nutrientDefs.first.key, 'energy');
    expect(nutrientDefs.first.fdcNumbers, ['208', '958', '957']);
    final fdc = FixtureProvider();
    // Brussels sprouts 2685575 is recorded as a search hit only.
    final sprouts = (await fdc.search(
      'brussels sprouts',
    )).singleWhere((c) => c.fdcId == 2685575).toFood();
    expect(kcalPer100g(sprouts).toStringAsFixed(4), '48.8000'); // 957 59.5
    for (final (fdcId, kcal) in [
      (2346386, '335.8933'), // heavy cream; 957 343.3100
      (2747662, '27.9906'), // poblano: 957 only, its fallback
      (746784, '385.0000'), // Foundation granulated sugar: 208
      (170848, '392.0000'), // SR Legacy Parmesan: 208
    ]) {
      final food = (await fdc.food(fdcId))!;
      expect(kcalPer100g(food).toStringAsFixed(4), kcal, reason: '$fdcId');
    }
  });

  group('matcher v90 (batch M86) — whole recipes', skip: skipIfNoCorpus, () {
    // Each recipe in its own fresh database: a food detail another
    // recipe's compute caches would change what an earlier recipe's rows
    // read (a search hit's rounded nutrients, then the detail).
    final dbs = <String, SaltDatabase>{};
    late FixtureProvider fdc;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      fdc = FixtureProvider(pending: {...pendingSearches});
      for (final file in {for (final r in _rows) r.$1, ..._totals.keys}) {
        final dir = Directory.systemTemp.createTempSync('salt-v90-');
        final db = dbs[file] = SaltDatabase.open(
          ServerConfig(
            dataDir: dir.path,
            logLevel: Level.WARNING,
            trustProxy: false,
          ).dbPath,
        )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
        addTearDown(() {
          db.dispose();
          dir.deleteSync(recursive: true);
        });
        recipes[file] = await _compute(db, fdc, loadCorpusRecipe(file));
      }
    });

    String kcalOf(SaltDatabase db, IngredientMatchRow row) {
      final food = knownFood(db, nutrientSiblings[row.fdcId] ?? row.fdcId!)!;
      return (kcalPer100g(food) * (row.grams ?? 0) / 100).toStringAsFixed(2);
    }

    test('each row its record, source, grams, energy and basis (the v90 '
        "replay's): the 958 rows move in energy only, the converses not at "
        'all', () {
      for (final (file, position, raw, fdcId, source, grams, kcal, basis)
          in _rows) {
        final recipe = recipes[file]!;
        final db = dbs[file]!;
        final line = nutritionLines(recipe)[position];
        final row = _row(db, recipe.id, position);
        final reason = '$file|$position';
        expect(line.raw, raw, reason: reason);
        expect(
          (row.fdcId, row.status, row.hold, row.gramSource),
          (fdcId, 'auto', null, source),
          reason: reason,
        );
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(kcalOf(db, row), kcal, reason: reason);
        expect(
          gramBasisFor(db, line, row, recipe: recipe),
          basis,
          reason: reason,
        );
      }
    });

    test('the calibration totals (status, kcal per serving): R23 moves, R03 '
        'does not', () {
      for (final MapEntry(key: file, value: want) in _totals.entries) {
        final n = dbs[file]!.nutritionFor(recipes[file]!.id)!;
        expect(
          (n.status, n.caloriesPerServing?.toStringAsFixed(2)),
          want,
          reason: file,
        );
      }
    });

    test('a second compute writes nothing: every row and total as the first '
        'compute left it', () async {
      for (final file in recipes.keys) {
        final id = recipes[file]!.id;
        final db = dbs[file]!;
        List<Object?> rowsOf() => [
          for (final m in db.ingredientMatchesFor(id))
            (m.position, m.fdcId, m.grams, m.gramSource, m.status, m.hold),
        ];
        final rows = rowsOf();
        final totals = db.nutritionFor(id)!.totalsJson;
        expect(
          await matchAndCompute(db, fdc, nutritionRecipeOf(db, id)!.recipe),
          isNull,
        );
        expect(rowsOf(), rows, reason: file);
        expect(db.nutritionFor(id)!.totalsJson, totals, reason: file);
      }
    });
  });
}

/// [r] stored and computed (its section children first).
Future<Recipe> _compute(
  SaltDatabase db,
  NutritionProvider fdc,
  Recipe r,
) async {
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
