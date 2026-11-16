// The v112 pins (batch M99, prep52 P1: poultry edible share; matcherVersion
// 98). W1-A: a whole bird whose PREP cuts it into breast pieces, thighs and
// drumsticks reads AH-102's derived 'chicken whole pieces' row (583–586),
// never the ready-to-cook yield. W1-B: a skin set aside that a later
// sentence RENDERS, strained out after, does not veto the skin trip, and a
// part-scoped skin sentence trips a whole bird whose prep keeps that part.
// W1-C: a whole bird whose prep keeps its breast alone ("breast removed, …,
// and reserved; remaining chicken cut into …") in a recipe that strains the
// rest out reads 'chicken whole breast' (583–584). The W1 dependent: the
// browning-fat plan sizes classic chicken noodle soup's oil from the kept
// breast's STORED grams. Corpus-backed groups skip without SALT_CORPUS_DIR;
// every corpus read sits inside a test body (the loader never reads the
// corpus). The synthesized recipes are NEGATIVE-path inputs (the allowed
// exception), each naming its corpus source.
//
// Hand derivations (the printed weight × the share = grams; grams × the
// record's kcal per 100 g, nutrient 208 — SR 171447 215, SR 171052 119,
// FNDDS 2710180 / 2710186 900):
//   coq-au-riesling|0: 4–5 lb midpoint 4.5 × 453.59237 = 2,041.17 g ×
//     0.3811 (meat: 27×65 + 19×59 + 17×55 = 3,811 / 10⁴) = 777.89 g on
//     171052; × 1.19 = 925.69 kcal.
//   moroccan-chicken-with-olives-and-lemon|8: 3¾ lb = 1,700.97 g × 0.3811 =
//     648.24 g on 171052; × 1.19 = 771.41 kcal.
//   chicken-with-40-cloves-of-garlic|1: 1,700.97 g × 0.4399 (meat and skin:
//     27×74 + 19×70 + 17×63 = 4,399 / 10⁴) = 748.26 g on 171447; × 2.15 =
//     1,608.75 kcal.
//   classic-chicken-noodle-soup|1: 4 lb = 1,814.37 g × 0.1755 (27×65 / 10⁴)
//     = 318.42 g on 171052; × 1.19 = 378.92 kcal.
//   classic-chicken-noodle-soup|0: 0.015195 (FNDDS 2705972: 2 g oil per
//     131.62 g) × 318.42 g ÷ lipid 1.00 = 4.84 g; × 9.00 = 43.56 kcal.
// ignore_for_file: lines_longer_than_80_chars
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v26_cost_test.dart' show capLines, capStep, capSteps, ln;
import 'nutrition_v27_cost_test.dart' show tok;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _coq = '0127-coq-au-riesling.yaml';
const _moroccan = '0100-moroccan-chicken-with-olives-and-lemon.yaml';
const _forty = '0452-chicken-with-40-cloves-of-garlic.yaml';
const _classic = '0002-classic-chicken-noodle-soup.yaml';

const _pieces =
    'derived from USDA AH-102 items 583–586: the breast, thighs and drumsticks (27, 19, 17 of the carcass) × their';
const _piecesMeat =
    '$_pieces meat 65/59/55 %; the wings and back are not counted)';
const _piecesSkin =
    '$_pieces meat and skin 74/70/63 %; the wings and back are not counted)';
const _browning =
    'skimmed / poured off — only the fat the browned food keeps counted · approximation (browning fat: 1.52 g fat per 100 g of the raw chicken — USDA FNDDS 2705972 recipe: 2 g oil per 131.62 g raw chicken breast (the browned piece keeps a film; the steps skim / pour off the rest))';

/// (file, position, raw start, record, source, grams, kcal, basis).
const _moved = [
  (
    _coq,
    0,
    '1 (4- to 5-pound) whole chicken, cut into 8 pieces',
    171052,
    'weight',
    '777.89',
    '925.69',
    'from the printed weight (4–5 lb, the midpoint) × 0.38 edible · approximate ($_piecesMeat',
  ),
  (
    _moroccan,
    8,
    '1 (3½ to 4-pound) whole chicken, cut into 8 pieces',
    171052,
    'weight',
    '648.24',
    '771.41',
    'from the printed weight (3½–4 lb, the midpoint) × 0.38 edible · approximate ($_piecesMeat',
  ),
  (
    _forty,
    1,
    '1 (3½- to 4-pound) chicken, cut into 8 pieces',
    171447,
    'weight',
    '748.26',
    '1608.75',
    'from the printed weight (3½–4 lb, the midpoint) × 0.44 edible · approximate ($_piecesSkin',
  ),
  (
    _classic,
    1,
    '1 (4-pound) whole chicken, breast removed, split, and reserved',
    171052,
    'weight',
    '318.42',
    '378.92',
    'from the printed weight × 0.18 edible · approximate (derived from USDA AH-102 items 583–584: the breast, 27 of the carcass, × its meat 65 %; the rest of the bird is strained out with the stock)',
  ),
  // The W1 dependent (the ruled `_browningFatPlan` proxy, the recipe's
  // heaviest counted meat row read by its STORED grams: the kept breast).
  (
    _classic,
    0,
    '1 tablespoon vegetable oil',
    2710180,
    'discarded',
    '4.84',
    '43.56',
    _browning,
  ),
  // NOT moved (the replay's): 40-cloves|4's first mention (S1, a pie
  // plate) heats nothing, so the plan never admits it; moroccan|10 is no
  // plan row before or after (its share is below 1 at v111 already, and
  // the line is not admitted).
  (
    _forty,
    4,
    '1 tablespoon olive oil',
    2710186,
    'portion',
    '14.00',
    '126.00',
    '1 tablespoon · USDA portion',
  ),
  (
    _moroccan,
    10,
    '1 tablespoon olive oil',
    2710186,
    'portion',
    '14.00',
    '126.00',
    '1 tablespoon · USDA portion',
  ),
];

/// The class's look-alikes, unchanged (file, position, raw start, record,
/// grams, basis) — the v111 rows: a whole bird with no named pieces keeps
/// the ready-to-cook yield (m1); the skin vetoes that render nothing stand
/// (stretched, reserved, tapered).
const _unmoved = [
  (
    '0134-perfect-roast-chicken.yaml',
    2,
    '1 (3½- to 4-pound) whole chicken, giblets discarded',
    171447,
    '1035.00',
    'from the printed weight (3½–4 lb, the midpoint) × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '1076-broiled-chicken-with-gravy.yaml',
    0,
    '1 (4-pound) whole chicken, giblets and neck reserved',
    171447,
    '1104.00',
    'from the printed weight × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0176-grillroasted-boneless-turkey-breast.yaml',
    1,
    '1 (5- to 7-pound) whole bone-in turkey breast, trimmed',
    171093,
    '1817.11',
    'from the printed weight (5–7 lb, the midpoint) × 0.67 edible',
  ),
  (
    '1126-porchetta-style-turkey-breast.yaml',
    8,
    '1 (7- to 8-pound) bone-in turkey breast',
    171093,
    '2271.39',
    'from the printed weight (7–8 lb, the midpoint) × 0.67 edible',
  ),
  (
    '0125-braised-chicken-with-mustard-and-herbs.yaml',
    2,
    '1½–2 pounds chicken leg quarters, separated into drumsticks and thighs',
    172378,
    '529.41',
    'from 1 1/2–2 pound (the midpoint) × 0.67 edible',
  ),
];

final _fx = FixtureProvider(pending: {...pendingSearches, 'thyme or dried'});

void main() {
  group('v112 (M99: poultry edible share)', skip: skipIfNoCorpus, () {
    moved();
    unmoved();
  });
  synthesized();
  costs();
}

/// [r] stored and computed (its section children first).
Future<Recipe> _compute(SaltDatabase db, Recipe r) async {
  db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
  final stored = db.recipeByIdOrSlug(r.id)!.recipe;
  for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
    expect(
      await matchAndCompute(db, _fx, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }
  expect(await matchAndCompute(db, _fx, stored), isNull);
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

/// Recipes whose other lines search answers the fixtures do not hold
/// ("cracked green olives", 0125's breasts): computed with their real steps
/// and only these lines (the bird and the oil the plan would size from it).
const _onlyLines = {
  _moroccan: [8, 10],
  '0125-braised-chicken-with-mustard-and-herbs.yaml': [2],
};

/// [file] computed (whole, or its [_onlyLines]) and [position]'s index in it.
Future<(Recipe, int)> _computeAt(
  SaltDatabase db,
  String file,
  int position,
) async {
  final corpus = loadCorpusRecipe(file);
  final only = _onlyLines[file];
  if (only == null) return (await _compute(db, corpus), position);
  final lines = nutritionLines(corpus);
  return (
    await _compute(
      db,
      corpus.copyWith(
        ingredients: [
          IngredientGroup(items: [for (final k in only) lines[k]]),
        ],
      ),
    ),
    only.indexOf(position),
  );
}

SaltDatabase _db() {
  final dir = Directory.systemTemp.createTempSync('salt-v112-');
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

IngredientMatchRow _row(SaltDatabase db, String id, int position) =>
    db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

String _kcal(SaltDatabase db, IngredientMatchRow row) =>
    (kcalPer100g(knownFood(db, nutrientSiblings[row.fdcId] ?? row.fdcId!)!) *
            row.grams! /
            100)
        .toStringAsFixed(2);

/// W1-A, W1-B, W1-C and the dependent: each moved row's record, source,
/// grams, energy and basis in its real recipe on the fixtures (mutants m3,
/// m5, m8, m13 die here).
void moved() {
  for (final (file, position, raw, fdcId, source, grams, kcal, basis)
      in _moved) {
    test('$file|$position: $fdcId $grams g `$source`, $kcal kcal', () async {
      final db = _db();
      final (recipe, at) = await _computeAt(db, file, position);
      final line = nutritionLines(recipe)[at];
      expect(line.raw, startsWith(raw));
      final row = _row(db, recipe.id, at);
      expect(
        (row.fdcId, row.status, row.hold, row.gramSource),
        (fdcId, 'auto', null, source),
      );
      expect(row.grams?.toStringAsFixed(2), grams);
      expect(_kcal(db, row), kcal);
      expect(gramBasisFor(db, line, row, recipe: recipe), basis);
    });
  }
}

/// R7's negatives: the look-alikes keep their v111 rows (m1).
void unmoved() {
  for (final (file, position, raw, fdcId, grams, basis) in _unmoved) {
    test('$file|$position unchanged: $fdcId $grams g', () async {
      final db = _db();
      final (recipe, at) = await _computeAt(db, file, position);
      final line = nutritionLines(recipe)[at];
      expect(line.raw, startsWith(raw));
      final row = _row(db, recipe.id, at);
      expect((row.fdcId, row.grams?.toStringAsFixed(2)), (fdcId, grams));
      expect(gramBasisFor(db, line, row, recipe: recipe), startsWith(basis));
    });
  }
}

/// The coq-shape line (0127 line 0's prep; the line's weight 4 lb, 0002's).
const _coqShape =
    '1 (4-pound) whole chicken, cut into 8 pieces (4 breast pieces, 2 drumsticks, 2 thighs), wings and back reserved';

/// The classic-shape line (0002 line 1, as printed).
const _classicShape =
    '1 (4-pound) whole chicken, breast removed, split, and reserved; remaining chicken cut into 2-inch pieces';

/// 0127's own S1 skin-off sentence and S3 strain, as printed.
const _skinOff =
    'Remove skin from chicken breast pieces, drumsticks, and thighs and set aside.';
const _strain =
    'Strain cooking liquid through fine-mesh strainer set over large bowl, pressing on solids to extract as much liquid as possible; discard solids.';

/// A recipe of [raws] and [steps] (STATED synthesized negative-path
/// recipes: their lines and sentences are re-texts of 0127 and 0002).
Recipe _synth(List<String> raws, List<String> steps) => Recipe(
  id: 'r',
  title: 'r',
  slug: 'r',
  source: const RecipeSource(name: 'Test', type: 'book'),
  steps: [
    for (final (i, s) in steps.indexed) RecipeStep(number: i + 1, text: s),
  ],
  ingredients: [
    IngredientGroup(items: [for (final r in raws) ln(r)]),
  ],
);

/// The mutants no corpus line reaches (critique F11): corpusless.
void synthesized() {
  group('v112 synthesized negative paths (corpusless)', () {
    late FdcFood chicken;
    setUpAll(() async => chicken = (await _fx.food(171447))!);

    String grams(Recipe r) {
      final db = _db();
      final g = lineGrams(db, nutritionLines(r)[0], chicken, recipe: r)!;
      return '${g.grams.toStringAsFixed(2)} ${g.basis}';
    }

    test('the shapes read the PREP: the coq shape, the classic shape', () {
      expect(ln(_coqShape).prep, startsWith('cut into 8 pieces (4 breast'));
      expect(ln(_classicShape).prep, startsWith('breast removed, split'));
    });

    test('W1-A on a 4-lb bird: 1,814.37 g × 0.4399 = 798.14 g; ten pieces '
        'naming the WINGS keep the ready-to-cook 0.608 — 1,104.00 g (m1, '
        'm2: no corpus list names wings, critic/bird.out)', () {
      expect(
        grams(_synth([_coqShape], ['Season the chicken.'])),
        startsWith(
          '798.14 from the printed weight × 0.44 edible · approximate ($_piecesSkin',
        ),
      );
      expect(
        grams(
          _synth(
            [
              '1 (4-pound) whole chicken, cut into 10 pieces (4 breast pieces, 2 drumsticks, 2 thighs, 2 wings)',
            ],
            ['Season the chicken.'],
          ),
        ),
        '1104.00 from the printed weight × 0.61 edible (USDA ready-to-cook yield)',
      );
      // closer 1 (verify1 D1, mutant a5: wings added to `_keptPiece`): a list
      // of THREE kinds, one of them wings, is no kept-pieces list either —
      // the "no other kind" gate on its own (the ten-piece list above names
      // four kinds, so its count alone refuses it). STATED synthesized
      // negative path: 0127 line 0's list with its drumsticks re-texted as
      // wings (no corpus list names wings, critic/bird.out).
      expect(
        grams(
          _synth(
            [
              '1 (4-pound) whole chicken, cut into 8 pieces (4 breast pieces, 2 thighs, 2 wings)',
            ],
            ['Season the chicken.'],
          ),
        ),
        '1104.00 from the printed weight × 0.61 edible (USDA ready-to-cook yield)',
      );
      // The owner gate (mutants o2, o3, o4: each survived the pins above).
      // STATED synthesized negative paths, re-texts of 0127 line 0's list
      // (no corpus prep has any of the three shapes): every prep outside the
      // corpus's own shape weighs as v111 — a list that does not OPEN the
      // prep (`_cutIntoPieces`' anchor), a list of TWO kinds (the share
      // counts all three), and a piece with words after its kind
      // (`_keptPiece`'s end anchor: "2 drumsticks and 2 wings" names wings).
      for (final list in [
        'trimmed and cut into 8 pieces (4 breast pieces, 2 drumsticks, 2 thighs)',
        'cut into 6 pieces (4 breast pieces, 2 thighs)',
        'cut into 10 pieces (4 breast pieces, 2 thighs, 2 drumsticks and 2 wings)',
      ]) {
        expect(
          grams(
            _synth(
              ['1 (4-pound) whole chicken, $list'],
              ['Season the chicken.'],
            ),
          ),
          '1104.00 from the printed weight × 0.61 edible (USDA ready-to-cook yield)',
          reason: list,
        );
      }
    });

    test("W1-C only where the steps strain: the classic shape with 0127's "
        'strain 1,814.37 g × 0.1998 = 362.51 g; with no strain 1,104.00 g, '
        'and its breast-skin sentence trips nothing (m7)', () {
      const breastSkin =
          'When cool, remove the skin and bones from the breast pieces and discard.';
      final strained = _synth([_classicShape], [breastSkin, _strain]);
      expect(
        grams(strained),
        startsWith('362.51 from the printed weight × 0.20 edible'),
      );
      expect(skinDiscarded(strained, nutritionLines(strained)[0]), isTrue);
      final none = _synth([_classicShape], [breastSkin, 'Simmer the soup.']);
      expect(
        grams(none),
        '1104.00 from the printed weight × 0.61 edible (USDA ready-to-cook yield)',
      );
      expect(skinDiscarded(none, nutritionLines(none)[0]), isFalse);
      // The owner gate (mutant o5: `_breastReserved` cut after "reserved"
      // survived). STATED synthesized negative path, 0002 line 1 without its
      // "; remaining chicken cut into …" clause: nothing says the rest of the
      // bird goes to the stock, so the line weighs as v111 even where the
      // steps strain, and its breast-skin sentence trips nothing.
      final noRest = _synth(
        ['1 (4-pound) whole chicken, breast removed, split, and reserved'],
        [breastSkin, _strain],
      );
      expect(
        grams(noRest),
        '1104.00 from the printed weight × 0.61 edible (USDA ready-to-cook yield)',
      );
      expect(skinDiscarded(noRest, nutritionLines(noRest)[0]), isFalse);
    });

    test('the gates around the shapes: a pieces prep on a line that buys no '
        'whole bird (chicken parts) and on a whole TURKEY (no turkey row) '
        'weighs as the same line without it', () async {
      final turkey = (await _fx.food(171081))!;
      String on(FdcFood food, String raw) {
        final r = _synth([raw], ['Season the bird.']);
        final g = lineGrams(_db(), nutritionLines(r)[0], food, recipe: r)!;
        return '${g.grams.toStringAsFixed(2)} ${g.basis}';
      }

      const list =
          ', cut into 8 pieces (4 breast pieces, 2 drumsticks, 2 thighs)';
      for (final (food, raw) in [
        (chicken, '3 pounds bone-in chicken parts'),
        (turkey, '1 (12-pound) whole turkey'),
      ]) {
        expect(on(food, '$raw$list'), on(food, raw), reason: raw);
      }
    });

    test('W1-B: the veto is lifted only by a skin RENDERED before the '
        'strain — rendered and strained trips; rendered with no strain '
        '(m4), bacon "beginning to render" (m12) and a strain before the '
        'render stay vetoed; a wing-skin sentence trips no kept piece (m6)', () {
      bool trips(List<String> steps) {
        final r = _synth([_coqShape], steps);
        return skinDiscarded(r, nutritionLines(r)[0]);
      }

      const rendered =
          'Add chicken skin, back, and wings to pot and cook until skin is rendered, 10 to 12 minutes.';
      expect(trips([_skinOff, rendered, _strain]), isTrue);
      expect(trips([_skinOff]), isFalse);
      expect(
        trips([
          _skinOff,
          'Cook until skin is rendered; serve with the cracklings.',
        ]),
        isFalse,
      );
      expect(
        trips([
          _skinOff,
          'Cook bacon in large Dutch oven over medium-low heat, stirring occasionally, until beginning to render, 2 to 4 minutes.',
          _strain,
        ]),
        isFalse,
      );
      expect(trips([_skinOff, _strain, rendered]), isFalse);
      // A skin rendered BEFORE the sentence that sets it aside is no lift.
      expect(trips([rendered, _skinOff, _strain]), isFalse);
      // The owner gate (mutants o8, o9, o10 and the render pattern's own
      // word: each survived the pins above). STATED synthesized negative
      // paths, re-texts of 0127's S1 and S3 (no corpus recipe has any of
      // them): the LAST render must stand before the strain (o8: a skin
      // rendered again after it is not strained out); within ONE sentence
      // the order is not read, so a render that also sets the skin aside
      // (o9) and a render in the strain's own sentence (o10) lift nothing;
      // and bacon FAT that "is rendered" is no skin (the pattern's "skin").
      expect(trips([_skinOff, rendered, _strain, rendered]), isFalse);
      expect(
        trips([
          _skinOff,
          'Cook until skin is rendered and crisp; set aside for serving.',
          _strain,
        ]),
        isFalse,
      );
      expect(
        trips([
          _skinOff,
          'Cook until skin is rendered, then strain cooking liquid through fine-mesh strainer set over large bowl, pressing on solids to extract as much liquid as possible; discard solids.',
        ]),
        isFalse,
      );
      expect(
        trips([
          _skinOff,
          'Cook bacon in large Dutch oven over medium-low heat until fat is rendered, 5 to 7 minutes.',
          _strain,
        ]),
        isFalse,
      );
      // The verifier of the owner's hand edits (hv1: mutants o22, b1, b5
      // survived the pins above). STATED synthesized, re-texts of 0127's S1
      // (no corpus recipe has any of them). Negative path: a word ENDING in
      // "skin" renders no chicken skin (b1: the pattern's leading boundary).
      expect(
        trips([
          _skinOff,
          'Cook until bacon is browned and pigskin is rendered, 10 to 12 minutes.',
          _strain,
        ]),
        isFalse,
      );
      // 0127's own sentence with its three kinds RE-ORDERED and the skin
      // discarded (o22: the kept list read as 'breast' alone): `_skinPart`
      // reads the first part named right after "skin … from", and every
      // kept kind trips the line — thighs first trips as the corpus's breast
      // first does.
      const thighsFirst =
          'Remove skin from chicken thighs, drumsticks, and breast pieces and discard.';
      expect(trips([thighsFirst]), isTrue);
      // With no vetoing sentence the strain is never read (b5:
      // `_skinVetoed`'s early return, a cost gate): a discarded skin, a
      // render and a strain leave memo:strainAt uncounted.
      final noVeto = _synth([_coqShape], [thighsFirst, rendered, _strain]);
      stepIndexCounts.clear();
      expect(skinDiscarded(noVeto, nutritionLines(noVeto)[0]), isTrue);
      expect(stepIndexCounts['memo:skinSentences'], 1);
      expect(stepIndexCounts['memo:strainAt'], isNull);
      expect(trips(['Remove the skin from the wings and discard.']), isFalse);
      expect(
        trips(['Remove the skin from the breast pieces and discard.']),
        isTrue,
      );
    });

    test('the memo keys carry the kept parts: two lines of ONE item, the '
        "coq shape (kept 'breast pieces…') and the bare whole chicken (kept "
        'none), answer apart in the same recipe — a breast-skin sentence '
        'trips the first alone, and its "leaving skin on the wings" is the '
        "first's kept part alone (closer 1, verify1 D2: mutants mk, mk2)", () {
      // STATED synthesized negative path: 0127 line 0 (the coq shape) beside
      // its own bird with no prep (0002 line 1's 4-lb weight), and 0637's
      // "leaving skin on wings" form on 0127's breast pieces; no corpus
      // recipe lists one bird twice.
      const plain = '1 (4-pound) whole chicken';
      const breastSkin =
          'Remove the skin from the breast pieces, leaving skin on the wings, and discard.';
      final one = _synth([_coqShape, plain], [breastSkin]);
      final lines = nutritionLines(one);
      expect(lines[0].item, lines[1].item);
      expect(lines[1].item, isNotNull);
      expect(
        [skinDiscarded(one, lines[0]), skinDiscarded(one, lines[1])],
        [isTrue, isFalse],
      );
      final both = _synth(
        [_coqShape, plain],
        [breastSkin, 'Remove and discard the skin.'],
      );
      final bothLines = nutritionLines(both);
      expect(
        [skinKeptPart(both, bothLines[0]), skinKeptPart(both, bothLines[1])],
        ['wings', null],
      );
    });
  });
}

/// RULE C (R11) on the editor's caps (STATED synthesized: 400 distinct
/// whole-bird lines, the coq shape or the classic shape with a token in the
/// item — the v27 cost files' form — and 120 steps of 0127's S1 skin-off
/// sentence to the step cap, the true path's last step ending in a render
/// and 0127's S3 strain). Each line's skin reads (`skinDiscarded`,
/// `skinKeptPart`) and grams (`lineGrams` on fixture 171447) on one index:
/// the skin facts once per skin sentence, the strain once per index — on
/// the true path, and on the classic shape whose gate reads it — never on
/// the coq shape's quiet path; the skin scans once per line. Counts exact
/// (measured), the clock a backstop.
void costs() {
  group('v112 RULE C caps (corpusless)', () {
    late FdcFood chicken;
    setUpAll(() async => chicken = (await _fx.food(171447))!);

    List<String> stepsOf({required bool render}) {
      const full = (capStep + 1) ~/ (_skinOff.length + 1);
      final step = List.filled(full, _skinOff).join(' ');
      final last = [
        ...List.filled(full - 4, _skinOff),
        if (render) 'Cook until bacon is browned and skin is rendered.',
        _strain,
      ].join(' ');
      return [...List.filled(capSteps - 1, step), last];
    }

    for (final (shape, line, render, strainReads, trips) in [
      ('coq true', _coqShape, true, 1, true),
      ('coq quiet', _coqShape, false, null, false),
      ('classic', _classicShape, false, 1, false),
    ]) {
      test('$shape: memo:skinSentences 1, memo:strainAt $strainReads, '
          'skinScans $capLines', () {
        final raws = [
          for (var i = 0; i < capLines; i++)
            line.replaceFirst('whole chicken', 'whole chicken ${tok(i)}'),
        ];
        final r = _synth(raws, stepsOf(render: render));
        final skinSentences = [
          for (final s in r.steps) ...s.text.split(RegExp(r'(?<=\.)\s+')),
        ].where((s) => s.toLowerCase().contains(RegExp(r'\bskin\b'))).length;
        final db = _db();
        stepIndexCounts.clear();
        final sw = Stopwatch()..start();
        for (final l in nutritionLines(r)) {
          expect(skinDiscarded(r, l), trips, reason: l.raw);
          skinKeptPart(r, l);
          lineGrams(db, l, chicken, recipe: r);
        }
        final ms = sw.elapsedMilliseconds;
        final counts = Map.of(stepIndexCounts)..remove('names');
        expectBounded(r, counts, 'v112 $shape');
        expect(counts['memo:skinSentences'], 1);
        expect(counts['memo:strainAt'], strainReads);
        expect(counts['skinSentenceFacts'], skinSentences);
        expect(counts['skinScans'], capLines);
        expect(counts['memo:skinKeptPart'], trips ? capLines : null);
        // ignore: avoid_print
        print('v112 $shape ${ms}ms');
        expect(ms, lessThan(backstopMs), reason: '$shape: ${ms}ms');
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  });
}
