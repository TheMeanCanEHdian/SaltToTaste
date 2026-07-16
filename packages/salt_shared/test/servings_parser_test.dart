import 'package:salt_shared/src/model/recipe.dart' show Serves;
import 'package:salt_shared/src/util/servings_parser.dart';
import 'package:test/test.dart';

import 'corpus.dart';

/// Every distinct top-level `servings:` value in the corpus, unquoted,
/// nulls skipped (exactly one corpus recipe has `servings: null`).
Set<String> _distinctCorpusServings() => distinctCorpusValues(
      RegExp(r'^servings: (.+)$', multiLine: true),
      firstMatchOnly: true,
    );

/// Asserts [text] parses to `Serves(min, max)`.
void expectServes(String text, int min, int max) {
  final Serves? serves = parseServings(text);
  expect(serves, isNotNull, reason: 'no parse for "$text"');
  expect(serves!.min, min, reason: 'min for "$text"');
  expect(serves.max, max, reason: 'max for "$text"');
}

// Every test string below is a verbatim servings value from the corpus.
void main() {
  group('parseServings', () {
    test('SERVES n', () {
      expectServes('SERVES 4', 4, 4);
      expectServes('SERVES 2', 2, 2);
      expectServes('SERVES 9', 9, 9);
      expectServes('SERVES 16', 16, 16);
    });

    test('is case-insensitive', () {
      expectServes('Serves 4', 4, 4);
      expectServes('Serves 8 to 10', 8, 10);
      expectServes('SERVES 4 to 6', 4, 6);
      expectServes('Serves 6 as a main dish', 6, 6);
    });

    test('SERVES n TO m', () {
      expectServes('SERVES 4 TO 6', 4, 6);
      expectServes('SERVES 6 TO 8', 6, 8);
      expectServes('SERVES 10 TO 12', 10, 12);
      expectServes('SERVES 18 TO 24', 18, 24);
    });

    test('SERVES ABOUT n', () {
      expectServes('SERVES ABOUT 20', 20, 20);
    });

    test('SERVES with trailing prose keeps the first clause', () {
      expectServes('SERVES 4 AS A MAIN DISH', 4, 4);
      expectServes('SERVES 4 TO 6 AS A SIDE DISH', 4, 6);
      expectServes('SERVES 8 TO 10 AS A SIDE DISH', 8, 10);
      expectServes('SERVES 4 AS AN APPETIZER OR A SIDE DISH', 4, 4);
      expectServes('SERVES 4 AS A MAIN COURSE OR 6 AS AN APPETIZER', 4, 4);
      expectServes(
          'SERVES 8 TO 10 AS AN APPETIZER OR 4 TO 6 AS A MAIN DISH', 8, 10);
      expectServes(
          'SERVES 6 TO 8 AS A MAIN COURSE OR 10 TO 12 AS AN APPETIZER', 6, 8);
      expectServes('SERVES 10 TO 22, DEPENDING ON TURKEY SIZE', 10, 22);
    });

    test('SERVES with a parenthetical or trailing MAKES clause', () {
      expectServes('SERVES 8 (MAKES ABOUT 1 QUART)', 8, 8);
      expectServes('SERVES 8 (MAKES 2 LOAVES)', 8, 8);
      expectServes('SERVES 6 TO 8 (MAKES 24 PUFFS)', 6, 8);
      expectServes('SERVES 6 TO 8 (MAKES 4½ CUPS)', 6, 8);
      expectServes('SERVES 12 (MAKES ABOUT 2¾ CUPS)', 12, 12);
      expectServes('SERVES 4 (MAKES 12 PANCAKES)', 4, 4);
      expectServes('SERVES 4 (MAKES SIX 7-INCH WAFFLES)', 4, 4);
      expectServes('SERVES 4 TO 6; MAKES 36 RAVIOLI', 4, 6);
      expectServes('SERVES 4 TO 6 (MAKES ABOUT 15 PAKORAS)', 4, 6);
      expectServes('SERVES 6 (MAKES ABOUT 1 POUND SALMON)', 6, 6);
    });

    test('MAKES n <things>', () {
      expectServes('MAKES 24 COOKIES', 24, 24);
      expectServes('MAKES 12 MUFFINS', 12, 12);
      expectServes('MAKES 1 LOAF', 1, 1);
      expectServes('MAKES 2 LOAVES', 2, 2);
      expectServes('MAKES 8 SCONES', 8, 8);
      expectServes('MAKES 64 TRUFFLES', 64, 64);
      expectServes('MAKES 1 COCKTAIL', 1, 1);
      expectServes('MAKES 80 1½-INCH COOKIES', 80, 80);
      expectServes('MAKES 2 FOLDED 8-INCH QUESADILLAS', 2, 2);
    });

    test('bare MAKES n', () {
      expectServes('MAKES 4', 4, 4);
      expectServes('MAKES 12', 12, 12);
    });

    test('MAKES ABOUT n', () {
      expectServes('MAKES ABOUT 24 COOKIES', 24, 24);
      expectServes('MAKES ABOUT 48 SMALL COOKIES', 48, 48);
      expectServes('MAKES ABOUT 16 LARGE COOKIES', 16, 16);
      expectServes('MAKES ABOUT 40 DUMPLINGS', 40, 40);
    });

    test('MAKES n TO m', () {
      expectServes('MAKES 32 TO 40 PIECES', 32, 40);
      expectServes('MAKES 1 TO 16 EGGS', 1, 16);
      expectServes(
          'MAKES 3 TO 4 WAFFLES, DEPENDING ON THE SIZE OF THE IRON', 3, 4);
      // Fractional endpoints round to the nearest whole count.
      expectServes('MAKES 2½ TO 3 CUPS', 3, 3);
    });

    test('MAKES with number words', () {
      expectServes('MAKES ONE 8-INCH LOAF', 1, 1);
      expectServes('MAKES ONE 9-INCH SINGLE CRUST', 1, 1);
      expectServes('MAKES TWO 9-INCH PIZZAS', 2, 2);
      expectServes('MAKES TWO 11½-INCH PIZZAS', 2, 2);
      expectServes('MAKES FOUR 1-PINT JARS', 4, 4);
      expectServes('MAKES FOUR 15-INCH-LONG BAGUETTES', 4, 4);
      expectServes('MAKES EIGHT 7-INCH PITA BREADS', 8, 8);
      expectServes('MAKES TWELVE 2-INCH FRITTERS', 12, 12);
      expectServes('MAKES SIXTEEN 2-INCH BROWNIES', 16, 16);
      expectServes('MAKES ABOUT EIGHT 7-INCH ROUND WAFFLES', 8, 8);
      expectServes('MAKES ABOUT FORTY 2½-INCH COOKIES', 40, 40);
    });

    test('MAKES ENOUGH FOR', () {
      expectServes('MAKES ENOUGH FOR ONE 9-INCH PIE', 1, 1);
      expectServes('MAKES ENOUGH FOR ONE 9-INCH TART', 1, 1);
    });

    test('DOZEN multiplies by 12', () {
      expectServes('MAKES 2 DOZEN 2-INCH BROWNIES', 24, 24);
    });

    test('a SERVES/SERVING clause wins over a MAKES count', () {
      expectServes('MAKES 18 TAMALES; SERVES 6 TO 8', 6, 8);
      expectServes('MAKES 1 POUND; SERVES 4 TO 6', 4, 6);
      expectServes('MAKES 2 SMALL LOAVES; SERVES 6 TO 8', 6, 8);
      expectServes('MAKES 12 (4-INCH) PANCAKES; SERVES 3 TO 4', 3, 4);
      expectServes('MAKES SIXTEEN 4-INCH PANCAKES; SERVES 4 TO 6', 4, 6);
      expectServes(
          'Makes about sixteen 4-inch pancakes; serves 4 to 6', 4, 6);
      expectServes('MAKES SIX 9-INCH CALZONES (SERVES 6 TO 8)', 6, 8);
      expectServes('MAKES 2 LOAVES (SERVES 20)', 20, 20);
      expectServes('MAKES ONE 8-INCH LOAF, SERVING 8', 8, 8);
      expectServes('MAKES 2 TARTS, SERVING 6', 6, 6);
      expectServes('MAKES 2 TARTS, SERVING 8 TO 10', 8, 10);
      expectServes('MAKES FOUR 9-INCH PIZZAS, SERVING 4 TO 6', 4, 6);
      expectServes('MAKES 18 TO 20, SERVING 6 TO 8 AS AN APPETIZER', 6, 8);
      expectServes('MAKES 24 PIECES, ENOUGH TO SERVE 4 TO 6', 4, 6);
    });

    test('a count before the noun SERVINGS wins over a MAKES count', () {
      expectServes(
          'MAKES 3 CUPS OF MIX; ENOUGH FOR TWELVE 1-CUP SERVINGS', 12, 12);
    });

    // Documented behavior: pure quantities of volume or weight return the
    // leading number (the serving basis is editable later in the app).
    test('volume and weight yields return the leading number', () {
      expectServes('MAKES ABOUT 4 CUPS', 4, 4);
      expectServes('MAKES 2 CUPS', 2, 2);
      expectServes('MAKES ABOUT 1 QUART', 1, 1);
      expectServes('MAKES 1 QUART', 1, 1);
      expectServes('MAKES ABOUT 2 POUNDS (4 CUPS)', 2, 2);
      expectServes('MAKES ABOUT 2 CUPS, ENOUGH FOR 4 SANDWICHES', 2, 2);
      expectServes('MAKES 5 CUPS; ENOUGH FOR 1 POUND PASTA', 5, 5);
      expectServes('MAKES 6 CUPS; ENOUGH FOR 2 POUNDS PASTA', 6, 6);
      // Fractional leading numbers round to a whole count, floor of 1.
      expectServes('MAKES 1½ CUPS', 2, 2);
      expectServes('MAKES 2¼ CUPS', 2, 2);
      expectServes('MAKES 2½ CUPS', 3, 3);
      expectServes('MAKES ABOUT 1½ POUNDS', 2, 2);
      expectServes('MAKES ABOUT 1¾ CUPS BASE; ENOUGH FOR 7 QUARTS BROTH', 2, 2);
      expectServes('MAKES ABOUT 1½ CUPS; ENOUGH FOR 3 CUPS ICED COFFEE', 2, 2);
      expectServes(
          'MAKES ABOUT ¼ CUP, ENOUGH TO DRESS 8 TO 10 CUPS LIGHTLY '
          'PACKED GREENS',
          1,
          1);
    });

    // Regression tests from the P0 code review. These forms come from
    // hand-edited files and editor input, so they are not in the corpus
    // vocabulary; the corpus coverage test below remains the real-data gate.
    test('SERVES hyphen/en-dash ranges parse like TO ranges', () {
      expectServes('SERVES 4-6', 4, 6);
      expectServes('SERVES 4–6', 4, 6);
      expectServes('SERVES 4 - 6', 4, 6);
    });

    test('DOZEN multiplies before rounding', () {
      expectServes('MAKES 1½ DOZEN COOKIES', 18, 18);
      expectServes('MAKES 2 DOZEN COOKIES', 24, 24);
      expectServes('MAKES ½ DOZEN MUFFINS', 6, 6);
    });

    test('n SERVINGS with a preceding non-count word', () {
      expectServes('ABOUT 12 SERVINGS', 12, 12);
      expectServes('YIELDS 12 SERVINGS', 12, 12);
      expectServes('4 TO 6 SERVINGS', 4, 6);
      expectServes('MAKES ABOUT TWELVE 1-CUP SERVINGS', 12, 12);
    });

    test('returns null when no count can be extracted', () {
      expect(parseServings(null), isNull);
      expect(parseServings(''), isNull);
      expect(parseServings('   '), isNull);
      expect(parseServings('SEE NOTE'), isNull);
      expect(parseServings('MAKES A BATCH'), isNull);
    });

    // The whole point: run the parser over every distinct servings value in
    // the real corpus and require a >= 99% parse-success rate.
    test('parses >= 99% of all distinct corpus servings values', () {
      final values = _distinctCorpusServings();
      expect(values.length, greaterThan(100),
          reason: 'corpus not found at $corpusDir');

      final failures = <String>[];
      for (final value in values) {
        if (parseServings(value) == null) failures.add(value);
      }
      if (failures.isNotEmpty) {
        print('unparsed corpus servings values: $failures');
      }
      final rate = (values.length - failures.length) / values.length;
      expect(rate, greaterThanOrEqualTo(0.99),
          reason: '${failures.length}/${values.length} values failed');
    }, skip: skipIfNoCorpus);
  });
}
