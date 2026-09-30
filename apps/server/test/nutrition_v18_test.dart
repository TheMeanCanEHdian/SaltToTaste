// Real corpus lines are kept verbatim, one literal per entry; steps wrap
// across adjacent literals.
// ignore_for_file: lines_longer_than_80_chars, no_adjacent_strings_in_list

import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Matcher v18: checkpoint 9's density guard (a density key matches as a
/// word, 'ice cream' 0.558, compounds that are not the key's food on their
/// record's own portion) and the non-pairing half of Run 049 (flake and
/// coarse sea salt as the line's own food, the weighed line's readers, a
/// held medium's hold and typed grams). Real corpus lines (recipe named on
/// each; D0 proves each exists); FDC answers recorded from sweep snapshot
/// 13. A guard no corpus line exercises is pinned on a synthesized input,
/// said so where it is.
void main() {
  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v18');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    db.upsertSource(slug: 'src', name: 'Test', type: 'book');
    return db;
  }

  Recipe recipeOf(
    SaltDatabase db,
    List<String> raws, {
    String id = 'r',
    List<String> steps = const [],
    List<Subsection> subsections = const [],
  }) {
    final recipe = Recipe(
      id: id,
      title: id,
      slug: id,
      source: const RecipeSource(name: 'Test', type: 'book'),
      ingredients: [
        IngredientGroup(items: [for (final raw in raws) lineOf(raw)]),
      ],
      steps: [
        for (final (i, text) in steps.indexed)
          RecipeStep(number: i + 1, text: text),
      ],
      subsections: subsections,
    );
    db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h$id$raws');
    return recipe;
  }

  Subsection subsectionOf(String title, List<String> raws) => Subsection(
    title: title,
    kind: 'variation',
    ingredients: [
      IngredientGroup(items: [for (final raw in raws) lineOf(raw)]),
    ],
  );

  IngredientMatchRow rowAt(SaltDatabase db, {String id = 'r'}) =>
      db.ingredientMatchesFor(id).single;

  Future<GramResolution?> gramsOn(String raw, int? fdcId) async => lineGrams(
    tempDb(),
    lineOf(raw),
    fdcId == null ? null : await FixtureProvider().food(fdcId),
  );

  // (corpus file, line, its record in snapshot 13, grams, source): every
  // row the density guard moved in the cache-only replay of snapshot 13 —
  // 28 counted (checkpoint 9's 27 and 1174's salted peanuts) and 3 in
  // `check` — at the grams the record's own portion gives ('ice cream'
  // 0.558 is 168809's "cup (4 fl oz)" 66 g a half cup). v19 (Run 050):
  // the peanuts on 173806's own 'cup' 146 g, not 'nuts' 0.55 (1174's
  // 174262 has no volume portion: 'nuts' still), and the malted milk
  // powder on no portion of 174867's made-up drink (no grams).
  const moved = <(String, String, int, double?, String?)>[
    (
      '0368-baked-manicotti.yaml',
      '3 cups part-skim ricotta cheese',
      171248,
      741.00,
      'portion',
    ),
    (
      '0372-four-cheese-lasagna.yaml',
      '1½ cups part-skim ricotta cheese',
      171248,
      370.50,
      'portion',
    ),
    (
      '0374-lasagna-with-hearty-tomato-meat-sauce.yaml',
      '1¾ cups whole-milk or part-skim ricotta cheese',
      171248,
      432.25,
      'portion',
    ),
    (
      '0959-bananas-foster.yaml',
      '1 pint vanilla ice cream, divided among four bowls',
      167575,
      264.03,
      'density',
    ),
    (
      '0820-chocolate-chip-cookie-ice-cream-sandwiches.yaml',
      '3 pints ice cream',
      168809,
      792.10,
      'density',
    ),
    (
      '0905-chocolate-volcano-cakes-with-espresso-ice-cream.yaml',
      '2 pints coffee ice cream, softened',
      168809,
      528.06,
      'density',
    ),
    (
      '1199-profiteroles.yaml',
      '1 quart vanilla or coffee ice cream',
      167575,
      528.06,
      'density',
    ),
    (
      '0868-carrot-layer-cake.yaml',
      '⅓ cup buttermilk powder',
      171274,
      40.00,
      'portion',
    ),
    (
      '0750-easy-buttermilk-waffles.yaml',
      '½ cup dried buttermilk powder',
      171274,
      60.00,
      'portion',
    ),
    (
      '1150-deluxe-blueberry-pancakes.yaml',
      '3 tablespoons malted milk powder',
      174867,
      null,
      null,
    ),
    (
      '0626-grilled-glazed-boneless-skinless-chicken-breasts.yaml',
      '2 teaspoons nonfat dry milk powder',
      172195,
      5.00,
      'portion',
    ),
    (
      '1114-sweet-cream-ice-cream.yaml',
      '½ cup plus ⅓ cup nonfat dry milk powder',
      172195,
      100.00,
      'portion',
    ),
    (
      '1164-sweet-cream-ice-cream.yaml',
      '½ cup plus ⅓ cup nonfat dry milk powder',
      172195,
      100.00,
      'portion',
    ),
    (
      '0836-glazed-butter-cookies.yaml',
      '2 tablespoons cream cheese, at room temperature',
      173418,
      29.00,
      'portion',
    ),
    (
      '0836-glazed-butter-cookies.yaml',
      '1 tablespoon cream cheese, at room temperature',
      173418,
      14.50,
      'portion',
    ),
    (
      '0766-quick-cinnamon-buns-with-buttermilk-icing.yaml',
      '2 tablespoons cream cheese, softened',
      173418,
      29.00,
      'portion',
    ),
    (
      '0061-italian-pasta-salad.yaml',
      '½ cup oil-packed sun-dried tomatoes, sliced thin',
      169384,
      55.00,
      'portion',
    ),
    (
      '0069-skillet-chicken-broccoli-and-ziti.yaml',
      '¼ cup oil-packed sun-dried tomatoes, rinsed and chopped coarse',
      169384,
      27.50,
      'portion',
    ),
    (
      '0508-shu-mai-steamed-chinese-dumplings.yaml',
      '¼ cup chopped water chestnuts',
      170066,
      31.00,
      'portion',
    ),
    (
      '0513-sung-choy-bao-chicken-lettuce-wraps.yaml',
      '½ cup water chestnuts, cut into ¼-inch pieces',
      170066,
      62.00,
      'portion',
    ),
    (
      '1179-chicken-and-spiced-freekeh-with-cilantro-and-preserved-lemon.yaml',
      '½ cup shelled unsalted pistachios, toasted and chopped',
      170185,
      61.50,
      'portion',
    ),
    (
      '0809-multigrain-bread.yaml',
      '¾ cup unsalted pumpkin seeds or sunflower seeds',
      170154,
      100.50,
      'portion',
    ),
    (
      '0545-kung-pao-shrimp.yaml',
      '½ cup unsalted roasted peanuts',
      173806,
      73.00,
      'portion',
    ),
    (
      '0553-pad-thai.yaml',
      '½ cup unsalted roasted peanuts, chopped coarse',
      173806,
      73.00,
      'portion',
    ),
    (
      '0551-panang-beef-curry.yaml',
      '⅓ cup unsalted dry-roasted peanuts, chopped fine',
      173806,
      48.67,
      'portion',
    ),
    (
      '0552-stir-fried-thai-style-beef-with-chiles-and-shallots.yaml',
      '⅓ cup unsalted roasted peanuts, chopped coarse',
      173806,
      48.67,
      'portion',
    ),
    (
      '0554-shrimp-pad-thai.yaml',
      '¼ cup roasted unsalted peanuts, chopped coarse',
      173806,
      36.50,
      'portion',
    ),
    (
      '1174-lao-hu-cai-tiger-salad.yaml',
      '2 tablespoons chopped salted dry-roasted peanuts',
      174262,
      16.27,
      'density',
    ),
    // In `check`: the radish and the pepitas on their records' portions;
    // 'water' no longer sizes watermelon, and 2747675 has no portion.
    (
      '0553-pad-thai.yaml',
      '2 tablespoons chopped Thai salted preserved radish (optional)',
      170122,
      18.38,
      'portion',
    ),
    (
      '1071-watermelon-salad-with-cotija-and-serrano-chiles.yaml',
      '5 tablespoons chopped roasted, salted pepitas, divided',
      323294,
      42.19,
      'portion',
    ),
    (
      '1071-watermelon-salad-with-cotija-and-serrano-chiles.yaml',
      '6 cups 1½-inch seedless watermelon pieces',
      2747675,
      null,
      null,
    ),
  ];

  // Density lines the guard must NOT move (their snapshot-13 grams).
  const kept = <(String, String, int, double)>[
    // 'nuts' is still the tail of a nut's name.
    (
      '0040-arugula-salad-with-figs-prosciutto-walnuts-and-parmesan.yaml',
      '½ cup walnuts, toasted and chopped',
      2346394,
      65.06,
    ),
    // "unsalted" is "without salt": 'butter' still sizes it.
    (
      '0015-carrot-ginger-soup.yaml',
      '2 tablespoons unsalted butter',
      173430,
      28.36,
    ),
  ];

  group('D: the density guard (checkpoint 9)', () {
    test('D0: every pinned line is its corpus line — the same raw, item and '
        'amounts the corpus file stores', () {
      for (final (file, raw) in [
        for (final (file, raw, _, _, _) in moved) (file, raw),
        for (final (file, raw, _, _) in kept) (file, raw),
      ]) {
        final stored = [
          for (final g in loadCorpusRecipe(file).ingredients) ...g.items,
        ].firstWhere((l) => l.raw == raw, orElse: () => fail('$file: $raw'));
        final line = lineOf(raw);
        expect(stored.item, line.item, reason: raw);
        expect(stored.amounts, line.amounts, reason: raw);
      }
    }, skip: skipIfNoCorpus);

    test("D1: each line the guard moved weighs on its record's own portion "
        "(or 'ice cream' 0.558, 'nuts' 0.55)", () async {
      for (final (_, raw, fdcId, grams, source) in moved) {
        final g = await gramsOn(raw, fdcId);
        expect(
          g?.grams,
          grams == null ? isNull : closeTo(grams, 0.005),
          reason: raw,
        );
        expect(g?.source.name, source, reason: raw);
      }
    });

    test('D2: the density lines it must not move keep their grams', () async {
      for (final (_, raw, fdcId, grams) in kept) {
        final g = await gramsOn(raw, fdcId);
        expect(g?.grams, closeTo(grams, 0.005), reason: raw);
        expect(g?.source, GramSource.density, reason: raw);
      }
    });

    test("D3: a record's whipped portion sizes only a whipped line — "
        '173418 "tbsp" 14.5 g, never the median with "tbsp, whipped" 10 g '
        '(synthesized whipped line, a stated exception)', () async {
      expect(
        (await gramsOn('2 tablespoons cream cheese, softened', 173418))?.grams,
        closeTo(29.0, 0.005),
      );
      expect(
        (await gramsOn('2 tablespoons whipped cream cheese', 173418))?.grams,
        closeTo(20.0, 0.005),
      );
    });
  });

  group('G: grams (Run 049)', () {
    test('G1: flake or coarse sea salt weighs like kosher only as the '
        "line's OWN food — never the butter, oil or sugar a plus part, an "
        '"and" tail or a substitute paren sprinkles it on (synthesized '
        'lines, a stated exception: no corpus line has one)', () async {
      for (final (raw, fdcId, grams) in <(String, int, double)>[
        (
          '3 tablespoons unsalted butter, melted, plus flaky sea salt for sprinkling',
          173430,
          42.54,
        ),
        (
          '2 tablespoons canola oil, plus coarse sea salt for serving',
          172336,
          27.21,
        ),
        ('½ cup packed brown sugar, plus flaky sea salt', 168833, 110.01),
        (
          '2 tablespoons unsalted butter, softened, and coarse sea salt',
          173430,
          28.36,
        ),
        ('1 teaspoon table salt (or 2 teaspoons flaky sea salt)', 173468, 6.01),
        // The corpus's own: Run 047's 0227 and 0805, still kosher's 0.72.
        ('2 tablespoons flake sea salt', 173468, 21.29),
        ('2 teaspoons coarse sea salt, divided', 173468, 7.10),
      ]) {
        expect(
          (await gramsOn(raw, fdcId))?.grams,
          closeTo(grams, 0.01),
          reason: raw,
        );
      }
    });

    test(
      'G2: the plus part of a coarse sea salt line is kosher too — '
      '14.20 g, never 10.65 + 6.01 (synthesized, a stated exception)',
      () async {
        expect(
          (await gramsOn(
            '1 tablespoon plus 1 teaspoon coarse sea salt',
            173468,
          ))?.grams,
          closeTo(14.20, 0.01),
        );
      },
    );

    test("G2: so is a held medium's eaten plus part — Classic Macaroni and "
        "Cheese's (0300) steps, its salt line spelled coarse sea salt "
        '(synthesized, a stated exception): the eaten teaspoon is 3.55 g, '
        "never table salt's 6.01", () async {
      final db = tempDb();
      final r = recipeOf(
        db,
        ['1 tablespoon plus 1 teaspoon coarse sea salt'],
        steps: [
          'Adjust an oven rack to the lower-middle position and heat the '
              'broiler. Bring 4 quarts water to a rolling boil in a large pot. '
              'Add 1 tablespoon of the salt and the macaroni and stir to '
              'separate the noodles. Cook until tender, drain, and set aside.',
          'In the now-empty pot, melt the butter over medium-high heat. Add '
              'the flour, mustard, cayenne (if using), and remaining 1 '
              'teaspoon salt and whisk well to combine.',
        ],
      );
      await matchAndCompute(db, FixtureProvider(), r);
      final row = rowAt(db);
      expect((row.hold, row.gramSource), ('discarded_medium', 'discarded'));
      expect(row.grams, closeTo(3.55, 0.01));
    });

    test('G3: the spellings of a flake or coarse sea salt weigh like kosher '
        '(synthesized, a stated exception)', () async {
      for (final (raw, grams) in <(String, double)>[
        ('1 teaspoon flaky Maldon sea salt', 3.55),
        ('1 teaspoon Maldon flake sea salt', 3.55),
        ('1 teaspoon Maldon sea salt flakes', 3.55),
        ('1 tablespoon sea salt flakes', 10.65),
        ('1 teaspoon flaked sea salt', 3.55),
        ('1 teaspoon coarse-grind sea salt', 3.55),
        // A paren before the salt is no food of its own.
        ('1 teaspoon (optional) flaky sea salt', 3.55),
        // Plain and fine sea salt stay table salt's (Run 048).
        ('1 teaspoon sea salt', 6.01),
        ('1 teaspoon fine sea salt', 6.01),
      ]) {
        expect(
          (await gramsOn(raw, 173468))?.grams,
          closeTo(grams, 0.01),
          reason: raw,
        );
      }
    });

    test('G4: an adjectival volume paren the parse KEPT as a volume amount '
        "is one item's volume, as the one it drops; a trailing total stays "
        'the total (synthesized lines, a stated exception)', () async {
      expect(
        parseIngredientLine(
          '2 (about 1 cup) ripe pears, sliced',
        ).amounts.map((a) => a.measure),
        containsAll([Measure.count, Measure.volume]),
      );
      expect(
        (await gramsOn('2 (about 1 cup) ripe pears, sliced', 167778))?.grams,
        closeTo(279.90, 0.01), // 473 mL, the paren's whole millilitres
      );
      expect(
        (await gramsOn('2 ripe pears, sliced (about 1 cup)', 167778))?.grams,
        closeTo(140, 0.01),
      );
    });

    test('G5: an amount-less "each" paren weighs nothing (synthesized, a '
        'stated exception)', () async {
      expect(
        await gramsOn('Swiss chard leaves, torn (about 1 cup each)', 169991),
        isNull,
      );
    });
  });

  group("H: a held medium's hold and a person's typed grams (Run 049)", () {
    test('H1: a second amount edit that makes the line no medium clears '
        'the hold an earlier edit stored; a bare re-confirm keeps its '
        'grams (synthesized amount edits of a kosher salt line, a stated '
        'exception)', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      var r = recipeOf(db, ['½ cup kosher salt']);
      await matchAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 0, {'confirmed': true});
      r = recipeOf(db, ['⅓ cup kosher salt']);
      await matchAndCompute(db, provider, r);
      expect(rowAt(db).hold, 'discarded_medium');
      r = recipeOf(db, ['1 tablespoon kosher salt']);
      await matchAndCompute(db, provider, r);
      var row = rowAt(db);
      expect((row.status, row.hold), ('confirmed', null));
      expect(row.grams, closeTo(10.65, 0.01));
      await applyMatchOverride(db, provider, r, 0, {'confirmed': true});
      row = rowAt(db);
      expect((row.gramSource, row.hold), ('density', null));
      expect(row.grams, closeTo(10.65, 0.01));
    });

    test("H2: a held medium's typed grams (0052's salt, 2 g) come back "
        "from a skip as the person's counted row, and the next compute "
        'keeps them', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      // Sesame-Lemon Cucumber Salad (0052): its salt line and first step.
      final r = recipeOf(
        db,
        ['1 tablespoon table salt'],
        steps: [
          'Toss the cucumbers with the salt in a colander set over a large '
              'bowl. Weight the cucumbers with a gallon-sized zipper-lock bag '
              'filled with water; drain for 1 to 3 hours. Rinse and pat dry.',
        ],
      );
      await matchAndCompute(db, provider, r);
      expect(rowAt(db).hold, 'discarded_medium');
      await applyMatchOverride(db, provider, r, 0, {
        'confirmed': true,
        'grams': 2,
      });
      final typed = db.nutritionFor('r')!.totalGrams;
      await applyMatchOverride(db, provider, r, 0, {'skipped': true});
      await applyMatchOverride(db, provider, r, 0, {'skipped': false});
      await matchAndCompute(db, provider, r);
      final row = rowAt(db);
      expect(
        (row.status, row.grams, row.gramSource, row.hold),
        ('overridden', 2, 'override', null),
      );
      expect(db.nutritionFor('r')!.totalGrams, typed);
    });
  });

  group("W: the weighed line's readers (Run 049; synthesized sub-recipe "
      'plus lines, a stated exception — the corpus has one, 0711)', () {
    // A same-food plus line (namesSecondFood is false, so a decision on its
    // key reaches it) whose eaten part is a held salt bath; and Run 048
    // P9's own input, which names a second food.
    Recipe saltOf(SaltDatabase db, {String id = 'r', bool seasoned = false}) =>
        recipeOf(
          db,
          [
            if (seasoned)
              '1 recipe Seasoned Salt, plus ¼ cup kosher salt (recipe follows)'
            else
              '1 recipe Kosher Salt (recipe follows), plus ¼ cup kosher salt',
          ],
          id: id,
          subsections: [
            subsectionOf(seasoned ? 'Seasoned Salt' : 'Kosher Salt', [
              '2 tablespoons kosher salt',
            ]),
          ],
        );

    test('W1: the approximation label reads the weighed line — "1 recipe '
        'Pesto Base, plus 2 ounces pancetta" on the bacon record says it '
        'as the plain pancetta line does', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = recipeOf(
        db,
        [
          '1 recipe Pesto Base, plus 2 ounces pancetta, chopped fine (recipe follows)',
        ],
        subsections: [
          subsectionOf('Pesto Base', ['4 ounces pancetta, chopped fine']),
        ],
      );
      await matchAndCompute(db, provider, r);
      final row = rowAt(db);
      expect(row.fdcId, 168277);
      expect(
        gramBasisFor(db, nutritionLines(r).single, row, recipe: r),
        contains('approximation (counted as Pork, cured, bacon'),
      );
    });

    test('W2: an unmatched row whose EATEN part is a held salt bath is not '
        'reached by a decision on its key', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      await matchAndCompute(db, provider, saltOf(db, id: 'a'));
      await matchAndCompute(db, provider, saltOf(db, id: 'b'));
      // Recipe b's row as FDC-found-nothing leaves it (a stated exception).
      db.upsertIngredientMatch(
        rowAt(db, id: 'b').copyWith(
          clearGrams: true,
          clearGramSource: true,
          status: 'unmatched',
          description: 'No FoodData Central match',
          confidence: 0,
          clearHold: true,
        ),
      );
      final key = rowAt(db, id: 'b').itemKey!;
      expect(
        decisionReach(
          db,
          key,
          excluding: (recipeId: 'a', position: 0),
          fdcId: 173468,
        ),
        isEmpty,
      );
    });

    test('W3: the matches GET reads the weighed line — its held flag (no '
        'portion filled from the poured-away bath) and its search key (the '
        'eaten plural reads the singular answer)', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = saltOf(db, seasoned: true);
      await matchAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 0, {'fdc_id': 173468});
      var item =
          ((await matchesBody(db, provider, r))['items']! as List).single
              as Map;
      final portions = item['portions']! as List;
      expect(portions, isNotEmpty);
      expect([
        for (final p in portions) (p as Map)['fill'],
      ], everyElement(isNull));

      final onion = recipeOf(db, ['1 onion, chopped fine'], id: 'a');
      await matchAndCompute(db, provider, onion);
      final crispy = recipeOf(
        db,
        ['1 recipe Crispy Onions, plus 1 cup reserved onions (recipe follows)'],
        id: 'c',
        subsections: [
          subsectionOf('Crispy Onions', [
            '2 pounds onions, halved and sliced crosswise into ¼-inch-thick pieces',
            '2 teaspoons salt',
            '1½ cups vegetable oil',
          ]),
        ],
      );
      await matchAndCompute(db, provider, crispy);
      item =
          ((await matchesBody(db, provider, crispy))['items']! as List).single
              as Map;
      expect(item['candidates_query'], 'onion');
    });

    test('W4: an un-skip weighs the held check on the EATEN part — a row an '
        "older matcher stored at the whole line's density comes back as the "
        'compute writes it, never at 72 g (the stored row is a stated '
        'exception)', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = saltOf(db);
      await matchAndCompute(db, provider, r);
      db.upsertIngredientMatch(
        rowAt(db).copyWith(
          fdcId: 173468,
          description: 'Salt, table',
          confidence: 0.9,
          grams: 72,
          gramSource: 'density',
          status: 'skipped',
          clearHold: true,
        ),
      );
      await applyMatchOverride(db, provider, r, 0, {'skipped': false});
      // Its eaten part weighs nothing on a held bath: the line's 0 g
      // sub-recipe row, as the compute writes it — never the stored 72 g.
      final row = rowAt(db);
      expect(
        (row.status, row.fdcId, row.grams, row.gramSource, row.hold),
        ('confirmed', null, 0, 'unmeasured', null),
      );
    });

    test('W4: apply_to_all weighs its outcome on the EATEN part — the other '
        "recipe's same line lands as the compute writes it, never counted at "
        "the bath's grams "
        '(its unheld row on another food is a stated exception)', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final a = saltOf(db, id: 'a');
      await matchAndCompute(db, provider, a);
      await matchAndCompute(db, provider, saltOf(db, id: 'b'));
      db.upsertIngredientMatch(
        rowAt(db, id: 'b').copyWith(
          fdcId: 172336,
          description: 'Oil, canola',
          confidence: 0.9,
          grams: 42.6,
          gramSource: 'density',
          status: 'auto',
          clearHold: true,
        ),
      );
      final receipt = await applyMatchOverride(db, provider, a, 0, {
        'fdc_id': 173468,
        'apply_to_all': true,
      });
      expect(receipt?.lines, 1);
      // The held bath's eaten part weighs nothing: the 0 g sub-recipe
      // row, as the compute writes it — never 42.6 g of the bath counted.
      final row = rowAt(db, id: 'b');
      expect(
        (row.fdcId, row.grams, row.gramSource, row.hold),
        (null, 0, 'unmeasured', null),
      );
    });
  });

  test("W5: a person's typed grams on the second-food rule's own record "
      'survive a skip and an un-skip — Classic Guacamole (0471): the rule '
      'never re-derives the row it counts on', () async {
    final db = tempDb();
    final provider = FixtureProvider();
    final r = recipeOf(db, [
      '¼ teaspoon grated lime zest plus 1½–2 tablespoons juice',
    ]);
    await matchAndCompute(db, provider, r);
    expect(rowAt(db).gramSource, isNot('override'));
    await applyMatchOverride(db, provider, r, 0, {
      'confirmed': true,
      'grams': 40,
    });
    await applyMatchOverride(db, provider, r, 0, {'skipped': true});
    await applyMatchOverride(db, provider, r, 0, {'skipped': false});
    final row = rowAt(db);
    expect((row.fdcId, row.grams, row.gramSource), (168156, 40, 'override'));
  });

  test('B: "dry milk" without "powder" is dry milk too — "½ cup nonfat dry '
      'milk" on 172195 weighs its record\'s cup (120 g), never "milk" at '
      '1.03 g/mL (122 g)', () async {
    // Synthesized line (stated exception): every corpus dry-milk line says
    // "powder", which "milk powder" already catches; another library's
    // "nonfat dry milk" needs the "dry milk" term on its own.
    final db = tempDb();
    final dryMilk = (await FixtureProvider().food(172195))!;
    final got = lineGrams(db, lineOf('½ cup nonfat dry milk'), dryMilk);
    expect(got?.grams, closeTo(60, 0.001));
    expect(got?.source, GramSource.portion);
  });
}
