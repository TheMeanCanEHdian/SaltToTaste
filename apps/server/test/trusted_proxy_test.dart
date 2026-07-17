import 'dart:io';

import 'package:salt_server/src/config.dart';
import 'package:test/test.dart';

/// `TRUST_PROXY` alone used to mean "believe X-Forwarded-For from whoever
/// connected", so anyone who could reach the port minted a fresh rate-limit
/// bucket per request by inventing the header — login throttling was
/// decorative in the deployment the README documents. Nothing tested it:
/// before this file, every config in the suite set `trustProxy: false`.
void main() {
  ServerConfig configFor(String? trustProxy, String? trusted) =>
      ServerConfig.fromEnvironment(
        environment: {
          'DATA_DIR': '/tmp/salt-test',
          if (trustProxy != null) 'TRUST_PROXY': trustProxy,
          if (trusted != null) 'TRUSTED_PROXIES': trusted,
        },
      );

  group('the address an operator types vs the one dart:io reports', () {
    // The gap that made the whole peer check inert in production, and which
    // ServerConfig-only tests could never see: the shipped binary binds
    // `InternetAddress.anyIPv6` (dart_frog's generated entrypoint, which the
    // Dockerfile compiles and runs), and that listener is DUAL-STACK. So an
    // IPv4 peer — the reverse proxy on the Docker bridge — arrives as
    // `::ffff:172.17.0.2`, never `172.17.0.2`. Matching the operator's typed
    // `172.17.0.0/16` against that string found nothing, so TRUST_PROXY +
    // TRUSTED_PROXIES did NOTHING while looking configured, and the session
    // cookie silently lost `Secure` along with it.
    test('a REAL peer on the production bind is matched', () async {
      final config = ServerConfig.fromEnvironment(
        environment: {
          'DATA_DIR': '/tmp/salt-test',
          'TRUST_PROXY': 'true',
          'TRUSTED_PROXIES': '127.0.0.0/8',
        },
      );

      // Bind the way production does, and ask a real socket what the peer
      // looks like. Nothing else can produce this string.
      final server = await HttpServer.bind(InternetAddress.anyIPv6, 0);
      String? peer;
      server.listen((request) {
        peer = request.connectionInfo!.remoteAddress.address;
        request.response
          ..statusCode = 200
          ..close();
      });
      final socket = await Socket.connect(
        InternetAddress('127.0.0.1'),
        server.port,
      );
      socket.write('GET / HTTP/1.1\r\nHost: x\r\n\r\n');
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await socket.close();
      await server.close(force: true);

      expect(
        peer,
        startsWith('::ffff:'),
        reason:
            'the dual-stack bind reports IPv4 peers mapped; if this ever '
            'stops being true the rest of this test is meaningless',
      );
      expect(
        config.isTrustedProxy(peer),
        isTrue,
        reason:
            'the peer the SERVER actually sees ($peer) must match the '
            'CIDR an operator actually writes — this is the production path',
      );
    });

    test('an IPv4-mapped peer matches a plain IPv4 rule, both forms', () {
      final config = ServerConfig.fromEnvironment(
        environment: {
          'DATA_DIR': '/tmp/salt-test',
          'TRUST_PROXY': 'true',
          'TRUSTED_PROXIES': '172.17.0.0/16, 10.0.0.5',
        },
      );
      expect(config.isTrustedProxy('::ffff:172.17.0.2'), isTrue);
      expect(config.isTrustedProxy('172.17.0.2'), isTrue);
      expect(config.isTrustedProxy('::ffff:10.0.0.5'), isTrue);
      expect(config.isTrustedProxy('10.0.0.5'), isTrue);
      // Still fails closed for anything outside the rule, mapped or not.
      expect(config.isTrustedProxy('::ffff:172.18.0.2'), isFalse);
      expect(config.isTrustedProxy('172.18.0.2'), isFalse);
    });

    test('one IPv6 address matches however it is spelled', () {
      final config = ServerConfig.fromEnvironment(
        environment: {
          'DATA_DIR': '/tmp/salt-test',
          'TRUST_PROXY': 'true',
          'TRUSTED_PROXIES': '0:0:0:0:0:0:0:1',
        },
      );
      // The operator wrote the expanded form; dart:io reports the compressed
      // one. They are the same address and must behave like it.
      expect(config.isTrustedProxy('::1'), isTrue);
      expect(config.isTrustedProxy('0:0:0:0:0:0:0:1'), isTrue);
      expect(config.isTrustedProxy('::2'), isFalse);
    });
  });

  group('TRUSTED_PROXIES', () {
    test('an exact address is trusted; nothing else is', () {
      final config = configFor('true', '10.0.0.5');
      expect(config.isTrustedProxy('10.0.0.5'), isTrue);
      expect(config.isTrustedProxy('10.0.0.6'), isFalse);
      expect(config.isTrustedProxy('10.0.0.50'), isFalse);
      expect(config.isTrustedProxy(null), isFalse);
    });

    test('an IPv4 CIDR covers its block and stops at the edges', () {
      // The documented deployment puts the proxy on a Docker bridge, where
      // its address is assigned and moves — exact IPs would be unusable.
      final config = configFor('true', '172.17.0.0/16');
      expect(config.isTrustedProxy('172.17.0.1'), isTrue);
      expect(config.isTrustedProxy('172.17.255.254'), isTrue);
      expect(config.isTrustedProxy('172.18.0.1'), isFalse);
      expect(config.isTrustedProxy('172.16.255.254'), isFalse);
    });

    test('several entries, mixed forms', () {
      final config = configFor('true', ' 127.0.0.1 , 172.17.0.0/16 ,::1 ');
      expect(config.isTrustedProxy('127.0.0.1'), isTrue);
      expect(config.isTrustedProxy('172.17.9.9'), isTrue);
      expect(config.isTrustedProxy('::1'), isTrue);
      expect(config.isTrustedProxy('192.168.1.1'), isFalse);
    });

    test('TRUST_PROXY without TRUSTED_PROXIES trusts NOBODY', () {
      // Fails closed: the cost is one shared rate-limit bucket, not an
      // unlimited supply of them. Boot warns about it.
      final config = configFor('true', null);
      expect(config.trustProxy, isTrue);
      expect(config.trustedProxies, isEmpty);
      expect(config.isTrustedProxy('10.0.0.5'), isFalse);
    });

    test('TRUSTED_PROXIES without TRUST_PROXY trusts nobody either', () {
      final config = configFor(null, '10.0.0.5');
      expect(config.isTrustedProxy('10.0.0.5'), isFalse);
    });

    test('an unparseable entry never widens trust', () {
      // A typo must fail closed, not match everything.
      final config = configFor('true', 'not-an-ip/xx, 10.0.0.0/99, /16');
      expect(config.isTrustedProxy('10.0.0.1'), isFalse);
      expect(config.isTrustedProxy('anything'), isFalse);
    });

    test('a /0 entry is honoured as written', () {
      // Deliberately trusting everything is the operator's call to make; it
      // must not be an accident of parsing, so it is spelled 0.0.0.0/0.
      final config = configFor('true', '0.0.0.0/0');
      expect(config.isTrustedProxy('8.8.8.8'), isTrue);
    });
  });
}
