// Matcher v29 (Run 059 I2): RULE B — a clause boundary is the LATEST of a
// clause mark, a new-verb-phrase opener or the fat's own mention; a phrase
// opening on the evidence's own (non-fry) heat verb opens no clause; the
// participle exception deleted; the hyphenated vessels; the heat reading's
// whole-sentence passes built once per sentence per index. Real corpus
// recipes (0491, 0149) and the library's own frying sentences. Synthesized,
// each a stated exception (no corpus step says it — typed through the
// editor/API, an admin's or an import's path): every typed sentence below
// (Run 059 O7/S9's oven-and-oil sentences, O8/S11's hyphenated vessels,
// S23's mark-then-participle sentence, Sonnet critic 2's marks × verbs
// sentence) and the retyped steps of 0491 and 0149.

// The typed sentences of a list read as one string each.
// ignore_for_file: no_adjacent_strings_in_list

import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';

bool _heat(String s, [String fat = 'oil']) => heatsFatToFryForTest(s, fat);

/// [r] with every step's [from] written [to].
Recipe _stepSays(Recipe r, String from, String to) => r.copyWith(
  steps: [
    for (final s in r.steps) s.copyWith(text: s.text.replaceAll(from, to)),
  ],
);

DiscardedMedium? _medium(Recipe r, String raw) {
  final line = nutritionLines(r).firstWhere((l) => l.raw == raw);
  return discardedMediumOf(r, line, normalizeItem(lineItemOf(line)));
}

const _tostadas = '0491-spicy-mexican-shredded-pork-tostadas.yaml';
const _chicken = '0149-easier-fried-chicken.yaml';

void main() {
  group('I2(a) (Run 059 O7/S9): the boundary is the LATEST of a mark, an '
      "opener or the fat's own mention — never the evidence verb", () {
    test('every sentence O7, S9 and S23 list reads TRUE (v28 read each '
        "false: the oven governed the fat's own temperature)", () {
      for (final s in [
        // O7.
        'Set a wire rack in a rimmed baking sheet in a 200-degree oven, '
            'heating the vegetable oil in an 8-inch heavy-bottomed skillet '
            'over medium heat to 350 degrees.',
        'Set a wire rack in a rimmed baking sheet in a 200-degree oven, '
            'bringing the vegetable oil in an 8-inch heavy-bottomed skillet '
            'over medium heat to 350 degrees.',
        'Warm the platter in the oven, returning the oil to 350 degrees.',
        'Keep the chicken warm in the oven, frying the remaining pieces in '
            'oil at 350 degrees.',
        // S9.
        'Heat the oven to 200 degrees and heat the oil to 350 degrees.',
        'Place a rack in the oven and heat the vegetable oil in an 8-inch '
            'heavy-bottomed skillet over medium heat to 350 degrees.',
        'Set the pot in the oven and heat oil to 350 degrees.',
        'Place the rack in the oven and bring the oil to 350 degrees.',
        'Adjust an oven rack to the middle position and heat the oil in a '
            'Dutch oven to 350 degrees.',
        'Preheat the oven to 200 degrees and add the oil, heated to 350 '
            'degrees.',
        // S23.
        'Place the pizza stone in the oven, set the burner to medium, '
            'bringing the oil to 350 degrees.',
        // v28 pinned these false (I3(a)): the fat's own mention, or a new
        // verb phrase, now ends the oven's clause.
        'Set the pitas in the oven and heat the oil to 375 degrees.',
        'Set the pitas in the oven then heat the oil to 375 degrees.',
        'Grill the pitas and fry them in the oil at 375 degrees.',
        'Bake the croutons and heat the oil to 350 degrees.',
        'Fry the baking potatoes in oil at 350 degrees.',
      ]) {
        expect(_heat(s), isTrue, reason: s);
      }
    });

    test('every v28 negative still reads FALSE: a phrase opening on a heat '
        "verb whose object it never names continues the appliance's "
        'clause', () {
      for (final s in [
        'Brush the pitas with the oil and bake them in an oven heated to 375 '
            'degrees.',
        'Clean and oil cooking grate, then heat grill until lid thermometer '
            'registers 350 degrees.',
        'Brush the pork with the oil and cook in the smoker, holding it at '
            '300 degrees.',
        'Brush the pitas with the oil and heat them on the grill, keeping the '
            'temperature at 350 degrees.',
        'Toss the potatoes with the oil and roast in an oven heated to 200C.',
        'Add the oil to the smoker, holding it at 300 degrees.',
        'Rub the oil on the pizza stone and heat it at 350 degrees.',
        // After a mark, an "and"/"then" before the heat verb is skipped.
        'Rub the oil on the pizza stone, then heat it at 350 degrees.',
        'Rub the oil on the pizza stone; and heat it at 350 degrees.',
        // A boundary inside the temperature's lead is none.
        'Brush with oil and heat in the oven between about 350 and about 375 '
            'degrees.',
        'Heat the oil in the grill-pan on the grill to 350 degrees.',
      ]) {
        expect(_heat(s), isFalse, reason: s);
      }
    });

    test('each term of the boundary, the only thing between a sentence and '
        'its answer (S23)', () {
      for (final (s, want) in [
        // A mark opens a clause unless a heat verb follows it DIRECTLY:
        // "add" opens one, the later "keeping" does not reach back.
        (
          'Heat the oil in the pot set beside the oven, add the chicken, '
              'keeping it at 350 degrees.',
          true,
        ),
        // Spaces after a mark are skipped before the heat-verb test.
        ('Heat the oil in the smoker,   holding it at 300 degrees.', false),
        // An opener opens a clause; a fry verb's phrase is the fat's own.
        (
          'Heat the oil in a Dutch oven, keep the fried pieces warm in the '
              'oven and fry the rest at 350 degrees.',
          true,
        ),
        (
          'Heat the oil in a Dutch oven; keep the pieces warm in the oven, '
              'frying the rest at 350 degrees.',
          true,
        ),
        // Each mark.
        for (final m in [';', ',', ' —', ' (', ')'])
          (
            'Heat the oil beside the oven${m}add the fish at 350 degrees.',
            true,
          ),
        // A lead's own "(" opens the temperature's clause.
        ('Heat the oil beside the oven (350 degrees).', true),
        ('Heat the oil beside the oven (about 350 degrees).', true),
      ]) {
        expect(_heat(s), want, reason: s);
      }
    });

    test("0491's and 0149's frying oil retyped in O7's and S9's sentences: "
        'still frying oil (v28 counted ~150 g and ~380 g of poured-away oil '
        'whole)', () {
      final tostadas = loadCorpusRecipe(_tostadas);
      const fry =
          'Heat the vegetable oil in an 8-inch heavy-bottomed skillet over '
          'medium heat to 350 degrees.';
      const tail =
          'the vegetable oil in an 8-inch heavy-bottomed skillet over medium '
          'heat to 350 degrees.';
      expect(
        _medium(tostadas, '¾ cup vegetable oil'),
        DiscardedMedium.fryingOil,
      );
      for (final to in [
        'Set a wire rack in a rimmed baking sheet in a 200-degree oven, '
            'heating $tail',
        'Set a wire rack in a rimmed baking sheet in a 200-degree oven, '
            'bringing $tail',
        'Warm the platter in the oven, returning $tail',
        'Place a rack in the oven and heat $tail',
      ]) {
        final typed = _stepSays(tostadas, fry, to);
        expect(typed.steps.map((s) => s.text).join(), contains(to));
        expect(
          _medium(typed, '¾ cup vegetable oil'),
          DiscardedMedium.fryingOil,
          reason: to,
        );
      }
      final chicken = loadCorpusRecipe(_chicken);
      const heat = 'Heat the oil in an 11-inch straight-sided sauté pan';
      final typed = _stepSays(
        chicken,
        heat,
        'Place a rack in the oven and heat the oil in an 11-inch '
        'straight-sided sauté pan',
      );
      expect(typed.steps.map((s) => s.text).join(), contains('the oven and'));
      expect(
        (
          _medium(chicken, '1¾ cups vegetable oil'),
          _medium(typed, '1¾ cups vegetable oil'),
        ),
        (DiscardedMedium.fryingOil, DiscardedMedium.fryingOil),
      );
    }, skip: skipIfNoCorpus);
  });

  group('I2(b) (Run 059 O8/S11): a hyphenated vessel never excludes', () {
    test('"grill-pan", "broiler-pan", "sheet-pan", "roasting-pan" and '
        '"baking-sheet/-dish" read TRUE before and after the temperature; '
        'the appliance beside them still excludes', () {
      for (final v in [
        'grill-pan',
        'grill-pans',
        'broiler-pan',
        'sheet-pan',
        'roasting-pan',
        'baking-sheet',
        'baking-dish',
      ]) {
        for (final s in [
          'Heat the oil in a $v to 350 degrees.',
          'Heat the oil to 350 degrees in a $v.',
        ]) {
          expect(_heat(s), isTrue, reason: s);
        }
      }
      expect(
        _heat(
          'Heat the oil in the grill-pan on the grill to 350 '
          'degrees.',
        ),
        isFalse,
      );
    });
  });

  group('I2(c) (Run 059 S15 / Sonnet critic 2): the whole-sentence passes '
      'built ONCE per sentence per index, every pass counted', () {
    String fill(String head, String unit, int n) {
      final b = StringBuffer(head);
      while (b.length + unit.length < n) {
        b.write(unit);
      }
      return '$b';
    }

    test('every pass counted, read only as far as a check needs: a '
        'sentence whose temperature ends it costs five passes; one that '
        'answers at its first temperature its prefix', () {
      // The temperatures, the heat verbs, the boundaries, the fat's
      // mentions and the governing words (from the fat's mention on): five
      // whole passes, each counted once, a handful of pointer steps.
      final plain = '${fill('Heat the oil', ' stir', 1000)} to 350F.';
      stepIndexCounts.clear();
      expect(_heat(plain), isTrue);
      expect(
        stepIndexCounts['heatClauseChars'],
        inInclusiveRange(4.9 * plain.length, 5.1 * plain.length),
      );
      // The governing words read from the clause's start (the last mark),
      // as v27 read the clause: four whole passes, not five.
      final marked = '${fill('Heat the oil', ', stir', 1000)} to 350F.';
      stepIndexCounts.clear();
      expect(_heat(marked), isTrue);
      expect(
        stepIndexCounts['heatClauseChars'],
        inInclusiveRange(4 * marked.length, 4.5 * marked.length),
      );
      // The answer at the first of ~40 temperatures: the prefix alone.
      final early = '${fill('Heat the oil', ' to 350 degrees,', 1000)}.';
      stepIndexCounts.clear();
      expect(_heat(early), isTrue);
      // (The fat's mentions are one native search, to the end: counted
      // whole.)
      expect(stepIndexCounts['heatClauseChars'], lessThan(1.5 * early.length));
    });

    test('a ~1,000-character sentence of marks and heat verbs reads at most '
        '6 times its length in one check — an O(marks × verbs) rescan reads '
        'it ~18 times', () {
      for (final s in [
        '${fill('Heat the oil', ', heat', 1000)} to 350F.',
        '${fill('Heat the oil', ', heat the oil', 1000)} to 350F.',
        '${fill('Heat the oil', ' and heat', 1000)} to 350F.',
        '${fill('Heat the oil', ', heat it at 350 degrees', 1000)}.',
      ]) {
        stepIndexCounts.clear();
        _heat(s);
        expect(stepIndexCounts['heatChecks'], 1, reason: s);
        expect(
          stepIndexCounts['heatClauseChars'],
          lessThanOrEqualTo(6 * s.length),
          reason: s,
        );
      }
    });

    test(
      'one reading shared by the fats: a later fat whose clause starts '
      "EARLIER than an earlier fat's rescans the governing words from it",
      () {
        // The oil's clause starts after "oil" (no oven in it: frying heat);
        // the shortening's after "shortening", the oven inside it.
        const s =
            'Heat the shortening in the oven with the oil to 350 degrees.';
        expect(heatsFatsToFryForTest(s, ['oil', 'shortening']), [true, false]);
        expect(heatsFatsToFryForTest(s, ['shortening', 'oil']), [false, true]);
        expect([_heat(s), _heat(s, 'shortening')], [true, false]);
      },
    );

    test("0149's frying sentences, every fat and both callers: each "
        'sentence read once, its reading shared by every later check', () {
      final r = loadCorpusRecipe(_chicken);
      stepIndexCounts.clear();
      friesForTest(r);
      for (final l in nutritionLines(r)) {
        discardedMediumOf(r, l, normalizeItem(lineItemOf(l)));
      }
      final checks = stepIndexCounts['heatChecks']!;
      final readings = stepIndexCounts['memo:heatReading']!;
      final runs = {
        for (final step in r.steps)
          for (final s in step.text.toLowerCase().split(RegExp(r'(?<=\.)\s+')))
            if (RegExp(r'\d\d\d').hasMatch(s)) s,
      };
      expect(readings, inInclusiveRange(1, runs.length));
      expect(checks, greaterThan(readings));
      final chars = runs.fold(0, (n, s) => n + s.length);
      // Four passes once, two per fat — never per check.
      expect(
        stepIndexCounts['heatClauseChars'],
        lessThanOrEqualTo((4 + 2 * 3) * chars + checks * 8),
      );
    }, skip: skipIfNoCorpus);
  });
}
