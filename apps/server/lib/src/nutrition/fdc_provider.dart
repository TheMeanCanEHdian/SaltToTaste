import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_server/src/nutrition/provider.dart';

final Logger _log = Logger('fdc');

/// Requests per hour the provider allows itself (the token-bucket
/// capacity default) — under api.data.gov's 1,000/hr default so
/// interactive traffic never trips the hard limit.
const int fdcRequestsPerHour = 900;

/// A token-bucket rate limiter: at most [capacity] acquisitions per
/// window (default one hour). Excess callers poll-wait for a free slot
/// (approximately in arrival order, not strictly FIFO).
class TokenBucket {
  /// Creates a bucket allowing [capacity] acquisitions per [window]
  /// (default one hour).
  TokenBucket({this.capacity = fdcRequestsPerHour, Duration? window})
    : _window = window ?? const Duration(hours: 1);

  /// Maximum acquisitions per window.
  final int capacity;
  final Duration _window;
  final List<DateTime> _grants = [];

  /// Completes when a request slot is available (immediately when under
  /// the limit; otherwise after the oldest grant leaves the window).
  ///
  /// With [maxWait], returns false instead of waiting longer than that —
  /// interactive requests must fail fast rather than hold an HTTP
  /// connection open for up to an hour.
  Future<bool> acquire({Duration? maxWait}) async {
    final deadline = maxWait == null ? null : DateTime.now().add(maxWait);
    while (true) {
      final now = DateTime.now();
      _grants.removeWhere((grant) => now.difference(grant) >= _window);
      if (_grants.length < capacity) {
        _grants.add(now);
        return true;
      }
      final wait = _window - now.difference(_grants.first);
      if (deadline != null &&
          now.add(wait).isAfter(deadline) &&
          now.isBefore(deadline)) {
        return false;
      }
      if (deadline != null && !now.isBefore(deadline)) {
        return false;
      }
      _log.info(
        'FDC rate limit reached; waiting ${wait.inSeconds}s '
        '(queue drains automatically)',
      );
      await Future<void>.delayed(wait + const Duration(milliseconds: 50));
    }
  }
}

/// USDA FoodData Central client.
///
/// The API key is fetched per request via [apiKey] (it lives in the
/// settings table and may be replaced at runtime) and is sent as the
/// `X-Api-Key` HEADER — never in the URL, so it cannot leak into logs.
class UsdaFdcProvider implements NutritionProvider {
  /// Creates the client; [apiKey] is consulted on every request and
  /// [host] is overridable for tests.
  UsdaFdcProvider({
    required this.apiKey,
    TokenBucket? bucket,
    String host = 'api.nal.usda.gov',
    this.maxRateWait,
  }) : _bucket = bucket ?? TokenBucket(),
       // ignore: prefer_initializing_formals
       _host = host;

  /// Returns the configured key, or null when unset.
  final String? Function() apiKey;
  final TokenBucket _bucket;
  final String _host;

  /// Cap on how long a request may wait for a rate-limit slot. Null waits
  /// as long as it takes (the bulk job); interactive endpoints set ~30s so
  /// a drained budget turns into a fast, explained failure instead of a
  /// stuck HTTP request.
  final Duration? maxRateWait;

  static const Duration _timeout = Duration(seconds: 30);

  @override
  Future<List<FdcCandidate>> search(String query) async {
    // requireAllWords tightens relevance (drops partial-term noise like
    // "minced" pulling in "Ham, minced"). But an extra word the food's name
    // lacks can zero the whole search, so fall back to the loose search when
    // the strict one finds nothing.
    var hits = await _searchOnce(query, requireAllWords: true);
    if (hits.isEmpty) {
      hits = await _searchOnce(query, requireAllWords: false);
    }
    return hits;
  }

  Future<List<FdcCandidate>> _searchOnce(
    String query, {
    required bool requireAllWords,
  }) async {
    final json = await _get('/fdc/v1/foods/search', {
      'query': query,
      'dataType': 'Foundation,SR Legacy',
      'pageSize': '25',
      if (requireAllWords) 'requireAllWords': 'true',
    });
    final foods = json['foods'];
    if (foods is! List) {
      return const [];
    }
    return [
      for (final food in foods.cast<Map<String, dynamic>>())
        if (food['fdcId'] is num && food['description'] is String)
          FdcCandidate(
            fdcId: (food['fdcId'] as num).toInt(),
            description: food['description'] as String,
            dataType: food['dataType'] as String? ?? '',
            nutrientsPer100g: _searchNutrients(food['foodNutrients']),
          ),
    ];
  }

  /// Per-100 g amounts from a search hit's `foodNutrients`
  /// (`nutrientNumber`/`value`), filtered to the reported set.
  static Map<String, double>? _searchNutrients(Object? raw) {
    if (raw is! List) {
      return null;
    }
    final nutrients = <String, double>{};
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final number = entry['nutrientNumber']?.toString();
      final value = entry['value'];
      if (number != null &&
          value is num &&
          nutrientByFdcNumber.containsKey(number)) {
        nutrients[number] = value.toDouble();
      }
    }
    return nutrients.isEmpty ? null : nutrients;
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    final Map<String, dynamic> json;
    try {
      json = await _get('/fdc/v1/food/$fdcId', const {});
    } on _NotFound {
      return null;
    }
    // Detail nutrients arrive as {nutrient: {number, ...}, amount} per 100g.
    final nutrients = <String, double>{};
    final rawNutrients = json['foodNutrients'];
    if (rawNutrients is List) {
      for (final entry in rawNutrients.cast<Map<String, dynamic>>()) {
        final nutrient = entry['nutrient'];
        final amount = entry['amount'];
        if (nutrient is Map<String, dynamic> && amount is num) {
          final number = nutrient['number']?.toString();
          if (number != null && nutrientByFdcNumber.containsKey(number)) {
            nutrients[number] = amount.toDouble();
          }
        }
      }
    }
    final portions = <FdcPortion>[];
    final rawPortions = json['foodPortions'];
    if (rawPortions is List) {
      for (final entry in rawPortions.cast<Map<String, dynamic>>()) {
        final gramWeight = entry['gramWeight'];
        if (gramWeight is! num || gramWeight <= 0) {
          continue;
        }
        final measureUnit = entry['measureUnit'];
        final unitName = measureUnit is Map<String, dynamic>
            ? measureUnit['name']?.toString().toLowerCase()
            : null;
        portions.add(
          FdcPortion(
            gramWeight: gramWeight.toDouble(),
            amount: (entry['amount'] as num?)?.toDouble(),
            unit: (unitName == null || unitName == 'undetermined')
                ? null
                : unitName,
            description:
                entry['portionDescription'] as String? ??
                entry['modifier'] as String?,
          ),
        );
      }
    }
    return FdcFood(
      fdcId: fdcId,
      description: json['description'] as String? ?? 'FDC food $fdcId',
      dataType: json['dataType'] as String? ?? '',
      nutrientsPer100g: nutrients,
      portions: portions,
    );
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final key = apiKey();
    if (key == null || key.isEmpty) {
      throw const NutritionProviderException(
        'No FoodData Central API key is configured. An admin can add one '
        'in Settings → Nutrition (free at api.data.gov/signup).',
      );
    }
    if (!await _bucket.acquire(maxWait: maxRateWait)) {
      throw const NutritionProviderException(
        'The FoodData Central request budget for this hour is used up '
        '(a bulk compute may be running). Try again in a little while.',
      );
    }

    final uri = Uri.https(_host, path, query.isEmpty ? null : query);
    var attempt = 0;
    while (true) {
      attempt += 1;
      final client = HttpClient()..connectionTimeout = _timeout;
      try {
        final request = await client.getUrl(uri);
        // Header, not query param: request URIs get logged; headers don't.
        request.headers.set('X-Api-Key', key);
        final response = await request.close().timeout(_timeout);
        // The body read needs its own timeout: a stalled stream after
        // headers would otherwise hang the caller forever.
        final body = await utf8.decoder.bind(response).join().timeout(_timeout);
        switch (response.statusCode) {
          case 200:
            final decoded = jsonDecode(body);
            if (decoded is! Map<String, dynamic>) {
              throw const NutritionProviderException(
                'FoodData Central returned an unexpected response.',
              );
            }
            return decoded;
          case 404:
            throw const _NotFound();
          case 401:
          case 403:
            throw const NutritionProviderException(
              'FoodData Central rejected the API key. Check it in '
              'Settings → Nutrition.',
            );
          case 429:
            if (attempt >= 4) {
              throw const NutritionProviderException(
                'FoodData Central rate limit hit repeatedly; try again '
                'later.',
              );
            }
            final delay = Duration(seconds: 15 * attempt * attempt);
            _log.warning(
              'FDC 429; backing off ${delay.inSeconds}s (attempt $attempt)',
            );
            await Future<void>.delayed(delay);
            continue;
          default:
            throw NutritionProviderException(
              'FoodData Central error ${response.statusCode}.',
            );
        }
      } on NutritionProviderException {
        rethrow;
      } on _NotFound {
        rethrow;
      } on Exception catch (error) {
        if (attempt >= 3) {
          // The message never includes the URI (it carries no secret, but
          // uniformity keeps log grepping simple) nor the key.
          throw NutritionProviderException(
            'Could not reach FoodData Central: '
            "${error.runtimeType}. Check the server's connectivity.",
          );
        }
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      } finally {
        client.close(force: true);
      }
    }
  }
}

class _NotFound implements Exception {
  const _NotFound();
}
