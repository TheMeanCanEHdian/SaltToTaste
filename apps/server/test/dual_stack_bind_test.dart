import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/dual_stack_bind.dart';

/// The harness helper's own pins: what its port is, and that its retry is
/// bounded. That the port dodges a foreign `127.0.0.1` listener is a property
/// of the kernel's port hand-out and is not pinned here: staging it (one
/// listener held on the port the counter hands out next) leans on macOS's
/// sequential ephemeral counter, and Linux draws at random. Measured, see
/// support/dual_stack_bind.dart.
// Synthesized refusals: a wildcard-held port cannot come from the corpus.
void main() {
  /// What [server] reports as the peer of a connect to `127.0.0.1`.
  Future<String> peerOver127(HttpServer server) async {
    server.listen((request) {
      request.response
        ..write(request.connectionInfo!.remoteAddress.address)
        ..close();
    });
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final response = await request.close();
    return response.transform(utf8.decoder).join();
  }

  test('the server is bound on the port it was handed, and an IPv4 connect '
      'reaches it as a mapped peer', () async {
    final handed = <int>[];
    final server = await bindOnFreeLoopbackPort((port) {
      handed.add(port);
      return HttpServer.bind(InternetAddress.anyIPv6, port);
    });
    addTearDown(() => server.close(force: true));
    expect(handed, [server.port]);
    expect(handed.single, isNot(0), reason: 'port 0 is the collision');
    expect(await peerOver127(server), '::ffff:127.0.0.1');
  });

  test('a refused port is given up for a newly drawn one', () async {
    final handed = <int>[];
    final server = await bindOnFreeLoopbackPort((port) async {
      handed.add(port);
      if (handed.length < 3) {
        // Keep the refused number taken, so no later draw can equal it by
        // chance: three distinct ports is then the helper's doing.
        final taken = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
        );
        addTearDown(taken.close);
        throw const SocketException('address in use');
      }
      return HttpServer.bind(InternetAddress.anyIPv6, port);
    });
    addTearDown(() => server.close(force: true));
    expect(handed, hasLength(3));
    expect(handed.toSet(), hasLength(3), reason: 'the same port retried');
    expect(server.port, handed.last);
    expect(await peerOver127(server), '::ffff:127.0.0.1');
  });

  test('a bind that always refuses is rethrown after $bindAttempts draws, '
      'never spun on', () async {
    var draws = 0;
    await expectLater(
      bindOnFreeLoopbackPort((port) {
        draws++;
        throw SocketException('refused', port: port);
      }),
      throwsA(isA<SocketException>()),
    );
    expect(draws, bindAttempts);
  });

  test('an error that is not a refusal is not retried', () async {
    var draws = 0;
    await expectLater(
      bindOnFreeLoopbackPort((port) {
        draws++;
        throw StateError('not a socket error');
      }),
      throwsStateError,
    );
    expect(draws, 1);
  });
}
