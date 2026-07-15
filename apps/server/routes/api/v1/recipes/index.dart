import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/recipe_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `GET /api/v1/recipes?page=&limit=` -> one page of recipe cards:
/// `{"items": [...], "total": n, "page": p, "limit": l}`. Requires auth.
Response onRequest(RequestContext context) {
  requireUser(context);
  requireGet(context);
  final params = parseListParams(context.request.uri.queryParameters);
  return Response.json(
    body: listRecipes(
      context.read<SaltDatabase>(),
      page: params.page,
      limit: params.limit,
      query: context.request.uri.queryParameters['q'],
    ),
  );
}
