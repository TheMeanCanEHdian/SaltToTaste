import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart' show auditLog;
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
///
/// Both arms write an [auditLog] line naming the actor and the archive.
/// Taking the snapshot off the box is the highest-value exfiltration this API
/// permits and deleting it is the most useful anti-forensics move, yet the
/// access line says only `GET /api/v1/backups/x -> 200` — no actor, no
/// object. WARNING, like the other account-in-doubt actions, so both stand
/// out in the viewer's default filter. `name` is logged only AFTER
/// `backupPathFor` has matched it against the strict pattern, so no
/// caller-chosen text reaches the record.
Response onRequest(RequestContext context, String name) {
  requireMethods(context, {HttpMethod.get, HttpMethod.delete});
  final user = requireAdmin(context);
  // Authorization before existence: a caller without rights gets 403
  // whether or not the archive exists.
  requireFullScope(user);
  final config = context.read<ServerConfig>();

  if (context.request.method == HttpMethod.delete) {
    requireCsrf(context, user);
    final path = backupPathFor(config, name);
    File(path).deleteSync();
    auditLog.warning(
      'Backup deleted: $name by ${user.username} (id ${user.id}).',
    );
    return Response(statusCode: 204);
  }
  // Not cross-site drivable: the download streams the entire database
  // snapshot off disk, and requireCsrf gates mutating METHODS only while the
  // session cookie is SameSite=Lax. The app opens this with `launchUrl` (a
  // top-level navigation, so no custom header), which is exactly why the
  // Sec-Fetch-Site arm exists. Above every line below it — which also keeps
  // authorization ahead of existence, since `backupPathFor` follows.
  requireNotCrossSite(context);
  final path = backupPathFor(config, name);

  final file = File(path);
  final sizeBytes = file.lengthSync();
  // Logged where the archive is handed over, not when the stream finishes: a
  // download the client aborts halfway still put the bytes on the wire.
  auditLog.warning(
    'Backup downloaded: $name ($sizeBytes bytes) by ${user.username} '
    '(id ${user.id}).',
  );
  return Response.stream(
    body: file.openRead(),
    headers: {
      HttpHeaders.contentTypeHeader: 'application/gzip',
      HttpHeaders.contentLengthHeader: '$sizeBytes',
      'Content-Disposition': 'attachment; filename="$name"',
    },
  );
}
