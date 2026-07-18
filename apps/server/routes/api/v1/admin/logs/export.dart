import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/handlers/admin_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `GET /api/v1/admin/logs/export?level=&logger=&q=` (admin) — the full matching
/// log as a downloadable text file. `Content-Disposition: attachment` makes the
/// browser save it (secrets are already redacted in the store).
Future<Response> onRequest(RequestContext context) async {
  requireMethods(context, {HttpMethod.get});
  requireAdmin(context);
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
