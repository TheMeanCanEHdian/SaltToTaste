/// Common Latin diacritics and ligatures folded to plain ASCII, plus unicode
/// vulgar fractions expanded to their digit forms (the `/` then collapses to
/// `-` like every other non-alphanumeric run).
const Map<String, String> _foldings = {
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
  '¼': '1/4', '½': '1/2', '¾': '3/4',
  '⅓': '1/3', '⅔': '2/3',
  '⅕': '1/5', '⅖': '2/5', '⅗': '3/5', '⅘': '4/5',
  '⅙': '1/6', '⅚': '5/6',
  '⅛': '1/8', '⅜': '3/8', '⅝': '5/8', '⅞': '7/8',
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
