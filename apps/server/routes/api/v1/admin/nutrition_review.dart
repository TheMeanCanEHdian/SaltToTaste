import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/admin_handlers.dart';
import 'package:salt_server/src/handlers/recipe_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `GET /api/v1/admin/nutrition_review?bucket=&page=&limit=` (admin) — the
/// cross-recipe queue of ingredient-match lines that still need a look
/// (wrong/no match, no grams, low confidence), worst first. `bucket` narrows
/// the list to one triage bucket.
Future<Response> onRequest(RequestContext context) async {
  requireMethods(context, {HttpMethod.get});
  requireAdmin(context);
  final db = context.read<SaltDatabase>();
  final query = context.request.uri.queryParameters;
  final params = parseListParams(query);
  return Response.json(
    body: nutritionReviewHandler(
      db,
      bucket: query['bucket'],
      page: params.page,
      limit: params.limit,
    ),
  );
}
