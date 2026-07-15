import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/services/library_scan.dart';

/// `POST /api/v1/library/rescan` (admin, full scope) — reconcile the YAML
/// library with the database right now and return the scan report.
///
/// Cleanly hand-edited files win (imported + normalized), malformed files
/// are skipped with a reason (database stays authoritative), missing
/// exports are re-materialized.
Response onRequest(RequestContext context) {
  requireMethods(context, {HttpMethod.post});
  final user = requireAdmin(context);
  requireCsrf(context, user);
  requireFullScope(user);
  final report = scanLibrary(
    db: context.read<SaltDatabase>(),
    config: context.read<ServerConfig>(),
  );
  return Response.json(body: {'last_scan': report.toJson()});
}
