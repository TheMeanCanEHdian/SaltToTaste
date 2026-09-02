import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';

/// `GET /api/v1/nutrition/bulk/counts` (admin) — how many recipes each
/// `POST /api/v1/nutrition/bulk` scope would select right now:
/// `{"missing": n, "stale": n, "all": n}`. The same selection the sweep
/// runs, so the count shown before the click is the `total` the 202 will
/// echo after it.
Response onRequest(RequestContext context) {
  requireGet(context);
  requireAdmin(context);
  // Not cross-site drivable: `stale` hashes every recipe with nutrition on
  // the serving isolate (~110-190 ms for 1,198 recipes), and requireCsrf
  // gates mutating METHODS only. Above the work, because the guard exists to
  // stop the COST.
  requireNotCrossSite(context);
  final db = context.read<SaltDatabase>();
  return Response.json(
    body: {
      for (final scope in BulkScope.values)
        scope.wireName: bulkScopeIds(db, scope).length,
    },
  );
}
