import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/token_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `DELETE /api/v1/sessions/<id>` — sign out one of the caller's sessions
/// (deleting the current one acts as logout).
Response onRequest(RequestContext context, String id) {
  requireMethods(context, {HttpMethod.delete});
  final actor = requireUser(context);
  requireCsrf(context, actor);
  deleteSessionHandler(context.read<SaltDatabase>(), actor, id);
  return Response(statusCode: HttpStatus.noContent);
}
