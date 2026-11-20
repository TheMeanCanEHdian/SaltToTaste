// The port for a test server that binds `InternetAddress.anyIPv6` the way
// production does and is reached over `127.0.0.1`, so that the peer it sees
// is `::ffff:127.0.0.1`: secure_cookie_http_test, trusted_proxy_test and the
// v111 Y6 table of static_asset_headers_test.
import 'dart:io';

/// How many ports [bindOnFreeLoopbackPort] draws before it gives up.
const bindAttempts = 20;

/// Runs [bind] on a port no other socket holds on `127.0.0.1`.
///
/// Port 0 on a wildcard bind is free for the WILDCARD address only. macOS
/// hands `[::]:0` the next ephemeral port even while another socket — another
/// process, or another isolate of the run — listens on it at `127.0.0.1`
/// (measured 2026-11-19 beside 200 listeners of a second process: 199 of
/// 20,000 binds), the more specific listener takes the IPv4 connect, and the
/// test reads that listener's answer — the foreign 401 and "Cannot GET /"
/// bodies of two of the four recorded full-suite failures (the other two
/// read "Connection closed before full header").
///
/// So the number comes from a throwaway bind ON `127.0.0.1`, which the kernel
/// never places on a held port (0 of 20,000, same conditions), and [bind]
/// gets it. A socket holding that number on a wildcard address then refuses
/// [bind] with a `SocketException` (23 such ports on the measuring Mac, 41
/// refusals in 30,000, never more than 2 adjacent): the next number is
/// drawn, [bindAttempts] in all, and the last refusal is rethrown.
///
/// Staged with a second process listening on every other ephemeral port at
/// `127.0.0.1`: the three files are +80 -14 on port 0 (10 failures read that
/// process's answer, 4 show the test's own server never saw the request) and
/// all green on this. The kit and its outputs:
/// .claude/diag/2026-11-19/dual-stack-port.
//
// ponytail: the reservation is closed before [bind] runs, so a process that
// binds 127.0.0.1:<port> by NUMBER in that instant, or while the server is
// up, still answers instead (an ephemeral 127.0.0.1:0 bind does not: 0 of
// 20,000 landed under a held `[::]` listener). Only a per-request identity
// check closes that; add one if a foreign body is ever read again.
Future<HttpServer> bindOnFreeLoopbackPort(
  Future<HttpServer> Function(int port) bind,
) async {
  for (var attempt = 1; ; attempt++) {
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    try {
      return await bind(port);
    } on SocketException {
      if (attempt == bindAttempts) rethrow;
    }
  }
}
