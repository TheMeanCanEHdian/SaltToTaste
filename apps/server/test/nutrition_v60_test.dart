// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v60 (batch M61, fried doughs, fritters, rolls and falafel take an
// uptake; matcherVersion 59; prep48 design_v2 §2 M61, §1 Q12, §6 F16; the
// owner's rulings R-a … R-e, decided 2026-10-08 under the 2026-10-07
// standing authorization; zero requests; step-reading, pre-Q18): a frying
// oil no counted line is the fried food of counts the uptake of the PRODUCT
// a frying sentence names (engine `_friedProductOf`) on its raw mix — the
// counted rows of the oil line's ingredient group before it. Every row
// value is the fresh compute of the WHOLE recipe over recorded real FDC
// answers (FixtureProvider; 10 searches and 2 foods added --from-db from
// snapshot 24, JSON-equal, 0 existing entries changed), equal to the v60
// replay of snapshot 24 (rp43, fix60 r1) on every pinned row and to the
// unchanged v59 tree's compute on every row M61 must not move; never the
// network. Synthesized, STATED (no corpus recipe holds them): the step
// words and the line the three gate pins and the stand-in flag pin below
// take out of real recipes, and the confirmed-GET pin's edit of pakoras'
// oil line to "3 quarts" (a carried row, closer 3).

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

/// (file, section title or null, position, raw, fdc id, confidence, grams,
/// kcal (null on a held row: it counts nothing), hold, basis) — an `auto`
/// row of the fresh compute.
typedef _Row = (
  String,
  String?,
  int,
  String,
  int?,
  String,
  String?,
  String?,
  String?,
  String?,
);

const _pakoras = '1137-pakoras-south-asian-spiced-vegetable-fritters.yaml';
const _lumpia = '1194-lumpiang-shanghai-with-seasoned-vinegar.yaml';
const _falafel = '0570-falafel.yaml';
const _doughnuts = '1105-yeasted-doughnuts.yaml';
const _struffoli = '1163-struffoli-neapolitan-honey-balls.yaml';
const _tempeh = '1193-crispy-tempeh-with-sambal-sauce.yaml';
const _confit = '1077-turkey-thigh-confit-with-citrus-mustard-sauce.yaml';
const _eggplant = '0053-crispy-thai-eggplant-salad.yaml';
const _cornFritters = '0674-corn-fritters.yaml';
const _southernFritters = '0675-southern-corn-fritters.yaml';

/// M61's reach (design_v2 §2 M61, plan_figures §5: exactly these 5 rows,
/// +5,107.46 kcal per batch, each 0 g before): R-a pakoras on FNDDS 2710066
/// by its formula (8.43 %); R-b the lumpia on 2708702, a stand-in (7.62 %);
/// R-d the yeast dough DERIVED from SR 172758 with the protein tracer
/// (16.72 %); R-e falafel DERIVED from SR 172455 with the carbohydrate
/// tracer (21.64 %); R-c struffoli on 2708024 "Fritter, plain", a stand-in
/// (23.32 %, Q12 iii). Grams = u × the raw mix / 100.
const List<_Row> _reach = [
  (
    _pakoras,
    null,
    14,
    '2 quarts canola oil for frying',
    172360,
    '0.888889',
    '40.72',
    '359.96',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 8.43 % of the raw pakora batter's weight — USDA FNDDS 2710066 recipe: 21 g oil per 249.18 g raw pakora batter)",
  ),
  (
    _lumpia,
    null,
    17,
    '1½ quarts vegetable oil for frying',
    2710180,
    '0.923333',
    '99.34',
    '894.06',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 7.62 % of the raw lumpia's weight — USDA FNDDS 2708702 recipe: 8 g oil per 104.99 g raw egg roll (no record for lumpia; read as Egg roll, with beef and/or pork))",
  ),
  (
    _falafel,
    null,
    11,
    '2 quarts vegetable oil for frying',
    2710180,
    '0.923333',
    '85.55',
    '769.95',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 21.64 % of the raw falafel mix\'s weight — derived from USDA SR Legacy 172455 "Falafel, home-prepared")',
  ),
  (
    _doughnuts,
    null,
    7,
    '2 quarts vegetable oil for frying',
    2710180,
    '0.923333',
    '213.80',
    '1924.20',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 16.72 % of the raw doughnut dough\'s weight — derived from USDA SR Legacy 172758 "Doughnuts, yeast-leavened, glazed, enriched (includes honey buns)")',
  ),
  (
    _struffoli,
    null,
    7,
    '2 quarts vegetable oil for frying',
    2710180,
    '0.923333',
    '128.81',
    '1159.29',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 23.32 % of the raw struffoli dough's weight — USDA FNDDS 2708024 recipe: 80 g oil per 343 g raw fritter batter (no record for struffoli dough; read as Fritter, plain))",
  ),
];

/// Rows M61 must not move (each equal to the v59 compute): tempeh is no
/// product word (its kept part stays); duck fat for confit fries nothing; the
/// Fried Shallots section's oil fries shallots, no product; both corn
/// fritters' oils are HELD `ambiguous_medium` (M61 reads only unheld
/// `discarded` frying oils).
const List<_Row> _negatives = [
  (
    _tempeh,
    null,
    5,
    '1 cup vegetable oil',
    2710180,
    '0.923333',
    '28.00',
    '252.00',
    null,
    'discarded in cooking — only the part the recipe keeps counted',
  ),
  (
    _confit,
    null,
    6,
    '6 cups duck fat, chicken fat, or vegetable oil for confit',
    173572,
    '1.000000',
    '0.00',
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximation (counted as Fat, goose)',
  ),
  // RE-PIN (M64 batch, v63, Q12 (a)): M61 still reads no product here,
  // but the section's yield prints the oil out — the ¼ cup kept, 56.00 g
  // (was 0.00).
  (
    _eggplant,
    'Fried Shallots and Fried Shallot Oil',
    1,
    '2 cups vegetable oil',
    2710180,
    '0.923333',
    '56.00',
    '504.00',
    null,
    "discarded in cooking — only the part the recipe keeps counted · approximate (the difference of the yield's printed volumes: 2 cups in, about 1¾ cups out as shallot oil — the ¼ cup the shallots, the pan and the towel keep counted as eaten)",
  ),
  (
    _cornFritters,
    null,
    8,
    '¼ cup vegetable oil, plus more as needed',
    2710180,
    '0.923333',
    null,
    null,
    'ambiguous_medium',
    null,
  ),
  (
    _southernFritters,
    null,
    1,
    '1 teaspoon plus ½ cup vegetable oil',
    2710180,
    '0.923333',
    '4.53',
    null,
    'ambiguous_medium',
    'discarded in cooking — only "1 teaspoon" counted',
  ),
];

/// The 36 rows that already carry a fried food's uptake (v59: "frying oil
/// absorbed"; none in M61's five recipes) — each equal to the v59 compute,
/// row by row (crispy-thai-eggplant-salad|10 first).
const List<_Row> _uptakes = [
  (
    _eggplant,
    null,
    10,
    '2 cups vegetable oil',
    2710180,
    '0.923333',
    '40.82',
    '367.38',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw eggplant\'s weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil" (no record for eggplant; read as Fast foods, potato, french fried in vegetable oil))',
  ),
  (
    '0042-almond-crusted-chicken-with-wilted-spinach-salad.yaml',
    null,
    7,
    '¾ cup plus 2 tablespoons vegetable oil',
    2710180,
    '0.923333',
    '69.66',
    '626.94',
    null,
    'discarded in cooking — only "plus 2 tablespoons vegetable oil" and the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast\'s weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)',
  ),
  (
    '0114-breaded-chicken-cutlets.yaml',
    null,
    5,
    '1 tablespoon plus ¾ cup vegetable oil',
    2710180,
    '0.923333',
    '55.66',
    '500.94',
    null,
    'discarded in cooking — only "1 tablespoon" and the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast\'s weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)',
  ),
  (
    '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
    null,
    4,
    '½ cup vegetable oil',
    2710180,
    '0.923333',
    '53.02',
    '477.18',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  (
    '0116-chicken-schnitzel.yaml',
    null,
    7,
    '2 cups vegetable oil for frying',
    2710180,
    '0.923333',
    '53.02',
    '477.18',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  (
    '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
    null,
    12,
    '1 tablespoon plus ¾ cup vegetable oil',
    2710180,
    '0.923333',
    '55.66',
    '500.94',
    null,
    'discarded in cooking — only "1 tablespoon" and the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast\'s weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)',
  ),
  (
    '0151-buffalo-wings.yaml',
    null,
    5,
    '1–2 quarts peanut oil, for frying',
    2710187,
    '0.990000',
    '44.97',
    '404.73',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.61 % of the raw chicken wings' weight — USDA FNDDS 2706065 recipe: 7 g oil per 105.96 g raw chicken wing)",
  ),
  (
    '0198-crispy-pan-fried-pork-chops.yaml',
    null,
    7,
    '⅔ cup vegetable oil',
    2710180,
    '0.923333',
    '53.02',
    '477.18',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw pork's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw))",
  ),
  (
    '0215-horseradish-crusted-beef-tenderloin.yaml',
    null,
    3,
    '1 cup plus 2 teaspoons vegetable oil',
    2710180,
    '0.923333',
    '38.09',
    '342.81',
    null,
    'discarded in cooking — only "plus 2 teaspoons vegetable oil", the 1 tablespoon the steps keep and the oil the fried food absorbs counted · approximation (frying oil absorbed: 10.9 % of the raw potatoes\' weight — derived from USDA SR Legacy 19411 "Snacks, potato chips, plain, salted")',
  ),
  (
    '0233-pork-schnitzel-breaded-pork-cutlets.yaml',
    null,
    3,
    '2 cups plus 1 tablespoon vegetable oil',
    2710180,
    '0.923333',
    '51.87',
    '466.83',
    null,
    'discarded in cooking — only "plus 1 tablespoon vegetable oil" and the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw pork\'s weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw))',
  ),
  (
    '0255-fish-and-chips.yaml',
    null,
    1,
    '3 quarts plus ¼ cup peanut oil or canola oil',
    2710187,
    '0.990000',
    '170.78',
    '1537.02',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted ("plus ¼ cup peanut oil or canola oil": the steps rinse it off) · approximation (frying oil absorbed: 15.38 % of the raw cod\'s weight — USDA FNDDS 2706244 recipe: 10 g oil per 65 g raw cod; 6.0 % of the raw potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil")',
  ),
  (
    '0279-crispy-salt-and-pepper-shrimp.yaml',
    null,
    7,
    '4 cups vegetable oil',
    2710180,
    '0.923333',
    '64.06',
    '576.54',
    null,
    'discarded in cooking — only the part the recipe keeps and the oil the fried food absorbs counted · approximation (frying oil absorbed: 5.3 % of the raw shrimp\'s weight — derived from USDA SR Legacy 171982 "Mollusks, squid, mixed species, cooked, fried")',
  ),
  (
    '0287-easy-salmon-cakes.yaml',
    null,
    11,
    '½ cup vegetable oil',
    2710180,
    '0.923333',
    '37.87',
    '340.83',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw salmon's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast (no record for salmon; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw))",
  ),
  // RE-PIN (M63 batch, v62, Q11): the crab cake's own read oil, FNDDS
  // 2706549 7.69 % (was 30.30 g, 272.70 kcal on the breast's 6.68 %
  // stand-in) — the one uptake row M63 moves.
  (
    '0288-maryland-crab-cakes.yaml',
    null,
    9,
    '¼ cup vegetable oil',
    2710180,
    '0.923333',
    '34.88',
    '313.92',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 7.69 % of the raw crab's weight — USDA FNDDS 2706549 recipe: 5 g oil per 65 g raw crab)",
  ),
  (
    '0304-chicken-fried-steaks.yaml',
    null,
    8,
    '4–5 cups peanut oil',
    2710187,
    '0.990000',
    '84.11',
    '756.99',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 9.89 % of the raw beef's weight — USDA FNDDS 2705842 recipe: 9 g oil per 90.99 g raw beef steak)",
  ),
  (
    '0316-classic-french-fries.yaml',
    null,
    1,
    '2 quarts peanut oil',
    2710187,
    '0.990000',
    '55.11',
    '495.99',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil")',
  ),
  (
    '0316-steak-fries.yaml',
    null,
    1,
    '2 quarts peanut oil',
    2710187,
    '0.990000',
    '68.04',
    '612.36',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil")',
  ),
  (
    '0317-easier-french-fries.yaml',
    null,
    1,
    '6 cups peanut oil',
    2710187,
    '0.990000',
    '68.04',
    '612.36',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil")',
  ),
  (
    '0318-thick-cut-sweet-potato-fries.yaml',
    null,
    4,
    '3 cups peanut oil',
    2710187,
    '0.990000',
    '65.32',
    '587.88',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw sweet potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil" (no record for sweet potatoes; read as Fast foods, potato, french fried in vegetable oil))',
  ),
  (
    '0319-crunchy-kettle-potato-chips.yaml',
    null,
    0,
    '2 quarts vegetable oil, for frying',
    2710180,
    '0.923333',
    '49.44',
    '444.96',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 10.9 % of the raw potatoes\' weight — derived from USDA SR Legacy 19411 "Snacks, potato chips, plain, salted")',
  ),
  (
    '0415-best-chicken-parmesan.yaml',
    null,
    19,
    '⅓ cup vegetable oil',
    2710180,
    '0.923333',
    '26.51',
    '238.59',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  (
    '0464-steak-frites.yaml',
    null,
    9,
    '3 quarts peanut oil',
    2710187,
    '0.990000',
    '68.04',
    '612.36',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil")',
  ),
  (
    '0491-spicy-mexican-shredded-pork-tostadas.yaml',
    null,
    10,
    '¾ cup vegetable oil',
    2710180,
    '0.923333',
    '41.81',
    '376.29',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 13.4 % of the raw corn tortillas\' weight — derived from USDA SR Legacy 167525 "Tostada shells, corn")',
  ),
  (
    '0511-shrimp-tempura.yaml',
    null,
    0,
    '3 quarts peanut or vegetable oil',
    2710187,
    '0.673333',
    '104.64',
    '941.76',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 15.38 % of the raw shrimp's weight — USDA FNDDS 2706364 recipe: 10 g oil per 65 g raw shrimp)",
  ),
  (
    '0525-orange-flavored-chicken.yaml',
    null,
    16,
    '3 cups peanut or vegetable oil',
    2710187,
    '0.673333',
    '48.38',
    '435.42',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 7.11 % of the raw chicken thigh's weight — USDA FNDDS 2706047 recipe: 7 g oil per 98.39 g raw chicken thigh)",
  ),
  (
    '0526-dakgangjeong-korean-fried-chicken-wings.yaml',
    null,
    7,
    '2 quarts vegetable oil',
    2710180,
    '0.923333',
    '44.97',
    '404.73',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.61 % of the raw chicken wings' weight — USDA FNDDS 2706065 recipe: 7 g oil per 105.96 g raw chicken wing)",
  ),
  (
    '0527-karaage-japanese-fried-chicken-thighs.yaml',
    null,
    8,
    '1 quart vegetable oil for frying',
    2710180,
    '0.923333',
    '48.38',
    '435.42',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 7.11 % of the raw chicken thigh's weight — USDA FNDDS 2706047 recipe: 7 g oil per 98.39 g raw chicken thigh)",
  ),
  (
    '0536-crispy-orange-beef.yaml',
    null,
    8,
    '3 cups vegetable oil',
    2710180,
    '0.923333',
    '95.29',
    '857.61',
    null,
    "discarded in cooking — only the part the recipe keeps and the oil the fried food absorbs counted · approximation (frying oil absorbed: 9.89 % of the raw beef's weight — USDA FNDDS 2705842 recipe: 9 g oil per 90.99 g raw beef steak (no record for beef; read as Beef, steak, country fried))",
  ),
  (
    '0672-buffalo-cauliflower-bites.yaml',
    null,
    4,
    '1–2 quarts peanut or vegetable oil',
    2710187,
    '0.673333',
    '73.30',
    '659.70',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed — derived: 16.16 % of the raw cauliflower's weight — USDA FNDDS 2710042 recipe: 12 g oil per 39.58 g raw cauliflower, scaled to the recipe's batter (122.16 g of 229.20 g carbohydrate))",
  ),
  (
    '0690-patatas-bravas.yaml',
    null,
    12,
    '3 cups vegetable oil',
    2710180,
    '0.923333',
    '49.60',
    '446.40',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil")',
  ),
  (
    '0706-platanos-maduros-fried-sweet-plantains.yaml',
    null,
    0,
    '3 cups vegetable oil',
    2710180,
    '0.923333',
    '66.27',
    '596.43',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 5.5 % of the raw plantains\' weight — derived from USDA SR Legacy 168200 "Plantains, yellow, fried, Latino restaurant")',
  ),
  (
    '1081-crispy-fish-sandwiches-with-tartar-sauce.yaml',
    null,
    11,
    '2 quarts peanut or vegetable oil for frying',
    2710187,
    '0.500000',
    '87.20',
    '784.80',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 15.38 % of the raw haddock's weight — USDA FNDDS 2706258 recipe: 10 g oil per 65 g raw haddock)",
  ),
  (
    '1084-rhode-islandstyle-fried-calamari.yaml',
    null,
    7,
    '2 quarts vegetable oil for frying',
    2710180,
    '0.923333',
    '24.04',
    '216.36',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 5.3 % of the raw squid\'s weight — derived from USDA SR Legacy 171982 "Mollusks, squid, mixed species, cooked, fried")',
  ),
  (
    '1123-pastelon-puerto-rican-sweet-plantain-and-picadillo-casserole.yaml',
    null,
    7,
    '¾ cup vegetable oil for frying',
    2710180,
    '0.923333',
    '81.08',
    '729.72',
    null,
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 5.5 % of the raw plantains\' weight — derived from USDA SR Legacy 168200 "Plantains, yellow, fried, Latino restaurant")',
  ),
  (
    '1133-chicken-francese.yaml',
    null,
    8,
    '⅓ cup extra-virgin olive oil for frying',
    748608,
    '1.000000',
    '26.13',
    '220.35',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  (
    '1133-chicken-francese.yaml',
    null,
    9,
    '⅓ cup vegetable oil for frying',
    2710180,
    '0.923333',
    '26.89',
    '242.01',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
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
    // RE-PIN (M62 batch, v61): matcherVersion 60 (was 59).
    // RE-PIN (M63 batch, v62): matcherVersion 61 (was 60).
    // RE-PIN (M64 batch, v63): matcherVersion 62 (was 61).
    expect(matcherVersion, 62);
  });

  group('matcher v60 (batch M61)', skip: skipIfNoCorpus, () {
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
      tempDir = Directory.systemTemp.createTempSync('salt-v60-');
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
        ..._uptakes,
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

    Recipe recipeOf(String file, String? section) => section == null
        ? recipes[file]!
        : nutritionRecipeOf(
            db,
            sectionKeyOf(recipes[file]!.id, section),
          )!.recipe;

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
    /// the grams, the energy, the hold and the basis; `auto`.
    void expectRows(List<_Row> rows) {
      for (final (
            file,
            section,
            position,
            raw,
            fdcId,
            confidence,
            grams,
            kcal,
            hold,
            basis,
          )
          in rows) {
        final recipe = recipeOf(file, section);
        final line = nutritionLines(recipe)[position];
        final row = rowIn(recipe, position);
        final reason = '$file|$section|$position';
        expect(line.raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.confidence.toStringAsFixed(6), confidence, reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(row.status, 'auto', reason: reason);
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

    /// The counted grams of [file]'s rows at [positions].
    double sumOf(String file, Iterable<int> positions) => positions.fold(
      0,
      (n, p) => n + rowIn(recipes[file]!, p).grams!,
    );

    String g2(double v) => v.toStringAsFixed(2);

    test('M61 reaches exactly its 5 rows (design_v2 §2 M61)', () {
      expect(_reach, hasLength(5));
      expectRows(_reach);
    });

    test("the raw mix is the counted rows of the oil line's group before it "
        '(Q12 ii) and the oil u × that mix / 100 at the five figures', () {
      // Pakoras: |0–|12 but the unmatched ajwain |6; the water |13 carries no
      // record.
      final pakoras = recipes[_pakoras]!;
      expect(rowIn(pakoras, 6).fdcId, isNull);
      expect(rowIn(pakoras, 13).fdcId, isNull);
      expect(nutritionLines(pakoras)[13].raw, '¼ cup water');
      final pakoraMix = sumOf(_pakoras, [
        0,
        1,
        2,
        3,
        4,
        5,
        7,
        8,
        9,
        10,
        11,
        12,
      ]);
      expect(g2(pakoraMix), '483.06');
      // Lumpia: the LUMPIA group |6–|16 — never the DIPPING SAUCE |0–|5
      // before it (the mutant "every counted main row" reads 1,490.58).
      final lumpiaMix = sumOf(_lumpia, [for (var p = 6; p <= 16; p++) p]);
      expect(g2(lumpiaMix), '1303.73');
      expect(g2(sumOf(_lumpia, [0, 1, 2, 3, 4, 5])), '186.85');
      expect(recipes[_lumpia]!.ingredients.first.items, hasLength(6));
      // Falafel: |0–|10 (the TAHINI SAUCE group follows the oil).
      final falafelMix = sumOf(_falafel, [for (var p = 0; p <= 10; p++) p]);
      expect(g2(falafelMix), '395.35');
      // Doughnuts: |0–|6, never the GLAZE |8–|10 after the oil.
      final doughMix = sumOf(_doughnuts, [for (var p = 0; p <= 6; p++) p]);
      // 1,278.71 at full precision (22½ oz of flour = 637.864 g …); the
      // plan's 1,278.69 summed the replay's 2-dp rows — the oil is 213.80
      // either way.
      expect(g2(doughMix), '1278.71');
      expect(g2(sumOf(_doughnuts, [8, 10])), '368.94');
      expect(recipes[_doughnuts]!.ingredients.first.items, hasLength(8));
      // Struffoli: |0–|6 (one group; the honey and garnishes follow the oil).
      final struffoliMix = sumOf(_struffoli, [for (var p = 0; p <= 6; p++) p]);
      expect(g2(struffoliMix), '552.37');
      for (final (file, position, u, mix) in [
        (_pakoras, 14, 8.43, pakoraMix),
        (_lumpia, 17, 7.62, lumpiaMix),
        (_falafel, 11, 21.64, falafelMix),
        (_doughnuts, 7, 16.72, doughMix),
        (_struffoli, 7, 23.32, struffoliMix),
      ]) {
        expect(
          g2(rowIn(recipes[file]!, position).grams!),
          g2(u * mix / 100),
          reason: file,
        );
        expect(
          basisIn(recipes[file]!, position),
          contains(
            'frying oil absorbed: ${u.toStringAsFixed(2)} % of the raw ',
          ),
          reason: file,
        );
      }
    });

    test('the rows M61 must not move equal v59', () {
      expectRows(_negatives);
    });

    test('the 36 uptake rows equal v59, row by row', () {
      expect(_uptakes, hasLength(36));
      expect(
        _uptakes.every((r) => r.$10!.contains('frying oil absorbed')),
        isTrue,
      );
      expectRows(_uptakes);
    });

    /// [corpus] with [id] appended to its id and slug, computed whole.
    Future<Recipe> variant(Recipe corpus, String id) => compute(
      corpus.copyWith(id: '${corpus.id}-$id', slug: '${corpus.slug}-$id'),
    );

    test('a product word in a NON-frying sentence fries nothing — STATED '
        'synthesized: struffoli with "to transfer struffoli to pot" read '
        '"to transfer pieces to pot" keeps its oil at 0 g', () async {
      final corpus = loadCorpusRecipe(_struffoli);
      const frying = 'to transfer struffoli to pot';
      expect(corpus.steps.where((s) => s.text.contains(frying)), hasLength(1));
      final stored = await variant(
        corpus.copyWith(
          steps: [
            for (final s in corpus.steps)
              s.copyWith(
                text: s.text.replaceAll(frying, 'to transfer pieces to pot'),
              ),
          ],
        ),
        'no-frying-word',
      );
      // "struffoli" and "dough" stay in other sentences ("While struffoli
      // cool", "Repeat with remaining dough").
      expect(rowIn(stored, 7).grams, 0);
      expect(basisIn(stored, 7), 'discarded in cooking — counted as 0 g');
    });

    test(
      'no product word, no uptake — STATED synthesized: the lumpia with '
      'every "lumpia" in its steps read "rolls" keeps its oil at 0 g',
      () async {
        final corpus = loadCorpusRecipe(_lumpia);
        final stored = await variant(
          corpus.copyWith(
            steps: [
              for (final s in corpus.steps)
                s.copyWith(
                  text: s.text
                      .replaceAll('lumpia', 'rolls')
                      .replaceAll('Lumpia', 'Rolls'),
                ),
            ],
          ),
          'no-product',
        );
        expect(rowIn(stored, 17).grams, 0);
        expect(basisIn(stored, 17), 'discarded in cooking — counted as 0 g');
      },
    );

    test('Q12 (iv): a roll with no meat has no read record (FNDDS 2708700 '
        'was never read) — STATED synthesized: the lumpia without its "1 '
        'pound ground pork" keeps its oil at 0 g', () async {
      final corpus = loadCorpusRecipe(_lumpia);
      final group = corpus.ingredients[1];
      expect(group.items[6].raw, '1 pound ground pork');
      final stored = await variant(
        corpus.copyWith(
          ingredients: [
            corpus.ingredients.first,
            group.copyWith(
              items: [
                for (final i in group.items)
                  if (i.raw != '1 pound ground pork') i,
              ],
            ),
          ],
        ),
        'meatless',
      );
      expect(
        nutritionLines(stored)[16].raw,
        '1½ quarts vegetable oil for frying',
      );
      expect(rowIn(stored, 16).grams, 0);
      expect(basisIn(stored, 16), 'discarded in cooking — counted as 0 g');
    });

    test(
      "a bare batter or dough is a stand-in, flagged as API.md's M61 table "
      'quotes (closer 1, verify1 D1) — STATED synthesized: the pakoras '
      'with "pakoras" in its steps read "pieces" (its "batter to oil" is '
      'the frying sentence left) and the doughnuts with "doughnut" in its '
      'steps read "dough round" (its yeast row kept)',
      () async {
        final pakoras = loadCorpusRecipe(_pakoras);
        final batter = await variant(
          pakoras.copyWith(
            steps: [
              for (final s in pakoras.steps)
                s.copyWith(text: s.text.replaceAll('pakoras', 'pieces')),
            ],
          ),
          'bare-batter',
        );
        expect(rowIn(batter, 14).grams?.toStringAsFixed(2), '40.72');
        expect(
          basisIn(batter, 14),
          "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 8.43 % of the raw batter's weight — USDA FNDDS 2710066 recipe: 21 g oil per 249.18 g raw pakora batter (no record for batter; read as Pakora))",
        );
        final doughnuts = loadCorpusRecipe(_doughnuts);
        final dough = await variant(
          doughnuts.copyWith(
            steps: [
              for (final s in doughnuts.steps)
                s.copyWith(text: s.text.replaceAll('doughnut', 'dough round')),
            ],
          ),
          'bare-dough',
        );
        expect(rowIn(dough, 7).grams?.toStringAsFixed(2), '213.80');
        expect(
          basisIn(dough, 7),
          'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 16.72 % of the raw dough\'s weight — derived from USDA SR Legacy 172758 "Doughnuts, yeast-leavened, glazed, enriched (includes honey buns)" (no record for dough; read as Doughnuts, yeast-leavened, glazed, enriched (includes honey buns)))',
        );
      },
    );

    test('the five recipes move kcal per serving only', () {
      (String, String) of(String file) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        return (n.status, n.caloriesPerServing!.toStringAsFixed(2));
      }

      expect(of(_pakoras), ('partial', '226.76')); // v59 136.77 (ajwain)
      // Lumpia: the replay's 655.72 (v59 506.71); its pork |12 reads 1,034.19
      // kcal in a fresh compute against the replay's 1,035.43.
      expect(of(_lumpia), ('complete', '655.51'));
      expect(of(_falafel), ('complete', '613.83')); // v59 421.35
      expect(of(_doughnuts), ('complete', '599.61')); // v59 439.26
      expect(of(_struffoli), ('partial', '716.48')); // v59 523.27 (cherries)
    });

    test('the matches GET plans M52 once per request (closer 2, verify2 D1: '
        "once per row, O(oils²) at the caps) and every line's gram_basis "
        "equals the memo-free per-row plan's", () async {
      final reached = {
        for (final (file, _, _, _, _, _, _, _, _, _) in [
          ..._reach,
          ..._uptakes,
        ])
          file,
      };
      // Not vacuous: the GET shows the 5 reach and 36 uptake flags.
      var flagged = 0;
      for (final MapEntry(key: file, value: recipe) in recipes.entries) {
        m52PlanRuns = 0;
        final items =
            (await matchesBody(db, provider, recipe))['items']!
                as List<Map<String, Object?>>;
        expect(
          m52PlanRuns,
          reached.contains(file) ? 1 : lessThanOrEqualTo(1),
          reason: file,
        );
        final lines = nutritionLines(recipe);
        expect(items, hasLength(lines.length), reason: file);
        for (final (position, line) in lines.indexed) {
          final match = items[position]['match'] as Map<String, Object?>?;
          if ('${match?['gram_basis']}'.contains('frying oil absorbed')) {
            flagged++;
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
      expect(flagged, _reach.length + _uptakes.length);
    });

    test('a second recompute writes nothing', () {
      for (final file in const [
        _pakoras,
        _lumpia,
        _falafel,
        _doughnuts,
        _struffoli,
      ]) {
        final recipe = recipes[file]!;
        List<(int, double?, String?)> rows() => [
          for (final r in db.ingredientMatchesFor(recipe.id))
            (r.position, r.grams, r.updatedAt),
        ];
        final before = rows();
        expect(recomputeTotals(db, recipe), isTrue, reason: file);
        expect(rows(), before, reason: file);
      }
    });

    // Last: it writes person decisions into the group's database.
    test('every M52 coat and oil row CONFIRMED through the real PUT: the '
        'matches GET still plans M52 once per request (closer 3, verify3 D1: '
        'once per confirmed row) and shows what the per-row derivation '
        'shows', () async {
      final reached = {
        for (final (file, _, _, _, _, _, _, _, _, _) in [
          ..._reach,
          ..._uptakes,
        ])
          file,
      };
      var confirmed = 0;
      var oilFlags = 0;
      for (final file in reached) {
        final recipe = recipes[file]!;
        // The rows M52 weighs ([_m52Plan]'s candidates): an engine row
        // held `coating`, or one it counted `discarded`.
        for (final r in db.ingredientMatchesFor(recipe.id)) {
          if (r.status == 'auto' &&
              (r.hold == 'coating' ||
                  (r.hold == null && r.gramSource == 'discarded'))) {
            await applyMatchOverride(db, provider, recipe, r.position, {
              'raw': r.raw,
              'confirmed': true,
            });
            confirmed++;
          }
        }
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
          // The shipped per-row path: [derivedFor] with no memo.
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
          if (row.status == 'confirmed' &&
              '${match['gram_basis']}'.contains('frying oil absorbed')) {
            oilFlags++;
          }
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
      // Not vacuous: every flagged oil confirmed and shown with its flag.
      expect(confirmed, greaterThanOrEqualTo(_reach.length + _uptakes.length));
      expect(oilFlags, _reach.length + _uptakes.length);
      // The guard (STATED synthesized: pakoras' confirmed oil line edited
      // to "3 quarts", not computed — a carried row, the stored row not the
      // confirm's): its own plan, as shipped — the request's stored plan
      // drops the line (its text moved) and would show the 0 g pour-away.
      const old = '2 quarts canola oil for frying';
      const now = '3 quarts canola oil for frying';
      final pakoras = recipes[_pakoras]!;
      final parsed = parseIngredientLine(now);
      db.upsertRecipe(
        pakoras.copyWith(
          ingredients: [
            for (final g in pakoras.ingredients)
              g.copyWith(
                items: [
                  for (final l in g.items)
                    l.raw == old
                        ? IngredientLine(
                            raw: now,
                            item: parsed.item,
                            amounts: parsed.amounts,
                          )
                        : l,
                ],
              ),
          ],
        ),
        sourceSlug: _source,
        contentHash: '${pakoras.id} 3 quarts',
      );
      final edited = db.recipeByIdOrSlug(pakoras.id)!.recipe;
      final line = nutritionLines(edited)[14];
      expect(line.raw, now);
      final match =
          ((await matchesBody(db, provider, edited))['items']!
                  as List<Map<String, Object?>>)[14]['match']!
              as Map<String, Object?>;
      final d = await derivedFor(
        db,
        cacheOnly,
        edited,
        14,
        line,
        rowIn(edited, 14),
      );
      expect(
        (match['carried_from'], match['status'], match['grams'], d.row.grams),
        (old, 'confirmed', 40.72, 40.72),
      );
    });
  });
}
