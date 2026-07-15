import 'dart:io';

import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/services/import_service.dart';

const _usage = 'Usage: dart run salt_server:import <source-root> '
    '[--data-dir=PATH]';

const _maxPrintedWarnings = 20;

void main(List<String> args) {
  final String sourceRoot;
  final String? dataDirOverride;
  try {
    (sourceRoot, dataDirOverride) = _parseArgs(args);
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
    final summary = importSourceRoot(
      sourceRootPath: sourceRoot,
      db: db,
      config: config,
      onProgress: (done, total) {
        if (done % 100 == 0) {
          stdout.writeln('imported $done/$total');
        }
      },
    );
    stdout.writeln(summary);
    for (final warning in summary.warnings.take(_maxPrintedWarnings)) {
      // Multi-line messages (e.g. YAML parse errors) collapse to one bullet.
      stdout.writeln('  - ${_singleLine(warning)}');
    }
    if (summary.warnings.length > _maxPrintedWarnings) {
      final more = summary.warnings.length - _maxPrintedWarnings;
      stdout.writeln('  ... and $more more');
    }
    if (summary.failed > 0) {
      exitCode = 1;
    }
  } on AppException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } finally {
    db.dispose();
  }
}

String _singleLine(String text) =>
    text.replaceAll(RegExp(r'\s*\n\s*'), ' ');

/// Parses `<source-root> [--data-dir=PATH]`; throws [FormatException] on
/// unknown options, a missing source root, or extra positional arguments.
(String, String?) _parseArgs(List<String> args) {
  String? sourceRoot;
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
    } else if (arg.startsWith('-')) {
      throw FormatException('Unknown option: $arg');
    } else if (sourceRoot == null) {
      sourceRoot = arg;
    } else {
      throw FormatException('Unexpected argument: $arg');
    }
  }
  if (sourceRoot == null || sourceRoot.isEmpty) {
    throw const FormatException('Missing <source-root> argument.');
  }
  if (dataDir != null && dataDir.isEmpty) {
    throw const FormatException('--data-dir requires a non-empty value.');
  }
  return (sourceRoot, dataDir);
}
