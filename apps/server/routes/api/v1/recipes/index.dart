import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/recipe_handlers.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';

/// `GET /api/v1/recipes?page=&limit=` -> one page of recipe cards:
/// `{"items": [...], "total": n, "page": p, "limit": l}`.
///
/// Any other method gets a 405 error envelope.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return errorResponse(
      statusCode: HttpStatus.methodNotAllowed,
      code: 'method_not_allowed',
      message: 'Only GET is allowed for /api/v1/recipes.',
      requestId: requestIdOf(context),
    );
  }
  final params = parseListParams(context.request.uri.queryParameters);
  return Response.json(
    body: listRecipes(
      context.read<SaltDatabase>(),
      page: params.page,
      limit: params.limit,
    ),
  );
}
