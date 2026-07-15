import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_shared/salt_shared.dart';

final Logger _log = Logger('http');

/// The body dart_frog's router returns for unmatched routes.
const String _routerNotFoundBody = 'Route not found';

/// Middleware that converts exceptions into the uniform error envelope
/// `{"error": {"code", "message", "request_id"}}`.
///
/// * [AppException] becomes a response with its status code and error code.
/// * Anything else is logged at SEVERE (with stack trace) and becomes an
///   opaque 500 `internal` envelope — clients never see stack traces.
/// * A bare 404 from dart_frog's router (empty or `Route not found` body)
///   is rewrapped into a `not_found` envelope.
Middleware errorHandler() {
  return (handler) {
    return (context) async {
      final requestId = requestIdOf(context);
      try {
        final response = await handler(context);
        if (response.statusCode == HttpStatus.notFound) {
          final body = await response.body();
          if (body.isEmpty || body == _routerNotFoundBody) {
            return errorResponse(
              statusCode: HttpStatus.notFound,
              code: 'not_found',
              message: 'Not found.',
              requestId: requestId,
            );
          }
          // The body stream was consumed above; rebuild the response so it
          // can still be served downstream.
          return response.copyWith(body: body);
        }
        return response;
      } on AppException catch (exception) {
        return errorResponse(
          statusCode: exception.statusCode,
          code: exception.code,
          message: exception.message,
          requestId: requestId,
        );
      } catch (error, stackTrace) {
        _log.severe(
          'Unhandled error on ${context.request.method.value} '
          '${context.request.uri.path} rid=${requestId ?? '-'}',
          error,
          stackTrace,
        );
        return errorResponse(
          statusCode: HttpStatus.internalServerError,
          code: 'internal',
          message: 'Internal server error.',
          requestId: requestId,
        );
      }
    };
  };
}

/// Builds an error-envelope JSON response from the shared [ApiError] DTO.
Response errorResponse({
  required int statusCode,
  required String code,
  required String message,
  String? requestId,
}) {
  final error = ApiError(code: code, message: message, requestId: requestId);
  return Response.json(
    statusCode: statusCode,
    body: {'error': error.toMap()},
  );
}
