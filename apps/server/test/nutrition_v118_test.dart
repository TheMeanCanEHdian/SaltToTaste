// The v118 pins (batch M105, prep52 P6: portion and density figures;
// matcherVersion 104). W4: a rustic slice on its record's own BARE-noun
// slice (SR 174913 'slice' 29 g) ahead of the 50 g fallback, the 454 g loaf
// flagged. S8a: the 'ginger' density gone (SR 169231's own 'tsp' 2.0 g
// sizes the root), the per-inch figure 8 → 6 g (ginger, galangal). S8c:
// gelatin by the spoon at the corpus packet (¼ ounce in 2 teaspoons, 0.7190
// g/mL). S8b: the five instant espresso / coffee keys at the Branded labels'
// 2.0 g a teaspoon. S7a: whole / torn / loose mint leaves on SR 173474's
// spoon (`leafSiblings`). Corpus-backed groups skip without SALT_CORPUS_DIR;
// every corpus read sits inside a test body. Each pinned line is computed
// ALONE (its own line in its recipe's real steps) on the fixtures — the
// fixtures' details of 174913, 169231, 169599, 171893, 173475, 173474,
// 169103 and 167749 equal snapshot 33's.
//
// Hand derivations (grams × the record's kcal per 100 g, nutrient 208):
//   breakfast-strata|0 "8–10 … slices": midpoint 9 × 29 g = 261.00 g ×
//     2.59 = 675.99 (was 9 × 50 = 450.00 g, 1,165.50).
//   palak-dal|1 "1 tablespoon grated fresh ginger": 3 tsp × 2.0 g = 6.00 g
//     × 0.80 = 4.80 (was 14.79 mL × 0.54 = 7.98 g, 6.39).
//   xihongshi|3 "2 teaspoons …": 2 × 2.0 = 4.00 g, 3.20 (was 5.32, 4.26).
//   mahogany-chicken-thighs|7 "1 (2-inch) piece": 2 × 6 = 12.00 g, 9.60
//     (was 16.00, 12.80).
//   buttermilk-panna-cotta|1 "2 teaspoons unflavored gelatin": 9.86 mL ×
//     0.25 × 28.3495 / 9.85784 = 7.09 g × 3.35 = 23.74 (was 4.67, 15.63).
//   tiramisu|2 "1½ tablespoons instant espresso powder": 4.5 tsp × 2.0 =
//     9.00 g × 3.53 = 31.77 (was 9.54, 33.67).
//   thai-grilled-beef-salad|11 "1½ cups fresh mint leaves, torn": 24 tbsp ×
//     1.6 g = 38.40 g × 0.44 = 16.90 (was 136.80, 60.19).
// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

final _fx = FixtureProvider(pending: pendingSearches);

const _strata = '0743-breakfast-strata-with-spinach-and-gruyere.yaml';
const _palak = '0109-palak-dal-spinach-dal-with-cumin-and-mustard-seeds.yaml';
const _xihongshi =
    '1145-xihongshi-chao-jidan-chinese-stir-fried-tomatoes-and-eggs.yaml';
const _mahogany = '0129-mahogany-chicken-thighs.yaml';
const _pannaCotta =
    '0926-buttermilk-vanilla-panna-cotta-with-berries-and-honey.yaml';
const _bestStew = '0005-best-beef-stew.yaml';
const _tiramisu = '0910-tiramisu.yaml';
const _crinkle = '0822-chocolate-crinkle-cookies.yaml';
const _thaiBeef = '0556-thai-grilled-beef-salad.yaml';
const _bunCha = '0559-bun-cha.yaml';

const _packet =
    'approximate (ATK: 2 teaspoons ≈ 1 packet; 1 package = ¼ ounce)';
const _labels =
    'approximate (instant espresso labels (FDC Branded 2059824 DeLallo, 2503093 Ferrara): 1 teaspoon = 2.0 g)';
const _leaf = 'approximate (USDA 173474 Peppermint, fresh: 2 tbsp = 3.2 g)';
const _inch = 'approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)';

/// The moved rows, every stored column the rules write (the replay's, on
/// snapshot 33, equal to the fixtures' compute): (file, position, raw,
/// record, description, status, hold, gram source, confidence, grams,
/// kcal, basis).
const _moved = [
  (
    _strata,
    0,
    '8–10 (½-inch-thick) slices supermarket French or Italian bread',
    174913,
    'Bread, Italian',
    'auto',
    null,
    'piece',
    '0.575000',
    '261.00',
    '675.99',
    '8–10 slice · USDA portion',
  ),
  (
    _palak,
    1,
    '1 tablespoon grated fresh ginger',
    169231,
    'Ginger root, raw',
    'auto',
    null,
    'portion',
    '0.886667',
    '6.00',
    '4.80',
    '1 tablespoon · USDA portion',
  ),
  (
    _xihongshi,
    3,
    '2 teaspoons grated fresh ginger',
    169231,
    'Ginger root, raw',
    'auto',
    null,
    'portion',
    '0.886667',
    '4.00',
    '3.20',
    '2 teaspoon · USDA portion',
  ),
  (
    _mahogany,
    7,
    '1 (2-inch) piece ginger, peeled, halved, and smashed',
    169231,
    'Ginger root, raw',
    'auto',
    null,
    'piece',
    '0.886667',
    '12.00',
    '9.60',
    '1 piece × 2 inch × 6 g per inch · $_inch',
  ),
  (
    _pannaCotta,
    1,
    '2 teaspoons unflavored gelatin',
    169599,
    'Gelatins, dry powder, unsweetened',
    'auto',
    null,
    'density',
    '1.000000',
    '7.09',
    '23.74',
    '2 teaspoon ≈ 10 mL · $_packet',
  ),
  (
    _bestStew,
    15,
    '2 teaspoons (about 1 packet) unflavored powdered gelatin',
    169599,
    'Gelatins, dry powder, unsweetened',
    'auto',
    null,
    'density',
    '1.000000',
    '7.09',
    '23.74',
    '2 teaspoon ≈ 10 mL · $_packet',
  ),
  (
    _tiramisu,
    2,
    '1½ tablespoons instant espresso powder',
    171893,
    'Beverages, coffee, instant, regular, powder',
    'auto',
    null,
    'density',
    '0.583333',
    '9.00',
    '31.77',
    '1 1/2 tablespoon ≈ 22 mL · $_labels',
  ),
  (
    _crinkle,
    7,
    '4 teaspoons instant espresso powder (optional)',
    171893,
    'Beverages, coffee, instant, regular, powder',
    'auto',
    null,
    'density',
    '0.583333',
    '8.00',
    '28.24',
    '4 teaspoon ≈ 20 mL · $_labels',
  ),
  (
    _thaiBeef,
    11,
    '1½ cups fresh mint leaves, torn',
    173475,
    'Spearmint, fresh',
    'auto',
    null,
    'portion',
    '0.900000',
    '38.40',
    '16.90',
    '1 1/2 cup · USDA portion · $_leaf',
  ),
  (
    _bunCha,
    5,
    '1 cup fresh mint leaves, torn if large',
    173475,
    'Spearmint, fresh',
    'auto',
    null,
    'portion',
    '0.900000',
    '25.60',
    '11.26',
    '1 cup · USDA portion · $_leaf',
  ),
];

/// The design's negatives and the look-alikes, unchanged (file, position,
/// raw start, record, gram source, grams, basis) — the v117 rows,
/// byte-identical in the replay.
const _unmoved = [
  // S8a: a strained ginger stays 0 g (P5 before P6: the per-inch figure
  // never re-prices a strained row).
  (
    '0538-chinese-style-barbecued-spareribs.yaml',
    0,
    '1 (6-inch) piece fresh ginger',
    169231,
    'discarded',
    '0.00',
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  // S8a: the peel strips keep their own 0.8 g an inch (the "scale every
  // `_perInch` figure" mutant).
  (
    '0456-daube-provencal.yaml',
    15,
    '4 strips zest from 1 orange',
    169103,
    'piece',
    '9.60',
    '4 strip × 3 inch × 0.8 g per inch · approximate (ATK: 10 (3-inch) strips orange peel ≈ ¼ cup)',
  ),
  (
    '0959-bananas-foster.yaml',
    3,
    '1 (2-inch) strip zest from 1 lemon',
    167749,
    'piece',
    '1.60',
    '1 strip × 2 inch × 0.8 g per inch · approximate (the orange-peel strip figure, extended to lemon)',
  ),
  // S8a: the longer keys keep their own figures.
  (
    '0026-red-lentil-soup-with-warm-spices.yaml',
    5,
    '¼ teaspoon ground ginger',
    170926,
    'density',
    '0.46',
    '1/4 teaspoon ≈ 1 mL',
  ),
  // S8c: the packet by its printed weight.
  (
    '0937-chilled-lemon-souffle.yaml',
    1,
    '1 (¼-ounce) package gelatin',
    169599,
    'weight',
    '7.09',
    'from the printed weight',
  ),
  // S7a: the fine cuts keep 173475's own '2 tbsp' 11.4 g.
  (
    '0054-green-bean-salad-with-cherry-tomatoes-and-feta.yaml',
    5,
    '2 tablespoons chopped fresh mint',
    173475,
    'portion',
    '11.40',
    '2 tablespoon · USDA portion',
  ),
  (
    '0063-lentil-salad-with-olives-mint-and-feta.yaml',
    9,
    '½ cup minced fresh mint',
    173475,
    'portion',
    '45.60',
    '1/2 cup · USDA portion',
  ),
];

void main() {
  test('matcherVersion 107', () {
    // RE-PIN (M106 batch, v119): matcherVersion 105 (was 104).
    // RE-PIN (M107 batch, v120): matcherVersion 106 (was 105).
    // RE-PIN (M108 batch, v121): matcherVersion 107 (was 106).
    expect(matcherVersion, 107);
  });
  group(
    'v118 (M105: portion and density figures)',
    skip: skipIfNoCorpus,
    () {
      moved();
      unmoved();
      resolver();
      properties();
    },
  );
  synthesized();
}

/// [file]'s line [position] ALONE in its recipe (the real steps), stored
/// and computed on the fixtures — the recipe and the line's index (0).
Future<(SaltDatabase, Recipe)> _alone(String file, int position) async {
  final (db, _) = a.pathDb();
  final corpus = loadCorpusRecipe(file);
  final r = corpus.copyWith(
    ingredients: [
      IngredientGroup(items: [nutritionLines(corpus)[position]]),
    ],
  );
  await d.editAndCompute(db, _fx, r);
  return (db, r);
}

String? _kcal(SaltDatabase db, IngredientMatchRow row) => row.grams == null
    ? null
    : (kcalPer100g(knownFood(db, row.fdcId!)!) * row.grams! / 100)
          .toStringAsFixed(2);

/// R8: every stored column the rules write, the basis, and (A2) the
/// matches GET's grams and `gram_basis`.
void moved() {
  for (final (
        file,
        position,
        raw,
        fdcId,
        description,
        status,
        hold,
        source,
        confidence,
        grams,
        kcal,
        basis,
      )
      in _moved) {
    test('$file|$position: $fdcId $grams `$source`', () async {
      final (db, r) = await _alone(file, position);
      final line = nutritionLines(r).single;
      expect(line.raw, startsWith(raw));
      final row = d.rowOf(db, r, 0);
      expect(
        (
          row.fdcId,
          row.description,
          row.status,
          row.hold,
          row.gramSource,
          row.confidence.toStringAsFixed(6),
          row.grams?.toStringAsFixed(2),
          _kcal(db, row),
        ),
        (fdcId, description, status, hold, source, confidence, grams, kcal),
      );
      expect(gramBasisFor(db, line, row, recipe: r), basis);
      final body = await matchesBody(db, _fx, r);
      final m = ((body['items']! as List).single as Map)['match'] as Map;
      expect(
        ((m['grams'] as num?)?.toStringAsFixed(2), m['hold'], m['gram_basis']),
        (grams, hold, basis),
      );
    });
  }
}

/// The negatives keep their v117 rows.
void unmoved() {
  for (final (file, position, raw, fdcId, source, grams, basis) in _unmoved) {
    test('$file|$position unchanged: $fdcId $grams `$source`', () async {
      final (db, r) = await _alone(file, position);
      final line = nutritionLines(r).single;
      expect(line.raw, startsWith(raw));
      final row = d.rowOf(db, r, 0);
      expect(
        (row.fdcId, row.gramSource, row.grams?.toStringAsFixed(2)),
        (fdcId, source, grams),
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

GramResolution? _on(IngredientLine line, FdcFood? food) => resolveGrams(
  amounts: line.amounts,
  food: food,
  normalizedItem: normalizeItem(lineItemOf(line)),
  raw: line.raw,
);

/// The rows no fixture compute reaches whole (a person's pick in the
/// library; a section line) and the resolver's own gates, on corpus lines.
void resolver() {
  test('W4: acquacotta|16 (a person-picked row in the library) on 174913 '
      'reads its slice, 290.00 g; the bruschetta section loaf 454 g, '
      'flagged; the same rustic slice with no record keeps 50 g, '
      'unflagged', () async {
    final bread = (await _fx.food(174913))!;
    final slices = _lineOf(
      '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml',
      '10 (½-inch-thick) slices thick-crusted country bread',
    );
    final loaf = _lineOf(
      '1189-bruschetta-with-artichoke-hearts-and-parmesan.yaml',
      '1 (10 by 5-inch) loaf country bread',
    );
    String? g(GramResolution? x) =>
        x == null ? null : '${x.grams.toStringAsFixed(2)} ${x.basis}';
    expect(g(_on(slices, bread)), '290.00 10 slice · USDA portion');
    expect(
      g(_on(loaf, bread)),
      '454.00 1 loaf × 454 g each · approximate (ATK: a 1-pound loaf)',
    );
    expect(g(_on(slices, null)), '500.00 10 slice × 50 g each');
  });

  test('S8a: galangal by the inch on ginger root at 6 g (guay-tiew|5); a '
      'bare-count piece ("1 (1-inch piece) ginger", crispy-thai-eggplant|4) '
      'at 6 g; fresh ginger with no record reads no table figure', () async {
    final root = (await _fx.food(169231))!;
    final galangal = _lineOf(
      '0011-guay-tiew-tom-yum-goong-thai-hot-and-sour-noodle-soup-with-shrimp.yaml',
      '1 (2-inch) piece fresh galangal',
    );
    final bare = _lineOf(
      '0053-crispy-thai-eggplant-salad.yaml',
      '1 (1-inch piece) ginger',
    );
    final grated = _lineOf(_palak, '1 tablespoon grated fresh ginger');
    expect(
      _on(galangal, root)?.basis,
      "1 piece × 2 inch × 6 g per inch · approximate (ginger's figure (ATK's substitute for galangal))",
    );
    expect(_on(galangal, root)?.grams.toStringAsFixed(2), '12.00');
    expect(
      _on(bare, root)?.basis,
      '1 × 1 inch × 6 g per inch · $_inch',
    );
    expect(_on(bare, root)?.grams.toStringAsFixed(2), '6.00');
    expect(_on(grated, null), isNull);
  });

  // S7a's fetch arm in `gramsFor` asks for 173474 only for a VOLUME line on
  // 173475 (its `volumeMlOf(line.amounts) != null` gate, closed in the M105
  // closer round 1): berry-fool|8 "6 sprigs fresh mint (optional)" — one of
  // the two non-volume rows on 173475 — computed alone on a cold cache asks
  // FDC for its own record only; the control, thai-grilled-beef-salad|11
  // "1½ cups fresh mint leaves, torn", fetches the sibling too.
  test('S7a: a sprig line on 173475 (berry-fool|8) never fetches 173474; a '
      'volume leaf line (thai-grilled-beef-salad|11) does', () async {
    Future<(int, bool, String)> cold(String file, int position) async {
      final (db, _) = a.pathDb();
      final fx = FixtureProvider(pending: pendingSearches);
      final corpus = loadCorpusRecipe(file);
      final r = corpus.copyWith(
        ingredients: [
          IngredientGroup(items: [nutritionLines(corpus)[position]]),
        ],
      );
      await d.editAndCompute(db, fx, r);
      final row = d.rowOf(db, r, 0);
      return (
        fx.foodCalls,
        db.fdcFoodCacheGet(173474) != null,
        '${row.fdcId} ${row.grams?.toStringAsFixed(2)}',
      );
    }

    expect(await cold('0965-berry-fool.yaml', 8), (1, false, '173475 0.00'));
    expect(await cold(_thaiBeef, 11), (2, true, '173475 38.40'));
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

/// The shipped rustic-bread words (`_rusticBreadWords`), read by another
/// method: the property's reference.
const _rustic = [
  'rustic',
  'country',
  'crusty',
  'artisan',
  'peasant',
  'sourdough',
  'ciabatta',
  'baguette',
  'french',
  'italian',
];
final _cutWord = RegExp(r'\b(chopped|minced|diced|grated|sliced|shredded)\b');

/// R9 / A5 — what each changed table sizes, over every corpus recipe's own
/// lines (the property's limit: the titled sections' lines are not looped;
/// the replay's sections hold the bruschetta loaf and the section rows the
/// replay names). Each item's class is every corpus line naming its food,
/// weighed through `lineGrams` (the recipe's real steps) on the item's
/// RECORD whatever record the matcher gives the line — the selector of the
/// site, not the replay's reach (the replay is the reach: docs/API.md
/// "Matcher v118").
void properties() {
  test('the five selectors on every corpus line', () async {
    final (db, _) = a.pathDb();
    final foods = {
      for (final id in [174913, 169231, 169599, 171893, 173475, 173474])
        id: (await _fx.food(id))!,
    };
    db.fdcFoodCachePut(173474, jsonEncode(foods[173474]!.toJson()));
    final out = <String, List<String>>{};
    void add(String k, String v) => (out[k] ??= []).add(v);
    for (final file in _files()) {
      final r = loadCorpusRecipe(file);
      for (final (k, line) in nutritionLines(r).indexed) {
        final tag = '$file|$k';
        final item = normalizeItem(lineItemOf(line));
        final words = item.split(RegExp('[^a-z]+')).toSet();
        // The grams too, so each class's SHA pins the figure, not only
        // which lines read it.
        String? basisOn(int id) => switch (lineGrams(
          db,
          line,
          foods[id],
          recipe: r,
        )) {
          final g? => '${g.grams.toStringAsFixed(2)} g ${g.basis}',
          null => null,
        };
        final units = {for (final x in line.amounts) (x.unit ?? '')};
        // W4: a rustic bread counted by the slice or the loaf.
        if (RegExp('bread|ciabatta|baguette').hasMatch(item) &&
            _rustic.any(item.contains) &&
            units.intersection({
              'slice',
              'slices',
              'loaf',
              'loaves',
            }).isNotEmpty) {
          final b = basisOn(174913) ?? '-';
          add(
            b.endsWith('slice · USDA portion')
                ? 'w4.slice'
                : b.contains('(ATK: a 1-pound loaf)')
                ? 'w4.loaf'
                : b.contains('× 50 g each')
                ? 'w4.fifty'
                : 'w4.other',
            '$tag $b',
          );
        }
        // S8a: fresh ginger (and galangal) on 169231.
        if (words.contains('ginger') || words.contains('galangal')) {
          final b = basisOn(169231) ?? '-';
          add(
            b.contains(' × 6 g per inch')
                ? 's8a.inch'
                : b.contains(' × 8 g per inch')
                ? 's8a.inch8'
                : b.contains('· USDA portion')
                ? 's8a.record'
                : b.contains(' mL')
                ? (RegExp(
                        r'\b(ground|crystallized) ginger\b',
                      ).hasMatch(line.raw.toLowerCase())
                      ? 's8a.table'
                      : 's8a.table-fresh')
                : 's8a.other',
            '$tag $b',
          );
        }
        // S8c: gelatin on 169599.
        if (words.contains('gelatin')) {
          final b = basisOn(169599) ?? '-';
          add(
            b.contains(_packet)
                ? 's8c.packet'
                : b.contains('· USDA portion')
                ? 's8c.envelope'
                : 's8c.other',
            '$tag $b',
          );
        }
        // S8b: instant espresso / coffee on 171893.
        if (words.contains('espresso') ||
            (words.contains('coffee') &&
                (words.contains('instant') || words.contains('powder')))) {
          final b = basisOn(171893) ?? '-';
          add(b.contains(_labels) ? 's8b.labels' : 's8b.other', '$tag $b');
        }
        // S7a: mint by the volume on 173475.
        if (words.contains('mint') && volumeMlOf(line.amounts) != null) {
          final b = basisOn(173475) ?? '-';
          final cut = _cutWord.hasMatch(line.raw.toLowerCase());
          add(
            b.contains(_leaf)
                ? (cut ? 's7a.leaf-but-cut' : 's7a.leaf')
                : (cut ? 's7a.cut' : 's7a.whole-unflagged'),
            '$tag $b',
          );
        }
      }
    }
    final got = {
      for (final MapEntry(:key, :value) in out.entries)
        key: (value.length, _sha(value)),
    };
    // Measured on the v118 tree. Absent keys are the disjoint classes, each
    // empty: no rustic slice at 50 g on a record printing its own slice
    // (`w4.fifty`), no piece at 8 g an inch (`s8a.inch8`), no fresh ginger by
    // a table density (`s8a.table-fresh`: the 19 table lines are ground or
    // crystallized ginger, longer keys), no gelatin spoon on 169599's
    // envelope (`s8c.envelope`), no cut mint flagged (`s7a.leaf-but-cut`) and
    // no whole-leaf mint volume unflagged (`s7a.whole-unflagged`). The
    // others: w4.other the printed weights; s8a.other a printed weight (1172
    // |0); s8b.other the espresso BEANS (0905|1) and a reference line (0899
    // |10); s8c.other the packet's printed weight (0937|1). s7a.leaf holds 4
    // dried-mint lines (0026|14, 0375|9, 1145|7, 1184|9) the matcher never
    // lands on 173475 (the replay's 8 rows are the fresh leaves): stated.
    expect(got, {
      'w4.slice': (
        3,
        'e1d01d63eb1955d1a0624df08639ea53c0dd34a44c3c6b4241ecba384fd1622e',
      ),
      'w4.loaf': (
        2,
        '5a9517ea0fb0675d2552b9c0548b563070c466892113b425ae354fd666ec222b',
      ),
      'w4.other': (
        5,
        '54c0785cb73ea963cd5ca686614aac56f75167b256b8fc7beaba2a50d7c49820',
      ),
      's8a.inch': (
        18,
        '81d237d263b5fc532e5a5db1afc1fea1ec77f0ec6132afd1df2f670a1e237afc',
      ),
      's8a.record': (
        62,
        'd002ee1ac70dc92155be0fdc9f07bf983f52cc203530a15cd01bed753b9fd11f',
      ),
      's8a.table': (
        19,
        'fe5cd3b978b66185aa39cfa297bb06f2cdbd365b9a2264e7e6da1efdfda4bf89',
      ),
      's8a.other': (
        1,
        '9d5a2990459e77d0492e69c413e402b511082409d8ec0d4ca1303be5a2222b7b',
      ),
      's8c.packet': (
        32,
        '75445bb5993c5151c37118df165047ab95d8f208b338617466c9a16978aa1ec2',
      ),
      's8c.other': (
        1,
        '7399bbec7b366993e3d4f125dedcdea8016addb61166edcc98bd7d5b92a6855a',
      ),
      's8b.labels': (
        16,
        '8c76418992e1b2fef6c21f7bd9dd0efebe6e95f4a6a6ad8914e121b3b098c32f',
      ),
      's8b.other': (
        2,
        '082f6b7c616f883f03610d4c34501ca17de936cc00bc0e436a4346a8d7f72181',
      ),
      's7a.leaf': (
        12,
        '90815e9f0ee5aa2e0759a291f49619200e39e6c06171902e3571cd8010ece6d0',
      ),
      's7a.cut': (
        24,
        '5b7b32a2afe9105fa5ec1c1da9ac18f99e849a488ac90a5c5fea7f12f969f211',
      ),
    });
  });
}

/// STATED synthesized (negative path): inputs no corpus line holds, each
/// naming its corpus source.
void synthesized() {
  // Each of S8b's five keys alone, so a mutant leaving ONE key at the old
  // 0.43 dies on a value: the corpus's 16 instant espresso / coffee lines
  // (the property's `s8b.labels`; e.g. 0897|0 "2 teaspoons instant coffee
  // powder", 0822|7 "4 teaspoons instant espresso powder") reach the keys
  // by their longest match, so a key no corpus line ends on is pinned here.
  // 2 teaspoons × 2.0 g = 4.00 g (was 0.43 × 9.86 mL = 4.24 g).
  test(
    'S8b: each of the five keys weighs 2 teaspoons at 4.00 g, flagged',
    () async {
      final coffee = (await FixtureProvider().food(171893))!;
      for (final item in [
        'espresso powder',
        'instant coffee',
        'coffee powder',
        'instant coffee powder',
        'instant espresso',
      ]) {
        final g = resolveGrams(
          amounts: const [
            Amount(
              measure: Measure.volume,
              quantity: '2',
              unit: 'teaspoon',
              primary: true,
            ),
          ],
          food: coffee,
          normalizedItem: item,
          raw: '2 teaspoons $item',
        );
        expect(
          (g?.grams.toStringAsFixed(2), g?.source, g?.basis),
          ('4.00', GramSource.density, '2 teaspoon ≈ 10 mL · $_labels'),
          reason: item,
        );
      }
    },
  );

  // W4: the loaf flag on the plural unit — the corpus's two flagged loaves
  // (the property's `w4.loaf`: 1075|0, 1146|2) are each "1 loaf"; with no
  // record the fallback weighs "2 loaves crusty bread" at 2 × 454 g.
  test('W4: "2 loaves crusty bread" (no record) is 908 g, flagged', () {
    final g = resolveGrams(
      amounts: const [
        Amount(
          measure: Measure.count,
          quantity: '2',
          unit: 'loaves',
          primary: true,
        ),
      ],
      food: null,
      normalizedItem: 'crusty bread',
      raw: '2 loaves crusty bread',
    );
    expect(
      (g?.grams.toStringAsFixed(2), g?.basis),
      ('908.00', '2 loaves × 454 g each · approximate (ATK: a 1-pound loaf)'),
    );
  });

  // S7a's four cut words no corpus mint line prints ("diced", "grated",
  // "sliced", "shredded"; the property's 24 cut lines say chopped / minced;
  // diced and grated added in the M105 closer round 1) and a printed weight
  // beside the volume (no corpus mint line prints one): each keeps 173475's
  // own reading, unflagged, with 173474 cached. Sources: 0063|9 "½ cup
  // minced fresh mint" re-worded; 0556|11 "1½ cups fresh mint leaves" with
  // a weight.
  test('S7a: diced, grated, sliced, shredded and a printed weight stay on '
      '173475 (unflagged)', () async {
    final (db, _) = a.pathDb();
    final fx = FixtureProvider();
    final spearmint = (await fx.food(173475))!;
    db.fdcFoodCachePut(173474, jsonEncode((await fx.food(173474))!.toJson()));
    String? on(String raw) {
      final p = parseIngredientLine(raw);
      final g = lineGrams(
        db,
        IngredientLine(raw: raw, item: p.item, amounts: p.amounts),
        spearmint,
      );
      return g == null ? null : '${g.grams.toStringAsFixed(2)} ${g.basis}';
    }

    // 'Chopped': owner gate — the cut word read case-sensitively passed the
    // file; the whole-library replay is byte-identical under it (0 of the
    // corpus's 59 mint lines capitalise a cut word).
    for (final cut in ['diced', 'grated', 'sliced', 'shredded', 'Chopped']) {
      expect(
        on('½ cup $cut fresh mint'),
        '45.60 1/2 cup · USDA portion',
        reason: cut,
      );
    }
    expect(
      on('1 ounce (about 1 cup) fresh mint leaves'),
      '28.35 from 1 ounce',
    );
    // Not vacuous: the same whole leaves by the volume alone are flagged.
    expect(
      on('½ cup fresh mint leaves'),
      '12.80 1/2 cup · USDA portion · $_leaf',
    );
    // Owner gate: `leafWeighing` answers a VOLUME line only. Without its
    // volume guard the file passed and the replay is byte-identical —
    // `lineGrams` keeps a leaf weighing only when it sized the line by a
    // portion, and the sibling food carries volume portions alone — so the
    // guard is pinned where it differs, on the function (0965|8's "6 sprigs
    // fresh mint (optional)", a count; the whole leaves by the cup beside it).
    final peppermint = (await fx.food(173474))!;
    ({FdcFood food, String note})? leaf(String raw) => leafWeighing(
      spearmint,
      peppermint,
      raw,
      parseIngredientLine(raw).amounts,
    );
    expect(leaf('6 sprigs fresh mint (optional)'), isNull);
    expect(leaf('½ cup fresh mint leaves')?.note, _leaf);
  });
}
