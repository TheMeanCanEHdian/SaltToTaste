import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/handlers/tag_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/http/path_params.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `PUT /api/v1/tags/<name>/style` (admin) `{icon?, color?, bg_color?}` —
/// set or clear the tag's chip style (Lucide icon + `#RRGGBB` colors).
Future<Response> onRequest(RequestContext context, String rawName) async {
  final name = decodePathParam(rawName);
  requireMethods(context, {HttpMethod.put});
  final actor = requireAdmin(context);
  requireCsrf(context, actor);
  requireFullScope(actor);
  final body = await readJsonBody(context.request);
  final icon = body['icon'];
  final color = body['color'];
  final bgColor = body['bg_color'];
  if (icon is! String? || color is! String? || bgColor is! String?) {
    throw const ValidationException(
      "'icon', 'color', and 'bg_color' must be strings when present.",
    );
  }
  return Response.json(
    body: putTagStyleHandler(
      context.read<SaltDatabase>(),
      name,
      icon: icon,
      color: color,
      bgColor: bgColor,
    ),
  );
}
