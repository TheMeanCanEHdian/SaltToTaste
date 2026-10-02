import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/http/path_params.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/nutrition/engine.dart';

/// `GET /api/v1/recipes/<id-or-slug>/nutrition` (any auth) — the computed
/// per-serving label data (`{"status": "none"}` before the first compute;
/// `"stale"` when the ingredients changed since).
///
/// `PUT {serving_basis}` (admin, full scope) — change the per-serving
/// divisor: the stored per-recipe totals divided anew (no FDC call, no row
/// or cache read; the stamp, status and counts unchanged).
Future<Response> onRequest(RequestContext context, String rawId) async {
  final id = decodePathParam(rawId);
  requireMethods(context, {HttpMethod.get, HttpMethod.put});
  final user = requireUser(context);
  final db = context.read<SaltDatabase>();

  if (context.request.method == HttpMethod.get) {
    final found = db.recipeByIdOrSlug(id);
    if (found == null) {
      throw NotFoundException('recipe not found: $id');
    }
    return Response.json(
      body: nutritionBody(db, found.recipe, forAdmin: user.isAdmin),
    );
  }

  // Permission before existence: every mutation in the API 403s a member
  // or read-scoped PAT regardless of the target (the permission-matrix
  // contract).
  requireCsrf(context, user);
  requireWrite(context);
  final found = db.recipeByIdOrSlug(id);
  if (found == null) {
    throw NotFoundException('recipe not found: $id');
  }
  final body = await readJsonBody(context.request);
  final basis = body['serving_basis'];
  if (basis is! num || basis < 1 || basis > 1000) {
    throw const ValidationException(
      "'serving_basis' must be a number between 1 and 1000.",
    );
  }
  if (db.nutritionFor(found.recipe.id) == null) {
    throw const ValidationException(
      'Compute nutrition first, then adjust the serving basis.',
    );
  }
  // Pure arithmetic over the stored per-recipe totals ([rebaseNutrition];
  // v27, RULE A): no row, food or cache is read, so nothing here can
  // fetch, fail on FDC, drop a food or move the stamp (Run 057 Opus critic
  // 3; the verifier's D1: a re-read of the rows against the caches dropped
  // 0857's flour once its stand-in left the search cache — complete ->
  // partial, fresh -> stale).
  rebaseNutrition(db, found.recipe.id, basis.toInt());
  return Response.json(
    body: nutritionBody(db, found.recipe, forAdmin: user.isAdmin),
  );
}
