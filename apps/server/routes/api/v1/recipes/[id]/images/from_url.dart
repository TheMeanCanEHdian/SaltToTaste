import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/handlers/recipe_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/http/path_params.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/services/image_ingest.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart' as edit;

/// `POST /api/v1/recipes/<id-or-slug>/images/from_url` (admin, full scope)
/// `{url, role?}` — download a photo from the web into the library.
///
/// The fetch is SSRF-guarded (http/https only, public hosts only, redirects
/// re-validated, size/time capped) and the payload must pass the same
/// magic-byte validation as an upload. `role` is `hero` (default) or
/// `gallery`. Responds with the updated detail body.
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
  final body = await readJsonBody(context.request);
  final url = body['url'];
  if (url is! String || url.trim().isEmpty) {
    throw const ValidationException("'url' is required.");
  }
  final role = body['role'] ?? 'hero';
  if (role is! String) {
    throw const ValidationException("'role' must be a string.");
  }
  // Role first: an invalid role must not leave an orphan image on disk.
  edit.requireImageRole(role);

  // Scheme/host/port/path only. The full URL used to be stored verbatim, so
  // a presigned download URL wrote its token into the exported YAML
  // (2026-07-28 review, item 1).
  final credit = creditUrl(url);
  final bytes = await fetchImageFromUrl(url);
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
    // Default the free-text photo credit to where the photo came from —
    // only when no credit was ever written (review Y6). Null leaves it
    // alone, which is the right answer for a URL that yields no safe form.
    creditIfEmpty: credit.isEmpty ? null : credit,
  );
  return Response.json(
    statusCode: 201,
    body: recipeDetailBody(
      result.recipe,
      result.sourceSlug,
      // Attaching a photo changes the content hash; hand the editor the
      // fresh one so its next save's precondition holds (review B11).
      baseHash: db.contentHashOf(result.recipe.id),
      favorite: db.isFavorite(userId: user.id, recipeId: result.recipe.id),
      note: db.noteFor(userId: user.id, recipeId: result.recipe.id),
    ),
  );
}
