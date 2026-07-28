import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/http/path_params.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/services/image_ingest.dart';

/// `POST /api/v1/recipes/<id-or-slug>/images/store` (admin, full scope) —
/// upload a photo as the raw request body and get back its stored
/// `images/<file>` reference WITHOUT attaching it to the recipe.
///
/// Unlike the hero/gallery upload, this does not touch the recipe document: the
/// editor drops the returned reference into a technique step's `image` and
/// persists it with the recipe's own PUT. Same magic-byte + 25 MB validation.
/// Responds `{"reference": "images/<file>"}`.
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
  final bytes = await collectImageBytes(context.request.bytes());
  final reference = saveRecipeImage(
    config: config,
    sourceSlug: found.sourceSlug,
    recipeId: found.recipe.id,
    bytes: bytes,
  );
  return Response.json(statusCode: 201, body: {'reference': reference});
}
