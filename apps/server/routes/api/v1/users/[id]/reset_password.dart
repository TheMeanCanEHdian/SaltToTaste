import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/handlers/user_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `POST /api/v1/users/<id>/reset_password` (admin) — issue a new
/// temporary password (returned once); forces a change at next sign-in and
/// signs the user out everywhere.
Future<Response> onRequest(RequestContext context, String id) async {
  requireMethods(context, {HttpMethod.post});
  final actor = requireAdmin(context);
  requireCsrf(context, actor);

  final userId = int.tryParse(id);
  if (userId == null) {
    throw const ValidationException('User id must be an integer.');
  }
  return Response.json(
    body: await resetPasswordHandler(
      context.read<SaltDatabase>(),
      context.read<AuthRuntime>().hasher,
      actor,
      userId,
    ),
  );
}
