import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Hashes and verifies passwords with Argon2id (RFC 9106), stored as PHC
/// strings: `$argon2id$v=19$m=19456,t=2,p=1$<b64salt>$<b64hash>`.
///
/// Defaults follow the OWASP Password Storage Cheat Sheet first-choice
/// parameters (19 MiB memory, 2 iterations, 1 lane). [verify] honours the
/// parameters embedded in the stored string, so old hashes keep verifying
/// after the defaults change.
///
/// Pure service: no I/O, no logging (PHC strings and passwords are secrets
/// and must never be logged by callers either).
class PasswordHasher {
  /// Creates a hasher. [random] is injectable for tests; production code
  /// uses a CSPRNG ([Random.secure]).
  PasswordHasher({Random? random}) : _random = random ?? Random.secure();

  /// Argon2id memory cost in KiB (19 MiB, OWASP recommendation).
  static const int memoryKib = 19456;

  /// Argon2id iteration count (`t`).
  static const int iterations = 2;

  /// Argon2id lane count (`p`).
  static const int parallelism = 1;

  /// Salt length in bytes.
  static const int saltLength = 16;

  /// Derived hash length in bytes.
  static const int hashLength = 32;

  // Upper bounds accepted when *verifying* a stored PHC string. Protects
  // against a corrupted/hostile row turning verification into a memory bomb.
  static const int _maxMemoryKib = 1 << 22; // 4 GiB
  static const int _maxIterations = 64;
  static const int _maxParallelism = 64;

  /// Fixed hash of an unknown, discarded random password. Used by
  /// [dummyVerify] so that login attempts against nonexistent usernames cost
  /// the same as attempts against real ones (no timing oracle).
  static const String _dummyPhc =
      r'$argon2id$v=19$m=19456,t=2,p=1'
      r'$YSa5N2IXyyvXK6jihRf+gQ$IobwD7L4prH4QbmTo5F7mV9ep12GvFQAyBTF6lH6gGg';

  final Random _random;

  /// Hashes [password] with a fresh random salt and the current default
  /// parameters, returning a PHC-formatted string.
  Future<String> hash(String password) async {
    final salt =
        List<int>.generate(saltLength, (_) => _random.nextInt(256));
    final algorithm = Argon2id(
      memory: memoryKib,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: hashLength,
    );
    final key = await algorithm.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final derived = await key.extractBytes();
    return r'$argon2id$v=19'
        '\$m=$memoryKib,t=$iterations,p=$parallelism'
        '\$${_base64NoPad(salt)}'
        '\$${_base64NoPad(derived)}';
  }

  /// Verifies [password] against [phcString].
  ///
  /// Recomputes the hash using the salt and parameters embedded in the
  /// string (they may differ from the current defaults) and compares in
  /// constant time. Returns `false` for malformed input; never throws.
  Future<bool> verify(String password, String phcString) async {
    try {
      final parsed = _parsePhc(phcString);
      if (parsed == null) return false;
      final algorithm = Argon2id(
        memory: parsed.memory,
        iterations: parsed.iterations,
        parallelism: parsed.parallelism,
        hashLength: parsed.hash.length,
      );
      final key = await algorithm.deriveKeyFromPassword(
        password: password,
        nonce: parsed.salt,
      );
      final computed = await key.extractBytes();
      return _constantTimeEquals(computed, parsed.hash);
    } on Object {
      // Malformed input must yield false, not an exception (and certainly
      // not an error message that echoes hash material).
      return false;
    }
  }

  /// Burns the same CPU/memory as a real [verify] against a baked-in hash,
  /// discarding the result. Call this when the username does not exist so
  /// unknown-user logins are not detectable by response timing.
  Future<void> dummyVerify(String password) async {
    await verify(password, _dummyPhc);
  }

  // ---------------------------------------------------------------------
  // PHC parsing
  // ---------------------------------------------------------------------

  ({int memory, int iterations, int parallelism, List<int> salt,
      List<int> hash})? _parsePhc(String phcString) {
    // Expected: '' / 'argon2id' / 'v=19' / 'm=..,t=..,p=..' / salt / hash
    final parts = phcString.split(r'$');
    if (parts.length != 6 || parts[0].isNotEmpty) return null;
    if (parts[1] != 'argon2id') return null;
    if (parts[2] != 'v=19') return null;

    final params = <String, int>{};
    for (final pair in parts[3].split(',')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) return null;
      final value = int.tryParse(pair.substring(eq + 1));
      if (value == null || value < 1) return null;
      params[pair.substring(0, eq)] = value;
    }
    final memory = params['m'];
    final iterations = params['t'];
    final parallelism = params['p'];
    if (memory == null || iterations == null || parallelism == null ||
        params.length != 3) {
      return null;
    }
    if (memory > _maxMemoryKib ||
        iterations > _maxIterations ||
        parallelism > _maxParallelism ||
        memory < 8 * parallelism) {
      return null;
    }

    final salt = _base64NoPadDecode(parts[4]);
    final hash = _base64NoPadDecode(parts[5]);
    if (salt == null || hash == null) return null;
    if (salt.length < 8 || hash.length < 12) return null;
    return (
      memory: memory,
      iterations: iterations,
      parallelism: parallelism,
      salt: salt,
      hash: hash,
    );
  }

  /// Standard base64 without `=` padding, per the PHC string format.
  static String _base64NoPad(List<int> bytes) =>
      base64.encode(bytes).replaceAll('=', '');

  static List<int>? _base64NoPadDecode(String input) {
    // PHC B64 never contains padding; reject it rather than normalize it so
    // each hash has exactly one encoding.
    if (input.isEmpty || input.contains('=')) return null;
    final padding = (4 - input.length % 4) % 4;
    final padded = input.padRight(input.length + padding, '=');
    try {
      return base64.decode(padded);
    } on FormatException {
      return null;
    }
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    var diff = a.length ^ b.length;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i % (b.isEmpty ? 1 : b.length)];
    }
    return diff == 0;
  }
}
