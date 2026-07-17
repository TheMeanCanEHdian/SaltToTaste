import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/bootstrap.dart';
import 'package:salt_server/src/shutdown.dart';

final Logger _log = Logger('server');

/// Custom Dart Frog entrypoint: initializes configuration, logging, and the
/// database before serving, so a bad `LOG_LEVEL`/`DATA_DIR` fails the process
/// at startup (with a clear message) instead of turning every request into a
/// silent 500. On a first boot with zero users this also prints the one-time
/// setup code used by `POST /api/v1/auth/setup`.
Future<HttpServer> run(Handler handler, InternetAddress ip, int port) async {
  try {
    initServer();
  } catch (error, stackTrace) {
    stderr
      ..writeln('Fatal: server configuration failed.')
      ..writeln(error)
      ..writeln(stackTrace);
    rethrow;
  }
  // Spawn the search worker isolate(s) AFTER initServer has opened and migrated
  // the database, so their read-only connections can attach (#48).
  await initSearchService();
  final server = await serve(handler, ip, port);
  // Reap half-open / idle sockets after this window: bounds slowloris-style
  // connection accumulation (measured in availability_vectors_test.dart), below
  // Dart's 120s default. `null` disables (CONNECTION_IDLE_TIMEOUT_SECONDS=0).
  server.idleTimeout = serverConfig.connectionIdleTimeout;
  _handleShutdownSignals(server);
  return server;
}

/// Graceful shutdown on SIGTERM/SIGINT (`docker stop`, ^C): stop accepting
/// connections, drain in-flight requests (bounded), then close SQLite
/// cleanly so the WAL checkpoints and the next boot needs no recovery.
void _handleShutdownSignals(HttpServer server) {
  if (Platform.isWindows) {
    return; // sigterm.watch() is unsupported; dev-only platform.
  }
  var shuttingDown = false;
  Future<void> shutdown(String signal) async {
    if (shuttingDown) {
      return;
    }
    shuttingDown = true;
    _log.info('$signal received; draining requests');
    // Bounded well under Docker's 10s stop grace so the final WAL checkpoint
    // still fits. drainConnections waits for in-flight requests to finish
    // (idle/half-open sockets are reaped by its initial close()).
    await drainConnections(
      server,
      bound: const Duration(seconds: 5),
      onForceClose: () =>
          _log.warning('Drain timed out; closing connections forcibly'),
    );
    // Stop the search workers (closing their read-only connections) BEFORE the
    // writer closes, so its final WAL checkpoint is not blocked by a reader.
    await disposeSearchService();
    disposeServer();
    _log.info('Shutdown complete');
    exit(0);
  }

  ProcessSignal.sigterm.watch().listen((_) => shutdown('SIGTERM'));
  ProcessSignal.sigint.watch().listen((_) => shutdown('SIGINT'));
}
