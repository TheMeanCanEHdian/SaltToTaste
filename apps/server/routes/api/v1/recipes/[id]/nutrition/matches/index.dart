import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/http/path_params.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/nutrition/provider.dart';

/// `GET /api/v1/recipes/<id-or-slug>/nutrition/matches` (any auth) — one
/// entry per ingredient line: the stored match decision plus ranked
/// candidates for the review sheet's re-pick list.
Future<Response> onRequest(RequestContext context, String rawId) async {
  final id = decodePathParam(rawId);
  requireGet(context);
  requireUser(context);
  final db = context.read<SaltDatabase>();
  final found = db.recipeByIdOrSlug(id);
  if (found == null) {
    throw NotFoundException('recipe not found: $id');
  }
  return Response.json(
    body: await matchesBody(
      db,
      context.read<NutritionProvider>(),
      found.recipe,
    ),
  );
}
