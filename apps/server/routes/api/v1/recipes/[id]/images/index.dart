import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/recipe_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/http/path_params.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/services/image_ingest.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart' as edit;

/// `POST /api/v1/recipes/<id-or-slug>/images?role=hero|gallery` (admin,
/// full scope) — upload a photo as the raw request body.
///
/// The body must be a real JPEG/PNG/WebP (validated by magic bytes, 25 MB
/// cap enforced while reading); the server generates the stored file name.
/// `role=hero` (default) replaces the hero image, `role=gallery` appends.
/// Responds with the updated detail body.
Future<Response> onRequest(RequestContext context, String rawId) async {
  final id = decodePathParam(rawId);
  requireMethods(context, {HttpMethod.post});
  final user = requireUser(context);
  requireCsrf(context, user);
  requireWrite(context);
  final db = context.read<SaltDatabase>();
  final config = context.read<ServerConfig>();

  final found = db.recipeByIdOrSlug(id);
  if (found == null) {
    throw NotFoundException('recipe not found: $id');
  }
  final role = context.request.uri.queryParameters['role'] ?? 'hero';
  // Role first: an invalid role must not leave an orphan image on disk.
  edit.requireImageRole(role);
  final bytes = await collectImageBytes(context.request.bytes());
  final reference = saveRecipeImage(
    config: config,
    sourceSlug: found.sourceSlug,
    recipeId: found.recipe.id,
    bytes: bytes,
  );
  final result = edit.attachRecipeImage(
    db,
    config,
    found.recipe.id,
    reference: reference,
    role: role,
  );
  return Response.json(
    statusCode: 201,
    body: recipeDetailBody(
      result.recipe,
      result.sourceSlug,
      favorite: db.isFavorite(userId: user.id, recipeId: result.recipe.id),
      note: db.noteFor(userId: user.id, recipeId: result.recipe.id),
    ),
  );
}
