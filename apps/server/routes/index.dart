import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/http/method_guard.dart';

/// `GET /` — serves the bundled web app (`public/index.html`) when present,
/// falling back to a small identity payload on API-only deployments.
Response onRequest(RequestContext context) {
  requireGet(context);
  final index = File('public/index.html');
  if (index.existsSync()) {
    return Response.bytes(
      body: index.readAsBytesSync(),
      headers: {
        HttpHeaders.contentTypeHeader: 'text/html; charset=utf-8',
        // The shell must revalidate so deploys take effect immediately;
        // hashed assets under /assets remain long-cacheable.
        HttpHeaders.cacheControlHeader: 'no-cache',
      },
    );
  }
  return Response.json(body: {'name': 'salt_server'});
}
