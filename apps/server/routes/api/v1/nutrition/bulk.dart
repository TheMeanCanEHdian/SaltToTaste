import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/bootstrap.dart'
    show bulkNutritionProvider, fdcApiKeySetting;
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';

/// `POST /api/v1/nutrition/bulk` (admin, full scope) — start a background
/// compute over every recipe without stored nutrition. Returns
/// `202 {"job_id": n}`; progress via `GET /api/v1/nutrition/jobs/<id>`.
/// `409 conflict` when a bulk job is already running.
Response onRequest(RequestContext context) {
  requireMethods(context, {HttpMethod.post});
  final user = requireAdmin(context);
  requireCsrf(context, user);
  requireFullScope(user);
  final db = context.read<SaltDatabase>();
  final key = db.getSetting(fdcApiKeySetting);
  if (key == null || key.isEmpty) {
    throw const ValidationException(
      'No FoodData Central API key is configured. Add one in '
      'Settings → Nutrition first (free at api.data.gov/signup).',
    );
  }
  // The bulk provider has no rate-limit wait cap: the job is expected to
  // ride out the hourly budget, unlike interactive requests.
  final jobId = startBulkJob(db, bulkNutritionProvider);
  if (jobId == null) {
    throw const ConflictException('A bulk nutrition job is already running.');
  }
  return Response.json(statusCode: 202, body: {'job_id': jobId});
}
