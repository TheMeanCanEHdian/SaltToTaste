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
final Map<String, double> _vulgarFractions = vulgarFractionAscii.map(
  (char, ascii) {
    final parts = ascii.split('/');
    return MapEntry(char, int.parse(parts[0]) / int.parse(parts[1]));
  },
);

/// Every unicode vulgar-fraction character [parseQuantity] understands,
/// as a single string suitable for regex character classes. Derived from
/// [vulgarFractionAscii] so the two can never drift apart.
final String vulgarFractionChars = vulgarFractionAscii.keys.join();

final RegExp _wholeNumber = RegExp(r'^\d+$');
final RegExp _asciiFraction = RegExp(r'^(?:(\d+)\s+)?(\d+)\s*/\s*(\d+)$');
final RegExp _decimal = RegExp(r'^(?:\d+(?:\.\d+)?|\.\d+)$');
final RegExp _trailingZeros = RegExp(r'0+$');
final RegExp _trailingDot = RegExp(r'\.$');

/// Parses a corpus quantity string to its numeric value.
///
/// Accepts integers (`'2'`), ASCII fractions (`'1/2'`), mixed numbers
/// (`'4 1/4'`), unicode vulgar fractions standalone (`'¼'`) or mixed
/// (`'1¾'`, `'1 ¾'`), and plain decimals (`'1.5'`). Leading/trailing
/// whitespace is ignored. Returns null for anything else — in particular,
/// ranges are not quantities and do not parse.
double? parseQuantity(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;

  // Unicode vulgar fraction, standalone ('¼') or mixed ('1¾', '1 ¾').
  final lastChar = trimmed.substring(trimmed.length - 1);
  final vulgar = _vulgarFractions[lastChar];
  if (vulgar != null) {
    final whole = trimmed.substring(0, trimmed.length - 1).trimRight();
    if (whole.isEmpty) return vulgar;
    if (!_wholeNumber.hasMatch(whole)) return null;
    return int.parse(whole) + vulgar;
  }

  // ASCII fraction ('1/2') or mixed number ('4 1/4').
  final fraction = _asciiFraction.firstMatch(trimmed);
  if (fraction != null) {
    final whole = fraction.group(1);
    final numerator = int.parse(fraction.group(2)!);
    final denominator = int.parse(fraction.group(3)!);
    if (denominator == 0) return null;
    return (whole == null ? 0 : int.parse(whole)) + numerator / denominator;
  }

  // Integer ('2') or plain decimal ('1.5').
  if (_decimal.hasMatch(trimmed)) return double.parse(trimmed);
  return null;
}

/// Formats a numeric quantity for display in the editor.
///
/// Whole values render as bare integers (`'2'`). Other values render as the
/// nearest "nice" fraction — halves, thirds, quarters, or eighths — in ASCII
/// mixed-number form (`'1 3/4'`). When no such fraction is within 1% relative
/// error of [value], falls back to a decimal trimmed to at most three places.
String formatQuantity(double value) {
  if (!value.isFinite) return value.toString();
  if (value < 0) return '-${formatQuantity(-value)}';

  final nearestInt = value.round();
  if ((value - nearestInt).abs() < 1e-9) return nearestInt.toString();

  double? bestError;
  var bestNumerator = 0;
  var bestDenominator = 1;
  for (final denominator in const [2, 3, 4, 8]) {
    final numerator = (value * denominator).round();
    if (numerator == 0) continue;
    final error = (numerator / denominator - value).abs() / value;
    if (bestError == null || error < bestError) {
      bestError = error;
      bestNumerator = numerator;
      bestDenominator = denominator;
    }
  }
  if (bestError != null && bestError <= 0.01) {
    final divisor = _gcd(bestNumerator, bestDenominator);
    final denominator = bestDenominator ~/ divisor;
    var numerator = bestNumerator ~/ divisor;
    final whole = numerator ~/ denominator;
    numerator -= whole * denominator;
    if (numerator == 0) return whole.toString();
    final fraction = '$numerator/$denominator';
    return whole == 0 ? fraction : '$whole $fraction';
  }

  var text = value.toStringAsFixed(3);
  text = text.replaceFirst(_trailingZeros, '');
  text = text.replaceFirst(_trailingDot, '');
  return text;
}

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);
