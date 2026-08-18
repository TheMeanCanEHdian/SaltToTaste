import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_server/src/services/legacy_import.dart';
import 'package:salt_server/src/services/library_io.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

/// P5 legacy v0 importer tests against the real sample recipe shipped with
/// the old Flask app (`test/fixtures/legacy-v0/`) — the actual format the
/// importer exists to migrate.
void main() {
  // A real legacy v0 (old Flask app) recipe, preserved as a fixture at
  // cutover when the Python tree was removed.
  const legacyRoot = 'test/fixtures/legacy-v0';

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
    final asparagus = lines.firstWhere(
      (line) => line.raw == '8 ounce Asparagus',
    );
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

    final images = Directory(
      '${config.libraryDir}/$legacySourceSlug/images',
    ).listSync().whereType<File>();
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

  // A real symlink is the one synthetic input the real-data rule allows: it
  // cannot be committed as a fixture. The recipe it hangs off is the real v0
  // sample; only the link is crafted.
  test('a legacy image symlinked out of the root is never copied', () {
    final scratch = _tempDir('salt-legacy-symlink');
    final secret = File('${scratch.path}/host-secret.txt')
      ..writeAsStringSync(_secretBytes);
    final root = Directory('${scratch.path}/root')..createSync();
    Directory('${root.path}/_recipes').createSync();
    Directory('${root.path}/_images').createSync();
    File('$legacyRoot/_recipes/$_fixtureFile')
        .copySync('${root.path}/_recipes/$_fixtureFile');
    Link('${root.path}/_images/$_fixtureImage').createSync(secret.path);

    final target = _freshTarget();
    final summary = importLegacyRoot(
      sourceRootPath: root.path,
      db: target.db,
      config: target.config,
    );

    expect(summary.imported, 1, reason: 'the recipe itself still imports');
    _expectSecretAbsent(target.config.libraryDir);
    expect(
      Directory(
        '${target.config.libraryDir}/$legacySourceSlug/images',
      ).listSync(),
      isEmpty,
    );
    expect(
      summary.warnings,
      contains(contains('resolves outside the source root')),
      reason: 'the operator must see that a file was skipped',
    );
  });

  // Drift guard: `_copyImages` in import_service.dart enforces the same
  // boundary and had no test of its own. The v1 source root below is real
  // data — the legacy importer's own canonical v2 export of the v0 fixture.
  test('the v1 importer also refuses a symlink out of the source root', () {
    importLegacyRoot(sourceRootPath: legacyRoot, db: db, config: config);
    final canonical = File(
      exportPathFor(config, legacySourceSlug, _fixtureRecipeId),
    ).readAsStringSync();
    final hero = RecipeYamlCodec.decode(canonical).recipe.images.hero;
    expect(hero, startsWith('images/'));

    final scratch = _tempDir('salt-v1-symlink');
    final secret = File('${scratch.path}/host-secret.txt')
      ..writeAsStringSync(_secretBytes);
    final root = Directory('${scratch.path}/legacy-v1-root')..createSync();
    Directory('${root.path}/recipes').createSync();
    Directory('${root.path}/images').createSync();
    File(
      '${root.path}/recipes/$_fixtureRecipeId.yaml',
    ).writeAsStringSync(canonical);
    Link('${root.path}/$hero').createSync(secret.path);

    final target = _freshTarget();
    final summary = importSourceRoot(
      sourceRootPath: root.path,
      db: target.db,
      config: target.config,
    );

    expect(summary.imported, 1);
    _expectSecretAbsent(target.config.libraryDir);
    expect(
      Directory('${target.config.libraryDir}/legacy-v1-root/images').listSync(),
      isEmpty,
    );
    expect(
      summary.warnings,
      contains(contains('image resolves outside the source root')),
    );
  });
}

const String _fixtureFile =
    'brown-butter-gemelli-with-asparagus,-walnuts,-and-lemony-ricotta.yaml';
const String _fixtureImage =
    'brown-butter-gemelli-with-asparagus,-walnuts,-and-lemony-ricotta.jpg';
const String _fixtureRecipeId =
    'v0-brown-butter-gemelli-with-asparagus-walnuts-and-lemony-ricotta';
const String _secretBytes = 'SECRET-HOST-BYTES-NOT-IN-THE-LIBRARY';

Directory _tempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

({ServerConfig config, SaltDatabase db}) _freshTarget() {
  final config = ServerConfig(
    dataDir: _tempDir('salt-import-target').path,
    logLevel: Level.WARNING,
    trustProxy: false,
  );
  final db = SaltDatabase.open(config.dbPath);
  addTearDown(db.dispose);
  return (config: config, db: db);
}

/// Fails if any byte of the symlink target reached the served library.
void _expectSecretAbsent(String libraryDir) {
  for (final entry in Directory(libraryDir).listSync(recursive: true)) {
    if (entry is File) {
      expect(entry.readAsStringSync(), isNot(contains(_secretBytes)));
    }
  }
}
