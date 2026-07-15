import 'package:salt_shared/salt_shared.dart';

/// Base type for domain errors that map to a specific HTTP status code and
/// stable machine-readable error code.
///
/// The error-handler middleware converts any thrown [AppException] into the
/// uniform envelope `{"error": {"code", "message", "request_id"}}`. Feature
/// code should throw these instead of hand-building error responses.
abstract base class AppException implements Exception {
  /// Creates an exception that maps to [statusCode] / [code].
  const AppException(this.statusCode, this.code, this.message);

  /// HTTP status code of the resulting response.
  final int statusCode;

  /// Stable machine-readable error code (see [ApiErrorCodes] / docs/API.md).
  final String code;

  /// Human-readable, actionable message for API clients. Never a stack
  /// trace and never secret material.
  final String message;

  @override
  String toString() => 'AppException($statusCode $code): $message';
}

/// The requested resource does not exist (HTTP 404, code `not_found`).
final class NotFoundException extends AppException {
  /// Creates a not-found exception with the client-facing [message].
  const NotFoundException(String message)
      : super(404, ApiErrorCodes.notFound, message);
}

/// The request was well-formed but semantically invalid (HTTP 422, code
/// `validation`).
final class ValidationException extends AppException {
  /// Creates a validation exception with the client-facing [message].
  const ValidationException(String message)
      : super(422, ApiErrorCodes.validation, message);
}

/// The route exists but the HTTP method is not supported (HTTP 405, code
/// `method_not_allowed`). [allow] is the value for the `Allow` response
/// header the error handler attaches.
final class MethodNotAllowedException extends AppException {
  /// Creates a method-not-allowed exception advertising the [allow] methods.
  const MethodNotAllowedException(this.allow)
      : super(
          405,
          ApiErrorCodes.methodNotAllowed,
          'Method not allowed.',
        );

  /// Comma-separated list of allowed methods (e.g. `GET`).
  final String allow;
}
