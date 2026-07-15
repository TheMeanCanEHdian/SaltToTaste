import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/token_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `DELETE /api/v1/tokens/<id>` — revoke one of the caller's tokens.
Response onRequest(RequestContext context, String id) {
  requireMethods(context, {HttpMethod.delete});
  final actor = requireUser(context);
  requireCsrf(context, actor);
  final tokenId = int.tryParse(id);
  if (tokenId == null) {
    throw const ValidationException('Token id must be an integer.');
  }
  revokeTokenHandler(context.read<SaltDatabase>(), actor, tokenId);
  return Response(statusCode: HttpStatus.noContent);
}
