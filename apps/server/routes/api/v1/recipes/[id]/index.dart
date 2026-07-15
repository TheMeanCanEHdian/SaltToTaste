import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/handlers/recipe_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/services/backup_service.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart' as edit;

/// `GET /api/v1/recipes/<id-or-slug>` -> the full recipe document plus the
/// viewer's personal `favorite`/`note` (any auth).
///
/// `PUT` `{recipe: {...}}` (admin, full scope) -> the updated detail body.
/// Editable keys present in the submission replace the stored values (null
/// clears); absent keys are untouched. Saving re-exports the canonical YAML,
/// preserving an unsynced hand edit as a `.conflict-*` copy.
///
/// `DELETE` (admin, full scope) -> 204 after taking a backup; removes the
/// database row and the library YAML.
///
/// 404 envelope when no recipe matches.
Future<Response> onRequest(RequestContext context, String id) async {
  requireMethods(
    context,
    {HttpMethod.get, HttpMethod.put, HttpMethod.delete},
  );
  final user = requireUser(context);
  final db = context.read<SaltDatabase>();

  if (context.request.method == HttpMethod.get) {
    return Response.json(body: recipeDetail(db, id, viewerId: user.id));
  }

  requireCsrf(context, user);
  requireWrite(context);
  final config = context.read<ServerConfig>();

  if (context.request.method == HttpMethod.put) {
    final result = edit.updateRecipe(
      db,
      config,
      id,
      edit.recipeObjectOf(await readJsonBody(context.request)),
    );
    return Response.json(
      body: recipeDetailBody(
        result.recipe,
        result.sourceSlug,
        favorite: db.isFavorite(userId: user.id, recipeId: result.recipe.id),
        note: db.noteFor(userId: user.id, recipeId: result.recipe.id),
      ),
    );
  }

  edit.deleteRecipe(
    db,
    config,
    id,
    beforeDestructive: () =>
        createBackup(db: db, config: config, trigger: 'before-delete'),
  );
  return Response(statusCode: 204);
}
