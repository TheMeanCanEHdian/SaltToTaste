// Matcher v95 (batch M93; matcherVersion 90 — the C4 pan-fat share; prep51
// design_v2 §1 Q3 Part A option (b) / §2 M93, ruled by the owner
// 2026-10-29; zero requests). `_panFatShare` (engine.dart) was FNDDS
// 2705980's own oil per raw breast (2 g per 125.77 g = 1.5902 %); it is now
// derived from two FNDDS recipes, both already in the tree and on disk
// (.claude/diag/2026-10-07/live47_raw/2705975.json, live55_raw/
// 2705980.json): 2705975 "Chicken breast, fried, coated, prepared skinless,
// coating eaten, from raw" — 7 g "Vegetable oil, NFS" (82101000) per 15 g
// breading (99995000) — at 2705980 "Chicken breast, baked, coated, skin /
// coating eaten" — 10 g breading per 125.77 g raw breast (its 88 g cooked
// breast brought to raw by protein, prep47 p3_read_figures.md) — 7 / 15 ×
// 10 / 125.77 = 3.7105 %. The split over the lines' fat (204), the cap at
// the whole line and `_panFatLines` are unchanged; `_panFatFlag` names both
// records. REACH (fix95 gate1, the v94 rows of snapshot 30): exactly the six
// C4 pan rows of chicken-saltimbocca, chicken-francese, fish-meunière and
// parmesan-crusted-chicken-cutlets (none capped) and their four totals.
// Every whole-recipe figure is a fresh compute on the recorded fixtures
// (FixtureProvider) — the replay's in each comment. Never the network.
// Every corpus line is real; STATED synthesized (no corpus row sits at the
// cap under either share): saltimbocca with its pan line |5 replaced by
// another REAL corpus line — 0067's "1 tablespoon olive oil" (14.00 g, now
// capped: the breast keeps 23.14 g of fat) or 0258's "1 teaspoon olive oil"
// (4.53 g, capped under both shares) — the v78 constructions.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _parmesan = '0419-parmesan-crusted-chicken-cutlets.yaml';
const _francese = '0420-chicken-francese.yaml';
const _saltimbocca = '0421-chicken-saltimbocca.yaml';
const _meuniere = '0466-fish-meuniere-with-browned-butter-and-lemon.yaml';
const _piccata = '0418-chicken-piccata.yaml';
const _blackened = '1124-blackened-chicken.yaml';

/// The v94 flag (the v94 replay's rows, verbatim) — no row prints it now.
const _oldFlag =
    'approximation (pan fat: 1.59 g fat per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 2 g oil per 125.77 g raw chicken breast (no record for the fat a sautéed piece keeps; the steps pour off / wipe out the rest))';

/// The v95 basis of a pan line on the raw [food] (the fix95 gate1 rows).
String _pan(String food, {bool butter = false}) =>
    "discarded in cooking — only the fat the sautéed food keeps counted · approximation (pan fat: 3.71 g fat per 100 g of the raw $food — derived from two USDA FNDDS recipes: 2705975's 7 g oil per 15 g breading × 2705980's 10 g breading per 125.77 g raw chicken breast (no record for the fat a sautéed piece keeps; the steps pour off / wipe out the rest)${butter ? '; a butter line weighed by its own fat' : ''})";

/// The six rows (file, position, raw, record, whole grams, grams, kcal,
/// basis) — the v94 → v95 replay's grams / kcal in each comment.
final _reach = [
  // 9.92 → 23.14 g, 89.28 → 208.26 kcal.
  (
    _saltimbocca,
    5,
    '4 tablespoons olive oil',
    2710186,
    '56.00',
    '23.14',
    '208.26',
    _pan('chicken breast'),
  ),
  // 5.44 → 12.70 g, 48.96 → 114.30.
  (
    _francese,
    13,
    '2 tablespoons olive oil',
    2710186,
    '28.00',
    '12.70',
    '114.30',
    _pan('chicken breast'),
  ),
  // 5.51 → 12.87 g, 39.51 → 92.28.
  (
    _francese,
    12,
    '2 tablespoons unsalted butter',
    173430,
    '28.36',
    '12.87',
    '92.28',
    _pan('chicken breast', butter: true),
  ),
  // 5.44 → 12.70 g, 48.96 → 114.30.
  (
    _meuniere,
    3,
    '2 tablespoons vegetable oil',
    2710180,
    '28.00',
    '12.70',
    '114.30',
    _pan('flatfish'),
  ),
  // 5.51 → 12.87 g, 39.51 → 92.28.
  (
    _meuniere,
    4,
    '2 tablespoons unsalted butter, cut into 2 pieces',
    173430,
    '28.36',
    '12.87',
    '92.28',
    _pan('flatfish', butter: true),
  ),
  // 6.76 → 15.78 g, 60.84 → 142.02 — below its 18.14 g whole: uncapped.
  (
    _parmesan,
    6,
    '4 teaspoons olive oil',
    2710186,
    '18.14',
    '15.78',
    '142.02',
    _pan('chicken breast'),
  ),
];

/// (file, per serving, batch energy, total grams) after the compute — the
/// v94 → v95 replay's per serving in each comment. Every row of the four
/// equals the replay but the breast's: the Foundation chicken breast 2646170
/// (623.69 g; 425.24 g on parmesan-crusted) prices on the fixtures at its
/// search HIT's rounded 958, 112.0 kcal per 100 g, against snapshot 30's
/// DETAIL, 112.20227 (698.53 vs 699.79 kcal; 476.27 vs 477.13) — the
/// standing offset v61 / v68 / v78 already pin (332.99 / 357.13 / 417.18 at
/// v94 against the replay's 333.21 / 357.45 / 417.49), untouched by M93: the
/// per-serving moves equal the replay's to the cent of rounding.
const _totals = [
  // replay 417.49 → 447.24 (+29.75); fixtures 417.18 → 446.92 (+29.74).
  (_saltimbocca, '446.92', '1787.69', '1121.6'),
  // replay 357.45 → 386.97 (+29.52); fixtures 357.13 → 386.66 (+29.53).
  (_francese, '386.66', '1546.63', '1527.7'),
  // replay 258.01 → 287.54 (+29.53); fixtures equal the replay.
  (_meuniere, '287.54', '1150.15', '758.2'),
  // replay 333.21 → 353.50 (+20.29); fixtures 332.99 → 353.29 (+20.30).
  (_parmesan, '353.29', '1413.14', '658.7'),
];

/// Rows the share does not reach (file, position, raw, grams, source) — the
/// v94 replay's rows, unchanged in v95.
const _converses = [
  // A pan-fat-window line ([panFatLinesOf]) in a recipe that is no dredged
  // pan-fry (not C4): the window weighs nothing there.
  (_blackened, 10, '1 teaspoon vegetable oil', '4.53', 'density'),
  // A C4 recipe whose steps neither pour off the fat nor wipe the skillet.
  (_piccata, 4, '4 tablespoons vegetable oil', '56.00', 'portion'),
  // A fat before the dredge (francese's sauce butter, S2).
  (_francese, 0, '3 tablespoons unsalted butter', '42.54', 'density'),
];

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

SaltDatabase _db() {
  final dir = Directory.systemTemp.createTempSync('salt-v95-');
  final db = SaltDatabase.open(
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
  return db;
}

void main() {
  test(
    'matcherVersion 92 (v95 set it to 90, batch M93: six rows, four totals)',
    () {
      // RE-PIN (M94 batch, v96): matcherVersion 91 (was 90).
      // RE-PIN (M95 batch, v97): matcherVersion 92 (was 91).
      expect(matcherVersion, 92);
    },
  );

  test("the share from the four figures the flag prints (2705975's o 7, b "
      "15; 2705980's b 10, r 125.77 — the raw JSONs' inputFoods and "
      "prep47's raw-by-protein r): 7 / 15 × 10 / 125.77 = 0.037105 (was "
      "2 / 125.77 = 0.015902) — the engine's own `_panFatShare`", () {
    // CLOSER 1 (verify1 D1): the engine's figure itself, through
    // `panFatShareForTest` — the same four parses in the same order, so
    // exactly equal; a share hard-coded at the rounded 3.71 % (0.0371, the
    // brief's figure) passed every grams pin and the flag's two places.
    expect(panFatShareForTest, 7 / 15 * 10 / 125.77);
    expect(panFatShareForTest.toStringAsFixed(6), '0.037105');
    expect((7 / 15 * 10 / 125.77).toStringAsFixed(6), '0.037105');
    expect((2 / 125.77).toStringAsFixed(6), '0.015902');
    expect((7 / 15 * 10 / 125.77 * 100).toStringAsFixed(2), '3.71');
  });

  group('matcher v95 (batch M93)', skip: skipIfNoCorpus, () {
    late SaltDatabase db;
    late FixtureProvider fdc;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      db = _db();
      fdc = FixtureProvider(pending: {...pendingSearches});
      for (final file in {
        for (final r in _reach) r.$1,
        for (final r in _converses) r.$1,
      }) {
        recipes[file] = await _compute(db, fdc, loadCorpusRecipe(file));
      }
    });

    IngredientMatchRow rowIn(String id, int position) =>
        db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

    String? basisOf(Recipe recipe, int position) => gramBasisFor(
      db,
      nutritionLines(recipe)[position],
      rowIn(recipe.id, position),
      recipe: recipe,
    );

    String kcalOf(IngredientMatchRow row) =>
        (kcalPer100g(
                  knownFood(db, nutrientSiblings[row.fdcId] ?? row.fdcId!)!,
                ) *
                row.grams! /
                100)
            .toStringAsFixed(2);

    /// [corpus] with its line [position] (one group) replaced by the real
    /// corpus line [raw] of [from] (STATED synthesized).
    Recipe withLine(Recipe corpus, int position, String from, String raw) {
      final line = nutritionLines(
        loadCorpusRecipe(from),
      ).firstWhere((l) => l.raw == raw);
      final group = corpus.ingredients.single;
      return corpus.copyWith(
        id: '${corpus.id}-v95-$position',
        slug: '${corpus.slug}-v95-$position',
        ingredients: [
          group.copyWith(
            items: [
              for (final (i, l) in group.items.indexed)
                i == position ? line : l,
            ],
          ),
        ],
      );
    }

    test('the six rows at the new share: record, status, grams, energy, '
        'basis — each below its whole line (none capped)', () {
      for (final (file, position, raw, fdcId, whole, grams, kcal, basis)
          in _reach) {
        final recipe = recipes[file]!;
        final row = rowIn(recipe.id, position);
        final reason = '$file|$position';
        expect(nutritionLines(recipe)[position].raw, raw, reason: reason);
        expect(
          (
            row.fdcId,
            row.status,
            row.hold,
            row.gramSource,
            row.grams?.toStringAsFixed(2),
            kcalOf(row),
          ),
          (fdcId, 'auto', null, 'discarded', grams, kcal),
          reason: reason,
        );
        expect(basisOf(recipe, position), basis, reason: reason);
        expect(basisOf(recipe, position), isNot(contains(_oldFlag)));
        final record = knownFood(db, fdcId)!;
        expect(
          lineGrams(
            db,
            nutritionLines(recipe)[position],
            record,
            recipe: recipe,
          )!.grams.toStringAsFixed(2),
          whole,
          reason: reason,
        );
        expect(row.grams, lessThan(double.parse(whole)), reason: reason);
      }
    });

    test("the split by the lines' own fat (204): meunière's sole 623.69 g × "
        '0.037105 = 23.142 g of fat over 28.00 g of oil at 100 % and 28.36 g '
        'of butter at 81.11 % — 12.70 g and 12.87 g', () {
      final sole = rowIn(recipes[_meuniere]!.id, 1).grams!;
      expect(sole.toStringAsFixed(2), '623.69');
      final fat = sole * 7 / 15 * 10 / 125.77;
      expect(fat.toStringAsFixed(3), '23.142');
      final kept = fat / (28.00 * 1.00 + 28.36 * 0.8111);
      expect((kept * 28.00).toStringAsFixed(2), '12.70');
      expect((kept * 28.36).toStringAsFixed(2), '12.87');
      expect(rowIn(recipes[_meuniere]!.id, 4).grams, 12.87);
      expect(rowIn(recipes[_meuniere]!.id, 3).grams, 12.70);
    });

    test('the four totals: status, per serving, batch energy, total grams', () {
      expect(
        [
          for (final (file, _, _, _) in _totals)
            (
              file,
              db.nutritionFor(recipes[file]!.id)!.status,
              db
                  .nutritionFor(recipes[file]!.id)!
                  .caloriesPerServing
                  ?.toStringAsFixed(2),
              batchTotalsOf(
                db.nutritionFor(recipes[file]!.id)!,
              )['energy']!.toStringAsFixed(2),
              db
                  .nutritionFor(recipes[file]!.id)!
                  .totalGrams
                  ?.toStringAsFixed(1),
            ),
        ],
        [
          for (final (file, perServing, energy, grams) in _totals)
            (file, 'complete', perServing, energy, grams),
        ],
      );
    });

    test('the converses keep their v94 rows: no pan-fat basis', () {
      for (final (file, position, raw, grams, source) in _converses) {
        final recipe = recipes[file]!;
        final row = rowIn(recipe.id, position);
        final reason = '$file|$position';
        expect(nutritionLines(recipe)[position].raw, raw, reason: reason);
        expect(
          (row.grams?.toStringAsFixed(2), row.gramSource),
          (grams, source),
          reason: reason,
        );
        expect(basisOf(recipe, position), isNot(contains('pan fat')));
      }
      // blackened-chicken's line IS in a pan-fat window; the window weighs
      // only under C4 (a dredged pan-fry).
      expect(panFatLinesOf(recipes[_blackened]!), contains(10));
      expect(panFatLinesOf(recipes[_piccata]!), isEmpty);
    });

    test('the GET shows the new basis (saltimbocca|5, meunière|4)', () async {
      for (final (file, position, basis) in [
        (_saltimbocca, 5, _pan('chicken breast')),
        (_meuniere, 4, _pan('flatfish', butter: true)),
      ]) {
        final items =
            ((await matchesBody(db, fdc, recipes[file]!))['items']! as List)
                .cast<Map<String, Object?>>();
        final item = items.singleWhere((i) => i['position'] == position);
        expect(
          (item['match']! as Map<String, Object?>)['gram_basis'],
          basis,
          reason: '$file|$position',
        );
      }
    });

    test("the cap at the whole line — STATED synthesized: saltimbocca's pan "
        'line |5 as 0067\'s real "1 tablespoon olive oil" (14.00 g: the '
        'v94 share kept 9.92 g of it, the breast now keeps 23.14 g of fat — '
        'capped, the whole line) and as 0258\'s real "1 teaspoon olive oil" '
        '(4.53 g, capped under both shares)', () async {
      for (final (from, raw, grams) in const [
        ('0067-skillet-lasagna.yaml', '1 tablespoon olive oil', '14.00'),
        (
          '0258-broiled-salmon-with-mustard-and-crisp-dilled-crust.yaml',
          '1 teaspoon olive oil',
          '4.53',
        ),
      ]) {
        final r = await _compute(
          db,
          fdc,
          withLine(loadCorpusRecipe(_saltimbocca), 5, from, raw),
        );
        final row = rowIn(r.id, 5);
        expect(
          (row.fdcId, row.gramSource, row.grams?.toStringAsFixed(2)),
          (2710186, 'discarded', grams),
          reason: raw,
        );
        expect(basisOf(r, 5), _pan('chicken breast'), reason: raw);
      }
    });

    test('a second compute writes nothing: every row and total of the '
        'computed recipes as the first compute left it', () async {
      for (final file in recipes.keys) {
        final id = recipes[file]!.id;
        List<Object?> rowsOf() => [
          for (final m in db.ingredientMatchesFor(id))
            (
              m.position,
              m.fdcId,
              m.confidence,
              m.grams,
              m.gramSource,
              m.status,
              m.hold,
            ),
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
