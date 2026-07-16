import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/services/library_io.dart';
import 'package:salt_server/src/services/serves_backfill.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';

/// The serves-vs-yield backfill, driven by two real corpus recipes: a pie
/// dough whose verbatim servings is a YIELD ('MAKES ENOUGH FOR ONE 9-INCH
/// PIE') and the Bundt cake, which really does state 'SERVES 12'.
void main() {
  if (!corpusAvailable) {
    test(
      'corpus-backed tests (skipped: corpus absent)',
      () {},
      skip: 'ATK corpus not present; set SALT_CORPUS_DIR',
    );
    return;
  }

  const sourceSlug = 'test-source';
  late Directory tempDir;
  late ServerConfig config;
  late SaltDatabase db;

  /// Stores [recipe] the way an import would, with [serves] forced into the
  /// document — reproducing a row written before the parser told a yield
  /// from a serving count.
  Recipe storeWithServes(Recipe recipe, Serves? serves) {
    final map = recipe.toMap();
    map['serves'] = serves?.toMap();
    final stale = RecipeMapper.fromMap(map);
    final canonical = RecipeYamlCodec.encode(stale);
    db.upsertRecipe(
      stale,
      sourceSlug: sourceSlug,
      contentHash: contentHashOfText(canonical),
    );
    exportRecipeYaml(
      config: config,
      sourceSlug: sourceSlug,
      recipeId: stale.id,
      canonical: canonical,
    );
    return stale;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('salt-backfill-test');
    config = ServerConfig(
      dataDir: tempDir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    );
    db = SaltDatabase.open(config.dbPath)
      ..upsertSource(slug: sourceSlug, name: 'Test', type: 'epub');
  });

  tearDown(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  test('clears a yield that had been stored as a serving count', () {
    final dough = loadCorpusRecipe('0972-basic-double-crust-pie-dough.yaml');
    // Precondition: this recipe states a yield, not servings.
    expect(dough.servings, 'MAKES ENOUGH FOR ONE 9-INCH PIE');
    // The old parser read 'ONE' as a count and stored serves 1.
    final stale = storeWithServes(dough, const Serves(min: 1, max: 1));
    expect(db.recipeByIdOrSlug(stale.id)!.recipe.serves?.min, 1);

    expect(backfillServes(db, config), 1);

    final fixed = db.recipeByIdOrSlug(stale.id)!.recipe;
    expect(fixed.serves, isNull, reason: 'a yield states no serving count');
    // The verbatim yield survives — it is what the UI now shows.
    expect(fixed.servings, 'MAKES ENOUGH FOR ONE 9-INCH PIE');
  });

  test('rewrites the exported YAML and the content hash', () {
    final dough = loadCorpusRecipe('0972-basic-double-crust-pie-dough.yaml');
    final stale = storeWithServes(dough, const Serves(min: 1, max: 1));
    final staleHash = db.contentHashOf(stale.id);
    final exportFile = File(exportPathFor(config, sourceSlug, stale.id));
    expect(exportFile.readAsStringSync(), contains('min: 1'));

    backfillServes(db, config);

    expect(db.contentHashOf(stale.id), isNot(staleHash));
    final rewritten = exportFile.readAsStringSync();
    expect(rewritten, contains('serves: null'));
    // The rewritten file must still decode, with no serving count.
    expect(RecipeYamlCodec.decode(rewritten).recipe.serves, isNull);
  });

  test('leaves a real SERVES count alone', () {
    final bundt = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
    expect(bundt.servings, 'SERVES 12');
    final stored = storeWithServes(bundt, const Serves(min: 12, max: 12));
    final hash = db.contentHashOf(stored.id);

    expect(backfillServes(db, config), 0, reason: 'nothing to correct');

    expect(db.recipeByIdOrSlug(stored.id)!.recipe.serves?.min, 12);
    expect(db.contentHashOf(stored.id), hash, reason: 'row untouched');
  });

  test('runs once: a second pass is a no-op', () {
    final dough = loadCorpusRecipe('0972-basic-double-crust-pie-dough.yaml');
    storeWithServes(dough, const Serves(min: 1, max: 1));

    expect(backfillServes(db, config), 1);
    expect(db.getSetting(servesBackfillSetting), isNotNull);
    // Even with another stale row present, the marker stops a second pass.
    final bundt = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
    storeWithServes(bundt, const Serves(min: 99, max: 99));
    expect(backfillServes(db, config), 0);
    expect(db.recipeByIdOrSlug(bundt.id)!.recipe.serves?.min, 99);
  });

  test('preserves a hand-edited library file as a conflict copy', () {
    final dough = loadCorpusRecipe('0972-basic-double-crust-pie-dough.yaml');
    final stale = storeWithServes(dough, const Serves(min: 1, max: 1));
    final exportFile = File(exportPathFor(config, sourceSlug, stale.id));
    // Someone edited the YAML by hand while the server was down.
    exportFile.writeAsStringSync(
      '# hand edited\n${exportFile.readAsStringSync()}',
    );

    backfillServes(db, config);

    final conflicts = exportFile.parent
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('.conflict-'))
        .toList();
    expect(conflicts, hasLength(1), reason: 'hand edit must not be clobbered');
    expect(conflicts.single.readAsStringSync(), contains('# hand edited'));
  });
}
