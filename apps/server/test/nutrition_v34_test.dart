// Real corpus file names wrap past the line limit; one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Matcher v34: the coat's other layers (the owner, 2026-10-03, "the
/// narrow version"). A nut, cheese, cracker, chip, cornflake or Melba toast
/// line named in a sentence that sets the coat out in its shallow dish or
/// names it with the crumbs is held `coating` with the dredge of a recipe
/// that holds one (L1), or of a recipe whose directions leave an excess of
/// the coat with no dredge line (L2). Every pin is a real corpus line.
void main() {
  DiscardedMedium? mediumOf(String file, int position, String raw) {
    final recipe = loadCorpusRecipe(file);
    final line = nutritionLines(recipe)[position];
    expect(line.raw, startsWith(raw), reason: file);
    return discardedMediumOf(recipe, line, normalizeItem(lineItemOf(line)));
  }

  String stepsOf(String file) =>
      loadCorpusRecipe(file).steps.map((s) => s.text).join(' ');

  group('v34 coat layers', skip: skipIfNoCorpus, () {
    test('L1: a layer named in the coat’s shallow dish or with its crumbs, '
        'in a recipe that holds a dredge, is held with it', () {
      for (final (file, position, raw, sentence) in const [
        (
          '0117-nut-crusted-chicken-breasts-with-lemon-and-thyme.yaml',
          2,
          '1 cup almonds, chopped coarse',
          'add the bread crumbs and ground almonds and cook',
        ),
        (
          '0315-oven-fried-onion-rings.yaml',
          6,
          '30 saltine crackers',
          'Pulse the saltines and chips together in a food processor until finely ground; place in a separate shallow baking dish.',
        ),
        (
          '0315-oven-fried-onion-rings.yaml',
          7,
          '4 cups kettle-cooked potato chips',
          'Pulse the saltines and chips together',
        ),
        (
          '0419-parmesan-crusted-chicken-cutlets.yaml',
          3,
          '¼ cup grated Parmesan cheese plus 6 ounces',
          'Whisk ¼ cup of the flour and the ¼ cup grated Parmesan together in a shallow dish.',
        ),
        (
          '0042-almond-crusted-chicken-with-wilted-spinach-salad.yaml',
          2,
          '1 cup sliced almonds',
          'Process the almonds in a food processor to fine crumbs',
        ),
        (
          '0407-eggplant-parmesan.yaml',
          3,
          '2 ounces Parmesan cheese, grated (about 1 cup)',
          'Transfer the crumbs to a pie plate and stir in the Parmesan',
        ),
        (
          '0416-lighter-chicken-parmesan.yaml',
          2,
          '1 ounce Parmesan cheese, grated (about ½ cup), plus extra',
          'Spread the bread crumbs in a shallow dish and cool slightly; when cool, stir in the Parmesan.',
        ),
      ]) {
        expect(stepsOf(file), contains(sentence), reason: file);
        expect(
          mediumOf(file, position, raw),
          DiscardedMedium.coating,
          reason: '$file #$position',
        );
      }
      // The crumbs each stirred-in layer is mixed through already hold
      // (v33), so the layer holds with them (0407 and 0416 are 0117's shape).
      for (final (file, position, raw) in const [
        (
          '0117-nut-crusted-chicken-breasts-with-lemon-and-thyme.yaml',
          5,
          '1 cup panko bread crumbs',
        ),
        (
          '0407-eggplant-parmesan.yaml',
          2,
          '8 slices high-quality white sandwich bread',
        ),
        ('0416-lighter-chicken-parmesan.yaml', 0, '1½ cups panko'),
      ]) {
        expect(
          mediumOf(file, position, raw),
          DiscardedMedium.coating,
          reason: '$file #$position',
        );
      }
    });

    test('L2: 0150 Oven-Fried Chicken has no dredge line to hold; its Melba '
        'toast is held by the excess signal ("Gently shake off the '
        'excess"), its oil drizzled over the crumbs is not a layer', () {
      const file = '0150-oven-fried-chicken.yaml';
      expect(leavesExcessForTest(loadCorpusRecipe(file)), isTrue);
      expect(
        stepsOf(file),
        contains(
          'Drizzle the oil over the Melba toast crumbs in a pie plate or shallow dish',
        ),
      );
      expect(
        mediumOf(file, 8, '1 box (about 5 ounces) plain Melba toast'),
        DiscardedMedium.coating,
      );
      expect(mediumOf(file, 7, '¼ cup vegetable oil'), isNull);
    });

    test('non-trips: named in a dish or with crumbs, but no held dredge and '
        'no excess sentence — a crust (0415, 0041, 0258), a binder (0000), '
        'nuts in a filling (0957), a chip garnish (0820), a gratin topping '
        '(0440)', () {
      for (final (file, position, raw) in const [
        ('0415-best-chicken-parmesan.yaml', 14, '1½ ounces Parmesan cheese'),
        (
          '0041-salad-with-herbed-baked-goat-cheese-and-vinaigrette.yaml',
          0,
          '3 ounces white Melba toasts',
        ),
        (
          '0041-salad-with-herbed-baked-goat-cheese-and-vinaigrette.yaml',
          6,
          '12 ounces goat cheese',
        ),
        (
          '0258-broiled-salmon-with-mustard-and-crisp-dilled-crust.yaml',
          1,
          '4 ounces plain high-quality potato chips',
        ),
        ('0000-italian-style-turkey-meatballs.yaml', 3, '1 ounce Parmesan'),
        ('0957-easy-apple-strudel.yaml', 7, '⅓ cup finely chopped walnuts'),
        (
          '0820-chocolate-chip-cookie-ice-cream-sandwiches.yaml',
          8,
          '½ cup (3 ounces) mini semisweet chocolate chips',
        ),
        ('0440-summer-vegetable-gratin.yaml', 10, '2 ounces grated Parmesan'),
      ]) {
        expect(
          mediumOf(file, position, raw),
          isNull,
          reason: '$file #$position',
        );
      }
    });

    test('non-trip: cheese in a sauce (0300 Classic Macaroni and Cheese, the '
        'cheddar whisked into the sauce; the crumbs sentence names no '
        'cheese, and the recipe holds no dredge)', () {
      const file = '0300-classic-macaroni-and-cheese.yaml';
      expect(
        stepsOf(file),
        contains('Off the heat, whisk in the cheeses until fully melted.'),
      );
      expect(leavesExcessForTest(loadCorpusRecipe(file)), isFalse);
      expect(mediumOf(file, 10, '8 ounces sharp cheddar cheese'), isNull);
      expect(mediumOf(file, 9, '8 ounces Monterey Jack cheese'), isNull);
    });

    test('non-trips in a recipe that holds a dredge: a cheese filling (0118 '
        'cream cheese, cheddar), a topping after the coat’s line of the same '
        'head (0407 mozzarella, the second Parmesan)', () {
      for (final (file, position, raw) in const [
        (
          '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
          3,
          '4 ounces cream cheese',
        ),
        (
          '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
          5,
          '2 ounces cheddar cheese',
        ),
        ('0407-eggplant-parmesan.yaml', 14, '8 ounces whole-milk'),
        ('0407-eggplant-parmesan.yaml', 15, '1 ounce Parmesan cheese'),
      ]) {
        expect(
          mediumOf(file, position, raw),
          isNull,
          reason: '$file #$position',
        );
      }
    });

    test('the quarter-cup guard: 0206’s 2 tablespoons of Parmesan tossed '
        'with the crumbs stay counted; the same line at ¼ cup (a stated '
        'negative-path edit of the real line) is held', () {
      const file = '0206-crunchy-baked-pork-chops.yaml';
      expect(stepsOf(file), contains('Toss the crumbs with the Parmesan'));
      expect(mediumOf(file, 7, '2 tablespoons grated Parmesan cheese'), isNull);
      // The real recipe with line 7 alone at ¼ cup: the guard is the only
      // condition that kept it counted.
      final recipe = loadCorpusRecipe(file);
      final edited = recipe.copyWith(
        ingredients: [
          for (final group in recipe.ingredients)
            group.copyWith(
              items: [
                for (final item in group.items)
                  item.raw == '2 tablespoons grated Parmesan cheese'
                      ? item.copyWith(
                          amounts: [
                            item.amounts.single.copyWith(
                              quantity: '1/4',
                              unit: 'cup',
                            ),
                          ],
                        )
                      : item,
              ],
            ),
        ],
      );
      final quarter = nutritionLines(edited)[7];
      expect(quarter.amounts.single.unit, 'cup');
      expect(
        discardedMediumOf(edited, quarter, normalizeItem(lineItemOf(quarter))),
        DiscardedMedium.coating,
      );
    });

    test('the guard reads no amount as no layer: 0419’s Parmesan line with '
        'its amounts removed (a stated negative-path edit; an amount-less '
        'line is 0 g unmeasured) stays counted', () {
      final recipe = loadCorpusRecipe(
        '0419-parmesan-crusted-chicken-cutlets.yaml',
      );
      final edited = recipe.copyWith(
        ingredients: [
          for (final group in recipe.ingredients)
            group.copyWith(
              items: [
                for (final item in group.items)
                  item.raw.startsWith('¼ cup grated Parmesan')
                      ? item.copyWith(amounts: const [])
                      : item,
              ],
            ),
        ],
      );
      final bare = nutritionLines(edited)[3];
      expect(bare.amounts, isEmpty);
      expect(
        discardedMediumOf(edited, bare, normalizeItem(lineItemOf(bare))),
        isNull,
      );
    });

    test(
      '(c): a row with no food gets no hold — 0198’s cornflakes, which '
      'the line reading reaches, are written unmatched by the compute',
      () async {
        const file = '0198-crispy-pan-fried-pork-chops.yaml';
        expect(mediumOf(file, 4, '3 cups cornflakes'), DiscardedMedium.coating);
        final dir = Directory.systemTemp.createTempSync('salt-v34');
        addTearDown(() => dir.deleteSync(recursive: true));
        final db = SaltDatabase.open('${dir.path}/salt.db');
        addTearDown(db.dispose);
        db.upsertSource(slug: 'src', name: 'Test', type: 'book');
        final recipe = loadCorpusRecipe(file);
        db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h');
        await matchAndCompute(db, FixtureProvider(), recipe);
        final rows = db.ingredientMatchesFor(recipe.id);
        final flakes = rows.singleWhere((r) => r.position == 4);
        expect(
          (flakes.status, flakes.fdcId, flakes.hold),
          ('unmatched', null, null),
        );
        // RE-PIN (M52 batch, v53, Q2 a): the cornstarch the engine held is
        // now counted by the coat budget, unheld (the cornflakes' row has
        // no food, so the cornstarch carries the whole budget: 793.79 g of
        // pork × C1 5.73 / 100 = 45.48 g carbohydrate, 49.83 g of it).
        final starch = rows.singleWhere((r) => r.position == 0);
        expect(
          (starch.hold, starch.gramSource, starch.grams?.toStringAsFixed(2)),
          (null, 'discarded', '49.83'),
        );
      },
    );
  });
}
