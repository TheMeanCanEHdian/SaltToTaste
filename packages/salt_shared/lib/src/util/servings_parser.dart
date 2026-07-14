import '../model/recipe.dart';
import 'quantity.dart';

/// Unicode vulgar-fraction characters that appear in corpus servings strings
/// (e.g. `MAKES 1½ CUPS`).
const String _fractionChars = '¼½¾⅓⅔⅕⅖⅗⅘⅙⅚⅐⅛⅜⅝⅞⅑⅒';

/// A numeric token: digits with an optional trailing vulgar fraction
/// (`12`, `2½`), or a vulgar fraction alone (`¼`).
const String _num = '(?:\\d+[$_fractionChars]?|[$_fractionChars])';

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

/// `SERVES 6`, `SERVES 6 TO 8`, `SERVES ABOUT 20`, `SERVING 6`,
/// `ENOUGH TO SERVE 4 TO 6` — anywhere in the string. Deliberately does not
/// match the noun `SERVINGS` (handled by [_servingsNounRe]).
final RegExp _servesRe = RegExp(
  '\\bSERV(?:ES|ING|E)\\b\\s+(?:ABOUT\\s+)?($_num)(?:\\s+TO\\s+($_num))?',
);

/// `... TWELVE 1-CUP SERVINGS`: a count (word or number) at most one token
/// before the noun `SERVINGS`.
final RegExp _servingsNounRe = RegExp(
  '\\b([A-Z]+|$_num)(?:\\s+\\S+)?\\s+SERVINGS\\b',
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
///   `MAKES 18 TAMALES; SERVES 6 TO 8` yields 6–8. Only the first clause
///   counts: `SERVES 4 AS A MAIN COURSE OR 6 AS AN APPETIZER` yields 4.
/// * `... TWELVE 1-CUP SERVINGS` yields the count before the noun.
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

Serves? _servingsNoun(String text) {
  for (final match in _servingsNounRe.allMatches(text)) {
    final serves = _buildServes(match.group(1)!, null);
    if (serves != null) return serves;
  }
  return null;
}

Serves? _makesClause(String text) {
  final match = _makesRe.firstMatch(text);
  if (match == null) return null;
  final serves = _buildServes(match.group(1)!, match.group(2));
  if (serves == null) return null;
  if (match.group(3) == null) return serves;
  return Serves(min: serves.min * 12, max: serves.max * 12);
}

Serves? _bareNumber(String text) {
  final match = _bareNumberRe.firstMatch(text);
  if (match == null) return null;
  return _buildServes(match.group(1)!, match.group(2));
}

Serves? _buildServes(String minToken, String? maxToken) {
  final minValue = _tokenValue(minToken);
  if (minValue == null) return null;
  final min = _count(minValue);
  var max = min;
  if (maxToken != null) {
    final maxValue = _tokenValue(maxToken);
    if (maxValue == null) return null;
    max = _count(maxValue);
  }
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
