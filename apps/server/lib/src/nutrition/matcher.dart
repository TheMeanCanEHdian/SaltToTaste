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

/// Preparation words — how the cook cuts/handles the food, never what it IS.
/// Dropped from the query so "minced fresh oregano" searches "oregano"
/// (otherwise "minced" hits "Ham, minced") and correct matches stop being
/// confidence-deflated by noise tokens. Deliberately CONSERVATIVE: anything
/// that could change the food's identity (raw/cooked/roasted/dried/ground)
/// stays out of this list. "leaves"/"cut" also stay out — dropping them turns
/// "bay leaves" into "bay".
const Set<String> _prepWords = {
  'minced',
  'chopped',
  'sliced',
  'diced',
  'grated',
  'shredded',
  'crushed',
  'crumbled',
  'halved',
  'quartered',
  'cored',
  'peeled',
  'seeded',
  'pitted',
  'trimmed',
  'sifted',
  'packed',
  'softened',
  'melted',
  'beaten',
  'cubed',
  'mashed',
  'thawed',
  'drained',
  'rinsed',
  'divided',
  'julienned',
  'shaved',
  'coarse',
  'coarsely',
  'fine',
  'finely',
  'thin',
  'thinly',
  'roughly',
  // Size / vessel words: describe the piece bought, not the food. "small head
  // escarole" must search "escarole", not drag in "Beans, Dry, Small Red".
  // ("whole" stays — it's an FDC form, e.g. "whole milk", "whole wheat".)
  'small',
  'medium',
  'large',
  'head',
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
      if (word.isNotEmpty &&
          !_stopWords.contains(word) &&
          !_prepWords.contains(word))
        _synonyms[word] ?? word,
  ];
  return words.join(' ');
}

/// Whether the normalized item is water/ice (skip FDC, contribute zeros).
bool isWaterLike(String normalizedItem) =>
    waterLikeItems.contains(normalizedItem);

/// Seasoning a recipe adds "to taste": with no amount on the line it
/// contributes nothing measurable, and FDC's search for it returns bell
/// peppers and salted nuts. Such a line is confirmed as a deliberate
/// no-match instead of sitting in the review queue forever. A line WITH an
/// amount ("1 teaspoon table salt") is matched normally.
const Set<String> seasoningToTasteItems = {
  'salt',
  'table salt',
  'kosher salt',
  'sea salt',
  'flaky sea salt',
  'flake sea salt',
  'pepper',
  'black pepper',
  'ground pepper',
  'ground black pepper',
  'salt and pepper',
  'salt and black pepper',
  'salt and ground pepper',
  'salt and ground black pepper',
  'table salt and pepper',
  'table salt and ground black pepper',
  'kosher salt and pepper',
  'kosher salt and ground black pepper',
};

/// Whether an amount-less line of [normalizedItem] is seasoning to taste.
bool isSeasoningToTaste(String normalizedItem) =>
    seasoningToTasteItems.contains(normalizedItem);

/// Phrases FDC's search cannot find under the recipe's words, rewritten to
/// the words FDC files them under. Keyed by the NORMALIZED item — exactly as
/// [normalizeItem] leaves it, prep words already gone — the value is the
/// query. Bare 'rye' is deliberately absent: in recipes it is a grain or a
/// bread (every corpus use), the spirit is 'rye whiskey'. Every target was chosen from a recorded FDC answer (see
/// test/fixtures/fdc/searches.json).
///
/// Pepper: FDC's search for "black pepper", "pepper" or "red pepper flakes"
/// returns only the vegetables ("Peppers, sweet, green…"); the spice records
/// answer to "spices pepper …". Spirits: FDC has no brand liqueurs at all —
/// "grand marnier" found a candy bar — but clean generic entries for
/// liqueur, brandy, rum and whiskey.
const Map<String, String> _queryRewrites = {
  // pepper, the spice
  'pepper': 'spices pepper black',
  'black pepper': 'spices pepper black',
  'ground pepper': 'spices pepper black',
  'ground black pepper': 'spices pepper black',
  'cracked black pepper': 'spices pepper black',
  'black peppercorns': 'spices pepper black',
  'peppercorns': 'spices pepper black',
  'whole peppercorns': 'spices pepper black',
  'whole black peppercorns': 'spices pepper black',
  'cracked peppercorns': 'spices pepper black',
  'cracked black peppercorns': 'spices pepper black',
  'white pepper': 'spices pepper white',
  'ground white pepper': 'spices pepper white',
  'red pepper flakes': 'spices pepper red cayenne',
  'cayenne': 'spices pepper red cayenne',
  'cayenne pepper': 'spices pepper red cayenne',
  'ground cayenne pepper': 'spices pepper red cayenne',
  // orange liqueurs and liqueurs in general
  'grand marnier': 'liqueur',
  'cointreau': 'liqueur',
  'triple sec': 'liqueur',
  'orange liqueur': 'liqueur',
  'amaretto': 'liqueur',
  'kahlua': 'liqueur',
  'coffee liqueur': 'liqueur',
  // brandies
  'calvados': 'brandy',
  'cognac': 'brandy',
  'armagnac': 'brandy',
  'apple brandy': 'brandy',
  // rums
  'spiced rum': 'rum',
  'dark rum': 'rum',
  'light rum': 'rum',
  'white rum': 'rum',
  'gold rum': 'rum',
  // whiskeys
  'bourbon': 'whiskey',
  'bourbon whiskey': 'whiskey',
  'rye whiskey': 'whiskey',
  'scotch': 'whiskey',
  'scotch whisky': 'whiskey',
  'whisky': 'whiskey',
};

/// The FDC search query for a normalized item: the item itself, unless a
/// [_queryRewrites] phrase applies. The item key (identity across recipes)
/// stays the normalized item; only what is sent to FDC — and so the search
/// cache key — changes.
String searchQueryFor(String normalizedItem) =>
    _queryRewrites[normalizedItem] ?? normalizedItem;

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
  // Prepared-product forms: recipes call for the ingredient, not the
  // ready-to-drink/ready-to-pour product built from it.
  'beverage',
  'mix',
  'syrup',
  'drink',
  'prepared',
};

/// Added meat qualifiers a generic query didn't ask for: "sausage"/"bacon"
/// default to pork, not "Sausage, turkey" / "Bacon, turkey"; a deli/luncheon
/// cut is not the raw ingredient ("chicken breast" wants the raw cut, not
/// "Lunchmeat, chicken breast"). Query-gated, so "turkey bacon"/"chicken
/// sausage"/"deli ham" still match. ("bits" is deliberately NOT here:
/// penalizing it surfaced Canadian bacon — leaner and further from real bacon
/// than the crumbled-bacon "Bacon bits".)
///
/// Docked HARDER than a plain off-form ([_modifiedFormTokens], -0.06): the
/// wrong MEAT is a bigger error than the wrong cook-state, and at -0.06 it lost
/// to it — "breakfast sausage" matched a raw TURKEY link (which also took the
/// +0.02 raw-form bonus) over the real pre-COOKED beef breakfast sausage
/// (docked -0.06 for "cooked"). The species dock must outweigh that ~0.08 form
/// swing so meat type wins. Still light enough that a turkey/chicken match with
/// no better option merely falls toward the review gate, not off a cliff.
const Set<String> _offMeatTokens = {
  'turkey',
  'chicken',
  'lunchmeat',
  'luncheon',
  'deli',
  'blood',
};

/// A food processed into a DIFFERENT staple — "almonds" is not "almond FLOUR",
/// "Dijon mustard" is not "mustard OIL", "rice" is not "rice FLOUR". A base-
/// form change is a much bigger error than an off-form ([_modifiedFormTokens]),
/// so it takes a heavier penalty — enough to reliably demote it below the whole
/// food. Applied only when the query itself did not ask for the form.
const Set<String> _baseFormChangeTokens = {
  'flour',
  'oil',
  'juice',
  'sauce',
  'paste',
  'meal',
  'butter',
};

/// Reconstitutable-concentrate markers. A bouillon CUBE, broth GRANULE, or
/// juice CONCENTRATE is a fundamentally different food from the ready-to-use
/// liquid a recipe asks for — and because grams are then estimated from the
/// recipe's VOLUME, matching "8 cups chicken broth" to dry cubes overstates
/// calories 10-50×. So a candidate whose description carries one of these takes
/// the heavy base-form-class penalty, unless the query itself names the form
/// ("beef bouillon" still matches bouillon).
///
/// Matched as SUBSTRINGS, not tokens, on purpose: the ranker's plural stemmer
/// mangles the very words at issue ("cubes" → "cub", "granules" → "granul"), so
/// a token-set check would silently miss them. Substrings also fold the
/// singular/plural/-ed variants (cube/cubes/cubed) into one marker.
///
/// Deliberately excludes dry/dried/powder/powdered/condensed/instant: those
/// correctly describe foods that ONLY exist concentrated (cocoa powder,
/// gelatin, dry milk, condensed milk), and penalizing them would sink the one
/// correct match below the review gate. The distinction rides on these narrow
/// reconstitution nouns, not on "dry".
const Set<String> _concentrateMarkers = {
  'cube',
  'bouillon',
  'concentrate',
  'granule',
};

/// Meat-analog markers. An IMITATION/vegetarian version is a fundamentally
/// different food from the meat a recipe asks for ("Bacon, meatless" is soy;
/// "Hot dog, vegetarian" is not a beef frank). Whole-word, query-gated, so a
/// query that itself names the analog ("vegetarian sausage") still matches it.
const Set<String> _meatAnalogMarkers = {
  'meatless',
  'vegetarian',
  'vegan',
  'imitation',
  'substitute',
  'analog',
  'analogue',
};

/// Prepared-dish / composite markers. A raw ingredient must not match a
/// finished dish or beverage built from it ("ginger" → "Tea, ginger",
/// "shrimp" → "Shrimp cocktail", "chicken" → "Chicken cacciatore"). Whole-word
/// and query-gated ("curry powder", "shrimp salad" still match).
///
/// Deliberately EXCLUDES words that FDC also uses to file real INGREDIENTS,
/// found by an adversarial live-FDC sweep:
///  - `soup`/`salad` — broths are "Soup, X broth", mayo is "Salad dressing";
///  - `pie` — "Pie crust" covers graham-cracker/cookie crusts and tart shells;
///  - `wonton` — "Wonton wrappers" is FDC's entry for egg-roll/gyoza wrappers;
///  - `dip` — tzatziki/queso/baba ganoush are filed "X dip";
///  - `sandwich` — sandwich cookies (Oreos) are "Cookies, sandwich";
///  - `adobo` — "chipotle in adobo" is a common ingredient.
/// (`tea` is kept: ginger→"Tea, ginger" is common and correctable to Ginger
/// root; the rare matcha/hibiscus whose ONLY match is tea-filed just fall to
/// the review gate — an honest gap, not a wrong number.)
const Set<String> _dishMarkers = {
  'cocktail',
  'scampi',
  'fajita',
  'teriyaki',
  'creole',
  'stroganoff',
  'croquette',
  'burrito',
  'quesadilla',
  'enchilada',
  'tamale',
  'risotto',
  'pilaf',
  'quiche',
  'souffle',
  'frittata',
  'omelet',
  'cacciatore',
  'parmigiana',
  'scallopini',
  'marsala',
  'gratin',
  'tempura',
  'lasagna',
  'tea',
  'pizza',
  'taco',
  'gumbo',
  'chowder',
  'bisque',
  'casserole',
  'stew',
  'curry',
  'pudding',
  'toast',
  'chips',
  'nugget',
  'fritter',
  'dumpling',
  'paella',
  'jambalaya',
  // A "... breakfast biscuit" is a sandwich, not the meat: "breakfast sausage"
  // otherwise matched "Sausage, egg and cheese breakfast biscuit" over the real
  // sausage. Query-gated, so a recipe that asks for "biscuit(s)" still matches.
  'biscuit',
};

/// Description tokens for the plain/whole form — a small tiebreak bonus.
const Set<String> _plainFormTokens = {'whole', 'raw', 'regular'};

/// Whole words of [text], lowercased, no stemming — for marker sets that must
/// match "tea" without also matching "steak" (a substring check would).
Set<String> _words(String text) =>
    text.toLowerCase().split(RegExp('[^a-z]+')).toSet();

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
      // FNDDS values are recipe-CALCULATED, not directly analyzed, so it sits
      // just below SR Legacy for raw single ingredients — but it's the right
      // (and often only) layer for cooked/composite lines ("chicken broth",
      // "escarole, cooked"), so it wins there on the name match alone.
      'Survey (FNDDS)' => 0.04,
      _ => 0.0,
    };
    for (final token in descriptionTokens) {
      if (queryTokens.contains(token)) {
        continue;
      }
      if (_baseFormChangeTokens.contains(token)) {
        score -= 0.25;
      } else if (_offMeatTokens.contains(token)) {
        score -= 0.12;
      } else if (_modifiedFormTokens.contains(token)) {
        score -= 0.06;
      }
    }
    // Reconstitutable-concentrate penalty (substring, query-gated). One dock is
    // enough — "bouillon cubes" is a single concept, not two errors.
    final descriptionLower = candidate.description.toLowerCase();
    final queryLower = query.toLowerCase();
    for (final marker in _concentrateMarkers) {
      if (descriptionLower.contains(marker) && !queryLower.contains(marker)) {
        score -= 0.25;
        break;
      }
    }
    // Meat-analog / prepared-dish penalty (whole-word, query-gated). A recipe's
    // raw ingredient is not a soy analog or a finished dish built from it. One
    // dock, base-form magnitude — a wrong food, not a modified form.
    final descriptionWords = _words(candidate.description);
    final queryWords = _words(query);
    final wrongFood = _meatAnalogMarkers
        .followedBy(_dishMarkers)
        .any(
          (marker) =>
              descriptionWords.contains(marker) && !queryWords.contains(marker),
        );
    if (wrongFood) {
      score -= 0.25;
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

/// The rewrite table's keys. Every key must be a normalized item exactly as
/// [normalizeItem] produces it — a key the normalizer would rewrite first is
/// dead (pinned by a test): 'crushed red pepper' once sat in the table while
/// the line normalized to 'red pepper' and searched the vegetable.
Iterable<String> get queryRewriteKeys => _queryRewrites.keys;
