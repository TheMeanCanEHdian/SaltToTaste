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
}
