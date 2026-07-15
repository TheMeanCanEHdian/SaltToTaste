import 'package:salt_server/src/auth/setup_code.dart';
import 'package:test/test.dart';

void main() {
  group('generateSetupCode', () {
    test('is XXXX-XXXX from the unambiguous alphabet', () {
      final pattern = RegExp(
        '^[$setupCodeAlphabet]{4}-[$setupCodeAlphabet]{4}\$',
      );
      for (var i = 0; i < 200; i++) {
        final code = generateSetupCode();
        expect(code, matches(pattern));
        expect(code, isNot(matches(RegExp('[ILO01]'))));
      }
    });

    test('alphabet excludes ambiguous characters', () {
      expect(setupCodeAlphabet.length, 31);
      for (final ambiguous in ['I', 'L', 'O', '0', '1']) {
        expect(setupCodeAlphabet.contains(ambiguous), isFalse);
      }
    });

    test('codes are effectively unique', () {
      final seen = <String>{};
      for (var i = 0; i < 200; i++) {
        expect(seen.add(generateSetupCode()), isTrue);
      }
    });
  });

  group('setupCodeMatches', () {
    const expected = 'AB2D-EF3H';

    test('accepts exact match', () {
      expect(setupCodeMatches(expected, 'AB2D-EF3H'), isTrue);
    });

    test('is case-insensitive', () {
      expect(setupCodeMatches(expected, 'ab2d-ef3h'), isTrue);
      expect(setupCodeMatches(expected, 'Ab2d-eF3H'), isTrue);
    });

    test('tolerates missing dashes and stray whitespace', () {
      expect(setupCodeMatches(expected, 'AB2DEF3H'), isTrue);
      expect(setupCodeMatches(expected, ' AB2D EF3H '), isTrue);
      expect(setupCodeMatches(expected, 'ab2d ef3h'), isTrue);
      expect(setupCodeMatches(expected, 'A B 2 D - E F 3 H'), isTrue);
    });

    test('rejects wrong, partial and empty input', () {
      expect(setupCodeMatches(expected, 'AB2D-EF3J'), isFalse);
      expect(setupCodeMatches(expected, 'AB2D'), isFalse);
      expect(setupCodeMatches(expected, 'AB2D-EF3H-AB2D'), isFalse);
      expect(setupCodeMatches(expected, ''), isFalse);
      expect(setupCodeMatches(expected, '  -  '), isFalse);
      expect(setupCodeMatches('', 'AB2D-EF3H'), isFalse);
    });

    test('works against generated codes', () {
      final code = generateSetupCode();
      expect(setupCodeMatches(code, code.toLowerCase()), isTrue);
      expect(
        setupCodeMatches(code, code.replaceAll('-', ' ')),
        isTrue,
      );
    });
  });
}
