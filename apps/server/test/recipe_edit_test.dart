import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/services/library_io.dart';
import 'package:salt_server/src/services/library_scan.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:test/test.dart';

import 'support/corpus.dart';

/// P5 edit-service tests, driven by the real Bundt cake corpus recipe.
///
/// A client submission is built from the real document's editable fields —
/// exactly what the editor will send after loading the recipe.
void main() {
  // Pure request-validation pins — no corpus data involved, so they run
  // everywhere (CI included). They once sat behind the whole-file corpus
  // gate and never ran there (review T1). Synthesized bodies: negative-path
  // inputs the corpus cannot produce.
  group('validation (corpus-free)', () {
    late Directory validationDir;
    late ServerConfig validationConfig;
    late SaltDatabase validationDb;

    setUpAll(() {
      validationDir = Directory.systemTemp.createTempSync('salt-edit-val');
      validationConfig = ServerConfig(
        dataDir: validationDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      validationDb = SaltDatabase.open(validationConfig.dbPath);
    });

    tearDownAll(() {
      validationDb.dispose();
      validationDir.deleteSync(recursive: true);
    });

    test('rejects a missing title', () {
      expect(
        () => createRecipe(validationDb, validationConfig, {
          'servings': 'SERVES 4',
        }),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects a malformed ingredient shape with a 422, not a 500', () {
      expect(
        () => createRecipe(validationDb, validationConfig, {
          'title': 'Broken',
          // A mapping where the schema requires a list of groups.
          'ingredients': {'items': 'nope'},
        }),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects an image path that escapes the library', () {
      expect(
        () => createRecipe(validationDb, validationConfig, {
          'title': 'Sneaky',
          'images': {'hero': '../../etc/passwd'},
        }),
        throwsA(isA<ValidationException>()),
      );
    });
  });

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
  late Map<String, Object?> submission;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('salt-edit-test');
    config = ServerConfig(
      dataDir: tempDir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    );
    db = SaltDatabase.open(config.dbPath);
    bundt = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
    final doc = bundt.toMap();
    submission = {
      for (final key in editableRecipeKeys)
        if (doc.containsKey(key)) key: doc[key],
    };
  });

  tearDownAll(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  group('create', () {
    late Recipe created;

    test('stores the recipe and exports canonical YAML', () {
      final result = createRecipe(db, config, submission);
      created = result.recipe;
      expect(result.sourceSlug, manualSourceSlug);
      expect(created.id, startsWith('manual-'));
      expect(created.id, endsWith('rich-chocolate-bundt-cake'));
      expect(created.slug, 'rich-chocolate-bundt-cake');
      expect(created.title, bundt.title);
      expect(created.serves?.min, 12);
      expect(created.ingredients.single.items, hasLength(13));

      final exportFile = File(
        exportPathFor(config, manualSourceSlug, created.id),
      );
      expect(exportFile.existsSync(), isTrue);

      // The export re-imports idempotently: decode -> re-encode -> same text.
      final text = exportFile.readAsStringSync();
      final decoded = RecipeYamlCodec.decode(text).recipe;
      expect(RecipeYamlCodec.encode(decoded), text);
      expect(decoded.toMap(), created.toMap());
      expect(db.contentHashOf(created.id), contentHashOfText(text));
    });

    test('a second recipe with the same title gets distinct id and slug', () {
      final result = createRecipe(db, config, submission);
      expect(result.recipe.id, isNot(created.id));
      expect(result.recipe.slug, 'rich-chocolate-bundt-cake-2');
      // Clean up so later expectations stay simple.
      deleteRecipe(db, config, result.recipe.id);
    });

    test('a recipe whose stored document no longer decodes is still '
        'deletable', () {
      // The reindex warning tells the operator to delete such a recipe.
      // Every per-recipe route decodes the document first, so before the
      // identity lookup that door threw the same FormatException the
      // warning was about (D1 review, critique #1).
      final victim = createRecipe(db, config, submission).recipe;
      sqlite3.open(config.dbPath)
        ..execute('UPDATE recipes SET doc = ? WHERE id = ?', [
          '{"title": ',
          victim.id,
        ])
        ..dispose();
      expect(
        () => db.recipeByIdOrSlug(victim.id),
        throwsFormatException,
        reason: 'the read path is genuinely broken for this row',
      );

      deleteRecipe(db, config, victim.id);

      expect(db.recipeIdentityByIdOrSlug(victim.id), isNull);
      expect(
        File(exportPathFor(config, manualSourceSlug, victim.id)).existsSync(),
        isFalse,
      );
    });

    test('a scan right after creating finds nothing to reconcile', () {
      final report = scanLibrary(db: db, config: config);
      expect(report.updatedFromDisk, isEmpty);
      expect(report.added, isEmpty);
      expect(report.skipped, isEmpty);
    });

    group('update', () {
      test(
        'merge semantics: a title-only submission keeps everything else',
        () {
          final result = updateRecipe(db, config, created.slug, {
            'title': '${bundt.title} (Weeknight)',
          });
          expect(result.changed, isTrue);
          expect(result.recipe.title, '${bundt.title} (Weeknight)');
          expect(result.recipe.slug, created.slug, reason: 'slug is stable');
          expect(result.recipe.id, created.id);
          expect(
            result.recipe.ingredients.single.items.map((i) => i.raw),
            bundt.ingredients.single.items.map((i) => i.raw),
          );
          expect(result.recipe.background, bundt.background);

          final text = File(
            exportPathFor(config, manualSourceSlug, created.id),
          ).readAsStringSync();
          expect(text, contains('(Weeknight)'));
        },
      );

      test('an identical submission is a no-op', () {
        final before = db.contentHashOf(created.id);
        final result = updateRecipe(db, config, created.id, {
          'title': '${bundt.title} (Weeknight)',
        });
        expect(result.changed, isFalse);
        expect(db.contentHashOf(created.id), before);
      });

      test('explicit null clears an optional field', () {
        final result = updateRecipe(db, config, created.id, {'category': null});
        expect(result.recipe.category, isNull);
      });

      // The editor cannot show variants/extras/techniques yet, so it never
      // submits those keys — and merge semantics must therefore leave them
      // alone. If the editor ever starts sending them (or someone adds them
      // to a submission builder), an admin saving a title edit would silently
      // destroy a recipe's variations. Pinned with a recipe that has them.
      test('a save leaves variants, extras, and techniques untouched', () {
        final dough = loadCorpusRecipe(
          '0972-basic-double-crust-pie-dough.yaml',
        );
        expect(dough.subsections, isNotEmpty, reason: 'fixture precondition');
        expect(dough.techniques, isNotEmpty, reason: 'fixture precondition');
        final doc = dough.toMap();
        final full = {
          for (final key in editableRecipeKeys)
            if (doc.containsKey(key)) key: doc[key],
        };
        final stored = createRecipe(db, config, full).recipe;
        // These tests share one database: leaving this recipe behind would
        // keep its `dessert` tag alive and break the orphaned-tag test.
        // Registered here, not run at the end of the body, so an assertion
        // failure below cannot cascade into an unrelated test's failure.
        addTearDown(() => deleteRecipe(db, config, stored.id));
        expect(stored.subsections, hasLength(dough.subsections.length));

        // Exactly what the editor sends: no subsections/techniques key.
        final result = updateRecipe(db, config, stored.id, {
          'title': 'Pie Dough (edited)',
        });

        expect(result.recipe.title, 'Pie Dough (edited)');
        expect(
          result.recipe.subsections.map((s) => s.title),
          dough.subsections.map((s) => s.title),
          reason: 'variants and extras must survive an unrelated edit',
        );
        expect(
          result.recipe.subsections.map((s) => s.kind),
          dough.subsections.map((s) => s.kind),
        );
        expect(
          result.recipe.techniques.map((t) => t.heading),
          dough.techniques.map((t) => t.heading),
        );
        // And they must still be on disk, not just in the row.
        final text = File(
          exportPathFor(config, manualSourceSlug, result.recipe.id),
        ).readAsStringSync();
        expect(text, contains('Single-Crust Pie Dough for Custard Pies'));
      });

      test('a hand-edited file is preserved as a conflict copy on save', () {
        final exportFile = File(
          exportPathFor(config, manualSourceSlug, created.id),
        );
        final handEdited = '# my hand edit\n${exportFile.readAsStringSync()}';
        exportFile.writeAsStringSync(handEdited);

        updateRecipe(db, config, created.id, {'category': 'Cakes'});

        final conflicts = exportFile.parent
            .listSync()
            .whereType<File>()
            .where((f) => f.path.contains('${created.id}.conflict-'))
            .toList();
        expect(
          conflicts,
          hasLength(1),
          reason: 'the hand edit must not be silently overwritten',
        );
        expect(conflicts.single.readAsStringSync(), handEdited);
        expect(
          exportFile.readAsStringSync(),
          contains('category: Cakes'),
        );
      });

      test('update of a missing recipe -> 404', () {
        expect(
          () => updateRecipe(db, config, 'no-such-recipe', {'title': 'X'}),
          throwsA(isA<NotFoundException>()),
        );
      });
    });

    group('delete', () {
      test('runs the backup hook, removes the row and the export', () {
        var backedUp = false;
        deleteRecipe(
          db,
          config,
          created.slug,
          beforeDestructive: () => backedUp = true,
        );
        expect(backedUp, isTrue);
        expect(db.recipeExists(created.id), isFalse);
        expect(
          File(
            exportPathFor(config, manualSourceSlug, created.id),
          ).existsSync(),
          isFalse,
        );
        // The conflict copy from the earlier test is operator data — kept.
        final conflicts =
            Directory(
              '${config.libraryDir}/$manualSourceSlug/recipes',
            ).listSync().whereType<File>().where(
              (f) => f.path.contains('.conflict-'),
            );
        expect(conflicts, isNotEmpty);
      });

      test('tags orphaned by the delete disappear from the tag list', () {
        expect(
          db.listTags().where((tag) => tag.name == 'dessert'),
          isEmpty,
          reason: 'the only dessert-tagged recipe in this database is gone',
        );
      });

      test('delete of a missing recipe -> 404', () {
        expect(
          () => deleteRecipe(db, config, created.id),
          throwsA(isA<NotFoundException>()),
        );
      });
    });
  });

  group('hand-set serves survives unrelated edits (review B9/Y1)', () {
    test('a category edit keeps a scan-imported serves; a servings edit '
        're-derives', () {
      // A real yield-only recipe: its servings text parses to no count, so
      // any stored serves can only be a hand-set override.
      final vinaigrette = loadCorpusRecipe('0038-foolproof-vinaigrette.yaml');
      expect(vinaigrette.serves, isNull, reason: 'yield-only fixture');
      final doc = vinaigrette.toMap();
      final created = createRecipe(db, config, {
        for (final key in editableRecipeKeys)
          if (doc.containsKey(key)) key: doc[key],
      }).recipe;
      expect(created.serves, isNull);

      // The library scan imports a hand-edited file verbatim ("file wins");
      // simulate its upsert of a hand-set serves on this yield-only recipe.
      final handEdited = created.copyWith(
        serves: const Serves(min: 8, max: 8),
      );
      db.upsertRecipe(
        handEdited,
        sourceSlug: manualSourceSlug,
        contentHash: contentHashOfText(RecipeYamlCodec.encode(handEdited)),
      );

      final updated = updateRecipe(db, config, created.id, {
        'category': 'Dressings',
      }).recipe;
      expect(
        updated.serves?.min,
        8,
        reason: 'an unrelated edit must not revert the hand-set value',
      );

      final rederived = updateRecipe(db, config, created.id, {
        'servings': 'SERVES 4',
      }).recipe;
      expect(
        rederived.serves?.min,
        4,
        reason: 'editing the servings text itself re-derives',
      );

      deleteRecipe(db, config, created.id);
    });
  });

  group('step numbering (review B4)', () {
    test('a save preserves meaningful duplicate step numbers', () {
      // 0485-steak-fajitas encodes the book's alternate branches as two
      // steps sharing a number (charcoal step 2 vs gas step 2). A routine
      // save must not linearize that run — ~103 corpus recipes carry one.
      final fajitas = loadCorpusRecipe('0485-steak-fajitas.yaml');
      final authored = [for (final step in fajitas.steps) step.number];
      expect(
        authored,
        isNot([for (var i = 1; i <= authored.length; i++) i]),
        reason: 'the fixture really is non-sequential',
      );

      final doc = fajitas.toMap();
      final result = createRecipe(db, config, {
        for (final key in editableRecipeKeys)
          if (doc.containsKey(key)) key: doc[key],
      });
      expect(
        [for (final step in result.recipe.steps) step.number],
        authored,
      );
      deleteRecipe(db, config, result.recipe.id);
    });

    test('a broken numbering is still normalized to 1..n', () {
      // Synthesized negative path: no corpus recipe carries a gapped run.
      final result = createRecipe(db, config, {
        'title': 'Gapped numbering',
        'steps': [
          {'number': 3, 'text': 'first'},
          {'number': 9, 'text': 'second'},
        ],
      });
      expect([for (final step in result.recipe.steps) step.number], [1, 2]);
      deleteRecipe(db, config, result.recipe.id);
    });
  });
}
