import 'package:salt_shared/salt_shared.dart' show vulgarFractionAscii;

/// Common Latin diacritics and ligatures folded to plain ASCII. Unicode
/// vulgar fractions come from salt_shared's [vulgarFractionAscii] — derived,
/// not copied, so the two can never drift apart (a hand-copied table here
/// once went stale, missing ⅐/⅑/⅒ — review S2). The fraction's `/` then
/// collapses to `-` like every other non-alphanumeric run.
final Map<String, String> _foldings = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
  'æ': 'ae',
  'ç': 'c', 'ć': 'c', 'č': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ę': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
  'ñ': 'n', 'ń': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o',
  'œ': 'oe',
  'š': 's', 'ß': 'ss',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u',
  'ý': 'y', 'ÿ': 'y',
  'ž': 'z', 'ź': 'z', 'ż': 'z',
  ...vulgarFractionAscii,
  // Apostrophes vanish entirely ("America's" -> "americas") instead of
  // splitting the word.
  "'": '', '’': '', 'ʼ': '',
};

final RegExp _nonAlphanumericRun = RegExp('[^a-z0-9]+');
final RegExp _edgeDashes = RegExp(r'^-+|-+$');

/// Converts [text] into a URL-safe slug.
///
/// Lowercases, folds common diacritics/ligatures to ASCII, expands unicode
/// vulgar fractions (`½` -> `1-2`), drops apostrophes, collapses every other
/// run of non-`[a-z0-9]` characters to a single `-`, and trims leading and
/// trailing dashes. Characters with no trivial ASCII folding (e.g. CJK)
/// collapse into the surrounding dash run.
String slugify(String text) {
  final folded = StringBuffer();
  for (final char in text.toLowerCase().split('')) {
    folded.write(_foldings[char] ?? char);
  }
  return folded
      .toString()
      .replaceAll(_nonAlphanumericRun, '-')
      .replaceAll(_edgeDashes, '');
}
