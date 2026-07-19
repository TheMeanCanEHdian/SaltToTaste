import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/services/image_ingest.dart';

/// `POST /api/v1/recipes/<id-or-slug>/images/store_from_url` (admin, full
/// scope) `{url}` — download a photo into the library and get back its stored
/// `images/<file>` reference WITHOUT attaching it to the recipe (the store-only
/// twin of `from_url`, for technique-step images).
///
/// Same SSRF guard (http/https only, public hosts only, redirects re-validated,
/// size/time capped) and magic-byte validation as `from_url`. Responds
/// `{"reference": "images/<file>"}`.
Future<Response> onRequest(RequestContext context, String id) async {
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
  final bytes = await fetchImageFromUrl(url);
  final reference = saveRecipeImage(
    config: config,
    sourceSlug: found.sourceSlug,
    recipeId: found.recipe.id,
    bytes: bytes,
  );
  return Response.json(statusCode: 201, body: {'reference': reference});
}
