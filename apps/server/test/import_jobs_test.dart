import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/services/import_job.dart';
import 'package:salt_server/src/services/legacy_import.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';

/// P7 import-job tests against REAL data: two corpus files as a v1 source
/// root and the legacy app's shipped sample as a v0 root, both placed
/// inside the allowlisted import directory.
void main() {
  // Corpus-backed integration tests: skip (not fail) when the ATK corpus is
  // absent — e.g. CI — so `dart test` stays green. Set SALT_CORPUS_DIR to run.
  if (!corpusAvailable) {
    test('corpus-backed tests (skipped: corpus absent)', () {},
        skip: 'ATK corpus not present; set SALT_CORPUS_DIR');
    return;
  }
  late Directory tempDir;
  late ServerConfig config;
  late SaltDatabase db;

  const corpusFiles = [
    '0857-rich-chocolate-bundt-cake.yaml',
    '0747-100-percent-whole-wheat-pancakes.yaml',
  ];
  const legacySample = 'test/fixtures/legacy-v0';

  void copyTree(String from, String to) {
    Directory(to).createSync(recursive: true);
    for (final entity in Directory(from).listSync(recursive: true)) {
      final relative = entity.path.substring(from.length + 1);
      if (entity is Directory) {
        Directory('$to/$relative').createSync(recursive: true);
      } else if (entity is File) {
        File('$to/$relative').parent.createSync(recursive: true);
        entity.copySync('$to/$relative');
      }
    }
  }

  Future<Map<String, Object?>> awaitJob(int jobId) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (true) {
      final job = db.importJob(jobId)!;
      if (job['status'] != 'running') {
        return job;
      }
      if (DateTime.now().isAfter(deadline)) {
        fail('import job $jobId still running after 30s: $job');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('salt_import_job_test_');
    config = ServerConfig(
      dataDir: tempDir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    );
    Directory(config.libraryDir).createSync(recursive: true);
    Directory(config.importDir).createSync(recursive: true);
    db = SaltDatabase.open(config.dbPath);

    // A v1 source root holding two REAL corpus files.
    final v1Recipes = Directory('${config.importDir}/corpus sample/recipes')
      ..createSync(recursive: true);
    for (final name in corpusFiles) {
      File('$corpusRecipesDir/$name').copySync('${v1Recipes.path}/$name');
    }
    // The legacy app's real sample data as a v0 root.
    copyTree(legacySample, '${config.importDir}/legacy-sample');
    // Noise that must not be detected.
    Directory('${config.importDir}/noise').createSync();
  });

  tearDownAll(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  test('candidates detect v1 and legacy roots, skip noise', () {
    final candidates = importCandidates(config);
    final byPath = {for (final c in candidates) c.path: c};
    expect(byPath.keys, containsAll(['corpus sample', 'legacy-sample']));
    expect(byPath.containsKey('noise'), isFalse);
    expect(byPath['corpus sample']!.kind, 'v1');
    expect(byPath['corpus sample']!.fileCount, 2);
    expect(byPath['legacy-sample']!.kind, 'legacy');
    expect(byPath['legacy-sample']!.fileCount, greaterThan(0));
  });

  test('containment: traversal, outside paths, and symlink escapes', () {
    // A sibling directory outside the allowlist root.
    final outside = Directory('${tempDir.path}/outside')..createSync();
    expect(
      () => resolveImportPath(config, '../outside'),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => resolveImportPath(config, outside.path),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => resolveImportPath(config, ''),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => resolveImportPath(config, 'does-not-exist'),
      throwsA(isA<ValidationException>()),
    );
    // A symlink INSIDE the import dir pointing OUTSIDE must not pass.
    Link('${config.importDir}/sneaky').createSync(outside.path);
    expect(
      () => resolveImportPath(config, 'sneaky'),
      throwsA(isA<ValidationException>()),
    );
    // The happy path resolves (spaces included — the real corpus name has
    // them).
    expect(
      resolveImportPath(config, 'corpus sample'),
      startsWith(Directory(config.importDir).resolveSymbolicLinksSync()),
    );
  });

  test('a v1 import runs to done and is idempotent on re-run', () async {
    final path = resolveImportPath(config, 'corpus sample');
    final jobId = startImportJob(db, config, path: path)!;

    // Single flight: a second start while running returns null.
    expect(startImportJob(db, config, path: path), isNull);

    final job = await awaitJob(jobId);
    expect(job['status'], 'done', reason: '$job');
    expect(job['total'], 2);
    expect(job['imported'], 2);
    expect(job['legacy'], false);
    expect(db.recipeByIdOrSlug('rich-chocolate-bundt-cake'), isNotNull,
        reason: 'the isolate written rows must be visible on this conn');
    final exported = Directory(config.libraryDir)
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('0857-rich-chocolate-bundt-cake.yaml'),
        );
    expect(exported, isNotEmpty,
        reason: 'canonical YAML export must appear in the library');

    // Idempotent: unchanged files skip.
    final second = await awaitJob(startImportJob(db, config, path: path)!);
    expect(second['status'], 'done');
    expect(second['skipped'], 2);
    expect(second['imported'], 0);
  });

  test('a legacy v0 import auto-detects and maps to schema v2', () async {
    final path = resolveImportPath(config, 'legacy-sample');
    expect(looksLikeLegacyRoot(path), isTrue);
    final job = await awaitJob(startImportJob(db, config, path: path)!);
    expect(job['status'], 'done', reason: '$job');
    expect(job['legacy'], true);
    expect(job['imported'], greaterThan(0));
    // v0 ids derive from the file name with a v0- prefix.
    final imported = db.listCards(page: 1, limit: 100).items.where(
          (card) => card.id.startsWith('v0-'),
        );
    expect(imported, isNotEmpty,
        reason: 'legacy recipes land with v0- ids');
    final detail = db.recipeByIdOrSlug(imported.first.id)!;
    expect(detail.recipe.source.type, 'legacy-v0');
  });

  test('a nonexistent recipes dir fails the JOB, not silently', () async {
    final empty = Directory('${config.importDir}/empty')..createSync();
    final path = resolveImportPath(config, 'empty');
    final job = await awaitJob(startImportJob(db, config, path: path)!);
    expect(job['status'], 'failed');
    expect('${job['log']}', contains('recipes'));
    expect(empty.existsSync(), isTrue);
  });

  test('boot reconciliation fails orphaned running jobs', () {
    final orphan = db.createImportJob(sourcePath: '/x', legacy: false);
    expect(db.failOrphanedImportJobs(), 1);
    final job = db.importJob(orphan)!;
    expect(job['status'], 'failed');
    expect('${job['log']}', contains('interrupted'));
  });
}
