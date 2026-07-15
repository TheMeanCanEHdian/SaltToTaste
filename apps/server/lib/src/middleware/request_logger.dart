import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/middleware/request_context.dart';

final Logger _log = Logger('http');

/// Middleware that logs `METHOD path -> status (Nms) rid=<id>` at INFO on
/// the `http` logger once the response has resolved.
///
/// Wired outside the error handler so failed requests are still logged,
/// with the status of the error envelope they produced.
Middleware requestLogger() {
  return (handler) {
    return (context) async {
      final stopwatch = Stopwatch()..start();
      final response = await handler(context);
      stopwatch.stop();
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
