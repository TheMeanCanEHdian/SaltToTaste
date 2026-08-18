import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/middleware/auth.dart';
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

/// Middleware that logs `METHOD path -> status (Nms) from <ip> rid=<id>` at
/// INFO on the `http` logger once the response has resolved.
///
/// [config] supplies the trusted-proxy set so the client IP respects the proxy
/// configuration (rightmost `X-Forwarded-For` from a trusted hop, else the
/// socket peer). It is passed as a value, not read from a provider, because
/// this middleware is wired UPSTREAM of the `ServerConfig` provider. When it is
/// null (some hand-rolled test pipelines), the `from <ip>` clause is omitted.
///
/// Wired outside the error handler so failed requests are still logged,
/// with the status of the error envelope they produced. [unloggedPaths] are
/// exempt (operational polling noise).
Middleware requestLogger([ServerConfig? config]) {
  return (handler) {
    return (context) async {
      final stopwatch = Stopwatch()..start();
      final response = await handler(context);
      stopwatch.stop();
      if (unloggedPaths.contains(context.request.uri.path)) {
        return response;
      }
      final from = config == null
          ? ''
          : ' from ${clientIpFor(context, config)}';
      // The id travels as DATA (RequestLogMessage), so the store never has to
      // recover it from text an attacker shares a line with — see S8.
      _log.info(
        RequestLogMessage(
          '${context.request.method.value} '
          '${loggedPath(context.request.uri.path)} '
          '-> ${response.statusCode} '
          '(${stopwatch.elapsedMilliseconds}ms)$from',
          requestIdOf(context),
        ),
      );
      return response;
    };
  };
}
