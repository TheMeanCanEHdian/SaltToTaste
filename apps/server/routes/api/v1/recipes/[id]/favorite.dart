import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/http/path_params.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `PUT /api/v1/recipes/<id-or-slug>/favorite` marks the recipe as one of
/// the caller's favorites; `DELETE` unmarks it. Both are idempotent and
/// return `{"favorite": bool}`.
///
/// Favorites are personal data: members may write them, and (unlike server
/// data) a `read`-scoped PAT may too — the documented scope model reserves
/// `full` for mutations of shared state.
Response onRequest(RequestContext context, String rawId) {
  final id = decodePathParam(rawId);
  requireMethods(context, {HttpMethod.put, HttpMethod.delete});
  final user = requireUser(context);
  requireCsrf(context, user);
  final db = context.read<SaltDatabase>();

  final found = db.recipeByIdOrSlug(id);
  if (found == null) {
    throw NotFoundException('recipe not found: $id');
  }
  final favorite = context.request.method == HttpMethod.put;
  db.setFavorite(
    userId: user.id,
    recipeId: found.recipe.id,
    favorite: favorite,
  );
  return Response.json(body: {'favorite': favorite});
}
