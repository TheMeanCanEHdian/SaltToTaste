import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart' hide requestLogger;
import 'package:salt_server/src/app_pipeline.dart';
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/search/fts_compiler.dart';
import 'package:salt_server/src/search/search_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
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
        logStore: LogStore(directory: '${tempDir.path}/logs'),
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

    // Asked of SQLite itself: leaving WAL mode takes the exclusive lock that
    // any other connection which has read the database denies.
    String leaveWal() {
      final probe = sqlite3.open('${tempDir.path}/salt.db');
      try {
        probe.execute('PRAGMA busy_timeout = 0');
        final row = probe.select('PRAGMA journal_mode = DELETE').single;
        return '${row.values.single}';
      } on SqliteException catch (error) {
        return 'refused: ${error.message}';
      } finally {
        probe.dispose();
      }
    }

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
    // one worker). A zero timeout has expired before the reply is awaited (the
    // next test pins that), so every search times out and evicts its worker.
    // `_SearchWorker.run` raises it after sending the request, so the worker
    // is usually evicted with a search in flight; that order is NOT pinned —
    // telling a busy worker's exit from an idle one's needs a negative wait.
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

    // CI run 42758491911 (the test above, its first search): `Duration.zero`
    // armed a zero TIMER, and that timer's event and the worker's reply are
    // both messages to this isolate, delivered in arrival order — a reply
    // queued first won, and the search returned a page instead of timing out.
    // A non-positive timeout is now expired before the reply is awaited, so
    // the search fails before this isolate handles ANY event. The sentinel is
    // a zero timer queued ahead of the search: a timer-decided timeout fires
    // after it, and a reply that wins resolves the search — both fail here.
    test(
      'a non-positive timeout expires before any event is handled',
      () async {
        final svc = await IsolateSearchService.spawn(
          dbPath: '${tempDir.path}/salt.db',
          count: 1,
          timeout: Duration.zero,
        );
        addTearDown(svc.dispose);

        var eventHandled = false;
        Timer.run(() => eventHandled = true);
        bool? failedBeforeAnyEvent;
        await svc
            .search(query, page: 1, limit: 10)
            .then<void>(
              (_) =>
                  fail('the reply won the race: a zero timeout served a page'),
              onError: (Object error) {
                failedBeforeAnyEvent = !eventHandled;
                expect(error, isA<StateError>());
              },
            );
        expect(
          failedBeforeAnyEvent,
          isTrue,
          reason: 'the timeout was left to a timer, which the reply can beat',
        );
      },
    );

    // Six archived gate logs, 2026-10-30 → 2026-11-09 (this file's tearDown:
    // "Directory not empty", errno 66). An evicted worker is only ASKED to
    // die — `Isolate.kill` returns at once — and dispose() used to return at
    // once after an eviction. The search the worker was evicted under could
    // still be running: its first read re-created `salt.db-shm` after the
    // recursive delete had listed the directory. dispose() must not complete
    // before the exit signal of every killed isolate has arrived. That signal
    // is an event, so right after the kill it is still owed, whatever the
    // worker's pace.
    // What it holds: dispose() tracks the kill and waits on that counter —
    // `pendingExits` 1 for 0 with the kill untracked, 0 for 1 with the wait
    // skipped. What it does NOT hold: it reads the counter, so a dispose()
    // that clears the counter without waiting passes it; the lock group's
    // 'dispose() kills a worker that missed its shutdown reply …' holds the
    // wait itself. It also assumes an idle killed worker dies within the
    // wait's 1 s bound.
    test('dispose() waits until every killed worker has exited', () async {
      final svc = await IsolateSearchService.spawn(
        dbPath: '${tempDir.path}/salt.db',
        count: 1,
      );
      svc.crashWorkersForTest(); // the kill is requested, nothing more
      expect(svc.pendingExits, 1);

      await svc.dispose();
      expect(
        svc.pendingExits,
        0,
        reason: 'dispose() returned while a killed worker could still run',
      );
    });

    // A worker whose connection cannot open dies before it sends `ready`. The
    // spawn used to await that message alone, so it never completed — and
    // every request sharing it waited forever. No timer is involved: the
    // spawn fails on the worker's exit signal.
    test('a worker that dies before it is ready fails the spawn', () async {
      await expectLater(
        IsolateSearchService.spawn(
          dbPath: '${tempDir.path}/missing/salt.db',
          count: 1,
        ),
        throwsA(isA<StateError>()),
      );
    });

    // The same death during a RESPAWN: the search that triggered it fails
    // with a StateError (the uniform error envelope), the slot is left empty,
    // and the next search respawns and is served. The database's directory
    // is moved away for the respawn, so the worker's open fails.
    test(
      'a worker that dies during a respawn fails that search only',
      () async {
        final dir = Directory('${tempDir.path}/sub')..createSync();
        SaltDatabase.open('${dir.path}/salt.db').dispose();
        final svc = await IsolateSearchService.spawn(
          dbPath: '${dir.path}/salt.db',
          count: 1,
        );
        addTearDown(svc.dispose);
        svc.crashWorkersForTest();
        final moved = dir.renameSync('${tempDir.path}/moved');
        await expectLater(
          svc.search(query, page: 1, limit: 10),
          throwsA(isA<StateError>()),
        );
        moved.renameSync(dir.path);
        await svc.search(query, page: 1, limit: 10);
        expect(svc.totalSpawns, 2, reason: 'the failed spawn is not counted');
      },
    );

    // A killed worker never runs its own dispose(), and `package:sqlite3`
    // closes an undisposed database from a Dart `Finalizer`, which does not
    // run for a dead isolate: the process kept the connection's descriptors
    // on `salt.db`, `-wal` and `-shm` for good (lsof, 2026-11-09), so the
    // writer was never the last connection again. The worker's connection is
    // now closed natively when its isolate exits. Asked of SQLite itself
    // ([leaveWal]) — so the worker serves a search first, and the writer is
    // closed before the question is put.
    test("a killed worker's connection is closed once it has exited", () async {
      final svc = await IsolateSearchService.spawn(
        dbPath: '${tempDir.path}/salt.db',
        count: 1,
      );
      await svc.search(query, page: 1, limit: 10);
      svc.crashWorkersForTest();
      await svc.dispose();
      db.dispose();

      expect(
        leaveWal(),
        'delete',
        reason: 'another connection still holds the database open',
      );
    });

    // dispose() during a respawn used to see an empty slot and return: the
    // spawning isolate then served the pending search AFTER dispose() and
    // kept its connection open past the writer's close. Now dispose() awaits
    // the spawn (bounded, 2 s) and shuts its isolate down like any other.
    // Asked of SQLite ([leaveWal]). Only the worker's thread could falsify
    // it: over 2 s to spawn (or to answer the shutdown), then over 1 s to
    // die once killed.
    test('dispose() during a respawn shuts the new worker down too', () async {
      final svc = await IsolateSearchService.spawn(
        dbPath: '${tempDir.path}/salt.db',
        count: 1,
      );
      svc.crashWorkersForTest();
      // The respawn is in flight when dispose() starts. Its search is served
      // (before dispose() returns now, after it before), so the new worker has
      // READ the database: an idle connection would not deny the question.
      final pending = svc.search(query, page: 1, limit: 10);
      await svc.dispose();
      await pending.then((_) {}, onError: (_) {});
      db.dispose();

      expect(
        leaveWal(),
        'delete',
        reason: 'the respawned worker outlived dispose()',
      );
    });
  });

  // A worker held INSIDE native code: this isolate opens a database in
  // rollback-journal mode and holds `BEGIN EXCLUSIVE`, so every worker read
  // busy-waits inside SQLite (busy_timeout 5000: measured 5.27 s before it
  // gives up, a release noticed within ~140 ms) until [release] commits — a
  // kill cannot land until then.
  group('IsolateSearchService with a worker held inside SQLite', () {
    const query = CompiledSearch(ftsMatch: '"anything"');
    late String path;
    late Database lock;
    var released = false;

    void release() {
      if (!released) {
        released = true;
        lock
          ..execute('COMMIT')
          ..dispose();
      }
    }

    setUp(() {
      // Its own file: the outer writer keeps salt.db in WAL mode.
      path = '${tempDir.path}/locked.db';
      SaltDatabase.open(path).dispose();
      released = false;
      lock = sqlite3.open(path)
        ..execute('PRAGMA journal_mode = DELETE')
        ..execute('BEGIN EXCLUSIVE');
    });
    tearDown(release);

    // A request queued behind a wedged worker times out AFTER that worker was
    // evicted and replaced; its timeout must not kill the replacement. A and
    // B go to worker 1, held in SQLite; A times out and evicts it; D spawns
    // worker 2 and waits in SQLite too; B's timeout fires; the lock is
    // released. With the slot's isolate evicted instead of B's own, B's
    // timeout killed worker 2 under D (D failed 'search timed out') or while
    // it was still spawning (D never completed).
    // Timers: B's timeout (armed ~300 ms after A's) and the release (armed
    // 600 ms after A failed) are both on THIS isolate's queue, so they fire
    // in deadline order however it stalls. What only worker 2's thread
    // decides is how soon after the release it serves D: within D's own
    // timeout, which leaves it ~1.4 s (T 2000 ms − 600 ms + the spawn).
    test("a stale request's timeout never kills the replacement", () async {
      final svc = await IsolateSearchService.spawn(
        dbPath: path,
        count: 1,
        timeout: const Duration(milliseconds: 2000),
      );
      addTearDown(svc.dispose);
      final a = svc.search(query, page: 1, limit: 10);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final b = svc.search(query, page: 1, limit: 10); // queued at worker 1
      unawaited(b.then((_) {}, onError: (_) {}));
      await expectLater(a, throwsA(isA<StateError>())); // worker 1 evicted
      final d = svc.search(query, page: 1, limit: 10); // spawns worker 2
      Timer(const Duration(milliseconds: 600), release); // after b's timeout
      Object? dError;
      await d.then(
        (_) {},
        onError: (Object error) {
          dError = error;
        },
      );
      expect(dError, isNull, reason: "b's timeout killed worker 2 under d");
      await svc.search(query, page: 1, limit: 10); // worker 2 still serves
      expect(svc.totalSpawns, 2, reason: 'a third spawn: worker 2 was killed');
    });

    // Polls a condition set by this isolate's own port handlers.
    Future<void> until(bool Function() condition) async {
      while (!condition()) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }

    // Worker 1 times out inside SQLite and is evicted; worker 2 replaces it
    // and is READY before worker 1 can die; the release lets worker 1 die. Its
    // late exit must only settle its own entry: marking the slot dead orphans
    // worker 2 (a live isolate, its connection open, never killed or waited)
    // and the next search spawns a third.
    // Timers: worker 1's search fails on this isolate's timeout (T 2500 ms),
    // which fires before worker 1's own 'database is locked' reply (≥ 5.27 s)
    // even if this isolate stalls, since both arrive as events in order; it
    // cannot die before the release or that reply, so `pendingExits` is 1.
    // What only the workers' threads decide, and so is NOT asserted: whether
    // worker 2 is ready before worker 1's busy-wait gives up (the mutant's
    // kill needs it: ~2.7 s of slack), and whether worker 2 serves its search
    // within T after the release. A search it did not serve timed out and
    // evicted worker 2 legitimately — then a third spawn is the real code's.
    test("a killed worker's late exit never orphans its replacement", () async {
      final svc = await IsolateSearchService.spawn(
        dbPath: path,
        count: 1,
        timeout: const Duration(milliseconds: 2500),
      );
      addTearDown(svc.dispose);
      await expectLater(
        svc.search(query, page: 1, limit: 10),
        throwsA(isA<StateError>()),
      );
      expect(svc.pendingExits, 1, reason: 'precondition: worker 1 in SQLite');
      final second = svc.search(query, page: 1, limit: 10);
      await until(() => svc.totalSpawns == 2); // worker 2 ready
      release(); // worker 1 leaves SQLite and dies
      final served = await second.then((_) => true, onError: (_) => false);
      await until(() => svc.pendingExits == 0); // every late exit handled
      await svc.search(query, page: 1, limit: 10);
      expect(
        svc.totalSpawns,
        served ? 2 : 3,
        reason: "worker 1's late exit marked worker 2 dead (orphaned)",
      );
    });

    // dispose() asks the worker to shut down; held inside SQLite it misses the
    // 2 s reply, so dispose() must kill it AND wait for its exit, which comes
    // only after the release at 2.5 s. Returning without the kill, without
    // the wait, or with the wait's set cleared instead, returns at ~2.0 s.
    // Timers: the release (2.5 s) and dispose()'s reply timeout (2 s) are
    // both this isolate's, so they fire in deadline order however it stalls;
    // the wait's 1 s bound ends after the release too. ASSUMED, the worker's
    // pace: its thread STARTS the search (enters SQLite) within dispose()'s
    // 2 s reply bound. A worker starved past that still has the search
    // queued when the kill lands; `Isolate.immediate` acts before it, so the
    // worker dies at ~2.0 s, its exit arrives and dispose() returns before
    // the release — `released` false on the real code. NOT asserted: that
    // the exit arrived (`pendingExits` 0) — that needs the worker's thread
    // to leave SQLite and die within 0.5 s of the release.
    test('dispose() kills a worker that missed its shutdown reply and waits '
        'for its exit', () async {
      final svc = await IsolateSearchService.spawn(dbPath: path, count: 1);
      unawaited(
        svc.search(query, page: 1, limit: 10).then((_) {}, onError: (_) {}),
      );
      // run() sends its request in a microtask; a timer event comes after it,
      // so the request is queued at the worker ahead of the shutdown.
      await Future<void>.delayed(Duration.zero);
      Timer(const Duration(milliseconds: 2500), release);
      await svc.dispose();
      expect(
        released,
        isTrue,
        reason: 'dispose() returned while the worker was still inside SQLite',
      );
    });
  });
}
