import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:salt_server/src/auth/setup_code.dart';
import 'package:salt_server/src/db/salt_database.dart';

/// Settings-table key holding the pending account-recovery code.
///
/// The value is `<sha256-hex>:<expiry-iso8601-utc>` — only a digest of the
/// [normalizeSetupCode] form, never the code itself: `bin/recover.dart`
/// issues the code in one process and the server verifies it in another, so
/// it has to survive at rest, and anything that can read the settings table
/// must not be able to read a live recovery code out of it.
const String recoveryCodeSetting = 'auth.recovery_code';

/// How long an issued recovery code stays usable. Short by design: the code
/// is printed to the console and the operator is standing right there.
const Duration recoveryCodeLifetime = Duration(minutes: 15);

/// Outcome of checking a provided recovery code.
enum RecoveryCodeStatus {
  /// No code has been issued, or the issued one expired — nothing to match
  /// against (403: recovery is not open).
  unavailable,

  /// A code is pending but the provided one is not it (422: bad input).
  invalid,

  /// The provided code matches the pending, unexpired code.
  valid,
}

/// How many 4-character groups a recovery code carries: 12 characters over a
/// 31-symbol alphabet, ~59 bits.
///
/// Longer than the first-boot setup code's 8 characters (~40 bits), and
/// deliberately so. This code GRANTS ADMIN, and the storage below is an
/// unsalted SHA-256 — which is the right choice for a high-entropy secret and
/// the wrong one for a guessable one. 40 bits was the weak part, not the
/// hash, so the fix is entropy rather than a slow KDF: argon2id here would
/// cost 19 MiB per attempt to defend a code that lives 15 minutes, and would
/// not change what an ONLINE guesser faces at all.
const int recoveryCodeGroups = 3;

/// Issues a fresh single-use recovery code, persists its digest and expiry,
/// and returns the plaintext for the CLI to print.
///
/// Replaces any code already pending: the operator at the console is the
/// only party who can be running this, and the newest code wins.
/// [now] overrides the clock (tests).
String issueRecoveryCode(SaltDatabase db, {DateTime? now}) {
  final code = generateSetupCode(groups: recoveryCodeGroups);
  final expiresAt = (now ?? DateTime.now().toUtc()).toUtc().add(
    recoveryCodeLifetime,
  );
  db.setSetting(
    recoveryCodeSetting,
    '${_digest(code)}:${expiresAt.toIso8601String()}',
  );
  return code;
}

/// Checks [provided] against the pending recovery code.
///
/// An expired (or unparseable) record is treated as absent and cleaned up on
/// the way out, so a stale row can never be matched. [now] overrides the
/// clock (tests).
RecoveryCodeStatus checkRecoveryCode(
  SaltDatabase db,
  String provided, {
  DateTime? now,
}) {
  final record = db.getSetting(recoveryCodeSetting);
  if (record == null) {
    return RecoveryCodeStatus.unavailable;
  }
  // The digest is hex, so the first colon is the separator (the ISO expiry
  // has colons of its own).
  final separator = record.indexOf(':');
  if (separator < 0) {
    clearRecoveryCode(db);
    return RecoveryCodeStatus.unavailable;
  }
  final expiresAt = DateTime.tryParse(record.substring(separator + 1));
  if (expiresAt == null ||
      !expiresAt.isAfter((now ?? DateTime.now().toUtc()).toUtc())) {
    clearRecoveryCode(db);
    return RecoveryCodeStatus.unavailable;
  }
  // Both sides are hex digests of the normalized code: same alphabet, same
  // length, no dashes or spaces — so setupCodeMatches' case-folding is a
  // no-op here and what it actually contributes is its non-short-circuiting
  // compare. Reused rather than re-implemented on purpose.
  final expected = record.substring(0, separator);
  return setupCodeMatches(expected, _digest(provided))
      ? RecoveryCodeStatus.valid
      : RecoveryCodeStatus.invalid;
}

/// Consumes (clears) the pending recovery code. Single use: call this the
/// moment a code is accepted, before anything is changed.
void clearRecoveryCode(SaltDatabase db) =>
    db.deleteSetting(recoveryCodeSetting);

String _digest(String code) =>
    sha256.convert(utf8.encode(normalizeSetupCode(code))).toString();
