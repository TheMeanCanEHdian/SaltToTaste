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

/// What a forwarded header actually BUYS a peer — the two halves of the proxy
/// trust boundary, driven over a real socket bound the way production binds.
///
/// Both halves matter and only one was ever pinned. `trustsForwardedHeaders`
/// decides WHO may set a forwarded header; `clientIp` decides WHICH value is
/// believed once a real proxy is configured. The peer check without the
/// rightmost-value rule is not a guard: the attacker is behind the proxy too,
/// so their `X-Forwarded-For: 1.2.3.4` simply arrives leftmost of the real IP
/// the proxy appends, and keying on it hands them a fresh rate-limit bucket
/// per request.
///
/// THE BIND IS PART OF THE TEST. Production binds `InternetAddress.anyIPv6`
/// (dart_frog's generated entrypoint, which the Dockerfile compiles and runs),
/// and that listener is dual-stack, so an IPv4 peer arrives as
/// `::ffff:127.0.0.1`. An earlier version of this file bound `loopbackIPv4`
/// and therefore saw a plain `127.0.0.1` — a peer production never sees — so
/// the original `::ffff:` bug passed it 4/4 green while the deployment was
/// dead. A test that invents its own peer proves nothing about the one the
/// server meets.
// Synthesized credentials: auth inputs cannot come from the recipe corpus.
const _password = 'correct-horse-battery';
const _csrfHeader = {'X-Requested-With': 'SaltToTaste'};

void main() {
  late AuthRuntime runtime;
  late String passwordHash;

  setUpAll(() async {
    runtime = AuthRuntime(setupCode: 'ABCD-EFGH');
    passwordHash = await runtime.hasher.hash(_password);
  });

  /// Serves [handler] under [environment] on a production-shaped dual-stack
  /// bind, and returns its base URI.
  Future<Uri> serveUnder(
    Handler handler,
    Map<String, String> environment,
  ) async {
    final dir = Directory.systemTemp.createTempSync('salt_cookie_case_');
    final config = ServerConfig.fromEnvironment(
      environment: {'DATA_DIR': dir.path, 'LOG_LEVEL': 'ERROR', ...environment},
    );
    configureLogging(config);
    final db = SaltDatabase.open(config.dbPath)
      ..createUser(
        username: 'proxied',
        passwordHash: passwordHash,
        role: 'admin',
      );

    final pipeline = handler
        .use(authProvider())
        .use(provider<AuthRuntime>((_) => runtime))
        .use(provider<SaltDatabase>((_) => db))
        .use(provider<ServerConfig>((_) => config))
        .use(errorHandler())
        .use(requestLogger())
        .use(requestIdProvider());
    // anyIPv6, exactly as production does — see the note above.
    final server = await serve(pipeline, InternetAddress.anyIPv6, 0);
    addTearDown(() async {
      await server.close(force: true);
      db.dispose();
      dir.deleteSync(recursive: true);
    });
    // Connect over IPv4 so the dual-stack listener reports a mapped peer,
    // which is what the reverse proxy on a Docker bridge looks like.
    return Uri.parse('http://127.0.0.1:${server.port}');
  }

  /// The `set-cookie` from a successful login carrying [headers].
  Future<String> loginSetCookie({
    required Map<String, String> environment,
    Map<String, String> headers = const {},
  }) async {
    final base = await serveUnder(login_route.onRequest, environment);
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.postUrl(
      base.replace(path: '/api/v1/auth/login'),
    );
    request.headers.contentType = ContentType.json;
    for (final entry in {..._csrfHeader, ...headers}.entries) {
      request.headers.set(entry.key, entry.value);
    }
    request.write(jsonEncode({'username': 'proxied', 'password': _password}));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    expect(
      response.statusCode,
      HttpStatus.ok,
      reason: 'login must succeed or the cookie assertion is vacuous: $body',
    );
    final cookie = response.headers['set-cookie']?.first;
    expect(cookie, isNotNull, reason: 'no session cookie was issued');
    return cookie!;
  }

  /// What `clientIp` resolves to for a request carrying [headers].
  Future<String> clientIpFor({
    required Map<String, String> environment,
    Map<String, String> headers = const {},
  }) async {
    final base = await serveUnder(
      (context) => Response(body: clientIp(context)),
      environment,
    );
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.getUrl(base);
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final response = await request.close();
    return response.transform(utf8.decoder).join();
  }

  group('the peer the server actually sees', () {
    test('is IPv4-MAPPED, as production reports it', () async {
      // If this ever stops being true, every other test here is measuring a
      // peer the deployment never meets — which is exactly how the original
      // bug shipped green.
      final peer = await clientIpFor(environment: {});
      expect(peer, startsWith('::ffff:'));
      expect(peer, '::ffff:127.0.0.1');
    });
  });

  group('which X-Forwarded-For value is believed', () {
    // The half the peer check does NOT cover. An attacker behind the proxy
    // sends `X-Forwarded-For: 1.2.3.4`; the proxy appends the real client IP,
    // so the header arrives as `1.2.3.4, <real>`. Only the RIGHTMOST value was
    // appended by a hop we trust.
    test(
      'the RIGHTMOST value wins — the leftmost is attacker-supplied',
      () async {
        final ip = await clientIpFor(
          environment: {
            'TRUST_PROXY': 'true',
            'TRUSTED_PROXIES': '127.0.0.0/8',
          },
          headers: {'X-Forwarded-For': '1.2.3.4, 9.9.9.9'},
        );
        expect(
          ip,
          '9.9.9.9',
          reason:
              'taking the leftmost hands an attacker a fresh rate-limit bucket '
              'per request, which is the bug this whole surface exists to fix',
        );
      },
    );

    test('an UNTRUSTED peer cannot set it at all', () async {
      final ip = await clientIpFor(
        environment: {'TRUST_PROXY': 'true', 'TRUSTED_PROXIES': '10.99.99.99'},
        headers: {'X-Forwarded-For': '1.2.3.4'},
      );
      expect(ip, '::ffff:127.0.0.1', reason: 'the socket peer, not the header');
    });

    test(
      'TRUST_PROXY off ignores the header even from the real proxy',
      () async {
        final ip = await clientIpFor(
          environment: {'TRUSTED_PROXIES': '127.0.0.0/8'},
          headers: {'X-Forwarded-For': '1.2.3.4'},
        );
        expect(ip, '::ffff:127.0.0.1');
      },
    );

    test('a single forwarded value from a trusted proxy is used', () async {
      final ip = await clientIpFor(
        environment: {'TRUST_PROXY': 'true', 'TRUSTED_PROXIES': '127.0.0.0/8'},
        headers: {'X-Forwarded-For': '9.9.9.9'},
      );
      expect(ip, '9.9.9.9');
    });
  });

  group('the Secure attribute', () {
    test('behind a TRUSTED proxy, an https request is Secure', () async {
      final cookie = await loginSetCookie(
        environment: {'TRUST_PROXY': 'true', 'TRUSTED_PROXIES': '127.0.0.0/8'},
        headers: {'X-Forwarded-Proto': 'https'},
      );
      expect(
        cookie,
        contains('; Secure'),
        reason:
            'a session cookie behind a TLS proxy MUST be Secure — this is the '
            'assertion whose absence let isSecureRequest be broken twice with '
            'a green suite',
      );
    });

    test('a TRUSTED proxy forwarding http gets NO Secure', () async {
      // The untested quadrant: the peer IS trusted, so the header is read —
      // and its VALUE has to be checked. `return true` here would make the
      // cookie Secure over cleartext, and the browser would then refuse to
      // send it back at all.
      final cookie = await loginSetCookie(
        environment: {'TRUST_PROXY': 'true', 'TRUSTED_PROXIES': '127.0.0.0/8'},
        headers: {'X-Forwarded-Proto': 'http'},
      );
      expect(cookie, isNot(contains('; Secure')));
    });

    test('from an UNTRUSTED peer, X-Forwarded-Proto is ignored', () async {
      final cookie = await loginSetCookie(
        environment: {'TRUST_PROXY': 'true', 'TRUSTED_PROXIES': '10.99.99.99'},
        headers: {'X-Forwarded-Proto': 'https'},
      );
      expect(
        cookie,
        isNot(contains('; Secure')),
        reason:
            'a peer that is not our proxy must not describe its own connection',
      );
    });

    test('SECURE_COOKIES forces Secure with no proxy at all', () async {
      // The direct-TLS deployment. Zero references in test/ before this.
      final cookie = await loginSetCookie(
        environment: {'SECURE_COOKIES': 'true'},
      );
      expect(cookie, contains('; Secure'));
    });

    test('plain http with no proxy gets no Secure', () async {
      // The negative that must stay true: Secure on a cleartext cookie makes
      // the session unusable rather than insecure, so this keeps local
      // development working.
      final cookie = await loginSetCookie(environment: {});
      expect(cookie, isNot(contains('; Secure')));
    });
  });
}
