import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/handlers/user_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `PATCH /api/v1/users/<id>` (admin) `{role? | disabled?}` — change a
/// user's role or disable/enable the account (never your own).
Future<Response> onRequest(RequestContext context, String id) async {
  requireMethods(context, {HttpMethod.patch});
  final actor = requireAdmin(context);
  requireCsrf(context, actor);

  final userId = int.tryParse(id);
  if (userId == null) {
    throw const ValidationException('User id must be an integer.');
  }
  final body = await readJsonBody(context.request.json);
  final role = body['role'];
  final disabled = body['disabled'];
  if (role is! String? || disabled is! bool?) {
    throw const ValidationException(
      "'role' must be a string and 'disabled' a boolean.",
    );
  }
  if (role == null && disabled == null) {
    throw const ValidationException("Provide 'role' and/or 'disabled'.");
  }
  return Response.json(
    body: patchUserHandler(
      context.read<SaltDatabase>(),
      actor,
      userId,
      role: role,
      disabled: disabled,
    ),
  );
}
