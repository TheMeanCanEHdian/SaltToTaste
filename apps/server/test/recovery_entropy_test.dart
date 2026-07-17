import 'dart:io';
import 'dart:math';

import 'package:salt_server/src/auth/recovery.dart';
import 'package:salt_server/src/auth/setup_code.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:test/test.dart';

/// The recovery code grants admin and is stored as an unsalted SHA-256 — which
/// is correct for a HIGH-ENTROPY secret and wrong for a guessable one. It used
/// to be the setup code's 8 characters (~40 bits), so the entropy was the weak
/// part, not the hash. These pin the length, because nothing else would notice
/// it shrinking back.
void main() {
  double bitsOf(int chars) => chars * (log(setupCodeAlphabet.length) / log(2));

  test('the code ISSUED to an operator carries ~59 bits', () {
    // Through issueRecoveryCode, not generateSetupCode: the constant and the
    // issuer are different things, and only the issuer's output is what an
    // operator actually types. Asserting on the generator alone let the real
    // code shrink to 8 characters with this file green.
    final tempDir = Directory.systemTemp.createTempSync('salt_recovery_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${tempDir.path}/salt.db');
    addTearDown(db.dispose);

    final code = issueRecoveryCode(db);
    final stripped = code.replaceAll('-', '');
    expect(stripped.length, 12);
    expect(code, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$')));
    expect(
      bitsOf(stripped.length),
      greaterThan(55),
      reason: 'measured ${bitsOf(stripped.length).toStringAsFixed(1)} bits',
    );

    // And it round-trips: a length change that broke redemption would be a
    // worse bug than the entropy it bought.
    expect(
      checkRecoveryCode(db, code),
      RecoveryCodeStatus.valid,
      reason: 'the issued code must actually be redeemable',
    );
  });

  test('the first-boot setup code is deliberately still 8 characters', () {
    // Not an oversight: it is consumed once, at first boot, before any user
    // exists. Only the admin-granting recovery code was lengthened.
    final code = generateSetupCode();
    expect(code.replaceAll('-', '').length, 8);
  });

  test('the alphabet stays unambiguous — length is the entropy knob', () {
    // I/L/O/0/1 are excluded so a code read off a terminal cannot be mistyped
    // into a DIFFERENT valid code. Re-adding them would be the wrong way to
    // buy entropy.
    for (final ambiguous in ['I', 'L', 'O', '0', '1']) {
      expect(
        setupCodeAlphabet,
        isNot(contains(ambiguous)),
        reason: '$ambiguous is easy to misread',
      );
    }
    expect(setupCodeAlphabet.length, 31);
  });

  test('codes do not repeat', () {
    final seen = {for (var i = 0; i < 200; i++) generateSetupCode(groups: 3)};
    expect(seen, hasLength(200), reason: 'CSPRNG, not a counter');
  });
}
