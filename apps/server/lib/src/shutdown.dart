import 'dart:async';
import 'dart:io';

/// Drains in-flight requests before shutdown and reports whether it had to
/// force-close.
///
/// [HttpServer.close] (without `force`) stops the listener and reaps IDLE
/// connections, but its future does NOT wait for requests that are actively
/// being served — so calling `exit(0)` right after it kills a committed save
/// the client never learns about (the "drain was a no-op" bug found in the P7
/// review). This instead polls [HttpServer.connectionsInfo] for real `active`
/// requests up to [bound]; if any remain it force-closes and returns `true`.
///
/// Because idle and half-open sockets are reaped by the initial `close()`, a
/// slowloris connection stalled mid-headers (counted `idle`, not `active`) does
/// NOT extend the drain — verified in `availability_vectors_test.dart`.
///
/// Extracted from the SIGTERM handler so this guarantee is driven by a test
/// rather than only reasoned about (task #48): task #42's critic could reason
/// about the drain but not exercise it in-harness.
Future<bool> drainConnections(
  HttpServer server, {
  required Duration bound,
  Duration pollInterval = const Duration(milliseconds: 100),
  void Function()? onForceClose,
}) async {
  await server.close();
  final deadline = DateTime.now().add(bound);
  while (server.connectionsInfo().active > 0 &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(pollInterval);
  }
  if (server.connectionsInfo().active > 0) {
    onForceClose?.call();
    await server.close(force: true);
    return true;
  }
  return false;
}
