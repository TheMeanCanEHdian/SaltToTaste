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
  ('peanut butter', 1.09),
  ('jam', 1.35),
  ('breadcrumbs', 0.45),
  ('panko', 0.25),
  ('parmesan', 0.42),
  ('cheese', 0.47),
  ('nuts', 0.55),
  ('chocolate chips', 0.72),
];

/// Piece weights (grams each) for common counted items, keyed by tokens.
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
];

/// Result of a resolution attempt.
class GramResolution {
  /// Pairs the resolved grams with how they were determined.
  const GramResolution({required this.grams, required this.source});

  /// Resolved grams for the whole line.
  final double grams;

  /// How [grams] was determined.
  final GramSource source;
}

double? _quantityValue(String quantity) {
  final direct = parseQuantity(quantity);
  if (direct != null) {
    return direct;
  }
  // Ranges take the midpoint ("4-6", "4 to 6").
  final range =
      RegExp(r'^\s*(\S+)\s*(?:-|–|to)\s*(\S+)\s*$').firstMatch(quantity);
  if (range != null) {
    final low = parseQuantity(range.group(1)!);
    final high = parseQuantity(range.group(2)!);
    if (low != null && high != null) {
      return (low + high) / 2;
    }
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
      final parsed =
          leading == null ? null : _quantityValue(leading.group(1)!.trim());
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
        );
      }
    }
    final density = _tableLookup(_densities, normalizedItem);
    if (density != null) {
      return GramResolution(
        grams: quantity * ml * density,
        source: GramSource.density,
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
    if (food != null) {
      for (final unit in const ['piece', 'each', 'whole', 'unit']) {
        final perUnit = _portionGramsPerUnit(food, unit);
        if (perUnit != null) {
          return GramResolution(
            grams: quantity * perUnit,
            source: GramSource.piece,
          );
        }
      }
    }
    final pieceWeight = _tableLookup(_pieceWeights, normalizedItem);
    if (pieceWeight != null) {
      return GramResolution(
        grams: quantity * pieceWeight,
        source: GramSource.piece,
      );
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
