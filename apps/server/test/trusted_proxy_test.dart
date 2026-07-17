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
