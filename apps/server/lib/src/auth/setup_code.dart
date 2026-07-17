import 'dart:math';

/// Alphabet for setup codes: no I/L/O/0/1, so codes read unambiguously from
/// a server log.
const String setupCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

final Random _secureRandom = Random.secure();

/// Generates a code of [groups] dash-separated 4-character groups from
/// [setupCodeAlphabet] using a CSPRNG.
///
/// Entropy is `log2(31^(4 * groups))`: 2 groups ~40 bits, 3 groups ~59 bits.
/// The alphabet is deliberately 31 symbols (no I/L/O/0/1) so a code read off
/// a terminal cannot be mistyped into a different valid one; length, not
/// alphabet, is the knob for entropy.
String generateSetupCode({int groups = 2}) {
  String group() => String.fromCharCodes(
    List<int>.generate(
      4,
      (_) => setupCodeAlphabet.codeUnitAt(
        _secureRandom.nextInt(setupCodeAlphabet.length),
      ),
    ),
  );
  return List<String>.generate(groups, (_) => group()).join('-');
}

/// Whether [provided] matches [expected], ignoring case, dashes and
/// whitespace, using a comparison that does not short-circuit on the first
/// differing character.
bool setupCodeMatches(String expected, String provided) {
  final a = normalizeSetupCode(expected);
  final b = normalizeSetupCode(provided);
  if (a.isEmpty || b.isEmpty) return false;
  var diff = a.length ^ b.length;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i % b.length);
  }
  return diff == 0;
}

/// The comparison form of [code]: upper-cased with dashes and whitespace
/// removed, so how the operator retypes a code never matters.
///
/// Anything that persists a *digest* of a code (see `recovery.dart`) must
/// digest this form — the same code typed two ways has to hash the same.
String normalizeSetupCode(String code) =>
    code.toUpperCase().replaceAll(RegExp(r'[-\s]'), '');
