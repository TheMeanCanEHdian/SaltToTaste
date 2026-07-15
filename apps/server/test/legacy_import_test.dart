import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/services/legacy_import.dart';
import 'package:salt_server/src/services/library_io.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

/// P5 legacy v0 importer tests against the real sample recipe shipped with
/// the old Flask app (`saltToTaste/sample/`) — the actual format the
/// importer exists to migrate.
void main() {
  // `dart test` runs from the package root (apps/server); the legacy sample
  // ships in the repo's untouched Python tree.
  const legacyRoot = '../../saltToTaste/sample';

  late Directory tempDir;
  late ServerConfig config;
  late SaltDatabase db;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('salt-legacy-test');
    config = ServerConfig(
      dataDir: tempDir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    );
    db = SaltDatabase.open(config.dbPath);
  });

  tearDownAll(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  test('the sample directory is detected as a legacy root', () {
    expect(looksLikeLegacyRoot(legacyRoot), isTrue);
  });

  test('imports the real v0 sample with a faithful v2 mapping', () {
    final summary = importLegacyRoot(
      sourceRootPath: legacyRoot,
      db: db,
      config: config,
    );
    expect(summary.total, 1);
    expect(summary.imported, 1);
    expect(summary.failed, 0);

    final found = db.recipeByIdOrSlug(
      'v0-brown-butter-gemelli-with-asparagus-walnuts-and-lemony-ricotta',
    );
    expect(found, isNotNull);
    final recipe = found!.recipe;

    expect(
      recipe.title,
      'Brown Butter Gemelli with Asparagus, Walnuts, and Lemony Ricotta',
    );
    expect(found.sourceSlug, legacySourceSlug);
    expect(recipe.source.type, 'legacy-v0');
    expect(recipe.source.url, contains('hellofresh.com'));
    expect(recipe.servings, '2');
    expect(recipe.serves, const Serves(min: 2, max: 2));
    expect(recipe.times.prep, 30);
    expect(recipe.times.cook, isNull, reason: 'v0 stored null');
    expect(recipe.tags, ['meal', 'hello fresh', 'vegetarian']);
    expect(recipe.background, contains('pasta night'));
    expect(recipe.images.credit, contains('img.hellofresh.com'));
    expect(recipe.steps, hasLength(6));
    expect(recipe.steps.first.number, 1);
    expect(recipe.notes, isNull, reason: 'v0 notes was an empty list');

    // The flat strings became structured lines via the ingredient parser.
    final lines = recipe.ingredients.single.items;
    expect(lines, hasLength(14));
    final asparagus =
        lines.firstWhere((line) => line.raw == '8 ounce Asparagus');
    expect(asparagus.amounts.single.measure, Measure.weight);
    expect(asparagus.amounts.single.quantity, '8');
    expect(asparagus.amounts.single.unit, 'ounce');
    final salt = lines.firstWhere((line) => line.raw == 'Salt');
    expect(salt.amounts, isEmpty);

    // Old Edamam calories are dropped, loudly.
    expect(
      recipe.extraction?.warnings.single,
      contains('calories'),
    );
    expect(
      summary.warnings.where((warning) => warning.contains('calories')),
      isNotEmpty,
    );

    // Canonical YAML exported; the image copied under its route-safe name.
    final export = File(exportPathFor(config, legacySourceSlug, recipe.id));
    expect(export.existsSync(), isTrue);
    final reDecoded = RecipeYamlCodec.decode(export.readAsStringSync());
    expect(reDecoded.recipe.toMap(), recipe.toMap());

    final images = Directory('${config.libraryDir}/$legacySourceSlug/images')
        .listSync()
        .whereType<File>();
    expect(images, hasLength(1));
  });

  test('re-running is idempotent', () {
    final summary = importLegacyRoot(
      sourceRootPath: legacyRoot,
      db: db,
      config: config,
    );
    expect(summary.skipped, 1);
    expect(summary.imported, 0);
    expect(summary.updated, 0);
  });
}
