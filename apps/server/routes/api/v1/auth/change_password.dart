import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `POST /api/v1/auth/change_password` `{current_password?, new_password}`
/// -> replaces the caller's password and deletes their other sessions.
///
/// Allowed while a password change is pending (that is its purpose;
/// `current_password` is then not required). Requires the anti-CSRF header;
/// PATs may not change passwords (403).
Future<Response> onRequest(RequestContext context) async {
  requirePost(context);
  final user = requireUserAllowingPasswordChange(context);
  requireCsrf(context, user);
  final body = await readJsonBody(context.request.json);
  final result = await changePassword(
    context.read<SaltDatabase>(),
    context.read<AuthRuntime>(),
    user,
    body,
  );
  return Response.json(body: result);
}
