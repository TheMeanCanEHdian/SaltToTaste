// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v87 (batch M85; matcherVersion 82 — a record choice, ALONE; prep51
// design_v2 §2 M85, decided under the 2026-10-07 standing authorization;
// zero requests): grated Parmesan is the block grated by hand, so it counts
// SR 170848 "Cheese, parmesan, hard" (392 kcal, 3.22 g carbohydrate,
// 1,175 mg sodium per 100 g) — not Foundation 325036 "Cheese, parmesan,
// grated" (421, 12.4 g, 1,750 mg), the retail grated product. `_rankAs`
// gains 'parmesan cheese' and 'parmesan' → the cached 'parmesan cheese'
// answer ranked under 'cheese parmesan hard' (the shipped 'parmesan cheese
// rind' entry's form; 170848 is that answer's index 2, its detail
// recorded); the accepted Asiago and Montasio approximations ("as
// Parmesan") follow it — the Asiago rewrite onto that answer became a
// rank-as read of it (a rank-as key is never a rewrite target: v21's M2),
// Montasio's rank-as words became the hard block's, and both
// `approximationRecords` entries re-point 325036 → 170848. Grams are keyed
// by the item, so they move only where a coat budget re-solves on the
// Parmesan part's lower carbohydrate (lighter-chicken-parmesan,
// eggplant-parmesan: every part of each budget, M88 re-derives them). Every
// whole-recipe value is the fresh compute over recorded real FDC answers
// (FixtureProvider). Every pinned ROW equals the v87 replay of snapshot 29
// (fix87 g1) on every pinned field; the TOTALS are the fixture compute's —
// equal to the replay for kale, farfalle, onion soup and frico, not for
// the other five (`_totals` gives each replay figure).
// Never the network. Every corpus line is real; the cap shapes' 400
// repeated real lines are the house's cap-shape exception (STATED).

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

const _kale = '0044-kale-caesar-salad.yaml';
const _meatloaf = '0307-turkey-meatloaf-with-ketchupbrown-sugar-glaze.yaml';
const _farfalle = '0335-farfalle-with-pesto.yaml';
const _ziti = '0069-skillet-chicken-broccoli-and-ziti.yaml';
const _onion = '0433-streamlined-french-onion-soup.yaml';
const _frico = '0402-frico.yaml';
const _minestrone = '0028-hearty-minestrone.yaml';
const _lighter = '0416-lighter-chicken-parmesan.yaml';
const _eggplant = '0407-eggplant-parmesan.yaml';

const _hard = 'Cheese, parmesan, hard';
const _asHard = 'approximation (counted as Cheese, parmesan, hard)';

// RE-PIN (M88 batch, v88): FNDDS 2706442's flag names its two inputs (was
// "coat: 12.12 g carbohydrate per 100 g of the raw chicken breast — USDA
// FNDDS 2706442 recipe: 112.25 g crust (81 g dry crumbs and 31.25 g flour as
// separate inputs; 82.46 g carbohydrate; …) per 680.4 g raw chicken; …").
const _crumbCoat =
    'discarded in cooking — only the coat on the food counted · approximation '
    '(coat: 31.25 g flour and 81 g dry crumbs per 680.4 g raw chicken breast — '
    'USDA FNDDS 2706442 recipe: flour (Foundation 789890) and dry crumbs (SR '
    '174928) as separate inputs, 3.55 g flour carbohydrate and 11.905 g dry '
    'crumbs per 100 g raw (the dredge sized by the flour, the crumbs by their '
    'dry mass; a fresh bread brought to dry crumbs by carbohydrate); the '
    "record's 18.75 g grated Parmesan follows its mozzarella and sauce — a "
    "topping, not read; the dredge's excess not counted)";
const _batterCoat =
    'discarded in cooking — only the coat on the food counted · approximation '
    '(coat: 7.93 g carbohydrate per 100 g of the raw eggplant — USDA FNDDS '
    '2710050 recipe: 13.2 g batter (4 g flour, 0.5 g dried egg, 8.3 g water, '
    '0.3 g dry milk, 0.1 g baking powder; 3.28 g carbohydrate) per 41.4 g raw '
    'eggplant (a crumb coat read on a batter figure; 8.3 g of the 13.2 g '
    "batter is water and carries no carbohydrate); the dredge's excess not "
    'counted)';

/// The pinned rows (file, position, raw, fdc id, gram source, grams, kcal,
/// basis) — the v87 replay's; v86's in the comment where it moved.
typedef _Row = (String, int, String, int, String?, String?, String, String?);

const List<_Row> _rows = [
  // 'parmesan cheese' (v86: 325036, 119.35 kcal).
  (
    _kale,
    6,
    '1 ounce Parmesan cheese, grated (½ cup)',
    170848,
    'weight',
    '28.35',
    '111.13',
    'from 1 ounce',
  ),
  // 'parmesan' (v86: 325036, 119.35; 59.68 — the volume at grams.dart's
  // printed hard-cheese figure, keyed by the item).
  (
    _meatloaf,
    12,
    '1 ounce Parmesan, grated (½ cup)',
    170848,
    'weight',
    '28.35',
    '111.13',
    'from 1 ounce',
  ),
  (
    _farfalle,
    6,
    '¼ cup grated Parmesan',
    170848,
    'density',
    '14.18',
    '55.57',
    "1/4 cup ≈ 59 mL · grated, at ATK's printed 1 ounce = ½ cup",
  ),
  // The approximations, flagged on the new record (v86: 325036, "counted
  // as Cheese, parmesan, grated"; 119.35 / 179.03 / 1,909.62 kcal).
  (
    _ziti,
    13,
    '1 ounce Asiago cheese, grated (about ½ cup), plus extra for serving',
    170848,
    'weight',
    '28.35',
    '111.13',
    'from 1 ounce · $_asHard',
  ),
  (
    _onion,
    13,
    '1½ ounces Asiago cheese, grated (about ¾ cup)',
    170848,
    'weight',
    '42.52',
    '166.70',
    'from 1 1/2 ounce · $_asHard',
  ),
  (
    _frico,
    0,
    '1 pound Montasio or aged Asiago cheese, grated fine (about 8 cups)',
    170848,
    'weight',
    '453.59',
    '1778.08',
    'from 1 pound · $_asHard',
  ),
  // The converse: the rind already read 170848 (pF F3), discarded, 0 g.
  (
    _minestrone,
    14,
    '1 piece Parmesan cheese rind, about 5 by 2 inches',
    170848,
    'discarded',
    '0.00',
    '0.00',
    'removed and discarded (step 4) — counted as 0 g',
  ),
  // One of the 13 amount-less 'parmesan cheese' rows: its record moves, 0 g
  // either way (v86: 325036).
  (
    _minestrone,
    19,
    'Grated Parmesan cheese, for serving',
    170848,
    'unmeasured',
    '0.00',
    '0.00',
    'no amount on the line — counted as 0 g',
  ),
  // The coat budgets re-solve on the Parmesan part's carbohydrate (12.4 →
  // 3.22 %): f rises and EVERY part of the budget moves — the replay's
  // figures, which M88 (the dredge's own figure) re-derives on these rows.
  // lighter (v86): |0 56.15 g 221.79, |2 17.94 g 75.53 on 325036, |3 44.85 g
  // 164.15.
  (
    _lighter,
    0,
    '1½ cups panko (Japanese-style bread crumbs)',
    174928,
    'discarded',
    // RE-PIN (M88 batch, v88): was 57.37 g, 226.61 kcal — the crumbs' own
    // share f_c (the v88 replay's row).
    '57.55',
    '227.32',
    _crumbCoat,
  ),
  (
    _lighter,
    2,
    '1 ounce Parmesan cheese, grated (about ½ cup), plus extra for serving',
    170848,
    'discarded',
    // RE-PIN (M88 batch, v88): was 18.33 g, 71.85 kcal — a Cheese part of
    // the crumbs by its own mass, f_c (the v88 replay's row).
    '18.39',
    '72.09',
    _crumbCoat,
  ),
  (
    _lighter,
    3,
    '½ cup unbleached all-purpose flour',
    789890,
    'discarded',
    // RE-PIN (M88 batch, v88): was 45.83 g, 167.74 kcal — the dredge's own
    // share f_d (the v88 replay's row).
    '29.29',
    '107.20',
    _crumbCoat,
  ),
  // eggplant (v86): |2 88.21 g 234.64, |3 13.78 g 58.01 on 325036, |5 34.46 g
  // 126.12; |15 (the topping, outside the budget) 28.35 g 119.35.
  (
    _eggplant,
    2,
    '8 slices high-quality white sandwich bread, torn into quarters',
    174924,
    'discarded',
    '89.79',
    '238.84',
    _batterCoat,
  ),
  (
    _eggplant,
    3,
    '2 ounces Parmesan cheese, grated (about 1 cup)',
    170848,
    'discarded',
    '14.03',
    '55.00',
    _batterCoat,
  ),
  (
    _eggplant,
    5,
    '1 cup unbleached all-purpose flour',
    789890,
    'discarded',
    '35.07',
    '128.36',
    _batterCoat,
  ),
  (
    _eggplant,
    15,
    '1 ounce Parmesan cheese, grated (about ½ cup)',
    170848,
    'weight',
    '28.35',
    '111.13',
    'from 1 ounce',
  ),
];

/// Each recipe's (status, kcal per serving, total grams) — the fresh compute;
/// the v87 replay's per serving where it differs (other rows' search-hit
/// energies recorded from earlier snapshots differ from the library's; the
/// pinned rows are equal), then v86's replay figure.
const Map<String, (String, String, String)> _totals = {
  _kale: ('complete', '263.21', '629.40'), // = replay; v86 265.26
  // RE-PIN (M90 batch, v89): the replay 647.55 → 641.85: was 648.42, 1521.80.
  // RE-PIN (M86 batch, v90, 958: 2514747 turkey): was 642.72.
  _meatloaf: ('complete', '654.06', '1515.90'), // replay 647.55; v86 649.60
  // RE-PIN (M86 batch, v90, 958: 2346392 nuts): was 704.76.
  _farfalle: ('complete', '701.02', '658.70'), // = replay; v86 705.79
  // RE-PIN (M86 batch, v90, 958: 2646170 chicken, 2346386 cream): was 595.31.
  _ziti: ('complete', '599.90', '1752.40'), // replay 595.35; v86 597.41
  _onion: ('complete', '362.29', '3620.50'), // = replay; v86 364.34
  _frico: ('complete', '222.26', '453.60'), // = replay; v86 238.70
  // Unmoved: its Parmesan rows count 0 g.
  // RE-PIN (M86 batch, v90, 958: 2644281 beans, 2346405 celery, 2258586
  // carrots, 2685568 squash +1 more): was 264.97.
  _minestrone: ('complete', '259.46', '1833.60'), // replay 265.05 both
  // The re-solved budgets add grams (v86 1,782.60 and 2,765.00 g).
  // RE-PIN (M88 batch, v88): was 298.40 / 1,785.10 (replay 298.43) — the
  // dredge split (the v88 replay 288.50).
  // RE-PIN (M86 batch, v90, 958: 2646170 chicken, 2685580 tomato): was 288.46.
  _lighter: ('complete', '294.42', '1768.80'), // replay 288.50; v86 297.64
  // RE-PIN (M86 batch, v90, 958: 2685577 eggplant): was 451.60.
  _eggplant: ('partial', '446.01', '2767.50'), // replay 451.58; v86 452.38
};

/// The recorded cached answers (FixtureProvider) every Parmesan, Asiago and
/// Montasio line reads.
Future<List<FdcCandidate>> _answer(String query) =>
    FixtureProvider(pending: {...pendingSearches}).search(query);

void main() {
  test('matcherVersion 92 (v87 set it to 82, batch M85: rows move)', () {
    // RE-PIN (M88 batch, v88): matcherVersion 83 (was 82).
    // RE-PIN (M90 batch, v89): matcherVersion 84 (was 83).
    // RE-PIN (M86 batch, v90): matcherVersion 85 (was 84).
    // RE-PIN (M87 batch, v91): matcherVersion 86 (was 85).
    // RE-PIN (M89 batch, v92): matcherVersion 87 (was 86).
    // RE-PIN (M91 batch, v93): matcherVersion 88 (was 87).
    // RE-PIN (M92 batch, v94): matcherVersion 89 (was 88).
    // RE-PIN (M93 batch, v95): matcherVersion 90 (was 89).
    // RE-PIN (M94 batch, v96): matcherVersion 91 (was 90).
    // RE-PIN (M95 batch, v97): matcherVersion 92 (was 91).
    expect(matcherVersion, 92);
  });

  test("the four rank-as reads: the cached 'parmesan cheese' answer under "
      "the hard block's words; Asiago is no rewrite (M2) and both "
      'approximations name 170848', () {
    for (final item in [
      'parmesan cheese',
      'parmesan',
      'asiago cheese',
      'montasio or aged asiago cheese',
    ]) {
      expect(rankAsFor(item), (
        query: 'cheese parmesan hard',
        answer: 'parmesan cheese',
      ), reason: item);
    }
    // The rewrite onto the answer became the rank-as read of it: 'parmesan
    // cheese' is no rewrite target, so v21's M2 holds for every rank-as key.
    expect(searchQueryFor('asiago cheese'), 'asiago cheese');
    expect(approximationRecords['asiago cheese'], 170848);
    expect(approximationRecords['montasio or aged asiago cheese'], 170848);
    for (final (item, fdcId, flagged) in [
      ('asiago cheese', 170848, true),
      ('asiago cheese', 325036, false),
      ('montasio or aged asiago cheese', 170848, true),
      ('montasio or aged asiago cheese', 325036, false),
      // Parmesan is the food: never flagged.
      ('parmesan cheese', 170848, false),
      ('parmesan', 170848, false),
    ]) {
      expect(
        isApproximation(
          item: item,
          raw: item,
          fdcId: fdcId,
          description: _hard,
        ),
        flagged,
        reason: '$item on $fdcId',
      );
    }
  });

  test(
    'the recorded answers: the hard block ranks first under its words '
    "(1.0) in the cached 'parmesan cheese' answer, which every Parmesan, "
    "Asiago and Montasio line reads; the bare 'parmesan' answer holds 170848 "
    'too — the census: no line of these items reads an answer without it',
    () async {
      final hits = await _answer('parmesan cheese');
      expect(
        hits.take(3).map((h) => (h.fdcId, h.description)),
        [
          (171247, 'Cheese, parmesan, grated'),
          (325036, 'Cheese, parmesan, grated'),
          (170848, _hard),
        ],
      );
      final hard = rankCandidates('cheese parmesan hard', hits).first;
      expect((hard.candidate.fdcId, hard.confidence), (170848, 1.0));
      final own = await _answer('parmesan');
      expect(own.indexWhere((h) => h.fdcId == 170848), 2);
    },
  );

  group('matcher v87 (batch M85) — whole recipes', skip: skipIfNoCorpus, () {
    // Each recipe in its own fresh database: a food detail another
    // recipe's compute caches would change what an earlier recipe's rows
    // read (a search hit's rounded nutrients, then the detail) — the
    // library's caches hold every detail already (the replay).
    final dbs = <String, SaltDatabase>{};
    late FixtureProvider fdc;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      fdc = FixtureProvider(pending: {...pendingSearches});
      for (final file in _totals.keys) {
        final dir = Directory.systemTemp.createTempSync('salt-v87-');
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

    test('each row its record, source, grams, energy and basis (the v87 '
        "replay's): Parmesan, Asiago and Montasio on 170848, the rind's "
        'converse, the two budgets re-solved', () {
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

    test('no Parmesan, Asiago or Montasio row of the nine recipes stays on '
        '325036', () {
      for (final file in recipes.keys) {
        final rows = dbs[file]!.ingredientMatchesFor(recipes[file]!.id);
        expect(rows.where((m) => m.fdcId == 325036), isEmpty, reason: file);
      }
    });

    test('the totals (status, kcal per serving, total grams): the fixture '
        "compute's (`_totals` gives the replay's where it differs)", () {
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

  // RULE C: M85 adds no reader — the rank-as path is the shipped one (one
  // `_rankAs` lookup per line in `lineSearchFor`, before the rewrite and the
  // left-alternative reads it replaces) and `approximationRecords` is a map
  // read; nothing memoized is touched. The cap shapes (STATED, the house's
  // exception: 400 repeated real lines under 0044's real steps), each
  // through the compute (matchAndCompute) and the GET (gramBasisFor on every
  // stored row): TRUE — 400 × kale-caesar|6 "1 ounce Parmesan cheese,
  // grated (½ cup)" (every row on 170848; 325036 at base 2cb275e); QUIET —
  // 400 × 0044's "3 tablespoons mayonnaise" (FNDDS 2710204). Counts: each
  // shape's map exactly, EQUAL to base 2cb275e's (the process-wide `names`
  // aside). Clocks (fix87, two runs each, base → tree): TRUE 609 / 542 →
  // 634 / 523 ms, QUIET 518 / 486 → 476 / 464 ms — each under the backstop.
  group('RULE C, the Parmesan rank-as at the caps', skip: skipIfNoCorpus, () {
    late final base = loadCorpusRecipe(_kale);
    final shapes = {
      'M85-TRUE': (
        '1 ounce Parmesan cheese, grated (½ cup)',
        170848,
        'from 1 ounce',
      ),
      'M85-QUIET': (
        '3 tablespoons mayonnaise',
        2710204,
        '3 tablespoon · USDA portion',
      ),
    };
    for (final MapEntry(key: shape, value: (raw, fdcId, basis))
        in shapes.entries) {
      test('$shape: 400 rows on $fdcId, every one weighed; the counts exact, '
          'within the backstop', () async {
        final dir = Directory.systemTemp.createTempSync('salt-v87-');
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
        final fdc = FixtureProvider(pending: {...pendingSearches});
        final p = parseIngredientLine(raw);
        final r = base.copyWith(
          ingredients: [
            IngredientGroup(
              items: [
                for (var i = 0; i < 400; i++)
                  IngredientLine(
                    raw: raw,
                    item: p.item,
                    prep: p.prep,
                    amounts: p.amounts,
                  ),
              ],
            ),
          ],
        );
        db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
        final stored = db.recipeByIdOrSlug(r.id)!.recipe;
        stepIndexCounts.clear();
        final sw = Stopwatch()..start();
        expect(await matchAndCompute(db, fdc, stored), isNull);
        final rows = db.ingredientMatchesFor(stored.id);
        final lines = nutritionLines(stored);
        final bases = {
          for (final row in rows)
            gramBasisFor(db, lines[row.position], row, recipe: stored),
        };
        final ms = sw.elapsedMilliseconds;
        final counts = Map.of(stepIndexCounts)..remove('names');
        expectBounded(stored, counts, shape);
        expect(
          (
            rows.length,
            rows.where((m) => m.fdcId == fdcId).length,
            rows.where((m) => m.grams != null).length,
            bases.single,
          ),
          (400, 400, 400, basis),
          reason: shape,
        );
        expect(counts, _capCounts[shape], reason: shape);
        expect(ms, lessThan(backstopMs), reason: shape);
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
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

/// Each cap shape's counts on the tree — equal to base 2cb275e's (fix87
/// cost_base.log / cost_tip.log, both runs; the process-wide `names` aside).
const Map<String, int> _shared = {
  'indexes': 1,
  'memo:skinSentences': 1,
  'allSentences': 1,
  'lower': 1,
  'sentences': 15,
  'memo:starter': 1,
  'heads': 1,
  'words': 175,
  'memo:braise': 1,
  'memo:strain': 1,
  'memo:pourAway': 1,
  'cheese': 1,
  'memo:brines': 1,
  'memo:wordHeads': 1,
  'memo:brineWords': 1,
  'memo:parting': 1,
  'memo:strainAt': 1,
  'memo:savesRemainder': 1,
  'memo:setAsideLine': 1,
  'memo:reservedWhole': 1,
  'memo:discards': 1,
  'memo:dips': 1,
  'memo:leftInBowl': 1,
  'memo:keptSolids': 1,
  // RE-PIN (M94 batch, v96): + the browning-fat reader's memo, once
  // per index (every `_m52Plan` reads it).
  'memo:browningFat': 1,
  'memo:cutShare': 1,
  'memo:panFatLines': 1,
  'memo:liftedFromMarinade': 1,
};
const Map<String, Map<String, int>> _capCounts = {
  'M85-TRUE': {..._shared, 'memo:naming': 2},
  'M85-QUIET': {..._shared, 'memo:naming': 1},
};
