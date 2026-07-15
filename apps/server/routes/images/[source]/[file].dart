import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/handlers/image_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `GET /images/<source>/<file>` -> recipe image bytes from
/// `<libraryDir>/<source>/images/<file>`, cacheable for a day and
/// revalidatable via `Last-Modified` / `If-Modified-Since`. Requires auth.
///
/// Path containment (segment validation, canonicalized-path check, size cap)
/// lives in [resolveLibraryImage].
Response onRequest(RequestContext context, String source, String file) {
  requireUser(context);
  requireGet(context);
  final image = resolveLibraryImage(
    libraryDir: context.read<ServerConfig>().libraryDir,
    source: source,
    file: file,
  );

  final headers = <String, String>{
    // `private`: the route now requires auth, so shared proxy caches must
    // not serve these bytes to other clients; browser caching stays.
    HttpHeaders.cacheControlHeader: 'private, max-age=86400',
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
