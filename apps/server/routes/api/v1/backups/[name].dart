import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/services/backup_service.dart';

/// `GET /api/v1/backups/<name>` (admin, full scope) — download the backup
/// archive. `DELETE` (admin, full scope) — remove it.
///
/// The download requires full scope even though it is a read: the archive
/// contains the database snapshot — password/session/token hashes and every
/// user's private notes — secret material no other endpoint ever returns,
/// so a leaked read-scoped PAT must not be able to exfiltrate it.
///
/// [name] must match the strict backup-name pattern (no separators), which
/// doubles as the path-containment guard.
Response onRequest(RequestContext context, String name) {
  requireMethods(context, {HttpMethod.get, HttpMethod.delete});
  final user = requireAdmin(context);
  // Authorization before existence: a caller without rights gets 403
  // whether or not the archive exists.
  requireFullScope(user);
  final config = context.read<ServerConfig>();

  if (context.request.method == HttpMethod.delete) {
    requireCsrf(context, user);
    File(backupPathFor(config, name)).deleteSync();
    return Response(statusCode: 204);
  }
  final path = backupPathFor(config, name);

  final file = File(path);
  return Response.stream(
    body: file.openRead(),
    headers: {
      HttpHeaders.contentTypeHeader: 'application/gzip',
      HttpHeaders.contentLengthHeader: '${file.lengthSync()}',
      'Content-Disposition': 'attachment; filename="$name"',
    },
  );
}
