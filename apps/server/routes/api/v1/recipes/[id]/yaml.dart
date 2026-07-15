import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/recipe_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';

/// `GET /api/v1/recipes/<id-or-slug>/yaml` -> the canonical schema-v2 YAML
/// export as an `application/yaml` attachment named `<recipe id>.yaml`.
///
/// The recipe id is validated at import time (isSafeRecipeId), so it is a
/// safe `Content-Disposition` filename with no quote/CRLF injection surface.
/// 404 envelope when no recipe matches.
Response onRequest(RequestContext context, String id) {
  requireGet(context);
  final result = recipeYaml(context.read<SaltDatabase>(), id);
  return Response(
    body: result.yaml,
    headers: {
      HttpHeaders.contentTypeHeader: 'application/yaml; charset=utf-8',
      'Content-Disposition': 'attachment; filename="${result.fileName}"',
    },
  );
}
