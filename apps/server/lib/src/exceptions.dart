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

/// No valid credential accompanied the request (HTTP 401, code
/// `unauthorized`). Covers missing, malformed, expired, and revoked
/// credentials alike so the response never reveals which one it was.
final class UnauthorizedException extends AppException {
  /// Creates an unauthorized exception with the uniform sign-in message.
  const UnauthorizedException()
    : super(401, ApiErrorCodes.unauthorized, 'Sign in to continue.');
}

/// The authenticated user lacks permission for this action (HTTP 403, code
/// `forbidden`).
final class ForbiddenException extends AppException {
  /// Creates a forbidden exception with the client-facing [message].
  const ForbiddenException([
    String message = 'You do not have permission to perform this action.',
  ]) : super(403, ApiErrorCodes.forbidden, message);
}

/// A request carrying an AMBIENT credential could not prove it is not a
/// cross-site drive (HTTP 403, code `csrf`).
///
/// Two request shapes land here, and they accept different proofs:
/// * a MUTATING method (POST/PUT/PATCH/DELETE) on a session, without
///   `X-Requested-With: SaltToTaste` — the header is the only proof
///   accepted, because a cross-site form submission is a mutation too;
/// * a side-effectful GET (`admin/logs`, `admin/logs/export`,
///   `nutrition/search`, `backups/<name>`, `import/candidates`) carrying
///   neither that header NOR a `Sec-Fetch-Site` the browser itself stamped
///   as not cross-site (`same-origin` or `none`). The second proof exists
///   because the app opens two of those by top-level navigation, which
///   cannot carry a custom header.
///
/// A request authenticated by `Authorization: Bearer` — a PAT, or a session
/// token sent the way the login response hands it to non-browser clients —
/// never reaches the GET guard: a browser cannot attach that header
/// ambiently, so it is not the shape either guard exists to stop.
final class CsrfException extends AppException {
  /// Creates a CSRF exception naming both accepted proofs.
  const CsrfException()
    : super(
        403,
        ApiErrorCodes.csrf,
        'This request must prove it is not cross-site: send the header '
        '"X-Requested-With: SaltToTaste", or (on a side-effectful GET) '
        'make it a same-origin request. Bearer tokens are exempt.',
      );
}

/// The account must change its password before using this endpoint
/// (HTTP 403, code `password_change_required`).
final class PasswordChangeRequiredException extends AppException {
  /// Creates a password-change-required exception.
  const PasswordChangeRequiredException()
    : super(
        403,
        ApiErrorCodes.passwordChangeRequired,
        'You must change your password before continuing.',
      );
}

/// The request conflicts with existing state, e.g. a duplicate username
/// (HTTP 409, code `conflict`).
final class ConflictException extends AppException {
  /// Creates a conflict exception with the client-facing [message].
  const ConflictException(String message)
    : super(409, ApiErrorCodes.conflict, message);
}

/// Too many requests of a rate-limited kind — text search, presently (HTTP
/// 429, code `rate_limited`). Distinct from [LockedException], which is a
/// sign-in-failure lockout; the error handler advertises [retryAfterSeconds]
/// as a `Retry-After` header.
final class TooManyRequestsException extends AppException {
  /// Creates the exception advertising the remaining wait in
  /// [retryAfterSeconds].
  TooManyRequestsException(this.retryAfterSeconds)
    : super(
        429,
        ApiErrorCodes.rateLimited,
        'Too many requests. Try again in $retryAfterSeconds seconds.',
      );

  /// Whole seconds (rounded up) until another request is allowed.
  final int retryAfterSeconds;
}

/// Too many failed sign-in attempts for this account from this address
/// (HTTP 429, code `locked`).
final class LockedException extends AppException {
  /// Creates a locked exception advertising the remaining lockout in
  /// [retryAfterSeconds].
  LockedException(this.retryAfterSeconds)
    : super(
        429,
        ApiErrorCodes.locked,
        'Too many failed attempts. '
        'Try again in $retryAfterSeconds seconds.',
      );

  /// Whole seconds (rounded up) until another attempt is allowed.
  final int retryAfterSeconds;
}
