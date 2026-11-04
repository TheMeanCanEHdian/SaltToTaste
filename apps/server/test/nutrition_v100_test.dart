// Matcher v100 (batch M97; matcherVersion 94 — the uncoated SHALLOW-FRY
// reader and the ROUX guard; M97 design_v2 §2, under the standing
// authorization (2026-10-07) and the owner's 2026-11-02 "go ahead with the
// shallow-fry reader"; zero requests — L54 was the orchestrator's: no plain
// uncoated meatball record exists, FNDDS 2706395 and 2706467 read and
// rejected). Q1 RULED (a) and Q2 RULED (b) by the orchestrator: the figure
// is the shipped `_browningFatShare` (FNDDS 2705972's sauté film, 2 g oil
// per 131.62 g raw breast = 1.5195 %) as a FLAGGED stand-in by cooking
// method, on the pieces' RAW MIX (the counted rows of the first shallow
// line's ingredient group before it, never a fat line); an amount-less
// "for pan-frying" line is admitted (no whole to cap at).
// REACH (fix100 replay on snapshot 32 against the v99 rows; 3 rows, 0
// person rows): sunday-gravy|20 10.13 → 11.19 g (SF-1; SF-2: the browning
// plan skips it), spaghetti-and-meatballs|10 0.00 `unmeasured` → 10.02 g
// `discarded` (SF-1, Q2 b), broiled-chicken-with-gravy|12 20.68 `discarded`
// → 28.36 g `density` (RX-1: the butter a roux binds is in the gravy).
// Every whole-recipe figure is a fresh compute on the recorded fixtures
// (FixtureProvider), the replay's in each comment. Never the network.
// Every corpus line and step is real; STATED synthesized (named at each):
// the cap shapes' repeated real lines and real sentences (one real sentence
// deleted for QUIET), the person paths' typed / skipped real rows, and the
// 0351 gate variants (R4's window, R5's reuse; closer1: R5's away / now-empty
// / named-reuse / cooking terms, R2's `_heatsTheOil` amount and the basis
// arm — real sentences moved or carried in from other corpus recipes, two
// reworded heat sentences, one retyped real line; closer2: RX-1's own
// sentence / "roux" / "flour over" / "flour mixture" forms on the real 1076,
// R5's wipe / plain pour-off / kept-part pour-off / batch run, R4's slotted
// spoon / drain / "<noun> mixture" / not-a-piece forms, R3's cold placement /
// fat aside / batch word / no add, R2's other food's print and the plan's
// below-gate line on the real 0351 — real sentences carried in, a few words
// reworded or a line retyped — and P's two edges: every piece skipped
// through the PUT, 1076's real butter line carried into 0351's group 1;
// closer3: R4's window edge (S3 split after S3.1), R5's "pan" fold, lead-in
// and "repeat with" join, the plan's unheld term (a retyped held line) and
// the flag's butter clause (0095's real butter line) on the real 0351, and
// RX-1's amount run on the real 1076 — real sentences carried in, one word
// reworded or a line retyped; closer4: the one table's 62 SYNTH rows on the
// real 0351 / 1076 — the weight print, the lifted or added forms and words
// no corpus sentence holds around 0351's meatballs ("lays", "laid", "puts",
// "the pieces", "the batch", "each meatball", the lift verbs, destinations,
// fillers and not-a-piece words), the vessel words and introducers ("wok",
// "griddle", "pan", "pot", "another", "the second"), "reserve the oil",
// "now empty", a skillet's fond, "stir-fry", S3.0's vessel deleted — each
// stated at its row; closer5: the table's 84 SYNTH rows — verify5's probe
// inputs and the mechanical screen's: the verb forms no corpus sentence
// holds around 0351's meatballs ("transfers", "lifted", "drains",
// "arranges", "adds" …), fillers, destinations and drain forms, the "leav…
// in" / "to the …" / "reserve …" reuse words, the fat objects' words and
// units, vessel introducers with S3.0's fry vessel renamed, cooking
// lead-ins, a no-break space between an amount and its unit, a decimal
// and a semicolon in a reserve run, and the stated recipes: two fry lines
// (A21_*, PL_splitU), |20 retyped "1 bottle olive oil, for pan-frying"
// (A23), group 1 split before |20 (PL_groupOf) — each stated at its row;
// closer6 (the orchestrator, verify6 D1–D4): the table's 8 SYNTH rows —
// verify6's 7 surviving code terms: R1's every-mention clause and FIRST
// mention (0095's real butter line at |20, mentioned twice), R3's
// heat-clause null branch (a "repeat with" heat naming no pan oil), R5's
// discard `now == 1` (0142's real pour-off with one word changed, then
// 0310's real reheat) and the run's `later` carry (two batch sentences
// between two lift-outs), the plan's sibling lipid read (|20 retyped
// "½ cup extra-virgin olive oil") and its `sized` guard (a two-fry recipe
// with one amount-less line) — each stated at its row; each named at its
// test).
// STATED EQUIVALENT (no corpus pin can kill them; named, never counted):
// - C4 precedence (R0's `_panFatAt`): the two ample C4 lines,
//   best-crab-cakes|14 and chicken-saltimbocca|5, are refused by R2 too
//   (their heat sentences heat 1 / 2 tablespoons) — and saltimbocca by R3;
// - the multiplier form: the flag prints '1.52', the engine multiplies
//   `_browningFatShare` (0.015195…) — equal to the cent on both reach rows
//   (11.19, 10.02);
// - R4's every-mention clause: DROPPED from the rule (pA §10, measured
//   equivalent under the line gate), so it has no mutant;
// - the per-pan split on the corpus: every recipe holds one shallow line,
//   so the split is the identity there (P17 exercises it at the caps;
//   closer5: pinned by value on the stated two-fry recipes, A21_* and
//   PL_splitU — the FIRST line's group and the equal shares);
// - `_m52KeysAlike`'s piece refusal (fix.md M15): a confirm passes it the
//   confirmed line's own row — a fat or a coat part, never a piece — so
//   the refusal never decides a returned value on the corpus.
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
const _gravy = '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml';
const _spaghetti = '0357-spaghetti-and-meatballs.yaml';
const _broiled = '1076-broiled-chicken-with-gravy.yaml';
const _scallops =
    '0043-pan-seared-scallops-with-wilted-spinach-watercress-and-orange-salad.yaml';
const _tacos = '0480-steak-tacos.yaml';
const _cioppino = '0108-cioppino.yaml';
const _halibut = '0273-braised-halibut-with-leeks-and-mustard.yaml';
const _gumbo = '0107-creole-style-shrimp-and-sausage-gumbo.yaml';
const _portobellos =
    '0546-stir-fried-portobellos-with-ginger-oyster-sauce.yaml';
const _sweetFries = '0318-thick-cut-sweet-potato-fries.yaml';
const _irish = '1070-irish-stew-with-carrots-and-turnips.yaml';
const _dumplings = '0095-chicken-and-dumplings.yaml';
const _roastedShrimp =
    '0280-garlicky-roasted-shrimp-with-parsley-and-anise.yaml';
const _slowRoasted =
    '0133-slow-roasted-chicken-parts-with-shallot-garlic-pan-sauce.yaml';
const _broccoli = '1096-skillet-roasted-broccoli.yaml';
const _smothered = '0205-smothered-pork-chops.yaml';
const _cassoulet = '0461-simplified-cassoulet-with-pork-and-kielbasa.yaml';

// Computed first (as nutrition_v59_test): its deli-ham line caches the one
// recorded answer holding 168322, the cooked bacon rule B1 counts
// cassoulet|8 on — a cached search hit, no fixture recorded.
const _deliHam = '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml';

const _basis =
    'shallow-fried and lifted out — only the oil the fried pieces keep counted';

/// The shallow-fry flag (Q1 (a): the stand-in said, the food word fixed).
const _flag =
    'approximation (shallow-fry uptake: 1.52 g fat per 100 g of the raw fried pieces — USDA FNDDS 2705972 recipe: 2 g oil per 131.62 g raw chicken breast (a stand-in by cooking method: the lifted-out pieces keep a film, the rest of the oil stays in the pan))';

/// The rows the reader must leave as they were — the v99 rows, byte-equal
/// on the replay: (file, position, raw, record, grams, source, kcal, the
/// rule that refuses it, the pin). Each a REAL corpus line.
const _negatives = [
  // P5 R2: S2.0 "Add 2 tablespoons of the vegetable oil to a 12-inch
  // skillet and heat …" — a print of the head below ¼ cup.
  (_scallops, 5, '¼ cup vegetable oil', 2710180, '56.00', 'portion', '504.00'),
  // P6 the line gate: 2 tablespoons (a T0 sear, design D2).
  (
    _tacos,
    11,
    '2 tablespoons vegetable oil',
    2710180,
    '28.00',
    'portion',
    '252.00',
  ),
  // P7 R3: "Add onions …" joins the fat before the halibut leaves (its
  // one counted piece row before |0: none — so a dropped R3 admits the
  // line, `shallowFryLinesOf`, but sizes nothing: the value pin is the next).
  (_cioppino, 0, '¼ cup vegetable oil', 2710180, '56.00', 'portion', '504.00'),
  // P7′ R3 (the value pin, fix100's mutant probe): S1.0 "Add the butter to
  // the Dutch oven and melt …", S1.1 "Add the carrots, celery, onion …" —
  // the vegetables, never the chicken S2.0 lifts out (a dropped R3: 25.07 g).
  (
    _dumplings,
    3,
    '4 tablespoons (½ stick) unsalted butter',
    173430,
    '56.72',
    'density',
    '406.70',
  ),
  // P8 R5: "Add leeks, mustard, and ½ teaspoon salt to skillet and cook"
  // (its fish row unmatched — no snapshot answers the raw halibut — so a
  // dropped R5 sizes nothing here: the value pin is the synthesized one).
  (
    _halibut,
    2,
    '6 tablespoons unsalted butter',
    173430,
    '85.08',
    'density',
    '610.05',
  ),
  // P9 R4: a roux; nothing lifted out.
  (_gumbo, 3, '½ cup vegetable oil', 2710180, '112.00', 'portion', '1008.00'),
  // P10 R1: its one mention heats nothing.
  (
    _portobellos,
    8,
    '¼ cup peanut or vegetable oil',
    2710187,
    '56.00',
    'portion',
    '504.00',
  ),
  // P10′ R1 (the value pin, fix100's mutant probe): S1.1 "Combine melted
  // butter, oil, garlic, … in large bowl" heats nothing — the broiled shrimp
  // S2.2 transfers took it (a dropped R1: 5.55 g).
  (
    _roastedShrimp,
    3,
    '¼ cup vegetable oil',
    2710180,
    '56.00',
    'portion',
    '504.00',
  ),
  // P11 R0: a frying-oil medium (the fryer block's uptake).
  (
    _sweetFries,
    4,
    '3 cups peanut oil',
    2710187,
    '121.27',
    'discarded',
    '1091.43',
  ),
  // P12: the browning film kept — the ribs' on |0 (albondigas-en-chipotle|2's
  // 5.17 g, RULED, is pinned byte-equal by nutrition_v96_test's `_beyond`:
  // computed alone its oregano line asks "oregano or dried", a query no
  // snapshot holds; v96's shared fixture DB computes braised-oxtails' "1
  // tablespoon minced fresh oregano, divided" first — measured, fix100:
  // oxtails then albondigas computes on the fixtures).
  (
    _gravy,
    0,
    '2 tablespoons olive oil',
    2710186,
    '10.13',
    'discarded',
    '91.17',
  ),
  // P13 the roux window (h / h+1): irish-stew's flour is later in the step
  // (RX-2, deferred D3) — the browning row stands.
  (
    _irish,
    1,
    '3 tablespoons vegetable oil',
    2710180,
    '20.39',
    'discarded',
    '183.51',
  ),
  // R4's "names a piece" clause (closer1, verify1 D4): it ALONE refuses the
  // next two real rows (mutant X, the clause off — `piece ?? ''`: 39.86 g and
  // 8.62 g `discarded`). 0133 S3.0 "Melt butter in now-empty skillet over
  // medium-low heat." heats the butter; the first lift-out after it, S4.1
  // "Transfer sheet to upper rack and broil chicken …", moves the sheet
  // (`_notAPiece`) — the butter is the served pan sauce's.
  (
    _slowRoasted,
    7,
    '4 tablespoons unsalted butter, cut into 4 pieces',
    173430,
    '56.72',
    'density',
    '406.70',
  ),
  // 1096 S1.0 "Add oil to 12-inch nonstick or carbon-steel skillet …" heats
  // the oil; its lift-out S2.5 "Transfer to platter; …" names no piece — the
  // broccoli leaves with what it took up.
  (
    _broccoli,
    2,
    '5 tablespoons vegetable oil',
    2710180,
    '70.00',
    'portion',
    '630.00',
  ),
  // `_shallowFryIn`'s head gate (`!_panFatHeads.contains(head)`, the
  // reader's first term — closer4, verify4 D1) ALONE refuses the next two
  // real rows: neither head is a pan fat, yet each line's mentions heat it
  // and the pieces leave — 0205 S0.0 "Fry the bacon in a small saucepan …",
  // S0.1 "Using a slotted spoon, transfer the bacon to a paper towel–lined
  // plate …" (the broth whisked into that pan); 0461 S2.0 "… fry the bacon
  // in a large Dutch oven …", S2.1 "… transfer the remaining bacon to a
  // paper towel–lined plate …". Mutant V01 (the gate dropped) moves both on
  // the snapshot-32 replay (verify4): 414.03 `density` → 260.26 g
  // `discarded`, and 81.93 `weight` → 25.11 g `discarded`. The kcal column
  // is this form's (the row's record × its grams): cassoulet's 321.98 =
  // 168277's 393 kcal × 81.93 g; the replay's stored 494.11 is rule B1's
  // parts (168322 56.13 g × 468 + 172345 25.80 g × 897), unmoved with it.
  (
    _smothered,
    2,
    '1¾ cups low-sodium chicken broth',
    171609,
    '414.03',
    'density',
    '66.24',
  ),
  (
    _cassoulet,
    8,
    '6 ounces (about 6 slices) bacon, cut into ¼-inch pieces',
    168277,
    '81.93',
    'weight',
    '321.98',
  ),
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
  final dir = Directory.systemTemp.createTempSync('salt-v100-');
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
    'P18: matcherVersion 95 (v100 set it to 94, batch M97: the shallow-fry reader and '
    'the roux guard)',
    () {
      // RE-PIN (fix101 batch, v101): matcherVersion 95 (was 94).
      expect(matcherVersion, 95);
    },
  );

  group('matcher v100 (batch M97)', skip: skipIfNoCorpus, () {
    late SaltDatabase db;
    late FixtureProvider fdc;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      db = _db();
      fdc = FixtureProvider(pending: pendingSearches);
      for (final file in {
        _deliHam,
        _gravy,
        _spaghetti,
        _broiled,
        for (final n in _negatives) n.$1,
      }) {
        recipes[file] = await _compute(db, fdc, loadCorpusRecipe(file));
      }
      // Settled (the person sweeps' form): a second pass over the filled
      // search cache.
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

    // closer5: a row with no grams (A23's tip row) prints 'null'.
    String kcalOf(IngredientMatchRow row) => row.grams == null
        ? 'null'
        : (kcalPer100g(
                    knownFood(db, nutrientSiblings[row.fdcId] ?? row.fdcId!)!,
                  ) *
                  row.grams! /
                  100)
              .toStringAsFixed(2);

    (int?, String, String?, String?, String?, String) formOf(
      IngredientMatchRow r,
    ) => (
      r.fdcId,
      r.status,
      r.hold,
      r.gramSource,
      r.grams?.toStringAsFixed(2),
      kcalOf(r),
    );

    test('P1 / P2 / P3 (SF-1, SF-2): sunday-gravy|20 "½ cup olive oil" — '
        'S3.0 heats it in a large nonstick skillet, S3.1 "Add the meatballs '
        '…", S3.2 "Transfer the meatballs to a paper towel–lined plate", the '
        "skillet never used again — is the shallow plan's: 11.19 g "
        '`discarded`, 100.71 kcal (replay 10.13 → 11.19, 91.17 → 100.71) = '
        "0.015195 × the pieces' raw 736.23 g; it stays in the browning TEXT "
        "set, the ribs' |0 keeps its film (mutants: the reader off, or the "
        "browning plan's skip dropped → 10.13; P = the meat rows → 7.75)", () {
      final gravy = recipes[_gravy]!;
      expect(nutritionLines(gravy)[20].raw, '½ cup olive oil');
      final row = rowIn(gravy.id, 20);
      expect(formOf(row), (
        2710186,
        'auto',
        null,
        'discarded',
        '11.19',
        '100.71',
      ));
      expect(basisOf(gravy, 20), '$_basis · $_flag');
      expect(basisOf(gravy, 20), contains('2705972'));
      expect(basisOf(gravy, 20), contains('the raw fried pieces'));
      // The text sets, after the values (the value pins kill first).
      expect(shallowFryLinesOf(gravy), {20});
      expect(browningFatLinesOf(gravy), containsAll([0, 20]));
      // P3 (design C2-1): the pieces = the counted rows of |20's group (YAML
      // group 1, |10–|23) from its start to |20, no fat line among them —
      // |15 "Table salt" has no grams and is not counted.
      final pieces = [
        for (final m in db.ingredientMatchesFor(gravy.id))
          if (m.position >= 10 && m.position < 20 && (m.grams ?? 0) > 0) m,
      ];
      expect(
        [for (final m in pieces) m.position],
        [10, 11, 12, 13, 14, 16, 17, 18, 19],
      );
      final raw = pieces.fold<double>(0, (n, m) => n + m.grams!);
      expect(raw.toStringAsFixed(2), '736.23');
      expect((browningFatShareForTest * raw).toStringAsFixed(2), '11.19');
      // The printed '1.52' gives the same cent (STATED EQUIVALENT).
      expect((0.0152 * raw).toStringAsFixed(2), '11.19');
      // P12: |0 keeps the ribs' browning film (pB B7 / D4 not built).
      expect(formOf(rowIn(gravy.id, 0)), (
        2710186,
        'auto',
        null,
        'discarded',
        '10.13',
        '91.17',
      ));
    });

    test('P19 (SF-1 under Q2 b): spaghetti-and-meatballs|10 "Vegetable oil, '
        'for pan-frying" (no amount) — S2.0 pours it into a 12-inch skillet, '
        'S2.2 "Add the meatballs …", S2.3 "Transfer the meatballs to a paper '
        'towel–lined plate and discard the oil left in the skillet" — 10.02 g '
        '`discarded` 90.18 kcal (replay 0.00 `unmeasured` → 10.02) = 0.015195 '
        '× |0–|9 659.41 g (mutant: `amounts.isNotEmpty` restored → 0.00 '
        '`unmeasured`)', () {
      final spaghetti = recipes[_spaghetti]!;
      expect(
        nutritionLines(spaghetti)[10].raw,
        'Vegetable oil, for pan-frying',
      );
      final row = rowIn(spaghetti.id, 10);
      expect(formOf(row), (
        2710180,
        'auto',
        null,
        'discarded',
        '10.02',
        '90.18',
      ));
      expect(basisOf(spaghetti, 10), '$_basis · $_flag');
      expect(shallowFryLinesOf(spaghetti), {10});
      final raw = [
        for (final m in db.ingredientMatchesFor(spaghetti.id))
          if (m.position < 10 && (m.grams ?? 0) > 0) m.grams!,
      ].fold<double>(0, (n, g) => n + g);
      expect(raw.toStringAsFixed(2), '659.41');
      expect((browningFatShareForTest * raw).toStringAsFixed(2), '10.02');
    });

    test('P4 (RX-1, the roux guard): broiled-chicken-with-gravy|12 "2 '
        'tablespoons unsalted butter" — S3.1 "Melt butter in now-empty '
        'saucepan over medium heat." then S3.2 "Add flour and cook …" — is no '
        "browning line: the engine's whole row, 28.36 g `density` 203.35 kcal "
        '(replay 20.68 `discarded` → 28.36 = v95) (mutant: the guard off → '
        '20.68 `discarded`)', () {
      final broiled = recipes[_broiled]!;
      expect(nutritionLines(broiled)[12].raw, '2 tablespoons unsalted butter');
      expect(formOf(rowIn(broiled.id, 12)), (
        173430,
        'auto',
        null,
        'density',
        '28.36',
        '203.35',
      ));
      expect(basisOf(broiled, 12), '2 tablespoon ≈ 30 mL');
      expect(browningFatLinesOf(broiled), isNot(contains(12)));
      expect(shallowFryLinesOf(broiled), isEmpty);
    });

    test('P5–P13 NEGATIVES: the v99 rows, unmoved — scallops|5 (R2), '
        'steak-tacos|11 (the line gate), cioppino|0 and '
        'chicken-and-dumplings|3 (R3), braised-halibut|2 (R5), creole '
        'gumbo|3 (R4), stir-fried-portobellos|8 and garlicky-roasted-shrimp|3 '
        '(R1), '
        'thick-cut-sweet-potato-fries|4 (R0, a frying oil), sunday-gravy|0 and '
        'albondigas|2 (the browning film), irish-stew|1 (the roux window), '
        'slow-roasted-chicken-parts|7 and skillet-roasted-broccoli|2 (R4: the '
        'lift-out names no piece), smothered-pork-chops|2 and '
        'simplified-cassoulet|8 (the head gate) — none a shallow-fry line', () {
      for (final (file, position, raw, fdcId, grams, source, kcal)
          in _negatives) {
        final recipe = recipes[file]!;
        final reason = '$file|$position';
        expect(nutritionLines(recipe)[position].raw, raw, reason: reason);
        final row = rowIn(recipe.id, position);
        expect(formOf(row), (
          fdcId,
          'auto',
          null,
          source,
          grams,
          kcal,
        ), reason: reason);
        expect(
          basisOf(recipe, position),
          isNot(contains(_basis)),
          reason: reason,
        );
      }
      // The text sets, after every value (the value pins kill first).
      for (final (file, position, _, _, _, _, _) in _negatives) {
        expect(
          shallowFryLinesOf(recipes[file]!),
          isNot(contains(position)),
          reason: '$file|$position',
        );
      }
    });

    test('the gates no corpus row moves by value — STATED synthesized (each '
        "the REAL 0351, its own lines, real sentences only): R4's window — "
        'S3 split into three steps (S3.0 | S3.1 | S3.2–S3.5: the lift-out two '
        "steps after the heat); R5's named reuse — 0351's own S1.3 \"Add the "
        'crushed tomatoes and broth, scraping up any browned bits." repeated '
        'right after S3.2 (the skillet deglazed: its fat reused). Each refuses '
        '|20, which goes back to the browning film, 10.13 g (mutants: the '
        'window dropped / R5 dropped → 11.19)', () async {
      final real = loadCorpusRecipe(_gravy);
      final s3 = real.steps[3].text;
      const heat =
          'When the sauce is 30 minutes from being done, heat the oil in a large nonstick skillet over medium-high heat until shimmering. ';
      const add =
          'Add the meatballs and cook until well browned all over, 5 to 7 minutes. ';
      const lift =
          'Transfer the meatballs to a paper towel–lined plate to drain briefly. ';
      const deglaze =
          'Add the crushed tomatoes and broth, scraping up any browned bits. ';
      expect(s3, startsWith('$heat$add$lift'));
      expect(real.steps[1].text, contains(deglaze.trim()));
      List<RecipeStep> renumbered(List<String> texts) => [
        for (final (i, t) in texts.indexed) RecipeStep(number: i + 1, text: t),
      ];
      final texts = [for (final step in real.steps) step.text];
      for (final (tag, steps) in [
        (
          'window',
          renumbered([
            ...texts.take(3),
            heat.trim(),
            add.trim(),
            s3.substring(heat.length + add.length),
            ...texts.skip(4),
          ]),
        ),
        (
          'reuse',
          renumbered([
            ...texts.take(3),
            s3.replaceFirst(lift, '$lift$deglaze'),
            ...texts.skip(4),
          ]),
        ),
      ]) {
        final recipe = await _compute(
          db,
          fdc,
          real.copyWith(
            id: '${real.id}-v100-$tag',
            slug: '${real.slug}-v100-$tag',
            steps: steps,
          ),
        );
        expect(
          formOf(rowIn(recipe.id, 20)),
          (2710186, 'auto', null, 'discarded', '10.13', '91.17'),
          reason: tag,
        );
        expect(basisOf(recipe, 20), isNot(contains(_basis)), reason: tag);
        expect(shallowFryLinesOf(recipe), isEmpty, reason: tag);
        expect(browningFatLinesOf(recipe), containsAll([0, 20]), reason: tag);
      }
    });

    // closer1 (verify1 D2 / D5): the sub-gates of R5 and R2 and the basis
    // arm no corpus row moves by value. STATED synthesized, each the REAL
    // 0351 with its step 4 (S3) changed as named — real corpus sentences
    // only, but for T's and the basis arm's rewordings (named there):
    // - U `_awayFromPan`: 0351's own S1.3 "Add the crushed tomatoes and broth,
    //   scraping up any browned bits." after S3.3 "Remove the sauce from the
    //   oven …" — the sauce, not the skillet: no pan event, |20 admitted;
    // - W "now-empty": 0017 mushroom-bisque's "Return soup to now-empty pot
    //   and bring to simmer over low heat." after the lift-out — the pan
    //   reused in any vessel state: refused;
    // - Z `_panReused`: 0458 slow-cooker-beef-burgundy's "Simmer, scraping up
    //   any browned bits, for about 1 minute." after the lift-out (no cooking
    //   verb first, no vessel): the fat reused by name, refused;
    // - Y `_cooksInPan`: 0351's own S1.2 "Stir in the garlic and cook until
    //   fragrant, about 30 seconds." after the lift-out: a cooking sentence
    //   while the skillet is current, refused;
    // - T R2's `_heatsTheOil` amount: S3.0's "heat the oil" reworded "heat 2
    //   tablespoons more of the olive oil" (SYNTHESIZED words: no corpus
    //   sentence heats "N more of the <kind> oil" — grep 0 hits — the one form
    //   whose head `_stepAmount`'s four words miss; 0466 daube's "Heat 2
    //   tablespoons of the oil" is the shape): refused;
    // - the basis arm (`discardedBasis()` reads `_shallowFryBasis` before the
    //   kept-in-pan basis): |0 retyped as 0480 steak-tacos' real |11 "2
    //   tablespoons vegetable oil", S3.0's "heat the oil" reworded "heat the
    //   olive oil" (SYNTHESIZED word: `_panOilAt` names ONE oil by a kind word
    //   only it has, its doc's 0228 "Heat vegetable oil"), and 1189
    //   erbazzone's "Pour out all but 1 tablespoon fat from pot." after S3.3
    //   (the pot: no R5 event) — |20 admitted, its basis the shallow plan's,
    //   never "1 tablespoon kept (the steps pour off the rest)".
    test('the R5 / R2 sub-gates and the basis arm — STATED synthesized on the '
        'REAL 0351 (closer1): U the away sentence → |20 11.19 (mutant '
        '`_awayFromPan` off → 10.13); W "now-empty", Z a named reuse, Y a '
        'cooking sentence, T "heat 2 tablespoons more of the olive oil" → '
        '10.13, the browning film (mutants: each term off → 11.19); the basis '
        'arm: a pour-off to a kept part → |20 11.19 with the shallow basis '
        '(mutant: the arm narrowed to the browning basis → "1 tablespoon kept '
        '(the steps pour off the rest)")', () async {
      final real = loadCorpusRecipe(_gravy);
      final s3 = real.steps[3].text;
      const heat = 'heat the oil in a large nonstick skillet';
      const lift =
          'Transfer the meatballs to a paper towel–lined plate to drain briefly. ';
      const skim =
          'Remove the sauce from the oven and skim the fat from the top with a large spoon. ';
      const deglaze =
          'Add the crushed tomatoes and broth, scraping up any browned bits. ';
      const garlic =
          'Stir in the garlic and cook until fragrant, about 30 seconds. ';
      const nowEmpty =
          'Return soup to now-empty pot and bring to simmer over low heat. ';
      const simmer =
          'Simmer, scraping up any browned bits, for about 1 minute. ';
      const pourOut = 'Pour out all but 1 tablespoon fat from pot. ';
      expect(s3, contains(heat));
      expect(s3, contains('$lift$skim'));
      expect(real.steps[1].text, contains(deglaze.trim()));
      expect(real.steps[1].text, contains(garlic.trim()));
      for (final (file, sentence) in const [
        ('0017-mushroom-bisque.yaml', nowEmpty),
        ('0458-slow-cooker-beef-burgundy.yaml', simmer),
        ('1189-erbazzone-swiss-chard-pie.yaml', pourOut),
      ]) {
        expect(
          [
            for (final step in loadCorpusRecipe(file).steps) step.text,
          ].join(' '),
          contains(sentence.trim()),
          reason: file,
        );
      }
      final tacosOil = nutritionLines(loadCorpusRecipe(_tacos))[11];
      expect(tacosOil.raw, '2 tablespoons vegetable oil');
      final retyped = [
        for (final (i, g) in real.ingredients.indexed)
          i == 0 ? g.copyWith(items: [tacosOil, ...g.items.skip(1)]) : g,
      ];
      const admitted = (2710186, 'auto', null, 'discarded', '11.19', '100.71');
      const film = (2710186, 'auto', null, 'discarded', '10.13', '91.17');
      for (final (tag, step4, ingredients, form, shallow) in [
        ('away', s3.replaceFirst(skim, '$skim$deglaze'), null, admitted, true),
        (
          'nowempty',
          s3.replaceFirst(lift, '$lift$nowEmpty'),
          null,
          film,
          false,
        ),
        ('simmer', s3.replaceFirst(lift, '$lift$simmer'), null, film, false),
        ('cooks', s3.replaceFirst(lift, '$lift$garlic'), null, film, false),
        (
          'little',
          s3.replaceFirst(
            heat,
            'heat 2 tablespoons more of the olive oil in a large nonstick skillet',
          ),
          null,
          film,
          false,
        ),
        (
          'kept',
          s3
              .replaceFirst(
                heat,
                'heat the olive oil in a large nonstick skillet',
              )
              .replaceFirst(skim, '$skim$pourOut'),
          retyped,
          admitted,
          true,
        ),
      ]) {
        final recipe = await _compute(
          db,
          fdc,
          real.copyWith(
            id: '${real.id}-v100-$tag',
            slug: '${real.slug}-v100-$tag',
            ingredients: ingredients ?? real.ingredients,
            steps: [
              for (final (i, step) in real.steps.indexed)
                i == 3 ? step.copyWith(text: step4) : step,
            ],
          ),
        );
        expect(formOf(rowIn(recipe.id, 20)), form, reason: tag);
        if (shallow) {
          expect(basisOf(recipe, 20), '$_basis · $_flag', reason: tag);
        } else {
          expect(basisOf(recipe, 20), isNot(contains(_basis)), reason: tag);
        }
        expect(
          shallowFryLinesOf(recipe),
          shallow ? {20} : isEmpty,
          reason: tag,
        );
      }
    });

    // closer2 (verify2 D3): RX-1's sub-gates, which no corpus row moves by
    // value (the browning text set stays 43 lines under each mutant). STATED
    // synthesized, each the REAL 1076 with its step 4 changed (real corpus
    // sentences carried in, one reworded, named):
    // - the mention's OWN sentence (N1): S3.1 "Melt butter in now-empty
    //   saucepan over medium heat." and S3.2 "Add flour and cook, …" read as
    //   0162 slow-roasted-turkey's ONE sentence "In a medium saucepan, heat
    //   the butter over medium-high heat; add the flour and cook, …" (the next,
    //   "Slowly whisk in stock.", adds none): bound, 28.36 g `density`;
    // - "roux" (N2 / N2r): S3.2 read as 0107 gumbo's "Add the onions, bell
    //   pepper, … to the roux and cook, …": bound;
    // - "flour over" (N2 / N2o): S3.2 read as 0223 brisket's "Sprinkle the
    //   flour over the onions and cook, …" with "the flour" REWORDED "2
    //   tablespoons of the flour" (SYNTHESIZED words: every corpus "flour
    //   over" sentence — 0096, 0194, 0223, 0422, 0459, 0974, 0986 — is also a
    //   "sprinkle (the) flour" the add arm reads first; 0466 daube's "Heat 2
    //   tablespoons of the oil" is the shape): bound;
    // - "(?! mixture)" (N2b): S3.2 read as 0435 cheese-souffle's "Stir in
    //   flour mixture and cook for 1 minute." (a batter's flour, no roux): not
    //   bound — the browning row, 20.68 g `discarded` (= v99).
    test('RX-1 sub-gates — STATED synthesized on the REAL 1076 (closer2): the '
        "mention's own sentence (0162's), \"roux\" (0107's) and \"flour over\" "
        "(0223's, reworded) bind → |12 28.36 g `density` (mutants: each arm "
        'off → 20.68 `discarded`); "flour mixture" (0435, cheese-souffle) '
        'binds nothing → '
        '20.68 `discarded` (mutant: the lookahead off → 28.36)', () async {
      final real = loadCorpusRecipe(_broiled);
      final s4 = real.steps[3].text;
      const melt = 'Melt butter in now-empty saucepan over medium heat. ';
      const flour =
          'Add flour and cook, stirring constantly, until mixture is deep golden brown, 5 to 8 minutes.';
      const own =
          'In a medium saucepan, heat the butter over medium-high heat; add the flour and cook, stirring constantly, until the flour is dark golden brown and fragrant, about 5 minutes.';
      const roux =
          'Add the onions, bell pepper, celery, garlic, thyme, 1 teaspoon salt, and ¼ teaspoon cayenne to the roux and cook, stirring frequently, until the vegetables soften, 8 to 10 minutes.';
      const over =
          'Sprinkle the flour over the onions and cook, stirring constantly, until well combined, about 2 minutes.';
      const mixture = 'Stir in flour mixture and cook for 1 minute.';
      expect(s4, contains('$melt$flour Slowly whisk in stock.'));
      for (final (file, sentence) in const [
        ('0162-slow-roasted-turkey-with-gravy.yaml', own),
        ('0107-creole-style-shrimp-and-sausage-gumbo.yaml', roux),
        ('0223-onion-braised-beef-brisket.yaml', over),
        ('0435-cheese-souffle.yaml', mixture),
      ]) {
        expect(
          [
            for (final step in loadCorpusRecipe(file).steps) step.text,
          ].join(' '),
          contains(sentence),
          reason: file,
        );
      }
      const bound = (173430, 'auto', null, 'density', '28.36', '203.35');
      const film = (173430, 'auto', null, 'discarded', '20.68', '148.28');
      for (final (tag, step4, form) in [
        ('own', s4.replaceFirst('$melt$flour', own), bound),
        ('roux', s4.replaceFirst(flour, roux), bound),
        (
          'over',
          s4.replaceFirst(
            flour,
            over.replaceFirst('the flour', '2 tablespoons of the flour'),
          ),
          bound,
        ),
        ('mixture', s4.replaceFirst(flour, mixture), film),
      ]) {
        final recipe = await _compute(
          db,
          fdc,
          real.copyWith(
            id: '${real.id}-v100-rx-$tag',
            slug: '${real.slug}-v100-rx-$tag',
            steps: [
              for (final (i, step) in real.steps.indexed)
                i == 3 ? step.copyWith(text: step4) : step,
            ],
          ),
        );
        expect(nutritionLines(recipe)[12].raw, '2 tablespoons unsalted butter');
        expect(formOf(rowIn(recipe.id, 12)), form, reason: tag);
        expect(
          browningFatLinesOf(recipe).contains(12),
          form == film,
          reason: tag,
        );
      }
    });

    // closer2 (verify2 D4–D7): the R5, R4, R3 and R2 sub-gates and the plan's
    // below-gate refusal, which no corpus row moves by value (the shallow and
    // browning text sets unchanged under each mutant). STATED synthesized,
    // each the REAL 0351 with its step 4 (S3) changed — real corpus
    // sentences carried in, but for the words named SYNTHESIZED:
    // - R5 a wipe (N4): 0070 fajitas' "Wipe out skillet with paper towels."
    //   then 0351's own S1.2 "Stir in the garlic and cook …" after the
    //   lift-out — the wipe discards first: |20 11.19 g;
    // - R5 a plain pour-off (N5): 0142 lemon-sauce chicken's "Pour off and
    //   discard fat in skillet." then the same S1.2: 11.19 g;
    // - R5 a pour-off to a kept part (N6): 0332 amatriciana's "Pour off all
    //   but 1 tablespoon fat from skillet." after the lift-out — the fat
    //   reused: 10.13 g, the browning film (never read as a plain pour-off);
    // - R5's batch run (N7): 0000 turkey-meatballs' "Add meatballs and cook
    //   until well browned all over, …" then S3.2 again after the lift-out —
    //   a second batch, in the run, no reuse: 11.19 g;
    // - R4 "using a slotted spoon, transfer" (N8): S3.2 read as 0165's "With
    //   a slotted spoon, transfer the sausage to a medium bowl." with its
    //   piece word read "meatballs" (SYNTHESIZED word: no corpus meatball is
    //   lifted with a slotted spoon): 11.19 g;
    // - R4 "drain … on paper towels" (N9): S3.2 read "Drain the meatballs on
    //   paper towels." (SYNTHESIZED: 0689 latkes' "Drain on paper towels …",
    //   the one corpus form, with the piece named): 11.19 g;
    // - R4's "<noun> mixture" (N20 / N20m): S3.2's "the meatballs" read "the
    //   meatball mixture" (SYNTHESIZED word: 0216's "Transfer the
    //   onion-mushroom mixture to a plate …" is the shape): no piece, 10.13 g;
    // - R4's `_notAPiece` (N20 / N20n): S3.1 + S3.2 read as 0360's "Add
    //   meatballs to sauce and gently simmer, …" and 0180's "Transfer to a
    //   plate and set aside." — "to" is no piece: 10.13 g;
    // - R3's heat-clause cut (N16): S3.0 read as 0121's "Place breasts, skin
    //   side down, in oil and place skillet over medium heat." — the food
    //   placed before the heat clause is not read: 11.19 g;
    // - R3's fat aside (N10): S3.0 read as 0310 burgers' "Return the skillet
    //   to high heat; add the oil and heat until just smoking.": 11.19 g;
    // - R3's batch words (N11): S3.1 read as 0008 chili's "Add half of the
    //   beef and cook until browned on all sides, …": 11.19 g;
    // - R3's "none added" (N12): S3.1 "Add the meatballs and cook …" deleted
    //   (one real sentence removed): 10.13 g;
    // - R2's print of the head (N21): S3.0 read as 0685 greens' "Heat the oil,
    //   garlic, and ¼ teaspoon red pepper flakes in a large skillet …" — a
    //   small print of ANOTHER food: 11.19 g;
    // - the plan's below-gate `auto` refusal (N18): |20 retyped "½ cup
    //   vegetable oil for brushing the tortillas" (SYNTHESIZED line: 0351's
    //   real amount on 0472 quesadillas' real |3 item, the one corpus fat line
    //   matched `auto` below the gate, 0.39) and S3.0's "heat the oil" read
    //   "heat the vegetable oil" (SYNTHESIZED word: `_lineMentionsOf` gives an
    //   oil mention to ONE kind, as closer1's 'kept' variant): a shallow line
    //   the plan does not weigh — the engine's row, 112.00 g `portion`.
    test("R5 / R4 / R3 / R2 sub-gates and the plan's below-gate refusal — "
        'STATED synthesized on the REAL 0351 (closer2): a wipe, a plain '
        'pour-off, a batch run, a slotted spoon, a drain, a cold placement, the '
        "fat's own add, a batch word, another food's print → |20 11.19 g "
        '(mutants: each term off → 10.13); a pour-off to a kept part, a '
        '"<noun> mixture", a `_notAPiece` word, no add → 10.13 (mutants: each '
        'term off → 11.19); a below-gate `auto` shallow line → 112.00 g '
        '`portion` (mutant: admitted → 11.19)', () async {
      final real = loadCorpusRecipe(_gravy);
      final s3 = real.steps[3].text;
      const heat =
          'When the sauce is 30 minutes from being done, heat the oil in a large nonstick skillet over medium-high heat until shimmering. ';
      const add =
          'Add the meatballs and cook until well browned all over, 5 to 7 minutes. ';
      const lift =
          'Transfer the meatballs to a paper towel–lined plate to drain briefly. ';
      const garlic =
          'Stir in the garlic and cook until fragrant, about 30 seconds. ';
      const wipe = 'Wipe out skillet with paper towels. ';
      const pourOff = 'Pour off and discard fat in skillet. ';
      const allBut = 'Pour off all but 1 tablespoon fat from skillet. ';
      const batch =
          'Add meatballs and cook until well browned all over, 5 to 7 minutes. ';
      const slotted =
          'With a slotted spoon, transfer the sausage to a medium bowl. ';
      const toSauce =
          'Add meatballs to sauce and gently simmer, turning them occasionally, until cooked through, 5 to 10 minutes. ';
      const toPlate = 'Transfer to a plate and set aside. ';
      const cold =
          'Place breasts, skin side down, in oil and place skillet over medium heat. ';
      const fatAside =
          'Return the skillet to high heat; add the oil and heat until just smoking. ';
      const half =
          'Add half of the beef and cook until browned on all sides, about 10 minutes. ';
      const otherPrint =
          'Heat the oil, garlic, and ¼ teaspoon red pepper flakes in a large skillet over medium heat until the garlic starts to sizzle, about 1 minute. ';
      expect(s3, startsWith('$heat$add$lift'));
      expect(real.steps[1].text, contains(garlic.trim()));
      for (final (file, sentence) in const [
        ('0070-skillet-chicken-fajitas.yaml', wipe),
        ('0142-skillet-roasted-chicken-in-lemon-sauce.yaml', pourOff),
        ('0332-pasta-allamatriciana.yaml', allBut),
        ('0000-italian-style-turkey-meatballs.yaml', batch),
        (
          '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml',
          slotted,
        ),
        ('0360-sausage-meatballs-and-spaghetti.yaml', toSauce),
        ('0180-quick-green-bean-casserole.yaml', toPlate),
        (
          '0121-crispy-skinned-chicken-breasts-with-vinegar-pepper-pan-sauce.yaml',
          cold,
        ),
        ('0310-best-old-fashioned-burgers.yaml', fatAside),
        ('0008-our-favorite-chili.yaml', half),
        ('0685-quick-cooked-tough-greens.yaml', otherPrint),
      ]) {
        expect(
          [
            for (final step in loadCorpusRecipe(file).steps) step.text,
          ].join(' '),
          contains(sentence.trim()),
          reason: file,
        );
      }
      final brush = nutritionLines(
        loadCorpusRecipe('0472-quesadillas.yaml'),
      )[3];
      expect(brush.raw, 'Vegetable oil for brushing the tortillas');
      final retyped = [
        for (final (i, g) in real.ingredients.indexed)
          i == 1
              ? g.copyWith(
                  items: [
                    for (final (j, line) in g.items.indexed)
                      j == 10
                          ? line.copyWith(
                              raw:
                                  '½ cup vegetable oil for brushing the tortillas',
                              item: brush.item,
                              prep: brush.prep,
                            )
                          : line,
                  ],
                )
              : g,
      ];
      const admitted = (2710186, 'auto', null, 'discarded', '11.19', '100.71');
      const film = (2710186, 'auto', null, 'discarded', '10.13', '91.17');
      for (final (tag, step4, ingredients, form) in [
        ('wiped', s3.replaceFirst(lift, '$lift$wipe$garlic'), null, admitted),
        (
          'pouredoff',
          s3.replaceFirst(lift, '$lift$pourOff$garlic'),
          null,
          admitted,
        ),
        ('allbut', s3.replaceFirst(lift, '$lift$allBut'), null, film),
        ('batch', s3.replaceFirst(lift, '$lift$batch$lift'), null, admitted),
        (
          'slotted',
          s3.replaceFirst(lift, slotted.replaceFirst('sausage', 'meatballs')),
          null,
          admitted,
        ),
        (
          'drain',
          s3.replaceFirst(lift, 'Drain the meatballs on paper towels. '),
          null,
          admitted,
        ),
        (
          'mixture',
          s3.replaceFirst(
            lift,
            lift.replaceFirst('the meatballs', 'the meatball mixture'),
          ),
          null,
          film,
        ),
        (
          'notapiece',
          s3.replaceFirst('$add$lift', '$toSauce$toPlate'),
          null,
          film,
        ),
        ('cold', s3.replaceFirst(heat, cold), null, admitted),
        ('fataside', s3.replaceFirst(heat, fatAside), null, admitted),
        ('half', s3.replaceFirst(add, half), null, admitted),
        ('noadd', s3.replaceFirst(add, ''), null, film),
        ('otherprint', s3.replaceFirst(heat, otherPrint), null, admitted),
        (
          'belowgate',
          s3.replaceFirst('heat the oil in', 'heat the vegetable oil in'),
          retyped,
          (2710180, 'auto', null, 'portion', '112.00', '1008.00'),
        ),
      ]) {
        final recipe = await _compute(
          db,
          fdc,
          real.copyWith(
            id: '${real.id}-v100-c2-$tag',
            slug: '${real.slug}-v100-c2-$tag',
            ingredients: ingredients ?? real.ingredients,
            steps: [
              for (final (i, step) in real.steps.indexed)
                i == 3 ? step.copyWith(text: step4) : step,
            ],
          ),
        );
        final row = rowIn(recipe.id, 20);
        expect(formOf(row), form, reason: tag);
        if (form == admitted) {
          expect(basisOf(recipe, 20), '$_basis · $_flag', reason: tag);
        } else {
          expect(basisOf(recipe, 20), isNot(contains(_basis)), reason: tag);
        }
        // The text sets, after the values: every variant but the film ones
        // (and the below-gate line, which the plan alone refuses) is shallow.
        expect(
          shallowFryLinesOf(recipe),
          form == film ? isEmpty : {20},
          reason: tag,
        );
        if (tag == 'belowgate') {
          expect(belowConfidenceGate(row.confidence), isTrue, reason: tag);
        }
      }
    });

    // closer2 (verify2 D1 / D2): P's two edges.
    // - no counted piece (N19, the plan's `uptake <= 0` return): the REAL
    //   0351 with EVERY piece row of |20's group — |10–|14, |16–|19 (|15 has
    //   no grams) — skipped through the PUT (a person path, STATED: the
    //   P15 / P16 form, every row): no entry, the engine's row 112.00 g
    //   `portion`, and a full compute after writes nothing;
    // - a fat line inside P's range (N15, `_shallowPieceAt`'s `_panFatHeads`
    //   exclusion, design C2-1): the REAL 0351 with 1076 broiled's REAL |12
    //   "2 tablespoons unsalted butter" at the start of group 1 (STATED
    //   synthesized: a real line carried in; no step names it — its row is
    //   the engine's 28.36 g `density`): P stays the ten real rows, 736.23 g
    //   → |21 11.19 g (the butter in P: 764.59 g → 11.62).
    test("P's edges (closer2): every piece skipped through the PUT → |20 the "
        "engine's 112.00 g `portion` (mutant: the no-uptake return off → 0.00 "
        "`discarded`); a fat line at the group's start is no piece → |21 "
        '11.19 g (mutant: the fat-head exclusion off → 11.62)', () async {
      final real = loadCorpusRecipe(_gravy);
      var recipe = await _compute(
        db,
        fdc,
        real.copyWith(
          id: '${real.id}-v100-c2-noparts',
          slug: '${real.slug}-v100-c2-noparts',
        ),
      );
      expect(rowIn(recipe.id, 20).grams?.toStringAsFixed(2), '11.19');
      expect(rowIn(recipe.id, 15).grams, isNull);
      for (final p in [10, 11, 12, 13, 14, 16, 17, 18, 19]) {
        final fresh = nutritionRecipeOf(db, recipe.id)!.recipe;
        await applyMatchOverride(db, fdc, fresh, p, {
          'raw': nutritionLines(fresh)[p].raw,
          'skipped': true,
        });
      }
      const engine = (2710186, 'auto', null, 'portion', '112.00', '1008.00');
      expect(formOf(rowIn(recipe.id, 20)), engine);
      List<Object?> rowsOf() => [
        for (final m in db.ingredientMatchesFor(recipe.id))
          (m.position, m.fdcId, m.grams, m.gramSource, m.status, m.hold),
      ];
      final rows = rowsOf();
      final totals = db.nutritionFor(recipe.id)!.totalsJson;
      recipe = nutritionRecipeOf(db, recipe.id)!.recipe;
      expect(await matchAndCompute(db, fdc, recipe), isNull);
      expect(rowsOf(), rows);
      expect(db.nutritionFor(recipe.id)!.totalsJson, totals);
      expect(formOf(rowIn(recipe.id, 20)), engine);
      expect(shallowFryLinesOf(recipe), {20});

      final butter = nutritionLines(loadCorpusRecipe(_broiled))[12];
      expect(butter.raw, '2 tablespoons unsalted butter');
      recipe = await _compute(
        db,
        fdc,
        real.copyWith(
          id: '${real.id}-v100-c2-fathead',
          slug: '${real.slug}-v100-c2-fathead',
          ingredients: [
            for (final (i, g) in real.ingredients.indexed)
              i == 1 ? g.copyWith(items: [butter, ...g.items]) : g,
          ],
        ),
      );
      expect(nutritionLines(recipe)[21].raw, '½ cup olive oil');
      expect(formOf(rowIn(recipe.id, 21)), (
        2710186,
        'auto',
        null,
        'discarded',
        '11.19',
        '100.71',
      ));
      expect(formOf(rowIn(recipe.id, 10)), (
        173430,
        'auto',
        null,
        'density',
        '28.36',
        '203.35',
      ));
      expect(shallowFryLinesOf(recipe), {21});
    });

    // closer3 (verify3 D1, D2, D4–D7): R4's window edge, R5's pan fold,
    // lead-in and "repeat with" join, the plan's unheld term and the flag's
    // butter clause, which no corpus row moves by value (verify3's census:
    // the shallow and browning text sets unchanged under each mutant).
    // STATED synthesized, each the REAL 0351 — real corpus sentences carried
    // in, but for the words and the line named SYNTHESIZED:
    // - R4's window edge (O1, `stepOf(lift.at) > h.$1 + 1`): S3 split after
    //   S3.1 — S3.0–S3.1 | S3.2–S3.5, real sentences only: the lift-out in
    //   the NEXT step after the heat is in the window: |20 11.19 g;
    // - R5's "pan" → "skillet" fold (O3, `_fryVesselOf`): S3.0's "large
    //   nonstick skillet" read "large nonstick pan" (SYNTHESIZED word: the
    //   fold's own form, `_PanFacts`' "pan" as "skillet") and 0310 burgers'
    //   "Return the skillet to high heat; add the oil and heat until just
    //   smoking." after the lift-out — the fry's pan current, reused: 10.13;
    // - R5's lead-in (O4, `_cooksInPan`'s "<word>, "): 0013 tomato soup's
    //   "Off heat, stir in brandy." after the lift-out — a cooking sentence
    //   while the skillet is current: 10.13;
    // - R5's "repeat with" join (O7, `runEnd`): 0421 saltimbocca's "Add the
    //   remaining 2 tablespoons oil to the skillet and repeat with the
    //   remaining 4 cutlets." after the lift-out — a second batch, in the
    //   run, no reuse: 11.19 g;
    // - the plan's unheld term (O5, `_shallowFryPlan`'s `r.hold != null`):
    //   |20 retyped "½ cup olive oil plus 2 tablespoons unsalted butter"
    //   (SYNTHESIZED line: 0351's real |20 with 1076's real |12 joined in the
    //   corpus's "<a> plus <b>" form — 14 held `second_food` rows on the
    //   replay, e.g. smashed-burgers|2 "… dill pickles plus ½ teaspoon
    //   brine"; no held corpus fat line is a shallow line): still a shallow
    //   line, the plan leaves the held row as it is — 112.00 g `portion`, the
    //   person's `second_food` hold kept;
    // - the flag's butter clause (O6): |20 = 0095 dumplings' real |3 "4
    //   tablespoons (½ stick) unsalted butter" and S3.0's "heat the oil" read
    //   "heat the butter" (SYNTHESIZED word): the same U ÷ butter's 81.11 %
    //   fat = 13.79 g, the flag ending "; a butter line weighed by its own
    //   fat)".
    test("R4's window edge, R5's pan fold / lead-in / repeat join, the plan's "
        'unheld term and the butter flag — STATED synthesized on the REAL '
        '0351 (closer3): the lift-out a step after the heat, a "repeat with" '
        'batch → |20 11.19 g (mutants: the window narrowed / the join off → '
        '10.13); the "pan" heated then "the skillet" reused, "Off heat, stir '
        'in …" → 10.13 (mutants: the fold / the lead-in off → 11.19); a held '
        "line → the engine's 112.00 g `portion`, its hold kept (mutant: the "
        'unheld term off → 11.19 `discarded`); a butter line → 13.79 g, the '
        "flag's butter clause (mutant: the clause off)", () async {
      final real = loadCorpusRecipe(_gravy);
      final s3 = real.steps[3].text;
      const heat =
          'When the sauce is 30 minutes from being done, heat the oil in a large nonstick skillet over medium-high heat until shimmering. ';
      const add =
          'Add the meatballs and cook until well browned all over, 5 to 7 minutes. ';
      const lift =
          'Transfer the meatballs to a paper towel–lined plate to drain briefly. ';
      const fatAside =
          'Return the skillet to high heat; add the oil and heat until just smoking. ';
      const offHeat = 'Off heat, stir in brandy. ';
      const repeat =
          'Add the remaining 2 tablespoons oil to the skillet and repeat with the remaining 4 cutlets. ';
      expect(s3, startsWith('$heat$add$lift'));
      for (final (file, sentence) in const [
        ('0310-best-old-fashioned-burgers.yaml', fatAside),
        ('0013-ultimate-cream-of-tomato-soup.yaml', offHeat),
        ('0421-chicken-saltimbocca.yaml', repeat),
      ]) {
        expect(
          [
            for (final step in loadCorpusRecipe(file).steps) step.text,
          ].join(' '),
          contains(sentence.trim()),
          reason: file,
        );
      }
      final butter = nutritionLines(loadCorpusRecipe(_dumplings))[3];
      expect(butter.raw, '4 tablespoons (½ stick) unsalted butter');
      expect(
        nutritionLines(loadCorpusRecipe(_broiled))[12].raw,
        '2 tablespoons unsalted butter',
      );
      expect(nutritionLines(real)[20].raw, '½ cup olive oil');
      List<IngredientGroup> at20(IngredientLine Function(IngredientLine) f) => [
        for (final (i, g) in real.ingredients.indexed)
          i == 1
              ? g.copyWith(
                  items: [
                    for (final (j, line) in g.items.indexed)
                      j == 10 ? f(line) : line,
                  ],
                )
              : g,
      ];
      List<RecipeStep> renumbered(List<String> texts) => [
        for (final (i, t) in texts.indexed) RecipeStep(number: i + 1, text: t),
      ];
      final texts = [for (final step in real.steps) step.text];
      List<RecipeStep> withS3(String step4) =>
          renumbered([...texts.take(3), step4, ...texts.skip(4)]);
      const admitted = (2710186, 'auto', null, 'discarded', '11.19', '100.71');
      const film = (2710186, 'auto', null, 'discarded', '10.13', '91.17');
      const held = (
        2710186,
        'auto',
        'second_food',
        'portion',
        '112.00',
        '1008.00',
      );
      const melted = (173430, 'auto', null, 'discarded', '13.79', '98.87');
      final butterFlag =
          '${_flag.substring(0, _flag.length - 1)}; a butter line weighed by its own fat)';
      for (final (tag, steps, ingredients, form, basis) in [
        (
          'window1',
          renumbered([
            ...texts.take(3),
            '$heat$add'.trim(),
            s3.substring(heat.length + add.length),
            ...texts.skip(4),
          ]),
          null,
          admitted,
          '$_basis · $_flag',
        ),
        (
          'vesselpan',
          withS3(
            s3
                .replaceFirst('large nonstick skillet', 'large nonstick pan')
                .replaceFirst(lift, '$lift$fatAside'),
          ),
          null,
          film,
          null,
        ),
        (
          'leadin',
          withS3(s3.replaceFirst(lift, '$lift$offHeat')),
          null,
          film,
          null,
        ),
        (
          'repeat',
          withS3(s3.replaceFirst(lift, '$lift$repeat')),
          null,
          admitted,
          '$_basis · $_flag',
        ),
        (
          'held',
          real.steps,
          at20(
            (line) => line.copyWith(
              raw: '½ cup olive oil plus 2 tablespoons unsalted butter',
            ),
          ),
          held,
          null,
        ),
        (
          'butter',
          withS3(s3.replaceFirst('heat the oil in', 'heat the butter in')),
          at20((_) => butter),
          melted,
          '$_basis · $butterFlag',
        ),
      ]) {
        final recipe = await _compute(
          db,
          fdc,
          real.copyWith(
            id: '${real.id}-v100-c3-$tag',
            slug: '${real.slug}-v100-c3-$tag',
            ingredients: ingredients ?? real.ingredients,
            steps: steps,
          ),
        );
        expect(formOf(rowIn(recipe.id, 20)), form, reason: tag);
        if (basis != null) {
          expect(basisOf(recipe, 20), basis, reason: tag);
        } else {
          expect(basisOf(recipe, 20), isNot(contains(_basis)), reason: tag);
        }
        // The text sets, after the values: the held line is shallow — the
        // plan alone refuses it.
        expect(
          shallowFryLinesOf(recipe),
          form == film ? isEmpty : {20},
          reason: tag,
        );
      }
    });

    // closer3 (verify3 D3): RX-1's amount run (O2, `_rouxFlour`'s
    // "(?:<amount> <unit> )?"), which no corpus row moves by value. STATED
    // synthesized: the REAL 1076 with S3.2 "Add flour and cook, …" replaced
    // by 0476 beef empanadas' real "Add the remaining 2 cups flour and pulse
    // …" (a real sentence carried in) — flour added by amount binds the
    // melted butter: |12 the engine's 28.36 g `density`, no browning line.
    test('RX-1 amount run — STATED synthesized on the REAL 1076 (closer3): '
        '0476\'s "Add the remaining 2 cups flour …" after the melt binds → '
        '|12 28.36 g `density` (mutant: the amount run off → 20.68 '
        '`discarded`)', () async {
      final real = loadCorpusRecipe(_broiled);
      final s4 = real.steps[3].text;
      const flour =
          'Add flour and cook, stirring constantly, until mixture is deep golden brown, 5 to 8 minutes.';
      const amount =
          'Add the remaining 2 cups flour and pulse until the mixture is evenly distributed around the bowl, 4 to 6 quick pulses.';
      expect(
        s4,
        contains('Melt butter in now-empty saucepan over medium heat. $flour'),
      );
      expect(
        [
          for (final step in loadCorpusRecipe('0476-beef-empanadas.yaml').steps)
            step.text,
        ].join(' '),
        contains(amount),
      );
      final recipe = await _compute(
        db,
        fdc,
        real.copyWith(
          id: '${real.id}-v100-c3-amount',
          slug: '${real.slug}-v100-c3-amount',
          steps: [
            for (final (i, step) in real.steps.indexed)
              i == 3
                  ? step.copyWith(text: s4.replaceFirst(flour, amount))
                  : step,
          ],
        ),
      );
      expect(nutritionLines(recipe)[12].raw, '2 tablespoons unsalted butter');
      expect(
        formOf(rowIn(recipe.id, 12)),
        (173430, 'auto', null, 'density', '28.36', '203.35'),
      );
      expect(browningFatLinesOf(recipe).contains(12), isFalse);
    });

    // closer4 (verify4 D2–D7 and the tail it named, ruling4: ONE table),
    // extended by closer5 (verify5 D1–D5, ruling5): each row the REAL 0351
    // (|20, its own lines) or the REAL 1076 (|12) with one sentence edit (a
    // few with two, or a STATED recipe: A21_*, A23, PL_*), the value the tip
    // computes; its mutant gives the other. closer4's 116 rows came from a
    // HAND-LISTED screen (fix100/closer4.md: 111 one-word mutants of 13
    // families on the round-3 file — it missed whole families); closer5's
    // 108 from verify5's 44 measured survivors (41 rows) and a MECHANICAL
    // screen (fix100/c5/screen.tsv, enumerated by script): every
    // alternation branch, optional item (present and absent), star run,
    // bounded run (n → n − 1), character-class member and lookahead of the
    // new regexes — `_rouxFlour`, `_liftVerb`, `_liftObject`, `_liftTo`,
    // `_drainsOnTowels`, `_addsFood`, `_fryFatObject`, `_pieceWords`,
    // `_batchVerb`, `_vesselWord`, `_anotherVessel`, `_awayFromPan`,
    // `_panReused`, `_cooksInPan`, R5's `_poursOffFat` (`_plainPourOff`)
    // and `_piecesIn`'s cut set — each word of `_notAPiece`, and 38 code
    // terms (`_bindsRoux`' finds and window, the "now empty" forms,
    // `_liftsPiecesOut`'s finds and object terms, `_heatsLittle`'s terms,
    // the plan's FIRST line, whole-≤0 term, splits, P's bounds and fat-head
    // exclusion, `_groupOf`'s bound, and six head-gate terms): 344 mutants —
    // 217 killed by a pin of the round-5 file (SI_medium by P11′'s text set,
    // SI_panfat only by the TRUE shape's exact counts: the two head-gate
    // terms the header carries STATED EQUIVALENT by value), 55 by verify5's
    // rows, 72 by closer5's, 0 equivalent; on the final file every one of
    // the 344 and verify5's 44 is killed (fix100/closer5.md). Each
    // carried-in sentence is
    // asserted real in its recipe below; a SYNTH row states the recorded
    // exception at the row (no corpus sentence reaches the alternative, or
    // the piece must be one 0351's S3.1 adds). 11.19 = the shallow plan's
    // (admitted), 10.13 = the browning film; 1076|12: 28.36 `density` (the
    // roux guard) vs 20.68 `discarded`.
    test('the gate alternatives, one table (closer4): each row the REAL 0351 '
        "|20 or 1076 |12 with one sentence edit, its value the tip's — 11.19 "
        'admitted / 10.13 film, 28.36 `density` / 20.68 `discarded` (each '
        "row's one-word mutant gives the other)", () async {
      final gravy = loadCorpusRecipe(_gravy);
      final broiled = loadCorpusRecipe(_broiled);
      final t = [for (final step in gravy.steps) step.text];
      final bt = [for (final step in broiled.steps) step.text];
      final s3 = t[3];
      const heat =
          'When the sauce is 30 minutes from being done, heat the oil in a large nonstick skillet over medium-high heat until shimmering. ';
      const add =
          'Add the meatballs and cook until well browned all over, 5 to 7 minutes. ';
      const lift =
          'Transfer the meatballs to a paper towel–lined plate to drain briefly. ';
      const roux =
          'Add flour and cook, stirring constantly, until mixture is deep golden brown, 5 to 8 minutes.';
      expect(s3, startsWith('$heat$add$lift'));
      expect(
        bt[3],
        contains('Melt butter in now-empty saucepan over medium heat. $roux'),
      );
      expect(nutritionLines(gravy)[20].raw, '½ cup olive oil');
      expect(nutritionLines(broiled)[12].raw, '2 tablespoons unsalted butter');
      for (final (file, sentence) in const [
        (
          '0708-best-summer-tomato-gratin.yaml',
          'Heat ¼ cup oil in 12-inch ovensafe skillet over medium-low heat until shimmering.',
        ),
        (
          '0068-cast-iron-baked-ziti-with-charred-tomatoes.yaml',
          'Heat 12-inch cast-iron skillet over medium heat for 5 minutes.',
        ),
        (
          '0003-old-fashioned-slow-cooker-chicken-noodle-soup.yaml',
          'Bring 4 quarts water to a boil in a large pot.',
        ),
        (
          '0303-turkey-tetrazzini.yaml',
          'Whisk in the flour and cook, whisking constantly, until the flour turns golden, 1 to 2 minutes.',
        ),
        (
          '0805-fougasse.yaml',
          'Add all-purpose flour, salt, and yeast to mixer bowl.',
        ),
        (
          '0432-classic-french-onion-soup.yaml',
          'Repeat the process of deglazing 2 to 3 more times, until the onions are very dark brown.',
        ),
        (
          '0357-pork-fennel-and-lemon-ragu-with-pappardelle.yaml',
          'Cover pot so fond will steam and soften.',
        ),
        (
          '0000-italian-style-turkey-meatballs.yaml',
          'Transfer meatballs to paper towel–lined plate, leaving fat in skillet.',
        ),
        (
          '0500-mexican-rice.yaml',
          'Drop 3 or 4 grains of rice into the oil; if the grains sizzle, the oil is ready.',
        ),
        (
          '0121-crispy-skinned-chicken-breasts-with-vinegar-pepper-pan-sauce.yaml',
          'Transfer breasts to individual plates and let rest while preparing pan sauce.',
        ),
        (
          '0017-mushroom-bisque.yaml',
          'Return soup to now-empty pot and bring to simmer over low heat.',
        ),
        (
          '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml',
          'Add 2 tablespoons salt and the pasta to the boiling water and cook, stirring often, until al dente.',
        ),
        (
          '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml',
          'Using tongs, transfer the meatballs, ribs, and sausage to a serving platter and cut the sausages in half.',
        ),
        (
          '1135-gnocchi-a-la-parisienne-with-arugula-tomatoes-and-olives.yaml',
          'When all eggs have been added, scrape down sides of bowl with rubber spatula.',
        ),
        (
          '0138-glazed-roast-chicken.yaml',
          'Carve the chicken, adding any accumulated juices to the sauce.',
        ),
        ('0542-mu-shu-pork.yaml', 'Unwrap and place on plate.'),
        (
          '0369-hand-rolled-meat-ravioli.yaml',
          'Repeat placing 1-tablespoon mounds of filling, spaced 1½ inches apart, 1 inch from bottom edge of dough.',
        ),
        (
          '0416-lighter-chicken-parmesan.yaml',
          'Lay the chicken on the wire rack.',
        ),
        ('1123-briam.yaml', 'Arrange zucchini in single layer.'),
        ('0908-paris-brest.yaml', 'Put all remaining dough into pastry bag.'),
        (
          '0744-easy-pancakes.yaml',
          'Drop 1 tablespoon batter in center of skillet.',
        ),
        (
          '0856-angel-food-cake.yaml',
          'Wipe any drops of batter off the sides of the pan and lightly tap the pan against the countertop two or three times to settle the batter.',
        ),
        (
          '0570-falafel.yaml',
          'Microwave, whisking every 10 seconds, until mixture thickens to stiff, smooth, pudding-like consistency that forms mound when dropped from end of whisk into bowl, 40 to 80 seconds.',
        ),
        ('1123-briam.yaml', 'Sprinkle parsley over top and serve.'),
        ('0866-carrot-cake.yaml', 'Stir in the carrots.'),
        (
          '0750-easy-buttermilk-waffles.yaml',
          'Make a well in the center of the dry ingredients and pour in the wet ingredients.',
        ),
        (
          '0238-french-style-pot-roasted-pork-loin.yaml',
          'Melt 1 tablespoon of the butter in an 8-inch skillet over medium-low heat.',
        ),
        (
          '0303-turkey-tetrazzini.yaml',
          'Melt the remaining 6 tablespoons butter in the clean skillet over medium heat.',
        ),
        (
          '0028-hearty-minestrone.yaml',
          'Reduce the heat and vigorously simmer, stirring occasionally, until the beans are fully tender and the liquid begins to thicken, 45 to 60 minutes.',
        ),
        (
          '0071-skillet-chicken-pot-pie-with-biscuit-topping.yaml',
          'Stir the peas and carrots into the sauce and simmer until heated through, about 2 minutes.',
        ),
        (
          '0241-garlic-studded-roast-pork-loin.yaml',
          'Remove the meat from the oven; immediately reduce the oven temperature to 325 degrees.',
        ),
        (
          '0008-our-favorite-chili.yaml',
          'Cook until the meat and beans are fully tender, 1½ to 2 hours.',
        ),
        ('0542-mu-shu-pork.yaml', 'Add pork mixture.'),
        (
          '0266-butter-basted-fish-fillets-with-garlic-and-thyme.yaml',
          'Cook for 1 minute.',
        ),
        (
          '0268-oven-steamed-fish-with-scallions-and-ginger.yaml',
          'Stir until ginger is beginning to brown and crisp.',
        ),
        (
          '0204-cider-glazed-pork-chops.yaml',
          'Return the chops to the skillet and turn to coat both sides with the glaze.',
        ),
        (
          '0558-vietnamese-style-caramel-chicken-with-broccoli.yaml',
          'Reduce heat to medium-low, cover, and simmer until chicken is fork-tender and registers 205 degrees, 30 to 40 minutes, flipping chicken halfway through simmering.',
        ),
        (
          '0590-grilled-mojo-marinated-skirt-steak.yaml',
          'Place steaks in dish.',
        ),
        (
          '0804-piadine-italian-flatbreads.yaml',
          'Heat 12-inch cast-iron skillet over medium heat until drop of water dripped onto surface sizzles immediately, about 3 minutes.',
        ),
        (
          '0002-classic-chicken-noodle-soup.yaml',
          'Add the onion and cook, stirring frequently, until the onion is translucent, 3 to 5 minutes.',
        ),
        (
          '0002-classic-chicken-noodle-soup.yaml',
          'Reduce the heat to medium-low and simmer until the flavors have blended, about 20 minutes.',
        ),
        (
          '0005-best-beef-stew.yaml',
          'Increase the heat to high and allow the wine to simmer until thickened and slightly reduced, about 2 minutes.',
        ),
        (
          '0010-vietnamese-beef-pho.yaml',
          'Pour broth through colander set in large bowl.',
        ),
        (
          '0026-red-lentil-soup-with-warm-spices.yaml',
          'Whisk soup vigorously until it is coarsely pureed, about 30 seconds.',
        ),
        (
          '0026-red-lentil-soup-with-warm-spices.yaml',
          'Melt remaining 2 tablespoons butter in small skillet over medium-low heat.',
        ),
        ('0020-sweet-potato-soup.yaml', 'Bring to simmer over high heat.'),
        (
          '0010-vietnamese-beef-pho.yaml',
          'Place noodles in large container and cover with hot tap water.',
        ),
        (
          '0002-classic-chicken-noodle-soup.yaml',
          'Heat the oil in a large Dutch oven over medium-high heat until shimmering.',
        ),
        (
          '0353-simple-italian-style-meat-sauce.yaml',
          'Heat the oil in a large saucepan over medium-high heat until just smoking.',
        ),
        (
          '0354-fettuccine-with-slow-simmered-bolognese-sauce.yaml',
          'Add the meat and ½ teaspoon salt; crumble the meat into tiny pieces with a wooden spoon.',
        ),
        (
          '0576-tender-juicy-grilled-burgers.yaml',
          'Transfer meat to baking sheet.',
        ),
        (
          '0235-maple-glazed-pork-tenderloin.yaml',
          'Transfer the meat to a carving board and slice into ¼-inch-thick pieces.',
        ),
        (
          '0798-almost-no-knead-bread.yaml',
          'Using rubber spatula, fold mixture, scraping up dry flour from bottom of bowl, until shaggy ball forms.',
        ),
        (
          '0040-wilted-spinach-salad-with-warm-bacon-dressing.yaml',
          'Working quickly, scrape the bottom of the skillet with a wooden spoon to loosen the browned bits.',
        ),
        ('0094-shepherds-pie.yaml', 'Stir in flour and cook for 1 minute.'),
        (
          '0142-skillet-roasted-chicken-in-lemon-sauce.yaml',
          'Sprinkle flour evenly over shallot-garlic mixture and cook, stirring constantly, until flour is lightly browned, about 1 minute.',
        ),
        (
          '0451-coq-au-vin.yaml',
          'Transfer the chicken to a plate, leaving the fat in the pot.',
        ),
        (
          '1086-pasta-with-burst-cherry-tomato-sauce-and-fried-caper-crumbs.yaml',
          'Leave oil in skillet and return skillet to medium heat.',
        ),
        (
          '0422-chicken-canzanese.yaml',
          'Sprinkle the flour over the fat and cook, stirring constantly, for 1 minute.',
        ),
        (
          '0316-classic-french-fries.yaml',
          'Using the paper towels as a funnel, pour the potatoes into the hot oil.',
        ),
        (
          '0143-best-roast-chicken-with-root-vegetables.yaml',
          'Reserve 3 tablespoons fat, discarding remaining fat.',
        ),
        (
          '0163-turkey-and-gravy-for-a-crowd.yaml',
          'Reserve ½ cup plus 1 tablespoon fat (if there is not enough fat, add extra melted butter to make up difference) and 8 cups liquid; discard remaining liquid.',
        ),
        (
          '0071-skillet-chicken-pot-pie-with-biscuit-topping.yaml',
          'Add the remaining 2 tablespoons butter to the skillet and return to medium heat until melted.',
        ),
        (
          '0689-potato-roesti.yaml',
          'Add remaining 2 tablespoons butter to skillet and swirl to coat pan.',
        ),
        (
          '1124-blackened-chicken.yaml',
          'Add 1 tablespoon butter to skillet, then tilt skillet or spread butter with flexible spatula until it coats skillet evenly.',
        ),
        (
          '1122-roast-chicken-with-quinoa-swiss-chard-and-lime.yaml',
          'Add 2 teaspoons fat to now-empty skillet.',
        ),
        (
          '0277-pan-seared-scallops.yaml',
          'Add 1 tablespoon of the butter to the skillet.',
        ),
        (
          '0913-foolproof-new-york-cheesecake.yaml',
          'Add 6 tablespoons melted butter and pulse until crumbs are evenly moistened, about 10 pulses.',
        ),
        (
          '0958-skillet-apple-pie.yaml',
          'Add the shortening and pulse until the mixture has the texture of coarse sand, about 10 pulses.',
        ),
        (
          '1131-pasta-cacio-e-uova-pasta-with-cheese-and-eggs.yaml',
          'Immediately add lard, egg mixture, and 1 tablespoon reserved cooking water to pasta and stir until cheese is fully melted.',
        ),
        (
          '0206-crunchy-baked-pork-chops.yaml',
          'In a second pie plate, whisk the egg whites and mustard together; add the remaining 6 tablespoons flour and whisk until almost smooth, with pea-sized lumps remaining.',
        ),
        (
          '0131-spice-rubbed-picnic-chicken.yaml',
          'If desired, secure the skin of each breast piece with two or three toothpicks placed near the edges of the skin.',
        ),
        (
          '0510-goi-cuo-n-vietnamese-summer-rolls.yaml',
          '(Leftovers can be wrapped tightly and refrigerated for up to 24 hours, but wrappers will become chewier and may break in places.)',
        ),
        (
          '0632-jerk-chicken.yaml',
          'When top coals are partially covered with ash, pour evenly over unlit briquettes, keeping coals arranged over half of grill.',
        ),
        (
          '1168-milk-chocolate-cremeux-tart.yaml',
          '(Dough scraps can be sprinkled with sugar and baked as cook’s treat.)',
        ),
        (
          '0136-crisp-skinned-roast-chicken.yaml',
          'Place the foil loosely in a large roasting pan.',
        ),
        (
          '0005-avgolemono-greek-chicken-and-rice-soup-with-egg-and-lemon.yaml',
          'Turn off heat, add chicken, cover, and let sit for 15 minutes.',
        ),
        (
          '0673-modern-cauliflower-gratin.yaml',
          'Re-cover pot, reduce heat to low, and continue to cook stem mixture until very soft, about 10 minutes longer.',
        ),
        (
          '0506-chinese-pork-dumplings.yaml',
          'To pan-fry, increase water to ⅔ cup and covered cooking time to 8 minutes.',
        ),
        (
          '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
          'Transfer cutlets to towel-lined rack and season with salt to taste.',
        ),
        (
          '0043-pan-seared-scallops-with-wilted-spinach-watercress-and-orange-salad.yaml',
          'Transfer all the scallops to a clean, large plate; set aside.',
        ),
        (
          '0281-spanish-style-garlic-shrimp.yaml',
          'Using a slotted spoon, remove the smashed garlic from the skillet and discard.',
        ),
        (
          '1070-irish-stew-with-carrots-and-turnips.yaml',
          'If serving immediately, stir carrots and turnips into liquid, wait 5 minutes, and spoon off any fat that rises to top.',
        ),
        (
          '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml',
          'Stir in the garlic and cook until fragrant, about 30 seconds.',
        ),
        (
          '0951-cherry-clafouti.yaml',
          'Whisk in remaining ½ cup flour until smooth.',
        ),
        (
          '0806-pita-bread.yaml',
          'Using rolling pin, gently roll into 7-inch circle, adding flour as necessary to prevent sticking.',
        ),
        // closer6 (verify6 D3): the discard-in-another-vessel row's two
        // sentences (0142's with skillet → pot, one word changed).
        (
          '0142-skillet-roasted-chicken-in-lemon-sauce.yaml',
          'Pour off and discard fat in skillet.',
        ),
        (
          '0310-best-old-fashioned-burgers.yaml',
          'Return the skillet to high heat; add the oil and heat until just smoking.',
        ),
      ]) {
        expect(
          [
            for (final step in loadCorpusRecipe(file).steps) step.text,
          ].join(' '),
          contains(sentence),
          reason: file,
        );
      }
      List<String> g3(String x) => [...t.take(3), x, ...t.skip(4)];
      List<String> heatAs(String x) => g3(s3.replaceFirst(heat, '$x '));
      List<String> addAs(String x) => g3(s3.replaceFirst(add, '$x '));
      List<String> liftAs(String x) => g3(s3.replaceFirst(lift, '$x '));
      List<String> before(String x) => g3(s3.replaceFirst(lift, '$x $lift'));
      List<String> after(String x) => g3(s3.replaceFirst(lift, '$lift$x '));
      // A batch sentence, then 0351's real S3.2 repeated (a later lift-out).
      List<String> batch(String x) =>
          g3(s3.replaceFirst(lift, '$lift$x $lift'));
      List<String> addLift(String a, String l) =>
          g3(s3.replaceFirst(add, '$a ').replaceFirst(lift, '$l '));
      List<String> b3(String x) => [
        ...bt.take(3),
        bt[3].replaceFirst(roux, x),
        ...bt.skip(4),
      ];
      const admitted = (2710186, 'auto', null, 'discarded', '11.19', '100.71');
      const film = (2710186, 'auto', null, 'discarded', '10.13', '91.17');
      const density = (173430, 'auto', null, 'density', '28.36', '203.35');
      // closer5 (verify5 D5, the plan terms): A21's STATED synthesized
      // two-fry recipe (no corpus recipe holds two shallow lines) — 0351's
      // real lines |17 "1 pound meatloaf mix", |20, |18 "2 ounces thinly
      // sliced prosciutto, minced", |20 again in one group, S3 twice
      // (the cap shapes' `capped` form); A23's |20 retyped "1 bottle olive
      // oil, for pan-frying" (STATED synthesized: a bottle no line weighs).
      expect(nutritionLines(gravy)[17].raw, '1 pound meatloaf mix');
      expect(
        nutritionLines(gravy)[18].raw,
        '2 ounces thinly sliced prosciutto, minced',
      );
      final twoFry = capped(
        gravy,
        [
          '1 pound meatloaf mix',
          '½ cup olive oil',
          '2 ounces thinly sliced prosciutto, minced',
          '½ cup olive oil',
        ],
        [s3, s3],
      );
      const bottle = '1 bottle olive oil, for pan-frying';
      final parsed = parseIngredientLine(bottle);
      final bottled = gravy.copyWith(
        ingredients: [
          for (final (i, g) in gravy.ingredients.indexed)
            i == 1
                ? g.copyWith(
                    items: [
                      for (final (j, line) in g.items.indexed)
                        j == 10
                            ? line.copyWith(
                                raw: bottle,
                                amounts: parsed.amounts,
                                item: parsed.item,
                                prep: parsed.prep,
                              )
                            : line,
                    ],
                  )
                : g,
        ],
      );
      // closer5 (the screen's plan terms): PL_groupOf's 0351 with group 1
      // split before |20 (STATED synthesized: no corpus shallow line opens
      // its group) and PL_splitU's two-fry recipe with an amount-less line
      // (STATED synthesized: 0357's real |10 "Vegetable oil, for
      // pan-frying" for each of A21's two oil lines — both amount-less).
      final split20 = gravy.copyWith(
        ingredients: [
          for (final (i, g) in gravy.ingredients.indexed)
            if (i == 1) ...[
              g.copyWith(items: g.items.take(10).toList()),
              g.copyWith(items: g.items.skip(10).toList()),
            ] else
              g,
        ],
      );
      expect(
        nutritionLines(loadCorpusRecipe(_spaghetti))[10].raw,
        'Vegetable oil, for pan-frying',
      );
      final twoLabelled = capped(
        gravy,
        [
          '1 pound meatloaf mix',
          'Vegetable oil, for pan-frying',
          '2 ounces thinly sliced prosciutto, minced',
          'Vegetable oil, for pan-frying',
        ],
        [s3, s3],
      );
      // closer5: S3.0's fry vessel renamed and a sentence after the
      // lift-out (the `_anotherVessel` rows).
      List<String> vesselAfter(String vessel, String x) => g3(
        s3
            .replaceFirst('large nonstick skillet', vessel)
            .replaceFirst(lift, '$lift$x '),
      );
      // closer6 (verify6 D1, D4): |20 = 0095's real "4 tablespoons (½
      // stick) unsalted butter" (the v6_O46 / v6_O47 rows — STATED
      // synthesized: no corpus shallow recipe mentions its fat line
      // twice); |20 retyped "½ cup extra-virgin olive oil" (v6_O28 —
      // STATED synthesized: 748608 carries no '204', its nutrient sibling
      // 171413 does); a two-fry recipe with one amount line (gumbo|3's
      // real "½ cup vegetable oil") and one amount-less (0357|10's real
      // "Vegetable oil, for pan-frying"), S3 twice (v6_P24_* — STATED
      // synthesized: no corpus recipe holds two shallow lines).
      final butter = nutritionLines(loadCorpusRecipe(_dumplings))[3];
      expect(butter.raw, '4 tablespoons (½ stick) unsalted butter');
      expect(
        nutritionLines(loadCorpusRecipe(_gumbo))[3].raw,
        '½ cup vegetable oil',
      );
      Recipe at20(IngredientLine line) => gravy.copyWith(
        ingredients: [
          for (final (i, g) in gravy.ingredients.indexed)
            i == 1
                ? g.copyWith(
                    items: [
                      for (final (j, l) in g.items.indexed) j == 10 ? line : l,
                    ],
                  )
                : g,
        ],
      );
      final buttered = at20(butter);
      const evooRaw = '½ cup extra-virgin olive oil';
      final evooParsed = parseIngredientLine(evooRaw);
      final evoo = at20(
        nutritionLines(gravy)[20].copyWith(
          raw: evooRaw,
          amounts: evooParsed.amounts,
          item: evooParsed.item,
          prep: evooParsed.prep,
        ),
      );
      final twoMixed = capped(
        gravy,
        [
          '1 pound meatloaf mix',
          '½ cup vegetable oil',
          '2 ounces thinly sliced prosciutto, minced',
          'Vegetable oil, for pan-frying',
        ],
        [s3, s3],
      );
      // closer5: every row compared, the flipped ones listed (each
      // mutant's own row named in its failure — fix100/closer5.md).
      final flipped = <String>[];
      for (final (tag, real, at, steps, form) in [
        // V02 R2 `_heatsLittle`'s unread-volume fallback `?? _quarterCupMl` →
        // `?? 0` — SYNTH: a weight print (no corpus heat sentence prints a fat
        // by weight; verify4 grep 0); the mutant: 10.13 (the film).
        (
          'V02',
          gravy,
          20,
          g3(s3.replaceFirst('heat the oil in', 'heat 4 ounces of the oil in')),
          admitted,
        ),
        // V03 R2's `<` → `<=` (exactly ¼ cup is ample) —
        // 0708-best-summer-tomato-gratin.yaml; the mutant: 10.13 (the film).
        (
          'V03',
          gravy,
          20,
          heatAs(
            'Heat ¼ cup oil in 12-inch ovensafe skillet over medium-low heat until shimmering.',
          ),
          admitted,
        ),
        // V04 `_fryVesselOf`'s scan back through h's step → h's sentence only —
        // 0068-cast-iron-baked-ziti-with-charred-tomatoes.yaml + SYNTH: S3.0's "
        // in a large nonstick skillet" deleted; the mutant: 10.13 (the film).
        (
          'V04',
          gravy,
          20,
          heatAs(
            'Heat 12-inch cast-iron skillet over medium heat for 5 minutes. When the sauce is 30 minutes from being done, heat the oil over medium-high heat until shimmering.',
          ),
          admitted,
        ),
        // V05 `_panFactsOf`'s `another.isNotEmpty ||` (an introduced vessel
        // switches away) —
        // 0003-old-fashioned-slow-cooker-chicken-noodle-soup.yaml; the mutant:
        // 10.13 (the film).
        (
          'V05',
          gravy,
          20,
          after('Bring 4 quarts water to a boil in a large pot.'),
          admitted,
        ),
        // V07 `vessel == null ||` (no fry vessel: any named vessel current) —
        // SYNTH: S3.0's vessel deleted (S3.5 "Return the pot …" then current);
        // the mutant: 11.19 (admitted).
        (
          'V07',
          gravy,
          20,
          g3(s3.replaceFirst(' in a large nonstick skillet', '')),
          film,
        ),
        // V08 R3's plural stem (`piece.length > 3 && …s`) — SYNTH: "the
        // meatballs" → "each meatball"; the mutant: 10.13 (the film).
        (
          'V08',
          gravy,
          20,
          addAs(
            'Add each meatball and cook until well browned all over, 5 to 7 minutes.',
          ),
          admitted,
        ),
        // V09 R3's cut of the lift sentence at its verb — SYNTH: an add after
        // the lift-out verb; the mutant: 10.13 (the film).
        (
          'V09',
          gravy,
          20,
          liftAs(
            'Transfer the meatballs to a paper towel–lined plate to drain briefly and add the onions to the pot.',
          ),
          admitted,
        ),
        // V13 `_rouxFlour`'s "stir in|whisk in" (and RF_whiskin, "whisk in"
        // alone) — 0303-turkey-tetrazzini.yaml; the mutant: 20.68 `discarded`.
        (
          'V13',
          broiled,
          12,
          b3(
            'Whisk in the flour and cook, whisking constantly, until the flour turns golden, 1 to 2 minutes.',
          ),
          density,
        ),
        // V14 `_rouxFlour`'s "(?:all-purpose )?" — 0805-fougasse.yaml; the
        // mutant: 20.68 `discarded`.
        (
          'V14',
          broiled,
          12,
          b3('Add all-purpose flour, salt, and yeast to mixer bowl.'),
          density,
        ),
        // V15 `_panReused`'s "deglaz" — 0432-classic-french-onion-soup.yaml; the
        // mutant: 11.19 (admitted).
        (
          'V15',
          gravy,
          20,
          after(
            'Repeat the process of deglazing 2 to 3 more times, until the onions are very dark brown.',
          ),
          film,
        ),
        // V16 `_panReused`'s "fond" —
        // 0357-pork-fennel-and-lemon-ragu-with-pappardelle.yaml ("Cover pot so
        // fond …") + SYNTH: "pot" → "skillet"; the mutant: 11.19 (admitted).
        (
          'V16',
          gravy,
          20,
          after('Cover skillet so fond will steam and soften.'),
          film,
        ),
        // V17 `_panReused`'s "leav… fat in" —
        // 0000-italian-style-turkey-meatballs.yaml; the mutant: 11.19
        // (admitted).
        (
          'V17',
          gravy,
          20,
          liftAs(
            'Transfer meatballs to paper towel–lined plate, leaving fat in skillet.',
          ),
          film,
        ),
        // V18 `_panReused`'s "to / into / over the fat" —
        // 0500-mexican-rice.yaml; the mutant: 11.19 (admitted).
        (
          'V18',
          gravy,
          20,
          after(
            'Drop 3 or 4 grains of rice into the oil; if the grains sizzle, the oil is ready.',
          ),
          film,
        ),
        // V19 `_panReused`'s "reserve … fat" — SYNTH: no corpus sentence
        // isolates "reserve … fat"; the mutant: 11.19 (admitted).
        ('V19', gravy, 20, after('Reserve the oil for another use.'), film),
        // V20 `_panReused`'s "pan sauce" —
        // 0121-crispy-skinned-chicken-breasts-with-vinegar-pepper-pan-sauce.yaml;
        // the mutant: 11.19 (admitted).
        (
          'V20',
          gravy,
          20,
          after(
            'Transfer breasts to individual plates and let rest while preparing pan sauce.',
          ),
          film,
        ),
        // V24 `nowEmpty`'s "now empty" spelling — 0017-mushroom-bisque.yaml
        // ("now-empty") + SYNTH: the hyphen dropped (the corpus never spells it
        // so); the mutant: 11.19 (admitted).
        (
          'V24',
          gravy,
          20,
          after(
            'Return soup to now empty pot and bring to simmer over low heat.',
          ),
          film,
        ),
        // V25 `_awayFromPan`'s "boiling water" — OWN: 0351 S4.1; the mutant:
        // 10.13 (the film).
        (
          'V25',
          gravy,
          20,
          after(
            'Add 2 tablespoons salt and the pasta to the boiling water and cook, stirring often, until al dente.',
          ),
          admitted,
        ),
        // V26 `_liftTo`'s "platter" — OWN: 0351 S5.0; the mutant: 10.13 (the
        // film).
        (
          'V26',
          gravy,
          20,
          liftAs(
            'Using tongs, transfer the meatballs, ribs, and sausage to a serving platter and cut the sausages in half.',
          ),
          admitted,
        ),
        // AF_added `_addsFood`'s "added" —
        // 1135-gnocchi-a-la-parisienne-with-arugula-tomatoes-and-olives.yaml;
        // the mutant: 11.19 (admitted).
        (
          'AF_added',
          gravy,
          20,
          before(
            'When all eggs have been added, scrape down sides of bowl with rubber spatula.',
          ),
          film,
        ),
        // AF_adding `_addsFood`'s "adding" — 0138-glazed-roast-chicken.yaml; the
        // mutant: 11.19 (admitted).
        (
          'AF_adding',
          gravy,
          20,
          before(
            'Carve the chicken, adding any accumulated juices to the sauce.',
          ),
          film,
        ),
        // AF_placesd `_addsFood`'s "place[sd]?" — 0542-mu-shu-pork.yaml; the
        // mutant: 11.19 (admitted).
        ('AF_placesd', gravy, 20, before('Unwrap and place on plate.'), film),
        // AF_placing `_addsFood`'s "placing" —
        // 0369-hand-rolled-meat-ravioli.yaml; the mutant: 11.19 (admitted).
        (
          'AF_placing',
          gravy,
          20,
          before(
            'Repeat placing 1-tablespoon mounds of filling, spaced 1½ inches apart, 1 inch from bottom edge of dough.',
          ),
          film,
        ),
        // AF_lay `_addsFood`'s "lay" — 0416-lighter-chicken-parmesan.yaml; the
        // mutant: 11.19 (admitted).
        (
          'AF_lay',
          gravy,
          20,
          before('Lay the chicken on the wire rack.'),
          film,
        ),
        // AF_lays `_addsFood`'s "lays" — 0416-lighter-chicken-parmesan.yaml
        // ("Lay …") + SYNTH: "Lay" → "Lays" (no corpus "lays"); the mutant:
        // 11.19 (admitted).
        (
          'AF_lays',
          gravy,
          20,
          before('Lays the chicken on the wire rack.'),
          film,
        ),
        // AF_laid `_addsFood`'s "laid" — 0416-lighter-chicken-parmesan.yaml
        // ("Lay …") + SYNTH: "Lay" → "Laid" (no corpus "laid"); the mutant:
        // 11.19 (admitted).
        (
          'AF_laid',
          gravy,
          20,
          before('Laid the chicken on the wire rack.'),
          film,
        ),
        // AF_arrangesd `_addsFood`'s "arrange[sd]?" — 1123-briam.yaml; the
        // mutant: 11.19 (admitted).
        (
          'AF_arrangesd',
          gravy,
          20,
          before('Arrange zucchini in single layer.'),
          film,
        ),
        // AF_put `_addsFood`'s "put" — 0908-paris-brest.yaml; the mutant: 11.19
        // (admitted).
        (
          'AF_put',
          gravy,
          20,
          before('Put all remaining dough into pastry bag.'),
          film,
        ),
        // AF_puts `_addsFood`'s "puts" — 0908-paris-brest.yaml ("Put …") +
        // SYNTH: "Put" → "Puts" (no corpus "puts"); the mutant: 11.19
        // (admitted).
        (
          'AF_puts',
          gravy,
          20,
          before('Puts all remaining dough into pastry bag.'),
          film,
        ),
        // AF_drop `_addsFood`'s "drop" — 0744-easy-pancakes.yaml; the mutant:
        // 11.19 (admitted).
        (
          'AF_drop',
          gravy,
          20,
          before('Drop 1 tablespoon batter in center of skillet.'),
          film,
        ),
        // AF_drops `_addsFood`'s "drops" — 0856-angel-food-cake.yaml; the
        // mutant: 11.19 (admitted).
        (
          'AF_drops',
          gravy,
          20,
          before(
            'Wipe any drops of batter off the sides of the pan and lightly tap the pan against the countertop two or three times to settle the batter.',
          ),
          film,
        ),
        // AF_dropped `_addsFood`'s "dropped" — 0570-falafel.yaml; the mutant:
        // 11.19 (admitted).
        (
          'AF_dropped',
          gravy,
          20,
          before(
            'Microwave, whisking every 10 seconds, until mixture thickens to stiff, smooth, pudding-like consistency that forms mound when dropped from end of whisk into bowl, 40 to 80 seconds.',
          ),
          film,
        ),
        // AF_sprinklesd `_addsFood`'s "sprinkle[sd]?" — 1123-briam.yaml; the
        // mutant: 11.19 (admitted).
        (
          'AF_sprinklesd',
          gravy,
          20,
          before('Sprinkle parsley over top and serve.'),
          film,
        ),
        // AF_stirin `_addsFood`'s "stir in" — 0866-carrot-cake.yaml; the mutant:
        // 11.19 (admitted).
        ('AF_stirin', gravy, 20, before('Stir in the carrots.'), film),
        // AF_pourin `_addsFood`'s "pour in" — 0750-easy-buttermilk-waffles.yaml;
        // the mutant: 11.19 (admitted).
        (
          'AF_pourin',
          gravy,
          20,
          before(
            'Make a well in the center of the dry ingredients and pour in the wet ingredients.',
          ),
          film,
        ),
        // AV_an `_anotherVessel`'s "an" —
        // 0238-french-style-pot-roasted-pork-loin.yaml; the mutant: 10.13 (the
        // film).
        (
          'AV_an',
          gravy,
          20,
          after(
            'Melt 1 tablespoon of the butter in an 8-inch skillet over medium-low heat.',
          ),
          admitted,
        ),
        // AV_another `_anotherVessel`'s "another" —
        // 0238-french-style-pot-roasted-pork-loin.yaml + SYNTH: "an" → "another"
        // (no corpus "another skillet"); the mutant: 10.13 (the film).
        (
          'AV_another',
          gravy,
          20,
          after(
            'Melt 1 tablespoon of the butter in another 8-inch skillet over medium-low heat.',
          ),
          admitted,
        ),
        // AV_second `_anotherVessel`'s "second" —
        // 0238-french-style-pot-roasted-pork-loin.yaml + SYNTH: "an 8-inch" →
        // "the second" (no corpus "second skillet"); the mutant: 10.13 (the
        // film).
        (
          'AV_second',
          gravy,
          20,
          after(
            'Melt 1 tablespoon of the butter in the second skillet over medium-low heat.',
          ),
          admitted,
        ),
        // AV_clean `_anotherVessel`'s "clean" — 0303-turkey-tetrazzini.yaml; the
        // mutant: 10.13 (the film).
        (
          'AV_clean',
          gravy,
          20,
          after(
            'Melt the remaining 6 tablespoons butter in the clean skillet over medium heat.',
          ),
          admitted,
        ),
        // A_liquid `_awayFromPan`'s "the liquid" — 0028-hearty-minestrone.yaml;
        // the mutant: 10.13 (the film).
        (
          'A_liquid',
          gravy,
          20,
          after(
            'Reduce the heat and vigorously simmer, stirring occasionally, until the beans are fully tender and the liquid begins to thicken, 45 to 60 minutes.',
          ),
          admitted,
        ),
        // A_sauce `_awayFromPan`'s "the sauce" —
        // 0071-skillet-chicken-pot-pie-with-biscuit-topping.yaml; the mutant:
        // 10.13 (the film).
        (
          'A_sauce',
          gravy,
          20,
          after(
            'Stir the peas and carrots into the sauce and simmer until heated through, about 2 minutes.',
          ),
          admitted,
        ),
        // A_oven `_awayFromPan`'s "from the oven" —
        // 0241-garlic-studded-roast-pork-loin.yaml +
        // 0008-our-favorite-chili.yaml; the mutant: 10.13 (the film).
        (
          'A_oven',
          gravy,
          20,
          after(
            'Remove the meat from the oven; immediately reduce the oven temperature to 325 degrees. Cook until the meat and beans are fully tender, 1½ to 2 hours.',
          ),
          admitted,
        ),
        // BV_add `_batchVerb`'s "add" — 0542-mu-shu-pork.yaml; the mutant: 10.13
        // (the film).
        ('BV_add', gravy, 20, batch('Add pork mixture.'), admitted),
        // BV_cook `_batchVerb`'s "cook" —
        // 0266-butter-basted-fish-fillets-with-garlic-and-thyme.yaml; the
        // mutant: 10.13 (the film).
        ('BV_cook', gravy, 20, batch('Cook for 1 minute.'), admitted),
        // BV_brown `_batchVerb`'s "brown" —
        // 0268-oven-steamed-fish-with-scallions-and-ginger.yaml; the mutant:
        // 10.13 (the film).
        (
          'BV_brown',
          gravy,
          20,
          batch('Stir until ginger is beginning to brown and crisp.'),
          admitted,
        ),
        // BV_fry `_batchVerb`'s "fry" — SYNTH: no corpus sentence opens on a
        // cooking verb with "fry" its only batch verb, and a plain "fry" makes
        // |20 an ambiguous medium on 0351 (R0 refuses first — closer4 probe:
        // 0268's sentence with "brown" → "fry" held); "stir-fry" is no
        // frying-medium signal; the mutant: 10.13 (the film).
        (
          'BV_fry',
          gravy,
          20,
          batch('Stir-fry the remaining meatballs.'),
          admitted,
        ),
        // BV_turn `_batchVerb`'s "turn" — 0204-cider-glazed-pork-chops.yaml; the
        // mutant: 10.13 (the film).
        (
          'BV_turn',
          gravy,
          20,
          batch(
            'Return the chops to the skillet and turn to coat both sides with the glaze.',
          ),
          admitted,
        ),
        // BV_flip `_batchVerb`'s "flip" —
        // 0558-vietnamese-style-caramel-chicken-with-broccoli.yaml; the mutant:
        // 10.13 (the film).
        (
          'BV_flip',
          gravy,
          20,
          batch(
            'Reduce heat to medium-low, cover, and simmer until chicken is fork-tender and registers 205 degrees, 30 to 40 minutes, flipping chicken halfway through simmering.',
          ),
          admitted,
        ),
        // BV_place `_batchVerb`'s "place" —
        // 0590-grilled-mojo-marinated-skirt-steak.yaml; the mutant: 10.13 (the
        // film).
        ('BV_place', gravy, 20, batch('Place steaks in dish.'), admitted),
        // BV_drop `_batchVerb`'s "drop" — 0804-piadine-italian-flatbreads.yaml;
        // the mutant: 10.13 (the film).
        (
          'BV_drop',
          gravy,
          20,
          batch(
            'Heat 12-inch cast-iron skillet over medium heat until drop of water dripped onto surface sizzles immediately, about 3 minutes.',
          ),
          admitted,
        ),
        // CP_add `_cooksInPan`'s "add" — 0002-classic-chicken-noodle-soup.yaml;
        // the mutant: 11.19 (admitted).
        (
          'CP_add',
          gravy,
          20,
          after(
            'Add the onion and cook, stirring frequently, until the onion is translucent, 3 to 5 minutes.',
          ),
          film,
        ),
        // CP_cook `_cooksInPan`'s "cook" — 0008-our-favorite-chili.yaml; the
        // mutant: 11.19 (admitted).
        (
          'CP_cook',
          gravy,
          20,
          after(
            'Cook until the meat and beans are fully tender, 1½ to 2 hours.',
          ),
          film,
        ),
        // CP_reduce `_cooksInPan`'s "reduce" —
        // 0002-classic-chicken-noodle-soup.yaml; the mutant: 11.19 (admitted).
        (
          'CP_reduce',
          gravy,
          20,
          after(
            'Reduce the heat to medium-low and simmer until the flavors have blended, about 20 minutes.',
          ),
          film,
        ),
        // CP_increase `_cooksInPan`'s "increase" — 0005-best-beef-stew.yaml; the
        // mutant: 11.19 (admitted).
        (
          'CP_increase',
          gravy,
          20,
          after(
            'Increase the heat to high and allow the wine to simmer until thickened and slightly reduced, about 2 minutes.',
          ),
          film,
        ),
        // CP_pour `_cooksInPan`'s "pour" — 0010-vietnamese-beef-pho.yaml; the
        // mutant: 11.19 (admitted).
        (
          'CP_pour',
          gravy,
          20,
          after('Pour broth through colander set in large bowl.'),
          film,
        ),
        // CP_whisk `_cooksInPan`'s "whisk" —
        // 0026-red-lentil-soup-with-warm-spices.yaml; the mutant: 11.19
        // (admitted).
        (
          'CP_whisk',
          gravy,
          20,
          after(
            'Whisk soup vigorously until it is coarsely pureed, about 30 seconds.',
          ),
          film,
        ),
        // CP_melt `_cooksInPan`'s "melt" —
        // 0026-red-lentil-soup-with-warm-spices.yaml; the mutant: 11.19
        // (admitted).
        (
          'CP_melt',
          gravy,
          20,
          after(
            'Melt remaining 2 tablespoons butter in small skillet over medium-low heat.',
          ),
          film,
        ),
        // CP_heat `_cooksInPan`'s "heat" —
        // 0068-cast-iron-baked-ziti-with-charred-tomatoes.yaml; the mutant:
        // 11.19 (admitted).
        (
          'CP_heat',
          gravy,
          20,
          after(
            'Heat 12-inch cast-iron skillet over medium heat for 5 minutes.',
          ),
          film,
        ),
        // CP_bring `_cooksInPan`'s "bring" — 0020-sweet-potato-soup.yaml; the
        // mutant: 11.19 (admitted).
        ('CP_bring', gravy, 20, after('Bring to simmer over high heat.'), film),
        // CP_place `_cooksInPan`'s "place" — 0010-vietnamese-beef-pho.yaml; the
        // mutant: 11.19 (admitted).
        (
          'CP_place',
          gravy,
          20,
          after(
            'Place noodles in large container and cover with hot tap water.',
          ),
          film,
        ),
        // VW_dutchoven `_vesselWord`'s "dutch oven" —
        // 0002-classic-chicken-noodle-soup.yaml; the mutant: 10.13 (the film).
        (
          'VW_dutchoven',
          gravy,
          20,
          heatAs(
            'Heat the oil in a large Dutch oven over medium-high heat until shimmering.',
          ),
          admitted,
        ),
        // VW_saucepan `_vesselWord`'s "saucepan" —
        // 0353-simple-italian-style-meat-sauce.yaml; the mutant: 10.13 (the
        // film).
        (
          'VW_saucepan',
          gravy,
          20,
          heatAs(
            'Heat the oil in a large saucepan over medium-high heat until just smoking.',
          ),
          admitted,
        ),
        // VW_wok `_vesselWord`'s "wok" — SYNTH: "nonstick skillet" → "wok" (no
        // corpus sentence heats the oil in a wok); the mutant: 10.13 (the film).
        (
          'VW_wok',
          gravy,
          20,
          g3(s3.replaceFirst('large nonstick skillet', 'large wok')),
          admitted,
        ),
        // VW_griddle `_vesselWord`'s "griddle" — SYNTH: "large nonstick skillet"
        // → "griddle" (no corpus sentence heats the oil on a griddle); the
        // mutant: 10.13 (the film).
        (
          'VW_griddle',
          gravy,
          20,
          g3(s3.replaceFirst('a large nonstick skillet', 'a griddle')),
          admitted,
        ),
        // VW_pan `_vesselWord`'s "pan" — SYNTH: "skillet" → "pan"; the mutant:
        // 10.13 (the film).
        (
          'VW_pan',
          gravy,
          20,
          g3(s3.replaceFirst('large nonstick skillet', 'large nonstick pan')),
          admitted,
        ),
        // VW_pot `_vesselWord`'s "pot" — SYNTH: "nonstick skillet" → "pot" (S3.5
        // returns that pot to the oven: reused); the mutant: 11.19 (admitted).
        (
          'VW_pot',
          gravy,
          20,
          g3(s3.replaceFirst('large nonstick skillet', 'large pot')),
          film,
        ),
        // PW_meat `_pieceWords`' "meat" —
        // 0354-fettuccine-with-slow-simmered-bolognese-sauce.yaml; the mutant:
        // 10.13 (the film).
        (
          'PW_meat',
          gravy,
          20,
          addAs(
            'Add the meat and ½ teaspoon salt; crumble the meat into tiny pieces with a wooden spoon.',
          ),
          admitted,
        ),
        // PW_pieces `_pieceWords`' "pieces" — SYNTH: "the meatballs" → "the
        // pieces" (no corpus add opens on "pieces"); the mutant: 10.13 (the
        // film).
        (
          'PW_pieces',
          gravy,
          20,
          addAs(
            'Add the pieces and cook until well browned all over, 5 to 7 minutes.',
          ),
          admitted,
        ),
        // PW_batch `_pieceWords`' "batch" — SYNTH: "the meatballs" → "the batch"
        // (no corpus add opens on "batch"); the mutant: 10.13 (the film).
        (
          'PW_batch',
          gravy,
          20,
          addAs(
            'Add the batch and cook until well browned all over, 5 to 7 minutes.',
          ),
          admitted,
        ),
        // T_plate `_liftTo`'s "plate" — SYNTH: "a paper towel–lined plate" → "a
        // plate" (P1's also matches "paper towel"); the mutant: 10.13 (the
        // film).
        (
          'T_plate',
          gravy,
          20,
          liftAs('Transfer the meatballs to a plate to drain briefly.'),
          admitted,
        ),
        // T_wirerack `_liftTo`'s "wire rack" — SYNTH: four words before "wire
        // rack" — "rack" alone reaches it through the {0,4} word run otherwise;
        // the mutant: 10.13 (the film).
        (
          'T_wirerack',
          gravy,
          20,
          liftAs(
            'Transfer the meatballs to the prepared large clean cooling wire rack to drain briefly.',
          ),
          admitted,
        ),
        // T_rack `_liftTo`'s "rack" — SYNTH: "paper towel–lined plate" → "rack";
        // the mutant: 10.13 (the film).
        (
          'T_rack',
          gravy,
          20,
          liftAs('Transfer the meatballs to a rack to drain briefly.'),
          admitted,
        ),
        // T_bakingsheet `_liftTo`'s "baking sheet" —
        // 0576-tender-juicy-grilled-burgers.yaml; the mutant: 10.13 (the film).
        (
          'T_bakingsheet',
          gravy,
          20,
          liftAs('Transfer meat to baking sheet.'),
          admitted,
        ),
        // T_cutting `_liftTo`'s "cutting board" — SYNTH: "paper towel–lined
        // plate" → "cutting board" (no corpus lift of a piece word to one); the
        // mutant: 10.13 (the film).
        (
          'T_cutting',
          gravy,
          20,
          liftAs('Transfer the meatballs to a cutting board.'),
          admitted,
        ),
        // T_carving `_liftTo`'s "carving board" —
        // 0235-maple-glazed-pork-tenderloin.yaml; the mutant: 10.13 (the film).
        (
          'T_carving',
          gravy,
          20,
          liftAs(
            'Transfer the meat to a carving board and slice into ¼-inch-thick pieces.',
          ),
          admitted,
        ),
        // T_towels `_liftTo`'s "paper towels?" — SYNTH: "a paper towel–lined
        // plate" → "paper towels"; the mutant: 10.13 (the film).
        (
          'T_towels',
          gravy,
          20,
          liftAs('Transfer the meatballs to paper towels to drain briefly.'),
          admitted,
        ),
        // L_remove `_liftVerb`'s "remove" — SYNTH: "Transfer" → "Remove" (also
        // N_mov); the mutant: 10.13 (the film).
        (
          'L_remove',
          gravy,
          20,
          liftAs('Remove the meatballs to a paper towel–lined plate.'),
          admitted,
        ),
        // L_move `_liftVerb`'s "move" — SYNTH: "Transfer" → "Move" (also N_mov);
        // the mutant: 10.13 (the film).
        (
          'L_move',
          gravy,
          20,
          liftAs('Move the meatballs to a paper towel–lined plate.'),
          admitted,
        ),
        // L_lift `_liftVerb`'s "lift" — SYNTH: "Transfer" → "Lift" (also
        // N_lift); the mutant: 10.13 (the film).
        (
          'L_lift',
          gravy,
          20,
          liftAs('Lift the meatballs to a paper towel–lined plate.'),
          admitted,
        ),
        // PR_scrap `_panReused`'s "scrap… up" — 0798-almost-no-knead-bread.yaml;
        // the mutant: 11.19 (admitted).
        (
          'PR_scrap',
          gravy,
          20,
          after(
            'Using rubber spatula, fold mixture, scraping up dry flour from bottom of bowl, until shaggy ball forms.',
          ),
          film,
        ),
        // PR_bits `_panReused`'s "browned bits" —
        // 0040-wilted-spinach-salad-with-warm-bacon-dressing.yaml; the mutant:
        // 11.19 (admitted).
        (
          'PR_bits',
          gravy,
          20,
          after(
            'Working quickly, scrape the bottom of the skillet with a wooden spoon to loosen the browned bits.',
          ),
          film,
        ),
        // RF_stirin `_rouxFlour`'s "stir in" — 0094-shepherds-pie.yaml; the
        // mutant: 20.68 `discarded`.
        (
          'RF_stirin',
          broiled,
          12,
          b3('Stir in flour and cook for 1 minute.'),
          density,
        ),
        // NP_it `_notAPiece`'s "it" — SYNTH: S3.1 names "it", S3.2 lifts it; the
        // mutant: 11.19 (admitted).
        (
          'NP_it',
          gravy,
          20,
          addLift(
            'Add the meatballs and the it and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the it to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_them `_notAPiece`'s "them" — SYNTH: S3.1 names "them", S3.2 lifts
        // it; the mutant: 11.19 (admitted).
        (
          'NP_them',
          gravy,
          20,
          addLift(
            'Add the meatballs and the them and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the them to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_mixture `_notAPiece`'s "mixture" — SYNTH: S3.1 names "mixture",
        // S3.2 lifts it; the mutant: 11.19 (admitted).
        (
          'NP_mixture',
          gravy,
          20,
          addLift(
            'Add the meatballs and the mixture and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the mixture to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_contents `_notAPiece`'s "contents" — SYNTH: S3.1 names "contents",
        // S3.2 lifts it; the mutant: 11.19 (admitted).
        (
          'NP_contents',
          gravy,
          20,
          addLift(
            'Add the meatballs and the contents and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the contents to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_from `_notAPiece`'s "from" — SYNTH: S3.1 names "from", S3.2 lifts
        // it; the mutant: 11.19 (admitted).
        (
          'NP_from',
          gravy,
          20,
          addLift(
            'Add the meatballs and the from and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the from to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_with `_notAPiece`'s "with" — SYNTH: S3.1 names "with", S3.2 lifts
        // it; the mutant: 11.19 (admitted).
        (
          'NP_with',
          gravy,
          20,
          addLift(
            'Add the meatballs and the with and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the with to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_into `_notAPiece`'s "into" — SYNTH: S3.1 names "into", S3.2 lifts
        // it; the mutant: 11.19 (admitted).
        (
          'NP_into',
          gravy,
          20,
          addLift(
            'Add the meatballs and the into and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the into to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_onto `_notAPiece`'s "onto" — SYNTH: S3.1 names "onto", S3.2 lifts
        // it; the mutant: 11.19 (admitted).
        (
          'NP_onto',
          gravy,
          20,
          addLift(
            'Add the meatballs and the onto and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the onto to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_and `_notAPiece`'s "and" — SYNTH: S3.1 names "and", S3.2 lifts it;
        // the mutant: 11.19 (admitted).
        (
          'NP_and',
          gravy,
          20,
          addLift(
            'Add the meatballs and the and and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the and to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_on `_notAPiece`'s "on" — SYNTH: S3.1 names "on", S3.2 lifts it; the
        // mutant: 11.19 (admitted).
        (
          'NP_on',
          gravy,
          20,
          addLift(
            'Add the meatballs and the on and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the on to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_pan `_notAPiece`'s "pan" — SYNTH: S3.1 names "pan", S3.2 lifts it;
        // the mutant: 11.19 (admitted).
        (
          'NP_pan',
          gravy,
          20,
          addLift(
            'Add the meatballs and the pan and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the pan to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_skillet `_notAPiece`'s "skillet" — SYNTH: S3.1 names "skillet",
        // S3.2 lifts it; the mutant: 11.19 (admitted).
        (
          'NP_skillet',
          gravy,
          20,
          addLift(
            'Add the meatballs and the skillet and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the skillet to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_pot `_notAPiece`'s "pot" — SYNTH: S3.1 names "pot", S3.2 lifts it;
        // the mutant: 11.19 (admitted).
        (
          'NP_pot',
          gravy,
          20,
          addLift(
            'Add the meatballs and the pot and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the pot to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_saucepan `_notAPiece`'s "saucepan" — SYNTH: S3.1 names "saucepan",
        // S3.2 lifts it; the mutant: 11.19 (admitted).
        (
          'NP_saucepan',
          gravy,
          20,
          addLift(
            'Add the meatballs and the saucepan and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the saucepan to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_wok `_notAPiece`'s "wok" — SYNTH: S3.1 names "wok", S3.2 lifts it;
        // the mutant: 11.19 (admitted).
        (
          'NP_wok',
          gravy,
          20,
          addLift(
            'Add the meatballs and the wok and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the wok to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_dutch `_notAPiece`'s "dutch" — SYNTH: S3.1 names "Dutch oven", S3.2
        // lifts it; the mutant: 11.19 (admitted).
        (
          'NP_dutch',
          gravy,
          20,
          addLift(
            'Add the meatballs and the Dutch oven and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the Dutch oven to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_sheet `_notAPiece`'s "sheet" — SYNTH: S3.1 names "sheet", S3.2
        // lifts it; the mutant: 11.19 (admitted).
        (
          'NP_sheet',
          gravy,
          20,
          addLift(
            'Add the meatballs and the sheet and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the sheet to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_plate `_notAPiece`'s "plate" — SYNTH: S3.1 names "plate", S3.2
        // lifts it; the mutant: 11.19 (admitted).
        (
          'NP_plate',
          gravy,
          20,
          addLift(
            'Add the meatballs and the plate and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the plate to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_platter `_notAPiece`'s "platter" — SYNTH: S3.1 names "platter",
        // S3.2 lifts it; the mutant: 11.19 (admitted).
        (
          'NP_platter',
          gravy,
          20,
          addLift(
            'Add the meatballs and the platter and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the platter to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_bowl `_notAPiece`'s "bowl" — SYNTH: S3.1 names "bowl", S3.2 lifts
        // it; the mutant: 11.19 (admitted).
        (
          'NP_bowl',
          gravy,
          20,
          addLift(
            'Add the meatballs and the bowl and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the bowl to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // NP_everything `_notAPiece`'s "everything" — SYNTH: S3.1 names
        // "everything", S3.2 lifts it; the mutant: 11.19 (admitted).
        (
          'NP_everything',
          gravy,
          20,
          addLift(
            'Add the meatballs and the everything and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the everything to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // LO_half `_liftObject`'s filler "half" — SYNTH: "half the meatballs"
        // lifted; the mutant: 10.13 (the film).
        (
          'LO_half',
          gravy,
          20,
          liftAs(
            'Transfer half the meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LO_each `_liftObject`'s filler "each" — SYNTH: "each meatball" lifted;
        // the mutant: 10.13 (the film).
        (
          'LO_each',
          gravy,
          20,
          liftAs(
            'Transfer each meatball to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LO_both `_liftObject`'s filler "both" — SYNTH: "both meatballs"
        // lifted; the mutant: 10.13 (the film).
        (
          'LO_both',
          gravy,
          20,
          liftAs(
            'Transfer both meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LO_first `_liftObject`'s filler "first" — SYNTH: "the first meatballs"
        // lifted; the mutant: 10.13 (the film).
        (
          'LO_first',
          gravy,
          20,
          liftAs(
            'Transfer the first meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LO_second `_liftObject`'s filler "second" — SYNTH: "the second
        // meatballs" lifted; the mutant: 10.13 (the film).
        (
          'LO_second',
          gravy,
          20,
          liftAs(
            'Transfer the second meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LO_batch `_liftObject`'s filler "batch" — SYNTH: "the batch meatballs"
        // lifted; the mutant: 10.13 (the film).
        (
          'LO_batch',
          gravy,
          20,
          liftAs(
            'Transfer the batch meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LO_remaining `_liftObject`'s filler "remaining" — SYNTH: "the
        // remaining meatballs" lifted; the mutant: 10.13 (the film).
        (
          'LO_remaining',
          gravy,
          20,
          liftAs(
            'Transfer the remaining meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LO_seared `_liftObject`'s filler "seared" — SYNTH: "the seared
        // meatballs" lifted; the mutant: 10.13 (the film).
        (
          'LO_seared',
          gravy,
          20,
          liftAs(
            'Transfer the seared meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LO_fried `_liftObject`'s filler "fried" — SYNTH: "the fried meatballs"
        // lifted; the mutant: 10.13 (the film).
        (
          'LO_fried',
          gravy,
          20,
          liftAs(
            'Transfer the fried meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LO_cooked `_liftObject`'s filler "cooked" — SYNTH: "the cooked
        // meatballs" lifted; the mutant: 10.13 (the film).
        (
          'LO_cooked',
          gravy,
          20,
          liftAs(
            'Transfer the cooked meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LO_of `_liftObject`'s filler "of" — SYNTH: "each of the meatballs"
        // lifted; the mutant: 10.13 (the film).
        (
          'LO_of',
          gravy,
          20,
          liftAs(
            'Transfer each of the meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LO_all `_liftObject`'s filler "all" — SYNTH: "meatballs" (which holds
        // "all") → "patties", "all the patties" lifted; the mutant: 10.13 (the
        // film).
        (
          'LO_all',
          gravy,
          20,
          addLift(
            'Add the patties and cook until well browned, 5 to 7 minutes.',
            'Transfer all the patties to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LO_browned `_liftObject`'s filler "browned" — SYNTH: S3.1 without
        // "browned", "the browned meatballs" lifted; the mutant: 10.13 (the
        // film).
        (
          'LO_browned',
          gravy,
          20,
          addLift(
            'Add the meatballs and cook until golden, 5 to 7 minutes.',
            'Transfer the browned meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // RF_sprinkle `_rouxFlour`'s "sprinkle" —
        // 0142-skillet-roasted-chicken-in-lemon-sauce.yaml; the mutant: 20.68
        // `discarded`.
        (
          'RF_sprinkle',
          broiled,
          12,
          b3(
            'Sprinkle flour evenly over shallot-garlic mixture and cook, stirring constantly, until flour is lightly browned, about 1 minute.',
          ),
          density,
        ),
        // PR_l_the (the "leav… in" filler "the ") (verify5); SYNTH: 0451-coq-
        // au-vin's real "Transfer the chicken to a plate, leaving the fat in
        // the pot." with piece + vessel changed; the mutant: 11.19 (admitted).
        (
          'PR_l_the',
          gravy,
          20,
          liftAs(
            'Transfer the meatballs to a plate, leaving the fat in the skillet.',
          ),
          film,
        ),
        // PR_l_any (the filler "any ") (verify5); SYNTH: 0451-coq-au-vin's real
        // "Transfer the chicken to a plate, leaving the fat in the pot." with
        // piece + vessel changed, "the" → "any"; the mutant: 11.19 (admitted).
        (
          'PR_l_any',
          gravy,
          20,
          liftAs(
            'Transfer the meatballs to a plate, leaving any fat in the skillet.',
          ),
          film,
        ),
        // PR_l_rendered (the filler "rendered ") (verify5); SYNTH: 0451-coq-au-
        // vin's real "Transfer the chicken to a plate, leaving the fat in the
        // pot." with piece + vessel changed, "rendered" added; the mutant:
        // 11.19 (admitted).
        (
          'PR_l_rendered',
          gravy,
          20,
          liftAs(
            'Transfer the meatballs to a plate, leaving the rendered fat in the skillet.',
          ),
          film,
        ),
        // PR_l_oil (the "leav… in" word "oil") (verify5); 1086-pasta-with-
        // burst-cherry-tomato-sauce-and-fried-caper-crumbs.yaml; the mutant:
        // 11.19 (admitted).
        (
          'PR_l_oil',
          gravy,
          20,
          after('Leave oil in skillet and return skillet to medium heat.'),
          film,
        ),
        // PR_l_drippings (the word "drippings") (verify5); SYNTH: 0451-coq-au-
        // vin's real "Transfer the chicken to a plate, leaving the fat in the
        // pot." with piece + vessel changed, "fat" → "drippings"; the mutant:
        // 11.19 (admitted).
        (
          'PR_l_drippings',
          gravy,
          20,
          liftAs(
            'Transfer the meatballs to a plate, leaving the drippings in the skillet.',
          ),
          film,
        ),
        // PR_l_grease (the word "grease") (verify5); SYNTH: 0451-coq-au-vin's
        // real "Transfer the chicken to a plate, leaving the fat in the pot."
        // with piece + vessel changed, "fat" → "grease"; the mutant: 11.19
        // (admitted).
        (
          'PR_l_grease',
          gravy,
          20,
          liftAs(
            'Transfer the meatballs to a plate, leaving the grease in the skillet.',
          ),
          film,
        ),
        // PR_t_to ("to the …") (verify5); SYNTH: no corpus sentence tips food
        // "to the fat" after a fry; the mutant: 11.19 (admitted).
        (
          'PR_t_to',
          gravy,
          20,
          after('Off heat, tip the onions to the fat.'),
          film,
        ),
        // PR_t_over ("over the …") and PR_t_fat (its word "fat") (verify5);
        // 0422-chicken-canzanese.yaml; the mutant: 11.19 (admitted).
        (
          'PR_t_over',
          gravy,
          20,
          after(
            'Sprinkle the flour over the fat and cook, stirring constantly, for 1 minute.',
          ),
          film,
        ),
        // PR_t_rendered (the filler "rendered ") (verify5); SYNTH: no corpus
        // sentence tips food "into the rendered fat" after a fry; the mutant:
        // 11.19 (admitted).
        (
          'PR_t_rendered',
          gravy,
          20,
          after('Off heat, tip the onions into the rendered fat.'),
          film,
        ),
        // PR_t_hot (the filler "hot ") (verify5); 0316-classic-french-
        // fries.yaml; the mutant: 11.19 (admitted).
        (
          'PR_t_hot',
          gravy,
          20,
          after(
            'Using the paper towels as a funnel, pour the potatoes into the hot oil.',
          ),
          film,
        ),
        // PR_t_remaining (the filler "remaining ") (verify5); SYNTH: no corpus
        // sentence tips food "into the remaining fat" after a fry; the mutant:
        // 11.19 (admitted).
        (
          'PR_t_remaining',
          gravy,
          20,
          after('Off heat, tip the onions into the remaining fat.'),
          film,
        ),
        // PR_t_drippings (the word "drippings") (verify5); SYNTH: no corpus
        // sentence tips food "into the drippings" after a fry; the mutant:
        // 11.19 (admitted).
        (
          'PR_t_drippings',
          gravy,
          20,
          after('Off heat, tip the onions into the drippings.'),
          film,
        ),
        // PR_t_grease (the word "grease") (verify5); SYNTH: no corpus sentence
        // tips food "into the grease" after a fry; the mutant: 11.19
        // (admitted).
        (
          'PR_t_grease',
          gravy,
          20,
          after('Off heat, tip the onions into the grease.'),
          film,
        ),
        // PR_r_fat ("reserve … fat") and A12 (the run {0,40}? → {0,10}?)
        // (verify5); 0143-best-roast-chicken-with-root-vegetables.yaml; the
        // mutant: 11.19 (admitted).
        (
          'PR_r_fat',
          gravy,
          20,
          after('Reserve 3 tablespoons fat, discarding remaining fat.'),
          film,
        ),
        // A12 (the run {0,40}? → {0,10}?: " ½ cup plus 1 tablespoon " is 25
        // characters) (verify5); 0163-turkey-and-gravy-for-a-crowd.yaml; the
        // mutant: 11.19 (admitted).
        (
          'A12',
          gravy,
          20,
          after(
            'Reserve ½ cup plus 1 tablespoon fat (if there is not enough fat, add extra melted butter to make up difference) and 8 cups liquid; discard remaining liquid.',
          ),
          film,
        ),
        // PR_r_drippings ("reserve … drippings") (verify5); SYNTH: no corpus
        // sentence reserves drippings after a fry; the mutant: 11.19
        // (admitted).
        (
          'PR_r_drippings',
          gravy,
          20,
          after('Reserve the drippings.'),
          film,
        ),
        // PR_r_grease ("reserve … grease") (verify5); SYNTH: no corpus sentence
        // reserves grease after a fry; the mutant: 11.19 (admitted).
        (
          'PR_r_grease',
          gravy,
          20,
          after('Reserve the grease.'),
          film,
        ),
        // FF_the1 (`_fryFatObject`'s leading "the ") and FF_butter (its word
        // "butter") (verify5); 0071-skillet-chicken-pot-pie-with-biscuit-
        // topping.yaml; the mutant: 10.13 (the film).
        (
          'FF_the1',
          gravy,
          20,
          before(
            'Add the remaining 2 tablespoons butter to the skillet and return to medium heat until melted.',
          ),
          admitted,
        ),
        // FF_remaining (the filler "remaining ") (verify5); 0689-potato-
        // roesti.yaml; the mutant: 10.13 (the film).
        (
          'FF_remaining',
          gravy,
          20,
          before(
            'Add remaining 2 tablespoons butter to skillet and swirl to coat pan.',
          ),
          admitted,
        ),
        // FF_tbsp (the unit "tablespoons?") and FF_amount (the amount run)
        // (verify5); 1124-blackened-chicken.yaml; the mutant: 10.13 (the film).
        (
          'FF_tbsp',
          gravy,
          20,
          before(
            'Add 1 tablespoon butter to skillet, then tilt skillet or spread butter with flexible spatula until it coats skillet evenly.',
          ),
          admitted,
        ),
        // FF_tsp (the unit "teaspoons?") and FF_fat (the word "fat") (verify5);
        // 1122-roast-chicken-with-quinoa-swiss-chard-and-lime.yaml; the mutant:
        // 10.13 (the film).
        (
          'FF_tsp',
          gravy,
          20,
          before('Add 2 teaspoons fat to now-empty skillet.'),
          admitted,
        ),
        // FF_cups (the unit "cups?") (verify5); SYNTH: no corpus add sentence
        // names a fat by cups before a lift-out; the mutant: 10.13 (the film).
        (
          'FF_cups',
          gravy,
          20,
          before('Add ½ cup butter.'),
          admitted,
        ),
        // FF_of (the filler "of ") (verify5); 0277-pan-seared-scallops.yaml;
        // the mutant: 10.13 (the film).
        (
          'FF_of',
          gravy,
          20,
          before('Add 1 tablespoon of the butter to the skillet.'),
          admitted,
        ),
        // FF_the2 (the filler "the " after "of") (verify5); SYNTH: 0277's real
        // sentence with "melted" added; the mutant: 10.13 (the film).
        (
          'FF_the2',
          gravy,
          20,
          before('Add 1 tablespoon of the melted butter to the skillet.'),
          admitted,
        ),
        // FF_word (the one-word run "[a-z-]+ ") (verify5); 0913-foolproof-new-
        // york-cheesecake.yaml; the mutant: 10.13 (the film).
        (
          'FF_word',
          gravy,
          20,
          before(
            'Add 6 tablespoons melted butter and pulse until crumbs are evenly moistened, about 10 pulses.',
          ),
          admitted,
        ),
        // FF_shortening (the word "shortening") (verify5); 0958-skillet-apple-
        // pie.yaml; the mutant: 10.13 (the film).
        (
          'FF_shortening',
          gravy,
          20,
          before(
            'Add the shortening and pulse until the mixture has the texture of coarse sand, about 10 pulses.',
          ),
          admitted,
        ),
        // FF_lard (the word "lard") (verify5); 1131-pasta-cacio-e-uova-pasta-
        // with-cheese-and-eggs.yaml; the mutant: 10.13 (the film).
        (
          'FF_lard',
          gravy,
          20,
          before(
            'Immediately add lard, egg mixture, and 1 tablespoon reserved cooking water to pasta and stir until cheese is fully melted.',
          ),
          admitted,
        ),
        // A18 (`_piecesIn`'s object cut drops ",") (verify5); SYNTH: no corpus
        // add sentence lists a food before 0351's meatballs; the mutant: 11.19
        // (admitted).
        (
          'A18',
          gravy,
          20,
          addAs(
            'Add the garlic, then the meatballs and cook until well browned all over, 5 to 7 minutes.',
          ),
          film,
        ),
        // A18s (the cut drops ";") (verify5); SYNTH: no corpus add sentence
        // lists a food before 0351's meatballs; the mutant: 11.19 (admitted).
        (
          'A18s',
          gravy,
          20,
          addAs(
            'Add the garlic; then the meatballs and cook until well browned all over, 5 to 7 minutes.',
          ),
          film,
        ),
        // A18c (the cut drops ":") (verify5); SYNTH: no corpus add sentence
        // lists a food before 0351's meatballs; the mutant: 11.19 (admitted).
        (
          'A18c',
          gravy,
          20,
          addAs(
            'Add the garlic: then the meatballs and cook until well browned all over, 5 to 7 minutes.',
          ),
          film,
        ),
        // `_drainsOnTowels`' filler "briefly" (DT_briefly) (verify5); SYNTH: no
        // corpus drain sentence of this form ("the pieces" added, "briefly"
        // read as the filler, no piece); the mutant: 11.19 (admitted).
        (
          'DT_briefly',
          gravy,
          20,
          addLift(
            'Add the pieces and cook until well browned all over, 5 to 7 minutes.',
            'Drain briefly on paper towels.',
          ),
          film,
        ),
        // the filler "them" (DT_them) (verify5); SYNTH: no corpus drain
        // sentence of this form (the piece "well", in S3.1's "well browned");
        // the mutant: 10.13 (the film).
        (
          'DT_them',
          gravy,
          20,
          liftAs('Drain them well on paper towels.'),
          admitted,
        ),
        // the filler "it" (DT_it) (verify5); SYNTH: no corpus drain sentence of
        // this form; the mutant: 10.13 (the film).
        (
          'DT_it',
          gravy,
          20,
          liftAs('Drain it well on paper towels.'),
          admitted,
        ),
        // the singular "towel" (DT_towels, "towels?" → "towels") (verify5);
        // SYNTH: no corpus drain sentence of this form; the mutant: 10.13 (the
        // film).
        (
          'DT_towels',
          gravy,
          20,
          liftAs('Drain the meatballs on paper towel.'),
          admitted,
        ),
        // A2 (`admits`' `_firstAfter(lifts, o, …, strict: true)` non-strict: a
        // lift-out IN h decides) (verify5); SYNTH: no corpus heat sentence of a
        // fat line holds a lift-out; the mutant: 10.13 (the film).
        (
          'A2',
          gravy,
          20,
          heatAs(
            'Transfer the sausages to a plate, then heat the oil in a large nonstick skillet over medium-high heat until shimmering.',
          ),
          admitted,
        ),
        // `_rouxFlour`'s filler "in " (RF_in) (verify5); SYNTH: 1076's real
        // S3.2 with "in" added; the mutant: 20.68 `discarded`.
        (
          'RF_in',
          broiled,
          12,
          b3(
            'Add in flour and cook, stirring constantly, until mixture is deep golden brown, 5 to 8 minutes.',
          ),
          density,
        ),
        // the unit "teaspoons?" (RF_tsp) (verify5); SYNTH: 1076's real S3.2
        // with "2 teaspoons" added; the mutant: 20.68 `discarded`.
        (
          'RF_tsp',
          broiled,
          12,
          b3(
            'Add 2 teaspoons flour and cook, stirring constantly, until mixture is deep golden brown, 5 to 8 minutes.',
          ),
          density,
        ),
        // the unit "tablespoons?" (RF_tbsp) (verify5); 0206-crunchy-baked-pork-
        // chops.yaml; the mutant: 20.68 `discarded`.
        (
          'RF_tbsp',
          broiled,
          12,
          b3(
            'In a second pie plate, whisk the egg whites and mustard together; add the remaining 6 tablespoons flour and whisk until almost smooth, with pea-sized lumps remaining.',
          ),
          density,
        ),
        // AF_class_d / AF_optdel_placesd (`_addsFood`'s "placed") (verify5);
        // 0131-spice-rubbed-picnic-chicken.yaml; the mutant: 11.19 (admitted).
        (
          'AF_placed',
          gravy,
          20,
          before(
            'If desired, secure the skin of each breast piece with two or three toothpicks placed near the edges of the skin.',
          ),
          film,
        ),
        // AF_class_s ("places") (verify5); 0510-goi-cuo-n-vietnamese-summer-
        // rolls.yaml; the mutant: 11.19 (admitted).
        (
          'AF_places',
          gravy,
          20,
          before(
            '(Leftovers can be wrapped tightly and refrigerated for up to 24 hours, but wrappers will become chewier and may break in places.)',
          ),
          film,
        ),
        // AF_class_d2 / AF_optdel_arrangesd ("arranged") (verify5); 0632-jerk-
        // chicken.yaml; the mutant: 11.19 (admitted).
        (
          'AF_arranged',
          gravy,
          20,
          before(
            'When top coals are partially covered with ash, pour evenly over unlit briquettes, keeping coals arranged over half of grill.',
          ),
          film,
        ),
        // AF_class_s2 ("arranges") (verify5); SYNTH: 1123-briam's real "Arrange
        // zucchini in single layer." with "Arrange" → "Arranges" (no corpus
        // sentence holds "arranges"); the mutant: 11.19 (admitted).
        (
          'AF_arranges',
          gravy,
          20,
          before('Arranges zucchini in single layer.'),
          film,
        ),
        // AF_class_d3 / AF_optdel_sprinklesd ("sprinkled") (verify5);
        // 1168-milk-chocolate-cremeux-tart.yaml; the mutant: 11.19 (admitted).
        (
          'AF_sprinkled',
          gravy,
          20,
          before(
            '(Dough scraps can be sprinkled with sugar and baked as cook’s treat.)',
          ),
          film,
        ),
        // AF_class_s3 ("sprinkles") (verify5); SYNTH: 1123-briam's real
        // "Sprinkle parsley over top and serve." with "Sprinkle" → "Sprinkles"
        // (no corpus sentence holds "sprinkles"); the mutant: 11.19 (admitted).
        (
          'AF_sprinkles',
          gravy,
          20,
          before('Sprinkles parsley over top and serve.'),
          film,
        ),
        // AF_optdel_adds ("adds") (verify5); SYNTH: 0542-mu-shu-pork's real
        // "Add pork mixture." with "Add" → "Adds" (no corpus sentence holds
        // "adds"); the mutant: 11.19 (admitted).
        (
          'AF_adds',
          gravy,
          20,
          before('Adds pork mixture.'),
          film,
        ),
        // AV_alt_pan (`_anotherVessel`'s "pan") (verify5); 0136-crisp-skinned-
        // roast-chicken.yaml; the mutant: 10.13 (the film).
        (
          'AV_pan',
          gravy,
          20,
          after('Place the foil loosely in a large roasting pan.'),
          admitted,
        ),
        // AV_alt_saucepan ("saucepan") (verify5); SYNTH: S3.0's "large nonstick
        // skillet" → "large saucepan" (the fry vessel) and 0238's real "Melt 1
        // tablespoon of the butter in an 8-inch skillet over medium-low heat."
        // with the vessel "a small saucepan" after the lift-out; the mutant:
        // 10.13 (the film).
        (
          'AV_saucepan',
          gravy,
          20,
          vesselAfter(
            'large saucepan',
            'Melt 1 tablespoon of the butter in a small saucepan over medium-low heat.',
          ),
          admitted,
        ),
        // AV_alt_dutchoven ("dutch oven") (verify5); SYNTH: S3.0's "large
        // nonstick skillet" → "large Dutch oven" (the fry vessel) and 0238's
        // real "Melt 1 tablespoon of the butter in an 8-inch skillet over
        // medium-low heat." with the vessel "a small Dutch oven" after the
        // lift-out; the mutant: 10.13 (the film).
        (
          'AV_dutchoven',
          gravy,
          20,
          vesselAfter(
            'large Dutch oven',
            'Melt 1 tablespoon of the butter in a small Dutch oven over medium-low heat.',
          ),
          admitted,
        ),
        // AV_alt_wok ("wok") (verify5); SYNTH: S3.0's "large nonstick skillet"
        // → "large wok" (the fry vessel) and 0238's real "Melt 1 tablespoon of
        // the butter in an 8-inch skillet over medium-low heat." with the
        // vessel "a small wok" after the lift-out; the mutant: 10.13 (the
        // film).
        (
          'AV_wok',
          gravy,
          20,
          vesselAfter(
            'large wok',
            'Melt 1 tablespoon of the butter in a small wok over medium-low heat.',
          ),
          admitted,
        ),
        // AV_alt_griddle ("griddle") (verify5); SYNTH: S3.0's "large nonstick
        // skillet" → "large griddle" (the fry vessel) and 0238's real "Melt 1
        // tablespoon of the butter in an 8-inch skillet over medium-low heat."
        // with the vessel "a small griddle" after the lift-out; the mutant:
        // 10.13 (the film).
        (
          'AV_griddle',
          gravy,
          20,
          vesselAfter(
            'large griddle',
            'Melt 1 tablespoon of the butter in a small griddle over medium-low heat.',
          ),
          admitted,
        ),
        // AV_alt_pot ("pot") (verify5); SYNTH: S3.0's "large nonstick skillet"
        // → "large pot" (the fry vessel) and 0238's real "Melt 1 tablespoon of
        // the butter in an 8-inch skillet over medium-low heat." with the
        // vessel "a small pot" after the lift-out, then closer2's plain pour-
        // off with "skillet" → "pot" (0351's S3.5 "Return the pot …" cooks in
        // the fry pot: the discard first); the mutant: 10.13 (the film).
        (
          'AV_pot',
          gravy,
          20,
          vesselAfter(
            'large pot',
            'Melt 1 tablespoon of the butter in a small pot over medium-low heat. Pour off and discard fat in pot.',
          ),
          admitted,
        ),
        // AV_bound_Qw03Q (the run {0,3}? → {0,2}?) (verify5); SYNTH: 0238's
        // real sentence with "an 8-inch" → "another large heavy 8-inch" (three
        // words between); the mutant: 10.13 (the film).
        (
          'AV_bound3',
          gravy,
          20,
          after(
            'Melt 1 tablespoon of the butter in another large heavy 8-inch skillet over medium-low heat.',
          ),
          admitted,
        ),
        // AV_class_endash (the run's "–") (verify5); SYNTH: 0238's real
        // sentence with "an 8-inch" → "a heavy–bottomed" (no corpus sentence
        // introduces a vessel with an en-dash word); the mutant: 10.13 (the
        // film).
        (
          'AV_endash',
          gravy,
          20,
          after(
            'Melt 1 tablespoon of the butter in a heavy–bottomed skillet over medium-low heat.',
          ),
          admitted,
        ),
        // CP_bound_Qaz02 (the lead-in run {0,2} → {0,1}: "turn off heat,")
        // (verify5); 0005-avgolemono-greek-chicken-and-rice-soup-with-egg-and-
        // lemon.yaml; the mutant: 11.19 (admitted).
        (
          'CP_bound2',
          gravy,
          20,
          after(
            'Turn off heat, add chicken, cover, and let sit for 15 minutes.',
          ),
          film,
        ),
        // CP_class_hyphen (the lead-in run's "-": "re-cover") (verify5); SYNTH:
        // 0673-modern-cauliflower-gratin's real "Re-cover pot, reduce heat to
        // low, …" with "pot" → "skillet" (the fry vessel); the mutant: 11.19
        // (admitted).
        (
          'CP_hyphen1',
          gravy,
          20,
          after(
            'Re-cover skillet, reduce heat to low, and continue to cook stem mixture until very soft, about 10 minutes longer.',
          ),
          film,
        ),
        // CP_class_hyphen2 (the lead-in word's "-": "pan-fry,") (verify5);
        // 0506-chinese-pork-dumplings.yaml; the mutant: 11.19 (admitted).
        (
          'CP_hyphen2',
          gravy,
          20,
          after(
            'To pan-fry, increase water to ⅔ cup and covered cooking time to 8 minutes.',
          ),
          film,
        ),
        // CP_optdel_X (the lead-in's "\(?") (verify5); SYNTH: 0306-meatloaf-
        // with-brown-sugarketchup-glaze's real "(If necessary, add more milk, …
        // no longer sticks.)" with the period moved outside the parenthesis (as
        // written, ".)" ends no sentence and it joins S3.3's "the sauce"); the
        // mutant: 11.19 (admitted).
        (
          'CP_paren',
          gravy,
          20,
          after(
            '(If necessary, add more milk, a couple of tablespoons at a time, until the mixture no longer sticks).',
          ),
          film,
        ),
        // DT_class_hyphen (the piece word's "-") (verify5); SYNTH: no corpus
        // drain sentence names a hyphenated piece (0351's S3.1 adds it); the
        // mutant: 10.13 (the film).
        (
          'DT_hyphen',
          gravy,
          20,
          addLift(
            'Add the short-ribs and cook until well browned all over, 5 to 7 minutes.',
            'Drain the short-ribs on paper towels.',
          ),
          admitted,
        ),
        // DT_optreq_QQthebrieflythemit (the filler absent) (verify5); SYNTH: no
        // corpus drain sentence of this form; the mutant: 10.13 (the film).
        (
          'DT_nofiller',
          gravy,
          20,
          liftAs('Drain meatballs on paper towels.'),
          admitted,
        ),
        // DT_stardel_wS ("drain\w*": "draining") (verify5); SYNTH: no corpus
        // drain sentence of this form; the mutant: 10.13 (the film).
        (
          'DT_draining',
          gravy,
          20,
          liftAs('Draining the meatballs on paper towels, set them aside.'),
          admitted,
        ),
        // FF_class_hyphen (the word's "-") (verify5); SYNTH: no corpus add
        // sentence names a fat after a hyphenated word; the mutant: 10.13 (the
        // film).
        (
          'FF_hyphen',
          gravy,
          20,
          before('Add 2 tablespoons garlic-herb butter to the skillet.'),
          admitted,
        ),
        // FF_stardel_sS (the amount's "\s*": a no-break space) (verify5);
        // SYNTH: a no-break space between the amount and its unit (no corpus
        // sentence holds one: 0 of 22,700); the mutant: 10.13 (the film).
        (
          'FF_nbsp',
          gravy,
          20,
          before('Add 2\u00a0tablespoons butter to the skillet.'),
          admitted,
        ),
        // FF_optreq_teaspoons (the singular "teaspoon") (verify5); SYNTH:
        // 1124-blackened-chicken's real sentence with "tablespoon" →
        // "teaspoon"; the mutant: 10.13 (the film).
        (
          'FF_teaspoon',
          gravy,
          20,
          before(
            'Add 1 teaspoon butter to skillet, then tilt skillet or spread butter with flexible spatula until it coats skillet evenly.',
          ),
          admitted,
        ),
        // FF_optdel_cups (the plural "cups") (verify5); SYNTH: FF_cups'
        // sentence with "½ cup" → "2 cups"; the mutant: 10.13 (the film).
        (
          'FF_cups2',
          gravy,
          20,
          before('Add 2 cups butter.'),
          admitted,
        ),
        // LO_bound_QQthehalfofalleach (the fillers {0,5} → {0,4}) (verify5);
        // SYNTH: five fillers before "meatballs"; the mutant: 10.13 (the film).
        (
          'LO_five',
          gravy,
          20,
          liftAs(
            'Transfer half of the cooked seared meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LO_class_hyphen (the piece word's "-") (verify5); SYNTH: "bone-in"
        // lifted, "the bone pieces" added (R3 refuses the piece "bone-in"; the
        // mutant reads "bone"); the mutant: 11.19 (admitted).
        (
          'LO_hyphen',
          gravy,
          20,
          addLift(
            'Add the bone pieces and cook until well browned all over, 5 to 7 minutes.',
            'Transfer the bone-in pieces to a paper towel–lined plate to drain briefly.',
          ),
          film,
        ),
        // LO_class_hyphen2 (the second word's "-") (verify5); SYNTH: a
        // hyphenated word starting "mixture" after the piece (the mutant reads
        // "mixture": no piece); the mutant: 10.13 (the film).
        (
          'LO_hyphen2',
          gravy,
          20,
          liftAs(
            'Transfer the meatballs mixture-free to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LO_optreq_Qaz (the second word absent) (verify5); SYNTH: the piece
        // followed by a comma; the mutant: 10.13 (the film).
        (
          'LO_comma',
          gravy,
          20,
          liftAs(
            'Transfer meatballs, in batches, to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LT_alt_a ("a ") (verify5); SYNTH: four words between "a" and the
        // plate; the mutant: 10.13 (the film).
        (
          'LT_a',
          gravy,
          20,
          liftAs(
            'Transfer the meatballs to a large, rimmed, oiled, foil–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LT_alt_an ("an ") (verify5); SYNTH: four words between "an" and the
        // plate; the mutant: 10.13 (the film).
        (
          'LT_an',
          gravy,
          20,
          liftAs(
            'Transfer the meatballs to an extra-large, rimmed, oiled, foil–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LT_class_endash (the run's "–") (verify5); SYNTH: an en-dash word
        // other than "paper towel–lined" (whose "paper towel" is a destination
        // itself); the mutant: 10.13 (the film).
        (
          'LT_endash',
          gravy,
          20,
          liftAs(
            'Transfer the meatballs to a foil–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LT_class_hyphen (the run's "-") (verify5); SYNTH: 0115-chicken-katsu-
        // crispy-pan-fried-chicken-cutlets's real "Transfer cutlets to towel-
        // lined rack …" with the piece 0351's; the mutant: 10.13 (the film).
        (
          'LT_hyphen',
          gravy,
          20,
          liftAs(
            'Transfer the meatballs to a towel-lined rack to drain briefly.',
          ),
          admitted,
        ),
        // LT_optdel_X (the run's ",?") (verify5); SYNTH: 0043-pan-seared-
        // scallops-with-wilted-spinach-watercress-and-orange-salad's real
        // "Transfer all the scallops to a clean, large plate; set aside." with
        // the piece 0351's; the mutant: 10.13 (the film).
        (
          'LT_comma',
          gravy,
          20,
          liftAs(
            'Transfer all the meatballs to a clean, large plate; set aside.',
          ),
          admitted,
        ),
        // LT_optreq_towels (the singular "paper towel") (verify5); SYNTH: no
        // corpus lift-out to a single paper towel; the mutant: 10.13 (the
        // film).
        (
          'LT_towel',
          gravy,
          20,
          liftAs('Transfer the meatballs to a paper towel to drain briefly.'),
          admitted,
        ),
        // LV_alt_s (`_liftVerb`'s "transfers") and LV_optdel_Qsredring (its
        // suffix group) (verify5); SYNTH: 0351's real S3.2 with "Transfer" →
        // "Transfers" (no corpus lift-out of a piece holds the form); the
        // mutant: 10.13 (the film).
        (
          'LV_transfers',
          gravy,
          20,
          liftAs(
            'Transfers the meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LV_alt_red (`_liftVerb`'s "transferred") and LV_optdel_Qsredring (its
        // suffix group) (verify5); SYNTH: 0351's real S3.2 with "Transfer" →
        // "Transferred" (no corpus lift-out of a piece holds the form); the
        // mutant: 10.13 (the film).
        (
          'LV_transferred',
          gravy,
          20,
          liftAs(
            'Transferred the meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LV_alt_ring (`_liftVerb`'s "transferring") and LV_optdel_Qsredring
        // (its suffix group) (verify5); SYNTH: 0351's real S3.2 with "Transfer"
        // → "Transferring" (no corpus lift-out of a piece holds the form); the
        // mutant: 10.13 (the film).
        (
          'LV_transferring',
          gravy,
          20,
          liftAs(
            'Transferring the meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LV_alt_es (`_liftVerb`'s "removes") (verify5); SYNTH: 0351's real
        // S3.2 with "Transfer" → "Removes" (no corpus lift-out of a piece holds
        // the form); the mutant: 10.13 (the film).
        (
          'LV_removes',
          gravy,
          20,
          liftAs(
            'Removes the meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LV_alt_ed (`_liftVerb`'s "removed") (verify5); SYNTH: 0351's real
        // S3.2 with "Transfer" → "Removed" (no corpus lift-out of a piece holds
        // the form); the mutant: 10.13 (the film).
        (
          'LV_removed',
          gravy,
          20,
          liftAs(
            'Removed the meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LV_alt_ing (`_liftVerb`'s "removing") (verify5); SYNTH: 0351's real
        // S3.2 with "Transfer" → "Removing" (no corpus lift-out of a piece
        // holds the form); the mutant: 10.13 (the film).
        (
          'LV_removing',
          gravy,
          20,
          liftAs(
            'Removing the meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LV_alt_es2 (`_liftVerb`'s "moves") (verify5); SYNTH: 0351's real S3.2
        // with "Transfer" → "Moves" (no corpus lift-out of a piece holds the
        // form); the mutant: 10.13 (the film).
        (
          'LV_moves',
          gravy,
          20,
          liftAs(
            'Moves the meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LV_alt_ed2 (`_liftVerb`'s "moved") (verify5); SYNTH: 0351's real S3.2
        // with "Transfer" → "Moved" (no corpus lift-out of a piece holds the
        // form); the mutant: 10.13 (the film).
        (
          'LV_moved',
          gravy,
          20,
          liftAs(
            'Moved the meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LV_alt_ing2 (`_liftVerb`'s "moving") (verify5); SYNTH: 0351's real
        // S3.2 with "Transfer" → "Moving" (no corpus lift-out of a piece holds
        // the form); the mutant: 10.13 (the film).
        (
          'LV_moving',
          gravy,
          20,
          liftAs(
            'Moving the meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LV_alt_s2 (`_liftVerb`'s "lifts") and LV_optdel_Qseding (its suffix
        // group) (verify5); SYNTH: 0351's real S3.2 with "Transfer" → "Lifts"
        // (no corpus lift-out of a piece holds the form); the mutant: 10.13
        // (the film).
        (
          'LV_lifts',
          gravy,
          20,
          liftAs(
            'Lifts the meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LV_alt_ed3 (`_liftVerb`'s "lifted") and LV_optdel_Qseding (its suffix
        // group) (verify5); SYNTH: 0351's real S3.2 with "Transfer" → "Lifted"
        // (no corpus lift-out of a piece holds the form); the mutant: 10.13
        // (the film).
        (
          'LV_lifted',
          gravy,
          20,
          liftAs(
            'Lifted the meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LV_alt_ing3 (`_liftVerb`'s "lifting") and LV_optdel_Qseding (its
        // suffix group) (verify5); SYNTH: 0351's real S3.2 with "Transfer" →
        // "Lifting" (no corpus lift-out of a piece holds the form); the mutant:
        // 10.13 (the film).
        (
          'LV_lifting',
          gravy,
          20,
          liftAs(
            'Lifting the meatballs to a paper towel–lined plate to drain briefly.',
          ),
          admitted,
        ),
        // LN_drainnp (the drain's not-a-piece object) (verify5); SYNTH:
        // "everything" added and drained; the mutant: 11.19 (admitted).
        (
          'LN_drainnp',
          gravy,
          20,
          addLift(
            'Add everything and cook until well browned all over, 5 to 7 minutes.',
            'Drain everything on paper towels.',
          ),
          film,
        ),
        // LN_segment (the segment cut at the next lift verb) (verify5); SYNTH:
        // two lift verbs, the first without a destination; the mutant: 10.13
        // (the film).
        (
          'LN_segment',
          gravy,
          20,
          liftAs(
            'Remove the onions and transfer the meatballs to a paper towel–lined plate.',
          ),
          admitted,
        ),
        // LN_slottedT (the slotted-spoon lift's "transfer") (verify5); SYNTH:
        // 0281-spanish-style-garlic-shrimp's real "Using a slotted spoon,
        // remove the smashed garlic from the skillet and discard." with the
        // piece 0351's, "and discard" dropped; the mutant: 11.19 (admitted).
        (
          'LN_slotted',
          gravy,
          20,
          liftAs(
            'Using a slotted spoon, remove the meatballs from the skillet.',
          ),
          film,
        ),
        // PR_class_X (the run's "." in "[^.;]") (verify5); SYNTH: a decimal
        // amount (the run stops at its period; the mutant crosses it); the
        // mutant: 10.13 (the film).
        (
          'PR_period',
          gravy,
          20,
          after('Reserve 1.5 tablespoons fat.'),
          admitted,
        ),
        // PR_class_semi (the run's ";") (verify5); SYNTH: "reserve" and "fat"
        // across a semicolon; the mutant: 10.13 (the film).
        (
          'PR_semi',
          gravy,
          20,
          after('Reserve the skillet; pour the fat into a bowl.'),
          admitted,
        ),
        // PR_bound_040Q (the run {0,40}? → {0,39}?) (verify5); SYNTH: 0143's
        // real "Reserve 3 tablespoons fat" with words added — the run " the
        // remaining three tablespoons of the " is exactly 40 characters; the
        // mutant: 11.19 (admitted).
        (
          'PR_forty',
          gravy,
          20,
          after('Reserve the remaining three tablespoons of the fat.'),
          film,
        ),
        // PR_stardel_wS3 ("reserve\w*": "reserved") (verify5); SYNTH: no corpus
        // sentence keeps "the reserved fat" after a fry (0265's real "reserving
        // ½ cup oil" is no "reserve\w*" form: "reserv-ing"); the mutant: 11.19
        // (admitted).
        (
          'PR_reserved',
          gravy,
          20,
          after('Keep the reserved fat in the skillet.'),
          film,
        ),
        // PO_alt_spoon ("spoon") (verify5); 1070-irish-stew-with-carrots-and-
        // turnips.yaml; the mutant: 10.13 (the film).
        (
          'PO_spoon',
          gravy,
          20,
          after(
            'If serving immediately, stir carrots and turnips into liquid, wait 5 minutes, and spoon off any fat that rises to top.',
          ),
          admitted,
        ),
        // PO_alt_drain ("drain") (verify5); SYNTH: closer2's "Pour off and
        // discard fat in skillet." with "Pour" → "Drain", then 0351's real
        // S1.2; the mutant: 10.13 (the film).
        (
          'PO_drain',
          gravy,
          20,
          after(
            'Drain off and discard fat in skillet. Stir in the garlic and cook until fragrant, about 30 seconds.',
          ),
          admitted,
        ),
        // PO_alt_grease ("grease") (verify5); SYNTH: closer2's pour-off with
        // "fat" → "grease", then 0351's real S1.2; the mutant: 10.13 (the
        // film).
        (
          'PO_grease',
          gravy,
          20,
          after(
            'Pour off and discard grease in skillet. Stir in the garlic and cook until fragrant, about 30 seconds.',
          ),
          admitted,
        ),
        // PO_stardel_wS ("pour\w*": "pouring") (verify5); SYNTH: "pouring off
        // the fat", then 0351's real S1.2; the mutant: 10.13 (the film).
        (
          'PO_pouring',
          gravy,
          20,
          after(
            'Pouring off the fat, discard it from the skillet. Stir in the garlic and cook until fragrant, about 30 seconds.',
          ),
          admitted,
        ),
        // RF_optreq_tablespoons (the singular "tablespoon") (verify5); SYNTH:
        // 1076's real S3.2 with "1 tablespoon" added; the mutant: 20.68
        // `discarded`.
        (
          'RF_tablespoon',
          broiled,
          12,
          b3(
            'Add 1 tablespoon flour and cook, stirring constantly, until mixture is deep golden brown, 5 to 8 minutes.',
          ),
          density,
        ),
        // RF_optreq_teaspoons (the singular "teaspoon") (verify5); SYNTH:
        // 1076's real S3.2 with "1 teaspoon" added; the mutant: 20.68
        // `discarded`.
        (
          'RF_teaspoon',
          broiled,
          12,
          b3(
            'Add 1 teaspoon flour and cook, stirring constantly, until mixture is deep golden brown, 5 to 8 minutes.',
          ),
          density,
        ),
        // RF_optreq_cups (the singular "cup") (verify5); 0951-cherry-
        // clafouti.yaml; the mutant: 20.68 `discarded`.
        (
          'RF_cup',
          broiled,
          12,
          b3('Whisk in remaining ½ cup flour until smooth.'),
          density,
        ),
        // RF_stardel_sS (the amount's "\s*": a no-break space) (verify5);
        // SYNTH: 1076's real S3.2 with "2" + a no-break space + "tablespoons"
        // added (no corpus sentence holds one); the mutant: 20.68 `discarded`.
        (
          'RF_nbsp',
          broiled,
          12,
          b3(
            'Add 2\u00a0tablespoons flour and cook, stirring constantly, until mixture is deep golden brown, 5 to 8 minutes.',
          ),
          density,
        ),
        // RF_stardel_wS ("add\w*": "adding") (verify5); 0806-pita-bread.yaml;
        // the mutant: 20.68 `discarded`.
        (
          'RF_adding',
          broiled,
          12,
          b3(
            'Using rolling pin, gently roll into 7-inch circle, adding flour as necessary to prevent sticking.',
          ),
          density,
        ),
        // PW_optreq_pieces (the singular "piece") (verify5); SYNTH: 0351's S3.1
        // with "the meatballs" → "the piece"; the mutant: 10.13 (the film).
        (
          'PW_piece',
          gravy,
          20,
          addAs(
            'Add the piece and cook until well browned all over, 5 to 7 minutes.',
          ),
          admitted,
        ),
        // A21 (verify5 D5) the FIRST shallow line's group
        // (`shallow.reduce(min)`): P = the counted rows before |1 (the
        // meatloaf mix 453.59 g) → 6.89 g U, split by whole → 3.45 g on
        // each oil line; STATED synthesized (above); the mutant
        // (`reduce(max)`: P before |3, + the prosciutto, 510.29 g): 3.88 g.
        (
          'A21_1',
          twoFry,
          1,
          [s3, s3],
          (2710186, 'auto', null, 'discarded', '3.45', '31.05'),
        ),
        (
          'A21_3',
          twoFry,
          3,
          [s3, s3],
          (2710186, 'auto', null, 'discarded', '3.45', '31.05'),
        ),
        // A23 (verify5 D5) the plan's "an amount line weighed to nothing
        // is no entry" (`lines[k].amounts.isNotEmpty && (whole ?? 0) <=
        // 0`): |20 "1 bottle olive oil, for pan-frying" is a shallow line
        // (Q2 b's label) the engine weighs to nothing — the engine's row,
        // grams null; STATED synthesized (above); the mutant (the term
        // off): 11.19 g `discarded` (no whole to cap at).
        ('A23', bottled, 20, t, (2710186, 'auto', null, null, null, 'null')),
        // PL_groupOf (the screen) `_groupOf`'s bound (`i < end`): |20 opens
        // its group, so P is empty — no uptake, no plan entry, the engine's
        // own row; STATED synthesized (above); the mutant (`i <= end`: the
        // group before) reads |10–|19: 11.19 g `discarded`.
        (
          'PL_groupOf',
          split20,
          20,
          t,
          (2710186, 'auto', null, 'portion', '112.00', '1008.00'),
        ),
        // PL_splitU (the screen) the plan's equal shares beside an
        // amount-less line (`uptake / pans.length`): U 6.89 g in equal
        // shares over |1 and |3; STATED synthesized (above); the mutant
        // (`uptake`): each 6.89 g.
        (
          'PL_splitU',
          twoLabelled,
          1,
          [s3, s3],
          (2710180, 'auto', null, 'discarded', '3.45', '31.05'),
        ),
        // closer6 (verify6 D1) R1's every-mention clause: |20 the butter
        // line, S3.0 "heat the butter in …" and a NON-heating second
        // mention appended ("Stir in the butter.", SYNTH) — R1 refuses
        // (not every mention heated): the engine's own row, by density,
        // no film (the browning scan keeps |0 alone); the mutant
        // (`every` → `any`): admitted, 13.79 `discarded`.
        (
          'v6_O46',
          buttered,
          20,
          g3(
            '${s3.replaceFirst('heat the oil in', 'heat the butter in')} Stir in the butter.',
          ),
          (173430, 'auto', null, 'density', '56.72', '406.70'),
        ),
        // R1's FIRST mention: a second HEATING mention in another vessel
        // after the lift-out ("Melt the butter in a large saucepan.",
        // SYNTH) — h is the first, admitted 13.79; the mutant (`first` →
        // `last`) reads the saucepan's: 12.49 (the film).
        (
          'v6_O47',
          buttered,
          20,
          g3(
            s3
                .replaceFirst('heat the oil in', 'heat the butter in')
                .replaceFirst(
                  lift,
                  '${lift}Melt the butter in a large saucepan. ',
                ),
          ),
          (173430, 'auto', null, 'discarded', '13.79', '98.87'),
        ),
        // closer6 (verify6 D2) R3's heat-clause null branch: S3.0 a
        // `_repeatWith` heat naming no pan oil ("… repeat with remaining
        // 2 batches and the oil in the pan, adding the onions.", SYNTH) —
        // the whole sentence is cut, the onions never a piece: admitted;
        // the mutant (`''` → `s`): 10.13 (the film).
        (
          'v6_O2',
          gravy,
          20,
          heatAs(
            'When the sauce is 30 minutes from being done, repeat with remaining 2 batches and the oil in the pan, adding the onions.',
          ),
          admitted,
        ),
        // closer6 (verify6 D3) R5's discard `now == 1`: after the
        // lift-out 0142's real "Pour off and discard fat in skillet." with
        // skillet → pot (one word, SYNTH) then 0310's real "Return the
        // skillet to high heat; add the oil and heat until just smoking."
        // — the discard is another vessel's, the skillet reused: refused
        // (the film); the mutant (`f.discarded` alone): admitted 11.19.
        (
          'v6_O8',
          gravy,
          20,
          after(
            'Pour off and discard fat in pot. Return the skillet to high heat; add the oil and heat until just smoking.',
          ),
          film,
        ),
        // the run's `later = later || …` carry: two batch sentences
        // between two lift-outs ("Add the remaining meatballs. Cook until
        // well browned all over, 5 to 7 minutes." then S3.2 again, SYNTH)
        // — every batch precedes a later lift-out: admitted; the mutant
        // (`later = lift.contains(o)`): 10.13 (the film).
        (
          'v6_P11',
          gravy,
          20,
          g3(
            s3.replaceFirst(
              lift,
              '${lift}Add the remaining meatballs. Cook until well browned all over, 5 to 7 minutes. $lift',
            ),
          ),
          admitted,
        ),
        // closer6 (verify6 D4) the plan's lipid read through the nutrient
        // sibling: |20 retyped "½ cup extra-virgin olive oil" (STATED
        // synthesized, above) — admitted 11.19, its kcal by the sibling's
        // 884; the mutant (`r.fdcId!` alone): lipid 0, no plan entry —
        // 107.29 `portion`.
        (
          'v6_O28',
          evoo,
          20,
          t,
          (748608, 'auto', null, 'discarded', '11.19', '98.92'),
        ),
        // the plan's `sized = pans.every(…)`: the two-fry recipe with one
        // amount-less pan (STATED synthesized, above) — not every pan
        // sized, so equal shares, 3.45 / 3.45; the mutant (`any`) reads
        // the amount-less pan's `whole!` and throws.
        (
          'v6_P24_1',
          twoMixed,
          1,
          [s3, s3],
          (2710180, 'auto', null, 'discarded', '3.45', '31.05'),
        ),
        (
          'v6_P24_3',
          twoMixed,
          3,
          [s3, s3],
          (2710180, 'auto', null, 'discarded', '3.45', '31.05'),
        ),
      ]) {
        final recipe = await _compute(
          db,
          fdc,
          real.copyWith(
            id: '${real.id}-v100-c4-$tag',
            slug: '${real.slug}-v100-c4-$tag',
            steps: [
              for (final (i, text) in steps.indexed)
                RecipeStep(number: i + 1, text: text),
            ],
          ),
        );
        final got = formOf(rowIn(recipe.id, at));
        if (got != form) {
          flipped.add('$tag: $got');
        }
      }
      expect(flipped, isEmpty);
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('the three recipes per serving on the fixtures (replay: gravy 889.33 '
        '→ 890.52, spaghetti 862.32 → 884.87, broiled 686.70 → 700.46)', () {
      for (final (file, perServing) in const [
        (_gravy, '890.60'),
        (_spaghetti, '884.71'),
        (_broiled, '700.46'),
      ]) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        expect(
          (n.status, n.caloriesPerServing?.toStringAsFixed(2)),
          ('complete', perServing),
          reason: file,
        );
      }
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

    test("P11′ R0's medium term (text): the frying oils a dropped term "
        'would admit — chicken-schnitzel|7, easier-fried-chicken|10, '
        'easy-salmon-cakes|11, patatas-bravas|12 — are no shallow-fry lines. '
        'STATED EQUIVALENT by value on the corpus: the fryer block writes each '
        "medium line's entry after the merge (fix100's mutant probe: every "
        'row as the tip)', () {
      for (final (file, position) in const [
        ('0116-chicken-schnitzel.yaml', 7),
        ('0149-easier-fried-chicken.yaml', 10),
        ('0287-easy-salmon-cakes.yaml', 11),
        ('0690-patatas-bravas.yaml', 12),
      ]) {
        expect(
          shallowFryLinesOf(loadCorpusRecipe(file)),
          isNot(contains(position)),
          reason: '$file|$position',
        );
      }
    });

    test("P14 (the key, pC C6): the shallow plan reads every piece row's "
        "grams, so the M52 key does — sunday-gravy's rows and the same rows "
        "with |11 buttermilk at 61.00 g (STATED: one real row's grams "
        'halved) key apart (mutant: the ` pieces` term dropped → alike)', () {
      final gravy = recipes[_gravy]!;
      final rows = db.ingredientMatchesFor(gravy.id);
      expect(rowIn(gravy.id, 11).grams?.toStringAsFixed(2), '122.00');
      final halved = [
        for (final r in rows) r.position == 11 ? r.copyWith(grams: 61) : r,
      ];
      expect(m52KeyOf(gravy, rows), isNot(m52KeyOf(gravy, halved)));
    });

    test("P15 / P16 (the person paths): a person's typed grams on a piece "
        'move the oil — |17 meatloaf mix typed 226.80 g (STATED: half its '
        'pound), then a Confirm of |20 through the PUT: 0.015195 × 509.44 = '
        '7.74 g stored == derived == GET, a recompute writes nothing; a skip '
        'of |17 leaves 0.015195 × 282.64 = 4.29 g and a full compute after '
        'writes nothing (mutant: the reader off → 10.13)', () async {
      for (final (tag, decision, grams) in const [
        ('typed', 'typed', '7.74'),
        ('skip', 'skipped', '4.29'),
      ]) {
        final corpus = loadCorpusRecipe(_gravy);
        final recipe = await _compute(
          db,
          fdc,
          corpus.copyWith(
            id: '${corpus.id}-v100-$tag',
            slug: '${corpus.slug}-v100-$tag',
          ),
        );
        expect(
          rowIn(recipe.id, 20).grams?.toStringAsFixed(2),
          '11.19',
          reason: tag,
        );
        await applyMatchOverride(db, fdc, recipe, 17, {
          'raw': nutritionLines(recipe)[17].raw,
          if (decision == 'typed') 'grams': 226.80 else 'skipped': true,
        });
        final fresh = nutritionRecipeOf(db, recipe.id)!.recipe;
        if (decision == 'typed') {
          final line = nutritionLines(fresh)[20];
          await applyMatchOverride(db, fdc, fresh, 20, {
            'raw': line.raw,
            'confirmed': true,
          });
          final stored = rowIn(recipe.id, 20);
          final derived = (await derivedFor(
            db,
            fdc,
            fresh,
            20,
            line,
            stored,
          )).row;
          final item =
              ((await matchesBody(db, fdc, fresh))['items']! as List)
                      .cast<Map<String, Object?>>()
                      .singleWhere((i) => i['position'] == 20)['match']!
                  as Map<String, Object?>;
          for (final form in <(Object?, String?, Object?)>[
            (
              stored.status,
              stored.grams?.toStringAsFixed(2),
              stored.gramSource,
            ),
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
            expect(form, ('confirmed', grams, 'discarded'), reason: tag);
          }
          expect(item['gram_basis'], '$_basis · $_flag', reason: tag);
          List<Object?> rowsOf() => [
            for (final m in db.ingredientMatchesFor(recipe.id))
              (m.position, m.grams, m.gramSource, m.status, m.hold),
          ];
          final rows = rowsOf();
          expect(
            recomputeTotals(db, nutritionRecipeOf(db, recipe.id)!.recipe),
            isTrue,
          );
          expect(rowsOf(), rows, reason: tag);
        } else {
          expect(
            (
              rowIn(recipe.id, 20).status,
              rowIn(recipe.id, 20).grams?.toStringAsFixed(2),
              rowIn(recipe.id, 20).gramSource,
            ),
            ('auto', grams, 'discarded'),
            reason: tag,
          );
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
          expect(rowsOf(), rows, reason: tag);
          expect(db.nutritionFor(recipe.id)!.totalsJson, totals, reason: tag);
        }
      }
    });
  });

  // RULE C (the NEW reader `_shallowFryIn` inside memo:browningFat, once per
  // index; each fat line's mentions read once, `browningFatLineReads`; the
  // lift-outs once, R2 / R3–R5 once per heat sentence, R5's pan events in
  // one backward pass per fry vessel — counted `memo:panVerdict` (closer4,
  // verify4 D8): 1 on every TRUE and PIECES path, absent on QUIET (no
  // lift-out: R4 refuses before R5)). STATED synthesized (the cap-shape
  // exception): P17 — sunday-gravy's REAL |17 "1 pound meatloaf mix" and 399
  // copies of its REAL |20 "½ cup olive oil" (one group) under 120 ×
  // 10,000-character steps of its REAL S3 text — TRUE: every copy heated,
  // the meatballs added and lifted out, the skillet never reused (every copy
  // admitted; U = 0.015195 × 453.59 g split over the 399 by their wholes,
  // 0.02 g each); QUIET: S3's real "Transfer the meatballs to a paper
  // towel–lined plate to drain briefly." deleted (no lift-out: no copy
  // admitted). P17′ PIECES — 399 copies of the REAL |17 then the REAL |20
  // (the pieces' base read and keyed once a build) under the TRUE steps.
  // The counts below are the tree's, EXACTLY (fix100 cost probe); a second
  // full compute writes nothing on every shape (design C2-1: P is one base,
  // the first shallow line's group before it, no fat line — the same on
  // every compute).
  group('RULE C, the shallow-fry reader at the caps', skip: skipIfNoCorpus, () {
    const meat = '1 pound meatloaf mix';
    const oil = '½ cup olive oil';
    const transfer =
        'Transfer the meatballs to a paper towel–lined plate to drain briefly. ';
    for (final (shape, lines, loud) in [
      ('TRUE', [meat, for (var i = 1; i < capLines; i++) oil], true),
      ('QUIET', [meat, for (var i = 1; i < capLines; i++) oil], false),
      ('PIECES', [for (var i = 1; i < capLines; i++) meat, oil], true),
    ]) {
      test('$shape: the counts exact, every family bounded, within the '
          'backstop; a second compute writes nothing', () async {
        final base = loadCorpusRecipe(_gravy);
        expect(nutritionLines(base)[17].raw, meat);
        expect(nutritionLines(base)[20].raw, oil);
        final s3 = '${base.steps[3].text} ';
        expect(s3, contains(transfer));
        final r = capped(base, lines, [
          for (var i = 0; i < capSteps; i++)
            fill(loud ? s3 : s3.replaceFirst(transfer, ''), capStep),
        ]);
        final db = wp.tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        wp.saveRecipe(db, r);
        Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
        Future<void> timed(String step, Future<Object?> Function() run) async {
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
        List<Object?> rowsOf() => [
          for (final m in db.ingredientMatchesFor(r.id))
            (m.position, m.grams, m.gramSource, m.status, m.hold),
        ];
        final rows = rowsOf();
        expect(await matchAndCompute(db, provider, stored()), isNull);
        expect(rowsOf(), rows, reason: shape);
        final oils = [
          for (final m in db.ingredientMatchesFor(r.id))
            if (nutritionLines(r)[m.position].raw == oil)
              (m.grams?.toStringAsFixed(2), m.gramSource),
        ];
        expect(oils.toSet(), _capRows[shape], reason: shape);
        expect(
          shallowFryLinesOf(stored()).length,
          _capShallow[shape],
          reason: shape,
        );
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
  });
}

/// Each shape's oil rows (grams, source) after the settled compute.
const Map<String, Set<(String?, String?)>> _capRows = {
  'TRUE': {('0.02', 'discarded')},
  'QUIET': {('6.89', 'discarded'), ('112.00', 'portion')},
  'PIECES': {('112.00', 'portion')},
};

/// Each shape's shallow-fry lines.
const Map<String, int> _capShallow = {'TRUE': 399, 'QUIET': 0, 'PIECES': 1};

/// Each cap shape's counts on the tree (fix100 cost probe; the process-wide
/// `names` aside).
const Map<String, Map<String, int>> _capCounts = {
  'TRUE compute': {
    'indexes': 1,
    'memo:skinSentences': 1,
    'allSentences': 1,
    'lower': 1,
    'sentences': 13800,
    'skinScans': 2,
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
    'words': 216600,
    'memo:naming': 2,
    'memo:strainAt': 1,
    'memo:savesRemainder': 1,
    'memo:setAsideLine': 1,
    'memo:measuresOut': 1,
    'memo:reservedWhole': 1,
    'memo:discards': 1,
    'memo:oilOwners': 1,
    'memo:shallowFries': 1,
    'memo:fryVerbAt': 1,
    'memo:fries': 1,
    'memo:reservedUse': 1,
    'memo:baconPan': 1,
    'memo:baconKept': 1,
    'memo:pourOffFat': 1,
    'memo:dips': 1,
    'memo:leftInBowl': 1,
    'memo:keptSolids': 1,
    'memo:browningFat': 1,
    // RE-PIN (M97 batch, v100; closer4 — verify4 D8): R5's per-vessel
    // pan-event pass, now counted — one fry vessel ("skillet") built once
    // for every admitted line (V12, rebuilt per line: 399).
    'memo:panVerdict': 1,
    'memo:panFatLines': 1,
    'browningFatLineReads': 399,
    'memo:parenthetical': 1,
  },
  'TRUE GET': {
    // RE-PIN (fix101 batch, v101, U1): + the GET offer's as-picked
    // read (`pickedMoveSource` → `_carriedIdOf`), once per line text and
    // record.
    'carriedReads': 2,
    'indexes': 1,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'lower': 1,
    'sentences': 13800,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 216600,
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
    // RE-PIN (M97 batch, v100; closer4 — verify4 D8): R5's per-vessel
    // pan-event pass, now counted — one fry vessel ("skillet") built once
    // for every admitted line (V12, rebuilt per line: 399).
    'memo:panVerdict': 1,
    'memo:oilOwners': 1,
    'memo:shallowFries': 1,
    'memo:fryVerbAt': 1,
    'memo:fries': 1,
    'allSentences': 1,
    'memo:reservedUse': 1,
    'browningFatLineReads': 399,
    'memo:parenthetical': 1,
    'memo:skinSentences': 1,
    'skinScans': 2,
    'memo:liftedFromMarinade': 1,
    'memo:baconPan': 1,
    'memo:baconKept': 1,
    'memo:pourOffFat': 1,
    'm52Keys': 1,
    'memo:coatShape': 1,
    'memo:mayHoldCoat': 1,
  },
  'TRUE recompute': {
    'indexes': 1,
    'memo:dips': 1,
    'lower': 1,
    'sentences': 13800,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'memo:pourAway': 1,
    'memo:oilOwners': 1,
    'words': 216600,
    'memo:naming': 1,
    'memo:shallowFries': 1,
    'memo:fryVerbAt': 1,
    'memo:fries': 1,
    'allSentences': 1,
    'memo:reservedUse': 1,
    'memo:leftInBowl': 1,
    'memo:keptSolids': 1,
    'memo:browningFat': 1,
    // RE-PIN (M97 batch, v100; closer4 — verify4 D8): R5's per-vessel
    // pan-event pass, now counted — one fry vessel ("skillet") built once
    // for every admitted line (V12, rebuilt per line: 399).
    'memo:panVerdict': 1,
    'memo:panFatLines': 1,
    'browningFatLineReads': 399,
    'memo:parenthetical': 1,
    'memo:skinSentences': 1,
    'skinScans': 1,
    'memo:baconPan': 1,
    'memo:baconKept': 1,
    'memo:pourOffFat': 1,
  },
  'QUIET compute': {
    'indexes': 1,
    'memo:skinSentences': 1,
    'allSentences': 1,
    'lower': 1,
    'sentences': 12720,
    'skinScans': 2,
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
    'words': 209160,
    'memo:naming': 2,
    'memo:strainAt': 1,
    'memo:savesRemainder': 1,
    'memo:setAsideLine': 1,
    'memo:measuresOut': 1,
    'memo:reservedWhole': 1,
    'memo:discards': 1,
    'memo:oilOwners': 1,
    'memo:shallowFries': 1,
    'memo:fryVerbAt': 1,
    'memo:fries': 1,
    'memo:reservedUse': 1,
    'memo:baconPan': 1,
    'memo:baconKept': 1,
    'memo:pourOffFat': 1,
    'memo:dips': 1,
    'memo:leftInBowl': 1,
    'memo:keptSolids': 1,
    'memo:browningFat': 1,
    'memo:panFatLines': 1,
    'browningFatLineReads': 399,
    'memo:parenthetical': 1,
  },
  'QUIET GET': {
    // RE-PIN (fix101 batch, v101, U1): + the GET offer's as-picked
    // read (`pickedMoveSource` → `_carriedIdOf`), once per line text and
    // record.
    'carriedReads': 2,
    'indexes': 1,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'lower': 1,
    'sentences': 12720,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 209160,
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
    'memo:oilOwners': 1,
    'memo:shallowFries': 1,
    'memo:fryVerbAt': 1,
    'memo:fries': 1,
    'allSentences': 1,
    'memo:reservedUse': 1,
    'browningFatLineReads': 399,
    'memo:parenthetical': 1,
    'memo:skinSentences': 1,
    'skinScans': 2,
    'memo:liftedFromMarinade': 1,
    'memo:baconPan': 1,
    'memo:baconKept': 1,
    'memo:pourOffFat': 1,
    'm52Keys': 1,
    'memo:coatShape': 1,
    'memo:mayHoldCoat': 1,
  },
  'QUIET recompute': {
    'indexes': 1,
    'memo:dips': 1,
    'lower': 1,
    'sentences': 12720,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'memo:pourAway': 1,
    'memo:oilOwners': 1,
    'words': 209160,
    'memo:naming': 1,
    'memo:shallowFries': 1,
    'memo:fryVerbAt': 1,
    'memo:fries': 1,
    'allSentences': 1,
    'memo:reservedUse': 1,
    'memo:leftInBowl': 1,
    'memo:keptSolids': 1,
    'memo:browningFat': 1,
    'memo:panFatLines': 1,
    'browningFatLineReads': 399,
    'memo:parenthetical': 1,
    'memo:skinSentences': 1,
    'skinScans': 1,
    'memo:baconPan': 1,
    'memo:baconKept': 1,
    'memo:pourOffFat': 1,
  },
  'PIECES compute': {
    'indexes': 1,
    'memo:skinSentences': 1,
    'allSentences': 1,
    'lower': 1,
    'sentences': 13800,
    'skinScans': 2,
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
    'words': 216600,
    'memo:naming': 2,
    'memo:strainAt': 1,
    'memo:savesRemainder': 1,
    'memo:setAsideLine': 1,
    'memo:measuresOut': 1,
    'memo:reservedWhole': 1,
    'memo:discards': 1,
    'memo:oilOwners': 1,
    'memo:shallowFries': 1,
    'memo:fryVerbAt': 1,
    'memo:fries': 1,
    'memo:reservedUse': 1,
    'memo:baconPan': 1,
    'memo:baconKept': 1,
    'memo:pourOffFat': 1,
    'memo:dips': 1,
    'memo:leftInBowl': 1,
    'memo:keptSolids': 1,
    'memo:browningFat': 1,
    // RE-PIN (M97 batch, v100; closer4 — verify4 D8): R5's per-vessel
    // pan-event pass, now counted — one fry vessel ("skillet") built once
    // for every admitted line (V12, rebuilt per line: 1 — one shallow line; TRUE kills it).
    'memo:panVerdict': 1,
    'memo:panFatLines': 1,
    'browningFatLineReads': 1,
    'memo:parenthetical': 1,
  },
  'PIECES GET': {
    // RE-PIN (fix101 batch, v101, U1): + the GET offer's as-picked
    // read (`pickedMoveSource` → `_carriedIdOf`), once per line text and
    // record.
    'carriedReads': 2,
    'indexes': 1,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'lower': 1,
    'sentences': 13800,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 216600,
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
    // RE-PIN (M97 batch, v100; closer4 — verify4 D8): R5's per-vessel
    // pan-event pass, now counted — one fry vessel ("skillet") built once
    // for every admitted line (V12, rebuilt per line: 1 — one shallow line; TRUE kills it).
    'memo:panVerdict': 1,
    'memo:oilOwners': 1,
    'memo:shallowFries': 1,
    'memo:fryVerbAt': 1,
    'memo:fries': 1,
    'allSentences': 1,
    'memo:reservedUse': 1,
    'browningFatLineReads': 1,
    'memo:parenthetical': 1,
    'memo:skinSentences': 1,
    'skinScans': 2,
    'memo:liftedFromMarinade': 1,
    'memo:baconPan': 1,
    'memo:baconKept': 1,
    'memo:pourOffFat': 1,
    'm52Keys': 1,
    'memo:coatShape': 1,
    'memo:mayHoldCoat': 1,
  },
  'PIECES recompute': {
    'indexes': 1,
    'memo:dips': 1,
    'lower': 1,
    'sentences': 13800,
    'memo:leftInBowl': 1,
    'heads': 1,
    'memo:keptSolids': 1,
    'memo:browningFat': 1,
    // RE-PIN (M97 batch, v100; closer4 — verify4 D8): R5's per-vessel
    // pan-event pass, now counted — one fry vessel ("skillet") built once
    // for every admitted line (V12, rebuilt per line: 1 — one shallow line; TRUE kills it).
    'memo:panVerdict': 1,
    'memo:starter': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'memo:pourAway': 1,
    'memo:oilOwners': 1,
    'words': 216600,
    'memo:naming': 1,
    'memo:shallowFries': 1,
    'memo:fryVerbAt': 1,
    'memo:fries': 1,
    'allSentences': 1,
    'memo:reservedUse': 1,
    'memo:panFatLines': 1,
    'browningFatLineReads': 1,
    'memo:parenthetical': 1,
    'memo:skinSentences': 1,
    'skinScans': 1,
    'memo:baconPan': 1,
    'memo:baconKept': 1,
    'memo:pourOffFat': 1,
  },
};
