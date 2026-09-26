import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/nutrition/fdc_provider.dart';
import 'package:test/test.dart';

/// The FDC request tally (sweep audit 2026-09-26: the spend split of a 900
/// budget had to be inferred by subtraction, and retries were invisible to
/// the bucket). UsdaFdcProvider runs against a fake HTTP layer here
/// (HttpOverrides): the response BODIES are the recorded fixture payloads
/// put back into FDC's wire shape; the 404 and the 503 are negative paths
/// the recordings cannot supply.
void main() {
  final searches =
      jsonDecode(File('test/fixtures/fdc/searches.json').readAsStringSync())
          as Map<String, dynamic>;
  final foods =
      jsonDecode(File('test/fixtures/fdc/foods.json').readAsStringSync())
          as Map<String, dynamic>;

  // FDC's search wire shape for a recorded answer.
  String searchBody(String query) => jsonEncode({
    'foods': [
      for (final hit in (searches[query] as List).cast<Map<String, dynamic>>())
        {
          'fdcId': hit['fdc_id'],
          'description': hit['description'],
          'dataType': hit['data_type'],
          'foodNutrients': [
            for (final entry
                in ((hit['nutrients'] ?? const <String, dynamic>{})
                        as Map<String, dynamic>)
                    .entries)
              {'nutrientNumber': entry.key, 'value': entry.value},
          ],
        },
    ],
  });

  // FDC's detail wire shape for a recorded food.
  String foodBody(String id) {
    final food = foods[id] as Map<String, dynamic>;
    return jsonEncode({
      'description': food['description'],
      'dataType': food['data_type'],
      'foodNutrients': [
        for (final entry in (food['nutrients'] as Map<String, dynamic>).entries)
          {
            'nutrient': {'number': entry.key},
            'amount': entry.value,
          },
      ],
    });
  }

  test(
    'every request is tallied by kind — strict and loose searches, food '
    'details, 404s and retries — and the tally never carries the key',
    () async {
      final id = foods.keys.first;
      var failNextSearch = false;
      final requests = <String>[];
      final provider = UsdaFdcProvider(
        apiKey: () => 'fixture-key-not-real',
        bucket: TokenBucket(capacity: 50),
      );

      await HttpOverrides.runZoned(
        () async {
          // Strict finds nothing, so the loose pass runs: two searches.
          await provider.search('sour cream');
          expect(provider.requestCounts, {
            'search_strict': 1,
            'search_loose': 1,
          });

          await provider.food(int.parse(id));
          expect(await provider.food(1), isNull, reason: 'FDC 404s this id');
          expect(provider.requestCounts['food'], 2);
          expect(provider.requestCounts['food_404'], 1);

          // One 503, then the answer: a retry api.data.gov counts, the bucket
          // does not.
          failNextSearch = true;
          await provider.search('sour cream');
          expect(provider.requestCounts['retry'], 1);
        },
        createHttpClient: (_) => _FakeClient((method, uri, body) {
          requests.add('$method ${uri.path}');
          if (uri.path.endsWith('/foods/search')) {
            if (failNextSearch) {
              failNextSearch = false;
              return (503, '');
            }
            final strict = (jsonDecode(body) as Map)['requireAllWords'] == true;
            return (200, strict ? '{"foods": []}' : searchBody('sour cream'));
          }
          final foodId = uri.pathSegments.last;
          return foods.containsKey(foodId)
              ? (200, foodBody(foodId))
              : (404, '');
        }),
      );

      expect(
        requests,
        hasLength(7),
        reason: 'every request above hit the wire',
      );
      expect(provider.requestCounts, {
        'search_strict': 2,
        'search_loose': 2,
        'food': 2,
        'food_404': 1,
        'retry': 1,
      });
      expect(
        provider.requestCountsText,
        'search_strict 2, search_loose 2, food 2, food_404 1, retry 1',
      );
    },
  );

  test('a rate-limit wait logs the tally, not the key', () async {
    final records = <String>[];
    final sub = Logger('fdc').onRecord.listen((r) => records.add(r.message));
    addTearDown(sub.cancel);
    final bucket = TokenBucket(
      capacity: 1,
      window: const Duration(milliseconds: 150),
    );
    final provider = UsdaFdcProvider(
      apiKey: () => 'fixture-key-not-real',
      bucket: bucket,
    );
    await HttpOverrides.runZoned(
      () async {
        await provider.search('sour cream');
        await provider.search('sour cream');
      },
      createHttpClient: (_) =>
          _FakeClient((method, uri, body) => (200, searchBody('sour cream'))),
    );
    final waits = records.where((m) => m.contains('rate limit')).toList();
    expect(waits, hasLength(1), reason: 'the second search had to wait');
    expect(waits.single, contains('search_strict 1, search_loose 0'));
    expect(records.join(), isNot(contains('fixture-key-not-real')));
  });
}

/// Answers each request from [respond] — (status, body) — with no network.
class _FakeClient implements HttpClient {
  _FakeClient(this.respond);

  final (int, String) Function(String method, Uri uri, String body) respond;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async =>
      _FakeRequest('POST', url, respond);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeRequest('GET', url, respond);

  @override
  void close({bool force = false}) {}

  // connectionTimeout and the rest: unused or ignored.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this._method, this._uri, this._respond);

  final String _method;
  final Uri _uri;
  final (int, String) Function(String, Uri, String) _respond;
  final StringBuffer _body = StringBuffer();

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  void write(Object? object) => _body.write(object);

  @override
  Future<HttpClientResponse> close() async {
    final (status, text) = _respond(_method, _uri, _body.toString());
    return _FakeResponse(status, text);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHeaders implements HttpHeaders {
  // set(), contentType=: accepted and ignored.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.statusCode, this._text);

  @override
  final int statusCode;
  final String _text;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(_text)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
