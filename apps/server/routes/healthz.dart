import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/http/method_guard.dart';

/// Liveness probe: `GET /healthz` -> `200 {"status": "ok"}`. No auth.
Response onRequest(RequestContext context) {
  requireGet(context);
  return Response.json(body: {'status': 'ok'});
}
