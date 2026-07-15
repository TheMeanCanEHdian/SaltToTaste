import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `POST /api/v1/auth/logout` -> deletes the current session and clears the
/// session cookie. Allowed while a password change is pending; requires the
/// anti-CSRF header on session requests. A PAT cannot log out (422).
Response onRequest(RequestContext context) {
  requirePost(context);
  final user = requireUserAllowingPasswordChange(context);
  requireCsrf(context, user);
  final body = logoutUser(context.read<SaltDatabase>(), user);
  return Response.json(
    body: body,
    headers: {
      'Set-Cookie': expiredSessionCookie(secure: isSecureRequest(context)),
    },
  );
}
