import 'dart:io';

import 'package:salt_shared/src/util/quantity.dart';
import 'package:test/test.dart';

/// The real recipe corpus (1,198 extracted YAML documents).
const String _corpusDir = '/Users/drivard/Documents/Claude Projects/'
    'Recipe Extraction/The Complete America_s Test Kitchen TV Show '
    'Cookbook 2001–2023/recipes';

/// Every distinct `quantity:` value in the corpus, unquoted, nulls skipped.
Set<String> _distinctCorpusQuantities() {
  final lineRe = RegExp(r'^\s*quantity: (.+)$', multiLine: true);
  final values = <String>{};
  for (final entity in Directory(_corpusDir).listSync()) {
    if (entity is! File || !entity.path.endsWith('.yaml')) continue;
    for (final match in lineRe.allMatches(entity.readAsStringSync())) {
      var value = match.group(1)!.trim();
      if (value.length >= 2 && value.startsWith("'") && value.endsWith("'")) {
        value = value.substring(1, value.length - 1);
      }
      if (value.isEmpty || value == 'null') continue;
      values.add(value);
    }
  }
  return values;
}

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

  group('formatQuantity', () {
    test('renders whole values as integers', () {
      expect(formatQuantity(1), '1');
      expect(formatQuantity(2), '2');
      expect(formatQuantity(12), '12');
      expect(formatQuantity(0), '0');
      expect(formatQuantity(2.0000000001), '2');
    });

    test('renders nice fractions in ASCII mixed-number form', () {
      expect(formatQuantity(0.5), '1/2');
      expect(formatQuantity(0.25), '1/4');
      expect(formatQuantity(0.75), '3/4');
      expect(formatQuantity(1 / 3), '1/3');
      expect(formatQuantity(2 / 3), '2/3');
      expect(formatQuantity(0.125), '1/8');
      expect(formatQuantity(0.375), '3/8');
      expect(formatQuantity(1.75), '1 3/4');
      expect(formatQuantity(2.5), '2 1/2');
      expect(formatQuantity(1 + 1 / 3), '1 1/3');
      expect(formatQuantity(5.625), '5 5/8');
    });

    test('snaps near-misses within 1% relative error', () {
      expect(formatQuantity(0.501), '1/2');
      expect(formatQuantity(1.999), '2');
      expect(formatQuantity(0.334), '1/3');
      // The error budget is relative, so larger values snap to a nearby
      // nice fraction: 10 1/4 is within 0.49% of 10.2.
      expect(formatQuantity(10.2), '10 1/4');
    });

    test('falls back to a trimmed decimal', () {
      // Small fifths/tenths have no nice fraction within 1% relative error.
      expect(formatQuantity(0.2), '0.2');
      expect(formatQuantity(0.15), '0.15');
      expect(formatQuantity(0.6), '0.6');
      expect(formatQuantity(1.9), '1.9');
    });

    // Round trip: every common corpus quantity string survives
    // parse -> format unchanged.
    test('round-trips common corpus quantity strings', () {
      const corpusValues = [
        '1',
        '2',
        '3',
        '4',
        '6',
        '12',
        '1/2',
        '1/4',
        '3/4',
        '1/3',
        '2/3',
        '1/8',
        '3/8',
        '7/8',
        '1 1/2',
        '1 1/4',
        '1 3/4',
        '2 1/2',
        '2 1/3',
        '4 1/4',
        '5 1/4',
        '8 3/4',
        '3 3/8',
        '11 5/8',
      ];
      for (final value in corpusValues) {
        final parsed = parseQuantity(value);
        expect(parsed, isNotNull, reason: 'parse failed for "$value"');
        expect(
          formatQuantity(parsed!),
          value,
          reason: 'round trip failed for "$value"',
        );
      }
    });

    // Unicode corpus forms normalize to their ASCII equivalents.
    test('formats parsed unicode fractions as ASCII', () {
      expect(formatQuantity(parseQuantity('¾')!), '3/4');
      expect(formatQuantity(parseQuantity('1½')!), '1 1/2');
      expect(formatQuantity(parseQuantity('2⅓')!), '2 1/3');
      expect(formatQuantity(parseQuantity('8¾')!), '8 3/4');
      expect(formatQuantity(parseQuantity('1⅛')!), '1 1/8');
    });
  });

  group('corpus coverage', () {
    // Every distinct quantity value in the real corpus is either a range
    // (which by design does not parse) or parses to a number.
    test('parses every non-range corpus quantity value', () {
      final values = _distinctCorpusQuantities();
      expect(values.length, greaterThan(50),
          reason: 'corpus not found at $_corpusDir');

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
