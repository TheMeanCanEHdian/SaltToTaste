import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/bootstrap.dart' show fdcApiKeySetting;
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/nutrition/provider.dart';

/// `GET /api/v1/nutrition/search?q=<term>` (admin, full scope) — search USDA
/// FoodData Central for a term and return ranked candidates, so an admin can
/// re-pick a match by hand when none of the auto-found candidates fit.
///
/// Admin + full scope because a cache miss SPENDS the FDC request budget;
/// the per-line `matches` GET stays cache-only so members never can.
Future<Response> onRequest(RequestContext context) async {
  requireGet(context);
  final user = requireAdmin(context);
  requireFullScope(user);
  // Not cross-site drivable: a cache miss spends up to 2 calls of a 900/hr
  // shared FDC budget and writes a cache row, and requireCsrf gates mutating
  // METHODS only. Above every line below it, because the guard exists to stop
  // the COST — including the cache keys an unguarded drive would mint.
  requireNotCrossSite(context);
  final query = context.request.uri.queryParameters['q']?.trim() ?? '';
  // `fresh=true`: bypass the search cache and replace its row — a person
  // asking for a live answer, which costs one FDC request.
  final freshParam = context.request.uri.queryParameters['fresh'];
  if (freshParam != null && freshParam != 'true' && freshParam != 'false') {
    throw const ValidationException("'fresh' must be true or false.");
  }
  final fresh = freshParam == 'true';
  if (query.isEmpty) {
    throw const ValidationException('Pass a search term as ?q=.');
  }
  // Bounded so a caller cannot mint unbounded cache keys.
  if (query.length > 120) {
    throw const ValidationException(
      'Search term is too long (120 characters max).',
    );
  }
  final db = context.read<SaltDatabase>();
  final key = db.getSetting(fdcApiKeySetting);
  if (key == null || key.isEmpty) {
    throw const ValidationException(
      'No FoodData Central API key is configured. Add one in '
      'Settings → Nutrition first (free at api.data.gov/signup).',
    );
  }
  try {
    return Response.json(
      body: await foodSearchBody(
        db,
        context.read<NutritionProvider>(),
        query,
        fresh: fresh,
      ),
    );
    // A provider failure (rejected key, drained hourly budget, FDC outage)
    // is an expected, actionable condition — a 422 with the provider's own
    // message, exactly like the sibling nutrition routes, never a 500
    // (review B15).
  } on NutritionProviderException catch (error) {
    throw ValidationException(error.message);
  }
}
