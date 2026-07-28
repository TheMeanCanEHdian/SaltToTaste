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
  final query = context.request.uri.queryParameters['q']?.trim() ?? '';
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
      body: await foodSearchBody(db, context.read<NutritionProvider>(), query),
    );
    // A provider failure (rejected key, drained hourly budget, FDC outage)
    // is an expected, actionable condition — a 422 with the provider's own
    // message, exactly like the sibling nutrition routes, never a 500
    // (review B15).
  } on NutritionProviderException catch (error) {
    throw ValidationException(error.message);
  }
}
