import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/handlers/image_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';

/// `GET /images/<source>/<file>` -> recipe image bytes from
/// `<libraryDir>/<source>/images/<file>`, cacheable for a day and
/// revalidatable via `Last-Modified` / `If-Modified-Since`.
///
/// Path containment (segment validation, canonicalized-path check, size cap)
/// lives in [resolveLibraryImage].
Response onRequest(RequestContext context, String source, String file) {
  requireGet(context);
  final image = resolveLibraryImage(
    libraryDir: context.read<ServerConfig>().libraryDir,
    source: source,
    file: file,
  );

  final headers = <String, String>{
    HttpHeaders.cacheControlHeader: 'public, max-age=86400',
    HttpHeaders.lastModifiedHeader: HttpDate.format(image.lastModified),
  };

  final since = _ifModifiedSince(context);
  if (since != null && !image.lastModified.isAfter(since)) {
    return Response(statusCode: HttpStatus.notModified, headers: headers);
  }

  return Response.bytes(
    body: image.readBytes(),
    headers: {...headers, HttpHeaders.contentTypeHeader: image.contentType},
  );
}

DateTime? _ifModifiedSince(RequestContext context) {
  final raw = context.request.headers[HttpHeaders.ifModifiedSinceHeader];
  if (raw == null) {
    return null;
  }
  try {
    return HttpDate.parse(raw);
  } on Exception {
    return null;
  }
}
