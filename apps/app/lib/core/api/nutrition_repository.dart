import 'package:dio/dio.dart';

import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException, apiGuard;

/// One nutrient row of the computed label.
class NutrientValue {
  const NutrientValue({
    required this.key,
    required this.label,
    required this.amount,
    required this.unit,
    this.dvPercent,
  });

  final String key;
  final String label;
  final double amount;
  final String unit;

  /// % Daily Value, or null when the FDA defines none (total sugars,
  /// trans fat, mono/poly).
  final double? dvPercent;
}

/// The computed per-serving label for a recipe.
class RecipeNutrition {
  const RecipeNutrition({
    required this.status,
    this.servingBasis,
    this.caloriesPerServing,
    this.perServing = const {},
    this.totalGrams,
    this.matchedCount = 0,
    this.totalCount = 0,
    this.lowConfidence = 0,
    this.computedAt,
    this.computingJobId,
  });

  factory RecipeNutrition.fromJson(Map<String, dynamic> json) {
    final perServing = <String, NutrientValue>{};
    final raw = json['per_serving'];
    if (raw is Map<String, dynamic>) {
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic> && value['amount'] is num) {
          perServing[entry.key] = NutrientValue(
            key: entry.key,
            label: value['label'] as String? ?? entry.key,
            amount: (value['amount']! as num).toDouble(),
            unit: value['unit'] as String? ?? '',
            dvPercent: (value['dv_percent'] as num?)?.toDouble(),
          );
        }
      }
    }
    return RecipeNutrition(
      status: json['status'] as String? ?? 'none',
      servingBasis: (json['serving_basis'] as num?)?.toInt(),
      caloriesPerServing: (json['calories_per_serving'] as num?)?.toDouble(),
      perServing: perServing,
      totalGrams: (json['total_grams'] as num?)?.toDouble(),
      matchedCount: (json['matched_count'] as num?)?.toInt() ?? 0,
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
      lowConfidence: (json['low_confidence'] as num?)?.toInt() ?? 0,
      computedAt: json['computed_at'] as String?,
      computingJobId: (json['computing_job_id'] as num?)?.toInt(),
    );
  }

  /// `none` | `complete` | `partial` | `stale`.
  final String status;
  final int? servingBasis;
  final double? caloriesPerServing;

  /// Nutrient key → value, in the server's (label) order.
  final Map<String, NutrientValue> perServing;
  final double? totalGrams;

  /// Lines contributing nutrients vs total ingredient lines.
  final int matchedCount;
  final int totalCount;

  /// Auto matches below 0.5 confidence that nobody has reviewed yet.
  final int lowConfidence;
  final String? computedAt;

  /// A background compute in flight for this recipe (the client polls this
  /// job and re-attaches to it after navigating away and back). Null when
  /// nothing is running.
  final int? computingJobId;

  bool get exists => status != 'none';

  /// The badge stays amber while anything needs a human look: an
  /// unmatched line, or an unreviewed low-confidence match.
  bool get needsReview => matchedCount < totalCount || lowConfidence > 0;
}

/// One ingredient line's match state on the review sheet.
class IngredientMatch {
  const IngredientMatch({
    required this.position,
    required this.raw,
    this.fdcId,
    this.description,
    this.dataType,
    this.confidence = 0,
    this.grams,
    this.gramSource,
    this.status = 'unmatched',
    this.candidates = const [],
  });

  factory IngredientMatch.fromJson(Map<String, dynamic> json) {
    final match = json['match'];
    final candidates = <MatchCandidate>[
      if (json['candidates'] is List)
        for (final raw in json['candidates'] as List<dynamic>)
          MatchCandidate.fromJson(raw as Map<String, dynamic>),
    ];
    if (match is! Map<String, dynamic>) {
      return IngredientMatch(
        position: (json['position']! as num).toInt(),
        raw: json['raw'] as String? ?? '',
        candidates: candidates,
      );
    }
    return IngredientMatch(
      position: (json['position']! as num).toInt(),
      raw: json['raw'] as String? ?? '',
      fdcId: (match['fdc_id'] as num?)?.toInt(),
      description: match['description'] as String?,
      dataType: match['data_type'] as String?,
      confidence: (match['confidence'] as num?)?.toDouble() ?? 0,
      grams: (match['grams'] as num?)?.toDouble(),
      gramSource: match['gram_source'] as String?,
      status: match['status'] as String? ?? 'unmatched',
      candidates: candidates,
    );
  }

  final int position;
  final String raw;
  final int? fdcId;
  final String? description;

  /// `Foundation` | `SR Legacy`.
  final String? dataType;
  final double confidence;
  final double? grams;

  /// `weight` | `portion` | `density` | `piece` | `override`.
  final String? gramSource;

  /// `auto` | `confirmed` | `overridden` | `skipped` | `unmatched`.
  final String status;
  final List<MatchCandidate> candidates;
}

/// A re-pick option on the review sheet.
class MatchCandidate {
  const MatchCandidate({
    required this.fdcId,
    required this.description,
    required this.dataType,
    required this.confidence,
  });

  factory MatchCandidate.fromJson(Map<String, dynamic> json) => MatchCandidate(
    fdcId: (json['fdc_id']! as num).toInt(),
    description: json['description'] as String? ?? '',
    dataType: json['data_type'] as String? ?? '',
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
  );

  final int fdcId;
  final String description;
  final String dataType;
  final double confidence;
}

/// Bulk-compute job progress.
class NutritionJob {
  const NutritionJob({
    required this.id,
    required this.status,
    required this.total,
    required this.done,
    required this.failed,
    this.log = const [],
  });

  factory NutritionJob.fromJson(Map<String, dynamic> json) => NutritionJob(
    id: (json['id']! as num).toInt(),
    status: json['status'] as String? ?? '',
    total: (json['total'] as num?)?.toInt() ?? 0,
    done: (json['done'] as num?)?.toInt() ?? 0,
    failed: (json['failed'] as num?)?.toInt() ?? 0,
    log: [
      if (json['log'] is List)
        for (final entry in json['log'] as List<dynamic>) '$entry',
    ],
  );

  final int id;

  /// `running` | `done` | `failed`.
  final String status;
  final int total;
  final int done;
  final int failed;
  final List<String> log;
}

/// Access to the nutrition API.
class NutritionRepository {
  NutritionRepository(this._dio);

  final Dio _dio;

  /// The computed label for a recipe (`status: none` before any compute).
  Future<RecipeNutrition> nutrition(String idOrSlug) {
    return apiGuard(() async {
      final response = await _dio.get<dynamic>(
        '/api/v1/recipes/${_seg(idOrSlug)}/nutrition',
      );
      return RecipeNutrition.fromJson(_asMap(response.data));
    }, notFoundMessage: 'Recipe not found.');
  }

  /// Starts a background match+compute for a recipe (admin) and returns the
  /// job id to poll via [job]. Returns immediately — the label lands via
  /// [nutrition] once the job finishes. Single-flight per recipe server-side.
  Future<int> startCompute(String idOrSlug) {
    return apiGuard(() async {
      final data = _asMap(
        (await _dio.post<dynamic>(
          '/api/v1/recipes/${_seg(idOrSlug)}/nutrition/compute',
        )).data,
      );
      return (data['job_id']! as num).toInt();
    }, notFoundMessage: 'Recipe not found.');
  }

  /// Changes the per-serving divisor (instant, no FDC calls).
  Future<RecipeNutrition> setServingBasis(String idOrSlug, int basis) {
    return apiGuard(() async {
      final response = await _dio.put<dynamic>(
        '/api/v1/recipes/${_seg(idOrSlug)}/nutrition',
        data: {'serving_basis': basis},
      );
      return RecipeNutrition.fromJson(_asMap(response.data));
    }, notFoundMessage: 'Recipe not found.');
  }

  /// Per-line match transparency for the review sheet.
  Future<List<IngredientMatch>> matches(String idOrSlug) {
    return apiGuard(() async {
      final response = await _dio.get<dynamic>(
        '/api/v1/recipes/${_seg(idOrSlug)}/nutrition/matches',
      );
      final data = _asMap(response.data);
      return [
        if (data['items'] is List)
          for (final item in data['items'] as List<dynamic>)
            IngredientMatch.fromJson(item as Map<String, dynamic>),
      ];
    }, notFoundMessage: 'Recipe not found.');
  }

  /// Overrides one line (re-pick / set grams / confirm / skip) and returns
  /// the refreshed match list.
  Future<List<IngredientMatch>> overrideMatch(
    String idOrSlug,
    int position, {
    int? fdcId,
    double? grams,
    bool? confirmed,
    bool? skipped,
  }) {
    return apiGuard(() async {
      final response = await _dio.put<dynamic>(
        '/api/v1/recipes/${_seg(idOrSlug)}/nutrition/matches/$position',
        data: {
          if (fdcId != null) 'fdc_id': fdcId,
          if (grams != null) 'grams': grams,
          if (confirmed != null) 'confirmed': confirmed,
          if (skipped != null) 'skipped': skipped,
        },
      );
      final data = _asMap(response.data);
      return [
        if (data['items'] is List)
          for (final item in data['items'] as List<dynamic>)
            IngredientMatch.fromJson(item as Map<String, dynamic>),
      ];
    }, notFoundMessage: 'Recipe not found.');
  }

  /// The FDC key state (never the key itself).
  Future<({bool configured, String? masked})> fdcKeyStatus() {
    return apiGuard(() async {
      final data = _asMap(
        (await _dio.get<dynamic>('/api/v1/settings/fdc_key')).data,
      );
      return (
        configured: data['configured'] == true,
        masked: data['masked'] as String?,
      );
    });
  }

  /// Stores/replaces the FDC key (empty clears).
  Future<({bool configured, String? masked})> setFdcKey(String key) {
    return apiGuard(() async {
      final data = _asMap(
        (await _dio.put<dynamic>(
          '/api/v1/settings/fdc_key',
          data: {'api_key': key},
        )).data,
      );
      return (
        configured: data['configured'] == true,
        masked: data['masked'] as String?,
      );
    });
  }

  /// Starts a bulk compute; returns the job id.
  Future<int> startBulk() {
    return apiGuard(() async {
      final data = _asMap(
        (await _dio.post<dynamic>('/api/v1/nutrition/bulk')).data,
      );
      return (data['job_id']! as num).toInt();
    });
  }

  /// Bulk-job progress.
  Future<NutritionJob> job(int id) {
    return apiGuard(() async {
      final response = await _dio.get<dynamic>('/api/v1/nutrition/jobs/$id');
      return NutritionJob.fromJson(_asMap(response.data));
    });
  }

  static String _seg(String idOrSlug) => Uri.encodeComponent(idOrSlug);

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const RepositoryException(
        'The server returned an unexpected response. Please try again.',
      );
    }
    return data;
  }
}
