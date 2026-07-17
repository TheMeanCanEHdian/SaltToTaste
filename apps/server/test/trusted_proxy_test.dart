import 'dart:io';

import 'package:salt_server/src/bootstrap.dart';
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

  group('only a REAL IPv4-mapped address may unmap', () {
    // The `::ffff:0:0/96` prefix guards in _asIpv4 are the security of this
    // whole surface, and nothing pinned them: the review deleted the
    // all-zero-prefix loop and all 320 tests stayed green while a hostile
    // peer gained the proxy's trust. Every address here is chosen so that
    // exactly one guard stands between it and a false match.
    test('a public IPv6 ending in the bridge quad is NOT the bridge', () {
      final config = configFor('true', '172.17.0.0/16');
      // Bytes: [32,1,13,184, 0,0,0,0, 0,0, 255,255, 172,17,0,2] — the 0xffff
      // marker and the trailing quad both look exactly like a mapped
      // 172.17.0.2. Only the all-zero test on bytes[0..9] tells them apart,
      // and the attacker picks this address.
      expect(
        config.isTrustedProxy('2001:db8::ffff:172.17.0.2'),
        isFalse,
        reason:
            'a globally-routable IPv6 that merely ENDS in a trusted quad must '
            'never be unmapped into it — delete the zero-prefix loop in '
            '_asIpv4 and this is how a hostile peer becomes the proxy',
      );
      // The genuine mapped form of the same quad still works, so the guard
      // above is not just refusing everything.
      expect(config.isTrustedProxy('::ffff:172.17.0.2'), isTrue);
    });

    test('an IPv4-COMPATIBLE address is not an IPv4-mapped one', () {
      // `::172.17.0.2` has the all-zero prefix but NOT the 0xffff marker: the
      // deprecated IPv4-compatible form. It is not our proxy, and only the
      // bytes[10..11] check says so.
      final config = configFor('true', '172.17.0.0/16');
      expect(
        config.isTrustedProxy('::172.17.0.2'),
        isFalse,
        reason:
            'without the 0xffff check this deprecated form unmaps into the '
            'trusted block',
      );
    });

    test('an exact IPv6 rule cannot be matched by a mapped IPv4 peer', () {
      // The two address families must not leak into each other in either
      // direction: ::ffff:0.0.0.1 is not ::1.
      final config = configFor('true', '::1');
      expect(config.isTrustedProxy('::ffff:0.0.0.1'), isFalse);
      expect(config.isTrustedProxy('::1'), isTrue);
    });

    test('a leading-zero entry means what it says', () {
      // dart:io echoes the input back for IPv4, so `010.0.0.5` stayed
      // `010.0.0.5` and never string-matched the `10.0.0.5` a peer reports —
      // correct configuration failing closed, silently. _asIpv4 canonicalises
      // from the bytes now.
      final config = configFor('true', '010.0.0.5');
      expect(
        config.isTrustedProxy('10.0.0.5'),
        isTrue,
        reason: '010.0.0.5 and 10.0.0.5 are the same address',
      );
      expect(config.isTrustedProxy('::ffff:10.0.0.5'), isTrue);
      expect(config.isTrustedProxy('10.0.0.6'), isFalse);
    });
  });

  group('configWarnings', () {
    // Every warning here covers a config that fails closed IN SILENCE. That
    // silence is the whole defect: an operator who sets TRUSTED_PROXIES and
    // is told nothing has no way to learn it trusts nobody until a cookie
    // goes missing its Secure flag in production.
    test('a correct proxy config says nothing', () {
      expect(configWarnings(configFor('true', '172.17.0.0/16')), isEmpty);
      expect(configWarnings(configFor(null, null)), isEmpty);
    });

    test('TRUST_PROXY with an empty list warns', () {
      expect(
        configWarnings(configFor('true', null)),
        contains(contains('TRUSTED_PROXIES is empty')),
      );
    });

    test('TRUSTED_PROXIES without TRUST_PROXY warns', () {
      // The list is set, so the empty-list warning cannot fire; without this
      // one the misconfiguration is completely silent.
      expect(
        configWarnings(configFor(null, '172.17.0.0/16')),
        contains(contains('TRUST_PROXY is not enabled')),
      );
    });

    test('an entry that can never match is named', () {
      final warnings = configWarnings(configFor('true', 'fd00::/8, caddy'));
      expect(warnings, hasLength(1));
      // Naming them matters: the operator has to find which one is wrong.
      expect(warnings.single, contains('fd00::/8'));
      expect(warnings.single, contains('caddy'));
    });

    test('a usable entry beside an unusable one still warns', () {
      // The dangerous shape: it half works, so nothing looks broken.
      expect(
        configWarnings(configFor('true', '172.17.0.0/16, fd00::/8')),
        contains(contains('fd00::/8')),
      );
    });
  });

  group('isUsableProxyEntry', () {
    // Existence is not usability, and the boot warning only ever fired on an
    // EMPTY list — so an entry that can never match looked configured and was
    // ignored in silence, which is the exact shape of the bug this surface
    // was fixed for.
    test('the forms the README documents are usable', () {
      for (final entry in ['172.17.0.0/16', '10.0.0.5', '::1', '0.0.0.0/0']) {
        expect(isUsableProxyEntry(entry), isTrue, reason: entry);
      }
    });

    test('the forms that silently match nothing are reported', () {
      for (final entry in [
        'fd00::/8', // IPv6 CIDR — unsupported, and the natural guess
        '172.17.O.0/16', // letter O for zero
        'caddy', // a Compose service name
        '10.0.0.0/99',
        '10.0.0.0/-1',
        '/16',
        '',
      ]) {
        expect(isUsableProxyEntry(entry), isFalse, reason: entry);
      }
    });
  });
}
