import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/bootstrap.dart';

/// Custom Dart Frog entrypoint: initializes configuration and logging before
/// serving, so a bad `LOG_LEVEL`/`DATA_DIR` fails the process at startup
/// (with a clear message) instead of turning every request into a silent 500.
Future<HttpServer> run(Handler handler, InternetAddress ip, int port) async {
  try {
    initServer();
  } catch (error, stackTrace) {
    stderr
      ..writeln('Fatal: server configuration failed.')
      ..writeln(error)
      ..writeln(stackTrace);
    rethrow;
  }
  return serve(handler, ip, port);
}
