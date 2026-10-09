// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v65 (batch M66 — coat parts and dips; matcherVersion 64; prep49
// design_v2 §2 M66, the owner's Q5 (a) gated, Q7 (the one-way door,
// accepted 2026-10-09) and Q8 (b); zero requests; reach pre-Q18 — the
// crumb gate and the dip readers read steps): R3 a nut or cheese layer a
// step names with a crumb joins the coat's parts at the one f
// (`_layerInCrumb`); R1 the dip is sized off B, never the parts' Σ (C = B);
// R2 a dip line's part a LATER step writes ("remaining ¼ teaspoon zest")
// is eaten whole; R3' a head two dip-recipe lines share is told apart by
// each line's own word ("black", "cayenne"); R4 an egg dip with no coat
// beside it opens the budget where the recipe shallow-fries the coated
// food and it has a shape (0415);
// and the basis texts — a C5 batter names the breading's carbohydrate it
// is matched by (Q1 b), alcohol in a fried batter says USDA prints no
// frying row (Q8 b). Every row value is the fresh compute of the WHOLE
// recipe (sections first) over recorded real FDC answers
// (FixtureProvider; one search added --from-db from snapshot 25, JSON-equal,
// 0 existing entries changed: "sole or flounder fillets", 0466's fish, so
// its held C4 dusting can be pinned), equal to the v65 replay of snapshot
// 25 (rp43, fix65 r1) on every pinned field and, on every row M66 must not
// move, to the v64 rows; never the network.
// Synthesized, STATED (no corpus recipe holds them): the lighter-chicken-
// parmesan copy whose one Parmesan sentence names no crumb ("Spread the
// toasted mixture in a shallow dish …") — the crumb gate's negative; the
// almond-crusted copy with a first step "Sprinkle ½ teaspoon zest over the
// spinach." — R2's after-the-dip guard; the almond-crusted copy with a
// second "2 large eggs" line (the real |4 line, in SALAD) and "Whisk 2 large
// eggs into the dressing." after S4 — R2's writers guard (closer 1, D1);
// the best-chicken-parmesan copy whose S4 bakes the cutlets ("Place cutlets
// on a wire rack set in a rimmed baking sheet and bake …") — R4's
// shallow-fry condition (closer 2, D1); the onion-rings copy whose S1 reads
// "the salt, pepper, and cayenne" — R3''s own-word ceiling (closer 2, D2).

import 'dart:io';

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

/// (file, position, raw, fdc id, confidence, grams, kcal, status, hold,
/// basis) — a row of the fresh compute.
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
const _nutCrusted =
    '0117-nut-crusted-chicken-breasts-with-lemon-and-thyme.yaml';
const _lighter = '0416-lighter-chicken-parmesan.yaml';
const _bestParmesan = '0415-best-chicken-parmesan.yaml';
const _onionRings = '0315-oven-fried-onion-rings.yaml';
const _parmesanCrusted = '0419-parmesan-crusted-chicken-cutlets.yaml';
const _tempura = '0511-shrimp-tempura.yaml';
const _fishChips = '0255-fish-and-chips.yaml';
const _sandwiches = '1081-crispy-fish-sandwiches-with-tartar-sauce.yaml';

/// The dip's basis (M62 E-w) and its kept-part form (R2).
const _dipBasis =
    "discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat's carbohydrate — USDA FNDDS 2710785 \"Breading or batter as ingredient in food\": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip's excess not counted)";

/// RE-PIN (M69 batch, v68): the coat flags of the rows M69 releases.
const _c4Breast =
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast (no record for a sautéed flour dusting; read as the baked breaded breast, the lightest coat USDA prints; FNDDS 2706416 Veal Marsala's 62.5 g flour per 617.60 g raw veal, 7.82, counts the dish's whole flour, sauce included, and is not read); the dredge's excess not counted)";
const _c4Sole =
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw flatfish — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast (no record for a sautéed flour dusting; read as the baked breaded breast, the lightest coat USDA prints; FNDDS 2706416 Veal Marsala's 62.5 g flour per 617.60 g raw veal, 7.82, counts the dish's whole flour, sauce included, and is not read); the dredge's excess not counted)";
const _eggplantCoat =
    "discarded in cooking — only the coat on the food counted · approximation (coat: 7.93 g carbohydrate per 100 g of the raw eggplant — USDA FNDDS 2710050 recipe: 13.2 g batter (4 g flour, 0.5 g dried egg, 8.3 g water, 0.3 g dry milk, 0.1 g baking powder; 3.28 g carbohydrate) per 41.4 g raw eggplant (a crumb coat read on a batter figure; 8.3 g of the 13.2 g batter is water and carries no carbohydrate); the dredge's excess not counted)";
const _dipKeptBasis =
    "discarded in cooking — only the part the recipe keeps and the dip on the food counted · approximation (dip: 1.17 g per g of the coat's carbohydrate — USDA FNDDS 2710785 \"Breading or batter as ingredient in food\": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip's excess not counted)";

/// The 18 rows M66 moves the grams or the hold of (fix65 r1 vs the v64
/// rows), by rule: R3 almond |2 |3, nut-crusted |2 |5 |9, lighter |0 |2 |3;
/// R3 + R1 + R2 almond |4 |5 |6; R3' nut-crusted |8 |10 |11 |12,
/// onion-rings |5; R4 best-chicken-parmesan |12 |13.
const List<_Row> _reach = [
  (
    _almond,
    2,
    '1 cup sliced almonds',
    170567,
    '0.900000',
    '79.97',
    '463.03',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
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
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
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
  (
    _bestParmesan,
    12,
    '1 large egg',
    748967,
    '0.920000',
    '23.18',
    '34.31',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _bestParmesan,
    13,
    '1 tablespoon all-purpose flour',
    789890,
    '0.950000',
    '3.50',
    '12.81',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _lighter,
    0,
    '1½ cups panko (Japanese-style bread crumbs)',
    174928,
    '0.880000',
    '15.78',
    '62.33',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    _lighter,
    2,
    '1 ounce Parmesan cheese, grated (about ½ cup), plus extra for serving',
    325036,
    '0.983333',
    '5.04',
    '21.22',
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
    '10.73',
    '39.27',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    _nutCrusted,
    2,
    '1 cup almonds, chopped coarse',
    170567,
    '0.900000',
    '21.66',
    '125.41',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    _nutCrusted,
    5,
    '1 cup panko bread crumbs',
    174928,
    '0.563333',
    '8.96',
    '35.39',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
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
  (
    _nutCrusted,
    9,
    '1 cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '18.28',
    '66.90',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    _nutCrusted,
    10,
    '3 large eggs',
    748967,
    '0.920000',
    '27.60',
    '40.85',
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
    '1.90',
    '1.16',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _nutCrusted,
    12,
    '¼ teaspoon ground black pepper',
    170931,
    '1.000000',
    '0.11',
    '0.28',
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    _onionRings,
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

/// The 15 C5 batter rows whose basis alone moves (Q1 b: "25 g breading
/// (USDA 99995000, 40.1 % carbohydrate) per 65 g raw shrimp, matched by its
/// carbohydrate"; 0 kcal, 0 grams).
const List<_Row> _texts = [
  (
    _sandwiches,
    6,
    '½ cup all-purpose flour',
    789890,
    '0.950000',
    '47.03',
    '172.13',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw haddock — USDA FNDDS 2706258 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw haddock, matched by its carbohydrate; the batter's excess not counted)",
  ),
  (
    _sandwiches,
    7,
    '½ cup cornstarch',
    169698,
    '1.000000',
    '49.79',
    '189.70',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw haddock — USDA FNDDS 2706258 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw haddock, matched by its carbohydrate; the batter's excess not counted)",
  ),
  (
    _sandwiches,
    9,
    '½ teaspoon baking powder',
    172804,
    '0.850000',
    '1.77',
    '0.90',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw haddock — USDA FNDDS 2706258 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw haddock, matched by its carbohydrate; the batter's excess not counted)",
  ),
  (
    _sandwiches,
    10,
    '¾ cup beer',
    2710616,
    '0.990000',
    '140.31',
    '60.33',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw haddock — USDA FNDDS 2706258 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw haddock, matched by its carbohydrate; the batter's excess not counted)",
  ),
  (
    _fishChips,
    2,
    '1½ cups unbleached all-purpose flour',
    789890,
    '0.950000',
    '89.12',
    '326.18',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw cod, matched by its carbohydrate; the batter's excess not counted)",
  ),
  (
    _fishChips,
    3,
    '½ cup cornstarch',
    169698,
    '1.000000',
    '31.45',
    '119.82',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw cod, matched by its carbohydrate; the batter's excess not counted)",
  ),
  (
    _fishChips,
    4,
    '½ teaspoon cayenne pepper',
    170932,
    '1.000000',
    '0.44',
    '1.40',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw cod, matched by its carbohydrate; the batter's excess not counted)",
  ),
  (
    _fishChips,
    5,
    '½ teaspoon paprika',
    171329,
    '0.900000',
    '0.57',
    '1.61',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw cod, matched by its carbohydrate; the batter's excess not counted)",
  ),
  (
    _fishChips,
    8,
    '1 teaspoon baking powder',
    172804,
    '0.850000',
    '2.23',
    '1.14',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw cod, matched by its carbohydrate; the batter's excess not counted)",
  ),
  (
    _fishChips,
    10,
    '1½ cups (12 ounces) cold beer',
    2710616,
    '0.565000',
    '167.52',
    '72.03',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw cod, matched by its carbohydrate; the batter's excess not counted)",
  ),
  (
    _tempura,
    2,
    '1½ cups (7½ ounces) unbleached all-purpose flour',
    789890,
    '0.950000',
    '99.71',
    '364.94',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw shrimp — USDA FNDDS 2706364 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw shrimp, matched by its carbohydrate; the batter's excess not counted)",
  ),
  (
    _tempura,
    3,
    '½ cup cornstarch',
    169698,
    '1.000000',
    '29.96',
    '114.15',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw shrimp — USDA FNDDS 2706364 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw shrimp, matched by its carbohydrate; the batter's excess not counted)",
  ),
  (
    _tempura,
    4,
    '1 cup vodka',
    2710704,
    '0.990000',
    '105.05',
    '242.67',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw shrimp — USDA FNDDS 2706364 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw shrimp, matched by its carbohydrate; the batter's excess not counted)",
  ),
  (
    _tempura,
    5,
    '1 large egg',
    748967,
    '0.920000',
    '23.45',
    '34.71',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw shrimp — USDA FNDDS 2706364 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw shrimp, matched by its carbohydrate; the batter's excess not counted)",
  ),
  (
    _tempura,
    6,
    '1 cup seltzer water',
    2710539,
    '0.923333',
    '110.95',
    '0.00',
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw shrimp — USDA FNDDS 2706364 recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw shrimp, matched by its carbohydrate; the batter's excess not counted)",
  ),
];

/// Every other coat, dip, held-coat and bowl-excess row of the 42 recipes
/// that hold one (fix65 gen.py: a basis naming "coat:", "dip:" or the
/// excess in the bowl, or a `coating` hold), equal to the v64 rows — among
/// them breaded|4 41.92, katsu|1 53.35, crispy-fried|12 105.95,
/// crispy-pan-fried-pork-chops|1 46.82, parmesan-crusted|2–|5 held (its
/// cheese crust names no crumb, and no budget reaches it until M69), the
/// spicy sandwiches' air-fried dips (no shape) and the three non-coat D5
/// rows' recipes (scones, truffles, macaroons). The energy is not pinned
/// here (a fresh compute counts some records on their search hit).
const List<_Row> _negatives = [
  // RE-PIN (M69 batch, v68): no longer held — C4 at 3.18 (R1) (was held `coating`).
  (
    '0415-better-chicken-marsala.yaml',
    6,
    '¾ cup all-purpose flour',
    789890,
    '0.950000',
    '32.66',
    null,
    'auto',
    null,
    _c4Breast,
  ),
  (
    '0114-breaded-chicken-cutlets.yaml',
    2,
    '3 slices high-quality white sandwich bread, torn into quarters',
    174924,
    '0.914286',
    '26.93',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    '0114-breaded-chicken-cutlets.yaml',
    3,
    '¾ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '29.01',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    '0114-breaded-chicken-cutlets.yaml',
    4,
    '2 large eggs',
    748967,
    '0.920000',
    '41.92',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0758-british-style-currant-scones.yaml',
    0,
    '3 cups (15 ounces) all-purpose flour',
    789890,
    '0.950000',
    '425.24',
    null,
    'auto',
    null,
    'from 15 ounce · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0758-british-style-currant-scones.yaml',
    1,
    '⅓ cup (2⅓ ounces) sugar',
    746784,
    '0.950000',
    '66.15',
    null,
    'auto',
    null,
    'from 2 1/3 ounce · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0758-british-style-currant-scones.yaml',
    2,
    '2 tablespoons baking powder',
    172804,
    '0.850000',
    '27.21',
    null,
    'auto',
    null,
    '2 tablespoon ≈ 30 mL · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0758-british-style-currant-scones.yaml',
    3,
    '½ teaspoon salt',
    173468,
    '0.900000',
    '3.01',
    null,
    'auto',
    null,
    '1/2 teaspoon ≈ 2 mL · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0758-british-style-currant-scones.yaml',
    4,
    '8 tablespoons unsalted butter, cut into ½-inch pieces and softened',
    173430,
    '1.000000',
    '113.44',
    null,
    'auto',
    null,
    '8 tablespoon ≈ 118 mL · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0758-british-style-currant-scones.yaml',
    5,
    '¾ cup dried currants',
    2709201,
    '0.990000',
    '120.00',
    null,
    'auto',
    null,
    '3/4 cup · USDA portion · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0758-british-style-currant-scones.yaml',
    6,
    '1 cup whole milk',
    2705385,
    '1.000000',
    '244.00',
    null,
    'auto',
    null,
    '1 cup · USDA portion · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0758-british-style-currant-scones.yaml',
    7,
    '2 large eggs',
    748967,
    '0.920000',
    '100.00',
    null,
    'auto',
    null,
    '2 × 50 g each · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  // RE-PIN (M69 batch, v68): no longer held — C4 at 3.18 (R1) (was held `coating`).
  (
    '0420-chicken-francese.yaml',
    9,
    '1 cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '25.66',
    null,
    'auto',
    null,
    _c4Breast,
  ),
  // RE-PIN (M69 batch, v68): no longer held — C4 at 3.18 (R1) (was held `coating`).
  (
    '0420-chicken-francese.yaml',
    10,
    '2 large eggs',
    748967,
    '0.920000',
    '17.83',
    null,
    'auto',
    null,
    _dipBasis,
  ),
  // RE-PIN (M69 batch, v68): no longer held — C4 at 3.18 (R1) (was held `coating`).
  (
    '0420-chicken-francese.yaml',
    11,
    '2 tablespoons milk',
    2705385,
    '0.910000',
    '5.43',
    null,
    'auto',
    null,
    _dipBasis,
  ),
  (
    '1133-chicken-francese.yaml',
    5,
    '¾ cup all-purpose flour, divided',
    789890,
    '0.950000',
    '61.35',
    null,
    'auto',
    null,
    "discarded in cooking — only the part the recipe keeps and the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    '0304-chicken-fried-steaks.yaml',
    0,
    '3 cups unbleached all-purpose flour',
    789890,
    '0.950000',
    '96.71',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 8.79 g carbohydrate per 100 g of the raw beef — USDA FNDDS 2705842 recipe: 20 g breading per 90.99 g raw beef steak; the dredge's excess not counted)",
  ),
  (
    '0304-chicken-fried-steaks.yaml',
    3,
    '1 large egg',
    748967,
    '0.920000',
    '14.58',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0304-chicken-fried-steaks.yaml',
    4,
    '1 teaspoon baking powder',
    172804,
    '0.850000',
    '1.32',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0304-chicken-fried-steaks.yaml',
    5,
    '½ teaspoon baking soda',
    175040,
    '0.900000',
    '0.67',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0304-chicken-fried-steaks.yaml',
    6,
    '1 cup buttermilk',
    2705393,
    '0.990000',
    '71.13',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
    0,
    '2 cups panko bread crumbs',
    174928,
    '0.563333',
    '63.19',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
    1,
    '2 large eggs',
    748967,
    '0.920000',
    '53.35',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0122-chicken-kiev.yaml',
    7,
    '4 slices high-quality white sandwich bread, torn into quarters',
    174924,
    '0.914286',
    '20.38',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    '0122-chicken-kiev.yaml',
    11,
    '1 cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '21.96',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    '0122-chicken-kiev.yaml',
    12,
    '3 large eggs, beaten',
    748967,
    '0.920000',
    '30.67',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0122-chicken-kiev.yaml',
    13,
    '1 teaspoon Dijon mustard',
    326698,
    '0.983333',
    '1.06',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  // RE-PIN (M69 batch, v68): no longer held — C4 at 3.18 (R1) (was held `coating`).
  (
    '0418-chicken-piccata.yaml',
    3,
    '½ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '27.99',
    null,
    'auto',
    null,
    _c4Breast,
  ),
  // RE-PIN (M69 batch, v68): no longer held — C4 at 3.18 (R1) (was held `coating`).
  (
    '0421-chicken-saltimbocca.yaml',
    1,
    '½ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '25.66',
    null,
    'auto',
    null,
    _c4Breast,
  ),
  (
    '0116-chicken-schnitzel.yaml',
    0,
    '½ cup all-purpose flour',
    789890,
    '0.950000',
    '13.58',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    '0116-chicken-schnitzel.yaml',
    1,
    '2 large eggs',
    748967,
    '0.920000',
    '46.80',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0116-chicken-schnitzel.yaml',
    2,
    '1 tablespoon vegetable oil',
    2710180,
    '0.923333',
    '6.55',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0116-chicken-schnitzel.yaml',
    3,
    '2 cups plain dried bread crumbs',
    174928,
    '0.657500',
    '48.61',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    '1209-chocolate-dipped-triple-coconut-macaroons.yaml',
    7,
    '10 ounces semisweet chocolate, chopped, divided',
    170271,
    '0.866667',
    '283.50',
    null,
    'auto',
    null,
    'from 10 ounce · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0852-chocolate-truffles.yaml',
    6,
    '1 cup (3 ounces) Dutch-processed cocoa',
    169594,
    '0.623214',
    '85.05',
    null,
    'auto',
    null,
    'from 3 ounce · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0852-chocolate-truffles.yaml',
    7,
    '¼ cup (1 ounce) confectioners’ sugar',
    169656,
    '1.000000',
    '28.35',
    null,
    'auto',
    null,
    'from 1 ounce · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0148-crispy-fried-chicken.yaml',
    8,
    '4 cups (20 ounces) unbleached all-purpose flour',
    789890,
    '0.950000',
    '144.06',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 8.79 g carbohydrate per 100 g of the raw chicken — USDA FNDDS 2705842 recipe: 20 g breading per 90.99 g raw beef steak (no record for chicken; read as Beef, steak, country fried); the dredge's excess not counted)",
  ),
  (
    '0148-crispy-fried-chicken.yaml',
    9,
    '1 large egg',
    748967,
    '0.920000',
    '21.71',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0148-crispy-fried-chicken.yaml',
    10,
    '1 teaspoon baking powder',
    172804,
    '0.850000',
    '1.97',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0148-crispy-fried-chicken.yaml',
    11,
    '½ teaspoon baking soda',
    175040,
    '0.900000',
    '1.00',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0148-crispy-fried-chicken.yaml',
    12,
    '1 cup buttermilk',
    2705393,
    '0.990000',
    '105.95',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0198-crispy-pan-fried-pork-chops.yaml',
    0,
    '⅔ cup cornstarch',
    169698,
    '1.000000',
    '49.83',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
  (
    '0198-crispy-pan-fried-pork-chops.yaml',
    1,
    '1 cup buttermilk',
    2705393,
    '0.990000',
    '46.82',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0198-crispy-pan-fried-pork-chops.yaml',
    2,
    '2 tablespoons Dijon mustard',
    326698,
    '0.983333',
    '5.96',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0198-crispy-pan-fried-pork-chops.yaml',
    3,
    '1 medium garlic clove, minced or pressed through a garlic press (about 1 teaspoon)',
    1104647,
    '0.970000',
    '0.58',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0279-crispy-salt-and-pepper-shrimp.yaml',
    8,
    '5 tablespoons cornstarch',
    169698,
    '1.000000',
    '39.92',
    null,
    'auto',
    null,
    'discarded in cooking — only the part the recipe keeps and the coat on the food counted · approximation (coat: 3.94 g carbohydrate per 100 g of the raw shrimp — derived from USDA SR Legacy 171982 "Mollusks, squid, mixed species, cooked, fried"; the dredge\'s excess not counted)',
  ),
  (
    '0206-crunchy-baked-pork-chops.yaml',
    2,
    '4 slices high-quality white sandwich bread, torn into 1-inch pieces',
    174924,
    '0.914286',
    '74.70',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 6.61 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705871 recipe: 10 g breading per 108.38 g raw pork chop; the dredge's excess not counted)",
  ),
  (
    '0206-crunchy-baked-pork-chops.yaml',
    10,
    '¼ cup plus 6 tablespoons unbleached all-purpose flour',
    789890,
    '0.950000',
    '65.37',
    null,
    'auto',
    null,
    'discarded in cooking — only "plus 6 tablespoons unbleached all-purpose flour" and the coat on the food counted · approximation (coat: 6.61 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705871 recipe: 10 g breading per 108.38 g raw pork chop; the dredge\'s excess not counted)',
  ),
  (
    '0206-crunchy-baked-pork-chops.yaml',
    11,
    '3 large egg whites',
    747997,
    '0.950000',
    '41.86',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0206-crunchy-baked-pork-chops.yaml',
    12,
    '3 tablespoons Dijon mustard',
    326698,
    '0.983333',
    '19.69',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0254-crunchy-oven-fried-fish.yaml',
    0,
    '4 slices high-quality white sandwich bread, torn into quarters',
    174924,
    '0.914286',
    '59.82',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 7.41 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706243 recipe: 15 g breading per 81 g raw cod; the dredge's excess not counted)",
  ),
  (
    '0254-crunchy-oven-fried-fish.yaml',
    5,
    '¼ cup plus 5 tablespoons unbleached all-purpose flour',
    789890,
    '0.950000',
    '53.82',
    null,
    'auto',
    null,
    'discarded in cooking — only "plus 5 tablespoons unbleached all-purpose flour" and the coat on the food counted · approximation (coat: 7.41 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706243 recipe: 15 g breading per 81 g raw cod; the dredge\'s excess not counted)',
  ),
  (
    '0526-dakgangjeong-korean-fried-chicken-wings.yaml',
    8,
    '1 cup all-purpose flour',
    789890,
    '0.950000',
    '40.36',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.66 g carbohydrate per 100 g of the raw chicken wings — USDA FNDDS 2706065 recipe: 15 g breading per 105.96 g raw chicken wing (a batter read on a breading figure); the batter's excess not counted)",
  ),
  (
    '0526-dakgangjeong-korean-fried-chicken-wings.yaml',
    9,
    '3 tablespoons cornstarch',
    169698,
    '1.000000',
    '8.01',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.66 g carbohydrate per 100 g of the raw chicken wings — USDA FNDDS 2706065 recipe: 15 g breading per 105.96 g raw chicken wing (a batter read on a breading figure); the batter's excess not counted)",
  ),
  (
    '0149-easier-fried-chicken.yaml',
    8,
    '2 cups unbleached all-purpose flour',
    789890,
    '0.950000',
    '45.60',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  // RE-PIN (M69 batch, v68): no longer held — the eggplant coat at 7.93 (R2) (was held `coating`).
  (
    '0407-eggplant-parmesan.yaml',
    2,
    '8 slices high-quality white sandwich bread, torn into quarters',
    174924,
    '0.914286',
    '76.37',
    null,
    'auto',
    null,
    _eggplantCoat,
  ),
  // RE-PIN (M69 batch, v68): no longer held — the eggplant coat at 7.93 (R2) (was held `coating`).
  (
    '0407-eggplant-parmesan.yaml',
    3,
    '2 ounces Parmesan cheese, grated (about 1 cup)',
    325036,
    '0.983333',
    '19.33',
    null,
    'auto',
    null,
    _eggplantCoat,
  ),
  // RE-PIN (M69 batch, v68): no longer held — the eggplant coat at 7.93 (R2) (was held `coating`).
  (
    '0407-eggplant-parmesan.yaml',
    5,
    '1 cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '41.14',
    null,
    'auto',
    null,
    _eggplantCoat,
  ),
  // RE-PIN (M69 batch, v68): no longer held — the eggplant coat at 7.93 (R2) (was held `coating`).
  (
    '0407-eggplant-parmesan.yaml',
    6,
    '4 large eggs',
    748967,
    '0.920000',
    '84.39',
    null,
    'auto',
    null,
    _dipBasis,
  ),
  // RE-PIN (M69 batch, v68): no longer held — C4 at 3.18 (R1) (was held `coating`).
  (
    '0466-fish-meuniere-with-browned-butter-and-lemon.yaml',
    0,
    '½ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '25.66',
    null,
    'auto',
    null,
    _c4Sole,
  ),
  (
    '0527-karaage-japanese-fried-chicken-thighs.yaml',
    7,
    '1¼ cups cornstarch',
    169698,
    '1.000000',
    '45.47',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 6.10 g carbohydrate per 100 g of the raw chicken thigh — USDA FNDDS 2706047 recipe: 15 g breading per 98.39 g raw chicken thigh; the dredge's excess not counted)",
  ),
  (
    '0416-lighter-chicken-parmesan.yaml',
    6,
    '3 large egg whites',
    747997,
    '0.950000',
    '23.79',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0235-maple-glazed-pork-tenderloin.yaml',
    6,
    '¼ cup cornstarch',
    169698,
    '1.000000',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  (
    '0288-maryland-crab-cakes.yaml',
    8,
    '¼ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '30.16',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw crab — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for crab; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
  // RE-PIN (M69 batch, v68): no longer held — C4 at 3.18 (R1) (was held `coating`).
  (
    '0418-next-level-chicken-piccata.yaml',
    3,
    '¾ cup all-purpose flour',
    789890,
    '0.950000',
    '32.66',
    null,
    'auto',
    null,
    _c4Breast,
  ),
  (
    '0525-orange-flavored-chicken.yaml',
    13,
    '1 cup cornstarch',
    169698,
    '1.000000',
    '45.47',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 6.10 g carbohydrate per 100 g of the raw chicken thigh — USDA FNDDS 2706047 recipe: 15 g breading per 98.39 g raw chicken thigh; the dredge's excess not counted)",
  ),
  (
    '0150-oven-fried-chicken.yaml',
    8,
    '1 box (about 5 ounces) plain Melba toast, crushed',
    174977,
    '0.950000',
    '42.90',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.10 g carbohydrate per 100 g of the raw chicken legs — USDA FNDDS 2705998 recipe: 10 g breading per 129.02 g raw chicken legs; the dredge's excess not counted)",
  ),
  (
    '0315-oven-fried-onion-rings.yaml',
    0,
    '½ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '30.16',
    null,
    'auto',
    'coating',
    'discarded in cooking — only the part the recipe keeps counted',
  ),
  (
    '0315-oven-fried-onion-rings.yaml',
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
    '0315-oven-fried-onion-rings.yaml',
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
    '0315-oven-fried-onion-rings.yaml',
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
    '0315-oven-fried-onion-rings.yaml',
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
    '0315-oven-fried-onion-rings.yaml',
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
    '0315-oven-fried-onion-rings.yaml',
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
    '0257-pan-seared-salmon-steaks.yaml',
    2,
    '¼ cup cornstarch',
    169698,
    '1.000000',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  // RE-PIN (M69 batch, v68): no longer held — C4 at 3.18 (R1) (was held `coating`).
  (
    '0419-parmesan-crusted-chicken-cutlets.yaml',
    2,
    '5 tablespoons unbleached all-purpose flour',
    789890,
    '0.950000',
    '17.49',
    null,
    'auto',
    null,
    _c4Breast,
  ),
  (
    '0419-parmesan-crusted-chicken-cutlets.yaml',
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
  // RE-PIN (M69 batch, v68): no longer held — C4 at 3.18 (R1) (was held `coating`).
  (
    '0419-parmesan-crusted-chicken-cutlets.yaml',
    4,
    '3 large egg whites',
    747997,
    '0.950000',
    '14.96',
    null,
    'auto',
    null,
    _dipBasis,
  ),
  // RE-PIN (M69 batch, v68): no longer held — C4 at 3.18 (R1) (was held `coating`).
  (
    '0419-parmesan-crusted-chicken-cutlets.yaml',
    5,
    '2 tablespoons minced fresh chives (optional)',
    169994,
    '0.920000',
    '0.91',
    null,
    'auto',
    null,
    _dipBasis,
  ),
  (
    '0233-pork-schnitzel-breaded-pork-cutlets.yaml',
    0,
    '7 slices high-quality white sandwich bread, crusts removed, cut into ¾-inch cubes (about 4 cups)',
    174924,
    '0.914286',
    '39.27',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
  (
    '0233-pork-schnitzel-breaded-pork-cutlets.yaml',
    1,
    '½ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '16.92',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
  (
    '0233-pork-schnitzel-breaded-pork-cutlets.yaml',
    2,
    '2 large eggs',
    748967,
    '0.920000',
    '38.11',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '1084-rhode-islandstyle-fried-calamari.yaml',
    2,
    '1½ cups all-purpose flour',
    789890,
    '0.950000',
    '23.12',
    null,
    'auto',
    null,
    'discarded in cooking — only the coat on the food counted · approximation (coat: 3.94 g carbohydrate per 100 g of the raw squid — derived from USDA SR Legacy 171982 "Mollusks, squid, mixed species, cooked, fried"; the dredge\'s excess not counted)',
  ),
  (
    '0077-skillet-chicken-and-rice-with-peas-and-scallions.yaml',
    2,
    '½ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    null,
    null,
    'auto',
    'coating',
    null,
  ),
  (
    '1185-spicy-fried-chicken-sandwiches.yaml',
    2,
    '1 large egg',
    748967,
    '0.920000',
    '50.00',
    null,
    'auto',
    null,
    '1 × 50 g each · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '1185-spicy-fried-chicken-sandwiches.yaml',
    3,
    '3 tablespoons hot sauce, divided',
    2710093,
    '0.923333',
    '48.00',
    null,
    'auto',
    null,
    '3 tablespoon · USDA portion · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '1185-spicy-fried-chicken-sandwiches.yaml',
    4,
    '1 tablespoon all-purpose flour',
    789890,
    '0.950000',
    '7.54',
    null,
    'auto',
    null,
    '1 tablespoon ≈ 15 mL · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '1185-spicy-fried-chicken-sandwiches.yaml',
    6,
    '⅛ teaspoon table salt',
    173468,
    '1.000000',
    '0.75',
    null,
    'auto',
    null,
    '1/8 teaspoon ≈ 1 mL · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '1185-spicy-fried-chicken-sandwiches.yaml',
    7,
    '⅛ teaspoon pepper',
    170931,
    '1.000000',
    '0.29',
    null,
    'auto',
    null,
    '1/8 teaspoon · USDA portion · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
    10,
    '¾ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '14.32',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  (
    '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
    11,
    '2 large eggs',
    748967,
    '0.920000',
    '23.26',
    null,
    'auto',
    null,
    'discarded in cooking — only the dip on the food counted · approximation (dip: 1.17 g per g of the coat\'s carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g; the dip\'s excess not counted)',
  ),
  (
    '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
    13,
    '4 slices high-quality white sandwich bread, pulsed in a food processor to coarse crumbs and dried',
    174924,
    '0.914286',
    '17.73',
    null,
    'auto',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
];

/// The dip sentence an H row's `hold_note` shows (M62 H).
const _ringsDip =
    'Dip in the buttermilk mixture, allowing the excess to drip back into the bowl, then drop into the crumb coating, turning the ring over to coat evenly.';

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
    // RE-PIN (M67 batch, v66): matcherVersion 65 (was 64).
    // RE-PIN (M68 batch, v67): matcherVersion 66 (was 65).
    // RE-PIN (M69 batch, v68): matcherVersion 67 (was 66).
    expect(matcherVersion, 67);
  });

  group('matcher v65 (batch M66)', skip: skipIfNoCorpus, () {
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

    /// [corpus] with [id] appended to its id and slug, computed whole.
    Future<Recipe> variant(Recipe corpus, String id) => compute(
      corpus.copyWith(id: '${corpus.id}-$id', slug: '${corpus.slug}-$id'),
    );

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v65-');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath)
        ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: pendingSearches);
      for (final (file, _, _, _, _, _, _, _, _, _) in [
        ..._reach,
        ..._texts,
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

    IngredientMatchRow rowOf(String file, int position) =>
        rowIn(recipes[file]!, position);

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

    /// [file]'s line [p]: its whole grams (the plan's dredge or dip) and its
    /// record.
    (double, FdcFood) whole(String file, int p) {
      final recipe = recipes[file]!;
      final line = nutritionLines(recipe)[p];
      final food = knownFood(db, rowIn(recipe, p).fdcId!, line: line)!;
      return (lineGrams(db, line, food, recipe: recipe)!.grams, food);
    }

    double cho(FdcFood food) => food.nutrientsPer100g['205']! / 100;

    test('M66 moves exactly its 18 gram rows (design_v2 §2 M66): 3 holds '
        "released (the layers R3 joins), 1 added (R3': onion-rings|5)", () {
      expect(_reach, hasLength(18));
      expectRows(_reach);
      for (final (file, position) in [
        (_almond, 2),
        (_nutCrusted, 2),
        (_lighter, 2),
      ]) {
        final row = rowOf(file, position);
        expect(
          (row.hold, row.gramSource),
          (null, 'discarded'),
          reason: '$file|$position',
        );
      }
      expect(rowOf(_onionRings, 5).hold, 'coating');
      // R2's kept part shows in the basis; every other moved dip reads E-w's.
      expect(_reach.where((r) => r.$10 == _dipKeptBasis).map((r) => r.$2), [
        6,
      ]);
      expect(_reach.where((r) => r.$10 == _dipBasis), hasLength(7));
    });

    test('the 15 C5 batter rows say what is applied (Q1 b) and the 3 '
        'alcohol lines of a fried batter name the missing R6 row (Q8 b) — '
        '0 grams, 0 kcal', () {
      expect(_texts, hasLength(15));
      expect(
        _texts.every(
          (r) => r.$10!.contains(
            ' g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw ',
          ),
        ),
        isTrue,
      );
      expectRows(_texts);
      String? retention(String file, int position) => alcoholRetentionOf(
        recipes[file]!,
        nutritionLines(recipes[file]!)[position],
        rowOf(file, position),
      )?.flag;
      for (final (file, position, minutes) in [
        (_tempura, 4, 2),
        (_fishChips, 10, 7),
        (_sandwiches, 10, 8),
      ]) {
        expect(
          retention(file, position),
          'approximate (USDA retention: alcohol cooked $minutes min keeps '
          '85 %, the stirred-into-hot-liquid figure (USDA prints no row for a '
          'batter fried in oil))',
          reason: '$file|$position',
        );
      }
    });

    test('the rows M66 must not move equal v64 (92 rows)', () {
      expect(_negatives, hasLength(92));
      expectRows(_negatives);
      String g(String file, int p) => g2(rowOf(file, p).grams!);
      expect(g('0114-breaded-chicken-cutlets.yaml', 4), '41.92');
      expect(
        g('0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml', 1),
        '53.35',
      );
      expect(g('0148-crispy-fried-chicken.yaml', 12), '105.95');
      expect(g('0198-crispy-pan-fried-pork-chops.yaml', 1), '46.82');
      // RE-PIN (M69 batch, v68): C4 budgets the flour |2 and its dip |4 |5;
      // the cheese crust |3 stays held (Q5).
      for (final (p, hold) in const [
        (2, null),
        (3, 'coating'),
        (4, null),
        (5, null),
      ]) {
        expect(rowOf(_parmesanCrusted, p).hold, hold, reason: '$p');
      }
    });

    test('R3 by hand: almond-crusted|2 joins at f = B / Σ CHO = 0.869248 — '
        '92 g of almonds at 21.55 % beside the panko at 71.98 % (not '
        "pB's 79.98 on the rounded f 0.8693)", () {
      final b = 5.73 * rowOf(_almond, 0).grams! / 100;
      expect(g2(b), '35.74');
      final (almonds, nuts) = whole(_almond, 2);
      final (panko, crumbs) = whole(_almond, 3);
      expect((g2(almonds), cho(nuts), cho(crumbs)), ('92.00', 0.2155, 0.7198));
      final f = b / (almonds * cho(nuts) + panko * cho(crumbs));
      expect(f.toStringAsFixed(6), '0.869248');
      expect(g2(f * almonds), '79.97');
      expect(g2(f * panko), '25.71');
      // nut-crusted's almonds weigh the line's 'cup, whole' 143 g (not
      // 'cup, ground' 95 g): "1 cup almonds, chopped coarse".
      expect(g2(whole(_nutCrusted, 2).$1), '143.00');
    });

    test('the dips by hand (audit 4 L189, L002, L200, L192): W = 135 / (287 '
        "× 0.401) g a gram of B (R1, C = B), shared by the dip lines' whole "
        'grams less a part a later step eats (R2)', () {
      const w = (15 + 120) / (287 * 0.401);
      expect(w.toStringAsFixed(6), '1.173026');
      // L189 / L002: almond-crusted — eggs, Dijon, zest; S4's "remaining ¼
      // teaspoon zest" is eaten whole on 169103's 'tsp' 2.0 g.
      final b = 5.73 * rowOf(_almond, 0).grams! / 100;
      final (eggs, _) = whole(_almond, 4);
      final (mustard, _) = whole(_almond, 5);
      final (zest, peel) = whole(_almond, 6);
      expect(
        [
          for (final p in peel.portions)
            if (p.description == 'tsp') p.gramWeight,
        ],
        [2.0],
      );
      const eaten = 0.25 * 2.0;
      expect((g2(eggs), g2(mustard), g2(zest)), ('100.00', '5.18', '2.50'));
      final fw = w * b / (eggs + mustard + zest - eaten);
      expect(fw.toStringAsFixed(5), '0.39114');
      expect(g2(fw * eggs), '39.11');
      // 5.1754 g of Dijon (not the design's rounded 5.18 → 2.03).
      expect(g2(fw * mustard), '2.02');
      expect(g2(fw * (zest - eaten) + eaten), '1.28');
      expect(rowOf(_almond, 6).grams, 1.28);
      // L200: nut-crusted — the black pepper is the dip's (its own word),
      // the cayenne the crumb's: f_w over 150 + 10.35 + 0.58.
      final bn = 3.18 * rowOf(_nutCrusted, 0).grams! / 100;
      final dips = [10, 11, 12].map((p) => whole(_nutCrusted, p).$1).toList();
      expect(dips.map(g2).toList(), ['150.00', '10.35', '0.58']);
      final fn = w * bn / dips.fold<double>(0, (a, b) => a + b);
      expect(fn.toStringAsFixed(5), '0.18399');
      expect(g2(fn * dips[2]), '0.11');
      expect(rowOf(_nutCrusted, 8).gramSource, 'portion');
      expect(g2(rowOf(_nutCrusted, 8).grams!), '0.23');
      // L192: best-chicken-parmesan — no coat line; the dip alone opens
      // the budget (R4) on the breast's C1 5.73 (2705975, the record its
      // oil already reads): W = 26.68 g over 50 + 7.54.
      final bp = 5.73 * rowOf(_bestParmesan, 8).grams! / 100;
      expect(g2(rowOf(_bestParmesan, 8).grams!), '396.89');
      expect(g2(w * bp), '26.68');
      final (egg, _) = whole(_bestParmesan, 12);
      final (flour, _) = whole(_bestParmesan, 13);
      final fb = w * bp / (egg + flour);
      expect(fb.toStringAsFixed(5), '0.46361');
      expect((g2(fb * egg), g2(fb * flour)), ('23.18', '3.50'));
    });

    test("R1's reach (closer 3, D1): the two budgets at f = 1 size no dip — "
        "maryland-crab-cakes' flour and crispy-salt-and-pepper-shrimp's "
        'cornstarch count whole (B above Σ) and neither recipe writes a dip, '
        'so W, off B or off Σ, has nothing to size', () {
      const crab = '0288-maryland-crab-cakes.yaml';
      const shrimp = '0279-crispy-salt-and-pepper-shrimp.yaml';
      // "Lightly dredge the crab cakes in the flour": C1 5.73 on the pound
      // of crab over the whole ¼ cup at 77.3 %.
      final bc = 5.73 * rowOf(crab, 0).grams! / 100;
      final (flour, wheat) = whole(crab, 8);
      expect((g2(bc), g2(flour * cho(wheat))), ('25.99', '23.32'));
      expect(g2(rowOf(crab, 8).grams!), g2(flour));
      // 3 of the 5 tablespoons are tossed with the shrimp and eaten whole;
      // the "remaining 2 tablespoons" dredge the jalapeños ("Shaking off
      // excess cornstarch") — 3.94 on 1½ pounds of shrimp over those 2.
      final bs = 3.94 * rowOf(shrimp, 0).grams! / 100;
      final (starch, corn) = whole(shrimp, 8);
      expect((g2(bs), g2(starch * 2 / 5 * cho(corn))), ('26.81', '14.58'));
      expect(g2(rowOf(shrimp, 8).grams!), g2(starch));
      for (final file in [crab, shrimp]) {
        final recipe = recipes[file]!;
        for (var p = 0; p < nutritionLines(recipe).length; p++) {
          expect(
            basisIn(recipe, p) ?? '',
            isNot(contains('the dip on the food')),
            reason: '$file|$p',
          );
        }
      }
    });

    test('the crumb gate (critic F4): a layer no sentence names with a crumb '
        "stays held — 0419's cheese crust (no budget either) and a STATED "
        'synthesized lighter-chicken-parmesan whose one Parmesan sentence '
        'names no crumb', () async {
      expect(rowOf(_parmesanCrusted, 3).hold, 'coating');
      final corpus = loadCorpusRecipe(_lighter);
      const real =
          'Spread the bread crumbs in a shallow dish and cool slightly; when cool, stir in the Parmesan.';
      const edited =
          'Spread the toasted mixture in a shallow dish and cool slightly; when cool, stir in the Parmesan.';
      expect(corpus.steps.first.text, contains(real));
      final noCrumb = await variant(
        corpus.copyWith(
          steps: [
            corpus.steps.first.copyWith(
              text: corpus.steps.first.text.replaceFirst(real, edited),
            ),
            ...corpus.steps.skip(1),
          ],
        ),
        'no-crumb',
      );
      // The coat is budgeted as v64 had it (the panko and flour alone);
      // the Parmesan, still a layer of the coat, stays held.
      expect(rowIn(noCrumb, 2).hold, 'coating');
      expect(rowIn(noCrumb, 2).grams, isNull);
      expect(g2(rowIn(noCrumb, 0).grams!), '16.29');
      expect(g2(rowIn(noCrumb, 3).grams!), '11.07');
      // The real recipe: the Parmesan joins.
      expect(g2(rowOf(_lighter, 2).grams!), '5.04');
    });

    test('R2 reads only the steps AFTER the dip: a STATED synthesized '
        'almond-crusted copy whose first step writes "½ teaspoon zest" '
        "(a non-dredge step before the mixing one) keeps S4's ¼ teaspoon as "
        "|6's eaten part — 1.28 g as the real recipe", () async {
      final corpus = loadCorpusRecipe(_almond);
      final early = await variant(
        corpus.copyWith(
          steps: [
            const RecipeStep(
              number: 0,
              text: 'Sprinkle ½ teaspoon zest over the spinach.',
            ),
            ...corpus.steps,
          ],
        ),
        'early-zest',
      );
      expect(g2(rowIn(early, 6).grams!), '1.28');
      expect(g2(rowIn(early, 4).grams!), '39.11');
      expect(basisIn(early, 6), _dipKeptBasis);
    });

    test('R2 never eats a mention another line writes (closer 1, D1; Run '
        "054 O7) — the item-last-word reader's writers are every line whose "
        "head or last word is the word, and the dip line's own head's: "
        'STATED synthesized almond-crusted copies, each adding one REAL '
        'corpus line to SALAD and one sentence to S4', () async {
      final corpus = loadCorpusRecipe(_almond);
      IngredientLine real(String file, String raw) => [
        for (final g in loadCorpusRecipe(file).ingredients) ...g.items,
      ].firstWhere((l) => l.raw == raw);
      Future<Recipe> plus(IngredientLine line, String sentence, String id) {
        final last = corpus.steps.last;
        return variant(
          corpus.copyWith(
            ingredients: [
              for (final g in corpus.ingredients)
                g.group == 'SALAD' ? g.copyWith(items: [...g.items, line]) : g,
            ],
            steps: [
              ...corpus.steps.take(corpus.steps.length - 1),
              last.copyWith(text: '$sentence ${last.text}'),
            ],
          ),
          id,
        );
      }

      // (a) The verifier's P4: a second "2 large eggs" (0042's own |4 line)
      // whisked into the dressing — the mention is |11's (last word
      // "eggs"): |4 keeps its dip share, |11 counts whole, the eggs once.
      final eggs = corpus.ingredients.first.items[4];
      expect(eggs.raw, '2 large eggs');
      final p4 = await plus(
        eggs,
        'Whisk 2 large eggs into the dressing.',
        'second-eggs',
      );
      expect(nutritionLines(p4)[11].raw, '2 large eggs');
      expect(
        (rowIn(p4, 4).grams, rowIn(p4, 4).gramSource),
        (39.11, 'discarded'),
      );
      expect((rowIn(p4, 11).grams, rowIn(p4, 11).gramSource), (100.0, 'piece'));
      expect(g2(rowIn(p4, 5).grams!), '2.02');
      expect(g2(rowIn(p4, 6).grams!), '1.28');
      // (b) The own head's writers: 1158's "2 large eggs plus 1 large
      // white" (head 'egg', last word "white") writes the "2 large eggs"
      // — never |4's eaten part.
      final white = await plus(
        real('1158-choux-au-craquelin.yaml', '2 large eggs plus 1 large white'),
        'Whisk 2 large eggs into the dressing.',
        'eggs-plus-white',
      );
      expect(
        (rowIn(white, 4).grams, rowIn(white, 4).gramSource),
        (39.11, 'discarded'),
      );
      // (c) The last word's writers: 0667's "1 teaspoon grated lemon zest"
      // (head 'lemon') writes "1 teaspoon lemon zest" — the orange zest
      // |6 eats only S4's "remaining ¼ teaspoon zest", as the real recipe.
      final lemon = await plus(
        real(
          '0667-beets-with-lemon-and-almonds.yaml',
          '1 teaspoon grated lemon zest',
        ),
        'Sprinkle 1 teaspoon lemon zest over the spinach.',
        'lemon-zest',
      );
      expect(nutritionLines(lemon)[11].raw, '1 teaspoon grated lemon zest');
      expect(g2(rowIn(lemon, 6).grams!), '1.28');
      expect(g2(rowIn(lemon, 4).grams!), '39.11');
    });

    test("R3': onion-rings|5's bare \"cayenne\" in the buttermilk-mixture "
        'sentence names it — held `coating` with its siblings, its '
        '`hold_note` the dip sentence', () async {
      final rings = recipes[_onionRings]!;
      final row = rowIn(rings, 5);
      expect((row.hold, row.grams, row.gramSource), ('coating', null, null));
      expect(holdNoteOf(rings, nutritionLines(rings)[5], 'coating'), _ringsDip);
      final item =
          ((await matchesBody(db, provider, rings))['items']!
              as List<Map<String, Object?>>)[5];
      expect((item['match']! as Map)['hold_note'], _ringsDip);
      // Its sibling |4 black pepper keeps its own word's sentence, as before.
      expect(rowIn(rings, 4).hold, 'coating');
    });

    test("R3''s ceiling (closer 2, D2): a line with an own word is named "
        'only where that word is written — a STATED synthesized onion-rings '
        'copy whose S1 calls the black pepper by its bare head ("the salt, '
        'pepper, and cayenne") leaves |4 out of the held dip, counted whole; '
        '|1–|3 and |5 stay held', () async {
      final corpus = loadCorpusRecipe(_onionRings);
      const real = 'the salt, black pepper, and cayenne';
      final s1 = corpus.steps.first;
      expect(s1.text, contains(real));
      final bare = await variant(
        corpus.copyWith(
          steps: [
            s1.copyWith(
              text: s1.text.replaceFirst(real, 'the salt, pepper, and cayenne'),
            ),
            ...corpus.steps.skip(1),
          ],
        ),
        'bare-pepper',
      );
      expect(nutritionLines(bare)[4].raw, '¼ teaspoon ground black pepper');
      final pepper = rowIn(bare, 4);
      expect((pepper.hold, pepper.gramSource), (null, 'density'));
      expect(g2(pepper.grams!), '0.58');
      expect(basisIn(bare, 4), '1/4 teaspoon ≈ 1 mL');
      for (final p in [1, 2, 3, 5]) {
        expect(rowIn(bare, p).hold, 'coating', reason: '|$p');
      }
    });

    test('R4 budgets a dip with no coat line only where the recipe '
        'SHALLOW-FRIES the coated food (closer 2, D1; Q24 b, '
        '`_shallowFries`, its frying oil a medium): a STATED synthesized '
        'best-chicken-parmesan copy whose S4 bakes the cutlets keeps |12 and '
        "|13 whole with D5's bowl flag", () async {
      final corpus = loadCorpusRecipe(_bestParmesan);
      final s4 = corpus.steps[3];
      expect(s4.text, startsWith('Heat oil in 10-inch nonstick skillet'));
      final baked = await variant(
        corpus.copyWith(
          steps: [
            ...corpus.steps.take(3),
            s4.copyWith(
              text:
                  'Place cutlets on a wire rack set in a rimmed baking sheet and bake until golden brown and the chicken registers 160 degrees, 15 to 20 minutes.',
            ),
            ...corpus.steps.skip(4),
          ],
        ),
        'baked',
      );
      const bowl =
          ' · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)';
      expect(
        (rowIn(baked, 12).grams, rowIn(baked, 12).gramSource),
        (50.0, 'piece'),
      );
      expect(basisIn(baked, 12), '1 × 50 g each$bowl');
      expect(
        (g2(rowIn(baked, 13).grams!), rowIn(baked, 13).gramSource),
        ('7.54', 'density'),
      );
      expect(basisIn(baked, 13), '1 tablespoon ≈ 15 mL$bowl');
      // The real recipe shallow-fries: R4's budgeted dip.
      expect(g2(rowOf(_bestParmesan, 12).grams!), '23.18');
    });

    test('per serving: the five recipes move; nut-crusted, lighter and '
        'almond-crusted turn complete (the layer R3 releases was each '
        "one's only uncounted line — design_v2's \"statuses unchanged\" "
        'does not hold)', () {
      (String, String, int?) of(String file) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        return (
          n.status,
          n.caloriesPerServing!.toStringAsFixed(2),
          n.matchedCount,
        );
      }

      // The replay's figure in the comment where a fresh compute differs (a
      // chicken record reads another energy here; the rows' grams are
      // equal); then v64's.
      expect(of(_almond), ('complete', '520.26', 11)); // 520.31; 402.18, 10
      expect(of(_nutCrusted), ('complete', '385.78', 13)); // 385.84; 360.45
      expect(of(_lighter), ('complete', '235.25', 12)); // 235.29; 232.29
      expect(of(_bestParmesan), ('complete', '486.52', 21)); // 486.50; 500.12
      expect(of(_onionRings), ('partial', '217.50', 2)); // = replay; 217.86, 3
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
      for (final MapEntry(key: file, value: recipe) in recipes.entries) {
        m52PlanRuns = 0;
        final items =
            (await matchesBody(db, provider, recipe))['items']!
                as List<Map<String, Object?>>;
        expect(m52PlanRuns, lessThanOrEqualTo(1), reason: file);
        for (final (position, line) in nutritionLines(recipe).indexed) {
          final match = items[position]['match'] as Map<String, Object?>?;
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
    });

    // Last: it writes person decisions (on computed copies).
    test("Q7 (the owner's one-way door, accepted): a person's CONFIRM "
        "through the real PUT reads the plan's share — almond-crusted|2's "
        'almonds 79.97 g `discarded` (no longer 0 g poured away), '
        "best-chicken-parmesan|12's egg 23.18 — and a recompute keeps "
        'each', () async {
      Future<IngredientMatchRow> confirm(Recipe recipe, int position) async {
        await applyMatchOverride(db, provider, recipe, position, {
          'raw': nutritionLines(recipe)[position].raw,
          'confirmed': true,
        });
        final row = rowIn(recipe, position);
        expect(recomputeTotals(db, recipe), isTrue);
        expect(sameMatchRow(rowIn(recipe, position), row), isTrue);
        return row;
      }

      final almond = await variant(loadCorpusRecipe(_almond), 'confirm');
      final nuts = await confirm(almond, 2);
      expect(
        (nuts.status, nuts.grams, nuts.gramSource, nuts.hold),
        ('confirmed', 79.97, 'discarded', null),
      );
      expect(basisIn(almond, 2), _reach.first.$10);
      final parm = await variant(loadCorpusRecipe(_bestParmesan), 'confirm');
      final egg = await confirm(parm, 12);
      expect(
        (egg.status, egg.grams, egg.gramSource),
        ('confirmed', 23.18, 'discarded'),
      );
      expect(basisIn(parm, 12), _dipBasis);
    });
  });
}
