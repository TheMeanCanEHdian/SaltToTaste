/// Amount → grams resolution, in confidence order: a weight amount converts
/// directly; a volume amount goes through the food's own household portions,
/// falling back to a built-in density table; a count goes through piece
/// portions or a piece-weight table.
library;

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
  ('bell pepper', 119),
  ('jalapeno', 14),
  ('cinnamon stick', 3),
  // Whole vegetables/fruit FDC gives no usable per-item portion for (its
  // Foundation entries carry only a ~85 g reference-serving weight).
  ('avocado', 150),
  ('english cucumber', 300),
  ('cucumber', 300),
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

double? _quantityValue(String quantity) {
  final direct = parseQuantity(quantity);
  if (direct != null) {
    return direct;
  }
  // Ranges take the midpoint ("4-6", "4 to 6").
  final range = RegExp(
    r'^\s*(\S+)\s*(?:-|–|to)\s*(\S+)\s*$',
  ).firstMatch(quantity);
  if (range != null) {
    final low = parseQuantity(range.group(1)!);
    final high = parseQuantity(range.group(2)!);
    if (low != null && high != null) {
      return (low + high) / 2;
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
    r'([\d./]+(?:\s*(?:to|-)\s*[\d./]+)?)\s*-?\s*'
    r'(ounces?|oz|pounds?|lbs?|grams?|kilograms?|kg)\b',
    caseSensitive: false,
  );
  for (final paren in RegExp(r'\(([^)]*)\)').allMatches(raw)) {
    final inner = paren.group(1)!;
    final match = weight.firstMatch(inner);
    if (match == null) {
      continue;
    }
    final quantity = _quantityValue(match.group(1)!);
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
};

/// Grams for ONE whole item from a portion whose description reads like a
/// single countable unit ("1 whole", "1 medium", "1 regular ear", "1 bun") as
/// opposed to a volume/weight serving ("1 cup", "1 fl oz", "1 serving"). For a
/// bare count ("1 leek") when the amount names no unit. When the food lists
/// several sizes, prefers the medium/regular one (what an unsized recipe
/// count means). Ignores Foundation "reference amount" portions (their
/// description is empty), which are a serving weight, not a whole item.
double? _wholeItemPortionGrams(FdcFood food) {
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
    final rank =
        description.contains('regular') || description.contains('medium')
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

/// Resolves one ingredient line to grams using its parsed [amounts], the
/// matched [food] (may be null), and the normalized item (for the fallback
/// tables). Null when nothing resolvable exists.
GramResolution? resolveGrams({
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
  }

  // 3. Counts through piece portions / the piece table.
  for (final amount in _byPreference(amounts)) {
    if (amount.measure != Measure.count) {
      continue;
    }
    final quantity = _quantityValue(amount.quantity);
    if (quantity == null) {
      continue;
    }
    final amountUnit = (amount.unit ?? '').toLowerCase();

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
    final pieceWeight = _containerUnits.contains(amountUnit)
        ? null
        : _tableLookup(_pieceWeights, normalizedItem);
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
      final perUnit = _wholeItemPortionGrams(food) ?? _legacyPiecePortion(food);
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
