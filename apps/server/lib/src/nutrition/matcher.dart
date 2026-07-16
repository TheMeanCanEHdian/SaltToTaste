/// Ingredient → FDC food matching: query normalization and candidate
/// ranking with a 0–1 confidence score.
library;

import 'package:salt_server/src/nutrition/provider.dart';

/// Words that describe handling/quality, not identity — dropped from the
/// search query so "unbleached all-purpose flour" still hits "Flour, wheat,
/// all-purpose". Deliberately small: over-stripping hurts more than it
/// helps ("unsalted", "brown", "dark" are identity and stay).
const Set<String> _stopWords = {
  'fresh',
  'freshly',
  'optional',
  'preferably',
  'plus',
  'extra',
  'good-quality',
  'high-quality',
  'quality',
  'store-bought',
  'storebought',
  'homemade',
  'best',
  'favorite',
  'your',
  'assorted',
  'unbleached',
  'organic',
};

/// Items that are nutritionally (effectively) zero — matched locally so
/// they never cost an FDC request and never dilute the match ratio.
const Set<String> waterLikeItems = {
  'water',
  'boiling water',
  'cold water',
  'warm water',
  'hot water',
  'ice water',
  'iced water',
  'tap water',
  'ice',
  'ice cubes',
};

/// Kitchen-name → FDC-vocabulary synonyms applied word-by-word.
const Map<String, String> _synonyms = {
  'confectioners': 'powdered',
  "confectioners'": 'powdered',
  // FDC's house style for salt state.
  'unsalted': 'without salt',
  'salted': 'with salt',
  'scallions': 'green onions',
  'scallion': 'green onion',
  // FDC files bittersweet/semisweet bars under "Chocolate, dark, <n>%".
  'bittersweet': 'dark',
  'semisweet': 'dark',
};

/// The FDC search query for an ingredient item: lowercased, parentheticals
/// and stop-words removed, synonyms applied, whitespace collapsed. Empty
/// when nothing searchable remains.
String normalizeItem(String item) {
  var text = item.toLowerCase();
  text = text.replaceAll(RegExp(r'\(.*?\)'), ' ');
  final words = [
    for (final word in text.split(RegExp('[^a-z0-9%-]+')))
      if (word.isNotEmpty && !_stopWords.contains(word))
        _synonyms[word] ?? word,
  ];
  return words.join(' ');
}

/// Whether the normalized item is water/ice (skip FDC, contribute zeros).
bool isWaterLike(String normalizedItem) =>
    waterLikeItems.contains(normalizedItem);

/// A ranked candidate.
class RankedCandidate {
  /// Pairs a candidate with its score.
  const RankedCandidate({required this.candidate, required this.confidence});

  /// The FDC search hit.
  final FdcCandidate candidate;

  /// 0–1; ≥ 0.75 reads as high, ≥ 0.5 medium, else low.
  final double confidence;
}

String _singular(String word) {
  if (word.length > 3 && word.endsWith('ies')) {
    return '${word.substring(0, word.length - 3)}y';
  }
  if (word.length > 3 && word.endsWith('es')) {
    return word.substring(0, word.length - 2);
  }
  if (word.length > 2 && word.endsWith('s')) {
    return word.substring(0, word.length - 1);
  }
  return word;
}

Set<String> _tokens(String text) => {
  for (final word in text.toLowerCase().split(RegExp('[^a-z0-9%]+')))
    if (word.length > 1) _singular(word),
};

/// Description tokens that mark a MODIFIED form of a food — penalized
/// unless the query itself asks for them, so "large eggs" prefers
/// "egg, whole" over "egg white", and "espresso powder" prefers regular
/// coffee over decaffeinated.
const Set<String> _modifiedFormTokens = {
  'low',
  'light',
  'white',
  'yolk',
  'decaffeinated',
  'dried',
  'dehydrated',
  'powdered',
  'canned',
  'frozen',
  'cooked',
  'roasted',
  'toasted',
  'sweetened',
  'fat-free',
  'nonfat',
  'lowfat',
  'reduced',
  'imitation',
  'substitute',
  // Prepared-product forms: recipes call for the ingredient, not the
  // ready-to-drink/ready-to-pour product built from it.
  'beverage',
  'mix',
  'syrup',
  'drink',
  'prepared',
};

/// Description tokens for the plain/whole form — a small tiebreak bonus.
const Set<String> _plainFormTokens = {'whole', 'raw', 'regular'};

/// Ranks [candidates] against the normalized [query].
///
/// Score = token overlap between the query and the candidate description
/// (how much of the query the description covers, discounted by how much
/// extra specificity the description adds), plus a data-type nudge
/// (Foundation is the highest-quality analysis set), a full-coverage
/// bonus, and modified-form tiebreaks (see [_modifiedFormTokens]).
List<RankedCandidate> rankCandidates(
  String query,
  List<FdcCandidate> candidates,
) {
  final queryTokens = _tokens(query);
  if (queryTokens.isEmpty || candidates.isEmpty) {
    return const [];
  }
  final ranked = <RankedCandidate>[];
  for (final candidate in candidates) {
    final descriptionTokens = _tokens(candidate.description);
    if (descriptionTokens.isEmpty) {
      continue;
    }
    final overlap = queryTokens.intersection(descriptionTokens).length;
    final coverage = overlap / queryTokens.length;
    final precision = overlap / descriptionTokens.length;
    var score = 0.65 * coverage + 0.2 * precision;
    if (coverage == 1) {
      score += 0.1;
    }
    score += switch (candidate.dataType) {
      'Foundation' => 0.1,
      'SR Legacy' => 0.05,
      _ => 0.0,
    };
    for (final token in descriptionTokens) {
      if (_modifiedFormTokens.contains(token) && !queryTokens.contains(token)) {
        score -= 0.06;
      }
    }
    if (descriptionTokens.any(_plainFormTokens.contains)) {
      score += 0.02;
    }
    ranked.add(
      RankedCandidate(
        candidate: candidate,
        confidence: score.clamp(0.0, 1.0),
      ),
    );
  }
  ranked.sort((a, b) => b.confidence.compareTo(a.confidence));
  return ranked;
}
