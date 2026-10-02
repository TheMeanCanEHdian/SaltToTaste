// Matcher v26 (Run 056 I3, I10's O14/S15/S16/O17): RULE B — a sentence
// belongs to a line — for every frying FAT, every candidate, whole
// sentences. Real corpus recipes throughout; the 67 corpus sentences naming
// oil with a 3xx-degree temperature are read as written. Synthesized, each a
// stated exception (no corpus line or step says it — a member- or
// admin-typed recipe is what Run 056 reached): the typed steps and retyped
// lines below (O3's shortening and lard fries on 0806, O2's ¾-cup pair on
// 0491, S3's identical raws on 0806, Opus critic 2's 24-ounce oil and
// "for pan-frying" lines, O4/S4/S16/O17's oven, toaster, smoker, slow
// cooker, pizza stone and convection sentences, the temperature spellings,
// the "a" and the 8-word walk of `_oilPhraseFollows`).

// The typed sentences of a list read as one string each.
// ignore_for_file: no_adjacent_strings_in_list

import 'dart:io';

import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
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

/// [r] with [raw] added to its first ingredient group.
Recipe _added(Recipe r, String raw) => r.copyWith(
  ingredients: [
    r.ingredients.first.copyWith(
      items: [...r.ingredients.first.items, _parsed(raw)],
    ),
    ...r.ingredients.skip(1),
  ],
);

/// [r] with a step [text] appended.
Recipe _plusStep(Recipe r, String text) => r.copyWith(
  steps: [
    ...r.steps,
    r.steps.last.copyWith(text: text),
  ],
);

/// [r] with every step's [from] written [to].
Recipe _stepSays(Recipe r, String from, String to) => r.copyWith(
  steps: [
    for (final s in r.steps) s.copyWith(text: s.text.replaceAll(from, to)),
  ],
);

DiscardedMedium? _medium(Recipe r, String raw, {double? grams}) {
  final line = nutritionLines(r).firstWhere((l) => l.raw == raw);
  return discardedMediumOf(
    r,
    line,
    normalizeItem(lineItemOf(line)),
    grams: grams,
  );
}

/// Every line [raw] of [r] (identical raws included) read alone.
List<DiscardedMedium?> _mediums(Recipe r, String raw) => [
  for (final line in nutritionLines(r))
    if (line.raw == raw)
      discardedMediumOf(r, line, normalizeItem(lineItemOf(line))),
];

/// What the engine writes for [raw] matched to [food] (picked).
({double? grams, String? source, String? hold, String? note}) _out(
  Recipe r,
  String raw,
  FdcFood food,
) {
  final line = nutritionLines(r).firstWhere((l) => l.raw == raw);
  final o = engineOutcome(
    r,
    line,
    food,
    resolveGrams(
      amounts: line.amounts,
      food: food,
      normalizedItem: normalizeItem(lineItemOf(line)),
      raw: line.raw,
    ),
    picked: true,
  );
  return (
    grams: o.grams,
    source: o.source,
    hold: o.hold,
    note: holdNoteOf(r, line, o.hold),
  );
}

const _pita = '0806-pita-bread.yaml';
const _olive = '¼ cup extra-virgin olive oil';
const _tostadas = '0491-spicy-mexican-shredded-pork-tostadas.yaml';
const _bravas = '0690-patatas-bravas.yaml';
const _tempeh = '1193-crispy-tempeh-with-sambal-sauce.yaml';
const _amb = DiscardedMedium.ambiguousMedium;
const _fry = DiscardedMedium.fryingOil;

void main() {
  late FdcFood oil;
  setUpAll(() async => oil = (await FixtureProvider().food(2710180))!);

  group('RULE B (Run 056 I3): every fat, every candidate', () {
    test('O3: shortening and lard heated to a frying temperature are frying '
        "fat again (v25 read only the word \"oil\") — 0806's olive oil "
        'retyped "1 cup vegetable shortening" / "1 cup lard" with a typed '
        'fry sentence', () {
      final pita = loadCorpusRecipe(_pita);
      for (final (line, step) in [
        (
          '1 cup vegetable shortening',
          'Heat the shortening in a Dutch oven to 375 degrees.',
        ),
        ('1 cup lard', 'Heat the lard in a large skillet to 350 degrees.'),
        ('1 cup lard', 'Cook the pitas in the lard, then discard the lard.'),
      ]) {
        final r = _plusStep(_retyped(pita, _olive, line), step);
        expect(_medium(r, line), _fry, reason: step);
        expect(friesForTest(r), isTrue, reason: step);
      }
    }, skip: skipIfNoCorpus);

    test("O3: a lard pour-off keeps its written part — 0806's olive oil "
        'retyped "1 cup lard", "Heat the lard … to 350 degrees. Pour off all '
        'but 2 tablespoons lard.": the 2 tablespoons are eaten, the rest '
        'poured away', () {
      final r = _plusStep(
        _retyped(loadCorpusRecipe(_pita), _olive, '1 cup lard'),
        'Heat the lard in a Dutch oven to 350 degrees. Pour off all but 2 '
        'tablespoons lard.',
      );
      expect(_medium(r, '1 cup lard'), _fry);
      final kept = _out(r, '1 cup lard', oil);
      expect(kept.grams, closeTo(28.0, 0.1));
    }, skip: skipIfNoCorpus);

    test("O3: a shortening sentence binds by the SHORTENING's own amount — "
        '0806\'s olive oil retyped "1 cup vegetable shortening" beside an '
        'added "½ cup shortening": "Heat 1 cup of the shortening …" fries '
        'the cup alone', () {
      final r = _plusStep(
        _added(
          _retyped(
            loadCorpusRecipe(_pita),
            _olive,
            '1 cup vegetable shortening',
          ),
          '½ cup shortening',
        ),
        'Heat 1 cup of the shortening in a Dutch oven to 375 degrees.',
      );
      expect(
        [
          _medium(r, '1 cup vegetable shortening'),
          _medium(r, '½ cup shortening'),
        ],
        [_fry, null],
      );
    }, skip: skipIfNoCorpus);

    test("O2: an amount two candidates share binds NEITHER — 0491's pork oil "
        'retyped "¾ cup olive oil" beside its "¾ cup vegetable oil", the '
        'fry sentence "Heat ¾ cup oil in an 8-inch …": both held '
        '`ambiguous_medium` (v25 zeroed both), as the amount-less control '
        'is', () {
      final two = _retyped(
        loadCorpusRecipe(_tostadas),
        '2 tablespoons olive oil',
        '¾ cup olive oil',
      );
      for (final heat in [
        'Heat ¾ cup oil in an 8-inch',
        'Heat the oil in an 8-inch',
      ]) {
        final r = _stepSays(two, 'Heat the vegetable oil in an 8-inch', heat);
        expect(
          [_medium(r, '¾ cup vegetable oil'), _medium(r, '¾ cup olive oil')],
          [_amb, _amb],
          reason: heat,
        );
        final held = _out(r, '¾ cup olive oil', oil);
        expect((held.grams, held.hold), (null, 'ambiguous_medium'));
      }
    }, skip: skipIfNoCorpus);

    test('S3: identical raws are two lines — 0806 with a "¼ cup vegetable '
        'oil" added and "Heat ¼ cup oil in a Dutch oven to 375 degrees." '
        'holds both; its olive oil written twice with "Heat the olive oil '
        '…" holds both copies (v25 zeroed them)', () {
      final pita = loadCorpusRecipe(_pita);
      final shared = _plusStep(
        _added(pita, '¼ cup vegetable oil'),
        'Heat ¼ cup oil in a Dutch oven to 375 degrees.',
      );
      expect(
        [_medium(shared, _olive), _medium(shared, '¼ cup vegetable oil')],
        [_amb, _amb],
      );
      for (final heat in [
        'Heat the olive oil in a Dutch oven to 375 degrees.',
        'Heat ¼ cup oil in a Dutch oven to 375 degrees.',
      ]) {
        final twice = _plusStep(_added(pita, _olive), heat);
        expect(_mediums(twice, _olive), [_amb, _amb], reason: heat);
      }
      // One copy alone is the one candidate: it fries.
      expect(
        _medium(
          _plusStep(pita, 'Heat the olive oil in a Dutch oven to 375 degrees.'),
          _olive,
        ),
        _fry,
      );
    }, skip: skipIfNoCorpus);

    test('Opus critic 2 GAP 1: a candidate is every line the mass rule could '
        "zero — 0690's frying oil written by WEIGHT (\"24 ounces vegetable "
        'oil", 680 g) beside its sauce oil retyped "½ cup extra-virgin olive '
        'oil": the aioli is HELD (v25 zeroed it as the single candidate) and '
        'the 24 ounces stay frying oil by their mass', () {
      final r = _retyped(
        _retyped(
          loadCorpusRecipe(_bravas),
          '1 tablespoon vegetable oil',
          '½ cup extra-virgin olive oil',
        ),
        '3 cups vegetable oil',
        '24 ounces vegetable oil',
      );
      expect(_medium(r, '½ cup extra-virgin olive oil'), _amb);
      final aioli = _out(r, '½ cup extra-virgin olive oil', oil);
      expect((aioli.grams, aioli.hold), (null, 'ambiguous_medium'));
      expect(
        aioli.note,
        '"Heat oil in large Dutch oven over high heat to 375 degrees."',
      );
      expect(
        weightGramsOf(parseIngredientLine('24 ounces vegetable oil').amounts),
        closeTo(680.4, 0.1),
      );
      expect(_medium(r, '24 ounces vegetable oil', grams: 680.4), _fry);
      final frying = _out(r, '24 ounces vegetable oil', oil);
      expect((frying.grams, frying.source), (0.0, 'discarded'));
      // Under the frying mass, a weight is no candidate: 12 ounces (340 g)
      // leaves the aioli the one candidate — the v25 shape, by volume.
      final light = _retyped(r, '24 ounces vegetable oil', '12 ounces oil');
      expect(_medium(light, '½ cup extra-virgin olive oil'), _fry);
    }, skip: skipIfNoCorpus);

    test('Opus critic 2 GAP 2: a line "for pan-frying" is a candidate only '
        'with NO amount (the comment and API.md stand; a line with an '
        'amount is one by its mass) — 0491 with "Heat the oil in an 8-inch '
        '…": "2 tablespoons peanut oil, for pan-frying" leaves the ¾ cup '
        'the one candidate; "Peanut oil, for pan-frying" holds it', () {
      final r = _stepSays(
        loadCorpusRecipe(_tostadas),
        'Heat the vegetable oil in an 8-inch',
        'Heat the oil in an 8-inch',
      );
      expect(_medium(r, '¾ cup vegetable oil'), _fry);
      final small = _added(r, '2 tablespoons peanut oil, for pan-frying');
      expect(_medium(small, '¾ cup vegetable oil'), _fry);
      expect(_medium(small, '2 tablespoons peanut oil, for pan-frying'), null);
      final bare = _added(r, 'Peanut oil, for pan-frying');
      expect(_medium(bare, '¾ cup vegetable oil'), _amb);
    }, skip: skipIfNoCorpus);
  });

  group('RULE B (Run 056 I3(d)(e)): frying heat is positive evidence from '
      'the WHOLE sentence', () {
    test('the 67 corpus sentences naming oil with a 3xx-degree temperature '
        'each read as frying heat, as written', () {
      final split = RegExp(r'(?<=\.)\s+');
      final temp = RegExp(r'\b3\d\d degrees');
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
          for (final s in step.text.toLowerCase().split(split)) {
            if (temp.hasMatch(s) && fat.hasMatch(s)) {
              found.add(s);
            }
          }
        }
      }
      expect(found, hasLength(67));
      expect([
        for (final s in found)
          if (!heatsFatToFryForTest(s, 'oil')) s,
      ], isEmpty);
    }, skip: skipIfNoCorpus);

    // Each sentence brushes or tosses with the oil and names a heat that is
    // not the fat's; each term of the list is the ONLY thing between the
    // sentence and frying heat (a heating verb, "to" and a 3xx temperature
    // stand in each), so dropping it from the list fries the oil.
    const notFrying = [
      'Brush the pitas with the oil and heat them in the oven to 375 degrees.',
      'Brush the pitas with the oil and heat them to 375 degrees in the oven.',
      'Brush the pitas with the oil, heat to 375 degrees and bake.',
      'Brush the pitas with the oil, heat to 375 degrees and keep baking.',
      'Brush the pitas with the oil, heat to 375 degrees and roast.',
      'Brush the pitas with the oil and heat them under the broiler to 375 '
          'degrees.',
      'Brush the pitas with the oil and heat them on the grill to 375 '
          'degrees.',
      'Toss the pitas with the oil and heat them in the air fryer to 375 '
          'degrees.',
      'Toss the pitas with the oil and heat them in the air-fryer to 375 '
          'degrees.',
      'Rub the pitas with the oil and heat them in the smoker to 325 degrees.',
      'Brush with the oil and heat in the slow cooker to 300 degrees.',
      'Brush with the oil and heat in the slow-cooker to 300 degrees.',
      'Brush the pitas with the oil and heat them on a pizza stone to 375 '
          'degrees.',
      'Brush the pitas with the oil and heat them in the toaster to 350 '
          'degrees.',
      'Brush the pitas with the oil and heat them on the convection setting '
          'to 375 degrees.',
      'Brush the pitas with the oil and bake them; meanwhile heat the oil in '
          'a skillet to 375 degrees.',
    ];
    // O4/S4's own sentences: no heating verb or no "to" — a setting.
    const settings = [
      'Brush the pitas with the oil and cook them at 375 degrees in the oven.',
      'Toss the nuts with the oil and toast at 350 degrees until fragrant.',
      'Rub the pitas with the oil and smoke at 325 degrees.',
      'Brush the pitas with the oil and place in a preheated 350 degrees '
          'oven.',
      'Brush the pitas with the oil and cook them on a pizza stone at 375 '
          'degrees.',
      'Brush with the oil and cook in the slow cooker at 300 degrees.',
      'Brush the pitas with the oil and cook on the convection setting at '
          '375 degrees.',
      'Heat the oil and cook the pitas at 375 degrees.',
      // No heating verb: the pitas, not the fat, are cooked "to" it.
      'Brush the pitas with the oil and cook them to 375 degrees.',
    ];
    test("O4/S4/S16/O17: an oven's, a grill's, an air fryer's, a smoker's, a "
        "slow cooker's, a pizza stone's, a toaster's or a convection heat "
        'ANYWHERE in the sentence, or a temperature "at" (a setting), is not '
        "the oil's — 0806's ¼ cup olive oil stays counted and the recipe "
        'fries nothing', () {
      final pita = loadCorpusRecipe(_pita);
      for (final s in [...notFrying, ...settings]) {
        final r = _plusStep(pita, s);
        expect(_medium(r, _olive), isNull, reason: s);
        expect(friesForTest(r), isFalse, reason: s);
      }
    }, skip: skipIfNoCorpus);

    test('frying heat in every temperature spelling (Opus critic 2): '
        '"350 degrees", "350 degrees F", "350 degrees Fahrenheit", "350°F", '
        '"350 °F", "350°", "350F" and a Celsius frying range 160–200 °C — and '
        'in every fry vessel (Dutch oven, skillet, pot, saucepan, wok, '
        'fryer); 300–399 °F only', () {
      for (final t in [
        '350 degrees',
        '325 degrees',
        '350 degrees F',
        '350 degrees Fahrenheit',
        '350°F',
        '350 °F',
        '350°',
        '350F',
        '160°C',
        '180 °C',
        '190 degrees C',
        '200 degrees Celsius',
        '175C',
      ]) {
        expect(
          heatsFatToFryForTest('Heat the oil in a Dutch oven to $t.', 'oil'),
          isTrue,
          reason: t,
        );
      }
      for (final t in [
        '400 degrees',
        '299 degrees',
        '150°C',
        '210 °C',
        '350 for 10 minutes',
        '180 cups',
        '3500 degrees',
        '1350 degrees',
        '1180°C',
      ]) {
        expect(
          heatsFatToFryForTest('Heat the oil in a Dutch oven to $t.', 'oil'),
          isFalse,
          reason: t,
        );
      }
      // Each fat by its own noun (O3).
      expect(
        heatsFatToFryForTest('Maintain a lard temperature of 350 °F.', 'lard'),
        isTrue,
      );
      expect(
        heatsFatToFryForTest('Heat the shortening to 375 degrees.', 'oil'),
        isFalse,
      );
      // "oil temperature" leads no number: a digit before 3xx is no 3xx.
      expect(
        heatsFatToFryForTest('Keep an oil temperature of 1350 degrees.', 'oil'),
        isFalse,
      );
      for (final vessel in [
        'a Dutch oven',
        'a large skillet',
        'a large pot',
        'a saucepan',
        'a wok',
        'a deep fryer',
      ]) {
        expect(
          heatsFatToFryForTest('Heat the oil in $vessel to 375°F.', 'oil'),
          isTrue,
          reason: vessel,
        );
      }
      // The leads: "until it registers", "reaches", a paren, "about".
      for (final s in [
        'Heat the oil until it registers 375 degrees.',
        'When the oil reaches 375°F, add the chicken.',
        'Heat the oil until shimmering (350 degrees).',
        'Heat the oil to about 350 degrees.',
        'Maintain an oil temperature of 325 °F.',
      ]) {
        expect(heatsFatToFryForTest(s, 'oil'), isTrue, reason: s);
      }
      // Each sentence's ONLY heat verb or lead word (the v26 verifier's D3:
      // dropping warm*, brought, registers, around or approximately left
      // every test green).
      for (final s in [
        'Warm the oil to 350 degrees.',
        'The oil, brought to 350 degrees, is ready.',
        'Fry when the oil registers 350 degrees.',
        'Heat the oil to around 350 degrees.',
        'Heat the oil to approximately 350 degrees.',
      ]) {
        expect(heatsFatToFryForTest(s, 'oil'), isTrue, reason: s);
      }
      // A decimal point before the digits is no boundary: "1.350" is no 350.
      expect(
        heatsFatToFryForTest(
          'Keep the oil temperature at 1.350 degrees.',
          'oil',
        ),
        isFalse,
      );
    });

    test('a spelling fries the recipe too: 0806 with its olive oil heated '
        '"to 180°C"', () {
      final r = _plusStep(
        loadCorpusRecipe(_pita),
        'Heat the oil in a Dutch oven to 180°C.',
      );
      expect((_medium(r, _olive), friesForTest(r)), (_fry, true));
    }, skip: skipIfNoCorpus);
  });

  group("RULE B (Run 056 O14/S15): _oilPhraseFollows' words, each "
      'discriminating — two ≥ ¼-cup oils, so only the binding decides', () {
    // 1193 Crispy Tempeh's water retyped "¼ cup toasted sesame oil" (O14,
    // S15): a sentence BOUND to the 1 cup fries it alone (its "pour off
    // all but 2 tablespoons oil" then joins it) and the sesame oil counts;
    // UNBOUND, both are held.
    Recipe tempeh(String heat, {String water = '¼ cup toasted sesame oil'}) =>
        _stepSays(
          _retyped(loadCorpusRecipe(_tempeh), '½ cup water', water),
          'Heat oil in',
          heat,
        );
    const veg = '1 cup vegetable oil';

    test('"Heat 1 cup of the oil" (the corpus\'s own "of the": "Heat ⅓ cup of '
        'the oil", 0198) binds the cup — "of" and "the" are allowed', () {
      final r = tempeh('Heat 1 cup of the oil in');
      expect(
        [_medium(r, veg), _medium(r, '¼ cup toasted sesame oil')],
        [_fry, null],
      );
    }, skip: skipIfNoCorpus);

    test('"Heat 1 cup vegetable oil" beside a "¼ cup vegetable oil" (O14): a '
        'kind word both lines share binds by itself to neither, but is '
        'allowed between the amount and "oil" — the cup is bound', () {
      final r = tempeh(
        'Heat 1 cup vegetable oil in',
        water: '¼ cup vegetable oil',
      );
      expect(
        [_medium(r, veg), _medium(r, '¼ cup vegetable oil')],
        [_fry, null],
      );
    }, skip: skipIfNoCorpus);

    test('"Heat 1 cup of a vegetable oil" (typed: no corpus sentence has "a" '
        'there) binds the cup — "a" is allowed', () {
      // Beside a "¼ cup vegetable oil" — "vegetable" binds neither by
      // itself, so only the walk past "a" binds the cup.
      final r = tempeh(
        'Heat 1 cup of a vegetable oil in',
        water: '¼ cup vegetable oil',
      );
      expect(
        [_medium(r, veg), _medium(r, '¼ cup vegetable oil')],
        [_fry, null],
      );
    }, skip: skipIfNoCorpus);

    test('the walk reads eight words: "oil" as the eighth binds, as the '
        'ninth does not (typed, hostile)', () {
      final eighth = tempeh('Heat 1 cup of the of the of the of oil in');
      expect(_medium(eighth, veg), _fry);
      expect(_medium(eighth, '¼ cup toasted sesame oil'), isNull);
      final ninth = tempeh('Heat 1 cup of the of the of the of the oil in');
      expect(
        [_medium(ninth, veg), _medium(ninth, '¼ cup toasted sesame oil')],
        [_amb, _amb],
      );
    }, skip: skipIfNoCorpus);

    test('another food\'s word between binds nothing: "Heat 1 cup butter '
        'and the oil" holds both', () {
      final r = tempeh('Heat 1 cup butter and the oil in');
      expect(
        [_medium(r, veg), _medium(r, '¼ cup toasted sesame oil')],
        [_amb, _amb],
      );
    }, skip: skipIfNoCorpus);
  });

  group('I7 (Run 056 O11/S12/O10): what the amount measures', () {
    double? grams(String raw, FdcFood? food) {
      final p = parseIngredientLine(raw);
      return resolveGrams(
        amounts: p.amounts,
        food: food,
        normalizedItem: normalizeItem(p.item ?? raw),
        raw: raw,
      )?.grams;
    }

    test("O11/S12: a plus part's form is read after its comma too — "
        '"¼ cup grated Parmesan cheese plus 2 cups, shredded" (the corpus\'s '
        'own spelling, 0419\'s "plus 6 ounces, shredded"; typed with a '
        'volume: a stated exception) weighs its 2 cups shredded, 0.36 g/mL, '
        'as the comma-free line does (v25: the grated 0.24, 127.6 g)', () {
      for (final raw in const [
        '¼ cup grated Parmesan cheese plus 2 cups, shredded',
        '¼ cup grated Parmesan cheese plus 2 cups shredded',
      ]) {
        expect(grams(raw, null), closeTo(184.28, 0.01), reason: raw);
      }
      expect(
        plusPartOf('¼ cup grated Parmesan cheese plus 2 cups, shredded')!.form,
        '2 cups, shredded',
      );
    });

    test('O10: a paren of ONE word qualifies the measured head, a paren — '
        'or a comma part — of more words is a note on the line: on 2708216 '
        'Popcorn, NFS ("1 cup, popped" 14 g; "1 cup, unpopped, yields" 193 '
        'g) "8 cups popped popcorn (unpopped kernels discarded)" is 8 popped '
        'cups, 112 g (v25: 1,544 g); "(unpopped)" and ", unpopped" still '
        'measure kernels (typed: no corpus popcorn line has a paren or a '
        'comma — a stated exception)', () async {
      final popcorn = (await FixtureProvider().food(2708216))!;
      for (final (raw, g) in const [
        ('8 cups popped popcorn (unpopped kernels discarded)', 112.0),
        ('8 cups popped popcorn (old maids and kernels removed)', 112.0),
        ('8 cups popped popcorn, unpopped kernels discarded', 112.0),
        ('8 cups popped popcorn, old maids and kernels removed', 112.0),
        ('½ cup popcorn (unpopped)', 96.5),
        ('½ cup popcorn (kernels)', 96.5),
        ('½ cup popcorn, unpopped', 96.5),
      ]) {
        expect(grams(raw, popcorn), closeTo(g, 0.01), reason: raw);
      }
    });
  });
}
