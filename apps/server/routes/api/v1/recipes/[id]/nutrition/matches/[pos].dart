import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/http/path_params.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/nutrition/provider.dart';

/// `PUT /api/v1/recipes/<id-or-slug>/nutrition/matches/<pos>` (admin, full
/// scope) — override one line's match: `{fdc_id}` re-picks the food,
/// `{grams}` sets the amount by hand, `{confirmed: true}` blesses the auto
/// match, `{skipped: true}` excludes the line. Totals recompute instantly.
Future<Response> onRequest(
  RequestContext context,
  String rawId,
  String pos,
) async {
  final id = decodePathParam(rawId);
  requireMethods(context, {HttpMethod.put});
  final user = requireUser(context);
  requireCsrf(context, user);
  requireWrite(context);
  final position = int.tryParse(pos);
  if (position == null || position < 0) {
    throw const ValidationException('Position must be a non-negative index.');
  }
  final db = context.read<SaltDatabase>();
  final found = db.recipeByIdOrSlug(id);
  if (found == null) {
    throw NotFoundException('recipe not found: $id');
  }
  final provider = context.read<NutritionProvider>();
  final AppliedToOthers? applied;
  try {
    applied = await applyMatchOverride(
      db,
      provider,
      found.recipe,
      position,
      await readJsonBody(context.request),
    );
  } on NutritionProviderException catch (exception) {
    throw ValidationException(exception.message);
  }
  return Response.json(
    body: {
      ...await matchesBody(db, provider, found.recipe),
      if (applied != null)
        'applied': {
          'recipes': applied.recipes,
          'lines': applied.lines,
          'failed': applied.failed,
        },
    },
  );
}
