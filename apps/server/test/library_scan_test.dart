import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/services/library_io.dart';
import 'package:salt_server/src/services/library_scan.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';

/// P5 reconciliation-scan tests against real corpus recipes: a clean hand
/// edit wins, a malformed edit loses (database stays), a missing export
/// self-heals, and a hand-dropped new file is imported.
void main() {
  late Directory tempDir;
  late ServerConfig config;
  late SaltDatabase db;
  late Recipe bundt;
  late String recipeId;
  late File exportFile;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('salt-scan-test');
    config = ServerConfig(
      dataDir: tempDir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    );
    db = SaltDatabase.open(config.dbPath);

    bundt = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
    final doc = bundt.toMap();
    final created = createRecipe(db, config, {
      for (final key in editableRecipeKeys)
        if (doc.containsKey(key)) key: doc[key],
    });
    recipeId = created.recipe.id;
    exportFile =
        File(exportPathFor(config, manualSourceSlug, recipeId));
  });

  tearDownAll(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  test('an in-sync library scans clean', () {
    final report = scanLibrary(db: db, config: config);
    expect(report.filesSeen, 1);
    expect(report.updatedFromDisk, isEmpty);
    expect(report.added, isEmpty);
    expect(report.reExported, isEmpty);
    expect(report.skipped, isEmpty);
    expect(lastScanReport(db), isNotNull,
        reason: 'the report is persisted for the Settings UI');
  });

  test('a clean hand edit wins and is normalized back to canonical form',
      () {
    final original = exportFile.readAsStringSync();
    expect(original, contains('title: Rich Chocolate Bundt Cake'));
    exportFile.writeAsStringSync(
      original.replaceFirst(
        'title: Rich Chocolate Bundt Cake',
        'title: Rich Chocolate Bundt Cake (Hand Edited)',
      ),
    );

    final report = scanLibrary(db: db, config: config);
    expect(report.updatedFromDisk, [recipeId]);

    final stored = db.recipeByIdOrSlug(recipeId)!.recipe;
    expect(stored.title, 'Rich Chocolate Bundt Cake (Hand Edited)');

    // The file was rewritten canonically and now matches the database hash.
    final text = exportFile.readAsStringSync();
    expect(contentHashOfText(text), db.contentHashOf(recipeId));
    expect(RecipeYamlCodec.decode(text).recipe.title, stored.title);
  });

  test('a malformed hand edit is skipped and the database version stays',
      () {
    final good = exportFile.readAsStringSync();
    exportFile.writeAsStringSync('$good\n\t: this is not valid yaml');

    final report = scanLibrary(db: db, config: config);
    expect(report.updatedFromDisk, isEmpty);
    expect(report.skipped, hasLength(1));
    expect(report.skipped.single.file, contains('$recipeId.yaml'));
    expect(report.skipped.single.reason, contains('not importable'));

    final stored = db.recipeByIdOrSlug(recipeId)!.recipe;
    expect(stored.title, 'Rich Chocolate Bundt Cake (Hand Edited)',
        reason: 'the malformed file must not clobber the database');

    // Put the good text back for the next tests.
    exportFile.writeAsStringSync(good);
  });

  test('a file whose document id does not match its name is skipped', () {
    final text = exportFile.readAsStringSync();
    final impostor = File('${exportFile.parent.path}/some-other-name.yaml')
      ..writeAsStringSync(text);

    final report = scanLibrary(db: db, config: config);
    expect(report.skipped, hasLength(1));
    expect(report.skipped.single.reason, contains('does not match'));
    impostor.deleteSync();
  });

  test('a missing export is re-materialized from the database', () {
    exportFile.deleteSync();
    final report = scanLibrary(db: db, config: config);
    expect(report.reExported, [recipeId]);
    expect(exportFile.existsSync(), isTrue);
    expect(
      contentHashOfText(exportFile.readAsStringSync()),
      db.contentHashOf(recipeId),
    );
  });

  test('a new hand-dropped corpus file is imported (added)', () {
    final lemon = loadCorpusRecipe('0860-lemon-bundt-cake.yaml');
    final canonical = RecipeYamlCodec.encode(lemon);
    File('${exportFile.parent.path}/${lemon.id}.yaml')
        .writeAsStringSync(canonical);

    final report = scanLibrary(db: db, config: config);
    expect(report.added, [lemon.id]);
    expect(db.recipeExists(lemon.id), isTrue);
    expect(
      db.recipeByIdOrSlug(lemon.id)!.recipe.title,
      lemon.title,
    );
  });

  test('conflict copies are surfaced by the scan', () {
    // Force a save-time conflict: hand-edit, then save through the app.
    final handEdited = '# unsynced edit\n${exportFile.readAsStringSync()}';
    exportFile.writeAsStringSync(handEdited);
    updateRecipe(db, config, recipeId, {'category': 'Conflicted'});

    final report = scanLibrary(db: db, config: config);
    expect(report.conflictFiles, hasLength(1));
    expect(report.conflictFiles.single, contains('$recipeId.conflict-'));
  });
}
