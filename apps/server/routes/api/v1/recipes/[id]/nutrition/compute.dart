import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/provider.dart';

/// `POST /api/v1/recipes/<id-or-slug>/nutrition/compute` (admin, full
/// scope) — start a background match+compute over every ingredient line and
/// return `{job_id}` (202). The client polls `/nutrition/jobs/<id>` for
/// progress; the label lands via `GET .../nutrition` when the job finishes.
/// User overrides on unchanged lines survive the recompute.
///
/// Asynchronous so the request returns immediately instead of holding a
/// connection open (and erroring) for the seconds a cold compute can take.
/// Single-flight per recipe: a second call while one runs re-attaches to it.
Future<Response> onRequest(RequestContext context, String id) async {
  requireMethods(context, {HttpMethod.post});
  final user = requireUser(context);
  requireCsrf(context, user);
  requireWrite(context);
  final db = context.read<SaltDatabase>();
  final found = db.recipeByIdOrSlug(id);
  if (found == null) {
    throw NotFoundException('recipe not found: $id');
  }
  final jobId = startRecipeComputeJob(
    db,
    context.read<NutritionProvider>(),
    found.recipe,
  );
  return Response.json(statusCode: 202, body: {'job_id': jobId});
}
