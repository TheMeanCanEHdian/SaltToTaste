import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/services/library_io.dart';
import 'package:salt_server/src/services/library_scan.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart' show OpenMode, sqlite3;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart' show loadYaml;

import 'support/corpus.dart';

/// P5 reconciliation-scan tests against real corpus recipes: a clean hand
/// edit wins, a malformed edit loses (database stays), a missing export
/// self-heals, and a hand-dropped new file is imported.
///
/// The T9 additions cover what a *real* editor does to an exported file —
/// CRLF line endings, a UTF-8 BOM, flow style, reordered keys — plus the
/// scan branches that had no test at all.
void main() {
  // These need no recipe data, so they must keep running where the corpus is
  // absent (CI) — they sit deliberately ABOVE the corpus gate (review T1).
  _scanBranchesWithoutCorpus();

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
    exportFile = File(exportPathFor(config, manualSourceSlug, recipeId));
  });

  tearDownAll(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  /// Puts the shared fixture (file AND database) back to [good] once the
  /// calling test finishes — pass or fail. Restoring inline at the end of
  /// the body instead lets the first failed expectation throw past the
  /// restore, corrupting the fixture for every later test in the file and
  /// turning one real failure into a fan-out of misleading ones.
  void restoreFixtureAfterTest(String good) {
    addTearDown(() {
      exportFile.writeAsStringSync(good);
      scanLibrary(db: db, config: config);
    });
  }

  test('an in-sync library scans clean', () {
    final report = scanLibrary(db: db, config: config);
    expect(report.filesSeen, 1);
    expect(report.updatedFromDisk, isEmpty);
    expect(report.added, isEmpty);
    expect(report.reExported, isEmpty);
    expect(report.skipped, isEmpty);
    expect(
      lastScanReport(db),
      isNotNull,
      reason: 'the report is persisted for the Settings UI',
    );
  });

  test('a clean hand edit wins and is normalized back to canonical form', () {
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

  test('a malformed hand edit is skipped and the database version stays', () {
    final good = exportFile.readAsStringSync();
    restoreFixtureAfterTest(good);
    exportFile.writeAsStringSync('$good\n\t: this is not valid yaml');

    final report = scanLibrary(db: db, config: config);
    expect(report.updatedFromDisk, isEmpty);
    expect(report.skipped, hasLength(1));
    expect(report.skipped.single.file, contains('$recipeId.yaml'));
    expect(report.skipped.single.reason, contains('not importable'));

    final stored = db.recipeByIdOrSlug(recipeId)!.recipe;
    expect(
      stored.title,
      'Rich Chocolate Bundt Cake (Hand Edited)',
      reason: 'the malformed file must not clobber the database',
    );
  });

  test('an over-cap hand edit is skipped, not imported (review B13)', () {
    // Synthesized negative path: a title beyond the editor's 250 cap. The
    // scan once imported it verbatim, after which every UNRELATED in-app
    // save 422'd — the recipe became uneditable from the editor.
    final good = exportFile.readAsStringSync();
    restoreFixtureAfterTest(good);
    final decoded = RecipeYamlCodec.decode(good).recipe;
    final overCap = decoded.copyWith(title: 'X' * 300);
    exportFile.writeAsStringSync(RecipeYamlCodec.encode(overCap));

    final report = scanLibrary(db: db, config: config);
    expect(report.updatedFromDisk, isEmpty);
    expect(report.skipped, hasLength(1));
    expect(report.skipped.single.reason, contains('fails validation'));
    expect(
      db.recipeByIdOrSlug(recipeId)!.recipe.title,
      isNot(overCap.title),
      reason: 'the database version stays authoritative',
    );
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
    File(
      '${exportFile.parent.path}/${lemon.id}.yaml',
    ).writeAsStringSync(canonical);

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

  // --- T9: hand edits in the shapes real editors actually produce ---------
  //
  // Every hand edit above is already in the codec's own canonical form. A
  // human's editor is not: Notepad writes CRLF and a BOM, and a YAML-aware
  // editor may reflow a mapping or reorder keys. Each case below starts from
  // the CURRENT export (real corpus data) and reshapes only its *text*.
  group('editor-realistic hand edits', () {
    test('a CRLF hand edit (Windows editor) wins and is stored as LF', () {
      final good = exportFile.readAsStringSync();
      restoreFixtureAfterTest(good);
      final recipe = RecipeYamlCodec.decode(good).recipe;
      final canonical = RecipeYamlCodec.encode(
        recipe.copyWith(title: '${recipe.title} (Windows)'),
      );
      exportFile.writeAsStringSync(canonical.replaceAll('\n', '\r\n'));

      final report = scanLibrary(db: db, config: config);
      expect(report.updatedFromDisk, [recipeId]);
      expect(report.skipped, isEmpty);

      final stored = db.recipeByIdOrSlug(recipeId)!.recipe;
      expect(stored.title, '${recipe.title} (Windows)');
      expect(
        stored.background,
        bundt.background,
        reason: 'the multi-line block scalars survive the CR strip intact',
      );

      final text = exportFile.readAsStringSync();
      expect(text, canonical, reason: 'rewritten canonically, LF only');
      expect(text, isNot(contains('\r')));
      expect(contentHashOfText(text), db.contentHashOf(recipeId));
    });

    test('a UTF-8 BOM is invisible to the scan and stays on disk', () {
      // WHAT IS PINNED: a BOM'd file survives the scan with its recipe
      // intact — untouched it is not even noticed, edited it wins normally —
      // and the BOM bytes are left exactly where the editor put them. That
      // last part is this test's only coverage the CRLF test above does not
      // already give: measured under a mutation of the stored-hash source,
      // this test still passes in isolation.
      //
      // DOCUMENTED DEFECT, deliberately NOT pinned: RecipeYamlCodec.decode
      // has no BOM handling at all. Handed a BOM-bearing STRING it throws
      // today — measured symptom: `YamlException: Error on line 2, column 1:
      // Only expected one document.` The scan is safe only incidentally,
      // because it decodes what File.readAsStringSync() returns and Dart's
      // UTF-8 decoder drops a leading BOM (utf8.decode over the raw bytes
      // drops it too, so reading bytes instead would behave the same). Any
      // path that decodes a BOM'd string it did NOT read from a file — an
      // upload body, an archive entry — throws with a message that never
      // mentions a BOM. Teaching the codec to tolerate a leading BOM is a
      // FIX, and nothing here should turn red for it.
      final good = exportFile.readAsStringSync();
      restoreFixtureAfterTest(good);
      final bom = utf8.encode('\u{FEFF}');

      // A BOM added to an otherwise untouched export is not even noticed:
      // the stripped text still hashes to the stored hash.
      exportFile.writeAsBytesSync([...bom, ...utf8.encode(good)]);
      var report = scanLibrary(db: db, config: config);
      expect(report.updatedFromDisk, isEmpty);
      expect(report.skipped, isEmpty);
      expect(exportFile.readAsBytesSync().take(3).toList(), bom);

      // A BOM'd file that was really edited still wins normally.
      final recipe = RecipeYamlCodec.decode(good).recipe;
      final canonical = RecipeYamlCodec.encode(
        recipe.copyWith(title: '${recipe.title} (Notepad)'),
      );
      exportFile.writeAsBytesSync([...bom, ...utf8.encode(canonical)]);
      report = scanLibrary(db: db, config: config);
      expect(report.updatedFromDisk, [recipeId]);
      expect(report.skipped, isEmpty);
      expect(
        db.recipeByIdOrSlug(recipeId)!.recipe.title,
        '${recipe.title} (Notepad)',
      );
      expect(
        exportFile.readAsBytesSync().take(3).toList(),
        bom,
        reason:
            'the decoded text already equals canonical, so the file — '
            'BOM and all — is left exactly as the editor saved it',
      );
      expect(
        contentHashOfText(exportFile.readAsStringSync()),
        db.contentHashOf(recipeId),
        reason:
            'the stored hash is over the BOM-stripped text, so the '
            'library still scans clean on every later pass',
      );

      // The recipe itself came back out of the BOM'd file unharmed — the
      // round-trip the documented codec defect never gets to break here.
      expect(
        RecipeYamlCodec.decode(exportFile.readAsStringSync()).recipe.title,
        '${recipe.title} (Notepad)',
      );
    });

    test('flow style is read by meaning and normalized back to block', () {
      final good = exportFile.readAsStringSync();
      restoreFixtureAfterTest(good);
      final recipe = RecipeYamlCodec.decode(good).recipe;
      final serves = recipe.serves!;

      // Blocks as the canonical emitter writes them, built from the real
      // values so a change in either the data or the emitter fails loudly.
      final servesBlock =
          'serves:\n  min: ${serves.min}\n'
          '  max: ${serves.max}\n';
      final tagsBlock =
          'tags:\n${recipe.tags.map((tag) => '- $tag').join('\n')}\n';
      expect(good, contains(servesBlock));
      expect(good, contains(tagsBlock));

      exportFile.writeAsStringSync(
        good
            .replaceFirst(
              servesBlock,
              'serves: {min: ${serves.min}, max: ${serves.max}}\n',
            )
            .replaceFirst(tagsBlock, 'tags: [${recipe.tags.join(', ')}]\n'),
      );

      final report = scanLibrary(db: db, config: config);
      expect(report.skipped, isEmpty);
      expect(
        report.updatedFromDisk,
        [recipeId],
        reason: 'the scan triggers on bytes even when meaning is unchanged',
      );

      final stored = db.recipeByIdOrSlug(recipeId)!.recipe;
      expect(stored.serves!.min, serves.min);
      expect(stored.serves!.max, serves.max);
      expect(stored.tags, recipe.tags);
      expect(
        exportFile.readAsStringSync(),
        good,
        reason: 'a pure reflow is normalized back to the same bytes',
      );
      expect(contentHashOfText(good), db.contentHashOf(recipeId));
    });

    test('reordered top-level keys are read by meaning, not by position', () {
      final good = exportFile.readAsStringSync();
      restoreFixtureAfterTest(good);
      final lines = good.split('\n');
      // Column 0 only, so an indented `title:` inside a block scalar or a
      // subsection can never be picked up here.
      final index = lines.indexWhere((line) => line.startsWith('title: '));
      expect(index, isNonNegative);
      final titleLine = lines[index];
      final body = [...lines]..removeAt(index);
      while (body.isNotEmpty && body.last.isEmpty) {
        body.removeLast();
      }
      // The canonical order puts `title` third; move it to the very end.
      exportFile.writeAsStringSync('${body.join('\n')}\n$titleLine\n');

      final report = scanLibrary(db: db, config: config);
      expect(report.skipped, isEmpty);
      expect(report.updatedFromDisk, [recipeId]);

      final before = RecipeYamlCodec.decode(good).recipe;
      final stored = db.recipeByIdOrSlug(recipeId)!.recipe;
      expect(stored.title, before.title);
      expect(RecipeYamlCodec.encode(stored), good);
      expect(
        exportFile.readAsStringSync(),
        good,
        reason: 'the file is rewritten in canonical key order',
      );
      expect(contentHashOfText(good), db.contentHashOf(recipeId));
    });
  });

  // --- T9: scan branches that had no coverage ----------------------------
  group('previously uncovered scan branches', () {
    test('the same id in two source directories: the later one is refused', () {
      // Two copies of one recipe would otherwise fight over the database row
      // on every scan. Directories are scanned in sorted order.
      final lib = _freshLibrary();
      final lemon = loadCorpusRecipe('0860-lemon-bundt-cake.yaml');
      final canonical = RecipeYamlCodec.encode(lemon);
      for (final source in ['aaa-first', 'zzz-second']) {
        final dir = Directory('${lib.config.libraryDir}/$source/recipes')
          ..createSync(recursive: true);
        File('${dir.path}/${lemon.id}.yaml').writeAsStringSync(canonical);
      }

      final report = scanLibrary(db: lib.db, config: lib.config);
      expect(report.filesSeen, 2);
      expect(report.added, [lemon.id]);
      expect(report.skipped, hasLength(1));
      expect(
        report.skipped.single.file,
        'zzz-second/recipes/${lemon.id}.yaml',
      );
      expect(report.skipped.single.reason, contains('duplicate id'));
      expect(lib.db.recipeExists(lemon.id), isTrue);
    });

    test('a hand-made source directory gets its sources row created', () {
      // The library is hand-editable, so a whole source folder can appear.
      // Identity comes from its source.yaml — the corpus's real one here.
      final lib = _freshLibrary();
      final lemon = loadCorpusRecipe('0860-lemon-bundt-cake.yaml');
      const slug = 'hand-made-source';
      final dir = Directory('${lib.config.libraryDir}/$slug/recipes')
        ..createSync(recursive: true);
      File(
        '${dir.path}/${lemon.id}.yaml',
      ).writeAsStringSync(RecipeYamlCodec.encode(lemon));
      final sourceYaml = File('$corpusRoot/source.yaml').readAsStringSync();
      File('${dir.parent.path}/source.yaml').writeAsStringSync(sourceYaml);
      expect(lib.db.sourceExists(slug), isFalse);

      final report = scanLibrary(db: lib.db, config: lib.config);
      expect(report.added, [lemon.id]);
      expect(report.skipped, isEmpty);
      expect(lib.db.sourceExists(slug), isTrue);

      // sourceExists() alone would hold however the parse went — the row is
      // upserted unconditionally, with the directory slug as the fallback
      // identity. So read the row itself and hold it against the real
      // source.yaml: `name`/`type` lifted out, every other key kept as meta.
      final expected =
          yamlToPlain(loadYaml(sourceYaml))! as Map<String, Object?>;
      final row = _sourceRow(lib.config.dbPath, slug);
      expect(row.name, expected['name']);
      expect(
        row.name,
        isNot(slug),
        reason: 'the real name, not the directory-name fallback',
      );
      expect(row.type, expected['type']);
      expect(row.type, isNot('manual'), reason: 'not the type fallback');
      expect(
        row.meta,
        {...expected}..removeWhere((key, _) => key == 'name' || key == 'type'),
      );
    });

    test('a hand-copied file with a duplicate slug is given a free one', () {
      // Copying an export and giving it a new id (but forgetting the slug)
      // is the realistic way a slug collision reaches the scan.
      final lib = _freshLibrary();
      final lemon = loadCorpusRecipe('0860-lemon-bundt-cake.yaml');
      final dir = Directory('${lib.config.libraryDir}/my-recipes/recipes')
        ..createSync(recursive: true);
      File(
        '${dir.path}/${lemon.id}.yaml',
      ).writeAsStringSync(RecipeYamlCodec.encode(lemon));
      expect(scanLibrary(db: lib.db, config: lib.config).added, [lemon.id]);

      final copyId = '${lemon.id}-copy';
      final copyFile = File('${dir.path}/$copyId.yaml')
        ..writeAsStringSync(RecipeYamlCodec.encode(lemon.copyWith(id: copyId)));

      final report = scanLibrary(db: lib.db, config: lib.config);
      expect(report.added, [copyId]);
      expect(report.skipped, isEmpty);

      final stored = lib.db.recipeByIdOrSlug(copyId)!.recipe;
      expect(stored.slug, isNot(lemon.slug));
      expect(stored.slug, startsWith(lemon.slug));
      expect(
        lib.db.recipeByIdOrSlug(lemon.id)!.recipe.slug,
        lemon.slug,
        reason: 'the original keeps the slug it already owned',
      );
      // The invariant the resolve-before-encode ordering exists for: the
      // file, the stored hash and the stored document all carry one slug.
      final text = copyFile.readAsStringSync();
      expect(RecipeYamlCodec.decode(text).recipe.slug, stored.slug);
      expect(contentHashOfText(text), lib.db.contentHashOf(copyId));
    });
  });
  test(
    'one row whose document does not decode does not abort the self-heal',
    () {
      // Both export files vanish. The good row must be re-exported even though
      // the bad row sits next to it in the same loop; the bad one is skipped
      // with a WARNING, and — via the identity lookup — remains deletable.
      final doc = bundt.toMap();
      final bad = createRecipe(db, config, {
        for (final key in editableRecipeKeys)
          if (doc.containsKey(key)) key: doc[key],
      }).recipe;
      final badFile = File(exportPathFor(config, manualSourceSlug, bad.id));
      sqlite3.open(config.dbPath)
        ..execute('UPDATE recipes SET doc = ? WHERE id = ?', [
          '{"title": ',
          bad.id,
        ])
        ..dispose();
      exportFile.deleteSync();
      badFile.deleteSync();
      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);

      final report = scanLibrary(db: db, config: config);

      expect(report.reExported, [recipeId], reason: 'the good row healed');
      expect(exportFile.existsSync(), isTrue);
      expect(badFile.existsSync(), isFalse);
      expect(
        records.where(
          (r) =>
              r.level >= Level.WARNING &&
              r.message.contains('Self-heal skipped ${bad.id}'),
        ),
        hasLength(1),
      );

      deleteRecipe(db, config, bad.id);
      expect(db.recipeIdentityByIdOrSlug(bad.id), isNull);
    },
  );
}

/// Reconciliation branches that need no recipe data at all, so they run
/// everywhere — including CI, which has no ATK corpus.
void _scanBranchesWithoutCorpus() {
  group('scan branches that need no recipe data', () {
    test('a source directory with no recipes/ subdirectory is ignored', () {
      final lib = _freshLibrary();
      Directory(
        '${lib.config.libraryDir}/orphan-source',
      ).createSync(recursive: true);

      final report = scanLibrary(db: lib.db, config: lib.config);
      expect(report.filesSeen, 0);
      expect(report.skipped, isEmpty);
      expect(report.added, isEmpty);
      expect(report.conflictFiles, isEmpty);
      expect(lastScanReport(lib.db), isNotNull);
    });

    test('a leftover atomic-write .yaml.tmp file is never scanned', () {
      // `writeAtomically` stages `<id>.yaml.tmp` before renaming; a crash in
      // between leaves one behind. A half-written file must never be taken
      // for a hand edit.
      final lib = _freshLibrary();
      final dir = Directory('${lib.config.libraryDir}/my-recipes/recipes')
        ..createSync(recursive: true);
      File('${dir.path}/half-written.yaml.tmp').writeAsStringSync('id: half');

      final report = scanLibrary(db: lib.db, config: lib.config);
      expect(report.filesSeen, 0);
      expect(report.skipped, isEmpty);
      expect(report.added, isEmpty);
    });

    test('a file whose name is not a safe recipe id is refused unread', () {
      // Crafted hostile name (a permitted synthetic negative input): a
      // leading dot is not a legal recipe id. `..evil.yaml` holds no
      // separator, so by itself it traverses nothing — what is pinned here
      // is the isSafeRecipeId branch, plus the ordering: the name is refused
      // BEFORE the file is opened.
      final lib = _freshLibrary();
      final dir = Directory('${lib.config.libraryDir}/my-recipes/recipes')
        ..createSync(recursive: true);
      // Bytes that are not valid UTF-8, so this file cannot be read at all.
      // The scan's readAsStringSync sits outside every try/catch, so a
      // refactor that read first and validated second would throw a
      // FileSystemException out of scanLibrary (or, if the read moved inside
      // the decode guard, report 'not importable') instead of the reason
      // asserted below.
      final evil = File('${dir.path}/..evil.yaml')
        ..writeAsBytesSync([0xff, 0xfe, 0xff]);
      expect(
        evil.readAsStringSync,
        throwsA(isA<FileSystemException>()),
        reason: 'premise: opening this file cannot silently succeed',
      );

      final report = scanLibrary(db: lib.db, config: lib.config);
      expect(report.filesSeen, 1);
      expect(report.added, isEmpty);
      expect(report.skipped, hasLength(1));
      expect(report.skipped.single.file, 'my-recipes/recipes/..evil.yaml');
      expect(report.skipped.single.reason, 'unsafe file name');
    });
  });
}

/// The `sources` row for [slug], read straight out of the database file.
/// `SaltDatabase` exposes only `sourceExists`, which cannot see the identity
/// the scan parsed out of a hand-dropped `source.yaml`; a second, read-only
/// connection can (WAL readers coexist with the open writer).
({String name, String type, Map<String, Object?> meta}) _sourceRow(
  String dbPath,
  String slug,
) {
  final raw = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    final row = raw.select(
      'SELECT name, type, meta FROM sources WHERE slug = ?',
      [slug],
    ).single;
    return (
      name: row['name'] as String,
      type: row['type'] as String,
      meta: jsonDecode(row['meta'] as String) as Map<String, Object?>,
    );
  } finally {
    raw.dispose();
  }
}

/// A throwaway data directory plus open database, both cleaned up when the
/// calling test finishes.
({ServerConfig config, SaltDatabase db}) _freshLibrary() {
  final dir = Directory.systemTemp.createTempSync('salt-scan-branch');
  addTearDown(() => dir.deleteSync(recursive: true));
  final config = ServerConfig(
    dataDir: dir.path,
    logLevel: Level.WARNING,
    trustProxy: false,
  );
  final db = SaltDatabase.open(config.dbPath);
  addTearDown(db.dispose);
  return (config: config, db: db);
}
