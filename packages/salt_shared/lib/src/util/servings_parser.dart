import '../model/recipe.dart';
import 'quantity.dart';

/// Unicode vulgar-fraction characters that appear in corpus servings strings
/// (e.g. `MAKES 1½ CUPS`), shared with [parseQuantity] so the two parsers
/// always agree on the fraction vocabulary.
final String _fractionChars = vulgarFractionChars;

/// A numeric token: digits with an optional trailing vulgar fraction
/// (`12`, `2½`), or a vulgar fraction alone (`¼`).
final String _num = '(?:\\d+[$_fractionChars]?|[$_fractionChars])';

/// Number words that actually occur in the corpus servings vocabulary
/// (`MAKES TWO 12-INCH PIZZAS`, `MAKES ABOUT FORTY 2½-INCH COOKIES`),
/// padded out to a contiguous one-to-twenty range plus the tens.
const Map<String, int> _numberWords = {
  'ONE': 1,
  'TWO': 2,
  'THREE': 3,
  'FOUR': 4,
  'FIVE': 5,
  'SIX': 6,
  'SEVEN': 7,
  'EIGHT': 8,
  'NINE': 9,
  'TEN': 10,
  'ELEVEN': 11,
  'TWELVE': 12,
  'THIRTEEN': 13,
  'FOURTEEN': 14,
  'FIFTEEN': 15,
  'SIXTEEN': 16,
  'SEVENTEEN': 17,
  'EIGHTEEN': 18,
  'NINETEEN': 19,
  'TWENTY': 20,
  'THIRTY': 30,
  'FORTY': 40,
  'FIFTY': 50,
  'SIXTY': 60,
};

/// `SERVES 6`, `SERVES 6 TO 8`, `SERVES 4-6`, `SERVES 4–6`,
/// `SERVES ABOUT 20`, `SERVING 6`, `ENOUGH TO SERVE 4 TO 6` — anywhere in
/// the string. Deliberately does not match the noun `SERVINGS` (handled by
/// [_servingsNoun]).
final RegExp _servesRe = RegExp(
  '\\bSERV(?:ES|ING|E)\\b\\s+(?:ABOUT\\s+)?($_num)'
  '(?:(?:\\s+TO\\s+|\\s*[–-]\\s*)($_num))?',
);

/// Strips leading/trailing punctuation from a whitespace token, keeping
/// letters, digits, vulgar fractions, and interior punctuation
/// (`'SERVINGS.'` → `'SERVINGS'`, `'(12'` → `'12'`, `'1-CUP'` unchanged).
final RegExp _tokenTrim = RegExp(
  '^[^0-9A-Z$_fractionChars]+|[^0-9A-Z$_fractionChars]+\$',
);

/// `MAKES [ABOUT] [ENOUGH FOR] <count> [TO <count>] [DOZEN] ...` where
/// `<count>` is a number (`24`, `1½`, `¼`) or a number word (`FORTY`).
final RegExp _makesRe = RegExp(
  '\\bMAKES\\s+(?:ABOUT\\s+)?(?:ENOUGH\\s+FOR\\s+)?($_num|[A-Z]+)'
  '(?:\\s+TO\\s+($_num|[A-Z]+))?(\\s+DOZEN\\b)?',
);

/// Bare editor input: `4`, `4 TO 6`, `4-6`, `4–6`.
final RegExp _bareNumberRe = RegExp(
  '^($_num)(?:\\s*(?:TO|–|-)\\s*($_num))?\$',
);

/// Parses a verbatim servings string (e.g. `SERVES 6 TO 8`,
/// `MAKES 24 COOKIES`) into a numeric [Serves] yield.
///
/// Matching is case-insensitive and extracts the primary yield count:
///
/// * A `SERVES`/`SERVING`/`SERVE` clause anywhere in the string wins, so
///   `MAKES 18 TAMALES; SERVES 6 TO 8` yields 6–8. Ranges accept `TO`,
///   `-`, and `–` (`SERVES 4-6` yields 4–6). Only the first clause
///   counts: `SERVES 4 AS A MAIN COURSE OR 6 AS AN APPETIZER` yields 4.
/// * `... TWELVE 1-CUP SERVINGS` / `ABOUT 12 SERVINGS` / `4 TO 6 SERVINGS`
///   yield the count (or range) just before the noun.
/// * Otherwise the leading `MAKES [ABOUT] n ...` count is used, including
///   ranges (`MAKES 32 TO 40 PIECES`), number words
///   (`MAKES TWO 12-INCH PIZZAS`), `ENOUGH FOR` (`MAKES ENOUGH FOR ONE
///   9-INCH PIE`), and `DOZEN` as a ×12 multiplier (`MAKES 2 DOZEN 2-INCH
///   BROWNIES` yields 24).
/// * Pure quantities of volume or weight still return the leading number
///   (`MAKES ABOUT 4 CUPS` yields 4) — the serving basis is editable later.
///   Fractional counts round to the nearest integer with a floor of 1, so
///   `MAKES 1½ CUPS` yields 2 and `MAKES ABOUT ¼ CUP` yields 1.
///
/// Returns null when [text] is null, blank, or no count can be extracted.
Serves? parseServings(String? text) {
  if (text == null) return null;
  final normalized = text.trim().toUpperCase();
  if (normalized.isEmpty) return null;

  return _servesClause(normalized) ??
      _servingsNoun(normalized) ??
      _makesClause(normalized) ??
      _bareNumber(normalized);
}

Serves? _servesClause(String text) {
  final match = _servesRe.firstMatch(text);
  if (match == null) return null;
  return _buildServes(match.group(1)!, match.group(2));
}

/// `... TWELVE 1-CUP SERVINGS`, `ABOUT 12 SERVINGS`, `4 TO 6 SERVINGS`:
/// scans tokens for the noun `SERVINGS` and reads the count (number, range,
/// or number word) at most one descriptor token before it. A token scan is
/// used instead of a regex because a greedy word alternative would let a
/// non-count word (`ABOUT`) consume the span holding the real count.
Serves? _servingsNoun(String text) {
  final tokens = text.split(RegExp(r'\s+'));
  for (var i = 1; i < tokens.length; i++) {
    if (_cleanToken(tokens[i]) != 'SERVINGS') continue;
    for (var back = 1; back <= 2; back++) {
      final serves = _countEndingAt(tokens, i - back);
      if (serves != null) return serves;
    }
  }
  return null;
}

/// Reads a count that ends at [tokens]`[j]`: a range token (`4-6`), a plain
/// number or number word, or the upper bound of an `X TO Y` phrase.
Serves? _countEndingAt(List<String> tokens, int j) {
  if (j < 0) return null;
  final token = _cleanToken(tokens[j]);
  if (token == 'TO') return null;

  final range = _bareNumberRe.firstMatch(token);
  if (range != null && range.group(2) != null) {
    return _buildServes(range.group(1)!, range.group(2));
  }

  final value = _tokenValue(token);
  if (value == null) return null;

  // `4 TO 6 SERVINGS` — token j is the upper bound.
  if (j >= 2 && _cleanToken(tokens[j - 1]) == 'TO') {
    final lower = _tokenValue(_cleanToken(tokens[j - 2]));
    if (lower != null) return _servesFromValues(lower, value);
  }
  return _servesFromValues(value, null);
}

String _cleanToken(String token) => token.replaceAll(_tokenTrim, '');

Serves? _makesClause(String text) {
  final match = _makesRe.firstMatch(text);
  if (match == null) return null;
  final multiplier = match.group(3) == null ? 1 : 12;
  return _buildServes(match.group(1)!, match.group(2), multiplier: multiplier);
}

Serves? _bareNumber(String text) {
  final match = _bareNumberRe.firstMatch(text);
  if (match == null) return null;
  return _buildServes(match.group(1)!, match.group(2));
}

Serves? _buildServes(String minToken, String? maxToken, {int multiplier = 1}) {
  final minValue = _tokenValue(minToken);
  if (minValue == null) return null;
  double? maxValue;
  if (maxToken != null) {
    maxValue = _tokenValue(maxToken);
    if (maxValue == null) return null;
  }
  return _servesFromValues(minValue, maxValue, multiplier: multiplier);
}

/// Builds a [Serves] from raw numeric values, applying [multiplier] (e.g.
/// DOZEN ×12) BEFORE rounding so `1½ DOZEN` yields 18, not 24.
Serves _servesFromValues(double minValue, double? maxValue, {int multiplier = 1}) {
  final min = _count(minValue * multiplier);
  final max = _count((maxValue ?? minValue) * multiplier);
  return min <= max ? Serves(min: min, max: max) : Serves(min: max, max: min);
}

/// Resolves a token to a numeric value: a number word or a parseable number.
double? _tokenValue(String token) {
  final word = _numberWords[token];
  if (word != null) return word.toDouble();
  return parseQuantity(token);
}

/// Rounds a yield value to a whole count, never below 1.
int _count(double value) {
  final rounded = value.round();
  return rounded < 1 ? 1 : rounded;
}
