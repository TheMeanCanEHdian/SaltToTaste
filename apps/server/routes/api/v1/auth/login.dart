import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `POST /api/v1/auth/login` `{username, password, remember?}` -> signs in:
/// `{"token": t, "user": {"id", "username", "role",
/// "must_change_password"}}` plus the session cookie.
///
/// Failures are uniform 422 envelopes; repeated failures per IP+username
/// escalate to 429 `locked` envelopes with the retry delay in the message.
Future<Response> onRequest(RequestContext context) async {
  requireMethods(context, {HttpMethod.post});
  final body = await readJsonBody(context.request);
  final result = await login(
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
