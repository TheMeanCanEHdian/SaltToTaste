// Matcher v28 (Run 058 I3): RULE B — a scope boundary is a CLAUSE MARK,
// never the evidence's own word; the heat reading linear per clause; the
// vessel compounds never exclude; the fry range judged on the library; the
// medium densities and every both-family threshold pinned at its boundary.
// Real corpus recipes throughout (0656, 0424, 0380, 0148, 0116, 0690, 0672,
// 0511) and the library's own frying sentences. Synthesized, each a stated
// exception (no corpus step or line says it — typed through the editor/API,
// an admin's or an import's path): every typed sentence below (Run 058
// O2/S4's appliance sentences, S7's and S31's vessels, S5/S9's hostile
// many-temperature sentences, S23's verb forms), and every retyped line
// (S6's weight-written crumbs and starch, S20's boundary amounts,
// "oil-packed sun-dried tomato oil", the plus parts and "for … frying" labels).

// The typed sentences of a list read as one string each.
// ignore_for_file: no_adjacent_strings_in_list

import 'dart:io';

import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

IngredientLine _parsed(String raw) => IngredientLine(
  raw: raw,
  item: parseIngredientLine(raw).item,
  amounts: parseIngredientLine(raw).amounts,
);

/// [r] with the line [raw] retyped [to], parsed as the editor does.
Recipe _retyped(Recipe r, String raw, String to) => r.copyWith(
  ingredients: [
    for (final g in r.ingredients)
      g.copyWith(
        items: [
          for (final l in g.items) l.raw != raw ? l : _parsed(to),
        ],
      ),
  ],
);

/// [r] with every step's [from] written [to].
Recipe _stepSays(Recipe r, String from, String to) => r.copyWith(
  steps: [
    for (final s in r.steps) s.copyWith(text: s.text.replaceAll(from, to)),
  ],
);

DiscardedMedium? _medium(Recipe r, String raw, {bool bySentence = true}) {
  final line = nutritionLines(r).firstWhere((l) => l.raw == raw);
  return discardedMediumOf(
    r,
    line,
    normalizeItem(lineItemOf(line)),
    bySentence: bySentence,
  );
}

bool _heat(String s, [String fat = 'oil']) => heatsFatToFryForTest(s, fat);

const _fry = DiscardedMedium.fryingOil;
const _amb = DiscardedMedium.ambiguousMedium;
const _coating = DiscardedMedium.coating;
const _bravas = '0690-patatas-bravas.yaml';
const _schnitzel = '0116-chicken-schnitzel.yaml';

void main() {
  group('I3(a) (Run 058 O2/S4): the clause starts at a clause MARK, never a '
      'heat verb — an appliance governs a temperature its own verb heats', () {
    test('every sentence O2 and S4 list reads FALSE (v27 read each true: the '
        'heat verb cut the appliance out of its clause)', () {
      for (final s in [
        // O2.
        'Clean and oil cooking grate, then heat grill until lid thermometer '
            'registers 350 degrees.',
        'Brush the pitas with the oil and bake them in an oven heated to 375 '
            'degrees.',
        'Brush the dough with oil and bake until the oven thermometer '
            'registers 375 degrees.',
        'Brush the pork with the oil and cook in the smoker, holding it at '
            '300 degrees.',
        'Brush the pitas with the oil and heat them on the grill to 375 '
            'degrees.',
        'Brush the pitas with the oil and heat them on the grill, keeping the '
            'temperature at 350 degrees.',
        // S4.
        'Toss the vegetables with the oil and roast in an oven heated to '
            '200°C.',
        'Toss the potatoes with the oil and roast in an oven heated to 200C.',
        'Rub the chicken with the oil and place it in an oven heated to 350 '
            'degrees.',
        'Brush with the oil and cook on a grill heated to 350°F.',
        'Rub the oil on the pizza stone and heat it at 350 degrees.',
        'Brush with the oil and bake in an oven that has been heated to 350F.',
        'Brush with the oil and bake in the oven (heated to 350F).',
        'Toss the vegetables with the oil and roast in a 200°C oven.',
      ]) {
        expect(_heat(s), isFalse, reason: s);
      }
    });

    test("0611 Rosticciana's eaten rosemary oil (¼ cup) with O2's typed grill "
        'sentence: no frying medium (v27 zeroed ~54 g of eaten oil)', () {
      const olive = '¼ cup extra-virgin olive oil';
      final r = loadCorpusRecipe(
        '0611-rosticciana-tuscan-grilled-pork-ribs.yaml',
      );
      final typed = _stepSays(
        r,
        'Clean and oil cooking grate.',
        'Clean and oil cooking grate, then heat grill until lid thermometer '
            'registers 350 degrees.',
      );
      expect(typed.steps.map((s) => s.text).join(), contains('registers 350'));
      expect((_medium(r, olive), _medium(typed, olive)), (null, null));
    }, skip: skipIfNoCorpus);

    test('a mark followed by a heat verb PARTICIPLE (-ing, -ed, held, kept, '
        'brought) opens no clause; one followed by any other word — the '
        'imperative included — does', () {
      for (final p in [
        'heating it',
        'heated',
        'reheated',
        'warmed',
        'brought',
        'held',
        'kept',
        'holding it',
        'keeping it',
        'maintaining it',
      ]) {
        for (final mark in [',', ', ', ',  ', ';', ' (', ' —']) {
          final s =
              'Brush the pork with the oil and cook it in the smoker$mark$p '
              'at 300 degrees.';
          expect(_heat(s), isFalse, reason: s);
        }
      }
      for (final w in [
        'heat the oil',
        'bring the oil',
        'keep the oil',
        'hold the oil',
        'return the oil',
        'then heat the oil',
        'meanwhile heat the oil',
      ]) {
        for (final mark in [',', ';', ' (', ' —']) {
          final s = 'Set the pork in the smoker$mark$w to 300 degrees.';
          expect(_heat(s), isTrue, reason: s);
        }
      }
      // The participle phrase of the fat itself stays the fat's.
      expect(_heat('The oil, heated to 350 degrees, is ready.'), isTrue);
    });

    test('the clause marks still cut (; , — ( )), each the only one, and a '
        'heat verb no longer does: "Set the pitas in the oven and heat the '
        'oil" is the oven\'s clause (v27 read it the oil\'s)', () {
      for (final cut in ['; ', ', ', ' — ', ' (', ') ']) {
        final s =
            'Set the pitas beside the oven${cut}heat the oil to 375 degrees.';
        expect(_heat(s), isTrue, reason: s);
      }
      for (final s in [
        'Set the pitas in the oven and heat the oil to 375 degrees.',
        'Set the pitas in the oven then heat the oil to 375 degrees.',
        'Grill the pitas and fry them in the oil at 375 degrees.',
        // A method verb before the heat verb in one clause governs (v26 read
        // the same; no corpus sentence with a fat says it).
        'Bake the croutons and heat the oil to 350 degrees.',
      ]) {
        expect(_heat(s), isFalse, reason: s);
      }
    });

    test('ONE locator, answered per temperature with forward pointers: each '
        'governing kind before, at and after a clause start, two '
        'temperatures each in its own clause', () {
      for (final s in [
        // The governed temperature first, then the fat's own.
        'Bake the pitas with the oil at 375 degrees; heat the oil to 350 '
            'degrees.',
        'Roast the pitas in the oil at 375 degrees; heat the oil to 350 '
            'degrees.',
        'Brush the pitas with the oil, baked at 375 degrees; heat the oil to '
            '350 degrees.',
        'Brush the pitas with the oil in the oven at 375 degrees; heat the '
            'oil to 350 degrees.',
        // The fat's own first.
        'Heat the oil to 350 degrees; bake the pitas at 375 degrees.',
        // A method verb in an earlier clause, its lead in this one.
        'Brush the pitas with the oil and bake; heat the oil at 350 degrees.',
        // A method verb's lead must follow it AND precede the temperature:
        // "in" before "baking", "in" after the 350, lead neither.
        'Heat the oil in the pot for baking until it reads 350 degrees.',
        'Heat the oil for baking until it reads 350 degrees in the pot.',
        // A lead is a whole word: "meat" ends in no "at".
        'Heat the oil for baking the meat until it reads 350 degrees.',
        // A method verb after the temperature leads a later one.
        'Heat the oil to 350 degrees while the pitas bake at 375 degrees.',
      ]) {
        expect(_heat(s), isTrue, reason: s);
      }
      for (final s in [
        'Heat the oil beside the oven, bake at 375 degrees, roast at 350 '
            'degrees.',
        'Brush the pitas with the oil, bake them to 375 degrees, then roast '
            'to 350 degrees.',
        'Brush the pitas with the oil and bake them with the oil at 375 '
            'degrees.',
        'Brush the pitas with the oil and heat them, roasted in 375 degrees.',
      ]) {
        expect(_heat(s), isFalse, reason: s);
      }
    });
  });

  group('I3(d) (Run 058 S7, S31(b)): a vessel never excludes; an appliance '
      'excludes the temperature it governs', () {
    const vessels = [
      'oven-safe skillet',
      'oven safe skillet',
      'oven-proof skillet',
      'oven proof skillet',
      'ovenproof skillet',
      'ovensafe skillet',
      'Dutch oven',
      'Dutch-oven',
      'French oven',
      'French-oven',
      'roasting pan',
      'baking pan',
      'baking sheet',
      'baking dish',
      'broiling pan',
      'broiler pan',
      'broiler pans',
      'broiler-safe skillet',
      'broiler-proof skillet',
      'grill pan',
      'grill-safe skillet',
      'stovetop grill pan',
      'sheet pan',
      'pizza pan',
    ];
    test('"heat the oil in a <vessel> to 350 degrees" and "to 350 degrees in '
        'a <vessel>" read TRUE for every vessel', () {
      for (final v in vessels) {
        for (final s in [
          'Heat the oil in a $v to 350 degrees.',
          'Heat the oil to 350 degrees in a $v.',
        ]) {
          expect(_heat(s), isTrue, reason: s);
        }
      }
    });

    test('every appliance read FALSE before and after the temperature', () {
      for (final a in [
        'oven',
        'broiler',
        'grill',
        'air fryer',
        'smoker',
        'slow cooker',
        'pizza stone',
        'toaster',
        'convection oven',
        'oven safely',
        'grill proofing',
      ]) {
        for (final s in [
          'Brush the pitas with the oil and heat them in the $a to 350 '
              'degrees.',
          'Brush the pitas with the oil and heat them to 350 degrees in the '
              '$a.',
        ]) {
          expect(_heat(s), isFalse, reason: s);
        }
      }
    });
  });

  group('I3(c) (Run 058 O3): the fry range stays 300–399 °F, judged on the '
      "library's six sentences naming a fat with 400–450 °F", () {
    test(
      'the six sentences, as written: 0202/0272 heat the oven first (no '
      "fat's heat in any range); 0511's and 0672's 400-degree fries read "
      "false — 300–450 would read three of them true and hold 0672's "
      'eaten "¼ cup coconut oil" (its buffalo sauce) as ambiguous_medium',
      () {
        final split = RegExp(r'(?<=\.)\s+');
        final hot = RegExp(r'\b4[0-5]\d degrees');
        final fat = RegExp(r'\b(?:oil|shortening|lard)\b');
        final found = <String>[];
        final files =
            Directory(corpusRecipesDir)
                .listSync()
                .map((f) => f.uri.pathSegments.last)
                .where((n) => n.endsWith('.yaml'))
                .toList()
              ..sort();
        for (final f in files) {
          for (final step in loadCorpusRecipe(f).steps) {
            for (final s in step.text.split(split)) {
              if (hot.hasMatch(s) && fat.hasMatch(s.toLowerCase())) {
                found.add('${f.substring(0, 4)} $s');
              }
            }
          }
        }
        expect(found, hasLength(6));
        expect(found.map((s) => s.substring(0, 4)).toSet(), {
          '0202',
          '0272',
          '0511',
          '0672',
        });
        for (final s in found) {
          for (final f in ['oil', 'shortening', 'lard']) {
            expect(_heat(s.substring(5), f), isFalse, reason: s);
          }
        }
        // The row 300–450 would move: counted today.
        final buffalo = loadCorpusRecipe('0672-buffalo-cauliflower-bites.yaml');
        expect(_medium(buffalo, '¼ cup coconut oil'), isNull);
        expect(_medium(buffalo, '1–2 quarts peanut or vegetable oil'), _fry);
        // The same fry at 375 is frying heat.
        expect(
          _heat(
            'Add oil to large Dutch oven until it measures about 1½ inches '
            'deep and heat over medium-high heat to 375 degrees.',
          ),
          isTrue,
        );
      },
      skip: skipIfNoCorpus,
    );

    test('each end of both scales', () {
      for (final (t, want) in [
        ('299 degrees', false),
        ('300 degrees', true),
        ('399 degrees', true),
        ('400 degrees', false),
        ('450 degrees', false),
        ('159°C', false),
        ('160°C', true),
        ('200°C', true),
        ('201°C', false),
        ('230°C', false),
      ]) {
        expect(_heat('Heat the oil in a Dutch oven to $t.'), want, reason: t);
      }
    });
  });

  group('I3(b) (Run 058 S5/S9): the heat reading is LINEAR per clause — the '
      'governing words located once per sentence, each temperature answered '
      'by a forward pointer', () {
    String fill(String head, String unit, int n) {
      final b = StringBuffer(head);
      while (b.length + unit.length < n) {
        b.write(unit);
      }
      return '$b.';
    }

    test('S5\'s "cook the oil shortening lard to 350F …" and S9\'s "Oil to '
        '350 degrees …" / "to 350° …" (~1,000 characters, up to 124 '
        'temperatures): heatClauseChars ≤ 2 × the sentence per check, one '
        'heatChecks per fat', () {
      for (final (s, fats) in [
        (
          fill('cook the oil shortening lard', ' to 350F', 990),
          [
            'oil',
            'shortening',
            'lard',
          ],
        ),
        (fill('Oil', ' to 350 degrees', 1000), ['oil']),
        (fill('Oil', ' to 350°', 1000), ['oil']),
        (fill('Heat the oil', ', bake at 350°', 1000), ['oil']),
        (fill('Heat the oil', ' in the oven at 350°', 1000), ['oil']),
      ]) {
        expect(RegExp('350').allMatches(s).length, greaterThan(40));
        for (final fat in fats) {
          stepIndexCounts.clear();
          _heat(s, fat);
          expect(stepIndexCounts['heatChecks'], 1, reason: s);
          expect(
            stepIndexCounts['heatClauseChars'],
            inInclusiveRange(s.length, 2 * s.length),
            reason: '$fat: $s',
          );
        }
      }
    });
  });

  group('I3(e) (Run 058 S6): the medium densities — every corpus dredge, '
      'brine and frying-fat head sized, read only where no food is', () {
    test("each figure is a recorded FDC record's cup (grams ÷ 236.588 mL), "
        "within the table's rounding", () async {
      for (final (item, id) in [
        ('vegetable shortening', 173584),
        ('lard', 171401),
        ('plain dried bread crumbs', 174928),
        ('cornstarch', 169698),
        // Any other starch reads cornstarch's (no starch record cached).
        ('tapioca starch', 169698),
        ('potato starch', 169698),
      ]) {
        final food = (await FixtureProvider().food(id))!;
        final cup = food.portions.firstWhere((p) => p.description == 'cup');
        expect(
          densityOf(item),
          closeTo(cup.gramWeight / 236.588, 0.01),
          reason: '$item on $id ${food.description}',
        );
      }
      // The longest key wins in its table: panko keeps its own figure.
      expect(densityOf('panko bread crumbs'), 0.25);
      expect(densityOf('breadcrumbs'), densityOf('bread crumbs'));
      expect(densityOf('lard or extra-virgin olive oil'), 0.92);
    });

    test("a line's grams keep its record's own portion (the food-free "
        'figures never weigh a line: in the table they moved 10 corpus '
        'rows off their USDA portion)', () async {
      for (final (raw, id) in [
        (
          '½ cup vegetable shortening, cut into ½-inch pieces and chilled',
          173584,
        ),
        ('6 tablespoons lard, softened', 171401),
        ('⅓ cup plain dried bread crumbs', 174928),
      ]) {
        final line = _parsed(raw);
        final g = resolveGrams(
          amounts: line.amounts,
          food: await FixtureProvider().food(id),
          normalizedItem: normalizeItem(lineItemOf(line)),
          raw: raw,
        )!;
        expect(g.source, GramSource.portion, reason: raw);
      }
    });

    test(
      "every dredge head of the library has a density: 0116 Schnitzel's "
      'crumbs written by weight (27 g = ¼ cup at 0.45) and a starch (32 g '
      '= ¼ cup at 0.54) dredge like their volume; one gram under does not',
      () {
        final base = loadCorpusRecipe(_schnitzel);
        const crumbs = '2 cups plain dried bread crumbs';
        for (final (raw, step, want) in [
          (crumbs, null, _coating),
          ('8 ounces plain dried bread crumbs', null, _coating),
          ('27 grams plain dried bread crumbs', null, _coating),
          ('26 grams plain dried bread crumbs', null, null),
          ('4 ounces potato starch', 'potato starch', _coating),
          ('4 ounces tapioca starch', 'tapioca starch', _coating),
          ('32 grams tapioca starch', 'tapioca starch', _coating),
          ('31 grams tapioca starch', 'tapioca starch', null),
        ]) {
          var r = _retyped(base, crumbs, raw);
          if (step != null) {
            r = _stepSays(r, 'bread crumbs', step);
          }
          expect(_medium(r, raw), want, reason: raw);
        }
      },
      skip: skipIfNoCorpus,
    );
  });

  group('I3(f) (Run 058 S20): every both-family threshold at its boundary, '
      'in BOTH families', () {
    // Each case: the corpus recipe, its line, then (retyped, want) at the
    // boundary and one step under, by volume then by weight.
    for (final (name, file, from, cases) in [
      (
        "the salt bath's ¼ cup (0656 Grilled Cauliflower; ¼ cup table salt "
            '= 72.2 g at 1.22)',
        '0656-grilled-cauliflower.yaml',
        '¼ cup salt',
        [
          ('¼ cup salt', DiscardedMedium.saltBath),
          ('3 tablespoons salt', null),
          ('73 grams salt', DiscardedMedium.saltBath),
          ('72 grams salt', null),
        ],
      ),
      (
        "the brine sugar's ¼ cup (0424 Pork Chops with Vinegar Peppers; "
            '50.3 g at 0.85)',
        '0424-pork-chops-with-vinegar-and-sweet-peppers.yaml',
        '1 cup sugar',
        [
          ('¼ cup sugar', DiscardedMedium.brineSugar),
          ('3 tablespoons sugar', null),
          ('51 grams sugar', DiscardedMedium.brineSugar),
          ('50 grams sugar', null),
        ],
      ),
      (
        "the cheese milk's 4 cups (0380 Homemade Ricotta; 974.7 g at 1.03)",
        '0380-homemade-ricotta-cheese.yaml',
        '1 gallon pasteurized (not ultrapasteurized or UHT) whole milk',
        [
          ('1 quart whole milk', DiscardedMedium.cheeseMilk),
          ('4 cups whole milk', DiscardedMedium.cheeseMilk),
          ('3¾ cups whole milk', null),
          ('975 grams whole milk', DiscardedMedium.cheeseMilk),
          ('974 grams whole milk', null),
          // 946.1 mL: under four cups (946.35 mL), past v27's 946.
          ('974.5 grams whole milk', null),
        ],
      ),
      (
        "the buttermilk soak's 4 cups (0148 Crispy Fried Chicken)",
        '0148-crispy-fried-chicken.yaml',
        '7 cups buttermilk',
        [
          ('4 cups buttermilk', DiscardedMedium.soak),
          ('3¾ cups buttermilk', DiscardedMedium.brine),
          ('975 grams buttermilk', DiscardedMedium.soak),
          ('974 grams buttermilk', DiscardedMedium.brine),
          ('974.5 grams buttermilk', DiscardedMedium.brine),
        ],
      ),
    ]) {
      test(name, () {
        final r = loadCorpusRecipe(file);
        for (final (raw, want) in cases) {
          expect(_medium(_retyped(r, from, raw), raw), want, reason: raw);
        }
      }, skip: skipIfNoCorpus);
    }

    test("the mass rule's 400 g at each fat's density: shortening and lard "
        "at 0.87 (1⅞ cups = 386 g, kept; 2 cups = 412 g, zeroed — at oil's "
        '0.92 1⅞ cups was 408 g), oil at 0.92; a fat item the table refuses '
        "at oil's (the `fat:` fallback: 1 pound of the tomatoes' oil)", () {
      final r = loadCorpusRecipe(_bravas);
      for (final (raw, want) in [
        ('1⅞ cups vegetable shortening', null),
        ('2 cups vegetable shortening', _fry),
        ('1⅞ cups lard', null),
        ('2 cups lard', _fry),
        ('1⅞ cups vegetable oil', _fry),
        ('1¾ cups vegetable oil', null),
        ('1 pound oil-packed sun-dried tomato oil', _fry),
        ('14 ounces oil-packed sun-dried tomato oil', null),
      ]) {
        final typed = _retyped(r, '3 cups vegetable oil', raw);
        expect(_medium(typed, raw, bySentence: false), want, reason: raw);
      }
      expect(
        densityOf(
          normalizeItem(
            lineItemOf(
              _parsed('1 pound oil-packed sun-dried tomato oil'),
            ),
          ),
        ),
        isNull,
      );
    }, skip: skipIfNoCorpus);

    test("candidacy's ¼ cup reads a same-food plus part in both families: "
        "beside 0690's aioli, \"2 tablespoons plus 8 ounces vegetable oil\" "
        'is a candidate (the sentence held for both), a plus part with no '
        'quantity is none', () {
      const aioli = '½ cup extra-virgin olive oil';
      final base = _retyped(
        loadCorpusRecipe(_bravas),
        '1 tablespoon vegetable oil',
        aioli,
      );
      for (final (raw, want) in [
        ('2 tablespoons plus 8 ounces vegetable oil', (_amb, _amb)),
        ('2 tablespoons plus ¼ cup vegetable oil', (_amb, _amb)),
        // 29.6 mL + 28 g ÷ 0.92 = 60.0 mL; + 27 g = 58.9 mL.
        ('2 tablespoons plus 28 grams vegetable oil', (_amb, _amb)),
        ('2 tablespoons plus 27 grams vegetable oil', (null, _fry)),
        ('2 tablespoons plus 1 bottle vegetable oil', (null, _fry)),
        // Another food's part is never the oil's.
        ('2 tablespoons vegetable oil plus ¼ cup butter', (null, _fry)),
      ]) {
        final r = _retyped(base, '3 cups vegetable oil', raw);
        expect((_medium(r, raw), _medium(r, aioli)), want, reason: raw);
      }
    }, skip: skipIfNoCorpus);

    test('every "for … frying" label form makes a small line a candidate, '
        'in any case', () {
      const aioli = '½ cup extra-virgin olive oil';
      final base = _retyped(
        loadCorpusRecipe(_bravas),
        '1 tablespoon vegetable oil',
        aioli,
      );
      for (final (label, want) in [
        ('for pan-frying', (_amb, _amb)),
        ('For Pan-Frying', (_amb, _amb)),
        ('for shallow-frying', (_amb, _amb)),
        ('FOR SHALLOW-FRYING', (_amb, _amb)),
        ('for frying', (_fry, _amb)),
        ('for deep frying', (_fry, _amb)),
        ('for deep-frying', (_fry, _amb)),
        ('for deepfrying', (_fry, _amb)),
        ('for sautéing', (null, _fry)),
      ]) {
        final raw = '3 tablespoons vegetable oil, $label';
        final r = _retyped(base, '3 cups vegetable oil', raw);
        expect((_medium(r, raw), _medium(r, aioli)), want, reason: raw);
      }
    }, skip: skipIfNoCorpus);
  });

  group("I3 S23 (Run 058): the heat reading's arms, each the only thing "
      'between a sentence and its answer', () {
    test('every reheat form and the bare register/reach is a heat verb, '
        "each the sentence's only one", () {
      for (final s in [
        'The oil reheats to 350 degrees.',
        'Once the oil is reheated to 350 degrees, add the fish.',
        'Reheating the oil to 350 degrees takes 5 minutes.',
        'Let the oil reach 350 degrees.',
        'The oil should register 350 degrees.',
      ]) {
        expect(_heat(s), isTrue, reason: s);
      }
      // Not a heat verb: no lead's verb phrase heats.
      expect(_heat('Let the oil sit at 350 degrees.'), isFalse);
    });

    test('word boundaries: a lead, a method word and an appliance are whole '
        'words', () {
      for (final s in [
        // "oven" or "grill" inside a word is none.
        'Heat the oil beside the ovenware to 350 degrees.',
        'Heat the oil beside the grillwork to 350 degrees.',
      ]) {
        expect(_heat(s), isTrue, reason: s);
      }
      for (final s in [
        // A lead ending a longer word leads nothing ("that", "into").
        'Heat the oil, stir in salt that 350 degrees.',
        'Heat the oil into 350 degrees.',
        // "baking" then "in" leads (v27 read the same: S23's sentence).
        'Fry the baking potatoes in oil at 350 degrees.',
      ]) {
        expect(_heat(s), isFalse, reason: s);
      }
    });
  });
}
