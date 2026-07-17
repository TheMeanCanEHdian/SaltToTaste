import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart' hide requestLogger;
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:test/test.dart';

import '../routes/api/v1/auth/login.dart' as login_route;
import '../routes/api/v1/recipes/index.dart' as recipes_route;

// Auth inputs cannot come from the recipe corpus, so they are synthesized.
const _password = 'correct-horse-battery-staple';

/// The search rate limit wired end to end: a burst of `GET /recipes?q=` past
/// the per-user budget is refused with a 429 envelope and a `Retry-After`,
/// plain listing is never throttled, and the budget is per user — not global.
/// An empty database is enough: the FTS query returns no rows, but the limiter
/// fires before results are ever computed.
void main() {
  late Directory tempDir;
  late SaltDatabase db;
  late HttpServer server;
  late Uri baseUri;
  late String samSession;
  late String patSession;

  // Reassigned fresh per test; the provider below reads this variable at
  // request time, so each test gets an untouched budget.
  late RequestRateLimiter limiter;

  FutureOr<Response> dispatch(RequestContext context) {
    switch (context.request.uri.path) {
      case '/api/v1/auth/login':
        return login_route.onRequest(context);
      case '/api/v1/recipes':
        return recipes_route.onRequest(context);
      default:
        return Response(statusCode: HttpStatus.notFound);
    }
  }

  Future<(HttpClientResponse, String)> send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    Object? jsonBody,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, baseUri.resolve(path));
      headers.forEach(request.headers.set);
      if (jsonBody != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(jsonBody));
      }
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      return (response, body);
    } finally {
      client.close();
    }
  }

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('salt_search_rl_');
    final config = ServerConfig.fromEnvironment(
      environment: {'DATA_DIR': tempDir.path, 'LOG_LEVEL': 'ERROR'},
    );
    configureLogging(config);
    db = SaltDatabase.open(config.dbPath);
    final runtime = AuthRuntime();
    limiter = RequestRateLimiter(maxRequests: 3);

    final pipeline = dispatch
        .use(authProvider())
        .use(provider<RequestRateLimiter>((_) => limiter))
        .use(provider<NutritionProvider>((_) => _UnusedNutrition()))
        .use(provider<AuthRuntime>((_) => runtime))
        .use(provider<SaltDatabase>((_) => db))
        .use(provider<ServerConfig>((_) => config))
        .use(errorHandler())
        .use(requestIdProvider());
    server = await serve(pipeline, InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://127.0.0.1:${server.port}');

    for (final name in ['sam', 'pat']) {
      db.createUser(
        username: name,
        passwordHash: await runtime.hasher.hash(_password),
        role: 'member',
      );
    }

    Future<String> login(String username) async {
      final (response, body) = await send(
        'POST',
        '/api/v1/auth/login',
        jsonBody: {'username': username, 'password': _password},
      );
      expect(response.statusCode, HttpStatus.ok, reason: body);
      return (jsonDecode(body) as Map<String, dynamic>)['token'] as String;
    }

    samSession = await login('sam');
    patSession = await login('pat');
  });

  setUp(() {
    // A fresh budget of three searches per user for each test.
    limiter = RequestRateLimiter(maxRequests: 3);
  });

  tearDownAll(() async {
    db.dispose();
    await server.close(force: true);
    tempDir.deleteSync(recursive: true);
  });

  Map<String, String> bearer(String token) => {
    'Authorization': 'Bearer $token',
  };

  Map<String, dynamic> errorOf(String body) =>
      (jsonDecode(body) as Map<String, dynamic>)['error']
          as Map<String, dynamic>;

  test(
    'a burst past the budget is refused with a 429 and Retry-After',
    () async {
      for (var i = 0; i < 3; i++) {
        final (response, body) = await send(
          'GET',
          '/api/v1/recipes?q=cake',
          headers: bearer(samSession),
        );
        expect(
          response.statusCode,
          HttpStatus.ok,
          reason: 'search ${i + 1}: $body',
        );
      }
      final (response, body) = await send(
        'GET',
        '/api/v1/recipes?q=cake',
        headers: bearer(samSession),
      );
      expect(response.statusCode, 429, reason: body);
      expect(errorOf(body)['code'], 'rate_limited');
      final retryAfter = response.headers.value(HttpHeaders.retryAfterHeader);
      expect(retryAfter, isNotNull);
      expect(int.parse(retryAfter!), greaterThan(0));
    },
  );

  test('plain listing (no q) is never rate-limited', () async {
    // Well past the search budget of three: ordinary browsing and pagination
    // must not trip the guard.
    for (var i = 0; i < 8; i++) {
      final (response, _) = await send(
        'GET',
        '/api/v1/recipes',
        headers: bearer(samSession),
      );
      expect(response.statusCode, HttpStatus.ok, reason: 'page ${i + 1}');
    }
  });

  test('a whitespace-only q is treated as no search', () async {
    // `q=%20` trims to empty, so it is the cheap listing path, not FTS, and is
    // not counted against the budget.
    for (var i = 0; i < 6; i++) {
      final (response, _) = await send(
        'GET',
        '/api/v1/recipes?q=%20',
        headers: bearer(samSession),
      );
      expect(
        response.statusCode,
        HttpStatus.ok,
        reason: 'blank search ${i + 1}',
      );
    }
  });

  test('the budget is per user, not global', () async {
    for (var i = 0; i < 3; i++) {
      await send('GET', '/api/v1/recipes?q=cake', headers: bearer(samSession));
    }
    final (samBlocked, _) = await send(
      'GET',
      '/api/v1/recipes?q=cake',
      headers: bearer(samSession),
    );
    expect(samBlocked.statusCode, 429, reason: 'sam has spent the budget');

    final (patOk, body) = await send(
      'GET',
      '/api/v1/recipes?q=cake',
      headers: bearer(patSession),
    );
    expect(
      patOk.statusCode,
      HttpStatus.ok,
      reason: 'pat has an untouched budget: $body',
    );
  });
}

/// The search route here never touches nutrition; this stands in for the
/// provider so the real auth chain can be assembled.
class _UnusedNutrition implements NutritionProvider {
  @override
  Future<List<FdcCandidate>> search(String query) => throw UnimplementedError();

  @override
  Future<FdcFood?> food(int fdcId) => throw UnimplementedError();
}
