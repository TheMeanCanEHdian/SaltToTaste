import 'package:salt_shared/src/util/quantity.dart';
import 'package:test/test.dart';

import 'corpus.dart';

/// Every distinct `quantity:` value in the corpus, unquoted, nulls skipped.
Set<String> _distinctCorpusQuantities() =>
    distinctCorpusValues(RegExp(r'^\s*quantity: (.+)$', multiLine: true));

void main() {
  group('parseQuantity', () {
    // Integer values from the corpus quantity vocabulary.
    test('parses integers', () {
      expect(parseQuantity('1'), 1);
      expect(parseQuantity('2'), 2);
      expect(parseQuantity('12'), 12);
      expect(parseQuantity('30'), 30);
      expect(parseQuantity('62'), 62);
    });

    // ASCII fractions from the corpus quantity vocabulary.
    test('parses ASCII fractions', () {
      expect(parseQuantity('1/2'), 0.5);
      expect(parseQuantity('1/4'), 0.25);
      expect(parseQuantity('3/4'), 0.75);
      expect(parseQuantity('1/3'), closeTo(1 / 3, 1e-12));
      expect(parseQuantity('2/3'), closeTo(2 / 3, 1e-12));
      expect(parseQuantity('1/8'), 0.125);
      expect(parseQuantity('3/8'), 0.375);
      expect(parseQuantity('7/8'), 0.875);
    });

    // Mixed numbers from the corpus quantity vocabulary.
    test('parses mixed numbers', () {
      expect(parseQuantity('4 1/4'), 4.25);
      expect(parseQuantity('1 3/4'), 1.75);
      expect(parseQuantity('1 1/2'), 1.5);
      expect(parseQuantity('2 1/3'), closeTo(2 + 1 / 3, 1e-12));
      expect(parseQuantity('3 3/8'), 3.375);
      expect(parseQuantity('11 5/8'), 11.625);
      expect(parseQuantity('10 1/5'), closeTo(10.2, 1e-12));
      expect(parseQuantity('4 2/5'), closeTo(4.4, 1e-12));
    });

    test('parses standalone unicode vulgar fractions', () {
      expect(parseQuantity('¼'), 0.25);
      expect(parseQuantity('½'), 0.5);
      expect(parseQuantity('¾'), 0.75);
      expect(parseQuantity('⅓'), closeTo(1 / 3, 1e-12));
      expect(parseQuantity('⅔'), closeTo(2 / 3, 1e-12));
      expect(parseQuantity('⅕'), closeTo(1 / 5, 1e-12));
      expect(parseQuantity('⅖'), closeTo(2 / 5, 1e-12));
      expect(parseQuantity('⅗'), closeTo(3 / 5, 1e-12));
      expect(parseQuantity('⅘'), closeTo(4 / 5, 1e-12));
      expect(parseQuantity('⅙'), closeTo(1 / 6, 1e-12));
      expect(parseQuantity('⅚'), closeTo(5 / 6, 1e-12));
      expect(parseQuantity('⅐'), closeTo(1 / 7, 1e-12));
      expect(parseQuantity('⅛'), 0.125);
      expect(parseQuantity('⅜'), 0.375);
      expect(parseQuantity('⅝'), 0.625);
      expect(parseQuantity('⅞'), 0.875);
      expect(parseQuantity('⅑'), closeTo(1 / 9, 1e-12));
      expect(parseQuantity('⅒'), closeTo(1 / 10, 1e-12));
    });

    // Attached unicode mixed numbers as they appear in corpus source text
    // ('1½ cups', '8¾ ounces', '2⅓ cups', '1⅛ teaspoons').
    test('parses attached unicode mixed numbers', () {
      expect(parseQuantity('1½'), 1.5);
      expect(parseQuantity('1¾'), 1.75);
      expect(parseQuantity('8¾'), 8.75);
      expect(parseQuantity('2⅓'), closeTo(2 + 1 / 3, 1e-12));
      expect(parseQuantity('1⅛'), 1.125);
      expect(parseQuantity('10½'), 10.5);
      expect(parseQuantity('16½'), 16.5);
    });

    test('parses spaced unicode mixed numbers', () {
      expect(parseQuantity('1 ¾'), 1.75);
      expect(parseQuantity('2 ½'), 2.5);
    });

    test('parses plain decimals', () {
      expect(parseQuantity('1.5'), 1.5);
      expect(parseQuantity('0.75'), 0.75);
      expect(parseQuantity('.5'), 0.5);
    });

    test('trims whitespace', () {
      expect(parseQuantity(' 2 '), 2);
      expect(parseQuantity('  1 3/4  '), 1.75);
      expect(parseQuantity(' 1½ '), 1.5);
    });

    // Range strings occur in the corpus quantity field but are not
    // quantities; they must not parse.
    test('returns null for ranges', () {
      expect(parseQuantity('1–2'), isNull);
      expect(parseQuantity('1/4–1/2'), isNull);
      expect(parseQuantity('4-5'), isNull);
      expect(parseQuantity('3–3 1/2'), isNull);
      expect(parseQuantity('1 1/2–2'), isNull);
    });

    test('returns null for unparseable input', () {
      expect(parseQuantity(''), isNull);
      expect(parseQuantity('   '), isNull);
      expect(parseQuantity('pinch'), isNull);
      expect(parseQuantity('to taste'), isNull);
      expect(parseQuantity('1/0'), isNull);
      expect(parseQuantity('1.'), isNull);
      expect(parseQuantity('1 2'), isNull);
    });
  });

  group('corpus coverage', skip: skipIfNoCorpus, () {
    // Every distinct quantity value in the real corpus is either a range
    // (which by design does not parse) or parses to a number.
    test('parses every non-range corpus quantity value', () {
      final values = _distinctCorpusQuantities();
      expect(
        values.length,
        greaterThan(50),
        reason: 'corpus not found at $corpusDir',
      );

      final range = RegExp('[–-]');
      final failures = <String>[];
      for (final value in values) {
        if (range.hasMatch(value)) continue;
        if (parseQuantity(value) == null) failures.add(value);
      }
      if (failures.isNotEmpty) {
        print('unparseable corpus quantities: $failures');
      }
      expect(failures, isEmpty);
    });
  });
}
