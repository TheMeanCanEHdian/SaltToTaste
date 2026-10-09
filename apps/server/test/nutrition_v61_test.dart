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
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

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
  (
    _nutCrusted,
    8,
    '⅛ teaspoon cayenne pepper',
    170932,
    '1.000000',
    '0.04',
    '0.13',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _nutCrusted,
    10,
    '3 large eggs',
    748967,
    '0.920000',
    '27.66',
    '40.94',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _nutCrusted,
    11,
    '2 teaspoons Dijon mustard',
    326698,
    '0.983333',
    '1.91',
    '1.17',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _stuffed,
    11,
    '2 large eggs',
    748967,
    '0.920000',
    '23.26',
    '34.42',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _kiev,
    12,
    '3 large eggs, beaten',
    748967,
    '0.920000',
    '30.67',
    '45.39',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _kiev,
    13,
    '1 teaspoon Dijon mustard',
    326698,
    '0.983333',
    '1.06',
    '0.65',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
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
  (
    _porkChops,
    1,
    '1 cup buttermilk',
    2705393,
    '0.990000',
    '46.82',
    '20.13',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
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
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _porkChops,
    3,
    '1 medium garlic clove, minced or pressed through a garlic press (about 1 teaspoon)',
    1104647,
    '0.970000',
    '0.58',
    '0.83',
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
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
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
  (
    _lighter,
    6,
    '3 large egg whites',
    747997,
    '0.950000',
    '23.79',
    '13.08',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _almond,
    4,
    '2 large eggs',
    748967,
    '0.920000',
    '23.19',
    '34.32',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _almond,
    5,
    '1 teaspoon Dijon mustard',
    326698,
    '0.983333',
    '1.20',
    '0.73',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _almond,
    6,
    '1¼ teaspoons grated zest from 1 orange',
    169103,
    '0.886667',
    '0.58',
    '0.56',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
];

/// M62 H (the owner's Q9 door; plan_figures §3: exactly these 9 rows,
/// −646.74 kcal counted): the dip of a coat held with no budget (no coated
/// meat, or C4's sautéed dusting) held `coating` with it, no grams; the
/// design's 10th, oven-fried-onion-rings|5 cayenne, is beyond the line
/// rule's reach (A13's one 'pepper' word goes to |4) — a negative below.
const List<_Row> _held = [
  (
    _eggplant,
    6,
    '4 large eggs',
    748967,
    '0.920000',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  (
    _onionRings,
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
    _onionRings,
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
    _onionRings,
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
    _onionRings,
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
    _parmesanCrusted,
    4,
    '3 large egg whites',
    747997,
    '0.950000',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  (
    _parmesanCrusted,
    5,
    '2 tablespoons minced fresh chives (optional)',
    169994,
    '0.920000',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  (
    _francese,
    10,
    '2 large eggs',
    748967,
    '0.920000',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  (
    _francese,
    11,
    '2 tablespoons milk',
    2705385,
    '0.910000',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
];

/// No coat at all (no line held `coating`, none budgeted): the dip's lines
/// keep the D5 flag only — 7 rows, 0 kcal moved (plan_figures §1).
const List<_Row> _flagged = [
  (
    _bestParmesan,
    12,
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
    _bestParmesan,
    13,
    '1 tablespoon all-purpose flour',
    789890,
    '0.950000',
    '7.54',
    '27.60',
    'auto',
    null,
    '1 tablespoon ≈ 15 mL · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
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
  (
    _spicy,
    4,
    '1 tablespoon all-purpose flour',
    789890,
    '0.950000',
    '7.54',
    '27.60',
    'auto',
    null,
    '1 tablespoon ≈ 15 mL · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
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
  (
    _breaded,
    2,
    '3 slices high-quality white sandwich bread, torn into quarters',
    174924,
    '0.914286',
    '26.93',
    '71.63',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    _breaded,
    3,
    '¾ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '29.01',
    '106.18',
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
  (
    _schnitzel,
    0,
    '½ cup all-purpose flour',
    789890,
    '0.950000',
    '13.58',
    '49.70',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    _schnitzel,
    3,
    '2 cups plain dried bread crumbs',
    174928,
    '0.657500',
    '48.61',
    '192.01',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    _nutCrusted,
    5,
    '1 cup panko bread crumbs',
    174928,
    '0.563333',
    '10.99',
    '43.41',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    _nutCrusted,
    9,
    '1 cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '22.42',
    '82.06',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    _stuffed,
    10,
    '¾ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '14.32',
    '52.41',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    _stuffed,
    13,
    '4 slices high-quality white sandwich bread, pulsed in a food processor to coarse crumbs and dried',
    174924,
    '0.914286',
    '17.73',
    '47.16',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    _kiev,
    7,
    '4 slices high-quality white sandwich bread, torn into quarters',
    174924,
    '0.914286',
    '20.38',
    '54.21',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    _kiev,
    11,
    '1 cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '21.96',
    '80.37',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
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
  (
    _crunchy,
    2,
    '4 slices high-quality white sandwich bread, torn into 1-inch pieces',
    174924,
    '0.914286',
    '74.70',
    '198.70',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 6.61 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705871 recipe: 10 g breading per 108.38 g raw pork chop; the dredge's excess not counted)",
  ),
  (
    _crunchy,
    10,
    '¼ cup plus 6 tablespoons unbleached all-purpose flour',
    789890,
    '0.950000',
    '65.37',
    '239.25',
    'auto',
    null,
    'discarded in cooking — only "plus 6 tablespoons unbleached all-purpose flour" and the coat on the food counted · approximation (coat: 6.61 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705871 recipe: 10 g breading per 108.38 g raw pork chop; the dredge\'s excess not counted)',
  ),
  (
    _porkSchnitzel,
    0,
    '7 slices high-quality white sandwich bread, crusts removed, cut into ¾-inch cubes (about 4 cups)',
    174924,
    '0.914286',
    '39.27',
    '104.46',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
  (
    _porkSchnitzel,
    1,
    '½ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '16.92',
    '61.93',
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
  (
    _lighter,
    0,
    '1½ cups panko (Japanese-style bread crumbs)',
    174928,
    '0.880000',
    '16.29',
    '64.35',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    _lighter,
    3,
    '½ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '11.07',
    '40.52',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    _almond,
    3,
    '½ cup panko (Japanese-style bread crumbs)',
    174928,
    '0.880000',
    '29.57',
    '116.80',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
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
  (
    _nutCrusted,
    12,
    '¼ teaspoon ground black pepper',
    170931,
    '1.000000',
    '0.58',
    '1.45',
    'auto',
    null,
    '1/4 teaspoon ≈ 1 mL',
  ),
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
    '1/4 teaspoon · USDA portion',
  ),
  (
    _onionRings,
    0,
    '½ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '30.16',
    '110.40',
    'auto',
    'coating',
    'discarded in cooking — only the part the recipe keeps counted',
  ),
  (
    _onionRings,
    6,
    '30 saltine crackers',
    2708167,
    '0.990000',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  (
    _onionRings,
    7,
    '4 cups kettle-cooked potato chips',
    2709422,
    '0.990000',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  (
    _eggplant,
    2,
    '8 slices high-quality white sandwich bread, torn into quarters',
    174924,
    '0.914286',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  (
    _eggplant,
    3,
    '2 ounces Parmesan cheese, grated (about 1 cup)',
    325036,
    '0.983333',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  (
    _eggplant,
    5,
    '1 cup unbleached all-purpose flour',
    789890,
    '0.950000',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  (
    _parmesanCrusted,
    2,
    '5 tablespoons unbleached all-purpose flour',
    789890,
    '0.950000',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  (
    _parmesanCrusted,
    3,
    '¼ cup grated Parmesan cheese plus 6 ounces, shredded (about 2 cups; see note)',
    325036,
    '0.983333',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  (
    _francese,
    9,
    '1 cup unbleached all-purpose flour',
    789890,
    '0.950000',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
];

/// Each H recipe's dip sentence as written — its held rows' `hold_note`.
const Map<String, String> _heldNotes = {
  _eggplant:
      'Remove the slices, shaking off the excess flour, dip into the eggs, let the excess egg run off, then coat evenly with the bread-crumb mixture; set the breaded slices on a wire rack set over a baking sheet.',
  _onionRings:
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
  test('the matcher version carries the batch (update the literal with a '
      'bump)', () {
    // RE-PIN (M63 batch, v62): matcherVersion 61 (was 60).
    expect(matcherVersion, 61);
  });

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
          recipes[file] = await compute(loadCorpusRecipe(file));
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

    test('E-w reaches exactly its 28 dip rows, each `discarded` with the '
        'read wet share in its basis (plan_figures §4)', () {
      expect(_dips, hasLength(28));
      expect(_dips.every((r) => r.$10 == _dipBasis), isTrue);
      expectRows(_dips);
      for (final (file, position, _, _, _, _, _, _, _, _) in _dips) {
        expect(
          rowIn(recipes[file]!, position).gramSource,
          'discarded',
          reason: '$file|$position',
        );
      }
    });

    test("the coat's parts of the 13 recipes stay as v60 — no re-split "
        "(F12: katsu|0 63.19, not §2-E's 62.49)", () {
      expect(_parts, hasLength(21));
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
        "(9 rows, the owner's Q9 door) — no grams, its `hold_note` the dip "
        'sentence; the coats already held stay as v60', () async {
      expect(_held, hasLength(9));
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
      // The coat's own held line keeps its own note.
      final rings = recipes[_onionRings]!;
      expect(
        holdNoteOf(rings, nutritionLines(rings)[0], 'coating'),
        '¼ cup flour is used outside the dredge, eaten',
      );
    });

    test('no coat at all: the dip keeps the D5 flag only (7 rows, 0 kcal '
        'moved); spicy|5 garlic powder, named by no sentence, unflagged', () {
      expect(_flagged, hasLength(7));
      expect(_flagged.every((r) => r.$10!.endsWith(_d5)), isTrue);
      expectRows(_flagged);
    });

    test('the rows M62 must not move equal v60 (plan_figures §4: no excess '
        'phrase, the kept oil parts, the garnish egg, the brine, the rule '
        'rows, the A13 ceiling, the coats already held)', () {
      expectRows(_negatives);
    });

    test('per serving: the 13 E-w recipes and the 4 H recipes move; no '
        'status moves', () {
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
      expect(of(_breaded), (
        'complete',
        '350.48',
        7,
      )); // replay 350.53; v60 372.02
      expect(of(_katsu), ('complete', '411.79', 5)); // 411.86; 429.12
      expect(of(_schnitzel), ('complete', '423.57', 9)); // 423.64; 460.09
      expect(of(_nutCrusted), ('partial', '360.39', 12)); // 360.45; 407.15
      expect(of(_stuffed), ('complete', '544.46', 14)); // 544.51; 572.91
      expect(of(_kiev), ('complete', '540.11', 14)); // 540.19; 584.97
      expect(of(_crispyFried), ('complete', '832.44', 13)); // = replay; 858.08
      expect(of(_porkChops), ('partial', '480.50', 8)); // = replay; 506.39
      expect(of(_crunchy), ('complete', '468.36', 14)); // 468.90; 480.86
      expect(of(_porkSchnitzel), (
        'complete',
        '367.75',
        10,
      )); // = replay; 390.64
      expect(of(_steaks), ('complete', '534.48', 18)); // = replay; 555.87
      expect(of(_lighter), ('partial', '232.26', 11)); // 232.29; 239.19
      expect(of(_almond), ('partial', '402.13', 10)); // 402.18; 431.67
      // H: the counted lines fall by the held dips.
      expect(of(_eggplant), (
        'partial',
        '360.35',
        12,
      )); // 360.33; v60 409.66, 13
      expect(of(_onionRings), ('partial', '217.86', 3)); // = replay; 249.84, 7
      expect(of(_parmesanCrusted), (
        'partial',
        '153.50',
        4,
      )); // 153.54; 167.60, 6
      expect(of(_francese), ('partial', '407.39', 12)); // 407.44; 449.08, 14
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
          if (match?['gram_basis'] == _dipBasis) {
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
      final corpus = loadCorpusRecipe(file);
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

      final eggplant = await variant(_eggplant, 'confirm');
      final poured = await put(eggplant, 6, {'confirmed': true});
      expect(
        (poured.status, poured.grams, poured.gramSource, poured.hold),
        ('confirmed', 0.0, 'discarded', null),
      );
      expect(basisIn(eggplant, 6), 'poured away — counted as 0 g');
      final eggplantItem =
          ((await matchesBody(db, provider, eggplant))['items']!
              as List<Map<String, Object?>>)[6];
      expect(
        (eggplantItem['match']! as Map)['hold_note'],
        'poured away after your confirm',
      );

      final rings = await variant(_onionRings, 'pick');
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
        _heldNotes[_onionRings],
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
      expect(decided, 44);
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
