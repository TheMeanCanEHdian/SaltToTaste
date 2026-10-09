// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v53 (batch M52, coats and frying-oil uptake; matcherVersion 52;
// prep47 design_v2 §1 Q2 (a), Q3 (a) and Q24 (b), §2 "M52", critic F1, F2,
// F8 and F13, decided under the owner's 2026-10-07 standing authorization,
// re-ruling checkpoint 9 Q2, the 2026-10-03 (night) (1) and — for a coated
// food browned in the oil — the 2026-10-03 R4; zero requests): a held
// dredge counts its share of a coat budget sized from the coated food
// (k by the coat's shape, read from USDA FNDDS fried and baked coated
// recipes' `inputFoods`; the last cook decides); a zeroed frying oil
// counts what its fried food absorbs (u per food, read or derived) on top
// of its kept part, capped at the line; an oil of ¼ cup or more heated for
// a coated food browned in it is a frying oil (five lines — the fifth,
// 0415's, ruled in by the closer) and that food's crumbs a held dredge.
// Every row value is the v53 compute of the WHOLE recipe on recorded real
// FDC answers (FixtureProvider; 20 searches and 4 foods added --from-db
// from snapshot 22, JSON-equal — 8 and 1 of them for verify2 D2's rows),
// never the network; the replay of snapshot 22 agrees on every pinned row
// but one (0255|1's oil lands on the snapshot's cached peanut-oil answer
// there, 2710187: 226.78 g — the same 170.77 g of uptake on its 56.00 g
// kept part).

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

/// (file, section title or null, position, raw, fdc id, grams, gram
/// source, hold, basis) — each the v53 compute's row (an `auto` row).
const List<
  (String, String?, int, String, int?, String?, String?, String?, String?)
>
_rows = [
  // C1 thigh k 6.10 (2706047, critic F8): 680.39 × 6.10 / 100 = 41.50 g CHO ÷ cornstarch 91.27 %
  (
    '0527-karaage-japanese-fried-chicken-thighs.yaml',
    null,
    7,
    '1¼ cups cornstarch',
    169698,
    '45.47',
    'discarded',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 6.10 g carbohydrate per 100 g of the raw chicken thigh — USDA FNDDS 2706047 recipe: 15 g breading per 98.39 g raw chicken thigh; the dredge's excess not counted)",
  ),
  // O1b 7.11 % × 680.39 g of thighs
  (
    '0527-karaage-japanese-fried-chicken-thighs.yaml',
    null,
    8,
    '1 quart vegetable oil for frying',
    2710180,
    '48.38',
    'discarded',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 7.11 % of the raw chicken thigh's weight — USDA FNDDS 2706047 recipe: 7 g oil per 98.39 g raw chicken thigh)",
  ),
  // C1d 8.79 (2705842, "coat with flour again"): 1266.89 × 8.79 / 100 = 111.36 g CHO ÷ flour
  (
    '0148-crispy-fried-chicken.yaml',
    null,
    8,
    '4 cups (20 ounces) unbleached all-purpose flour',
    789890,
    '144.06',
    'discarded',
    null,
    // RE-PIN (M58 batch, v57, S): the stand-in named (was without it).
    "discarded in cooking — only the coat on the food counted · approximation (coat: 8.79 g carbohydrate per 100 g of the raw chicken — USDA FNDDS 2705842 recipe: 20 g breading per 90.99 g raw beef steak (no record for chicken; read as Beef, steak, country fried); the dredge's excess not counted)",
  ),
  // O1c: bone-in skin-on, 0 g, its basis
  (
    '0148-crispy-fried-chicken.yaml',
    null,
    7,
    '3–4 quarts peanut oil or vegetable oil, for frying',
    2710187,
    '0.00',
    'discarded',
    null,
    'frying oil: 0 g — USDA FNDDS 2705996 recipe adds 7 g oil per 100 g, but the fried skin-on parts carry less fat (17.2 g) than the raw parts counted here: no net uptake',
  ),
  // C2 fish 7.41 (2706243), B split by CHO with |5: the bread at 49 % carbohydrate
  (
    '0254-crunchy-oven-fried-fish.yaml',
    null,
    0,
    '4 slices high-quality white sandwich bread, torn into quarters',
    174924,
    '59.82',
    'discarded',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 7.41 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706243 recipe: 15 g breading per 81 g raw cod; the dredge's excess not counted)",
  ),
  // C2 fish: its eaten 5 tablespoons (37.71) + f × the ¼ cup
  (
    '0254-crunchy-oven-fried-fish.yaml',
    null,
    5,
    '¼ cup plus 5 tablespoons unbleached all-purpose flour',
    789890,
    '53.82',
    'discarded',
    null,
    'discarded in cooking — only "plus 5 tablespoons unbleached all-purpose flour" and the coat on the food counted · approximation (coat: 7.41 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706243 recipe: 15 g breading per 81 g raw cod; the dredge\'s excess not counted)',
  ),
  // C3 3.94 (SR 171982, derived): f capped at 1 — its 2-tablespoon dredge part whole + the eaten 3 tablespoons
  (
    '0279-crispy-salt-and-pepper-shrimp.yaml',
    null,
    8,
    '5 tablespoons cornstarch',
    169698,
    '39.92',
    'discarded',
    null,
    'discarded in cooking — only the part the recipe keeps and the coat on the food counted · approximation (coat: 3.94 g carbohydrate per 100 g of the raw shrimp — derived from USDA SR Legacy 171982 "Mollusks, squid, mixed species, cooked, fried"; the dredge\'s excess not counted)',
  ),
  // O3 5.3 % × 680.39 g of shrimp (derived)
  // RE-PIN (M59 batch, v58, C): on top of the 2 tablespoons step 5
  // reserves and step 6 heats, 28.00 g kept (was 36.06)
  (
    '0279-crispy-salt-and-pepper-shrimp.yaml',
    null,
    7,
    '4 cups vegetable oil',
    2710180,
    '64.06',
    'discarded',
    null,
    'discarded in cooking — only the part the recipe keeps and the oil the fried food absorbs counted · approximation (frying oil absorbed: 5.3 % of the raw shrimp\'s weight — derived from USDA SR Legacy 171982 "Mollusks, squid, mixed species, cooked, fried")',
  ),
  // C5 15.38 (2706244): 680.39 × 15.38 / 100 less the counted cornstarch |3 carbohydrate
  // RE-PIN (M58 batch, v57, W): the batter's lines are coat parts, never
  // off B — every part at one f 0.4924 (was 59.95, the batter's excess
  // "the dredge's")
  (
    '0255-fish-and-chips.yaml',
    null,
    2,
    '1½ cups unbleached all-purpose flour',
    789890,
    '89.12',
    'discarded',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading per 65 g raw cod; the batter's excess not counted)",
  ),
  // the counted cornstarch (the batter): unchanged, off the budget
  // RE-PIN (M58 batch, v57, W): a coat part at f (was 63.88 g counted
  // whole, `density`, the D5 flag)
  (
    '0255-fish-and-chips.yaml',
    null,
    3,
    '½ cup cornstarch',
    169698,
    '31.45',
    'discarded',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 15.38 g carbohydrate per 100 g of the raw cod — USDA FNDDS 2706244 recipe: 25 g breading per 65 g raw cod; the batter's excess not counted)",
  ),
  // O2 cod 15.38 % + O4 chips 6.0 % on top of its kept ¼ cup
  // RE-PIN (M59 batch, v58, F1): the ¼ cup tossed with the fries is
  // drained and rinsed off in step 1 — the uptake alone (was 225.19)
  (
    '0255-fish-and-chips.yaml',
    null,
    1,
    '3 quarts plus ¼ cup peanut oil or canola oil',
    172336,
    '170.78',
    'discarded',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted ("plus ¼ cup peanut oil or canola oil": the steps rinse it off) · approximation (frying oil absorbed: 15.38 % of the raw cod\'s weight — USDA FNDDS 2706244 recipe: 10 g oil per 65 g raw cod; 6.0 % of the raw potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil")',
  ),
  // O4 6.0 % × 918.52 g of potatoes (derived, SR 170698)
  (
    '0316-classic-french-fries.yaml',
    null,
    1,
    '2 quarts peanut oil',
    2710187,
    '55.11',
    'discarded',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil")',
  ),
  // eggplant 6.0 %, a flagged stand-in on SR 170698
  (
    '0053-crispy-thai-eggplant-salad.yaml',
    null,
    10,
    '2 cups vegetable oil',
    2710180,
    '40.82',
    'discarded',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw eggplant\'s weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil" (no record for eggplant; read as Fast foods, potato, french fried in vegetable oil))',
  ),
  // the strained-and-kept shallot oil: shallots have no class, 0 g
  // RE-PIN (M64 batch, v63, Q12 (a)): still no uptake (no class), but the
  // section's yield prints the oil out — 2 cups in, about 1¾ cups out: the
  // ¼ cup kept is counted, 56.00 g (was 0.00).
  (
    '0053-crispy-thai-eggplant-salad.yaml',
    'Fried Shallots and Fried Shallot Oil',
    1,
    '2 cups vegetable oil',
    2710180,
    '56.00',
    'discarded',
    null,
    "discarded in cooking — only the part the recipe keeps counted · approximate (the difference of the yield's printed volumes: 2 cups in, about 1¾ cups out as shallot oil — the ¼ cup the shallots, the pan and the towel keep counted as eaten)",
  ),
  // O4p 5.5 % × 1204.85 g (derived, SR 168200) — named by its "Fried …" title, no steps printed
  (
    '0706-platanos-maduros-fried-sweet-plantains.yaml',
    null,
    0,
    '3 cups vegetable oil',
    2710180,
    '66.27',
    'discarded',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 5.5 % of the raw plantains\' weight — derived from USDA SR Legacy 168200 "Plantains, yellow, fried, Latino restaurant")',
  ),
  // C1 breast 5.73: its eaten teaspoon + f × the dredge
  (
    '1133-chicken-francese.yaml',
    null,
    5,
    '¾ cup all-purpose flour, divided',
    789890,
    '61.35',
    'discarded',
    null,
    "discarded in cooking — only the part the recipe keeps and the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  // O1a split by grams: the olive oil
  (
    '1133-chicken-francese.yaml',
    null,
    8,
    '⅓ cup extra-virgin olive oil for frying',
    748608,
    '26.13',
    'discarded',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  // O1a split by grams: the vegetable oil
  (
    '1133-chicken-francese.yaml',
    null,
    9,
    '⅓ cup vegetable oil for frying',
    2710180,
    '26.89',
    'discarded',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  // C1d 8.79 on 850.49 g of cube steak
  (
    '0304-chicken-fried-steaks.yaml',
    null,
    0,
    '3 cups unbleached all-purpose flour',
    789890,
    '96.71',
    'discarded',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 8.79 g carbohydrate per 100 g of the raw beef — USDA FNDDS 2705842 recipe: 20 g breading per 90.99 g raw beef steak; the dredge's excess not counted)",
  ),
  // O1d 9.89 % (read, the cube steak holds its dredge) — was 18.1 in P3
  (
    '0304-chicken-fried-steaks.yaml',
    null,
    8,
    '4–5 cups peanut oil',
    2710187,
    '84.11',
    'discarded',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 9.89 % of the raw beef's weight — USDA FNDDS 2705842 recipe: 9 g oil per 90.99 g raw beef steak)",
  ),
  // O2s 15.38 % (2706364) × 680.39 g
  (
    '0511-shrimp-tempura.yaml',
    null,
    0,
    '3 quarts peanut or vegetable oil',
    2710187,
    '104.64',
    'discarded',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 15.38 % of the raw shrimp's weight — USDA FNDDS 2706364 recipe: 10 g oil per 65 g raw shrimp)",
  ),
  // O5 30.32 % (2710042) × 453.59 g
  // RE-PIN (M59 batch, v58, D): scaled to the batter the CAULIFLOWER group
  // carries, 122.16 of FNDDS's 229.20 g carbohydrate (was 137.53)
  (
    '0672-buffalo-cauliflower-bites.yaml',
    null,
    4,
    '1–2 quarts peanut or vegetable oil',
    2710187,
    '73.30',
    'discarded',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed — derived: 16.16 % of the raw cauliflower's weight — USDA FNDDS 2710042 recipe: 12 g oil per 39.58 g raw cauliflower, scaled to the recipe's batter (122.16 g of 229.20 g carbohydrate))",
  ),
  // C2 chicken 3.18 by the LAST cook (browned, then baked; critic F2)
  (
    '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
    null,
    10,
    '¾ cup unbleached all-purpose flour',
    789890,
    '14.32',
    'discarded',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  // C2 with |10, split by carbohydrate
  (
    '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
    null,
    13,
    '4 slices high-quality white sandwich bread, pulsed in a food processor to coarse crumbs and dried',
    174924,
    '17.73',
    'discarded',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  // Q24 b: its eaten tablespoon kept + O1a 6.68 % × 623.69 g
  (
    '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
    null,
    12,
    '1 tablespoon plus ¾ cup vegetable oil',
    2710180,
    '55.66',
    'discarded',
    null,
    'discarded in cooking — only "1 tablespoon" and the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast\'s weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)',
  ),
  // F13: 23.07 kept + O4c 10.9 % × 137.78 g of grated potato
  (
    '0215-horseradish-crusted-beef-tenderloin.yaml',
    null,
    3,
    '1 cup plus 2 teaspoons vegetable oil',
    2710180,
    '38.09',
    'discarded',
    null,
    'discarded in cooking — only "plus 2 teaspoons vegetable oil", the 1 tablespoon the steps keep and the oil the fried food absorbs counted · approximation (frying oil absorbed: 10.9 % of the raw potatoes\' weight — derived from USDA SR Legacy 19411 "Snacks, potato chips, plain, salted")',
  ),
  // Q24 b cascade (critic F1): held, then C1 5.73 × 793.79 / 100 = 45.48 g CHO ÷ panko 71.98 %
  (
    '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
    null,
    0,
    '2 cups panko bread crumbs',
    174928,
    '63.19',
    'discarded',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  // Q24 b: O1a 6.68 % × 793.79 g (was 112.00 counted whole)
  (
    '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
    null,
    4,
    '½ cup vegetable oil',
    2710180,
    '53.02',
    'discarded',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  // no dredge (3 tablespoons < ¼ cup): byte-equal, counted whole
  (
    '0287-easy-salmon-cakes.yaml',
    null,
    0,
    '3 tablespoons plus ¾ cup panko bread crumbs',
    174928,
    '55.45',
    'density',
    null,
    '3 tablespoon ≈ 44 mL + ¾ cup panko bread crumbs',
  ),
  // Q24 b: salmon has no record — O1a stand-in × 566.99 g
  (
    '0287-easy-salmon-cakes.yaml',
    null,
    11,
    '½ cup vegetable oil',
    2710180,
    '37.87',
    'discarded',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw salmon's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast (no record for salmon; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw))",
  ),
  // C1 5.73 (a crumb line in the cake: not C3), f capped at 1
  (
    '0288-maryland-crab-cakes.yaml',
    null,
    8,
    '¼ cup unbleached all-purpose flour',
    789890,
    '30.16',
    'discarded',
    null,
    // RE-PIN (M58 batch, v57, S): the stand-in named (was without it).
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw crab — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for crab; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
  // Q24 b: was ambiguous_medium; crab O1a stand-in × 453.59 g
  // RE-PIN (M63 batch, v62, Q11): the crab cake's own read oil, FNDDS
  // 2706549 7.69 % × 453.59 g (was 30.30 g on the breast's 6.68 %).
  (
    '0288-maryland-crab-cakes.yaml',
    null,
    9,
    '¼ cup vegetable oil',
    2710180,
    '34.88',
    'discarded',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 7.69 % of the raw crab's weight — USDA FNDDS 2706549 recipe: 5 g oil per 65 g raw crab)",
  ),
  // Q24 b, the FIFTH oil (katsu's twin; missed by P3's ≥ 100 g probe): O1a × 396.89 g
  (
    '0415-best-chicken-parmesan.yaml',
    null,
    19,
    '⅓ cup vegetable oil',
    2710180,
    '26.51',
    'discarded',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  // fried, then BAKED: the last cook decides — C2 3.18 (P3 had C1)
  (
    '0149-easier-fried-chicken.yaml',
    null,
    8,
    '2 cups unbleached all-purpose flour',
    789890,
    '45.60',
    'discarded',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.18 g carbohydrate per 100 g of the raw chicken — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw chicken breast; the dredge's excess not counted)",
  ),
  // O1c: bone-in skin-on, 0 g, its basis
  (
    '0149-easier-fried-chicken.yaml',
    null,
    10,
    '1¾ cups vegetable oil',
    2710180,
    '0.00',
    'discarded',
    null,
    'frying oil: 0 g — USDA FNDDS 2705996 recipe adds 7 g oil per 100 g, but the fried skin-on parts carry less fat (17.2 g) than the raw parts counted here: no net uptake',
  ),
  // negative: C4 sautéed dusting stays held
  (
    '0418-chicken-piccata.yaml',
    null,
    3,
    '½ cup unbleached all-purpose flour',
    789890,
    null,
    null,
    'coating',
    null,
  ),
  // negative: C4 stays held
  (
    '0257-pan-seared-salmon-steaks.yaml',
    null,
    2,
    '¼ cup cornstarch',
    169698,
    null,
    null,
    'coating',
    null,
  ),
  // negative: the nut layer stays held
  (
    '0042-almond-crusted-chicken-with-wilted-spinach-salad.yaml',
    null,
    2,
    '1 cup sliced almonds',
    170567,
    null,
    null,
    'coating',
    null,
  ),
  // C1 5.73 on the breasts, the panko alone (the almonds stay held)
  (
    '0042-almond-crusted-chicken-with-wilted-spinach-salad.yaml',
    null,
    3,
    '½ cup panko (Japanese-style bread crumbs)',
    174928,
    '29.57',
    'discarded',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast; the dredge's excess not counted)",
  ),
  // negative: a baked vegetable coat (no meat line) stays held
  (
    '0407-eggplant-parmesan.yaml',
    null,
    5,
    '1 cup unbleached all-purpose flour',
    789890,
    null,
    null,
    'coating',
    null,
  ),
  // negative: a fried batter whole — 0 g
  // RE-PIN (M61 batch, v60): falafel takes its uptake on the raw mix (R-e:
  // 21.64 % derived from SR 172455 × the FALAFEL group's 395.35 g; was
  // 0.00, "discarded in cooking — counted as 0 g").
  (
    '0570-falafel.yaml',
    null,
    11,
    '2 quarts vegetable oil for frying',
    2710180,
    '85.55',
    'discarded',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 21.64 % of the raw falafel mix\'s weight — derived from USDA SR Legacy 172455 "Falafel, home-prepared")',
  ),
  // negative: confit — 0 g
  (
    '1077-turkey-thigh-confit-with-citrus-mustard-sauce.yaml',
    null,
    6,
    '6 cups duck fat, chicken fat, or vegetable oil for confit',
    173572,
    '0.00',
    'discarded',
    null,
    'discarded in cooking — counted as 0 g · approximation (counted as Fat, goose)',
  ),
  // negative: tempeh has no class — its kept 28 g, byte-equal
  (
    '1193-crispy-tempeh-with-sambal-sauce.yaml',
    null,
    5,
    '1 cup vegetable oil',
    2710180,
    '28.00',
    'discarded',
    null,
    'discarded in cooking — only the part the recipe keeps counted',
  ),
  // verify2 D2: the read/derived figures with corpus reach no row pinned
  // C2 pork 6.61 (2705871; P3 had 6.42): B = 793.79 × 6.61 / 100 = 52.47 g CHO over bread 112 × 49.42 % + flour 30.16 × 77.3 % = 78.66 → f 0.66701
  (
    '0206-crunchy-baked-pork-chops.yaml',
    null,
    2,
    '4 slices high-quality white sandwich bread, torn into 1-inch pieces',
    174924,
    '74.70',
    'discarded',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 6.61 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705871 recipe: 10 g breading per 108.38 g raw pork chop; the dredge's excess not counted)",
  ),
  // C2 pork: its eaten 6 tablespoons (45.25) + f × the ¼ cup (30.16)
  (
    '0206-crunchy-baked-pork-chops.yaml',
    null,
    10,
    '¼ cup plus 6 tablespoons unbleached all-purpose flour',
    789890,
    '65.37',
    'discarded',
    null,
    'discarded in cooking — only "plus 6 tablespoons unbleached all-purpose flour" and the coat on the food counted · approximation (coat: 6.61 g carbohydrate per 100 g of the raw pork — USDA FNDDS 2705871 recipe: 10 g breading per 108.38 g raw pork chop; the dredge\'s excess not counted)',
  ),
  // C2 legs 3.10 (2705998; P3 had 3.25): 1060 × 3.10 / 100 = 32.86 g CHO ÷ Melba toast 76.6 %
  (
    '0150-oven-fried-chicken.yaml',
    null,
    8,
    '1 box (about 5 ounces) plain Melba toast, crushed',
    174977,
    '42.90',
    'discarded',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 3.10 g carbohydrate per 100 g of the raw chicken legs — USDA FNDDS 2705998 recipe: 10 g breading per 129.02 g raw chicken legs; the dredge's excess not counted)",
  ),
  // O1w 6.61 % (2706065; P3 had 6.2) × 680.39 g of wings
  (
    '0151-buffalo-wings.yaml',
    null,
    5,
    '1–2 quarts peanut oil, for frying',
    2710187,
    '44.97',
    'discarded',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.61 % of the raw chicken wings' weight — USDA FNDDS 2706065 recipe: 7 g oil per 105.96 g raw chicken wing)",
  ),
  // O1w 6.61 % × 680.39 g of wings
  (
    '0526-dakgangjeong-korean-fried-chicken-wings.yaml',
    null,
    7,
    '2 quarts vegetable oil',
    2710180,
    '44.97',
    'discarded',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.61 % of the raw chicken wings' weight — USDA FNDDS 2706065 recipe: 7 g oil per 105.96 g raw chicken wing)",
  ),
  // O2 haddock 15.38 % (2706258; P3 had 15.4) × 566.99 g
  (
    '1081-crispy-fish-sandwiches-with-tartar-sauce.yaml',
    null,
    11,
    '2 quarts peanut or vegetable oil for frying',
    2710187,
    '87.20',
    'discarded',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 15.38 % of the raw haddock's weight — USDA FNDDS 2706258 recipe: 10 g oil per 65 g raw haddock)",
  ),
  // O6 13.4 % (derived, SR 167525; P3 had 13.5) × 312 g of corn tortillas
  (
    '0491-spicy-mexican-shredded-pork-tostadas.yaml',
    null,
    10,
    '¾ cup vegetable oil',
    2710180,
    '41.81',
    'discarded',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 13.4 % of the raw corn tortillas\' weight — derived from USDA SR Legacy 167525 "Tostada shells, corn")',
  ),
  // O3 Mollusks 5.3 % (derived, SR 171982; P3 had 5.9) × 453.59 g of squid
  (
    '1084-rhode-islandstyle-fried-calamari.yaml',
    null,
    7,
    '2 quarts vegetable oil for frying',
    2710180,
    '24.04',
    'discarded',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 5.3 % of the raw squid\'s weight — derived from USDA SR Legacy 171982 "Mollusks, squid, mixed species, cooked, fried")',
  ),
  // C3 3.94 (derived, SR 171982), f < 1: 453.59 × 3.94 / 100 = 17.87 g CHO ÷ flour 77.3 %
  (
    '1084-rhode-islandstyle-fried-calamari.yaml',
    null,
    2,
    '1½ cups all-purpose flour',
    789890,
    '23.12',
    'discarded',
    null,
    'discarded in cooking — only the coat on the food counted · approximation (coat: 3.94 g carbohydrate per 100 g of the raw squid — derived from USDA SR Legacy 171982 "Mollusks, squid, mixed species, cooked, fried"; the dredge\'s excess not counted)',
  ),
  // sweet potatoes 6.0 % × 1088.62 g, a flagged stand-in on SR 170698
  (
    '0318-thick-cut-sweet-potato-fries.yaml',
    null,
    4,
    '3 cups peanut oil',
    2710187,
    '65.32',
    'discarded',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw sweet potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil" (no record for sweet potatoes; read as Fast foods, potato, french fried in vegetable oil))',
  ),
];

void main() {
  test('the matcher version carries the batch (update the literal with a '
      'bump)', () {
    // RE-PIN (Q25 batch, v54): matcherVersion 53 (was 52).
    // RE-PIN (M57 batch, v56): matcherVersion 55 (was 54).
    // RE-PIN (M58 batch, v57): matcherVersion 56 (was 55).
    // RE-PIN (M59 batch, v58): matcherVersion 57 (was 56).
    // RE-PIN (M60 batch, v59): matcherVersion 58 (was 57).
    // RE-PIN (M61 batch, v60): matcherVersion 59 (was 58).
    // RE-PIN (M62 batch, v61): matcherVersion 60 (was 59).
    // RE-PIN (M63 batch, v62): matcherVersion 61 (was 60).
    // RE-PIN (M64 batch, v63): matcherVersion 62 (was 61).
    expect(matcherVersion, 62);
  });

  group('matcher v53 (batch M52)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('salt-v53-');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath)
        ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider();
    });

    tearDown(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    /// [file] stored and computed whole (its sections first, as the
    /// per-recipe job does); its stored recipe.
    Future<Recipe> computed(String file) async {
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
      return db.recipeByIdOrSlug(host.id)!.recipe;
    }

    IngredientMatchRow rowOf(Recipe r, int position) => db
        .ingredientMatchesFor(r.id)
        .singleWhere((m) => m.position == position);

    double gramsOf(Recipe r, int position) => rowOf(r, position).grams!;

    /// The line's grams on its row's record, whole ([lineGrams]).
    double wholeOf(Recipe r, int position) {
      final line = nutritionLines(r)[position];
      return lineGrams(
        db,
        line,
        knownFood(db, rowOf(r, position).fdcId!, line: line),
        recipe: r,
      )!.grams;
    }

    /// The record's carbohydrate, a fraction of its weight.
    double cho(Recipe r, int position) =>
        knownFood(db, rowOf(r, position).fdcId!)!.nutrientsPer100g['205']! /
        100;

    String g2(double v) => v.toStringAsFixed(2);

    test('each line computed in its WHOLE recipe lands its record, grams, '
        'source, hold and basis', () async {
      final recipes = <String, Recipe>{};
      for (final (
            file,
            section,
            position,
            raw,
            fdcId,
            grams,
            source,
            hold,
            basis,
          )
          in _rows) {
        final host = recipes[file] ??= await computed(file);
        final recipe = section == null
            ? host
            : nutritionRecipeOf(db, sectionKeyOf(host.id, section))!.recipe;
        final line = nutritionLines(recipe)[position];
        final row = db
            .ingredientMatchesFor(recipe.id)
            .singleWhere((r) => r.position == position);
        final reason = '$file|$section|$position';
        expect(line.raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.status, 'auto', reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(row.gramSource, source, reason: reason);
        expect(row.hold, hold, reason: reason);
        expect(
          gramBasisFor(db, line, row, recipe: recipe),
          basis,
          reason: reason,
        );
      }
    });

    test('the read figures, by hand: each row re-derived from its coated or '
        "fried food's row and the records' carbohydrate "
        '(p3_read_figures.md)', () async {
      // Karaage (C1 thigh 6.10 / O1b 7.11 — the thigh's own record, F8).
      final karaage = await computed(
        '0527-karaage-japanese-fried-chicken-thighs.yaml',
      );
      final thighs = gramsOf(karaage, 6);
      expect(g2(thighs), '680.39');
      expect(cho(karaage, 7), 0.9127);
      expect(
        g2(gramsOf(karaage, 7)),
        g2(thighs * 6.10 / 100 / cho(karaage, 7)),
      );
      expect(g2(gramsOf(karaage, 8)), g2(thighs * 7.11 / 100));
      // Crispy Fried Chicken (C1d 8.79 on the skin-on parts; O1c 0).
      final fried = await computed('0148-crispy-fried-chicken.yaml');
      expect(
        g2(gramsOf(fried, 8)),
        g2(gramsOf(fried, 6) * 8.79 / 100 / cho(fried, 8)),
      );
      expect(gramsOf(fried, 7), 0);
      // Fish and chips: C5 15.38 less the counted cornstarch's
      // carbohydrate; the oil's cod 15.38 % + chips 6.0 % on its kept ¼ cup.
      // RE-PIN (M58 batch, v57, W): the batter's lines (|3 |4 |5 |8 |10)
      // are coat parts beside the flour, never off B — one f for all.
      final chips = await computed('0255-fish-and-chips.yaml');
      final cod = gramsOf(chips, 9);
      const batter = [2, 3, 4, 5, 8, 10];
      final batterF =
          cod *
          15.38 /
          100 /
          batter.fold<double>(
            0,
            (n, p) => n + wholeOf(chips, p) * cho(chips, p),
          );
      for (final p in batter) {
        expect(g2(gramsOf(chips, p)), g2(batterF * wholeOf(chips, p)));
      }
      // RE-PIN (M59 batch, v58, F1): the kept ¼ cup is rinsed off (step 1
      // tosses the fries in it, then drains and rinses them) — the uptake
      // alone.
      expect(
        g2(gramsOf(chips, 1)),
        g2(cod * 15.38 / 100 + gramsOf(chips, 0) * 6.0 / 100),
      );
      // Katsu (the Q24 b cascade): C1 5.73 on the breasts, the panko alone.
      final katsu = await computed(
        '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
      );
      expect(
        g2(gramsOf(katsu, 0)),
        g2(gramsOf(katsu, 3) * 5.73 / 100 / cho(katsu, 0)),
      );
      expect(g2(gramsOf(katsu, 4)), g2(gramsOf(katsu, 3) * 6.68 / 100));
      // Stuffed cutlets (C2 3.18 by the last cook, F2): B shared by the
      // flour and the bread by their carbohydrate.
      final stuffed = await computed(
        '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
      );
      final budget = gramsOf(stuffed, 8) * 3.18 / 100;
      final f =
          budget /
          (wholeOf(stuffed, 10) * cho(stuffed, 10) +
              wholeOf(stuffed, 13) * cho(stuffed, 13));
      expect(f, lessThan(1));
      expect(g2(gramsOf(stuffed, 10)), g2(f * wholeOf(stuffed, 10)));
      expect(g2(gramsOf(stuffed, 13)), g2(f * wholeOf(stuffed, 13)));
      // Francese: the two oils of one fry split the breasts' uptake by
      // their grams.
      final francese = await computed('1133-chicken-francese.yaml');
      final uptake = gramsOf(francese, 0) * 6.68 / 100;
      final olive = wholeOf(francese, 8);
      final vegetable = wholeOf(francese, 9);
      expect(
        g2(gramsOf(francese, 8)),
        g2(uptake * olive / (olive + vegetable)),
      );
      expect(
        g2(gramsOf(francese, 9)),
        g2(uptake * vegetable / (olive + vegetable)),
      );
      // Horseradish (F13): the kept 23.07 g + the grated potato's chips
      // uptake on top.
      final horseradish = await computed(
        '0215-horseradish-crusted-beef-tenderloin.yaml',
      );
      expect(
        g2(gramsOf(horseradish, 3)),
        g2(23.07 + gramsOf(horseradish, 10) * 10.9 / 100),
      );
    });

    test('Q24 (b): exactly five oils heated for a coated food browned in '
        "them are frying oil — the fifth, 0415, katsu's twin — and a "
        "sauté's tablespoons are none; 0287's panko is no dredge (its "
        'first amount, 3 tablespoons, is under ¼ cup)', () {
      DiscardedMedium? mediumOf(String file, String raw) {
        final r = loadCorpusRecipe(file);
        final line = nutritionLines(r).singleWhere((l) => l.raw == raw);
        return discardedMediumOf(r, line, normalizeItem(lineItemOf(line)));
      }

      for (final (file, raw) in const [
        (
          '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
          '1 tablespoon plus ¾ cup vegetable oil',
        ),
        (
          '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
          '½ cup vegetable oil',
        ),
        ('0287-easy-salmon-cakes.yaml', '½ cup vegetable oil'),
        ('0288-maryland-crab-cakes.yaml', '¼ cup vegetable oil'),
        ('0415-best-chicken-parmesan.yaml', '⅓ cup vegetable oil'),
      ]) {
        expect(mediumOf(file, raw), DiscardedMedium.fryingOil, reason: file);
      }
      // 0415's sauce oil and a sauté's (0418 piccata) stay counted.
      expect(
        mediumOf(
          '0415-best-chicken-parmesan.yaml',
          '2 tablespoons extra-virgin olive oil',
        ),
        isNull,
      );
      expect(
        mediumOf(
          '0287-easy-salmon-cakes.yaml',
          '3 tablespoons plus ¾ cup panko bread crumbs',
        ),
        isNull,
      );
      expect(
        mediumOf(
          '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
          '2 cups panko bread crumbs',
        ),
        DiscardedMedium.coating,
      );
    });

    test(
      'every path that totals the recipe re-reads the budget: a '
      "person's grams typed on the coated food move the coat and the oil "
      '(the plain recompute), a second recompute writes nothing; a '
      "person's confirm of the coat keeps the budget's grams (verify2 D1: "
      "the engine's current weight, as a confirm keeps rule B1's parts)",
      () async {
        final karaage = await computed(
          '0527-karaage-japanese-fried-chicken-thighs.yaml',
        );
        final thighs = nutritionLines(karaage)[6];
        await applyMatchOverride(db, provider, karaage, 6, {
          'raw': thighs.raw,
          'grams': 340.2,
        });
        expect(
          g2(gramsOf(karaage, 7)),
          g2(340.2 * 6.10 / 100 / cho(karaage, 7)),
        );
        expect(g2(gramsOf(karaage, 8)), g2(340.2 * 7.11 / 100));
        final before = [
          for (final r in db.ingredientMatchesFor(karaage.id)) r.updatedAt,
        ];
        expect(recomputeTotals(db, karaage), isTrue);
        expect([
          for (final r in db.ingredientMatchesFor(karaage.id)) r.updatedAt,
        ], before);
        await applyMatchOverride(db, provider, karaage, 7, {
          'raw': nutritionLines(karaage)[7].raw,
          'confirmed': true,
        });
        final confirmed = rowOf(karaage, 7);
        expect(
          (confirmed.status, g2(confirmed.grams!), confirmed.gramSource),
          ('confirmed', g2(340.2 * 6.10 / 100 / cho(karaage, 7)), 'discarded'),
        );
      },
    );

    test("verify2 D1: a person's CONFIRM of the budgeted coat and the uptake "
        'oil keeps the grams the GET showed (karaage |7 45.47, |8 48.38), '
        'the totals and the status unmoved; the confirmed rows follow the '
        "coated food's typed grams (the totals' write) and a full re-match "
        'keeps them', () async {
      final karaage = await computed(
        '0527-karaage-japanese-fried-chicken-thighs.yaml',
      );
      final lines = nutritionLines(karaage);
      final before = db.nutritionFor(karaage.id)!;
      final bases = [
        for (final p in const [7, 8])
          gramBasisFor(db, lines[p], rowOf(karaage, p), recipe: karaage),
      ];
      expect(bases[0], startsWith('discarded in cooking — only the coat'));
      expect(bases[1], startsWith('discarded in cooking — only the oil'));
      for (final p in const [8, 7]) {
        await applyMatchOverride(db, provider, karaage, p, {
          'raw': lines[p].raw,
          'confirmed': true,
        });
      }
      (String, String, String?) shape(int p) {
        final r = rowOf(karaage, p);
        return (r.status, g2(r.grams!), r.gramSource);
      }

      expect(shape(7), ('confirmed', '45.47', 'discarded'));
      expect(shape(8), ('confirmed', '48.38', 'discarded'));
      expect([
        for (final p in const [7, 8])
          gramBasisFor(db, lines[p], rowOf(karaage, p), recipe: karaage),
      ], bases);
      // The GET derives a decided row at read ([derivedFor], RULE A).
      Future<List<(Object?, String, Object?)>> shown() async => [
        for (final item
            in (await matchesBody(db, provider, karaage))['items']! as List)
          if ((item as Map<String, Object?>)['position'] case 7 || 8)
            (
              (item['match']! as Map)['status'],
              g2((item['match']! as Map)['grams']! as double),
              (item['match']! as Map)['gram_basis'],
            ),
      ];
      expect(await shown(), [
        ('confirmed', '45.47', bases[0]),
        ('confirmed', '48.38', bases[1]),
      ]);
      final after = db.nutritionFor(karaage.id)!;
      expect(after.status, 'complete');
      expect(
        after.caloriesPerServing!.toStringAsFixed(2),
        before.caloriesPerServing!.toStringAsFixed(2),
      );
      // The coated food's typed grams move the CONFIRMED rows too.
      await applyMatchOverride(db, provider, karaage, 6, {
        'raw': lines[6].raw,
        'grams': 340.2,
      });
      final coat = g2(340.2 * 6.10 / 100 / cho(karaage, 7));
      final oil = g2(340.2 * 7.11 / 100);
      expect(shape(7), ('confirmed', coat, 'discarded'));
      expect(shape(8), ('confirmed', oil, 'discarded'));
      expect([for (final (_, g, _) in await shown()) g], [coat, oil]);
      expect(await matchAndCompute(db, provider, karaage), isNull);
      expect(shape(7), ('confirmed', coat, 'discarded'));
      expect(shape(8), ('confirmed', oil, 'discarded'));
    });

    test('the cap: an oil counts at most its line less its kept part (a '
        "STATED synthesized input — no corpus fry binds it: karaage's "
        'quart of frying oil written as 3 tablespoons)', () async {
      final corpus = loadCorpusRecipe(
        '0527-karaage-japanese-fried-chicken-thighs.yaml',
      );
      const small = '3 tablespoons vegetable oil for frying';
      final parsed = parseIngredientLine(small);
      final edited = corpus.copyWith(
        ingredients: [
          for (final group in corpus.ingredients)
            group.copyWith(
              items: [
                for (final item in group.items)
                  item.raw == '1 quart vegetable oil for frying'
                      ? IngredientLine(
                          raw: small,
                          item: parsed.item,
                          amounts: parsed.amounts,
                        )
                      : item,
              ],
            ),
        ],
      );
      db.upsertRecipe(edited, sourceSlug: _source, contentHash: edited.id);
      final stored = db.recipeByIdOrSlug(edited.id)!.recipe;
      expect(await matchAndCompute(db, provider, stored), isNull);
      final oil = rowOf(stored, 8);
      expect(oil.raw, small);
      // 680.39 × 7.11 % = 48.38 g would be absorbed; the line is 42 g.
      expect(gramsOf(stored, 6) * 7.11 / 100, greaterThan(oil.grams!));
      expect(g2(oil.grams!), g2(wholeOf(stored, 8)));
      expect(oil.gramSource, 'discarded');
    });
  });
}
