import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/http/path_params.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// Maximum length of a personal note body.
const int _maxNoteLength = 20000;

/// The caller's personal note on a recipe — private per-user data that
/// never touches the shared YAML.
///
/// `GET /api/v1/recipes/<id-or-slug>/note` -> `{"note": string | null}`.
/// `PUT` `{note: string}` sets it (an empty string deletes, like DELETE).
/// `DELETE` removes it. All roles may write their own note; like favorites,
/// a `read`-scoped PAT may too (personal data, not shared state).
Future<Response> onRequest(RequestContext context, String rawId) async {
  final id = decodePathParam(rawId);
  requireMethods(
    context,
    {HttpMethod.get, HttpMethod.put, HttpMethod.delete},
  );
  final user = requireUser(context);
  final db = context.read<SaltDatabase>();

  final found = db.recipeByIdOrSlug(id);
  if (found == null) {
    throw NotFoundException('recipe not found: $id');
  }
  final recipeId = found.recipe.id;

  switch (context.request.method) {
    case HttpMethod.get:
      return Response.json(
        body: {'note': db.noteFor(userId: user.id, recipeId: recipeId)},
      );
    case HttpMethod.put:
      requireCsrf(context, user);
      final body = await readJsonBody(context.request);
      final note = body['note'];
      if (note is! String) {
        throw const ValidationException("'note' must be a string.");
      }
      if (note.length > _maxNoteLength) {
        throw const ValidationException(
          "'note' must be at most $_maxNoteLength characters.",
        );
      }
      if (note.isEmpty) {
        db.deleteNote(userId: user.id, recipeId: recipeId);
        return Response.json(body: {'note': null});
      }
      db.setNote(userId: user.id, recipeId: recipeId, body: note);
      return Response.json(body: {'note': note});
    // requireMethods narrowed the method set; anything left is DELETE.
    // ignore: no_default_cases
    default:
      requireCsrf(context, user);
      db.deleteNote(userId: user.id, recipeId: recipeId);
      return Response.json(body: {'note': null});
  }
}
