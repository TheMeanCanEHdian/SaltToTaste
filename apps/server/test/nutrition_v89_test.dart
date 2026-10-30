// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v89 (batch M90; matcherVersion 84 — prep51 design_v2 §1 Q6
// option (b), ruled under the 2026-10-07 standing authorization; zero
// requests): six density keys weigh the corpus's printed cup AHEAD of the
// record's own volume figure (`_approximateDensities` recordFirst false —
// v49's tapioca-starch form), each flagged with its print: packed brown
// sugar 7 ounces a cup (86 of 88 prints; was 0.93), cornstarch 4 (4 of 4;
// was 0.54), sugar / granulated sugar 7 (225 of 237; was 0.85), cornmeal 5
// (8 of 9; was 0.66), confectioners' / powdered sugar 4 (34 of 34; was
// 0.51), bread flour 5½ (21 of 31 exactly, 27 within 0.7 %; was 0.52) —
// each figure oz × 28.3495 ÷ 236.588, each count the closer's own corpus
// grep. Z5's recordFirst keys keep the record's own figure (lentil). A
// record's portion in the line's OWN unit still wins first: Foundation
// 746784's 'cup' 188 g and 'teaspoon' 4 g size every cup and teaspoon line
// of sugar, so its tablespoon lines and the volume parts the arm weighs
// read the print. Every pinned figure is the v89 replay of snapshot 29
// (fix89/c1/g1) on the row's own fixture record; v88's in each comment.
// The rows beyond the brief's enumerated reach (plus parts, a step print,
// two stand-in records, the coat co-parts) are pinned as the replay moves
// them — ruled ACCEPT (fix89/ruling4.md). Never the
// network. Every corpus line is real; the cap shapes' 400 repeated real
// lines are the house's cap-shape exception (STATED).

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

const _chutney =
    '0178-cranberry-chutney-with-apples-and-crystallized-ginger.yaml';
const _gingerbread = '0877-gingerbread-layer-cake.yaml';
const _wings = '0526-dakgangjeong-korean-fried-chicken-wings.yaml';

/// A line weighed by [lineGrams] on its row's own record: (file, section,
/// position, raw, record, gram source, grams, basis) — the v89 replay's.
typedef _Line = (String, String?, int, String, int, String, String, String);

/// One stated corpus row per key spelling the corpus reaches, at its print.
const List<_Line> _keys = [
  // brown sugar (v88: 220.03 g, `1 cup ≈ 237 mL` — 0.93, SR 168833's own
  // 'cup packed' 220 g).
  (
    _chutney,
    null,
    6,
    '1 cup packed brown sugar',
    168833,
    'density',
    '198.45',
    '1 cup ≈ 237 mL · approximate (ATK: 1 cup packed brown sugar = 7 ounces)',
  ),
  // cornstarch (v88: 23.95 g at 0.54, SR 169698's 'cup' 128 g).
  (
    _gingerbread,
    null,
    2,
    '3 tablespoons cornstarch',
    169698,
    'density',
    '21.26',
    '3 tablespoon ≈ 44 mL · approximate (ATK: 1 cup cornstarch = 4 ounces)',
  ),
  // sugar (v88: 25.14 g at the kitchen 0.85).
  (
    '0010-vietnamese-beef-pho.yaml',
    null,
    6,
    '2 tablespoons sugar, plus extra for seasoning',
    746784,
    'density',
    '24.81',
    '2 tablespoon ≈ 30 mL · approximate (ATK: 1 cup sugar = 7 ounces)',
  ),
  // granulated sugar, its own key (v88: 25.14 g at 0.85).
  (
    '0766-quick-cinnamon-buns-with-buttermilk-icing.yaml',
    null,
    8,
    '2 tablespoons granulated sugar',
    746784,
    'density',
    '24.81',
    '2 tablespoon ≈ 30 mL · approximate (ATK: 1 cup sugar = 7 ounces)',
  ),
  // cornmeal (v88: 29.28 g at the kitchen 0.66; SR 169697's 'cup' 122 g
  // is 0.52).
  (
    '0008-our-favorite-chili.yaml',
    null,
    4,
    '3 tablespoons cornmeal',
    169697,
    'density',
    '26.58',
    '3 tablespoon ≈ 44 mL · approximate (ATK: 1 cup cornmeal = 5 ounces)',
  ),
  // confectioners' sugar — normalized 'powdered sugar' (v88: 7.54 g at
  // 0.51; SR 169656's 'cup unsifted' 120 g).
  (
    '0765-cranberry-pecan-muffins.yaml',
    null,
    15,
    '1 tablespoon confectioners’ sugar',
    169656,
    'density',
    '7.09',
    "1 tablespoon ≈ 15 mL · approximate (ATK: 1 cup confectioners' sugar = 4 ounces)",
  ),
  // bread flour (v88: 7.69 g at the kitchen 0.52; SR 168913's 'cup
  // unsifted, dipped' 137 g). The brief's 9.74 was rounded: 14.7868 mL ×
  // 0.659045 = 9.745 g.
  (
    '1152-kanelbullar-swedish-cinnamon-buns.yaml',
    null,
    12,
    '1 tablespoon bread flour',
    168913,
    'density',
    '9.75',
    '1 tablespoon ≈ 15 mL · approximate (ATK: 1 cup bread flour = 5½ ounces)',
  ),
];

/// The converses, each unmoved since v88: a weight-printed line per key
/// (its paren is its grams), a cup-unit sugar line (Foundation 746784's own
/// 'cup' 188 g in the line's own unit wins before any density), and a Z5
/// recordFirst key (lentil: the record's own cup).
const List<_Line> _converses = [
  (
    '0181-candied-sweet-potato-casserole.yaml',
    null,
    7,
    '½ cup packed (3½ ounces) light brown sugar',
    168833,
    'weight',
    '99.22',
    'from 3 1/2 ounce',
  ),
  (
    '0989-lemon-meringue-pie.yaml',
    null,
    3,
    '¼ cup (1 ounce) cornstarch',
    169698,
    'weight',
    '28.35',
    'from 1 ounce',
  ),
  (
    '0177-classic-cranberry-sauce.yaml',
    null,
    0,
    '1 cup (7 ounces) sugar',
    746784,
    'weight',
    '198.45',
    'from 7 ounce',
  ),
  (
    '0072-skillet-tamale-pie.yaml',
    null,
    12,
    '¾ cup (3¾ ounces) yellow cornmeal',
    168039,
    'weight',
    '106.31',
    'from 3 3/4 ounce',
  ),
  (
    '0766-quick-cinnamon-buns-with-buttermilk-icing.yaml',
    null,
    16,
    '1 cup (4 ounces) confectioners’ sugar',
    169656,
    'weight',
    '113.40',
    'from 4 ounce',
  ),
  (
    '0389-cast-iron-pan-pizza.yaml',
    null,
    0,
    '2 cups (11 ounces) bread flour',
    168913,
    'weight',
    '311.84',
    'from 11 ounce',
  ),
  (
    '0259-miso-marinated-salmon.yaml',
    null,
    1,
    '¼ cup sugar',
    746784,
    'portion',
    '47.00',
    '1/4 cup · USDA portion',
  ),
  (
    '1176-red-lentil-kibbeh.yaml',
    null,
    9,
    '¾ cup dried red lentils, picked over and rinsed',
    174284,
    'portion',
    '144.00',
    '3/4 cup · USDA portion',
  ),
];

/// Rows the brief's census did not enumerate (its density-source rows on
/// each key's own records), moved by the same figures — pinned as the
/// replay moves them, for the orchestrator's ruling (fix89/closer1.md and
/// closer2.md D1): EVERY one of the 28 that [lineGrams] weighs alone — 27;
/// the 28th, shrimp-pad-thai|3's step print (38.71 g), is nutrition_v71's
/// RE-PIN. The 21 "plus" parts (brown sugar 2 on SR 168833, sugar 19 on
/// Foundation 746784: 18 'weight', holiday-eggnog|1 'portion'), the 5 rows
/// 'sugar' sizes on SR 170674 turbinado as a word, chili-con-carne|13 on
/// 2710835 masa harina by the alternative's 'cornstarch'.
const List<_Line> _beyond = [
  // v88: 172.57 g — the second part's ⅓ cup packed at 0.93; at the print it
  // weighs 66.15 g, its own printed 2⅓ ounces.
  (
    '1166-apple-blackberry-betty.yaml',
    null,
    1,
    '½ cup packed (3½ ounces) plus ⅓ cup packed (2⅓ ounces) light brown sugar, divided',
    168833,
    'weight',
    '165.37',
    'from 3 1/2 ounce + ⅓ cup packed light brown sugar',
  ),
  // v88: 286.43 g — the 7 tablespoons at 0.85.
  (
    '0773-cream-cheese-coffee-cake.yaml',
    null,
    8,
    '1 cup (7 ounces) plus 7 tablespoons sugar',
    746784,
    'weight',
    '285.27',
    'from 7 ounce + 7 tablespoons sugar',
  ),
  // v88: 119.14 g — the record's own ½ cup, its 2 tablespoons at 0.85.
  (
    '0853-holiday-eggnog.yaml',
    null,
    1,
    '½ cup plus 2 tablespoons sugar',
    746784,
    'portion',
    '118.81',
    '1/2 cup · USDA portion + 2 tablespoons sugar',
  ),
  // v88: 41.90 g, unflagged — 'sugar' sizes SR 170674 "Sugar, turbinado"
  // as a word, ahead of its own 'cup' 202 g (0.854; the corpus's one
  // turbinado print, "¾ cup (6 ounces)", is 8 ounces a cup).
  (
    '0927-classic-creme-brulee.yaml',
    null,
    5,
    '8–12 teaspoons turbinado or Demerara sugar',
    170674,
    'density',
    '41.34',
    '8–12 teaspoon ≈ 49 mL · approximate (ATK: 1 cup sugar = 7 ounces)',
  ),
  // v88: 39.92 g — the alternative's 'cornstarch' sizes Foundation 2710835
  // masa harina (portion-less) at its figure.
  (
    '0495-chili-con-carne.yaml',
    null,
    13,
    '5 tablespoons masa harina or 3 tablespoons cornstarch',
    2710835,
    'density',
    '35.44',
    '5 tablespoon ≈ 74 mL · approximate (ATK: 1 cup cornstarch = 4 ounces)',
  ),
  // closer 2 (D1): the other 22, each at the v89 replay (fix89/c2/g1).
  // v88: 126.73 g.
  (
    '0954-apple-crumble.yaml',
    null,
    1,
    '½ cup packed (3½ ounces) plus 2 tablespoons packed dark brown sugar, divided',
    168833,
    'weight',
    '124.03',
    'from 3 1/2 ounce + 2 tablespoons packed dark brown sugar',
  ),
  // v88: 273.20 g.
  (
    '0856-olive-oil-cake.yaml',
    null,
    4,
    '1¼ cups (8¾ ounces) plus 2 tablespoons sugar',
    746784,
    'weight',
    '272.86',
    'from 8 3/4 ounce + 2 tablespoons sugar',
  ),
  // v88: 211.02 g.
  (
    '0866-french-apple-cake.yaml',
    null,
    4,
    '1 cup (7 ounces) plus 1 tablespoon granulated sugar',
    746784,
    'weight',
    '210.85',
    'from 7 ounce + 1 tablespoon granulated sugar',
  ),
  // v88: 273.20 g.
  (
    '0870-best-almond-cake.yaml',
    null,
    6,
    '1¼ cups (8¾ ounces) plus 2 tablespoons sugar',
    746784,
    'weight',
    '272.86',
    'from 8 3/4 ounce + 2 tablespoons sugar',
  ),
  // v88: 161.40 g.
  (
    '0922-classic-bread-pudding.yaml',
    null,
    1,
    '¾ cup (5¼ ounces) plus 1 tablespoon granulated sugar',
    746784,
    'weight',
    '161.24',
    'from 5 1/4 ounce + 1 tablespoon granulated sugar',
  ),
  // v88: 124.36 g.
  (
    '0944-raspberry-sorbet.yaml',
    null,
    4,
    '½ cup (3½ ounces) plus 2 tablespoons sugar',
    746784,
    'weight',
    '124.03',
    'from 3 1/2 ounce + 2 tablespoons sugar',
  ),
  // v88: 74.75 g.
  (
    '0957-easy-apple-strudel.yaml',
    null,
    6,
    '¼ cup (1¾ ounces) plus 2 tablespoons granulated sugar',
    746784,
    'weight',
    '74.42',
    'from 1 3/4 ounce + 2 tablespoons granulated sugar',
  ),
  // v88: 149.50 g.
  (
    '0965-berry-fool.yaml',
    null,
    2,
    '½ cup (3½ ounces) plus 4 tablespoons sugar',
    746784,
    'weight',
    '148.84',
    'from 3 1/2 ounce + 4 tablespoons sugar',
  ),
  // v88: 223.58 g.
  (
    '0966-rhubarb-fool.yaml',
    null,
    2,
    '1 cup (7 ounces) plus 2 tablespoons sugar',
    746784,
    'weight',
    '223.25',
    'from 7 ounce + 2 tablespoons sugar',
  ),
  // v88: 161.40 g.
  (
    '0977-classic-apple-pie.yaml',
    null,
    2,
    '¾ cup (5¼ ounces) plus 1 tablespoon sugar',
    746784,
    'weight',
    '161.24',
    'from 5 1/4 ounce + 1 tablespoon sugar',
  ),
  // v88: 111.79 g.
  (
    '0978-deep-dish-apple-pie.yaml',
    null,
    4,
    '½ cup (3½ ounces) plus 1 tablespoon granulated sugar',
    746784,
    'weight',
    '111.63',
    'from 3 1/2 ounce + 1 tablespoon granulated sugar',
  ),
  // v88: 136.93 g.
  (
    '0982-fresh-peach-pie.yaml',
    null,
    1,
    '½ cup (3½ ounces) plus 3 tablespoons sugar',
    746784,
    'weight',
    '136.43',
    'from 3 1/2 ounce + 3 tablespoons sugar',
  ),
  // v88: 111.79 g.
  (
    '1005-free-form-apple-tart.yaml',
    null,
    2,
    '½ cup (3½ ounces) plus 1 tablespoon sugar',
    746784,
    'weight',
    '111.63',
    'from 3 1/2 ounce + 1 tablespoon sugar',
  ),
  // v88: 124.36 g.
  (
    '1006-peach-tarte-tatin.yaml',
    null,
    2,
    '½ cup (3½ ounces) plus 2 tablespoons sugar',
    746784,
    'weight',
    '124.03',
    'from 3 1/2 ounce + 2 tablespoons sugar',
  ),
  // v88: 111.79 g.
  (
    '1104-banana-muffins-with-coconut-and-macadamia.yaml',
    null,
    7,
    '½ cup (3½ ounces) plus 1 tablespoon sugar, divided',
    746784,
    'weight',
    '111.63',
    'from 3 1/2 ounce + 1 tablespoon sugar',
  ),
  // v88: 136.93 g.
  (
    '1115-fresh-peach-pie-with-all-butter-lattice-top.yaml',
    null,
    1,
    '½ cup (3½ ounces) plus 3 tablespoons sugar',
    746784,
    'weight',
    '136.43',
    'from 3 1/2 ounce + 3 tablespoons sugar',
  ),
  // v88: 260.63 g.
  (
    '1116-cranberry-curd-tart-with-almond-crust.yaml',
    null,
    1,
    '1¼ cups (8¾ ounces) plus 1 tablespoon sugar, divided',
    746784,
    'weight',
    '260.46',
    'from 8 3/4 ounce + 1 tablespoon sugar',
  ),
  // v88: 322.81 g.
  (
    '1203-salted-caramel-apple-pie.yaml',
    null,
    1,
    '1½ cups (10½ ounces) plus 2 tablespoons sugar, divided',
    746784,
    'weight',
    '322.48',
    'from 10 1/2 ounce + 2 tablespoons sugar',
  ),
  // v88: 16.76 g.
  (
    '0834-sables-french-butter-cookies.yaml',
    null,
    7,
    '4 teaspoons turbinado sugar',
    170674,
    'density',
    '16.54',
    '4 teaspoon ≈ 20 mL · approximate (ATK: 1 cup sugar = 7 ounces)',
  ),
  // v88: 16.76 g.
  (
    '0928-sous-vide-creme-brulee.yaml',
    null,
    5,
    '4 teaspoons turbinado or Demerara sugar',
    170674,
    'density',
    '16.54',
    '4 teaspoon ≈ 20 mL · approximate (ATK: 1 cup sugar = 7 ounces)',
  ),
  // v88: 6.28 g.
  (
    '1000-linzertorte.yaml',
    null,
    14,
    '1½ teaspoons turbinado or Demerara sugar (optional)',
    170674,
    'density',
    '6.20',
    '1 1/2 teaspoon ≈ 7 mL · approximate (ATK: 1 cup sugar = 7 ounces)',
  ),
  // v88: 25.14 g.
  (
    '1166-fruit-hand-pies.yaml',
    null,
    7,
    '2 tablespoons demerara or turbinado sugar (optional)',
    170674,
    'density',
    '24.81',
    '2 tablespoon ≈ 30 mL · approximate (ATK: 1 cup sugar = 7 ounces)',
  ),
];

/// closer 2 (D2 / D3), each recipe computed whole in its own database (its
/// section children first; its others before it): the rows the replay moves
/// through a routed child or a shared budget that the brief does not
/// enumerate and no earlier pin holds — the two-key rows (D2: each key's
/// revert alone moves part of the row) and the section-routed hosts (D3) —
/// (file, position, others, gram source, grams, basis), the v89 replay's
/// (fix89/c2/g1). barbecued-pulled-pork|1, the third two-key row, is the
/// Dry Rub's own total below (its other sections need an unrecorded search).
typedef _Host = (String, int, List<String>, String, String, String);
const List<_Host> _hosts = [
  // D2 + D3: Golden Cornbread — sugar and cornmeal (v88: 1167.82 g, 2537.91 kcal → 2454.01 kcal).
  (
    '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml',
    4,
    <String>[],
    'recipe',
    '1145.93',
    'from the recipe Golden Cornbread: 1146 g, 2,454 kcal',
  ),
  // D2: the batter oil — cornstarch and cornmeal (v88: 73.30 g, 659.70 kcal → 591.66 kcal).
  (
    '0672-buffalo-cauliflower-bites.yaml',
    4,
    <String>[],
    'discarded',
    '65.74',
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed — derived: 14.49 % of the raw cauliflower's weight — USDA FNDDS 2710042 recipe: 12 g oil per 39.58 g raw cauliflower, scaled to the recipe's batter (109.56 g of 229.20 g carbohydrate))",
  ),
  // D3: Spicy Peanut Dipping Sauce (v88: 262.00 g, 932.91 kcal → 927.78 kcal).
  (
    '0515-beef-satay.yaml',
    8,
    <String>[],
    'recipe',
    '260.60',
    // RE-PIN (M86 batch, v90, 958: the sauce's 2262072 peanut butter): was
    // 928 kcal.
    'from the recipe Spicy Peanut Dipping Sauce: 261 g, 873 kcal',
  ),
  // D3: foolproof-double-crust-pie-dough's Foolproof Single-Crust Pie Dough (v88: 357.00 g, 1824.22 kcal → 1823.58 kcal).
  (
    '0985-fresh-strawberry-pie.yaml',
    0,
    ['0974-foolproof-double-crust-pie-dough.yaml'],
    'recipe',
    '356.90',
    'from the recipe Foolproof Single-Crust Pie Dough: 357 g, 1,824 kcal',
  ),
  // D3: Orange Salsa with Cuban Flavors (v88: 825.70 g, 523.96 kcal → 520.54 kcal).
  (
    '0607-grill-roasted-bone-in-pork-rib-roast.yaml',
    4,
    <String>[],
    'recipe',
    '824.80',
    'from the recipe Orange Salsa with Cuban Flavors: 825 g, 521 kcal',
  ),
  // D3: Pub-Style Burger Sauce (v88: 235.30 g, 1213.57 kcal → 1208.45 kcal).
  (
    '0312-juicy-pub-style-burgers.yaml',
    5,
    <String>[],
    'recipe',
    '233.90',
    'from the recipe Pub-Style Burger Sauce: 234 g, 1,208 kcal',
  ),
  // D3: Spice Rub (v88: 79.80 g, 205.38 kcal → 195.13 kcal).
  (
    '0614-memphis-style-barbecued-spareribs.yaml',
    0,
    <String>[],
    'recipe',
    '77.10',
    'from the recipe Spice Rub: 77 g, 195 kcal',
  ),
  // D3: Curtido (v88: 893.50 g, 316.59 kcal → 315.95 kcal).
  (
    '1101-pupusas-with-quick-salsa-and-curtido.yaml',
    7,
    <String>[],
    'recipe',
    '893.40',
    // RE-PIN (M86 batch, v90, 958: the Curtido's 2346407 cabbage, 2258586
    // carrot): was 316 kcal.
    'from the recipe Curtido: 893 g, 299 kcal',
  ),
  // D3: Slab Pie Dough (v88: 761.30 g, 3963.66 kcal → 3962.38 kcal).
  (
    '1204-triple-berry-slab-pie-with-ginger-lemon-streusel.yaml',
    0,
    <String>[],
    'recipe',
    '761.00',
    'from the recipe Slab Pie Dough: 761 g, 3,962 kcal',
  ),
];

void main() {
  test('matcherVersion 85 (v89 set it to 84, batch M90: rows move)', () {
    // RE-PIN (M86 batch, v90): matcherVersion 85 (was 84).
    expect(matcherVersion, 85);
  });

  test("the six keys' figures are the corpus's printed cups, oz × 28.3495 ÷ "
      '236.588 (every spelling); the closed and neighbouring keys keep '
      'theirs', () {
    for (final (item, ounces) in [
      ('brown sugar', 7.0),
      ('light brown sugar', 7.0),
      ('cornstarch', 4.0),
      ('sugar', 7.0),
      ('granulated sugar', 7.0),
      ('cornmeal', 5.0),
      ('confectioners sugar', 4.0),
      ('powdered sugar', 4.0),
      ('bread flour', 5.5),
    ]) {
      expect(densityOf(item), ounces * 28.3495 / 236.588, reason: item);
    }
    expect((7 * 28.3495 / 236.588).toStringAsFixed(4), '0.8388');
    expect((4 * 28.3495 / 236.588).toStringAsFixed(4), '0.4793');
    expect((5 * 28.3495 / 236.588).toStringAsFixed(4), '0.5991');
    expect((5.5 * 28.3495 / 236.588).toStringAsFixed(4), '0.6590');
    // CLOSED (the brief): cake flour keeps its 0.46 (no unprinted row);
    // tapioca starch v49's own print; any other starch the food-free
    // medium figure (RULE B, 169698's cup).
    expect(densityOf('cake flour'), 0.46);
    expect(densityOf('tapioca starch'), 3 * 28.3495 / (0.75 * 236.588));
    expect(densityOf('potato starch'), 0.54);
    // RULE B's medium thresholds read the same figures (engine
    // `_mediumMl`): ¼ cup of cornstarch is 28.35 g, of sugar 49.61 g.
    expect(
      (densityOf('cornstarch')! * 236.588 / 4).toStringAsFixed(2),
      '28.35',
    );
    expect((densityOf('sugar')! * 236.588 / 4).toStringAsFixed(2), '49.61');
  });

  group("lineGrams on each row's own record", skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;
    final ids = <String, String>{};

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('salt-v89-');
      db = SaltDatabase.open(
        ServerConfig(
          dataDir: tempDir.path,
          logLevel: Level.WARNING,
          trustProxy: false,
        ).dbPath,
      )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: {...pendingSearches});
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    Future<void> expectLines(List<_Line> lines) async {
      for (final (file, section, position, raw, fdcId, source, grams, basis)
          in lines) {
        final id = ids.putIfAbsent(file, () {
          final recipe = loadCorpusRecipe(file);
          db.upsertRecipe(recipe, sourceSlug: _source, contentHash: recipe.id);
          return recipe.id;
        });
        final recipe = section == null
            ? db.recipeByIdOrSlug(id)!.recipe
            : nutritionRecipeOf(db, sectionKeyOf(id, section))!.recipe;
        final line = nutritionLines(recipe)[position];
        final reason = '$file|${section ?? ''}|$position';
        final food = await provider.food(fdcId);
        expect(food?.fdcId, fdcId, reason: reason);
        final weighed = lineGrams(db, line, food, recipe: recipe);
        expect(line.raw, raw, reason: reason);
        expect(
          (
            weighed?.source.name,
            weighed?.grams.toStringAsFixed(2),
            weighed?.basis,
          ),
          (source, grams, basis),
          reason: reason,
        );
      }
    }

    test('one stated corpus row per key spelling, at its print and flagged '
        'with it', () async {
      expect(_keys, hasLength(7));
      await expectLines(_keys);
    });

    test('the converses: a weight-printed line per key, a cup-unit sugar line '
        "on 746784's own cup, a Z5 recordFirst lentil — v88's rows", () async {
      expect(_converses, hasLength(8));
      await expectLines(_converses);
    });

    test(
      "beyond the brief's enumerated reach (ruled ACCEPT, fix89/ruling4.md): the "
      '21 plus parts, the 5 turbinado rows, masa harina by the '
      "alternative's word",
      () async {
        // RE-PIN (M90 batch, v89, closer 2 D1): was the first 5 of these.
        expect(_beyond, hasLength(27));
        await expectLines(_beyond);
      },
    );
  });

  group('matcher v89 (batch M90) — whole recipes', skip: skipIfNoCorpus, () {
    // Each recipe in its own fresh database (a detail another recipe's
    // compute caches would change what an earlier recipe's rows read).
    final dbs = <String, SaltDatabase>{};
    late FixtureProvider fdc;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      fdc = FixtureProvider(pending: {...pendingSearches});
      for (final file in _totals.keys) {
        final dir = Directory.systemTemp.createTempSync('salt-v89-');
        final db = dbs[file] = SaltDatabase.open(
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
        recipes[file] = await _compute(db, fdc, loadCorpusRecipe(file));
      }
    });

    test("dakgangjeong's coat on the combined figure (§0.5 order row: M82's "
        're-solve, then the cornstarch at its print): the flour |8 42.32 g '
        'and the cornstarch |9 6.35 g, `discarded`', () {
      final db = dbs[_wings]!;
      final id = recipes[_wings]!.id;
      expect(
        [
          for (final position in [8, 9])
            () {
              final row = _row(db, id, position);
              return (
                row.fdcId,
                row.gramSource,
                row.grams?.toStringAsFixed(2),
              );
            }(),
        ],
        // v88: 41.53 and 7.02 g (M82's figures; 40.36 and 8.01 at v82).
        [(789890, 'discarded', '42.32'), (169698, 'discarded', '6.35')],
      );
    });

    test("the totals: the chutney's brown sugar at its print (a6 R18, the "
        "replay's 471.63 → 444.30 per serving), the wings' coat", () {
      for (final MapEntry(key: file, value: want) in _totals.entries) {
        final n = dbs[file]!.nutritionFor(recipes[file]!.id)!;
        expect(
          (n.status, n.caloriesPerServing?.toStringAsFixed(2)),
          want,
          reason: file,
        );
      }
    });

    test('a second compute writes nothing: every row and total as the first '
        'compute left it', () async {
      for (final file in recipes.keys) {
        final id = recipes[file]!.id;
        final db = dbs[file]!;
        List<Object?> rowsOf() => [
          for (final m in db.ingredientMatchesFor(id))
            (m.position, m.fdcId, m.grams, m.gramSource, m.status, m.hold),
        ];
        final rows = rowsOf();
        final totals = db.nutritionFor(id)!.totalsJson;
        expect(
          await matchAndCompute(db, fdc, nutritionRecipeOf(db, id)!.recipe),
          isNull,
        );
        expect(rowsOf(), rows, reason: file);
        expect(db.nutritionFor(id)!.totalsJson, totals, reason: file);
      }
    });
  });

  group(
    'closer 2 — the two-key rows (D2) and the section-routed hosts (D3)',
    skip: skipIfNoCorpus,
    () {
      SaltDatabase fresh() {
        final dir = Directory.systemTemp.createTempSync('salt-v89-');
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

      test(
        'each row at the v89 replay, its recipe computed whole',
        () async {
          expect(_hosts, hasLength(9));
          for (final (file, position, others, source, grams, basis) in _hosts) {
            final db = fresh();
            final fdc = FixtureProvider(pending: {...pendingSearches});
            for (final other in others) {
              await _compute(db, fdc, loadCorpusRecipe(other));
            }
            final recipe = await _compute(db, fdc, loadCorpusRecipe(file));
            final row = _row(db, recipe.id, position);
            expect(
              (
                row.gramSource,
                row.grams?.toStringAsFixed(2),
                gramBasisFor(
                  db,
                  nutritionLines(recipe)[position],
                  row,
                  recipe: recipe,
                ),
              ),
              (source, grams, basis),
              reason: '$file|$position',
            );
          }
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      test('barbecued-pulled-pork|1 (D2: brown sugar and sugar) reads 0.75 of '
          'the Dry Rub: its total at the v89 replay', () async {
        // The replay's host row: 112.43 g, 276.96 kcal (v88: 114.60 g, 285.12
        // kcal); the Dry Rub v88: 152.80 g, 380.17 kcal. Brown sugar's revert
        // alone gives back −7.69 kcal of the row, sugar's −0.48 (c2/twokey.txt).
        final db = fresh();
        final fdc = FixtureProvider(pending: {...pendingSearches});
        final recipe = loadCorpusRecipe('0609-barbecued-pulled-pork.yaml');
        db.upsertRecipe(
          recipe,
          sourceSlug: _source,
          contentHash: contentHashOf(recipe),
        );
        final key = sectionKeyOf(recipe.id, 'Dry Rub for Barbecue');
        expect(
          await matchAndCompute(db, fdc, nutritionRecipeOf(db, key)!.recipe),
          isNull,
        );
        final n = db.nutritionFor(key)!;
        expect(
          (
            n.status,
            n.totalGrams?.toStringAsFixed(2),
            n.caloriesPerServing?.toStringAsFixed(2),
          ),
          ('complete', '149.90', '369.28'),
        );
      });
    },
  );

  // RULE C: M90 adds no reader — a density-table change: the six figures
  // and their `_approximateDensities` entries are read by the volume arm
  // `lineGrams` already walks (one `_densityOf` per amount; nothing
  // memoized is touched). The cap shapes (STATED, the house's exception:
  // 400 repeated real lines under the real steps of the line's own recipe),
  // each through the compute (matchAndCompute) and the GET (gramBasisFor on
  // every stored row): TRUE — 400 × gingerbread-layer-cake|2 "3 tablespoons
  // cornstarch" (every row on 169698 at the print, flagged); QUIET — 400 ×
  // red-lentil-kibbeh|9 "¾ cup dried red lentils, picked over and rinsed"
  // (Z5 recordFirst: the record's own cup). Counts: each shape's map
  // exactly, EQUAL to base d02f207's (the process-wide `names` aside).
  // Clocks (fix89 closer 1, two runs each, base → tree): TRUE 382 / 367 →
  // 381 / 360 ms, QUIET 458 / 479 → 449 / 453 ms — each under the
  // backstop; the TRUE rows weigh 23.95 g at base (no flag), 21.26 g here.
  group('RULE C, the printed densities at the caps', skip: skipIfNoCorpus, () {
    final shapes = {
      'M90-TRUE': (
        _gingerbread,
        '3 tablespoons cornstarch',
        169698,
        '3 tablespoon ≈ 44 mL · approximate (ATK: 1 cup cornstarch = 4 ounces)',
      ),
      'M90-QUIET': (
        '1176-red-lentil-kibbeh.yaml',
        '¾ cup dried red lentils, picked over and rinsed',
        174284,
        '3/4 cup · USDA portion',
      ),
    };
    for (final MapEntry(key: shape, value: (file, raw, fdcId, basis))
        in shapes.entries) {
      test('$shape: 400 rows on $fdcId, every one weighed; the counts exact, '
          'within the backstop', () async {
        final dir = Directory.systemTemp.createTempSync('salt-v89-');
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
        final fdc = FixtureProvider(pending: {...pendingSearches});
        final p = parseIngredientLine(raw);
        final r = loadCorpusRecipe(file).copyWith(
          ingredients: [
            IngredientGroup(
              items: [
                for (var i = 0; i < 400; i++)
                  IngredientLine(
                    raw: raw,
                    item: p.item,
                    prep: p.prep,
                    amounts: p.amounts,
                  ),
              ],
            ),
          ],
        );
        db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
        final stored = db.recipeByIdOrSlug(r.id)!.recipe;
        stepIndexCounts.clear();
        final sw = Stopwatch()..start();
        expect(await matchAndCompute(db, fdc, stored), isNull);
        final rows = db.ingredientMatchesFor(stored.id);
        final lines = nutritionLines(stored);
        final bases = {
          for (final row in rows)
            gramBasisFor(db, lines[row.position], row, recipe: stored),
        };
        final ms = sw.elapsedMilliseconds;
        final counts = Map.of(stepIndexCounts)..remove('names');
        expectBounded(stored, counts, shape);
        expect(
          (
            rows.length,
            rows.where((m) => m.fdcId == fdcId).length,
            rows.where((m) => m.grams != null).length,
            bases.single,
          ),
          (400, 400, 400, basis),
          reason: shape,
        );
        expect(counts, _capCounts[shape], reason: shape);
        expect(ms, lessThan(backstopMs), reason: shape);
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
  });
}

/// [r] stored and computed (its section children first).
Future<Recipe> _compute(
  SaltDatabase db,
  NutritionProvider fdc,
  Recipe r,
) async {
  db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
  final stored = db.recipeByIdOrSlug(r.id)!.recipe;
  for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
    expect(
      await matchAndCompute(db, fdc, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }
  expect(await matchAndCompute(db, fdc, stored), isNull);
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

IngredientMatchRow _row(SaltDatabase db, String id, int position) =>
    db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

/// Each recipe's (status, kcal per serving) — the fresh compute; the v89
/// replay's in the comment (v88's before the arrow).
const Map<String, (String, String)> _totals = {
  // RE-PIN (M86 batch, v90, 958: 1750342 Granny Smith apples): was 444.30
  // (the v90 replay 444.30 → 437.12).
  _chutney: ('complete', '437.12'), // replay 471.63 → 444.30
  // The fresh compute in its own database; the replay's 513.09 → 512.69
  // (other rows' search-hit energies recorded from earlier snapshots differ
  // from the library's; the coat rows |8 |9 are the replay's, above).
  // RE-PIN (M86 batch, v90, 958: 2727568 chicken): was 513.46.
  _wings: ('complete', '521.96'),
};

/// Each cap shape's counts on the tree — equal to base d02f207's (fix89
/// c1/cap_base_{1,2}.log and cap_tip_{1,2}.log; the process-wide `names`
/// aside): the steps read once per index, the sentences and words of each
/// recipe's own steps.
const Map<String, int> _shared = {
  'allSentences': 1,
  'cheese': 1,
  'heads': 1,
  'indexes': 1,
  'lower': 1,
  'memo:braise': 1,
  'memo:brineWords': 1,
  'memo:brines': 1,
  'memo:cutShare': 1,
  'memo:dips': 1,
  'memo:discards': 1,
  'memo:keptSolids': 1,
  'memo:leftInBowl': 1,
  'memo:liftedFromMarinade': 1,
  'memo:naming': 1,
  'memo:panFatLines': 1,
  'memo:parting': 1,
  'memo:pourAway': 1,
  'memo:reservedWhole': 1,
  'memo:savesRemainder': 1,
  'memo:setAsideLine': 1,
  'memo:skinSentences': 1,
  'memo:starter': 1,
  'memo:strain': 1,
  'memo:strainAt': 1,
  'memo:wordHeads': 1,
};
const Map<String, Map<String, int>> _capCounts = {
  'M90-TRUE': {..._shared, 'sentences': 28, 'words': 340},
  'M90-QUIET': {..._shared, 'sentences': 12, 'words': 149},
};
