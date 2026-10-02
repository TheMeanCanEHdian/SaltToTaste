// Matcher v27 (Run 057 I2/I3/I5): RULE B — the exclusion is scoped and
// bounded, the evidence list is open and pinned on typed POSITIVES; one
// candidacy reading shared with the mass rule, every medium threshold in both
// unit families; the popcorn qualifier read by vocabulary. Real corpus
// recipes throughout (0149, 0000, 0690, 0148, 0806). Synthesized, each a
// stated exception (no corpus step or line says it — Run 057 typed them
// through the editor/API, an admin's or an import's path): every typed
// sentence below (S2/O4/O5/O10/S10/S13 and each term's own sentence), the
// retyped lines (S3/O6's bottle and "for frying" lines, Sonnet critic 1's
// weight-written oil, flour and salt), and the popcorn lines (S6/O8/O13).

// The typed sentences of a list read as one string each.
// ignore_for_file: no_adjacent_strings_in_list

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

/// [r] with every step's [from] written [to].
Recipe _stepSays(Recipe r, String from, String to) => r.copyWith(
  steps: [
    for (final s in r.steps) s.copyWith(text: s.text.replaceAll(from, to)),
  ],
);

/// [r] with a step [text] appended.
Recipe _plusStep(Recipe r, String text) => r.copyWith(
  steps: [
    ...r.steps,
    r.steps.last.copyWith(text: text),
  ],
);

DiscardedMedium? _medium(Recipe r, String raw) {
  final line = nutritionLines(r).firstWhere((l) => l.raw == raw);
  return discardedMediumOf(
    r,
    line,
    normalizeItem(lineItemOf(line)),
  );
}

bool _heat(String s, [String fat = 'oil']) => heatsFatToFryForTest(s, fat);

const _fry = DiscardedMedium.fryingOil;
const _amb = DiscardedMedium.ambiguousMedium;
const _coating = DiscardedMedium.coating;
const _easier = '0149-easier-fried-chicken.yaml';
const _easierOil = '1¾ cups vegetable oil';
const _easierFlour = '2 cups unbleached all-purpose flour';
const _easierStep = 'medium-high heat to 375 degrees';
const _mashed = '0000-garlic-and-olive-oil-mashed-potatoes.yaml';
const _mashedOlive = '½ cup plus 2 tablespoons extra-virgin olive oil';
const _bravas = '0690-patatas-bravas.yaml';
const _pita = '0806-pita-bread.yaml';
const _olive = '¼ cup extra-virgin olive oil';

void main() {
  group('I2 (Run 057 S2/O4/O5/O10/S10/S13): frying heat — the exclusion '
      'scoped to the clause it governs, the leads and spellings open', () {
    // Run 057's own typed positives, every one: v26 read each false.
    const positives = [
      // S2.
      'Heat the oil in a Dutch oven to 350 degrees and fry the potatoes.',
      'Heat the oil in a Dutch oven to 350 degrees, fry the potatoes, then '
          'drain on a baking sheet.',
      'Whisk the flour, baking powder and salt, then heat the oil in a Dutch '
          'oven to 375 degrees and fry the potatoes.',
      'Heat the oil in a Dutch oven to 350 degrees and fry the potatoes; '
          'keep warm in a 200 degree oven.',
      'Heat the oil to between 350 and 375 degrees and fry the potatoes.',
      'Heat the oil in a Dutch oven until a deep-fry thermometer reads 350 '
          'degrees and fry the potatoes.',
      'Fry the potatoes in oil at 350 degrees.',
      'Maintain the temperature of the oil at 350 degrees.',
      'Heat the oil in a Dutch oven to 350 degrees; meanwhile heat the oven '
          'to 200 degrees for holding.',
      'Heat the oil until it is 350 degrees.',
      'Maintain the oil at 350 degrees.',
      'Heat the oil to a temperature of 350 degrees.',
      'Heat the oil to roughly 350 degrees.',
      'Heat the oil to approx. 350 degrees.',
      // O4.
      'Line a rimmed baking sheet with paper towels and heat the oil in an '
          '11-inch straight-sided sauté pan over medium-high heat to 375 '
          'degrees.',
      'While the chicken rests in the baking soda rub, heat the oil in an '
          '11-inch straight-sided sauté pan over medium-high heat to 375 '
          'degrees.',
      'Heat the oil (roasted peanut works well) in an 11-inch straight-sided '
          'sauté pan to 375 degrees.',
      'Heat 1 cup oil in a skillet to 350 degrees and line a baking sheet '
          'with paper towels.',
      // O5.
      'Heat the oil over medium-high heat to 350–375 degrees.',
      'Heat the oil over medium-high heat to 350-375 degrees.',
      'Heat the oil over medium-high heat to between 350 and 375 degrees.',
      'Heat the oil until it reads 375 degrees.',
      'Heat the oil to a temperature of 375 degrees.',
      // O10 / S10.
      'The oil, heated to 350 degrees, is ready.',
      'When the oil reached 375 degrees, add the chicken.',
      'Heat the oil in a Dutch oven to 180° C.',
      'Heat the oil in a Dutch oven to 350° F.',
      'Heat the oil to 395 degrees.',
      'Fry when the oil reached 385 degrees.',
      // S13.
      'Heat the oil to 350ºF.',
      'Heat the oil to 350˚F.',
      'Heat the oil to 350 deg F.',
      'Heat the oil to 350 fahrenheit.',
      // v26's typed negative, judged a fry under the scoped rule: the bake
      // is outside the 375's clause (the ";").
      'Brush the pitas with the oil and bake them; meanwhile heat the oil in '
          'a skillet to 375 degrees.',
    ];
    test('every typed positive Run 057 lists is frying heat', () {
      for (final s in positives) {
        expect(_heat(s), isTrue, reason: s);
      }
    });

    // O10/S10's orders and their typed negatives.
    const negatives = [
      'Heat the skillet to 350 degrees and add the oil.',
      'Add the oil to 375°F and heat it.',
      'Toss the pitas with the oil and heat them in the airfryer to 375 '
          'degrees.',
      'Cook the pitas at 375 degrees; adjust the oil temperature as needed.',
      'Heat the skillet to 375 degrees, then add the oil.',
      'Heat the oil, then cook the pitas at 375 degrees.',
      'Heat the oil and cook the pitas at 375 degrees.',
      // A temperature no lead introduces is not the fat's heat.
      'Heat the oil gently; a 375 degree reading means it is too hot.',
    ];
    test('the orders: the fat, the "oil temperature" and a heat verb come '
        'BEFORE the temperature, the verb in its own verb phrase', () {
      for (final s in negatives) {
        expect(_heat(s), isFalse, reason: s);
      }
    });

    test("every lead, each the sentence's only one before its digits", () {
      for (final s in [
        'Heat the oil to 350 degrees.',
        'Heat the oil until 350 degrees.',
        'Heat the oil until it registers 350 degrees.',
        'Heat the oil until the thermometer registered 350 degrees.',
        'Heat the oil until it reaches 350 degrees.',
        'Heat the oil until it reached 350 degrees.',
        'Heat the oil until the thermometer reads 350 degrees.',
        'Heat the oil until the thermometer should read 350 degrees.',
        'Heat the oil until it is 350 degrees.',
        'Fry the potatoes in the oil at 350 degrees.',
        'Heat the oil to a temperature of 350 degrees.',
        'Heat the oil until shimmering (350 degrees).',
        'Heat the oil to between 350 and 375 degrees.',
        'Heat the oil to between about 350 and 375 degrees.',
        'Heat the oil to between 350° and 375°.',
        'Heat the oil to 350–375 degrees.',
        'Heat the oil to 350-375 degrees.',
        'Heat the oil from 350°–375°F.',
        'Heat the oil from 350 to 375 degrees.',
        'Heat the oil to about 350 degrees.',
        'Heat the oil to around 350 degrees.',
        'Heat the oil to approximately 350 degrees.',
        'Heat the oil to approx. 350 degrees.',
        'Heat the oil to roughly 350 degrees.',
      ]) {
        expect(_heat(s), isTrue, reason: s);
      }
    });

    test("every heat verb in every form, each the sentence's only one", () {
      for (final s in [
        'Heat the oil to 350 degrees.',
        'The cook heats the oil to 350 degrees.',
        'The oil, heated to 350 degrees, is ready.',
        'While heating the oil to 350 degrees, dredge the fish.',
        'Reheat the oil to 350 degrees.',
        'Bring the oil to 350 degrees.',
        'The cook brings the oil to 350 degrees.',
        'After bringing the oil to 350 degrees, add the fish.',
        'The oil, brought to 350 degrees, is ready.',
        'Warm the oil to 350 degrees.',
        'The cook warms the oil to 350 degrees.',
        'The oil, warmed to 350 degrees, is ready.',
        'While warming the oil to 350 degrees, dredge the fish.',
        'Return the oil to 350 degrees.',
        'The cook returns the oil to 350 degrees.',
        'The oil, returned to 350 degrees, is ready.',
        'After returning the oil to 350 degrees, add the fish.',
        'Let the oil reach a temperature of 350 degrees.',
        'Once the oil reaches a temperature of 350 degrees, add the fish.',
        'Once the oil reached a temperature of 350 degrees, add the fish.',
        'The oil, on reaching a temperature of 350 degrees, is ready.',
        'The oil should register a temperature of 350 degrees.',
        'Once the oil registers a temperature of 350 degrees, add the fish.',
        'Once the oil registered a temperature of 350 degrees, add the fish.',
        'The thermometer, registering the oil at 350 degrees, is in.',
        'The thermometer should read the oil at 350 degrees.',
        'Once the thermometer reads the oil at 350 degrees, add the fish.',
        'The thermometer, reading the oil at 350 degrees, is in.',
        'Maintain the oil at 350 degrees.',
        'The cook maintains the oil at 350 degrees.',
        'The oil, maintained at 350 degrees, is ready.',
        'While maintaining the oil at 350 degrees, fry the fish.',
        'Keep the oil at 350 degrees.',
        'The cook keeps the oil at 350 degrees.',
        'While keeping the oil at 350 degrees, add the fish.',
        'The oil, kept at 350 degrees, is ready.',
        'Hold the oil at 350 degrees.',
        'The cook holds the oil at 350 degrees.',
        'While holding the oil at 350 degrees, add the fish.',
        'The oil, held at 350 degrees, is ready.',
        'Fry the fish in the oil at 350 degrees.',
        'The cook fries the fish in the oil at 350 degrees.',
        'The fish, fried in the oil at 350 degrees, is ready.',
        'While frying the fish in the oil at 350 degrees, make the sauce.',
        'Deep-fry the fish in the oil at 350 degrees.',
        'Pan-fry the fish in the oil at 350 degrees.',
      ]) {
        expect(_heat(s), isTrue, reason: s);
      }
      // An air fry, an oven-fry and a stir-fry fry nothing in a fat.
      for (final s in [
        'Air fry the pitas with the oil at 375 degrees.',
        'Air-fry the pitas with the oil at 375 degrees.',
        'Oven-fry the potatoes with the oil at 375 degrees.',
        'Stir-fry the vegetables in the oil at 375 degrees.',
        'Stir fry the vegetables in the oil at 375 degrees.',
        // No heat verb at all: a setting.
        'Toss the nuts with the oil and toast at 350 degrees.',
      ]) {
        expect(_heat(s), isFalse, reason: s);
      }
    });

    test('every spelling: the degree sign typed °, º or ˚ (a space before '
        'its letter or not), "deg", "deg.", "degree(s)", "F", "Fahrenheit", '
        'and the Celsius 160–200 as "C" or "Celsius"', () {
      for (final t in [
        '350 degrees', '350 degree', '350 deg', '350 deg.', '350 deg. F',
        '350 deg F', '350 Fahrenheit', '350 degrees Fahrenheit', '350°F',
        '350° F', '350 °F', '350°', '350F', '350 F', '350ºF', '350˚F',
        '350º', '350˚ F', '300 degrees', '399 degrees', //
        '180°C', '180° C', '180 °C', '180 degrees C', '180 degrees Celsius',
        '180 deg C', '180 deg. C', '180 Celsius', '180C', '180 C', '180ºC',
        '180˚ C', '160 degrees C', '200 degrees C', '199 C',
      ]) {
        expect(_heat('Heat the oil in a Dutch oven to $t.'), isTrue, reason: t);
      }
      for (final t in [
        '400 degrees',
        '299 degrees',
        '159 degrees C',
        '201 degrees C',
        '180 degrees',
        '350 for 10 minutes',
        '180 cups',
        '3500 degrees',
        '1350 degrees',
        '1180°C',
        '350 dregs',
        '180 calories',
      ]) {
        expect(
          _heat('Heat the oil in a Dutch oven to $t.'),
          isFalse,
          reason: t,
        );
      }
    });

    test('an appliance excludes only a temperature in its own clause (; , — '
        '( ) or a heat verb cut it): each cut, and each appliance', () {
      for (final s in [
        'Heat the oil beside the oven; at 350 degrees, add the fish.',
        'Heat the oil beside the oven, to 350 degrees.',
        'Heat the oil beside the oven — to 350 degrees.',
        'Heat the oil beside the oven (350 degrees).',
        'Heat the oil (not the oven) to 350 degrees.',
        'Set the pitas in the oven and heat the oil to 375 degrees.',
        'Heat the oil in an oven-safe skillet to 350 degrees.',
        'Heat the oil in a Dutch oven to 350 degrees.',
        // An appliance AFTER the temperature governs only the words right
        // after it (below), not the rest of its clause.
        'Heat the oil to 375 degrees while the oven preheats.',
        // A method verb leading a LATER temperature, not this one.
        'Heat the oil to 375 degrees while the pitas bake in the oven.',
      ]) {
        expect(_heat(s), isTrue, reason: s);
      }
      for (final appliance in [
        'the oven',
        'the broiler',
        'the grill',
        'the air fryer',
        'the air-fryer',
        'the airfryer',
        'the smoker',
        'the slow cooker',
        'the slow-cooker',
        'a pizza stone',
        'the toaster',
        'the convection setting',
      ]) {
        final s =
            'Brush the pitas with the oil and heat them on $appliance '
            'to 375 degrees.';
        expect(_heat(s), isFalse, reason: s);
      }
    });

    test('a method verb governs only the temperature it leads (at, to, in) '
        '— never an adjective ("roasted peppers") or "baking '
        'sheet/powder/soda/dish/pan"', () {
      for (final m in [
        'bake at',
        'bakes at',
        'baking at',
        'bake to',
        'bake in the pan at',
        'roast at',
        'roasts at',
        'roasting at',
        'broil at',
        'broils at',
        'broiling at',
        'baked at',
        'roasted at',
        'broiled at',
        'grilled at',
        'baked in the pan at',
        'roasted to',
        'bake in the pan until',
      ]) {
        final s = 'Brush the pitas with the oil, heat them, $m 375 degrees.';
        expect(_heat(s), isFalse, reason: s);
      }
      for (final s in [
        'Heat the oil with the roasted peppers to 375 degrees.',
        'Heat the oil beside the baking sheet to 375 degrees.',
        'Heat the oil beside the baking sheets to 375 degrees.',
        'Heat the oil beside the baking powder to 375 degrees.',
        'Heat the oil beside the baking soda to 375 degrees.',
        'Heat the oil beside the baking dish to 375 degrees.',
        'Heat the oil beside the baking pan to 375 degrees.',
        'Heat the oil to 375 degrees and drain on a baking sheet.',
        // A method word naming a VESSEL never governs (v27 closer, the
        // verifier's D8 / zz_probe2, typed): a roasting pan over two
        // burners fries.
        'Heat 1 inch of oil in a roasting pan to 350 degrees.',
        'Heat the oil in a large roasting pan over two burners to 350 '
            'degrees.',
        'Heat the oil in the roasting pans to 350 degrees.',
        'Heat the oil beside the roasting rack to 350 degrees.',
        'Heat the oil in a broiling pan to 350 degrees.',
        'Heat the oil on a baking tray to 350 degrees.',
      ]) {
        expect(_heat(s), isTrue, reason: s);
      }
      expect(
        _heat(
          'Brush the pitas with the oil, heat them, roast in a pan at '
          '375 degrees.',
        ),
        isFalse,
        reason: 'the method word still governs when no vessel follows it',
      );
    });

    test('the words right after a temperature: an appliance phrase or a '
        'method verb joined to it', () {
      for (final after in [
        'in the oven',
        'on the grill',
        'under the broiler',
        'inside the smoker',
        'in a hot preheated oven',
        'in an oven',
        'in a very hot oven',
        'in your oven',
        'oven',
        'and bake',
        'then bake',
        'and then bake',
        'and keep baking',
        'and continue baking',
        'and roast',
        'and broil',
        'F in the oven',
        'Fahrenheit in the oven',
      ]) {
        final s = 'Heat the oil to 375 degrees $after.';
        expect(_heat(s), isFalse, reason: s);
      }
      expect(_heat('Heat the oil to 375 degrees and fry the fish.'), isTrue);
      // The words after stay inside the temperature's clause: a heat verb
      // ends them (v27 closer, the verifier's D8 / zz_probe2, typed) — the
      // oven reheated is its own clause's — as does a clause mark.
      for (final s in [
        'Heat oil to 375 degrees in pot and reheat oven.',
        'Heat oil to 375 degrees in pot then heat oven.',
        'Heat oil to 375 degrees in pot, then the oven.',
      ]) {
        expect(_heat(s), isTrue, reason: s);
      }
      expect(
        _heat('Heat oil to 375 degrees in pot and oven.'),
        isFalse,
        reason: 'no heat verb between: the oven still governs',
      );
    });

    test('"and"/"then" open a new verb phrase unless an article or a number '
        'follows', () {
      for (final s in [
        'Heat the oil and the butter to 350 degrees.',
        'Heat the oil and a knob of butter to 350 degrees.',
        'Heat the oil and an onion to 350 degrees.',
        'Heat the oil and its garlic to 350 degrees.',
        'Heat the oil to between about 350 and about 375 degrees.',
        'Heat the oil to between 350 and around 375 degrees.',
        'Heat the oil to between 350 and approximately 375 degrees.',
        'Heat the oil to between 350 and approx 375 degrees.',
        'Heat the oil to between 350 and roughly 375 degrees.',
        'Keep the oil temperature near 350 degrees.',
      ]) {
        expect(_heat(s), isTrue, reason: s);
      }
    });

    test('end to end (O4/O5): 0149 Easier Fried Chicken with its frying '
        'sentence retyped — the 381 g of oil discarded, the flour held as a '
        'coating, the recipe fries', () {
      final r = loadCorpusRecipe(_easier);
      const h = 'Heat the oil in an 11-inch straight-sided sauté pan';
      for (final x in [
        r,
        _stepSays(
          r,
          h,
          'Line a rimmed baking sheet with paper towels and '
          'heat the oil in an 11-inch straight-sided sauté pan',
        ),
        _stepSays(
          r,
          h,
          'While the chicken rests in the baking soda rub, '
          'heat the oil in an 11-inch straight-sided sauté pan',
        ),
        _stepSays(
          r,
          h,
          'Heat the oil (roasted peanut works well) in an '
          '11-inch straight-sided sauté pan',
        ),
        for (final t in [
          'to 350–375 degrees',
          'to 350-375 degrees',
          'to between 350 and 375 degrees',
          'until it reads 375 degrees',
          'to a temperature of 375 degrees',
        ])
          _stepSays(r, _easierStep, 'medium-high heat $t'),
      ]) {
        expect(
          (
            _medium(x, _easierOil),
            _medium(x, _easierFlour),
            friesForTest(x),
          ),
          (_fry, _coating, true),
        );
      }
    }, skip: skipIfNoCorpus);

    test("end to end (S2): 0000's olive oil retyped \"1 cup vegetable oil\" "
        'with each S2 sentence appended — the cup is frying oil', () {
      final r = _retyped(
        loadCorpusRecipe(_mashed),
        _mashedOlive,
        '1 cup vegetable oil',
      );
      for (final s in positives.take(8)) {
        expect(
          _medium(_plusStep(r, s), '1 cup vegetable oil'),
          _fry,
          reason: s,
        );
      }
      // v26's own pita negatives stay counted: an oven governing the heat.
      final pita = loadCorpusRecipe(_pita);
      expect(
        _medium(
          _plusStep(
            pita,
            'Brush the pitas with the oil, heat to 375 '
            'degrees and keep baking.',
          ),
          _olive,
        ),
        isNull,
      );
    }, skip: skipIfNoCorpus);
  });

  group('I3 (Run 057 S3/O6, Sonnet critics 1/2): ONE candidacy, the mass '
      "rule's own reading; every medium threshold in both unit families", () {
    late FdcFood oil;
    setUpAll(() async => oil = (await FixtureProvider().food(2710180))!);

    ({double? grams, String? hold}) out(Recipe r, String raw) {
      final line = nutritionLines(r).firstWhere((l) => l.raw == raw);
      final o = engineOutcome(
        r,
        line,
        oil,
        resolveGrams(
          amounts: line.amounts,
          food: oil,
          normalizedItem: normalizeItem(lineItemOf(line)),
          raw: line.raw,
        ),
        picked: true,
      );
      return (grams: o.grams, hold: o.hold);
    }

    test("0690's aioli oil (\"½ cup extra-virgin olive oil\") beside every "
        'line the mass rule zeroes — a printed-weight bottle, a counted or a '
        'small "for frying" line — is HELD, never zeroed alone; the line '
        'held with no food iff the compute does not zero it', () {
      const aioli = '½ cup extra-virgin olive oil';
      final base = _retyped(
        loadCorpusRecipe(_bravas),
        '1 tablespoon vegetable oil',
        aioli,
      );
      // ONE reading on both paths (v27 closer, the verifier's D3 /
      // zz_probe1): the mass rule reads no food, so a reader with none —
      // the matches GET's `held`, the reach, an un-skip ([heldMediumLine])
      // — holds exactly the lines the compute ([engineOutcome]) does not
      // zero. The 48-ounce bottle, 24 ounces and 3 quarts are zeroed on
      // both (v27 as handed over held them with no grams).
      for (final (fry, own) in [
        ('24 ounces vegetable oil', _fry),
        ('1 (48-ounce) bottle vegetable oil', _fry),
        ('3 quarts vegetable oil', _fry),
        ('1 bottle vegetable oil, for frying', _fry),
        ('3 tablespoons vegetable oil, for frying', _fry),
        ('3 tablespoons vegetable oil, for deep frying', _fry),
        ('3 tablespoons vegetable oil, for pan-frying', _amb),
      ]) {
        final r = _retyped(base, '3 cups vegetable oil', fry);
        IngredientLine lineOf(String raw) =>
            nutritionLines(r).firstWhere((l) => l.raw == raw);
        expect((_medium(r, fry), _medium(r, aioli)), (own, _amb), reason: fry);
        final o = out(r, fry);
        expect(o.grams == 0, own == _fry, reason: fry);
        expect(heldMediumLine(r, lineOf(fry)), o.grams != 0, reason: fry);
        expect(out(r, aioli).hold, 'ambiguous_medium', reason: fry);
        expect(heldMediumLine(r, lineOf(aioli)), isTrue, reason: fry);
      }
      // The bottle resolves to 1,361 g: the mass rule zeroes it outright.
      final bottle = _retyped(
        base,
        '3 cups vegetable oil',
        '1 (48-ounce) bottle vegetable oil',
      );
      expect(out(bottle, '1 (48-ounce) bottle vegetable oil').grams, 0);
    }, skip: skipIfNoCorpus);

    test("0690's frying oil written by weight fries like \"1 cup\": the "
        'quarter cup is 54.4 g of oil (0.92 g/mL)', () {
      final r = loadCorpusRecipe(_bravas);
      for (final (raw, want) in [
        ('1 cup vegetable oil', _fry),
        ('8 ounces vegetable oil', _fry),
        ('12 ounces vegetable oil', _fry),
        ('200 grams vegetable oil', _fry),
        ('55 grams vegetable oil', _fry),
        ('54 grams vegetable oil', null),
        ('1 ounce vegetable oil', null),
      ]) {
        expect(
          _medium(_retyped(r, '3 cups vegetable oil', raw), raw),
          want,
          reason: raw,
        );
      }
    }, skip: skipIfNoCorpus);

    test('a fat the density table does not list (shortening) is read at '
        "oil's 0.92: 0690 frying 12 ounces of shortening; an amount-less "
        '"for pan-frying" line weighs nothing and is never zeroed or held', () {
      final r = _stepSays(
        _retyped(
          loadCorpusRecipe(_bravas),
          '3 cups vegetable oil',
          '12 ounces vegetable shortening',
        ),
        'Heat oil in large Dutch oven',
        'Heat shortening in large Dutch oven',
      );
      expect(_medium(r, '12 ounces vegetable shortening'), _fry);
      final bare = _plusStep(
        _retyped(
          loadCorpusRecipe(_bravas),
          '1 tablespoon vegetable oil',
          'Vegetable oil, for pan-frying',
        ),
        'Heat the oil to 375 degrees.',
      );
      expect(_medium(bare, 'Vegetable oil, for pan-frying'), isNull);
      // 3 cups (653 g at 0.92) is the mass rule's, read with no food as the
      // compute reads it (v27 closer, D3: v27 as handed over held it here
      // while the compute zeroed it).
      expect(_medium(bare, '3 cups vegetable oil'), _fry);
    }, skip: skipIfNoCorpus);

    test("the mass rule's 400 g read with no food (D3): 0690's frying oil "
        'retyped 400 grams zeroes on the mass rule alone, 399 grams does not '
        '(its own sentence still fries it)', () {
      for (final (raw, alone) in [
        ('400 grams vegetable oil', _fry),
        ('399 grams vegetable oil', null),
        ('15 ounces vegetable oil', _fry),
        ('14 ounces vegetable oil', null),
        ('2 cups vegetable oil', _fry),
        ('1¾ cups vegetable oil', null),
      ]) {
        final r = _retyped(
          loadCorpusRecipe(_bravas),
          '3 cups vegetable oil',
          raw,
        );
        final line = nutritionLines(r).firstWhere((l) => l.raw == raw);
        final item = normalizeItem(lineItemOf(line));
        expect(
          discardedMediumOf(r, line, item, bySentence: false),
          alone,
          reason: raw,
        );
        expect(_medium(r, raw), _fry, reason: raw);
      }
    }, skip: skipIfNoCorpus);

    test('a dredge written by weight is a dredge for the oil owners too: '
        "0116 Schnitzel's flour retyped \"3 ounces\" (85 g, 167 mL at 0.51), "
        'its crumbs 2 tablespoons (no dredge), its frying sentence naming no '
        'oil, a ½ cup olive oil added — '
        'the fried, dredged food holds both oil candidates', () {
      final base = loadCorpusRecipe('0116-chicken-schnitzel.yaml');
      final r = _stepSays(
        _retyped(
          _retyped(
            _retyped(
              base,
              '2 cups plain dried bread crumbs',
              '2 tablespoons plain dried bread crumbs',
            ),
            '½ cup all-purpose flour',
            '3 ounces all-purpose flour',
          ),
          '1 tablespoon vegetable oil',
          '½ cup olive oil',
        ),
        'Add 2 cups oil to large Dutch oven and heat over medium-high heat '
            'to 350 degrees.',
        'Fry the cutlets in batches.',
      );
      expect(_medium(r, '3 ounces all-purpose flour'), _coating);
      expect(_medium(r, '½ cup olive oil'), _amb);
    }, skip: skipIfNoCorpus);

    test("0148's dredge, brine salt and buttermilk soak written by weight: "
        'flour ¼ cup = 30.2 g (0.51), table salt 44 mL = 53.7 g (1.22), '
        'kosher 31.7 g (0.72), buttermilk 4 cups = 974 g (1.03)', () {
      final r = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
      const flour = '4 cups (20 ounces) unbleached all-purpose flour';
      for (final (from, raw, want) in [
        (flour, flour, _coating),
        (flour, '20 ounces unbleached all-purpose flour', _coating),
        (flour, '2 pounds unbleached all-purpose flour', _coating),
        (flour, '31 grams unbleached all-purpose flour', _coating),
        (flour, '30 grams unbleached all-purpose flour', null),
        ('½ cup table salt', '½ cup table salt', DiscardedMedium.brine),
        ('½ cup table salt', '4 ounces table salt', DiscardedMedium.brine),
        ('½ cup table salt', '1 pound table salt', DiscardedMedium.brine),
        ('½ cup table salt', '54 grams table salt', DiscardedMedium.brine),
        ('½ cup table salt', '53 grams table salt', null),
        ('½ cup table salt', '32 grams kosher salt', DiscardedMedium.brine),
        ('½ cup table salt', '31 grams kosher salt', null),
        ('7 cups buttermilk', '64 ounces buttermilk', DiscardedMedium.soak),
        ('7 cups buttermilk', '980 grams buttermilk', DiscardedMedium.soak),
        ('7 cups buttermilk', '970 grams buttermilk', DiscardedMedium.brine),
      ]) {
        expect(_medium(_retyped(r, from, raw), raw), want, reason: raw);
      }
    }, skip: skipIfNoCorpus);
  });

  group('I5 (Run 057 S6/O8/O13): the popcorn qualifier by vocabulary, not by '
      'word count', () {
    late FdcFood popcorn;
    setUpAll(() async => popcorn = (await FixtureProvider().food(2708216))!);
    double? grams(String raw) {
      final p = parseIngredientLine(raw);
      return resolveGrams(
        amounts: p.amounts,
        food: popcorn,
        normalizedItem: normalizeItem(p.item ?? raw),
        raw: raw,
      )?.grams;
    }

    test('every word a qualifier: the kernel cup (96.5 g); a number, a '
        '"from" or a removal verb: a note (the popped cup)', () {
      for (final (raw, g) in [
        // Run 057's shapes.
        ('½ cup popcorn (unpopped kernels)', 96.5),
        ('½ cup popcorn (raw kernels)', 96.5),
        ('½ cup popcorn, unpopped kernels', 96.5),
        ('½ cup popcorn (dry, unpopped)', 96.5),
        ('½ cup popcorn (yellow kernels)', 96.5),
        ('8 cups popped popcorn (unpopped kernels discarded)', 112.0),
        ('8 cups popped popcorn (old maids and kernels removed)', 112.0),
        ('8 cups popped popcorn, unpopped kernels reserved', 112.0),
        ('8 cups popped popcorn (unpopped kernels for another use)', 112.0),
        ('½ cup popcorn (unpopped)', 96.5),
        // Each other word of the vocabulary, its line's only qualifier.
        ('½ cup popcorn (kernels)', 96.5),
        ('½ cup popcorn (white kernel)', 96.5),
        ('½ cup popcorn (dry kernels)', 96.5),
        ('½ cup popcorn (plain kernels)', 96.5),
        ('8 cups corn (popped)', 112.0),
        ('8 cups corn (air-popped)', 112.0),
        ('8 cups corn, popped', 112.0),
        // A number or "from" is a note.
        ('8 cups popped popcorn (from ⅓ cup kernels)', 112.0),
        ('8 cups popped popcorn (⅓ cup kernels)', 112.0),
        ('8 cups popped popcorn (2 kernels)', 112.0),
      ]) {
        expect(grams(raw), closeTo(g, 0.01), reason: raw);
      }
    });
  });
}
