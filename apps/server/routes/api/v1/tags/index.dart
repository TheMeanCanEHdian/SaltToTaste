import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/tag_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `GET /api/v1/tags` — every tag with recipe counts and chip styles.
Response onRequest(RequestContext context) {
  requireGet(context);
  requireUser(context);
  return Response.json(
    body: listTagsHandler(context.read<SaltDatabase>()),
  );
}
