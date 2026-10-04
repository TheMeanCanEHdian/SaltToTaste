// Real corpus file names wrap past the line limit; one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Matcher v33: the dredge-reach ruling (the owner, 2026-10-03, on the
/// dredge survey's option 1 — `.claude/diag/2026-10-01/prep30/dredge.md`):
/// a reachable dredge is held `coating` in ANY cooking class whose
/// directions leave an excess of the coat, and still whenever the recipe
/// fries; a coat wholly eaten stays counted. Every pin is a real corpus
/// line; the recorded answers come from snapshot 14, never live.
void main() {
  DiscardedMedium? mediumOf(String file, int position, String raw) {
    final recipe = loadCorpusRecipe(file);
    final line = nutritionLines(recipe)[position];
    expect(line.raw, startsWith(raw), reason: file);
    return discardedMediumOf(recipe, line, normalizeItem(lineItemOf(line)));
  }

  group('v33 dredge reach', skip: skipIfNoCorpus, () {
    test('the excess signal reproduces the survey Y/N on all 47 in-scope '
        'recipes (shake / remove / pat off the excess of the coat)', () {
      for (final (file, cls, excess) in _survey) {
        expect(
          leavesExcessForTest(loadCorpusRecipe(file)),
          excess,
          reason: '$file [$cls]',
        );
      }
      expect(_survey, hasLength(47));
    });

    test('held in every cooking class whose directions leave an excess: '
        'sautéed (0418 piccata), baked (0122 Kiev), shallow (0118), fried '
        '(0148, unchanged)', () {
      for (final (file, position, raw) in const [
        ('0418-chicken-piccata.yaml', 3, '½ cup unbleached all-purpose flour'),
        ('0257-pan-seared-salmon-steaks.yaml', 2, '¼ cup cornstarch'),
        ('0235-maple-glazed-pork-tenderloin.yaml', 6, '¼ cup cornstarch'),
        ('0122-chicken-kiev.yaml', 11, '1 cup unbleached all-purpose flour'),
        (
          '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
          10,
          '¾ cup unbleached all-purpose flour',
        ),
        ('0148-crispy-fried-chicken.yaml', 8, '4 cups (20 ounces)'),
      ]) {
        expect(
          mediumOf(file, position, raw),
          DiscardedMedium.coating,
          reason: file,
        );
      }
    });

    test('a coat wholly eaten stays counted in every class: a coat set out '
        'in a shallow dish with no excess sentence (0414 Marsala, 0115 '
        'katsu, 1093 tacos, 1185 air-fried), a toss (0536)', () {
      for (final (file, position, raw) in const [
        ('0414-chicken-marsala.yaml', 1, '1 cup unbleached all-purpose flour'),
        (
          '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
          0,
          '2 cups panko bread crumbs',
        ),
        ('1093-vegan-baja-style-cauliflower-tacos.yaml', 7, '1 cup panko'),
        ('1185-spicy-fried-chicken-sandwiches.yaml', 0, '1 cup panko'),
        ('0536-crispy-orange-beef.yaml', 2, '6 tablespoons cornstarch'),
      ]) {
        expect(mediumOf(file, position, raw), isNull, reason: file);
      }
    });

    test('D2: the bread a newly held breading crumbs is held with its flour '
        '— a step pulses it (0122 Kiev) or the line says so (0118)', () {
      expect(
        mediumOf('0122-chicken-kiev.yaml', 7, '4 slices high-quality white'),
        DiscardedMedium.coating,
      );
      expect(
        mediumOf(
          '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
          13,
          '4 slices high-quality white sandwich bread, pulsed',
        ),
        DiscardedMedium.coating,
      );
    });

    test('D2: a crumb or panko line the steps call by another name is held '
        'with the flour of the same coat (0416 "coat both sides of the '
        'chicken with the bread crumbs"; 0117 "the panko mixture")', () {
      expect(
        mediumOf(
          '0416-lighter-chicken-parmesan.yaml',
          0,
          '1½ cups panko (Japanese-style bread crumbs)',
        ),
        DiscardedMedium.coating,
      );
      expect(
        mediumOf(
          '0117-nut-crusted-chicken-breasts-with-lemon-and-thyme.yaml',
          5,
          '1 cup panko bread crumbs',
        ),
        DiscardedMedium.coating,
      );
      // Each guard on its own (0416 edited, a stated exception: no corpus
      // recipe holds a dredge with a crumb line under a quarter cup or with
      // no sentence coating the food in crumbs): 3 tablespoons of the panko,
      // or the coat sentence cut — counted.
      final parm = loadCorpusRecipe('0416-lighter-chicken-parmesan.yaml');
      final panko = nutritionLines(parm)[0];
      final small = panko.copyWith(
        amounts: [
          panko.amounts.single.copyWith(quantity: '3', unit: 'tablespoon'),
        ],
      );
      expect(
        discardedMediumOf(parm, small, normalizeItem(lineItemOf(small))),
        isNull,
      );
      const coat =
          'Finally, coat both sides of the chicken with the bread '
          'crumbs. ';
      final uncoated = parm.copyWith(
        steps: [
          for (final step in parm.steps)
            step.copyWith(text: step.text.replaceAll(coat, '')),
        ],
      );
      expect(
        uncoated.steps.map((s) => s.text).join(),
        isNot(contains(coat)),
      );
      final line = nutritionLines(uncoated)[0];
      expect(
        discardedMediumOf(uncoated, line, normalizeItem(lineItemOf(line))),
        isNull,
      );
    });

    test('D3: a fried dredge stays held with no excess sentence (0288 '
        'Maryland crab cakes, "Lightly dredge")', () {
      const file = '0288-maryland-crab-cakes.yaml';
      expect(leavesExcessForTest(loadCorpusRecipe(file)), isFalse);
      expect(
        mediumOf(file, 8, '¼ cup unbleached all-purpose flour'),
        DiscardedMedium.coating,
      );
    });

    test('a dough dusted and shaken off is no dredge (0792 rolls, 0806 '
        'pita): its flour counts', () {
      for (final (file, position, raw) in const [
        ('0792-rustic-dinner-rolls.yaml', 3, '3 cups plus 1 tablespoon'),
        ('0806-pita-bread.yaml', 0, '2⅔ cups (14⅔ ounces) bread flour'),
      ]) {
        expect(leavesExcessForTest(loadCorpusRecipe(file)), isFalse);
        expect(mediumOf(file, position, raw), isNull, reason: file);
      }
    });

    test("a plus line's set-out part is the dredge's: 0206's ¼ cup goes to "
        'the pie plate, its 6 tablespoons into the egg whites — eaten, held '
        'with the line', () async {
      final recipe = loadCorpusRecipe('0206-crunchy-baked-pork-chops.yaml');
      final line = nutritionLines(recipe)[10];
      expect(line.raw, '¼ cup plus 6 tablespoons unbleached all-purpose flour');
      final flour = (await FixtureProvider().food(789890))!;
      final out = engineOutcome(
        recipe,
        line,
        flour,
        resolveGrams(
          amounts: line.amounts,
          food: flour,
          normalizedItem: normalizeItem(lineItemOf(line)),
        ),
      );
      expect(out.grams, closeTo(45.25, 0.01));
      expect((out.source, out.hold), ('discarded', 'coating'));
    });
  });
}

/// The survey's 47 in-scope recipes: file, class, "the directions leave an
/// excess" (the survey's reading).
const _survey = [
  ('0148-crispy-fried-chicken.yaml', 'DEEP', true),
  ('0116-chicken-schnitzel.yaml', 'DEEP', true),
  ('0233-pork-schnitzel-breaded-pork-cutlets.yaml', 'DEEP', true),
  ('0304-chicken-fried-steaks.yaml', 'DEEP', true),
  ('0525-orange-flavored-chicken.yaml', 'DEEP', false),
  ('0527-karaage-japanese-fried-chicken-thighs.yaml', 'DEEP', true),
  ('1084-rhode-islandstyle-fried-calamari.yaml', 'DEEP', true),
  ('0279-crispy-salt-and-pepper-shrimp.yaml', 'DEEP', true),
  ('0536-crispy-orange-beef.yaml', 'DEEP', false),
  ('0464-steak-frites.yaml', 'DEEP', false),
  ('0255-fish-and-chips.yaml', 'DEEP', true),
  ('0114-breaded-chicken-cutlets.yaml', 'SHALLOW', true),
  (
    '0042-almond-crusted-chicken-with-wilted-spinach-salad.yaml',
    'SHALLOW',
    false,
  ),
  (
    '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
    'SHALLOW',
    false,
  ),
  ('0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml', 'SHALLOW', true),
  ('0198-crispy-pan-fried-pork-chops.yaml', 'SHALLOW', true),
  ('0415-best-chicken-parmesan.yaml', 'SHALLOW', false),
  ('0287-easy-salmon-cakes.yaml', 'SHALLOW', false),
  ('0288-maryland-crab-cakes.yaml', 'SHALLOW', false),
  ('1133-chicken-francese.yaml', 'SHALLOW', true),
  (
    '0265-poached-fish-fillets-with-crispy-artichokes-and-sherry-tomato-vinaigrette.yaml',
    'SHALLOW',
    true,
  ),
  ('0180-quick-green-bean-casserole.yaml', 'SHALLOW', false),
  ('0149-easier-fried-chicken.yaml', 'SHALLOW', false),
  ('0077-skillet-chicken-and-rice-with-peas-and-scallions.yaml', 'SAUTE', true),
  ('0414-chicken-marsala.yaml', 'SAUTE', false),
  ('0415-better-chicken-marsala.yaml', 'SAUTE', true),
  ('0418-chicken-piccata.yaml', 'SAUTE', true),
  ('0418-next-level-chicken-piccata.yaml', 'SAUTE', true),
  ('0419-parmesan-crusted-chicken-cutlets.yaml', 'SAUTE', true),
  ('0420-chicken-francese.yaml', 'SAUTE', true),
  ('0421-chicken-saltimbocca.yaml', 'SAUTE', true),
  ('0466-fish-meuniere-with-browned-butter-and-lemon.yaml', 'SAUTE', true),
  ('0257-pan-seared-salmon-steaks.yaml', 'SAUTE', true),
  ('0289-best-crab-cakes.yaml', 'SAUTE', false),
  ('0235-maple-glazed-pork-tenderloin.yaml', 'SAUTE', true),
  ('0122-chicken-kiev.yaml', 'BAKED', true),
  ('0117-nut-crusted-chicken-breasts-with-lemon-and-thyme.yaml', 'BAKED', true),
  ('0150-oven-fried-chicken.yaml', 'BAKED', true),
  ('0206-crunchy-baked-pork-chops.yaml', 'BAKED', true),
  ('0254-crunchy-oven-fried-fish.yaml', 'BAKED', true),
  ('0416-lighter-chicken-parmesan.yaml', 'BAKED', true),
  ('0407-eggplant-parmesan.yaml', 'BAKED', true),
  ('0315-oven-fried-onion-rings.yaml', 'BAKED', true),
  (
    '0041-salad-with-herbed-baked-goat-cheese-and-vinaigrette.yaml',
    'BAKED',
    false,
  ),
  ('1093-vegan-baja-style-cauliflower-tacos.yaml', 'BAKED', false),
  ('0215-horseradish-crusted-beef-tenderloin.yaml', 'BAKED', true),
  ('1185-spicy-fried-chicken-sandwiches.yaml', 'OTHER', false),
];
