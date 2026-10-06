import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/http/path_params.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';

/// `PUT /api/v1/recipes/<id-or-slug>/nutrition/matches/<pos>` (admin, full
/// scope) — override one line's match: `{fdc_id}` re-picks the food,
/// `{grams}` sets the amount by hand, `{confirmed: true}` blesses the auto
/// match, `{skipped: true}` excludes the line. Totals recompute instantly.
/// An optional `raw` (the line's text as the client saw it) guards against
/// a save since: 409 `line_moved` when the line at <pos> reads otherwise.
/// v44: `?section=<title>` decides a line of that section (404 "No section
/// with that title." for none); `{child, section}` picks a section.
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
  // This lookup resolves the slug and answers 404; the write itself reads
  // the STORED recipe (applyMatchOverride), so a save landing while the
  // body streams in is the version it lays out against either way.
  final body = await readJsonBody(context.request);
  final found = db.recipeByIdOrSlug(id);
  if (found == null) {
    throw NotFoundException('recipe not found: $id');
  }
  final target = routeRecipeOf(
    db,
    found.recipe,
    context.request.uri.queryParameters['section'],
  );
  final provider = context.read<NutritionProvider>();
  final AppliedToOthers? applied;
  try {
    applied = await applyMatchOverride(
      db,
      provider,
      target,
      position,
      body,
      decidedBy: user.id,
    );
  } on NutritionProviderException catch (exception) {
    throw ValidationException(exception.message);
  }
  final recipe = nutritionRecipeOf(db, target.id)?.recipe ?? target;
  return Response.json(
    body: {
      ...await matchesBody(db, provider, recipe),
      if (applied != null) 'applied': appliedJson(applied),
    },
  );
}
