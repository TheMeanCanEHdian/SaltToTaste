import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/services/library_scan.dart';

/// `GET /api/v1/library` (admin) -> `{"last_scan": {...} | null}` — the
/// report of the most recent reconciliation scan (startup or rescan).
Response onRequest(RequestContext context) {
  requireGet(context);
  requireAdmin(context);
  return Response.json(
    body: {'last_scan': lastScanReport(context.read<SaltDatabase>())},
  );
}
