// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v88 (batch M88; matcherVersion 83 — the dredge's own figure;
// prep51 design_v2 §1 Q4 (b) / §2 M88, ruled under the 2026-10-07 standing
// authorization; zero requests). FNDDS 2706442 "Chicken or turkey
// parmigiana" (live62_raw/2706442.json, inputFoods by sequenceNumber) lists
// its breading as SEPARATE inputs — 3 flour 31.25 g (Foundation 789890),
// 4 egg 100 g, 5 dry crumbs 81 g (SR 174928) — per 1 + 10 raw chicken
// breast 510.3 + 170.1 = 680.4 g. Under `_coatFigure`'s 2706442 read the
// coat's budgeted parts on a `Flour,` record are the DREDGE and share f_d
// = min(1, 3.55 × raw ÷ 100 ÷ Σ dredge × carbohydrate); every other part is
// the CRUMB layer and shares f_c = min(1, 11.905 × raw ÷ 100 ÷ Σ w), w = a
// `Bread,` part's dredge × its carbohydrate ÷ 0.7198 (SR 174928's dry
// crumbs), any other part (Nuts, Cheese) its own dredge grams. B (12.12)
// and the dips' W unchanged; a group with no part counts nothing. REACH
// (the v88 replay of snapshot 29 vs the v87 rows, fix88 g1): exactly the
// ten coat parts of chicken-kiev, lighter-chicken-parmesan,
// stuffed-chicken-cutlets and nut-crusted-chicken-breasts. Every pinned
// ROW equals that replay on every pinned field; every whole-recipe value
// is the fresh compute over recorded real FDC answers (FixtureProvider;
// this file records none). Never the network. Every corpus line is real.
// STATED construction: a person's typed grams through the real PUT (the
// person path — no corpus row types grams).

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

const _kiev = '0122-chicken-kiev.yaml';
const _lighter = '0416-lighter-chicken-parmesan.yaml';
const _stuffed = '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml';
const _nut = '0117-nut-crusted-chicken-breasts-with-lemon-and-thyme.yaml';
const _breaded = '0114-breaded-chicken-cutlets.yaml';
const _eggplant = '0407-eggplant-parmesan.yaml';
const _almond = '0042-almond-crusted-chicken-with-wilted-spinach-salad.yaml';
const _easier = '0149-easier-fried-chicken.yaml';
const _piccata = '0418-chicken-piccata.yaml';
const _rings = '0315-oven-fried-onion-rings.yaml';

/// The 2706442 coat flag (engine `_coatFlag`; docs/API.md's "Matcher v88"
/// section quotes it character for character).
const _flag =
    "approximation (coat: 31.25 g flour and 81 g dry crumbs per 680.4 g raw chicken breast — USDA FNDDS 2706442 recipe: flour (Foundation 789890) and dry crumbs (SR 174928) as separate inputs, 3.55 g flour carbohydrate and 11.905 g dry crumbs per 100 g raw (the dredge sized by the flour, the crumbs by their dry mass; a fresh bread brought to dry crumbs by carbohydrate); the record's 18.75 g grated Parmesan follows its mozzarella and sauce — a topping, not read; the dredge's excess not counted)";

/// The nut crust's stand-in clause, by mass since v88.
const _nutStandIn =
    " (no record for a nut crust; read as FNDDS 2706442's crumb crust by mass)";

/// A coat part's basis; [nut]: nut-crusted's stand-in.
String _crumb({bool nut = false}) =>
    'discarded in cooking — only the coat on the food counted · ${nut ? _flag.replaceFirst('; the record', '$_nutStandIn; the record') : _flag}';

/// A dip line's basis ([dijon]: the M73 mustard stand-in first) — unchanged.
String _dip({bool dijon = false}) =>
    'discarded in cooking — only the dip on the food counted · ${dijon ? 'approximate (FDC holds no Dijon mustard — counted as prepared yellow mustard) · ' : ''}approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)';

/// The ten parts M88 moves and the four recipes' dips (file, position, raw,
/// fdc id, grams, kcal, basis) — the v88 replay's; the v87 replay's in each
/// comment, and the share that moved it.
final _reach = [
  // Pin (1). v87 73.34 g, 268.42 kcal (the one f). f_d: 39.06 × 0.773 =
  // 30.19 g carbohydrate = 3.55 × 850.49 / 100 (the dredge's budget).
  (
    _kiev,
    11,
    '1 cup unbleached all-purpose flour',
    789890,
    '39.06',
    '142.96',
    _crumb(),
  ),
  // Pin (6). v87 93.87 g, 249.69. f_c below 1: 147.47 × 0.4942 / 0.7198 =
  // 101.25 g dry = 11.905 × 850.49 / 100 — four 45.36 g slices (M82's C1)
  // weigh 181.44 g, f_c 0.8128.
  (
    _kiev,
    7,
    '4 slices high-quality white sandwich bread, torn into quarters',
    174924,
    '147.47',
    '392.27',
    _crumb(),
  ),
  // Pin (5): the dips unchanged (W = 1.173 × B, B = 12.12 × raw / 100).
  (_kiev, 12, '3 large eggs, beaten', 748967, '116.88', '172.98', _dip()),
  (
    _kiev,
    13,
    '1 teaspoon Dijon mustard',
    326698,
    '4.03',
    '2.46',
    _dip(dijon: true),
  ),
  // v87 57.37 g, 226.61. f_c: panko on SR 174928 itself is its own dry
  // mass; 57.55 + the Parmesan's 18.39 = 75.94 = 11.905 × 637.86 / 100.
  (
    _lighter,
    0,
    '1½ cups panko (Japanese-style bread crumbs)',
    174928,
    '57.55',
    '227.32',
    _crumb(),
  ),
  // Pin (4). v87 18.33 g, 71.85 (SR 170848 since v87). f_c: a Cheese part
  // by its own mass.
  (
    _lighter,
    2,
    '1 ounce Parmesan cheese, grated (about ½ cup), plus extra for serving',
    170848,
    '18.39',
    '72.09',
    _crumb(),
  ),
  // v87 45.83 g, 167.74. f_d: 29.29 × 0.773 = 22.64 = 3.55 × 637.86 / 100.
  (
    _lighter,
    3,
    '½ cup unbleached all-purpose flour',
    789890,
    '29.29',
    '107.20',
    _crumb(),
  ),
  (_lighter, 6, '3 large egg whites', 747997, '90.69', '49.88', _dip()),
  // v87 46.76 g, 171.14. f_d: 28.64 × 0.773 = 22.14 = 3.55 × 623.69 / 100.
  (
    _stuffed,
    10,
    '¾ cup unbleached all-purpose flour',
    789890,
    '28.64',
    '104.82',
    _crumb(),
  ),
  (_stuffed, 11, '2 large eggs', 748967, '88.67', '131.23', _dip()),
  // Pin (3). v87 79.81 g, 212.29. f_c at the crumbs' budget: 108.15 ×
  // 0.4942 / 0.7198 = 74.25 g dry = 11.905 × 623.69 / 100 (f_c 0.5961; by its
  // own fresh mass it would be 74.25 g).
  (
    _stuffed,
    13,
    '4 slices high-quality white sandwich bread, pulsed in a food processor to coarse crumbs and dried',
    174924,
    '108.15',
    '287.68',
    _crumb(),
  ),
  // Pin (2). v87 75.19 g, 435.35. f_c: a Nuts part by its own mass; 66.85 +
  // the panko's 27.65 = 94.50 = 11.905 × 793.79 / 100.
  (
    _nut,
    2,
    '1 cup almonds, chopped coarse',
    170567,
    '66.85',
    '387.06',
    _crumb(nut: true),
  ),
  // v87 31.10 g, 122.84. f_c.
  (
    _nut,
    5,
    '1 cup panko bread crumbs',
    174928,
    '27.65',
    '109.22',
    _crumb(nut: true),
  ),
  // v87 74.54 g, 272.82. f_d: 36.45 × 0.773 = 28.18 = 3.55 × 793.79 / 100.
  (
    _nut,
    9,
    '1 cup unbleached all-purpose flour',
    789890,
    '36.45',
    '133.41',
    _crumb(nut: true),
  ),
  (_nut, 10, '3 large eggs', 748967, '105.19', '155.68', _dip()),
  (
    _nut,
    11,
    '2 teaspoons Dijon mustard',
    326698,
    '7.26',
    '4.43',
    _dip(dijon: true),
  ),
  (_nut, 12, '¼ teaspoon ground black pepper', 170931, '0.41', '1.03', _dip()),
];

/// Pin (9) — rows M88 must not move (file, position, raw, fdc id, grams,
/// kcal, the coat head their basis carries): every other coat read keeps
/// the one f — the C1 crusts (a `Flour,` beside a `Bread,` part, and a nut
/// crust, on 2705975), the eggplant's own arm (a flour, a bread and a
/// cheese part on 2710050), C2's default (no crumb part), C4, the onion
/// rings. Each equal to the v87 and v88 replays.
const _negatives = [
  (
    _breaded,
    2,
    '3 slices high-quality white sandwich bread, torn into quarters',
    174924,
    '32.54',
    '86.56',
    'coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975',
  ),
  (
    _breaded,
    3,
    '¾ cup unbleached all-purpose flour',
    789890,
    '25.43',
    '93.07',
    'coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975',
  ),
  (
    _eggplant,
    2,
    '8 slices high-quality white sandwich bread, torn into quarters',
    174924,
    '89.79',
    '238.84',
    'coat: 7.93 g carbohydrate per 100 g of the raw eggplant — USDA FNDDS 2710050',
  ),
  (
    _eggplant,
    3,
    '2 ounces Parmesan cheese, grated (about 1 cup)',
    170848,
    '14.03',
    '55.00',
    'coat: 7.93 g carbohydrate per 100 g of the raw eggplant — USDA FNDDS 2710050',
  ),
  (
    _eggplant,
    5,
    '1 cup unbleached all-purpose flour',
    789890,
    '35.07',
    '128.36',
    'coat: 7.93 g carbohydrate per 100 g of the raw eggplant — USDA FNDDS 2710050',
  ),
  (
    _almond,
    2,
    '1 cup sliced almonds',
    170567,
    '79.97',
    '463.03',
    'coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975',
  ),
  (
    _almond,
    3,
    '½ cup panko (Japanese-style bread crumbs)',
    174928,
    '25.71',
    '101.55',
    'coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975',
  ),
  (
    _easier,
    8,
    '2 cups unbleached all-purpose flour',
    789890,
    '45.60',
    '166.90',
    'coat: 3.18 g carbohydrate per 100 g of the raw chicken — USDA FNDDS 2705980',
  ),
  (
    _piccata,
    3,
    '½ cup unbleached all-purpose flour',
    789890,
    '27.99',
    '102.44',
    'coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980',
  ),
  (
    _rings,
    0,
    '½ cup unbleached all-purpose flour',
    789890,
    '70.87',
    '259.38',
    'coat: 50.53 g carbohydrate per 100 g of the raw onions — USDA FNDDS 2710042',
  ),
];

/// Each crumb-crust recipe's (status, kcal per serving, total grams) — the
/// fresh compute (other rows' search-hit energies recorded from earlier
/// snapshots differ from the library's; the pinned rows are equal); the
/// v88 replay's per serving in the comment, then v87's replay.
const Map<String, (String, String, String)> _totals = {
  _kiev: ('complete', '672.63', '1331.00'), // replay 672.70; v87 668.42
  _lighter: ('complete', '288.46', '1768.80'), // replay 288.50; v87 298.43
  _stuffed: ('complete', '641.32', '1274.70'), // replay 641.38; v87 639.11
  _nut: ('complete', '515.98', '1129.30'), // replay 516.05; v87 566.38
};

void main() {
  test('matcherVersion 83 (v88, batch M88: rows move)', () {
    expect(matcherVersion, 83);
  });

  test("pin (7) — the figures: FNDDS 2706442's two inputs by sequenceNumber "
      '(3 flour 31.25 g, 5 dry crumbs 81 g; 1 + 10 raw breast 510.3 + 170.1 '
      'g) on the records the coat reads (Foundation 789890 77.3 %, SR 174928 '
      '71.98 % carbohydrate): the dredge 3.55 g carbohydrate and the crumbs '
      '11.905 g dry per 100 g raw, beside the whole k 12.12 (nutrition_v80) '
      'and the crumbs by carbohydrate 8.57 (option (a), not built)', () async {
    final provider = FixtureProvider();
    final flour = (await provider.food(789890))!.nutrientsPer100g['205']!;
    final crumbs = (await provider.food(174928))!.nutrientsPer100g['205']!;
    expect((flour, crumbs), (77.3, 71.98));
    const raw = 510.3 + 170.1;
    expect(raw.toStringAsFixed(1), '680.4');
    expect((31.25 * flour / raw).toStringAsFixed(2), '3.55');
    expect((81 / raw * 100).toStringAsFixed(3), '11.905');
    expect((81 * crumbs / raw).toStringAsFixed(2), '8.57');
    expect(
      ((31.25 * flour + 81 * crumbs) / raw).toStringAsFixed(2),
      '12.12',
    );
    // SR 174928's carbohydrate per gram: a fresh bread's dry-crumb mass.
    expect((crumbs / 100).toStringAsFixed(4), '0.7198');
  });

  group('matcher v88 (batch M88) — whole recipes', skip: skipIfNoCorpus, () {
    // Each recipe in its own fresh database (nutrition_v87's reason: a
    // food detail another recipe's compute caches changes a later read).
    final dbs = <String, SaltDatabase>{};
    late FixtureProvider fdc;
    final recipes = <String, Recipe>{};

    SaltDatabase freshDb() {
      final dir = Directory.systemTemp.createTempSync('salt-v88-');
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

    setUpAll(() async {
      fdc = FixtureProvider(pending: {...pendingSearches});
      for (final file in {
        for (final r in _reach) r.$1,
        for (final r in _negatives) r.$1,
      }) {
        final db = dbs[file] = freshDb();
        recipes[file] = await _compute(db, fdc, loadCorpusRecipe(file));
      }
    });

    String kcalOf(SaltDatabase db, IngredientMatchRow row) {
      final food = knownFood(db, nutrientSiblings[row.fdcId] ?? row.fdcId!)!;
      return (kcalPer100g(food) * (row.grams ?? 0) / 100).toStringAsFixed(2);
    }

    String? basisOf(String file, int position) {
      final recipe = recipes[file]!;
      return gramBasisFor(
        dbs[file]!,
        nutritionLines(recipe)[position],
        _row(dbs[file]!, recipe.id, position),
        recipe: recipe,
      );
    }

    test('pins (1)–(6): the ten parts and the dips — record, source, grams, '
        "energy and basis (the v88 replay's); the flour parts at f_d, the "
        'crumb, nut and cheese parts at f_c, the dips at v87', () {
      expect(_reach, hasLength(17));
      for (final (file, position, raw, fdcId, grams, kcal, basis) in _reach) {
        final recipe = recipes[file]!;
        final db = dbs[file]!;
        final row = _row(db, recipe.id, position);
        final reason = '$file|$position';
        expect(nutritionLines(recipe)[position].raw, raw, reason: reason);
        expect(
          (row.fdcId, row.status, row.hold, row.gramSource),
          (fdcId, 'auto', null, 'discarded'),
          reason: reason,
        );
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(kcalOf(db, row), kcal, reason: reason);
        expect(basisOf(file, position), basis, reason: reason);
      }
    });

    test(
      "the two budgets by arithmetic on each recipe's own rows: the flour "
      "parts' carbohydrate = 3.55 × the coated breast's raw grams / 100, the "
      "crumb parts' dry-crumb mass (a `Bread,` part's grams × its "
      'carbohydrate ÷ 0.7198, a nut or cheese part its grams) = 11.905 × '
      "raw / 100 — each to the parts' rounding; and the two fresh-bread "
      'lines weigh 181.44 g whole (four 45.36 g slices), so kiev|7 sits '
      'below its line (f_c 0.8128) and stuffed|13 at its budget (0.5961)',
      () {
        for (final (file, coated, raw) in [
          (_kiev, 10, '850.49'),
          (_lighter, 8, '637.86'),
          (_stuffed, 8, '623.69'),
          (_nut, 0, '793.79'),
        ]) {
          final db = dbs[file]!;
          final id = recipes[file]!.id;
          final food = _row(db, id, coated);
          expect(
            (food.description, food.grams?.toStringAsFixed(2)),
            ('Chicken, breast, boneless, skinless, raw', raw),
            reason: file,
          );
          var dredge = 0.0;
          var dry = 0.0;
          for (final (f, position, _, _, _, _, basis) in _reach) {
            if (f != file || basis.contains('(dip:')) {
              continue;
            }
            final row = _row(db, id, position);
            final cho =
                knownFood(db, row.fdcId!)!.nutrientsPer100g['205']! / 100;
            final d = row.description!;
            if (d.startsWith('Flour,')) {
              dredge += row.grams! * cho;
            } else {
              dry += d.startsWith('Bread,')
                  ? row.grams! * cho / 0.7198
                  : row.grams!;
            }
          }
          expect(dredge, closeTo(3.55 * food.grams! / 100, 0.01), reason: file);
          expect(dry, closeTo(11.905 * food.grams! / 100, 0.01), reason: file);
        }
        for (final (file, position, share) in [
          (_kiev, 7, '0.8128'),
          (_stuffed, 13, '0.5961'),
        ]) {
          final recipe = recipes[file]!;
          final db = dbs[file]!;
          final line = nutritionLines(recipe)[position];
          final row = _row(db, recipe.id, position);
          final whole = lineGrams(
            db,
            line,
            knownFood(db, row.fdcId!),
            recipe: recipe,
          )!.grams;
          expect(whole.toStringAsFixed(2), '181.44', reason: '$file|$position');
          expect(
            (row.grams! / whole).toStringAsFixed(4),
            share,
            reason: '$file|$position',
          );
        }
      },
    );

    test('pin (9) — the negatives: every other coat read keeps the one f '
        '(the C1 crusts, the eggplant, C2 default, C4, the onion rings), '
        'byte-equal to v87', () {
      for (final (file, position, raw, fdcId, grams, kcal, head)
          in _negatives) {
        final recipe = recipes[file]!;
        final db = dbs[file]!;
        final row = _row(db, recipe.id, position);
        final reason = '$file|$position';
        expect(nutritionLines(recipe)[position].raw, raw, reason: reason);
        expect(
          (row.fdcId, row.status, row.hold, row.gramSource),
          (fdcId, 'auto', null, 'discarded'),
          reason: reason,
        );
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(kcalOf(db, row), kcal, reason: reason);
        final basis = basisOf(file, position)!;
        expect(basis, contains(head), reason: reason);
        expect(basis, isNot(contains('81 g dry crumbs')), reason: reason);
      }
    });

    test('the totals (status, kcal per serving, total grams): the fixture '
        "compute's — all four stay complete", () {
      for (final MapEntry(key: file, value: want) in _totals.entries) {
        final n = dbs[file]!.nutritionFor(recipes[file]!.id)!;
        expect(
          (
            n.status,
            n.caloriesPerServing?.toStringAsFixed(2),
            n.totalGrams?.toStringAsFixed(2),
          ),
          want,
          reason: file,
        );
      }
    });

    test('pin (8) — the flag reads in docs/API.md character for character '
        '(its line breaks folded), the nut stand-in clause too', () {
      final api = File(
        '../../docs/API.md',
      ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
      expect(api, contains(_flag));
      expect(api, contains(_nutStandIn.trim()));
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
        expect(recomputeTotals(db, recipes[file]!), isTrue, reason: file);
        expect(rowsOf(), rows, reason: file);
      }
    });

    // The person path (STATED: a person's typed grams through the real PUT;
    // unguarded, Q7 — no users). Typed grams leave the line out of the
    // parts (`_m52Engine`: an `override` row is no plan part).
    test("typed grams on the FLOUR line (kiev|11, a person's 40 g) leave it "
        'out of the parts: the crumbs keep their OWN budget — kiev|7 stays '
        '147.47 g (v87: the whole 12.12 at the one f, f = 1, its 181.44 g '
        'line) — and the dips keep W; no fallback to the one f', () async {
      final db = freshDb();
      final kiev = await _compute(db, fdc, loadCorpusRecipe(_kiev));
      await applyMatchOverride(db, fdc, kiev, 11, {
        'raw': nutritionLines(kiev)[11].raw,
        'grams': 40,
      });
      expect(
        (_row(db, kiev.id, 11).grams, _row(db, kiev.id, 11).gramSource),
        (40.0, 'override'),
      );
      final bread = _row(db, kiev.id, 7);
      expect(
        (bread.grams?.toStringAsFixed(2), bread.gramSource),
        ('147.47', 'discarded'),
      );
      expect(
        gramBasisFor(db, nutritionLines(kiev)[7], bread, recipe: kiev),
        _crumb(),
      );
      expect(_row(db, kiev.id, 12).grams?.toStringAsFixed(2), '116.88');
    });

    test("min(1, …)'s cap: typed grams on nut-crusted|2's almonds (a "
        "person's 80 g — nutrition_v80's CC11 value) leave the panko the "
        "crumbs' only part: its dry mass under the crumbs' 94.50 g budget, so "
        'f_c = 1 and it counts its whole line; the flour keeps f_d', () async {
      final db = freshDb();
      final nut = await _compute(db, fdc, loadCorpusRecipe(_nut));
      await applyMatchOverride(db, fdc, nut, 2, {
        'raw': nutritionLines(nut)[2].raw,
        'grams': 80,
      });
      final panko = _row(db, nut.id, 5);
      final whole = lineGrams(
        db,
        nutritionLines(nut)[5],
        knownFood(db, panko.fdcId!),
        recipe: nut,
      )?.grams;
      expect(
        (
          panko.grams?.toStringAsFixed(2),
          whole?.toStringAsFixed(2),
          panko.gramSource,
        ),
        ('59.15', '59.15', 'discarded'),
      );
      expect(_row(db, nut.id, 9).grams?.toStringAsFixed(2), '36.45');
      expect(
        gramBasisFor(db, nutritionLines(nut)[5], panko, recipe: nut),
        _crumb(),
      );
    });

    // STATED (the person path — no corpus row types grams, and no corpus
    // 2706442 coat reaches f_d's cap: kiev|11's own replay is 39.06 g of
    // its 141.75 g line): f_d = min(1, …) caps once 3.55 × raw ÷ 100 meets
    // the flour line's carbohydrate, 141.7475 g × 77.3 % = 109.57 g, i.e.
    // a typed chicken above 3,086.50 g. Uncapped (f_d without min(1, …), the
    // crumbs' f_c still capped) kiev|11 reads 183.70 g, more than its line.
    test("f_d's min(1, …) cap: typed grams on kiev|10's chicken (a person's "
        '4,000 g, past the 3,086.50 g where 3.55 × raw ÷ 100 meets the '
        "flour line's 109.57 g carbohydrate) leave kiev|11 its whole "
        '141.75 g line, f_d = 1 — uncapped it would count more flour than '
        'the line holds', () async {
      final db = freshDb();
      final kiev = await _compute(db, fdc, loadCorpusRecipe(_kiev));
      await applyMatchOverride(db, fdc, kiev, 10, {
        'raw': nutritionLines(kiev)[10].raw,
        'grams': 4000,
      });
      expect(
        (_row(db, kiev.id, 10).grams, _row(db, kiev.id, 10).gramSource),
        (4000.0, 'override'),
      );
      final flour = _row(db, kiev.id, 11);
      final whole = lineGrams(
        db,
        nutritionLines(kiev)[11],
        knownFood(db, flour.fdcId!),
        recipe: kiev,
      )?.grams;
      expect(
        (
          flour.fdcId,
          flour.grams?.toStringAsFixed(2),
          whole?.toStringAsFixed(2),
          flour.gramSource,
        ),
        (789890, '141.75', '141.75', 'discarded'),
      );
    });

    test('the converse (CC11, unchanged): typed grams on the CRUMB line '
        "(kiev|7, a person's 40 g) leave no `Bread,` part — the flour reads "
        "C2's default 3.18 at the one f, as at v87", () async {
      final db = freshDb();
      final kiev = await _compute(db, fdc, loadCorpusRecipe(_kiev));
      await applyMatchOverride(db, fdc, kiev, 7, {
        'raw': nutritionLines(kiev)[7].raw,
        'grams': 40,
      });
      final flour = _row(db, kiev.id, 11);
      expect(
        (flour.grams?.toStringAsFixed(2), flour.gramSource),
        ('34.99', 'discarded'),
      );
      expect(
        gramBasisFor(db, nutritionLines(kiev)[11], flour, recipe: kiev),
        contains(
          'coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — '
          'USDA FNDDS 2705980',
        ),
      );
    });
  });
}

/// [r] stored and computed (its section children first).
Future<Recipe> _compute(
  SaltDatabase db,
  FixtureProvider fdc,
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
