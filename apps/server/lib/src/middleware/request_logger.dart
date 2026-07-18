import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/middleware/request_context.dart';

final Logger _log = Logger('http');

/// Paths whose request logging is suppressed: high-frequency, self-referential
/// polling that would otherwise flood the log with noise.
///
/// * `/healthz` — the container liveness probe hits it every 30s (Dockerfile
///   `HEALTHCHECK`).
/// * `/api/v1/admin/logs` — the admin log viewer's own read. Its "Live" tail
///   polls every few seconds, and each poll would log a line _about the act of
///   reading the log_, which then shows up in the very list being read.
///
/// Skipping them at the source keeps them out of both the store and stdout, and
/// stops self-poll noise from rotating real history out of the sized log file.
/// The one-off `/api/v1/admin/logs/export` download is deliberately NOT here —
/// it is rare and worth a trace.
const Set<String> unloggedPaths = {'/healthz', '/api/v1/admin/logs'};

/// Middleware that logs `METHOD path -> status (Nms) rid=<id>` at INFO on
/// the `http` logger once the response has resolved.
///
/// Wired outside the error handler so failed requests are still logged,
/// with the status of the error envelope they produced. [unloggedPaths] are
/// exempt (operational polling noise).
Middleware requestLogger() {
  return (handler) {
    return (context) async {
      final stopwatch = Stopwatch()..start();
      final response = await handler(context);
      stopwatch.stop();
      if (unloggedPaths.contains(context.request.uri.path)) {
        return response;
      }
      final rid = requestIdOf(context) ?? '-';
      _log.info(
        '${context.request.method.value} ${context.request.uri.path} '
        '-> ${response.statusCode} '
        '(${stopwatch.elapsedMilliseconds}ms) rid=$rid',
      );
      return response;
    };
  };
}
