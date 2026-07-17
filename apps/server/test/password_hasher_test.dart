import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:salt_server/src/auth/password_hasher.dart';
import 'package:test/test.dart';

// Synthesized credentials: auth inputs cannot come from the recipe corpus.
const _password = 'plum-Torte_Battery-91!';

/// PHC string produced once by this implementation (cryptography 2.9.0,
/// OWASP params) for the password below — pins the output across package
/// and platform upgrades.
const _knownPassword = 'correct horse battery staple';
const _knownPhc =
    r'$argon2id$v=19$m=19456,t=2,p=1'
    r'$c2FsdC10by10YXN0ZS12Mg$ZcvQ66hAFnOYGst1nsWjj1x3yG9y+4Ax8QTOW2IjPpQ';

final _phcPattern = RegExp(
  r'^\$argon2id\$v=19\$m=19456,t=2,p=1'
  r'\$[A-Za-z0-9+/]{22}\$[A-Za-z0-9+/]{43}$',
);

void main() {
  final hasher = PasswordHasher();

  group('hash', () {
    test(
      'produces a PHC string with OWASP params and unpadded base64',
      () async {
        final phc = await hasher.hash(_password);
        expect(phc, matches(_phcPattern));
      },
    );

    test(
      'salts randomly: same password, different hashes, both verify',
      () async {
        final first = await hasher.hash(_password);
        final second = await hasher.hash(_password);
        expect(first, isNot(second));
        expect(await hasher.verify(_password, first), isTrue);
        expect(await hasher.verify(_password, second), isTrue);
      },
    );
  });

  group('verify', () {
    test('roundtrip accepts the original password', () async {
      final phc = await hasher.hash(_password);
      expect(await hasher.verify(_password, phc), isTrue);
    });

    test('rejects a wrong password', () async {
      final phc = await hasher.hash(_password);
      expect(await hasher.verify('plum-Torte_Battery-92!', phc), isFalse);
      expect(await hasher.verify('', phc), isFalse);
    });

    test('known vector: baked PHC still verifies', () async {
      expect(await hasher.verify(_knownPassword, _knownPhc), isTrue);
      expect(await hasher.verify('incorrect horse', _knownPhc), isFalse);
    });

    test('honours embedded params that differ from current defaults', () async {
      // Build a valid PHC string with non-default (cheap) params directly
      // from the algorithm, then check verify() reproduces it.
      const salt = [7, 6, 5, 4, 3, 2, 1, 0, 0, 1, 2, 3, 4, 5, 6, 7];
      final algorithm = Argon2id(
        memory: 64,
        iterations: 3,
        parallelism: 2,
        hashLength: 16,
      );
      final key = await algorithm.deriveKeyFromPassword(
        password: _password,
        nonce: salt,
      );
      final derived = await key.extractBytes();
      String b64(List<int> bytes) => base64.encode(bytes).replaceAll('=', '');
      final phc =
          '\$argon2id\$v=19\$m=64,t=3,p=2\$${b64(salt)}\$${b64(derived)}';
      expect(await hasher.verify(_password, phc), isTrue);
      expect(await hasher.verify('wrong', phc), isFalse);
    });

    test('returns false (never throws) on malformed PHC strings', () async {
      final salt = 'A' * 22; // 16 bytes, unpadded base64
      final digest = 'A' * 43; // 32 bytes, unpadded base64
      final malformed = <String, String>{
        'empty': '',
        'garbage': 'not a phc string',
        'wrong algorithm': '\$argon2i\$v=19\$m=19456,t=2,p=1\$$salt\$$digest',
        'wrong version': '\$argon2id\$v=18\$m=19456,t=2,p=1\$$salt\$$digest',
        'missing p': '\$argon2id\$v=19\$m=19456,t=2\$$salt\$$digest',
        'extra param': '\$argon2id\$v=19\$m=19456,t=2,p=1,x=9\$$salt\$$digest',
        'non-numeric m': '\$argon2id\$v=19\$m=abc,t=2,p=1\$$salt\$$digest',
        'zero memory': '\$argon2id\$v=19\$m=0,t=2,p=1\$$salt\$$digest',
        'm below 8p': '\$argon2id\$v=19\$m=4,t=2,p=1\$$salt\$$digest',
        'memory bomb':
            '\$argon2id\$v=19\$m=999999999999,t=2,p=1\$$salt\$$digest',
        'bad base64 salt': '\$argon2id\$v=19\$m=19456,t=2,p=1\$!!!!\$$digest',
        'padded base64 salt':
            '\$argon2id\$v=19\$m=19456,t=2,p=1\$$salt==\$$digest',
        'empty hash': '\$argon2id\$v=19\$m=19456,t=2,p=1\$$salt\$',
        'hash too short': '\$argon2id\$v=19\$m=19456,t=2,p=1\$$salt\$AAAA',
        'missing hash section': '\$argon2id\$v=19\$m=19456,t=2,p=1\$$salt',
        'too many sections': r'$argon2id$v=19$m=19456,t=2,p=1$a$b$c$d',
        'leading junk': 'x\$argon2id\$v=19\$m=19456,t=2,p=1\$$salt\$$digest',
      };
      for (final entry in malformed.entries) {
        expect(
          await hasher.verify(_password, entry.value),
          isFalse,
          reason: 'should reject ${entry.key}: ${entry.value}',
        );
      }
    });
  });

  group('dummyVerify', () {
    test('completes without throwing for arbitrary input', () async {
      await hasher.dummyVerify(_password);
      await hasher.dummyVerify('');
    });
  });

  group('underlying Argon2id implementation', () {
    test('matches the RFC 9106 section 5.3 Argon2id test vector', () async {
      final algorithm = Argon2id(
        memory: 32,
        iterations: 3,
        parallelism: 4,
        hashLength: 32,
      );
      final key = await algorithm.deriveKey(
        secretKey: SecretKey(List.filled(32, 0x01)),
        nonce: List.filled(16, 0x02),
        optionalSecret: List.filled(8, 0x03),
        associatedData: List.filled(12, 0x04),
      );
      final tag = await key.extractBytes();
      final hex = tag.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(
        hex,
        '0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659',
      );
    });
  });
}
