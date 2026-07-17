import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/auth/recovery.dart';
import 'package:salt_server/src/auth/setup_code.dart';
import 'package:salt_server/src/auth/tokens.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../routes/api/v1/auth/recover.dart' as recover_route;

// Synthesized credentials: auth inputs cannot come from the recipe corpus.
const _oldPassword = 'the-forgotten-one';
const _newPassword = 'recovered-admin-123';

/// A well-formed code that is definitely not [code] — generated codes are
/// random, so a fixed literal could (once in a billion runs) collide.
String _otherThan(String code) =>
    code == 'AAAA-AAAA' ? 'BBBB-BBBB' : 'AAAA-AAAA';

/// Runs [action], reporting only whether it succeeded — for races, where
/// which of two futures throws is the point.
Future<bool> _attempt(Future<Object?> Function() action) async {
  try {
    await action();
    return true;
  } on AppException {
    return false;
  }
}

void main() {
  late Directory tempDir;
  late ServerConfig config;
  late SaltDatabase db;
  late AuthRuntime runtime;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('salt_recovery_test_');
    config = ServerConfig.fromEnvironment(
      environment: {'DATA_DIR': tempDir.path, 'LOG_LEVEL': 'ERROR'},
    );
    configureLogging(config);
    db = SaltDatabase.open(config.dbPath);
    runtime = AuthRuntime();
  });

  tearDown(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  Future<int> createAdmin(
    String username, {
    bool disabled = false,
    String role = 'admin',
  }) async {
    final id = db.createUser(
      username: username,
      passwordHash: await runtime.hasher.hash(_oldPassword),
      role: role,
    );
    if (disabled) {
      db.setUserDisabled(id, disabled: true);
    }
    return id;
  }

  Future<SessionGrant> recover(
    String code,
    String username, {
    String password = _newPassword,
    String clientIp = '10.0.0.9',
  }) => recoverAdmin(db, runtime, {
    'recovery_code': code,
    'username': username,
    'new_password': password,
  }, clientIp: clientIp);

  group('issueRecoveryCode / checkRecoveryCode', () {
    test('round-trips: the issued code verifies', () {
      final code = issueRecoveryCode(db);
      expect(checkRecoveryCode(db, code), RecoveryCodeStatus.valid);
    });

    test('accepts the code however the operator retypes it', () {
      final code = issueRecoveryCode(db);
      expect(
        checkRecoveryCode(db, code.toLowerCase()),
        RecoveryCodeStatus.valid,
      );
      expect(
        checkRecoveryCode(db, ' ${code.replaceAll('-', ' ')} '),
        RecoveryCodeStatus.valid,
      );
    });

    test('a wrong code is invalid, not unavailable', () {
      final code = issueRecoveryCode(db);
      expect(
        checkRecoveryCode(db, _otherThan(code)),
        RecoveryCodeStatus.invalid,
      );
      expect(checkRecoveryCode(db, code), RecoveryCodeStatus.valid);
    });

    test('re-issuing replaces the previous code', () {
      final first = issueRecoveryCode(db);
      final second = issueRecoveryCode(db);
      expect(checkRecoveryCode(db, first), RecoveryCodeStatus.invalid);
      expect(checkRecoveryCode(db, second), RecoveryCodeStatus.valid);
    });

    test('nothing issued reads as unavailable', () {
      expect(
        checkRecoveryCode(db, 'AAAA-AAAA'),
        RecoveryCodeStatus.unavailable,
      );
    });

    test('an expired code is unavailable and its row is cleaned up', () {
      final code = issueRecoveryCode(
        db,
        now: DateTime.now().toUtc().subtract(
          recoveryCodeLifetime + const Duration(minutes: 1),
        ),
      );
      expect(checkRecoveryCode(db, code), RecoveryCodeStatus.unavailable);
      expect(db.getSetting(recoveryCodeSetting), isNull);
    });

    test('expiry is enforced on the clock, not on process lifetime', () {
      final code = issueRecoveryCode(db);
      final justBefore = DateTime.now().toUtc().add(
        recoveryCodeLifetime - const Duration(seconds: 1),
      );
      final justAfter = DateTime.now().toUtc().add(
        recoveryCodeLifetime + const Duration(seconds: 1),
      );
      expect(
        checkRecoveryCode(db, code, now: justBefore),
        RecoveryCodeStatus.valid,
      );
      expect(
        checkRecoveryCode(db, code, now: justAfter),
        RecoveryCodeStatus.unavailable,
      );
    });

    test('a garbled row is treated as absent', () {
      db.setSetting(recoveryCodeSetting, 'not-a-record');
      expect(
        checkRecoveryCode(db, 'AAAA-AAAA'),
        RecoveryCodeStatus.unavailable,
      );
      expect(db.getSetting(recoveryCodeSetting), isNull);
    });

    test('the settings row never contains the plaintext code', () {
      final code = issueRecoveryCode(db);
      final stored = db.getSetting(recoveryCodeSetting)!;
      expect(stored, isNot(contains(code)));
      expect(stored, isNot(contains(code.replaceAll('-', ''))));
      expect(stored, isNot(contains(code.toLowerCase())));
      // Digest + ISO expiry, and the digest is not of some other string.
      expect(stored, matches(RegExp(r'^[0-9a-f]{64}:.+$')));
    });

    test('no settings row anywhere holds the plaintext code', () {
      final code = issueRecoveryCode(db);
      // Every key, not just the one we expect to hold it: a leak into some
      // other row is exactly what checking the known key would miss. Read
      // through a second connection because SaltDatabase exposes no dump.
      final raw = sqlite3.open(config.dbPath, mode: OpenMode.readOnly);
      addTearDown(raw.dispose);
      final rows = raw.select('SELECT key, value FROM settings');
      expect(rows, isNotEmpty, reason: 'the code should have been stored');
      final normalized = normalizeSetupCode(code);
      for (final row in rows) {
        final value = '${row['value']}';
        expect(
          normalizeSetupCode(value),
          isNot(contains(normalized)),
          reason: 'settings[${row['key']}] leaks the plaintext code',
        );
      }
    });

    test('clearRecoveryCode consumes it', () {
      final code = issueRecoveryCode(db);
      clearRecoveryCode(db);
      expect(checkRecoveryCode(db, code), RecoveryCodeStatus.unavailable);
    });
  });

  group('recoverAdmin', () {
    test('re-enables and resets the only admin when it is disabled', () async {
      final id = await createAdmin('lockedout', disabled: true);
      final code = issueRecoveryCode(db);

      final grant = await recover(code, 'lockedout');

      expect(grant.body['user'], {
        'id': id,
        'username': 'lockedout',
        'role': 'admin',
      });
      final user = db.userById(id)!;
      expect(user.disabled, isFalse);
      expect(user.role, 'admin');
      expect(user.mustChangePassword, isFalse);
      expect(
        await runtime.hasher.verify(_newPassword, user.passwordHash),
        isTrue,
      );
      expect(
        await runtime.hasher.verify(_oldPassword, user.passwordHash),
        isFalse,
      );
      // The returned token is a live session for the recovered account.
      expect(db.sessionByHash(hashToken(grant.token))?.userId, id);
    });

    test('promotes a demoted account back to admin', () async {
      final id = await createAdmin('demoted', role: 'member');
      await recover(issueRecoveryCode(db), 'demoted');
      expect(db.userById(id)!.role, 'admin');
    });

    test('creates the admin when no user by that name exists', () async {
      expect(db.userCount(), 0);
      final grant = await recover(issueRecoveryCode(db), 'brandnew');

      final user = db.userByUsername('brandnew')!;
      expect(user.role, 'admin');
      expect(user.disabled, isFalse);
      expect(grant.body['user'], {
        'id': user.id,
        'username': 'brandnew',
        'role': 'admin',
      });
      expect(
        await runtime.hasher.verify(_newPassword, user.passwordHash),
        isTrue,
      );
    });

    test('a code is single-use: the second attempt is refused', () async {
      await createAdmin('lockedout', disabled: true);
      final code = issueRecoveryCode(db);

      await recover(code, 'lockedout');
      expect(db.getSetting(recoveryCodeSetting), isNull);
      await expectLater(
        recover(code, 'lockedout', password: 'second-attempt-123'),
        throwsA(isA<ForbiddenException>()),
      );
      // The refused attempt changed nothing.
      final user = db.userByUsername('lockedout')!;
      expect(
        await runtime.hasher.verify(_newPassword, user.passwordHash),
        isTrue,
      );
    });

    test("recovery revokes the account's API tokens, not just sessions",
        () async {
      final id = await createAdmin('lockedout', disabled: true);
      // A PAT outlives a password reset, so whoever caused the lockout would
      // still hold a working credential unless recovery revokes it too.
      final live = db.createApiToken(
        userId: id,
        name: 'laptop',
        prefix: 'salt_aaaa',
        tokenHash: 'hash-live',
        scope: 'full',
      );
      final alsoLive = db.createApiToken(
        userId: id,
        name: 'script',
        prefix: 'salt_bbbb',
        tokenHash: 'hash-also-live',
        scope: 'read',
      );
      // A bystander's token must survive: recovery targets one account.
      final otherId = await createAdmin('bystander', role: 'member');
      final bystander = db.createApiToken(
        userId: otherId,
        name: 'theirs',
        prefix: 'salt_cccc',
        tokenHash: 'hash-bystander',
        scope: 'read',
      );

      await recover(issueRecoveryCode(db), 'lockedout');

      for (final tokenId in [live, alsoLive]) {
        final row = db
            .apiTokensForUser(id)
            .firstWhere((token) => token.id == tokenId);
        expect(
          row.revokedAt,
          isNotNull,
          reason: 'token ${row.name} still works after recovery',
        );
      }
      final untouched = db
          .apiTokensForUser(otherId)
          .firstWhere((token) => token.id == bystander);
      expect(
        untouched.revokedAt,
        isNull,
        reason: "recovery must not revoke another account's tokens",
      );
    });

    test('repeated wrong codes from one IP lock the endpoint', () async {
      await createAdmin('lockedout', disabled: true);
      final code = issueRecoveryCode(db);
      final wrong = _otherThan(code);

      // The code check is only a SHA-256, so without a limit this endpoint
      // would be guessable far faster than the login form.
      for (var attempt = 0; attempt < 5; attempt += 1) {
        await expectLater(
          recover(wrong, 'lockedout', clientIp: '203.0.113.7'),
          throwsA(isA<ValidationException>()),
          reason: 'attempt $attempt should be a plain rejection',
        );
      }
      // Now locked: even the RIGHT code is refused, so a guesser who lands on
      // it after the limit trips still gets nothing.
      await expectLater(
        recover(code, 'lockedout', clientIp: '203.0.113.7'),
        throwsA(isA<LockedException>()),
      );
      // And the lock is per-IP: an unrelated host is unaffected.
      final grant = await recover(code, 'lockedout', clientIp: '198.51.100.4');
      expect(grant.body['user'], isA<Map<String, Object?>>());
    });


    test('failed logins must not disable the escape hatch', () async {
      // THE BUG: recoverAdmin gated on the SAME per-IP bucket login records
      // failures into. The condition that makes an operator need /recover —
      // repeated failed logins — was the condition that refused a VALID code.
      // It bit hardest on the default deployment: TRUST_PROXY is unset, so
      // clientIp is the reverse proxy's address for every request and one
      // household member's typos would lock recovery for everyone.
      await createAdmin('lockedout', disabled: true);
      const ip = '203.0.113.44';

      // Spray failed logins from this IP across DISTINCT usernames, so login's
      // per-account key never trips and only the aggregate IP bucket fills.
      for (var i = 0; i < 25; i += 1) {
        await expectLater(
          login(db, runtime, {
            'username': 'ghost$i',
            'password': 'wrong-password-here',
          }, clientIp: ip),
          throwsA(isA<AppException>()),
        );
      }

      // A freshly issued, VALID code from that same IP must still work.
      final grant = await recover(issueRecoveryCode(db), 'lockedout',
          clientIp: ip);
      expect(
        (grant.body['user']! as Map<String, Object?>)['username'],
        'lockedout',
        reason: 'a valid recovery code must survive a drained login bucket',
      );
    });

    test('a recovery attempt must not lock out normal logins', () async {
      // The mirror hazard: a code-guesser must not be able to spend the
      // household's login budget and lock everyone out of signing in.
      final id = await createAdmin('normal');
      const ip = '198.51.100.77';
      final code = issueRecoveryCode(db);
      final wrong = _otherThan(code);

      for (var i = 0; i < 6; i += 1) {
        await expectLater(
          recover(wrong, 'normal', clientIp: ip),
          throwsA(isA<AppException>()),
        );
      }

      // Login from the same IP is unaffected.
      final grant = await login(db, runtime, {
        'username': 'normal',
        'password': _oldPassword,
      }, clientIp: ip);
      expect((grant.body['user']! as Map<String, Object?>)['id'], id);
    });
    test('two concurrent redemptions of one code: exactly one wins', () async {
      final code = issueRecoveryCode(db);
      // Both requests get past the first check while suspended in the ~100ms
      // hash; only the post-await re-check keeps them from both succeeding.
      final outcomes = await Future.wait([
        _attempt(() => recover(code, 'racer')),
        _attempt(() => recover(code, 'racer')),
      ]);
      expect(outcomes.where((ok) => ok).length, 1);
      expect(db.userCount(), 1);
      expect(db.getSetting(recoveryCodeSetting), isNull);
    });

    test('a wrong code is a 422, a missing one a 403', () async {
      await expectLater(
        recover('AAAA-AAAA', 'anyone'),
        throwsA(isA<ForbiddenException>()),
      );
      final code = issueRecoveryCode(db);
      final wrong = code == 'AAAA-AAAA' ? 'BBBB-BBBB' : 'AAAA-AAAA';
      await expectLater(
        recover(wrong, 'anyone'),
        throwsA(isA<ValidationException>()),
      );
      // A rejected attempt does not burn the code.
      expect(checkRecoveryCode(db, code), RecoveryCodeStatus.valid);
      expect(db.userCount(), 0);
    });

    test('an expired code is refused with a 403', () async {
      final code = issueRecoveryCode(
        db,
        now: DateTime.now().toUtc().subtract(
          recoveryCodeLifetime + const Duration(minutes: 1),
        ),
      );
      await expectLater(
        recover(code, 'anyone'),
        throwsA(isA<ForbiddenException>()),
      );
      expect(db.userCount(), 0);
    });

    test('validates username and password like setup does', () async {
      final code = issueRecoveryCode(db);
      await expectLater(
        recover(code, 'no'),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        recover(code, 'admin', password: 'short'),
        throwsA(isA<ValidationException>()),
      );
      // Neither rejection consumed the code or created anything.
      expect(checkRecoveryCode(db, code), RecoveryCodeStatus.valid);
      expect(db.userCount(), 0);
    });

    test('the username is normalized, the stored spelling is echoed', () async {
      final code = issueRecoveryCode(db);
      final grant = await recover(code, '  MixedCase  ');
      expect(grant.body['user'], containsPair('username', 'mixedcase'));
      expect(db.userByUsername('mixedcase'), isNotNull);
    });
  });

  group('POST /api/v1/auth/recover', () {
    late HttpServer server;
    late Uri baseUri;

    setUp(() async {
      // The route wired like routes/_middleware.dart, with test singletons.
      final pipeline = recover_route.onRequest
          .use(authProvider())
          .use(provider<AuthRuntime>((_) => runtime))
          .use(provider<SaltDatabase>((_) => db))
          .use(provider<ServerConfig>((_) => config))
          .use(errorHandler())
          .use(requestIdProvider());
      server = await serve(pipeline, InternetAddress.loopbackIPv4, 0);
      baseUri = Uri.parse('http://127.0.0.1:${server.port}');
    });

    tearDown(() => server.close(force: true));

    Future<(HttpClientResponse, String)> post(Object body) async {
      final client = HttpClient();
      try {
        final request = await client.postUrl(baseUri.resolve('/'));
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
        final response = await request.close();
        return (response, await utf8.decoder.bind(response).join());
      } finally {
        client.close();
      }
    }

    test('unauthenticated: signs in and sets the session cookie', () async {
      await createAdmin('lockedout', disabled: true);
      final code = issueRecoveryCode(db);

      // No Authorization header, no cookie: the whole point of the endpoint.
      final (response, body) = await post({
        'recovery_code': code,
        'username': 'lockedout',
        'new_password': _newPassword,
      });

      expect(response.statusCode, HttpStatus.ok, reason: body);
      final token = (jsonDecode(body) as Map)['token'] as String;
      expect(
        response.headers.value('set-cookie'),
        allOf(contains('$sessionCookieName=$token'), contains('HttpOnly')),
      );
      expect(db.userByUsername('lockedout')!.disabled, isFalse);
    });

    test('a spent code -> 403 envelope', () async {
      final code = issueRecoveryCode(db);
      clearRecoveryCode(db);
      final (response, body) = await post({
        'recovery_code': code,
        'username': 'lockedout',
        'new_password': _newPassword,
      });
      expect(response.statusCode, HttpStatus.forbidden, reason: body);
      expect(
        ((jsonDecode(body) as Map)['error'] as Map)['code'],
        'forbidden',
      );
    });
  });
}
