import 'dart:io';

import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_server/src/services/slugify.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;
import 'package:test/test.dart';

import 'support/corpus.dart';

/// slugify("The Complete America's Test Kitchen TV Show Cookbook 2001–2023").
const _slug = 'the-complete-americas-test-kitchen-tv-show-cookbook-2001-2023';

const _recipeFiles = [
  '0020-sweet-potato-soup.yaml',
  '0038-foolproof-vinaigrette.yaml',
  '0857-rich-chocolate-bundt-cake.yaml',
];

const _imageFiles = [
  '0020-sweet-potato-soup-technique-01-01.jpg',
  '0038-foolproof-vinaigrette-hero.jpg',
  '0857-rich-chocolate-bundt-cake-hero.jpg',
];

void main() {
  group('slugify', () {
    test('folds punctuation, diacritics, and fractions', () {
      expect(
        slugify("The Complete America's Test Kitchen "
            'TV Show Cookbook 2001–2023'),
        _slug,
      );
      expect(slugify('Crème Brûlée!'), 'creme-brulee');
      expect(slugify('½ Batch Sauce'), '1-2-batch-sauce');
      expect(slugify('--Already--Slugged--'), 'already-slugged');
    });
  });

  group('importSourceRoot', skip: skipIfNoCorpus, () {
    late Directory sourceRoot;
    late Directory dataDir;
    late ServerConfig config;
    late SaltDatabase db;

    setUp(() {
      sourceRoot = Directory.systemTemp.createTempSync('salt_import_src');
      File('$corpusRoot/source.yaml')
          .copySync('${sourceRoot.path}/source.yaml');
      Directory('${sourceRoot.path}/recipes').createSync();
      Directory('${sourceRoot.path}/images').createSync();
      for (final name in _recipeFiles) {
        File('$corpusRecipesDir/$name')
            .copySync('${sourceRoot.path}/recipes/$name');
      }
      for (final name in _imageFiles) {
        File('$corpusImagesDir/$name')
            .copySync('${sourceRoot.path}/images/$name');
      }

      dataDir = Directory.systemTemp.createTempSync('salt_import_data');
      config = ServerConfig.fromEnvironment(
        environment: {'DATA_DIR': dataDir.path},
      );
      db = SaltDatabase.open(config.dbPath);
    });

    tearDown(() {
      db.dispose();
      sourceRoot.deleteSync(recursive: true);
      dataDir.deleteSync(recursive: true);
    });

    ImportSummary run({void Function(int, int)? onProgress}) =>
        importSourceRoot(
          sourceRootPath: sourceRoot.path,
          db: db,
          config: config,
          onProgress: onProgress,
        );

    test('imports three corpus recipes into the DB and the library', () {
      final progress = <(int, int)>[];
      final summary = run(onProgress: (done, total) {
        progress.add((done, total));
      });

      expect(summary.total, 3);
      expect(summary.imported, 3);
      expect(summary.updated, 0);
      expect(summary.skipped, 0);
      expect(summary.failed, 0);
      expect(summary.warnings, isEmpty);
      expect(progress, [(1, 3), (2, 3), (3, 3)]);
      expect(db.recipeCount(), 3);

      // The library holds canonical YAML that round-trips to a deep-equal
      // recipe for every imported file.
      for (final name in _recipeFiles) {
        final original = RecipeYamlCodec.decode(
          File('$corpusRecipesDir/$name').readAsStringSync(),
        ).recipe;
        final exported = File(
          '${config.libraryDir}/$_slug/recipes/${original.id}.yaml',
        );
        expect(exported.existsSync(), isTrue,
            reason: 'missing export for $name');
        final reDecoded =
            RecipeYamlCodec.decode(exported.readAsStringSync()).recipe;
        expect(reDecoded, equals(original));
        expect(
          File('${exported.path}.tmp').existsSync(),
          isFalse,
          reason: 'atomic-write temp file must not linger',
        );
      }

      // Hero and technique images were copied byte-for-byte.
      for (final name in _imageFiles) {
        final copied = File('${config.libraryDir}/$_slug/images/$name');
        expect(copied.existsSync(), isTrue, reason: 'missing image $name');
        expect(
          copied.lengthSync(),
          File('$corpusImagesDir/$name').lengthSync(),
        );
      }

      // source.yaml was copied verbatim and the source row stored.
      expect(
        File('${config.libraryDir}/$_slug/source.yaml').readAsStringSync(),
        File('$corpusRoot/source.yaml').readAsStringSync(),
      );
      final rawDb = raw_sqlite.sqlite3.open(config.dbPath);
      try {
        final row = rawDb.select(
          'SELECT slug, name, type, meta FROM sources WHERE slug = ?',
          [_slug],
        ).first;
        expect(
          row['name'],
          "The Complete America's Test Kitchen TV Show Cookbook 2001–2023",
        );
        expect(row['type'], 'epub');
        expect(row['meta'], contains('9781954210110'));
      } finally {
        rawDb.dispose();
      }
    });

    test('re-running the same import skips everything', () {
      run();
      final second = run();

      expect(second.total, 3);
      expect(second.imported, 0);
      expect(second.updated, 0);
      expect(second.skipped, 3);
      expect(second.failed, 0);
      expect(db.recipeCount(), 3);
    });

    test('a broken YAML file fails alone without stopping the run', () {
      File('${sourceRoot.path}/recipes/broken.yaml')
          .writeAsStringSync('title: "unterminated\n  - [what');

      final summary = run();

      expect(summary.total, 4);
      expect(summary.imported, 3);
      expect(summary.failed, 1);
      expect(summary.skipped, 0);
      expect(
        summary.warnings,
        contains(startsWith('broken.yaml:')),
      );
      expect(db.recipeCount(), 3);
      expect(
        File('${config.libraryDir}/$_slug/recipes/'
                'atk-tv-2023-0857-rich-chocolate-bundt-cake.yaml')
            .existsSync(),
        isTrue,
      );
    });

    test('a missing referenced image warns without failing the file', () {
      File('${sourceRoot.path}/images/0857-rich-chocolate-bundt-cake-hero.jpg')
          .deleteSync();

      final summary = run();

      expect(summary.imported, 3);
      expect(summary.failed, 0);
      expect(
        summary.warnings,
        contains(
          '0857-rich-chocolate-bundt-cake.yaml: image not found: '
          'images/0857-rich-chocolate-bundt-cake-hero.jpg',
        ),
      );
    });

    test('a missing source.yaml derives the name from the directory', () {
      File('${sourceRoot.path}/source.yaml').deleteSync();
      final derivedSlug = slugify(sourceRoot.uri.pathSegments
          .lastWhere((segment) => segment.isNotEmpty));

      final summary = run();

      expect(summary.imported, 3);
      expect(summary.warnings, contains(startsWith('source.yaml:')));
      expect(
        Directory('${config.libraryDir}/$derivedSlug/recipes')
            .listSync()
            .length,
        3,
      );
    });

    test('a source root without recipes/ is rejected', () {
      Directory('${sourceRoot.path}/recipes').deleteSync(recursive: true);
      expect(run, throwsA(isA<ValidationException>()));
      expect(
        () => importSourceRoot(
          sourceRootPath: '${sourceRoot.path}-does-not-exist',
          db: db,
          config: config,
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
