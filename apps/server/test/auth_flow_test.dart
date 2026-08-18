import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart' hide requestLogger;
import 'package:logging/logging.dart';
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/auth/recovery.dart';
import 'package:salt_server/src/auth/tokens.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/middleware/request_logger.dart';
import 'package:salt_server/src/search/search_service.dart';
import 'package:salt_server/src/services/backup_service.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../routes/api/v1/auth/change_password.dart' as change_password_route;
import '../routes/api/v1/auth/login.dart' as login_route;
import '../routes/api/v1/auth/logout.dart' as logout_route;
import '../routes/api/v1/auth/me.dart' as me_route;
import '../routes/api/v1/auth/setup.dart' as setup_route;
import '../routes/api/v1/backups/[name].dart' as backup_route;
import '../routes/api/v1/recipes/index.dart' as recipes_route;
import '../routes/api/v1/sessions/[id].dart' as session_route;
import '../routes/api/v1/settings/fdc_key.dart' as fdc_key_route;
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
const _accountDisabledError =
    'This account has been disabled. Contact an administrator.';
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
      case '/api/v1/settings/fdc_key':
        return fdc_key_route.onRequest(context);
      default:
        final path = context.request.uri.path;
        final backupMatch = RegExp(
          r'^/api/v1/backups/([^/]+)$',
        ).firstMatch(path);
        if (backupMatch != null) {
          return backup_route.onRequest(context, backupMatch.group(1)!);
        }
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
        .use(provider<SearchService>((_) => InlineSearchService(db)))
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
      'disabled user with the correct password -> specific disabled 422',
      () async {
        createMember('sleepy', disabled: true);
        final (response, body) = await loginAs('sleepy', _memberPassword);
        expect(response.statusCode, HttpStatus.unprocessableEntity);
        final error = errorOf(body);
        expect(error['code'], 'validation');
        expect(error['message'], _accountDisabledError);
      },
    );

    test(
      'disabled user with a WRONG password -> uniform 422 (no enumeration)',
      () async {
        // The disabled state is only ever named after a correct password; a
        // wrong guess must look identical to any other bad login.
        createMember('dozing', disabled: true);
        final (response, body) = await loginAs('dozing', 'not-the-password');
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

  group('disabled account lockout', () {
    test(
      'disabling a user ends its live session and kills its PAT mid-session',
      () async {
        final id = createMember('midshift');
        final sessionToken = await sessionTokenFor('midshift', _memberPassword);
        final pat = generatePat();
        db.createApiToken(
          userId: id,
          name: 'phone',
          prefix: pat.prefix,
          tokenHash: hashToken(pat.token),
          scope: 'read',
        );

        // Both credentials authenticate while the account is enabled.
        final (session0, _) = await send(
          'GET',
          '/api/v1/auth/me',
          headers: {'Cookie': '$sessionCookieName=$sessionToken'},
        );
        expect(session0.statusCode, HttpStatus.ok);
        final (pat0, _) = await send(
          'GET',
          '/api/v1/auth/me',
          headers: {'Authorization': 'Bearer ${pat.token}'},
        );
        expect(pat0.statusCode, HttpStatus.ok);

        // The operator flips the kill switch.
        db.setUserDisabled(id, disabled: true);

        // The session is gone — disabling deletes the user's sessions.
        final (session1, sessionBody) = await send(
          'GET',
          '/api/v1/auth/me',
          headers: {'Cookie': '$sessionCookieName=$sessionToken'},
        );
        expect(session1.statusCode, HttpStatus.unauthorized);
        expect(errorOf(sessionBody)['code'], 'unauthorized');

        // The load-bearing half: a disable does NOT revoke PATs, so only the
        // middleware resolving a disabled user to null stops this one. Without
        // it the kill switch would silently degrade to login-only while every
        // issued PAT stayed live.
        final (pat1, patBody) = await send(
          'GET',
          '/api/v1/auth/me',
          headers: {'Authorization': 'Bearer ${pat.token}'},
        );
        expect(
          pat1.statusCode,
          HttpStatus.unauthorized,
          reason: "a disabled user's PAT must resolve to unauthenticated",
        );
        expect(errorOf(patBody)['code'], 'unauthorized');
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

  group('login cannot be driven by a cross-site form', () {
    /// A raw POST with a chosen Content-Type — what an attacker's page can
    /// actually emit. `send` always sets application/json, so it cannot
    /// express this.
    Future<HttpClientResponse> postRaw(
      String path,
      String contentType,
      String body,
    ) async {
      final client = HttpClient();
      try {
        final request = await client.postUrl(baseUri.resolve(path));
        request.headers.set('content-type', contentType);
        request.write(body);
        return await request.close();
      } finally {
        client.close();
      }
    }

    test('text/plain shaped into valid JSON is refused', () async {
      // The real attack: <form enctype="text/plain"> can emit a body that
      // parses as JSON, and a form needs no CORS permission. Login is
      // unauthenticated, so requireCsrf has no session to key on and cannot
      // defend it — the Content-Type check is the only thing here.
      final response = await postRaw(
        '/api/v1/auth/login',
        'text/plain',
        jsonEncode({'username': 'admin', 'password': _adminPassword}),
      );
      await response.drain<void>();
      expect(
        response.statusCode,
        HttpStatus.unprocessableEntity,
        reason: 'a cross-site form must not be able to sign anyone in',
      );
    });

    test('a form encoding is refused BY THE GATE, not by the parser', () async {
      // A form-encoded body is not valid JSON anyway, so asserting only on
      // the status made this pass with the Content-Type check deleted — it
      // proved nothing. The MESSAGE is what distinguishes "refused because it
      // is not JSON-shaped" from "refused because a form may not do this".
      final response = await postRaw(
        '/api/v1/auth/login',
        'application/x-www-form-urlencoded',
        'username=admin&password=$_adminPassword',
      );
      final body = await utf8.decoder.bind(response).join();
      expect(response.statusCode, HttpStatus.unprocessableEntity);
      expect(
        errorOf(body)['message'],
        'Request body must be application/json.',
        reason:
            'must be turned away by the Content-Type gate; without it '
            'this still 422s on malformed JSON and tests nothing',
      );
    });

    test('application/json still works, charset and all', () async {
      final response = await postRaw(
        '/api/v1/auth/login',
        'application/json; charset=utf-8',
        jsonEncode({'username': 'admin', 'password': _adminPassword}),
      );
      await response.drain<void>();
      expect(
        response.statusCode,
        HttpStatus.ok,
        reason: 'the real client sends a charset; it must not be rejected',
      );
    });
  });

  group('remember me reaches the browser', () {
    // The server faithfully recorded a 90-day sliding session and then handed
    // out a cookie with no Max-Age — which a browser drops when the window
    // closes. The feature did nothing on web at all.
    test('remember: true sets Max-Age; plain login does not', () async {
      final (remembered, _) = await loginAs(
        'admin',
        _adminPassword,
        remember: true,
      );
      final rememberedCookie = remembered.headers.value('set-cookie');
      expect(
        rememberedCookie,
        contains('Max-Age=${rememberSessionLifetime.inSeconds}'),
        reason: 'without Max-Age the 90-day session dies with the browser',
      );

      final (plain, _) = await loginAs('admin', _adminPassword);
      expect(
        plain.headers.value('set-cookie'),
        isNot(contains('Max-Age')),
        reason: 'a non-remember session SHOULD die with the browser',
      );
    });

    test('the cookie keeps HttpOnly and SameSite alongside Max-Age', () async {
      final (response, _) = await loginAs(
        'admin',
        _adminPassword,
        remember: true,
      );
      final cookie = response.headers.value('set-cookie');
      expect(cookie, contains('HttpOnly'));
      expect(cookie, contains('SameSite=Lax'));
      expect(cookie, contains('Path=/'));
    });
  });

  group('admin password reset evicts every credential', () {
    // The reported hole: reset dropped SESSIONS but left PATs. A PAT is its
    // own credential, so must_change_password only FROZE it (403) — and the
    // moment the legitimate user completed the forced change it came back to
    // full service. The action an operator reaches for first on a suspected
    // compromise was the one that evicted everything except the attacker.
    test('a PAT does not survive the reset + forced-change cycle', () async {
      final victim = createMember('reset-victim');
      final pat = generatePat();
      db.createApiToken(
        userId: victim,
        name: 'attacker token',
        prefix: pat.prefix,
        tokenHash: hashToken(pat.token),
        scope: 'full',
      );
      Future<int> patStatus() async {
        final (response, _) = await send(
          'GET',
          '/api/v1/recipes',
          headers: {'Authorization': 'Bearer ${pat.token}'},
        );
        return response.statusCode;
      }

      expect(
        await patStatus(),
        HttpStatus.ok,
        reason: 'the PAT must work to begin with, or this proves nothing',
      );

      final adminToken = await sessionTokenFor('admin', _adminPassword);
      final (reset, resetBody) = await send(
        'POST',
        '/api/v1/users/$victim/reset_password',
        headers: {'Authorization': 'Bearer $adminToken', ..._csrfHeader},
      );
      expect(reset.statusCode, HttpStatus.ok, reason: resetBody);
      expect(
        jsonOf(resetBody)['revoked_tokens'],
        1,
        reason: 'the admin must be told what the reset evicted',
      );

      // The victim completes the forced change — this is the step that used
      // to REVIVE the attacker's token.
      final temp = jsonOf(resetBody)['temp_password'] as String;
      final victimToken = await sessionTokenFor('reset-victim', temp);
      final (changed, changedBody) = await send(
        'POST',
        '/api/v1/auth/change_password',
        headers: {'Authorization': 'Bearer $victimToken', ..._csrfHeader},
        jsonBody: {'new_password': 'victim-brand-new-password'},
      );
      expect(changed.statusCode, HttpStatus.ok, reason: changedBody);

      expect(
        await patStatus(),
        HttpStatus.unauthorized,
        reason: 'the PAT came back to life after the password change',
      );
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

  group('a password change evicts every credential', () {
    // The reported hole: change_password dropped the user's other SESSIONS
    // and never touched api_tokens. A session alone mints a full-scope PAT
    // (session logins are always `full`), PATs have no expiry, so a cookie
    // held for one minute bought permanent access that the victim's password
    // change did not take away.
    test('a PAT minted from the session dies with the password', () async {
      createMember('pat-minter');
      final session = await sessionTokenFor('pat-minter', _memberPassword);
      final (mint, mintBody) = await send(
        'POST',
        '/api/v1/tokens',
        headers: {'Cookie': '$sessionCookieName=$session', ..._csrfHeader},
        jsonBody: {'name': 'minted from a stolen cookie', 'scope': 'full'},
      );
      expect(mint.statusCode, HttpStatus.ok, reason: mintBody);
      final pat = jsonOf(mintBody)['token'] as String;

      Future<int> patStatus() async {
        final (response, _) = await send(
          'GET',
          '/api/v1/recipes',
          headers: {'Authorization': 'Bearer $pat'},
        );
        return response.statusCode;
      }

      expect(
        await patStatus(),
        HttpStatus.ok,
        reason: 'the PAT must work to begin with, or this proves nothing',
      );

      final (changed, changedBody) = await send(
        'POST',
        '/api/v1/auth/change_password',
        headers: {'Cookie': '$sessionCookieName=$session', ..._csrfHeader},
        jsonBody: {
          'current_password': _memberPassword,
          'new_password': 'the-minted-token-must-die',
        },
      );
      expect(changed.statusCode, HttpStatus.ok, reason: changedBody);
      expect(
        await patStatus(),
        HttpStatus.unauthorized,
        reason: 'the PAT outlived the password it was minted behind',
      );
      expect(
        jsonOf(changedBody)['revoked_tokens'],
        1,
        reason: 'the user must be told what their password change evicted',
      );
    });

    test('a rotation that fails changes nothing at all', () async {
      // The eviction and the rotation are ONE transaction:
      // `updatePasswordHash` revokes inside the transaction it already opens.
      // Ordering two separate statements was the older, weaker control — it
      // ruled out the compromise state (new password committed, every PAT
      // alive) but still left the caller a 500 that reads as "nothing
      // happened" over a database where half of it had. Atomic: the 500 is
      // now true.
      createMember('pat-partial');
      final session = await sessionTokenFor('pat-partial', _memberPassword);
      final auth = {'Cookie': '$sessionCookieName=$session', ..._csrfHeader};
      final (mint, mintBody) = await send(
        'POST',
        '/api/v1/tokens',
        headers: auth,
        jsonBody: {'name': 'survives a half-done rotation', 'scope': 'full'},
      );
      expect(mint.statusCode, HttpStatus.ok, reason: mintBody);
      final pat = jsonOf(mintBody)['token'] as String;

      // Hostile condition, synthesized because no input can produce it: a
      // trigger on the test's own database makes the password UPDATE — and
      // only that UPDATE — abort mid-request.
      final raw = sqlite3.open(config.dbPath);
      try {
        raw.execute(
          'CREATE TRIGGER halt_rotation AFTER UPDATE OF password_hash '
          "ON users BEGIN SELECT RAISE(ABORT, 'rotation failed'); END",
        );
        final (response, _) = await send(
          'POST',
          '/api/v1/auth/change_password',
          headers: auth,
          jsonBody: {
            'current_password': _memberPassword,
            'new_password': 'this-rotation-cannot-land',
          },
        );
        expect(
          response.statusCode,
          HttpStatus.internalServerError,
          reason: 'the trigger must actually break the rotation',
        );
      } finally {
        raw
          ..execute('DROP TRIGGER IF EXISTS halt_rotation')
          ..dispose();
      }

      // The forbidden outcome is "the new password works AND a PAT survived".
      // Nothing landed, so neither half of it did: the old password still
      // signs in and the PAT is exactly as it was.
      final (newPassword, newPasswordBody) = await loginAs(
        'pat-partial',
        'this-rotation-cannot-land',
      );
      expect(
        newPassword.statusCode,
        HttpStatus.unprocessableEntity,
        reason: 'the rotation must have rolled back',
      );
      expect(errorOf(newPasswordBody)['message'], _uniformLoginError);
      final (stillIn, stillInBody) = await loginAs(
        'pat-partial',
        _memberPassword,
      );
      expect(stillIn.statusCode, HttpStatus.ok, reason: stillInBody);
      final (patResponse, _) = await send(
        'GET',
        '/api/v1/recipes',
        headers: {'Authorization': 'Bearer $pat'},
      );
      expect(
        patResponse.statusCode,
        HttpStatus.ok,
        reason: 'the revocation must roll back with the rotation, not alone',
      );

      // And with nothing sabotaging it the same request does both — the pin
      // above must not be satisfiable by a handler that revokes nothing.
      final (changed, changedBody) = await send(
        'POST',
        '/api/v1/auth/change_password',
        headers: auth,
        jsonBody: {
          'current_password': _memberPassword,
          'new_password': 'this-rotation-does-land',
        },
      );
      expect(changed.statusCode, HttpStatus.ok, reason: changedBody);
      expect(jsonOf(changedBody)['revoked_tokens'], 1);
    });

    test(
      'a rotation whose EVICTION fails does not change the password',
      () async {
        // The other direction, and the one that is actually finding S4: the
        // test above aborts the PASSWORD write, which in the fixed order comes
        // after the revoke, so it only catches a revoke that committed too
        // early. It stays green even if the revocation is moved back OUT of the
        // transaction — the very split the fix removed — because then the abort
        // simply stops the revoke from running at all.
        //
        // Aborting the REVOKE instead is what distinguishes them. Atomic: the
        // password rolls back with it. Split: the password commits and every
        // PAT stays live, which is precisely the compromise state ("password
        // rotated, tokens still live") the eviction exists to prevent.
        createMember('evict-partial');
        final session = await sessionTokenFor('evict-partial', _memberPassword);
        final auth = {'Cookie': '$sessionCookieName=$session', ..._csrfHeader};
        final (mint, mintBody) = await send(
          'POST',
          '/api/v1/tokens',
          headers: auth,
          jsonBody: {'name': 'outlives a split rotation', 'scope': 'full'},
        );
        expect(mint.statusCode, HttpStatus.ok, reason: mintBody);

        // Synthesized hostile condition — no input can make the revoke fail.
        final raw = sqlite3.open(config.dbPath);
        try {
          raw.execute(
            'CREATE TRIGGER halt_eviction AFTER UPDATE OF revoked_at '
            "ON api_tokens BEGIN SELECT RAISE(ABORT, 'eviction failed'); END",
          );
          final (response, _) = await send(
            'POST',
            '/api/v1/auth/change_password',
            headers: auth,
            jsonBody: {
              'current_password': _memberPassword,
              'new_password': 'this-eviction-cannot-land',
            },
          );
          expect(
            response.statusCode,
            HttpStatus.internalServerError,
            reason: 'the trigger must actually break the eviction',
          );
        } finally {
          raw
            ..execute('DROP TRIGGER IF EXISTS halt_eviction')
            ..dispose();
        }

        final (newPassword, newPasswordBody) = await loginAs(
          'evict-partial',
          'this-eviction-cannot-land',
        );
        expect(
          newPassword.statusCode,
          HttpStatus.unprocessableEntity,
          reason:
              'the password must not have landed while the eviction failed — '
              'that is the compromise state, not a rolled-back request',
        );
        expect(errorOf(newPasswordBody)['message'], _uniformLoginError);
        final (stillIn, stillInBody) = await loginAs(
          'evict-partial',
          _memberPassword,
        );
        expect(stillIn.statusCode, HttpStatus.ok, reason: stillInBody);
      },
    );

    test('a failed recovery leaves no half-recovered admin', () async {
      // recoverAdmin used to make FOUR separate commits — revoke, rotate,
      // promote, re-enable — so a failure between them left the account part
      // way: the operator's new password live on an account still disabled,
      // or the tokens dead and nothing else done. `resetToEnabledAdmin` is
      // one transaction, and nothing pinned that before (the ordering at the
      // other two call sites was pinned; this one was not).
      final userId = createMember('recover-partial');
      final session = await sessionTokenFor('recover-partial', _memberPassword);
      final (mint, mintBody) = await send(
        'POST',
        '/api/v1/tokens',
        headers: {'Cookie': '$sessionCookieName=$session', ..._csrfHeader},
        jsonBody: {'name': 'outlives a failed recovery', 'scope': 'full'},
      );
      expect(mint.statusCode, HttpStatus.ok, reason: mintBody);
      final pat = jsonOf(mintBody)['token'] as String;
      db.setUserDisabled(userId, disabled: true);

      final code = issueRecoveryCode(db);
      final raw = sqlite3.open(config.dbPath);
      try {
        // Aborts the PROMOTION, the third of the four writes, so a version
        // that commits them separately gets the first two through: tokens
        // dead and the operator's new password live on an account still a
        // disabled member. One transaction has no such point.
        raw.execute(
          'CREATE TRIGGER halt_recovery AFTER UPDATE OF role '
          "ON users BEGIN SELECT RAISE(ABORT, 'promotion failed'); END",
        );
        await expectLater(
          recoverAdmin(db, runtime, {
            'recovery_code': code,
            'username': 'recover-partial',
            'new_password': 'recovered-the-hard-way',
          }, clientIp: '10.0.0.9'),
          throwsA(isA<SqliteException>()),
        );
      } finally {
        raw
          ..execute('DROP TRIGGER IF EXISTS halt_recovery')
          ..dispose();
      }

      final stored = db.userById(userId)!;
      expect(
        [stored.role, stored.disabled],
        ['member', true],
        reason: 'the promotion and the re-enable must have rolled back',
      );
      expect(
        stored.passwordHash,
        memberHash,
        reason: 'a recovery that did not complete must not rotate anything',
      );
      expect(
        db.apiTokensForUser(userId).single.revokedAt,
        isNull,
        reason: 'the revocation must roll back with the rest, not alone',
      );
      // The recovery code is single-use and was consumed before the account
      // was touched, so a retry needs a fresh one — and with nothing
      // sabotaging it, all four writes land together.
      final grant = await recoverAdmin(db, runtime, {
        'recovery_code': issueRecoveryCode(db),
        'username': 'recover-partial',
        'new_password': 'recovered-the-hard-way',
      }, clientIp: '10.0.0.9');
      expect(grant.body['user'], containsPair('role', 'admin'));
      final recovered = db.userById(userId)!;
      expect([recovered.role, recovered.disabled], ['admin', false]);
      final (deadPat, _) = await send(
        'GET',
        '/api/v1/recipes',
        headers: {'Authorization': 'Bearer $pat'},
      );
      expect(
        deadPat.statusCode,
        HttpStatus.unauthorized,
        reason: 'recovery must evict every API token it found',
      );
    });
  });

  group('auth events reach the log', () {
    /// Collects `auth` records emitted while [action] runs.
    ///
    /// Deliberately does NOT open the `auth` logger: this file boots the root
    /// logger at `LOG_LEVEL=ERROR`, the strictest supported setting, so every
    /// INFO expectation below only holds because [auditLog] pins its own
    /// level. Forcing the level here (as this helper used to) would have hidden
    /// exactly the defect that pin exists to stop.
    Future<List<LogRecord>> capture(Future<void> Function() action) async {
      final records = <LogRecord>[];
      final subscription = auditLog.onRecord.listen(records.add);
      try {
        await action();
        await Future<void>.delayed(Duration.zero);
      } finally {
        await subscription.cancel();
      }
      return records;
    }

    /// Fails if any [messages] entry carries something a log must never hold.
    void expectNoSecrets(List<String> messages, List<String> secrets) {
      for (final message in messages) {
        for (final secret in secrets) {
          expect(
            message,
            isNot(contains(secret)),
            reason: 'a secret reached an auth log line',
          );
        }
        expect(
          redactLogMessage(message),
          message,
          reason: 'a redactable secret reached an auth log line',
        );
      }
    }

    // These call `login` directly with a PRIVATE AuthRuntime: the shared
    // limiter in this file is process-wide sequential state, and a test that
    // spends its budget would silently change what a later test measures.
    Future<SessionGrant> loginWith(
      AuthRuntime auth,
      String username,
      String password,
    ) => login(
      db,
      auth,
      {'username': username, 'password': password},
      // Each of these tests builds its own AuthRuntime, so the aggregate
      // bucket is fresh and one test's attempts cannot lock another's.
      clientIp: '198.51.100.4',
    );

    test('failure, success and a disabled account each name it', () async {
      createMember('log-hit');
      createMember('log-off', disabled: true);
      final auth = AuthRuntime(hasher: runtime.hasher);
      late SessionGrant grant;
      final records = await capture(() async {
        await expectLater(
          loginWith(auth, 'log-hit', 'not-the-password'),
          throwsA(isA<ValidationException>()),
        );
        grant = await loginWith(auth, 'log-hit', _memberPassword);
        await expectLater(
          loginWith(auth, 'log-off', _memberPassword),
          throwsA(isA<ValidationException>()),
        );
      });

      final messages = [for (final record in records) record.message];
      // The access line says only "POST /auth/login -> 422": no actor, so it
      // cannot say which account was sprayed. These must.
      expect(
        messages,
        contains(
          allOf(contains('Login failed: log-hit'), contains('198.51.100.4')),
        ),
      );
      expect(messages, contains(contains('Login: log-hit')));
      expect(messages, contains(contains('Login refused: log-off')));
      expect(
        records.where((record) => record.level >= Level.WARNING).length,
        2,
        reason: 'the two rejections are warnings; the sign-in is not',
      );
      expectNoSecrets(messages, [
        _memberPassword,
        grant.token,
        memberHash,
      ]);
    });

    test('a lockout says which account it locked', () async {
      createMember('log-lock');
      // failureThreshold 1 so one wrong password locks the key: this proves
      // the lockout branch logs without spending 5 real Argon2id hashes.
      final auth = AuthRuntime(
        hasher: runtime.hasher,
        rateLimiter: LoginRateLimiter(failureThreshold: 1),
      );
      final records = await capture(() async {
        await expectLater(
          loginWith(auth, 'log-lock', 'not-the-password'),
          throwsA(isA<ValidationException>()),
        );
        await expectLater(
          loginWith(auth, 'log-lock', _memberPassword),
          throwsA(isA<LockedException>()),
        );
      });
      final messages = [for (final record in records) record.message];
      expect(messages, contains(contains('Login locked out: log-lock')));
      expectNoSecrets(messages, [_memberPassword, memberHash]);
    });

    test('an attempted username that cannot be one is not written '
        'through', () async {
      final auth = AuthRuntime(hasher: runtime.hasher);
      // `login` does not validate this field, so it is arbitrary attacker
      // text: writing it verbatim would let a peer pump the size-bounded log
      // store (evicting history), or smuggle a `rid=` the viewer would adopt
      // as the record's correlation id.
      for (final junk in ['A' * 4096, 'rid=00000000000000ff']) {
        final records = await capture(() async {
          await expectLater(
            loginWith(auth, junk, 'not-the-password'),
            throwsA(isA<ValidationException>()),
          );
        });
        final message = records.single.message;
        expect(message, contains('<invalid>'));
        expect(message, isNot(contains(junk)));
        expect(message.length, lessThan(120));
      }
    });

    test('a password change and a logout are recorded', () async {
      createMember('log-rotate');
      final session = await sessionTokenFor('log-rotate', _memberPassword);
      final auth = {'Cookie': '$sessionCookieName=$session', ..._csrfHeader};
      const newPassword = 'a-brand-new-password-9';
      final records = await capture(() async {
        final (bad, _) = await send(
          'POST',
          '/api/v1/auth/change_password',
          headers: auth,
          jsonBody: {
            'current_password': 'not-the-password',
            'new_password': newPassword,
          },
        );
        expect(bad.statusCode, HttpStatus.unprocessableEntity);
        final (ok, okBody) = await send(
          'POST',
          '/api/v1/auth/change_password',
          headers: auth,
          jsonBody: {
            'current_password': _memberPassword,
            'new_password': newPassword,
          },
        );
        expect(ok.statusCode, HttpStatus.ok, reason: okBody);
        final (out, _) = await send(
          'POST',
          '/api/v1/auth/logout',
          headers: auth,
        );
        expect(out.statusCode, HttpStatus.ok);
      });

      final messages = [for (final record in records) record.message];
      expect(
        messages,
        contains(contains('Password change rejected: log-rotate')),
      );
      expect(messages, contains(contains('Password changed: log-rotate')));
      expect(messages, contains(contains('Logout: log-rotate')));
      expectNoSecrets(messages, [
        _memberPassword,
        newPassword,
        session,
        memberHash,
      ]);
    });

    test('the trail survives the strictest supported LOG_LEVEL', () async {
      // `LOG_LEVEL=ERROR` and `WARN` are both supported operator settings
      // (ServerConfig._parseLogLevel) and both feed Logger.root.level. This
      // file boots at ERROR — the strictest — so if the audit channel
      // inherited the root level, every INFO record below would be discarded
      // and the whole account trail would vanish on a routine config choice.
      expect(
        Logger.root.level,
        Level.SEVERE,
        reason: 'this test is only meaningful with the root level raised',
      );
      createMember('log-level');
      // Subscribed at the ROOT, not at `auth`: that is the stream the stdout
      // printer and the admin log store both attach to, so this is what an
      // operator would actually be able to read back.
      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      try {
        await sessionTokenFor('log-level', _memberPassword);
        await Future<void>.delayed(Duration.zero);
      } finally {
        await subscription.cancel();
      }
      expect(
        [
          for (final record in records)
            if (record.level == Level.INFO) record.message,
        ],
        contains(contains('Login: log-level')),
      );
    });

    test('a backup download and delete name the admin who took it', () async {
      // The archive is every password/session/token hash and every private
      // note. `GET /api/v1/backups/x -> 200` names nobody, so before this the
      // highest-value exfiltration in the system left no attributable trace,
      // and DELETE let an intruder erase the evidence just as quietly.
      final token = await sessionTokenFor('admin', _adminPassword);
      final headers = {'Cookie': '$sessionCookieName=$token', ..._csrfHeader};
      // A real archive from the real service, not a planted file.
      final name = createBackup(db: db, config: config, trigger: 'manual');
      final records = await capture(() async {
        // Not `send`: the archive is gzip, so the body cannot be utf8-decoded.
        final client = HttpClient();
        try {
          final request = await client.openUrl(
            'GET',
            baseUri.resolve('/api/v1/backups/$name'),
          );
          headers.forEach(request.headers.set);
          final response = await request.close();
          final bytes = await response.fold<int>(
            0,
            (total, chunk) => total + chunk.length,
          );
          expect(response.statusCode, HttpStatus.ok);
          expect(bytes, greaterThan(0), reason: 'the archive really streamed');
        } finally {
          client.close();
        }
        final (gone, goneBody) = await send(
          'DELETE',
          '/api/v1/backups/$name',
          headers: headers,
        );
        expect(gone.statusCode, HttpStatus.noContent, reason: goneBody);
      });
      final messages = [for (final record in records) record.message];
      expect(
        messages,
        contains(
          allOf(contains('Backup downloaded: $name'), contains('admin')),
        ),
      );
      expect(
        messages,
        contains(allOf(contains('Backup deleted: $name'), contains('admin'))),
      );
      expect(
        records.every((record) => record.level >= Level.WARNING),
        isTrue,
        reason: 'both belong in the viewer default filter, like a reset',
      );
      expectNoSecrets(messages, [token, memberHash]);
    });

    test('setting and clearing the FDC key names the admin', () async {
      final token = await sessionTokenFor('admin', _adminPassword);
      final headers = {'Cookie': '$sessionCookieName=$token', ..._csrfHeader};
      // Synthesized: a deployment API key cannot come from the recipe corpus.
      const key = 'not-a-real-fdc-key-abcdefgh';
      final records = await capture(() async {
        for (final value in [key, '']) {
          final (response, body) = await send(
            'PUT',
            '/api/v1/settings/fdc_key',
            headers: headers,
            jsonBody: {'api_key': value},
          );
          expect(response.statusCode, HttpStatus.ok, reason: body);
        }
      });
      final messages = [for (final record in records) record.message];
      expect(
        messages,
        contains(allOf(contains('FDC API key set'), contains('admin'))),
      );
      expect(messages, contains(contains('FDC API key cleared')));
      // Not even the masked tail the GET hands back reaches the record.
      expectNoSecrets(messages, [key, key.substring(key.length - 4)]);
    });
  });
}
