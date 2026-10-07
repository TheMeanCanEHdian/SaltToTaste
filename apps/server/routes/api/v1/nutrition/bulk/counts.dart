import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';

/// `GET /api/v1/nutrition/bulk/counts` (admin) — how many recipes each
/// `POST /api/v1/nutrition/bulk` scope would select right now:
/// `{"missing": n, "stale": n, "all": n, "sections": {"missing": n,
/// "stale": n, "all": n}}`. The same selection the sweep runs, so the count
/// shown before the click is the `total` the 202 will echo after it — v47
/// (F12): RECIPES only; the sections a scope computes first (a recipe's
/// subsection its parents read, v44) are counted apart in `sections`.
Response onRequest(RequestContext context) {
  requireGet(context);
  requireAdmin(context);
  // Not cross-site drivable: every scope decodes the library and resolves
  // its child set, and `stale` hashes every stamp, on the serving isolate
  // (v47 F10: ONE read for the three scopes, [bulkScopes] — ~0.42–0.55 s
  // on snapshot 20, was ~0.94–1.28 s), and requireCsrf gates mutating
  // METHODS only. Above the work, because the guard exists to stop the
  // COST.
  requireNotCrossSite(context);
  return Response.json(body: bulkCountsBody(context.read<SaltDatabase>()));
}
