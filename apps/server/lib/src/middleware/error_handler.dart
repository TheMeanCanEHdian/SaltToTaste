import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_shared/salt_shared.dart';

final Logger _log = Logger('http');

/// Middleware that converts exceptions into the uniform error envelope
/// `{"error": {"code", "message", "request_id"}}`.
///
/// * [AppException] becomes a response with its status code and error code
///   (a [MethodNotAllowedException] also gets an `Allow` header).
/// * Anything else is logged at SEVERE (with stack trace) through
///   [throttle] and becomes an opaque 500 `internal` envelope — clients
///   never see stack traces.
/// * A 404 response from the inner handler is the router's unmatched-route
///   fallback (feature code throws [NotFoundException] instead of returning a
///   404), so it is rewrapped into a `not_found` envelope. This is keyed on
///   the status code, not the framework's fallback body text.
Middleware errorHandler({SevereThrottle? throttle}) {
  final records = throttle ?? severeThrottle;
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
          extra: exception.extra,
        );
      } catch (error, stackTrace) {
        // Same two rules as the request logger, because the same attacker
        // chooses the same path: the path goes through `loggedPath` (uncapped,
        // it evicted the exception and every stack frame out of the record the
        // store had just started keeping — review P1/P2), and the request id
        // travels as DATA, never as text the store has to parse back out (S8).
        records.severe(
          _log,
          'Unhandled error on ${context.request.method.value} '
          '${loggedPath(context.request.uri.path)}',
          requestId,
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

/// v108 V1 (Run 085/086): THE throttle of the persisting catch-alls — the
/// routes arm's [errorHandler] and `buildOutermostMiddleware`'s (v107 U1
/// throttled only the outer one; a truncated JSON body on the anonymous
/// login wrote a full stack per request one layer down). Keyed per throw
/// site — the error's type and its stack's top frame, never caller text
/// (the attacker's path would make every request distinct and the map
/// unbounded). A record is written when the site is new, its [every]
/// window has passed, or the clock went BACKWARDS (a stepped wall clock
/// never silences a site for the size of the step); every written record
/// carries its stack (at most one per site per window — a rotated store
/// still holds a frame), a re-opened site's naming how many it suppressed.
/// The bookkeeping is written AFTER the record.
class SevereThrottle {
  /// A throttle reading [now] (tests pass a fake clock).
  SevereThrottle({this.now = DateTime.now, this.every = _severeEvery});

  /// The clock.
  final DateTime Function() now;

  /// The window per site.
  final Duration every;

  final Map<String, ({DateTime at, int suppressed})> _seen = {};

  /// Writes [message]'s SEVERE record on [log] with [error] and its
  /// [stackTrace], or counts it suppressed.
  void severe(
    Logger log,
    String message,
    String? requestId,
    Object error,
    StackTrace stackTrace,
  ) {
    final site = '${error.runtimeType} ${'$stackTrace'.split('\n').first}';
    final at = now();
    final last = _seen[site];
    final gap = last == null ? null : at.difference(last.at);
    if (last != null && !gap!.isNegative && gap < every) {
      _seen[site] = (at: last.at, suppressed: last.suppressed + 1);
      return;
    }
    log.severe(
      RequestLogMessage(
        '$message'
        '${last == null ? '' : ' (${last.suppressed} like it suppressed)'}',
        requestId,
      ),
      error,
      stackTrace,
    );
    _seen[site] = (at: at, suppressed: 0);
  }
}

/// The SEVERE throttle window (v107 U1).
const Duration _severeEvery = Duration(seconds: 60);

/// The one [SevereThrottle] both catch-alls share in production (built at
/// library load, so no value swapped in `run()` is ever captured).
final SevereThrottle severeThrottle = SevereThrottle();

/// Builds an error-envelope JSON response from the shared [ApiError] DTO,
/// optionally with extra [headers] and [extra] keys of the `error` object.
Response errorResponse({
  required int statusCode,
  required String code,
  required String message,
  String? requestId,
  Map<String, String> headers = const {},
  Map<String, Object?> extra = const {},
}) {
  final error = ApiError(code: code, message: message, requestId: requestId);
  return Response.json(
    statusCode: statusCode,
    body: {
      'error': {...error.toMap(), ...extra},
    },
    headers: headers,
  );
}
