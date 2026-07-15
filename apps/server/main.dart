import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/bootstrap.dart';

/// Custom Dart Frog entrypoint: initializes configuration, logging, and the
/// database before serving, so a bad `LOG_LEVEL`/`DATA_DIR` fails the process
/// at startup (with a clear message) instead of turning every request into a
/// silent 500. On a first boot with zero users this also prints the one-time
/// setup code used by `POST /api/v1/auth/setup`.
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
