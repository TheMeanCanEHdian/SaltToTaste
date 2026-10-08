// Real corpus lines wrap across adjacent literals; the table keeps each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Matcher v42, B — canned beans (the owner's 2026-10-06 ruling (b)). A can
/// line weighed by its printed weight on a Foundation "drained and rinsed"
/// bean record counts its bean's drained share from FDC's own SR can pair
/// (chickpea, kidney, pinto; black, cannellini and navy the median),
/// flagged; a line keeping the liquid counts the can whole, "1 can
/// drained, 1 can undrained" half the cans at the share. Each row is a real
/// corpus line at the record, grams and basis the cache-only replay of
/// snapshot 19 derives at v42; the pairs are copied from snapshot 19
/// (tool/record_fdc_fixtures.dart --from-db).
void main() {
  /// [from]'s line at [position], alone in a recipe with [from]'s steps and
  /// prep notes, matched and computed on the fixtures; its one row and line.
  Future<(SaltDatabase, IngredientMatchRow, IngredientLine)> computed(
    Recipe from,
    int position,
  ) async {
    final line = nutritionLines(from)[position];
    final dir = Directory.systemTemp.createTempSync('salt-v42');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    db.upsertSource(slug: 'src', name: 'Test', type: 'book');
    final recipe = Recipe(
      id: 'r',
      title: 'r',
      slug: 'r',
      source: const RecipeSource(name: 'Test', type: 'book'),
      prepNotes: from.prepNotes,
      steps: from.steps,
      ingredients: [
        IngredientGroup(items: [line]),
      ],
    );
    db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'hr');
    await matchAndCompute(db, FixtureProvider(), recipe);
    return (db, db.ingredientMatchesFor('r').single, line);
  }

  test('each share is its FDC can pair, drained ÷ whole, to 3 dp; the '
      "median is the three pairs' middle; rinsing adds no factor", () async {
    final provider = FixtureProvider();
    Future<double> grams(int id, String portion) async => (await provider.food(
      id,
    ))!.portions.singleWhere((p) => p.description == portion).gramWeight;
    final pairs = {
      2644288: (
        await grams(173800, 'can drained'),
        await grams(175206, 'can (total can contents)'),
      ),
      2644289: (
        await grams(174285, 'can drained solids'),
        await grams(175195, 'can'),
      ),
      2644292: (
        await grams(174286, 'can drained solids'),
        await grams(175201, 'can'),
      ),
    };
    final shares = <double>[];
    for (final MapEntry(key: id, value: (drained, whole)) in pairs.entries) {
      final share = double.parse((drained / whole).toStringAsFixed(3));
      expect(cannedBeanShares[id]!.share, share, reason: '$id');
      expect(
        cannedBeanShares[id]!.from,
        endsWith('${drained.round()} g of ${whole.round()} g'),
      );
      shares.add(share);
    }
    shares.sort();
    expect(cannedBeanMedian, shares[1]);
    for (final id in [2644285, 2644287, 2644286]) {
      expect(cannedBeanShares[id]!.share, cannedBeanMedian, reason: '$id');
    }
    expect(cannedBeanShares.keys.toSet(), {
      2644288, 2644289, 2644292, 2644285, 2644287, 2644286, //
    });
    final rinsed = (await provider.food(175243))!.portions;
    expect(rinsed.map((p) => p.description), ['cup cup rinsed solids']);
  });

  group('in their recipes', skip: skipIfNoCorpus, () {
    test('the drained shares, the median, the half can, and the lines that '
        'keep the liquid, line by line', () async {
      for (final (file, position, raw, fdcId, grams, basis) in _pins) {
        final (db, row, line) = await computed(
          loadCorpusRecipe(file),
          position,
        );
        expect(line.raw, raw, reason: file);
        expect(row.fdcId, fdcId, reason: raw);
        expect(row.status, 'auto', reason: raw);
        expect(row.hold, isNull, reason: raw);
        expect(row.grams?.toStringAsFixed(2), grams, reason: raw);
        expect(
          gramBasisFor(
            db,
            line,
            row,
            recipe: db.recipeByIdOrSlug('r')!.recipe,
          ),
          basis,
          reason: raw,
        );
      }
    });
  });
}

const _pins = [
  (
    '0026-harira-moroccan-lentil-and-chickpea-soup.yaml',
    14,
    '1 (15-ounce) can chickpeas, rinsed',
    2644288,
    '240.26',
    "from the printed weight × 0.565 drained · approximate (drained weight: FDC's canned chickpea pair, 253 g of 448 g)",
  ),
  (
    '0495-beef-chili-with-kidney-beans.yaml',
    11,
    '2 (15-ounce) cans dark red kidney beans, drained and rinsed',
    2644289,
    '518.80',
    "2 × 425 g (printed weight) × 0.610 drained · approximate (drained weight: FDC's canned kidney bean pair, 266 g of 436 g)",
  ),
  // A can line with no drain word: the record is the drained beans.
  // RE-PIN (M47 batch, v49 Q14): its steps add "beans and their liquid" —
  // the whole can, on the pinto solids-and-liquids record (was 2644292,
  // 266.63 g at the drained share).
  (
    '0009-best-ground-beef-chili.yaml',
    17,
    '1 (15-ounce) can pinto beans',
    175201,
    '425.24',
    'from the printed weight (the steps add the beans and their liquid)',
  ),
  (
    '0072-skillet-tamale-pie.yaml',
    6,
    '1 (15-ounce) can black beans, drained and rinsed',
    2644285,
    '259.40',
    "from the printed weight × 0.610 drained · approximate (drained weight: the median of FDC's three canned-bean pairs, 0.610)",
  ),
  (
    '1075-espinacas-con-garbanzos-andalusian-spinach-and-chickpeas.yaml',
    1,
    '2 (15-ounce) cans chickpeas (1 can drained, 1 can undrained)',
    2644288,
    '665.50',
    // RE-PIN (M47 batch, v49 Q14 ii): the undrained can is a part on the
    // chickpea solids-and-liquids record (grams unchanged; the row's parts
    // pinned in nutrition_v49_test).
    "2 × 425 g (printed weight) × 0.565 drained on half the cans · approximate (drained weight: FDC's canned chickpea pair, 253 g of 448 g) · the undrained can on its solids-and-liquids record",
  ),
  (
    '0429-garlicky-shrimp-tomato-and-white-bean-stew.yaml',
    8,
    '2 (15-ounce) cans cannellini beans (1 can drained and rinsed, 1 can left undrained)',
    2644287,
    '684.64',
    "2 × 425 g (printed weight) × 0.610 drained on half the cans · approximate (drained weight: the median of FDC's three canned-bean pairs, 0.610)",
  ),
  // Not one of the six drained bean records (FNDDS "Lima beans, from
  // canned"): the can counts whole.
  (
    '1074-paella-de-verduras-cauliflower-and-bean-paella.yaml',
    11,
    '1 (15-ounce) can butter beans, rinsed',
    2709850,
    '425.24',
    'from the printed weight',
  ),
  // The liquid kept: the can counts whole.
  // RE-PIN (M47 batch, v49 Q14 ii): both on the chickpea solids-and-liquids
  // record 175206 (was 2644288), grams unchanged.
  (
    '1096-chana-masala.yaml',
    11,
    '2 (15-ounce) cans chickpeas, undrained',
    175206,
    '850.49',
    '2 × 425 g (printed weight)',
  ),
  (
    '0340-pasta-e-ceci-pasta-with-chickpeas.yaml',
    10,
    '2 (15-ounce) cans chickpeas (do not drain)',
    175206,
    '850.49',
    '2 × 425 g (printed weight)',
  ),
  (
    '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml',
    9,
    '2 (15-ounce) cans cannellini beans, drained with liquid reserved, rinsed',
    2644287,
    '850.49',
    '2 × 425 g (printed weight)',
  ),
];
