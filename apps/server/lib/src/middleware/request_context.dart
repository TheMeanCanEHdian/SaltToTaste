import 'dart:math';

import 'package:dart_frog/dart_frog.dart';

/// Name of the response header carrying the per-request id.
const String requestIdHeader = 'X-Request-Id';

/// Wrapper around the per-request id string.
///
/// Provided into the request context by [requestIdProvider]; the wrapper
/// type avoids colliding with any other `String` provider.
class RequestId {
  /// Wraps a generated request id.
  const RequestId(this.value);

  /// The id: 16 lowercase hex characters, CSPRNG-generated.
  final String value;
}

/// Middleware that generates a fresh request id for every request, exposes
/// it as [RequestId] via `context.read<RequestId>()`, and stamps the
/// [requestIdHeader] onto the response.
///
/// Wired outside the error handler so that error envelopes carry a matching
/// `request_id` and even error responses get the header.
Middleware requestIdProvider() {
  return (handler) {
    return (context) async {
      final id = _generateRequestId();
      final response = await handler(context.provide(() => RequestId(id)));
      return response.copyWith(headers: {requestIdHeader: id});
    };
  };
}

/// Reads the current request id from [context], or returns null when
/// [requestIdProvider] is not installed (e.g. bare unit tests).
String? requestIdOf(RequestContext context) {
  try {
    return context.read<RequestId>().value;
    // dart_frog signals "not provided" with a StateError by design; there is
    // no non-throwing probe on RequestContext.
    // ignore: avoid_catching_errors
  } on StateError {
    return null;
  }
}

final Random _random = Random.secure();

String _generateRequestId() {
  final buffer = StringBuffer();
  for (var i = 0; i < 8; i++) {
    buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
