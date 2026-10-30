// Matcher v96 (batch M94; matcherVersion 91 — the skimmed / poured-off
// browning fat; prep51 design_v2 §1 Q3 Part B option (d) / §2 M94, ruled by
// the owner 2026-10-29; zero requests). NEW `_browningFatShare` (its OWN
// constant, never `_panFatShare`) = FNDDS 2705972 "Chicken breast, sauteed,
// skin not eaten"'s oil per gram of RAW breast: its inputFoods (L51 #1,
// .claude/diag/2026-10-29/live51_raw/2705972.json) are 98 g 24122131
// "Chicken breast, baked, broiled, or roasted, skin not eaten, from raw" and
// 2 g 82101000 "Vegetable oil, NFS"; the 98 g brought to raw by protein on
// prep47's pair (p3_read_figures.md row 27, `_breastFried`'s 104.76): FNDDS
// 2705956 (= 24122131, a cached search hit: 203 30.22) ÷ SR 171077
// "Chicken, broiler or fryers, breast, skinless, boneless, meat only, raw"
// (203 22.5) → 98 × 30.22 / 22.5 = 131.62 g, so 2 / 131.62 = 1.5195 % (the
// design's ≈ 1.43 % was the protein-BALANCE estimate before L51 #1 read the
// inputFoods). NEW reader `_browningFatLines` (memo:browningFat, once per
// index): the first sentence outside a parenthesis matching `_skimsFat` (a
// fat skim, a fat separator, a plain pour / spoon / drain-off of fat or
// grease) and not `_pourOffAllButFat` (a printed kept part: no trigger); a
// fat line (`_panFatHeads`) whose every own mention (`_lineMentionsOf`) lies
// before it, each in a sentence that heats it (`_panOil`, or a "repeat with
// the remaining …" of the step's browning, `_repeatWith`). NEW plan arm
// `_browningFatPlan` (merged into `_m52Plan`'s returns FIRST, so the C4
// arm's own write wins): the browned food = the recipe's heaviest counted
// meat row; each admitted line keeps min(whole, share × that raw ÷ its own
// lipid) — per line (closer 1, verify1 D3), and a line the rule leaves
// whole is not planned (closer 1, verify1 D4). Closer 1 (verify1 D2): a
// person's Confirm of a planned browning line reads the plan through
// derivedFor, as M78's C4 rows do.
// REACH (fix96/c1 gate, the v95 rows of snapshot 30): the 15 rows of the
// design's Q3 Part B AND 7 rows beyond them — D1, RULED ACCEPT BY THE
// ORCHESTRATOR 2026-10-30 (fix96/ruling4.md: the trigger is the design's; no
// measured narrowing keeps the 15): their pins here are the replay's figures,
// tagged "D1 RULED".
// Every whole-recipe figure is a fresh compute on the recorded fixtures
// (FixtureProvider); the replay's in each comment. Never the network. Every
// corpus line and step is real; STATED synthesized (named at each): a real
// recipe with one of its real sentences deleted, and the cap shapes'
// repeated real lines.
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

import 'nutrition_v25_cost_test.dart' show fill;
import 'nutrition_v26_cost_test.dart' show capLines, capStep, capSteps, capped;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _hearty = '0002-hearty-chicken-noodle-soup.yaml';
const _classic = '0002-classic-chicken-noodle-soup.yaml';
const _slowSoup = '0003-old-fashioned-slow-cooker-chicken-noodle-soup.yaml';
const _pressure = '0004-pressure-cooker-chicken-noodle-soup.yaml';
const _bestStew = '0005-best-beef-stew.yaml';
const _skilletRoasted =
    '0075-skillet-roasted-chicken-breasts-with-potatoes.yaml';
const _brick = '0075-chicken-under-a-brick-with-herb-roasted-potatoes.yaml';
const _simplePotRoast = '0082-simple-pot-roast.yaml';
const _hungarian = '0086-hungarian-beef-stew.yaml';
const _shortRibs = '0087-braised-beef-short-ribs.yaml';
const _beerRibs = '0088-slow-cooker-beer-braised-short-ribs.yaml';
const _oxtails =
    '0089-braised-oxtails-with-white-beans-tomatoes-and-aleppo-pepper.yaml';
const _maple = '0235-maple-glazed-pork-tenderloin.yaml';
const _gravy = '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml';
const _saltimbocca = '0421-chicken-saltimbocca.yaml';
const _bouillabaisse = '0450-chicken-bouillabaisse.yaml';
const _frenchStyle = '0454-french-style-chicken-and-stuffing-in-a-pot.yaml';
const _daube = '0456-daube-provencal.yaml';
const _poivre = '0463-steak-au-poivre-with-brandied-cream-sauce.yaml';
const _irish = '1070-irish-stew-with-carrots-and-turnips.yaml';
const _broiled = '1076-broiled-chicken-with-gravy.yaml';
const _bulalo = '1171-bulalo-hearty-beef-shank-and-vegetable-soup.yaml';
const _teriyaki2 = '1178-chicken-teriyaki.yaml';
const _rootPotRoast = '1182-pot-roast-with-root-vegetables.yaml';
const _lamb =
    '1192-braised-lamb-shanks-with-red-wine-and-herbes-de-provence.yaml';
const _albondigas = '1208-albondigas-en-chipotle.yaml';

/// The flag of a browning-fat row on the raw [food] (the c1 gate rows).
String _flag(String food, {bool butter = false}) =>
    'approximation (browning fat: 1.52 g fat per 100 g of the raw $food — USDA FNDDS 2705972 recipe: 2 g oil per 131.62 g raw chicken breast (the browned piece keeps a film; the steps skim / pour off the rest)${butter ? '; a butter line weighed by its own fat' : ''})';

const _basis =
    'skimmed / poured off — only the fat the browned food keeps counted';

/// The basis of a browning row: [evoo] names 748608's sibling (M77).
String _browning(String food, {bool butter = false, bool evoo = false}) =>
    '$_basis · ${evoo ? 'nutrients of "Oil, olive, salad or cooking" · ' : ''}${_flag(food, butter: butter)}';

/// The browning rows (file, position, raw, record, whole, grams, kcal,
/// basis) — the v95 → v96 replay's grams / kcal in each comment (fix96/c1
/// gate). The record's energy: 2710180 / 2710186 900, 748608 by its
/// sibling 171413 884, 173430 717 (none a Foundation record M86's 958
/// reads). The browned food's raw grams in each comment (the recipe's
/// heaviest counted meat row) — kept = 0.015195 × that ÷ the line's fat.
final _the15 = [
  // 14.00 → 6.89 g, 126.00 → 62.01 kcal; ground chicken 453.59 g; T S3 skim.
  (
    _hearty,
    0,
    '1 tablespoon vegetable oil',
    2710180,
    '14.00',
    '6.89',
    '62.01',
    _browning('chicken'),
  ),
  // 14.00 → 6.10, 126.00 → 54.90; thighs 401.43 g; T S4.3 skim (S2.0's
  // "Pour off all but 1 tablespoon fat" is a printed kept part: no trigger).
  (
    _slowSoup,
    2,
    '1 tablespoon vegetable oil',
    2710180,
    '14.00',
    '6.10',
    '54.90',
    _browning('chicken thigh'),
  ),
  // 14.00 → 11.97, 126.00 → 107.73; 788.00 g.
  (
    _pressure,
    0,
    '1 tablespoon vegetable oil',
    2710180,
    '14.00',
    '11.97',
    '107.73',
    _browning('chicken'),
  ),
  // 28.00 → 24.12, 252.00 → 217.08; chuck-eye 1,587.57 g.
  (
    _simplePotRoast,
    2,
    '2 tablespoons vegetable oil',
    2710180,
    '28.00',
    '24.12',
    '217.08',
    _browning('beef'),
  ),
  // 28.00 → 24.12, 252.00 → 217.08; short ribs 1,587.57 g; T S3.2 the fat
  // separator; S1.6 "repeat with the remaining 1 tablespoon oil".
  (
    _shortRibs,
    2,
    '2 tablespoons vegetable oil',
    2710180,
    '28.00',
    '24.12',
    '217.08',
    _browning('beef'),
  ),
  // 26.82 → 15.56, 237.12 → 137.55; oxtails 1,024.00 g; T S5.1 separator.
  (
    _oxtails,
    3,
    '2 tablespoons extra-virgin olive oil',
    748608,
    '26.82',
    '15.56',
    '137.55',
    _browning('beef', evoo: true),
  ),
  // 28.00 → 18.95, 252.00 → 170.55; tenderloins 1,247.38 g; T S3.0 "Pour
  // off the fat from the skillet" (a K2 plain pour-off).
  (
    _maple,
    11,
    '2 tablespoons vegetable oil',
    2710180,
    '28.00',
    '18.95',
    '170.55',
    _browning('pork'),
  ),
  // 28.00 → 10.13, 252.00 → 91.17; backribs 666.50 g; T S4 skim.
  (
    _gravy,
    0,
    '2 tablespoons olive oil',
    2710186,
    '28.00',
    '10.13',
    '91.17',
    _browning('pork'),
  ),
  // 26.82 → 15.30, 237.12 → 135.25; breast 1,006.97 g; T S7.1 "Skim excess
  // fat from broth" (a K1 skim) — 26.82, not the brief's 26.83 (M82's
  // rounding of 0.907 × 2 × 14.787 mL).
  (
    _bouillabaisse,
    2,
    '2 tablespoons extra-virgin olive oil',
    748608,
    '26.82',
    '15.30',
    '135.25',
    _browning('chicken breast', evoo: true),
  ),
  // 9.07 → 6.72, 81.62 → 60.48; breast 442.25 g.
  (
    _frenchStyle,
    14,
    '2 teaspoons vegetable oil',
    2710180,
    '9.07',
    '6.72',
    '60.48',
    _browning('chicken breast'),
  ),
  // 56.00 → 24.12, 504.00 → 217.08; chuck-eye 1,587.57 g.
  (
    _daube,
    4,
    '4 tablespoons olive oil',
    2710186,
    '56.00',
    '24.12',
    '217.08',
    _browning('beef'),
  ),
  // 42.00 → 20.39, 378.00 → 183.51; lamb shoulder 1,341.81 g.
  (
    _irish,
    1,
    '3 tablespoons vegetable oil',
    2710180,
    '42.00',
    '20.39',
    '183.51',
    _browning('lamb'),
  ),
  // 42.00 → 25.85, 378.00 → 232.65; chuck-eye 1,700.97 g.
  (
    _rootPotRoast,
    3,
    '3 tablespoons vegetable oil, divided',
    2710180,
    '42.00',
    '25.85',
    '232.65',
    _browning('beef'),
  ),
  // 28.00 → 25.33, 252.00 → 227.97; fore-shanks 1,666.95 g (|0 M84's pair).
  (
    _lamb,
    2,
    '2 tablespoons vegetable oil, divided',
    2710180,
    '28.00',
    '25.33',
    '227.97',
    _browning('lamb'),
  ),
  // 28.00 (its used 2 × 1 tablespoon, `_partialUseOf`) → 16.82, 252.00 →
  // 151.38; shanks 1,106.76 g; T S6.2 "skim excess fat" (S1.2 "Pour off and
  // reserve oil left in pot" names no fat or grease: no trigger).
  (
    _bulalo,
    0,
    '¼ cup vegetable oil',
    2710180,
    '28.00',
    '16.82',
    '151.38',
    _browning('beef'),
  ),
];

/// D1 RULED (verify1 D1, the orchestrator's ACCEPT 2026-10-30): the rows the
/// brief's trigger admits beyond the 15, at the replay's figures.
final _beyond = [
  // 112.00 → 10.13 g, 1,008.00 → 91.17: S4.0 heats it in the MEATBALLS'
  // nonstick skillet before S4.3's skim of the sauce (another pan); the
  // ribs' 666.50 g (per line: |0 keeps its own 10.13 too).
  (
    _gravy,
    20,
    '½ cup olive oil',
    2710186,
    '112.00',
    '10.13',
    '91.17',
    _browning('pork'),
  ),
  // 26.82 → 5.17, 237.12 → 45.70: S2.0 the sauce's saucepan; T S5.2.
  (
    _albondigas,
    2,
    '2 tablespoons extra-virgin olive oil',
    748608,
    '26.82',
    '5.17',
    '45.70',
    _browning('beef', evoo: true),
  ),
  // 28.36 → 20.68, 203.35 → 148.28: S4.1 the gravy's roux; T S5.2 "Spoon
  // off fat and discard" (the skillet's drippings in a bowl).
  (
    _broiled,
    12,
    '2 tablespoons unsalted butter',
    173430,
    '28.36',
    '20.68',
    '148.28',
    _browning('chicken', butter: true),
  ),
  // 28.00 → 24.12, 252.00 → 217.08: S2.0 the onions' sweat; T S4.0 skim.
  (
    _hungarian,
    6,
    '2 tablespoons vegetable oil',
    2710180,
    '28.00',
    '24.12',
    '217.08',
    _browning('beef'),
  ),
  // 9.07 → 8.44, 81.62 → 75.96: the thighs browned S3.1; T S4.2 pour-off.
  (
    _teriyaki2,
    6,
    '2 teaspoons vegetable oil',
    2710180,
    '9.07',
    '8.44',
    '75.96',
    _browning('chicken thigh'),
  ),
  // 28.00 → 27.57, 252.00 → 248.13: chuck-eye 1,814.37 g browned; T S6.0.
  (
    _bestStew,
    4,
    '2 tablespoons vegetable oil',
    2710180,
    '28.00',
    '27.57',
    '248.13',
    _browning('beef'),
  ),
  // 28.36 → 27.93, 203.35 → 200.26: S2's onions in the ribs' skillet; T
  // S4.0 "skim off the hardened fat" (its |2 oil, capped on its own fat,
  // unplanned).
  (
    _beerRibs,
    3,
    '2 tablespoons unsalted butter',
    173430,
    '28.36',
    '27.93',
    '200.26',
    _browning('beef', butter: true),
  ),
];

/// Rows the arm does not move (file, position, raw, grams, source,
/// admitted by the text reader) — the v95 rows, unchanged.
const _unmoved = [
  // K-1's NEGATIVES: mentions AT and AFTER the pour-off (S4.0 / S5) and a
  // microwave-safe bowl's toss (S2.0, no heat) — refused by both tests.
  (_skilletRoasted, 2, '6 tablespoons olive oil', '84.00', 'portion', false),
  // S2.0's "mix remaining 2 tablespoons oil … in small bowl" is no heat
  // sentence.
  (
    _brick,
    2,
    '1 teaspoon plus 2 tablespoons vegetable oil, divided',
    '32.53',
    'density',
    false,
  ),
  // The sauce butter, whisked in "off the heat" (S4.3, a `_panOil`
  // sentence) AFTER S4.0's "Pour off any fat left in the pan".
  (
    _poivre,
    0,
    '4 tablespoons (½ stick) unsalted butter',
    '56.72',
    'density',
    false,
  ),
  // Admitted (S3.0 "Heat the oil in the skillet" before S4.0) but capped:
  // 1,020.58 g strip steak keeps 15.51 g of fat ≥ its 14.00 g — no entry.
  (_poivre, 7, '1 tablespoon vegetable oil', '14.00', 'portion', true),
  // Admitted and capped (closer 1, verify1 D4: the row as it was).
  (_classic, 0, '1 tablespoon vegetable oil', '14.00', 'portion', true),
  // A C4 row (`_panFatLines`): admitted by the text, the C4 arm's 23.14 g.
  (_saltimbocca, 5, '4 tablespoons olive oil', '23.14', 'discarded', true),
];

/// (file, status, per serving) after the settled compute — the v95 → v96
/// replay's per serving in each comment (the last six: D1 RULED). Where
/// the fixtures differ from the replay (the standing search-HIT-vs-DETAIL
/// offsets of these recipes' other rows, the same at v95 — closer 1's base
/// probe), the fixtures' v95 → v96 is stated: every MOVE equals the
/// replay's to the cent of rounding.
const _totals = [
  // replay 517.28 → 501.29 (-15.99).
  (_hearty, 'complete', '501.29'),
  // replay 276.45 → 264.60 (-11.85).
  (_slowSoup, 'complete', '264.60'),
  // replay 211.12 → 208.83 (-2.29).
  (_pressure, 'partial', '208.83'),
  // replay 565.56 → 559.74 (-5.82).
  (_simplePotRoast, 'complete', '559.74'),
  // replay 654.07 → 648.25 (-5.82).
  (_shortRibs, 'complete', '648.25'),
  // replay 591.11 → 574.52 (-16.59); fixtures 591.12 → 574.53.
  (_oxtails, 'complete', '574.53'),
  // replay 444.28 → 430.70 (-13.58).
  (_maple, 'partial', '430.70'),
  // replay 1024.04 → 889.33 (-134.71); fixtures 1024.12 → 889.41.
  (_gravy, 'complete', '889.41'),
  // replay 1341.15 → 1315.68 (-25.47); fixtures 1341.14 → 1315.67, partial (the replay complete).
  (_bouillabaisse, 'partial', '1315.67'),
  // replay 844.03 → 838.75 (-5.28); fixtures 844.08 → 838.79.
  (_frenchStyle, 'partial', '838.79'),
  // replay 1078.95 → 1007.22 (-71.73); fixtures 1078.93 → 1007.20.
  (_daube, 'complete', '1007.20'),
  // replay 781.09 → 748.67 (-32.42); fixtures 781.09 → 748.68.
  (_irish, 'complete', '748.68'),
  // replay 837.79 → 813.57 (-24.22); fixtures 837.85 → 813.63.
  (_rootPotRoast, 'complete', '813.63'),
  // replay 573.06 → 569.06 (-4.00).
  (_lamb, 'complete', '569.06'),
  // replay 390.58 → 373.81 (-16.77); fixtures 390.60 → 373.83.
  (_bulalo, 'complete', '373.83'),
  // replay 708.99 → 661.14 (-47.85); fixtures 708.87 → 661.01.
  (_albondigas, 'complete', '661.01'),
  // replay 767.89 → 767.25 (-0.64); fixtures 767.91 → 767.27.
  (_bestStew, 'complete', '767.27'),
  // replay 700.46 → 686.70 (-13.76).
  (_broiled, 'complete', '686.70'),
  // replay 331.38 → 329.97 (-1.41); fixtures 331.67 → 330.25.
  (_teriyaki2, 'complete', '330.25'),
  // replay 653.74 → 647.92 (-5.82).
  (_hungarian, 'complete', '647.92'),
  // replay 989.04 → 988.27 (-0.77).
  (_beerRibs, 'complete', '988.27'),
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
  final dir = Directory.systemTemp.createTempSync('salt-v96-');
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

/// [corpus] with the real step sentence [sentence] deleted (STATED
/// synthesized — the recipe's own steps less one), under its own id.
Recipe _without(Recipe corpus, String sentence, String tag) {
  var hits = 0;
  final steps = [
    for (final s in corpus.steps)
      s.text.contains(sentence)
          ? (() {
              hits++;
              return s.copyWith(text: s.text.replaceFirst(sentence, ''));
            })()
          : s,
  ];
  expect(hits, 1, reason: sentence);
  return corpus.copyWith(
    id: '${corpus.id}-v96-$tag',
    slug: '${corpus.slug}-v96-$tag',
    steps: steps,
  );
}

void main() {
  test('matcherVersion 91 (v96, batch M94: the browning fat)', () {
    expect(matcherVersion, 91);
  });

  test("the share from the figures the flag prints (2705972's inputFoods: "
      'o 2 g oil per 98 g baked-from-raw breast; r = 98 × 30.22 / 22.5 = '
      '131.62 g raw on the tracer pair 2705956 / 171077): 2 / 131.62 = '
      "0.015195 — the engine's own `_browningFatShare`, never the C4 "
      '`_panFatShare`', () {
    // The engine's figure itself (the v95 D1 lesson): the same two parses.
    expect(browningFatShareForTest, 2 / 131.62);
    expect(browningFatShareForTest.toStringAsFixed(6), '0.015195');
    expect(browningFatShareForTest.toStringAsFixed(4), '0.0152');
    expect((browningFatShareForTest * 100).toStringAsFixed(2), '1.52');
    // r: the 98 g brought to raw by protein (FNDDS 2705956's 30.22 over SR
    // 171077's 22.5 — prep47 row 27's pair, `_breastFried`'s 104.76).
    expect((98 * 30.22 / 22.5).toStringAsFixed(2), '131.62');
    expect((78 * 30.22 / 22.5).toStringAsFixed(2), '104.76');
    expect(browningFatShareForTest, isNot(panFatShareForTest));
  });

  group('matcher v96 (batch M94)', skip: skipIfNoCorpus, () {
    late SaltDatabase db;
    late FixtureProvider fdc;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      db = _db();
      // 'thyme or dried' (0003's "2 teaspoons minced fresh thyme or ½
      // teaspoon dried") is a query no snapshot holds — the library's row
      // predates it — answered as no hits, as v69 answers it (STATED; the
      // line is no browning line; its recipe's per serving the fixture's).
      fdc = FixtureProvider(pending: {...pendingSearches, 'thyme or dried'});
      for (final file in {
        for (final r in _the15) r.$1,
        for (final r in _beyond) r.$1,
        for (final r in _unmoved) r.$1,
      }) {
        recipes[file] = await _compute(db, fdc, loadCorpusRecipe(file));
      }
      // Settled (the person sweeps' form): a second pass, the fixture DB's
      // search cache filled by every recipe — 0003's "thyme or dried" line
      // finds the 'thyme' answer a later recipe caches (base and tip alike,
      // closer 1's probe).
      for (final file in recipes.keys.toList()) {
        recipes[file] = await _compute(db, fdc, recipes[file]!);
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

    test(
      'the tracer pair on the fixtures: 2705956 "Chicken breast, baked, '
      'broiled, or roasted, skin not eaten, from raw" 30.22 g protein, SR '
      '171077 22.5 g — 98 × 30.22 / 22.5 = the 131.62 the flag prints',
      () async {
        Future<double> protein(String query, int fdcId) async =>
            (await fdc.search(
              query,
            )).singleWhere((h) => h.fdcId == fdcId).nutrientsPer100g!['203']!;
        final baked = await protein(
          'bone-in skin-on chicken breast halves',
          2705956,
        );
        final raw = await protein('boneless skinless chicken breasts', 171077);
        expect((baked, raw), (30.22, 22.5));
        expect((98 * baked / raw).toStringAsFixed(2), '131.62');
        expect(
          _flag('beef'),
          contains('2 g oil per 131.62 g raw chicken breast'),
        );
        // 2705972's own hit: the cooked figures (E 176, P 29.62, F 5.45) —
        // the inputFoods are in its raw JSON only.
        final sauteed = (await fdc.search(
          'whole chicken',
        )).singleWhere((h) => h.fdcId == 2705972);
        expect(
          [
            for (final n in ['208', '203', '204']) sauteed.nutrientsPer100g![n],
          ],
          [176.0, 29.62, 5.45],
        );
      },
    );

    test('the trigger on the REAL steps: every row of the 15 and the 7 '
        'beyond is a line `browningFatLinesOf` names; the two K-1 negatives '
        'and the sauce butter are not; a capped line and a C4 line are', () {
      for (final (file, position, raw, _, _, _, _, _) in [
        ..._the15,
        ..._beyond,
      ]) {
        final recipe = recipes[file]!;
        expect(nutritionLines(recipe)[position].raw, raw, reason: file);
        expect(
          browningFatLinesOf(recipe),
          contains(position),
          reason: '$file|$position',
        );
      }
      for (final (file, position, raw, _, _, admitted) in _unmoved) {
        final recipe = recipes[file]!;
        expect(nutritionLines(recipe)[position].raw, raw, reason: file);
        expect(
          browningFatLinesOf(recipe).contains(position),
          admitted,
          reason: '$file|$position',
        );
      }
    });

    test('the 15 rows at the read share: record, status, grams, energy, '
        'basis — each below its whole line', () {
      for (final (file, position, raw, fdcId, whole, grams, kcal, basis)
          in _the15) {
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
        expect(
          double.parse(grams),
          lessThan(double.parse(whole)),
          reason: reason,
        );
      }
    });

    test('D1 RULED (verify1 D1, ACCEPT 2026-10-30): the 7 rows beyond the '
        "15 the brief's trigger admits — the replay's figures", () {
      for (final (file, position, raw, fdcId, whole, grams, kcal, basis)
          in _beyond) {
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
        expect(
          double.parse(grams),
          lessThan(double.parse(whole)),
          reason: reason,
        );
      }
    });

    test('rows the arm leaves as they were (the v95 rows): the K-1 negatives '
        'skillet-roasted|2 84.00 g and brick|2 32.53 g, the sauce butter '
        'steak-au-poivre|0 56.72 g, two admitted lines the rule leaves whole '
        '(steak-au-poivre|7, classic-chicken-noodle-soup|0 — no entry, '
        'closer 1, verify1 D4) and the C4 row saltimbocca|5 at its own '
        "arm's 23.14 g", () {
      for (final (file, position, _, grams, source, _) in _unmoved) {
        final recipe = recipes[file]!;
        final row = rowIn(recipe.id, position);
        final reason = '$file|$position';
        expect(
          (row.status, row.hold, row.grams?.toStringAsFixed(2), row.gramSource),
          ('auto', null, grams, source),
          reason: reason,
        );
        expect(
          basisOf(recipe, position),
          isNot(contains('browning fat')),
          reason: reason,
        );
        expect(
          basisOf(recipe, position),
          isNot(contains(_basis)),
          reason: reason,
        );
      }
      // The C4 row keeps the C4 arm's basis (v95's text).
      expect(
        basisOf(recipes[_saltimbocca]!, 5),
        startsWith(
          'discarded in cooking — only the fat the sautéed food keeps counted · approximation (pan fat: 3.71 g',
        ),
      );
    });

    test('per line (closer 1, verify1 D3): two admitted lines of one recipe '
        'each keep their OWN min(whole, share × raw ÷ lipid) — '
        "sunday-gravy|0 and |20 (D1 RULED) each 10.13 g on the ribs' "
        '666.50 g; slow-cooker-beer|3 butter 27.93 g while its |2 oil (4.53 g '
        'its printed kept part) is capped on its own fat and unplanned', () {
      final gravy = recipes[_gravy]!;
      final ribs = db
          .ingredientMatchesFor(gravy.id)
          .where((r) => r.description!.startsWith('Pork, fresh, backribs'))
          .single;
      expect(ribs.grams?.toStringAsFixed(2), '666.50');
      for (final p in [0, 20]) {
        expect(rowIn(gravy.id, p).grams?.toStringAsFixed(2), '10.13');
      }
      // 0.015195 × 666.50 g of fat on a 100 % oil: 10.13 g.
      expect(
        (browningFatShareForTest * ribs.grams! * 100 / 100).toStringAsFixed(2),
        '10.13',
      );
      final beer = recipes[_beerRibs]!;
      final oil = rowIn(beer.id, 2);
      expect(
        (oil.grams?.toStringAsFixed(2), oil.gramSource),
        ('4.53', 'discarded'),
      );
      expect(basisOf(beer, 2), isNot(contains(_basis)));
      expect(rowIn(beer.id, 3).grams?.toStringAsFixed(2), '27.93');
    });

    test('the trigger classes — STATED synthesized (each a REAL recipe less '
        'one of its REAL sentences): a K1 skim (bouillabaisse S7 "Skim excess '
        'fat from broth."), a K2 plain pour-off (maple S3 "Pour off the fat '
        'from the skillet …"), each the recipe\'s only trigger; a pour-off '
        'down to a printed part (0003 S2 "Pour off all but 1 tablespoon fat '
        '…") and bulalo S1\'s "Pour off and reserve oil left in pot." are '
        "none, nor a skim inside a parenthesis (hungarian S4's) — without the "
        "recipe's real skim the line is no longer named", () {
      for (final (file, position, sentence) in const [
        (_bouillabaisse, 2, 'Skim excess fat from broth.'),
        (
          _maple,
          11,
          'Pour off the fat from the skillet and return to medium heat.',
        ),
        (
          _slowSoup,
          2,
          'Let the soup settle for 5 minutes, then skim the fat from the surface using a large spoon.',
        ),
        (
          _bulalo,
          0,
          'Using wide, shallow spoon, skim excess fat from surface of broth.',
        ),
        // A skim inside a parenthesis is none: hungarian S4's own
        // "(… Before reheating, skim the hardened fat from the surface …)"
        // stays once its real first sentence is gone (|6: D1 RULED).
        (
          _hungarian,
          6,
          'Skim the fat off the surface using a wide spoon; stir in the remaining 1 teaspoon vinegar and the sour cream (if using).',
        ),
      ]) {
        final real = recipes[file]!;
        expect(browningFatLinesOf(real), contains(position), reason: file);
        final less = _without(loadCorpusRecipe(file), sentence, 'trigger');
        expect(
          browningFatLinesOf(less),
          isNot(contains(position)),
          reason: file,
        );
      }
      // A fat separator (short-ribs S3, oxtails S5) is a trigger too: their
      // rows are of the 15 (above); the separator is their first.
    });

    test('a fat line no sentence names is none — STATED synthesized (no '
        'corpus row reaches the gate: its mutant moves no replay row): '
        'short-ribs less its two REAL oil sentences (S1 "Heat 1 tablespoon of '
        'the oil …" and "Repeat with the remaining 1 tablespoon oil …"), S3\'s '
        'fat separator kept: |2 is no longer named', () {
      final real = recipes[_shortRibs]!;
      expect(browningFatLinesOf(real), contains(2));
      final less = _without(
        _without(
          loadCorpusRecipe(_shortRibs),
          'Heat 1 tablespoon of the oil in a large Dutch oven over medium-high heat until smoking.',
          'heat',
        ),
        'Repeat with the remaining 1 tablespoon oil and the remaining meat.',
        'repeat',
      );
      expect(
        less.steps.map((s) => s.text).join(' '),
        contains('fat separator'),
      );
      expect(browningFatLinesOf(less), isNot(contains(2)));
    });

    test('a mention IN the first trigger sentence is "at" it, never before — '
        'STATED synthesized (closer 3, verify3 D6: no corpus line turns on it — '
        "the at-or-before mutant's text census over the 1,198 files equals "
        "the tip's 44 lines, its replay (verify3's) the tip's; the M92 / v94 "
        '"IN the first defat sentence" precedent): '
        'skillet-roasted-chicken-breasts-with-potatoes less its three REAL '
        'non-browning oil sentences (S3 "Meanwhile, toss the potatoes with 1 '
        'more tablespoon of the oil …", S6 "Whisk the remaining 3 tablespoons '
        'oil …" and "Drizzle the oil mixture …"): |2 is named in S2 "Heat 1 '
        'tablespoon of the oil …" (before) and IN the trigger S5 "While the '
        'chicken bakes, pour off any fat in the skillet, add 1 tablespoon more '
        'oil, …" — refused', () {
      final real = recipes[_skilletRoasted]!;
      expect(nutritionLines(real)[2].raw, '6 tablespoons olive oil');
      expect(browningFatLinesOf(real), isNot(contains(2)));
      var less = loadCorpusRecipe(_skilletRoasted);
      for (final (sentence, tag) in const [
        (
          'Meanwhile, toss the potatoes with 1 more tablespoon of the oil, ½ teaspoon salt, and ¼ teaspoon pepper in a microwave-safe bowl.',
          'toss',
        ),
        (
          'Whisk the remaining 3 tablespoons oil, the lemon juice, garlic, thyme, and red pepper flakes together.',
          'whisk',
        ),
        (
          'Drizzle the oil mixture over the chicken and potatoes before serving.',
          'drizzle',
        ),
      ]) {
        less = _without(less, sentence, tag);
      }
      final steps = less.steps.map((s) => s.text).toList();
      expect(
        steps[1],
        contains(
          'Heat 1 tablespoon of the oil in a 12-inch nonstick skillet over medium-high heat until just smoking.',
        ),
      );
      expect(
        steps[4],
        startsWith(
          'While the chicken bakes, pour off any fat in the skillet, add 1 tablespoon more oil, and return to medium heat until shimmering.',
        ),
      );
      // No oil sentence is left after the trigger: only the AT boundary
      // refuses |2 (the at-or-before mutant admits it: {2}).
      expect(steps.sublist(5).join(' ').toLowerCase(), isNot(contains('oil')));
      expect(browningFatLinesOf(less), isEmpty);
    });

    test('a heat sentence: a "repeat with the remaining 1 tablespoon oil" of '
        "the step's browning is one (short-ribs S1, lamb S1 — both of the "
        '15); "off the heat, whisk in …" after the pour-off reads as heat '
        'too, so steak-au-poivre|0 is refused by its mention AFTER the '
        "trigger (verify1 D6: the brief's skillet-roasted|2 is refused by "
        'both tests, so "none at or after" dropped is equivalent there)', () {
      final poivre = loadCorpusRecipe(_poivre);
      final s = poivre.steps.map((x) => x.text).join(' ');
      expect(
        s,
        contains('Off the heat, whisk in the remaining 3 tablespoons butter'),
      );
      expect(browningFatLinesOf(recipes[_poivre]!), isNot(contains(0)));
      for (final file in [_shortRibs, _lamb]) {
        expect(
          loadCorpusRecipe(
            file,
          ).steps.map((x) => x.text.toLowerCase()).join(' '),
          contains('repeat with'),
        );
      }
    });

    test('per serving: every recipe the arm moves (the fresh compute here; '
        "the replay's v95 → v96 in each comment) — the combined recipes "
        "braised-lamb-shanks (M84's |0 pair + |2) and braised-beef-short-ribs "
        "(|0's M72 deduction + |2)", () {
      expect(
        [
          for (final (file, _, _) in _totals)
            (
              file,
              db.nutritionFor(recipes[file]!.id)!.status,
              db
                  .nutritionFor(recipes[file]!.id)!
                  .caloriesPerServing
                  ?.toStringAsFixed(2),
            ),
        ],
        [
          for (final (file, status, perServing) in _totals)
            (file, status, perServing),
        ],
      );
    });

    test('a third compute (and a recompute) writes nothing: every row and '
        'total of the settled recipes as it was', () async {
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
        expect(recomputeTotals(db, nutritionRecipeOf(db, id)!.recipe), isTrue);
        expect(rowsOf(), rows, reason: file);
        expect(db.nutritionFor(id)!.totalsJson, totals, reason: file);
      }
    });
    test("a person's Confirm of a browning line is the plan's grams (closer "
        "1, verify1 D2: `_browningFatAt` in `derivedFor`, M78 verify2 D2's "
        'form) — the stored row, the derivation and the GET agree: '
        'short-ribs|2 24.12 g, bulalo|0 16.82 g, maple|11 18.95 g '
        '`discarded` with the browning basis; a line the rule leaves whole '
        '(classic-chicken-noodle-soup|0) 14.00 g `portion`; the per serving '
        'unmoved', () async {
      for (final (file, position, grams, source, basis, perServing) in [
        (_shortRibs, 2, '24.12', 'discarded', _browning('beef'), '648.25'),
        (_bulalo, 0, '16.82', 'discarded', _browning('beef'), '373.83'),
        (_maple, 11, '18.95', 'discarded', _browning('pork'), '430.70'),
        (_classic, 0, '14.00', 'portion', null, null),
      ]) {
        final corpus = loadCorpusRecipe(file);
        final recipe = await _compute(
          db,
          fdc,
          corpus.copyWith(
            id: '${corpus.id}-v96-confirm',
            slug: '${corpus.slug}-v96-confirm',
          ),
        );
        final line = nutritionLines(recipe)[position];
        await applyMatchOverride(db, fdc, recipe, position, {
          'raw': line.raw,
          'confirmed': true,
        });
        final stored = rowIn(recipe.id, position);
        final derived = (await derivedFor(
          db,
          fdc,
          recipe,
          position,
          line,
          stored,
        )).row;
        final item =
            ((await matchesBody(db, fdc, recipe))['items']! as List)
                    .cast<Map<String, Object?>>()
                    .singleWhere((i) => i['position'] == position)['match']!
                as Map<String, Object?>;
        final reason = '$file|$position';
        for (final form in <(Object?, String?, Object?)>[
          (stored.status, stored.grams?.toStringAsFixed(2), stored.gramSource),
          (
            derived.status,
            derived.grams?.toStringAsFixed(2),
            derived.gramSource,
          ),
          (
            item['status'],
            (item['grams'] as num?)?.toStringAsFixed(2),
            item['gram_source'],
          ),
        ]) {
          expect(form, ('confirmed', grams, source), reason: reason);
        }
        if (basis != null) {
          expect(item['gram_basis'], basis, reason: reason);
        } else {
          expect(item['gram_basis'], isNot(contains(_basis)), reason: reason);
        }
        if (perServing != null) {
          expect(
            db.nutritionFor(recipe.id)!.caloriesPerServing?.toStringAsFixed(2),
            perServing,
            reason: reason,
          );
        }
      }
    });
    test("a person's typed grams on a browning line stand (the plan weighs "
        'only an engine row, `_m52Engine`: no `override` row) — '
        'short-ribs|2 typed 30 g: stored, derived and on the GET 30.00 g '
        '`override`, no browning basis (its own DB: the decision carries by '
        'the line text)', () async {
      final own = _db();
      final p = FixtureProvider(
        pending: {...pendingSearches, 'thyme or dried'},
      );
      final recipe = await _compute(own, p, loadCorpusRecipe(_shortRibs));
      expect(
        own
            .ingredientMatchesFor(recipe.id)
            .singleWhere((m) => m.position == 2)
            .grams
            ?.toStringAsFixed(2),
        '24.12',
      );
      final line = nutritionLines(recipe)[2];
      await applyMatchOverride(own, p, recipe, 2, {
        'raw': line.raw,
        'grams': 30,
      });
      final stored = own
          .ingredientMatchesFor(recipe.id)
          .singleWhere((m) => m.position == 2);
      final derived = (await derivedFor(own, p, recipe, 2, line, stored)).row;
      final item =
          ((await matchesBody(own, p, recipe))['items']! as List)
                  .cast<Map<String, Object?>>()
                  .singleWhere((i) => i['position'] == 2)['match']!
              as Map<String, Object?>;
      for (final form in <(String?, Object?)>[
        (stored.grams?.toStringAsFixed(2), stored.gramSource),
        (derived.grams?.toStringAsFixed(2), derived.gramSource),
        ((item['grams'] as num?)?.toStringAsFixed(2), item['gram_source']),
      ]) {
        expect(form, ('30.00', 'override'));
      }
      expect(item['gram_basis'], isNot(contains(_basis)));
    });
    test("a person's skip of the browned meat leaves no browning plan (closer "
        '2, verify2 D2: `_unplannedOf` reads `_browningFatAt`): '
        'short-ribs|0 / irish-stew|0 skipped through the PUT, the browning '
        'line goes back to its engine row — short-ribs|2 24.12 → 28.00 g '
        '`portion`, irish|1 20.39 → 42.00 g `portion`, no browning basis — '
        'and a full compute after the PUT writes nothing', () async {
      for (final (file, meat, fat, planned, whole, perServing) in [
        (_shortRibs, 0, 2, '24.12', '28.00', '83.18'),
        (_irish, 0, 1, '20.39', '42.00', '166.10'),
      ]) {
        final corpus = loadCorpusRecipe(file);
        final recipe = await _compute(
          db,
          fdc,
          corpus.copyWith(
            id: '${corpus.id}-v96-skip',
            slug: '${corpus.slug}-v96-skip',
          ),
        );
        final reason = '$file|$fat';
        (String, String?, String?) form(int position) {
          final r = rowIn(recipe.id, position);
          return (r.status, r.grams?.toStringAsFixed(2), r.gramSource);
        }

        expect(form(fat), ('auto', planned, 'discarded'), reason: reason);
        await applyMatchOverride(db, fdc, recipe, meat, {
          'raw': nutritionLines(recipe)[meat].raw,
          'skipped': true,
        });
        expect(form(meat).$1, 'skipped', reason: reason);
        expect(form(fat), ('auto', whole, 'portion'), reason: reason);
        expect(basisOf(recipe, fat), isNot(contains(_basis)), reason: reason);
        String? perServingOf() =>
            db.nutritionFor(recipe.id)!.caloriesPerServing?.toStringAsFixed(2);
        expect(perServingOf(), perServing, reason: reason);
        List<Object?> rowsOf() => [
          for (final m in db.ingredientMatchesFor(recipe.id))
            (m.position, m.fdcId, m.grams, m.gramSource, m.status, m.hold),
        ];
        final rows = rowsOf();
        final totals = db.nutritionFor(recipe.id)!.totalsJson;
        expect(
          await matchAndCompute(
            db,
            fdc,
            nutritionRecipeOf(db, recipe.id)!.recipe,
          ),
          isNull,
        );
        expect(rowsOf(), rows, reason: reason);
        expect(db.nutritionFor(recipe.id)!.totalsJson, totals, reason: reason);
      }
    });
    test('the M52 key (closer 2, verify2 D3: `_m52Key` reads '
        "`_browningFatAt`, M78's `pans` twin — v78 \"the M52 key (verify1 "
        'D4)"): a browning line\'s engine and planned forms key alike '
        '(short-ribs|2, irish-stew|1); a fat line the arm refuses keys its '
        'medium bit (skillet-roasted-chicken-breasts-with-potatoes|2, a K-1 '
        'negative)', () {
      for (final (file, position, alike) in [
        (_shortRibs, 2, true),
        (_irish, 1, true),
        (_skilletRoasted, 2, false),
      ]) {
        final recipe = recipes[file]!;
        expect(
          browningFatLinesOf(recipe).contains(position),
          alike,
          reason: '$file|$position',
        );
        final rows = db.ingredientMatchesFor(recipe.id);
        String keyAs(String source) => m52KeyOf(recipe, [
          for (final r in rows)
            r.position == position ? r.copyWith(gramSource: source) : r,
        ]);
        expect(
          keyAs('discarded') == keyAs('portion'),
          alike,
          reason: '$file|$position',
        );
      }
    });
  });

  // RULE C (the NEW reader `_browningFatLines`, memo:browningFat, once per
  // index; each fat line's mentions read once, `browningFatLineReads`).
  // STATED: braised-beef-short-ribs' REAL meat line |0 and 399 copies of its
  // REAL "2 tablespoons vegetable oil" (|2; the cap-shape exception) under
  // 120 × 10,000-character steps every sentence of which heats the oil —
  // TRUE: the last step skims the fat (every oil line admitted and planned,
  // each at the browned ribs' share, 24.12 g); QUIET: no step skims, pours
  // off or separates fat (the scan finds no trigger: no line read). The
  // counts below are the tree's, EXACTLY (fix96/c1 cost probe; base vs tip
  // in closer1.md).
  group(
    'RULE C, the browning-fat reader at the caps',
    skip: skipIfNoCorpus,
    () {
      for (final (shape, loud) in const [('TRUE', true), ('QUIET', false)]) {
        test('$shape: 399 oil lines and the ribs, every sentence heating the '
            'oil${loud ? ', the last step skimming the fat' : ', no skim'}; '
            'the counts exact, within the backstop', () async {
          final base = loadCorpusRecipe(_shortRibs);
          const meat =
              '3½ pounds boneless beef short ribs, trimmed of excess fat';
          const oil = '2 tablespoons vegetable oil';
          expect(nutritionLines(base)[0].raw, meat);
          expect(nutritionLines(base)[2].raw, oil);
          final r = capped(
            base,
            [meat, for (var i = 1; i < capLines; i++) oil],
            [
              for (var i = 0; i < capSteps; i++)
                fill(
                  loud && i == capSteps - 1
                      ? 'Skim the fat from the liquid. '
                      : 'Heat the oil in a Dutch oven. ',
                  capStep,
                ),
            ],
          );
          final db = wp.tempDb();
          final provider = FixtureProvider(pending: pendingSearches);
          wp.saveRecipe(db, r);
          Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
          Future<void> timed(
            String step,
            Future<Object?> Function() run,
          ) async {
            stepIndexCounts.clear();
            final sw = Stopwatch()..start();
            await run();
            final ms = sw.elapsedMilliseconds;
            final counts = Map.of(stepIndexCounts)..remove('names');
            expectBounded(r, counts, '$shape $step');
            expect(counts, _capCounts['$shape $step'], reason: '$shape $step');

            expect(ms, lessThan(backstopMs), reason: '$shape $step');
          }

          await timed('compute', () => matchAndCompute(db, provider, stored()));
          await timed('GET', () => matchesBody(db, provider, stored()));
          await timed('recompute', () async => recomputeTotals(db, stored()));
          final rows = db.ingredientMatchesFor(r.id);
          final oils = rows.where((m) => m.position > 0).toList();
          expect(oils.length, capLines - 1);
          expect(
            {for (final m in oils) (m.grams?.toStringAsFixed(2), m.gramSource)},
            {if (loud) ('24.12', 'discarded') else ('28.00', 'portion')},
          );
          expect(browningFatLinesOf(stored()).length, loud ? capLines - 1 : 0);
        }, timeout: const Timeout(Duration(minutes: 3)));
      }
    },
  );
}

/// Each cap shape's counts on the tree (fix96/c1 cost probe; the
/// process-wide `names` aside).
const Map<String, Map<String, int>> _capCounts = {
  'TRUE compute': {
    'indexes': 1,
    'memo:skinSentences': 1,
    'allSentences': 1,
    'lower': 1,
    'sentences': 40080,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 279387,
    'memo:naming': 2,
    'memo:strainAt': 1,
    'memo:savesRemainder': 1,
    'memo:setAsideLine': 1,
    'memo:measuresOut': 1,
    'memo:reservedWhole': 1,
    'memo:discards': 1,
    'memo:oilOwners': 1,
    'memo:reservedUse': 1,
    'memo:baconPan': 1,
    'memo:baconKept': 1,
    'memo:pourOffFat': 1,
    'memo:dips': 1,
    'memo:leftInBowl': 1,
    'memo:keptSolids': 1,
    'memo:browningFat': 1,
    'memo:parenthetical': 1,
    'browningFatLineReads': 399,
    'memo:defatsLiquid': 1,
  },
  'TRUE GET': {
    'leanOnlyReads': 1,
    'carriedReads': 1,
    'indexes': 1,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'lower': 1,
    'sentences': 40080,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 279387,
    'memo:naming': 2,
    'memo:strainAt': 1,
    'memo:savesRemainder': 1,
    'memo:setAsideLine': 1,
    'memo:measuresOut': 1,
    'memo:reservedWhole': 1,
    'memo:discards': 1,
    'memo:leftInBowl': 1,
    'memo:dips': 1,
    'memo:cutShare': 1,
    'memo:keptSolids': 1,
    'memo:panFatLines': 1,
    'memo:browningFat': 1,
    'memo:parenthetical': 1,
    'browningFatLineReads': 399,
    'memo:skinSentences': 1,
    'allSentences': 1,
    'memo:liftedFromMarinade': 1,
    'memo:defatsLiquid': 1,
    'memo:oilOwners': 1,
    'memo:reservedUse': 1,
    'memo:baconPan': 1,
    'memo:baconKept': 1,
    'memo:pourOffFat': 1,
    'm52Keys': 1,
    'memo:coatShape': 1,
    'memo:fries': 1,
    'memo:shallowFries': 1,
    'memo:mayHoldCoat': 1,
  },
  'TRUE recompute': {
    'indexes': 1,
    'memo:dips': 1,
    'lower': 1,
    'sentences': 40080,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'memo:pourAway': 1,
    'memo:oilOwners': 1,
    'memo:reservedUse': 1,
    'memo:leftInBowl': 1,
    'memo:keptSolids': 1,
    'memo:browningFat': 1,
    'memo:parenthetical': 1,
    'browningFatLineReads': 399,
    'words': 279387,
    'memo:naming': 1,
    'memo:skinSentences': 1,
    'allSentences': 1,
    'memo:baconPan': 1,
    'memo:baconKept': 1,
    'memo:pourOffFat': 1,
    'memo:defatsLiquid': 1,
  },
  'QUIET compute': {
    'indexes': 1,
    'memo:skinSentences': 1,
    'allSentences': 1,
    'lower': 1,
    'sentences': 40080,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 279720,
    'memo:naming': 1,
    'memo:strainAt': 1,
    'memo:savesRemainder': 1,
    'memo:setAsideLine': 1,
    'memo:measuresOut': 1,
    'memo:reservedWhole': 1,
    'memo:discards': 1,
    'memo:oilOwners': 1,
    'memo:reservedUse': 1,
    'memo:baconPan': 1,
    'memo:baconKept': 1,
    'memo:pourOffFat': 1,
    'memo:dips': 1,
    'memo:leftInBowl': 1,
    'memo:keptSolids': 1,
    'memo:browningFat': 1,
    'memo:defatsLiquid': 1,
  },
  'QUIET GET': {
    'leanOnlyReads': 1,
    'carriedReads': 1,
    'indexes': 1,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'lower': 1,
    'sentences': 40080,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 279720,
    'memo:naming': 1,
    'memo:strainAt': 1,
    'memo:savesRemainder': 1,
    'memo:setAsideLine': 1,
    'memo:measuresOut': 1,
    'memo:reservedWhole': 1,
    'memo:discards': 1,
    'memo:leftInBowl': 1,
    'memo:dips': 1,
    'memo:cutShare': 1,
    'memo:keptSolids': 1,
    'memo:panFatLines': 1,
    'memo:browningFat': 1,
    'memo:skinSentences': 1,
    'allSentences': 1,
    'memo:liftedFromMarinade': 1,
    'memo:defatsLiquid': 1,
    'memo:oilOwners': 1,
    'memo:reservedUse': 1,
  },
  'QUIET recompute': {
    'indexes': 1,
    'memo:dips': 1,
    'lower': 1,
    'sentences': 40080,
    'memo:leftInBowl': 1,
    'heads': 1,
    'memo:keptSolids': 1,
    'memo:browningFat': 1,
    'memo:defatsLiquid': 1,
  },
};
