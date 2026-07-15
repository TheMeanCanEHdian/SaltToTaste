import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `GET /api/v1/auth/me` -> the authenticated principal:
/// `{"user": {"id", "username", "role", "must_change_password", "scope",
/// "via"}}`. Allowed while a password change is pending.
Response onRequest(RequestContext context) {
  requireGet(context);
  final user = requireUserAllowingPasswordChange(context);
  return Response.json(body: currentUserBody(user));
}
