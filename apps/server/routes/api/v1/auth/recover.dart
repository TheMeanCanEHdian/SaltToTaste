import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `POST /api/v1/auth/recover` `{recovery_code, username, new_password}` ->
/// resets (or creates) that account as an enabled admin and signs it in:
/// `{"token": t, "user": {"id", "username", "role"}}` plus the session
/// cookie.
///
/// Unauthenticated: it has to work while every admin is locked out. The code
/// comes from `salt_server:recover` on the server host (`/app/recover` in the
/// container). 403 envelope when no code is pending or it expired; 422 on a
/// wrong code or invalid username/password; 423 once the per-IP rate limit
/// trips.
Future<Response> onRequest(RequestContext context) async {
  requireMethods(context, {HttpMethod.post});
  final body = await readJsonBody(context.request);
  final result = await recoverAdmin(
    context.read<SaltDatabase>(),
    context.read<AuthRuntime>(),
    body,
    clientIp: clientIp(context),
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
