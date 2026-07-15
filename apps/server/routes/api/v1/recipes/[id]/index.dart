import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/recipe_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `GET /api/v1/recipes/<id-or-slug>` -> the full recipe document:
/// `{"recipe": {...}, "source_slug": s, "hero_image_url": u | null}`.
/// Requires auth.
///
/// 404 envelope when no recipe matches.
Response onRequest(RequestContext context, String id) {
  requireUser(context);
  requireGet(context);
  return Response.json(body: recipeDetail(context.read<SaltDatabase>(), id));
}
