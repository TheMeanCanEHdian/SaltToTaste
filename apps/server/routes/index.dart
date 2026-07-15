import 'package:dart_frog/dart_frog.dart';

/// Minimal service-identity endpoint: `GET /` -> `{"name": "salt_server"}`.
Response onRequest(RequestContext context) {
  return Response.json(body: {'name': 'salt_server'});
}
