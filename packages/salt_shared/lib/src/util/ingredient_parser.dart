import '../model/recipe.dart';
import 'quantity.dart';

/// How much a [ParsedIngredient] should be trusted.
///
/// Drives the recipe editor's per-line chips and the legacy importer's
/// review routing.
enum ParseConfidence {
  /// Clean split — safe to accept as-is.
  parsed,

  /// Amounts were found but the line hit a known-hard shape (a leading
  /// `(14.5-ounce)` size descriptor, an `or` alternative, a missing item,
  /// a unit-like token the vocabulary doesn't recognize) — show the result
  /// but ask a human to check it.
  check,

  /// No amounts on the line (`Confectioners' sugar, for dusting`,
  /// `Salt and pepper`) — item/prep may still be filled in.
  none,
}

/// Result of parsing one raw ingredient line with [parseIngredientLine].
///
/// The raw line itself is not repeated here — callers pair the result with
/// the line they passed in (see [IngredientLine], which keeps `raw` verbatim
/// next to these fields).
class ParsedIngredient {
  const ParsedIngredient({
    this.amounts = const [],
    this.item,
    this.prep,
    required this.confidence,
  });

  /// 0, 1, or 2 amounts; dual lines (`1¾ cups (8¾ ounces) flour`) carry the
  /// as-listed measure flagged primary plus its equivalent.
  final List<Amount> amounts;

  /// The ingredient name (text before the first top-level comma), with any
  /// leading parenthetical size descriptor re-attached
  /// (`(15-ounce) chickpeas`).
  final String? item;

  /// Prep instructions (text after the item/prep comma boundary).
  final String? prep;

  final ParseConfidence confidence;
}

/// Splits a raw ingredient line (`1¾ cups (8¾ ounces) unbleached
/// all-purpose flour`) into structured [Amount]s, item, and prep.
///
/// This is a port of the Recipe Extraction project's Python
/// `ingredient_parser` — the module that produced the corpus — so its output
/// agrees with the stored corpus extraction on >99% of the 16,510 real
/// ingredient lines (see `test/ingredient_parser_test.dart` for the measured
/// rates). It deliberately improves on the extractor in one place: the
/// extractor could not match multi-word units, so the corpus stores its
/// seven `fluid ounce` lines misparsed (count, unit glued to the item);
/// this parser reads them correctly. The semantics, in the order applied:
///
/// * **Quantity** — a leading number in any corpus spelling: integer (`12`),
///   decimal, ASCII or unicode fraction (`3/4`, `¾`), mixed number (`1 3/4`,
///   `1¾`), or a dash range of two such numbers (`4–10`, `1½–2`). Kept as a
///   string with unicode fractions normalized to ASCII (`'1 3/4'`); ranges
///   keep their dash verbatim. A hyphen followed by letters is not a range,
///   so `(8-ounce)` package sizes never bleed into the quantity.
/// * **Unit** — the first token(s) after the quantity when they spell a
///   known cooking unit, canonicalized to singular (`cups` → `cup`);
///   recognized abbreviations (`tbsp`) expand and multi-word units are
///   matched longest-first (`8 fluid ounces` → `fluid ounce`). Units
///   classify as volume, weight, or count (containers like `can` and
///   `clove` are counts, as are unitless lines: `5 large eggs` → count,
///   unit null; `Pinch salt` → count with an empty-string quantity,
///   matching the YAML codec's convention). The whole vocabulary — names,
///   abbreviations, classification — lives in [_unitVocabulary]; the
///   parenthetical-equivalent regexes below derive from the same table.
/// * **Item / prep** — split at the first top-level comma (commas inside
///   parentheses don't count) after any leading compound-adjective clauses,
///   so `boneless, skinless chicken breasts, trimmed` keeps `boneless,
///   skinless chicken breasts` together as the item.
/// * **Dual amounts** — a parenthetical weight or volume *equivalent*
///   (`1 cup (7 ounces) sugar`, `1 pound cheddar (about 4 cups)`,
///   `1 cup (240 ml) milk`) becomes a secondary non-primary [Amount] and is
///   stripped from item/prep; `about` marks it [Amount.approximate]. One
///   exception: an `about`-marked equivalent of the *same* measure as the
///   primary (`1 pint grape tomatoes, quartered (about 1½ cups)`) is a
///   yield restatement and folds into the primary's approximate flag.
///   Hyphenated package sizes (`(8-ounce)`) are not equivalents and stay on
///   the item.
/// * **Confidence** — [ParseConfidence.none] when no amounts were found;
///   [ParseConfidence.check] when the line hit a shape the extractor
///   routinely got wrong (leading parenthetical size descriptor, `or`
///   alternatives, missing item) or the token after the quantity looks
///   unit-like but isn't in the vocabulary (`2 T sugar` must not silently
///   read as two of something); [ParseConfidence.parsed] otherwise.
ParsedIngredient parseIngredientLine(String raw) {
  // 1. Leading quantity (the publisher's number span, recovered from text).
  String? quantity;
  var rest = raw.trim();
  final quantityMatch = _quantityRe.firstMatch(raw);
  if (quantityMatch != null) {
    quantity = quantityMatch.group(1);
    rest = raw.substring(quantityMatch.end).trim();
  }

  rest = _normalizeFractions(rest);
  var low = false;

  // 2. Leading parenthetical size descriptor, e.g. `(14.5-ounce) can ...` —
  // a known hard case, always routed to review.
  String? size;
  final sizeMatch = _leadingParenRe.firstMatch(rest);
  if (sizeMatch != null) {
    size = sizeMatch.group(1)!.trim();
    rest = sizeMatch.group(2)!.trim();
    low = true;
  }

  // 3. Unit = leading token(s), stripped BEFORE splitting item/prep (so a
  // unit prefix like `pounds` doesn't hide a leading adjective clause
  // `bone-in`). Longest window first so a multi-word unit (`fluid ounces`)
  // beats its first word.
  String? unit;
  final tokens = rest.split(_whitespaceRe).where((t) => t.isNotEmpty).toList();
  for (var n = _maxUnitWords; n >= 1 && unit == null; n--) {
    if (tokens.length < n) continue;
    unit = _matchUnit(tokens.take(n).join(' '));
    if (unit != null) rest = tokens.sublist(n).join(' ');
  }
  // A unit-like but unrecognized token right after the quantity means the
  // count classification below is a guess — route to review.
  if (unit == null &&
      quantity != null &&
      tokens.isNotEmpty &&
      _looksUnitLike(tokens.first)) {
    low = true;
  }

  // 4. Item/prep at the first top-level comma after leading adjectives.
  var (:item, :prep) = _splitItemPrep(rest);

  // `or` alternatives are ambiguous to split -> flag for review.
  if (item != null && _orWordRe.hasMatch(item)) low = true;

  // Re-attach the size descriptor to the item so nothing is lost.
  if (size != null) item = item == null ? '($size)' : '($size) $item';

  // 5. Dual measurement: pull a parenthetical weight/volume equivalent out
  // of the item/prep text into typed amounts.
  final (:weight, :volume, :strip) = _extractMeasures(raw);
  if (strip.isNotEmpty) {
    item = _stripSubstrings(item, strip);
    prep = _stripSubstrings(prep, strip);
  }

  if (item == null) low = true;

  final amounts = _buildAmounts(
    quantity == null ? null : _normalizeFractions(quantity),
    unit,
    weight,
    volume,
  );
  return ParsedIngredient(
    amounts: amounts,
    item: item,
    prep: prep,
    confidence: amounts.isEmpty
        ? ParseConfidence.none
        : (low ? ParseConfidence.check : ParseConfidence.parsed),
  );
}

// --- vocabulary --------------------------------------------------------------

/// One entry in the unit vocabulary: the canonical (singular) spelling, its
/// measure classification, and accepted abbreviations.
class _UnitDef {
  const _UnitDef(this.canonical, this.measure, [this.aliases = const []]);

  /// Canonical singular spelling. May be multi-word (`fluid ounce`);
  /// plurals are handled by trailing-`s`/`es` stripping in [_matchUnit].
  final String canonical;

  final Measure measure;

  /// Accepted abbreviations, lowercase without dots (`oz`, `fl oz`) —
  /// [_matchUnit] strips dots before lookup.
  final List<String> aliases;
}

/// The single source of truth for unit knowledge. Primary-token matching,
/// measure classification, and the parenthetical-equivalent regexes
/// ([_weightUnitsRe]/[_volumeUnitsRe]) all derive from this table, so a
/// unit added here is recognized everywhere at once.
const List<_UnitDef> _unitVocabulary = [
  // Volume.
  _UnitDef('teaspoon', Measure.volume, ['tsp']),
  _UnitDef('tablespoon', Measure.volume, ['tbsp', 'tbs']),
  _UnitDef('cup', Measure.volume),
  _UnitDef('pint', Measure.volume),
  _UnitDef('quart', Measure.volume),
  _UnitDef('gallon', Measure.volume),
  _UnitDef('fluid ounce', Measure.volume, ['fl oz', 'fluid oz']),
  _UnitDef('milliliter', Measure.volume, ['ml']),
  _UnitDef('liter', Measure.volume, ['l']),
  // Weight.
  _UnitDef('ounce', Measure.weight, ['oz']),
  _UnitDef('pound', Measure.weight, ['lb', 'lbs']),
  _UnitDef('gram', Measure.weight, ['g']),
  _UnitDef('kilogram', Measure.weight, ['kg']),
  // Containers and pieces — count units.
  _UnitDef('clove', Measure.count),
  _UnitDef('can', Measure.count),
  _UnitDef('jar', Measure.count),
  _UnitDef('package', Measure.count, ['pkg']),
  _UnitDef('packet', Measure.count),
  _UnitDef('container', Measure.count),
  _UnitDef('bottle', Measure.count),
  _UnitDef('bunch', Measure.count),
  _UnitDef('head', Measure.count),
  _UnitDef('sprig', Measure.count),
  _UnitDef('stalk', Measure.count),
  _UnitDef('stick', Measure.count),
  _UnitDef('slice', Measure.count),
  _UnitDef('strip', Measure.count),
  _UnitDef('piece', Measure.count),
  _UnitDef('pinch', Measure.count),
  _UnitDef('dash', Measure.count),
  _UnitDef('drop', Measure.count),
  _UnitDef('sheet', Measure.count),
  _UnitDef('ear', Measure.count),
  _UnitDef('rib', Measure.count),
  _UnitDef('fillet', Measure.count),
  _UnitDef('loaf', Measure.count),
  _UnitDef('envelope', Measure.count),
  _UnitDef('bag', Measure.count),
  _UnitDef('box', Measure.count),
  _UnitDef('block', Measure.count),
  _UnitDef('wedge', Measure.count),
  _UnitDef('round', Measure.count),
  _UnitDef('square', Measure.count),
  _UnitDef('recipe', Measure.count),
  _UnitDef('batch', Measure.count),
  _UnitDef('scoop', Measure.count),
  _UnitDef('handful', Measure.count),
];

/// Canonical spelling → definition.
final Map<String, _UnitDef> _unitByCanonical = {
  for (final def in _unitVocabulary) def.canonical: def,
};

/// Abbreviation → canonical spelling.
final Map<String, String> _aliasToCanonical = {
  for (final def in _unitVocabulary)
    for (final alias in def.aliases) alias: def.canonical,
};

/// Longest unit spelling in words (2: `fluid ounce`) — the window size for
/// primary-unit matching.
final int _maxUnitWords = _unitVocabulary
    .expand((def) => [def.canonical, ...def.aliases])
    .map((name) => name.split(' ').length)
    .reduce((a, b) => a > b ? a : b);

/// Every non-final word of a multi-word unit spelling (`fluid`, `fl`): a
/// token equal to one of these started a multi-word unit but failed to
/// finish it — unmistakably unit-like.
final Set<String> _multiWordUnitPrefixes = {
  for (final def in _unitVocabulary)
    for (final name in [def.canonical, ...def.aliases])
      ...(name.split(' ')..removeLast()),
};

/// Compound adjectives that are never the whole item — the comma after them
/// is part of the item (`bone-in, skin-on chicken`), not the item/prep
/// boundary.
const Set<String> _leadingAdjectives = {
  'boneless', 'bone-in', 'skinless', 'skin-on', 'low-fat', 'low-sodium', //
  'reduced-fat', 'reduced-sodium', 'part-skim', 'whole-wheat', 'extra-virgin',
  'full-fat', 'fat-free', 'no-salt-added', 'sugar-free', 'gluten-free',
};

// --- regexes ------------------------------------------------------------------

final String _frc = vulgarFractionChars;

/// One number in any corpus spelling: `1 3/4` | `3/4` | `1¾`/`1 ¾` |
/// `12`/`1.5` | `¾`. Mixed forms come first so alternation prefers them.
final String _numberPart =
    '(?:\\d+(?:\\.\\d+)?\\s+\\d+\\s*/\\s*\\d+'
    '|\\d+\\s*/\\s*\\d+'
    '|\\d+(?:\\.\\d+)?\\s?[$_frc]'
    '|\\d+(?:\\.\\d+)?'
    '|[$_frc])';

/// Leading quantity: a number, optionally dash-joined to a second number
/// (`4–10`, `1½–2`). The lookahead requires whitespace, `(`, or end-of-line
/// next, so `8-ounce` (dash followed by letters) is never a range.
final RegExp _quantityRe = RegExp(
  '^\\s*($_numberPart(?:\\s*[-–—]\\s*$_numberPart)?)(?=[\\s(]|\$)',
);

final RegExp _leadingParenRe = RegExp(r'^\(([^)]*)\)\s*(.*)$');
final RegExp _whitespaceRe = RegExp(r'\s+');

/// Case-sensitive on purpose (ports the extractor): `or` mid-item flags the
/// line, a capitalized `Or` would not.
final RegExp _orWordRe = RegExp(r'\bor\b');

final RegExp _multiSpaceRe = RegExp(r'\s{2,}');
final RegExp _edgeTrimRe = RegExp(r'^[ ,]+|[ ,]+$');
final RegExp _aboutRe = RegExp(r'^about\b', caseSensitive: false);
final RegExp _aboutPrefixRe = RegExp(r'^about\s+', caseSensitive: false);

/// `"about 4 cups"` → quantity `4`, unit tail `cups`.
final RegExp _measureStringRe = RegExp(r'^([\d/.\s]*?)\s*([A-Za-z].*)$');

/// Regex alternation over every spelling — canonical with optional plural
/// `s`, plus abbreviations — of the units classified as [measure]. Longest
/// spellings first so `grams` is never half-matched by the `g` abbreviation.
String _unitAlternation(Measure measure) {
  final spellings =
      <String>[
        for (final def in _unitVocabulary)
          if (def.measure == measure) ...[
            '${RegExp.escape(def.canonical)}s?',
            ...def.aliases.map(RegExp.escape),
          ],
      ]..sort(
        (a, b) => a.length != b.length ? b.length - a.length : a.compareTo(b),
      );
  return '(?:${spellings.join('|')})';
}

final String _weightUnitsRe = _unitAlternation(Measure.weight);
final String _volumeUnitsRe = _unitAlternation(Measure.volume);

/// A parenthetical equivalent: a number, a REQUIRED space, then a unit. The
/// space distinguishes `(8 ounces)` / `(½ cup)` from a hyphenated package
/// size `(8-ounce)` (which stays on the item).
String _parenMeasureRe(String units) =>
    '\\((?:about\\s+)?[0-9$_frc][0-9$_frc/.\\s]*?\\s+$units\\)';

final RegExp _parenWeightRe = RegExp(
  _parenMeasureRe(_weightUnitsRe),
  caseSensitive: false,
);
final RegExp _parenVolumeRe = RegExp(
  _parenMeasureRe(_volumeUnitsRe),
  caseSensitive: false,
);

/// Characters a leading measure may contain (digits, fractions, `/`, `.`,
/// `-`, space) when filling the counterpart of a parenthetical equivalent.
final String _fracCls = '[\\d$_frc/.\\- ]';

final RegExp _leadingVolumeRe = RegExp(
  '^\\s*($_fracCls*\\s*$_volumeUnitsRe)\\b',
  caseSensitive: false,
);
final RegExp _leadingWeightRe = RegExp(
  '^\\s*($_fracCls*\\s*$_weightUnitsRe)\\b',
  caseSensitive: false,
);
final RegExp _leadingParenGuardRe = RegExp('^\\s*$_fracCls*\\s*\\(');

// --- helpers ------------------------------------------------------------------

/// Replaces unicode vulgar fractions with ASCII, inserting a space when a
/// digit immediately precedes (`1½` → `1 1/2`).
String _normalizeFractions(String text) {
  final out = StringBuffer();
  var lastWasDigit = false;
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    final ascii = vulgarFractionAscii[ch];
    if (ascii != null) {
      if (lastWasDigit) out.write(' ');
      out.write(ascii);
      lastWasDigit = false;
    } else {
      out.write(ch);
      lastWasDigit = ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;
    }
  }
  return out.toString();
}

/// Lowercases [text] and strips per-word leading/trailing dots
/// (`Fl. Oz.` → `fl oz`), collapsing whitespace.
String _normalizeUnitText(String text) {
  final words = <String>[];
  for (var word in text.toLowerCase().split(_whitespaceRe)) {
    while (word.startsWith('.')) {
      word = word.substring(1);
    }
    while (word.endsWith('.')) {
      word = word.substring(0, word.length - 1);
    }
    if (word.isNotEmpty) words.add(word);
  }
  return words.join(' ');
}

/// Resolves one exact spelling — canonical or abbreviation — to its
/// canonical unit, or null.
String? _lookupUnitSpelling(String spelling) {
  if (_unitByCanonical.containsKey(spelling)) return spelling;
  return _aliasToCanonical[spelling];
}

/// The canonical unit for [text] — one or more words (`cups`, `oz.`,
/// `fluid ounces`) — handling plural/abbreviation, or null.
String? _matchUnit(String text) {
  final t = _normalizeUnitText(text);
  if (t.isEmpty) return null;
  final direct = _lookupUnitSpelling(t);
  if (direct != null) return direct;
  if (t.endsWith('es')) {
    final match = _lookupUnitSpelling(t.substring(0, t.length - 2));
    if (match != null) return match; // pinches, dashes, boxes
  }
  if (t.endsWith('s')) {
    final match = _lookupUnitSpelling(t.substring(0, t.length - 1));
    if (match != null) return match; // cups, cloves, fluid ounces, ...
  }
  return null;
}

final RegExp _alphaWordRe = RegExp(r'^[a-z]+$');

/// Whether an unrecognized [token] sitting right after the quantity smells
/// like a unit the vocabulary is missing: the start of a multi-word unit
/// (`fluid` without a recognizable second word), a dotted abbreviation
/// (`T.`), or a one/two-letter token (`c`, `qt`). Real words (`large`,
/// `garlic`) don't qualify.
bool _looksUnitLike(String token) {
  final t = _normalizeUnitText(token);
  if (t.isEmpty || !_alphaWordRe.hasMatch(t)) return false;
  if (_multiWordUnitPrefixes.contains(t)) return true;
  if (token.contains('.')) return true;
  return t.length <= 2;
}

/// Canonical singular form of a unit (`ounces` → `ounce`); passes through
/// unchanged when not a recognized unit, null when empty.
String? _singularizeUnit(String? unit) {
  if (unit == null || unit.isEmpty) return null;
  return _matchUnit(unit) ?? unit;
}

/// Classifies a unit: null, unrecognized, and container/piece units (can,
/// clove, package, …) are counts.
Measure _measureOfUnit(String? unit) {
  final u = _singularizeUnit(unit);
  return _unitByCanonical[u]?.measure ?? Measure.count;
}

/// Splits on top-level commas only — commas inside parentheses stay put.
List<String> _splitClauses(String text) {
  final out = <String>[];
  var depth = 0;
  final current = StringBuffer();
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    if (ch == '(') depth++;
    if (ch == ')' && depth > 0) depth--;
    if (ch == ',' && depth == 0) {
      out.add(current.toString().trim());
      current.clear();
    } else {
      current.write(ch);
    }
  }
  final tail = current.toString().trim();
  if (tail.isNotEmpty) out.add(tail);
  return out;
}

/// Splits a description into (item, prep): the boundary is the first
/// top-level comma *after* any leading compound-adjective clauses, so
/// `bone-in, skin-on chicken, trimmed` → (`bone-in, skin-on chicken`,
/// `trimmed`) and parenthetical lists are never torn apart.
({String? item, String? prep}) _splitItemPrep(String desc) {
  final clauses = _splitClauses(desc);
  if (clauses.isEmpty) return (item: null, prep: null);
  var i = 0;
  while (i < clauses.length - 1 &&
      _leadingAdjectives.contains(clauses[i].toLowerCase())) {
    i++;
  }
  final item = clauses.sublist(0, i + 1).join(', ').trim();
  final prep = clauses.sublist(i + 1).join(', ').trim();
  return (item: item.isEmpty ? null : item, prep: prep.isEmpty ? null : prep);
}

/// One measure recovered by [_extractMeasures]: its text and whether it came
/// from a parenthetical equivalent (as opposed to being filled in from the
/// line's leading measure).
typedef _MeasureText = ({String text, bool fromParen});

/// Detects a *dual* measurement on an ingredient line: (weight, volume,
/// parenthetical substrings to strip from item/prep). Only fires when the
/// line carries a parenthetical equivalent; single-measure lines and
/// `(8-ounce)` package sizes return no strips and are left untouched.
({_MeasureText? weight, _MeasureText? volume, List<String> strip})
_extractMeasures(String raw) {
  _MeasureText? weight;
  _MeasureText? volume;
  final strip = <String>[];
  final w = _parenWeightRe.firstMatch(raw);
  if (w != null) {
    final text = w.group(0)!;
    weight = (
      text: _normalizeFractions(text.substring(1, text.length - 1).trim()),
      fromParen: true,
    );
    strip.add(_normalizeFractions(text));
  }
  final v = _parenVolumeRe.firstMatch(raw);
  if (v != null) {
    final text = v.group(0)!;
    volume = (
      text: _normalizeFractions(text.substring(1, text.length - 1).trim()),
      fromParen: true,
    );
    strip.add(_normalizeFractions(text));
  }
  if (strip.isEmpty) {
    return (weight: null, volume: null, strip: const []);
  }
  // Fill the counterpart from the primary measure at the start of the line.
  if (volume == null) {
    final p = _leadingVolumeRe.firstMatch(raw);
    if (p != null) {
      volume = (
        text: _normalizeFractions(p.group(1)!.trim()),
        fromParen: false,
      );
    }
  }
  if (weight == null && !_leadingParenGuardRe.hasMatch(raw)) {
    final p = _leadingWeightRe.firstMatch(raw);
    if (p != null) {
      weight = (
        text: _normalizeFractions(p.group(1)!.trim()),
        fromParen: false,
      );
    }
  }
  return (weight: weight, volume: volume, strip: strip);
}

String? _stripSubstrings(String? text, List<String> subs) {
  if (text == null) return null;
  var out = text;
  for (final s in subs) {
    out = out.replaceAll(s, '');
  }
  out = out.replaceAll(_multiSpaceRe, ' ').replaceAll(_edgeTrimRe, '');
  return out.isEmpty ? null : out;
}

/// `"about 4 cups"` → (`4`, `cup`, approximate). The quantity may be null
/// (`Pinch` equivalents have none).
({String? quantity, String? unit, bool approximate}) _parseMeasureString(
  String s,
) {
  final normalized = _normalizeFractions(s).trim();
  final approximate = _aboutRe.hasMatch(normalized);
  final stripped = normalized.replaceFirst(_aboutPrefixRe, '');
  final m = _measureStringRe.firstMatch(stripped);
  if (m != null) {
    final q = m.group(1)!.trim();
    return (
      quantity: q.isEmpty ? null : q,
      unit: _singularizeUnit(m.group(2)!.trim()),
      approximate: approximate,
    );
  }
  return (
    quantity: stripped.isEmpty ? null : stripped,
    unit: null,
    approximate: approximate,
  );
}

/// Turns the primary (quantity/unit) plus optional weight/volume equivalents
/// into a normalized amounts list — the as-listed measure flagged primary,
/// parenthetical equivalents (even exact ones of the same measure:
/// `1 cup (240 ml)`) as secondaries. A null quantity (unit-only lines like
/// `Pinch salt`) becomes the empty string, matching the YAML codec's
/// convention for the non-nullable model field.
List<Amount> _buildAmounts(
  String? quantity,
  String? unit,
  _MeasureText? weight,
  _MeasureText? volume,
) {
  Measure? primaryMeasure;
  if (quantity != null || unit != null) {
    primaryMeasure = _measureOfUnit(unit);
  }
  var primaryApproximate = false;
  final secondary = <Amount>[];
  for (final (kind, measure) in [
    (Measure.weight, weight),
    (Measure.volume, volume),
  ]) {
    if (measure == null) continue;
    final equivalent = _parseMeasureString(measure.text);
    if (kind == primaryMeasure &&
        (!measure.fromParen || equivalent.approximate)) {
      // Two shapes restate the primary rather than adding information: the
      // counterpart filled in from the line's leading measure, and an
      // `about`-marked parenthetical of the same measure (a yield
      // restatement: `1 pint grape tomatoes, quartered (about 1½ cups)`) —
      // both fold into the primary, keeping only the approximation. An
      // *exact* same-measure parenthetical (`1 cup (240 ml) milk`) is a
      // real conversion and becomes a secondary amount below.
      if (equivalent.approximate) primaryApproximate = true;
      continue;
    }
    secondary.add(
      Amount(
        measure: kind,
        quantity: equivalent.quantity ?? '',
        unit: equivalent.unit,
        approximate: equivalent.approximate,
      ),
    );
  }
  return [
    if (primaryMeasure != null)
      Amount(
        measure: primaryMeasure,
        quantity: quantity ?? '',
        unit: unit,
        approximate: primaryApproximate,
        primary: true,
      ),
    ...secondary,
  ];
}
