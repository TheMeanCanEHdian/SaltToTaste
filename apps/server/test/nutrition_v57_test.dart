// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v57 (batch M58, a batter left in the bowl joins the coat budget;
// matcherVersion 56; prep48 design_v2 §2 M58 W + S + the negimaki flag, the
// owner's Q8 and Q10, critic F10; decided 2026-10-08 under the standing
// authorization; zero requests; step-reading, pre-Q18): engine `_m52Plan`
// counts the lines a batter leaves in the bowl (`_batterInBowl`) as coat
// parts at the coat's one f = min(1, B / Σ carbohydrate), never off a C5
// budget; battered shrimp is C5 on FNDDS 2706364, a battered haddock C5 on
// 2706258; the coat flag says "the batter's excess", names a figure read
// on another food as a stand-in and a batter read on a C1/C2 breading
// figure; negimaki's glaze states its printed split, counted whole. Every
// row value is the v57 replay of snapshot 23 (rp43, fix57 r1), computed
// here on WHOLE recipes over recorded real FDC answers (FixtureProvider; 3
// searches and 1 food added --from-db from snapshot 23, JSON-equal, 0
// existing entries changed), never the network.

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

/// (file, position, raw, fdc id, confidence, grams, kcal, basis) — the v57
/// replay's row; kcal is grams × the record's energy (before any Q25
/// alcohol factor, as the replay's column reads it).
typedef _Row = (String, int, String, int?, String, String?, String, String?);

const _tempura = '0511-shrimp-tempura.yaml';
const _fishChips = '0255-fish-and-chips.yaml';
const _sandwiches = '1081-crispy-fish-sandwiches-with-tartar-sauce.yaml';
const _wings = '0526-dakgangjeong-korean-fried-chicken-wings.yaml';
const _negimakiFile =
    '0516-negimaki-japanese-grilled-steak-and-scallion-rolls.yaml';

/// W's reach (design_v2 §2 M58, exactly these 17 rows; −1,376.44 kcal per
/// batch at the Q25 factor): tempura (B = 15.38 × 680.39 g shrimp, f
/// 0.4690), the sandwiches (B on 566.99 g haddock, f 0.7795), dakgangjeong
/// (C1 wing 5.66, f 0.3345) and fish-and-chips (C5 cod, f 0.4924 — its
/// flour |2, already a coat part, rises as the starch and beer leave B's
/// subtraction). fish-and-chips |3 and |10 read 31.45 and 167.52 at full
/// precision (the design's hand f on rounded grams: 31.46, 167.51).
const List<_Row> _reach = [
  // v56: 212.62 g, 778.19 kcal
  // RE-PIN (M90 batch, v89, cornstarch: the budget re-solves on it): was 99.71 g, 364.94 kcal (the v89 replay's row).
  (
    _tempura,
    2,
    '1½ cups (7½ ounces) unbleached all-purpose flour',
    789890,
    '0.950000',
    '102.73',
    '375.99',
    // RE-PIN (M66 batch, v65, Q1 b): the C5 basis names the breading's carbohydrate it is matched by.
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw shrimp — USDA FNDDS 2706364 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw shrimp, matched by its carbohydrate; the batter's excess not counted)",
  ),
  // v56: 63.88 g, 243.38 kcal
  // RE-PIN (M90 batch, v89, cornstarch: its coat share re-solves): was 29.96 g, 114.15 kcal (the v89 replay's row).
  (
    _tempura,
    3,
    '½ cup cornstarch',
    169698,
    '1.000000',
    '27.39',
    '104.36',
    // RE-PIN (M66 batch, v65, Q1 b): the C5 basis names the breading's carbohydrate it is matched by.
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw shrimp — USDA FNDDS 2706364 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw shrimp, matched by its carbohydrate; the batter's excess not counted)",
  ),
  // v56: 224.00 g, 517.44 kcal
  // RE-PIN (M90 batch, v89, cornstarch: the budget re-solves on it): was 105.05 g, 242.67 kcal (the v89 replay's row).
  (
    _tempura,
    4,
    '1 cup vodka',
    2710704,
    '0.990000',
    '108.23',
    '250.01',
    // RE-PIN (M66 batch, v65, Q1 b): the C5 basis names the breading's carbohydrate it is matched by.
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw shrimp — USDA FNDDS 2706364 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw shrimp, matched by its carbohydrate; the batter's excess not counted)",
  ),
  // v56: 50.00 g, 74.00 kcal
  // RE-PIN (M90 batch, v89, cornstarch: the budget re-solves on it): was 23.45 g, 34.71 kcal (the v89 replay's row).
  (
    _tempura,
    5,
    '1 large egg',
    748967,
    '0.920000',
    '24.16',
    '35.76',
    // RE-PIN (M66 batch, v65, Q1 b): the C5 basis names the breading's carbohydrate it is matched by.
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw shrimp — USDA FNDDS 2706364 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw shrimp, matched by its carbohydrate; the batter's excess not counted)",
  ),
  // v56: 236.59 g, 0.00 kcal
  // RE-PIN (M90 batch, v89, cornstarch: the budget re-solves on it): was 110.95 g, 0.00 kcal (the v89 replay's row).
  (
    _tempura,
    6,
    '1 cup seltzer water',
    2710539,
    '0.923333',
    '114.31',
    '0.00',
    // RE-PIN (M66 batch, v65, Q1 b): the C5 basis names the breading's carbohydrate it is matched by.
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw shrimp — USDA FNDDS 2706364 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw shrimp, matched by its carbohydrate; the batter's excess not counted)",
  ),
  // v56: 60.33 g, 220.81 kcal
  // RE-PIN (M82 batch, v84, C5a): was 47.03 g, 172.13 kcal (the v84 replay's row).
  // RE-PIN (M90 batch, v89, cornstarch: the budget re-solves on it): was 51.49 g, 188.45 kcal (the v89 replay's row).
  (
    _sandwiches,
    6,
    '½ cup all-purpose flour',
    789890,
    '0.950000',
    '54.47',
    '199.36',
    // RE-PIN (M66 batch, v65, Q1 b): the C5 basis names the breading's carbohydrate it is matched by.
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw haddock — USDA FNDDS 2706258 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw haddock, matched by its carbohydrate; the batter's excess not counted)",
  ),
  // v56: 63.88 g, 243.38 kcal
  // RE-PIN (M82 batch, v84, C5a): was 49.79 g, 189.70 kcal (the v84 replay's row).
  // RE-PIN (M90 batch, v89, cornstarch: its coat share re-solves): was 46.41 g, 176.82 kcal (the v89 replay's row).
  (
    _sandwiches,
    7,
    '½ cup cornstarch',
    169698,
    '1.000000',
    '43.57',
    '166.00',
    // RE-PIN (M66 batch, v65, Q1 b): the C5 basis names the breading's carbohydrate it is matched by.
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw haddock — USDA FNDDS 2706258 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw haddock, matched by its carbohydrate; the batter's excess not counted)",
  ),
  // v56: 2.27 g, 1.16 kcal
  // RE-PIN (M82 batch, v84, C5a): was 1.77 g, 0.90 kcal (the v84 replay's row).
  // RE-PIN (M90 batch, v89, cornstarch: the budget re-solves on it): was 1.65 g, 0.84 kcal (the v89 replay's row).
  (
    _sandwiches,
    9,
    '½ teaspoon baking powder',
    172804,
    '0.850000',
    '1.74',
    '0.89',
    // RE-PIN (M66 batch, v65, Q1 b): the C5 basis names the breading's carbohydrate it is matched by.
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw haddock — USDA FNDDS 2706258 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw haddock, matched by its carbohydrate; the batter's excess not counted)",
  ),
  // v56: 180.00 g, 77.40 kcal
  // RE-PIN (M82 batch, v84, C5a): was 140.31 g, 60.33 kcal (the v84 replay's row).
  // RE-PIN (M90 batch, v89, cornstarch: the budget re-solves on it): was 130.78 g, 56.24 kcal (the v89 replay's row).
  (
    _sandwiches,
    10,
    '¾ cup beer',
    2710616,
    '0.990000',
    '138.33',
    '59.48',
    // RE-PIN (M66 batch, v65, Q1 b): the C5 basis names the breading's carbohydrate it is matched by.
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw haddock — USDA FNDDS 2706258 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw haddock, matched by its carbohydrate; the batter's excess not counted)",
  ),
  // v56: 120.66 g, 441.62 kcal
  // RE-PIN (M82 batch, v84, C5a): was 40.36 g, 147.72 kcal (the v84 replay's row).
  // RE-PIN (M90 batch, v89, cornstarch: the budget re-solves on it): was 41.53 g, 152.00 kcal (the v89 replay's row).
  (
    _wings,
    8,
    '1 cup all-purpose flour',
    789890,
    '0.950000',
    '42.32',
    '154.89',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.66 g carbohydrate per 100 g of the raw chicken wings — USDA FNDDS 2706065 recipe: 15 g breading per 105.96 g raw chicken wing (a batter read on a breading figure); the batter's excess not counted)",
  ),
  // v56: 23.95 g, 91.27 kcal
  // RE-PIN (M82 batch, v84, C5a): was 8.01 g, 30.52 kcal (the v84 replay's row).
  // RE-PIN (M90 batch, v89, cornstarch: its coat share re-solves): was 7.02 g, 26.75 kcal (the v89 replay's row).
  (
    _wings,
    9,
    '3 tablespoons cornstarch',
    169698,
    '1.000000',
    '6.35',
    '24.19',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.66 g carbohydrate per 100 g of the raw chicken wings — USDA FNDDS 2706065 recipe: 15 g breading per 105.96 g raw chicken wing (a batter read on a breading figure); the batter's excess not counted)",
  ),
  // v56: 59.95 g, 219.42 kcal
  // RE-PIN (M82 batch, v84, C5a): was 89.12 g, 326.18 kcal (the v84 replay's row).
  // RE-PIN (M90 batch, v89, cornstarch: the budget re-solves on it): was 93.89 g, 343.64 kcal (the v89 replay's row).
  (
    _fishChips,
    2,
    '1½ cups unbleached all-purpose flour',
    789890,
    '0.950000',
    '96.56',
    '353.41',
    // RE-PIN (M66 batch, v65, Q1 b): the C5 basis names the breading's carbohydrate it is matched by.
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw cod, matched by its carbohydrate; the batter's excess not counted)",
  ),
  // v56: 63.88 g, 243.38 kcal
  // RE-PIN (M82 batch, v84, C5a): was 31.45 g, 119.82 kcal (the v84 replay's row).
  // RE-PIN (M90 batch, v89, cornstarch: its coat share re-solves): was 28.21 g, 107.48 kcal (the v89 replay's row).
  (
    _fishChips,
    3,
    '½ cup cornstarch',
    169698,
    '1.000000',
    '25.75',
    '98.11',
    // RE-PIN (M66 batch, v65, Q1 b): the C5 basis names the breading's carbohydrate it is matched by.
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw cod, matched by its carbohydrate; the batter's excess not counted)",
  ),
  // v56: 0.90 g, 2.86 kcal
  // RE-PIN (M82 batch, v84, C5a): was 0.44 g, 1.40 kcal (the v84 replay's row).
  // RE-PIN (M90 batch, v89, cornstarch: the budget re-solves on it): was 0.40 g, 1.27 kcal (the v89 replay's row).
  (
    _fishChips,
    4,
    '½ teaspoon cayenne pepper',
    170932,
    '1.000000',
    '0.41',
    '1.30',
    // RE-PIN (M66 batch, v65, Q1 b): the C5 basis names the breading's carbohydrate it is matched by.
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw cod, matched by its carbohydrate; the batter's excess not counted)",
  ),
  // v56: 1.16 g, 3.27 kcal
  // RE-PIN (M82 batch, v84, C5a): was 0.57 g, 1.61 kcal (the v84 replay's row).
  // RE-PIN (M90 batch, v89, cornstarch: the budget re-solves on it): was 0.51 g, 1.44 kcal (the v89 replay's row).
  (
    _fishChips,
    5,
    '½ teaspoon paprika',
    171329,
    '0.900000',
    '0.53',
    '1.49',
    // RE-PIN (M66 batch, v65, Q1 b): the C5 basis names the breading's carbohydrate it is matched by.
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw cod, matched by its carbohydrate; the batter's excess not counted)",
  ),
  // v56: 4.53 g, 2.31 kcal
  // RE-PIN (M82 batch, v84, C5a): was 2.23 g, 1.14 kcal (the v84 replay's row).
  // RE-PIN (M90 batch, v89, cornstarch: the budget re-solves on it): was 2.00 g, 1.02 kcal (the v89 replay's row).
  (
    _fishChips,
    8,
    '1 teaspoon baking powder',
    172804,
    '0.850000',
    '2.06',
    '1.05',
    // RE-PIN (M66 batch, v65, Q1 b): the C5 basis names the breading's carbohydrate it is matched by.
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw cod, matched by its carbohydrate; the batter's excess not counted)",
  ),
  // v56: 340.19 g, 146.28 kcal
  // RE-PIN (M82 batch, v84, C5a): was 167.52 g, 72.03 kcal (the v84 replay's row).
  // RE-PIN (M90 batch, v89, cornstarch: the budget re-solves on it): was 150.23 g, 64.60 kcal (the v89 replay's row).
  (
    _fishChips,
    10,
    '1½ cups (12 ounces) cold beer',
    2710616,
    '0.565000',
    '154.50',
    '66.44',
    // RE-PIN (M66 batch, v65, Q1 b): the C5 basis names the breading's carbohydrate it is matched by.
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw cod, matched by its carbohydrate; the batter's excess not counted)",
  ),
];

/// S (flag only, 0 kcal): a coat figure read on another food says it stands
/// in, as the uptake clause on the same recipes does — chicken on the
/// country-fried steak (C1d), pork and crab on the fried breast (C1).
const List<_Row> _standIns = [
  // v56: the same grams; the flag moved
  (
    '0148-crispy-fried-chicken.yaml',
    8,
    '4 cups (20 ounces) unbleached all-purpose flour',
    789890,
    '0.950000',
    '144.06',
    '527.26',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 8.79 g carbohydrate per 100 g of the raw chicken — USDA FNDDS 2705842 recipe: 20 g breading per 90.99 g raw beef steak (no record for chicken; read as Beef, steak, country fried); the dredge's excess not counted)",
  ),
  // v56: the same grams; the flag moved
  (
    '0198-crispy-pan-fried-pork-chops.yaml',
    0,
    '⅔ cup cornstarch',
    169698,
    '1.000000',
    '49.83',
    '189.85',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
  // v56: the same grams; the flag moved
  // RE-PIN (M82 batch, v84, C5a): was 39.27 g, 104.46 kcal (the v84 replay's row).
  (
    '0233-pork-schnitzel-breaded-pork-cutlets.yaml',
    0,
    '7 slices high-quality white sandwich bread, crusts removed, cut into ¾-inch cubes (about 4 cups)',
    174924,
    '0.914286',
    '36.69',
    '97.60',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
  // v56: the same grams; the flag moved
  // RE-PIN (M82 batch, v84, C5a): was 16.92 g, 61.93 kcal (the v84 replay's row).
  (
    '0233-pork-schnitzel-breaded-pork-cutlets.yaml',
    1,
    '½ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '18.57',
    '67.97',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
  // v56: the same grams; the flag moved
  // RE-PIN (M82 batch, v84, C5a): was 30.16 g, 110.39 kcal (the v84 replay's row).
  (
    '0288-maryland-crab-cakes.yaml',
    8,
    '¼ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '33.62',
    '123.05',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw crab — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for crab; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
];

/// Q10 (flag only, 0 kcal): negimaki's glaze, counted whole, states the
/// printed split ("Divide evenly between two bowls … set aside for
/// serving"; "Discard remaining glaze"). Its flank steak has no coat shape
/// (grilled), so the glaze never reaches W.
const List<_Row> _negimaki = [
  // v56: the same grams; the flag moved
  (
    _negimakiFile,
    1,
    '⅓ cup soy sauce',
    2707442,
    '0.990000',
    '91.48',
    '48.48',
    '1/3 cup ≈ 79 mL · approximate (the steps divide the glaze evenly between two bowls — one half served, the other brushed on and its rest discarded; counted whole)',
  ),
  // v56: the same grams; the flag moved
  // RE-PIN (M90 batch, v89, sugar): was 37.71 g, 145.17 kcal (the v89 replay's row).
  (
    _negimakiFile,
    2,
    '3 tablespoons sugar',
    746784,
    '0.950000',
    '37.21',
    '143.25',
    '3 tablespoon ≈ 44 mL · approximate (ATK: 1 cup sugar = 7 ounces) · approximate (the steps divide the glaze evenly between two bowls — one half served, the other brushed on and its rest discarded; counted whole)',
  ),
  // v56: the same grams; the flag moved
  (
    _negimakiFile,
    3,
    '2 tablespoons mirin',
    2710692,
    '0.990000',
    '30.00',
    '48.00',
    '2 tablespoon · USDA portion · approximation (counted as Wine, dessert, sweet) · approximate (the steps divide the glaze evenly between two bowls — one half served, the other brushed on and its rest discarded; counted whole)',
  ),
  // v56: the same grams; the flag moved
  (
    _negimakiFile,
    4,
    '2 tablespoons sake',
    167723,
    '0.790000',
    '29.10',
    '38.99',
    '2 tablespoon · USDA portion · approximate (the steps divide the glaze evenly between two bowls — one half served, the other brushed on and its rest discarded; counted whole)',
  ),
];

/// Equal to v56: three of the recipes' frying oils (tempura's uptake stays
/// O2s 15.38 — C5 is not C3; fish-and-chips' oil, unmoved by W, reads
/// another peanut-oil record in a fresh compute than in snapshot 23 and is
/// pinned there by nutrition_v53_test);
/// the dips W does not read — a dough (the scones), a rolled cocoa coat
/// (the truffles), egg washes (E is M62's: katsu, lighter parmesan, its
/// E-w grams since v61 — RE-PIN, M62 batch) — and
/// the floured shrimp with no batter sentence, still C3.
const List<_Row> _kept = [
  (
    _tempura,
    0,
    '3 quarts peanut or vegetable oil',
    2710187,
    '0.673333',
    '104.64',
    '941.76',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 15.38 % of the raw shrimp's weight — USDA FNDDS 2706364 recipe: 10 g oil per 65 g raw shrimp)",
  ),
  (
    _sandwiches,
    11,
    '2 quarts peanut or vegetable oil for frying',
    2710187,
    '0.500000',
    '87.20',
    '784.80',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 15.38 % of the raw haddock's weight — USDA FNDDS 2706258 recipe: 10 g oil per 65 g raw haddock)",
  ),
  (
    _wings,
    7,
    '2 quarts vegetable oil',
    2710180,
    '0.923333',
    '44.97',
    '404.73',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.61 % of the raw chicken wings' weight — USDA FNDDS 2706065 recipe: 7 g oil per 105.96 g raw chicken wing)",
  ),
  (
    '0758-british-style-currant-scones.yaml',
    0,
    '3 cups (15 ounces) all-purpose flour',
    789890,
    '0.950000',
    '425.24',
    '1556.39',
    'from 15 ounce · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0852-chocolate-truffles.yaml',
    6,
    '1 cup (3 ounces) Dutch-processed cocoa',
    169594,
    '0.623214',
    '85.05',
    '187.11',
    'from 3 ounce · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  // RE-PIN (M90 batch, v89, cornstarch: its coat share re-solves): was 39.92 g, 152.10 kcal (the v89 replay's row).
  (
    '0279-crispy-salt-and-pepper-shrimp.yaml',
    8,
    '5 tablespoons cornstarch',
    169698,
    '1.000000',
    '35.44',
    '135.03',
    'discarded in cooking — only the part the recipe keeps and the coat on the food counted · approximation (coat: 3.94 g carbohydrate per 100 g of the raw shrimp — derived from USDA SR Legacy 171982 "Mollusks, squid, mixed species, cooked, fried"; the dredge\'s excess not counted)',
  ),
  // RE-PIN (M62 batch, v61): the two egg washes are M62's E-w dips now
  // (100.00 g / 148.00 kcal and 99.00 / 54.45, the D5 flag, before) —
  // W still never reads them (their dip word is no batter).
  (
    '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
    1,
    '2 large eggs',
    748967,
    '0.920000',
    '53.35',
    '78.96',
    "discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat's carbohydrate — USDA FNDDS 2710785 \"Breading or batter as ingredient in food\": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip's excess not counted)",
  ),
  // RE-PIN (M80 batch, v80, M80-2): lighter's crumb crust reads FNDDS
  // 2706442's 12.12, so its dip's W grows with B (was 23.79 g / 13.08 kcal
  // at 3.18) — W still never reads it as a batter.
  (
    '0416-lighter-chicken-parmesan.yaml',
    6,
    '3 large egg whites',
    747997,
    '0.950000',
    '90.69',
    '49.88',
    "discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat's carbohydrate — USDA FNDDS 2710785 \"Breading or batter as ingredient in food\": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip's excess not counted)",
  ),
];

/// The row's energy, as the totals read it (the record's first energy
/// number, else its Atwater sum): grams × kcal per 100 g.
double _kcalOf(SaltDatabase db, IngredientMatchRow row, IngredientLine line) {
  final grams = row.grams ?? 0;
  if (grams <= 0) {
    return 0;
  }
  expect(nutrientSiblings[row.fdcId], isNull);
  final food = knownFood(db, row.fdcId!, line: line)!;
  for (final number in nutrientDefs.first.fdcNumbers) {
    if (food.nutrientsPer100g[number] case final per100?) {
      return per100 * grams / 100;
    }
  }
  return kcalPer100g(food) * grams / 100;
}

void main() {
  group('matcher v57 (batch M58)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v57-');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath)
        ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: pendingSearches);
      // The detail snapshot 23 holds for dakgangjeong's wings (a weight
      // line fetches none: without it the energy is the search hit's
      // rounded 168 for 167.55 — 513.72 kcal per serving for the replay's
      // 512.96).
      db.fdcFoodCachePut(
        2727568,
        jsonEncode((await provider.food(2727568))!.toJson()),
      );
      // Each recipe stored and computed whole — lighter-chicken-parmesan's
      // one section (its Simple Tomato Sauce) computed first, as the replay
      // does.
      for (final (file, _, _, _, _, _, _, _) in [
        ..._reach,
        ..._standIns,
        ..._negimaki,
        ..._kept,
      ]) {
        if (recipes.containsKey(file)) {
          continue;
        }
        final host = loadCorpusRecipe(file);
        db.upsertRecipe(host, sourceSlug: _source, contentHash: host.id);
        final stored = db.recipeByIdOrSlug(host.id)!.recipe;
        for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
          expect(
            await matchAndCompute(
              db,
              provider,
              nutritionRecipeOf(db, key)!.recipe,
            ),
            isNull,
          );
        }
        expect(await matchAndCompute(db, provider, stored), isNull);
        recipes[file] = db.recipeByIdOrSlug(host.id)!.recipe;
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    IngredientMatchRow rowOf(String file, int position) => db
        .ingredientMatchesFor(recipes[file]!.id)
        .singleWhere((m) => m.position == position);

    String? basisOf(String file, int position) => gramBasisFor(
      db,
      nutritionLines(recipes[file]!)[position],
      rowOf(file, position),
      recipe: recipes[file],
    );

    /// Each [rows] entry computed in its whole recipe: the record, the
    /// confidence, the grams, the energy and the basis; no hold.
    void expectRows(List<_Row> rows) {
      for (final (file, position, raw, fdcId, confidence, grams, kcal, basis)
          in rows) {
        final line = nutritionLines(recipes[file]!)[position];
        final row = rowOf(file, position);
        final reason = '$file|$position';
        expect(line.raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.confidence.toStringAsFixed(6), confidence, reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(row.status, 'auto', reason: reason);
        expect(row.hold, isNull, reason: reason);
        expect(_kcalOf(db, row, line).toStringAsFixed(2), kcal, reason: reason);
        expect(basisOf(file, position), basis, reason: reason);
      }
    }

    test(
      'W reaches exactly its 17 rows: each batter line a coat part at '
      "the coat's one f, `discarded`, the batter flag (design_v2 §2 M58)",
      () {
        expect(_reach, hasLength(17));
        expectRows(_reach);
        for (final (file, position, _, _, _, _, _, _) in _reach) {
          expect(
            rowOf(file, position).gramSource,
            'discarded',
            reason: '$file|$position',
          );
        }
        // The design's named pins, read off the tuples above.
        String g(String file, int position) =>
            rowOf(file, position).grams!.toStringAsFixed(2);
        // RE-PIN (M90 batch, v89, cornstarch): the batter starch at 4 oz a cup
        // re-solves the coats f (the v89 replay rows): was 99.71, 105.05; 93.89,
        // 46.41, 41.53.
        expect(g(_tempura, 2), '102.73');
        expect(g(_tempura, 4), '108.23');
        // RE-PIN (M82 batch, v84, C5a): the batter flours at 5 oz a cup
        // re-solve the coats' f (the v84 replay's rows): was 89.12, 49.79,
        // 40.36.
        expect(g(_fishChips, 2), '96.56');
        expect(g(_sandwiches, 7), '43.57');
        expect(g(_wings, 8), '42.32');
        expect(
          basisOf(_sandwiches, 7),
          // RE-PIN (M66 batch, v65, Q1 b): the breading's carbohydrate named.
          contains(
            'USDA FNDDS 2706258 recipe: 25 g breading (USDA 99995000, 40.1 % '
            'carbohydrate) per 65 g raw haddock, matched by its carbohydrate',
          ),
        );
        expect(
          basisOf(_wings, 8),
          contains(
            'raw chicken wing (a batter read on a breading figure); '
            "the batter's excess not counted)",
          ),
        );
        expect(
          basisOf(_tempura, 2),
          // RE-PIN (M66 batch, v65, Q1 b): the breading's carbohydrate named.
          contains(
            'USDA FNDDS 2706364 recipe: 25 g breading (USDA 99995000, 40.1 % '
            'carbohydrate) per 65 g raw shrimp, matched by its carbohydrate; '
            "the batter's excess not counted)",
          ),
        );
      },
    );

    test("Q25 rides on W's grams: tempura's vodka keeps its 85 % flag at "
        '108.23 g (v89; was 105.05), the beers theirs', () {
      String? retention(String file, int position) => alcoholRetentionOf(
        recipes[file]!,
        nutritionLines(recipes[file]!)[position],
        rowOf(file, position),
      )?.flag;
      // RE-PIN (M66 batch, v65, Q8 b): a batter fried in oil names the
      // missing R6 row.
      expect(
        retention(_tempura, 4),
        'approximate (USDA retention: alcohol cooked 2 min keeps 85 %, the '
        'stirred-into-hot-liquid figure (USDA prints no row for a batter '
        'fried in oil))',
      );
      expect(retention(_fishChips, 10), contains('keeps 85 %'));
      expect(retention(_sandwiches, 10), contains('keeps 85 %'));
    });

    test(
      'S: a coat figure read on another food names the stand-in (five '
      'rows, grams unmoved); a same-family figure and a derived C3 do not',
      () {
        expect(_standIns, hasLength(5));
        expectRows(_standIns);
        // Same family (chicken on the breast, pork on the pork chop, beef on
        // the country-fried steak) or derived (C3): no suffix.
        expect(
          db
              .ingredientMatchesFor(recipes[_fishChips]!.id)
              .where((r) => r.gramSource == 'discarded')
              .map((r) => basisOf(_fishChips, r.position)!)
              .where((b) => b.contains('no record for')),
          isEmpty,
        );
        expect(
          basisOf('0279-crispy-salt-and-pepper-shrimp.yaml', 8),
          isNot(contains('no record for')),
        );
      },
    );

    test("Q10: negimaki's glaze states the printed split, counted whole "
        '(0 kcal)', () {
      expect(_negimaki, hasLength(4));
      expectRows(_negimaki);
    });

    test('the frying oils and the dips W does not read equal v56 (the '
        'scones, the truffles, the egg washes, the C3 shrimp)', () {
      expectRows(_kept);
    });

    test('the four recipes move kcal per serving only: statuses unchanged '
        '(tempura partial on its 0 g dipping-sauce reference)', () {
      (String, String) of(String file) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        return (n.status, n.caloriesPerServing!.toStringAsFixed(2));
      }

      // RE-PIN (M90 batch, v89, cornstarch): the coats re-solve (the replay
      // rows): was 280.02; 513.09, 1028.15.
      expect(of(_tempura), ('partial', '281.09')); // v56 381.94
      // RE-PIN (M82 batch, v84, C5a): the coats' flour re-solves (the
      // replay's 512.96 → 513.09, 1,028.23 → 1,028.15): was 512.96, 1028.23.
      // RE-PIN (M86 batch, v90, 958: 2727568 chicken): was 512.69.
      expect(of(_wings), ('complete', '521.61')); // v56 601.62
      expect(of(_sandwiches), ('complete', '1028.92')); // v56 1,057.75
      // fish-and-chips (replay 981.40, v56 1,003.49): its oil |1 reads
      // 172336 in a fresh compute, 2710187 in snapshot 23 (above) — the
      // status only.
      expect(of(_fishChips).$1, 'complete');
    });

    test('a second recompute writes nothing: the batter lines, written '
        "`discarded`, are parts again and never come off C5's B", () {
      for (final file in const [_tempura, _wings, _sandwiches, _fishChips]) {
        final recipe = recipes[file]!;
        final before = [
          for (final r in db.ingredientMatchesFor(recipe.id))
            (r.position, r.grams, r.updatedAt),
        ];
        expect(recomputeTotals(db, recipe), isTrue, reason: file);
        expect(
          [
            for (final r in db.ingredientMatchesFor(recipe.id))
              (r.position, r.grams, r.updatedAt),
          ],
          before,
          reason: file,
        );
      }
    });

    test("a person's CONFIRM of a batter line keeps the budget's grams the "
        'GET showed (verify2 D1, as for a coat): tempura|2 102.73, the '
        'totals unmoved', () async {
      final tempura = recipes[_tempura]!;
      final line = nutritionLines(tempura)[2];
      final basis = basisOf(_tempura, 2);
      final before = db.nutritionFor(tempura.id)!;
      await applyMatchOverride(db, provider, tempura, 2, {
        'raw': line.raw,
        'confirmed': true,
      });
      final row = rowOf(_tempura, 2);
      expect(
        (row.status, row.grams!.toStringAsFixed(2), row.gramSource),
        // RE-PIN (M90 batch, v89, cornstarch): was 99.71.
        ('confirmed', '102.73', 'discarded'),
      );
      expect(basisOf(_tempura, 2), basis);
      final shown = [
        for (final item
            in (await matchesBody(db, provider, tempura))['items']! as List)
          if ((item as Map<String, Object?>)['position'] == 2)
            (
              ((item['match']! as Map)['grams']! as double).toStringAsFixed(
                2,
              ),
              (item['match']! as Map)['gram_basis'],
            ),
      ];
      // RE-PIN (M90 batch, v89, cornstarch): was 99.71.
      expect(shown, [('102.73', basis)]);
      final after = db.nutritionFor(tempura.id)!;
      expect(
        (after.status, after.caloriesPerServing!.toStringAsFixed(2)),
        (before.status, before.caloriesPerServing!.toStringAsFixed(2)),
      );
    });
  });
}
