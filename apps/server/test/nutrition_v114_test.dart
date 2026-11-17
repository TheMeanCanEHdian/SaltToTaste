// The v114 pins (batch M101, prep52 P3: egg parts, each on its own record;
// matcherVersion 100). The owner's answer 2026-11-16 ("Split, with new
// label"): an egg line naming two DIFFERENT parts ("2 large eggs plus 2
// large yolks"; either order) counts each part on its OWN record at the
// piece table's weight — the whole egg 748967 (50 g), the yolk 748236
// (17 g), the white 747997 (33 g) — as a two-part row (`parts`, the roles
// the part words `egg` / `yolk` / `white` in the line's order); it reverses
// checkpoint 5's sum on the whole egg, and a line led by a part is no
// longer held. The pair path, citrus-only before (five sites):
// `secondFoodRuleOf`'s egg arm, `_pairOf`'s gate, `withParts`' roles,
// `_gramBasis`' join (each from the rule), and the handlers'
// `_heldOnOther` (a rule's second role).
// Corpus-backed groups skip without SALT_CORPUS_DIR; every corpus read sits
// inside a test body (the loader never reads the corpus). The corpusless
// groups compute synthesized one-line recipes on the fixtures' copies of
// snapshot 33's 748967 / 748236 / 747997 details (each STATED where it is
// synthesized).
//
// Hand derivation of every moved row (the replay's on snapshot 33, v113 →
// v114): count × the piece weight × the part record's kcal per 100 g in the
// engine's order (nutrient 208 on all three: 748967 148, 748236 334, 747997
// 55). E.g. fresh-pasta|1 "2 large eggs plus 6 large yolks" = 2 × 50 × 1.48
// + 6 × 17 × 3.34 = 148.00 + 340.68 = 488.68 (was 202 g × 1.48 = 298.96);
// chilled-lemon-souffle|4 "5 large egg whites plus 2 large egg yolks" = 5 ×
// 33 × 0.55 + 2 × 17 × 3.34 = 90.75 + 113.56 = 204.31 (was held, 0); every
// row's figure below is that product, and [_handKcal] re-derives it.
// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'nutrition_v28_rule_a_test.dart' as v28;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

final _fx = FixtureProvider(pending: pendingSearches);

const _egg = 748967;
const _yolk = 748236;
const _white = 747997;

/// Each part record's kcal per 100 g (nutrient 208; the fixtures' copies of
/// snapshot 33's details) — pinned against [kcalPer100g] in `records`.
const _kcalOf = {_egg: 148.0, _yolk: 334.0, _white: 55.0};

const _second =
    "USDA has no record of this line's second food to count — pick "
    'another food or skip the line.';

/// THE 46 ROWS (file, position, raw, record, stored confidence, grams, kcal,
/// basis, first part (record, grams, role), second part, v113 kcal) — the
/// replay's on snapshot 33 (v113 → v114), status `auto`, unheld, no
/// `held_on`, gram source `piece` on every one.
const _moved = [
  (
    '0005-avgolemono-greek-chicken-and-rice-soup-with-egg-and-lemon.yaml',
    9,
    '2 large eggs plus 2 large yolks',
    748967,
    '0.920000',
    '134.00',
    '261.56',
    '2 × 50 g egg + 2 × 17 g yolk, each on its own record',
    (748967, '100.00', 'egg'),
    (748236, '34.00', 'yolk'),
    '198.32',
  ),
  (
    '0324-fresh-pasta-without-a-machine.yaml',
    1,
    '2 large eggs plus 6 large yolks',
    748967,
    '0.920000',
    '202.00',
    '488.68',
    '2 × 50 g egg + 6 × 17 g yolk, each on its own record',
    (748967, '100.00', 'egg'),
    (748236, '102.00', 'yolk'),
    '298.96',
  ),
  (
    '0362-foolproof-spaghetti-carbonara.yaml',
    4,
    '3 large eggs plus 1 large yolk',
    748967,
    '0.920000',
    '167.00',
    '278.78',
    '3 × 50 g egg + 1 × 17 g yolk, each on its own record',
    (748967, '150.00', 'egg'),
    (748236, '17.00', 'yolk'),
    '247.16',
  ),
  (
    '0369-hand-rolled-meat-ravioli.yaml',
    1,
    '2 large eggs plus 6 large yolks',
    748967,
    '0.920000',
    '202.00',
    '488.68',
    '2 × 50 g egg + 6 × 17 g yolk, each on its own record',
    (748967, '100.00', 'egg'),
    (748236, '102.00', 'yolk'),
    '298.96',
  ),
  (
    '0447-duchess-potato-casserole.yaml',
    2,
    '1 large egg, separated, plus 2 large yolks',
    748967,
    '0.920000',
    '84.00',
    '187.56',
    '1 × 50 g egg + 2 × 17 g yolk, each on its own record',
    (748967, '50.00', 'egg'),
    (748236, '34.00', 'yolk'),
    '124.32',
  ),
  (
    '0742-quiche-lorraine.yaml',
    2,
    '2 large whole eggs plus 2 large egg yolks',
    748967,
    '0.920000',
    '134.00',
    '261.56',
    '2 × 50 g egg + 2 × 17 g yolk, each on its own record',
    (748967, '100.00', 'egg'),
    (748236, '34.00', 'yolk'),
    '198.32',
  ),
  (
    '0746-lemon-ricotta-pancakes.yaml',
    4,
    '2 large eggs, separated, plus 2 large whites',
    748967,
    '0.920000',
    '166.00',
    '184.30',
    '2 × 50 g egg + 2 × 33 g white, each on its own record',
    (748967, '100.00', 'egg'),
    (747997, '66.00', 'white'),
    '245.68',
  ),
  (
    '0762-bran-muffins.yaml',
    7,
    '1 large whole egg plus 1 large egg yolk',
    748967,
    '0.920000',
    '67.00',
    '130.78',
    '1 × 50 g egg + 1 × 17 g yolk, each on its own record',
    (748967, '50.00', 'egg'),
    (748236, '17.00', 'yolk'),
    '99.16',
  ),
  (
    '0769-perfect-sticky-buns.yaml',
    3,
    '1 large egg plus 1 large yolk',
    748967,
    '0.920000',
    '67.00',
    '130.78',
    '1 × 50 g egg + 1 × 17 g yolk, each on its own record',
    (748967, '50.00', 'egg'),
    (748236, '17.00', 'yolk'),
    '99.16',
  ),
  (
    '0771-new-yorkstyle-crumb-cake.yaml',
    11,
    '1 large whole egg plus 1 large egg yolk',
    748967,
    '0.920000',
    '67.00',
    '130.78',
    '1 × 50 g egg + 1 × 17 g yolk, each on its own record',
    (748967, '50.00', 'egg'),
    (748236, '17.00', 'yolk'),
    '99.16',
  ),
  (
    '0772-coffee-cake-with-pecan-cinnamon-streusel.yaml',
    15,
    '1 large egg plus 1 large yolk',
    748967,
    '0.920000',
    '67.00',
    '130.78',
    '1 × 50 g egg + 1 × 17 g yolk, each on its own record',
    (748967, '50.00', 'egg'),
    (748236, '17.00', 'yolk'),
    '99.16',
  ),
  (
    '0789-fresh-corn-cornbread.yaml',
    9,
    '2 large eggs plus 1 large yolk',
    748967,
    '0.920000',
    '117.00',
    '204.78',
    '2 × 50 g egg + 1 × 17 g yolk, each on its own record',
    (748967, '100.00', 'egg'),
    (748236, '17.00', 'yolk'),
    '173.16',
  ),
  (
    '0825-classic-chewy-oatmeal-cookies.yaml',
    8,
    '1 large egg plus 1 large yolk',
    748967,
    '0.920000',
    '67.00',
    '130.78',
    '1 × 50 g egg + 1 × 17 g yolk, each on its own record',
    (748967, '50.00', 'egg'),
    (748236, '17.00', 'yolk'),
    '99.16',
  ),
  (
    '0828-gingersnaps.yaml',
    12,
    '1 large egg plus 1 large yolk',
    748967,
    '0.920000',
    '67.00',
    '130.78',
    '1 × 50 g egg + 1 × 17 g yolk, each on its own record',
    (748967, '50.00', 'egg'),
    (748236, '17.00', 'yolk'),
    '99.16',
  ),
  (
    '0841-almond-biscotti.yaml',
    4,
    '2 large eggs, plus 1 large white beaten with pinch salt',
    748967,
    '0.920000',
    '133.00',
    '166.15',
    '2 × 50 g egg + 1 × 33 g white, each on its own record',
    (748967, '100.00', 'egg'),
    (747997, '33.00', 'white'),
    '196.84',
  ),
  (
    '0845-chewy-brownies.yaml',
    6,
    '2 large whole eggs plus 2 large egg yolks',
    748967,
    '0.920000',
    '134.00',
    '261.56',
    '2 × 50 g egg + 2 × 17 g yolk, each on its own record',
    (748967, '100.00', 'egg'),
    (748236, '34.00', 'yolk'),
    '198.32',
  ),
  (
    '0848-best-lemon-bars.yaml',
    8,
    '3 large eggs plus 3 large yolks',
    748967,
    '0.920000',
    '201.00',
    '392.34',
    '3 × 50 g egg + 3 × 17 g yolk, each on its own record',
    (748967, '150.00', 'egg'),
    (748236, '51.00', 'yolk'),
    '297.48',
  ),
  (
    '0853-holiday-eggnog.yaml',
    0,
    '6 large eggs plus 2 large yolks',
    748967,
    '0.920000',
    '334.00',
    '557.56',
    '6 × 50 g egg + 2 × 17 g yolk, each on its own record',
    (748967, '300.00', 'egg'),
    (748236, '34.00', 'yolk'),
    '494.32',
  ),
  (
    '0859-marbled-blueberry-bundt-cake.yaml',
    8,
    '3 large eggs plus 1 large yolk, room temperature',
    748967,
    '0.920000',
    '167.00',
    '278.78',
    '3 × 50 g egg + 1 × 17 g yolk, each on its own record',
    (748967, '150.00', 'egg'),
    (748236, '17.00', 'yolk'),
    '247.16',
  ),
  (
    '0860-lemon-bundt-cake.yaml',
    8,
    '3 large eggs plus 1 large egg yolk, at room temperature',
    748967,
    '0.920000',
    '167.00',
    '278.78',
    '3 × 50 g egg + 1 × 17 g yolk, each on its own record',
    (748967, '150.00', 'egg'),
    (748236, '17.00', 'yolk'),
    '247.16',
  ),
  (
    '0866-french-apple-cake.yaml',
    7,
    '1 large egg plus 2 large yolks',
    748967,
    '0.920000',
    '84.00',
    '187.56',
    '1 × 50 g egg + 2 × 17 g yolk, each on its own record',
    (748967, '50.00', 'egg'),
    (748236, '34.00', 'yolk'),
    '124.32',
  ),
  (
    '0869-spice-cake.yaml',
    10,
    '2 large whole eggs plus 3 large egg yolks, at room temperature',
    748967,
    '0.920000',
    '151.00',
    '318.34',
    '2 × 50 g egg + 3 × 17 g yolk, each on its own record',
    (748967, '100.00', 'egg'),
    (748236, '51.00', 'yolk'),
    '223.48',
  ),
  (
    '0874-raspberry-charlotte.yaml',
    17,
    '1 large egg plus 3 large egg whites (reserved from filling)',
    748967,
    '0.920000',
    '149.00',
    '128.45',
    '1 × 50 g egg + 3 × 33 g white, each on its own record',
    (748967, '50.00', 'egg'),
    (747997, '99.00', 'white'),
    '220.52',
  ),
  (
    '0878-coconut-layer-cake.yaml',
    2,
    '5 large egg whites plus 1 large egg, at room temperature',
    747997,
    '0.950000',
    '215.00',
    '164.75',
    '5 × 33 g white + 1 × 50 g egg, each on its own record',
    (747997, '165.00', 'white'),
    (748967, '50.00', 'egg'),
    '0.00',
  ),
  (
    '0881-lemon-layer-cake-with-fluffy-white-icing.yaml',
    4,
    '4 large whole eggs plus 6 large egg yolks (reserve the egg whites for the cake)',
    748967,
    '0.920000',
    '302.00',
    '636.68',
    '4 × 50 g egg + 6 × 17 g yolk, each on its own record',
    (748967, '200.00', 'egg'),
    (748236, '102.00', 'yolk'),
    '446.96',
  ),
  (
    '0885-fluffy-yellow-layer-cake-with-milk-chocolate-frosting.yaml',
    9,
    '6 large egg yolks plus 3 large egg whites, at room temperature',
    748236,
    '0.950000',
    '201.00',
    '395.13',
    '6 × 17 g yolk + 3 × 33 g white, each on its own record',
    (748236, '102.00', 'yolk'),
    (747997, '99.00', 'white'),
    '297.48',
  ),
  (
    '0886-yellow-sheet-cake-with-chocolate-frosting.yaml',
    0,
    '4 large eggs, plus 2 large yolks',
    748967,
    '0.920000',
    '234.00',
    '409.56',
    '4 × 50 g egg + 2 × 17 g yolk, each on its own record',
    (748967, '200.00', 'egg'),
    (748236, '34.00', 'yolk'),
    '346.32',
  ),
  (
    '0887-old-fashioned-chocolate-layer-cake-with-chocolate-frosting.yaml',
    9,
    '4 large whole eggs plus 2 large egg yolks, at room temperature',
    748967,
    '0.920000',
    '234.00',
    '409.56',
    '4 × 50 g egg + 2 × 17 g yolk, each on its own record',
    (748967, '200.00', 'egg'),
    (748236, '34.00', 'yolk'),
    '346.32',
  ),
  (
    '0905-chocolate-volcano-cakes-with-espresso-ice-cream.yaml',
    7,
    '3 large eggs plus 4 large egg yolks, at room temperature',
    748967,
    '0.920000',
    '218.00',
    '449.12',
    '3 × 50 g egg + 4 × 17 g yolk, each on its own record',
    (748967, '150.00', 'egg'),
    (748236, '68.00', 'yolk'),
    '322.64',
  ),
  (
    '0912-new-york-cheesecake.yaml',
    9,
    '6 large eggs plus 2 large egg yolks, at room temperature',
    748967,
    '0.920000',
    '334.00',
    '557.56',
    '6 × 50 g egg + 2 × 17 g yolk, each on its own record',
    (748967, '300.00', 'egg'),
    (748236, '34.00', 'yolk'),
    '494.32',
  ),
  (
    '0913-foolproof-new-york-cheesecake.yaml',
    11,
    '6 large eggs plus 2 large egg yolks',
    748967,
    '0.920000',
    '334.00',
    '557.56',
    '6 × 50 g egg + 2 × 17 g yolk, each on its own record',
    (748967, '300.00', 'egg'),
    (748236, '34.00', 'yolk'),
    '494.32',
  ),
  (
    '0916-lemon-cheesecake.yaml',
    14,
    '2 large whole eggs plus 1 large egg yolk',
    748967,
    '0.920000',
    '117.00',
    '204.78',
    '2 × 50 g egg + 1 × 17 g yolk, each on its own record',
    (748967, '100.00', 'egg'),
    (748236, '17.00', 'yolk'),
    '173.16',
  ),
  (
    '0917-lemon-pudding-cakes.yaml',
    7,
    '2 large eggs, separated, plus 2 large whites',
    748967,
    '0.920000',
    '166.00',
    '184.30',
    '2 × 50 g egg + 2 × 33 g white, each on its own record',
    (748967, '100.00', 'egg'),
    (747997, '66.00', 'white'),
    '245.68',
  ),
  (
    '0928-classic-creme-caramel.yaml',
    6,
    '3 large eggs, plus 2 large yolks',
    748967,
    '0.920000',
    '184.00',
    '335.56',
    '3 × 50 g egg + 2 × 17 g yolk, each on its own record',
    (748967, '150.00', 'egg'),
    (748236, '34.00', 'yolk'),
    '272.32',
  ),
  (
    '0937-chilled-lemon-souffle.yaml',
    4,
    '5 large egg whites plus 2 large egg yolks, at room temperature',
    747997,
    '0.950000',
    '199.00',
    '204.31',
    '5 × 33 g white + 2 × 17 g yolk, each on its own record',
    (747997, '165.00', 'white'),
    (748236, '34.00', 'yolk'),
    '0.00',
  ),
  (
    '0939-make-ahead-chocolate-souffles.yaml',
    7,
    '6 large egg yolks plus 8 large egg whites',
    748236,
    '0.950000',
    '366.00',
    '485.88',
    '6 × 17 g yolk + 8 × 33 g white, each on its own record',
    (748236, '102.00', 'yolk'),
    (747997, '264.00', 'white'),
    '541.68',
  ),
  (
    '0987-pumpkin-pie.yaml',
    3,
    '3 large whole eggs plus 2 large egg yolks',
    748967,
    '0.920000',
    '184.00',
    '335.56',
    '3 × 50 g egg + 2 × 17 g yolk, each on its own record',
    (748967, '150.00', 'egg'),
    (748236, '34.00', 'yolk'),
    '272.32',
  ),
  (
    '0994-lemon-tart.yaml',
    2,
    '7 large egg yolks plus 2 large whole eggs',
    748236,
    '0.950000',
    '219.00',
    '545.46',
    '7 × 17 g yolk + 2 × 50 g egg, each on its own record',
    (748236, '119.00', 'yolk'),
    (748967, '100.00', 'egg'),
    '0.00',
  ),
  (
    '0995-lemonolive-oil-tart.yaml',
    8,
    '3 large eggs plus 3 large yolks',
    748967,
    '0.920000',
    '201.00',
    '392.34',
    '3 × 50 g egg + 3 × 17 g yolk, each on its own record',
    (748967, '150.00', 'egg'),
    (748236, '51.00', 'yolk'),
    '297.48',
  ),
  (
    '1110-challah.yaml',
    2,
    '1 large egg plus 2 large yolks',
    748967,
    '0.920000',
    '84.00',
    '187.56',
    '1 × 50 g egg + 2 × 17 g yolk, each on its own record',
    (748967, '50.00', 'egg'),
    (748236, '34.00', 'yolk'),
    '124.32',
  ),
  (
    '1129-beef-wellington.yaml',
    17,
    '1 large egg plus 1 large yolk',
    748967,
    '0.920000',
    '67.00',
    '130.78',
    '1 × 50 g egg + 1 × 17 g yolk, each on its own record',
    (748967, '50.00', 'egg'),
    (748236, '17.00', 'yolk'),
    '99.16',
  ),
  (
    '1156-madeleines.yaml',
    2,
    '2 large eggs plus 1 large yolk',
    748967,
    '0.920000',
    '117.00',
    '204.78',
    '2 × 50 g egg + 1 × 17 g yolk, each on its own record',
    (748967, '100.00', 'egg'),
    (748236, '17.00', 'yolk'),
    '173.16',
  ),
  (
    '1157-pistachio-spice-biscotti.yaml',
    9,
    '2 large eggs, plus 1 large white beaten with pinch salt',
    748967,
    '0.920000',
    '133.00',
    '166.15',
    '2 × 50 g egg + 1 × 33 g white, each on its own record',
    (748967, '100.00', 'egg'),
    (747997, '33.00', 'white'),
    '196.84',
  ),
  (
    '1158-choux-au-craquelin.yaml',
    11,
    '2 large eggs plus 1 large white',
    748967,
    '0.920000',
    '133.00',
    '166.15',
    '2 × 50 g egg + 1 × 33 g white, each on its own record',
    (748967, '100.00', 'egg'),
    (747997, '33.00', 'white'),
    '196.84',
  ),
  (
    '1199-profiteroles.yaml',
    0,
    '2 large eggs plus 1 large white',
    748967,
    '0.920000',
    '133.00',
    '166.15',
    '2 × 50 g egg + 1 × 33 g white, each on its own record',
    (748967, '100.00', 'egg'),
    (747997, '33.00', 'white'),
    '196.84',
  ),
  (
    '1202-new-york-cheesecakes.yaml',
    9,
    '1 large egg plus 1 large yolk',
    748967,
    '0.920000',
    '67.00',
    '130.78',
    '1 × 50 g egg + 1 × 17 g yolk, each on its own record',
    (748967, '50.00', 'egg'),
    (748236, '17.00', 'yolk'),
    '99.16',
  ),
];

/// The unavailable wording (an outage) with the second-food replacement.
const _secondDown =
    "USDA could not serve this line's second food — pick another food or "
    'skip the line.';

void main() {
  records();
  rule();
  synthesized();
  group(
    'v114 (M101: egg parts, each on its own record)',
    skip: skipIfNoCorpus,
    () {
      moved();
      statuses();
      machinery();
      unmoved();
      person();
    },
  );
}

/// Count × the piece weight × the part record's kcal per 100 g, summed.
String _handKcal((int, String, String) first, (int, String, String) second) =>
    (double.parse(first.$2) * _kcalOf[first.$1]! / 100 +
            double.parse(second.$2) * _kcalOf[second.$1]! / 100)
        .toStringAsFixed(2);

/// The row's energy as the totals count a two-part row: each part on its
/// own record.
String _kcal(SaltDatabase db, IngredientMatchRow row) {
  var kcal = 0.0;
  for (final part in partsOf(row.parts)) {
    kcal += kcalPer100g(knownFood(db, part.fdcId)!) * part.grams / 100;
  }
  return kcal.toStringAsFixed(2);
}

String _parts((int, String, String) first, (int, String, String) second) =>
    jsonEncode([
      for (final (id, grams, role) in [first, second])
        {'fdc_id': id, 'grams': double.parse(grams), 'role': role},
    ]);

IngredientLine _lineOf(String raw) {
  final parsed = parseIngredientLine(raw);
  return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
}

/// [file] with only its line [position] (its real steps kept) — the egg rule
/// reads the line alone, and the fixtures hold no search answer for most of
/// these recipes' other lines.
Recipe _only(String file, int position) {
  final corpus = loadCorpusRecipe(file);
  return corpus.copyWith(
    ingredients: [
      IngredientGroup(items: [nutritionLines(corpus)[position]]),
    ],
  );
}

/// [r] with its nutrition line [at] replaced by [raw] (STATED synthesized).
Recipe _swapped(Recipe r, int at, String raw) => r.copyWith(
  ingredients: [
    IngredientGroup(
      items: [
        for (final (i, line) in nutritionLines(r).indexed)
          i == at ? _lineOf(raw) : line,
      ],
    ),
  ],
);

/// A one-line synthesized recipe (STATED: the corpusless groups' inputs).
Recipe _synth(String raw) => Recipe(
  id: 'v114',
  title: 'v114',
  slug: 'v114',
  source: const RecipeSource(name: 'Test', type: 'book'),
  ingredients: [
    IngredientGroup(items: [_lineOf(raw)]),
  ],
);

Future<Map<String, Object?>> _matchOf(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe r,
  int at,
) async {
  final body = await matchesBody(db, provider, r);
  final item = (body['items']! as List)[at] as Map<String, Object?>;
  return item['match']! as Map<String, Object?>;
}

Future<String> _confirmRefusal(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe r,
  int at,
) async {
  try {
    await applyMatchOverride(db, provider, r, at, {
      'raw': nutritionLines(r)[at].raw,
      'confirmed': true,
    });
    return 'ACCEPTED';
  } on ValidationException catch (e) {
    return e.message;
  }
}

/// The three part records' energies, as the engine reads them (corpusless:
/// the fixtures' verbatim copies of snapshot 33's details).
void records() {
  test('v114: the part records read 148 / 334 / 55 kcal per 100 g', () async {
    for (final MapEntry(key: id, value: kcal) in _kcalOf.entries) {
      expect(kcalPer100g((await _fx.food(id))!), kcal, reason: '$id');
    }
  });
}

/// The rule (corpusless; the six orders on REAL corpus line texts, parsed as
/// the engine parses them): each part's record, its piece weight, its role
/// and the join of the two bases; the first part's piece-table key the
/// words the row's confidence is ranked under.
void rule() {
  test('v114 rule: every pair of two different parts, either order, each '
      'on its own record at the piece table', () {
    for (final (raw, expected) in [
      // 0324 Fresh Pasta Without a Machine |1.
      (
        '2 large eggs plus 6 large yolks',
        (
          _egg,
          'egg',
          _yolk,
          ('egg', 'yolk'),
          100.0,
          '2 × 50 g egg',
          102.0,
          '6 × 17 g yolk',
        ),
      ),
      // 0746 Lemon Ricotta Pancakes |4.
      (
        '2 large eggs, separated, plus 2 large whites',
        (
          _egg,
          'egg',
          _white,
          ('egg', 'white'),
          100.0,
          '2 × 50 g egg',
          66.0,
          '2 × 33 g white',
        ),
      ),
      // 0885 Fluffy Yellow Layer Cake |9.
      (
        '6 large egg yolks plus 3 large egg whites, at room temperature',
        (
          _yolk,
          'egg yolk',
          _white,
          ('yolk', 'white'),
          102.0,
          '6 × 17 g yolk',
          99.0,
          '3 × 33 g white',
        ),
      ),
      // 0937 Chilled Lemon Soufflé |4 (held `second_food` before v114).
      (
        '5 large egg whites plus 2 large egg yolks, at room temperature',
        (
          _white,
          'egg white',
          _yolk,
          ('white', 'yolk'),
          165.0,
          '5 × 33 g white',
          34.0,
          '2 × 17 g yolk',
        ),
      ),
      // 0994 Lemon Tart |2 (held before v114).
      (
        '7 large egg yolks plus 2 large whole eggs',
        (
          _yolk,
          'egg yolk',
          _egg,
          ('yolk', 'egg'),
          119.0,
          '7 × 17 g yolk',
          100.0,
          '2 × 50 g egg',
        ),
      ),
      // 0878 Coconut Layer Cake |2 (held before v114).
      (
        '5 large egg whites plus 1 large egg, at room temperature',
        (
          _white,
          'egg white',
          _egg,
          ('white', 'egg'),
          165.0,
          '5 × 33 g white',
          50.0,
          '1 × 50 g egg',
        ),
      ),
    ]) {
      final rule = secondFoodRuleOf(_lineOf(raw))!;
      final a = rule.gramsOn(null)!;
      final b = rule.second!.grams(null)!;
      expect(
        (
          rule.fdcId,
          rule.query,
          rule.second!.fdcId,
          rule.roles,
          a.grams,
          a.basis,
          b.grams,
          b.basis,
        ),
        expected,
        reason: raw,
      );
      expect(
        (a.source, b.source),
        (GramSource.piece, GramSource.piece),
        reason: raw,
      );
      expect(
        rule.joinBasis(a.basis!, b.basis!),
        '${expected.$6} + ${expected.$8}, each on its own record',
        reason: raw,
      );
    }
  });

  test('v114 rule: the decision keys are unchanged — either order of yolks '
      'and whites is one key, eggs plus a part its own', () {
    for (final (raw, key) in [
      (
        '6 large egg yolks plus 3 large egg whites, at room temperature',
        'egg yolk plus white',
      ),
      (
        '5 large egg whites plus 2 large egg yolks, at room temperature',
        'egg yolk plus white',
      ),
      ('7 large egg yolks plus 2 large whole eggs', 'egg plus yolk'),
      (
        '5 large egg whites plus 1 large egg, at room temperature',
        'egg plus white',
      ),
      ('2 large eggs plus 6 large yolks', 'egg plus yolk'),
    ]) {
      expect(lineKeyOf(_lineOf(raw)), key, reason: raw);
    }
  });

  test('v114 rule (negative paths): no plus, a same-part pair, a non-count '
      'part and the switch off read no egg rule; the citrus pair keeps its '
      'roles and join', () {
    // Real corpus lines: 0041 |2, 0017 |11 (no plus — the plain egg and the
    // yolk-only line stay on their own record, one food).
    expect(secondFoodRuleOf(_lineOf('3 large eggs')), isNull);
    expect(secondFoodRuleOf(_lineOf('2 large egg yolks')), isNull);
    // STATED synthesized (no corpus line names one part twice, or a part by
    // volume beside a counted part). A same-part pair the plus reader calls
    // ONE food never reaches the egg arm ([namesSecondFood] false); one it
    // calls a second food (another bird's eggs or yolks) does, and the
    // `first == second` gate refuses it — never two parts on one record
    // (the gate dropped returns a rule here: the mutant this pin kills).
    expect(namesSecondFood('2 large egg yolks plus 2 large yolks'), isFalse);
    expect(
      secondFoodRuleOf(_lineOf('2 large egg yolks plus 2 large yolks')),
      isNull,
    );
    for (final raw in [
      '2 large eggs plus 2 quail eggs',
      '2 large egg yolks plus 2 duck yolks',
    ]) {
      expect(namesSecondFood(raw), isTrue, reason: raw);
      expect(secondFoodRuleOf(_lineOf(raw)), isNull, reason: raw);
    }
    expect(
      secondFoodRuleOf(_lineOf('1 cup egg whites plus 2 large eggs')),
      isNull,
    );
    expect(
      secondFoodRuleOf(_lineOf('2 large eggs plus 6 large yolks'), eggs: false),
      isNull,
    );
    // STATED LIMIT, measured (synthesized: no corpus line names three
    // parts): a three-part line reads its first two parts, the third
    // dropped — as base 2318767 did (its sum "2 × 50 g egg + 2 × 17 g
    // yolk, summed on the whole egg", 134 g). The design's "returns null as
    // today" was not so.
    final three = secondFoodRuleOf(
      _lineOf('2 large eggs plus 2 large yolks plus 1 large white'),
    )!;
    expect(
      (
        three.fdcId,
        three.second!.fdcId,
        three.gramsOn(null)!.grams,
        three.second!.grams(null)!.grams,
      ),
      (_egg, _yolk, 100.0, 34.0),
    );
    // The citrus pair (0536 |3's text): zest / juice, its join as before.
    final citrus = secondFoodRuleOf(
      _lineOf(
        '10 (3-inch) strips orange peel, sliced thin lengthwise (¼ cup), '
        'plus ¼ cup juice (2 oranges)',
      ),
      recipe: _synth('x'),
    )!;
    expect(
      (citrus.fdcId, citrus.second!.fdcId, citrus.roles),
      (169103, 169098, ('zest', 'juice')),
    );
    expect(citrus.joinBasis('A', 'B'), 'zest A + juice B');
  });
}

/// Corpusless computes on one-line recipes (STATED synthesized recipes; the
/// line texts real corpus lines unless said).
void synthesized() {
  test('v114 (corpusless): a pair row stores both parts with their roles; '
      "the matches GET's parts carry the citrus pair's keys, only the roles "
      'differ; the top-level record, grams and description are the first '
      "part's record, the parts' sum and that record's", () async {
    final (db, _) = a.pathDb();
    // 0447 Duchess Potato Casserole |2.
    final r = _synth('1 large egg, separated, plus 2 large yolks');
    await d.editAndCompute(db, _fx, r);
    final row = d.rowOf(db, r, 0);
    expect(
      (
        row.fdcId,
        row.description,
        row.grams,
        row.gramSource,
        row.status,
        row.hold,
        row.heldOn,
      ),
      (
        _egg,
        'Eggs, Grade A, Large, egg whole',
        84.0,
        'piece',
        'auto',
        null,
        null,
      ),
    );
    final match = await _matchOf(db, _fx, r, 0);
    expect(match['parts'], [
      {
        'fdc_id': _egg,
        'description': 'Eggs, Grade A, Large, egg whole',
        'data_type': 'Foundation',
        'grams': 50.0,
        'role': 'egg',
      },
      {
        'fdc_id': _yolk,
        'description': 'Eggs, Grade A, Large, egg yolk',
        'data_type': 'Foundation',
        'grams': 34.0,
        'role': 'yolk',
      },
    ]);
    expect(
      match['gram_basis'],
      '1 × 50 g egg + 2 × 17 g yolk, each on its own record',
    );
    // 50 × 1.48 + 34 × 3.34 = 74.00 + 113.56.
    expect(_kcal(db, row), '187.56');
  });

  // [the owner gate's pin; the hand-edit verifier's h7 and h5] no corpus egg
  // pair prints a fractional count, so the basis' decimal branch
  // (`label`) had no pin; and a first amount written as a vulgar fraction
  // alone puts no ASCII digit before "plus".
  test('v114 (corpusless): a fractional count weighs and prints as its '
      'decimal, a vulgar-fraction first amount is read (STATED synthesized: '
      'no corpus egg pair prints a fraction)', () async {
    final (db, _) = a.pathDb();
    final r = _synth('½ large egg plus 1 large yolk');
    await d.editAndCompute(db, _fx, r);
    final row = d.rowOf(db, r, 0);
    expect((row.fdcId, row.grams, row.hold), (_egg, 42.0, null));
    expect(row.parts, _parts((_egg, '25.00', 'egg'), (_yolk, '17.00', 'yolk')));
    expect(
      (await _matchOf(db, _fx, r, 0))['gram_basis'],
      '0.5 × 50 g egg + 1 × 17 g yolk, each on its own record',
    );
  });

  // [the owner gate's pin; hand-edit round 3] the arm of `_gramBasis` that
  // reads the first part's basis takes only a row whose stored grams ARE
  // that part's (within 0.05 g, the joined sum's own tolerance): a row a
  // little off reads the generic weigh. Widened to 60 g the arm passed the
  // whole suite. STATED synthesized: the stored grams are moved by hand —
  // an egg pair's piece weights read no food, so no person path stores them
  // off.
  test('v114 (corpusless): a row storing the first part alone reads that '
      "part's basis only at that part's grams (STATED synthesized: grams "
      '0.04 g and 0.06 g off)', () async {
    final (db, _) = a.pathDb();
    final r = _synth('2 large eggs plus 6 large yolks');
    await d.editAndCompute(db, _fx, r);
    final line = nutritionLines(r).single;
    await applyMatchOverride(db, _fx, r, 0, {'raw': line.raw, 'fdc_id': _egg});
    final row = d.rowOf(db, r, 0);
    expect(
      (row.status, row.grams, row.gramSource, row.parts),
      ('overridden', 100.0, 'piece', null),
    );
    for (final (grams, basis) in [
      (100.0, '2 × 50 g egg'),
      (100.04, '2 × 50 g egg'),
      (100.06, '2 × 50 g each'),
      (99.94, '2 × 50 g each'),
    ]) {
      expect(
        gramBasisFor(db, line, row.copyWith(grams: grams), recipe: r),
        basis,
        reason: '$grams',
      );
    }
  });

  test('v114 (corpusless): the pre-check reads "plus" in any case, as the '
      "rule's own pattern does (STATED synthesized: no corpus line prints "
      '"PLUS")', () async {
    // [the owner gate's pins] the pre-check is a bare find of the word, as
    // weak as the rule's own `\bplus\s+`: no space before it (",plus") and
    // a no-break space after it are read too — narrowed to ' plus ' the
    // whole file passed and the replay was byte-identical (no corpus line
    // prints either), these two left at the first part's 100 g.
    for (final raw in [
      '2 large eggs PLUS 6 large yolks',
      '2 large eggs,plus 6 large yolks',
      '2 large eggs plus 6 large yolks',
    ]) {
      final (db, _) = a.pathDb();
      final r = _synth(raw);
      await d.editAndCompute(db, _fx, r);
      final row = d.rowOf(db, r, 0);
      expect(
        (row.fdcId, row.grams, row.hold),
        (_egg, 202.0, null),
        reason: raw,
      );
      expect(
        row.parts,
        _parts((_egg, '100.00', 'egg'), (_yolk, '102.00', 'yolk')),
        reason: raw,
      );
    }
  });

  test('v114 (corpusless): a plain "3 large eggs" row (0041 |2) stays 150 g '
      'on the whole egg with no parts, and runs no pair rule — the reads of '
      'namesSecondFood across its compute and GET are counted', () async {
    final (db, _) = a.pathDb();
    final r = _synth('3 large eggs');
    secondFoodReads = 0;
    await d.editAndCompute(db, _fx, r);
    final computeReads = secondFoodReads;
    secondFoodReads = 0;
    await matchesBody(db, _fx, r);
    final getReads = secondFoodReads;
    final row = d.rowOf(db, r, 0);
    expect(
      (row.fdcId, row.grams, row.parts, row.hold),
      (_egg, 150.0, null, null),
    );
    // COUNT-PINNED (base == tip, [_plainReads]): the pre-check keeps the
    // widened gate from running the rule on a row with no "plus".
    expect((computeReads, getReads), _plainReads);
  });
}

/// [synthesized]' plain-egg read counts (compute, GET) — measured: 3 and 1
/// on the v114 tree and on base 2318767 alike (`engineOutcome`'s own read,
/// the key reach's and the GET's; the widened gate adds none).
const _plainReads = (3, 1);

/// Every moved row in its real recipe (its line alone, its real steps): the
/// stored record, status, hold, `held_on`, gram source, confidence, grams,
/// both parts (record, grams, role), the energy (each part on its own
/// record, re-derived by hand) and the basis.
void moved() {
  test('the 46 rows: every stored column the rule writes, as the replay '
      'stores it', () async {
    expect(_moved, hasLength(46));
    var signed = 0.0;
    for (final (
          file,
          position,
          raw,
          fdcId,
          confidence,
          grams,
          kcal,
          basis,
          first,
          second,
          before,
        )
        in _moved) {
      final reason = '$file|$position';
      final (db, _) = a.pathDb();
      final r = _only(file, position);
      final line = nutritionLines(r).single;
      expect(line.raw, raw, reason: reason);
      await d.editAndCompute(db, _fx, r);
      final row = d.rowOf(db, r, 0);
      expect(
        (
          row.fdcId,
          row.status,
          row.hold,
          row.heldOn,
          row.gramSource,
          row.confidence.toStringAsFixed(6),
          row.grams?.toStringAsFixed(2),
        ),
        (fdcId, 'auto', null, null, 'piece', confidence, grams),
        reason: reason,
      );
      expect(row.parts, _parts(first, second), reason: reason);
      expect(first.$1, fdcId, reason: '$reason: the first part is the row');
      expect(_kcal(db, row), kcal, reason: reason);
      expect(_handKcal(first, second), kcal, reason: reason);
      expect(gramBasisFor(db, line, row, recipe: r), basis, reason: reason);
      signed += double.parse(kcal) - double.parse(before);
    }
    // The replay's batch delta: +2,863.80 kcal.
    expect(signed.toStringAsFixed(2), '2863.80');
  });
}

/// The three rows held `second_food` before v114 counted: each its recipe's
/// only held row, so the recipe reads `complete` (the replay: partial →
/// complete).
void statuses() {
  test(
    'the three held rows count and their recipes complete (each its '
    "recipe's only held row; the per-serving figures the replay's)",
    () async {
      for (final (file, position, perServing) in [
        ('0937-chilled-lemon-souffle.yaml', 4, 395.35),
        ('0994-lemon-tart.yaml', 2, 471.42),
        ('0878-coconut-layer-cake.yaml', 2, 796.69),
      ]) {
        final (db, _) = a.pathDb();
        // The tart's crust, its sub-recipe line |0.
        await d.editAndCompute(
          db,
          _fx,
          loadCorpusRecipe('0994-classic-tart-dough.yaml'),
        );
        final r = loadCorpusRecipe(file);
        await d.editAndCompute(db, _fx, r);
        final row = d.rowOf(db, r, position);
        expect(
          (row.hold, row.heldOn, partsOf(row.parts).length),
          (null, null, 2),
          reason: file,
        );
        final label = db.nutritionFor(r.id)!;
        expect(label.status, 'complete', reason: file);
        expect(
          label.caloriesPerServing,
          closeTo(perServing, 0.005),
          reason: file,
        );
      }
    },
  );
}

/// Deletes [id]'s DETAIL alone (fdc_food_cache); the search answers that
/// list it stay (STATED synthesized cache state, as v110 X2's: no code
/// evicts fdc_food_cache).
void _dropDetail(String path, int id) {
  sqlite3.open(path)
    ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [id])
    ..dispose();
}

/// One pair of each new SECOND record (the v109 W8 / v110 X2 / v111 Y1 / Y2
/// machinery, on the egg roles): (file, position, first, second).
const _pairs = [
  ('0937-chilled-lemon-souffle.yaml', 4, _white, _yolk),
  ('0994-lemon-tart.yaml', 2, _yolk, _egg),
  ('0746-lemon-ricotta-pancakes.yaml', 4, _egg, _white),
];

/// Each [_pairs] row's FIRST part's own basis — what the GET serves while
/// the row stores that part alone (held on its gone second part).
const _firstBasis = {
  '0937-chilled-lemon-souffle.yaml': '5 × 33 g white',
  '0994-lemon-tart.yaml': '7 × 17 g yolk',
  '0746-lemon-ricotta-pancakes.yaml': '2 × 50 g egg',
};

/// The pair machinery (STATED synthesized cache states and provider
/// answers, as v110 X2 / X3 and v111 Y2 build them).
void machinery() {
  test("the second part's detail absent, FDC answering no such food: held "
      "food_gone ON that part, no parts, the first part's grams stored but "
      "never counted; the GET serves held_on and the confirm reads \"this line's "
      'second food"; its arrival re-opens the row', () async {
    for (final (file, position, first, second) in _pairs) {
      final reason = '$file|$position';
      final (db, path) = a.pathDb();
      final r = _only(file, position);
      await d.editAndCompute(db, _fx, r);
      final counted = d.rowOf(db, r, 0);
      v28.dropFood(path, second);
      db.clearDerivedSeq(r.id, [0]);
      final gone = v28.FoodFault(_fx, {second}, gone: true);
      await matchAndCompute(db, gone, r);
      final held = d.rowOf(db, r, 0);
      // The first part's grams stay on the held row (the citrus pair's
      // shape, v109 W8's `copyWith`): a `food_gone` row is never counted.
      expect(
        (
          held.status,
          held.fdcId,
          held.hold,
          held.heldOn,
          held.grams,
          held.parts,
        ),
        (
          'auto',
          first,
          'food_gone',
          second,
          partsOf(counted.parts).first.grams,
          null,
        ),
        reason: reason,
      );
      // Its recipe (the line alone) counts nothing: partial, no energy.
      final label = db.nutritionFor(r.id)!;
      expect(
        (label.status, label.caloriesPerServing),
        ('partial', null),
        reason: reason,
      );
      final match = await _matchOf(db, gone, r, 0);
      expect(
        (match['hold'], match['held_on']),
        ('food_gone', second),
        reason: reason,
      );
      // [the owner gate's pin] the held row's basis is the stored first
      // part's own, as its grams are.
      expect(match['gram_basis'], _firstBasis[file], reason: reason);
      expect(await _confirmRefusal(db, gone, r, 0), _second, reason: reason);
      // The arrival.
      await cachedFood(db, _fx, second);
      expect(nutritionIsFresh(db, r), isFalse, reason: reason);
      await matchAndCompute(db, _fx, r);
      final healed = d.rowOf(db, r, 0);
      expect(
        (healed.hold, healed.heldOn, healed.grams, healed.parts),
        (null, null, counted.grams, counted.parts),
        reason: reason,
      );
    }
  });

  test('an outage on the second part with the parts KEPT: held ON that part '
      '— the GET serves held_on and the confirm reads "second food" (each '
      'role a second part takes: yolk, egg, white)', () async {
    for (final (file, position, first, second) in _pairs) {
      final reason = '$file|$position';
      final (db, path) = a.pathDb();
      final r = _only(file, position);
      await d.editAndCompute(db, _fx, r);
      v28.dropFood(path, second);
      final down = v28.FoodFault(_fx, {second}, scope: FailureScope.food);
      for (var p = 1; p <= 3; p++) {
        await matchAndCompute(db, down, r);
      }
      final pair = d.rowOf(db, r, 0);
      expect(
        (pair.status, pair.hold, pair.heldOn),
        ('auto', 'food_unavailable', second),
        reason: reason,
      );
      expect(
        [for (final p in partsOf(pair.parts)) p.fdcId],
        [first, second],
        reason: reason,
      );
      final match = await _matchOf(db, down, r, 0);
      expect(match['held_on'], second, reason: reason);
      expect(
        await _confirmRefusal(db, down, r, 0),
        _secondDown,
        reason: reason,
      );
    }
  });

  // [the owner gate's pin; the hand-edit verifier's probe E] `_heldOnOther`'s
  // roles are a two-part RULE's second roles only: a half-drained can (the
  // half rule, no [SecondFoodRule]) held on its liquid twin — stored under
  // role `undrained` — reads "this food". The state: 1075 |1 confirmed, its
  // OWN record and the twin both dropped from the caches under a food
  // outage (the twin alone dropped re-derives the row un-split, no hold).
  // The set widened by 'undrained' passed seven test files before this pin.
  test('a half-drained can held ON its liquid twin (both records down, the '
      'parts kept) reads "this food": no held_on key, the plain refusal '
      '(STATED synthesized: the cache deletions and the fault)', () async {
    const own = 2644288;
    const twin = 175206;
    final (db, path) = a.pathDb();
    final r = _only(
      '1075-espinacas-con-garbanzos-andalusian-spinach-and-chickpeas.yaml',
      1,
    );
    await d.editAndCompute(db, _fx, r);
    final raw = nutritionLines(r).single.raw;
    expect(raw, '2 (15-ounce) cans chickpeas (1 can drained, 1 can undrained)');
    await applyMatchOverride(db, _fx, r, 0, {'raw': raw, 'confirmed': true});
    v28.dropFood(path, own);
    v28.dropFood(path, twin);
    final down = v28.FoodFault(_fx, {own, twin}, scope: FailureScope.food);
    for (var p = 1; p <= 3; p++) {
      await matchAndCompute(db, down, r);
    }
    final row = d.rowOf(db, r, 0);
    expect(
      (row.fdcId, row.status, row.hold, row.heldOn),
      (own, 'confirmed', 'food_unavailable', twin),
    );
    expect(
      row.parts,
      _parts((own, '240.26', 'drained'), (twin, '425.24', 'undrained')),
    );
    final match = await _matchOf(db, down, r, 0);
    expect(
      (match['hold'], match.containsKey('held_on')),
      ('food_unavailable', false),
    );
    expect(
      await _confirmRefusal(db, down, r, 0),
      'USDA could not serve this food — pick another food or skip the line.',
    );
  });

  test('an un-skip with the second part uncached under an outage: held '
      'food_unavailable ON that part at the PUT (`_heldOnOf` names the '
      "pair's second record), no parts; the GET serves held_on", () async {
    for (final (file, position, first, second) in _pairs) {
      final reason = '$file|$position';
      final (db, path) = a.pathDb();
      final r = _only(file, position);
      await d.editAndCompute(db, _fx, r);
      final raw = nutritionLines(r).single.raw;
      await applyMatchOverride(db, _fx, r, 0, {'raw': raw, 'skipped': true});
      v28.dropFood(path, second);
      final down = v28.FoodFault(_fx, {second}, scope: FailureScope.food);
      await applyMatchOverride(db, down, r, 0, {'raw': raw, 'skipped': false});
      final row = d.rowOf(db, r, 0);
      expect(
        (row.fdcId, row.hold, row.heldOn, row.parts),
        (first, 'food_unavailable', second, null),
        reason: reason,
      );
      final match = await _matchOf(db, down, r, 0);
      expect(
        (match['hold'], match['held_on']),
        ('food_unavailable', second),
        reason: reason,
      );
      expect(
        await _confirmRefusal(db, down, r, 0),
        _secondDown,
        reason: reason,
      );
    }
  });

  test("the FIRST part's detail absent (a search answer listing it cached), "
      "and both parts absent: held food_gone on the row's OWN record — no "
      'held_on, no grams, "this food"', () async {
    for (final (file, position, first, second) in _pairs) {
      for (final both in [false, true]) {
        final reason = '$file|$position both=$both';
        final (db, path) = a.pathDb();
        final r = _only(file, position);
        await d.editAndCompute(db, _fx, r);
        await searchCandidates(db, _fx, 'egg');
        _dropDetail(path, first);
        if (both) _dropDetail(path, second);
        db.clearDerivedSeq(r.id, [0]);
        final gone = v28.FoodFault(_fx, {first, if (both) second}, gone: true);
        await matchAndCompute(db, gone, r);
        final row = d.rowOf(db, r, 0);
        expect(
          (row.fdcId, row.hold, row.heldOn, row.grams, row.parts),
          (first, 'food_gone', null, null, null),
          reason: reason,
        );
        final match = await _matchOf(db, gone, r, 0);
        expect(match.containsKey('held_on'), isFalse, reason: reason);
        expect(
          await _confirmRefusal(db, gone, r, 0),
          noRecordMessage,
          reason: reason,
        );
      }
    }
  });
}

/// The look-alikes, unchanged.
void unmoved() {
  test('a plain egg line and a yolk-only line store no parts (one food on '
      'its own record)', () async {
    for (final (file, position, record, grams) in [
      (
        '0041-salad-with-herbed-baked-goat-cheese-and-vinaigrette.yaml',
        2,
        _egg,
        150.0,
      ),
      ('0017-mushroom-bisque.yaml', 11, _yolk, 34.0),
    ]) {
      final (db, _) = a.pathDb();
      final r = _only(file, position);
      await d.editAndCompute(db, _fx, r);
      final row = d.rowOf(db, r, 0);
      expect(
        (row.fdcId, row.grams, row.parts, row.hold),
        (record, grams, null, null),
        reason: file,
      );
    }
  });

  test('the citrus pairs keep their roles and basis (0536 |3, 0142 |8: the '
      'v113 rows)', () async {
    for (final (file, position, parts, basis) in [
      (
        '0536-crispy-orange-beef.yaml',
        3,
        '[{"fdc_id":169103,"grams":24.0,"role":"zest"},{"fdc_id":169098,"grams":62.0,"role":"juice"}]',
        'zest 1/4 cup · USDA portion + juice 1/4 cup · USDA portion',
      ),
      (
        '0142-skillet-roasted-chicken-in-lemon-sauce.yaml',
        8,
        '[{"fdc_id":167749,"grams":8.0,"role":"zest"},{"fdc_id":167747,"grams":60.92,"role":"juice"}]',
        'zest 4 teaspoon · USDA portion + juice 1/4 cup ≈ 59 mL',
      ),
    ]) {
      final (db, _) = a.pathDb();
      final r = loadCorpusRecipe(file);
      await d.editAndCompute(db, _fx, r);
      final row = d.rowOf(db, r, position);
      expect(row.parts, parts, reason: file);
      expect(
        gramBasisFor(db, nutritionLines(r)[position], row, recipe: r),
        basis,
        reason: file,
      );
    }
  });

  // [the owner gate's pin; hand-edit round 3] the citrus pair's row storing
  // its peel ALONE reads the peel's own basis through the same arm of
  // `_gramBasis` as an egg pair's: a pick of the peel (v108 V3) and the
  // pair held on its gone juice. The three corpus rows' bases are
  // byte-identical with and without the arm (their generic weigh read the
  // same), and no shipped test read them: a mutant wording the citrus arm
  // alone passed the whole suite. 0989 |1 keeps its lime-on-lemon-peel
  // approximation suffix.
  // [hand-edit round 4] On a JUICE-FIRST pair the arm is no no-op: without
  // it the generic weigh read the line's first amount — the juice's volume,
  // "1/4 cup ≈ 59 mL" — beside the peel's stored 8.0 g. No corpus line has
  // the shape (of the seven printing the juice before the zest, the five
  // joined by "plus" carry at most a tablespoon of zest, or strips: juice
  // only; two join by "and" or a comma, outside the rule), so the fourth
  // case swaps 0142's line 8 for a synthesized one; the arm restricted to
  // egg pairs passed the file before.
  test("a citrus pair storing its peel alone reads the peel's own basis: a "
      'pick of the peel, and the pair held on its gone juice (STATED '
      'synthesized: the cache deletion, the provider answer and the '
      'juice-first line)', () async {
    for (final (file, position, peel, juice, basis, swap) in [
      (
        '0536-crispy-orange-beef.yaml',
        3,
        169103,
        169098,
        '1/4 cup · USDA portion',
        null,
      ),
      (
        '0989-key-lime-pie.yaml',
        1,
        167749,
        168156,
        '4 teaspoon · USDA portion · approximation (counted as Lemon peel, raw)',
        null,
      ),
      (
        '0142-skillet-roasted-chicken-in-lemon-sauce.yaml',
        8,
        167749,
        167747,
        '4 teaspoon · USDA portion',
        null,
      ),
      (
        '0142-skillet-roasted-chicken-in-lemon-sauce.yaml',
        8,
        167749,
        167747,
        '4 teaspoon · USDA portion',
        '¼ cup lemon juice plus 4 teaspoons grated lemon zest',
      ),
    ]) {
      final corpus = loadCorpusRecipe(file);
      final r = swap == null ? corpus : _swapped(corpus, position, swap);
      final raw = nutritionLines(r)[position].raw;
      final (db, _) = a.pathDb();
      await d.editAndCompute(db, _fx, r);
      if (swap != null) {
        // The synthesized line is a two-part pair, the peel first.
        expect(
          d.rowOf(db, r, position).parts,
          _parts((peel, '8.00', 'zest'), (juice, '60.92', 'juice')),
          reason: swap,
        );
      }
      await applyMatchOverride(db, _fx, r, position, {
        'raw': raw,
        'fdc_id': peel,
      });
      final picked = d.rowOf(db, r, position);
      expect(
        (picked.fdcId, picked.status, picked.parts),
        (peel, 'overridden', null),
        reason: file,
      );
      expect(
        (await _matchOf(db, _fx, r, position))['gram_basis'],
        basis,
        reason: '$file ${swap ?? ''} pick',
      );
      final (db2, path2) = a.pathDb();
      await d.editAndCompute(db2, _fx, r);
      v28.dropFood(path2, juice);
      db2.clearDerivedSeq(r.id, [position]);
      final gone = v28.FoodFault(_fx, {juice}, gone: true);
      await matchAndCompute(db2, gone, r);
      final held = d.rowOf(db2, r, position);
      expect(
        (held.fdcId, held.hold, held.heldOn, held.parts),
        (peel, 'food_gone', juice, null),
        reason: file,
      );
      expect(
        (await _matchOf(db2, gone, r, position))['gram_basis'],
        basis,
        reason: '$file ${swap ?? ''} gone',
      );
    }
  });
}

/// One row of each of the six orders (its line alone).
const _orders = [
  ('0324-fresh-pasta-without-a-machine.yaml', 1),
  ('0994-lemon-tart.yaml', 2),
  ('0746-lemon-ricotta-pancakes.yaml', 4),
  ('0878-coconut-layer-cake.yaml', 2),
  ('0885-fluffy-yellow-layer-cake-with-milk-chocolate-frosting.yaml', 9),
  ('0937-chilled-lemon-souffle.yaml', 4),
];

String _g(double? x) => x?.toStringAsFixed(2) ?? '-';

/// sw8's state: each row's record, grams, source, hold, status, its parts;
/// the stored energy.
String _state(SaltDatabase db, String id) {
  final rows = db.ingredientMatchesFor(id)
    ..sort((a, b) => a.position.compareTo(b.position));
  final t = db.nutritionFor(id)?.totalsJson;
  final e = t == null
      ? null
      : ((jsonDecode(t) as Map)['energy'] as num?)?.toDouble();
  return [
    for (final r in rows)
      [
        r.position,
        r.fdcId,
        _g(r.grams),
        r.gramSource,
        r.hold,
        r.status,
        r.parts,
      ].join(':'),
    'E=${_g(e)}',
  ].join(' ');
}

/// The person paths on an egg pair (R13): each verb through the real PUT on
/// one row of each order, then sw8's invariant — stored == recomputeTotals
/// == a full compute, the GET's grams and hold == stored — and the row each
/// verb leaves.
void person() {
  test('a person decision on an egg pair (confirm, typed grams, skip and '
      'back, pick the same record, its apply_to_all, pick another): stored '
      '== recompute == compute == the GET, each order', () async {
    for (final (file, position) in _orders) {
      final probe = _only(file, position);
      final second = secondFoodRuleOf(
        nutritionLines(probe).single,
      )!.second!.fdcId;
      for (final (verb, puts)
          in <(String, List<Map<String, Object?>> Function(int own))>[
            (
              'confirm',
              (own) => [
                {'confirmed': true},
              ],
            ),
            (
              'typed',
              (own) => [
                {'grams': 77},
              ],
            ),
            (
              'skip-back',
              (own) => [
                {'skipped': true},
                {'skipped': false},
              ],
            ),
            (
              'pick-same',
              (own) => [
                {'fdc_id': own},
              ],
            ),
            (
              'pick-same-all',
              (own) => [
                {'fdc_id': own, 'apply_to_all': true},
              ],
            ),
            (
              'pick-other',
              (own) => [
                {'fdc_id': second},
              ],
            ),
          ]) {
        final reason = '$file|$position $verb';
        final (db, _) = a.pathDb();
        final r = _only(file, position);
        await d.editAndCompute(db, _fx, r);
        final raw = nutritionLines(r).single.raw;
        final own = d.rowOf(db, r, 0).fdcId!;
        String? refused;
        for (final body in puts(own)) {
          try {
            await applyMatchOverride(db, _fx, r, 0, {'raw': raw, ...body});
          } on ValidationException catch (e) {
            refused = e.message;
          }
        }
        final s1 = _state(db, r.id);
        final items = (await matchesBody(db, _fx, r))['items']! as List;
        final m = (items.single as Map)['match'] as Map;
        final row = d.rowOf(db, r, 0);
        expect(
          (_g((m['grams'] as num?)?.toDouble()), m['hold']),
          (_g(row.grams), row.hold),
          reason: '$reason GET',
        );
        expect(m['gram_basis'], _personBasis[reason], reason: '$reason basis');
        recomputeTotals(db, r);
        expect(_state(db, r.id), s1, reason: '$reason recompute');
        await matchAndCompute(db, _fx, r);
        expect(_state(db, r.id), s1, reason: '$reason compute');
        expect((refused, s1), (null, _personStates[reason]), reason: reason);
      }
    }
  });
}

/// The GET's `gram_basis` after each verb (measured on the v114 tree): the
/// pair's joined basis while the parts are kept, "entered by hand" under
/// typed grams, and — [the owner gate's pin; hand-edit round 2] — the FIRST
/// part's own basis on a pick of the row's own record, whose stored grams
/// are that part's alone. Before the fix `_gramBasis` fell through to the
/// generic weigh there: "N × W g each", and on 0885 |9 (yolks then whites)
/// "6 × 33 g each" beside the stored 102 g. A pick of the other part's
/// record is no rule row: the generic weigh, its grams and basis agreeing.
const _personBasis = {
  '0324-fresh-pasta-without-a-machine.yaml|1 confirm':
      '2 × 50 g egg + 6 × 17 g yolk, each on its own record',
  '0324-fresh-pasta-without-a-machine.yaml|1 typed': 'entered by hand',
  '0324-fresh-pasta-without-a-machine.yaml|1 skip-back':
      '2 × 50 g egg + 6 × 17 g yolk, each on its own record',
  '0324-fresh-pasta-without-a-machine.yaml|1 pick-same': '2 × 50 g egg',
  '0324-fresh-pasta-without-a-machine.yaml|1 pick-same-all': '2 × 50 g egg',
  '0324-fresh-pasta-without-a-machine.yaml|1 pick-other': '2 × 50 g each',
  '0994-lemon-tart.yaml|2 confirm':
      '7 × 17 g yolk + 2 × 50 g egg, each on its own record',
  '0994-lemon-tart.yaml|2 typed': 'entered by hand',
  '0994-lemon-tart.yaml|2 skip-back':
      '7 × 17 g yolk + 2 × 50 g egg, each on its own record',
  '0994-lemon-tart.yaml|2 pick-same': '7 × 17 g yolk',
  '0994-lemon-tart.yaml|2 pick-same-all': '7 × 17 g yolk',
  '0994-lemon-tart.yaml|2 pick-other': '7 × 17 g each',
  '0746-lemon-ricotta-pancakes.yaml|4 confirm':
      '2 × 50 g egg + 2 × 33 g white, each on its own record',
  '0746-lemon-ricotta-pancakes.yaml|4 typed': 'entered by hand',
  '0746-lemon-ricotta-pancakes.yaml|4 skip-back':
      '2 × 50 g egg + 2 × 33 g white, each on its own record',
  '0746-lemon-ricotta-pancakes.yaml|4 pick-same': '2 × 50 g egg',
  '0746-lemon-ricotta-pancakes.yaml|4 pick-same-all': '2 × 50 g egg',
  '0746-lemon-ricotta-pancakes.yaml|4 pick-other': '2 × 50 g each',
  '0878-coconut-layer-cake.yaml|2 confirm':
      '5 × 33 g white + 1 × 50 g egg, each on its own record',
  '0878-coconut-layer-cake.yaml|2 typed': 'entered by hand',
  '0878-coconut-layer-cake.yaml|2 skip-back':
      '5 × 33 g white + 1 × 50 g egg, each on its own record',
  '0878-coconut-layer-cake.yaml|2 pick-same': '5 × 33 g white',
  '0878-coconut-layer-cake.yaml|2 pick-same-all': '5 × 33 g white',
  '0878-coconut-layer-cake.yaml|2 pick-other': '5 × 33 g each',
  '0885-fluffy-yellow-layer-cake-with-milk-chocolate-frosting.yaml|9 confirm':
      '6 × 17 g yolk + 3 × 33 g white, each on its own record',
  '0885-fluffy-yellow-layer-cake-with-milk-chocolate-frosting.yaml|9 typed':
      'entered by hand',
  '0885-fluffy-yellow-layer-cake-with-milk-chocolate-frosting.yaml|9 skip-back':
      '6 × 17 g yolk + 3 × 33 g white, each on its own record',
  '0885-fluffy-yellow-layer-cake-with-milk-chocolate-frosting.yaml|9 pick-same':
      '6 × 17 g yolk',
  '0885-fluffy-yellow-layer-cake-with-milk-chocolate-frosting.yaml|9 pick-same-all':
      '6 × 17 g yolk',
  '0885-fluffy-yellow-layer-cake-with-milk-chocolate-frosting.yaml|9 pick-other':
      '6 × 33 g each',
  '0937-chilled-lemon-souffle.yaml|4 confirm':
      '5 × 33 g white + 2 × 17 g yolk, each on its own record',
  '0937-chilled-lemon-souffle.yaml|4 typed': 'entered by hand',
  '0937-chilled-lemon-souffle.yaml|4 skip-back':
      '5 × 33 g white + 2 × 17 g yolk, each on its own record',
  '0937-chilled-lemon-souffle.yaml|4 pick-same': '5 × 33 g white',
  '0937-chilled-lemon-souffle.yaml|4 pick-same-all': '5 × 33 g white',
  '0937-chilled-lemon-souffle.yaml|4 pick-other': '5 × 33 g each',
};

/// The state each verb leaves (measured on the v114 tree; sw8's form),
/// keyed "<file>|<position> <verb>"; no verb is refused.
/// A CHANGE FROM BASE (stated in docs/API.md; RULED KEPT in the owner gate:
/// a pick on a two-part row undoes the rule, Confirm keeps the pair): a
/// pick of the row's own record (and its apply_to_all) stores the FIRST
/// part's grams alone — the v108 V3 citrus pick's shape, a pick never reads
/// the second food. Base 2318767 stored the whole sum on 748967 (measured with
/// the same PUT on a base worktree): fresh-pasta|1 pick-same(-all)
/// '0:748967:202.00:piece:null:overridden:null E=298.96' (now 100.00 g,
/// 148.00: the six yolks dropped); pancakes|4 '…166.00… E=245.68' (now
/// 100.00 g, 148.00); lemon-tart|2, held at base, '0:748967:119.00:…
/// E=176.12' (now 119.00 g on 748236, 397.46).
const _personStates = {
  '0324-fresh-pasta-without-a-machine.yaml|1 confirm':
      '0:748967:202.00:piece:null:confirmed:[{"fdc_id":748967,"grams":100.0,"role":"egg"},{"fdc_id":748236,"grams":102.0,"role":"yolk"}] E=488.68',
  '0324-fresh-pasta-without-a-machine.yaml|1 typed':
      '0:748967:77.00:override:null:overridden:null E=113.96',
  '0324-fresh-pasta-without-a-machine.yaml|1 skip-back':
      '0:748967:202.00:piece:null:auto:[{"fdc_id":748967,"grams":100.0,"role":"egg"},{"fdc_id":748236,"grams":102.0,"role":"yolk"}] E=488.68',
  '0324-fresh-pasta-without-a-machine.yaml|1 pick-same':
      '0:748967:100.00:piece:null:overridden:null E=148.00',
  '0324-fresh-pasta-without-a-machine.yaml|1 pick-same-all':
      '0:748967:100.00:piece:null:overridden:null E=148.00',
  '0324-fresh-pasta-without-a-machine.yaml|1 pick-other':
      '0:748236:100.00:piece:null:overridden:null E=334.00',
  '0994-lemon-tart.yaml|2 confirm':
      '0:748236:219.00:piece:null:confirmed:[{"fdc_id":748236,"grams":119.0,"role":"yolk"},{"fdc_id":748967,"grams":100.0,"role":"egg"}] E=545.46',
  '0994-lemon-tart.yaml|2 typed':
      '0:748236:77.00:override:null:overridden:null E=257.18',
  '0994-lemon-tart.yaml|2 skip-back':
      '0:748236:219.00:piece:null:auto:[{"fdc_id":748236,"grams":119.0,"role":"yolk"},{"fdc_id":748967,"grams":100.0,"role":"egg"}] E=545.46',
  '0994-lemon-tart.yaml|2 pick-same':
      '0:748236:119.00:piece:null:overridden:null E=397.46',
  '0994-lemon-tart.yaml|2 pick-same-all':
      '0:748236:119.00:piece:null:overridden:null E=397.46',
  '0994-lemon-tart.yaml|2 pick-other':
      '0:748967:119.00:piece:null:overridden:null E=176.12',
  '0746-lemon-ricotta-pancakes.yaml|4 confirm':
      '0:748967:166.00:piece:null:confirmed:[{"fdc_id":748967,"grams":100.0,"role":"egg"},{"fdc_id":747997,"grams":66.0,"role":"white"}] E=184.30',
  '0746-lemon-ricotta-pancakes.yaml|4 typed':
      '0:748967:77.00:override:null:overridden:null E=113.96',
  '0746-lemon-ricotta-pancakes.yaml|4 skip-back':
      '0:748967:166.00:piece:null:auto:[{"fdc_id":748967,"grams":100.0,"role":"egg"},{"fdc_id":747997,"grams":66.0,"role":"white"}] E=184.30',
  '0746-lemon-ricotta-pancakes.yaml|4 pick-same':
      '0:748967:100.00:piece:null:overridden:null E=148.00',
  '0746-lemon-ricotta-pancakes.yaml|4 pick-same-all':
      '0:748967:100.00:piece:null:overridden:null E=148.00',
  '0746-lemon-ricotta-pancakes.yaml|4 pick-other':
      '0:747997:100.00:piece:null:overridden:null E=55.00',
  '0878-coconut-layer-cake.yaml|2 confirm':
      '0:747997:215.00:piece:null:confirmed:[{"fdc_id":747997,"grams":165.0,"role":"white"},{"fdc_id":748967,"grams":50.0,"role":"egg"}] E=164.75',
  '0878-coconut-layer-cake.yaml|2 typed':
      '0:747997:77.00:override:null:overridden:null E=42.35',
  '0878-coconut-layer-cake.yaml|2 skip-back':
      '0:747997:215.00:piece:null:auto:[{"fdc_id":747997,"grams":165.0,"role":"white"},{"fdc_id":748967,"grams":50.0,"role":"egg"}] E=164.75',
  '0878-coconut-layer-cake.yaml|2 pick-same':
      '0:747997:165.00:piece:null:overridden:null E=90.75',
  '0878-coconut-layer-cake.yaml|2 pick-same-all':
      '0:747997:165.00:piece:null:overridden:null E=90.75',
  '0878-coconut-layer-cake.yaml|2 pick-other':
      '0:748967:165.00:piece:null:overridden:null E=244.20',
  '0885-fluffy-yellow-layer-cake-with-milk-chocolate-frosting.yaml|9 confirm':
      '0:748236:201.00:piece:null:confirmed:[{"fdc_id":748236,"grams":102.0,"role":"yolk"},{"fdc_id":747997,"grams":99.0,"role":"white"}] E=395.13',
  '0885-fluffy-yellow-layer-cake-with-milk-chocolate-frosting.yaml|9 typed':
      '0:748236:77.00:override:null:overridden:null E=257.18',
  '0885-fluffy-yellow-layer-cake-with-milk-chocolate-frosting.yaml|9 skip-back':
      '0:748236:201.00:piece:null:auto:[{"fdc_id":748236,"grams":102.0,"role":"yolk"},{"fdc_id":747997,"grams":99.0,"role":"white"}] E=395.13',
  '0885-fluffy-yellow-layer-cake-with-milk-chocolate-frosting.yaml|9 pick-same':
      '0:748236:102.00:piece:null:overridden:null E=340.68',
  '0885-fluffy-yellow-layer-cake-with-milk-chocolate-frosting.yaml|9 pick-same-all':
      '0:748236:102.00:piece:null:overridden:null E=340.68',
  '0885-fluffy-yellow-layer-cake-with-milk-chocolate-frosting.yaml|9 pick-other':
      '0:747997:198.00:piece:null:overridden:null E=108.90',
  '0937-chilled-lemon-souffle.yaml|4 confirm':
      '0:747997:199.00:piece:null:confirmed:[{"fdc_id":747997,"grams":165.0,"role":"white"},{"fdc_id":748236,"grams":34.0,"role":"yolk"}] E=204.31',
  '0937-chilled-lemon-souffle.yaml|4 typed':
      '0:747997:77.00:override:null:overridden:null E=42.35',
  '0937-chilled-lemon-souffle.yaml|4 skip-back':
      '0:747997:199.00:piece:null:auto:[{"fdc_id":747997,"grams":165.0,"role":"white"},{"fdc_id":748236,"grams":34.0,"role":"yolk"}] E=204.31',
  '0937-chilled-lemon-souffle.yaml|4 pick-same':
      '0:747997:165.00:piece:null:overridden:null E=90.75',
  '0937-chilled-lemon-souffle.yaml|4 pick-same-all':
      '0:747997:165.00:piece:null:overridden:null E=90.75',
  '0937-chilled-lemon-souffle.yaml|4 pick-other':
      '0:748236:165.00:piece:null:overridden:null E=551.10',
};
