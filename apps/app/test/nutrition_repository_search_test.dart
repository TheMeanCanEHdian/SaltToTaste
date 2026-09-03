import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/api/nutrition_repository.dart';

import 'support/contract_goldens.dart';

/// The two wires the cache feature hangs on, pinned where the contract
/// golden cannot pin them (its timestamps are redacted to a stand-in):
/// a live search really sends `fresh=true`, and a matches line's cache
/// fields parse from the real wire shapes.
class _Adapter implements HttpClientAdapter {
  final List<Uri> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    return ResponseBody.fromString(
      jsonEncode({
        'items': [
          {
            'fdc_id': 170931,
            'description': 'Spices, pepper, black',
            'data_type': 'SR Legacy',
            'confidence': 1.0,
          },
        ],
        'query': 'spices pepper black',
        'cached': false,
        'cached_at': '2026-09-03T18:00:00Z',
      }),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('a live search sends fresh=true and a plain one does not', () async {
    final adapter = _Adapter();
    final repository = NutritionRepository(
      Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = adapter,
    );
    final live = await repository.searchFoods('pepper', fresh: true);
    await repository.searchFoods('pepper');
    expect(adapter.requests[0].queryParameters, {
      'q': 'pepper',
      'fresh': 'true',
    });
    expect(adapter.requests[1].queryParameters, {'q': 'pepper'});
    expect(live.query, 'spices pepper black');
    expect(live.cached, isFalse);
    expect(live.cachedAt, DateTime.utc(2026, 9, 3, 18));
    expect(live.items.single.description, 'Spices, pepper, black');
  });

  test("a matches line's cache fields parse from the wire shape", () {
    final raw = golden('nutrition_matches')['items'] as List<dynamic>;
    final line = {
      ...raw.first as Map<String, dynamic>,
      'candidates_query': 'without salt butter',
      'candidates_cached_at': '2026-09-03T18:00:00Z',
    };
    final parsed = IngredientMatch.fromJson(line);
    expect(parsed.candidatesQuery, 'without salt butter');
    expect(parsed.candidatesCachedAt, DateTime.utc(2026, 9, 3, 18));
    // The golden's redacted stand-in and a missing key both read as never.
    expect(
      IngredientMatch.fromJson(
        raw.first as Map<String, dynamic>,
      ).candidatesCachedAt,
      isNull,
    );
  });
}
