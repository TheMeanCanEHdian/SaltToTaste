import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/bootstrap.dart';

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
  final server = await serve(handler, ip, port);
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
    // close() only stops the listener and kills IDLE connections — its
    // future does NOT wait for active requests. Poll the connection stats
    // for a real drain (bounded well under Docker's 10s stop grace so the
    // final WAL checkpoint still fits).
    await server.close();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (server.connectionsInfo().active > 0 &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (server.connectionsInfo().active > 0) {
      _log.warning('Drain timed out; closing connections forcibly');
      await server.close(force: true);
    }
    disposeServer();
    _log.info('Shutdown complete');
    exit(0);
  }

  ProcessSignal.sigterm.watch().listen((_) => shutdown('SIGTERM'));
  ProcessSignal.sigint.watch().listen((_) => shutdown('SIGINT'));
}
