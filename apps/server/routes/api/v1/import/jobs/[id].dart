import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `GET /api/v1/import/jobs/<id>` (admin) — import-job progress:
/// `{id, status, source_path, legacy, total, done, imported, updated,
/// skipped, failed, log, started_at, finished_at}`.
Response onRequest(RequestContext context, String id) {
  requireGet(context);
  requireAdmin(context);
  final jobId = int.tryParse(id);
  final job = jobId == null
      ? null
      : context.read<SaltDatabase>().importJob(jobId);
  if (job == null) {
    throw NotFoundException('No import job $id.');
  }
  return Response.json(body: job);
}
