// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v59 (batch M60, the bone-in turkey breast, a peel written in the
// steps, bacon that drips; matcherVersion 58; prep48 design_v2 §2 M60 Y +
// P7a + P7b, the owner's Q14 (a) and Q15 (a), critic F8 and F15; decided
// 2026-10-08 under the 2026-10-07 standing authorization; zero requests;
// P7a/P7b pre-Q18): the bone-in turkey breast 171093 reads AH-102's derived
// breast-of-breast-plus-rib figure; a produce weight whose tail names no
// prep word takes its 'peeled' yield when a step pares it raw; bacon B1
// leaves unrendered that cooks ON a food keeps no fat. Every row value is
// the v59 replay of snapshot 23 (rp43, fix59 r1), computed here on WHOLE
// recipes over recorded real FDC answers (FixtureProvider; 4 searches and 1
// food added --from-db from snapshot 23, JSON-equal, 0 existing entries
// changed), never the network.

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

/// (file, position, raw, fdc id, confidence, grams, kcal, basis) — the v59
/// replay's row.
typedef _Row = (String, int, String, int?, String, String, String, String);

// Computed first: its deli-ham line caches the one answer holding 168322,
// the cooked bacon rule B1 writes (as nutrition_v41_test).
const _deliHam = '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml';
const _roastWhole = '0162-roast-whole-turkey-breast-with-gravy.yaml';
const _roastWhole2 = '1125-roast-whole-turkey-breast-with-gravy.yaml';
const _slowRoasted = '0162-slow-roasted-turkey-with-gravy.yaml';
const _braised = '0172-braised-turkey.yaml';
const _grillroasted = '0176-grillroasted-boneless-turkey-breast.yaml';
const _crowd = '0163-turkey-and-gravy-for-a-crowd.yaml';
const _enCocotte = '0173-turkey-breast-en-cocotte-with-pan-gravy.yaml';
const _porchetta = '1126-porchetta-style-turkey-breast.yaml';
const _burgers = '0309-juicy-grilled-turkey-burgers.yaml';
const _classic = '0154-classic-roast-turkey.yaml';
const _butternut =
    '0706-roasted-butternut-squash-with-browned-butter-and-hazelnuts.yaml';
const _pearCake = '0863-pear-walnut-upside-down-cake.yaml';
const _apples = '0953-best-baked-apples.yaml';
const _garlicMashed = '0000-garlic-and-olive-oil-mashed-potatoes.yaml';
const _blueCheeseMashed =
    '0695-mashed-potatoes-with-blue-cheese-and-port-caramelized-onions.yaml';
const _meatloaf = '0306-meatloaf-with-brown-sugarketchup-glaze.yaml';
const _scallops = '0652-grilled-bacon-wrapped-scallops.yaml';
const _tenderloin = '0593-grill-roasted-beef-tenderloin.yaml';
const _porkChops = '0205-smothered-pork-chops.yaml';
const _tartiflette = '1134-tartiflette-french-potato-and-cheese-gratin.yaml';
const _ovenBacon = '0733-oven-fried-bacon.yaml';

/// Y's flag, byte for byte design_v2 §2 M60 (F8: 2600 not cited).
const _yFlag =
    'derived from USDA AH-102 items 2591 and 2593, fryer-roaster class: '
    "a breast sold with its upper back (rib) attached — the breast's meat "
    'and skin, 87 % (85–89) of its 33 of 43 parts, 66.8 %; the back is not '
    'counted';

/// P7b's flag, byte for byte design_v2 §2 M60.
const _dripFlag =
    'approximate (USDA AH-102 item 1981: bacon, sliced, all methods → '
    'cooked 33 % (18–43); the fat drips off the food)';

/// Y's reach (all 8 rows on 171093; v58 1,656.00 g × 0.61 → × 0.67):
/// +2,318.63 kcal on the TSV (§2's +2,318.64 summed en-cocotte's rounded
/// 1,968.54 g; at full precision +274.02).
const List<_Row> _y = [
  (
    _roastWhole,
    0,
    '1 (5- to 7- pound) bone-in turkey breast',
    171093,
    '0.545714',
    '1817.11',
    '2852.86',
    'from the printed weight (5–7 lb, the midpoint) × 0.67 edible · approximate ($_yFlag)',
  ),
  (
    _roastWhole2,
    0,
    '1 (5- to 7-pound) bone-in turkey breast',
    171093,
    '0.545714',
    '1817.11',
    '2852.86',
    'from the printed weight (5–7 lb, the midpoint) × 0.67 edible · approximate ($_yFlag)',
  ),
  (
    _slowRoasted,
    6,
    '1 (5- to 7-pound) whole bone-in, skin-on turkey breast, trimmed',
    171093,
    '0.545714',
    '1817.11',
    '2852.86',
    'from the printed weight (5–7 lb, the midpoint) × 0.67 edible · approximate ($_yFlag)',
  ),
  (
    _braised,
    2,
    '1 (5- to 7-pound) whole bone-in, skin-on turkey breast, trimmed',
    171093,
    '0.545714',
    '1817.11',
    '2852.86',
    'from the printed weight (5–7 lb, the midpoint) × 0.67 edible · approximate ($_yFlag)',
  ),
  (
    _grillroasted,
    1,
    '1 (5- to 7-pound) whole bone-in turkey breast, trimmed',
    171093,
    '0.545714',
    '1817.11',
    '2852.86',
    'from the printed weight (5–7 lb, the midpoint) × 0.67 edible · approximate ($_yFlag)',
  ),
  (
    _crowd,
    16,
    '2 (5- to 6-pound) bone-in turkey breasts, trimmed',
    171093,
    '0.545714',
    '3331.37',
    '5230.25',
    '2 × 2495 g (printed 5–6 lb, the midpoint) × 0.67 edible · approximate ($_yFlag)',
  ),
  (
    _enCocotte,
    0,
    '1 (6- to 7-pound) whole bone-in turkey breast',
    171093,
    '0.545714',
    '1968.54',
    '3090.60',
    'from the printed weight (6–7 lb, the midpoint) × 0.67 edible · approximate ($_yFlag)',
  ),
  (
    _porchetta,
    8,
    '1 (7- to 8-pound) bone-in turkey breast',
    171093,
    '0.545714',
    '2271.39',
    '3566.08',
    'from the printed weight (7–8 lb, the midpoint) × 0.67 edible · approximate ($_yFlag)',
  ),
];

/// P7a's reach (a step pares the item raw; v58 at the printed weight):
/// −350.57 kcal. butternut step 1 "Using sharp vegetable peeler or chef's
/// knife, remove skin …", the pears step 2 "Peel, halve, and core pears.",
/// the apples step 2 "Peel the apples and use a melon baller …".
const List<_Row> _p7a = [
  (
    _butternut,
    0,
    '1 large (2½- to 3-pound) butternut squash',
    2685570,
    '0.970000',
    '1047.80',
    '504.33',
    'from the printed weight (2½–3 lb, the midpoint) × 0.84 edible · approximate (USDA AH-102 item 2459: butternut squash, raw whole → flesh 84 % (75–88); the steps peel it)',
  ),
  // RE-PIN (M64 batch, v63, P10): the pear half step 2 sets aside is
  // subtracted — 530.70 × 5/6 = 442.25 g (was 530.70; −59.26 kcal); P7a's
  // composed weighing kept, the part saved after it.
  (
    _pearCake,
    4,
    '3 ripe but firm Bosc pears (8 ounces each)',
    167778,
    '0.864444',
    '442.25',
    '296.31',
    '3 × 227 g (printed weight) × 0.78 edible · approximate (USDA AH-102 item 1734: pears, raw whole → pared, cored flesh 78 % (40–88); the steps peel it) · 1 pear half saved for another use (step 2) — only the rest counted',
  ),
  (
    _apples,
    0,
    '7 large (about 6 ounces each) Granny Smith apples',
    1750342,
    '0.970000',
    '928.73',
    '546.76',
    '7 × 170 g (printed weight) × 0.78 edible · approximate (USDA AH-102 item 17: apples, all cultivars, raw whole → flesh, pared and cored 78 % (60–87); the steps peel it)',
  ),
];

/// P7b's reach (v58 raw on 168277): two parts [168322 raw × 0.33, 172345
/// 0]; −1,274.96 kcal.
const List<_Row> _p7b = [
  (
    _meatloaf,
    17,
    '6–8 ounces bacon (8 to 12 slices, depending on loaf shape)',
    168277,
    '1.000000',
    '65.49',
    '306.49',
    '198 g raw → 65 g cooked bacon + 0.0 g bacon grease kept in the pan',
  ),
  (
    _scallops,
    0,
    '12 slices bacon',
    168277,
    '1.000000',
    '110.88',
    '518.92',
    '336 g raw → 111 g cooked bacon + 0.0 g bacon grease kept in the pan',
  ),
];

/// §2 M60's negatives, each equal to v58: the leg quarters and the thigh
/// (their own AH-102 rows), the whole bird (2592), the two mashed-potato
/// rows (peeled AFTER the simmer: the no-earlier-cook guard), the bacon
/// skewered for smoke over no food, the bacon pan-browned with no stated
/// pour-off, and oven-fried bacon (`steps: []` — waits for Q18).
const List<_Row> _kept = [
  (
    _crowd,
    12,
    '4 (1½- to 2-pound) turkey leg quarters, trimmed',
    171533,
    '1.000000',
    '2254.35',
    '3629.51',
    '4 × 794 g (printed 1½–2 lb, the midpoint) × 0.71 edible · approximate (USDA AH-102 item 2595: turkey leg quarter, raw, fryer-roaster class → meat and skin 71 % (69–73)) · approximation (counted as Turkey, retail parts, thigh, meat and skin, raw)',
  ),
  (
    _burgers,
    0,
    '1 (2-pound) bone-in turkey thigh, skinned, boned, trimmed, and cut into ½-inch pieces',
    174518,
    '0.962857',
    '698.53',
    '810.30',
    'from the printed weight × 0.77 edible · approximate (USDA AH-102 item 2598: turkey thigh, raw, fryer-roaster class → meat 77 % (76–80))',
  ),
  (
    _garlicMashed,
    0,
    '2 pounds russet potatoes (about 4 medium), scrubbed',
    2346401,
    '0.950000',
    '907.18',
    '756.77',
    'from 2 pound',
  ),
  (
    _blueCheeseMashed,
    8,
    '2 pounds russet potatoes',
    2346401,
    '0.950000',
    '907.18',
    '756.77',
    'from 2 pound',
  ),
  (
    _tenderloin,
    5,
    '3 slices bacon',
    168277,
    '1.000000',
    '84.00',
    '330.12',
    '3 slice × 28 g each',
  ),
  (
    _porkChops,
    0,
    '3 ounces bacon (about 3 slices), cut into ¼-inch pieces',
    168277,
    '1.000000',
    '85.05',
    '334.24',
    'from 3 ounce',
  ),
  (
    _ovenBacon,
    0,
    '12 slices bacon',
    168277,
    '1.000000',
    '336.00',
    '1320.48',
    '12 slice × 28 g each',
  ),
  (
    _classic,
    1,
    '1 (12- to 14-pound) turkey; giblets, neck, and tailpiece removed and reserved for gravy',
    171081,
    '1.000000',
    '3841.87',
    '5532.29',
    'from the printed weight (12–14 lb, the midpoint) × 0.65 edible · approximate (USDA AH-102 turkey dressing data, 12 lb and over (neck and giblets off 78 of 85); carcass → meat and skin, item 2592, fryer-roaster class, 71 % (67–75))',
  ),
];

/// The row's energy as the totals read it: each part (rule B1's) or the
/// row on its record — grams × the record's first energy number, else its
/// Atwater sum.
double _kcalOf(SaltDatabase db, IngredientMatchRow row, IngredientLine line) {
  double on(int fdcId, double grams) {
    if (grams <= 0) {
      return 0;
    }
    expect(nutrientSiblings[fdcId], isNull);
    final food = knownFood(db, fdcId, line: line)!;
    for (final number in nutrientDefs.first.fdcNumbers) {
      if (food.nutrientsPer100g[number] case final per100?) {
        return per100 * grams / 100;
      }
    }
    return kcalPer100g(food) * grams / 100;
  }

  return row.parts == null
      ? on(row.fdcId!, row.grams ?? 0)
      : partsOf(row.parts).fold(0, (t, p) => t + on(p.fdcId, p.grams));
}

void main() {
  test('the matcher version carries the batch (update the literal with a '
      'bump)', () {
    // RE-PIN (M61 batch, v60): matcherVersion 59 (was 58).
    // RE-PIN (M62 batch, v61): matcherVersion 60 (was 59).
    // RE-PIN (M63 batch, v62): matcherVersion 61 (was 60).
    // RE-PIN (M64 batch, v63): matcherVersion 62 (was 61).
    // RE-PIN (M65 batch, v64): matcherVersion 63 (was 62).
    // RE-PIN (M66 batch, v65): matcherVersion 64 (was 63).
    expect(matcherVersion, 64);
  });

  group('matcher v59 (batch M60)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v59-');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath)
        ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: pendingSearches);
      // The details snapshot 23 holds for the butternut, the russets and
      // the Granny Smiths (a weight line fetches none: without them the
      // energy is the search hit's rounded figure — 503.99 kcal for the
      // replay's 504.33).
      for (final id in [2685570, 2346401, 1750342]) {
        db.fdcFoodCachePut(id, jsonEncode((await provider.food(id))!.toJson()));
      }
      for (final file in [
        _deliHam,
        for (final rows in [_y, _p7a, _p7b, _kept])
          for (final (file, _, _, _, _, _, _, _) in rows) file,
        _tartiflette,
      ]) {
        if (recipes.containsKey(file)) {
          continue;
        }
        final host = loadCorpusRecipe(file);
        db.upsertRecipe(host, sourceSlug: _source, contentHash: host.id);
        final stored = db.recipeByIdOrSlug(host.id)!.recipe;
        expect(await matchAndCompute(db, provider, stored), isNull);
        recipes[file] = db.recipeByIdOrSlug(host.id)!.recipe;
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    IngredientLine lineOf(String file, int position) =>
        nutritionLines(recipes[file]!)[position];

    IngredientMatchRow rowOf(String file, int position) => db
        .ingredientMatchesFor(recipes[file]!.id)
        .singleWhere((m) => m.position == position);

    /// Each [rows] entry computed in its whole recipe: the record, the
    /// confidence, the grams, the energy and the basis; auto, no hold.
    void expectRows(List<_Row> rows) {
      for (final (file, position, raw, fdcId, confidence, grams, kcal, basis)
          in rows) {
        final recipe = recipes[file]!;
        final line = lineOf(file, position);
        final row = rowOf(file, position);
        final reason = '$file|$position';
        expect(line.raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.confidence.toStringAsFixed(6), confidence, reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(row.status, 'auto', reason: reason);
        expect(row.hold, isNull, reason: reason);
        expect(_kcalOf(db, row, line).toStringAsFixed(2), kcal, reason: reason);
        expect(
          gramBasisFor(db, line, row, recipe: recipe),
          basis,
          reason: reason,
        );
      }
    }

    test('Y reaches exactly the 8 rows on 171093 at the derived 66.77 % '
        '(design_v2 §2 M60, Q14 (a))', () {
      expect(_y, hasLength(8));
      expectRows(_y);
      final line = lineOf(_roastWhole, 0);
      final yieldOf = ah102YieldOf(
        knownFood(db, 171093, line: line)!,
        line.raw,
      )!;
      expect(yieldOf.share, 33 / 43 * 0.87);
      expect(yieldOf.share.toStringAsFixed(4), '0.6677');
      expect(yieldOf.flag, _yFlag);
      // The interim chicken class figure is gone (dead once the part reads).
      expect(boneInClassYields.containsKey(171093), isFalse);
    });

    test('P7a reaches exactly its 3 rows: the shipped peeled figure, '
        '"; the steps peel it"', () {
      expect(_p7a, hasLength(3));
      expectRows(_p7a);
      for (final (file, position, _, _, _, _, _, _) in _p7a) {
        expect(
          stepsPeelIn(recipes[file]!, lineOf(file, position)),
          isTrue,
          reason: file,
        );
      }
    });

    test('P7a: the mashed potatoes are peeled AFTER the simmer — the '
        'no-earlier-cook guard keeps both rows at 907.18 g', () {
      for (final file in [_garlicMashed, _blueCheeseMashed]) {
        final position = file == _garlicMashed ? 0 : 8;
        expect(
          stepsPeelIn(recipes[file]!, lineOf(file, position)),
          isFalse,
          reason: file,
        );
        expect(rowOf(file, position).grams?.toStringAsFixed(2), '907.18');
      }
    });

    test('P7a, STATED synthesized (the no-smaller-count guard moves no '
        "corpus row: the apples' step 2 pares all of them): without step 2's "
        '"Peel the apples", step 1\'s "Peel, core, and cut 1 apple" pares one '
        'of 7 and does not fire', () {
      final apples = recipes[_apples]!;
      final line = lineOf(_apples, 0);
      final step2 = apples.steps[1];
      final text = step2.text.replaceFirst(
        'Peel the apples and use a melon baller',
        'Use a melon baller',
      );
      expect(text, isNot(step2.text));
      final synthesized = apples.copyWith(
        steps: [...apples.steps]..[1] = step2.copyWith(text: text),
      );
      expect(stepsPeelIn(synthesized, line), isFalse);
      expect(stepsPeelIn(apples, line), isTrue);
    });

    test('P7a names the noun as every detector names a head (closer 2, '
        "verifier 2 D2: the head's sentences come from the step index's "
        'naming lookup; STATED synthesized, no corpus step writes these): '
        '"core garlic pears" names no pear, and a "-y" head is named and '
        'counted by its "-ies" plural', () {
      final cake = recipes[_pearCake]!;
      final step2 = cake.steps[1];
      Recipe step2As(String text) {
        expect(text, isNot(step2.text));
        return cake.copyWith(
          steps: [...cake.steps]..[1] = step2.copyWith(text: text),
        );
      }

      final pears = lineOf(_pearCake, 4);
      expect(stepsPeelIn(cake, pears), isTrue);
      expect(
        stepsPeelIn(
          step2As(step2.text.replaceFirst('core pears.', 'core garlic pears.')),
          pears,
        ),
        isFalse,
      );
      final p = parseIngredientLine('3 cherries');
      final cherries = IngredientLine(
        raw: '3 cherries',
        item: p.item,
        prep: p.prep,
        amounts: p.amounts,
      );
      expect(headNounOf(normalizeItem(lineItemOf(cherries))), 'cherry');
      expect(
        stepsPeelIn(
          step2As(step2.text.replaceFirst('core pears.', 'pit cherries.')),
          cherries,
        ),
        isTrue,
      );
      expect(
        stepsPeelIn(
          step2As(step2.text.replaceFirst('core pears.', 'pit 2 cherries.')),
          cherries,
        ),
        isFalse,
      );
    });

    test('P7a reads the step only when the tail names no prep word and the '
        'line never says "unpeeled" (STATED synthesized: no corpus line '
        'says unpeeled where a step pares it)', () {
      final line = lineOf(_butternut, 0);
      final squash = knownFood(db, 2685570, line: line)!;
      expect(produceYieldOf(squash, line.raw), isNull);
      expect(produceYieldOf(squash, line.raw, stepsPeel: true), (
        share: 0.84,
        flag:
            'USDA AH-102 item 2459: butternut squash, raw whole → flesh 84 % '
            '(75–88); the steps peel it',
      ));
      // The shipped tail word wins: no "; the steps peel it".
      expect(
        produceYieldOf(squash, '${line.raw}, peeled', stepsPeel: true)?.flag,
        'USDA AH-102 item 2459: butternut squash, raw whole → flesh 84 % '
        '(75–88)',
      );
      expect(
        produceYieldOf(squash, '${line.raw}, unpeeled', stepsPeel: true),
        isNull,
      );
    });

    test("P7b reaches exactly its 2 rows: B1's two parts with no fat kept, "
        'the drip flag (Q15 (a))', () {
      expect(_p7b, hasLength(2));
      expectRows(_p7b);
      final memo = ResolverMemo(db);
      for (final (file, position, cooked) in [
        (_meatloaf, 17, 65.49),
        (_scallops, 0, 110.88),
      ]) {
        final row = rowOf(file, position);
        expect(partsOf(row.parts), [
          (fdcId: cookedBaconFdcId, grams: cooked),
          (fdcId: baconGreaseFdcId, grams: 0.0),
        ], reason: file);
        expect(
          compositeFlagOf(
            db,
            recipes[file]!,
            lineOf(file, position),
            row,
            memo,
          ),
          _dripFlag,
          reason: file,
        );
      }
    });

    test('P7b, STATED synthesized (no corpus recipe lays bacon over a food '
        'it never bakes): the meatloaf without its "Bake the loaf" sentence '
        'leaves the bacon raw — the drip needs a LATER bake, roast, grill or '
        'broil', () {
      final meatloaf = recipes[_meatloaf]!;
      final line = lineOf(_meatloaf, 17);
      final row = rowOf(_meatloaf, 17);
      final step = meatloaf.steps.indexWhere(
        (s) => s.text.startsWith('Bake the loaf until the bacon is crisp'),
      );
      expect(step, isNonNegative);
      final text = meatloaf.steps[step].text.replaceFirst(
        RegExp(r'^Bake the loaf[^.]*\.\s*'),
        '',
      );
      final synthesized = meatloaf.copyWith(
        steps: [...meatloaf.steps]
          ..[step] = meatloaf.steps[step].copyWith(text: text),
      );
      expect(
        withRenderedBacon(synthesized, line, row, raw: 198.45).parts,
        isNull,
      );
      expect(
        partsOf(withRenderedBacon(meatloaf, line, row, raw: 198.45).parts),
        [
          (fdcId: cookedBaconFdcId, grams: 65.49),
          (fdcId: baconGreaseFdcId, grams: 0.0),
        ],
      );
    });

    test('P7b, STATED synthesized (the towel guard moves no corpus row: the '
        "scallops' towel sentence is followed by the wrap): without step 2's "
        'wrap, the bacon "arrange[d] … over towels" before the grill never '
        'drips', () {
      final scallops = recipes[_scallops]!;
      final line = lineOf(_scallops, 0);
      final row = rowOf(_scallops, 0);
      final step = scallops.steps.indexWhere(
        (s) => s.text.contains('and wrap with 1 slice bacon'),
      );
      expect(step, isNonNegative);
      final text = scallops.steps[step].text.replaceFirst(
        'and wrap with 1 slice bacon, trimming excess as necessary',
        'and set them on a plate',
      );
      expect(text, isNot(scallops.steps[step].text));
      final synthesized = scallops.copyWith(
        steps: [...scallops.steps]
          ..[step] = scallops.steps[step].copyWith(text: text),
      );
      expect(
        withRenderedBacon(synthesized, line, row, raw: 336).parts,
        isNull,
      );
    });

    test('the negatives equal v58: turkey leg quarters, thigh and whole '
        'bird, the mashed potatoes, the smoke bacon, the pan bacon with no '
        'pour-off, oven-fried bacon (steps: [], Q18)', () {
      expect(recipes[_ovenBacon]!.steps, isEmpty);
      expectRows(_kept);
    });

    test("tartiflette's rendered bacon keeps B1's pan fat and flag", () {
      final row = rowOf(_tartiflette, 2);
      expect(row.grams?.toStringAsFixed(2), '95.97');
      expect(partsOf(row.parts), [
        (fdcId: cookedBaconFdcId, grams: 70.17),
        (fdcId: baconGreaseFdcId, grams: 25.80),
      ]);
      expect(
        compositeFlagOf(
          db,
          recipes[_tartiflette]!,
          lineOf(_tartiflette, 2),
          row,
          ResolverMemo(db),
        ),
        baconYieldFlag,
      );
    });

    test('the recipes move kcal per serving only (statuses complete)', () {
      for (final (file, kcal) in [
        (_roastWhole, '544.34'), // v58 502.18
        (_roastWhole2, '544.34'), // v58 502.18
        (_slowRoasted, '608.72'), // v58 583.42
        (_braised, '601.81'), // v58 576.52
        (_grillroasted, '482.28'), // v58 440.12
        (_crowd, '566.13'), // v58 540.37
        (_enCocotte, '618.09'), // v58 572.42
        (_porchetta, '700.52'), // v58 647.82
        (_butternut, '351.03'), // v58 375.04
        // RE-PIN (M64 batch, v63, P10): 525.79 (was 533.20; −59.26 / 8).
        (_pearCake, '525.79'), // v58 545.74
        (_apples, '363.28'), // v58 388.98
        // meatloaf (replay 575.11, v58 654.01, −473.40 / 6): its saltines
        // |15 land another record with no grams in a fresh compute
        // (174928; 2708167 in snapshot 23) — not pinned here.
        (_scallops, '350.84'), // v58 551.23
      ]) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        expect(
          (n.status, n.caloriesPerServing!.toStringAsFixed(2)),
          ('complete', kcal),
          reason: file,
        );
      }
    });

    test('a second recompute writes nothing', () {
      for (final file in const [
        _roastWhole,
        _butternut,
        _meatloaf,
        _scallops,
      ]) {
        final recipe = recipes[file]!;
        List<(int, double?, String?)> rows() => [
          for (final r in db.ingredientMatchesFor(recipe.id))
            (r.position, r.grams, r.parts),
        ];
        final before = rows();
        expect(recomputeTotals(db, recipe), isTrue, reason: file);
        expect(rows(), before, reason: file);
      }
    });
  });
}
