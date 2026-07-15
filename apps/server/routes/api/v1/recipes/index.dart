import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/handlers/recipe_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart' as edit;

/// `GET /api/v1/recipes?page=&limit=&q=&favorites=` -> one page of recipe
/// cards `{"items": [...], "total": n, "page": p, "limit": l}` (any auth).
///
/// `POST /api/v1/recipes` `{recipe: {...}}` (admin, full scope) -> 201 with
/// the stored recipe's detail body. The server generates id and slug and
/// exports the canonical YAML to the library.
Future<Response> onRequest(RequestContext context) async {
  requireMethods(context, {HttpMethod.get, HttpMethod.post});
  final user = requireUser(context);
  final db = context.read<SaltDatabase>();

  if (context.request.method == HttpMethod.get) {
    final query = context.request.uri.queryParameters;
    final params = parseListParams(query);
    return Response.json(
      body: listRecipes(
        db,
        page: params.page,
        limit: params.limit,
        query: query['q'],
        viewerId: user.id,
        favoritesOnly: query['favorites'] == 'true',
      ),
    );
  }

  requireCsrf(context, user);
  requireWrite(context);
  final result = edit.createRecipe(
    db,
    context.read<ServerConfig>(),
    edit.recipeObjectOf(await readJsonBody(context.request)),
  );
  return Response.json(
    statusCode: 201,
    // A just-created recipe trivially has no personal data yet; the keys are
    // present so every detail-shaped response looks the same to clients.
    body: recipeDetailBody(result.recipe, result.sourceSlug, favorite: false),
  );
}
