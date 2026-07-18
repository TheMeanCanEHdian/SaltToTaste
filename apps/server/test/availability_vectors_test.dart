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
import 'package:salt_server/src/search/search_service.dart';
import 'package:salt_server/src/shutdown.dart';
import 'package:test/test.dart';

/// The two availability vectors #42's critic reasoned about but could not drive
/// in-harness, now driven with real sockets and the REAL drain code:
///
///  * slowloris — many half-open sockets that never finish their request must
///    NOT stall the single-isolate event loop (they are parked `idle`, not
///    `active`), and the server must reap them via its idle timeout;
///  * SIGTERM-drain — [drainConnections] must WAIT for an in-flight request to
///    finish (not the "drain was a no-op" bug), force-close only past its
///    bound, and never be extended by an idle/half-open socket.
class _UnusedNutrition implements NutritionProvider {
  @override
  Future<List<FdcCandidate>> search(String query) => throw UnimplementedError();
  @override
  Future<FdcFood?> food(int fdcId) => throw UnimplementedError();
}

void main() {
  late Directory tempDir;
  late SaltDatabase database;

  /// Slow (1500ms) and never-ending routes so a request can be caught in-flight
  /// by the drain, plus /healthz for the event-loop responsiveness probe.
  FutureOr<Response> dispatch(RequestContext context) async {
    switch (context.request.uri.path) {
      case '/healthz':
        return Response.json(body: {'status': 'ok'});
      case '/slow':
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        return Response(body: 'slow-done');
      case '/forever':
        await Future<void>.delayed(const Duration(seconds: 30));
        return Response(body: 'never');
      default:
        return Response(statusCode: HttpStatus.notFound, body: 'nope');
    }
  }

  Future<HttpServer> startServer() async {
    tempDir = Directory.systemTemp.createTempSync('salt_avail_test_');
    final config = ServerConfig.fromEnvironment(
      environment: {'DATA_DIR': tempDir.path, 'LOG_LEVEL': 'ERROR'},
    );
    database = SaltDatabase.open('${tempDir.path}/salt.db');
    File('${tempDir.path}/index.html').writeAsStringSync('<html></html>');
    final pipeline = buildAppMiddleware(
      dispatch,
      config: config,
      database: database,
      authRuntime: AuthRuntime(),
      nutritionProvider: _UnusedNutrition(),
      searchRateLimiter: RequestRateLimiter(),
      searchService: () => InlineSearchService(database),
      logStore: LogStore(directory: '${tempDir.path}/logs'),
      indexPath: '${tempDir.path}/index.html',
    );
    return serve(pipeline, InternetAddress.loopbackIPv4, 0);
  }

  void cleanup(HttpServer server) {
    addTearDown(() async {
      try {
        await server.close(force: true);
      } catch (_) {
        // Already closed by the drain under test.
      }
      database.dispose();
      tempDir.deleteSync(recursive: true);
    });
  }

  Future<int> healthzLatencyMs(int port) async {
    final client = HttpClient();
    try {
      final sw = Stopwatch()..start();
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/healthz'),
      );
      final resp = await req.close();
      await utf8.decoder.bind(resp).drain<void>();
      sw.stop();
      expect(resp.statusCode, 200);
      return sw.elapsedMilliseconds;
    } finally {
      client.close();
    }
  }

  /// Opens [n] connections that send a partial request and never terminate the
  /// headers (no final CRLF), holding each socket open.
  Future<List<Socket>> openSlowloris(int port, int n) async {
    final held = <Socket>[];
    for (var i = 0; i < n; i++) {
      final s = await Socket.connect(InternetAddress.loopbackIPv4, port);
      s
        ..listen((_) {}, onError: (_) {}, cancelOnError: false)
        ..write('GET /healthz HTTP/1.1\r\nHost: localhost\r\nX-Drip: ');
      held.add(s);
    }
    return held;
  }

  group('slowloris', () {
    test(
      'half-open sockets are parked idle and do not stall the event loop',
      () async {
        final server = await startServer();
        cleanup(server);

        const n = 300;
        final held = await openSlowloris(server.port, n);
        addTearDown(() {
          for (final s in held) {
            s.destroy();
          }
        });
        await Future<void>.delayed(const Duration(milliseconds: 300));

        final info = server.connectionsInfo();
        // The whole point: the half-open sockets are counted IDLE, never
        // ACTIVE, so they never touch the serving isolate's event loop.
        expect(info.active, 0, reason: 'half-open sockets must not be active');
        expect(
          info.idle,
          greaterThanOrEqualTo(n - 20),
          reason: 'held sockets should be parked idle',
        );

        // A normal request is still served promptly under the held load.
        final underLoad = await healthzLatencyMs(server.port);
        expect(
          underLoad,
          lessThan(750),
          reason: 'event loop must stay responsive with $n half-open sockets',
        );
      },
    );

    test(
      'the server reaps a socket stalled mid-headers after its idle timeout',
      () async {
        final server = await startServer();
        cleanup(server);
        // main.dart wires this from config; drive it fast here.
        server.idleTimeout = const Duration(seconds: 1);

        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          server.port,
        );
        var closedByServer = false;
        socket
          ..listen((_) {}, onDone: () => closedByServer = true, onError: (_) {})
          ..write('GET /healthz HTTP/1.1\r\nHost: localhost\r\nX-Drip: ');

        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(server.connectionsInfo().total, 1, reason: 'still held early');

        // The idle sweep fires on a timer at ~[1x, 2x] the timeout, so poll to
        // a generous deadline rather than a fixed wait (flaky at the boundary).
        final deadline = DateTime.now().add(const Duration(seconds: 4));
        while (!closedByServer && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          closedByServer,
          isTrue,
          reason: 'idle timeout must reap the stalled half-open socket',
        );
        expect(server.connectionsInfo().total, 0);
        socket.destroy();
      },
    );
  });

  group('SIGTERM drain', () {
    test(
      'waits for an in-flight request to finish, without force-closing',
      () async {
        final server = await startServer();
        cleanup(server);

        final client = HttpClient();
        addTearDown(client.close);
        final slowResult = () async {
          final req = await client.getUrl(
            Uri.parse('http://127.0.0.1:${server.port}/slow'),
          );
          final resp = await req.close();
          return (resp.statusCode, await utf8.decoder.bind(resp).join());
        }();
        // Let the request reach the handler and become active.
        await Future<void>.delayed(const Duration(milliseconds: 300));

        // Also hold a slowloris socket: it must NOT extend the drain.
        final stalled =
            await Socket.connect(
                InternetAddress.loopbackIPv4,
                server.port,
              )
              ..listen((_) {}, onError: (_) {})
              ..write('GET /slow HTTP/1.1\r\nHost: localhost\r\nX-Drip: ');
        addTearDown(stalled.destroy);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        final sw = Stopwatch()..start();
        final forced = await drainConnections(
          server,
          bound: const Duration(seconds: 5),
        );
        sw.stop();

        final (status, body) = await slowResult;

        // The drain BLOCKED until the in-flight request finished (~1200ms
        // left): a no-op drain that returned immediately would fail this.
        expect(
          sw.elapsedMilliseconds,
          greaterThan(800),
          reason:
              'drain must wait for the active request, not return instantly',
        );
        // ...but not the full 5s bound — the idle socket did not extend it.
        expect(sw.elapsedMilliseconds, lessThan(4000));
        expect(forced, isFalse, reason: 'nothing needed force-closing');
        expect(status, 200, reason: 'the in-flight request completed');
        expect(body, 'slow-done');
      },
    );

    test('force-closes a request that outlasts the drain bound', () async {
      final server = await startServer();
      cleanup(server);

      final client = HttpClient();
      addTearDown(client.close);
      // /forever runs 30s; the drain bound is 500ms, so it must be force-closed.
      var errored = false;
      final foreverResult = () async {
        try {
          final req = await client.getUrl(
            Uri.parse('http://127.0.0.1:${server.port}/forever'),
          );
          final resp = await req.close();
          await utf8.decoder.bind(resp).drain<void>();
        } on Object {
          errored = true;
        }
      }();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final sw = Stopwatch()..start();
      final forced = await drainConnections(
        server,
        bound: const Duration(milliseconds: 500),
      );
      sw.stop();
      await foreverResult;

      expect(forced, isTrue, reason: 'the over-long request must be forced');
      // Completed near the bound, NOT the 30s handler duration.
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(400));
      expect(sw.elapsedMilliseconds, lessThan(3000));
      expect(
        errored,
        isTrue,
        reason: 'the forced client sees its connection cut',
      );
    });
  });
}
