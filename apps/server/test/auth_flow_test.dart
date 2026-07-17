import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart' hide requestLogger;
import 'package:salt_server/src/auth/tokens.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/middleware/request_logger.dart';
import 'package:test/test.dart';

import '../routes/api/v1/auth/change_password.dart' as change_password_route;
import '../routes/api/v1/auth/login.dart' as login_route;
import '../routes/api/v1/auth/logout.dart' as logout_route;
import '../routes/api/v1/auth/me.dart' as me_route;
import '../routes/api/v1/auth/setup.dart' as setup_route;
import '../routes/api/v1/recipes/index.dart' as recipes_route;
import '../routes/api/v1/sessions/[id].dart' as session_route;
import '../routes/api/v1/tokens/[id].dart' as token_route;
import '../routes/api/v1/tokens/index.dart' as tokens_route;
import '../routes/api/v1/users/[id]/index.dart' as user_route;
import '../routes/api/v1/users/[id]/reset_password.dart' as reset_route;
import '../routes/api/v1/users/index.dart' as users_route;

// Synthesized credentials: auth inputs cannot come from the recipe corpus.
const _setupCode = 'ABCD-EFGH';
const _adminPassword = 'admin-password-123';
const _memberPassword = 'correct-horse-battery';
const _uniformLoginError = 'Invalid username or password.';
const _csrfHeader = {'X-Requested-With': 'SaltToTaste'};

void main() {
  late Directory tempDir;
  late ServerConfig config;
  late SaltDatabase db;
  late AuthRuntime runtime;
  late HttpServer server;
  late Uri baseUri;
  late String memberHash; // one Argon2id hash reused across test users

  // Filled by the setup test, used by everything after it.
  late String adminToken;
  late int adminId;

  // Stand-in for the generated dart_frog route table, wired exactly like
  // routes/_middleware.dart but with test-owned singletons.
  FutureOr<Response> dispatch(RequestContext context) {
    switch (context.request.uri.path) {
      case '/api/v1/auth/setup':
        return setup_route.onRequest(context);
      case '/api/v1/auth/login':
        return login_route.onRequest(context);
      case '/api/v1/auth/logout':
        return logout_route.onRequest(context);
      case '/api/v1/auth/me':
        return me_route.onRequest(context);
      case '/api/v1/auth/change_password':
        return change_password_route.onRequest(context);
      case '/api/v1/recipes':
        return recipes_route.onRequest(context);
      case '/api/v1/tokens':
        return tokens_route.onRequest(context);
      case '/api/v1/users':
        return users_route.onRequest(context);
      default:
        final path = context.request.uri.path;
        final tokenMatch = RegExp(r'^/api/v1/tokens/([^/]+)$').firstMatch(path);
        if (tokenMatch != null) {
          return token_route.onRequest(context, tokenMatch.group(1)!);
        }
        final sessionMatch = RegExp(
          r'^/api/v1/sessions/([^/]+)$',
        ).firstMatch(path);
        if (sessionMatch != null) {
          return session_route.onRequest(context, sessionMatch.group(1)!);
        }
        final resetMatch = RegExp(
          r'^/api/v1/users/([^/]+)/reset_password$',
        ).firstMatch(path);
        if (resetMatch != null) {
          return reset_route.onRequest(context, resetMatch.group(1)!);
        }
        final userMatch = RegExp(r'^/api/v1/users/([^/]+)$').firstMatch(path);
        if (userMatch != null) {
          return user_route.onRequest(context, userMatch.group(1)!);
        }
        return Response(
          statusCode: HttpStatus.notFound,
          body: 'Route not found',
        );
    }
  }

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('salt_auth_flow_test_');
    config = ServerConfig.fromEnvironment(
      environment: {'DATA_DIR': tempDir.path, 'LOG_LEVEL': 'ERROR'},
    );
    configureLogging(config);
    db = SaltDatabase.open(config.dbPath);
    runtime = AuthRuntime(setupCode: _setupCode);
    memberHash = await runtime.hasher.hash(_memberPassword);

    final pipeline = dispatch
        .use(authProvider())
        .use(provider<AuthRuntime>((_) => runtime))
        .use(provider<SaltDatabase>((_) => db))
        .use(provider<ServerConfig>((_) => config))
        .use(errorHandler())
        .use(requestLogger())
        .use(requestIdProvider());
    server = await serve(pipeline, InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://127.0.0.1:${server.port}');
  });

  tearDownAll(() async {
    await server.close(force: true);
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

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

  Map<String, dynamic> jsonOf(String body) =>
      jsonDecode(body) as Map<String, dynamic>;

  Map<String, dynamic> errorOf(String body) =>
      jsonOf(body)['error'] as Map<String, dynamic>;

  Future<(HttpClientResponse, String)> loginAs(
    String username,
    String password, {
    bool? remember,
  }) {
    return send(
      'POST',
      '/api/v1/auth/login',
      jsonBody: {
        'username': username,
        'password': password,
        if (remember != null) 'remember': remember,
      },
    );
  }

  /// Logs in expecting success and returns the raw session token.
  Future<String> sessionTokenFor(String username, String password) async {
    final (response, body) = await loginAs(username, password);
    expect(response.statusCode, HttpStatus.ok, reason: body);
    return jsonOf(body)['token'] as String;
  }

  int createMember(
    String username, {
    bool mustChangePassword = false,
    bool disabled = false,
  }) {
    final id = db.createUser(
      username: username,
      passwordHash: memberHash,
      role: 'member',
      mustChangePassword: mustChangePassword,
    );
    if (disabled) {
      db.setUserDisabled(id, disabled: true);
    }
    return id;
  }

  group('first boot', () {
    test('recipes without a credential -> 401 unauthorized envelope', () async {
      final (response, body) = await send('GET', '/api/v1/recipes');
      expect(response.statusCode, HttpStatus.unauthorized);
      final error = errorOf(body);
      expect(error['code'], 'unauthorized');
      expect(error['message'], 'Sign in to continue.');
      expect(error['request_id'], isNotNull);
    });

    test('garbage bearer token -> 401', () async {
      final (response, _) = await send(
        'GET',
        '/api/v1/recipes',
        headers: {'Authorization': 'Bearer ${generateOpaqueToken()}'},
      );
      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('setup with a wrong code -> 422 validation', () async {
      final (response, body) = await send(
        'POST',
        '/api/v1/auth/setup',
        jsonBody: {
          'setup_code': 'ZZZZ-ZZZZ',
          'username': 'admin',
          'password': _adminPassword,
        },
      );
      expect(response.statusCode, HttpStatus.unprocessableEntity);
      expect(errorOf(body)['code'], 'validation');
      expect(db.userCount(), 0);
    });

    test('setup rejects a short password and a bad username', () async {
      for (final payload in [
        {'username': 'admin', 'password': 'short-pass'},
        {'username': 'a', 'password': _adminPassword},
        {'username': 'has spaces!', 'password': _adminPassword},
      ]) {
        final (response, body) = await send(
          'POST',
          '/api/v1/auth/setup',
          jsonBody: {'setup_code': _setupCode, ...payload},
        );
        expect(
          response.statusCode,
          HttpStatus.unprocessableEntity,
          reason: '$payload should be rejected',
        );
        expect(errorOf(body)['code'], 'validation');
      }
      expect(db.userCount(), 0);
    });

    test('setup with the correct code creates a signed-in admin', () async {
      final (response, body) = await send(
        'POST',
        '/api/v1/auth/setup',
        jsonBody: {
          // Dash/case tolerance is part of the setup-code contract.
          'setup_code': _setupCode.toLowerCase().replaceAll('-', ''),
          'username': 'admin',
          'password': _adminPassword,
        },
      );
      expect(response.statusCode, HttpStatus.ok, reason: body);

      final decoded = jsonOf(body);
      adminToken = decoded['token'] as String;
      final user = decoded['user'] as Map<String, dynamic>;
      adminId = user['id'] as int;
      expect(user['username'], 'admin');
      expect(user['role'], 'admin');

      final setCookie = response.headers.value('set-cookie');
      expect(setCookie, isNotNull);
      expect(setCookie, startsWith('$sessionCookieName=$adminToken'));
      expect(setCookie, contains('HttpOnly'));
      expect(setCookie, contains('SameSite=Lax'));
      expect(setCookie, contains('Path=/'));
      // No trusted HTTPS proxy in tests -> no Secure attribute.
      expect(setCookie, isNot(contains('Secure')));

      // The one-time code is consumed.
      expect(runtime.setupCode, isNull);
    });

    test('the session cookie fetches recipes', () async {
      final (response, body) = await send(
        'GET',
        '/api/v1/recipes',
        headers: {'Cookie': '$sessionCookieName=$adminToken'},
      );
      expect(response.statusCode, HttpStatus.ok, reason: body);
      expect(jsonOf(body)['items'], isEmpty);
    });

    test('the same token works as a bearer credential', () async {
      final (response, _) = await send(
        'GET',
        '/api/v1/recipes',
        headers: {'Authorization': 'Bearer $adminToken'},
      );
      expect(response.statusCode, HttpStatus.ok);
    });

    test('me reports the session principal', () async {
      final (response, body) = await send(
        'GET',
        '/api/v1/auth/me',
        headers: {'Authorization': 'Bearer $adminToken'},
      );
      expect(response.statusCode, HttpStatus.ok);
      final user = jsonOf(body)['user'] as Map<String, dynamic>;
      expect(user['username'], 'admin');
      expect(user['role'], 'admin');
      expect(user['must_change_password'], false);
      expect(user['scope'], 'full');
      expect(user['via'], 'session');
    });

    test('setup is forbidden once a user exists', () async {
      final (response, body) = await send(
        'POST',
        '/api/v1/auth/setup',
        jsonBody: {
          'setup_code': _setupCode,
          'username': 'admin2',
          'password': _adminPassword,
        },
      );
      expect(response.statusCode, HttpStatus.forbidden);
      expect(errorOf(body)['code'], 'forbidden');
    });

    test('GET on the login route -> 405 envelope', () async {
      final (response, body) = await send('GET', '/api/v1/auth/login');
      expect(response.statusCode, HttpStatus.methodNotAllowed);
      expect(errorOf(body)['code'], 'method_not_allowed');
    });
  });

  group('login failures', () {
    test('unknown username -> uniform 422', () async {
      final (response, body) = await loginAs('ghost', _memberPassword);
      expect(response.statusCode, HttpStatus.unprocessableEntity);
      final error = errorOf(body);
      expect(error['code'], 'validation');
      expect(error['message'], _uniformLoginError);
    });

    test(
      'disabled user with the correct password -> same uniform 422',
      () async {
        createMember('sleepy', disabled: true);
        final (response, body) = await loginAs('sleepy', _memberPassword);
        expect(response.statusCode, HttpStatus.unprocessableEntity);
        final error = errorOf(body);
        expect(error['code'], 'validation');
        expect(error['message'], _uniformLoginError);
      },
    );

    test(
      'five wrong passwords lock the account; the 6th attempt is 429',
      () async {
        createMember('lockme');
        for (var attempt = 1; attempt <= 5; attempt++) {
          final (response, body) = await loginAs('lockme', 'wrong-password-x');
          expect(
            response.statusCode,
            HttpStatus.unprocessableEntity,
            reason: 'attempt $attempt should still be a plain failure',
          );
          expect(errorOf(body)['message'], _uniformLoginError);
        }
        // Locked now — even the correct password is rejected with 429.
        final (locked, lockedBody) = await loginAs('lockme', _memberPassword);
        expect(locked.statusCode, HttpStatus.tooManyRequests);
        final error = errorOf(lockedBody);
        expect(error['code'], 'locked');
        expect(
          error['message'],
          matches(RegExp(r'Try again in \d+ seconds\.')),
        );
      },
    );
  });

  group('sessions', () {
    test('cookie POST without X-Requested-With -> 403 csrf (and the session '
        'survives)', () async {
      final (response, body) = await send(
        'POST',
        '/api/v1/auth/logout',
        headers: {'Cookie': '$sessionCookieName=$adminToken'},
      );
      expect(response.statusCode, HttpStatus.forbidden);
      expect(errorOf(body)['code'], 'csrf');
      expect(db.sessionByHash(hashToken(adminToken)), isNotNull);
    });

    test('logout with the CSRF header deletes the session and clears the '
        'cookie', () async {
      createMember('leaver');
      final token = await sessionTokenFor('leaver', _memberPassword);
      final (response, _) = await send(
        'POST',
        '/api/v1/auth/logout',
        headers: {'Cookie': '$sessionCookieName=$token', ..._csrfHeader},
      );
      expect(response.statusCode, HttpStatus.ok);
      final setCookie = response.headers.value('set-cookie');
      expect(setCookie, startsWith('$sessionCookieName=;'));
      expect(setCookie, contains('Max-Age=0'));
      expect(db.sessionByHash(hashToken(token)), isNull);

      final (after, _) = await send(
        'GET',
        '/api/v1/auth/me',
        headers: {'Authorization': 'Bearer $token'},
      );
      expect(after.statusCode, HttpStatus.unauthorized);
    });

    test('expired session -> 401 and the row is deleted', () async {
      final token = generateOpaqueToken();
      db.createSession(
        tokenHash: hashToken(token),
        userId: adminId,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        remember: false,
      );
      final (response, _) = await send(
        'GET',
        '/api/v1/auth/me',
        headers: {'Authorization': 'Bearer $token'},
      );
      expect(response.statusCode, HttpStatus.unauthorized);
      expect(db.sessionByHash(hashToken(token)), isNull);
    });

    test('remember sessions get sliding expiry on each request', () async {
      createMember('sticky');
      final (response, body) = await loginAs(
        'sticky',
        _memberPassword,
        remember: true,
      );
      expect(response.statusCode, HttpStatus.ok);
      final token = jsonOf(body)['token'] as String;

      final before = db.sessionByHash(hashToken(token))!;
      expect(before.remember, isTrue);
      final ninetyDays = DateTime.now().toUtc().add(const Duration(days: 90));
      expect(
        before.expiresAt.difference(ninetyDays).abs(),
        lessThan(const Duration(minutes: 1)),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await send(
        'GET',
        '/api/v1/auth/me',
        headers: {'Authorization': 'Bearer $token'},
      );
      final after = db.sessionByHash(hashToken(token))!;
      expect(after.expiresAt.isAfter(before.expiresAt), isTrue);
    });

    test(
      'change_password keeps the current session and kills the other',
      () async {
        createMember('rotator');
        final tokenA = await sessionTokenFor('rotator', _memberPassword);
        final tokenB = await sessionTokenFor('rotator', _memberPassword);

        final (response, body) = await send(
          'POST',
          '/api/v1/auth/change_password',
          headers: {'Cookie': '$sessionCookieName=$tokenA', ..._csrfHeader},
          jsonBody: {
            'current_password': _memberPassword,
            'new_password': 'rotated-password-99',
          },
        );
        expect(response.statusCode, HttpStatus.ok, reason: body);

        final (otherSession, _) = await send(
          'GET',
          '/api/v1/auth/me',
          headers: {'Authorization': 'Bearer $tokenB'},
        );
        expect(otherSession.statusCode, HttpStatus.unauthorized);

        final (ownSession, _) = await send(
          'GET',
          '/api/v1/auth/me',
          headers: {'Authorization': 'Bearer $tokenA'},
        );
        expect(ownSession.statusCode, HttpStatus.ok);

        // Old password is dead, new one works.
        final (oldLogin, oldBody) = await loginAs('rotator', _memberPassword);
        expect(oldLogin.statusCode, HttpStatus.unprocessableEntity);
        expect(errorOf(oldBody)['message'], _uniformLoginError);
        await sessionTokenFor('rotator', 'rotated-password-99');
      },
    );

    test('change_password with a wrong current_password -> 422', () async {
      createMember('cautious');
      final token = await sessionTokenFor('cautious', _memberPassword);
      final (response, body) = await send(
        'POST',
        '/api/v1/auth/change_password',
        headers: {'Cookie': '$sessionCookieName=$token', ..._csrfHeader},
        jsonBody: {
          'current_password': 'not-the-password',
          'new_password': 'whatever-new-pass-1',
        },
      );
      expect(response.statusCode, HttpStatus.unprocessableEntity);
      expect(errorOf(body)['code'], 'validation');
    });
  });

  group('personal access tokens', () {
    late String patToken;
    late int patId;

    setUpAll(() {
      final pat = generatePat();
      patToken = pat.token;
      patId = db.createApiToken(
        userId: adminId,
        name: 'test token',
        prefix: pat.prefix,
        tokenHash: hashToken(pat.token),
        scope: 'read',
      );
    });

    test('a PAT bearer fetches recipes and reports pat/read via me', () async {
      final (recipes, _) = await send(
        'GET',
        '/api/v1/recipes',
        headers: {'Authorization': 'Bearer $patToken'},
      );
      expect(recipes.statusCode, HttpStatus.ok);

      final (me, body) = await send(
        'GET',
        '/api/v1/auth/me',
        headers: {'Authorization': 'Bearer $patToken'},
      );
      expect(me.statusCode, HttpStatus.ok);
      final user = jsonOf(body)['user'] as Map<String, dynamic>;
      expect(user['via'], 'pat');
      expect(user['scope'], 'read');
      expect(user['username'], 'admin');
    });

    test('a PAT cannot log out (422) nor change passwords (403)', () async {
      final (logout, logoutBody) = await send(
        'POST',
        '/api/v1/auth/logout',
        headers: {'Authorization': 'Bearer $patToken'},
      );
      expect(logout.statusCode, HttpStatus.unprocessableEntity);
      expect(errorOf(logoutBody)['code'], 'validation');

      final (change, changeBody) = await send(
        'POST',
        '/api/v1/auth/change_password',
        headers: {'Authorization': 'Bearer $patToken'},
        jsonBody: {'new_password': 'whatever-new-pass-1'},
      );
      expect(change.statusCode, HttpStatus.forbidden);
      expect(errorOf(changeBody)['code'], 'forbidden');
    });

    test(
      'a read-scoped PAT is denied every mutation (scope enforcement)',
      () async {
        // A leaked read PAT must not self-escalate by minting a full token,
        // and (even on an admin account) must not perform admin mutations:
        // effective permission = role ∩ scope.
        final attempts = <(String, String, Map<String, Object?>?)>[
          ('POST', '/api/v1/tokens', {'name': 'escalate', 'scope': 'full'}),
          ('POST', '/api/v1/users', {'username': 'mallory', 'role': 'admin'}),
          ('POST', '/api/v1/users/$adminId/reset_password', null),
          ('PATCH', '/api/v1/users/999', {'disabled': true}),
          ('DELETE', '/api/v1/tokens/999', null),
          ('DELETE', '/api/v1/sessions/doesnotmatter', null),
        ];
        for (final (method, path, body) in attempts) {
          final (response, responseBody) = await send(
            method,
            path,
            headers: {'Authorization': 'Bearer $patToken'},
            jsonBody: body,
          );
          expect(
            response.statusCode,
            HttpStatus.forbidden,
            reason: '$method $path must be forbidden for a read PAT',
          );
          expect(errorOf(responseBody)['code'], 'forbidden');
        }

        // Reads still work with the same token.
        final (recipes, _) = await send(
          'GET',
          '/api/v1/recipes',
          headers: {'Authorization': 'Bearer $patToken'},
        );
        expect(recipes.statusCode, HttpStatus.ok);
      },
    );

    test('a revoked PAT -> 401', () async {
      expect(db.revokeApiToken(id: patId, userId: adminId), isTrue);
      final (response, _) = await send(
        'GET',
        '/api/v1/recipes',
        headers: {'Authorization': 'Bearer $patToken'},
      );
      expect(response.statusCode, HttpStatus.unauthorized);
    });
  });

  group('must_change_password', () {
    test('is blocked from recipes until the password is changed', () async {
      createMember('newbie', mustChangePassword: true);
      final (loginResponse, loginBody) = await loginAs(
        'newbie',
        _memberPassword,
      );
      expect(loginResponse.statusCode, HttpStatus.ok);
      final decoded = jsonOf(loginBody);
      final token = decoded['token'] as String;
      final user = decoded['user'] as Map<String, dynamic>;
      expect(user['must_change_password'], true);

      final auth = {'Authorization': 'Bearer $token'};

      final (blocked, blockedBody) = await send(
        'GET',
        '/api/v1/recipes',
        headers: auth,
      );
      expect(blocked.statusCode, HttpStatus.forbidden);
      expect(errorOf(blockedBody)['code'], 'password_change_required');

      // /auth/me stays reachable so the client can see why.
      final (me, _) = await send('GET', '/api/v1/auth/me', headers: auth);
      expect(me.statusCode, HttpStatus.ok);

      // No current_password needed while the change is forced.
      final (change, changeBody) = await send(
        'POST',
        '/api/v1/auth/change_password',
        headers: {...auth, ..._csrfHeader},
        jsonBody: {'new_password': 'my-real-password-1'},
      );
      expect(change.statusCode, HttpStatus.ok, reason: changeBody);

      final (unblocked, _) = await send(
        'GET',
        '/api/v1/recipes',
        headers: auth,
      );
      expect(unblocked.statusCode, HttpStatus.ok);

      final (meAfter, meBody) = await send(
        'GET',
        '/api/v1/auth/me',
        headers: auth,
      );
      expect(meAfter.statusCode, HttpStatus.ok);
      final meUser = jsonOf(meBody)['user'] as Map<String, dynamic>;
      expect(meUser['must_change_password'], false);
    });
  });
}
