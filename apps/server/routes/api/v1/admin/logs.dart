import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/handlers/admin_handlers.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart' show auditLog;
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// How often one actor's log reads are recorded on the audit channel.
///
/// A line per read would be self-destroying: the viewer polls this endpoint
/// every 3 seconds with Live on, so ~1,200 records an hour would land in the
/// very store being read, and the store keeps one 4 MiB generation — the
/// audit line would rotate the audit trail away. One line per actor per
/// window records who read the server log without becoming the flood.
const Duration _auditWindow = Duration(minutes: 10);

/// When each user's log read was last recorded, for [_auditWindow]. Bounded
/// by the account count (only an admin reaches this route) and process-local,
/// so a restart records the next read.
final Map<int, DateTime> _lastAudited = {};

/// `GET /api/v1/admin/logs?level=&logger=&q=&limit=` (admin, full scope) —
/// recent server log records from the persistent log store (newest first,
/// secrets redacted).
///
/// Full scope on a READ, like the backup download (`backups/[name].dart`) and
/// for the same reason: the log is secret material no other endpoint returns —
/// client IPs, "Recovery code used: <user> is now an enabled admin", every
/// backup name, every request path. Effective permission = role ∩ scope, so a
/// leaked `read`-scoped PAT must not exfiltrate it.
///
/// Recorded on the audit channel — actor and target, like the backup
/// download — but at most once per actor per [_auditWindow], because the
/// viewer polls this route.
Future<Response> onRequest(RequestContext context) async {
  requireMethods(context, {HttpMethod.get});
  final user = requireAdmin(context);
  requireFullScope(user);
  // Not cross-site drivable: `?scan=full` spawns an isolate and parses the
  // whole history, and requireCsrf gates mutating METHODS only. Above every
  // line below it, because the guard exists to stop the COST.
  requireNotCrossSite(context);
  _auditRead(user);
  final store = context.read<LogStore>();
  final query = context.request.uri.queryParameters;
  final limit = (int.tryParse(query['limit'] ?? '') ?? 200).clamp(1, 1000);
  return Response.json(
    body: await logsHandler(
      store,
      limit: limit,
      level: query['level'],
      logger: query['logger'],
      query: query['q'],
      // The client requests a full-history scan on an explicit filter/search;
      // the recurring Live poll omits it and reads the cheap recent tail.
      fullScan: query['scan'] == 'full',
    ),
  );
}

/// Records that [user] read the server log, at most once per [_auditWindow].
///
/// No filter text is echoed: `q` is caller-chosen and the record must stay
/// something a caller cannot write through. Actor and target are the whole
/// point — the access line says only `GET /api/v1/admin/logs -> 200`.
void _auditRead(AuthUser user) {
  final now = DateTime.now().toUtc();
  final last = _lastAudited[user.id];
  if (last != null && now.difference(last) < _auditWindow) {
    return;
  }
  _lastAudited[user.id] = now;
  auditLog.warning(
    'Server log read by ${user.username} (id ${user.id}); repeats within '
    '${_auditWindow.inMinutes} minutes are not recorded again.',
  );
}
