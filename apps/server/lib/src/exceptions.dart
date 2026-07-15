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

  /// Stable machine-readable error code (catalog lives in docs/API.md).
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
      : super(404, 'not_found', message);
}

/// The request was well-formed but semantically invalid (HTTP 422, code
/// `validation`).
final class ValidationException extends AppException {
  /// Creates a validation exception with the client-facing [message].
  const ValidationException(String message)
      : super(422, 'validation', message);
}
