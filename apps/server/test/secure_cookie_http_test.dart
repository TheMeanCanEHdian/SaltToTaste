import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart' hide requestLogger;
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/middleware/request_logger.dart';
import 'package:test/test.dart';

import '../routes/api/v1/auth/login.dart' as login_route;

/// Whether a session cookie ever actually gains `Secure` — the consequence
/// that made a broken proxy check a VULNERABILITY rather than a rate-limit
/// bug, and which nothing in the suite asserted.
///
/// The gap this closes is precise. The address matching was mutation-proofed;
/// the security it exists to deliver was not. `isSecureRequest` could be
/// replaced with `=> false` and all 320 tests passed, because the only
/// assertion on the attribute anywhere in the repo was a NEGATIVE one
/// (auth_flow_test: no proxy, so no `Secure`) — which a permanently-broken
/// implementation satisfies perfectly. The fix was verified by hand instead,
/// which protects exactly one commit and nothing after it.
///
/// These drive the REAL login route over a REAL socket, so the peer address is
/// one the OS assigns rather than one a test invents — the mistake that let the
/// original bug ship green.
// Synthesized credentials: auth inputs cannot come from the recipe corpus.
const _password = 'correct-horse-battery';
const _csrfHeader = {'X-Requested-With': 'SaltToTaste'};

void main() {
  late Directory tempDir;
  late SaltDatabase db;
  late AuthRuntime runtime;
  late String passwordHash;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('salt_secure_cookie_test_');
    runtime = AuthRuntime(setupCode: 'ABCD-EFGH');
    passwordHash = await runtime.hasher.hash(_password);
  });

  tearDownAll(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  /// Serves the real login route under [environment], returns the `set-cookie`
  /// from a successful login carrying [headers].
  Future<String> loginSetCookie({
    required Map<String, String> environment,
    Map<String, String> headers = const {},
  }) async {
    final dir = Directory.systemTemp.createTempSync('salt_cookie_case_');
    final config = ServerConfig.fromEnvironment(
      environment: {'DATA_DIR': dir.path, 'LOG_LEVEL': 'ERROR', ...environment},
    );
    configureLogging(config);
    db = SaltDatabase.open(config.dbPath)
      ..createUser(
        username: 'proxied',
        passwordHash: passwordHash,
        role: 'admin',
      );

    final pipeline = login_route.onRequest
        .use(authProvider())
        .use(provider<AuthRuntime>((_) => runtime))
        .use(provider<SaltDatabase>((_) => db))
        .use(provider<ServerConfig>((_) => config))
        .use(errorHandler())
        .use(requestLogger())
        .use(requestIdProvider());
    final server = await serve(pipeline, InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));

    final client = HttpClient();
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/api/v1/auth/login'),
    );
    request.headers.contentType = ContentType.json;
    for (final entry in {..._csrfHeader, ...headers}.entries) {
      request.headers.set(entry.key, entry.value);
    }
    request.write(
      jsonEncode({'username': 'proxied', 'password': _password}),
    );
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    client.close();
    expect(
      response.statusCode,
      HttpStatus.ok,
      reason: 'login must succeed or the cookie assertion is vacuous: $body',
    );
    final cookie = response.headers['set-cookie']?.first;
    expect(cookie, isNotNull, reason: 'no session cookie was issued');
    return cookie!;
  }

  test('behind a TRUSTED proxy, an https request is Secure', () async {
    // The production path, and the one that was dead: the peer is the
    // loopback address the OS actually reports, matched by a CIDR an operator
    // would really write.
    final cookie = await loginSetCookie(
      environment: {'TRUST_PROXY': 'true', 'TRUSTED_PROXIES': '127.0.0.0/8'},
      headers: {'X-Forwarded-Proto': 'https'},
    );
    expect(
      cookie,
      contains('Secure'),
      reason:
          'a session cookie behind a TLS proxy MUST be Secure — this is the '
          'assertion whose absence let isSecureRequest be broken twice with a '
          'green suite',
    );
  });

  test('from an UNTRUSTED peer, X-Forwarded-Proto is ignored', () async {
    // TRUST_PROXY is on, but the peer (127.0.0.1) is not in TRUSTED_PROXIES,
    // so the forwarded header means nothing. Delete the peer check in
    // trustsForwardedHeaders — the `TRUST_PROXY=true means believe whoever
    // connected` bug this surface was fixed for — and this goes red.
    final cookie = await loginSetCookie(
      environment: {'TRUST_PROXY': 'true', 'TRUSTED_PROXIES': '10.99.99.99'},
      headers: {'X-Forwarded-Proto': 'https'},
    );
    expect(
      cookie,
      isNot(contains('Secure')),
      reason:
          'a peer that is not our proxy must not be able to describe its own '
          'connection',
    );
  });

  test('SECURE_COOKIES forces Secure with no proxy at all', () async {
    // The direct-TLS deployment. Zero references in test/ before this.
    final cookie = await loginSetCookie(
      environment: {'SECURE_COOKIES': 'true'},
    );
    expect(cookie, contains('Secure'));
  });

  test('plain http with no proxy gets no Secure', () async {
    // The negative that must stay true: Secure on a cleartext cookie would
    // make the session unusable rather than insecure, so this is the guard
    // that keeps local development working.
    final cookie = await loginSetCookie(environment: {});
    expect(cookie, isNot(contains('Secure')));
  });
}
