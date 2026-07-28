import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/services/backup_service.dart';
import 'package:test/test.dart';

/// Per-trigger retention pools (review B14). Corpus-free — the archives are
/// synthesized name-pattern files (real backup content is irrelevant to
/// pruning, which selects purely on name + mtime).
void main() {
  late Directory tempDir;
  late ServerConfig config;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('salt_retention_');
    config = ServerConfig(
      dataDir: tempDir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    );
    Directory(backupsDir(config)).createSync(recursive: true);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  File write(String stamp, String trigger, {int? n}) {
    final suffix = n == null ? '' : '-$n';
    final file = File(
      '${backupsDir(config)}/salt-backup-$stamp$suffix-$trigger.tar.gz',
    )..writeAsStringSync('x');
    return file;
  }

  test('a burst of before-delete backups cannot evict scheduled history', () {
    // Oldest first; mtimes follow write order on a fresh dir.
    final scheduledOld = write('20260701T010101', 'scheduled');
    final scheduledNew = write('20260702T010101', 'scheduled');
    final deletes = [
      for (var i = 0; i < 5; i++)
        write('20260703T0101${20 + i}', 'before-delete'),
    ];

    pruneBackups(config, keep: 2);

    expect(
      scheduledOld.existsSync() && scheduledNew.existsSync(),
      isTrue,
      reason:
          'the scheduled pool is untouched by the delete flood '
          '(one shared pool once erased it — review B14)',
    );
    final survivingDeletes = deletes.where((f) => f.existsSync()).toList();
    expect(survivingDeletes, hasLength(2));
    expect(
      survivingDeletes.map((f) => f.path),
      deletes.sublist(3).map((f) => f.path),
      reason: 'newest two before-delete archives survive',
    );
  });

  test('BACKUP_RETENTION reaches pruneBackups via the config', () {
    final parsed = ServerConfig.fromEnvironment(
      environment: {'DATA_DIR': tempDir.path, 'BACKUP_RETENTION': '3'},
    );
    expect(parsed.backupRetention, 3);
    // Invalid or zero falls back to the default — retention 0 would delete
    // the backup that was just written.
    for (final bogus in ['0', '-2', 'lots', '']) {
      expect(
        ServerConfig.fromEnvironment(
          environment: {'DATA_DIR': tempDir.path, 'BACKUP_RETENTION': bogus},
        ).backupRetention,
        ServerConfig.defaultBackupRetention,
        reason: 'BACKUP_RETENTION=$bogus',
      );
    }
  });
}
