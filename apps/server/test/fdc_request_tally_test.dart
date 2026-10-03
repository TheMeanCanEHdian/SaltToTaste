import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/fdc_provider.dart';
import 'package:salt_server/src/nutrition/provider.dart';
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
      // Room for exactly the seven requests below.
      final bucket = TokenBucket(capacity: 7);
      final provider = UsdaFdcProvider(
        apiKey: () => 'fixture-key-not-real',
        bucket: bucket,
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

          // One 503, then the answer: a retry is a request api.data.gov
          // counts, and it takes a grant of its own.
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
      // strict + loose + food (404s included) + retry = grants.
      final counts = provider.requestCounts;
      expect(
        counts['search_strict']! +
            counts['search_loose']! +
            counts['food']! +
            counts['retry']!,
        requests.length,
      );
      expect(
        await bucket.acquire(maxWait: Duration.zero),
        isFalse,
        reason: 'seven requests spent all seven grants',
      );
    },
  );

  test("a bulk job's closing line counts its own requests, not the "
      "process's", () async {
    final records = <String>[];
    final sub = Logger.root.onRecord.listen((r) => records.add(r.message));
    addTearDown(sub.cancel);
    final tmp = Directory.systemTemp.createTempSync('salt-bulk-tally');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final db = SaltDatabase.open('${tmp.path}/salt.db');
    addTearDown(db.dispose);
    final provider = UsdaFdcProvider(
      apiKey: () => 'fixture-key-not-real',
      bucket: TokenBucket(capacity: 50),
    );
    await HttpOverrides.runZoned(
      () async {
        // Interactive traffic before the job: one strict search.
        await provider.search('sour cream');
        // An empty library: the job itself asks FDC nothing.
        expect(startBulkJob(db, provider), isNotNull);
        for (var i = 0; i < 100 && !records.any(_ended); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      },
      createHttpClient: (_) =>
          _FakeClient((method, uri, body) => (200, searchBody('sour cream'))),
    );
    expect(
      records.singleWhere(_ended),
      contains(
        'by this job: search_strict 0, search_loose 0, food 0, food_404 0, '
        'retry 0 (process total: search_strict 1,',
      ),
    );
  });

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

  // RULE A's two failure classes (v28, Run 058 Opus critic 1 / S27): the
  // provider says which. Negative paths the recordings cannot supply (the
  // statuses are synthesized; the bodies are none).
  test("a failure is FOOD-scoped only for one food's detail (a 4xx, an "
      'unreadable answer, a 5xx after the retries); a key, the budget, a '
      'search or the network are GLOBAL', () async {
    Future<FailureScope> scopeOf(
      Future<Object?> Function(UsdaFdcProvider p) call,
      (int, String) Function(Uri uri) respond, {
      int capacity = 10,
    }) async {
      final provider = UsdaFdcProvider(
        apiKey: () => 'fixture-key-not-real',
        bucket: TokenBucket(capacity: capacity),
        maxRateWait: Duration.zero,
      );
      try {
        await HttpOverrides.runZoned(
          () => call(provider),
          createHttpClient: (_) => _FakeClient((m, uri, b) => respond(uri)),
        );
      } on NutritionProviderException catch (error) {
        return error.scope;
      }
      fail('no failure');
    }

    Future<Object?> detail(UsdaFdcProvider p) => p.food(1);
    Future<Object?> search(UsdaFdcProvider p) => p.search('sour cream');
    expect(await scopeOf(detail, (_) => (400, '')), FailureScope.food);
    expect(await scopeOf(detail, (_) => (200, '[]')), FailureScope.food);
    expect(await scopeOf(detail, (_) => (401, '')), FailureScope.global);
    expect(await scopeOf(detail, (_) => (403, '')), FailureScope.global);
    expect(await scopeOf(search, (_) => (400, '')), FailureScope.global);
    expect(await scopeOf(search, (_) => (200, '[]')), FailureScope.global);
    expect(
      await scopeOf(
        (p) async {
          // Strict and loose: both grants spent; the detail finds none.
          await p.search('sour cream');
          return p.food(1);
        },
        (uri) => (200, '{"foods": []}'),
        capacity: 2,
      ),
      FailureScope.global,
      reason: 'the budget spent',
    );
    expect(
      await scopeOf(
        (_) => UsdaFdcProvider(apiKey: () => null).food(1),
        (_) => (200, '{}'),
      ),
      FailureScope.global,
      reason: 'no key',
    );
    // A 5xx after the four attempts (3 + 6 + 9 s of backoff).
    expect(await scopeOf(detail, (_) => (503, '')), FailureScope.food);
    // A 429 after the four attempts is the KEY's rate limit: GLOBAL even on
    // a detail (the v28 closer's D6, A19). Its 15 + 60 + 135 s of backoff
    // run on zero-length timers (every other timer as asked).
    const backoff = {15, 60, 135};
    expect(
      await runZoned(
        () => scopeOf(detail, (_) => (429, '')),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, d, f) => parent.createTimer(
            zone,
            backoff.contains(d.inSeconds) ? Duration.zero : d,
            f,
          ),
        ),
      ),
      FailureScope.global,
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  // RULE B's classification TABLE (v29, Run 059 O22/O5/S5/S28/O14/S22):
  // every arm of fdc_provider.dart's `_request` pinned on its own, the
  // backoffs run on zero-length timers. Negative paths the recordings
  // cannot supply, synthesized (a stated exception): the statuses, the
  // unreadable bodies, and the dead network (a request that throws).
  test(
    'the classification TABLE, arm by arm: on a DETAIL 404 is null; '
    'another 4xx, a 5xx after the retries, an unreadable 200 are FOOD; '
    'a 429, a rejected key, the network and any SEARCH failure GLOBAL',
    () async {
      final calls = <int>[];
      Future<Object?> run(
        Future<Object?> Function(UsdaFdcProvider p) call,
        (int, String) Function(Uri uri) respond,
      ) {
        final provider = UsdaFdcProvider(
          apiKey: () => 'fixture-key-not-real',
          bucket: TokenBucket(capacity: 10),
          maxRateWait: Duration.zero,
        );
        var n = 0;
        return runZoned(
          () => HttpOverrides.runZoned(
            () async {
              try {
                return await call(provider);
              } on NutritionProviderException catch (error) {
                return error;
              } finally {
                calls.add(n);
              }
            },
            createHttpClient: (_) => _FakeClient((m, uri, b) {
              n++;
              return respond(uri);
            }),
          ),
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, d, f) => parent.createTimer(
              zone,
              // Every backoff (2, 4; 3, 6, 9; 15, 60, 135 s), never the 30 s
              // request timeouts.
              d == const Duration(seconds: 30) ? d : Duration.zero,
              f,
            ),
          ),
        );
      }

      Future<Object?> detail(UsdaFdcProvider p) => p.food(1);
      Future<Object?> search(UsdaFdcProvider p) => p.search('sour cream');
      Future<FailureScope?> scope(
        Future<Object?> Function(UsdaFdcProvider p) call,
        (int, String) Function(Uri uri) respond,
      ) async => switch (await run(call, respond)) {
        final NutritionProviderException e => e.scope,
        _ => null,
      };
      const food = FailureScope.food;
      const global = FailureScope.global;

      // A detail 404: no record, one request.
      calls.clear();
      expect(await run(detail, (_) => (404, '')), isNull);
      expect(calls, [1]);
      for (final (status, want) in [
        (400, food),
        (410, food),
        (422, food),
        (500, food),
        (503, food),
        (401, global),
        (403, global),
        (429, global),
      ]) {
        expect(
          await scope(detail, (_) => (status, '')),
          want,
          reason: '$status',
        );
      }
      // Unreadable 200s on a detail: retried with the network's ladder, then
      // the food's.
      for (final body in [
        '{"fdcId": 1, "descr',
        '<html>bad gateway</html>',
        '',
        '[]',
        // A JSON object of the wrong shape (Run 059 Opus critic 2 #2: a
        // TypeError escaped the pass): read defensively, the food's.
        '{"foodNutrients":[null]}',
        '{"description":5}',
        '{"foodPortions":["x"]}',
      ]) {
        calls.clear();
        expect(await scope(detail, (_) => (200, body)), food, reason: body);
      }
      // The network: GLOBAL even on a detail (a connect failure, a timeout,
      // a stream cut mid-body name no food), three attempts.
      for (final error in <Exception>[
        const SocketException('network is down'),
        TimeoutException('connect'),
        const HttpException('Connection closed while receiving data'),
      ]) {
        calls.clear();
        expect(
          await scope(detail, (_) => throw error),
          global,
          reason: '$error',
        );
        expect(calls, [3], reason: '$error');
        expect(
          await scope(search, (_) => throw error),
          global,
          reason: '$error',
        );
      }
      // Any SEARCH failure: GLOBAL.
      for (final status in [400, 404, 410, 500, 503, 429, 401]) {
        expect(
          await scope(search, (_) => (status, '')),
          global,
          reason: 'search $status',
        );
      }
      for (final body in ['{"foods": [', '<html>bad gateway</html>', '[]']) {
        expect(await scope(search, (_) => (200, body)), global, reason: body);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

bool _ended(String message) => message.contains('ended; FDC requests');

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
