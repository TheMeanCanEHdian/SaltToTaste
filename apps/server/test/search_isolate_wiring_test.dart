import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart' hide requestLogger;
import 'package:salt_server/src/app_pipeline.dart';
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/search/fts_compiler.dart';
import 'package:salt_server/src/search/search_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

/// Regression + resilience tests for the #48 review findings. None need the
/// corpus — the wiring and isolate lifecycle are exercised on an empty DB.

class _UnusedNutrition implements NutritionProvider {
  @override
  Future<List<FdcCandidate>> search(String query) => throw UnimplementedError();
  @override
  Future<FdcFood?> food(int fdcId) => throw UnimplementedError();
}

/// A stand-in service that just reports which instance served the request.
class _TaggedSearch implements SearchService {
  _TaggedSearch(this.tag);
  final String tag;
  @override
  Future<SearchPage> search(
    CompiledSearch compiled, {
    required int page,
    required int limit,
    int? viewerId,
    bool favoritesOnly = false,
  }) async => (items: const <RecipeCard>[], total: 0);
  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory tempDir;
  late SaltDatabase db;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('salt_wiring_test_');
    db = SaltDatabase.open('${tempDir.path}/salt.db');
    File('${tempDir.path}/index.html').writeAsStringSync('<html></html>');
  });
  tearDown(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  // HIGH (#48 review): the dart_frog entrypoint builds the chain BEFORE
  // initSearchService() runs, so a provider that captured the service by VALUE
  // froze in the InlineSearchService fallback and the isolate pool was never
  // used. The provider must resolve the thunk PER REQUEST.
  test(
    'the SearchService provider is resolved per request, not at build time',
    () async {
      var current = _TaggedSearch('inline-fallback');
      final pipeline = buildAppMiddleware(
        (context) => Response(
          body: (context.read<SearchService>() as _TaggedSearch).tag,
        ),
        config: ServerConfig.fromEnvironment(
          environment: {'DATA_DIR': tempDir.path, 'LOG_LEVEL': 'ERROR'},
        ),
        database: db,
        authRuntime: AuthRuntime(),
        nutritionProvider: _UnusedNutrition(),
        searchRateLimiter: RequestRateLimiter(),
        searchService: () => current,
        indexPath: '${tempDir.path}/index.html',
      );
      final server = await serve(pipeline, InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      Future<String> hit() async {
        final client = HttpClient();
        try {
          final req = await client.getUrl(
            Uri.parse('http://127.0.0.1:${server.port}/probe'),
          );
          final resp = await req.close();
          return utf8.decoder.bind(resp).join();
        } finally {
          client.close();
        }
      }

      expect(await hit(), 'inline-fallback');
      // Mirror initSearchService() swapping the singleton after the build.
      current = _TaggedSearch('isolate-pool');
      expect(
        await hit(),
        'isolate-pool',
        reason: 'a build-time-captured value would still say inline-fallback',
      );
    },
  );

  group('IsolateSearchService resilience', () {
    // A valid, cheap FTS match; on an empty DB it returns no rows.
    const query = CompiledSearch(ftsMatch: '"anything"');

    // MED (#48 review): after a worker death, two concurrent requests must
    // SHARE one respawn. Without the in-flight guard both spawn, orphaning an
    // isolate + its read-only WAL connection that dispose() never tracks.
    test(
      'concurrent respawn after a crash spawns exactly one replacement',
      () async {
        final svc = await IsolateSearchService.spawn(
          dbPath: '${tempDir.path}/salt.db',
          count: 1,
        );
        addTearDown(svc.dispose);
        expect(svc.totalSpawns, 1);

        svc.crashWorkersForTest(); // _commands == null, isolate killed
        await Future.wait([
          svc.search(query, page: 1, limit: 10),
          svc.search(query, page: 1, limit: 10),
        ]);
        expect(
          svc.totalSpawns,
          2,
          reason: 'the guard shares one respawn; a leaked double-spawn is 3',
        );
      },
    );

    // MED (#48 review): a wedged worker never fires onExit, so a timed-out
    // request must EVICT it or it poisons every future request (default pool =
    // one worker). A ~0 timeout guarantees the cross-isolate reply loses the
    // race, so every search times out.
    test(
      'a timed-out search evicts the worker so the next one respawns',
      () async {
        final svc = await IsolateSearchService.spawn(
          dbPath: '${tempDir.path}/salt.db',
          count: 1,
          timeout: Duration.zero,
        );
        addTearDown(svc.dispose);
        expect(svc.totalSpawns, 1);

        await expectLater(
          svc.search(query, page: 1, limit: 10),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          svc.search(query, page: 1, limit: 10),
          throwsA(isA<StateError>()),
        );
        expect(
          svc.totalSpawns,
          2,
          reason: 'the evicted worker respawned for the second search',
        );
      },
    );
  });
}
