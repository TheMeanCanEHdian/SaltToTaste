import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';

/// `GET /api/v1/recipes/<id-or-slug>/nutrition` (any auth) — the computed
/// per-serving label data (`{"status": "none"}` before the first compute;
/// `"stale"` when the ingredients changed since).
///
/// `PUT {serving_basis}` (admin, full scope) — change the per-serving
/// divisor and recompute instantly from the stored matches (no FDC calls).
Future<Response> onRequest(RequestContext context, String id) async {
  requireMethods(context, {HttpMethod.get, HttpMethod.put});
  final user = requireUser(context);
  final db = context.read<SaltDatabase>();

  if (context.request.method == HttpMethod.get) {
    final found = db.recipeByIdOrSlug(id);
    if (found == null) {
      throw NotFoundException('recipe not found: $id');
    }
    return Response.json(body: nutritionBody(db, found.recipe));
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
  try {
    // Mostly cache hits, but a food evicted from the cache re-fetches —
    // which can fail (no key, drained budget).
    await recomputeTotals(
      db,
      context.read<NutritionProvider>(),
      found.recipe,
      servingBasis: basis.toInt(),
    );
  } on NutritionProviderException catch (exception) {
    throw ValidationException(exception.message);
  }
  return Response.json(body: nutritionBody(db, found.recipe));
}
