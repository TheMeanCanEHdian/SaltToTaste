import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/handlers/image_handlers.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';

/// `GET /images/<source>/<file>` -> recipe image bytes from
/// `<libraryDir>/<source>/images/<file>`, cacheable for a day.
///
/// Path containment (segment validation + canonicalized-path check against
/// the library dir) lives in [resolveLibraryImage]. Any other method gets a
/// 405 envelope.
Response onRequest(RequestContext context, String source, String file) {
  if (context.request.method != HttpMethod.get) {
    return errorResponse(
      statusCode: HttpStatus.methodNotAllowed,
      code: 'method_not_allowed',
      message: 'Only GET is allowed for /images/<source>/<file>.',
      requestId: requestIdOf(context),
    );
  }
  final image = resolveLibraryImage(
    libraryDir: context.read<ServerConfig>().libraryDir,
    source: source,
    file: file,
  );
  return Response.bytes(
    body: image.bytes,
    headers: {
      HttpHeaders.contentTypeHeader: image.contentType,
      HttpHeaders.cacheControlHeader: 'public, max-age=86400',
    },
  );
}
