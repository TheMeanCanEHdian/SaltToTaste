import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `POST /api/v1/auth/setup` `{setup_code, username, password}` -> creates
/// the first admin account and signs it in:
/// `{"token": t, "user": {"id", "username", "role"}}` plus the session
/// cookie.
///
/// 403 envelope once any user exists; 422 on a wrong code or invalid
/// username/password.
Future<Response> onRequest(RequestContext context) async {
  requirePost(context);
  final body = await readJsonBody(context.request.json);
  final result = await setupAdmin(
    context.read<SaltDatabase>(),
    context.read<AuthRuntime>(),
    body,
    userAgent: context.request.headers['user-agent'],
  );
  return Response.json(
    body: result.body,
    headers: {
      'Set-Cookie': sessionCookie(
        result.token,
        secure: isSecureRequest(context),
      ),
    },
  );
}
