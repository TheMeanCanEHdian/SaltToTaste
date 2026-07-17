import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/admin_handlers.dart';
import 'package:salt_server/src/handlers/recipe_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `GET /api/v1/admin/recipe_review?issue=&page=&limit=` (admin) — the recipe
/// data-quality report: which recipes are missing or have incomplete data,
/// grouped by issue. `issue` narrows the list to one category.
Future<Response> onRequest(RequestContext context) async {
  requireMethods(context, {HttpMethod.get});
  requireAdmin(context);
  final db = context.read<SaltDatabase>();
  final query = context.request.uri.queryParameters;
  final params = parseListParams(query);
  return Response.json(
    body: recipeReviewHandler(
      db,
      issue: query['issue'],
      page: params.page,
      limit: params.limit,
    ),
  );
}
