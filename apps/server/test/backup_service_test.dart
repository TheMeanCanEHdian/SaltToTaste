import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/services/backup_service.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:test/test.dart';

import 'support/corpus.dart';

/// P5 backup tests: archives carry the YAML library plus a usable database
/// snapshot, images stay out unless asked for, retention prunes, and the
/// download-name check refuses traversal.
void main() {
  // Corpus-backed integration tests: skip (not fail) when the ATK corpus is
  // absent — e.g. CI — so `dart test` stays green. Set SALT_CORPUS_DIR to run.
  if (!corpusAvailable) {
    test(
      'corpus-backed tests (skipped: corpus absent)',
      () {},
      skip: 'ATK corpus not present; set SALT_CORPUS_DIR',
    );
    return;
  }
  late Directory tempDir;
  late ServerConfig config;
  late SaltDatabase db;
  late String recipeId;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('salt-backup-test');
    config = ServerConfig(
      dataDir: tempDir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    );
    db = SaltDatabase.open(config.dbPath);
    final bundt = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
    final doc = bundt.toMap();
    recipeId = createRecipe(db, config, {
      for (final key in editableRecipeKeys)
        if (doc.containsKey(key)) key: doc[key],
    }).recipe.id;

    // A real corpus image in the library, to prove default backups skip it.
    const heroName = '0857-rich-chocolate-bundt-cake-hero.jpg';
    final source = File('$corpusImagesDir/$heroName');
    Directory(
      '${config.libraryDir}/$manualSourceSlug/images',
    ).createSync(recursive: true);
    source.copySync(
      '${config.libraryDir}/$manualSourceSlug/images/$heroName',
    );
  });

  tearDownAll(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  List<String> archiveEntries(String name) {
    final bytes = File('${backupsDir(config)}/$name').readAsBytesSync();
    final archive = TarDecoder().decodeBytes(
      const GZipDecoder().decodeBytes(bytes),
    );
    return [for (final file in archive) file.name];
  }

  test('a backup carries the database snapshot and the recipe YAML', () {
    final name = createBackup(db: db, config: config, trigger: 'manual');
    expect(backupNamePattern.hasMatch(name), isTrue);

    final entries = archiveEntries(name);
    expect(entries, contains('salt.db'));
    expect(
      entries,
      contains('library/$manualSourceSlug/recipes/$recipeId.yaml'),
    );
    expect(
      entries.where((entry) => entry.contains('/images/')),
      isEmpty,
      reason: 'images are excluded by default',
    );

    // The YAML inside the archive is the canonical export, byte for byte.
    final bytes = File('${backupsDir(config)}/$name').readAsBytesSync();
    final archive = TarDecoder().decodeBytes(
      const GZipDecoder().decodeBytes(bytes),
    );
    final yamlEntry = archive.files.firstWhere(
      (file) => file.name.endsWith('$recipeId.yaml'),
    );
    final decoded = RecipeYamlCodec.decode(
      utf8.decode(yamlEntry.content as List<int>),
    );
    expect(decoded.recipe.id, recipeId);

    // The snapshot must be a USABLE database, not just a file named
    // salt.db — this is the disaster-recovery artifact.
    final dbEntry = archive.files.firstWhere((file) => file.name == 'salt.db');
    final restoredPath = '${tempDir.path}/restored-salt.db';
    File(restoredPath).writeAsBytesSync(dbEntry.content as List<int>);
    final restored = sqlite3.open(restoredPath);
    try {
      expect(
        restored.select('SELECT COUNT(*) AS n FROM recipes').first['n'],
        1,
      );
      expect(
        restored.select('SELECT id FROM recipes').first['id'],
        recipeId,
      );
    } finally {
      restored.dispose();
    }
  });

  test('include_images pulls the image files in', () {
    final name = createBackup(
      db: db,
      config: config,
      trigger: 'manual',
      includeImages: true,
    );
    expect(
      archiveEntries(name).where((entry) => entry.contains('/images/')),
      isNotEmpty,
    );
  });

  test('retention keeps only the newest backups', () {
    for (var i = 0; i < 3; i += 1) {
      createBackup(db: db, config: config, trigger: 'manual', keep: 2);
    }
    expect(listBackups(config), hasLength(2));
  });

  test('same-second backups never overwrite each other', () {
    final first = createBackup(db: db, config: config, trigger: 'manual');
    final second = createBackup(db: db, config: config, trigger: 'manual');
    expect(first, isNot(second));
    expect(backupNamePattern.hasMatch(second), isTrue);
  });

  test('backupPathFor refuses names that do not match the pattern', () {
    for (final name in [
      '../salt.db',
      'salt-backup-20260715T091423-manual.tar.gz/../../x',
      r'salt-backup-20260715T091423-manual.tar.gz\evil',
      'notabackup.tar.gz',
    ]) {
      expect(
        () => backupPathFor(config, name),
        throwsA(isA<Exception>()),
        reason: '"$name" must be rejected',
      );
    }
  });
}
