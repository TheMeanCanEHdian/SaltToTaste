import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/bootstrap.dart' show fdcApiKeySetting;
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart' show readJsonBody;
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';

/// `POST /api/v1/nutrition/bulk` (admin, full scope) — start a background
/// compute. Optional body `{"scope": "missing"|"stale"|"all"}`; `missing`
/// (never computed) is the default and the historical behaviour. Returns
/// `202 {"job_id": n, "scope": s, "total": n}`; progress via
/// `GET /api/v1/nutrition/jobs/<id>`. `409 conflict` when a bulk job is
/// already running.
Future<Response> onRequest(RequestContext context) async {
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
  // An absent body keeps the historical behaviour, so an existing client
  // that posts nothing is unaffected. An UNRECOGNISED scope is refused rather
  // than quietly treated as the default: silently computing something other
  // than what was asked spends the FDC budget on the wrong recipes.
  // The body is optional -- the shipped client posts none -- but a body that
  // IS present must be JSON, else 422 like every other endpoint. Gating the
  // parse on content-type silently dropped a scope sent as text/plain and
  // ran the job as `missing`; gating on Content-Length missed chunked bodies
  // entirely (shelf strips Transfer-Encoding). Only the bytes can say.
  final body = await readJsonBody(context.request, allowEmpty: true);
  final requested = body['scope'];
  final BulkScope? scope;
  if (requested == null) {
    scope = BulkScope.missing;
  } else if (requested is String) {
    scope = BulkScope.fromWire(requested);
  } else {
    scope = null;
  }
  if (scope == null) {
    throw ValidationException(
      'Unknown scope "$requested". Use '
      '${BulkScope.values.map((s) => s.wireName).join(', ')}.',
    );
  }
  // The bulk provider has no rate-limit wait cap: the job is expected to
  // ride out the hourly budget, unlike interactive requests.
  final jobId = startBulkJob(
    db,
    context.read<BulkNutritionProvider>().provider,
    scope: scope,
  );
  if (jobId == null) {
    throw const ConflictException('A bulk nutrition job is already running.');
  }
  return Response.json(
    statusCode: 202,
    body: {
      'job_id': jobId,
      // Echoed so a client can show what it actually started, and so the
      // count is visible before the first poll — a `stale` sweep selecting
      // nothing is a legitimate, and otherwise confusing, outcome.
      'scope': scope.wireName,
      'total': db.nutritionJob(jobId)?['total'] ?? 0,
    },
  );
}
