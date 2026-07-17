import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_shared/salt_shared.dart';

final Logger _log = Logger('http');

/// Middleware that converts exceptions into the uniform error envelope
/// `{"error": {"code", "message", "request_id"}}`.
///
/// * [AppException] becomes a response with its status code and error code
///   (a [MethodNotAllowedException] also gets an `Allow` header).
/// * Anything else is logged at SEVERE (with stack trace) and becomes an
///   opaque 500 `internal` envelope — clients never see stack traces.
/// * A 404 response from the inner handler is the router's unmatched-route
///   fallback (feature code throws [NotFoundException] instead of returning a
///   404), so it is rewrapped into a `not_found` envelope. This is keyed on
///   the status code, not the framework's fallback body text.
Middleware errorHandler() {
  return (handler) {
    return (context) async {
      final requestId = requestIdOf(context);
      try {
        final response = await handler(context);
        if (response.statusCode == HttpStatus.notFound) {
          // P7 note: the SPA fallback (serve index.html for page paths) will
          // branch here on the request path before this rewrap.
          return errorResponse(
            statusCode: HttpStatus.notFound,
            code: ApiErrorCodes.notFound,
            message: 'Not found.',
            requestId: requestId,
          );
        }
        return response;
      } on MethodNotAllowedException catch (exception) {
        return errorResponse(
          statusCode: exception.statusCode,
          code: exception.code,
          message: exception.message,
          requestId: requestId,
          headers: {HttpHeaders.allowHeader: exception.allow},
        );
      } on TooManyRequestsException catch (exception) {
        return errorResponse(
          statusCode: exception.statusCode,
          code: exception.code,
          message: exception.message,
          requestId: requestId,
          headers: {
            HttpHeaders.retryAfterHeader: '${exception.retryAfterSeconds}',
          },
        );
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
          code: ApiErrorCodes.internal,
          message: 'Internal server error.',
          requestId: requestId,
        );
      }
    };
  };
}

/// Builds an error-envelope JSON response from the shared [ApiError] DTO,
/// optionally with extra [headers].
Response errorResponse({
  required int statusCode,
  required String code,
  required String message,
  String? requestId,
  Map<String, String> headers = const {},
}) {
  final error = ApiError(code: code, message: message, requestId: requestId);
  return Response.json(
    statusCode: statusCode,
    body: {'error': error.toMap()},
    headers: headers,
  );
}
