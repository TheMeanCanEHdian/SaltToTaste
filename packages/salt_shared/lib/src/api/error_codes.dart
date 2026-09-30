/// The stable machine-readable error codes carried by [ApiError.code].
///
/// Shared by the server (which emits them) and the Flutter client (which maps
/// them to typed failures) so neither side matches on ad-hoc string literals.
/// The human-facing catalog lives in docs/API.md.
abstract final class ApiErrorCodes {
  /// A parameter or body value is invalid (HTTP 422).
  static const String validation = 'validation';

  /// The requested resource (or route) does not exist (HTTP 404).
  static const String notFound = 'not_found';

  /// The route exists but the HTTP method is not supported (HTTP 405).
  static const String methodNotAllowed = 'method_not_allowed';

  /// An unhandled server error; details appear only in the server logs
  /// (HTTP 500).
  static const String internal = 'internal';

  /// No valid credential accompanied the request — sign in (HTTP 401).
  static const String unauthorized = 'unauthorized';

  /// The authenticated user lacks permission for this action (HTTP 403).
  static const String forbidden = 'forbidden';

  /// A mutating session request is missing the anti-CSRF
  /// `X-Requested-With` header (HTTP 403).
  static const String csrf = 'csrf';

  /// The account must change its password before using this endpoint
  /// (HTTP 403).
  static const String passwordChangeRequired = 'password_change_required';

  /// Too many failed sign-in attempts; retry after the delay given in the
  /// message (HTTP 429).
  static const String locked = 'locked';

  /// Too many requests of a rate-limited kind (e.g. text search); retry after
  /// the `Retry-After` header (HTTP 429). Distinct from [locked], which is a
  /// sign-in-failure lockout.
  static const String rateLimited = 'rate_limited';

  /// The request conflicts with existing state, e.g. a duplicate username
  /// (HTTP 409).
  static const String conflict = 'conflict';

  /// A confirm-as-is of a below-gate zero row: its food is a hidden guess,
  /// so confirming it would decide that food library-wide (HTTP 422). Pick
  /// a food, or skip the line.
  static const String zeroRow = 'zero_row';

  /// A nutrition match write naming (`raw`) a line that is no longer at its
  /// position: the recipe was saved since the client read it (HTTP 409).
  /// The envelope carries `position`, where that line is now (or null).
  static const String lineMoved = 'line_moved';
}
