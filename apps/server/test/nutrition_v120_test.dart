// The v120 pins (batch M107, prep52 P8: a counted piece beside a printed
// volume; matcherVersion 106). The ruling R1 (OQ2 = (b), under the owner's
// standing matcher authorization) re-opens prep51's C3b: engine.dart's
// `_pieceVolumeOnSibling` (v84's `_cloveVolumeOnSibling`, C3a) reads a
// counted PIECE on any `volumeSiblings` record — no longer a garlic clove
// alone — whose count carries no unit and whose line prints a volume
// amount (both readers, `lineGrams` and `gramsFor`'s sibling fetch, ask for
// the sibling and the volume first): the line weighs that volume on the
// sibling's cup (`_foodGramsPerMl`: a named cut, else a fine cut reads the
// chopped cup, else the median of the line unit's cups). C3a's second-count
// guard (`_countBeforeParen`) is kept as shipped. Corpus-backed groups skip
// without SALT_CORPUS_DIR; every corpus read sits inside a test body. Each
// pinned line is computed ALONE (its own line in its recipe's real steps)
// on the fixtures; every value below is the replay's (snapshot 33, the
// v120 tree).
//
// Hand derivations (the printed volume in mL — 236.588 a cup, 14.7868 a
// tablespoon, 4.92892 a teaspoon — × the sibling portion's g/mL; kcal on
// the ROW's record, nutrient 208, else 958, else 957):
//   0086-hungarian-beef-stew.yaml|7 "6 medium onions, minced (about 6
//     cups)": 6 × 160 g ('cup, chopped' of SR 170000; "minced" is a fine
//     cut) = 960.00 g × 0.38 (Foundation 790646) = 364.80 (was 6 × 110 g,
//     660.00 g, 250.80).
//   classic-roast-stuffed-turkey section "Bread Stuffing …" |1 "6 medium
//     onions, sliced thin (about 7 cups)": 7 × 115 g ('cup, sliced') =
//     805.00 g, 305.90.
//   0083-old-fashioned-pot-roast.yaml|5 "1 celery rib, chopped medium
//     (about ¾ cup)": ¾ × 101 g (SR 169988 'cup chopped') = 75.75 g × 0.148322
//     (2346405, nutrient 958) = 11.24 (was 40.00 g, 5.93).
//   0471-cheesy-nachos-with-guacamole-and-salsa.yaml|2 "2 large jalapeño
//     chiles, sliced thin (about ¼ cup)": ¼ × 150 g (FNDDS 2710096 '1 cup',
//     its only volume portion) = 37.50 g × 0.241264 (2747661,
//     nutrient 957: it prints no 208 or 958) = 9.05 (was
//     28.00 g, 6.76).
// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_cost_test.dart' show capLines, capped, ln;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

final _fx = FixtureProvider(pending: pendingSearches);

/// The 31 moved main rows (the replay's 33 class rows but the two section
/// rows, [resolver]): "file|position", record, description, status, hold,
/// gram source, confidence, grams, kcal, basis — every column the rule
/// writes, each the replay's.
const _moved = [
  '0044-mediterranean-chopped-salad.yaml|8\t790577\tOnions, red, raw\tauto\t\tportion\t1.000000\t40.00\t17.60\t1/4 cup · USDA portion of "Onions, raw"',
  '0048-classic-greek-salad.yaml|7\t790577\tOnions, red, raw\tauto\t\tportion\t1.000000\t86.25\t37.95\t3/4 cup · USDA portion of "Onions, raw"',
  '0083-old-fashioned-pot-roast.yaml|3\t790646\tOnions, yellow, raw\tauto\t\tportion\t0.936667\t230.00\t87.40\t2 cup · USDA portion of "Onions, raw"',
  '0083-old-fashioned-pot-roast.yaml|4\t2258586\tCarrots, mature, raw\tauto\t\tportion\t0.936667\t128.00\t57.57\t1 cup · USDA portion of "Carrots, raw"',
  '0083-old-fashioned-pot-roast.yaml|5\t2346405\tCelery, raw\tauto\t\tportion\t0.970000\t75.75\t11.24\t3/4 cup · USDA portion of "Celery, raw"',
  '0086-hungarian-beef-stew.yaml|7\t790646\tOnions, yellow, raw\tauto\t\tportion\t0.936667\t960.00\t364.80\t6 cup · USDA portion of "Onions, raw"',
  '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml|9\t790646\tOnions, yellow, raw\tauto\t\tportion\t0.936667\t480.00\t182.40\t3 cup · USDA portion of "Onions, raw"',
  '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml|10\t2346405\tCelery, raw\tauto\t\tportion\t0.970000\t151.50\t22.47\t1 1/2 cup · USDA portion of "Celery, raw"',
  '0205-smothered-pork-chops.yaml|6\t790646\tOnions, yellow, raw\tauto\t\tportion\t1.000000\t402.50\t152.95\t3 1/2 cup · USDA portion of "Onions, raw"',
  '0268-cod-baked-in-foil-with-leeks-and-carrots.yaml|6\t2258586\tCarrots, mature, raw\tauto\t\tportion\t0.936667\t183.00\t82.31\t1 1/2 cup · USDA portion of "Carrots, raw"',
  '0286-shrimp-salad.yaml|8\t2346405\tCelery, raw\tauto\t\tportion\t0.970000\t33.67\t4.99\t1/3 cup · USDA portion of "Celery, raw"',
  '0290-crab-towers-with-avocado-and-gazpacho-salsas.yaml|12\t790577\tOnions, red, raw\tauto\t\tportion\t1.000000\t40.00\t17.60\t1/4 cup · USDA portion of "Onions, raw"',
  '0298-classic-tuna-salad.yaml|1\t2346405\tCelery, raw\tauto\t\tportion\t0.970000\t25.25\t3.75\t1/4 cup · USDA portion of "Celery, raw"',
  '0341-campanelle-with-asparagus-basil-and-balsamic-glaze.yaml|5\t790577\tOnions, red, raw\tauto\t\tportion\t1.000000\t172.50\t75.90\t1 1/2 cup · USDA portion of "Onions, raw"',
  '0355-pasta-with-streamlined-bolognese-sauce.yaml|2\t2258586\tCarrots, mature, raw\tauto\t\tportion\t0.936667\t64.00\t28.79\t1/2 cup · USDA portion of "Carrots, raw"',
  '0355-pasta-with-streamlined-bolognese-sauce.yaml|3\t790646\tOnions, yellow, raw\tauto\t\tportion\t0.936667\t40.00\t15.20\t1/4 cup · USDA portion of "Onions, raw"',
  '0406-hearty-tuscan-bean-stew.yaml|4\t790646\tOnions, yellow, raw\tauto\t\tportion\t0.936667\t240.00\t91.20\t1 1/2 cup · USDA portion of "Onions, raw"',
  '0410-mushroom-risotto.yaml|9\t790646\tOnions, yellow, raw\tauto\t\tportion\t0.936667\t320.00\t121.60\t2 cup · USDA portion of "Onions, raw"',
  '0412-butternut-squash-risotto.yaml|7\t790646\tOnions, yellow, raw\tauto\t\tportion\t0.936667\t240.00\t91.20\t1 1/2 cup · USDA portion of "Onions, raw"',
  '0424-italian-sausage-with-grapes-and-balsamic-vinegar.yaml|3\t790646\tOnions, yellow, raw\tauto\t\tportion\t0.936667\t172.50\t65.55\t1 1/2 cup · USDA portion of "Onions, raw"',
  '0424-pork-chops-with-vinegar-and-sweet-peppers.yaml|4\t790646\tOnions, yellow, raw\tauto\t\tportion\t0.936667\t200.00\t76.00\t1 1/4 cup · USDA portion of "Onions, raw"',
  '0440-summer-vegetable-gratin.yaml|5\t790646\tOnions, yellow, raw\tauto\t\tportion\t0.936667\t345.00\t131.10\t3 cup · USDA portion of "Onions, raw"',
  '0471-cheesy-nachos-with-guacamole-and-salsa.yaml|2\t2747661\tPeppers, jalapeno, seeded, raw\tauto\t\tportion\t0.920000\t37.50\t9.05\t1/4 cup · USDA portion of "Peppers, jalapenos"',
  '0495-beef-chili-with-kidney-beans.yaml|1\t790646\tOnions, yellow, raw\tauto\t\tportion\t0.936667\t320.00\t121.60\t2 cup · USDA portion of "Onions, raw"',
  '0496-white-chicken-chili.yaml|6\t790646\tOnions, yellow, raw\tauto\t\tportion\t0.936667\t275.00\t104.50\t2 cup · USDA portion of "Onions, raw"',
  '0512-vegetable-bibimbap-with-nurungji.yaml|18\t2258586\tCarrots, mature, raw\tauto\t\tportion\t0.936667\t220.00\t98.95\t2 cup · USDA portion of "Carrots, raw"',
  '0564-chicken-tikka-masala.yaml|10\t790646\tOnions, yellow, raw\tauto\t\tportion\t0.936667\t160.00\t60.80\t1 cup · USDA portion of "Onions, raw"',
  '0568-indian-style-curry-with-potatoes-cauliflower-peas-and-chickpeas.yaml|8\t790646\tOnions, yellow, raw\tauto\t\tportion\t0.936667\t320.00\t121.60\t2 cup · USDA portion of "Onions, raw"',
  '0570-falafel.yaml|3\t790646\tOnions, yellow, raw\tauto\t\tportion\t0.936667\t80.00\t30.40\t1/2 cup · USDA portion of "Onions, raw"',
  '0709-rice-pilaf.yaml|5\t790646\tOnions, yellow, raw\tauto\t\tportion\t0.936667\t80.00\t30.40\t1/2 cup · USDA portion of "Onions, raw"',
  '1077-turkey-thigh-confit-with-citrus-mustard-sauce.yaml|0\t790646\tOnions, yellow, raw\tauto\t\tportion\t0.936667\t760.00\t288.80\t4 3/4 cup · USDA portion of "Onions, raw"',
];

/// R2's negatives, each the v119 row, byte-identical in the replay
/// (file|position, raw start, record, gram source, grams, basis).
const _unmoved = [
  // The guard (a second count before the paren — WAIT-FOR-FIELDS): the
  // audit's own L676.
  (
    '0445-potatoes-lyonnaise.yaml|1',
    '1 large onion, halved pole to pole and sliced ¼ inch thick (about 3 cups)',
    790646,
    'piece',
    '150.00',
    '1 × 150 g each',
  ),
  // The guard reads "½-inch" as a second count (the shipped regex, not
  // widened or narrowed): the carrot keeps its piece.
  (
    '0028-hearty-minestrone.yaml|6',
    '1 medium carrot, peeled and cut into ½-inch pieces (about ¾ cup)',
    2258586,
    'piece',
    '61.00',
    '1 × 61 g each',
  ),
  // A clove UNIT: the count carries a unit.
  (
    '0075-chicken-under-a-brick-with-herb-roasted-potatoes.yaml|3',
    '3 cloves garlic, minced (about 1 tablespoon)',
    1104647,
    'piece',
    '9.00',
    '3 clove × 3 g each',
  ),
  // A head UNIT (and the guard: "5 medium cloves").
  (
    '0103-cuban-style-black-beans-and-rice.yaml|6',
    '1 head garlic, 5 medium cloves minced',
    1104647,
    'piece',
    '50.00',
    '1 head × 50 g each',
  ),
  // A printed weight.
  (
    '0223-onion-braised-beef-brisket.yaml|3',
    '3 large onions (about 2½ pounds)',
    790646,
    'weight',
    '1133.98',
    'from 2 1/2 pound',
  ),
  (
    '0035-vegetable-broth-base.yaml|1',
    '2 carrots, peeled and cut into ½-inch pieces (⅔ cup or 3 ounces)',
    2258586,
    'weight',
    '85.05',
    'from the printed weight',
  ),
  // A volume-primary line (already step 2).
  (
    '0055-american-potato-salad-with-hard-cooked-eggs-and-sweet-pickles.yaml|7',
    '2 tablespoons minced red onion',
    790577,
    'portion',
    '20.00',
    '2 tablespoon · USDA portion of "Onions, raw"',
  ),
  // An onion with no printed volume: Q9 (a)'s 110 g stays.
  (
    '0002-classic-chicken-noodle-soup.yaml|7',
    '1 medium onion, chopped medium',
    790646,
    'piece',
    '110.00',
    '1 × 110 g each',
  ),
  // Off a sibling: an anchovy count beside a volume.
  (
    '0005-best-beef-stew.yaml|1',
    '4 anchovy fillets, minced fine (about 2 teaspoons)',
    2706232,
    'piece',
    '16.00',
    '4 · USDA per-item weight',
  ),
];

void main() {
  test('matcherVersion 106', () => expect(matcherVersion, 106));
  group(
    'v120 (M107: a counted piece beside a printed volume)',
    skip: skipIfNoCorpus,
    () {
      moved();
      unmoved();
      resolver();
      fetch();
      properties();
      picks();
    },
  );
  caps();
  synthesized();
}

/// [file]'s line [position] ALONE in its recipe (the real steps).
Recipe _one(String file, int position) {
  final corpus = loadCorpusRecipe(file);
  return corpus.copyWith(
    ingredients: [
      IngredientGroup(items: [nutritionLines(corpus)[position]]),
    ],
  );
}

/// [file]'s line [position] ALONE in its recipe, stored and computed on
/// [fx] (the fixtures) on a fresh database — the recipe and the line's
/// index (0).
Future<(SaltDatabase, Recipe)> _alone(
  String file,
  int position, [
  NutritionProvider? fx,
]) async {
  final (db, _) = a.pathDb();
  final r = _one(file, position);
  await d.editAndCompute(db, fx ?? _fx, r);
  return (db, r);
}

/// The row's kcal on its record (every record here has a fixture detail).
Future<String?> _kcal(IngredientMatchRow row) async {
  final grams = row.grams;
  if (grams == null) return null;
  final food = (await _fx.food(row.fdcId!))!;
  return (kcalPer100g(food) * grams / 100).toStringAsFixed(2);
}

/// [want]'s key computed ALONE: every column [_moved] holds.
Future<String> _columns(String want) async {
  final key = want.split('\t').first;
  final [file, position] = key.split('|');
  final (db, r) = await _alone(file, int.parse(position));
  final line = nutritionLines(r).single;
  final row = d.rowOf(db, r, 0);
  return [
    key,
    row.fdcId,
    row.description,
    row.status,
    row.hold ?? '',
    row.gramSource,
    row.confidence.toStringAsFixed(6),
    row.grams?.toStringAsFixed(2),
    await _kcal(row),
    gramBasisFor(db, line, row, recipe: r),
  ].join('\t');
}

/// R7: every stored column the rule writes, the kcal and the basis; (A2)
/// the matches GET's grams and `gram_basis` for one moved row.
void moved() {
  test(
    'the moved rows: 31 rows, every column',
    () async {
      expect([for (final want in _moved) await _columns(want)], _moved);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
  test('A2: the GET reads a moved row', () async {
    final (db, r) = await _alone('0086-hungarian-beef-stew.yaml', 7);
    final body = await matchesBody(db, _fx, r);
    final m = ((body['items']! as List).single as Map)['match'] as Map;
    expect(
      ((m['grams'] as num?)?.toStringAsFixed(2), m['hold'], m['gram_basis']),
      ('960.00', null, '6 cup · USDA portion of "Onions, raw"'),
    );
  });
}

/// R2: the negatives keep their v119 rows.
void unmoved() {
  for (final (key, raw, fdcId, source, grams, basis) in _unmoved) {
    test('$key unchanged: $fdcId $grams `$source`', () async {
      final [file, position] = key.split('|');
      final (db, r) = await _alone(file, int.parse(position));
      final line = nutritionLines(r).single;
      expect(line.raw, startsWith(raw));
      final row = d.rowOf(db, r, 0);
      expect(
        (row.fdcId, row.gramSource, row.grams?.toStringAsFixed(2), row.hold),
        (fdcId, source, grams, null),
      );
      expect(gramBasisFor(db, line, row, recipe: r), basis);
    });
  }
}

/// The corpus line at [raw]'s start in [file], any section.
IngredientLine _lineOf(String file, String raw) {
  final r = loadCorpusRecipe(file);
  return [
    for (final g in r.ingredients) ...g.items,
    for (final s in r.subsections)
      for (final g in s.ingredients ?? const <IngredientGroup>[]) ...g.items,
  ].singleWhere((l) => l.raw.startsWith(raw));
}

/// A database whose FDC cache holds [ids]' fixture details.
Future<SaltDatabase> _cached(List<int> ids) async {
  final (db, _) = a.pathDb();
  for (final id in ids) {
    db.fdcFoodCachePut(id, jsonEncode((await _fx.food(id))!.toJson()));
  }
  return db;
}

/// The two moved section rows (the stuffing of
/// classic-roast-stuffed-turkey, "Bread Stuffing with Bacon, Apples, Sage,
/// and Caramelized Onions" |1; cheesy-nachos-with-guacamole-and-salsa's
/// "One-Minute Salsa" |3), weighed by the resolver on the replay's record
/// with the sibling cached: the replay's grams and basis.
void resolver() {
  test('the two moved section rows: grams and basis', () async {
    final db = await _cached([170000, 2710096]);
    for (final (file, raw, fdcId, want) in [
      (
        '0158-classic-roast-stuffed-turkey.yaml',
        '6 medium onions, sliced thin (about 7 cups)',
        790646,
        '805.00 g 7 cup · USDA portion of "Onions, raw"',
      ),
      (
        '0471-cheesy-nachos-with-guacamole-and-salsa.yaml',
        '½ small jalapeño chile, stemmed and seeded (about 1½ teaspoons)',
        2747661,
        '4.69 g 1 1/2 teaspoon · USDA portion of "Peppers, jalapenos"',
      ),
    ]) {
      final g = lineGrams(
        db,
        _lineOf(file, raw),
        await _fx.food(fdcId),
        recipe: loadCorpusRecipe(file),
      );
      expect(
        '${g?.grams.toStringAsFixed(2)} g ${g?.basis}',
        want,
        reason: '$file $raw',
      );
    }
  });
}

/// A provider counting the details it is asked for, by id.
class _Counting extends FixtureProvider {
  _Counting() : super(pending: pendingSearches);

  final ids = <int>[];

  @override
  Future<FdcFood?> food(int fdcId) {
    ids.add(fdcId);
    return super.food(fdcId);
  }
}

/// R7 / the design's m4: with no sibling detail cached the counted line
/// fetches SR 170000 ONCE (`gramsFor`'s sibling fetch reads the same
/// predicate), then weighs; the next compute asks nothing (v119: 790646
/// alone, 660.00 g).
void fetch() {
  test('the sibling fetch: 0086|7 asks 170000 once, then weighs', () async {
    final p = _Counting();
    final (db, r) = await _alone('0086-hungarian-beef-stew.yaml', 7, p);
    expect(p.ids, [790646, 170000]);
    expect(d.rowOf(db, r, 0).grams?.toStringAsFixed(2), '960.00');
    await matchAndCompute(db, p, r);
    expect(p.ids, [790646, 170000]);
    expect(d.rowOf(db, r, 0).grams?.toStringAsFixed(2), '960.00');
  });
}

/// Every corpus recipe file, sorted.
List<String> _files() =>
    Directory(corpusRecipesDir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.yaml'))
        .map((f) => f.uri.pathSegments.last)
        .toList()
      ..sort();

String _sha(Iterable<String> lines) =>
    sha256.convert(utf8.encode(lines.join('\n'))).toString();

/// R6's off-sibling class (closer 1, D2): the v119 replay's piece rows with a
/// primary count and a volume amount on a record with no `volumeSiblings`
/// entry — 21 rows, the 17 main ones here ("file|position", the row's
/// record, then its v119 grams and basis, each byte-identical in the v120
/// replay); the four section rows (oven-roasted-salmon "Spicy Cucumber
/// Relish" |0 cucumber 2346406 and |3 serrano 2747663, tamales "Red Chile
/// Chicken Filling" |0 ancho 169396, pavlova "Mango, Kiwi, and Blueberry
/// Topping" |1 kiwi 2710831) are not looped (the property's limit).
const _offSibling = {
  '0005-best-beef-stew.yaml|1': (2706232, '16.00 g 4 · USDA per-item weight'),
  '0028-hearty-minestrone.yaml|8': (2685568, '196.00 g 1 × 196 g each'),
  '0141-pollo-en-mole-poblano-chicken-in-puebla-style-mole.yaml|0': (
    169396,
    '34.00 g 2 · USDA per-item weight',
  ),
  '0290-crab-towers-with-avocado-and-gazpacho-salsas.yaml|8': (
    2258589,
    '119.00 g 1 × 119 g each',
  ),
  '0290-crab-towers-with-avocado-and-gazpacho-salsas.yaml|9': (
    2346406,
    '79.00 g 1/2 × 158 g each',
  ),
  '0376-beijing-style-meat-sauce-and-noodles.yaml|12': (
    2346406,
    '150.00 g 1/2 × 300 g each',
  ),
  '0404-pasta-e-fagioli-italian-pasta-and-bean-soup.yaml|7': (
    2706232,
    '12.00 g 3 · USDA per-item weight',
  ),
  '0424-pork-chops-with-vinegar-and-sweet-peppers.yaml|5': (
    2258590,
    '119.00 g 1 × 119 g each',
  ),
  '0424-pork-chops-with-vinegar-and-sweet-peppers.yaml|6': (
    2258589,
    '119.00 g 1 × 119 g each',
  ),
  '0424-pork-chops-with-vinegar-and-sweet-peppers.yaml|7': (
    2706232,
    '8.00 g 2 · USDA per-item weight',
  ),
  '0439-pissaladiere.yaml|12': (2706232, '32.00 g 8 · USDA per-item weight'),
  '0450-chicken-bouillabaisse.yaml|4': (2747655, '200.00 g 1 × 200 g each'),
  '0455-chicken-provencal.yaml|5': (2706232, '4.00 g 1 · USDA per-item weight'),
  '0456-daube-provencal.yaml|16': (2706232, '8.00 g 2 · USDA per-item weight'),
  '0636-grilled-chicken-souvlaki.yaml|3': (
    2346406,
    '150.00 g 1/2 × 300 g each',
  ),
  '0753-classic-banana-bread.yaml|4': (1105314, '354.00 g 3 × 118 g each'),
  '1104-banana-muffins-with-coconut-and-macadamia.yaml|6': (
    1105314,
    '531.00 g 4–5 × 118 g each',
  ),
};

/// R8 / A5 — the SELECTOR over every corpus recipe's own lines (the
/// property's limit: the titled sections' lines are not looped — the two
/// section rows are pinned in [resolver]): each line printing a volume
/// whose item names garlic, onion (red: 790577), carrot, celery or
/// jalapeño is weighed through `lineGrams` (its recipe's real steps) on
/// that class's `volumeSiblings` record whatever record the matcher gives
/// it; a line the record reads as a PIECE (no sibling cached) is 'arm' when
/// the cached sibling changes its basis, else 'kept' (the guard, a unit).
/// On the v120 replay: the 36 non-garlic 'arm' lines are the 31 moved main
/// rows and five lines on other rows — classic-gazpacho|3 on shallots
/// 170499, maryland-crab-cakes|1 and black-bean-burgers|3 (scallions) on
/// 2709794, irish-stew-with-carrots-and-turnips|2 on 170000 itself, and
/// braised-beef-short-ribs|3 strained out (0 g, `discarded`); the garlic
/// classes are byte-identical to v119's (C3a). The 15 'kept' lines are the
/// guard's 13 main lines, the head (a unit, and the guard) and the clove
/// unit. The same loop weighs R6's 17 off-sibling main rows ([_offSibling])
/// on their own records, with every `volumeSiblings` record's detail
/// cached (all 24 distinct values, a cache of their own) and with none:
/// each its v119 piece (a record with no `volumeSiblings` entry never
/// reaches the arm); the four off-sibling section rows are the limit above.
void properties() {
  test(
    'the selector on every corpus line',
    () async {
      final cached = await _cached([170000, 170393, 169988, 2710096, 169230]);
      // D3: the off-sibling branch reads a cache holding EVERY
      // `volumeSiblings` record's detail (all in the fixtures), so a record
      // given any sibling reads that sibling's portion.
      final allSiblings = await _cached(volumeSiblings.values.toSet().toList());
      final (bare, _) = a.pathDb();
      final foods = <int, FdcFood>{
        for (final id in [790646, 790577, 2258586, 2346405, 2747661, 1104647])
          id: (await _fx.food(id))!,
      };
      final out = <String, List<String>>{};
      final offFoods = <int, FdcFood>{
        for (final (id, _) in _offSibling.values) id: (await _fx.food(id))!,
      };
      final off = <String, (int, String)>{};
      for (final file in _files()) {
        final r = loadCorpusRecipe(file);
        for (final (k, line) in nutritionLines(r).indexed) {
          if (volumeMlOf(line.amounts) == null) continue;
          // D2: each off-sibling row weighs as at v119 with every sibling
          // cached, and as with none.
          if (_offSibling['$file|$k'] case (final id, _)) {
            expect(volumeSiblings[id], isNull);
            final g = lineGrams(allSiblings, line, offFoods[id], recipe: r);
            final b = lineGrams(bare, line, offFoods[id], recipe: r);
            expect(g?.source, GramSource.piece);
            expect('${g?.grams} ${g?.basis}', '${b?.grams} ${b?.basis}');
            off['$file|$k'] = (
              id,
              '${g?.grams.toStringAsFixed(2)} g ${g?.basis}',
            );
            continue;
          }
          final w = normalizeItem(
            lineItemOf(line),
          ).split(RegExp('[^a-z]+')).toSet();
          bool has(String x) => w.contains(x);
          final id = has('garlic')
              ? 1104647
              : (has('onion') || has('onions'))
              ? (has('red') ? 790577 : 790646)
              : (has('carrot') || has('carrots'))
              ? 2258586
              : has('celery')
              ? 2346405
              : (has('jalapeño') ||
                    has('jalapeno') ||
                    has('jalapeños') ||
                    has('jalapenos'))
              ? 2747661
              : null;
          if (id == null) continue;
          final own = lineGrams(bare, line, foods[id], recipe: r);
          if (own?.source != GramSource.piece) continue;
          final g = lineGrams(cached, line, foods[id], recipe: r);
          final kind = g?.basis == own?.basis ? 'kept' : 'arm';
          (out['$id.$kind'] ??= []).add(
            '$file|$k ${g?.grams.toStringAsFixed(2)} g ${g?.basis}',
          );
        }
      }
      final got = {
        for (final MapEntry(:key, :value) in out.entries)
          key: (value.length, _sha(value)),
      };
      // D2: all 17 off-sibling main rows reached, each at its v119 row.
      expect(off, _offSibling);
      // Measured on the v120 tree (each 'arm' line read against the replay's
      // rows, above).
      expect(got, {
        '1104647.arm': (
          155,
          '9cbbf8f5736f9f4211df6f2701a561e21fa5f6a02344d911162d192a1e85ca63',
        ),
        '1104647.kept': (
          5,
          'db57b5fd247c9bffd19dd51ac404e7dee7ff98e4e7fe490e447d84191b2f6e21',
        ),
        '2258586.arm': (
          4,
          'ad2a35393fd03d75a1847b13b2f86e93f7b25df196be70a3b8c8b10cc35c7c7b',
        ),
        '2258586.kept': (
          5,
          '82eb66d7e201b9a6d6b918f364c0004291831f240969abbe53def7adb475d77f',
        ),
        '2346405.arm': (
          4,
          '4b0967a23e098a5691607bd71eb11c3ed332f2d713aa790f43270c8bca476b1c',
        ),
        '2346405.kept': (
          2,
          'e01c5f3f3bb43ba385f55146cc46500988d5748b4756e25516288892f7bdb7ae',
        ),
        '2747661.arm': (
          1,
          '44942024944d5317af81bac40273430ac9db54ff8c6b5fb918e222a5add272ba',
        ),
        '790577.arm': (
          4,
          '4842dc96a38184fcd97b27d15fd80120bb62219223ec0501860fac0139fe1f9b',
        ),
        '790646.arm': (
          23,
          '9443c6575a42eea5b6836e043ad0fe0f909af94997995e481d0a948f34c985b2',
        ),
        '790646.kept': (
          3,
          'e431286fe878ae7116db71a0f55ca19adb0c832d27387b1930a45f637ed0ac65',
        ),
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// A13: a person's own pick (PUT fdc_id, no apply_to_all) on
/// 0086-hungarian-beef-stew.yaml|7 — the stored row, the basis, the matches
/// GET and the next compute: (i) the row's own record 790646 weighs the
/// printed 6 cups on its sibling (v119: 660.00 g `piece`, "6 × 110 g
/// each"); (ii) the sibling 170000 its own cup (the same at v119); (iii) a
/// third record with no sibling, Foundation 1104962 "Onions, white, raw",
/// counts six 110 g onions (the same at v119).
void picks() {
  for (final (pick, want) in [
    (
      790646,
      '790646 overridden null 960.00 portion 1.000000 | 6 cup · USDA portion of "Onions, raw" | 960.00 null 6 cup · USDA portion of "Onions, raw"',
    ),
    (
      170000,
      '170000 overridden null 960.00 portion 1.000000 | 6 cup · USDA portion | 960.00 null 6 cup · USDA portion',
    ),
    (
      1104962,
      '1104962 overridden null 660.00 piece 1.000000 | 6 × 110 g each | 660.00 null 6 × 110 g each',
    ),
  ]) {
    test("A13: a person's own pick of $pick on 0086|7", () async {
      final (db, r) = await _alone('0086-hungarian-beef-stew.yaml', 7);
      final line = nutritionLines(r).single;
      await applyMatchOverride(db, _fx, r, 0, {
        'raw': line.raw,
        'fdc_id': pick,
      });
      Future<String> read() async {
        final m = d.rowOf(db, r, 0);
        final body = await matchesBody(db, _fx, r);
        final g = ((body['items']! as List).single as Map)['match'] as Map;
        return '${m.fdcId} ${m.status} ${m.hold} '
            '${m.grams?.toStringAsFixed(2)} ${m.gramSource} '
            '${m.confidence.toStringAsFixed(6)} | '
            '${gramBasisFor(db, line, m, recipe: r)} | '
            '${(g['grams'] as num?)?.toStringAsFixed(2)} ${g['hold']} '
            '${g['gram_basis']}';
      }

      expect(await read(), want);
      await matchAndCompute(db, _fx, r);
      expect(await read(), want, reason: 'the next compute');
    });
  }
}

/// STATED synthesized (a gate no corpus line reaches alone), naming its
/// corpus source.
void synthesized() {
  // The unit gate on a unit other than the clove: every corpus head line
  // on 1104647 is also guarded (0103|6 "1 head garlic, 5 medium cloves
  // minced …", 0316|5 "1 medium head garlic, …, plus 2 medium garlic
  // cloves, …"); source 0103|6 with its second count dropped. The head
  // keeps its 50 g piece; the arm's own line shape (0327|2, C3a) weighs its
  // volume.
  test('the unit gate: a garlic head beside a volume keeps its count '
      '(STATED, synthesized)', () async {
    final db = await _cached([169230]);
    final garlic = await _fx.food(1104647);
    String weigh(String raw) {
      final line = ln(raw);
      final g = lineGrams(db, line, garlic);
      return '${g?.grams.toStringAsFixed(2)} g ${g?.basis}';
    }

    expect(
      weigh('1 head garlic, minced (about 5 teaspoons)'),
      '50.00 g 1 head × 50 g each',
    );
    expect(
      weigh('1 small garlic clove, minced (about ½ teaspoon)'),
      '1.40 g 1/2 teaspoon · USDA portion of "Garlic, raw"',
    );
  });

  // The unit gate reads EVERY count amount, not the primary one alone: a
  // second count carrying a unit keeps the piece. No corpus line and no
  // parse of one has a non-primary count with a unit (the YAML rework's
  // fields may write one), so the amounts are built by hand — source
  // 0491|2's "2 medium garlic cloves, minced (about 2 teaspoons)" shape,
  // with a non-primary "1 head" amount added. Without it the line weighs
  // its 2 teaspoons (5.60 g).
  test('the unit gate: a non-primary count with a unit keeps the piece '
      '(STATED, the amounts built by hand)', () async {
    final db = await _cached([169230]);
    const raw = '2 medium garlic cloves, minced (about 2 teaspoons)';
    final parsed = ln(raw);
    final line = IngredientLine(
      raw: raw,
      item: parsed.item,
      prep: parsed.prep,
      amounts: [
        const Amount(measure: Measure.count, quantity: '2', primary: true),
        const Amount(measure: Measure.count, quantity: '1', unit: 'head'),
        const Amount(measure: Measure.volume, quantity: '2', unit: 'teaspoon'),
      ],
    );
    final g = lineGrams(db, line, await _fx.food(1104647));
    expect(
      '${g?.grams.toStringAsFixed(2)} g ${g?.basis}',
      '6.00 g 2 × 3 g each',
    );
  });
}

/// Cost (no step reader is added: the arm reads the line's parsed amounts
/// and raw text inside `lineGrams`): 400 lines of one real line under the
/// recipe's own steps — TRUE 0086|7 (each line weighs its 6 cups on SR
/// 170000), QUIET 0445|1 (the guard keeps the 150 g onion). The compute's
/// and the GET's counts are base f1a79b8's exactly (measured on both
/// trees, two runs each); the TRUE compute fetches 170000 once more than
/// base. Measured (base → v120): TRUE compute 566 / 492 → 608 / 521 ms, GET
/// 356 / 343 → 339 / 330 ms; QUIET compute 497 / 500 → 493 / 483 ms, GET
/// 319 / 299 → 315 / 301 ms.
void caps() {
  group(
    'RULE C, a counted piece beside a printed volume at the caps',
    skip: skipIfNoCorpus,
    () {
      for (final (shape, file, position, grams, foodCalls, compute, get) in [
        (
          'TRUE',
          '0086-hungarian-beef-stew.yaml',
          7,
          '960.00',
          2,
          _trueCompute,
          _trueGet,
        ),
        (
          'QUIET',
          '0445-potatoes-lyonnaise.yaml',
          1,
          '150.00',
          1,
          _quietCompute,
          _quietGet,
        ),
      ]) {
        test('$shape: 400 × $file|$position — $grams g a line, $foodCalls food '
            'details fetched, the counts exact, within the backstop', () async {
          final dir = Directory.systemTemp.createTempSync('salt-v120-cap-');
          final db = SaltDatabase.open(
            ServerConfig(
              dataDir: dir.path,
              logLevel: Level.WARNING,
              trustProxy: false,
            ).dbPath,
          )..upsertSource(slug: 'atk-tv-2023', name: 'ATK', type: 'epub');
          addTearDown(() {
            db.dispose();
            dir.deleteSync(recursive: true);
          });
          final fdc = FixtureProvider(pending: {...pendingSearches});
          final base = loadCorpusRecipe(file);
          final raw = nutritionLines(base)[position].raw;
          final r = capped(base, List.filled(capLines, raw), [
            for (final s in base.steps) s.text,
          ]).copyWith(id: 'cap-$shape', slug: 'cap-$shape');
          db.upsertRecipe(
            r,
            sourceSlug: 'atk-tv-2023',
            contentHash: contentHashOf(r),
          );
          final stored = db.recipeByIdOrSlug(r.id)!.recipe;
          stepIndexCounts.clear();
          final sw = Stopwatch()..start();
          expect(await matchAndCompute(db, fdc, stored), isNull);
          final computeMs = sw.elapsedMilliseconds;
          final computed = Map.of(stepIndexCounts);
          expectBounded(stored, computed, '$shape compute');
          expect(computed, jsonDecode(compute), reason: '$shape compute');
          expect(computeMs, lessThan(backstopMs), reason: '$shape compute');
          expect(fdc.foodCalls, foodCalls, reason: '$shape compute');
          final rows = db.ingredientMatchesFor(r.id);
          expect(rows, hasLength(capLines));
          expect({for (final m in rows) m.grams?.toStringAsFixed(2)}, {grams});
          stepIndexCounts.clear();
          sw.reset();
          final body = await matchesBody(
            db,
            fdc,
            db.recipeByIdOrSlug(r.id)!.recipe,
          );
          final getMs = sw.elapsedMilliseconds;
          final got = Map.of(stepIndexCounts);
          expectBounded(stored, got, '$shape GET');
          expect(got, jsonDecode(get), reason: '$shape GET');
          expect(getMs, lessThan(backstopMs), reason: '$shape GET');
          expect(body['items']! as List, hasLength(capLines));
        }, timeout: const Timeout(Duration(minutes: 3)));
      }
    },
  );
}

// The cost families base f1a79b8 counts on each shape (the probe's JSON,
// identical on the v120 tree).
const _trueCompute =
    '{"allSentences":1,"cheese":1,"heads":1,"indexes":1,"lower":1,"memo:braise":1,"memo:brineWords":1,"memo:brines":1,"memo:browningFat":1,"memo:dips":1,"memo:discards":1,"memo:keptSolids":1,"memo:leftInBowl":1,"memo:naming":1,"memo:parting":1,"memo:pourAway":1,"memo:reservedWhole":1,"memo:savesRemainder":1,"memo:setAsideLine":1,"memo:setsAsidePieces":1,"memo:skinSentences":1,"memo:starter":1,"memo:strain":1,"memo:strainAt":1,"memo:wordHeads":1,"sentences":17,"skinScans":1,"words":340}';
const _trueGet =
    '{"allSentences":1,"carriedReads":1,"cheese":1,"heads":1,"indexes":1,"lower":1,"memo:braise":1,"memo:brineWords":1,"memo:brines":1,"memo:browningFat":1,"memo:cutShare":1,"memo:dips":1,"memo:discards":1,"memo:keptSolids":1,"memo:leftInBowl":1,"memo:liftedFromMarinade":1,"memo:naming":1,"memo:panFatLines":1,"memo:parting":1,"memo:pourAway":1,"memo:reservedWhole":1,"memo:savesRemainder":1,"memo:setAsideLine":1,"memo:setsAsidePieces":1,"memo:skinSentences":1,"memo:starter":1,"memo:strain":1,"memo:strainAt":1,"memo:wordHeads":1,"sentences":17,"skinScans":1,"words":340}';
const _quietCompute =
    '{"allSentences":1,"cheese":1,"heads":1,"indexes":1,"lower":1,"memo:braise":1,"memo:brineWords":1,"memo:brines":1,"memo:browningFat":1,"memo:bundles":1,"memo:dips":1,"memo:discards":1,"memo:foodNaming":1,"memo:keptSolids":1,"memo:leftInBowl":1,"memo:naming":1,"memo:parting":1,"memo:pourAway":1,"memo:reservedWhole":1,"memo:savesRemainder":1,"memo:setAsideLine":1,"memo:setsAsidePieces":1,"memo:skinSentences":1,"memo:starter":1,"memo:strain":1,"memo:strainAt":1,"memo:wordHeads":1,"sentences":17,"skinScans":1,"words":275}';
const _quietGet =
    '{"allSentences":1,"carriedReads":1,"cheese":1,"heads":1,"indexes":1,"lower":1,"memo:braise":1,"memo:brineWords":1,"memo:brines":1,"memo:browningFat":1,"memo:bundles":1,"memo:cutShare":1,"memo:dips":1,"memo:discards":1,"memo:foodNaming":1,"memo:keptSolids":1,"memo:leftInBowl":1,"memo:liftedFromMarinade":1,"memo:naming":1,"memo:panFatLines":1,"memo:parting":1,"memo:pourAway":1,"memo:reservedWhole":1,"memo:savesRemainder":1,"memo:setAsideLine":1,"memo:setsAsidePieces":1,"memo:skinSentences":1,"memo:starter":1,"memo:strain":1,"memo:strainAt":1,"memo:wordHeads":1,"sentences":17,"skinScans":1,"words":275}';
