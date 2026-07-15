import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `GET /api/v1/nutrition/jobs/<id>` (admin) — bulk-job progress:
/// `{id, status, total, done, failed, log, started_at, finished_at}`.
Response onRequest(RequestContext context, String id) {
  requireGet(context);
  requireAdmin(context);
  final jobId = int.tryParse(id);
  final job =
      jobId == null ? null : context.read<SaltDatabase>().nutritionJob(jobId);
  if (job == null) {
    throw NotFoundException('nutrition job not found: $id');
  }
  return Response.json(body: job);
}
