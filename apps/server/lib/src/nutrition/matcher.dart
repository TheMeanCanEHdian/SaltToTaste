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

/// Bumped whenever [normalizeItem], [itemKeyFor], the rewrite table or the
/// ranker changes what a line searches, how it is keyed, or how candidates
/// score. Folded into the nutrition staleness hash, so every computed recipe
/// becomes `stale` and the stale sweep re-resolves its engine rows (human
/// decisions are kept) — otherwise stored scores and picks stay frozen at the
/// matcher that wrote them, which the 2026-09-04 survey measured on every
/// computed recipe. Decision rows are re-keyed at boot from their item text
/// when this changes (services/decision_rekey.dart).
///
/// History: 1 = everything before 2026-09-07; 2 = diacritics folded, canned
/// crushed/diced tomatoes keep their form word, singular decision keys;
/// 3 = the ranker requires the ingredient's head noun, docks composite and
/// branded records harder, 'juice from 1 lemon' normalizes to 'lemon juice',
/// and the rewrite table gained the spice/bacon/shrimp/sherry/beer/mustard/
/// pasta entries (design review D4, measured on the 2026-09-08 diagnostic
/// set: 19 of 31 confidently wrong foods fixed, 0 correct lines regressed).
const int matcherVersion = 3;

/// Letters FDC and the corpus both write plainly: 'jalapeño' searched as
/// 'jalape o' (the split treated ñ as punctuation) on 65 corpus lines.
const Map<String, String> _folded = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ñ': 'n',
  'ç': 'c',
};

/// Prep words that name the PRODUCT when they precede these foods: a can of
/// crushed or diced tomatoes is a different food from a fresh one (FDC files
/// them apart), and stripping the word folded 51 canned lines into the
/// 9 fresh ones under one key.
const Set<String> _formPhrases = {'crushed tomatoes', 'diced tomatoes'};

/// The FDC search query for an ingredient item: lowercased, accents folded,
/// parentheticals and stop-words removed, synonyms applied, whitespace
/// collapsed. Empty when nothing searchable remains.
String normalizeItem(String item) {
  var text = item.toLowerCase();
  text = text.replaceAllMapped(
    RegExp('[${_folded.keys.join()}]'),
    (m) => _folded[m[0]]!,
  );
  text = text.replaceAll(RegExp(r'\(.*?\)'), ' ');
  final raw = text.split(RegExp('[^a-z0-9%-]+'));
  final words = <String>[];
  for (var i = 0; i < raw.length; i++) {
    final word = raw[i];
    if (word.isEmpty || _stopWords.contains(word)) {
      continue;
    }
    final formWord =
        i + 1 < raw.length && _formPhrases.contains('$word ${raw[i + 1]}');
    if (_prepWords.contains(word) && !formWord) {
      continue;
    }
    words.add(_synonyms[word] ?? word);
  }
  return _fruitFromTail(words).join(' ');
}

/// Citrus the corpus writes as "juice from 1 lemon" / "zest from 2 limes":
/// FDC names the fruit first ("Lemon juice, raw"), and the count is not part
/// of the food. 120 corpus lines; before this they searched 'juice from 1
/// lemon' (bottled concentrate won) under a key no other lemon-juice line
/// shared.
const Set<String> _citrus = {
  'lemon',
  'lime',
  'orange',
  'grapefruit',
  'tangerine',
  'clementine',
};

/// "<what> from [about] N [to M] <citrus>" → "<citrus> <what>", the fruit
/// named once. Anything else is returned unchanged.
List<String> _fruitFromTail(List<String> words) {
  final from = words.lastIndexOf('from');
  if (from < 1 || from == words.length - 1) {
    return words;
  }
  final tail = words.sublist(from + 1);
  final fruit = _keyWord(tail.last);
  if (!_citrus.contains(fruit)) {
    return words;
  }
  final countWords = tail.sublist(0, tail.length - 1);
  if (!countWords.every(
    (w) => RegExp(r'^\d+$').hasMatch(w) || w == 'about' || w == 'to',
  )) {
    return words;
  }
  final what = [
    for (final w in words.sublist(0, from))
      if (_keyWord(w) != fruit) w,
  ];
  return [fruit, ...what];
}

/// The key a human decision is stored and reused under (`ingredient_matches
/// .item_key`, `ingredient_decisions.item_key`): [normalizeItem] with every
/// word singular, so "1 onion" and "2 onions" — 66 such pairs, 2,036 corpus
/// lines — are one ingredient. Only the KEY: the FDC query keeps the line's
/// own words, so nothing cached is invalidated and ranking is unchanged.
/// Empty when nothing searchable remains.
String itemKeyFor(String item) => [
  for (final word in normalizeItem(item).split(' '))
    if (word.isNotEmpty) _keyWord(word),
].join(' ');

/// Singular form for a decision key. Deliberately plain: a key only has to
/// be the SAME for both spellings, not a dictionary word ('cooky' is fine).
/// Guards keep singular words that end in s ('asparagus', 'molasses').
String _keyWord(String word) {
  if (word.length <= 3 ||
      word.endsWith('ss') ||
      word.endsWith('us') ||
      word.endsWith('is')) {
    return word;
  }
  if (word.endsWith('ies')) {
    return '${word.substring(0, word.length - 3)}y';
  }
  if (word.endsWith('ves')) {
    // leaves → leaf, halves → half, loaves → loaf; but 'olives', 'chives',
    // 'cloves' keep their v: strip the s only.
    const fToVes = {'leaves', 'halves', 'loaves', 'calves', 'knives'};
    return fToVes.contains(word)
        ? '${word.substring(0, word.length - 3)}f'
        : word.substring(0, word.length - 1);
  }
  if (word.endsWith('oes')) {
    return word.substring(0, word.length - 2);
  }
  if (word.endsWith('es')) {
    final stem = word.substring(0, word.length - 2);
    if (stem.endsWith('ss')) {
      return word; // molasses
    }
    final sibilant =
        stem.endsWith('s') ||
        stem.endsWith('x') ||
        stem.endsWith('z') ||
        stem.endsWith('ch') ||
        stem.endsWith('sh');
    return sibilant ? stem : word.substring(0, word.length - 1);
  }
  if (word.endsWith('s')) {
    return word.substring(0, word.length - 1);
  }
  return word;
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
/// the words FDC files them under. Keyed by the NORMALIZED item — exactly
/// as [normalizeItem] leaves it, prep words already gone — the value is the
/// query. Bare 'rye' is deliberately absent: in recipes it is a grain or a
/// bread (every corpus use); the spirit is 'rye whiskey'. Every target was
/// chosen from a recorded FDC answer (test/fixtures/fdc/searches.json).
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
  // Design review D4 (2026-09-08), every target's answer recorded from live
  // FDC in the diagnostic cache: ground spices file under their seed; canned
  // tomatoes aside, FDC's spice records lead with "Spices, …".
  'ground cumin': 'cumin seeds',
  'ground coriander': 'coriander seeds',
  'ground fennel': 'fennel seeds',
  'cinnamon': 'ground cinnamon',
  'cinnamon stick': 'ground cinnamon',
  'cinnamon sticks': 'ground cinnamon',
  'whole cloves': 'ground cloves',
  'frozen phyllo': 'phyllo',
  'bay leaves': 'bay leaf',
  'parsley leaves': 'parsley',
  'vegetable oil for frying': 'vegetable oil',
  // 'bacon' alone returns bits, meatless and turkey bacon before pork.
  'bacon': 'pork cured bacon unprepared',
  // Every bare 'shrimp' answer is a dish (cocktail, scampi, fried).
  'shrimp': 'shrimp raw',
  'extra-large shrimp': 'shrimp raw',
  'jumbo shrimp': 'shrimp raw',
  'shell-on shrimp': 'shrimp raw',
  // FDC files sherry under dessert wine and lager under beer.
  'sherry': 'wine dessert dry',
  'dry sherry': 'wine dessert dry',
  'lager': 'beer',
  'mild lager': 'beer',
  'dijon mustard': 'mustard prepared',
  // Pasta shapes FDC does not know by name.
  'penne': 'pasta dry enriched',
  'campanelle': 'pasta dry enriched',
  'spaghettini': 'pasta dry enriched',
  'linguine': 'pasta dry enriched',
  'rigatoni': 'pasta dry enriched',
  'orecchiette': 'pasta dry enriched',
  'farfalle': 'pasta dry enriched',
  'ziti': 'pasta dry enriched',
  'fusilli': 'pasta dry enriched',
  'gemelli': 'pasta dry enriched',
  'cavatappi': 'pasta dry enriched',
  'bucatini': 'pasta dry enriched',
  'tagliatelle': 'pasta dry enriched',
  'fettuccine': 'pasta dry enriched',
  'pappardelle': 'pasta dry enriched',
  'orzo': 'pasta dry enriched',
  'ditalini': 'pasta dry enriched',
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

/// Words that say how an ingredient comes, never what it is. Dropped when
/// looking for the head noun. The conjunctions are here because
/// 'half-and-half' would otherwise have the head 'and' (21 corpus lines).
const Set<String> _formWords = {
  'ground',
  'whole',
  'dry',
  'dried',
  'fresh',
  'frozen',
  'ripe',
  'firm',
  'mild',
  'large',
  'small',
  'medium',
  'chopped',
  'and',
  'or',
  'plus',
};

/// Count nouns, BOTH numbers: 'garlic clove' and 'garlic cloves' must both
/// give the head 'garlic' (a plural-only list docked 'Garlic, raw' on 93
/// corpus lines).
const Set<String> _countNouns = {
  'leaf',
  'leaves',
  'wedge',
  'wedges',
  'clove',
  'cloves',
  'rib',
  'ribs',
  'sprig',
  'sprigs',
  'stalk',
  'stalks',
  'fillet',
  'fillets',
  'piece',
  'pieces',
  'half',
  'halves',
  'slice',
  'slices',
  'stick',
  'sticks',
  'head',
  'heads',
  'ear',
  'ears',
  'bunch',
  'bunches',
};

/// Compound identities whose LAST word names the form: 'anchovy paste',
/// 'celery root', 'tomato sauce' — the head is the word before.
const Set<String> _identityTails = {
  'paste',
  'sauce',
  'root',
  'dough',
  'zest',
  'thread',
  'threads',
  'mix',
  'spray',
};

/// The corpus says chile; FDC says pepper.
const Map<String, String> _headSynonyms = {
  'chile': 'pepper',
  'chili': 'pepper',
  'chily': 'pepper',
};

Set<String> _keyTokens(String text) => {
  for (final word in text.toLowerCase().split(RegExp('[^a-z0-9%]+')))
    if (word.length > 1) _keyWord(word),
};

/// Whether [tokens] carry [head]. The key stemmer turns 'cookies' into
/// 'cooky' but leaves 'cookie' alone, so an -ies head also matches its -ie
/// spelling (cookies/cookie, brownies/brownie).
bool _carriesHead(Set<String> tokens, String head) =>
    tokens.contains(head) ||
    (head.endsWith('y') &&
        tokens.contains('${head.substring(0, head.length - 1)}ie'));

/// The word that names the food in [query] (the FDC search query), in its
/// key form — or null when nothing identifies one. A trailing " for …"
/// clause and an "or … recipe …" cross-reference are cut (never a plain
/// "or": 'instant or rapid-rise yeast' needs its last alternative); form,
/// prep and stop words and count nouns are dropped; the last survivor is
/// the head, stepping back over an identity tail ('anchovy paste' →
/// anchovy). A modified-form word ('yolk', 'white') is never the identity.
///
/// Measured over all 13,614 corpus lines (design review D4): 484 distinct
/// heads, 261 lines with none; the risky heads a literal "last token" rule
/// produced (paste 106, chil 48, whit 29, and 21, lim 8) all go to zero.
String? headNounOf(String query) {
  var text = query;
  final forIdx = text.indexOf(' for ');
  if (forIdx > 0) {
    text = text.substring(0, forIdx);
  }
  final parts = text.split(' or ');
  while (parts.length > 1 && parts.last.contains('recipe')) {
    parts.removeLast();
  }
  text = parts.join(' or ');
  final kept = <String>[
    for (final w in text.split(RegExp('[^a-z0-9%]+')))
      if (w.length >= 2 &&
          !_formWords.contains(w) &&
          !_prepWords.contains(w) &&
          !_stopWords.contains(w) &&
          !_countNouns.contains(w))
        w,
  ];
  if (kept.isEmpty) {
    return null;
  }
  while (_identityTails.contains(kept.last) && kept.length > 1) {
    kept.removeLast();
  }
  final head = _keyWord(kept.last);
  if (_modifiedFormTokens.contains(head)) {
    return null;
  }
  return _headSynonyms[head] ?? head;
}

/// Whether any of [candidates] names the ingredient's head noun. False means
/// the search answer holds no record of the food at all — a list that is
/// hopeless, not mis-ranked (37 of 878 diagnostic lines): the sheet says so
/// instead of offering the top junk record.
bool candidatesNameIngredient(String query, List<FdcCandidate> candidates) {
  final head = headNounOf(query);
  if (head == null) {
    return true;
  }
  return candidates.any((c) => _carriesHead(_keyTokens(c.description), head));
}

/// Composite records — a dish or a product built from the food, never the
/// food. Only the markers MEASURED to change a chosen food on the 878-line
/// diagnostic set, both numbers (the older dish list is unstemmed, which is
/// why 'nugget' never docked "chicken nuggets"). Not 'bits' (FDC files
/// Canadian bacon under it), not 'pie'/'cookie' (they would dock "Pie
/// Crust, Cookie-type, Graham Cracker" — pinned).
const Set<String> _compositeMarkers = {
  'sandwich',
  'sandwiches',
  'cake',
  'cakes',
  'roll',
  'rolls',
  'bun',
  'buns',
  'nugget',
  'nuggets',
  'mock',
  'dressing',
  'dressings',
  'topping',
  'toppings',
  'candy',
  'candies',
};
const List<String> _compositePhrases = ['school lunch', 'with meat'];

/// The dock for a wrong-food record (analog, dish, composite): −0.25 left
/// "School Lunch, chicken nuggets" counted for 'whole chicken' at 0.627;
/// −0.40 puts it at 0.477. Measured: only those lines differ.
const double _wrongFoodDock = 0.40;

/// A token FDC writes in capitals is a brand (SWANSON, POPEYES, REAL LEMON)
/// unless the query names it; "USDA's" is a programme note, not a brand.
final RegExp _brandToken = RegExp(r"\b[A-Z][A-Z'&-]{3,}\b");

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
  final head = headNounOf(query);
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
    // 'sandwich' never docks a sandwich COOKIE: FDC files Oreos as
    // "Cookie, chocolate sandwich" (recorded 2026-09-08).
    final cookieRecord =
        descriptionWords.contains('cookie') ||
        descriptionWords.contains('cookies');
    final wrongFood =
        _meatAnalogMarkers
            .followedBy(_dishMarkers)
            .followedBy(_compositeMarkers)
            .any(
              (marker) =>
                  descriptionWords.contains(marker) &&
                  !queryWords.contains(marker) &&
                  !(cookieRecord && marker.startsWith('sandwich')),
            ) ||
        _compositePhrases.any(
          (phrase) =>
              descriptionLower.contains(phrase) && !queryLower.contains(phrase),
        );
    if (wrongFood) {
      score -= _wrongFoodDock;
    }
    if (descriptionTokens.any(_plainFormTokens.contains)) {
      score += 0.02;
    }
    // The ingredient's head noun must be in the record. Docked uniformly
    // even when NO candidate carries it: that is exactly what stops 156 g of
    // "Lentils, dry" counting for 'dry sherry'. Never excludes a candidate —
    // the sheet still shows the top one, held in `check`.
    if (head != null &&
        !_carriesHead(_keyTokens(candidate.description), head)) {
      score -= 0.30;
    }
    // A brand the query did not name. Safe only WITH the head-noun dock:
    // alone it handed "Soup, SWANSON, beef broth" to a beef-and-mushroom soup.
    if (_brandToken
        .allMatches(candidate.description)
        .map((m) => m[0]!)
        .any(
          (t) => !t.startsWith('USDA') && !queryLower.contains(t.toLowerCase()),
        )) {
      score -= 0.25;
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
