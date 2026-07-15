import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/recipe_handlers.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';

/// `GET /api/v1/recipes/<id-or-slug>` -> the full recipe document:
/// `{"recipe": {...}, "source_slug": s, "hero_image_url": u | null}`.
///
/// 404 envelope when no recipe matches; any other method gets a 405
/// envelope.
Response onRequest(RequestContext context, String id) {
  if (context.request.method != HttpMethod.get) {
    return errorResponse(
      statusCode: HttpStatus.methodNotAllowed,
      code: 'method_not_allowed',
      message: 'Only GET is allowed for /api/v1/recipes/<id>.',
      requestId: requestIdOf(context),
    );
  }
  return Response.json(body: recipeDetail(context.read<SaltDatabase>(), id));
}
