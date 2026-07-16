import 'dart:io';

import 'package:salt_server/src/auth/recovery.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';

const _usage = 'Usage: dart run salt_server:recover [--data-dir=PATH]';

/// Issues a single-use account-recovery code and prints it.
///
/// The trust model is the same as the first-boot setup code: being able to
/// run this on the server host — or `docker exec` into the container — is
/// the proof of authority. Nothing else about the deployment is inspected,
/// and no account is touched until someone redeems the code at `/recover`.
///
/// Safe to run against a live server: the code lives in the settings table,
/// so the running process picks it up without a restart.
void main(List<String> args) {
  final String? dataDirOverride;
  try {
    dataDirOverride = _parseArgs(args);
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..writeln(_usage);
    exitCode = 64;
    return;
  }

  final ServerConfig config;
  try {
    config = ServerConfig.fromEnvironment(
      environment: {
        ...Platform.environment,
        if (dataDirOverride != null) 'DATA_DIR': dataDirOverride,
      },
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }
  configureLogging(config);

  final db = SaltDatabase.open(config.dbPath);
  try {
    final code = issueRecoveryCode(db);
    final minutes = recoveryCodeLifetime.inMinutes;
    // Deliberate secret-on-stdout, like the setup code in bootstrap.dart:
    // the code exists to be read from this console. It is stored only as a
    // digest, so this line is the one and only place it can be read.
    stdout.writeln(
      'SaltToTaste recovery code: $code\n'
      'Open /recover in the app and enter it with a username and a new '
      'password to get an enabled admin account back. '
      'Single use; expires in $minutes minutes.',
    );
  } finally {
    db.dispose();
  }
}

/// Parses `[--data-dir=PATH]`; throws [FormatException] on unknown options
/// or any positional argument (there are none).
String? _parseArgs(List<String> args) {
  String? dataDir;
  for (var i = 0; i < args.length; i += 1) {
    final arg = args[i];
    if (arg.startsWith('--data-dir=')) {
      dataDir = arg.substring('--data-dir='.length);
    } else if (arg == '--data-dir') {
      i += 1;
      if (i >= args.length) {
        throw const FormatException('--data-dir requires a value.');
      }
      dataDir = args[i];
    } else {
      throw FormatException('Unexpected argument: $arg');
    }
  }
  if (dataDir != null && dataDir.isEmpty) {
    throw const FormatException('--data-dir requires a non-empty value.');
  }
  return dataDir;
}
