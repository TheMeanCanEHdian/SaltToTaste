// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v66 (batch M67 — fried doughs; matcherVersion 65; prep49
// design_v2 §2 M67, the owner's Q9 (A2) and Q10 (a), decided 2026-10-09
// under the standing authorization; Q7's one-way door accepted; zero
// requests; reach pre-Q18 — the sheet read is a step read): A2 a fried
// dough the steps roll to a sheet and cut counts only the cut share — one
// step printing the sheet ("10 by 13-inch rectangle"), the count ("cut 12
// rounds") and the round cutter ("3-inch round cutter"): s = 12 × π × 1.5²
// / 130 = 65.25 % (engine `_cutShareOf`) — each dough line at round2(s ×
// its WHOLE line), `discarded`, the uptake on the cut grams; B a cake dough
// (struffoli) takes 14.15 %, P3's carbohydrate balance on SR 174990
// "Doughnuts, cake-type, plain (includes unsugared, old-fashioned)", the one
// input FNDDS 2708063 lists (23.32 % on 2708024's fritter batter before).
// Every row value is the fresh compute of the WHOLE recipe (sections first)
// over recorded real FDC answers (FixtureProvider; one search added
// --from-db from snapshot 25, JSON-equal, 0 existing entries changed:
// "doughnut cake type", 174990's hit, read by the B pin), equal to the v66
// replay of snapshot 25 (rp43, fix66 r_B) on every pinned field and, on
// every row M67 must not move, to the v65 rows; never the network.
// Synthesized, STATED (no corpus recipe holds them): the yeasted-doughnuts
// copies whose step 3 reads "cut rounds" (no count) and "cut 20 rounds" (s
// = 1.087 ≥ 1) — A2's two negatives.

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

const _doughnuts = '1105-yeasted-doughnuts.yaml';
const _struffoli = '1163-struffoli-neapolitan-honey-balls.yaml';

/// The dough rows' basis (A2).
const _cutBasis =
    "discarded in cooking — only the cut dough counted · approximation (the cut share 65.25 %: 12 × 3-inch rounds from the steps' 10 by 13-inch sheet; the remaining dough, cut only \"if desired\", not counted)";

/// The 9 rows M67 moves (fix66 r_B vs the v65 rows): A2 yeasted-doughnuts
/// |0–|6 (the dough at the cut share) and |7 (the oil on the cut dough); B
/// struffoli|7.
const List<_Row> _reach = [
  (
    '1105-yeasted-doughnuts.yaml',
    0,
    '4½ cups (22½ ounces) all-purpose flour',
    789890,
    '0.950000',
    '416.20',
    '1523.29',
    'auto',
    null,
    "discarded in cooking — only the cut dough counted · approximation (the cut share 65.25 %: 12 × 3-inch rounds from the steps' 10 by 13-inch sheet; the remaining dough, cut only \"if desired\", not counted)",
  ),
  (
    '1105-yeasted-doughnuts.yaml',
    1,
    '½ cup (3½ ounces) granulated sugar',
    746784,
    '1.000000',
    '64.74',
    '249.25',
    'auto',
    null,
    "discarded in cooking — only the cut dough counted · approximation (the cut share 65.25 %: 12 × 3-inch rounds from the steps' 10 by 13-inch sheet; the remaining dough, cut only \"if desired\", not counted)",
  ),
  (
    '1105-yeasted-doughnuts.yaml',
    2,
    '1 teaspoon instant or rapid-rise yeast',
    2710005,
    '0.565000',
    '2.06',
    '6.70',
    'auto',
    null,
    "discarded in cooking — only the cut dough counted · approximation (the cut share 65.25 %: 12 × 3-inch rounds from the steps' 10 by 13-inch sheet; the remaining dough, cut only \"if desired\", not counted)",
  ),
  (
    '1105-yeasted-doughnuts.yaml',
    3,
    '1½ cups milk',
    2705385,
    '0.910000',
    '238.81',
    '145.67',
    'auto',
    null,
    "discarded in cooking — only the cut dough counted · approximation (the cut share 65.25 %: 12 × 3-inch rounds from the steps' 10 by 13-inch sheet; the remaining dough, cut only \"if desired\", not counted)",
  ),
  (
    '1105-yeasted-doughnuts.yaml',
    4,
    '1 large egg',
    748967,
    '0.920000',
    '32.62',
    '48.28',
    'auto',
    null,
    "discarded in cooking — only the cut dough counted · approximation (the cut share 65.25 %: 12 × 3-inch rounds from the steps' 10 by 13-inch sheet; the remaining dough, cut only \"if desired\", not counted)",
  ),
  (
    '1105-yeasted-doughnuts.yaml',
    5,
    '1½ teaspoons table salt',
    173468,
    '1.000000',
    '5.89',
    '0.00',
    'auto',
    null,
    "discarded in cooking — only the cut dough counted · approximation (the cut share 65.25 %: 12 × 3-inch rounds from the steps' 10 by 13-inch sheet; the remaining dough, cut only \"if desired\", not counted)",
  ),
  (
    '1105-yeasted-doughnuts.yaml',
    6,
    '8 tablespoons unsalted butter, cut into ½-inch pieces and softened',
    173430,
    '1.000000',
    '74.02',
    '530.72',
    'auto',
    null,
    "discarded in cooking — only the cut dough counted · approximation (the cut share 65.25 %: 12 × 3-inch rounds from the steps' 10 by 13-inch sheet; the remaining dough, cut only \"if desired\", not counted)",
  ),
  (
    '1105-yeasted-doughnuts.yaml',
    7,
    '2 quarts vegetable oil for frying',
    2710180,
    '0.923333',
    '139.50',
    '1255.50',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 16.72 % of the raw doughnut dough's weight — derived from USDA SR Legacy 172758 \"Doughnuts, yeast-leavened, glazed, enriched (includes honey buns)\")",
  ),
  (
    '1163-struffoli-neapolitan-honey-balls.yaml',
    7,
    '2 quarts vegetable oil for frying',
    2710180,
    '0.923333',
    '78.16',
    '703.44',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 14.15 % of the raw struffoli dough's weight — derived from USDA SR Legacy 174990 \"Doughnuts, cake-type, plain (includes unsugared, old-fashioned)\" by its carbohydrate (no record for struffoli dough; read as a cake doughnut; by its protein 30.62 %; FNDDS 2708024's fritter batter reads 23.32 %))",
  ),
];

/// The rows M67 must not move (each equal to the v65 rows): the 39 other
/// uptake rows, the doughnut glaze |8–|10 and the struffoli rows but its oil.
const List<_Row> _negatives = [
  (
    '0042-almond-crusted-chicken-with-wilted-spinach-salad.yaml',
    7,
    '¾ cup plus 2 tablespoons vegetable oil',
    2710180,
    '0.923333',
    '69.66',
    '626.94',
    'auto',
    null,
    "discarded in cooking — only \"plus 2 tablespoons vegetable oil\" and the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  (
    '0053-crispy-thai-eggplant-salad.yaml',
    10,
    '2 cups vegetable oil',
    2710180,
    '0.923333',
    '40.82',
    '367.38',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw eggplant's weight — derived from USDA SR Legacy 170698 \"Fast foods, potato, french fried in vegetable oil\" (no record for eggplant; read as Fast foods, potato, french fried in vegetable oil))",
  ),
  (
    '0114-breaded-chicken-cutlets.yaml',
    5,
    '1 tablespoon plus ¾ cup vegetable oil',
    2710180,
    '0.923333',
    '55.66',
    '500.94',
    'auto',
    null,
    "discarded in cooking — only \"1 tablespoon\" and the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  (
    '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
    4,
    '½ cup vegetable oil',
    2710180,
    '0.923333',
    '53.02',
    '477.18',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  (
    '0116-chicken-schnitzel.yaml',
    7,
    '2 cups vegetable oil for frying',
    2710180,
    '0.923333',
    '53.02',
    '477.18',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  (
    '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
    12,
    '1 tablespoon plus ¾ cup vegetable oil',
    2710180,
    '0.923333',
    '55.66',
    '500.94',
    'auto',
    null,
    "discarded in cooking — only \"1 tablespoon\" and the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  (
    '0151-buffalo-wings.yaml',
    5,
    '1–2 quarts peanut oil, for frying',
    2710187,
    '0.990000',
    '44.97',
    '404.73',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.61 % of the raw chicken wings' weight — USDA FNDDS 2706065 recipe: 7 g oil per 105.96 g raw chicken wing)",
  ),
  (
    '0198-crispy-pan-fried-pork-chops.yaml',
    7,
    '⅔ cup vegetable oil',
    2710180,
    '0.923333',
    '53.02',
    '477.18',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw pork's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw))",
  ),
  (
    '0215-horseradish-crusted-beef-tenderloin.yaml',
    3,
    '1 cup plus 2 teaspoons vegetable oil',
    2710180,
    '0.923333',
    '38.09',
    '342.81',
    'auto',
    null,
    "discarded in cooking — only \"plus 2 teaspoons vegetable oil\", the 1 tablespoon the steps keep and the oil the fried food absorbs counted · approximation (frying oil absorbed: 10.9 % of the raw potatoes' weight — derived from USDA SR Legacy 19411 \"Snacks, potato chips, plain, salted\")",
  ),
  (
    '0233-pork-schnitzel-breaded-pork-cutlets.yaml',
    3,
    '2 cups plus 1 tablespoon vegetable oil',
    2710180,
    '0.923333',
    '51.87',
    '466.83',
    'auto',
    null,
    "discarded in cooking — only \"plus 1 tablespoon vegetable oil\" and the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw pork's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw))",
  ),
  (
    '0255-fish-and-chips.yaml',
    1,
    '3 quarts plus ¼ cup peanut oil or canola oil',
    2710187,
    '0.990000',
    '170.78',
    '1537.02',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted (\"plus ¼ cup peanut oil or canola oil\": the steps rinse it off) · approximation (frying oil absorbed: 15.38 % of the raw cod's weight — USDA FNDDS 2706244 recipe: 10 g oil per 65 g raw cod; 6.0 % of the raw potatoes' weight — derived from USDA SR Legacy 170698 \"Fast foods, potato, french fried in vegetable oil\")",
  ),
  (
    '0279-crispy-salt-and-pepper-shrimp.yaml',
    7,
    '4 cups vegetable oil',
    2710180,
    '0.923333',
    '64.06',
    '576.54',
    'auto',
    null,
    "discarded in cooking — only the part the recipe keeps and the oil the fried food absorbs counted · approximation (frying oil absorbed: 5.3 % of the raw shrimp's weight — derived from USDA SR Legacy 171982 \"Mollusks, squid, mixed species, cooked, fried\")",
  ),
  (
    '0287-easy-salmon-cakes.yaml',
    11,
    '½ cup vegetable oil',
    2710180,
    '0.923333',
    '37.87',
    '340.83',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw salmon's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast (no record for salmon; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw))",
  ),
  (
    '0288-maryland-crab-cakes.yaml',
    9,
    '¼ cup vegetable oil',
    2710180,
    '0.923333',
    '34.88',
    '313.92',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 7.69 % of the raw crab's weight — USDA FNDDS 2706549 recipe: 5 g oil per 65 g raw crab)",
  ),
  (
    '0304-chicken-fried-steaks.yaml',
    8,
    '4–5 cups peanut oil',
    2710187,
    '0.990000',
    '84.11',
    '756.99',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 9.89 % of the raw beef's weight — USDA FNDDS 2705842 recipe: 9 g oil per 90.99 g raw beef steak)",
  ),
  (
    '0316-classic-french-fries.yaml',
    1,
    '2 quarts peanut oil',
    2710187,
    '0.990000',
    '55.11',
    '495.99',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw potatoes' weight — derived from USDA SR Legacy 170698 \"Fast foods, potato, french fried in vegetable oil\")",
  ),
  (
    '0316-steak-fries.yaml',
    1,
    '2 quarts peanut oil',
    2710187,
    '0.990000',
    '68.04',
    '612.36',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw potatoes' weight — derived from USDA SR Legacy 170698 \"Fast foods, potato, french fried in vegetable oil\")",
  ),
  (
    '0317-easier-french-fries.yaml',
    1,
    '6 cups peanut oil',
    2710187,
    '0.990000',
    '68.04',
    '612.36',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw potatoes' weight — derived from USDA SR Legacy 170698 \"Fast foods, potato, french fried in vegetable oil\")",
  ),
  (
    '0318-thick-cut-sweet-potato-fries.yaml',
    4,
    '3 cups peanut oil',
    2710187,
    '0.990000',
    '65.32',
    '587.88',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw sweet potatoes' weight — derived from USDA SR Legacy 170698 \"Fast foods, potato, french fried in vegetable oil\" (no record for sweet potatoes; read as Fast foods, potato, french fried in vegetable oil))",
  ),
  (
    '0319-crunchy-kettle-potato-chips.yaml',
    0,
    '2 quarts vegetable oil, for frying',
    2710180,
    '0.923333',
    '49.44',
    '444.96',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 10.9 % of the raw potatoes' weight — derived from USDA SR Legacy 19411 \"Snacks, potato chips, plain, salted\")",
  ),
  (
    '0415-best-chicken-parmesan.yaml',
    19,
    '⅓ cup vegetable oil',
    2710180,
    '0.923333',
    '26.51',
    '238.59',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  (
    '0464-steak-frites.yaml',
    9,
    '3 quarts peanut oil',
    2710187,
    '0.990000',
    '68.04',
    '612.36',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw potatoes' weight — derived from USDA SR Legacy 170698 \"Fast foods, potato, french fried in vegetable oil\")",
  ),
  (
    '0491-spicy-mexican-shredded-pork-tostadas.yaml',
    10,
    '¾ cup vegetable oil',
    2710180,
    '0.923333',
    '41.81',
    '376.29',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 13.4 % of the raw corn tortillas' weight — derived from USDA SR Legacy 167525 \"Tostada shells, corn\")",
  ),
  (
    '0511-shrimp-tempura.yaml',
    0,
    '3 quarts peanut or vegetable oil',
    2710187,
    '0.673333',
    '104.64',
    '941.76',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 15.38 % of the raw shrimp's weight — USDA FNDDS 2706364 recipe: 10 g oil per 65 g raw shrimp)",
  ),
  (
    '0525-orange-flavored-chicken.yaml',
    16,
    '3 cups peanut or vegetable oil',
    2710187,
    '0.673333',
    '48.38',
    '435.42',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 7.11 % of the raw chicken thigh's weight — USDA FNDDS 2706047 recipe: 7 g oil per 98.39 g raw chicken thigh)",
  ),
  (
    '0526-dakgangjeong-korean-fried-chicken-wings.yaml',
    7,
    '2 quarts vegetable oil',
    2710180,
    '0.923333',
    '44.97',
    '404.73',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.61 % of the raw chicken wings' weight — USDA FNDDS 2706065 recipe: 7 g oil per 105.96 g raw chicken wing)",
  ),
  (
    '0527-karaage-japanese-fried-chicken-thighs.yaml',
    8,
    '1 quart vegetable oil for frying',
    2710180,
    '0.923333',
    '48.38',
    '435.42',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 7.11 % of the raw chicken thigh's weight — USDA FNDDS 2706047 recipe: 7 g oil per 98.39 g raw chicken thigh)",
  ),
  (
    '0536-crispy-orange-beef.yaml',
    8,
    '3 cups vegetable oil',
    2710180,
    '0.923333',
    '95.29',
    '857.61',
    'auto',
    null,
    "discarded in cooking — only the part the recipe keeps and the oil the fried food absorbs counted · approximation (frying oil absorbed: 9.89 % of the raw beef's weight — USDA FNDDS 2705842 recipe: 9 g oil per 90.99 g raw beef steak (no record for beef; read as Beef, steak, country fried))",
  ),
  (
    '0570-falafel.yaml',
    11,
    '2 quarts vegetable oil for frying',
    2710180,
    '0.923333',
    '85.55',
    '769.95',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 21.64 % of the raw falafel mix's weight — derived from USDA SR Legacy 172455 \"Falafel, home-prepared\")",
  ),
  (
    '0672-buffalo-cauliflower-bites.yaml',
    4,
    '1–2 quarts peanut or vegetable oil',
    2710187,
    '0.673333',
    '73.30',
    '659.70',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed — derived: 16.16 % of the raw cauliflower's weight — USDA FNDDS 2710042 recipe: 12 g oil per 39.58 g raw cauliflower, scaled to the recipe's batter (122.16 g of 229.20 g carbohydrate))",
  ),
  (
    '0690-patatas-bravas.yaml',
    12,
    '3 cups vegetable oil',
    2710180,
    '0.923333',
    '49.60',
    '446.40',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw potatoes' weight — derived from USDA SR Legacy 170698 \"Fast foods, potato, french fried in vegetable oil\")",
  ),
  (
    '0706-platanos-maduros-fried-sweet-plantains.yaml',
    0,
    '3 cups vegetable oil',
    2710180,
    '0.923333',
    '66.27',
    '596.43',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 5.5 % of the raw plantains' weight — derived from USDA SR Legacy 168200 \"Plantains, yellow, fried, Latino restaurant\")",
  ),
  (
    '1081-crispy-fish-sandwiches-with-tartar-sauce.yaml',
    11,
    '2 quarts peanut or vegetable oil for frying',
    2710187,
    '0.500000',
    '87.20',
    '784.80',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 15.38 % of the raw haddock's weight — USDA FNDDS 2706258 recipe: 10 g oil per 65 g raw haddock)",
  ),
  (
    '1084-rhode-islandstyle-fried-calamari.yaml',
    7,
    '2 quarts vegetable oil for frying',
    2710180,
    '0.923333',
    '24.04',
    '216.36',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 5.3 % of the raw squid's weight — derived from USDA SR Legacy 171982 \"Mollusks, squid, mixed species, cooked, fried\")",
  ),
  (
    '1105-yeasted-doughnuts.yaml',
    8,
    '3¼ cups (13 ounces) confectioners’ sugar',
    169656,
    '1.000000',
    '368.54',
    '1433.63',
    'auto',
    null,
    'from 13 ounce',
  ),
  (
    '1105-yeasted-doughnuts.yaml',
    9,
    '½ cup hot water',
    null,
    '1.000000',
    null,
    null,
    'confirmed',
    null,
    null,
  ),
  (
    '1105-yeasted-doughnuts.yaml',
    10,
    'Pinch table salt',
    173468,
    '1.000000',
    '0.40',
    '0.00',
    'auto',
    null,
    'pinch · USDA portion',
  ),
  (
    '1123-pastelon-puerto-rican-sweet-plantain-and-picadillo-casserole.yaml',
    7,
    '¾ cup vegetable oil for frying',
    2710180,
    '0.923333',
    '81.08',
    '729.72',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 5.5 % of the raw plantains' weight — derived from USDA SR Legacy 168200 \"Plantains, yellow, fried, Latino restaurant\")",
  ),
  (
    '1133-chicken-francese.yaml',
    8,
    '⅓ cup extra-virgin olive oil for frying',
    748608,
    '1.000000',
    '26.13',
    '220.35',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  (
    '1133-chicken-francese.yaml',
    9,
    '⅓ cup vegetable oil for frying',
    2710180,
    '0.923333',
    '26.89',
    '242.01',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  (
    '1137-pakoras-south-asian-spiced-vegetable-fritters.yaml',
    14,
    '2 quarts canola oil for frying',
    172360,
    '0.888889',
    '40.72',
    '359.96',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 8.43 % of the raw pakora batter's weight — USDA FNDDS 2710066 recipe: 21 g oil per 249.18 g raw pakora batter)",
  ),
  (
    '1163-struffoli-neapolitan-honey-balls.yaml',
    0,
    '2 cups (10 ounces) all-purpose flour',
    789890,
    '0.950000',
    '283.50',
    '1037.59',
    'auto',
    null,
    'from 10 ounce',
  ),
  (
    '1163-struffoli-neapolitan-honey-balls.yaml',
    1,
    '¼ cup (1¾ ounces) sugar',
    746784,
    '0.950000',
    '49.61',
    '191.00',
    'auto',
    null,
    'from 1 3/4 ounce',
  ),
  (
    '1163-struffoli-neapolitan-honey-balls.yaml',
    2,
    '½ teaspoon table salt',
    173468,
    '1.000000',
    '3.01',
    '0.00',
    'auto',
    null,
    '1/2 teaspoon ≈ 2 mL',
  ),
  (
    '1163-struffoli-neapolitan-honey-balls.yaml',
    3,
    '¼ teaspoon baking powder',
    172804,
    '0.850000',
    '1.13',
    '0.58',
    'auto',
    null,
    '1/4 teaspoon ≈ 1 mL',
  ),
  (
    '1163-struffoli-neapolitan-honey-balls.yaml',
    4,
    '3 large eggs, lightly beaten',
    748967,
    '0.920000',
    '150.00',
    '222.00',
    'auto',
    null,
    '3 × 50 g each',
  ),
  (
    '1163-struffoli-neapolitan-honey-balls.yaml',
    5,
    '4 tablespoons unsalted butter, melted and cooled slightly',
    173430,
    '1.000000',
    '56.72',
    '406.70',
    'auto',
    null,
    '4 tablespoon ≈ 59 mL',
  ),
  (
    '1163-struffoli-neapolitan-honey-balls.yaml',
    6,
    '2 teaspoons vanilla extract',
    173471,
    '1.000000',
    '8.40',
    '24.19',
    'auto',
    null,
    '2 teaspoon · USDA portion',
  ),
  (
    '1163-struffoli-neapolitan-honey-balls.yaml',
    8,
    '1 cup honey',
    169640,
    '1.000000',
    '335.95',
    '1021.30',
    'auto',
    null,
    '1 cup ≈ 237 mL',
  ),
  (
    '1163-struffoli-neapolitan-honey-balls.yaml',
    9,
    '2 tablespoons multicolored nonpareils, plus extra for garnish',
    746784,
    '1.000000',
    '23.75',
    '91.44',
    'auto',
    null,
    '2 tablespoon · USDA portion · approximation (counted as Sugars, granulated)',
  ),
  (
    '1163-struffoli-neapolitan-honey-balls.yaml',
    10,
    '¼ cup sliced almonds, toasted (optional)',
    170567,
    '0.900000',
    '23.00',
    '133.17',
    'auto',
    null,
    '1/4 cup · USDA portion',
  ),
  (
    '1163-struffoli-neapolitan-honey-balls.yaml',
    11,
    '2 tablespoons candied orange peel, chopped fine (optional)',
    169103,
    '0.636667',
    '12.00',
    '11.64',
    'auto',
    null,
    '2 tablespoon · USDA portion',
  ),
  (
    '1163-struffoli-neapolitan-honey-balls.yaml',
    12,
    '8 candied cherries (optional)',
    167563,
    '0.000000',
    null,
    null,
    'auto',
    null,
    null,
  ),
  (
    '1194-lumpiang-shanghai-with-seasoned-vinegar.yaml',
    17,
    '1½ quarts vegetable oil for frying',
    2710180,
    '0.923333',
    '99.34',
    '894.06',
    'auto',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 7.62 % of the raw lumpia's weight — USDA FNDDS 2708702 recipe: 8 g oil per 104.99 g raw egg roll (no record for lumpia; read as Egg roll, with beef and/or pork))",
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
  test('the matcher version carries the batch (update the literal with a '
      'bump)', () {
    // RE-PIN (M68 batch, v67): matcherVersion 66 (was 65).
    // RE-PIN (M69 batch, v68): matcherVersion 67 (was 66).
    // RE-PIN (M70 batch, v69): matcherVersion 68 (was 67).
    expect(matcherVersion, 68);
  });

  group('matcher v66 (batch M67)', skip: skipIfNoCorpus, () {
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

    /// The doughnuts with step 3's "cut 12 rounds" read [cut].
    Recipe doughnutsCutting(String cut) {
      final corpus = loadCorpusRecipe(_doughnuts);
      expect(
        corpus.steps.where((s) => s.text.contains('cut 12 rounds')),
        hasLength(1),
      );
      return corpus.copyWith(
        steps: [
          for (final s in corpus.steps)
            s.copyWith(text: s.text.replaceAll('cut 12 rounds', cut)),
        ],
      );
    }

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v66-');
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

    /// [file]'s line [p]: its whole grams and its record.
    (double, FdcFood) whole(String file, int p) {
      final recipe = recipes[file]!;
      final line = nutritionLines(recipe)[p];
      final food = knownFood(db, rowIn(recipe, p).fdcId!, line: line)!;
      return (lineGrams(db, line, food, recipe: recipe)!.grams, food);
    }

    test('M67 moves exactly its 9 rows (design_v2 §2 M67): the 7 dough rows '
        '`discarded` at the cut share, the oil on the cut dough, the '
        "struffoli's oil at 14.15 %", () {
      expect(_reach, hasLength(9));
      expectRows(_reach);
      for (var p = 0; p <= 7; p++) {
        expect(rowIn(recipes[_doughnuts]!, p).gramSource, 'discarded');
      }
    });

    test('the rows M67 must not move equal v65 (54 rows: the 39 other '
        'uptake rows — pakoras|14 40.72, lumpiang-shanghai|17 99.34, '
        'falafel|11 85.55 among them — the doughnut glaze |8 368.54 with |9 '
        '|10, and struffoli |0–|6 |8–|12)', () {
      expect(_negatives, hasLength(54));
      expect(
        _negatives.where(
          (r) => r.$10?.contains('frying oil absorbed') ?? false,
        ),
        hasLength(39),
      );
      expectRows(_negatives);
      for (final (file, position, grams) in [
        (
          '1137-pakoras-south-asian-spiced-vegetable-fritters.yaml',
          14,
          '40.72',
        ),
        ('1194-lumpiang-shanghai-with-seasoned-vinegar.yaml', 17, '99.34'),
        ('0570-falafel.yaml', 11, '85.55'),
        (_doughnuts, 8, '368.54'),
      ]) {
        expect(
          rowIn(recipes[file]!, position).grams?.toStringAsFixed(2),
          grams,
          reason: '$file|$position',
        );
      }
    });

    test('A2 by hand: s = 12 × π × (3 / 2)² / (10 × 13) = 0.652485; each '
        'dough row is round2(s × its WHOLE line) — |0 22½ oz × 28.3495 = '
        "637.86375 g → s × 637.86375 = 416.1963 → 416.20 (design §2's "
        '416.19 applied s to the stored 2-dp 637.86: 416.1938) — and the oil '
        '16.72 % of their sum 834.34 = 139.50', () {
      const s = 12 * pi * 1.5 * 1.5 / (10 * 13);
      expect(s.toStringAsFixed(6), '0.652485');
      final recipe = recipes[_doughnuts]!;
      expect(whole(_doughnuts, 0).$1.toStringAsFixed(5), '637.86375');
      expect(g2(whole(_doughnuts, 0).$1), '637.86');
      // The 0.01 against §2 is the product's operand, not a rounding: s on
      // the whole line reads 416.1963, s on the stored 2-dp grams 416.1938.
      expect((s * whole(_doughnuts, 0).$1).toStringAsFixed(4), '416.1963');
      expect((s * 637.86).toStringAsFixed(4), '416.1938');
      expect(rowIn(recipe, 0).grams?.toStringAsFixed(2), '416.20');
      var sum = 0.0;
      for (var p = 0; p <= 6; p++) {
        final cut = double.parse(g2(s * whole(_doughnuts, p).$1));
        expect(rowIn(recipe, p).grams, cut, reason: '|$p');
        sum += cut;
      }
      expect(g2(sum), '834.34');
      expect(g2(16.72 * sum / 100), '139.50');
      expect(rowIn(recipe, 7).grams, 139.5);
    });

    test('B by hand: P3 balance on SR 174990 (its recorded hit under '
        '"doughnut cake type") with the carbohydrate tracer against the '
        'struffoli dough |0–|6 — D = 47.1 / 0.491276 = 95.873, O = 24.9 − D '
        '× 0.118227 = 13.565, u = 14.1492 % (the protein tracer 30.62 %); '
        '|7 = 14.15 × 552.37 / 100 = 78.16', () async {
      final record = (await provider.search(
        'doughnut cake type',
      )).singleWhere((h) => h.fdcId == 174990);
      expect(
        record.description,
        'Doughnuts, cake-type, plain (includes unsugared, old-fashioned)',
      );
      final n = record.nutrientsPer100g!;
      expect((n['203'], n['204'], n['205']), (5.31, 24.9, 47.1));
      final recipe = recipes[_struffoli]!;
      // The dough on the rows as the replay prints them (2 dp — the
      // planner's and the critic's read), then as the engine stores them.
      (double, double, double, double, double) balance({
        required bool printed,
      }) {
        var (mass, p, f, c) = (0.0, 0.0, 0.0, 0.0);
        for (var i = 0; i <= 6; i++) {
          final row = rowIn(recipe, i);
          final grams = printed ? double.parse(g2(row.grams!)) : row.grams!;
          final food = knownFood(
            db,
            row.fdcId!,
            line: nutritionLines(recipe)[i],
          )!.nutrientsPer100g;
          mass += grams;
          p += grams * (food['203'] ?? 0) / 100;
          f += grams * (food['204'] ?? 0) / 100;
          c += grams * (food['205'] ?? 0) / 100;
        }
        final d = 47.1 / (c / mass);
        final o = 24.9 - d * f / mass;
        final byProtein = 5.31 / (p / mass);
        return (
          mass,
          d,
          o,
          100 * o / d,
          100 * (24.9 - byProtein * f / mass) / byProtein,
        );
      }

      final (mass, d, o, u, protein) = balance(printed: true);
      expect(g2(mass), '552.37');
      expect(
        (d.toStringAsFixed(3), o.toStringAsFixed(3), u.toStringAsFixed(4)),
        ('95.873', '13.565', '14.1492'),
      );
      // The flag's "by its protein 30.62 %" is this read (30.6154).
      expect(protein.toStringAsFixed(4), '30.6154');
      // On the grams as the engine stores them (unrounded): the same 14.15,
      // the protein tracer 30.6147.
      final (_, _, _, uStored, proteinStored) = balance(printed: false);
      expect(
        (uStored.toStringAsFixed(4), proteinStored.toStringAsFixed(4)),
        ('14.1488', '30.6147'),
      );
      expect(g2(14.15 * mass / 100), '78.16');
      expect(rowIn(recipe, 7).grams, 78.16);
    });

    test("A2 reads the recipe's own steps: 1105's Jelly and Boston Cream "
        'variations print the same sheet, count and cutter but are never '
        'computed (CP3) — no section, 11 main rows', () {
      final recipe = recipes[_doughnuts]!;
      expect(
        [
          for (final v in recipe.subsections)
            if ((v.steps ?? const []).any(
              (s) =>
                  s.text.contains('10 by 13-inch rectangle') &&
                  s.text.contains('cut 12 rounds') &&
                  s.text.contains('3-inch round cutter'),
            ))
              (v.title, v.kind),
        ],
        [
          ('Jelly Doughnuts', 'variation'),
          ('Boston Cream Doughnuts', 'variation'),
        ],
      );
      expect(sectionChildKeysOf(db, recipe, ResolverMemo(db)), isEmpty);
      expect(db.ingredientMatchesFor(recipe.id), hasLength(11));
    });

    test('A2 needs the count and s < 1 — STATED synthesized: step 3 reading '
        '"cut rounds" (no count) or "cut 20 rounds" (s = 20 × π × 1.5² / 130 '
        '= 1.087) counts the whole dough and its uptake, 213.80', () async {
      expect((20 * pi * 1.5 * 1.5 / 130).toStringAsFixed(3), '1.087');
      for (final (cut, id) in [
        ('cut rounds', 'no-count'),
        ('cut 20 rounds', 'twenty'),
      ]) {
        final stored = await variant(doughnutsCutting(cut), id);
        expect(
          (
            rowIn(stored, 0).grams?.toStringAsFixed(2),
            rowIn(stored, 0).gramSource,
          ),
          ('637.86', 'weight'),
          reason: id,
        );
        expect(rowIn(stored, 7).grams?.toStringAsFixed(2), '213.80');
        expect(basisIn(stored, 0), 'from 22 1/2 ounce', reason: id);
      }
    });

    test('per serving: the two recipes move kcal only (statuses kept)', () {
      (String, String) of(String file) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        return (n.status, n.caloriesPerServing!.toStringAsFixed(2));
      }

      expect(of(_doughnuts), ('complete', '432.75')); // v65 599.61
      // The replay's 640.51 (design §2 ≈ 640.50); v65 716.48 (cherries).
      expect(of(_struffoli), ('partial', '640.51'));
    });

    test('a second recompute writes nothing (the dough rows read their '
        'WHOLE lines, never the cut grams the first one stored)', () {
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

    // Last: it writes person decisions (on a computed copy).
    test("Q7 (the owner's one-way door, accepted): a person's CONFIRM of "
        "yeasted-doughnuts|0 through the real PUT reads the plan's cut share "
        '— 416.20 g `discarded` — and a recompute keeps it; with every dough '
        'and oil row confirmed the matches GET plans M52 once and shows what '
        'the per-row derivation shows, and a compute plans it at most twice '
        "and writes what the PUTs wrote — from v65's whole rows too (the "
        'memo oracle at the mix positions)', () async {
      final copy = await variant(loadCorpusRecipe(_doughnuts), 'confirm');
      Future<void> confirm(int position) => applyMatchOverride(
        db,
        provider,
        copy,
        position,
        {'raw': nutritionLines(copy)[position].raw, 'confirmed': true},
      );
      await confirm(0);
      final flour = rowIn(copy, 0);
      expect(
        (flour.status, flour.grams, flour.gramSource, flour.hold),
        ('confirmed', 416.2, 'discarded', null),
      );
      expect(basisIn(copy, 0), _cutBasis);
      expect(recomputeTotals(db, copy), isTrue);
      expect(sameMatchRow(rowIn(copy, 0), flour), isTrue);
      for (var p = 1; p <= 7; p++) {
        await confirm(p);
      }
      m52PlanRuns = 0;
      final items =
          (await matchesBody(db, provider, copy))['items']!
              as List<Map<String, Object?>>;
      expect(m52PlanRuns, 1);
      for (var p = 0; p <= 7; p++) {
        final line = nutritionLines(copy)[p];
        final row = rowIn(copy, p);
        expect(row.status, 'confirmed');
        final d = await derivedFor(db, cacheOnly, copy, p, line, row);
        final shown = withDerived(row, d.row);
        final match = items[p]['match']! as Map<String, Object?>;
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
            gramBasisFor(db, line, shown, recipe: copy),
          ),
          reason: '|$p',
        );
      }
      final asPut = {
        for (final r in db.ingredientMatchesFor(copy.id)) r.position: r,
      };
      expect(
        [for (var p = 0; p <= 7; p++) asPut[p]!.grams],
        [416.2, 64.74, 2.06, 238.81, 32.62, 5.89, 74.02, 139.5],
      );
      Future<void> computesAsPut(String why) async {
        m52PlanRuns = 0;
        expect(await matchAndCompute(db, provider, copy), isNull);
        expect(m52PlanRuns, lessThanOrEqualTo(2), reason: why);
        for (var p = 0; p <= 7; p++) {
          final row = rowIn(copy, p);
          final reason = '$why |$p';
          expect(sameMatchRow(row, asPut[p]), isTrue, reason: reason);
          final d = await derivedFor(
            db,
            cacheOnly,
            copy,
            p,
            nutritionLines(copy)[p],
            row,
          );
          expect(
            sameMatchRow(withDerived(row, d.row), row),
            isTrue,
            reason: reason,
          );
        }
      }

      await computesAsPut('compute');
      // As v65 left the confirmed dough rows (each its whole line), the
      // first compute after the deploy: every derivation rewrites its row.
      for (var p = 0; p <= 6; p++) {
        final line = nutritionLines(copy)[p];
        final row = rowIn(copy, p);
        final whole = lineGrams(
          db,
          line,
          knownFood(db, row.fdcId!, line: line),
          recipe: copy,
        )!;
        db.upsertIngredientMatch(
          row.copyWith(grams: whole.grams, gramSource: whole.source.name),
        );
        expect(sameMatchRow(rowIn(copy, p), row), isFalse);
      }
      await computesAsPut('after the deploy');
    });
  });
}
