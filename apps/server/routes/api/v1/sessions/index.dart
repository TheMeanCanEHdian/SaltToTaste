import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/token_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `GET /api/v1/sessions` — the caller's active sessions (the current one
/// flagged), for the Account settings tab.
Response onRequest(RequestContext context) {
  requireGet(context);
  final actor = requireUser(context);
  return Response.json(
    body: listSessionsHandler(context.read<SaltDatabase>(), actor),
  );
}
