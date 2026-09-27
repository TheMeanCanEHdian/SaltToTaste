/// Amount → grams resolution, in confidence order: a weight amount converts
/// directly; a volume amount goes through the food's own household portions,
/// falling back to a built-in density table; a count goes through piece
/// portions or a piece-weight table.
library;

import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';

/// How a line's grams were determined (persisted; the UI explains it).
enum GramSource {
  /// A weight amount converted directly — the gold standard.
  weight,

  /// A volume amount through the matched food's own portion data.
  portion,

  /// A volume amount through the built-in density table (estimate).
  density,

  /// A count through portion/piece-weight data (estimate).
  piece,

  /// The user typed the grams by hand.
  override,

  /// A line with no amount at all ("Lemon wedges, for serving", "Vegetable
  /// oil spray"), counted as 0 g with its food still matched (the engine's
  /// `amountlessLinesZero`, user answer #3).
  unmeasured,

  /// A cooking medium the recipe discards — deep-frying oil, a brine, a
  /// buttermilk soak — counted as 0 g (the engine's discarded-media rule
  /// and its policy switch, engine.dart `discardedMediaPolicy`).
  discarded,
}

/// Grams per unit of weight.
const Map<String, double> _weightUnitGrams = {
  'gram': 1,
  'g': 1,
  'kilogram': 1000,
  'kg': 1000,
  'ounce': 28.3495,
  'oz': 28.3495,
  'pound': 453.592,
  'lb': 453.592,
};

/// Milliliters per unit of volume.
const Map<String, double> _volumeUnitMl = {
  'teaspoon': 4.92892,
  'tsp': 4.92892,
  'tablespoon': 14.7868,
  'tbsp': 14.7868,
  'fluid ounce': 29.5735,
  'cup': 236.588,
  'pint': 473.176,
  'quart': 946.353,
  'gallon': 3785.41,
  'milliliter': 1,
  'ml': 1,
  'liter': 1000,
  'l': 1000,
};

/// Density fallbacks (g/ml) for pantry staples, keyed by tokens matched
/// against the normalized item — used only when the matched food carries no
/// usable volume portion. Values are round kitchen figures, flagged as
/// estimates in the UI.
const List<(String, double)> _densities = [
  ('all-purpose flour', 0.51),
  ('bread flour', 0.52),
  ('cake flour', 0.46),
  ('whole-wheat flour', 0.54),
  ('flour', 0.51),
  ('granulated sugar', 0.85),
  ('brown sugar', 0.93),
  ('confectioners sugar', 0.51),
  ('powdered sugar', 0.51),
  ('sugar', 0.85),
  ('butter', 0.959),
  ('milk', 1.03),
  ('buttermilk', 1.03),
  ('heavy cream', 1.01),
  ('cream', 1.01),
  ('sour cream', 0.97),
  ('yogurt', 1.03),
  ('water', 1.0),
  ('oil', 0.92),
  ('honey', 1.42),
  ('maple syrup', 1.32),
  ('corn syrup', 1.38),
  ('molasses', 1.41),
  ('cocoa', 0.52),
  ('espresso powder', 0.43),
  ('instant coffee', 0.43),
  ('coffee powder', 0.43),
  ('brewed coffee', 1.0),
  ('coffee', 1.0),
  ('cornstarch', 0.54),
  ('cornmeal', 0.66),
  ('rice', 0.85),
  ('oats', 0.41),
  ('salt', 1.22),
  ('kosher salt', 0.72),
  ('baking powder', 0.92),
  ('baking soda', 0.93),
  ('yeast', 0.64),
  ('vanilla', 0.88),
  ('vinegar', 1.01),
  ('wine', 0.99),
  ('broth', 1.0),
  ('stock', 1.0),
  ('ketchup', 1.14),
  ('mayonnaise', 0.91),
  ('mustard', 1.05),
  ('soy sauce', 1.16),
  ('fish sauce', 1.2),
  ('peanut butter', 1.09),
  ('ginger', 0.54),
  ('tomato paste', 1.1),
  ('lemon juice', 1.03),
  ('lime juice', 1.03),
  ('sherry', 0.99),
  ('jam', 1.35),
  ('breadcrumbs', 0.45),
  ('panko', 0.25),
  ('parmesan', 0.42),
  ('cheese', 0.47),
  ('nuts', 0.55),
  ('chocolate chips', 0.72),
  // Ground spices & dried herbs (g/ml). FDC files these as "Spices, X" with
  // tsp/tbsp portions, but their measure unit is "undetermined" and the unit
  // sits in an amount-less description ("tsp") — so the portion matcher can't
  // use them and they fell through to nothing. Each density is BACK-DERIVED
  // from FDC's own 1-tsp gram weight (g ÷ 4.929 mL), so a volume estimate here
  // reproduces FDC's value. Keys are chosen to beat existing shorter entries by
  // length ("ground ginger" over fresh "ginger"; "dry mustard" over prepared
  // "mustard") and, for herbs with a fresh form, gated to "dried …" so a fresh
  // sprig isn't sized as fluffy dried leaf.
  ('black pepper', 0.47),
  ('white pepper', 0.49),
  ('cayenne', 0.37),
  ('paprika', 0.47),
  ('cumin', 0.43),
  ('cinnamon', 0.53),
  ('coriander', 0.37),
  ('nutmeg', 0.45),
  ('ground cloves', 0.43), // specific, so "garlic cloves" is untouched
  ('chili powder', 0.55),
  ('allspice', 0.39),
  ('ground ginger', 0.37), // beats fresh 'ginger' (0.54) by length
  ('cardamom', 0.41),
  ('turmeric', 0.61),
  ('curry powder', 0.41),
  ('ground fennel', 0.41),
  ('fennel seed', 0.41),
  ('dry mustard', 0.41), // beats prepared 'mustard' (1.05) by length
  ('ground mustard', 0.41),
  ('mustard powder', 0.41),
  ('garlic powder', 0.63),
  ('onion powder', 0.49),
  ('dried oregano', 0.20),
  ('dried thyme', 0.20),
  ('dried basil', 0.14),
  ('dried rosemary', 0.24),
  // Whole peppercorns (sweep accuracy batch): 'black pepper' (ground) sized
  // them. FDC 170931 "Spices, pepper, black" 'tsp, whole' = 2.9 g. No whole
  // MUSTARD seed entry: FDC's only record is ground (170929, tsp = 2.0 g),
  // which sized whole seeds at about half; they stay on 'mustard' (1.05)
  // until a whole-seed density is sourced (refix round 2).
  ('peppercorn', 0.59),
  ('black peppercorn', 0.59), // beats 'black pepper' (ground) by length
];

/// Piece weights (grams each) for common counted items, keyed by tokens.
/// A key's weight is PER counted unit as the recipe counts it — for items
/// always counted a particular way that means per slice (bread, bacon), per
/// ear (corn), per bulb (fennel), etc. Estimates, flagged as such in the UI.
const List<(String, double)> _pieceWeights = [
  ('large eggs', 50),
  ('large egg', 50),
  ('egg yolks', 17),
  ('egg yolk', 17),
  ('egg whites', 33),
  ('egg white', 33),
  ('eggs', 50),
  ('egg', 50),
  ('garlic cloves', 3),
  ('garlic clove', 3),
  ('garlic', 3),
  ('onion', 110),
  ('shallot', 30),
  ('scallions', 15),
  ('scallion', 15),
  // The matcher's synonym turns scallions into green onions before this
  // table sees the line, and 'onion' (110 g) caught them: 16 counted lines
  // at 110 g each. FDC 2709794 "Onions, green, raw" '1 whole' = 15 g.
  ('green onions', 15),
  ('green onion', 15),
  ('lemon', 58),
  ('lime', 44),
  ('orange', 131),
  ('carrot', 61),
  ('celery rib', 40),
  ('celery', 40),
  ('bay leaves', 0.2),
  ('bay leaf', 0.2),
  ('tomato', 123),
  ('potato', 213),
  ('apple', 182),
  ('banana', 118),
  // Whole tokens anchored to the head noun (audit 3, N7): 'apple' sized
  // pineapples at 91/182 g, 'garlic' (a clove) garlic heads at 3 g, and
  // 'tomato' 20 cherry tomatoes at 2,460 g. FDC SR 169124 "Pineapple, raw"
  // '1 fruit' = 905 g; 170457 'cherry' = 17 g; a head is about 50 g.
  ('pineapple', 905),
  ('cherry tomato', 17),
  ('garlic head', 50),
  ('bell pepper', 119),
  ('jalapeno', 14),
  ('cinnamon stick', 3),
  // Whole vegetables/fruit FDC gives no usable per-item portion for (its
  // Foundation entries carry only a ~85 g reference-serving weight).
  ('avocado', 150),
  ('english cucumber', 300),
  ('cucumber', 300),
  // FDC SR 168409 "Cucumber, with peel, raw": small (6-3/8") 158 g, medium
  // 201 g; 300 is its large (8-1/4") — 'small' read as the 300 g one.
  ('small cucumber', 158),
  ('medium cucumber', 201),
  ('zucchini', 196),
  ('leek', 89),
  ('fennel bulb', 200),
  ('fennel', 200),
  ('poblano', 45),
  ('serrano', 6),
  ('thai chile', 2),
  ('eggplant', 300), // longer key than "egg", so it wins the substring match
  // Counted-in-slices/sheets staples (per counted unit).
  ('sandwich bread', 28),
  ('bacon', 24),
  ('corn tortilla', 26),
  ('tortilla', 26),
  ('hamburger bun', 52),
  ('english muffin', 60),
  ('graham cracker', 14),
  ('ladyfinger', 11),
  ('phyllo', 19), // per sheet
  ('phyllo sheet', 19), // 'sheet' is the head of "phyllo sheets"
  ('puff pastry', 245), // per sheet (a standard frozen sheet)
  ('vanilla bean', 4),
];

/// Descriptor words that mark a RUSTIC/artisan loaf — thick, dense, crusty —
/// distinct from soft sandwich bread (which keeps its 28 g/slice table entry).
/// FDC gives these breads no usable per-slice or per-loaf portion, and the flat
/// [_pieceWeights] table can't serve them: a recipe counts them BOTH ways
/// ("8 slices country bread", "1 loaf crusty bread"), which need different
/// weights, and its substring keys wouldn't match "country WHITE bread" anyway.
const Set<String> _rusticBreadWords = {
  'rustic',
  'country',
  'crusty',
  'artisan',
  'peasant',
  'sourdough',
  'ciabatta',
  'baguette',
  'french',
  'italian',
};

const Set<String> _sliceUnits = {'slice', 'slices'};
const Set<String> _loafUnits = {'loaf', 'loaves'};

/// Grams per counted unit for a rustic/artisan bread, by the unit the recipe
/// used: a thick artisan SLICE ≈ 50 g (ATK's own "(9 ounces)" for 5 slices is
/// ~51 g/slice), a whole LOAF ≈ 454 g (its standard "1 (1-pound) loaf"). Only
/// for the crusty/rustic breads above; returns null for soft sandwich bread
/// (handled by the piece table) and for any non-slice/loaf unit. An estimate,
/// flagged as such — and only a FALLBACK: a real FDC slice/loaf portion is
/// preferred (matched earlier in the count loop).
double? _rusticBreadGrams(String normalizedItem, String unit) {
  final looksBread =
      normalizedItem.contains('bread') ||
      normalizedItem.contains('ciabatta') ||
      normalizedItem.contains('baguette');
  if (!looksBread || !_rusticBreadWords.any(normalizedItem.contains)) {
    return null;
  }
  if (_loafUnits.contains(unit)) {
    return 454;
  }
  if (_sliceUnits.contains(unit)) {
    return 50;
  }
  return null;
}

/// Result of a resolution attempt.
class GramResolution {
  /// Pairs the resolved grams with how they were determined.
  const GramResolution({
    required this.grams,
    required this.source,
    this.basis,
  });

  /// Resolved grams for the whole line.
  final double grams;

  /// How [grams] was determined.
  final GramSource source;

  /// A short, human-readable description of the INPUT the estimate ran
  /// against — so a reviewer can sanity-check it (e.g. "½ cup ≈ 118 mL" for a
  /// density estimate, or "8¾ ounces" for a direct weight). Null when there is
  /// nothing to show. Not stored; re-derived for display.
  final String? basis;
}

/// The amount as written, for a [GramResolution.basis] label ("½ cup", "2").
String _amountText(Amount amount) {
  final unit = amount.unit;
  return unit == null || unit.isEmpty
      ? amount.quantity
      : '${amount.quantity} $unit';
}

/// USER ANSWER #1 SWITCH (ranges). False (the default until the user
/// answers) sizes a parenthetical weight range written with a fraction at
/// its upper bound, as before unicode fractions were read: "(3½ to
/// 4-pound)" 1,814 g like its sibling "(3½- to 4-pound)", "(8¾ to 10
/// ounces)" 283 g (audit 3: 4 counted/check lines). True sizes it at the
/// midpoint (1,701 g; 266 g). Whole-number "(5 to 6-ounce)" keeps its
/// midpoint and "(6- to 8-ounce)" its upper bound either way — the B2
/// ruling (2026-07-28) left both as they were.
const bool rangeWeightsMidpoint = false;

double? _quantityValue(String quantity, {bool upper = false}) {
  final direct = parseQuantity(quantity);
  if (direct != null) {
    return direct;
  }
  // Ranges take the midpoint ("4-6", "4 to 6"), or the [upper] bound.
  final range = RegExp(
    r'^\s*(\S+)\s*(?:-|–|to)\s*(\S+)\s*$',
  ).firstMatch(quantity);
  if (range != null) {
    final low = parseQuantity(range.group(1)!);
    final high = parseQuantity(range.group(2)!);
    if (low != null && high != null) {
      // The larger bound: "(14⅔ to 6½ ounces) bread flour" is a corpus typo
      // for 16½, and 6½ ounces is not 2⅔–3 cups.
      return upper ? (low > high ? low : high) : (low + high) / 2;
    }
  }
  return null;
}

/// The line's volume in mL — its first volume amount — or null.
double? volumeMlOf(List<Amount> amounts) {
  for (final amount in _byPreference(amounts)) {
    final ml = _volumeUnitMl[(amount.unit ?? '').toLowerCase()];
    final quantity = _quantityValue(amount.quantity);
    if (amount.measure == Measure.volume && ml != null && quantity != null) {
      return quantity * ml;
    }
  }
  return null;
}

/// The FIRST count amount's numeric value ("2 cans" -> 2), or null.
double? _countQty(List<Amount> amounts) {
  for (final amount in amounts) {
    if (amount.measure == Measure.count) {
      final quantity = _quantityValue(amount.quantity);
      if (quantity != null) {
        return quantity;
      }
    }
  }
  return null;
}

/// Grams from the first weight printed in a raw parenthetical — the PER-unit
/// weight the amount parse missed. "(5 to 6-ounce)" -> 156 g, "(28-ounce)" ->
/// 794 g, "(about 8 ounces)" -> 227 g. Null when no parenthetical weight.
/// A weight printed in a raw parenthetical, and whether it reads PER counted
/// unit or as the line TOTAL.
///
/// Adjectival, before the food noun → per unit: "4 (5-ounce) breasts",
/// "2 (15-ounce) cans", "1 (1-pound) loaf" (and an explicit "(… each)").
/// Trailing, after the noun → total: "5 slices bread (9 ounces)",
/// "1 potato (about 8 ounces)". The distinction only changes the result when
/// the line is counted >1 — a trailing total was over-scaled by the count
/// before ("5 slices … (9 ounces)" read as 5×, a ~5× error).
({double grams, bool perUnit})? _parenWeight(String raw) {
  final weight = RegExp(
    // Unicode fractions too: "(1¼- to 1½-pound)" Cornish hens read 80 g
    // through a per-item portion, "(3½-pound)" roasts nothing (audit 1).
    '([\\d./$vulgarFractionChars]+'
    '(?:\\s*(?:to|-)\\s*[\\d./$vulgarFractionChars]+)?)\\s*-?\\s*'
    r'(ounces?|oz|pounds?|lbs?|grams?|kilograms?|kg)\b',
    caseSensitive: false,
  );
  for (final paren in RegExp(r'\(([^)]*)\)').allMatches(raw)) {
    final inner = paren.group(1)!;
    final match = weight.firstMatch(inner);
    if (match == null) {
      continue;
    }
    final text = match.group(1)!;
    final quantity = _quantityValue(
      text,
      upper:
          !rangeWeightsMidpoint &&
          text.contains(RegExp('[$vulgarFractionChars]')),
    );
    final unit = match.group(2)!.toLowerCase().replaceAll(RegExp(r's$'), '');
    final gramsPer = _weightUnitGrams[unit];
    if (quantity == null || gramsPer == null) {
      continue;
    }
    // Per unit iff the parenthetical is adjectival — nothing but the leading
    // count precedes it (no food noun, i.e. no letters) — or it says "each".
    final before = raw.substring(0, paren.start);
    final perUnit =
        inner.toLowerCase().contains('each') ||
        !RegExp('[a-z]', caseSensitive: false).hasMatch(before);
    return (grams: quantity * gramsPer, perUnit: perUnit);
  }
  return null;
}

/// The piece weight for [normalizedItem]: a key matches on WHOLE words
/// (key form), and its last word must be the item's head noun — 'apple' is
/// not in 'pineapple', and 'garlic' is not the food of 'mustard-garlic
/// butter'. The size and 'head' words normalizing strips are read back from
/// [raw] and the amount's [unit] ("1 garlic head", "1 small cucumber").
double? _pieceLookup(String normalizedItem, String? raw, String unit) {
  final alternatives = normalizedItem.split(' or ');
  final heads = {for (final item in alternatives) headNounOf(item)};
  final rawWords = (raw ?? '').toLowerCase().split(RegExp('[^a-z-]+'));
  final head =
      unit == 'head' || rawWords.contains('head') || rawWords.contains('heads');
  final sizes = [
    for (final size in const ['small', 'medium'])
      if (rawWords.contains(size)) size,
  ];
  // Each alternative as a run of key-form words, with the size before it and
  // 'head' after it: ' small cucumber ', ' whole garlic head '.
  final runs = [
    for (final item in alternatives)
      ' ${[
        ...sizes,
        ...item.split(' ').map(keyWordOf),
        if (head) 'head',
      ].join(' ')} ',
  ];
  String? bestKey;
  double? bestValue;
  for (final (key, value) in _pieceWeights) {
    final keyHead = headNounOf(key);
    // A chile is FDC's pepper: 'jalapeno chiles' is the jalapeno.
    final anchored = heads.contains(keyHead) || heads.contains('pepper');
    final run = ' ${key.split(' ').map(keyWordOf).join(' ')} ';
    if (anchored &&
        runs.any((words) => words.contains(run)) &&
        (bestKey == null || key.length > bestKey.length)) {
      bestKey = key;
      bestValue = value;
    }
  }
  return bestValue;
}

double? _tableLookup(List<(String, double)> table, String normalizedItem) {
  // Longest matching key wins, so "sour cream" beats "cream" regardless of
  // table order.
  String? bestKey;
  double? bestValue;
  for (final (key, value) in table) {
    if (normalizedItem.contains(key) &&
        (bestKey == null || key.length > bestKey.length)) {
      bestKey = key;
      bestValue = value;
    }
  }
  return bestValue;
}

/// Leading nouns in a portion description that mean a VOLUME/WEIGHT serving
/// (or a package), not a single countable item — so a bare count never scales
/// off "1 cup" or "1 serving".
const Set<String> _portionServingWords = {
  'cup',
  'cups',
  'tablespoon',
  'tablespoons',
  'tbsp',
  'teaspoon',
  'teaspoons',
  'tsp',
  'ounce',
  'ounces',
  'oz',
  'fl',
  'fluid',
  'ml',
  'milliliter',
  'liter',
  'l',
  'gram',
  'grams',
  'g',
  'lb',
  'pound',
  'quart',
  'pint',
  'gallon',
  'slice',
  'slices',
  'cubic',
  'serving',
  'package',
  'packet',
  'can',
  'bottle',
  'jar',
  'container',
  // Composite-dish language, never how a single produce/bakery item is named:
  // "1 piece"/"1 portion" of a wrong-food dish match is not one ingredient.
  'piece',
  'pieces',
  'portion',
  // Package nouns: "1 sleeve" of saltines is 115 g, not one cracker (audit
  // 2: '30 saltine crackers' counted 3,450 g).
  'sleeve',
  'box',
  'bag',
  'loaf',
};

/// Grams for ONE whole item from a portion whose description reads like a
/// single countable unit ("1 whole", "1 medium", "1 regular ear", "1 bun") as
/// opposed to a volume/weight serving ("1 cup", "1 fl oz", "1 serving"). For a
/// bare count ("1 leek") when the amount names no unit. When the food lists
/// several sizes, prefers the medium/regular one (what an unsized recipe
/// count means). Ignores Foundation "reference amount" portions (their
/// description is empty), which are a serving weight, not a whole item.
///
/// A portion whose noun the item itself names wins over any size rank:
/// "1 cracker" for 'saltine crackers', whatever FDC lists first.
double? _wholeItemPortionGrams(FdcFood food, String normalizedItem) {
  double? best;
  var bestRank = -1;
  for (final portion in food.portions) {
    final description = (portion.description ?? '').toLowerCase().trim();
    final match = RegExp(
      r'^([\d][\d./\s]*)\s*([a-z]+)',
    ).firstMatch(description);
    if (match == null) {
      continue;
    }
    final count = _quantityValue(match.group(1)!.trim());
    // Exactly one: "1 whole"/"1 medium" is a single item; "10 sprigs"/"4 large"
    // /"1/2 breast" is a multi-unit or partial serving, not one countable item.
    if (count != 1) {
      continue;
    }
    if (_portionServingWords.contains(match.group(2))) {
      continue;
    }
    // A single countable item a recipe writes as a BARE count is well under
    // 250 g (bigger ones — squash, cabbage — carry a unit or a printed
    // weight); a heavier "1 X" is a prepared-dish serving on a wrong-food
    // match ("1 piece" of "Lasagna, meatless" = 256 g), not one item.
    if (portion.gramWeight > 250) {
      continue;
    }
    final rank = normalizedItem.contains(match.group(2)!)
        ? 3
        : description.contains('regular') || description.contains('medium')
        ? 2
        : (description.contains('large') || description.contains('small')
              ? 0
              : 1);
    if (rank > bestRank) {
      // count is 1 here, so the portion weight IS the per-item weight.
      bestRank = rank;
      best = portion.gramWeight;
    }
  }
  return best;
}

/// Count units that name a PACKAGE, not a whole food — their weight is the
/// package size, which comes from a printed weight (the parenthetical handled
/// earlier). Without one we cannot know it, so a whole-item table value
/// ("1 can diced tomatoes" ≠ one 123 g tomato) must not fill in; leave it null.
const Set<String> _containerUnits = {
  'can',
  'cans',
  'jar',
  'jars',
  'bottle',
  'bottles',
  'package',
  'packages',
  'packet',
  'packets',
  'envelope',
  'envelopes',
  'block',
  'blocks',
  'bar',
  'bars',
  'cube',
  'cubes',
  'container',
  'containers',
  'box',
  'boxes',
  'tube',
  'tubes',
  // A strip of zest or a wedge is a piece of the fruit, not the fruit: "12
  // (3-inch) strips lemon zest" counted 12 whole lemons (696 g). Without a
  // portion of its own the line goes to review.
  'strip',
  'strips',
  'wedge',
  'wedges',
};

/// A portion keyed by a STRUCTURED piece/each/whole/unit measure (some foods
/// carry a `unit=piece, amount=n` portion whose description has no leading
/// count). Structured only — NOT a description text match, so it cannot
/// re-admit a "1 piece" dish serving the whole-item finder already excluded.
double? _legacyPiecePortion(FdcFood food) {
  const units = {'piece', 'pieces', 'each', 'whole', 'unit', 'units'};
  for (final portion in food.portions) {
    if (!units.contains((portion.unit ?? '').toLowerCase())) {
      continue;
    }
    final amount = portion.amount ?? 1;
    if (amount <= 0) {
      continue;
    }
    final perItem = portion.gramWeight / amount;
    if (perItem > 250) {
      continue; // same single-item sanity bound as the whole-item finder
    }
    return perItem;
  }
  return null;
}

/// Grams-per-single-[unit] from the food's own portions, when one matches.
double? _portionGramsPerUnit(FdcFood food, String unit) {
  final wanted = unit.toLowerCase();
  for (final portion in food.portions) {
    final portionUnit = portion.unit ?? '';
    final description = (portion.description ?? '').toLowerCase();
    double? amount;
    if (portionUnit == wanted || portionUnit == '${wanted}s') {
      amount = portion.amount ?? 1;
    } else if (description.contains(wanted)) {
      // A description-only match ("0.25 cup, sifted") is trusted only when
      // the description leads with its own parseable amount — the structured
      // `amount` field belongs to the (non-matching) measure unit, so
      // defaulting to 1 here would silently mis-scale the weight.
      final leading = RegExp(r'^([\d][\d./\s]*)').firstMatch(description);
      final parsed = leading == null
          ? null
          : _quantityValue(leading.group(1)!.trim());
      if (parsed == null) {
        continue;
      }
      amount = parsed;
    } else {
      continue;
    }
    if (amount <= 0) {
      continue;
    }
    return portion.gramWeight / amount;
  }
  return null;
}

/// Grams per mL from the food's OWN volume portions, for a volume line the
/// density table does not cover. SR Legacy writes a volume portion as
/// "tbsp"/"tsp"/"cup chopped" with the count in the structured amount (the
/// unit field is "undetermined", so [_portionGramsPerUnit] never matches
/// 'tablespoon' to it); FNDDS writes "1 cup". Audit 1: 190 no_grams lines on
/// the right food (parsley, black pepper, capers, thyme). Called AFTER the
/// density table, never before: food-first sized 26 kosher-salt lines ×1.71
/// on table salt's portion. A portion that names its volume only in
/// parentheses — 169599 gelatin's "envelope (1 tbsp)" = 7 g — is read when
/// no portion leads with one: the count there is the whole portion's, so the
/// structured amount is not applied (audit 3 refix: 30 gelatin lines).
double? _foodGramsPerMl(FdcFood food) {
  double? parenthesized;
  for (final portion in food.portions) {
    final description = (portion.description ?? '').toLowerCase().trim();
    final lead = RegExp(
      r'^([\d][\d./\s]*)?\s*([a-z]+)',
    ).firstMatch(description);
    var unit = _volumeAliases[(portion.unit ?? '').toLowerCase()];
    var amount = portion.amount;
    if (unit == null && lead != null) {
      unit = _volumeAliases[lead.group(2)];
      final count = lead.group(1);
      if (count != null) {
        amount = _quantityValue(count.trim());
      }
    }
    if (unit == null || amount == null || amount <= 0) {
      final paren = RegExp(
        r'\((\d[\d./\s]*?)\s*([a-z]+)',
      ).firstMatch(description);
      final inner = _volumeAliases[paren?.group(2)];
      final count = paren == null ? null : _quantityValue(paren.group(1)!);
      if (inner != null && count != null && count > 0) {
        parenthesized ??= portion.gramWeight / (count * _volumeUnitMl[inner]!);
      }
      continue;
    }
    return portion.gramWeight / (amount * _volumeUnitMl[unit]!);
  }
  return parenthesized;
}

/// Portion spellings of a volume unit → the [_volumeUnitMl] key.
const Map<String, String> _volumeAliases = {
  'tbsp': 'tablespoon',
  'tbs': 'tablespoon',
  'tablespoon': 'tablespoon',
  'tablespoons': 'tablespoon',
  'tsp': 'teaspoon',
  'teaspoon': 'teaspoon',
  'teaspoons': 'teaspoon',
  'cup': 'cup',
  'cups': 'cup',
  'fl': 'fluid ounce',
  'pint': 'pint',
  'quart': 'quart',
};

/// The second amount of a "plus" line: "¾ cup plus 2 tablespoons vegetable
/// oil", "6 sprigs parsley, plus 2 teaspoons minced", "2 teaspoons lemon zest
/// plus 2 tablespoons juice", "2 large eggs plus 1 large yolk". The corpus
/// parse keeps only the first amount, so the second was dropped (audit 1:
/// 26 volume-plus lines, 1,243 g) or, naming another food, silently left out.
class PlusPart {
  /// Pairs the second amount with what it names.
  const PlusPart({
    required this.amount,
    required this.text,
    required this.sameFood,
    this.weighsTotal = false,
  });

  /// The second amount as parsed.
  final Amount amount;

  /// The second part as written ("2 tablespoons juice").
  final String text;

  /// Whether the second part names no food beyond the first part's (or the
  /// first part names none: "¼ cup plus 2 teaspoons olive oil").
  final bool sameFood;

  /// Whether a parenthesis after the second amount weighs the WHOLE line
  /// ("1 teaspoon plus 1⅛ cups (8 ounces) sugar"): the weight already is the
  /// total, so the second amount is never added to it.
  final bool weighsTotal;
}

/// USER ANSWER #4 SWITCH (edible yield). True (the recommended default)
/// scales a weight on a bone-in cut, a whole bird or shellfish in the shell
/// by the edible yield FDC publishes for the matched record — its raw
/// "excluding refuse (yield from 1 raw chop, with refuse, weighing 151 g)"
/// portion (167833, a bone-in rib chop: 0.57) — and shows it in the basis.
/// FDC's nutrients are per 100 g EDIBLE, so the printed gross weight counted
/// bone as meat (audit 2: 59 counted lines, 143.7 kg). A record without such
/// a portion is left at the printed weight (no factor is guessed); false
/// turns the scaling off.
const bool edibleYieldOn = true;

/// A raw line that buys bone, a carcass or a shell by weight — the audit's
/// classifier (audit1/bone2.py). Boneless, ground and broth lines never are.
bool buysRefuse(String raw) {
  final line = raw.toLowerCase();
  if (RegExp(r'boneless|broth|stock|\bground\b').hasMatch(line)) {
    return false;
  }
  return RegExp(
    r'giblets|whole chicken|whole turkey\b|\) turkey\b|\bturkey \(|'
    'shoulder chops?|with or without bone|'
    'bone-in|standing rib|oxtails?|shanks?|racks? of|short ribs|spareribs|'
    r'baby back|drumsticks?|wings?\b|leg quarters?|'
    r'clams|mussels|oysters|lobsters?|shell-on|in the shell|crabs?\b',
  ).hasMatch(line);
}

/// The edible share of [food] as bought: FDC's own raw refuse portion
/// ("…excluding refuse (yield from 1 raw chop, with refuse, weighing 151
/// g)" = 86 g → 0.57), or null when the record publishes none.
double? edibleYieldOf(FdcFood food) {
  final refuse = RegExp(
    r'yield from 1 raw .*with refuse, weighing ([\d.]+) ?g',
  );
  for (final portion in food.portions) {
    final gross = refuse.firstMatch((portion.description ?? '').toLowerCase());
    final weighing = gross == null ? null : double.tryParse(gross.group(1)!);
    if (weighing == null || weighing <= 0) {
      continue;
    }
    final edible = portion.gramWeight / (portion.amount ?? 1);
    if (edible > 0 && edible < weighing) {
      return edible / weighing;
    }
  }
  return null;
}

/// Words of a second part that name no food ("at room temperature",
/// "16 individual raspberries", "reserved").
const Set<String> _plusFiller = {
  'and',
  'at',
  'room',
  'temperature',
  'very',
  'cold',
  'individual',
  'reserved',
};

/// The [PlusPart] of [raw], or null: only a NUMBER right after "plus" is a
/// second amount ("plus extra for serving" is not), and a part that says
/// what it is for ("plus 2 Thai chiles, sliced thin, for serving") is an
/// optional extra, never part of the line.
PlusPart? plusPartOf(String raw) {
  // "(about 2 tablespoons plus 2 teaspoons)" restates the first amount. The
  // blanking keeps every position, so [raw] still shows where a paren was.
  final text = raw.replaceAllMapped(
    RegExp(r'\([^)]*\)'),
    (paren) => ' ' * paren[0]!.length,
  );
  final plus = RegExp(
    '\\bplus\\s+(?=[\\d$vulgarFractionChars])',
    caseSensitive: false,
  ).firstMatch(text);
  if (plus == null) {
    return null;
  }
  var rest = text.substring(plus.end);
  final next = rest.toLowerCase().indexOf(' plus ');
  if (next >= 0) {
    rest = rest.substring(0, next);
  }
  if (RegExp(r'\bfor\b', caseSensitive: false).hasMatch(rest)) {
    return null;
  }
  // The amount and its food end at the first comma ("plus 4 tablespoons,
  // softened"); "2 additional tablespoons" is 2 tablespoons.
  final comma = rest.indexOf(',');
  final span = comma < 0 ? rest.length : comma;
  final part = rest
      .substring(0, span)
      .replaceAll(RegExp(r'\badditional\s+', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final second = parseIngredientLine(part);
  if (second.amounts.isEmpty) {
    return null;
  }
  // The words that could name a food: not a count noun, not a participle
  // or adverb ("melted and cooled slightly"), not a filler.
  Set<String> foodWords(String? item) => {
    for (final word in itemKeyFor(item ?? '').split(' '))
      if (word.isNotEmpty &&
          !isCountNoun(word) &&
          !word.endsWith('ed') &&
          !word.endsWith('ly') &&
          !_plusFiller.contains(word))
        word,
  };
  final firstWords = foodWords(
    parseIngredientLine(
      text.substring(0, plus.start).replaceAll(RegExp(r'\s+'), ' '),
    ).item,
  );
  return PlusPart(
    amount: second.amounts.first,
    text: part,
    sameFood:
        firstWords.isEmpty || firstWords.containsAll(foodWords(second.item)),
    // "½ cup (3½ ounces) plus 2 tablespoons sugar" weighs only the first.
    weighsTotal:
        raw.substring(plus.end, plus.end + span).contains('(') &&
        !raw.substring(0, plus.start).contains('('),
  );
}

/// A recipe's small measures → the FDC portion name that sizes them: FDC
/// has no "pinch", and a pinch is the same pinch of spice as its "dash".
const Map<String, String> _smallMeasures = {
  'pinch': 'dash',
  'pinches': 'dash',
  'dash': 'dash',
  'dashes': 'dash',
  'sprig': 'sprig',
  'sprigs': 'sprig',
};

/// Grams per [unit] (a [_smallMeasures] key) from the food's portion whose
/// description LEADS with that portion name (SR "dash", "sprig" with the
/// count in the structured amount; "10 sprigs" with it in the text).
double? _smallMeasureGrams(FdcFood food, String unit) {
  final wanted = _smallMeasures[unit];
  if (wanted == null) {
    return null;
  }
  final named = RegExp('^(?:([\\d][\\d./\\s]*)\\s*)?${wanted}s?\\b');
  for (final portion in food.portions) {
    final match = named.firstMatch(
      (portion.description ?? '').toLowerCase().trim(),
    );
    if (match == null) {
      continue;
    }
    final count = match.group(1) == null
        ? portion.amount
        : _quantityValue(match.group(1)!.trim());
    if (count != null && count > 0) {
      return portion.gramWeight / count;
    }
  }
  return null;
}

/// Resolves one ingredient line to grams using its parsed [amounts], the
/// matched [food] (may be null), and the normalized item (for the fallback
/// tables). Null when nothing resolvable exists. A same-food second amount
/// ([plusPartOf]) is added: "¾ cup plus 2 tablespoons oil" is both.
GramResolution? resolveGrams({
  required List<Amount> amounts,
  required FdcFood? food,
  required String normalizedItem,
  String? raw,
}) {
  var first = _resolveGrams(
    amounts: amounts,
    food: food,
    normalizedItem: normalizedItem,
    raw: raw,
  );
  final yieldFactor =
      !edibleYieldOn ||
          first?.source != GramSource.weight ||
          food == null ||
          raw == null ||
          !buysRefuse(raw)
      ? null
      : edibleYieldOf(food);
  if (yieldFactor != null) {
    first = GramResolution(
      grams: first!.grams * yieldFactor,
      source: first.source,
      basis:
          '${first.basis} × ${yieldFactor.toStringAsFixed(2)} edible '
          '(USDA refuse)',
    );
  }
  final drained = first?.source == GramSource.weight && raw != null
      ? _drainedCanGrams(amounts, food, raw)
      : null;
  if (drained != null) {
    first = GramResolution(
      grams: drained,
      source: GramSource.weight,
      basis: '${first!.basis} · drained (USDA can portion)',
    );
  }
  final plus = raw == null || first == null ? null : plusPartOf(raw);
  // A counted extra of the same food ("plus 1 lemon, cut into wedges") is
  // for serving, not in the dish; only a measured second amount is added.
  if (plus == null ||
      !plus.sameFood ||
      plus.amount.measure == Measure.count ||
      (plus.weighsTotal && first!.source == GramSource.weight)) {
    return first;
  }
  final second = _resolveGrams(
    amounts: [plus.amount],
    food: food,
    normalizedItem: normalizedItem,
  );
  if (second == null) {
    return first;
  }
  return GramResolution(
    grams: first!.grams + second.grams,
    source: first.source,
    basis: '${first.basis ?? ''} + ${plus.text}',
  );
}

/// A line that opens with a quantity and a volume unit.
final RegExp _lostVolumeUnit = RegExp(
  '^\\s*[\\d$vulgarFractionChars/ .-]+\\s*(cups?|tablespoons?|teaspoons?)\\b',
  caseSensitive: false,
);

/// USER ANSWER SWITCH (canned beans, audit 3). True (the default) counts a
/// can the line drains or rinses at its DRAINED weight — the food's own
/// USDA portion for a drained can — instead of the can's net weight (425 g
/// for 15 oz, about 240 g of it beans). False counts the net weight. Only a
/// record that publishes such a portion is changed; none of the records
/// cached today does (their details are pending live fetches), so until then
/// the net weight stands.
const bool cannedDrained = true;

/// [raw]'s cans at their drained weight on [food], or null.
double? _drainedCanGrams(List<Amount> amounts, FdcFood? food, String raw) {
  final text = raw.toLowerCase();
  if (!cannedDrained ||
      food == null ||
      !RegExp(r'\bcans?\b').hasMatch(text) ||
      !RegExp(r'\b(drained|rinsed)\b').hasMatch(text) ||
      RegExp(r'\b(undrained|do not drain)\b').hasMatch(text)) {
    return null;
  }
  final cans = amounts
      .where(
        (a) =>
            a.measure == Measure.count &&
            RegExp(r'^cans?$').hasMatch((a.unit ?? '').toLowerCase()),
      )
      .map((a) => _quantityValue(a.quantity))
      .whereType<double>()
      .firstOrNull;
  if (cans == null) {
    return null;
  }
  for (final portion in food.portions) {
    final name = (portion.description ?? '').toLowerCase();
    if (name.contains('can') && name.contains('drained')) {
      return cans * portion.gramWeight / (portion.amount ?? 1);
    }
  }
  return null;
}

GramResolution? _resolveGrams({
  required List<Amount> amounts,
  required FdcFood? food,
  required String normalizedItem,
  String? raw,
}) {
  // 1. Any weight amount converts directly — including the secondary of a
  //    dual "1¾ cups (8¾ ounces)" pair, which is exactly why ATK prints it.
  for (final amount in _byPreference(amounts)) {
    if (amount.measure != Measure.weight) {
      continue;
    }
    final quantity = _quantityValue(amount.quantity);
    final perUnit = _weightUnitGrams[(amount.unit ?? '').toLowerCase()];
    if (quantity != null && perUnit != null) {
      return GramResolution(
        grams: quantity * perUnit,
        source: GramSource.weight,
        basis: 'from ${_amountText(amount)}',
      );
    }
  }

  // 1b. A weight printed in a raw PARENTHETICAL that the amount parse dropped
  //     ("4 (5 to 6-ounce) chicken breasts", "2 (15-ounce) cans", "1 russet
  //     potato (about 8 ounces)"). It reads PER counted unit, so scale by the
  //     count; with no count it is the line total. Still the gold-standard
  //     weight source — preferred over piece/density estimates below.
  if (raw != null) {
    final paren = _parenWeight(raw);
    if (paren != null) {
      final count = _countQty(amounts);
      // A per-unit weight scales by the count; a trailing total is the line as
      // written (scaling it by the count is the ~5× "N slices … (X oz)" bug).
      final scaled = paren.perUnit && count != null && count > 1;
      final grams = scaled ? paren.grams * count : paren.grams;
      final countLabel = count == null
          ? null
          : (count == count.roundToDouble()
                ? count.toInt().toString()
                : count.toString());
      return GramResolution(
        grams: grams,
        source: GramSource.weight,
        basis: scaled
            ? '$countLabel × ${paren.grams.round()} g (printed weight)'
            : 'from the printed weight',
      );
    }
  }

  // 2. Volume through the food's portions, then the density table.
  for (final amount in _byPreference(amounts)) {
    if (amount.measure != Measure.volume) {
      continue;
    }
    final quantity = _quantityValue(amount.quantity);
    final unit = (amount.unit ?? '').toLowerCase();
    final ml = _volumeUnitMl[unit];
    if (quantity == null || ml == null) {
      continue;
    }
    if (food != null) {
      final perUnit = _portionGramsPerUnit(food, unit);
      if (perUnit != null) {
        return GramResolution(
          grams: quantity * perUnit,
          source: GramSource.portion,
          basis: '${_amountText(amount)} · USDA portion',
        );
      }
    }
    final density = _tableLookup(_densities, normalizedItem);
    if (density != null) {
      return GramResolution(
        grams: quantity * ml * density,
        source: GramSource.density,
        basis: '${_amountText(amount)} ≈ ${(quantity * ml).round()} mL',
      );
    }
    final perMl = food == null ? null : _foodGramsPerMl(food);
    if (perMl != null) {
      return GramResolution(
        grams: quantity * ml * perMl,
        source: GramSource.portion,
        basis: '${_amountText(amount)} · USDA portion',
      );
    }
  }

  // 3. Counts through piece portions / the piece table.
  for (final amount in _byPreference(amounts)) {
    if (amount.measure != Measure.count) {
      continue;
    }
    final amountUnit = (amount.unit ?? '').toLowerCase();
    // "Pinch cayenne pepper" parses with an empty quantity: one pinch.
    final quantity =
        _quantityValue(amount.quantity) ??
        (amount.quantity.trim().isEmpty &&
                _smallMeasures.containsKey(amountUnit)
            ? 1
            : null);
    if (quantity == null) {
      continue;
    }
    // A unit the parse lost: "½ cup plus 1 tablespoon half-and-half or milk"
    // came through as the bare count ½ and was sized as half a piece (7.5 g,
    // Strawberry Shortcakes; audit 3). No grams beats a wrong count.
    if (amountUnit.isEmpty && raw != null && _lostVolumeUnit.hasMatch(raw)) {
      continue;
    }
    // A pinch, a dash, a sprig: the food's own FDC portion of that name
    // ("dash" 0.1 g of black pepper, 0.4 g of salt; "sprig" of parsley), the
    // count in its structured amount (user answer #3's second half).
    final small = food == null ? null : _smallMeasureGrams(food, amountUnit);
    if (small != null) {
      return GramResolution(
        grams: quantity * small,
        source: GramSource.piece,
        basis: '${_amountText(amount)} · USDA portion',
      );
    }

    // 3a. The amount's OWN unit against the food's portions — "6 ears corn",
    //     "1 head lettuce": the recipe named the unit, so it is authoritative.
    if (food != null && amountUnit.isNotEmpty) {
      final perUnit = _portionGramsPerUnit(food, amountUnit);
      if (perUnit != null) {
        return GramResolution(
          grams: quantity * perUnit,
          source: GramSource.piece,
          basis: '${_amountText(amount)} · USDA portion',
        );
      }
    }

    // 3a.5 Rustic/artisan bread the flat piece table can't serve — its weight
    //      depends on the UNIT (thick slice vs whole loaf), not just the name.
    //      After 3a so a real FDC slice/loaf portion still wins.
    final breadGrams = _rusticBreadGrams(normalizedItem, amountUnit);
    if (breadGrams != null) {
      return GramResolution(
        grams: quantity * breadGrams,
        source: GramSource.piece,
        basis: '${_amountText(amount)} × ${breadGrams.round()} g each',
      );
    }

    // 3b. The curated piece table — hand-tuned to ATK's meaning, so it beats a
    //     fuzzy whole-item portion (a "graham cracker" is the 14 g rectangle,
    //     not FDC's ambiguous per-cracker serving). Skipped for a container
    //     count with no printed size — a whole-item weight is not a can.
    //     Skipped too for a bunch: every entry is per piece, and '2 bunches
    //     scallions' read as 2 scallions (30 g).
    final pieceWeight =
        _containerUnits.contains(amountUnit) || amountUnit == 'bunch'
        ? null
        : _pieceLookup(normalizedItem, raw, amountUnit);
    if (pieceWeight != null) {
      return GramResolution(
        grams: quantity * pieceWeight,
        source: GramSource.piece,
        basis: '${_amountText(amount)} × ${pieceWeight.round()} g each',
      );
    }

    // 3c. A BARE count on an uncovered item: the food's own whole-item weight,
    //     then the legacy generic-piece portion. Last, because it is the
    //     fuzziest — a wrong-food match can carry a large "1 serving" portion.
    //     Only for bare counts: if the recipe named a unit ("1 bunch parsley")
    //     that 3a could not match, guessing off an unrelated "1 sprig" is worse
    //     than leaving the line for review.
    if (food != null && amountUnit.isEmpty) {
      final perUnit =
          _wholeItemPortionGrams(food, normalizedItem) ??
          _legacyPiecePortion(food);
      if (perUnit != null) {
        return GramResolution(
          grams: quantity * perUnit,
          source: GramSource.piece,
          basis: '${_amountText(amount)} · USDA per-item weight',
        );
      }
    }
  }
  return null;
}

/// Primary amount first, then the rest in written order.
Iterable<Amount> _byPreference(List<Amount> amounts) sync* {
  for (final amount in amounts) {
    if (amount.primary) {
      yield amount;
    }
  }
  for (final amount in amounts) {
    if (!amount.primary) {
      yield amount;
    }
  }
}
