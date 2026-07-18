import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/handlers/admin_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `GET /api/v1/admin/logs?level=&logger=&q=&limit=` (admin) — recent server
/// log records from the persistent log store (newest first, secrets redacted).
Future<Response> onRequest(RequestContext context) async {
  requireMethods(context, {HttpMethod.get});
  requireAdmin(context);
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
