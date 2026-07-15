import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/services/library_io.dart';
import 'package:salt_server/src/services/library_scan.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';

/// P5 edit-service tests, driven by the real Bundt cake corpus recipe.
///
/// A client submission is built from the real document's editable fields —
/// exactly what the editor will send after loading the recipe.
void main() {
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

      final exportFile =
          File(exportPathFor(config, manualSourceSlug, created.id));
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

    test('a scan right after creating finds nothing to reconcile', () {
      final report = scanLibrary(db: db, config: config);
      expect(report.updatedFromDisk, isEmpty);
      expect(report.added, isEmpty);
      expect(report.skipped, isEmpty);
    });

    test('rejects a missing title', () {
      expect(
        () => createRecipe(db, config, {'servings': 'SERVES 4'}),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects a malformed ingredient shape with a 422, not a 500', () {
      expect(
        () => createRecipe(db, config, {
          'title': 'Broken',
          // A mapping where the schema requires a list of groups.
          'ingredients': {'items': 'nope'},
        }),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects an image path that escapes the library', () {
      expect(
        () => createRecipe(db, config, {
          'title': 'Sneaky',
          'images': {'hero': '../../etc/passwd'},
        }),
        throwsA(isA<ValidationException>()),
      );
    });

    group('update', () {
      test('merge semantics: a title-only submission keeps everything else',
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
      });

      test('an identical submission is a no-op', () {
        final before = db.contentHashOf(created.id);
        final result = updateRecipe(db, config, created.id, {
          'title': '${bundt.title} (Weeknight)',
        });
        expect(result.changed, isFalse);
        expect(db.contentHashOf(created.id), before);
      });

      test('explicit null clears an optional field', () {
        final result =
            updateRecipe(db, config, created.id, {'category': null});
        expect(result.recipe.category, isNull);
      });

      test('a hand-edited file is preserved as a conflict copy on save', () {
        final exportFile =
            File(exportPathFor(config, manualSourceSlug, created.id));
        final handEdited =
            '# my hand edit\n${exportFile.readAsStringSync()}';
        exportFile.writeAsStringSync(handEdited);

        updateRecipe(db, config, created.id, {'category': 'Cakes'});

        final conflicts = exportFile.parent
            .listSync()
            .whereType<File>()
            .where((f) => f.path.contains('${created.id}.conflict-'))
            .toList();
        expect(conflicts, hasLength(1),
            reason: 'the hand edit must not be silently overwritten');
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
          File(exportPathFor(config, manualSourceSlug, created.id))
              .existsSync(),
          isFalse,
        );
        // The conflict copy from the earlier test is operator data — kept.
        final conflicts = Directory(
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
}
