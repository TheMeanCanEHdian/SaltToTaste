import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/handlers/admin_handlers.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart' show auditLog;
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `GET /api/v1/admin/logs/export?level=&logger=&q=` (admin, full scope) — the
/// full matching log as a downloadable text file. `Content-Disposition:
/// attachment` makes the browser save it (secrets are already redacted in the
/// store).
///
/// Full scope on a READ, like the backup download (`backups/[name].dart`) and
/// for the same reason: the log is secret material no other endpoint returns —
/// client IPs, "Recovery code used: <user> is now an enabled admin", every
/// backup name, every request path. Effective permission = role ∩ scope, so a
/// leaked `read`-scoped PAT must not exfiltrate it.
///
/// Every export is recorded on the audit channel naming the actor — this is
/// the whole persisted log leaving the box, the same class of act as the
/// backup download, and the access line names nobody. Unlike the viewer's
/// read this is a one-shot user action, so it is not throttled.
Future<Response> onRequest(RequestContext context) async {
  requireMethods(context, {HttpMethod.get});
  final user = requireAdmin(context);
  requireFullScope(user);
  // Sharpest of the guarded GETs: no `maxScanBytes`, i.e. a synchronous
  // full-history parse on the serving isolate, once per navigation. Above
  // every line below it, because the guard exists to stop the COST.
  requireNotCrossSite(context);
  // No filter text is echoed: `q` is caller-chosen and an audit record must
  // stay something a caller cannot write through.
  auditLog.warning(
    'Server log exported by ${user.username} (id ${user.id}).',
  );
  final store = context.read<LogStore>();
  final query = context.request.uri.queryParameters;
  final export = logsExportHandler(
    store,
    level: query['level'],
    logger: query['logger'],
    query: query['q'],
  );
  return Response(
    body: export.body,
    headers: {
      'content-type': 'text/plain; charset=utf-8',
      'content-disposition': 'attachment; filename="${export.filename}"',
    },
  );
}
