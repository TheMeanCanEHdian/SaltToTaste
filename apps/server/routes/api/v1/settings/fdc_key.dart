import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/bootstrap.dart' show fdcApiKeySetting;
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// The per-deployment USDA FoodData Central API key (admin only).
///
/// The key is WRITE-ONLY: `GET` returns `{configured, masked}` — never the
/// full value — and it is never logged. `PUT {api_key}` stores/replaces it
/// (full scope); an empty string clears it.
///
/// A write leaves an [auditLog] line naming the actor and whether the key was
/// set or cleared — the access line is only `PUT /api/v1/settings/fdc_key ->
/// 200` and names nobody, so replacing a deployment credential (or silently
/// clearing it, which breaks every nutrition lookup) left no trace at all.
/// The key itself, and even its masked tail, stay out of the record: nothing
/// an operator needs from this line requires any part of the secret.
Future<Response> onRequest(RequestContext context) async {
  requireMethods(context, {HttpMethod.get, HttpMethod.put});
  final user = requireAdmin(context);
  final db = context.read<SaltDatabase>();

  if (context.request.method == HttpMethod.get) {
    final key = db.getSetting(fdcApiKeySetting);
    return Response.json(
      body: {
        'configured': key != null && key.isNotEmpty,
        'masked': key == null || key.isEmpty ? null : maskKey(key),
      },
    );
  }

  requireCsrf(context, user);
  requireFullScope(user);
  final body = await readJsonBody(context.request);
  final key = body['api_key'];
  if (key is! String) {
    throw const ValidationException("'api_key' must be a string.");
  }
  final trimmed = key.trim();
  if (trimmed.length > 128) {
    throw const ValidationException("'api_key' is implausibly long.");
  }
  db.setSetting(fdcApiKeySetting, trimmed);
  auditLog.info(
    'FDC API key ${trimmed.isEmpty ? 'cleared' : 'set'} by ${user.username} '
    '(id ${user.id}).',
  );
  return Response.json(
    body: {
      'configured': trimmed.isNotEmpty,
      'masked': trimmed.isEmpty ? null : maskKey(trimmed),
    },
  );
}
