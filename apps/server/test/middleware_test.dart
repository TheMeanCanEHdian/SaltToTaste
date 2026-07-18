import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart' hide requestLogger;
import 'package:logging/logging.dart';
import 'package:salt_server/src/app_pipeline.dart';
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/search/search_service.dart';
import 'package:test/test.dart';

import '../routes/healthz.dart' as healthz_route;
import '../routes/index.dart' as index_route;

final _hexId = RegExp(r'^[0-9a-f]{16}$');

/// The routes exercised here never touch nutrition; this stands in for the
/// provider so the REAL [buildAppMiddleware] chain can be assembled.
class _UnusedNutrition implements NutritionProvider {
  @override
  Future<List<FdcCandidate>> search(String query) => throw UnimplementedError();

  @override
  Future<FdcFood?> food(int fdcId) => throw UnimplementedError();
}

void main() {
  late Directory tempDir;
  late ServerConfig config;
  late SaltDatabase database;
  late HttpServer server;
  late Uri baseUri;
  final records = <LogRecord>[];

  // Stand-in for the generated dart_frog route table, using the real route
  // handlers plus routes that fail in every way the middleware must handle.
  FutureOr<Response> dispatch(RequestContext context) {
    switch (context.request.uri.path) {
      case '/':
        return index_route.onRequest(context);
      case '/healthz':
        return healthz_route.onRequest(context);
      case '/api/throws-not-found':
        throw const NotFoundException('Recipe does not exist.');
      case '/api/throws-validation':
        throw const ValidationException('Field "title" is required.');
      case '/api/throws-state-error':
        throw StateError('sensitive internal detail');
      case '/api/empty-404':
        return Response(statusCode: HttpStatus.notFound);
      case '/api/json-404':
        return Response.json(
          statusCode: HttpStatus.notFound,
          body: {'custom': true},
        );
      default:
        // Mimic dart_frog's router fallback for unmatched routes.
        return Response(
          statusCode: HttpStatus.notFound,
          body: 'Route not found',
        );
    }
  }

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('salt_middleware_test_');
    config = ServerConfig.fromEnvironment(
      environment: {'DATA_DIR': tempDir.path, 'LOG_LEVEL': 'INFO'},
    );
    configureLogging(config);
    Logger.root.onRecord.listen(records.add);

    // Drive the REAL production chain, not a parallel copy of it: a reorder in
    // buildAppMiddleware that stripped the CSP off the app shell or moved
    // errorHandler inside the providers must break a test here, which a
    // hand-rolled pipeline that could drift from production never guaranteed.
    // healthz reads SaltDatabase (for setup_required), so provide one.
    // The SPA fallback serves a REAL web-build shell written to the temp
    // dir (public/ is gitignored, so the checkout's copy can't be relied
    // on).
    database = SaltDatabase.open('${tempDir.path}/salt.db');
    File('${tempDir.path}/index.html').writeAsStringSync(
      '<!DOCTYPE html><html><head><title>SaltToTaste</title>\n'
      '</head><body></body></html>',
    );
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
    server = await serve(pipeline, InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://127.0.0.1:${server.port}');
  });

  tearDownAll(() async {
    database.dispose();
    await server.close(force: true);
    tempDir.deleteSync(recursive: true);
  });

  Future<(HttpClientResponse, String)> send(
    String method,
    String path,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, baseUri.resolve(path));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      return (response, body);
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> errorOf(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    return decoded['error'] as Map<String, dynamic>;
  }

  group('request id', () {
    test('every response carries a 16-hex X-Request-Id header', () async {
      final (response, _) = await send('GET', '/healthz');
      final id = response.headers.value(requestIdHeader);
      expect(id, isNotNull);
      expect(id, matches(_hexId));
    });

    test('ids differ between requests', () async {
      final (first, _) = await send('GET', '/healthz');
      final (second, _) = await send('GET', '/healthz');
      expect(
        first.headers.value(requestIdHeader),
        isNot(second.headers.value(requestIdHeader)),
      );
    });
  });

  group('error envelope', () {
    test(
      'AppException becomes its envelope with matching request_id',
      () async {
        final (response, body) = await send('GET', '/api/throws-not-found');
        expect(response.statusCode, HttpStatus.notFound);
        final error = errorOf(body);
        expect(error['code'], 'not_found');
        expect(error['message'], 'Recipe does not exist.');
        expect(error['request_id'], response.headers.value(requestIdHeader));
      },
    );

    test('ValidationException maps to 422/validation', () async {
      final (response, body) = await send('GET', '/api/throws-validation');
      expect(response.statusCode, HttpStatus.unprocessableEntity);
      expect(errorOf(body)['code'], 'validation');
    });

    test('unknown exceptions become an opaque 500 envelope', () async {
      records.clear();
      final (response, body) = await send('GET', '/api/throws-state-error');
      expect(response.statusCode, HttpStatus.internalServerError);
      final error = errorOf(body);
      expect(error['code'], 'internal');
      expect(error['message'], 'Internal server error.');
      expect(error['request_id'], response.headers.value(requestIdHeader));
      // No leaked details or stack frames in the body.
      expect(body, isNot(contains('StateError')));
      expect(body, isNot(contains('sensitive')));
      expect(body, isNot(contains('#0')));
      // ...but the log got the full story.
      final severe = records.where((r) => r.level == Level.SEVERE).toList();
      expect(severe, hasLength(1));
      expect(severe.single.loggerName, 'http');
      expect(severe.single.error, isA<StateError>());
      expect(severe.single.stackTrace, isNotNull);
    });

    test("router's bare 'Route not found' 404 is rewrapped", () async {
      final (response, body) = await send('GET', '/api/no-such-route');
      expect(response.statusCode, HttpStatus.notFound);
      final error = errorOf(body);
      expect(error['code'], 'not_found');
      expect(error['request_id'], matches(_hexId));
    });

    test('empty-body 404 is rewrapped', () async {
      final (response, body) = await send('GET', '/api/empty-404');
      expect(response.statusCode, HttpStatus.notFound);
      expect(errorOf(body)['code'], 'not_found');
    });

    test('any 404 response is rewrapped into the not_found envelope', () async {
      // Feature code throws NotFoundException rather than returning a 404
      // Response, so a 404 reaching the error handler is the router fallback
      // and is rewrapped regardless of its body (no framework-body sniffing).
      final (response, body) = await send('GET', '/api/json-404');
      expect(response.statusCode, HttpStatus.notFound);
      expect(errorOf(body)['code'], 'not_found');
    });
  });

  group('request logger', () {
    test('logs method, path, status, duration, and rid at INFO', () async {
      records.clear();
      await send('GET', '/api/empty-404');
      final http = records
          .where((r) => r.loggerName == 'http' && r.level == Level.INFO)
          .toList();
      expect(http, hasLength(1));
      expect(
        http.single.message,
        matches(
          RegExp(r'^GET /api/empty-404 -> 404 \(\d+ms\) rid=[0-9a-f]{16}$'),
        ),
      );
    });

    test(
      'operational polling paths are not logged (noise suppression)',
      () async {
        records.clear();
        // The liveness probe and the log viewer's own read both poll often;
        // logging them would flood the log (and show reads inside the very
        // list being read).
        await send('GET', '/healthz');
        await send('GET', '/api/v1/admin/logs');
        await send('GET', '/api/empty-404'); // an ordinary request IS logged
        final messages = records
            .where((r) => r.loggerName == 'http' && r.level == Level.INFO)
            .map((r) => r.message)
            .toList();
        expect(messages.where((m) => m.contains('/healthz')), isEmpty);
        expect(
          messages.where((m) => m.contains('/api/v1/admin/logs')),
          isEmpty,
        );
        expect(messages.any((m) => m.contains('/api/empty-404')), isTrue);
      },
    );

    test('failed requests are logged with their envelope status', () async {
      records.clear();
      await send('GET', '/api/throws-validation');
      final messages = records
          .where((r) => r.loggerName == 'http' && r.level == Level.INFO)
          .map((r) => r.message);
      expect(
        messages,
        contains(matches(RegExp('^GET /api/throws-validation -> 422 '))),
      );
    });
  });

  group('routes', () {
    test('GET /healthz returns ok', () async {
      final (response, body) = await send('GET', '/healthz');
      expect(response.statusCode, HttpStatus.ok);
      expect(jsonDecode(body), {'status': 'ok', 'setup_required': true});
    });

    test('POST /healthz returns a 405 envelope', () async {
      final (response, body) = await send('POST', '/healthz');
      expect(response.statusCode, HttpStatus.methodNotAllowed);
      final error = errorOf(body);
      expect(error['code'], 'method_not_allowed');
      expect(error['request_id'], matches(_hexId));
    });

    test('GET / serves the web app or the service identity', () async {
      final (response, body) = await send('GET', '/');
      expect(response.statusCode, HttpStatus.ok);
      // With a bundled web build (public/index.html) the shell is served;
      // API-only checkouts get the identity payload.
      if (File('public/index.html').existsSync()) {
        expect(body, contains('<!DOCTYPE html>'));
      } else {
        expect(jsonDecode(body), {'name': 'salt_server'});
      }
    });
  });

  group('web app serving (P7)', () {
    test('a deep link falls back to index.html with the CSP', () async {
      final (response, body) = await send(
        'GET',
        '/r/rich-chocolate-bundt-cake',
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'text/html');
      expect(body, contains('SaltToTaste'));
      expect(response.headers.value('cache-control'), 'no-cache');
      expect(
        response.headers.value('content-security-policy'),
        contains("default-src 'self'"),
      );
      expect(response.headers.value('x-frame-options'), 'DENY');
    });

    test('a deep link with a query string still boots the app', () async {
      final (response, body) = await send('GET', '/search?q=chocolate');
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'text/html');
      expect(body, contains('SaltToTaste'));
    });

    test('a recipe slug containing a dot still boots the app', () async {
      // Hand-edited YAML may give a recipe a dotted slug (e.g.
      // "st.-louis-gooey-butter-cake"); /r/ paths are exempt from the
      // "dotted segment is a missing asset" rule.
      final (response, _) = await send('GET', '/r/st.-louis-gooey-butter-cake');
      expect(response.statusCode, HttpStatus.ok);
    });

    test('API and asset misses keep their 404', () async {
      for (final path in [
        '/api/v1/does-not-exist',
        '/missing-chunk.dart.js',
        '/images/nope/x.jpg',
      ]) {
        final (response, _) = await send('GET', path);
        expect(response.statusCode, HttpStatus.notFound, reason: path);
      }
    });

    test('non-GET misses are not rewritten', () async {
      final (response, _) = await send('POST', '/r/some-recipe');
      expect(response.statusCode, HttpStatus.notFound);
    });

    test('every response carries nosniff and a referrer policy', () async {
      final (response, _) = await send('GET', '/healthz');
      expect(response.headers.value('x-content-type-options'), 'nosniff');
      expect(response.headers.value('referrer-policy'), 'same-origin');
      expect(
        response.headers.value('content-security-policy'),
        isNull,
        reason: 'CSP is for HTML, not JSON',
      );
    });
  });

  group('ServerConfig', () {
    test('creates the data dir and library subdir, exposes paths', () {
      final dir = Directory.systemTemp.createTempSync('salt_cfg_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final dataDir = '${dir.path}/nested/data';
      final cfg = ServerConfig.fromEnvironment(
        environment: {'DATA_DIR': dataDir},
      );
      expect(cfg.dataDir, dataDir);
      expect(cfg.dbPath, '$dataDir/salt.db');
      expect(cfg.libraryDir, '$dataDir/library');
      expect(Directory(cfg.libraryDir).existsSync(), isTrue);
    });

    test('resolves a relative DATA_DIR against the working directory', () {
      final dir = Directory.systemTemp.createTempSync('salt_cfg_rel_');
      final previous = Directory.current;
      Directory.current = dir;
      addTearDown(() {
        Directory.current = previous;
        dir.deleteSync(recursive: true);
      });
      final cfg = ServerConfig.fromEnvironment(
        environment: {'DATA_DIR': 'rel-data'},
      );
      expect(cfg.dataDir, '${Directory.current.path}/rel-data');
      expect(Directory(cfg.libraryDir).existsSync(), isTrue);
    });

    test('parses LOG_LEVEL values case-insensitively', () {
      final dir = Directory.systemTemp.createTempSync('salt_cfg_lvl_');
      addTearDown(() => dir.deleteSync(recursive: true));
      Level levelFor(String? raw) {
        return ServerConfig.fromEnvironment(
          environment: {
            'DATA_DIR': dir.path,
            if (raw != null) 'LOG_LEVEL': raw,
          },
        ).logLevel;
      }

      expect(levelFor(null), Level.INFO);
      expect(levelFor('INFO'), Level.INFO);
      expect(levelFor('debug'), Level.FINE);
      expect(levelFor('WARN'), Level.WARNING);
      expect(levelFor('Warning'), Level.WARNING);
      expect(levelFor('ERROR'), Level.SEVERE);
      expect(() => levelFor('VERBOSE'), throwsFormatException);
    });

    test('TRUST_PROXY is true only for "true"', () {
      final dir = Directory.systemTemp.createTempSync('salt_cfg_proxy_');
      addTearDown(() => dir.deleteSync(recursive: true));
      bool trustFor(String? raw) {
        return ServerConfig.fromEnvironment(
          environment: {
            'DATA_DIR': dir.path,
            if (raw != null) 'TRUST_PROXY': raw,
          },
        ).trustProxy;
      }

      expect(trustFor(null), isFalse);
      expect(trustFor('true'), isTrue);
      expect(trustFor('TRUE'), isTrue);
      expect(trustFor('1'), isFalse);
      expect(trustFor('false'), isFalse);
    });

    test('SEARCH_RATE_LIMIT parses; an invalid value keeps the default', () {
      final dir = Directory.systemTemp.createTempSync('salt_cfg_srl_');
      addTearDown(() => dir.deleteSync(recursive: true));
      int limitFor(String? raw) => ServerConfig.fromEnvironment(
        environment: {
          'DATA_DIR': dir.path,
          if (raw != null) 'SEARCH_RATE_LIMIT': raw,
        },
      ).searchRateLimit;

      expect(limitFor(null), ServerConfig.defaultSearchRateLimit);
      expect(limitFor('120'), 120);
      expect(limitFor('0'), 0, reason: '0 explicitly disables the limit');
      // A typo must fall back to the default, never silently disable the guard.
      expect(limitFor('abc'), ServerConfig.defaultSearchRateLimit);
      expect(limitFor('-5'), ServerConfig.defaultSearchRateLimit);
    });

    test('API_TOKEN_RETENTION_DAYS parses; an invalid value keeps default', () {
      final dir = Directory.systemTemp.createTempSync('salt_cfg_ret_');
      addTearDown(() => dir.deleteSync(recursive: true));
      int daysFor(String? raw) => ServerConfig.fromEnvironment(
        environment: {
          'DATA_DIR': dir.path,
          if (raw != null) 'API_TOKEN_RETENTION_DAYS': raw,
        },
      ).apiTokenRetentionDays;

      expect(daysFor(null), ServerConfig.defaultApiTokenRetentionDays);
      expect(daysFor('30'), 30);
      expect(daysFor('0'), 0, reason: '0 keeps revoked tokens forever');
      expect(daysFor('nope'), ServerConfig.defaultApiTokenRetentionDays);
      expect(daysFor('-1'), ServerConfig.defaultApiTokenRetentionDays);
    });

    test('CONNECTION_IDLE_TIMEOUT_SECONDS parses into a Duration', () {
      final dir = Directory.systemTemp.createTempSync('salt_cfg_idle_');
      addTearDown(() => dir.deleteSync(recursive: true));
      ServerConfig cfgFor(String? raw) => ServerConfig.fromEnvironment(
        environment: {
          'DATA_DIR': dir.path,
          if (raw != null) 'CONNECTION_IDLE_TIMEOUT_SECONDS': raw,
        },
      );

      // Default is below Dart's 120s so half-open sockets are reaped sooner.
      expect(
        cfgFor(null).connectionIdleTimeoutSeconds,
        ServerConfig.defaultConnectionIdleTimeoutSeconds,
      );
      expect(cfgFor(null).connectionIdleTimeout, const Duration(seconds: 75));
      expect(cfgFor('30').connectionIdleTimeout, const Duration(seconds: 30));
      // 0 disables the timeout (never auto-close), matching HttpServer.
      expect(cfgFor('0').connectionIdleTimeout, isNull);
      // A typo must not silently disable the reaper.
      expect(cfgFor('nope').connectionIdleTimeout, const Duration(seconds: 75));
      expect(cfgFor('-5').connectionIdleTimeout, const Duration(seconds: 75));
    });

    test('LOG_MAX_BYTES parses; an invalid value keeps the default', () {
      final dir = Directory.systemTemp.createTempSync('salt_cfg_log_');
      addTearDown(() => dir.deleteSync(recursive: true));
      int bytesFor(String? raw) => ServerConfig.fromEnvironment(
        environment: {
          'DATA_DIR': dir.path,
          if (raw != null) 'LOG_MAX_BYTES': raw,
        },
      ).logMaxBytes;

      expect(bytesFor(null), ServerConfig.defaultLogMaxBytes);
      expect(bytesFor('1048576'), 1048576);
      expect(bytesFor('0'), 0, reason: '0 disables the store');
      expect(bytesFor('nope'), ServerConfig.defaultLogMaxBytes);
      expect(bytesFor('-5'), ServerConfig.defaultLogMaxBytes);
    });
  });
}
