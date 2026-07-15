import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/services/import_job.dart';

/// `POST /api/v1/import` (admin, full scope) — start a background import
/// of `{path}` (a source folder inside the allowlisted import directory;
/// relative to it, or absolute). Format (Recipe Extraction v1 vs legacy
/// SaltToTaste v0) is auto-detected. Returns `202 {"job_id": n}`;
/// progress via `GET /api/v1/import/jobs/<id>`. `409 conflict` while an
/// import is already running.
Future<Response> onRequest(RequestContext context) async {
  requireMethods(context, {HttpMethod.post});
  final user = requireAdmin(context);
  requireCsrf(context, user);
  requireFullScope(user);
  final config = context.read<ServerConfig>();
  final body = await readJsonBody(context.request);
  final path = body['path'];
  if (path is! String) {
    throw const ValidationException("'path' (string) is required.");
  }
  final resolved = resolveImportPath(config, path);
  final jobId = startImportJob(
    context.read<SaltDatabase>(),
    config,
    path: resolved,
  );
  if (jobId == null) {
    throw const ConflictException('An import is already running.');
  }
  return Response.json(statusCode: 202, body: {'job_id': jobId});
}
