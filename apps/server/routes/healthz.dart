import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/http/method_guard.dart';

/// Liveness probe: `GET /healthz` -> `200 {"status": "ok", "setup_required":
/// bool}`. No auth — `setup_required` tells a fresh client to show the
/// first-run setup screen (it only reveals whether the instance is claimed).
Response onRequest(RequestContext context) {
  requireGet(context);
  return Response.json(
    body: {
      'status': 'ok',
      'setup_required': context.read<SaltDatabase>().userCount() == 0,
    },
  );
}
