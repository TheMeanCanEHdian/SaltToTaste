// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v68 (batch M70 — the records read at live step L49 and the
// zero-request giblets; matcherVersion 68; prep49 design_v2 §2 M70, the
// owner's Q1 flat (b′), Q11 and Q13 G2, 2026-10-09; zero requests; reach
// PRE-Q18 — the giblet and rind readers read steps): 1 the pomegranate
// brisket's ¼-inch flat on SR 173128 with its braised pair's energy share
// (engine `trimDepthRecords`, `braisedEnergyShare`, `trimStandInFlagOf`);
// 2 the Giblet Pan Gravy's reserved giblets weighed off the host's turkey
// on the cached 171083 hit (`hostWeighedGiblets`; grams.dart `buysRefuse`
// never fetches its detail); 3 yuca on SR 169985 with FNDDS 2709565's READ
// uptake 15 % (`_rankAs`, `_friedClassOf`); 4 a Parmesan rind on 170848,
// discarded whole (`_rankAs`, `_wholePieceHeads`); 5 a chopped or minced
// basil volume on SR 172232's chopped portion (grams.dart
// `fineCutSiblings`, `fineCutWeighing`); 6 Hershey's Kisses on 167587 at the
// label's 41 g per 9 (`_rankAs`, `_pieceWeights`); 7 powdered pectin on
// 168821 at the Sure-Jell label's 4 g a teaspoon (`_rankAs`, `_densities`).
// Every row value is the fresh compute of the WHOLE recipe (sections
// first; the deli-ham recipe and 0974's crusts first, as a library holds
// them) over recorded real FDC answers (FixtureProvider; 32 searches and 10
// details added --from-db from snapshot 26, and closer 1's 22 searches and
// 4 details for the full-set negatives, JSON-equal, 0 existing entries
// changed), equal to the v68 replay of snapshot 26 (rp43, fix69 r1/r3) on
// every pinned field and, on every row M70 must not move, to the v67 (M69)
// rows (two stated exceptions, the liquid smoke's and the Lapsang Souchong
// tea's grams); never the network.
// Synthesized, STATED: `trimStandInFlagOf` asked about a real flat line
// with no printed cap on 173128, a record it never sits on; and (closer 2,
// D1) 0154 re-saved with its bird's "12- to 14-pound" edited to "16- to
// 18-pound" — a host-only edit the Giblet Pan Gravy's hash must see.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

/// (file, section title, position, raw, fdc id, description, confidence,
/// grams, status, hold, kcal, basis) — a row of the fresh compute.
typedef _Row = (
  String,
  String?,
  int,
  String,
  int?,
  String,
  String,
  String?,
  String,
  String?,
  String?,
  String?,
);

/// The basil rows' basis suffix (grams.dart `fineCutWeighing`).
const String _chopped =
    ' · chopped: 2.65 g per tablespoon — USDA SR 172232 "Basil, fresh" '
    "'tbsp, chopped' × 2 = 5.3 g";

/// The pectin rows' label (grams.dart `_approximateDensities`).
const String _sureJell =
    'Sure-Jell label (Kraft Heinz, FDC Branded 2596757; the regular box — '
    'FDC holds no label of the low/no-sugar box the line names; the other '
    "makers' boxes read 3.2–4.0 g per teaspoon): ⅛ teaspoon = 0.5 g";

const _pomegranate =
    '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml';
const _classicTurkey = '0154-classic-roast-turkey.yaml';
const _stuffedTurkey = '0158-classic-roast-stuffed-turkey.yaml';
const _crispSkin =
    '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml';
const _yuca = '1098-fried-yuca.yaml';
const _minestrone = '0028-hearty-minestrone.yaml';
const _fagioli = '0404-pasta-e-fagioli-italian-pasta-and-bean-soup.yaml';
const _chickenSoup = '0403-italian-chicken-soup-with-parmesan-dumplings.yaml';
const _meringue = '1198-meringue-christmas-trees.yaml';
const _gravy = 'Giblet Pan Gravy';

/// The 63 rows M70 moves (fix69 r1 vs the v68 rows), by item.
const List<_Row> _reach = [
  // 1 pomegranate (Q1 flat (b′))
  (
    '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml',
    null,
    0,
    '1 (4- to 5-pound) beef brisket, flat cut, fat trimmed to ¼ inch',
    173128,
    'Beef, brisket, flat half, separable lean and fat, trimmed to 1/8" fat, choice, raw',
    '1.000000',
    '2041.16',
    'auto',
    null,
    '5674.44',
    "from the printed weight (4–5 lb, the midpoint) · approximate (the printed ¼-inch fat cap counted at USDA's ⅛-inch flat trim; USDA's braised pair 173128 → 173130 keeps 67.6 % of the energy by the protein tracer — the fat the steps skim, deducted)",
  ),
  // 2 giblets (Q13 G2) — an ENGINE rule row before (confirmed, 0 g)
  (
    '0154-classic-roast-turkey.yaml',
    'Giblet Pan Gravy',
    1,
    'Reserved turkey giblets, neck, and tailpiece',
    171083,
    'Turkey, whole, giblets, raw',
    '1.000000',
    '291.37',
    'auto',
    null,
    '361.29',
    "the host's turkey from the printed weight (12–14 lb, the midpoint): 5897 g × 7/85 neck and giblets (USDA AH-102 turkey dressing data, 12 lb and over: 85 with, 78 without) × 6/10 giblets (item 2590: neck 4, giblets 6, fryer-roaster class) · approximate (the neck and tailpiece are strained out — not counted)",
  ),
  // 3 yuca (pF L1; R-1 read)
  (
    '1098-fried-yuca.yaml',
    null,
    0,
    '2 pounds yuca roots',
    169985,
    'Cassava, raw',
    '1.000000',
    '907.18',
    'auto',
    null,
    '1451.49',
    'from 2 pound',
  ),
  (
    '1098-fried-yuca.yaml',
    null,
    2,
    '2 quarts vegetable oil',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '136.08',
    'auto',
    null,
    '1224.72',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 15.00 % of the raw yuca's weight — USDA FNDDS 2709565 recipe: 15 g oil per 100 g raw cassava)",
  ),
  // 4 rind (pF F3)
  (
    '0028-hearty-minestrone.yaml',
    null,
    14,
    '1 piece Parmesan cheese rind, about 5 by 2 inches',
    170848,
    'Cheese, parmesan, hard',
    '1.000000',
    '0.00',
    'auto',
    null,
    '0.00',
    'removed and discarded (step 4) — counted as 0 g',
  ),
  (
    '0404-pasta-e-fagioli-italian-pasta-and-bean-soup.yaml',
    null,
    9,
    '1 piece Parmesan cheese rind, about 5 inches by 2 inches',
    170848,
    'Cheese, parmesan, hard',
    '1.000000',
    '0.00',
    'auto',
    null,
    '0.00',
    'removed and discarded (step 2) — counted as 0 g',
  ),
  (
    '0403-italian-chicken-soup-with-parmesan-dumplings.yaml',
    null,
    8,
    '1 Parmesan cheese rind, plus 3 ounces Parmesan, shredded (1 cup)',
    170848,
    'Cheese, parmesan, hard',
    '1.000000',
    '85.05',
    'auto',
    'second_food',
    null,
    'from 3 ounce',
  ),
  // 5 basil (pE Q6): 50 rows
  (
    '0060-antipasto-pasta-salad.yaml',
    null,
    13,
    '1 cup minced fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '42.40',
    'auto',
    null,
    '9.75',
    '1 cup · USDA portion$_chopped',
  ),
  (
    '0368-baked-manicotti.yaml',
    null,
    11,
    '2 tablespoons chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  (
    '0368-baked-manicotti.yaml',
    null,
    5,
    '2 tablespoons chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  (
    '0367-baked-ziti.yaml',
    null,
    10,
    '½ cup plus 2 tablespoons chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '26.50',
    'auto',
    null,
    '6.09',
    '1/2 cup · USDA portion + 2 tablespoons chopped fresh basil leaves$_chopped',
  ),
  (
    '0415-best-chicken-parmesan.yaml',
    null,
    7,
    '2 tablespoons coarsely chopped fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  (
    '0708-best-summer-tomato-gratin.yaml',
    null,
    8,
    '2 tablespoons chopped fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  (
    '1089-braciole.yaml',
    null,
    4,
    '⅓ cup plus 2 tablespoons chopped fresh basil, divided',
    2709780,
    'Basil, raw',
    '0.910000',
    '19.43',
    'auto',
    null,
    '4.47',
    '1/3 cup · USDA portion + 2 tablespoons chopped fresh basil$_chopped',
  ),
  (
    '0341-campanelle-with-asparagus-basil-and-balsamic-glaze.yaml',
    null,
    8,
    '1 cup chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '42.40',
    'auto',
    null,
    '9.75',
    '1 cup · USDA portion$_chopped',
  ),
  (
    '0068-cast-iron-baked-ziti-with-charred-tomatoes.yaml',
    null,
    9,
    '¼ cup chopped fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '10.60',
    'auto',
    null,
    '2.44',
    '1/4 cup · USDA portion$_chopped',
  ),
  (
    '0387-chicago-style-deep-dish-pizza.yaml',
    null,
    15,
    '2 tablespoons chopped fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  (
    '0405-ciambotta-italian-vegetable-stew.yaml',
    null,
    0,
    '⅓ cup chopped fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '14.13',
    'auto',
    null,
    '3.25',
    '1/3 cup · USDA portion$_chopped',
  ),
  (
    '0358-classic-spaghetti-and-meatballs-for-a-crowd.yaml',
    null,
    22,
    '½ cup minced fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '21.20',
    'auto',
    null,
    '4.88',
    '1/2 cup · USDA portion$_chopped',
  ),
  (
    '0409-eggplant-involtini.yaml',
    null,
    10,
    '¼ cup plus 1 tablespoon chopped fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '13.25',
    'auto',
    null,
    '3.05',
    '1/4 cup · USDA portion + 1 tablespoon chopped fresh basil$_chopped',
  ),
  (
    '0407-eggplant-parmesan.yaml',
    null,
    12,
    '½ cup coarsely chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '21.20',
    'auto',
    null,
    '4.88',
    '1/2 cup · USDA portion$_chopped',
  ),
  (
    '0324-fresh-pasta-without-a-machine.yaml',
    'Tomato and Browned Butter Sauce',
    6,
    '3 tablespoons chopped fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '7.95',
    'auto',
    null,
    '1.83',
    '3 tablespoon · USDA portion$_chopped',
  ),
  (
    '0657-grilled-corn-with-flavored-butter.yaml',
    'Basil and Lemon Butter',
    1,
    '2 tablespoons minced fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  (
    '0654-grilled-swordfish-skewers-with-tomato-scallion-caponata.yaml',
    null,
    14,
    '2 tablespoons minced fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  (
    '0396-grilled-tomato-and-cheese-pizza.yaml',
    null,
    12,
    '½ cup chopped fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '21.20',
    'auto',
    null,
    '4.88',
    '1/2 cup · USDA portion$_chopped',
  ),
  (
    '0028-hearty-minestrone.yaml',
    null,
    17,
    '½ cup chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '21.20',
    'auto',
    null,
    '4.88',
    '1/2 cup · USDA portion$_chopped',
  ),
  (
    '0061-italian-pasta-salad.yaml',
    null,
    14,
    '1 cup chopped fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '42.40',
    'auto',
    null,
    '9.75',
    '1 cup · USDA portion$_chopped',
  ),
  (
    '0000-italian-style-turkey-meatballs.yaml',
    null,
    16,
    '¼ cup chopped fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '10.60',
    'auto',
    null,
    '2.44',
    '1/4 cup · USDA portion$_chopped',
  ),
  (
    '0374-lasagna-with-hearty-tomato-meat-sauce.yaml',
    null,
    11,
    '½ cup chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '21.20',
    'auto',
    null,
    '4.88',
    '1/2 cup · USDA portion$_chopped',
  ),
  (
    '0416-lighter-chicken-parmesan.yaml',
    null,
    11,
    '1 tablespoon minced fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '2.65',
    'auto',
    null,
    '0.61',
    '1 tablespoon · USDA portion$_chopped',
  ),
  (
    '0416-lighter-chicken-parmesan.yaml',
    'Simple Tomato Sauce',
    5,
    '1 tablespoon minced fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '2.65',
    'auto',
    null,
    '0.61',
    '1 tablespoon · USDA portion$_chopped',
  ),
  (
    '0034-lighter-corn-chowder.yaml',
    null,
    11,
    '3 tablespoons chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '7.95',
    'auto',
    null,
    '1.83',
    '3 tablespoon · USDA portion$_chopped',
  ),
  (
    '0330-marinara-sauce.yaml',
    null,
    6,
    '3 tablespoons chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '7.95',
    'auto',
    null,
    '1.83',
    '3 tablespoon · USDA portion$_chopped',
  ),
  (
    '0330-meatless-meat-sauce-with-chickpeas-and-mushrooms.yaml',
    null,
    11,
    '2 tablespoons chopped fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  (
    '0263-oven-roasted-salmon.yaml',
    'Fresh Tomato Relish',
    1,
    '2 tablespoons chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  (
    '0272-pan-roasted-halibut-steaks.yaml',
    'Chunky Cherry Tomato–Basil Vinaigrette',
    6,
    '2 tablespoons minced fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  (
    '0047-panzanella-italian-bread-salad.yaml',
    null,
    7,
    '¼ cup chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '10.60',
    'auto',
    null,
    '2.44',
    '1/4 cup · USDA portion$_chopped',
  ),
  (
    '0335-pasta-alla-norma.yaml',
    null,
    7,
    '6 tablespoons chopped fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '15.90',
    'auto',
    null,
    '3.66',
    '6 tablespoon · USDA portion$_chopped',
  ),
  (
    '0326-pasta-and-fresh-tomato-sauce-with-garlic-and-basil.yaml',
    null,
    3,
    '2 tablespoons chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  (
    '0327-pasta-caprese.yaml',
    null,
    8,
    '¼ cup chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '10.60',
    'auto',
    null,
    '2.44',
    '1/4 cup · USDA portion$_chopped',
  ),
  (
    '0326-pasta-with-creamy-tomato-sauce.yaml',
    null,
    14,
    '¼ cup chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '10.60',
    'auto',
    null,
    '2.44',
    '1/4 cup · USDA portion$_chopped',
  ),
  (
    '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml',
    null,
    22,
    '¼ cup chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '10.60',
    'auto',
    null,
    '2.44',
    '1/4 cup · USDA portion$_chopped',
  ),
  (
    '0361-penne-alla-vodka-penne-with-vodka-sauce.yaml',
    null,
    10,
    '2 tablespoons minced fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  (
    '0329-quick-tomato-sauce.yaml',
    null,
    7,
    '2 tablespoons chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  (
    '0360-sausage-meatballs-and-spaghetti.yaml',
    null,
    19,
    '1 tablespoon chopped fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '2.65',
    'auto',
    null,
    '0.61',
    '1 tablespoon · USDA portion$_chopped',
  ),
  (
    '0347-shrimp-fra-diavolo.yaml',
    null,
    9,
    '¼ cup chopped fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '10.60',
    'auto',
    null,
    '2.44',
    '1/4 cup · USDA portion$_chopped',
  ),
  (
    '0371-simple-cheese-lasagna.yaml',
    null,
    23,
    '3 tablespoons chopped fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '7.95',
    'auto',
    null,
    '1.83',
    '3 tablespoon · USDA portion$_chopped',
  ),
  (
    '0068-skillet-baked-ziti.yaml',
    null,
    9,
    '¼ cup minced fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '10.60',
    'auto',
    null,
    '2.44',
    '1/4 cup · USDA portion$_chopped',
  ),
  (
    '0067-skillet-lasagna.yaml',
    null,
    13,
    '3 tablespoons chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '7.95',
    'auto',
    null,
    '1.83',
    '3 tablespoon · USDA portion$_chopped',
  ),
  (
    '0322-spaghetti-al-limone-spaghetti-with-lemon-and-olive-oil.yaml',
    null,
    7,
    '2 tablespoons chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  (
    '0357-spaghetti-and-meatballs.yaml',
    null,
    14,
    '1 tablespoon minced fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '2.65',
    'auto',
    null,
    '0.61',
    '1 tablespoon · USDA portion$_chopped',
  ),
  (
    '0440-summer-vegetable-gratin.yaml',
    null,
    12,
    '¼ cup chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '10.60',
    'auto',
    null,
    '2.44',
    '1/4 cup · USDA portion$_chopped',
  ),
  (
    '0399-tomato-and-mozzarella-tart.yaml',
    null,
    8,
    '2 tablespoons minced fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  (
    '1132-ultracreamy-spaghetti-with-zucchini.yaml',
    null,
    5,
    '2 tablespoons chopped fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  (
    '0373-vegetable-lasagna.yaml',
    null,
    1,
    '¼ cup minced fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '10.60',
    'auto',
    null,
    '2.44',
    '1/4 cup · USDA portion$_chopped',
  ),
  (
    '0373-vegetable-lasagna.yaml',
    null,
    24,
    '2 tablespoons chopped fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  (
    '0441-walkaway-ratatouille.yaml',
    null,
    12,
    '2 tablespoons chopped fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.30',
    'auto',
    null,
    '1.22',
    '2 tablespoon · USDA portion$_chopped',
  ),
  // 6 Kisses (pF F6, Q11)
  (
    '1198-meringue-christmas-trees.yaml',
    null,
    8,
    '62 Hershey’s Kisses, unwrapped',
    167587,
    'Candies, milk chocolate',
    '1.000000',
    '282.44',
    'auto',
    null,
    '1511.08',
    "62 × 4.6 g each · approximate (Hershey's label: 9 pieces = 41 g (FDC Branded 1642930 and four more; three 2023 labels print 7 pieces = 32 g))",
  ),
  // 7 pectin (pF F1, Q11)
  (
    '0859-marbled-blueberry-bundt-cake.yaml',
    null,
    12,
    '3 tablespoons low- or no-sugar-needed fruit pectin',
    168821,
    'Pectin, unsweetened, dry mix',
    '1.000000',
    '36.00',
    'auto',
    null,
    '117.00',
    '3 tablespoon ≈ 44 mL · approximate ($_sureJell)',
  ),
  (
    '0982-fresh-peach-pie.yaml',
    null,
    4,
    '2 tablespoons low- or no-sugar-needed fruit pectin',
    168821,
    'Pectin, unsweetened, dry mix',
    '1.000000',
    '24.00',
    'auto',
    null,
    '78.00',
    '2 tablespoon ≈ 30 mL · approximate ($_sureJell)',
  ),
  (
    '1115-fresh-peach-pie-with-all-butter-lattice-top.yaml',
    null,
    4,
    '2 tablespoons low- or no-sugar-needed fruit pectin',
    168821,
    'Pectin, unsweetened, dry mix',
    '1.000000',
    '24.00',
    'auto',
    null,
    '78.00',
    '2 tablespoon ≈ 30 mL · approximate ($_sureJell)',
  ),
  (
    '0944-raspberry-sorbet.yaml',
    null,
    1,
    '1 teaspoon Sure-Jell for Less or No Sugar Needed Recipes',
    168821,
    'Pectin, unsweetened, dry mix',
    '1.000000',
    '4.00',
    'auto',
    null,
    '13.00',
    '1 teaspoon ≈ 5 mL · approximate ($_sureJell)',
  ),
  (
    '0985-fresh-strawberry-pie.yaml',
    null,
    4,
    '1½ teaspoons Sure-Jell for low-sugar recipes',
    168821,
    'Pectin, unsweetened, dry mix',
    '1.000000',
    '6.00',
    'auto',
    null,
    '19.50',
    '1 1/2 teaspoon ≈ 7 mL · approximate ($_sureJell)',
  ),
];

/// The routed parents that re-read a moved section (share 1 each): the
/// Giblet Pan Gravy in both turkeys, the Simple Tomato Sauce's basil.
const List<_Row> _parents = [
  (
    '0154-classic-roast-turkey.yaml',
    null,
    8,
    '1 recipe Giblet Pan Gravy (recipe follows)',
    null,
    '',
    '1.000000',
    '1566.60',
    'auto',
    null,
    '1148.85',
    'from the recipe Giblet Pan Gravy: 1567 g, 1,149 kcal',
  ),
  (
    '0158-classic-roast-stuffed-turkey.yaml',
    null,
    10,
    '1 recipe Giblet Pan Gravy (this page (optional)',
    null,
    '',
    '1.000000',
    '1566.60',
    'auto',
    null,
    '1148.85',
    'from the recipe Giblet Pan Gravy: 1567 g, 1,149 kcal',
  ),
  (
    '0416-lighter-chicken-parmesan.yaml',
    null,
    9,
    '1 recipe Simple Tomato Sauce (recipe follows), warmed (see note)',
    null,
    '',
    '1.000000',
    '829.50',
    'auto',
    null,
    '219.14',
    'from the recipe Simple Tomato Sauce: 830 g, 219 kcal',
  ),
];

/// Rows M70 must not move, equal to the v68 rows (the plan's per-item
/// negatives).
const List<_Row> _negatives = [
  // 1: the other 168743 rows, the whole brisket 168664, the racks
  (
    '0223-onion-braised-beef-brisket.yaml',
    null,
    0,
    '1 (4- to 5-pound) beef brisket, preferably flat cut',
    168743,
    'Beef, brisket, flat half, boneless, separable lean and fat, trimmed to 0" fat, choice, raw',
    '1.000000',
    '2041.16',
    'auto',
    null,
    '3449.57',
    'from the printed weight (4–5 lb, the midpoint)',
  ),
  (
    '0090-new-englandstyle-home-corned-beef-and-cabbage.yaml',
    null,
    6,
    '1 (4- to 5-pound) beef brisket, flat cut, trimmed',
    168743,
    'Beef, brisket, flat half, boneless, separable lean and fat, trimmed to 0" fat, choice, raw',
    '1.000000',
    '2041.16',
    'auto',
    null,
    '3449.57',
    "from the printed weight (4–5 lb, the midpoint) · approximate (the steps cure and rinse the brisket — the cure's sodium is not counted; a rinsed cure counts 0 g, CP9)",
  ),
  (
    '0091-home-corned-beef-with-vegetables.yaml',
    null,
    0,
    '1 (4½- to 5-pound) beef brisket, flat cut',
    168743,
    'Beef, brisket, flat half, boneless, separable lean and fat, trimmed to 0" fat, choice, raw',
    '1.000000',
    '2154.56',
    'auto',
    null,
    '3641.21',
    "from the printed weight (4½–5 lb, the midpoint) · approximate (the steps cure and rinse the brisket — the cure's sodium is not counted; a rinsed cure counts 0 g, CP9)",
  ),
  (
    '0595-barbecued-whole-beef-brisket-with-spicy-chili-rub.yaml',
    null,
    10,
    '1 (9- to 11-pound) whole beef brisket, fat trimmed to ¼ inch',
    168664,
    'Beef, brisket, whole, separable lean and fat, trimmed to 1/8" fat, all grades, raw',
    '0.886667',
    '4535.92',
    'auto',
    null,
    '11475.88',
    "from the printed weight (9–11 lb, the midpoint) · approximate (the printed ¼-inch fat cap counted at USDA's ⅛-inch trim, the deepest it publishes for brisket; the fat that renders into the separator is not deducted — USDA's own braised pair 168664 → 168665 keeps 93 % of the energy)",
  ),
  (
    '0228-roast-rack-of-lamb-with-roasted-red-pepper-relish.yaml',
    null,
    0,
    '2 racks of lamb (1¾ to 2 pounds each), fat trimmed to ⅛ to ¼ inch, rib bones frenched',
    174414,
    'Lamb, Australian, imported, fresh, rib chop/rack roast, frenched, bone-in, separable lean and fat, trimmed to 1/8" fat, raw',
    '0.539697',
    '1241.71',
    'auto',
    null,
    '2942.85',
    '2 × 850 g (printed 1¾–2 lb, the midpoint) × 0.73 edible · approximate (USDA AH-102 item 1364: lamb rib loin (rack), bone in, raw → lean and fat meat, slightly trimmed 73 % (61–88), as measured unfrenched; a frenched rack yields less)',
  ),
  (
    '0622-grilled-rack-of-lamb.yaml',
    null,
    5,
    '2 (1½- to 1¾-pound) racks of lamb (8 ribs each), frenched and trimmed',
    172641,
    'Lamb, New Zealand, imported, rack - fully frenched, separable lean and fat, raw',
    '0.539697',
    '1076.15',
    'auto',
    null,
    '1818.69',
    '2 × 737 g (printed 1½–1¾ lb, the midpoint) × 0.73 edible · approximate (USDA AH-102 item 1364: lamb rib loin (rack), bone in, raw → lean and fat meat, slightly trimmed 73 % (61–88), as measured unfrenched; a frenched rack yields less)',
  ),
  // 2: crisp-skin's strained reserved line (no stir-back), the birds, giblets discarded
  (
    '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml',
    'Turkey Gravy',
    0,
    'Reserved giblets, neck, tailpiece, and backbone and rib bones from the turkey',
    null,
    'Reserved from the main recipe — no amount on the line, counts as zero',
    '1.000000',
    '0.00',
    'confirmed',
    null,
    '0.00',
    'no amount on the line — counted as 0 g',
  ),
  (
    '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml',
    null,
    2,
    '1 (12- to 14-pound) turkey; giblets, neck, and tailpiece removed and reserved for gravy; turkey butterflied (see photos on this page) and backbone and rib bones reserved for gravy',
    171081,
    'Turkey, whole, meat and skin, raw',
    '1.000000',
    '3841.87',
    'auto',
    null,
    '5532.29',
    'from the printed weight (12–14 lb, the midpoint) × 0.65 edible · approximate (USDA AH-102 turkey dressing data, 12 lb and over (neck and giblets off 78 of 85); carcass → meat and skin, item 2592, fryer-roaster class, 71 % (67–75))',
  ),
  (
    '0154-classic-roast-turkey.yaml',
    null,
    1,
    '1 (12- to 14-pound) turkey; giblets, neck, and tailpiece removed and reserved for gravy',
    171081,
    'Turkey, whole, meat and skin, raw',
    '1.000000',
    '3841.87',
    'auto',
    null,
    '5532.29',
    'from the printed weight (12–14 lb, the midpoint) × 0.65 edible · approximate (USDA AH-102 turkey dressing data, 12 lb and over (neck and giblets off 78 of 85); carcass → meat and skin, item 2592, fryer-roaster class, 71 % (67–75))',
  ),
  (
    '0158-classic-roast-stuffed-turkey.yaml',
    null,
    1,
    '1 (12- to 14-pound) turkey; giblets, neck, and tailpiece removed and reserved for gravy (see this page)',
    171081,
    'Turkey, whole, meat and skin, raw',
    '1.000000',
    '3841.87',
    'auto',
    null,
    '5532.29',
    'from the printed weight (12–14 lb, the midpoint) × 0.65 edible · approximate (USDA AH-102 turkey dressing data, 12 lb and over (neck and giblets off 78 of 85); carcass → meat and skin, item 2592, fryer-roaster class, 71 % (67–75))',
  ),
  (
    '0170-herbed-roast-turkey.yaml',
    null,
    1,
    '1 (12- to 14-pound) turkey; giblets, neck, and tailpiece removed and discarded',
    171081,
    'Turkey, whole, meat and skin, raw',
    '1.000000',
    '3841.87',
    'auto',
    null,
    '5532.29',
    'from the printed weight (12–14 lb, the midpoint) × 0.65 edible · approximate (USDA AH-102 turkey dressing data, 12 lb and over (neck and giblets off 78 of 85); carcass → meat and skin, item 2592, fryer-roaster class, 71 % (67–75))',
  ),
  (
    '1076-broiled-chicken-with-gravy.yaml',
    null,
    0,
    '1 (4-pound) whole chicken, giblets and neck reserved',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1104.00',
    'auto',
    null,
    '2373.60',
    'from the printed weight × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0134-perfect-roast-chicken.yaml',
    null,
    2,
    '1 (3½- to 4-pound) whole chicken, giblets discarded',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1035.00',
    'auto',
    null,
    '2225.25',
    'from the printed weight (3½–4 lb, the midpoint) × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0147-roasted-cornish-game-hens.yaml',
    null,
    0,
    '4 (1¼- to 1½-pound) Cornish game hens, giblets discarded',
    171507,
    'Chicken, cornish game hens, meat and skin, raw',
    '1.000000',
    '1344.00',
    'auto',
    null,
    '2688.00',
    '4 × 336 g (USDA edible bird portion)',
  ),
  // the remaining 20 "giblets … discarded" lines (the full set: 23; closer 1, D1)
  (
    '0004-pressure-cooker-chicken-noodle-soup.yaml',
    null,
    8,
    '1 (4-pound) whole chicken, giblets discarded',
    171052,
    'Chicken, broilers or fryers, meat only, raw',
    '1.000000',
    '788.00',
    'auto',
    null,
    '937.72',
    'from the printed weight × 0.43 edible (USDA ready-to-cook yield)',
  ),
  (
    '0074-roast-chicken-with-warm-bread-salad.yaml',
    null,
    0,
    '1 (4-pound) whole chicken, giblets discarded',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1104.00',
    'auto',
    null,
    '2373.60',
    'from the printed weight × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0075-chicken-under-a-brick-with-herb-roasted-potatoes.yaml',
    null,
    0,
    '1 small (3-pound) whole chicken, giblets discarded',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '828.00',
    'auto',
    null,
    '1780.20',
    'from the printed weight × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0134-weeknight-roast-chicken.yaml',
    null,
    2,
    '1 (3½- to 4-pound) whole chicken, giblets removed and discarded',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1035.00',
    'auto',
    null,
    '2225.25',
    'from the printed weight (3½–4 lb, the midpoint) × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0136-crisp-skinned-roast-chicken.yaml',
    null,
    0,
    '1 (3½- to 4-pound) whole chicken, giblets discarded',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1035.00',
    'auto',
    null,
    '2225.25',
    'from the printed weight (3½–4 lb, the midpoint) × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0137-classic-roast-lemon-chicken.yaml',
    null,
    1,
    '1 (3½- to 4-pound) whole chicken, giblets discarded',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1035.00',
    'auto',
    null,
    '2225.25',
    'from the printed weight (3½–4 lb, the midpoint) × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0137-one-hour-broiled-chicken-and-pan-sauce.yaml',
    null,
    0,
    '1 (4-pound) whole chicken, giblets discarded',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1104.00',
    'auto',
    null,
    '2373.60',
    'from the printed weight × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0138-glazed-roast-chicken.yaml',
    null,
    0,
    '1 (6- to 7-pound) whole chicken, giblets discarded',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1794.00',
    'auto',
    null,
    '3857.10',
    'from the printed weight (6–7 lb, the midpoint) × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0139-peruvian-roast-chicken-with-garlic-and-lime.yaml',
    null,
    11,
    '1 (3½- to 4-pound) whole chicken, giblets discarded',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1035.00',
    'auto',
    null,
    '2225.25',
    'from the printed weight (3½–4 lb, the midpoint) × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0143-best-roast-chicken-with-root-vegetables.yaml',
    null,
    0,
    '1 (3½- to 4-pound) whole chicken, giblets discarded',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1035.00',
    'auto',
    null,
    '2225.25',
    'from the printed weight (3½–4 lb, the midpoint) × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0144-crisp-roast-butterflied-chicken-with-rosemary-and-garlic.yaml',
    null,
    3,
    '1 (3½- to 4-pound) whole chicken, giblets discarded',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1035.00',
    'auto',
    null,
    '2225.25',
    'from the printed weight (3½–4 lb, the midpoint) × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0145-high-roast-butterflied-chicken-with-potatoes.yaml',
    null,
    2,
    '1 (3½- to 4-pound) whole chicken, giblets discarded',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1035.00',
    'auto',
    null,
    '2225.25',
    'from the printed weight (3½–4 lb, the midpoint) × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0146-stuffed-roast-butterflied-chicken.yaml',
    null,
    2,
    '1 (5- to 6-pound) whole chicken, giblets discarded',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1518.00',
    'auto',
    null,
    '3263.70',
    'from the printed weight (5–6 lb, the midpoint) × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0453-french-chicken-in-a-pot.yaml',
    null,
    0,
    '1 (4½- to 5-pound) whole chicken, giblets discarded, wings tucked under back',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1311.00',
    'auto',
    null,
    '2818.65',
    'from the printed weight (4½–5 lb, the midpoint) × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0637-grilled-lemon-chicken-with-rosemary.yaml',
    null,
    0,
    '1 (3½- to 4-pound) whole chicken, giblets discarded',
    171052,
    'Chicken, broilers or fryers, meat only, raw',
    '1.000000',
    '738.75',
    'auto',
    null,
    '879.11',
    "from the printed weight (3½–4 lb, the midpoint) × 0.43 edible (USDA ready-to-cook yield) · approximate (skin discarded except the wings; the bird's meat-only yield)",
  ),
  (
    '0639-grill-roasted-whole-chicken.yaml',
    null,
    2,
    '1 (3½- to 4½-pound) whole chicken, giblets discarded',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1104.00',
    'auto',
    null,
    '2373.60',
    'from the printed weight (3½–4½ lb, the midpoint) × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0642-thai-grilled-cornish-game-hens-with-gai-yang-chili-dipping-sauce.yaml',
    null,
    0,
    '4 Cornish game hens (1¼ to 1½ pounds each), giblets discarded',
    171507,
    'Chicken, cornish game hens, meat and skin, raw',
    '1.000000',
    '1344.00',
    'auto',
    null,
    '2688.00',
    '4 × 336 g (USDA edible bird portion)',
  ),
  (
    '1122-roast-chicken-with-quinoa-swiss-chard-and-lime.yaml',
    null,
    2,
    '1 (4-pound) whole chicken, giblets discarded',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1104.00',
    'auto',
    null,
    '2373.60',
    'from the printed weight × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '1142-grilled-chicken-with-adobo-and-sazon.yaml',
    null,
    5,
    '1 (4- to 4½-pound) whole chicken, giblets discarded',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1173.00',
    'auto',
    null,
    '2521.95',
    'from the printed weight (4–4½ lb, the midpoint) × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '1177-multicooker-chicken-in-a-pot-with-lemon-herb-sauce.yaml',
    null,
    7,
    '1 (4-pound) whole chicken, giblets discarded',
    171447,
    'Chicken, broilers or fryers, meat and skin, raw',
    '1.000000',
    '1104.00',
    'auto',
    null,
    '2373.60',
    'from the printed weight × 0.61 edible (USDA ready-to-cook yield)',
  ),
  // 3: the shipped uptake rows, tempeh, the confit, the held salt
  (
    '0690-patatas-bravas.yaml',
    null,
    12,
    '3 cups vegetable oil',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '49.60',
    'auto',
    null,
    '446.40',
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil")',
  ),
  (
    '0706-platanos-maduros-fried-sweet-plantains.yaml',
    null,
    0,
    '3 cups vegetable oil',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '66.27',
    'auto',
    null,
    '596.43',
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 5.5 % of the raw plantains\' weight — derived from USDA SR Legacy 168200 "Plantains, yellow, fried, Latino restaurant")',
  ),
  (
    '0053-crispy-thai-eggplant-salad.yaml',
    null,
    10,
    '2 cups vegetable oil',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '40.82',
    'auto',
    null,
    '367.38',
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw eggplant\'s weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil" (no record for eggplant; read as Fast foods, potato, french fried in vegetable oil))',
  ),
  (
    '0319-crunchy-kettle-potato-chips.yaml',
    null,
    0,
    '2 quarts vegetable oil, for frying',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '49.44',
    'auto',
    null,
    '444.96',
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 10.9 % of the raw potatoes\' weight — derived from USDA SR Legacy 19411 "Snacks, potato chips, plain, salted")',
  ),
  (
    '1105-yeasted-doughnuts.yaml',
    null,
    7,
    '2 quarts vegetable oil for frying',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '139.50',
    'auto',
    null,
    '1255.50',
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 16.72 % of the raw doughnut dough\'s weight — derived from USDA SR Legacy 172758 "Doughnuts, yeast-leavened, glazed, enriched (includes honey buns)")',
  ),
  (
    '1163-struffoli-neapolitan-honey-balls.yaml',
    null,
    7,
    '2 quarts vegetable oil for frying',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '78.16',
    'auto',
    null,
    '703.44',
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 14.15 % of the raw struffoli dough\'s weight — derived from USDA SR Legacy 174990 "Doughnuts, cake-type, plain (includes unsugared, old-fashioned)" by its carbohydrate (no record for struffoli dough; read as a cake doughnut; by its protein 30.62 %; FNDDS 2708024\'s fritter batter reads 23.32 %))',
  ),
  (
    '1194-lumpiang-shanghai-with-seasoned-vinegar.yaml',
    null,
    17,
    '1½ quarts vegetable oil for frying',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '99.34',
    'auto',
    null,
    '894.06',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 7.62 % of the raw lumpia's weight — USDA FNDDS 2708702 recipe: 8 g oil per 104.99 g raw egg roll (no record for lumpia; read as Egg roll, with beef and/or pork))",
  ),
  (
    '0570-falafel.yaml',
    null,
    11,
    '2 quarts vegetable oil for frying',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '85.55',
    'auto',
    null,
    '769.95',
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 21.64 % of the raw falafel mix\'s weight — derived from USDA SR Legacy 172455 "Falafel, home-prepared")',
  ),
  (
    '1193-crispy-tempeh-with-sambal-sauce.yaml',
    null,
    5,
    '1 cup vegetable oil',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '28.00',
    'auto',
    null,
    '252.00',
    'discarded in cooking — only the part the recipe keeps counted',
  ),
  (
    '1077-turkey-thigh-confit-with-citrus-mustard-sauce.yaml',
    null,
    6,
    '6 cups duck fat, chicken fat, or vegetable oil for confit',
    173572,
    'Fat, goose',
    '1.000000',
    '0.00',
    'auto',
    null,
    '0.00',
    'discarded in cooking — counted as 0 g · approximation (counted as Fat, goose)',
  ),
  (
    '1098-fried-yuca.yaml',
    null,
    1,
    '1 teaspoon table salt',
    173468,
    'Salt, table',
    '1.000000',
    null,
    'auto',
    'discarded_medium',
    null,
    null,
  ),
  // the remaining 26 uptake rows (every v68 row whose basis says "only the oil the fried food absorbs": 34, the
  // plan's 27 among them; closer 1, D1)
  (
    '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
    null,
    4,
    '½ cup vegetable oil',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '53.02',
    'auto',
    null,
    '477.18',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  (
    '0116-chicken-schnitzel.yaml',
    null,
    7,
    '2 cups vegetable oil for frying',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '53.02',
    'auto',
    null,
    '477.18',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  (
    '0151-buffalo-wings.yaml',
    null,
    5,
    '1–2 quarts peanut oil, for frying',
    2710187,
    'Peanut oil',
    '0.990000',
    '44.97',
    'auto',
    null,
    '404.73',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.61 % of the raw chicken wings' weight — USDA FNDDS 2706065 recipe: 7 g oil per 105.96 g raw chicken wing)",
  ),
  (
    '0198-crispy-pan-fried-pork-chops.yaml',
    null,
    7,
    '⅔ cup vegetable oil',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '53.02',
    'auto',
    null,
    '477.18',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw pork's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast (no record for pork; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw))",
  ),
  (
    '0255-fish-and-chips.yaml',
    null,
    1,
    '3 quarts plus ¼ cup peanut oil or canola oil',
    2710187,
    'Peanut oil',
    '0.990000',
    '170.78',
    'auto',
    null,
    '1537.02',
    'discarded in cooking — only the oil the fried food absorbs counted ("plus ¼ cup peanut oil or canola oil": the steps rinse it off) · approximation (frying oil absorbed: 15.38 % of the raw cod\'s weight — USDA FNDDS 2706244 recipe: 10 g oil per 65 g raw cod; 6.0 % of the raw potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil")',
  ),
  (
    '0287-easy-salmon-cakes.yaml',
    null,
    11,
    '½ cup vegetable oil',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '37.87',
    'auto',
    null,
    '340.83',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw salmon's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast (no record for salmon; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw))",
  ),
  (
    '0288-maryland-crab-cakes.yaml',
    null,
    9,
    '¼ cup vegetable oil',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '34.88',
    'auto',
    null,
    '313.92',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 7.69 % of the raw crab's weight — USDA FNDDS 2706549 recipe: 5 g oil per 65 g raw crab)",
  ),
  (
    '0304-chicken-fried-steaks.yaml',
    null,
    8,
    '4–5 cups peanut oil',
    2710187,
    'Peanut oil',
    '0.990000',
    '84.11',
    'auto',
    null,
    '756.99',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 9.89 % of the raw beef's weight — USDA FNDDS 2705842 recipe: 9 g oil per 90.99 g raw beef steak)",
  ),
  (
    '0316-classic-french-fries.yaml',
    null,
    1,
    '2 quarts peanut oil',
    2710187,
    'Peanut oil',
    '0.990000',
    '55.11',
    'auto',
    null,
    '495.99',
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil")',
  ),
  (
    '0316-steak-fries.yaml',
    null,
    1,
    '2 quarts peanut oil',
    2710187,
    'Peanut oil',
    '0.990000',
    '68.04',
    'auto',
    null,
    '612.36',
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil")',
  ),
  (
    '0317-easier-french-fries.yaml',
    null,
    1,
    '6 cups peanut oil',
    2710187,
    'Peanut oil',
    '0.990000',
    '68.04',
    'auto',
    null,
    '612.36',
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil")',
  ),
  (
    '0318-thick-cut-sweet-potato-fries.yaml',
    null,
    4,
    '3 cups peanut oil',
    2710187,
    'Peanut oil',
    '0.990000',
    '65.32',
    'auto',
    null,
    '587.88',
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw sweet potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil" (no record for sweet potatoes; read as Fast foods, potato, french fried in vegetable oil))',
  ),
  (
    '0415-best-chicken-parmesan.yaml',
    null,
    19,
    '⅓ cup vegetable oil',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '26.51',
    'auto',
    null,
    '238.59',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  (
    '0464-steak-frites.yaml',
    null,
    9,
    '3 quarts peanut oil',
    2710187,
    'Peanut oil',
    '0.990000',
    '68.04',
    'auto',
    null,
    '612.36',
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw potatoes\' weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil")',
  ),
  (
    '0491-spicy-mexican-shredded-pork-tostadas.yaml',
    null,
    10,
    '¾ cup vegetable oil',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '41.81',
    'auto',
    null,
    '376.29',
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 13.4 % of the raw corn tortillas\' weight — derived from USDA SR Legacy 167525 "Tostada shells, corn")',
  ),
  (
    '0511-shrimp-tempura.yaml',
    null,
    0,
    '3 quarts peanut or vegetable oil',
    2710187,
    'Peanut oil',
    '0.673333',
    '104.64',
    'auto',
    null,
    '941.76',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 15.38 % of the raw shrimp's weight — USDA FNDDS 2706364 recipe: 10 g oil per 65 g raw shrimp)",
  ),
  (
    '0525-orange-flavored-chicken.yaml',
    null,
    16,
    '3 cups peanut or vegetable oil',
    2710187,
    'Peanut oil',
    '0.673333',
    '48.38',
    'auto',
    null,
    '435.42',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 7.11 % of the raw chicken thigh's weight — USDA FNDDS 2706047 recipe: 7 g oil per 98.39 g raw chicken thigh)",
  ),
  (
    '0526-dakgangjeong-korean-fried-chicken-wings.yaml',
    null,
    7,
    '2 quarts vegetable oil',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '44.97',
    'auto',
    null,
    '404.73',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.61 % of the raw chicken wings' weight — USDA FNDDS 2706065 recipe: 7 g oil per 105.96 g raw chicken wing)",
  ),
  (
    '0527-karaage-japanese-fried-chicken-thighs.yaml',
    null,
    8,
    '1 quart vegetable oil for frying',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '48.38',
    'auto',
    null,
    '435.42',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 7.11 % of the raw chicken thigh's weight — USDA FNDDS 2706047 recipe: 7 g oil per 98.39 g raw chicken thigh)",
  ),
  (
    '0672-buffalo-cauliflower-bites.yaml',
    null,
    4,
    '1–2 quarts peanut or vegetable oil',
    2710187,
    'Peanut oil',
    '0.673333',
    '73.30',
    'auto',
    null,
    '659.70',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed — derived: 16.16 % of the raw cauliflower's weight — USDA FNDDS 2710042 recipe: 12 g oil per 39.58 g raw cauliflower, scaled to the recipe's batter (122.16 g of 229.20 g carbohydrate))",
  ),
  (
    '1081-crispy-fish-sandwiches-with-tartar-sauce.yaml',
    null,
    11,
    '2 quarts peanut or vegetable oil for frying',
    2710187,
    'Peanut oil',
    '0.500000',
    '87.20',
    'auto',
    null,
    '784.80',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 15.38 % of the raw haddock's weight — USDA FNDDS 2706258 recipe: 10 g oil per 65 g raw haddock)",
  ),
  (
    '1084-rhode-islandstyle-fried-calamari.yaml',
    null,
    7,
    '2 quarts vegetable oil for frying',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '24.04',
    'auto',
    null,
    '216.36',
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 5.3 % of the raw squid\'s weight — derived from USDA SR Legacy 171982 "Mollusks, squid, mixed species, cooked, fried")',
  ),
  (
    '1123-pastelon-puerto-rican-sweet-plantain-and-picadillo-casserole.yaml',
    null,
    7,
    '¾ cup vegetable oil for frying',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '81.08',
    'auto',
    null,
    '729.72',
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 5.5 % of the raw plantains\' weight — derived from USDA SR Legacy 168200 "Plantains, yellow, fried, Latino restaurant")',
  ),
  (
    '1133-chicken-francese.yaml',
    null,
    8,
    '⅓ cup extra-virgin olive oil for frying',
    748608,
    'Oil, olive, extra virgin',
    '1.000000',
    '26.13',
    'auto',
    null,
    '220.35',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  (
    '1133-chicken-francese.yaml',
    null,
    9,
    '⅓ cup vegetable oil for frying',
    2710180,
    'Vegetable oil, NFS',
    '0.923333',
    '26.89',
    'auto',
    null,
    '242.01',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken breast)",
  ),
  (
    '1137-pakoras-south-asian-spiced-vegetable-fritters.yaml',
    null,
    14,
    '2 quarts canola oil for frying',
    172360,
    'Oil, industrial, canola (partially hydrogenated) oil for deep fat frying',
    '0.888889',
    '40.72',
    'auto',
    null,
    '359.96',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 8.43 % of the raw pakora batter's weight — USDA FNDDS 2710066 recipe: 21 g oil per 249.18 g raw pakora batter)",
  ),
  // 4: every other rind-word line keeps its head
  (
    '0332-pasta-allamatriciana.yaml',
    null,
    0,
    '8 ounces salt pork, rind removed, rinsed thoroughly, and patted dry',
    168287,
    'Pork, cured, salt pork, raw',
    '0.920000',
    '226.80',
    'auto',
    null,
    '1696.43',
    'from 8 ounce',
  ),
  (
    '0299-grown-up-grilled-cheese-sandwiches-with-cheddar-and-shallot.yaml',
    null,
    1,
    '2 ounces Brie cheese, rind removed',
    172177,
    'Cheese, brie',
    '1.000000',
    '56.70',
    'auto',
    null,
    '189.37',
    'from 2 ounce',
  ),
  (
    '0366-creamy-baked-four-cheese-pasta.yaml',
    null,
    3,
    '4 ounces Italian fontina cheese, rind removed, shredded (about 1 cup)',
    170843,
    'Cheese, fontina',
    '0.683333',
    '113.40',
    'auto',
    null,
    '441.12',
    'from 4 ounce',
  ),
  (
    '0263-oven-roasted-salmon.yaml',
    'Tangerine and Ginger Relish',
    0,
    '4 tangerines, rind and pith removed and segments cut into ½-inch pieces (about 1 cup)',
    2709175,
    'Tangerine, raw',
    '0.910000',
    '195.00',
    'auto',
    null,
    '103.35',
    '1 cup · USDA portion',
  ),
  (
    '1134-tartiflette-french-potato-and-cheese-gratin.yaml',
    null,
    0,
    '8 ounces ripe Camembert or Taleggio cheese, rind left on',
    172178,
    'Cheese, camembert',
    '0.683333',
    '226.80',
    'auto',
    null,
    '680.39',
    'from 8 ounce',
  ),
  (
    '0474-black-bean-soup.yaml',
    null,
    1,
    '4 ounces ham steak, trimmed of rind',
    167874,
    'Pork, cured, ham, steak, boneless, extra lean, unheated',
    '0.850000',
    '113.40',
    'auto',
    null,
    '138.35',
    'from 4 ounce',
  ),
  (
    '0457-beef-burgundy.yaml',
    null,
    0,
    '6 ounces salt pork, trimmed of rind and rind reserved, salt pork cut into ¼-inch pieces',
    168287,
    'Pork, cured, salt pork, raw',
    '0.920000',
    '170.10',
    'auto',
    null,
    '1272.33',
    'from 6 ounce',
  ),
  (
    '1120-new-england-fish-chowder.yaml',
    null,
    2,
    '4 ounces salt pork, rind removed, rinsed, and cut into 2 pieces',
    168287,
    'Pork, cured, salt pork, raw',
    '0.920000',
    null,
    'auto',
    'discarded_medium',
    null,
    null,
  ),
  (
    '0456-daube-provencal.yaml',
    null,
    5,
    '5 ounces salt pork, rind removed',
    168287,
    'Pork, cured, salt pork, raw',
    '0.920000',
    '0.00',
    'auto',
    null,
    '0.00',
    'removed and discarded (step 4) — counted as 0 g',
  ),
  // the remaining 13 rind-word lines (raw ∋ 'rind', tamarind included — the full set: 22; closer 1, D1)
  (
    '0315-pinto-beanbeet-burgers.yaml',
    null,
    1,
    '⅔ cup medium-grind bulgur, rinsed',
    170688,
    'Bulgur, dry',
    '1.000000',
    '93.33',
    'auto',
    null,
    '319.20',
    '2/3 cup · USDA portion',
  ),
  (
    '0372-four-cheese-lasagna.yaml',
    null,
    16,
    '8 ounces fontina cheese, rind removed, shredded (about 2 cups)',
    170843,
    'Cheese, fontina',
    '1.000000',
    '226.80',
    'auto',
    null,
    '882.24',
    'from 8 ounce',
  ),
  (
    '0553-pad-thai.yaml',
    null,
    1,
    '2 tablespoons tamarind paste',
    2709269,
    'Tamarind',
    '0.565000',
    '15.00',
    'auto',
    null,
    '35.85',
    '2 tablespoon · USDA portion of "Tamarinds, raw"',
  ),
  (
    '0554-shrimp-pad-thai.yaml',
    null,
    8,
    '3 tablespoons tamarind juice concentrate',
    2709269,
    'Tamarind',
    '0.565000',
    '22.50',
    'auto',
    null,
    '53.78',
    '3 tablespoon · USDA portion of "Tamarinds, raw"',
  ),
  (
    '0591-grill-roasted-beef-short-ribs.yaml',
    'Hoisin-Tamarind Glaze',
    2,
    '¼ cup tamarind paste',
    2709269,
    'Tamarind',
    '0.565000',
    '30.00',
    'auto',
    null,
    '71.70',
    '1/4 cup · USDA portion of "Tamarinds, raw"',
  ),
  (
    '0615-oven-barbecued-spareribs.yaml',
    null,
    10,
    '¼ cup finely ground Lapsang Souchong tea leaves (from about 10 tea bags, or ½ cup loose tea leaves ground to a powder in a spice grinder)',
    168416,
    'Drumstick leaves, raw',
    '0.000000',
    // As the liquid smoke below: the replay's row (byte-equal v68 → v69)
    // weighs 5.25 g on 168416's detail ('1/4 cup · USDA portion', 0 kcal),
    // which the library caches; this DB holds only its hit (a pick below
    // the gate fetches nothing), so no grams and no basis here.
    null,
    'auto',
    null,
    null,
    null,
  ),
  (
    '0628-grilled-stuffed-chicken-breasts-with-prosciutto-and-fontina.yaml',
    null,
    5,
    '2 ounces fontina cheese, rind removed, cut into four 3 by ½-inch sticks',
    170843,
    'Cheese, fontina',
    '1.000000',
    '56.70',
    'auto',
    null,
    '220.56',
    'from 2 ounce',
  ),
  (
    '0679-boston-baked-beans.yaml',
    null,
    0,
    '4 ounces salt pork, trimmed of rind and cut into ½-inch cubes',
    168287,
    'Pork, cured, salt pork, raw',
    '0.920000',
    '113.40',
    'auto',
    null,
    '848.22',
    'from 4 ounce',
  ),
  (
    '0717-tabbouleh.yaml',
    null,
    2,
    '½ cup medium-grind bulgur',
    170688,
    'Bulgur, dry',
    '1.000000',
    '70.00',
    'auto',
    null,
    '239.40',
    '1/2 cup · USDA portion',
  ),
  (
    '1070-vospov-kofte-red-lentil-kofte.yaml',
    null,
    4,
    '1 cup fine-grind bulgur',
    170688,
    'Bulgur, dry',
    '1.000000',
    '140.00',
    'auto',
    null,
    '478.80',
    '1 cup · USDA portion',
  ),
  (
    '1176-red-lentil-kibbeh.yaml',
    null,
    7,
    '1 cup medium-grind bulgur',
    170688,
    'Bulgur, dry',
    '1.000000',
    '140.00',
    'auto',
    null,
    '478.80',
    '1 cup · USDA portion',
  ),
  (
    '1186-ultimate-veggie-burgers.yaml',
    null,
    2,
    '¾ cup medium-grind bulgur, rinsed',
    170688,
    'Bulgur, dry',
    '1.000000',
    '105.00',
    'auto',
    null,
    '359.10',
    '3/4 cup · USDA portion',
  ),
  (
    '1192-gado-gado.yaml',
    null,
    8,
    '1 tablespoon tamarind paste',
    2709269,
    'Tamarind',
    '0.565000',
    '7.50',
    'auto',
    null,
    '17.93',
    '1 tablespoon · USDA portion of "Tamarinds, raw"',
  ),
  // 5: whole, packed, torn, shredded, Thai, sprig and count basil; herbs on other records
  (
    '0029-soupe-au-pistou-provencal-vegetable-soup.yaml',
    null,
    0,
    '¾ cup fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '18.00',
    'auto',
    null,
    '4.14',
    '3/4 cup · USDA portion',
  ),
  (
    '0335-farfalle-with-pesto.yaml',
    null,
    1,
    '2 cups packed fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '48.00',
    'auto',
    null,
    '11.04',
    '2 cup · USDA portion',
  ),
  (
    '0547-thai-style-chicken-with-basil.yaml',
    null,
    0,
    '2 cups tightly packed fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '48.00',
    'auto',
    null,
    '11.04',
    '2 cup · USDA portion',
  ),
  (
    '0059-pasta-salad-with-pesto.yaml',
    null,
    4,
    '3 cups packed fresh basil leaves (about 4 ounces)',
    2709780,
    'Basil, raw',
    '0.910000',
    '113.40',
    'auto',
    null,
    '26.08',
    'from 4 ounce',
  ),
  (
    '0407-eggplant-parmesan.yaml',
    null,
    16,
    '10 fresh basil leaves, torn, for garnish',
    2709780,
    'Basil, raw',
    '0.910000',
    '5.00',
    'auto',
    null,
    '1.15',
    '10 · USDA per-item weight',
  ),
  (
    '0386-deep-dish-pizza-with-tomatoes-mozzarella-and-basil.yaml',
    null,
    11,
    '3 tablespoons shredded fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '9.00',
    'auto',
    null,
    '2.07',
    '3 tablespoon · USDA portion',
  ),
  (
    '0415-best-chicken-parmesan.yaml',
    null,
    20,
    '¼ cup torn fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '6.00',
    'auto',
    null,
    '1.38',
    '1/4 cup · USDA portion',
  ),
  (
    '1189-bruschetta-with-artichoke-hearts-and-parmesan.yaml',
    null,
    4,
    '2 tablespoons finely shredded fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '6.00',
    'auto',
    null,
    '1.38',
    '2 tablespoon · USDA portion',
  ),
  (
    '0011-guay-tiew-tom-yum-goong-thai-hot-and-sour-noodle-soup-with-shrimp.yaml',
    null,
    14,
    '¼ cup fresh Thai basil leaves, torn if large (optional)',
    2709780,
    'Basil, raw',
    '1.000000',
    '6.00',
    'auto',
    null,
    '1.38',
    '1/4 cup · USDA portion · approximation (counted as Basil, raw)',
  ),
  (
    '0053-crispy-thai-eggplant-salad.yaml',
    null,
    13,
    '½ cup fresh Thai basil leaves',
    2709780,
    'Basil, raw',
    '1.000000',
    '12.00',
    'auto',
    null,
    '2.76',
    '1/2 cup · USDA portion · approximation (counted as Basil, raw)',
  ),
  (
    '0010-vietnamese-beef-pho.yaml',
    null,
    16,
    'Sprigs fresh Thai or Italian basil',
    2709780,
    'Basil, raw',
    '1.000000',
    '0.00',
    'auto',
    null,
    '0.00',
    'no amount on the line — counted as 0 g · approximation (counted as Basil, raw)',
  ),
  (
    '0405-ciambotta-italian-vegetable-stew.yaml',
    null,
    15,
    '1 cup shredded fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '24.00',
    'auto',
    null,
    '5.52',
    '1 cup · USDA portion',
  ),
  (
    '0032-creamy-gazpacho-andaluz.yaml',
    null,
    10,
    '2 tablespoons finely minced parsley, chives, or basil leaves',
    2709796,
    'Parsley, raw',
    '0.910000',
    '7.50',
    'auto',
    null,
    '2.70',
    '2 tablespoon · USDA portion',
  ),
  (
    '0240-herb-crusted-pork-roast.yaml',
    null,
    9,
    '⅓ cup fresh parsley or basil leaves',
    2709796,
    'Parsley, raw',
    '0.910000',
    '20.00',
    'auto',
    null,
    '7.20',
    '1/3 cup · USDA portion',
  ),
  (
    '0288-maryland-crab-cakes.yaml',
    null,
    2,
    '1 tablespoon chopped fresh herb, such as cilantro, dill, basil, or parsley',
    170416,
    'Parsley, fresh',
    '1.000000',
    '3.75',
    'auto',
    null,
    '1.35',
    '1 tablespoon · USDA portion · approximation (counted as Parsley, fresh)',
  ),
  (
    '0325-pasta-with-fresh-tomatoes-and-herbs.yaml',
    null,
    1,
    '¼ cup minced fresh herbs, such as basil, parsley, cilantro, mint, oregano, or tarragon',
    170416,
    'Parsley, fresh',
    '1.000000',
    '15.00',
    'auto',
    null,
    '5.40',
    '1/4 cup · USDA portion · approximation (counted as Parsley, fresh)',
  ),
  (
    '0632-jerk-chicken.yaml',
    null,
    14,
    '2 teaspoons dried basil',
    171317,
    'Spices, basil, dried',
    '0.933333',
    '1.38',
    'auto',
    null,
    '3.22',
    '2 teaspoon ≈ 10 mL',
  ),
  // the remaining 14 rows on 2709780 (the full set of the 26 it does not move; closer 1, D1)
  (
    '0315-pinto-beanbeet-burgers.yaml',
    null,
    4,
    '½ cup fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '12.00',
    'auto',
    null,
    '2.76',
    '1/2 cup · USDA portion',
  ),
  (
    '0336-pasta-with-pesto-potatoes-and-green-beans.yaml',
    null,
    5,
    '2 cups fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '48.00',
    'auto',
    null,
    '11.04',
    '2 cup · USDA portion',
  ),
  (
    '0337-pasta-with-pesto-alla-trapanese-tomato-and-almond-pesto.yaml',
    null,
    4,
    '½ cup packed fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '12.00',
    'auto',
    null,
    '2.76',
    '1/2 cup · USDA portion',
  ),
  (
    '0385-thin-crust-whole-wheat-pizza-with-garlic-oil-three-cheeses-and-basil.yaml',
    null,
    14,
    '1 cup fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '24.00',
    'auto',
    null,
    '5.52',
    '1 cup · USDA portion',
  ),
  (
    '0398-ultimate-grilled-pizza.yaml',
    null,
    15,
    '3 tablespoons shredded fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '9.00',
    'auto',
    null,
    '2.07',
    '3 tablespoon · USDA portion',
  ),
  (
    '0429-garlicky-shrimp-tomato-and-white-bean-stew.yaml',
    null,
    10,
    '¼ cup shredded fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '6.00',
    'auto',
    null,
    '1.38',
    '1/4 cup · USDA portion',
  ),
  (
    '0510-goi-cuo-n-vietnamese-summer-rolls.yaml',
    null,
    14,
    '1 cup Thai basil leaves',
    2709780,
    'Basil, raw',
    '1.000000',
    '24.00',
    'auto',
    null,
    '5.52',
    '1 cup · USDA portion · approximation (counted as Basil, raw)',
  ),
  (
    '0526-san-bei-ji-three-cup-chicken.yaml',
    null,
    11,
    '1 cup Thai basil leaves, large leaves halved lengthwise',
    2709780,
    'Basil, raw',
    '1.000000',
    '24.00',
    'auto',
    null,
    '5.52',
    '1 cup · USDA portion · approximation (counted as Basil, raw)',
  ),
  (
    '0548-thai-green-curry-with-chicken-broccoli-and-mushrooms.yaml',
    null,
    10,
    '½ cup loosely packed fresh basil leaves',
    2709780,
    'Basil, raw',
    '0.910000',
    '12.00',
    'auto',
    null,
    '2.76',
    '1/2 cup · USDA portion',
  ),
  (
    '0560-banh-xeo-sizzling-vietnamese-crepes.yaml',
    null,
    7,
    '1 cup fresh Thai basil leaves',
    2709780,
    'Basil, raw',
    '1.000000',
    '24.00',
    'auto',
    null,
    '5.52',
    '1 cup · USDA portion · approximation (counted as Basil, raw)',
  ),
  (
    '0680-fava-beans-with-artichokes-asparagus-and-peas.yaml',
    null,
    11,
    '2 tablespoons shredded fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '6.00',
    'auto',
    null,
    '1.38',
    '2 tablespoon · USDA portion',
  ),
  (
    '1086-pasta-with-burst-cherry-tomato-sauce-and-fried-caper-crumbs.yaml',
    null,
    17,
    '1 cup fresh basil leaves, torn if large',
    2709780,
    'Basil, raw',
    '0.910000',
    '24.00',
    'auto',
    null,
    '5.52',
    '1 cup · USDA portion',
  ),
  (
    '1088-spinach-and-ricotta-gnudi-with-tomato-butter-sauce.yaml',
    null,
    15,
    '2 tablespoons shredded fresh basil',
    2709780,
    'Basil, raw',
    '0.910000',
    '6.00',
    'auto',
    null,
    '1.38',
    '2 tablespoon · USDA portion',
  ),
  (
    '1193-crispy-tempeh-with-sambal-sauce.yaml',
    null,
    9,
    '1½ cups fresh Thai or Italian basil leaves',
    2709780,
    'Basil, raw',
    '1.000000',
    '36.00',
    'auto',
    null,
    '8.28',
    '1 1/2 cup · USDA portion · approximation (counted as Basil, raw)',
  ),
  // 6: every other 167587 row (weight lines)
  (
    '0885-fluffy-yellow-layer-cake-with-milk-chocolate-frosting.yaml',
    null,
    16,
    '8 ounces milk chocolate, melted and cooled slightly',
    167587,
    'Candies, milk chocolate',
    '1.000000',
    '226.80',
    'auto',
    null,
    '1213.36',
    'from 8 ounce',
  ),
  (
    '0889-chocolate-sheet-cake-with-easy-chocolate-frosting.yaml',
    null,
    13,
    '10 ounces milk chocolate, chopped',
    167587,
    'Candies, milk chocolate',
    '1.000000',
    '283.50',
    'auto',
    null,
    '1516.70',
    'from 10 ounce',
  ),
  (
    '0890-simple-chocolate-sheet-cake-with-milk-chocolate-frosting.yaml',
    null,
    10,
    '1 pound milk chocolate, chopped',
    167587,
    'Candies, milk chocolate',
    '1.000000',
    '453.59',
    'auto',
    null,
    '2426.72',
    'from 1 pound',
  ),
  (
    '1114-browned-butter-blondies.yaml',
    null,
    9,
    '½ cup (3 ounces) milk chocolate chips',
    167587,
    'Candies, milk chocolate',
    '1.000000',
    '85.05',
    'auto',
    null,
    '455.01',
    'from 3 ounce',
  ),
  (
    '1168-milk-chocolate-cremeux-tart.yaml',
    null,
    10,
    '12 ounces milk chocolate, chopped fine',
    167587,
    'Candies, milk chocolate',
    '1.000000',
    '340.19',
    'auto',
    null,
    '1820.04',
    'from 12 ounce',
  ),
  // 7: liquid smoke on 167682; 'sugar'-density rows
  (
    '0129-indoor-pulled-chicken.yaml',
    null,
    3,
    '1 tablespoon liquid smoke, divided',
    167682,
    'Pectin, liquid',
    '0.175000',
    // The replay's row (byte-equal v68 → v69) weighs 4.73 g on 167682's
    // detail, which the library caches; this DB holds only its hit (a pick
    // below the gate fetches nothing), so no grams and no basis here.
    null,
    'auto',
    'partial_pour_away',
    null,
    null,
  ),
  (
    '0985-fresh-strawberry-pie.yaml',
    null,
    8,
    '1 tablespoon sugar',
    746784,
    'Sugars, granulated',
    '0.950000',
    '12.57',
    'auto',
    null,
    '48.39',
    '1 tablespoon ≈ 15 mL',
  ),
  (
    '0944-raspberry-sorbet.yaml',
    null,
    4,
    '½ cup (3½ ounces) plus 2 tablespoons sugar',
    746784,
    'Sugars, granulated',
    '0.950000',
    '124.36',
    'auto',
    null,
    '478.79',
    'from 3 1/2 ounce + 2 tablespoons sugar',
  ),
  (
    '0010-vietnamese-beef-pho.yaml',
    null,
    6,
    '2 tablespoons sugar, plus extra for seasoning',
    746784,
    'Sugars, granulated',
    '0.950000',
    '25.14',
    'auto',
    null,
    '96.78',
    '2 tablespoon ≈ 30 mL',
  ),
  (
    '0011-guay-tiew-tom-yum-goong-thai-hot-and-sour-noodle-soup-with-shrimp.yaml',
    null,
    7,
    '1 tablespoon sugar, plus extra for seasoning',
    746784,
    'Sugars, granulated',
    '0.950000',
    '12.57',
    'auto',
    null,
    '48.39',
    '1 tablespoon ≈ 15 mL',
  ),
];

/// Every 'sugar'-density row M70 must not move — the 234 v68 rows whose
/// gram source is `density` and whose line names sugar (the five pectin
/// lines aside): (file, section, position, raw, the row's record, grams).
/// Their 195 recipes are not computed whole here: the pin reads the grams
/// reader the compute asks ([lineGrams] on the row's record), where a
/// density key ('fruit pectin', 'sure-jell') would reach (closer 1, D1).
const List<(String, String?, int, String, int, String)> _sugarDensity = [
  (
    '0010-vietnamese-beef-pho.yaml',
    null,
    6,
    '2 tablespoons sugar, plus extra for seasoning',
    746784,
    '25.14',
  ),
  (
    '0011-guay-tiew-tom-yum-goong-thai-hot-and-sour-noodle-soup-with-shrimp.yaml',
    null,
    7,
    '1 tablespoon sugar, plus extra for seasoning',
    746784,
    '12.57',
  ),
  (
    '0011-guay-tiew-tom-yum-goong-thai-hot-and-sour-noodle-soup-with-shrimp.yaml',
    'Nam Prik Pao (Thai Chili Jam)',
    4,
    '2 tablespoons packed brown sugar',
    168833,
    '27.50',
  ),
  (
    '0013-ultimate-cream-of-tomato-soup.yaml',
    null,
    1,
    '1½ tablespoons dark brown sugar',
    168833,
    '20.63',
  ),
  (
    '0014-creamless-creamy-tomato-soup.yaml',
    null,
    7,
    '1 tablespoon brown sugar',
    168833,
    '13.75',
  ),
  (
    '0019-butternut-squash-soup.yaml',
    null,
    6,
    '1 teaspoon dark brown sugar',
    168833,
    '4.58',
  ),
  (
    '0020-sweet-potato-soup.yaml',
    null,
    5,
    '1 tablespoon packed brown sugar',
    168833,
    '13.75',
  ),
  (
    '0021-super-greens-soup-with-lemon-tarragon-cream.yaml',
    null,
    7,
    '¾ teaspoon light brown sugar',
    168833,
    '3.44',
  ),
  (
    '0046-mango-orange-and-jicama-salad.yaml',
    null,
    0,
    '3 tablespoons sugar',
    746784,
    '37.71',
  ),
  (
    '0056-austrian-style-potato-salad.yaml',
    null,
    3,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0072-skillet-tamale-pie.yaml',
    null,
    13,
    '3 tablespoons sugar',
    746784,
    '37.71',
  ),
  (
    '0104-brown-rice-bowls-with-vegetables-and-salmon.yaml',
    null,
    4,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0129-indoor-pulled-chicken.yaml',
    'Lexington Vinegar Barbecue Sauce',
    3,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0129-indoor-pulled-chicken.yaml',
    'South Carolina Mustard Barbecue Sauce',
    2,
    '¼ cup packed brown sugar',
    168833,
    '55.01',
  ),
  (
    '0131-spice-rubbed-picnic-chicken.yaml',
    null,
    1,
    '3 tablespoons brown sugar',
    168833,
    '41.26',
  ),
  (
    '0139-peruvian-roast-chicken-with-garlic-and-lime.yaml',
    null,
    6,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0151-buffalo-wings.yaml',
    null,
    3,
    '1 tablespoon packed dark brown sugar',
    168833,
    '13.75',
  ),
  (
    '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml',
    'Golden Cornbread',
    6,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0178-cranberry-chutney-with-apples-and-crystallized-ginger.yaml',
    null,
    6,
    '1 cup packed brown sugar',
    168833,
    '220.03',
  ),
  (
    '0203-skillet-barbecued-pork-chops.yaml',
    null,
    4,
    '1 tablespoon brown sugar',
    168833,
    '13.75',
  ),
  (
    '0203-skillet-barbecued-pork-chops.yaml',
    null,
    14,
    '1 tablespoon brown sugar',
    168833,
    '13.75',
  ),
  (
    '0207-deviled-pork-chops.yaml',
    null,
    4,
    '2 teaspoons packed brown sugar',
    168833,
    '9.17',
  ),
  (
    '0223-onion-braised-beef-brisket.yaml',
    null,
    4,
    '1 tablespoon brown sugar',
    168833,
    '13.75',
  ),
  (
    '0234-pan-seared-oven-roasted-pork-tenderloin.yaml',
    'Garlicky Lime Sauce with Cilantro',
    4,
    '2 teaspoons light brown sugar',
    168833,
    '9.17',
  ),
  (
    '0235-maple-glazed-pork-tenderloin.yaml',
    null,
    7,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0244-slow-roasted-bone-in-pork-rib-roast.yaml',
    null,
    1,
    '2 tablespoons packed dark brown sugar',
    168833,
    '27.50',
  ),
  (
    '0246-slow-roasted-pork-shoulder-with-peach-sauce.yaml',
    null,
    2,
    '⅓ cup packed light brown sugar',
    168833,
    '73.34',
  ),
  (
    '0248-crispy-slow-roasted-pork-belly.yaml',
    null,
    2,
    '2 tablespoons packed dark brown sugar',
    168833,
    '27.50',
  ),
  (
    '0248-crispy-slow-roasted-pork-belly.yaml',
    null,
    6,
    '¼ cup packed dark brown sugar',
    168833,
    '55.01',
  ),
  (
    '0249-roast-fresh-ham.yaml',
    'Cider and Brown Sugar Glaze',
    1,
    '2 cups packed brown sugar',
    168833,
    '440.05',
  ),
  (
    '0249-roast-fresh-ham.yaml',
    'Spicy Pineapple-Ginger Glaze',
    1,
    '2 cups packed brown sugar',
    168833,
    '440.05',
  ),
  (
    '0249-roast-fresh-ham.yaml',
    'Coca-Cola Glaze with Lime and Jalapeño',
    2,
    '2 cups packed brown sugar',
    168833,
    '440.05',
  ),
  (
    '0249-roast-fresh-ham.yaml',
    'Orange, Cinnamon, and Star Anise Glaze',
    1,
    '2 cups packed brown sugar',
    168833,
    '440.05',
  ),
  (
    '0251-glazed-spiral-sliced-ham.yaml',
    'Cherry-Port Glaze',
    2,
    '1 cup packed dark brown sugar',
    168833,
    '220.03',
  ),
  (
    '0262-glazed-salmon.yaml',
    null,
    0,
    '1 teaspoon light brown sugar',
    168833,
    '4.58',
  ),
  (
    '0262-glazed-salmon.yaml',
    'Pomegranate-Balsamic Glaze',
    0,
    '3 tablespoons light brown sugar',
    168833,
    '41.26',
  ),
  (
    '0262-glazed-salmon.yaml',
    'Hoisin-Ginger Glaze',
    3,
    '2 tablespoons packed light brown sugar',
    168833,
    '27.50',
  ),
  (
    '0262-glazed-salmon.yaml',
    'Orange-Miso Glaze',
    2,
    '1 tablespoon light brown sugar',
    168833,
    '13.75',
  ),
  (
    '0262-glazed-salmon.yaml',
    'Soy-Mustard Glaze',
    0,
    '3 tablespoons light brown sugar',
    168833,
    '41.26',
  ),
  (
    '0303-cincinnati-chili.yaml',
    null,
    16,
    '2 teaspoons dark brown sugar',
    168833,
    '9.17',
  ),
  (
    '0305-glazed-all-beef-meatloaf.yaml',
    null,
    21,
    '3 tablespoons light brown sugar',
    168833,
    '41.26',
  ),
  (
    '0306-meatloaf-with-brown-sugarketchup-glaze.yaml',
    null,
    1,
    '¼ cup brown sugar',
    168833,
    '55.01',
  ),
  (
    '0307-turkey-meatloaf-with-ketchupbrown-sugar-glaze.yaml',
    null,
    15,
    '¼ cup packed brown sugar',
    168833,
    '55.01',
  ),
  (
    '0312-juicy-pub-style-burgers.yaml',
    'Pub-Style Burger Sauce',
    2,
    '1 tablespoon dark brown sugar',
    168833,
    '13.75',
  ),
  (
    '0313-classic-sloppy-joes.yaml',
    null,
    7,
    '2 teaspoons packed brown sugar, plus extra for seasoning',
    168833,
    '9.17',
  ),
  (
    '0398-ultimate-grilled-pizza.yaml',
    null,
    1,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0438-french-onion-and-bacon-tart.yaml',
    null,
    1,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  ('0439-pissaladiere.yaml', null, 7, '1 teaspoon brown sugar', 168833, '4.58'),
  (
    '0442-mushroom-and-leek-galette-with-gorgonzola.yaml',
    null,
    2,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  ('0457-beef-burgundy.yaml', null, 22, '1 tablespoon sugar', 746784, '12.57'),
  (
    '0458-slow-cooker-beef-burgundy.yaml',
    null,
    17,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0459-modern-beef-burgundy.yaml',
    null,
    6,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  ('0475-tamales.yaml', null, 7, '1 tablespoon sugar', 746784, '12.57'),
  ('0476-beef-empanadas.yaml', null, 17, '1 tablespoon sugar', 746784, '12.57'),
  (
    '0478-ground-beef-tacos.yaml',
    null,
    13,
    '1 teaspoon brown sugar',
    168833,
    '4.58',
  ),
  (
    '0482-tinga-de-pollo-shredded-chicken-tacos.yaml',
    null,
    9,
    '½ teaspoon brown sugar',
    168833,
    '2.29',
  ),
  (
    '0484-grilled-chicken-fajitas.yaml',
    null,
    6,
    '1½ teaspoons packed brown sugar',
    168833,
    '6.88',
  ),
  (
    '0512-vegetable-bibimbap-with-nurungji.yaml',
    null,
    1,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0512-vegetable-bibimbap-with-nurungji.yaml',
    null,
    16,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0515-beef-satay.yaml',
    null,
    2,
    '¼ cup packed dark brown sugar',
    168833,
    '55.01',
  ),
  (
    '0515-beef-satay.yaml',
    'Spicy Peanut Dipping Sauce',
    5,
    '1 tablespoon dark brown sugar',
    168833,
    '13.75',
  ),
  (
    '0516-negimaki-japanese-grilled-steak-and-scallion-rolls.yaml',
    null,
    2,
    '3 tablespoons sugar',
    746784,
    '37.71',
  ),
  (
    '0517-thai-style-chicken-soup.yaml',
    null,
    7,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0519-sesame-noodles-with-shredded-chicken.yaml',
    null,
    4,
    '2 tablespoons light brown sugar',
    168833,
    '27.50',
  ),
  (
    '0520-yakisoba-japanese-stir-fried-noodles-with-beef.yaml',
    null,
    5,
    '1½ tablespoons packed brown sugar',
    168833,
    '20.63',
  ),
  (
    '0523-nasi-goreng-indonesian-style-fried-rice.yaml',
    null,
    3,
    '2 tablespoons dark brown sugar',
    168833,
    '27.50',
  ),
  (
    '0525-orange-flavored-chicken.yaml',
    null,
    2,
    '½ cup packed dark brown sugar',
    168833,
    '110.01',
  ),
  (
    '0526-dakgangjeong-korean-fried-chicken-wings.yaml',
    null,
    4,
    '3 tablespoons sugar',
    746784,
    '37.71',
  ),
  (
    '0526-san-bei-ji-three-cup-chicken.yaml',
    null,
    2,
    '1 tablespoon packed brown sugar',
    168833,
    '13.75',
  ),
  (
    '0528-gongbao-jiding-sichuan-kung-pao-chicken.yaml',
    null,
    6,
    '1 tablespoon packed dark brown sugar',
    168833,
    '13.75',
  ),
  (
    '0531-stir-fried-beef-and-broccoli-with-oyster-sauce.yaml',
    null,
    3,
    '1 tablespoon light brown sugar',
    168833,
    '13.75',
  ),
  (
    '0532-beef-stir-fry-with-bell-peppers-and-black-pepper-sauce.yaml',
    null,
    6,
    '2½ teaspoons packed light brown sugar',
    168833,
    '11.46',
  ),
  (
    '0533-teriyaki-stir-fried-beef-with-green-beans-and-shiitakes.yaml',
    null,
    2,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0538-stir-fried-pork-eggplant-and-onion-with-garlic-and-black-pepper.yaml',
    null,
    2,
    '2½ tablespoons light brown sugar',
    168833,
    '34.38',
  ),
  (
    '0540-sichuan-stir-fried-pork-in-garlic-sauce.yaml',
    null,
    1,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0544-stir-fried-shrimp-with-snow-peas-and-red-bell-pepper-in-hot-and-sour-sauce.yaml',
    null,
    5,
    '3 tablespoons sugar',
    746784,
    '37.71',
  ),
  (
    '0546-stir-fried-portobellos-with-ginger-oyster-sauce.yaml',
    null,
    2,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0547-thai-style-chicken-with-basil.yaml',
    null,
    5,
    '1 tablespoon sugar, plus extra for serving',
    746784,
    '12.57',
  ),
  (
    '0548-thai-green-curry-with-chicken-broccoli-and-mushrooms.yaml',
    null,
    3,
    '2 tablespoons brown sugar',
    168833,
    '27.50',
  ),
  (
    '0552-stir-fried-thai-style-beef-with-chiles-and-shallots.yaml',
    null,
    3,
    '1 tablespoon light brown sugar',
    168833,
    '13.75',
  ),
  (
    '0552-stir-fried-thai-style-beef-with-chiles-and-shallots.yaml',
    null,
    7,
    '1 teaspoon light brown sugar',
    168833,
    '4.58',
  ),
  ('0553-pad-thai.yaml', null, 3, '3 tablespoons sugar', 746784, '37.71'),
  (
    '0553-thai-style-stir-fried-noodles-with-chicken-and-broccolini.yaml',
    null,
    8,
    '2 tablespoons packed dark brown sugar',
    168833,
    '27.50',
  ),
  (
    '0558-vietnamese-style-caramel-chicken-with-broccoli.yaml',
    null,
    2,
    '7 tablespoons sugar',
    746784,
    '87.98',
  ),
  ('0559-bun-cha.yaml', null, 7, '3 tablespoons sugar', 746784, '37.71'),
  (
    '0560-banh-xeo-sizzling-vietnamese-crepes.yaml',
    null,
    0,
    '3 tablespoons sugar, divided',
    746784,
    '37.71',
  ),
  (
    '0565-murgh-makhani-indian-butter-chicken.yaml',
    null,
    11,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0583-grilled-steak-tips.yaml',
    'Southwestern Marinade',
    3,
    '1 tablespoon packed dark brown sugar',
    168833,
    '13.75',
  ),
  (
    '0583-grilled-steak-tips.yaml',
    'Garlic, Ginger, and Soy Marinade',
    3,
    '2 tablespoons packed dark brown sugar',
    168833,
    '27.50',
  ),
  (
    '0587-grilled-steak-with-new-mexican-chile-rub.yaml',
    null,
    11,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0591-grill-roasted-beef-short-ribs.yaml',
    null,
    1,
    '1 tablespoon packed brown sugar',
    168833,
    '13.75',
  ),
  (
    '0591-grill-roasted-beef-short-ribs.yaml',
    'Mustard Glaze',
    2,
    '¼ cup packed brown sugar',
    168833,
    '55.01',
  ),
  (
    '0591-grill-roasted-beef-short-ribs.yaml',
    'Blackberry Glaze',
    3,
    '2 tablespoons packed brown sugar',
    168833,
    '27.50',
  ),
  (
    '0595-barbecued-whole-beef-brisket-with-spicy-chili-rub.yaml',
    null,
    4,
    '2 tablespoons dark brown sugar',
    168833,
    '27.50',
  ),
  (
    '0595-barbecued-whole-beef-brisket-with-spicy-chili-rub.yaml',
    null,
    5,
    '1 tablespoon granulated sugar',
    746784,
    '12.57',
  ),
  (
    '0598-grill-smoked-pork-chops.yaml',
    null,
    6,
    '1 tablespoon packed light brown sugar',
    168833,
    '13.75',
  ),
  (
    '0598-grilled-pork-chops.yaml',
    'Basic Spice Rub for Pork Chops',
    3,
    '2 teaspoons packed brown sugar',
    168833,
    '9.17',
  ),
  (
    '0601-grilled-glazed-pork-tenderloin-roast.yaml',
    'Satay Glaze',
    5,
    '¼ cup packed dark brown sugar',
    168833,
    '55.01',
  ),
  (
    '0603-grilled-stuffed-pork-tenderloin.yaml',
    null,
    0,
    '4 teaspoons packed dark brown sugar',
    168833,
    '18.34',
  ),
  (
    '0604-grilled-pork-loin-with-apple-cranberry-filling.yaml',
    null,
    2,
    '¾ cup packed light brown sugar',
    168833,
    '165.02',
  ),
  (
    '0606-smoked-pork-loin-with-dried-fruit-chutney.yaml',
    null,
    0,
    '½ cup packed light brown sugar',
    168833,
    '110.01',
  ),
  (
    '0606-smoked-pork-loin-with-dried-fruit-chutney.yaml',
    null,
    10,
    '3 tablespoons packed light brown sugar',
    168833,
    '41.26',
  ),
  (
    '0607-grill-roasted-bone-in-pork-rib-roast.yaml',
    'Orange Salsa with Cuban Flavors',
    6,
    '2 teaspoons packed brown sugar',
    168833,
    '9.17',
  ),
  (
    '0609-barbecued-pulled-pork.yaml',
    'Dry Rub for Barbecue',
    3,
    '2 tablespoons packed dark brown sugar',
    168833,
    '27.50',
  ),
  (
    '0609-barbecued-pulled-pork.yaml',
    'Dry Rub for Barbecue',
    6,
    '1 tablespoon granulated sugar',
    746784,
    '12.57',
  ),
  (
    '0609-barbecued-pulled-pork.yaml',
    'Eastern North Carolina Barbecue Sauce',
    2,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0610-smoky-pulled-pork-on-a-gas-grill.yaml',
    null,
    3,
    '2 teaspoons packed light brown sugar',
    168833,
    '9.17',
  ),
  (
    '0610-smoky-pulled-pork-on-a-gas-grill.yaml',
    null,
    10,
    '2 teaspoons packed light brown sugar',
    168833,
    '9.17',
  ),
  (
    '0612-sweet-and-tangy-grilled-country-style-pork-ribs.yaml',
    null,
    0,
    '4 teaspoons packed brown sugar',
    168833,
    '18.34',
  ),
  (
    '0613-kansas-city-sticky-ribs.yaml',
    null,
    1,
    '2 tablespoons brown sugar',
    168833,
    '27.50',
  ),
  (
    '0614-memphis-style-barbecued-spareribs.yaml',
    'Spice Rub',
    1,
    '2 tablespoons packed light brown sugar',
    168833,
    '27.50',
  ),
  (
    '0615-oven-barbecued-spareribs.yaml',
    null,
    3,
    '3 tablespoons packed brown sugar',
    168833,
    '41.26',
  ),
  (
    '0616-barbecued-baby-back-ribs.yaml',
    null,
    6,
    '1½ teaspoons packed dark brown sugar',
    168833,
    '6.88',
  ),
  (
    '0617-grilled-glazed-baby-back-ribs.yaml',
    'Lime Glaze',
    2,
    '¼ cup packed brown sugar',
    168833,
    '55.01',
  ),
  (
    '0618-texas-style-barbecued-beef-ribs.yaml',
    null,
    9,
    '2 tablespoons packed brown sugar',
    168833,
    '27.50',
  ),
  (
    '0618-texas-style-barbecued-beef-ribs.yaml',
    null,
    12,
    '3 tablespoons packed brown sugar',
    168833,
    '41.26',
  ),
  (
    '0620-grilled-lamb-kebabs.yaml',
    'Sweet Curry Marinade with Buttermilk',
    3,
    '1 tablespoon packed brown sugar',
    168833,
    '13.75',
  ),
  (
    '0621-grilled-beef-satay.yaml',
    null,
    1,
    '3 tablespoons packed dark brown sugar',
    168833,
    '41.26',
  ),
  (
    '0621-grilled-beef-satay.yaml',
    null,
    12,
    '2 tablespoons packed dark brown sugar',
    168833,
    '27.50',
  ),
  (
    '0627-grilled-glazed-bone-in-chicken-breasts.yaml',
    'Soy-Ginger Glaze',
    5,
    '3 tablespoons sugar',
    746784,
    '37.71',
  ),
  (
    '0630-grilled-spice-rubbed-chicken-drumsticks.yaml',
    'Barbecue Spice Rub',
    0,
    '3 tablespoons packed brown sugar',
    168833,
    '41.26',
  ),
  (
    '0630-grilled-spice-rubbed-chicken-drumsticks.yaml',
    'Jerk-Style Spice Rub',
    3,
    '2 tablespoons packed brown sugar',
    168833,
    '27.50',
  ),
  (
    '0631-peri-peri-grilled-chicken.yaml',
    null,
    6,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0632-jerk-chicken.yaml',
    null,
    12,
    '1 tablespoon packed brown sugar',
    168833,
    '13.75',
  ),
  (
    '0633-sweet-and-tangy-barbecued-chicken.yaml',
    null,
    0,
    '2 tablespoons packed dark brown sugar',
    168833,
    '27.50',
  ),
  (
    '0636-charcoal-grilled-barbecued-chicken-kebabs.yaml',
    null,
    6,
    '1 tablespoon packed light brown sugar',
    168833,
    '13.75',
  ),
  (
    '0641-grill-roasted-cornish-game-hens.yaml',
    null,
    2,
    '2 tablespoons packed brown sugar',
    168833,
    '27.50',
  ),
  (
    '0641-grill-roasted-cornish-game-hens.yaml',
    'Barbecue Glaze',
    1,
    '2 tablespoons brown sugar',
    168833,
    '27.50',
  ),
  (
    '0642-thai-grilled-cornish-game-hens-with-gai-yang-chili-dipping-sauce.yaml',
    null,
    3,
    '¼ cup packed light brown sugar',
    168833,
    '55.01',
  ),
  (
    '0646-grill-smoked-salmon.yaml',
    null,
    0,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0666-stir-fried-asparagus-with-shiitake-mushrooms.yaml',
    null,
    3,
    '2 teaspoons packed brown sugar',
    168833,
    '9.17',
  ),
  (
    '0667-beets-with-lemon-and-almonds.yaml',
    null,
    4,
    '1 tablespoon packed light brown sugar',
    168833,
    '13.75',
  ),
  ('0671-glazed-carrots.yaml', null, 2, '3 tablespoons sugar', 746784, '37.71'),
  (
    '0672-buffalo-cauliflower-bites.yaml',
    null,
    2,
    '1 tablespoon packed dark brown sugar',
    168833,
    '13.75',
  ),
  (
    '0678-new-england-baked-beans.yaml',
    null,
    5,
    '2 tablespoons packed dark brown sugar',
    168833,
    '27.50',
  ),
  (
    '0695-mashed-potatoes-with-blue-cheese-and-port-caramelized-onions.yaml',
    null,
    2,
    '½ teaspoon light brown sugar',
    168833,
    '2.29',
  ),
  (
    '0707-quick-roasted-acorn-squash-with-brown-sugar.yaml',
    null,
    3,
    '3 tablespoons dark brown sugar',
    168833,
    '41.26',
  ),
  (
    '0719-spiced-pecans-with-rum-glaze.yaml',
    null,
    1,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0719-spiced-pecans-with-rum-glaze.yaml',
    null,
    9,
    '1 teaspoon light or dark brown sugar',
    168833,
    '4.58',
  ),
  ('0744-easy-pancakes.yaml', null, 1, '3 tablespoons sugar', 746784, '37.71'),
  (
    '0745-blueberry-pancakes.yaml',
    null,
    3,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0747-100-percent-whole-wheat-pancakes.yaml',
    null,
    1,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0748-german-apple-pancake.yaml',
    null,
    1,
    '1 tablespoon granulated sugar',
    746784,
    '12.57',
  ),
  (
    '0750-easy-buttermilk-waffles.yaml',
    null,
    2,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0751-french-toast.yaml',
    null,
    3,
    '3 tablespoons light brown sugar',
    168833,
    '41.26',
  ),
  ('0751-yeasted-waffles.yaml', null, 3, '1 tablespoon sugar', 746784, '12.57'),
  (
    '0752-everyday-french-toast.yaml',
    null,
    2,
    '2 teaspoons packed brown sugar',
    168833,
    '9.17',
  ),
  (
    '0764-savory-corn-muffins.yaml',
    null,
    8,
    '3 tablespoons sugar',
    746784,
    '37.71',
  ),
  (
    '0765-cranberry-pecan-muffins.yaml',
    null,
    1,
    '1 tablespoon packed light brown sugar',
    168833,
    '13.75',
  ),
  (
    '0765-cranberry-pecan-muffins.yaml',
    null,
    2,
    '1 tablespoon plus 1 teaspoon granulated sugar',
    746784,
    '16.57',
  ),
  (
    '0765-cranberry-pecan-muffins.yaml',
    null,
    15,
    '1 tablespoon confectioners’ sugar',
    169656,
    '7.54',
  ),
  (
    '0766-quick-cinnamon-buns-with-buttermilk-icing.yaml',
    null,
    8,
    '2 tablespoons granulated sugar',
    746784,
    '25.14',
  ),
  (
    '0769-perfect-sticky-buns.yaml',
    null,
    6,
    '3 tablespoons granulated sugar',
    746784,
    '37.71',
  ),
  (
    '0784-ultimate-flaky-buttermilk-biscuits.yaml',
    null,
    1,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0785-zucchini-bread.yaml',
    null,
    13,
    '1 tablespoon granulated sugar',
    746784,
    '12.57',
  ),
  (
    '0786-irish-soda-bread.yaml',
    null,
    2,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0789-fresh-corn-cornbread.yaml',
    null,
    2,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0790-potato-burger-buns.yaml',
    null,
    3,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0791-fluffy-dinner-rolls.yaml',
    null,
    6,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0834-sables-french-butter-cookies.yaml',
    null,
    7,
    '4 teaspoons turbinado sugar',
    170674,
    '16.76',
  ),
  (
    '0846-cream-cheese-brownies.yaml',
    null,
    2,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0849-key-lime-bars.yaml',
    null,
    1,
    '3 tablespoons brown sugar',
    168833,
    '41.26',
  ),
  (
    '0851-baklava.yaml',
    null,
    11,
    '2 tablespoons granulated sugar',
    746784,
    '25.14',
  ),
  (
    '0872-strawberry-cream-cake.yaml',
    null,
    9,
    '4–6 tablespoons sugar',
    746784,
    '62.84',
  ),
  (
    '0899-bittersweet-chocolate-roulade.yaml',
    'Espresso-Mascarpone Cream',
    2,
    '6 tablespoons confectioners’ sugar',
    169656,
    '45.25',
  ),
  (
    '0903-triple-chocolate-mousse-cake.yaml',
    null,
    11,
    '1 tablespoon granulated sugar',
    746784,
    '12.57',
  ),
  (
    '0912-new-york-cheesecake.yaml',
    null,
    2,
    '3 tablespoons sugar',
    746784,
    '37.71',
  ),
  (
    '0914-light-new-york-cheesecake.yaml',
    null,
    2,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0915-spiced-pumpkin-cheesecake.yaml',
    null,
    2,
    '3 tablespoons sugar',
    746784,
    '37.71',
  ),
  (
    '0916-lemon-cheesecake.yaml',
    null,
    2,
    '3 tablespoons sugar',
    746784,
    '37.71',
  ),
  (
    '0922-classic-bread-pudding.yaml',
    null,
    0,
    '2 tablespoons light brown sugar',
    168833,
    '27.50',
  ),
  (
    '0923-chocolate-hazelnut-slow-cooker-bread-pudding.yaml',
    null,
    9,
    '2 tablespoons light brown sugar',
    168833,
    '27.50',
  ),
  ('0925-panna-cotta.yaml', null, 4, '6 tablespoons sugar', 746784, '75.41'),
  (
    '0927-classic-creme-brulee.yaml',
    null,
    5,
    '8–12 teaspoons turbinado or Demerara sugar',
    170674,
    '41.90',
  ),
  (
    '0928-sous-vide-creme-brulee.yaml',
    null,
    5,
    '4 teaspoons turbinado or Demerara sugar',
    170674,
    '16.76',
  ),
  (
    '0930-chocolate-pots-de-creme.yaml',
    null,
    2,
    '5 tablespoons sugar',
    746784,
    '62.84',
  ),
  (
    '0932-dark-chocolate-mousse.yaml',
    null,
    6,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0934-chocolate-semifreddo.yaml',
    null,
    4,
    '5 tablespoons sugar',
    746784,
    '62.84',
  ),
  (
    '0939-make-ahead-chocolate-souffles.yaml',
    null,
    1,
    '2 tablespoons granulated sugar',
    746784,
    '25.14',
  ),
  (
    '0939-make-ahead-chocolate-souffles.yaml',
    null,
    10,
    '2 tablespoons confectioners’ sugar',
    169656,
    '15.08',
  ),
  (
    '0940-pavlova-with-fruit-and-whipped-cream.yaml',
    null,
    6,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0940-pavlova-with-fruit-and-whipped-cream.yaml',
    'Mango, Kiwi, and Blueberry Topping',
    3,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0948-strawberry-shortcakes.yaml',
    null,
    1,
    '6 tablespoons sugar',
    746784,
    '75.41',
  ),
  (
    '0948-strawberry-shortcakes.yaml',
    null,
    3,
    '5 tablespoons sugar',
    746784,
    '62.84',
  ),
  (
    '0948-strawberry-shortcakes.yaml',
    null,
    11,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0951-simple-raspberry-gratin.yaml',
    null,
    1,
    '1 tablespoon granulated sugar',
    746784,
    '12.57',
  ),
  (
    '0952-individual-fresh-berry-gratins-with-zabaglione.yaml',
    null,
    4,
    '3 tablespoons granulated sugar',
    746784,
    '37.71',
  ),
  (
    '0952-individual-fresh-berry-gratins-with-zabaglione.yaml',
    null,
    6,
    '2 teaspoons light brown sugar',
    168833,
    '9.17',
  ),
  (
    '0955-skillet-apple-brown-betty.yaml',
    null,
    2,
    '2 tablespoons packed light brown sugar',
    168833,
    '27.50',
  ),
  (
    '0956-apple-strudel.yaml',
    null,
    1,
    '3 tablespoons granulated sugar',
    746784,
    '37.71',
  ),
  (
    '0956-apple-strudel.yaml',
    null,
    10,
    '1 tablespoon confectioners’ sugar, plus extra for serving',
    169656,
    '7.54',
  ),
  (
    '0957-easy-apple-strudel.yaml',
    null,
    12,
    '1½ teaspoons confectioners’ sugar',
    169656,
    '3.77',
  ),
  (
    '0958-skillet-apple-pie.yaml',
    null,
    1,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  ('0960-crepes-suzette.yaml', null, 5, '3 tablespoons sugar', 746784, '37.71'),
  (
    '0963-pear-crisp.yaml',
    null,
    3,
    '2 tablespoons granulated sugar',
    746784,
    '25.14',
  ),
  (
    '0963-pear-crisp.yaml',
    null,
    8,
    '2 tablespoons granulated sugar',
    746784,
    '25.14',
  ),
  (
    '0968-summer-berry-trifle.yaml',
    null,
    24,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0972-basic-double-crust-pie-dough.yaml',
    null,
    1,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0972-basic-double-crust-pie-dough.yaml',
    'Basic Single-Crust Pie Dough',
    1,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0973-all-butter-double-crust-pie-dough.yaml',
    null,
    3,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0974-foolproof-double-crust-pie-dough.yaml',
    null,
    1,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0974-foolproof-double-crust-pie-dough.yaml',
    'Foolproof Single-Crust Pie Dough',
    1,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0975-foolproof-all-butter-dough-for-single-crust-pie.yaml',
    null,
    2,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0976-foolproof-all-butter-dough-for-double-crust-pie.yaml',
    null,
    2,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0977-graham-cracker-crust.yaml',
    null,
    2,
    '3 tablespoons sugar',
    746784,
    '37.71',
  ),
  (
    '0982-fresh-peach-pie.yaml',
    'Pie Dough for Lattice-Top Pie',
    1,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0985-fresh-strawberry-pie.yaml',
    null,
    8,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '0986-strawberry-rhubarb-pie.yaml',
    null,
    1,
    '2 tablespoons sugar, plus 3 tablespoons for sprinkling',
    746784,
    '25.14',
  ),
  (
    '0990-lemon-chiffon-pie.yaml',
    null,
    1,
    '3 tablespoons sugar',
    746784,
    '37.71',
  ),
  (
    '0991-coconut-cream-pie.yaml',
    null,
    11,
    '1½ tablespoons sugar',
    746784,
    '18.85',
  ),
  (
    '0992-chocolate-cream-pie-with-oreo-cookie-crust.yaml',
    null,
    12,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '0993-chocolate-cream-pie-with-all-butter-crust.yaml',
    null,
    10,
    '1 tablespoon confectioners’ sugar',
    169656,
    '7.54',
  ),
  (
    '0998-free-form-summer-fruit-tart.yaml',
    null,
    6,
    '3–5 tablespoons plus 1 tablespoon sugar',
    746784,
    '62.84',
  ),
  (
    '0999-free-form-summer-fruit-tartlets-for-two.yaml',
    null,
    6,
    '3–5 tablespoons sugar',
    746784,
    '50.28',
  ),
  (
    '1000-linzertorte.yaml',
    null,
    14,
    '1½ teaspoons turbinado or Demerara sugar (optional)',
    170674,
    '6.28',
  ),
  (
    '1071-watermelon-salad-with-cotija-and-serrano-chiles.yaml',
    null,
    3,
    '1–2 tablespoons sugar (optional)',
    746784,
    '18.85',
  ),
  (
    '1078-bulgogi-korean-marinated-beef.yaml',
    null,
    1,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '1101-pupusas-with-quick-salsa-and-curtido.yaml',
    'Curtido',
    2,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '1103-upside-down-tomato-tart.yaml',
    null,
    1,
    '2½ tablespoons sugar',
    746784,
    '31.42',
  ),
  (
    '1104-crescent-shaped-rugelach-with-raisin-walnut-filling.yaml',
    null,
    1,
    '1½ tablespoons sugar',
    746784,
    '18.85',
  ),
  (
    '1115-fresh-peach-pie-with-all-butter-lattice-top.yaml',
    'Pie Dough for Lattice-Top Pie',
    1,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '1147-fresh-bulk-sausage.yaml',
    'Breakfast Seasoning',
    0,
    '1 tablespoon packed light brown sugar',
    168833,
    '13.75',
  ),
  (
    '1148-gravlax.yaml',
    null,
    0,
    '⅓ cup packed light brown sugar',
    168833,
    '73.34',
  ),
  (
    '1150-deluxe-blueberry-pancakes.yaml',
    null,
    3,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '1160-pouding-chomeur-maple-syrup-cake.yaml',
    null,
    4,
    '3 tablespoons sugar',
    746784,
    '37.71',
  ),
  (
    '1166-fruit-hand-pies.yaml',
    null,
    1,
    '2 tablespoons granulated sugar',
    746784,
    '25.14',
  ),
  (
    '1166-fruit-hand-pies.yaml',
    null,
    7,
    '2 tablespoons demerara or turbinado sugar (optional)',
    170674,
    '25.14',
  ),
  (
    '1172-nikujaga-beef-and-potato-stew.yaml',
    null,
    10,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '1177-caramelized-onion-pear-and-bacon-tart.yaml',
    null,
    3,
    '1½ teaspoons packed brown sugar',
    168833,
    '6.88',
  ),
  (
    '1178-chicken-teriyaki.yaml',
    null,
    4,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '1192-gado-gado.yaml',
    null,
    7,
    '4 teaspoons packed dark brown sugar',
    168833,
    '18.34',
  ),
  (
    '1202-new-york-cheesecakes.yaml',
    null,
    2,
    '1 tablespoon sugar',
    746784,
    '12.57',
  ),
  (
    '1204-triple-berry-slab-pie-with-ginger-lemon-streusel.yaml',
    'Slab Pie Dough',
    2,
    '2 tablespoons sugar',
    746784,
    '25.14',
  ),
  (
    '1208-albondigas-en-chipotle.yaml',
    null,
    11,
    '1 tablespoon packed brown sugar',
    168833,
    '13.75',
  ),
];

/// The pomegranate row's flag (engine `trimStandInFlagOf`, 173128).
const String _flatFlag =
    "approximate (the printed ¼-inch fat cap counted at USDA's ⅛-inch flat "
    "trim; USDA's braised pair 173128 → 173130 keeps 67.6 % of the energy by "
    'the protein tracer — the fat the steps skim, deducted)';

/// The row's energy, as the totals read it (the record's first energy
/// number, else its Atwater sum): grams × kcal per 100 g — GROSS (the
/// pomegranate's braised share is a totals deduction, as Q25's alcohol).
double _kcalOf(SaltDatabase db, IngredientMatchRow row, IngredientLine line) {
  final grams = row.grams ?? 0;
  if (grams <= 0 || row.fdcId == null) {
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

String _g2(double v) => v.toStringAsFixed(2);

void main() {
  test('the matcher version carries the batch (update the literal with a '
      'bump)', () {
    expect(matcherVersion, 68);
  });

  test('1: the flat gains its ⅛" record; the braised pair 173128 → 173130 '
      "keeps 67.6 % of the energy by the protein tracer (L49's cached hits: "
      'P 18.1 → 28.7, F 22.2 → 19.5, E 278 → 298)', () {
    expect(
      {for (final (_, pairs) in trimDepthRecords) ...pairs},
      {172641: 174414, 168607: 168664, 168743: 173128, 2727572: 171751},
    );
    expect(braisedEnergyShare.keys, [173128]);
    const yieldShare = 18.1 / 28.7;
    expect(yieldShare.toStringAsFixed(6), '0.630662');
    expect(braisedEnergyShare[173128], 298 * yieldShare / 278);
    expect(braisedEnergyShare[173128]!.toStringAsFixed(6), '0.676033');
    // The fat it keeps (stated, not deducted: energy only, Q25's shape).
    expect((19.5 * yieldShare / 22.2).toStringAsFixed(6), '0.553960');
    const flat =
        '1 (4- to 5-pound) beef brisket, flat cut, fat trimmed to ¼ inch';
    expect(trimStandInFlagOf(flat, 173128), _flatFlag);
    // The 168743 ¼" arm stays (the answer losing 173128 falls back to it).
    expect(
      trimStandInFlagOf(flat, 168743),
      'approximate (the printed ¼-inch fat cap renders and is skimmed (step '
      '5); counted as the 0-inch trimmed flat)',
    );
    // STATED synthesized: a real flat line with no printed cap on 173128.
    expect(
      trimStandInFlagOf(
        '1 (4- to 5-pound) beef brisket, preferably flat cut',
        173128,
      ),
      isNull,
    );
  });

  test('2: a reserved part is never bought — no detail is fetched for it; '
      'the birds still buy refuse', () {
    expect(buysRefuse('Reserved turkey giblets, neck, and tailpiece'), isFalse);
    expect(
      buysRefuse(
        'Reserved giblets, neck, tailpiece, and backbone and rib bones from '
        'the turkey',
      ),
      isFalse,
    );
    expect(
      buysRefuse(
        '1 (12- to 14-pound) turkey; giblets, neck, and tailpiece removed '
        'and reserved for gravy',
      ),
      isTrue,
    );
    expect(buysRefuse('1 (4-pound) whole chicken, giblets discarded'), isTrue);
  });

  test('5–7: the tables — the chopped sibling, the Kisses label piece, the '
      "Sure-Jell label's 4 g a teaspoon (longer than the stray 'sugar')", () {
    expect(fineCutSiblings, {2709780: 172232});
    expect(pieceWeightOf('hershey s kisses'), 41 / 9);
    expect((41 / 9).toStringAsFixed(4), '4.5556');
    expect((32 / 7).toStringAsFixed(4), '4.5714');
    for (final item in const [
      'low- or no-sugar-needed fruit pectin',
      'sure-jell for low-sugar recipes',
      'sure-jell for less or no sugar needed recipes',
    ]) {
      expect(densityOf(item), 4 / 4.92892, reason: item);
    }
    expect((4 / 4.92892).toStringAsFixed(6), '0.811537');
    expect(densityOf('sugar'), 0.85);
    expect(densityOf('granulated sugar'), 0.85);
  });

  group('matcher v68 (batch M70)', skip: skipIfNoCorpus, () {
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
      tempDir = Directory.systemTemp.createTempSync('salt-v69-');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath)
        ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      // 'reserved giblets' (0165's strained gravy line) is a query no
      // snapshot holds — the engine never asks it (the line stays the 0 g
      // rule row) — named so a build that matched it fails on its values,
      // not on the fixture tripwire (STATED). Two more no snapshot holds —
      // 0004's "1 minced fresh thyme or ¼ teaspoon dried" and 0146's "½
      // teaspoon minced fresh sage leaves or ¼ teaspoon dried sage", the
      // library's rows predating them — answered as no hits (neither line
      // is pinned; their recipes hold full-set negatives).
      provider = FixtureProvider(
        pending: {
          ...pendingSearches,
          'reserved giblets',
          'thyme or dried',
          'sage leaves or dried sage',
        },
      );
      // The deli-ham line caches the one answer that holds 168322, the
      // cooked bacon rule B1 counts (the v41 precedent), as a library does;
      // the strawberry pie's crust (a section of 0974) before its parent,
      // the bulk order.
      for (final file in const [
        '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
        '0974-foolproof-double-crust-pie-dough.yaml',
      ]) {
        await compute(loadCorpusRecipe(file));
      }
      for (final (file, _, _, _, _, _, _, _, _, _, _, _) in [
        ..._reach,
        ..._parents,
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

    /// [file]'s stored recipe, or its [section]'s (by title).
    Recipe recipeIn(String file, String? section) => section == null
        ? recipes[file]!
        : nutritionRecipeOf(
            db,
            sectionKeyOf(recipes[file]!.id, section),
          )!.recipe;

    IngredientMatchRow rowIn(String file, int position, {String? section}) => db
        .ingredientMatchesFor(recipeIn(file, section).id)
        .singleWhere((m) => m.position == position);

    String? basisIn(String file, int position, {String? section}) =>
        gramBasisFor(
          db,
          nutritionLines(recipeIn(file, section))[position],
          rowIn(file, position, section: section),
          recipe: recipeIn(file, section),
        );

    /// Each [rows] entry in its whole recipe (or section): the record, the
    /// description, the confidence, the grams, the status, the hold, the
    /// row's (gross) energy and the basis.
    void expectRows(List<_Row> rows) {
      for (final (
            file,
            section,
            position,
            raw,
            fdcId,
            description,
            confidence,
            grams,
            status,
            hold,
            kcal,
            basis,
          )
          in rows) {
        final line = nutritionLines(recipeIn(file, section))[position];
        final row = rowIn(file, position, section: section);
        final reason = '$file|${section ?? ''}|$position';
        expect(line.raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.description ?? '', description, reason: reason);
        expect(row.confidence.toStringAsFixed(6), confidence, reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(row.status, status, reason: reason);
        expect(row.hold, hold, reason: reason);
        if (kcal != null && fdcId != null) {
          expect(_g2(_kcalOf(db, row, line)), kcal, reason: reason);
        }
        expect(
          basisIn(file, position, section: section),
          basis,
          reason: reason,
        );
      }
    }

    /// The stored (status, kcal per serving, batch energy) of [file] (or
    /// its [section]).
    (String, String?, String) totalsOf(String file, {String? section}) {
      final n = db.nutritionFor(recipeIn(file, section).id)!;
      return (
        n.status,
        n.caloriesPerServing?.toStringAsFixed(2),
        _g2(batchTotalsOf(n)['energy'] ?? 0),
      );
    }

    test("M70 reaches exactly its 63 rows (design_v2 §2 M70; the plan's "
        'list re-derived on the v68 rows); the 3 routed parents re-read '
        'their sections', () {
      expect(_reach, hasLength(63));
      expect(
        _reach.where((r) => r.$5 == 2709780 && r.$12!.endsWith(_chopped)),
        hasLength(50),
      );
      expectRows(_reach);
      expectRows(_parents);
      for (final (file, section, position, source) in const [
        (_classicTurkey, _gravy, 1, 'weight'),
        (_yuca, null, 0, 'weight'),
        (_yuca, null, 2, 'discarded'),
        (_minestrone, null, 14, 'discarded'),
        (_fagioli, null, 9, 'discarded'),
        (_chickenSoup, null, 8, 'weight'),
        (_meringue, null, 8, 'piece'),
        ('0944-raspberry-sorbet.yaml', null, 1, 'density'),
        ('0000-italian-style-turkey-meatballs.yaml', null, 16, 'portion'),
      ]) {
        expect(
          rowIn(file, position, section: section).gramSource,
          source,
          reason: '$file|$position',
        );
      }
    });

    test('the rows M70 must not reach equal v68', () {
      expect(_negatives, hasLength(134));
      expectRows(_negatives);
    });

    test("the rank-as keys are the lines' own items (normalizeItem), each "
        "reading a cached answer under its record's words", () {
      for (final (file, position, item, query, answer) in const [
        (_yuca, 0, 'yuca roots', 'cassava raw', 'cassava raw'),
        (
          _minestrone,
          14,
          'parmesan cheese rind',
          'cheese parmesan hard',
          'parmesan cheese rind',
        ),
        (
          _fagioli,
          9,
          'parmesan cheese rind',
          'cheese parmesan hard',
          'parmesan cheese rind',
        ),
        (
          _chickenSoup,
          8,
          'parmesan cheese rind',
          'cheese parmesan hard',
          'parmesan cheese rind',
        ),
        (
          _meringue,
          8,
          'hershey s kisses',
          'candies milk chocolate',
          'milk chocolate candy',
        ),
        (
          '0859-marbled-blueberry-bundt-cake.yaml',
          12,
          'low- or no-sugar-needed fruit pectin',
          'pectin unsweetened dry mix',
          'low- or no-sugar-needed fruit pectin',
        ),
        (
          '0944-raspberry-sorbet.yaml',
          1,
          'sure-jell for less or no sugar needed recipes',
          'pectin unsweetened dry mix',
          'low- or no-sugar-needed fruit pectin',
        ),
        (
          '0985-fresh-strawberry-pie.yaml',
          4,
          'sure-jell for low-sugar recipes',
          'pectin unsweetened dry mix',
          'low- or no-sugar-needed fruit pectin',
        ),
      ]) {
        final line = nutritionLines(recipes[file]!)[position];
        expect(normalizeItem(lineItemOf(line)), item, reason: file);
        expect(rankAsFor(item), (query: query, answer: answer), reason: file);
      }
    });

    test('1 by hand: the row stays gross (2,041.16 g × 278 kcal = 5,674.44, '
        'the kcal column, as an alcohol row); the totals deduct (1 − e) of '
        'it, 1,838.33', () {
      final row = rowIn(_pomegranate, 0);
      final line = nutritionLines(recipes[_pomegranate]!)[0];
      expect(knownFood(db, 173128, line: line)!.nutrientsPer100g['208'], 278);
      final gross = row.grams! * 2.78;
      expect(_g2(gross), '5674.44');
      expect(_g2(gross * (1 - braisedEnergyShare[173128]!)), '1838.33');
      // The replay's 4,379.57 → 4,766.11 batch, 729.93 → 794.35 per
      // serving.
      expect(totalsOf(_pomegranate), ('complete', '794.35', '4766.11'));
    });

    test("2 by hand: the host's turkey prints 12–14 lb (5,896.70 g at the "
        'midpoint) × (85 − 78) / 85 × 6 / (4 + 6) = 291.37 g on the 171083 '
        "hit (124 kcal) = 361.29; no detail cached; a Confirm's gramsFor "
        'asks nothing; the strained crisp-skin gravy reads none', () async {
      final bird = nutritionLines(recipes[_classicTurkey]!)[1];
      expect(parenWeightGrams(bird.raw)!.toStringAsFixed(2), '5896.70');
      final section = recipeIn(_classicTurkey, _gravy);
      final line = nutritionLines(section)[1];
      final giblets = hostWeighedGiblets(
        db,
        section,
        line,
        normalizeItem(lineItemOf(line)),
      )!;
      expect(giblets.grams, parenWeightGrams(bird.raw)! * 7 / 85 * 6 / 10);
      expect(_g2(giblets.grams), '291.37');
      final hit = knownFood(db, 171083, line: line)!;
      expect(hit.description, 'Turkey, whole, giblets, raw');
      expect(hit.nutrientsPer100g['208'], 124);
      expect(_g2(giblets.grams * 1.24), '361.29');
      expect(db.fdcFoodCacheGet(171083), isNull);
      final asked = provider.foodCalls;
      final (food, grams) = await gramsFor(
        db,
        provider,
        hit,
        line,
        recipe: section,
      );
      expect(provider.foodCalls, asked);
      expect(food.fdcId, 171083);
      expect(grams?.grams, giblets.grams);
      expect(db.fdcFoodCacheGet(171083), isNull);
      // 0165's gravy roasts, simmers and strains its trimmings — never
      // stirs them back: its 0 g rule row stays (the negatives).
      final crisp = recipeIn(_crispSkin, 'Turkey Gravy');
      final strained = nutritionLines(crisp)[0];
      expect(
        hostWeighedGiblets(
          db,
          crisp,
          strained,
          normalizeItem(lineItemOf(strained)),
        ),
        isNull,
      );
      // The section's batch (per batch = per serving) and both parents (the
      // replay: 787.56 → 1,148.85; 678.04 → 714.17; 1,221.89 → 1,258.02).
      expect(
        totalsOf(_classicTurkey, section: _gravy),
        ('complete', '1148.85', '1148.85'),
      );
      expect(totalsOf(_classicTurkey).$2, '714.17');
      expect(totalsOf(_stuffedTurkey).$2, '1258.02');
    });

    test("2: a host-only edit of the bird's printed weight (12–14 → 16–18 lb) "
        'stales the Giblet Pan Gravy, whose recompute writes the live '
        "reader's 381.02 g (closer 2, D1: `ingredientsHashOf` hashes the "
        'grams the section reads off its host)', () async {
      final dir = Directory.systemTemp.createTempSync('salt-v69-host-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final own = SaltDatabase.open(
        ServerConfig(
          dataDir: dir.path,
          logLevel: Level.WARNING,
          trustProxy: false,
        ).dbPath,
      )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      addTearDown(own.dispose);
      final text = File(
        '$corpusRecipesDir/$_classicTurkey',
      ).readAsStringSync();
      final id = recipes[_classicTurkey]!.id;
      final key = sectionKeyOf(id, _gravy);
      Recipe gravy() => nutritionRecipeOf(own, key)!.recipe;
      IngredientMatchRow giblets() =>
          own.ingredientMatchesFor(key).singleWhere((m) => m.position == 1);
      // Saved, then computed as the bulk job's `_runOne` does: each section
      // not fresh first, then the host.
      Future<void> saveAndCompute(String yaml, String hash) async {
        own.upsertRecipe(
          RecipeYamlCodec.decode(yaml).recipe,
          sourceSlug: _source,
          contentHash: hash,
        );
        final host = own.recipeByIdOrSlug(id)!.recipe;
        for (final at in sectionChildKeysOf(own, host, ResolverMemo(own))) {
          final section = nutritionRecipeOf(own, at)!.recipe;
          if (!nutritionIsFresh(own, section)) {
            expect(await matchAndCompute(own, provider, section), isNull);
          }
        }
        expect(await matchAndCompute(own, provider, host), isNull);
      }

      // The section's own inputs (title, yield, steps, lines).
      List<Object?> ownInputs(Recipe r) => [
        r.title,
        '${r.servings}',
        for (final step in r.steps) step.text,
        for (final line in nutritionLines(r)) line.raw,
      ];

      await saveAndCompute(text, 'h1');
      expect(_g2(giblets().grams!), '291.37');
      final before = ownInputs(gravy());
      final edited = text.replaceAll('12- to 14-pound', '16- to 18-pound');
      expect(edited.split('16- to 18-pound'), hasLength(3)); // raw + item
      own.upsertRecipe(
        RecipeYamlCodec.decode(edited).recipe,
        sourceSlug: _source,
        contentHash: 'h2',
      );
      // The section's own text is unchanged — only the host's bird moved.
      expect(ownInputs(gravy()), before);
      final line = nutritionLines(gravy())[1];
      final live = hostWeighedGiblets(
        own,
        gravy(),
        line,
        normalizeItem(lineItemOf(line)),
      )!;
      expect(_g2(live.grams), '381.02'); // 17 lb × 7/85 × 6/10
      expect(nutritionIsFresh(own, gravy()), isFalse);
      await saveAndCompute(edited, 'h2');
      expect(nutritionIsFresh(own, gravy()), isTrue);
      expect(giblets().grams, live.grams);
      expect(
        gramBasisFor(own, line, giblets(), recipe: gravy()),
        "the host's turkey from the printed weight (16–18 lb, the midpoint): "
        '7711 g × 7/85 neck and giblets (USDA AH-102 turkey dressing data, 12 '
        'lb and over: 85 with, 78 without) × 6/10 giblets (item 2590: neck 4, '
        'giblets 6, fryer-roaster class) · approximate (the neck and '
        'tailpiece are strained out — not counted)',
      );
      // The batch moves by the grams alone: 1,148.85 + (381.02 − 291.37) ×
      // 1.24 (171083's 124 kcal) = 1,260.02 (per batch = per serving).
      final n = own.nutritionFor(key)!;
      expect(
        (
          n.status,
          _g2(n.caloriesPerServing!),
          _g2(batchTotalsOf(n)['energy']!),
        ),
        ('complete', '1260.02', '1260.02'),
      );
    });

    test('3 by hand: R-1 read FNDDS 2709565 "Yuca fries" — 100 g "Cassava, '
        'raw", 15 g "Vegetable oil, NFS": 907.18 g × 15 / 100 = 136.08 g; '
        'the recipe stays partial (its salt held)', () {
      final yuca = rowIn(_yuca, 0);
      expect(_g2(yuca.grams! * 15 / 100), '136.08');
      expect(rowIn(_yuca, 2).grams, 136.08);
      expect(rowIn(_yuca, 1).hold, 'discarded_medium');
      // 136.08 g × 9.00 = 1,224.72 (the stored grams; the brief's 1,224.70
      // priced 136.0776 g); the batch 2,676.21, per serving (4) 669.05.
      expect(totalsOf(_yuca), ('partial', '669.05', '2676.21'));
    });

    test('4: the two discarded rinds complete their soups; the dumpling '
        "soup's rind beside its shredded Parmesan stays held (`_cutFine`)", () {
      expect(totalsOf(_minestrone).$1, 'complete');
      expect(totalsOf(_fagioli).$1, 'complete');
      expect(rowIn(_chickenSoup, 8).hold, 'second_food');
      expect(totalsOf(_chickenSoup).$1, 'partial');
    });

    test("5 by hand on the cached SR 172232: 'tbsp, chopped' 5.3 g at amount "
        '2 → 2.65 g a tablespoon (42.40 g a cup); whole, packed, torn and '
        'shredded lines read no chopped portion', () {
      final sr = knownFood(db, 172232)!;
      final chopped = sr.portions.singleWhere(
        (p) => p.description == 'tbsp, chopped',
      );
      expect((chopped.gramWeight, chopped.amount), (5.3, 2.0));
      expect(_g2(chopped.gramWeight / chopped.amount!), '2.65');
      expect(_g2(chopped.gramWeight / chopped.amount! * 16), '42.40');
      final basil = knownFood(db, 2709780)!;
      for (final (file, position) in const [
        ('0029-soupe-au-pistou-provencal-vegetable-soup.yaml', 0),
        ('0335-farfalle-with-pesto.yaml', 1),
        ('0407-eggplant-parmesan.yaml', 16),
        ('0415-best-chicken-parmesan.yaml', 20),
        ('0405-ciambotta-italian-vegetable-stew.yaml', 15),
      ]) {
        final line = nutritionLines(recipes[file]!)[position];
        expect(
          fineCutWeighing(basil, sr, line.raw, line.amounts),
          isNull,
          reason: line.raw,
        );
      }
      final minced = nutritionLines(
        recipes['0060-antipasto-pasta-salad.yaml']!,
      )[13];
      expect(minced.raw, '1 cup minced fresh basil leaves');
      expect(
        fineCutWeighing(basil, sr, minced.raw, minced.amounts)?.food.portions,
        [chopped],
      );
    });

    test('6 and 7: the Kisses and the five pectin recipes complete', () {
      expect(totalsOf(_meringue), ('complete', '43.72', '2186.05'));
      for (final (file, perServing) in const [
        // The fresh compute (the replay: 512.98, 1,047.88 — search-hit
        // energies in other rows).
        ('0859-marbled-blueberry-bundt-cake.yaml', '512.99'),
        ('0982-fresh-peach-pie.yaml', '584.35'),
        ('1115-fresh-peach-pie-with-all-butter-lattice-top.yaml', '584.35'),
        ('0944-raspberry-sorbet.yaml', '1047.67'),
        ('0985-fresh-strawberry-pie.yaml', '476.91'),
      ]) {
        final (status, kcal, _) = totalsOf(file);
        expect((status, kcal), ('complete', perServing), reason: file);
      }
    });

    test('per serving: every recipe M70 moves — the fresh compute here (its '
        'search-hit energies and the children this DB holds differ from the '
        "library's in other rows); the replay's v68 → v69 in each comment; 8 "
        'partial → complete', () {
      for (final (file, status, perServing) in const [
        (
          '0000-italian-style-turkey-meatballs.yaml',
          'complete',
          '494.58',
        ), // replay complete 493.64 → complete 493.90
        (
          '0028-hearty-minestrone.yaml',
          'complete',
          '264.42',
        ), // replay partial 264.15 → complete 264.51
        (
          '0034-lighter-corn-chowder.yaml',
          'complete',
          '366.72',
        ), // replay complete 366.73 → complete 366.69
        (
          '0047-panzanella-italian-bread-salad.yaml',
          'complete',
          '576.70',
        ), // replay complete 576.36 → complete 576.62
        (
          '0060-antipasto-pasta-salad.yaml',
          'complete',
          '905.10',
        ), // replay complete 904.42 → complete 905.13
        (
          '0061-italian-pasta-salad.yaml',
          'partial',
          '492.07',
        ), // replay partial 491.54 → partial 492.07
        (
          '0067-skillet-lasagna.yaml',
          'complete',
          '723.42',
        ), // replay complete 723.04 → complete 722.98
        (
          '0068-cast-iron-baked-ziti-with-charred-tomatoes.yaml',
          'complete',
          '512.70',
        ), // replay complete 512.44 → complete 512.70
        (
          '0068-skillet-baked-ziti.yaml',
          'complete',
          '646.79',
        ), // replay complete 646.48 → complete 646.74
        (
          '0154-classic-roast-turkey.yaml',
          'complete',
          '714.17',
        ), // replay complete 678.04 → complete 714.17
        (
          '0158-classic-roast-stuffed-turkey.yaml',
          'complete',
          '1258.02',
        ), // replay complete 1221.89 → complete 1258.02
        (
          '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml',
          'complete',
          '794.35',
        ), // replay complete 729.93 → complete 794.35
        (
          '0322-spaghetti-al-limone-spaghetti-with-lemon-and-olive-oil.yaml',
          'complete',
          '625.59',
        ), // replay complete 625.63 → complete 625.59
        (
          '0326-pasta-and-fresh-tomato-sauce-with-garlic-and-basil.yaml',
          'complete',
          '550.02',
        ), // replay complete 550.06 → complete 550.02
        (
          '0326-pasta-with-creamy-tomato-sauce.yaml',
          'complete',
          '748.74',
        ), // replay complete 748.42 → complete 748.69
        (
          '0327-pasta-caprese.yaml',
          'complete',
          '825.96',
        ), // replay complete 825.69 → complete 825.96
        (
          '0329-quick-tomato-sauce.yaml',
          'complete',
          '216.14',
        ), // replay complete 216.13 → complete 216.07
        (
          '0330-marinara-sauce.yaml',
          'complete',
          '183.11',
        ), // replay complete 183.17 → complete 183.11
        (
          '0330-meatless-meat-sauce-with-chickpeas-and-mushrooms.yaml',
          'complete',
          '256.90',
        ), // replay complete 256.98 → complete 256.95
        (
          '0335-pasta-alla-norma.yaml',
          'complete',
          '480.86',
        ), // replay complete 480.91 → complete 480.83
        (
          '0341-campanelle-with-asparagus-basil-and-balsamic-glaze.yaml',
          'complete',
          '706.72',
        ), // replay complete 705.66 → complete 706.72
        (
          '0347-shrimp-fra-diavolo.yaml',
          'partial',
          '375.90',
        ), // replay partial 375.59 → partial 375.85
        (
          '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml',
          'complete',
          '1039.71',
        ), // replay complete 1039.31 → complete 1039.44
        (
          '0357-spaghetti-and-meatballs.yaml',
          'complete',
          '883.39',
        ), // replay complete 883.44 → complete 883.42
        (
          '0358-classic-spaghetti-and-meatballs-for-a-crowd.yaml',
          'partial',
          '947.89',
        ), // replay partial 947.76 → partial 947.94
        (
          '0360-sausage-meatballs-and-spaghetti.yaml',
          'complete',
          '640.53',
        ), // replay complete 640.73 → complete 640.71
        (
          '0361-penne-alla-vodka-penne-with-vodka-sauce.yaml',
          'complete',
          '677.93',
        ), // replay complete 677.92 → complete 677.88
        (
          '0367-baked-ziti.yaml',
          'complete',
          '584.87',
        ), // replay complete 584.63 → complete 584.87
        (
          '0368-baked-manicotti.yaml',
          'complete',
          '645.70',
        ), // replay complete 645.76 → complete 645.70
        (
          '0371-simple-cheese-lasagna.yaml',
          'complete',
          '557.60',
        ), // replay complete 557.61 → complete 557.58
        (
          '0373-vegetable-lasagna.yaml',
          'complete',
          '627.91',
        ), // replay complete 627.78 → complete 627.89
        (
          '0374-lasagna-with-hearty-tomato-meat-sauce.yaml',
          'complete',
          '832.42',
        ), // replay complete 831.83 → complete 832.19
        (
          '0387-chicago-style-deep-dish-pizza.yaml',
          'complete',
          '2680.10',
        ), // replay complete 2680.08 → complete 2680.00
        (
          '0396-grilled-tomato-and-cheese-pizza.yaml',
          'complete',
          '765.65',
        ), // replay complete 765.12 → complete 765.65
        (
          '0399-tomato-and-mozzarella-tart.yaml',
          'complete',
          '540.67',
        ), // replay complete 540.71 → complete 540.67
        (
          '0404-pasta-e-fagioli-italian-pasta-and-bean-soup.yaml',
          'complete',
          '285.32',
        ), // replay partial 285.61 → complete 285.61
        (
          '0405-ciambotta-italian-vegetable-stew.yaml',
          'complete',
          '260.43',
        ), // replay complete 260.16 → complete 260.40
        (
          '0407-eggplant-parmesan.yaml',
          'partial',
          '454.01',
        ), // replay partial 453.66 → partial 454.01
        (
          '0409-eggplant-involtini.yaml',
          'complete',
          '475.17',
        ), // replay complete 474.87 → complete 475.12
        (
          '0415-best-chicken-parmesan.yaml',
          'complete',
          '486.48',
        ), // replay complete 486.50 → complete 486.46
        (
          '0416-lighter-chicken-parmesan.yaml',
          'complete',
          '235.22',
        ), // replay complete 235.29 → complete 235.26
        (
          '0440-summer-vegetable-gratin.yaml',
          'complete',
          '240.59',
        ), // replay complete 240.41 → complete 240.59
        (
          '0441-walkaway-ratatouille.yaml',
          'complete',
          '213.23',
        ), // replay complete 213.26 → complete 213.23
        (
          '0654-grilled-swordfish-skewers-with-tomato-scallion-caponata.yaml',
          'complete',
          '458.49',
        ), // replay complete 458.53 → complete 458.49
        (
          '0708-best-summer-tomato-gratin.yaml',
          'complete',
          '280.01',
        ), // replay complete 279.94 → complete 279.91
        (
          '0859-marbled-blueberry-bundt-cake.yaml',
          'complete',
          '512.99',
        ), // replay partial 503.23 → complete 512.98
        (
          '0944-raspberry-sorbet.yaml',
          'complete',
          '1047.67',
        ), // replay partial 1034.88 → complete 1047.88
        (
          '0982-fresh-peach-pie.yaml',
          'complete',
          '584.35',
        ), // replay partial 574.60 → complete 584.35
        (
          '0985-fresh-strawberry-pie.yaml',
          'complete',
          '476.91',
        ), // replay partial 474.47 → complete 476.91
        (
          '1089-braciole.yaml',
          'complete',
          '634.92',
        ), // replay complete 634.51 → complete 634.72
        (
          '1098-fried-yuca.yaml',
          'partial',
          '669.05',
        ), // replay partial  → partial 669.05
        (
          '1115-fresh-peach-pie-with-all-butter-lattice-top.yaml',
          'complete',
          '584.35',
        ), // replay partial 574.60 → complete 584.35
        (
          '1132-ultracreamy-spaghetti-with-zucchini.yaml',
          'complete',
          '549.93',
        ), // replay complete 549.97 → complete 549.93
        (
          '1198-meringue-christmas-trees.yaml',
          'complete',
          '43.72',
        ), // replay partial 13.50 → complete 43.72
      ]) {
        final (s, kcal, _) = totalsOf(file);
        expect((s, kcal), (status, perServing), reason: file);
      }
    });

    test("the matches GET shows each item's basis (one row per item, the "
        'giblets in their section)', () async {
      for (final (file, section, position) in const [
        (_pomegranate, null, 0),
        (_classicTurkey, _gravy, 1),
        (_yuca, null, 2),
        (_minestrone, null, 14),
        ('0367-baked-ziti.yaml', null, 10),
        (_meringue, null, 8),
        ('0985-fresh-strawberry-pie.yaml', null, 4),
      ]) {
        final want = _reach
            .singleWhere(
              (r) => r.$1 == file && r.$2 == section && r.$3 == position,
            )
            .$12;
        final items =
            (await matchesBody(
                  db,
                  provider,
                  recipeIn(file, section),
                ))['items']!
                as List<Map<String, Object?>>;
        final match = items[position]['match'] as Map<String, Object?>?;
        expect(match?['gram_basis'], want, reason: '$file|$position');
      }
    });

    test('a recompute keeps the braised share (the pomegranate batch '
        'reads 4,766.11 again)', () {
      final id = recipes[_pomegranate]!.id;
      expect(recomputeTotals(db, recipes[_pomegranate]!), isTrue);
      expect(_g2(batchTotalsOf(db.nutritionFor(id)!)['energy']!), '4766.11');
    });

    test(
      'a second recompute writes nothing (each recipe and its sections)',
      () {
        for (final recipe in recipes.values) {
          for (final id in [
            recipe.id,
            ...sectionChildKeysOf(db, recipe, ResolverMemo(db)),
          ]) {
            final stored = nutritionRecipeOf(db, id)!.recipe;
            List<(int, double?, String?)> rows() => [
              for (final r in db.ingredientMatchesFor(id))
                (r.position, r.grams, r.updatedAt),
            ];
            final before = rows();
            expect(recomputeTotals(db, stored), isTrue, reason: id);
            expect(rows(), before, reason: id);
          }
        }
      },
    );
  });

  group('every sugar-density row (closer 1, D1)', skip: skipIfNoCorpus, () {
    test(
      "lineGrams on each row's own record reads v68's density grams on "
      "every 'sugar'-density line (234: no pectin key reaches one)",
      () async {
        expect(_sugarDensity, hasLength(234));
        final tempDir = Directory.systemTemp.createTempSync('salt-v69-sugar-');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final db = SaltDatabase.open('${tempDir.path}/salt.db')
          ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
        addTearDown(db.dispose);
        final provider = FixtureProvider();
        final ids = <String, String>{};
        for (final (file, section, position, raw, fdcId, grams)
            in _sugarDensity) {
          final id = ids.putIfAbsent(file, () {
            final recipe = loadCorpusRecipe(file);
            db.upsertRecipe(
              recipe,
              sourceSlug: _source,
              contentHash: recipe.id,
            );
            return recipe.id;
          });
          final recipe = section == null
              ? db.recipeByIdOrSlug(id)!.recipe
              : nutritionRecipeOf(db, sectionKeyOf(id, section))!.recipe;
          final line = nutritionLines(recipe)[position];
          final weighed = lineGrams(
            db,
            line,
            await provider.food(fdcId),
            recipe: recipe,
          );
          final reason = '$file|${section ?? ''}|$position';
          expect(line.raw, raw, reason: reason);
          expect(weighed?.source, GramSource.density, reason: reason);
          expect(weighed?.grams.toStringAsFixed(2), grams, reason: reason);
        }
        expect(ids, hasLength(195));
      },
    );
  });
}
