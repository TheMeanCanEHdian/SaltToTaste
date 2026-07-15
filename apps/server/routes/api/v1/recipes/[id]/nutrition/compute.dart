import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';

/// `POST /api/v1/recipes/<id-or-slug>/nutrition/compute` (admin, full
/// scope) — match every ingredient line against FoodData Central and store
/// the per-serving totals. User overrides on unchanged lines survive.
///
/// Synchronous: a typical recipe costs a handful of (cached, rate-limited)
/// FDC requests. `503`-flavored validation when no API key is configured.
Future<Response> onRequest(RequestContext context, String id) async {
  requireMethods(context, {HttpMethod.post});
  final user = requireUser(context);
  requireCsrf(context, user);
  requireWrite(context);
  final db = context.read<SaltDatabase>();
  final found = db.recipeByIdOrSlug(id);
  if (found == null) {
    throw NotFoundException('recipe not found: $id');
  }
  try {
    await matchAndCompute(
      db,
      context.read<NutritionProvider>(),
      found.recipe,
    );
  } on NutritionProviderException catch (exception) {
    throw ValidationException(exception.message);
  }
  return Response.json(body: nutritionBody(db, found.recipe));
}
