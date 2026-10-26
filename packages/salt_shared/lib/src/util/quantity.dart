/// ASCII spelling of every supported unicode vulgar-fraction code point
/// (`'½'` → `'1/2'`) — the corpus house style for quantity strings.
const Map<String, String> vulgarFractionAscii = {
  '¼': '1/4',
  '½': '1/2',
  '¾': '3/4',
  '⅓': '1/3',
  '⅔': '2/3',
  '⅕': '1/5',
  '⅖': '2/5',
  '⅗': '3/5',
  '⅘': '4/5',
  '⅙': '1/6',
  '⅚': '5/6',
  '⅐': '1/7',
  '⅛': '1/8',
  '⅜': '3/8',
  '⅝': '5/8',
  '⅞': '7/8',
  '⅑': '1/9',
  '⅒': '1/10',
};

/// Numeric value of every supported unicode vulgar-fraction code point.
/// Derived from [vulgarFractionAscii] so the two can never drift apart.
final Map<String, double> _vulgarFractions = vulgarFractionAscii.map((
  char,
  ascii,
) {
  final parts = ascii.split('/');
  return MapEntry(char, int.parse(parts[0]) / int.parse(parts[1]));
});

/// Every unicode vulgar-fraction character [parseQuantity] understands,
/// as a single string suitable for regex character classes. Derived from
/// [vulgarFractionAscii] so the two can never drift apart.
final String vulgarFractionChars = vulgarFractionAscii.keys.join();

final RegExp _wholeNumber = RegExp(r'^\d+$');
final RegExp _asciiFraction = RegExp(r'^(?:(\d+)\s+)?(\d+)\s*/\s*(\d+)$');
final RegExp _decimal = RegExp(r'^(?:\d+(?:\.\d+)?|\.\d+)$');

/// The largest quantity [parseQuantity] reads: a billion of any unit is no
/// recipe's (v81, Run 065/066 F14 — a longer digit run overflowed
/// `int.parse`, a FormatException, or read to Infinity grams, and either
/// crashed the server's compute and its matches GET on text the editor
/// accepts). Anything larger parses to null: an unmeasured amount.
const double maxQuantity = 1e9;

/// Parses a corpus quantity string to its numeric value.
///
/// Accepts integers (`'2'`), ASCII fractions (`'1/2'`), mixed numbers
/// (`'4 1/4'`), unicode vulgar fractions standalone (`'¼'`) or mixed
/// (`'1¾'`, `'1 ¾'`), and plain decimals (`'1.5'`). Leading/trailing
/// whitespace is ignored. Returns null for anything else — in particular,
/// ranges are not quantities and do not parse — and for any value above
/// [maxQuantity] (a whole, numerator or denominator past it included).
double? parseQuantity(String text) {
  final value = _parseQuantity(text);
  return value == null || !(value <= maxQuantity) ? null : value;
}

/// A digit run as a number, null past [maxQuantity] (never an overflow).
double? _digits(String digits) {
  final n = int.tryParse(digits);
  return n == null || n > maxQuantity ? null : n.toDouble();
}

double? _parseQuantity(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;

  // Unicode vulgar fraction, standalone ('¼') or mixed ('1¾', '1 ¾').
  final lastChar = trimmed.substring(trimmed.length - 1);
  final vulgar = _vulgarFractions[lastChar];
  if (vulgar != null) {
    final whole = trimmed.substring(0, trimmed.length - 1).trimRight();
    if (whole.isEmpty) return vulgar;
    if (!_wholeNumber.hasMatch(whole)) return null;
    final n = _digits(whole);
    return n == null ? null : n + vulgar;
  }

  // ASCII fraction ('1/2') or mixed number ('4 1/4').
  final fraction = _asciiFraction.firstMatch(trimmed);
  if (fraction != null) {
    final whole = fraction.group(1);
    final numerator = _digits(fraction.group(2)!);
    final denominator = _digits(fraction.group(3)!);
    final n = whole == null ? 0.0 : _digits(whole);
    if (numerator == null || denominator == null || n == null) return null;
    if (denominator == 0) return null;
    return n + numerator / denominator;
  }

  // Integer ('2') or plain decimal ('1.5').
  if (_decimal.hasMatch(trimmed)) return double.parse(trimmed);
  return null;
}

/// A share of a child recipe as the copy writes it (v41): whole numbers
/// bare ("1", "2"), a fraction by its vulgar character, mixed or not ("⅔",
/// "1½") when one lies within 1e-3, else two decimals ("0.38"). One rule for
/// the server's `share_text` and any client echo.
String shareText(double share) {
  final whole = share.floor();
  final rest = share - whole;
  if (rest < 1e-3) {
    return '$whole';
  }
  if (1 - rest < 1e-3) {
    return '${whole + 1}';
  }
  for (final MapEntry(key: char, value: value) in _vulgarFractions.entries) {
    if ((rest - value).abs() < 1e-3) {
      return whole == 0 ? char : '$whole$char';
    }
  }
  return share.toStringAsFixed(2);
}
