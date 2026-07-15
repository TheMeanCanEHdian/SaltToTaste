import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';

/// Liveness probe: `GET /healthz` -> `200 {"status": "ok"}`. No auth.
///
/// Any other method gets a 405 error envelope.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return errorResponse(
      statusCode: HttpStatus.methodNotAllowed,
      code: 'method_not_allowed',
      message: 'Only GET is allowed for /healthz.',
      requestId: requestIdOf(context),
    );
  }
  return Response.json(body: {'status': 'ok'});
}
