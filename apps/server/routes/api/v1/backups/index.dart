import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/services/backup_service.dart';

/// `GET /api/v1/backups` (admin) -> `{"items": [{name, size_bytes,
/// created_at}]}`, newest first.
///
/// `POST /api/v1/backups` (admin, full scope) `{include_images?: bool}` ->
/// 201 `{"backup": {...}}`. Creates a tar.gz of the YAML library plus a
/// compacted database snapshot; `include_images` adds the image files
/// (much larger, for a full off-machine copy). Old backups beyond the
/// retention window are pruned.
Future<Response> onRequest(RequestContext context) async {
  requireMethods(context, {HttpMethod.get, HttpMethod.post});
  final user = requireAdmin(context);
  final config = context.read<ServerConfig>();

  if (context.request.method == HttpMethod.get) {
    return Response.json(
      body: {
        'items': [
          for (final backup in listBackups(config)) _backupJson(backup),
        ],
      },
    );
  }

  requireCsrf(context, user);
  requireFullScope(user);
  final body = context.request.headers['content-length'] == null ||
          context.request.headers['content-length'] == '0'
      ? const <String, Object?>{}
      : await readJsonBody(context.request);
  final name = createBackup(
    db: context.read<SaltDatabase>(),
    config: config,
    trigger: 'manual',
    includeImages: body['include_images'] == true,
  );
  final info = listBackups(config).firstWhere((b) => b.name == name);
  return Response.json(statusCode: 201, body: {'backup': _backupJson(info)});
}

Map<String, Object?> _backupJson(BackupInfo backup) => {
      'name': backup.name,
      'size_bytes': backup.sizeBytes,
      'created_at': backup.createdAt.toIso8601String(),
    };
