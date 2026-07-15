import 'package:salt_server/src/auth/tokens.dart';
import 'package:test/test.dart';

final _base64UrlBody = RegExp(r'^[A-Za-z0-9_-]{43}$');

void main() {
  test('sessionCookieName is stable', () {
    expect(sessionCookieName, 'stt_session');
  });

  group('generateOpaqueToken', () {
    test('is 43 chars of unpadded base64url', () {
      for (var i = 0; i < 100; i++) {
        final token = generateOpaqueToken();
        expect(token, matches(_base64UrlBody));
        expect(token, isNot(contains('=')));
      }
    });

    test('never repeats', () {
      final seen = <String>{};
      for (var i = 0; i < 1000; i++) {
        expect(seen.add(generateOpaqueToken()), isTrue);
      }
    });
  });

  group('generatePat', () {
    test('token is marker + 43-char body; prefix is first 12 body chars', () {
      final pat = generatePat();
      expect(pat.token, startsWith('stt_pat_'));
      expect(pat.token.length, 'stt_pat_'.length + 43);
      expect(pat.token.substring('stt_pat_'.length), matches(_base64UrlBody));
      expect(pat.prefix.length, 12);
      expect(
        pat.prefix,
        pat.token.substring('stt_pat_'.length, 'stt_pat_'.length + 12),
      );
    });

    test('tokens and prefixes are unique across generations', () {
      final tokens = <String>{};
      final prefixes = <String>{};
      for (var i = 0; i < 500; i++) {
        final pat = generatePat();
        expect(tokens.add(pat.token), isTrue);
        // 12 base64url chars = 72 bits; collisions here would be a bug.
        expect(prefixes.add(pat.prefix), isTrue);
      }
    });
  });

  group('hashToken', () {
    test('is deterministic', () {
      final token = generateOpaqueToken();
      expect(hashToken(token), hashToken(token));
    });

    test('matches the SHA-256 known-answer vector', () {
      // FIPS 180-2 test vector: sha256("abc").
      expect(
        hashToken('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('is 64 lowercase hex chars and input-sensitive', () {
      final a = hashToken(generateOpaqueToken());
      final b = hashToken(generateOpaqueToken());
      expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(a, isNot(b));
    });
  });

  group('looksLikePat', () {
    test('accepts generated PATs', () {
      expect(looksLikePat(generatePat().token), isTrue);
    });

    test('rejects session tokens and near-misses', () {
      expect(looksLikePat(generateOpaqueToken()), isFalse);
      expect(looksLikePat(''), isFalse);
      expect(looksLikePat('stt_pat_'), isFalse);
      expect(looksLikePat('stt_pat_tooshort'), isFalse);
      expect(looksLikePat('stt_pat_${'A' * 44}'), isFalse); // too long
      expect(looksLikePat('stt_pat_${'A' * 42}!'), isFalse); // bad charset
      expect(looksLikePat('STT_PAT_${'A' * 43}'), isFalse); // wrong case
    });
  });
}
