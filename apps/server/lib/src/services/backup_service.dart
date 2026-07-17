import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';

final Logger _log = Logger('backup');

/// How many backups [pruneBackups] keeps by default.
const int defaultBackupRetention = 14;

/// Backup file names: `salt-backup-<utc stamp>[-<n>]-<trigger>.tar.gz`
/// (the `-<n>` disambiguates several backups within one second). The strict
/// shape doubles as the path-containment check for the download endpoint —
/// a name that matches cannot address outside the backups directory.
final RegExp backupNamePattern = RegExp(
  r'^salt-backup-[0-9]{8}T[0-9]{6}(-[0-9]{1,4})?-[a-z-]{1,32}\.tar\.gz$',
);

/// One entry of the backup listing.
class BackupInfo {
  /// Describes an on-disk backup archive.
  const BackupInfo({
    required this.name,
    required this.sizeBytes,
    required this.createdAt,
  });

  /// File name (matches [backupNamePattern]; the trigger is readable in it).
  final String name;

  /// Archive size in bytes.
  final int sizeBytes;

  /// File modification time (UTC) — when the backup finished writing.
  final DateTime createdAt;
}

/// Directory holding backup archives.
String backupsDir(ServerConfig config) => '${config.dataDir}/backups';

/// Creates a `.tar.gz` backup of the YAML library plus a compacted database
/// snapshot, prunes old backups, and returns the new archive's file name.
///
/// [trigger] (lowercase letters/dashes, e.g. `manual`, `before-delete`,
/// `before-import`, `scheduled`) is baked into the file name so the listing
/// explains itself. Image files are 97% of the library's bytes, are never
/// touched by destructive operations, and self-heal on re-import — so they
/// are excluded unless [includeImages] is set (a full manual backup).
///
/// Everything streams (bounded memory): files are added to the tar from
/// file streams and the gzip pass reads the tar back from disk.
String createBackup({
  required SaltDatabase db,
  required ServerConfig config,
  required String trigger,
  bool includeImages = false,
  int keep = defaultBackupRetention,
}) {
  final safeTrigger = trigger.toLowerCase().replaceAll(RegExp('[^a-z-]'), '-');
  if (safeTrigger.isEmpty || safeTrigger.length > 32) {
    throw const ValidationException('Invalid backup trigger.');
  }
  final stamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp('[-:]'), '')
      .split('.')
      .first;
  final dir = Directory(backupsDir(config))..createSync(recursive: true);
  var name = 'salt-backup-$stamp-$safeTrigger.tar.gz';
  var counter = 2;
  while (File('${dir.path}/$name').existsSync()) {
    // Never silently replace an existing archive (two before-delete backups
    // can land within one second).
    name = 'salt-backup-$stamp-$counter-$safeTrigger.tar.gz';
    counter += 1;
  }
  final finalPath = '${dir.path}/$name';
  final tarPath = '$finalPath.tar.tmp';
  final gzPath = '$finalPath.tmp';
  final snapshotPath = '$finalPath.db.tmp';
  final stopwatch = Stopwatch()..start();

  try {
    db.vacuumInto(snapshotPath);

    // Entries are added one at a time (TarEncoder.add materializes a single
    // file's bytes per call), so memory stays bounded by the largest file
    // and no two file handles are open at once.
    final tarOut = OutputFileStream(tarPath);
    final tar = TarEncoder()
      ..start(tarOut)
      ..add(ArchiveFile.bytes('salt.db', File(snapshotPath).readAsBytesSync()));
    final libraryRoot = Directory(config.libraryDir);
    final prefixLength = '${libraryRoot.parent.path}/'.length;
    final entries = libraryRoot.existsSync()
        ? (libraryRoot.listSync(recursive: true).whereType<File>().toList()
            ..sort((a, b) => a.path.compareTo(b.path)))
        : const <File>[];
    for (final file in entries) {
      final relative = file.path.substring(prefixLength);
      if (!includeImages && relative.contains('/images/')) {
        continue;
      }
      if (relative.endsWith('.tmp')) {
        continue;
      }
      tar.add(ArchiveFile.bytes(relative, file.readAsBytesSync()));
    }
    tar.finish();
    tarOut.closeSync();

    final tarIn = InputFileStream(tarPath);
    final gzOut = OutputFileStream(gzPath);
    const GZipEncoder().encodeStream(tarIn, gzOut);
    tarIn.closeSync();
    gzOut.closeSync();

    File(gzPath).renameSync(finalPath);
    _log.info(
      'Backup $name written '
      '(${File(finalPath).lengthSync()} bytes, '
      '${stopwatch.elapsedMilliseconds} ms, trigger: $safeTrigger)',
    );
  } finally {
    for (final temp in [snapshotPath, tarPath, gzPath]) {
      final file = File(temp);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  pruneBackups(config, keep: keep);
  return name;
}

/// All backups, newest first.
List<BackupInfo> listBackups(ServerConfig config) {
  final dir = Directory(backupsDir(config));
  if (!dir.existsSync()) {
    return const [];
  }
  final infos =
      <BackupInfo>[
          for (final file in dir.listSync().whereType<File>())
            if (backupNamePattern.hasMatch(_basename(file.path)))
              BackupInfo(
                name: _basename(file.path),
                sizeBytes: file.lengthSync(),
                createdAt: file.lastModifiedSync().toUtc(),
              ),
        ]
        // Newest first by actual creation time — lexical name order misranks
        // the `-N` same-second archives (retention would prune the wrong ones
        // during a burst of before-delete backups); the name only tiebreaks.
        ..sort((a, b) {
          final byTime = b.createdAt.compareTo(a.createdAt);
          return byTime != 0 ? byTime : b.name.compareTo(a.name);
        });
  return infos;
}

/// Deletes all but the newest [keep] backups.
void pruneBackups(ServerConfig config, {int keep = defaultBackupRetention}) {
  final backups = listBackups(config);
  for (final backup in backups.skip(keep)) {
    File('${backupsDir(config)}/${backup.name}').deleteSync();
    _log.info('Pruned old backup ${backup.name}');
  }
}

/// Absolute path of the named backup for download, or throws.
///
/// [name] must match [backupNamePattern] (which admits no separators, so it
/// cannot escape the backups directory) and must exist.
String backupPathFor(ServerConfig config, String name) {
  if (!backupNamePattern.hasMatch(name)) {
    throw const ValidationException('Not a valid backup name.');
  }
  final path = '${backupsDir(config)}/$name';
  if (!File(path).existsSync()) {
    throw NotFoundException('backup not found: $name');
  }
  return path;
}

String _basename(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}
