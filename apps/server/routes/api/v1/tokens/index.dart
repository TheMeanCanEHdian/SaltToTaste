import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/handlers/token_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `GET /api/v1/tokens` — the caller's personal access tokens.
/// `POST /api/v1/tokens` `{name, scope}` — mint a PAT; the full token value
/// appears only in this response.
Future<Response> onRequest(RequestContext context) async {
  requireMethods(context, {HttpMethod.get, HttpMethod.post});
  final actor = requireUser(context);
  final db = context.read<SaltDatabase>();

  if (context.request.method == HttpMethod.get) {
    return Response.json(
      body: listTokensHandler(
        db,
        actor,
        retentionDays: context.read<ServerConfig>().apiTokenRetentionDays,
      ),
    );
  }

  requireCsrf(context, actor);
  requireFullScope(actor);
  final body = await readJsonBody(context.request);
  return Response.json(
    body: createTokenHandler(
      db,
      actor,
      name: requireStringField(body, 'name'),
      scope: requireStringField(body, 'scope'),
    ),
  );
}
