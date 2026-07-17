/// Provider abstraction over USDA FoodData Central: search + food detail,
/// with the trimmed shapes the matcher and gram resolver consume.
library;

/// One search hit — enough to rank, to show in the re-pick UI, and (via
/// [nutrientsPer100g], which FDC includes in search responses) to stand in
/// for the detail record when FDC 404s a superseded food's detail.
class FdcCandidate {
  /// Builds a candidate from its parts.
  const FdcCandidate({
    required this.fdcId,
    required this.description,
    required this.dataType,
    this.nutrientsPer100g,
  });

  /// Decodes the cache-JSON form produced by [toJson].
  factory FdcCandidate.fromJson(Map<String, dynamic> json) => FdcCandidate(
    fdcId: (json['fdc_id']! as num).toInt(),
    description: json['description']! as String,
    dataType: json['data_type']! as String,
    nutrientsPer100g: json['nutrients'] is Map<String, dynamic>
        ? {
            for (final entry
                in (json['nutrients']! as Map<String, dynamic>).entries)
              entry.key: (entry.value as num).toDouble(),
          }
        : null,
  );

  /// FDC's stable food id.
  final int fdcId;

  /// FDC's food description ("Flour, wheat, all-purpose, unenriched").
  final String description;

  /// `Foundation` or `SR Legacy`.
  final String dataType;

  /// Per-100 g nutrient amounts from the SEARCH response (FDC includes
  /// them), keyed by nutrient number — the detail-404 fallback.
  final Map<String, double>? nutrientsPer100g;

  /// A portion-less food built from the search payload.
  FdcFood toFood() => FdcFood(
    fdcId: fdcId,
    description: description,
    dataType: dataType,
    nutrientsPer100g: nutrientsPer100g ?? const {},
    portions: const [],
  );

  /// Cache-JSON form.
  Map<String, Object?> toJson() => {
    'fdc_id': fdcId,
    'description': description,
    'data_type': dataType,
    if (nutrientsPer100g != null) 'nutrients': nutrientsPer100g,
  };
}

/// A household-measure portion of a food (`1 cup` → 125 g).
class FdcPortion {
  /// Builds a portion from its parts.
  const FdcPortion({
    required this.gramWeight,
    this.amount,
    this.unit,
    this.description,
  });

  /// Decodes the cache-JSON form produced by [toJson].
  factory FdcPortion.fromJson(Map<String, dynamic> json) => FdcPortion(
    gramWeight: (json['gram_weight']! as num).toDouble(),
    amount: (json['amount'] as num?)?.toDouble(),
    unit: json['unit'] as String?,
    description: json['description'] as String?,
  );

  /// Grams of the whole portion.
  final double gramWeight;

  /// How many [unit]s the portion is (e.g. 1 for `1 cup`), when known.
  final double? amount;

  /// Household unit name, lowercased (`cup`, `tablespoon`, `piece`...).
  final String? unit;

  /// Free-text portion description (SR Legacy household measures).
  final String? description;

  /// Cache-JSON form.
  Map<String, Object?> toJson() => {
    'gram_weight': gramWeight,
    'amount': amount,
    'unit': unit,
    'description': description,
  };
}

/// Food detail: per-100 g nutrient amounts (keyed by FDC nutrient number)
/// plus household portions.
class FdcFood {
  /// Builds a food from its parts.
  const FdcFood({
    required this.fdcId,
    required this.description,
    required this.dataType,
    required this.nutrientsPer100g,
    required this.portions,
  });

  /// Decodes the cache-JSON form produced by [toJson].
  factory FdcFood.fromJson(Map<String, dynamic> json) => FdcFood(
    fdcId: (json['fdc_id']! as num).toInt(),
    description: json['description']! as String,
    dataType: json['data_type']! as String,
    nutrientsPer100g: {
      for (final entry in (json['nutrients']! as Map<String, dynamic>).entries)
        entry.key: (entry.value as num).toDouble(),
    },
    portions: [
      for (final portion in json['portions']! as List<dynamic>)
        FdcPortion.fromJson(portion as Map<String, dynamic>),
    ],
  );

  /// FDC's stable food id.
  final int fdcId;

  /// FDC's food description.
  final String description;

  /// `Foundation` or `SR Legacy`.
  final String dataType;

  /// FDC nutrient number → amount per 100 g (in the nutrient's own unit).
  final Map<String, double> nutrientsPer100g;

  /// Household portions (`1 cup` → grams), possibly empty.
  final List<FdcPortion> portions;

  /// Cache-JSON form.
  Map<String, Object?> toJson() => {
    'fdc_id': fdcId,
    'description': description,
    'data_type': dataType,
    'nutrients': nutrientsPer100g,
    'portions': [for (final portion in portions) portion.toJson()],
  };
}

/// Thrown when FDC cannot be used at all (no key configured, invalid key).
class NutritionProviderException implements Exception {
  /// Creates the exception with its user-facing [message].
  const NutritionProviderException(this.message);

  /// User-facing explanation (no key material, ever).
  final String message;

  @override
  String toString() => message;
}

/// Search + detail against a nutrition database. The production
/// implementation is USDA FDC; tests substitute one backed by recorded
/// real responses.
abstract interface class NutritionProvider {
  /// Best candidates for a normalized ingredient query, most relevant
  /// first (provider order; the matcher re-ranks).
  Future<List<FdcCandidate>> search(String query);

  /// Full detail for one food, or null when it does not exist.
  Future<FdcFood?> food(int fdcId);
}
