// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v61 (batch M62, egg dips sized by the read wet share, held-coat
// dips held, no crumb rule; matcherVersion 60; prep48 design_v2 §2 M62, §1
// Q9 with H as the owner's decision, §6 F12; the planner's E-w — the
// verified figures of scratchpad/fix61/plan_figures.md — decided 2026-10-08
// under the 2026-10-07 standing authorization; zero requests — FNDDS
// 2710785 was read at live step L; step-reading, pre-Q18): a coat's dip in
// an egg or buttermilk mixture whose excess the steps leave in the bowl
// (engine `_dipsOf`, `_dipExcess`'s first arm) counts W = 135 / (287 ×
// 0.401) g a gram of the carbohydrate the coat's parts count, shared by the
// dip lines' whole grams (E-w); the dip of a coat held with no budget is
// held `coating` with it (H); a dip with no coat keeps the D5 flag only.
// Every row value is the fresh compute of the WHOLE recipe over recorded
// real FDC answers (FixtureProvider; no fixture added), equal to the v61
// replay of snapshot 24 (rp43, fix61 r1) on every pinned row (grams,
// source, hold and basis; a few OTHER rows' energies differ in a fresh
// compute — the per-serving pin says where) and to the v60 rows on every
// row M62 must not move; never the network. Synthesized, STATED (no corpus
// recipe holds them): nothing in the row pins; the person's decisions
// below are real PUTs on computed copies of the corpus recipes.

import 'dart:io';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v80_test.dart' show friedOnionRings;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

/// (file, position, raw, fdc id, confidence, grams, kcal (null on a held or
/// gram-less row: it counts nothing), status, hold, basis) — a row of the
/// fresh compute.
typedef _Row = (
  String,
  int,
  String,
  int?,
  String,
  String?,
  String?,
  String,
  String?,
  String?,
);

const _almond = '0042-almond-crusted-chicken-with-wilted-spinach-salad.yaml';
const _breaded = '0114-breaded-chicken-cutlets.yaml';
const _katsu = '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml';
const _schnitzel = '0116-chicken-schnitzel.yaml';
const _nutCrusted =
    '0117-nut-crusted-chicken-breasts-with-lemon-and-thyme.yaml';
const _stuffed = '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml';
const _kiev = '0122-chicken-kiev.yaml';
const _crispyFried = '0148-crispy-fried-chicken.yaml';
const _porkChops = '0198-crispy-pan-fried-pork-chops.yaml';
const _crunchy = '0206-crunchy-baked-pork-chops.yaml';
const _porkSchnitzel = '0233-pork-schnitzel-breaded-pork-cutlets.yaml';
const _steaks = '0304-chicken-fried-steaks.yaml';
const _lighter = '0416-lighter-chicken-parmesan.yaml';
const _onionRings = '0315-oven-fried-onion-rings.yaml';

/// RE-PIN (M80 batch, v80, M80-1) — STATED synthesized: the fried copy of
/// 0315 ([friedOnionRings], nutrition_v80_test: its S3 fries the rings
/// instead of baking them), under its own id — a fried coated onion reads no
/// coat figure, so its coat holds with no budget and H holds the dips: the
/// owner's Q9 door, whose last corpus vehicle (the onion rings) M80 budgets.
const _ringsFried = '0315-oven-fried-onion-rings.yaml#fried';

/// [file]'s corpus recipe, or [_ringsFried]'s copy of 0315.
Recipe _load(String file) =>
    file == _ringsFried ? friedOnionRings() : loadCorpusRecipe(file);
const _eggplant = '0407-eggplant-parmesan.yaml';
const _parmesanCrusted = '0419-parmesan-crusted-chicken-cutlets.yaml';
const _francese = '0420-chicken-francese.yaml';
const _bestParmesan = '0415-best-chicken-parmesan.yaml';
const _spicy = '1185-spicy-fried-chicken-sandwiches.yaml';
const _fish = '0254-crunchy-oven-fried-fish.yaml';
const _orange = '0525-orange-flavored-chicken.yaml';
const _ovenFried = '0150-oven-fried-chicken.yaml';
const _francese2 = '1133-chicken-francese.yaml';

/// E-w's basis (plan_figures §1, byte for byte).
const _dipBasis =
    "discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat's carbohydrate — USDA FNDDS 2710785 \"Breading or batter as ingredient in food\": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip's excess not counted)";

/// RE-PIN (M66 batch, v65, R2): a dip line with a part a later step eats
/// (almond|6's "remaining ¼ teaspoon zest") reads the kept-part form.
const _dipKeptBasis =
    "discarded in cooking — only the part the recipe keeps and the dip on the food counted · approximation (dip: 1.17 g per g of the coat's carbohydrate — USDA FNDDS 2710785 \"Breading or batter as ingredient in food\": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip's excess not counted)";

/// RE-PIN (M73 batch, v73, pD C4): a Dijon dip line says its stand-in.
const _dipDijonBasis =
    "discarded in cooking — only the dip on the food counted · approximate (FDC holds no Dijon mustard — counted as prepared yellow mustard) · approximation (dip: 1.17 g per g of the coat's carbohydrate — USDA FNDDS 2710785 \"Breading or batter as ingredient in food\": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip's excess not counted)";

/// RE-PIN (M69 batch, v68): the coat flags of the coats M69 budgets.
const _c4Breast =
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast (no record for a sautéed flour dusting; read as the baked breaded breast, the lightest coat USDA prints; FNDDS 2706416 Veal Marsala's 62.5 g flour per 617.60 g raw veal, 7.82, counts the dish's whole flour, sauce included, and is not read); the dredge's excess not counted)";
const _eggplantCoat =
    "discarded in cooking — only the coat on the food counted · approximation (coat: 7.93 g carbohydrate per 100 g of the raw eggplant — USDA FNDDS 2710050 recipe: 13.2 g batter (4 g flour, 0.5 g dried egg, 8.3 g water, 0.3 g dry milk, 0.1 g baking powder; 3.28 g carbohydrate) per 41.4 g raw eggplant (a crumb coat read on a batter figure; 8.3 g of the 13.2 g batter is water and carries no carbohydrate); the dredge's excess not counted)";

/// The D5 flag (v50 Q21) the dips with no coat keep.
const _d5 =
    ' · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)';

/// M62 E-w's reach (plan_figures §2, §4: exactly these 28 rows, −1,413.53
/// kcal per batch by the rows): the 13 recipes with a budgeted coat, each dip
/// line at f_w = min(1, W / Σ its dips' whole grams) — breaded|4 41.92,
/// katsu|1 53.35, the two schnitzel lines by a making sentence two steps
/// back, kiev|12 by the unique-head clause, nut-crusted's |8 cayenne by A13's
/// shared-head order (the ceiling: |12 black pepper stays whole, below),
/// almond's three at C = Σ CHO 21.29 < B 35.74.
/// RE-PIN (M66 batch, v65): 30 rows — R3' gives the pepper dip to |12 (the
/// ceiling above closed), R3 + R1 + R2 move almond's three, R4 adds
/// best-chicken-parmesan's two (from _flagged).
const List<_Row> _dips = [
  (
    _breaded,
    4,
    '2 large eggs',
    748967,
    '0.920000',
    '41.92',
    '62.04',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _katsu,
    1,
    '2 large eggs',
    748967,
    '0.920000',
    '53.35',
    '78.96',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _schnitzel,
    1,
    '2 large eggs',
    748967,
    '0.920000',
    '46.80',
    '69.26',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _schnitzel,
    2,
    '1 tablespoon vegetable oil',
    2710180,
    '0.923333',
    '6.55',
    '58.95',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M66 batch, v65): R3' — the pepper dip is |12's (its own word 'black'), not |8's (v61's A13 ceiling, closed); |8 below in _negatives
  // RE-PIN (M80 batch, v80, M80-2: the dip follows B at FNDDS 2706442's crumb-crust k 12.12) (was 0.11 g, 0.28 kcal).
  (
    _nutCrusted,
    12,
    '¼ teaspoon ground black pepper',
    170931,
    '1.000000',
    '0.41',
    '1.03',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M66 batch, v65): R3' — f_w over 150 + 10.35 + 0.575 (the black pepper in the dip, the cayenne out)
  // RE-PIN (M80 batch, v80, M80-2: as |12) (was 27.60 g, 40.85 kcal).
  (
    _nutCrusted,
    10,
    '3 large eggs',
    748967,
    '0.920000',
    '105.19',
    '155.68',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M66 batch, v65): R3' — as |10
  // RE-PIN (M73 batch, v73): the Dijon flag (pD C4).
  // RE-PIN (M80 batch, v80, M80-2: as |12) (was 1.90 g, 1.16 kcal).
  (
    _nutCrusted,
    11,
    '2 teaspoons Dijon mustard',
    326698,
    '0.983333',
    '7.26',
    '4.43',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximate (FDC holds no Dijon mustard — counted as prepared yellow mustard) · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M80 batch, v80, M80-2: the dip follows B at 12.12) (was 23.26 g, 34.42 kcal).
  (
    _stuffed,
    11,
    '2 large eggs',
    748967,
    '0.920000',
    '88.67',
    '131.23',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M80 batch, v80, M80-2: the dip follows B at 12.12) (was 30.67 g, 45.39 kcal).
  (
    _kiev,
    12,
    '3 large eggs, beaten',
    748967,
    '0.920000',
    '116.88',
    '172.98',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M73 batch, v73): the Dijon flag (pD C4).
  // RE-PIN (M80 batch, v80, M80-2: as |12) (was 1.06 g, 0.65 kcal).
  (
    _kiev,
    13,
    '1 teaspoon Dijon mustard',
    326698,
    '0.983333',
    '4.03',
    '2.46',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximate (FDC holds no Dijon mustard — counted as prepared yellow mustard) · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _crispyFried,
    9,
    '1 large egg',
    748967,
    '0.920000',
    '21.71',
    '32.13',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _crispyFried,
    10,
    '1 teaspoon baking powder',
    172804,
    '0.850000',
    '1.97',
    '1.00',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _crispyFried,
    11,
    '½ teaspoon baking soda',
    175040,
    '0.900000',
    '1.00',
    '0.00',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _crispyFried,
    12,
    '1 cup buttermilk',
    2705393,
    '0.990000',
    '105.95',
    '45.56',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M82 batch, v84, C3a): was 46.82 g, 20.13 kcal (the v84 replay's row).
  (
    _porkChops,
    1,
    '1 cup buttermilk',
    2705393,
    '0.990000',
    '46.85',
    '20.15',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M73 batch, v73): the Dijon flag (pD C4).
  (
    _porkChops,
    2,
    '2 tablespoons Dijon mustard',
    326698,
    '0.983333',
    '5.96',
    '3.64',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximate (FDC holds no Dijon mustard — counted as prepared yellow mustard) · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M82 batch, v84, C3a): was 0.58 g, 0.83 kcal (the v84 replay's row).
  (
    _porkChops,
    3,
    '1 medium garlic clove, minced or pressed through a garlic press (about 1 teaspoon)',
    1104647,
    '0.970000',
    '0.54',
    '0.77',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _crunchy,
    11,
    '3 large egg whites',
    747997,
    '0.950000',
    '41.86',
    '23.02',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M73 batch, v73): the Dijon flag (pD C4).
  (
    _crunchy,
    12,
    '3 tablespoons Dijon mustard',
    326698,
    '0.983333',
    '19.69',
    '12.01',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximate (FDC holds no Dijon mustard — counted as prepared yellow mustard) · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _porkSchnitzel,
    2,
    '2 large eggs',
    748967,
    '0.920000',
    '38.11',
    '56.40',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _steaks,
    3,
    '1 large egg',
    748967,
    '0.920000',
    '14.58',
    '21.58',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _steaks,
    4,
    '1 teaspoon baking powder',
    172804,
    '0.850000',
    '1.32',
    '0.67',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _steaks,
    5,
    '½ teaspoon baking soda',
    175040,
    '0.900000',
    '0.67',
    '0.00',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _steaks,
    6,
    '1 cup buttermilk',
    2705393,
    '0.990000',
    '71.13',
    '30.59',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M80 batch, v80, M80-2: the dip follows B at 12.12) (was 23.79 g, 13.08 kcal).
  (
    _lighter,
    6,
    '3 large egg whites',
    747997,
    '0.950000',
    '90.69',
    '49.88',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M66 batch, v65): R3 + R1 + R2 — the almonds join the coat (f < 1, C = B 35.74) and the zest's eaten ¼ teaspoon leaves the dip
  (
    _almond,
    4,
    '2 large eggs',
    748967,
    '0.920000',
    '39.11',
    '57.88',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M66 batch, v65): as |4
  // RE-PIN (M73 batch, v73): the Dijon flag (pD C4).
  (
    _almond,
    5,
    '1 teaspoon Dijon mustard',
    326698,
    '0.983333',
    '2.02',
    '1.23',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximate (FDC holds no Dijon mustard — counted as prepared yellow mustard) · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M66 batch, v65): R2 — 0.78 g of dip + the ¼ teaspoon (0.50 g) S4 writes, eaten whole: the kept-part basis
  (
    _almond,
    6,
    '1¼ teaspoons grated zest from 1 orange',
    169103,
    '0.886667',
    '1.28',
    '1.24',
    'auto',
    null,
    'discarded in cooking — only the part the recipe keeps and the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M66 batch, v65): R4 — dips alone open the budget (W = 1.173026 × 5.73 × 396.89 / 100 = 26.68 g); moved here from _flagged
  // RE-PIN (M82 batch, v84, C5a): was 23.18 g, 34.31 kcal (the v84 replay's row).
  (
    _bestParmesan,
    12,
    '1 large egg',
    748967,
    '0.920000',
    '22.66',
    '33.54',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M66 batch, v65): R4 — as |12
  // RE-PIN (M82 batch, v84, C5a): was 3.50 g, 12.81 kcal (the v84 replay's row).
  (
    _bestParmesan,
    13,
    '1 tablespoon all-purpose flour',
    789890,
    '0.950000',
    '4.02',
    '14.71',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M69 batch, v68): five of M62 H's dips are E-w dips since v68 —
  // their coats are budgeted (C4 at 3.18 on francese and parmesan-crusted,
  // R2's eggplant at 7.93); was held `coating` with no grams in _held.
  (
    _eggplant,
    6,
    '4 large eggs',
    748967,
    '0.920000',
    '84.39',
    '124.90',
    'auto',
    null,
    _dipBasis,
  ),
  (
    _parmesanCrusted,
    4,
    '3 large egg whites',
    747997,
    '0.950000',
    '14.96',
    '8.23',
    'auto',
    null,
    _dipBasis,
  ),
  (
    _parmesanCrusted,
    5,
    '2 tablespoons minced fresh chives (optional)',
    169994,
    '0.920000',
    '0.91',
    '0.27',
    'auto',
    null,
    _dipBasis,
  ),
  (
    _francese,
    10,
    '2 large eggs',
    748967,
    '0.920000',
    '17.83',
    '26.39',
    'auto',
    null,
    _dipBasis,
  ),
  (
    _francese,
    11,
    '2 tablespoons milk',
    2705385,
    '0.910000',
    '5.43',
    '3.31',
    'auto',
    null,
    _dipBasis,
  ),
  // RE-PIN (M80 batch, v80, M80-1: the coat is budgeted on the onion at 50.53 — an E-w dip at share 1, no longer H) (was no g, 0.00 kcal, held `coating`).
  (
    _onionRings,
    1,
    '1 large egg, at room temperature',
    748967,
    '0.920000',
    '50.00',
    '74.00',
    'auto',
    null,
    "discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat's carbohydrate — USDA FNDDS 2710785 \"Breading or batter as ingredient in food\": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip's excess not counted)",
  ),
  // RE-PIN (M80 batch, v80, M80-1: as |1) (was no g, 0.00 kcal, held `coating`).
  (
    _onionRings,
    2,
    '½ cup buttermilk, at room temperature',
    2705393,
    '0.990000',
    '122.00',
    '52.46',
    'auto',
    null,
    "discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat's carbohydrate — USDA FNDDS 2710785 \"Breading or batter as ingredient in food\": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip's excess not counted)",
  ),
  // RE-PIN (M80 batch, v80, M80-1: as |1) (was no g, 0.00 kcal, held `coating`).
  (
    _onionRings,
    3,
    '½ teaspoon table salt',
    173468,
    '1.000000',
    '3.01',
    '0.00',
    'auto',
    null,
    "discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat's carbohydrate — USDA FNDDS 2710785 \"Breading or batter as ingredient in food\": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip's excess not counted)",
  ),
  // RE-PIN (M80 batch, v80, M80-1: as |1) (was no g, 0.00 kcal, held `coating`).
  (
    _onionRings,
    4,
    '¼ teaspoon ground black pepper',
    170931,
    '1.000000',
    '0.58',
    '1.46',
    'auto',
    null,
    "discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat's carbohydrate — USDA FNDDS 2710785 \"Breading or batter as ingredient in food\": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip's excess not counted)",
  ),
  // RE-PIN (M66 batch, v65): R3' — the bare "cayenne" of the buttermilk-mixture sentence names |5: held `coating` with its siblings (H)
  // RE-PIN (M80 batch, v80, M80-1: an E-w dip at share 1 with its siblings, no longer H) (was no g, 0.00 kcal, held `coating`).
  (
    _onionRings,
    5,
    '¼ teaspoon cayenne pepper',
    170932,
    '1.000000',
    '0.45',
    '1.43',
    'auto',
    null,
    "discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat's carbohydrate — USDA FNDDS 2710785 \"Breading or batter as ingredient in food\": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip's excess not counted)",
  ),
];

/// M62 H (the owner's Q9 door; plan_figures §3: 9 rows at v61, 4 since v68,
/// −646.74 kcal counted): the dip of a coat held with no budget (no coated
/// meat, or C4's sautéed dusting) held `coating` with it, no grams; the
/// design's 10th, oven-fried-onion-rings|5 cayenne, is beyond the line
/// rule's reach (A13's one 'pepper' word goes to |4) — a negative below.
/// RE-PIN (M80 batch, v80, M80-1): the onion rings' coat is budgeted on the
/// onion (50.53), their dips E-w (in _dips) — the corpus holds no dip of a
/// budget-less coat any more, so H is pinned on [_ringsFried], the STATED
/// synthesized fried copy (a fried coated onion reads no figure): its five
/// dip lines, |5 cayenne with them since v65 (R3').
const List<_Row> _held = [
  (
    _ringsFried,
    1,
    '1 large egg, at room temperature',
    748967,
    '0.920000',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  (
    _ringsFried,
    2,
    '½ cup buttermilk, at room temperature',
    2705393,
    '0.990000',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  (
    _ringsFried,
    3,
    '½ teaspoon table salt',
    173468,
    '1.000000',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  (
    _ringsFried,
    4,
    '¼ teaspoon ground black pepper',
    170931,
    '1.000000',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  (
    _ringsFried,
    5,
    '¼ teaspoon cayenne pepper',
    170932,
    '1.000000',
    null,
    '0.00',
    'auto',
    'coating',
    null,
  ),
];

/// No coat at all (no line held `coating`, none budgeted): the dip's lines
/// keep the D5 flag only — 7 rows, 0 kcal moved (plan_figures §1).
const List<_Row> _flagged = [
  (
    _spicy,
    2,
    '1 large egg',
    748967,
    '0.920000',
    '50.00',
    '74.00',
    'auto',
    null,
    '1 × 50 g each · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    _spicy,
    3,
    '3 tablespoons hot sauce, divided',
    2710093,
    '0.923333',
    '48.00',
    '5.76',
    'auto',
    null,
    '3 tablespoon · USDA portion · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  // RE-PIN (M82 batch, v84, C5a): was 7.54 g, 27.60 kcal (the v84 replay's row).
  (
    _spicy,
    4,
    '1 tablespoon all-purpose flour',
    789890,
    '0.950000',
    '8.86',
    '32.42',
    'auto',
    null,
    '1 tablespoon ≈ 15 mL · approximate (ATK: 1 cup all-purpose flour = 5 ounces) · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    _spicy,
    6,
    '⅛ teaspoon table salt',
    173468,
    '1.000000',
    '0.75',
    '0.00',
    'auto',
    null,
    '1/8 teaspoon ≈ 1 mL · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    _spicy,
    7,
    '⅛ teaspoon pepper',
    170931,
    '1.000000',
    '0.29',
    '0.72',
    'auto',
    null,
    '1/8 teaspoon · USDA portion · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
];

/// The coat's parts of the 13 E-w recipes, each equal to v60: E-w sizes
/// the dips from the carbohydrate the parts count and never re-splits them
/// (§2's one f would have moved 20 of them; F12's katsu|0 stays 63.19).
const List<_Row> _parts = [
  // RE-PIN (M82 batch, v84, C1+C5a): was 26.93 g, 71.63 kcal (the v84 replay's row).
  (
    _breaded,
    2,
    '3 slices high-quality white sandwich bread, torn into quarters',
    174924,
    '0.914286',
    '32.54',
    '86.56',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  // RE-PIN (M82 batch, v84, C1+C5a): was 29.01 g, 106.18 kcal (the v84 replay's row).
  (
    _breaded,
    3,
    '¾ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '25.43',
    '93.07',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    _katsu,
    0,
    '2 cups panko bread crumbs',
    174928,
    '0.563333',
    '63.19',
    '249.60',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  // RE-PIN (M82 batch, v84, C5a): was 13.58 g, 49.70 kcal (the v84 replay's row).
  (
    _schnitzel,
    0,
    '½ cup all-purpose flour',
    789890,
    '0.950000',
    '15.33',
    '56.11',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  // RE-PIN (M82 batch, v84, C5a): was 48.61 g, 192.01 kcal (the v84 replay's row).
  (
    _schnitzel,
    3,
    '2 cups plain dried bread crumbs',
    174928,
    '0.657500',
    '46.73',
    '184.58',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  // RE-PIN (M66 batch, v65): R3 — the almonds join the parts (f 0.1515)
  // RE-PIN (M80 batch, v80, M80-2: a crumb-crust part at 12.12, the nut crust's stand-in flagged) (was 8.96 g, 35.39 kcal).
  // RE-PIN (M82 batch, v84, C5a): was 34.14 g, 134.85 kcal (the v84 replay's row).
  (
    _nutCrusted,
    5,
    '1 cup panko bread crumbs',
    174928,
    '0.563333',
    '31.10',
    '122.84',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 12.12 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2706442 recipe: 112.25 g crust (81 g dry crumbs and 31.25 g flour as separate inputs; 82.46 g carbohydrate; the record's 18.75 g grated Parmesan follows its mozzarella and sauce — a topping, not read) per 680.4 g raw chicken (no record for a nut crust; read as FNDDS 2706442's crumb crust); the dredge's excess not counted)",
  ),
  // RE-PIN (M66 batch, v65): R3 — as |5
  // RE-PIN (M80 batch, v80, M80-2: as |5) (was 18.28 g, 66.90 kcal).
  // RE-PIN (M82 batch, v84, C5a): was 69.65 g, 254.92 kcal (the v84 replay's row).
  (
    _nutCrusted,
    9,
    '1 cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '74.54',
    '272.82',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 12.12 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2706442 recipe: 112.25 g crust (81 g dry crumbs and 31.25 g flour as separate inputs; 82.46 g carbohydrate; the record's 18.75 g grated Parmesan follows its mozzarella and sauce — a topping, not read) per 680.4 g raw chicken (no record for a nut crust; read as FNDDS 2706442's crumb crust); the dredge's excess not counted)",
  ),
  // RE-PIN (M80 batch, v80, M80-2: a crumb-crust part at 12.12) (was 14.32 g, 52.41 kcal).
  // RE-PIN (M82 batch, v84, C1+C5a): was 54.59 g, 199.80 kcal (the v84 replay's row).
  (
    _stuffed,
    10,
    '¾ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '46.76',
    '171.14',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 12.12 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2706442 recipe: 112.25 g crust (81 g dry crumbs and 31.25 g flour as separate inputs; 82.46 g carbohydrate; the record's 18.75 g grated Parmesan follows its mozzarella and sauce — a topping, not read) per 680.4 g raw chicken; the dredge's excess not counted)",
  ),
  // RE-PIN (M80 batch, v80, M80-2: as |10) (was 17.73 g, 47.16 kcal).
  // RE-PIN (M82 batch, v84, C1+C5a): was 67.57 g, 179.74 kcal (the v84 replay's row).
  (
    _stuffed,
    13,
    '4 slices high-quality white sandwich bread, pulsed in a food processor to coarse crumbs and dried',
    174924,
    '0.914286',
    '79.81',
    '212.29',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 12.12 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2706442 recipe: 112.25 g crust (81 g dry crumbs and 31.25 g flour as separate inputs; 82.46 g carbohydrate; the record's 18.75 g grated Parmesan follows its mozzarella and sauce — a topping, not read) per 680.4 g raw chicken; the dredge's excess not counted)",
  ),
  // RE-PIN (M80 batch, v80, M80-2: a crumb-crust part at 12.12) (was 20.38 g, 54.21 kcal).
  // RE-PIN (M82 batch, v84, C1+C5a): was 77.68 g, 206.63 kcal (the v84 replay's row).
  (
    _kiev,
    7,
    '4 slices high-quality white sandwich bread, torn into quarters',
    174924,
    '0.914286',
    '93.87',
    '249.69',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 12.12 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2706442 recipe: 112.25 g crust (81 g dry crumbs and 31.25 g flour as separate inputs; 82.46 g carbohydrate; the record's 18.75 g grated Parmesan follows its mozzarella and sauce — a topping, not read) per 680.4 g raw chicken; the dredge's excess not counted)",
  ),
  // RE-PIN (M80 batch, v80, M80-2: as |7) (was 21.96 g, 80.37 kcal).
  // RE-PIN (M82 batch, v84, C1+C5a): was 83.69 g, 306.31 kcal (the v84 replay's row).
  (
    _kiev,
    11,
    '1 cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '73.34',
    '268.42',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 12.12 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2706442 recipe: 112.25 g crust (81 g dry crumbs and 31.25 g flour as separate inputs; 82.46 g carbohydrate; the record's 18.75 g grated Parmesan follows its mozzarella and sauce — a topping, not read) per 680.4 g raw chicken; the dredge's excess not counted)",
  ),
  (
    _crispyFried,
    8,
    '4 cups (20 ounces) unbleached all-purpose flour',
    789890,
    '0.950000',
    '144.06',
    '527.26',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 8.79 g carbohydrate per 100 g of the raw chicken — USDA FNDDS 2705842 recipe: 20 g breading per 90.99 g raw beef steak (no record for chicken; read as Beef, steak, country fried); the dredge's excess not counted)",
  ),
  (
    _porkChops,
    0,
    '⅔ cup cornstarch',
    169698,
    '1.000000',
    '49.83',
    '189.85',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
  // RE-PIN (M82 batch, v84, C1+C5a): was 74.70 g, 198.70 kcal (the v84 replay's row).
  (
    _crunchy,
    2,
    '4 slices high-quality white sandwich bread, torn into 1-inch pieces',
    174924,
    '0.914286',
    '81.33',
    '216.34',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 6.61 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705871 recipe: 10 g breading per 108.38 g raw pork chop; the dredge's excess not counted)",
  ),
  // RE-PIN (M82 batch, v84, C1+C5a): was 65.37 g, 239.25 kcal (the v84 replay's row).
  (
    _crunchy,
    10,
    '¼ cup plus 6 tablespoons unbleached all-purpose flour',
    789890,
    '0.950000',
    '69.04',
    '252.69',
    'auto',
    null,
    'discarded in cooking — only "plus 6 tablespoons unbleached all-purpose flour" and the coat on the food counted · approximation (coat: 6.61 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705871 recipe: 10 g breading per 108.38 g raw pork chop; the dredge\'s excess not counted)',
  ),
  // RE-PIN (M82 batch, v84, C5a): was 39.27 g, 104.46 kcal (the v84 replay's row).
  (
    _porkSchnitzel,
    0,
    '7 slices high-quality white sandwich bread, crusts removed, cut into ¾-inch cubes (about 4 cups)',
    174924,
    '0.914286',
    '36.69',
    '97.60',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
  // RE-PIN (M82 batch, v84, C5a): was 16.92 g, 61.93 kcal (the v84 replay's row).
  (
    _porkSchnitzel,
    1,
    '½ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '18.57',
    '67.97',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
  (
    _steaks,
    0,
    '3 cups unbleached all-purpose flour',
    789890,
    '0.950000',
    '96.71',
    '353.96',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 8.79 g carbohydrate per 100 g of the raw beef — USDA FNDDS 2705842 recipe: 20 g breading per 90.99 g raw beef steak; the dredge's excess not counted)",
  ),
  // RE-PIN (M66 batch, v65): R3 — the Parmesan joins the parts
  // RE-PIN (M80 batch, v80, M80-2: a crumb-crust part at 12.12) (was 15.78 g, 62.33 kcal).
  // RE-PIN (M82 batch, v84, C5a): was 60.16 g, 237.63 kcal (the v84 replay's row).
  // RE-PIN (M85 batch, v87): was 56.15 g, 221.79 kcal — the budget
  // re-solves on its Parmesan part's SR 170848 (the v87 replay's row).
  (
    _lighter,
    0,
    '1½ cups panko (Japanese-style bread crumbs)',
    174928,
    '0.880000',
    '57.37',
    '226.61',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 12.12 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2706442 recipe: 112.25 g crust (81 g dry crumbs and 31.25 g flour as separate inputs; 82.46 g carbohydrate; the record's 18.75 g grated Parmesan follows its mozzarella and sauce — a topping, not read) per 680.4 g raw chicken; the dredge's excess not counted)",
  ),
  // RE-PIN (M66 batch, v65): R3 — as |0
  // RE-PIN (M80 batch, v80, M80-2: as |0) (was 10.73 g, 39.27 kcal).
  // RE-PIN (M82 batch, v84, C5a): was 40.91 g, 149.73 kcal (the v84 replay's row).
  // RE-PIN (M85 batch, v87): was 44.85 g, 164.15 kcal — as |0 (the v87
  // replay's row).
  (
    _lighter,
    3,
    '½ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '45.83',
    '167.74',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 12.12 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2706442 recipe: 112.25 g crust (81 g dry crumbs and 31.25 g flour as separate inputs; 82.46 g carbohydrate; the record's 18.75 g grated Parmesan follows its mozzarella and sauce — a topping, not read) per 680.4 g raw chicken; the dredge's excess not counted)",
  ),
  // RE-PIN (M66 batch, v65): R3 — the almonds join the parts (f 0.8692)
  (
    _almond,
    3,
    '½ cup panko (Japanese-style bread crumbs)',
    174928,
    '0.880000',
    '25.71',
    '101.55',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  // RE-PIN (M80 batch, v80, M80-1: a coat part at f = 1 on the onion at 50.53 (its eaten ¼ cup on top), no longer held) (was 30.16 g, 0.00 kcal, held `coating`).
  // RE-PIN (M82 batch, v84, C5a): was 60.33 g, 220.81 kcal (the v84 replay's row).
  (
    _onionRings,
    0,
    '½ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '70.87',
    '259.38',
    'auto',
    null,
    "discarded in cooking — only the part the recipe keeps and the coat on the food counted · approximation (coat: 50.53 g carbohydrate per 100 g of the raw onions — USDA FNDDS 2710042 recipe: 50 g breading per 39.58 g raw cauliflower (no record for onions; read as Fried cauliflower); the dredge's excess not counted)",
  ),
  // RE-PIN (M80 batch, v80, M80-1: a coat part at f = 1, no longer held) (was no g, 0.00 kcal, held `coating`).
  (
    _onionRings,
    6,
    '30 saltine crackers',
    2708167,
    '0.990000',
    '90.00',
    '376.20',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 50.53 g carbohydrate per 100 g of the raw onions — USDA FNDDS 2710042 recipe: 50 g breading per 39.58 g raw cauliflower (no record for onions; read as Fried cauliflower); the dredge's excess not counted)",
  ),
  // RE-PIN (M80 batch, v80, M80-1: as |6) (was no g, 0.00 kcal, held `coating`).
  (
    _onionRings,
    7,
    '4 cups kettle-cooked potato chips',
    2709422,
    '0.990000',
    '100.00',
    '532.00',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 50.53 g carbohydrate per 100 g of the raw onions — USDA FNDDS 2710042 recipe: 50 g breading per 39.58 g raw cauliflower (no record for onions; read as Fried cauliflower); the dredge's excess not counted)",
  ),
];

/// Rows M62 must not move (plan_figures §4, each equal to v60): the egg
/// dips with no "excess" (crunchy-oven-fried-fish|6, orange-flavored|12,
/// oven-fried-chicken|9, chicken-francese-2|6), the frying oils' kept parts
/// beaten into the dip (breaded|5, stuffed|12, pork-schnitzel|3 — a medium
/// line is no dip line), pork-schnitzel|9's garnish egg (A13: the second
/// 'egg' line), crispy-fried|3's brine, spicy|5's garlic powder (named by no
/// sentence), the rule rows with no record (almond|1, katsu|2, lighter|7,
/// francese|8), the stated A13 ceiling (nut-crusted|12 black pepper and
/// onion-rings|5 cayenne counted whole), and the coats already held.
const List<_Row> _negatives = [
  (
    _fish,
    6,
    '2 large eggs',
    748967,
    '0.920000',
    '100.00',
    '148.00',
    'auto',
    null,
    '2 × 50 g each',
  ),
  (
    _orange,
    12,
    '3 large egg whites',
    747997,
    '0.950000',
    '99.00',
    '54.45',
    'auto',
    null,
    '3 × 33 g each',
  ),
  (
    _ovenFried,
    9,
    '2 large eggs',
    748967,
    '0.920000',
    '100.00',
    '148.00',
    'auto',
    null,
    '2 × 50 g each',
  ),
  (
    _francese2,
    6,
    '3 large eggs',
    748967,
    '0.920000',
    '150.00',
    '222.00',
    'auto',
    null,
    '3 × 50 g each',
  ),
  (
    _breaded,
    5,
    '1 tablespoon plus ¾ cup vegetable oil',
    2710180,
    '0.923333',
    '55.66',
    '500.94',
    'auto',
    null,
    'discarded in cooking — only "1 tablespoon" and the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast\'s weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)',
  ),
  (
    _stuffed,
    12,
    '1 tablespoon plus ¾ cup vegetable oil',
    2710180,
    '0.923333',
    '55.66',
    '500.94',
    'auto',
    null,
    'discarded in cooking — only "1 tablespoon" and the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast\'s weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)',
  ),
  (
    _porkSchnitzel,
    3,
    '2 cups plus 1 tablespoon vegetable oil',
    2710180,
    '0.923333',
    '51.87',
    '466.83',
    'auto',
    null,
    'discarded in cooking — only "plus 1 tablespoon vegetable oil" and the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw pork\'s weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw))',
  ),
  (
    _porkSchnitzel,
    9,
    '1 large hard-cooked egg (this page), yolk and white separated and passed separately through a fine-mesh strainer (optional)',
    173424,
    '0.940000',
    '50.00',
    '77.50',
    'auto',
    null,
    '1 × 50 g each',
  ),
  (
    _crispyFried,
    3,
    '7 cups buttermilk',
    2705393,
    '0.990000',
    '0.00',
    '0.00',
    'auto',
    null,
    'discarded in cooking — counted as 0 g',
  ),
  (
    _spicy,
    5,
    '½ teaspoon garlic powder',
    171325,
    '0.933333',
    '1.55',
    '5.14',
    'auto',
    null,
    '1/2 teaspoon ≈ 2 mL',
  ),
  (
    _almond,
    1,
    'Table salt and ground black pepper',
    null,
    '1.000000',
    null,
    null,
    'confirmed',
    null,
    null,
  ),
  (
    _katsu,
    2,
    'Salt',
    null,
    '1.000000',
    null,
    null,
    'confirmed',
    null,
    null,
  ),
  (
    _lighter,
    7,
    '1 tablespoon water',
    null,
    '1.000000',
    null,
    null,
    'confirmed',
    null,
    null,
  ),
  (
    _francese,
    8,
    'Table salt and ground black pepper',
    null,
    '1.000000',
    null,
    null,
    'confirmed',
    null,
    null,
  ),
  // RE-PIN (M66 batch, v65): R3' — the cayenne goes into the panko mixture, counted whole (its v60 state); |12 is the dip now, above
  (
    _nutCrusted,
    8,
    '⅛ teaspoon cayenne pepper',
    170932,
    '1.000000',
    '0.23',
    '0.72',
    'auto',
    null,
    '1/8 teaspoon · USDA portion',
  ),
  // RE-PIN (M69 batch, v68): budgeted since v68 (R2, the eggplant at 7.93), no longer held.
  // RE-PIN (M82 batch, v84, C1+C5a): was 76.37 g, 203.14 kcal (the v84 replay's row).
  // RE-PIN (M85 batch, v87): was 88.21 g, 234.64 kcal — the budget
  // re-solves on its Parmesan part's SR 170848 (the v87 replay's row).
  (
    _eggplant,
    2,
    '8 slices high-quality white sandwich bread, torn into quarters',
    174924,
    '0.914286',
    '89.79',
    '238.84',
    'auto',
    null,
    _eggplantCoat,
  ),
  // RE-PIN (M69 batch, v68): budgeted since v68 (R2, the eggplant at 7.93), no longer held.
  // RE-PIN (M82 batch, v84, C1+C5a): was 19.33 g, 81.38 kcal (the v84 replay's row).
  // RE-PIN (M85 batch, v87): SR 170848 "Cheese, parmesan, hard" at 1.0 (was
  // 325036 at 0.983333, 13.78 g, 58.01 kcal; the v87 replay's row).
  (
    _eggplant,
    3,
    '2 ounces Parmesan cheese, grated (about 1 cup)',
    170848,
    '1.000000',
    '14.03',
    '55.00',
    'auto',
    null,
    _eggplantCoat,
  ),
  // RE-PIN (M69 batch, v68): budgeted since v68 (R2, the eggplant at 7.93), no longer held.
  // RE-PIN (M82 batch, v84, C1+C5a): was 41.14 g, 150.57 kcal (the v84 replay's row).
  // RE-PIN (M85 batch, v87): was 34.46 g, 126.12 kcal — as |2 (the v87
  // replay's row).
  (
    _eggplant,
    5,
    '1 cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '35.07',
    '128.36',
    'auto',
    null,
    _eggplantCoat,
  ),
  // RE-PIN (M69 batch, v68): budgeted since v68 (R1, C4 at 3.18), no longer held.
  (
    _parmesanCrusted,
    2,
    '5 tablespoons unbleached all-purpose flour',
    789890,
    '0.950000',
    '17.49',
    '64.01',
    'auto',
    null,
    _c4Breast,
  ),
  // RE-PIN (M78 batch, v78, the owner's Q6 (c)): the pressed crust counts
  // its whole line, flagged — was held `coating`, no grams.
  // RE-PIN (M85 batch, v87): SR 170848 at 1.0 (was 325036 at 0.983333,
  // 775.78 kcal; the v87 replay's row).
  (
    _parmesanCrusted,
    3,
    '¼ cup grated Parmesan cheese plus 6 ounces, shredded (about 2 cups; see note)',
    170848,
    '1.000000',
    '184.27',
    '722.34',
    'auto',
    null,
    "1/4 cup ≈ 59 mL · grated, at ATK's printed 1 ounce = ½ cup + 6 ounces · approximate (a pressed cheese crust: no USDA record of a cheese crust, and the coat record's breading does not describe one — the line counted whole as printed; the part left in the dish is not deducted)",
  ),
  // RE-PIN (M69 batch, v68): budgeted since v68 (R1, C4 at 3.18), no longer held.
  (
    _francese,
    9,
    '1 cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '25.66',
    '93.92',
    'auto',
    null,
    _c4Breast,
  ),
];

/// Each H recipe's dip sentence as written — its held rows' `hold_note`.
const Map<String, String> _heldNotes = {
  _eggplant:
      'Remove the slices, shaking off the excess flour, dip into the eggs, let the excess egg run off, then coat evenly with the bread-crumb mixture; set the breaded slices on a wire rack set over a baking sheet.',
  // RE-PIN (M80 batch, v80, M80-1): H's dips are the fried copy's (the
  // corpus rings' are budgeted); the same S2 sentence.
  _ringsFried:
      'Dip in the buttermilk mixture, allowing the excess to drip back into the bowl, then drop into the crumb coating, turning the ring over to coat evenly.',
  _parmesanCrusted:
      'Working with 1 chicken cutlet at a time, dredge in the flour mixture, shaking off the excess, then coat with the egg white mixture, allowing the excess to drip off.',
  _francese:
      'Working with 1 chicken cutlet at a time, dredge in the flour, shaking off the excess, then coat with the egg mixture, allowing the excess to drip off.',
};

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
  group('matcher v61 (batch M62)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;
    final recipes = <String, Recipe>{};

    /// [recipe] stored and computed whole, its sections first, as the
    /// replay does; the stored recipe.
    Future<Recipe> compute(Recipe recipe) async {
      db.upsertRecipe(recipe, sourceSlug: _source, contentHash: recipe.id);
      final stored = db.recipeByIdOrSlug(recipe.id)!.recipe;
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
      return db.recipeByIdOrSlug(recipe.id)!.recipe;
    }

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v61-');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath)
        ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: pendingSearches);
      for (final (file, _, _, _, _, _, _, _, _, _) in [
        ..._dips,
        ..._held,
        ..._flagged,
        ..._parts,
        ..._negatives,
      ]) {
        if (!recipes.containsKey(file)) {
          recipes[file] = await compute(_load(file));
        }
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    IngredientMatchRow rowIn(Recipe recipe, int position) => db
        .ingredientMatchesFor(recipe.id)
        .singleWhere((m) => m.position == position);

    String? basisIn(Recipe recipe, int position) => gramBasisFor(
      db,
      nutritionLines(recipe)[position],
      rowIn(recipe, position),
      recipe: recipe,
    );

    /// Each [rows] entry in its whole recipe: the record, the confidence,
    /// the grams, the energy, the status, the hold and the basis.
    void expectRows(List<_Row> rows) {
      for (final (
            file,
            position,
            raw,
            fdcId,
            confidence,
            grams,
            kcal,
            status,
            hold,
            basis,
          )
          in rows) {
        final recipe = recipes[file]!;
        final line = nutritionLines(recipe)[position];
        final row = rowIn(recipe, position);
        final reason = '$file|$position';
        expect(line.raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.confidence.toStringAsFixed(6), confidence, reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(row.status, status, reason: reason);
        expect(row.hold, hold, reason: reason);
        if (kcal != null) {
          expect(
            _kcalOf(db, row, line).toStringAsFixed(2),
            kcal,
            reason: reason,
          );
        }
        expect(basisIn(recipe, position), basis, reason: reason);
      }
    }

    String g2(double v) => v.toStringAsFixed(2);

    test('E-w reaches exactly its 40 dip rows (28 at v61, 35 at v68), each '
        '`discarded` with the '
        'read wet share in its basis (plan_figures §4)', () {
      // RE-PIN (M66 batch, v65): 30 rows, almond|6 in the kept-part form.
      // RE-PIN (M69 batch, v68): 35 rows — five of H's dips are budgeted.
      // RE-PIN (M80 batch, v80, M80-1): 40 rows — the onion rings' five
      // dips are budgeted on the onion (H's last five corpus rows).
      expect(_dips, hasLength(40));
      // RE-PIN (M73 batch, v73): the five Dijon dips in the flagged form.
      expect(
        _dips.every(
          (r) =>
              r.$10 == _dipBasis ||
              r.$10 == _dipKeptBasis ||
              r.$10 == _dipDijonBasis,
        ),
        isTrue,
      );
      expect(_dips.where((r) => r.$10 == _dipDijonBasis), hasLength(5));
      expectRows(_dips);
      for (final (file, position, _, _, _, _, _, _, _, _) in _dips) {
        expect(
          rowIn(recipes[file]!, position).gramSource,
          'discarded',
          reason: '$file|$position',
        );
      }
    });

    test("the coat's parts of the 14 recipes — E-w never re-splits them "
        "(F12: katsu|0 63.19, not §2-E's 62.49)", () {
      // RE-PIN (M80 batch, v80): 24 parts — the onion rings' |0 |6 |7
      // (M80-1); the crumb crusts' parts at 12.12 (M80-2) re-pinned in place.
      expect(_parts, hasLength(24));
      expectRows(_parts);
      expect(rowIn(recipes[_katsu]!, 0).grams, 63.19);
    });

    test('E-w by hand: W = 135 / (287 × 0.401) g a gram of the carbohydrate '
        "C the coat counts (B = k × the coated food / 100, or the parts' Σ "
        "when it is smaller), shared by the dip lines' whole grams", () {
      const w = (15 + 120) / (287 * 0.401);
      expect(w.toStringAsFixed(6), '1.173026');
      // One dip line each, C = B on the fried breast's 5.73.
      for (final (file, coated, dip, whole, grams) in [
        (_breaded, 0, 4, 100.0, '41.92'),
        (_katsu, 3, 1, 100.0, '53.35'),
      ]) {
        final b = 5.73 * rowIn(recipes[file]!, coated).grams! / 100;
        expect(
          g2(min(1, w * b / whole) * whole),
          grams,
          reason: '$file|$dip',
        );
        expect(g2(rowIn(recipes[file]!, dip).grams!), grams, reason: file);
      }
      // Two dip lines (the eggs and the tablespoon of oil beaten in, made
      // two steps before the dip): W shared by 114 g.
      final schnitzel = recipes[_schnitzel]!;
      final w2 = w * 5.73 * rowIn(schnitzel, 4).grams! / 100;
      expect(g2(w2 / 114 * 100), '46.80');
      expect(g2(w2 / 114 * 14), '6.55');
      // Almond: its one counted part (panko |3, whole at f = 1) carries C =
      // 21.29 g of carbohydrate (its line's whole grams, as the plan reads
      // them), less than B = 35.74.
      final almond = recipes[_almond]!;
      (double, FdcFood) whole(int p) {
        final line = nutritionLines(almond)[p];
        final food = knownFood(db, rowIn(almond, p).fdcId!, line: line)!;
        return (lineGrams(db, line, food, recipe: almond)!.grams, food);
      }

      final (panko, crumbs) = whole(3);
      final cho = panko * crumbs.nutrientsPer100g['205']! / 100;
      expect(g2(cho), '21.29');
      expect(g2(5.73 * rowIn(almond, 0).grams! / 100), '35.74');
      final dips = whole(4).$1 + whole(5).$1 + whole(6).$1;
      expect(g2(dips), '107.68');
      expect(g2(w * cho / dips * 100), '23.19');
    });

    test('H: the dip of a coat held with no budget is held `coating` with it '
        '(9 rows at v61, 4 at v68; since v80 the STATED fried onion-ring '
        "copy's 5 — the owner's Q9 door) — no grams, its "
        '`hold_note` the dip '
        'sentence; the coats already held stay as v60', () async {
      // RE-PIN (M69 batch, v68): 4 rows — the onion rings' (no sourced
      // figure); the eggplant's, francese's and parmesan-crusted's coats are
      // budgeted since v68 (their dips in _dips).
      // RE-PIN (M80 batch, v80, M80-1): 5 rows — the fried copy's |1–|5 (the
      // corpus rings' dips are E-w now; the copy's |5 is held with them).
      expect(_held, hasLength(5));
      expectRows(_held);
      for (final (file, position, _, _, _, _, _, _, _, _) in _held) {
        final recipe = recipes[file]!;
        final row = rowIn(recipe, position);
        expect(row.gramSource, isNull, reason: '$file|$position');
        expect(
          holdNoteOf(recipe, nutritionLines(recipe)[position], row.hold),
          _heldNotes[file],
          reason: '$file|$position',
        );
        final item =
            ((await matchesBody(db, provider, recipe))['items']!
                as List<Map<String, Object?>>)[position];
        expect(
          (item['match']! as Map)['hold_note'],
          _heldNotes[file],
          reason: '$file|$position',
        );
      }
      // The coat's own held line keeps its own note. RE-PIN (M80 batch,
      // v80): on the fried copy (the corpus rings' coat is budgeted).
      final rings = recipes[_ringsFried]!;
      expect(
        holdNoteOf(rings, nutritionLines(rings)[0], 'coating'),
        '¼ cup flour is used outside the dredge, eaten',
      );
    });

    test('no coat at all: the dip keeps the D5 flag only (7 rows, 0 kcal '
        'moved); spicy|5 garlic powder, named by no sentence, unflagged', () {
      // RE-PIN (M66 batch, v65, R4): best-chicken-parmesan's two are dips.
      expect(_flagged, hasLength(5));
      expect(_flagged.every((r) => r.$10!.endsWith(_d5)), isTrue);
      expectRows(_flagged);
    });

    test('the rows M62 must not move equal v60 (plan_figures §4: no excess '
        'phrase, the kept oil parts, the garnish egg, the brine, the rule '
        'rows, the A13 ceiling, the coats already held)', () {
      expectRows(_negatives);
    });

    test('per serving: the 13 E-w recipes and the 4 H recipes move; no '
        'status moves at v61 (since v80 the onion rings complete)', () {
      (String, String, int?) of(String file) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        return (
          n.status,
          n.caloriesPerServing!.toStringAsFixed(2),
          n.matchedCount,
        );
      }

      // The replay's figure first where a fresh compute differs: a chicken,
      // pork or eggplant record reads another energy here (its rows' grams
      // are equal; plan_figures §2's per serving are the replay's).
      // RE-PIN (M82 batch, v84): was 350.48 (the replay 350.53 → 350.98).
      expect(of(_breaded), (
        'complete',
        '350.93',
        7,
      )); // replay 350.53; v60 372.02
      expect(of(_katsu), ('complete', '411.79', 5)); // 411.86; 429.12
      // RE-PIN (M82 batch, v84): was 423.57 (the replay 423.64 → 423.39).
      expect(of(_schnitzel), ('complete', '423.32', 9)); // 423.64; 460.09
      // RE-PIN (M66 batch, v65): nut-crusted, lighter and almond complete —
      // the nut or cheese layer R3 releases was each one's only uncounted
      // line; onion-rings' cayenne joins the held dip (R3').
      // RE-PIN (M80 batch, v80, M80-2): the crumb crusts at FNDDS 2706442's
      // 12.12 — nut-crusted 575.50 (was 385.78; the v80 replay 385.84 →
      // 575.56), stuffed 638.65 (was 544.46; 544.51 → 638.71), kiev 667.05
      // (was 540.11; 540.19 → 667.12).
      // RE-PIN (M82 batch, v84): was 575.50 (the replay 575.56 → 566.38).
      expect(of(_nutCrusted), ('complete', '566.32', 13)); // 575.56; 407.15
      // RE-PIN (M82 batch, v84): was 638.65 (the replay 638.71 → 639.11).
      expect(of(_stuffed), ('complete', '639.06', 14)); // 638.71; 572.91
      // RE-PIN (M82 batch, v84): was 667.05 (the replay 667.12 → 668.42).
      expect(of(_kiev), ('complete', '668.35', 14)); // 667.12; 584.97
      expect(of(_crispyFried), ('complete', '832.44', 13)); // = replay; 858.08
      // RE-PIN (M82 batch, v84): was 480.50 (the replay 480.50 → 480.49).
      expect(of(_porkChops), ('partial', '480.49', 8)); // = replay; 506.39
      // RE-PIN (M82 batch, v84): was 468.36 (the replay 468.90 → 476.47).
      // RE-PIN (M85 batch, v87): was 475.93 (the replay 476.47 → 475.96:
      // |7's Parmesan on 170848).
      expect(of(_crunchy), ('complete', '475.41', 14)); // 468.90; 480.86
      // RE-PIN (M82 batch, v84): was 367.75 (the replay 367.75 → 367.54).
      expect(of(_porkSchnitzel), (
        'complete',
        '367.54',
        10,
      )); // = replay; 390.64
      // RE-PIN (M82 batch, v84): was 534.48 (the replay 534.48 → 536.79).
      expect(of(_steaks), ('complete', '536.79', 18)); // = replay; 555.87
      // RE-PIN (M70 batch, v69, pE Q6): 235.22 (was 235.25) — its two
      // minced basil tablespoons on SR's chopped 2.65 g (replay 235.29 →
      // 235.26).
      // RE-PIN (M80 batch, v80, M80-2): 298.93 (was 235.22; the v80 replay
      // 235.26 → 298.97).
      // RE-PIN (M82 batch, v84): was 298.93 (the replay 298.97 → 297.64).
      // RE-PIN (M85 batch, v87): was 297.61 (the replay 297.64 → 298.43: the
      // coat re-solves on its Parmesan part's 170848).
      expect(of(_lighter), ('complete', '298.40', 12)); // 298.97; 239.19
      expect(of(_almond), ('complete', '520.26', 11)); // 520.31; 431.67
      // H: the counted lines fall by the held dips.
      // RE-PIN (M69 batch, v68): the eggplant (R2), parmesan-crusted and
      // francese (R1, C4) coats are budgeted — their dips counted; francese
      // turns complete (was 360.35 / 12, 153.50 / 4, partial 407.39 / 12).
      // RE-PIN (M70 batch, v69, pE Q6): 454.04 (was 453.68) — its chopped
      // basil |12 on SR's chopped cup (replay 453.66 → 454.01).
      // RE-PIN (M77 batch, v77): the EVOO rows at SR 171413's 884 kcal — was 454.04.
      // RE-PIN (M82 batch, v84): was 455.88 (the replay 455.86 → 452.38).
      // RE-PIN (M85 batch, v87): was 452.40 (the replay 452.38 → 451.58: the
      // coat re-solves on its Parmesan part's 170848, |15 on it too).
      expect(of(_eggplant), (
        'partial',
        '451.60',
        16,
      )); // replay 453.66; v67 360.33; v60 409.66, 13
      // RE-PIN (M80 batch, v80, M80-1): the coat budgeted on the onion —
      // complete 10/10 (was partial, 217.50, 2; = the v80 replay).
      // RE-PIN (M82 batch, v84): was 532.09 (the replay 532.09 → 541.73).
      expect(of(_onionRings), (
        'complete',
        '541.73',
        10,
      )); // = replay; 249.84, 7
      // RE-PIN (M78 batch, v78): the crust counted whole (Q6 (c)) and |6's
      // pan fat (Q7 (c)) — complete (was partial, 171.63, 7; the v78 replay
      // 171.67 → 340.01).
      // RE-PIN (M85 batch, v87): was 339.97 (the replay 340.01 → 326.65: the
      // crust's Parmesan on 170848).
      expect(of(_parmesanCrusted), (
        'complete',
        '326.61',
        8,
      )); // replay 340.01; v67 153.54; v60 167.60, 6
      // RE-PIN (M78 batch, v78, Q7 (c)): |12 and |13's pan fat, wiped out
      // after each batch (S5) — was 438.29 (the v78 replay 438.34 → 346.62).
      // RE-PIN (M82 batch, v84): was 346.57 (the replay 346.62 → 347.83).
      expect(of(_francese), (
        'complete',
        '347.78',
        15,
      )); // replay 346.62; v67 407.44; v60 449.08, 14
    });

    test('a second recompute writes nothing', () {
      for (final recipe in recipes.values) {
        List<(int, double?, String?, String?, String?)> rows() => [
          for (final r in db.ingredientMatchesFor(recipe.id))
            (r.position, r.grams, r.gramSource, r.hold, r.updatedAt),
        ];
        final before = rows();
        expect(recomputeTotals(db, recipe), isTrue, reason: recipe.slug);
        expect(rows(), before, reason: recipe.slug);
      }
    });

    test('the matches GET plans M52 once per request and every line shows '
        "the memo-free per-row plan's basis", () async {
      var dips = 0;
      for (final MapEntry(key: file, value: recipe) in recipes.entries) {
        m52PlanRuns = 0;
        final items =
            (await matchesBody(db, provider, recipe))['items']!
                as List<Map<String, Object?>>;
        expect(m52PlanRuns, lessThanOrEqualTo(1), reason: file);
        for (final (position, line) in nutritionLines(recipe).indexed) {
          final match = items[position]['match'] as Map<String, Object?>?;
          // RE-PIN (M66 batch, v65): the kept-part form is a dip too.
          // RE-PIN (M73 batch, v73): and the Dijon dips' flagged form.
          if (match?['gram_basis'] == _dipBasis ||
              match?['gram_basis'] == _dipKeptBasis ||
              match?['gram_basis'] == _dipDijonBasis) {
            dips++;
          }
          expect(
            match?['gram_basis'],
            match == null
                ? null
                : gramBasisFor(
                    db,
                    line,
                    rowIn(recipe, position),
                    recipe: recipe,
                  ),
            reason: '$file|$position',
          );
        }
      }
      expect(dips, _dips.length);
    });

    /// [corpus] with [id] appended to its id and slug, computed whole.
    Future<Recipe> variant(String file, String id) {
      final corpus = _load(file);
      return compute(
        corpus.copyWith(id: '${corpus.id}-$id', slug: '${corpus.slug}-$id'),
      );
    }

    test("a person's decision on a dip row (real PUTs on computed copies): "
        "an E-w dip's confirm keeps the plan's grams `discarded` (M58 W's "
        "precedent); an H dip's confirm is 0 g poured away, a pick keeps the "
        'hold, typed grams stand; a recompute keeps each', () async {
      Future<IngredientMatchRow> put(
        Recipe recipe,
        int position,
        Map<String, Object?> body,
      ) async {
        await applyMatchOverride(db, provider, recipe, position, {
          'raw': nutritionLines(recipe)[position].raw,
          ...body,
        });
        final row = rowIn(recipe, position);
        expect(recomputeTotals(db, recipe), isTrue);
        expect(sameMatchRow(rowIn(recipe, position), row), isTrue);
        return row;
      }

      final katsu = await variant(_katsu, 'confirm');
      final confirmed = await put(katsu, 1, {'confirmed': true});
      expect(
        (confirmed.status, confirmed.grams, confirmed.gramSource),
        ('confirmed', 53.35, 'discarded'),
      );
      expect(basisIn(katsu, 1), _dipBasis);

      // RE-PIN (M69 batch, v68 — Q7 accepted): the eggplant's coat is
      // budgeted (R2, 7.93), so a Confirm of its dip reads the plan's share
      // — 84.39 g `discarded`, E-w's basis (was 0 g poured away, H).
      final eggplant = await variant(_eggplant, 'confirm');
      final poured = await put(eggplant, 6, {'confirmed': true});
      expect(
        (poured.status, poured.grams, poured.gramSource, poured.hold),
        ('confirmed', 84.39, 'discarded', null),
      );
      expect(basisIn(eggplant, 6), _dipBasis);
      final eggplantItem =
          ((await matchesBody(db, provider, eggplant))['items']!
              as List<Map<String, Object?>>)[6];
      // RE-PIN (M69 batch, v68): the plan's share, no note (was "poured
      // away after your confirm").
      expect((eggplantItem['match']! as Map)['hold_note'], isNull);

      // RE-PIN (M80 batch, v80, M80-1): an H dip's pick on the fried copy
      // (the corpus rings' dips are E-w).
      final rings = await variant(_ringsFried, 'pick');
      final picked = await put(rings, 1, {'fdc_id': 748967});
      expect(
        (picked.status, picked.grams, picked.hold),
        ('overridden', null, 'coating'),
      );
      final ringsItem =
          ((await matchesBody(db, provider, rings))['items']!
              as List<Map<String, Object?>>)[1];
      expect(
        (ringsItem['match']! as Map)['hold_note'],
        _heldNotes[_ringsFried],
      );

      final francese = await variant(_francese, 'typed');
      final typed = await put(francese, 10, {'grams': 20});
      expect(
        (typed.grams, typed.gramSource, typed.hold),
        (20.0, 'override', null),
      );
    });

    test("the coat's shape is read once per recipe and coated record (its "
        "memo key names the record): fish-and-chips' cod coat is C5, and on "
        'the SAME recipe instance a pick of the chicken breast for the cod '
        "line reads the breast's C1", () async {
      final fish = await variant('0255-fish-and-chips.yaml', 'coated');
      const cod = '15.38 g carbohydrate per 100 g of the raw cod';
      const breast = '5.73 g carbohydrate per 100 g of the raw chicken breast';
      expect(basisIn(fish, 2), contains(cod));
      await applyMatchOverride(db, provider, fish, 9, {
        'raw': nutritionLines(fish)[9].raw,
        'fdc_id': 2646170,
      });
      expect(rowIn(fish, 9).description, startsWith('Chicken, breast'));
      expect(basisIn(fish, 2), contains(breast));
    });

    // Last: it writes person decisions into the group's database.
    test('every E-w dip CONFIRMED, every H dip PICKED and every flag-only '
        'dip CONFIRMED through the real PUT: the matches GET still plans M52 '
        'once per request and shows what the per-row derivation shows; a '
        'compute plans it at most twice and writes what the PUTs wrote — '
        "from v60's form too (closer 1, verify1 D1/D2)", () async {
      var decided = 0;
      for (final (file, position, _, fdcId, _, _, _, _, _, _) in [
        ..._dips,
        ..._held,
        ..._flagged,
      ]) {
        final recipe = recipes[file]!;
        await applyMatchOverride(db, provider, recipe, position, {
          'raw': nutritionLines(recipe)[position].raw,
          if (_held.any((h) => h.$1 == file))
            'fdc_id': fdcId
          else
            'confirmed': true,
        });
        decided++;
      }
      // RE-PIN (M80 batch, v80): 50 — 40 E-w, 5 H (the fried copy), 5
      // flag-only (was 44: 35, 4, 5).
      expect(decided, 50);
      final files = {
        for (final (file, _, _, _, _, _, _, _, _, _) in [
          ..._dips,
          ..._held,
          ..._flagged,
        ])
          file,
      };
      for (final file in files) {
        final recipe = recipes[file]!;
        m52PlanRuns = 0;
        final items =
            (await matchesBody(db, provider, recipe))['items']!
                as List<Map<String, Object?>>;
        expect(m52PlanRuns, 1, reason: file);
        for (final (position, line) in nutritionLines(recipe).indexed) {
          final row = rowIn(recipe, position);
          if (!isDecidedRow(row)) {
            continue;
          }
          final d = await derivedFor(
            db,
            cacheOnly,
            recipe,
            position,
            line,
            row,
          );
          final shown = withDerived(row, d.row);
          final match = items[position]['match']! as Map<String, Object?>;
          expect(
            (
              match['status'],
              match['grams'],
              match['gram_source'],
              match['hold'],
              match['gram_basis'],
            ),
            (
              shown.status,
              shown.grams,
              shown.gramSource,
              shown.hold,
              gramBasisFor(db, line, shown, recipe: recipe),
            ),
            reason: '$file|$position',
          );
        }
      }
      // A compute derives each decided row from ONE plan while the rows key
      // alike ([_m52OnConfirm]'s compute memo; before, one plan per decided
      // dip: 16.2 s at the editor caps) — and leaves every decided row as
      // the PUT's per-row derivation left it, each equal to the memo-free
      // derivation on the rows it wrote. (Its ENGINE rows may move: the
      // flagged flour's confirm is a decision other recipes' flour lines
      // carry, as shipped.) Then as v60 left the confirmed eggs (each
      // counted whole on its line's grams): the first compute after the
      // deploy, every derivation rewriting its row, lands there too.
      final asPut = {
        for (final file in files)
          file: {
            for (final r in db.ingredientMatchesFor(recipes[file]!.id))
              if (isDecidedRow(r)) r.position: r,
          },
      };
      Future<void> computesAsPut(String why) async {
        for (final file in files) {
          final recipe = recipes[file]!;
          m52PlanRuns = 0;
          expect(await matchAndCompute(db, provider, recipe), isNull);
          expect(m52PlanRuns, lessThanOrEqualTo(2), reason: '$why $file');
          final rows = db.ingredientMatchesFor(recipe.id);
          expect(
            {
              for (final r in rows)
                if (isDecidedRow(r)) r.position,
            },
            asPut[file]!.keys.toSet(),
            reason: '$why $file',
          );
          for (final row in rows) {
            final put = asPut[file]![row.position];
            if (put == null) {
              continue;
            }
            final reason = '$why $file|${row.position}';
            expect(sameMatchRow(row, put), isTrue, reason: reason);
            final line = nutritionLines(recipe)[row.position];
            final d = await derivedFor(
              db,
              cacheOnly,
              recipe,
              row.position,
              line,
              row,
            );
            expect(
              sameMatchRow(withDerived(row, d.row), row),
              isTrue,
              reason: reason,
            );
          }
        }
      }

      await computesAsPut('compute');
      for (final (file, position, _, _, _, _, _, _, _, _) in _dips) {
        final recipe = recipes[file]!;
        final line = nutritionLines(recipe)[position];
        final row = rowIn(recipe, position);
        final whole = lineGrams(
          db,
          line,
          knownFood(db, row.fdcId!, line: line),
          recipe: recipe,
        )!;
        db.upsertIngredientMatch(
          row.copyWith(grams: whole.grams, gramSource: whole.source.name),
        );
        expect(sameMatchRow(rowIn(recipe, position), row), isFalse);
      }
      await computesAsPut('after the deploy');
      // The E-w grams kept on the confirms, the H holds kept on the picks.
      for (final (file, position, _, _, _, grams, _, _, _, _) in _dips) {
        expect(
          rowIn(recipes[file]!, position).grams?.toStringAsFixed(2),
          grams,
          reason: '$file|$position',
        );
      }
      for (final (file, position, _, _, _, _, _, _, _, _) in _held) {
        expect(rowIn(recipes[file]!, position).hold, 'coating');
      }
    });
  });
}
