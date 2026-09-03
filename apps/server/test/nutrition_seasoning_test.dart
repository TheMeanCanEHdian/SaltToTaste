import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// "Salt and pepper" with no amount used to match green bell peppers at 0.47
/// and sit in the review queue on every sweep. Through the real engine on a
/// real corpus soup, such a line is now confirmed as seasoning to taste —
/// while a salt line WITH an amount (the Bundt cake's teaspoon) still matches
/// "Salt, table" from the recorded FDC answer.
void main() {
  group('seasoning to taste', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late Recipe soup;
    late Recipe bundt;
    late Recipe acquacotta;
    late Recipe tarte;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-seasoning-test');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath);
      final sourceRoot = Directory('${tempDir.path}/source')
        ..createSync(recursive: true);
      Directory('${sourceRoot.path}/recipes').createSync();
      for (final name in [
        '0002-classic-chicken-noodle-soup.yaml',
        '0857-rich-chocolate-bundt-cake.yaml',
        '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml',
        '1005-30-minute-tarte-tatin.yaml',
      ]) {
        File(
          '$corpusRecipesDir/$name',
        ).copySync('${sourceRoot.path}/recipes/$name');
      }
      importSourceRoot(sourceRootPath: sourceRoot.path, db: db, config: config);
      soup = db.recipeByIdOrSlug('classic-chicken-noodle-soup')!.recipe;
      bundt = db.recipeByIdOrSlug('rich-chocolate-bundt-cake')!.recipe;
      acquacotta = db
          .recipeByIdOrSlug('acquacotta-tuscan-white-bean-and-escarole-soup')!
          .recipe;
      tarte = db.recipeByIdOrSlug('30-minute-tarte-tatin')!.recipe;
      final provider = FixtureProvider();
      for (final recipe in [soup, bundt, acquacotta, tarte]) {
        await matchAndCompute(db, provider, recipe);
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    IngredientMatchRow rowWhere(
      Recipe recipe,
      bool Function(IngredientLine) pick,
    ) {
      final lines = nutritionLines(recipe);
      final position = lines.indexWhere(pick);
      expect(position, isNonNegative);
      return db
          .ingredientMatchesFor(recipe.id)
          .firstWhere((row) => row.position == position);
    }

    test('an amount-less "salt and pepper" line is a deliberate no-match', () {
      final row = rowWhere(
        soup,
        (line) =>
            line.amounts.isEmpty &&
            isSeasoningToTaste(normalizeItem(line.item ?? line.raw)),
      );
      expect(row.status, 'confirmed');
      expect(row.fdcId, isNull);
      expect(row.description, 'Seasoning to taste — no measurable amount');
      expect(
        matchBucketFor(
          status: row.status,
          fdcId: row.fdcId,
          grams: row.grams,
          confidence: row.confidence,
        ),
        MatchBucket.counted,
        reason: 'out of the review queue for good',
      );
    });

    test('the engine searches under the rewritten words: red pepper flakes '
        'find the spice, Grand Marnier finds liqueur, and the item key is '
        'unchanged', () {
      // Both queries were recorded from FDC. Under the recipe's own words
      // the recorded answers put a bell pepper and a candy bar first; the
      // fixtures hold those answers too, so a compute that searched the raw
      // item would land on them.
      final flakes = rowWhere(
        acquacotta,
        (line) => normalizeItem(line.item ?? line.raw) == 'red pepper flakes',
      );
      expect(flakes.description, 'Spices, pepper, red or cayenne');
      expect(flakes.itemKey, 'red pepper flakes', reason: 'identity stays');
      expect(flakes.status, 'auto');

      final liqueur = rowWhere(
        tarte,
        (line) => normalizeItem(line.item ?? line.raw) == 'grand marnier',
      );
      expect(liqueur.description, 'Liqueur');
      expect(liqueur.itemKey, 'grand marnier');
      expect(liqueur.confidence, greaterThanOrEqualTo(0.5));
    });

    test('a salt line with an amount is matched normally', () {
      final row = rowWhere(
        bundt,
        (line) =>
            line.amounts.isNotEmpty &&
            normalizeItem(line.item ?? line.raw) == 'table salt',
      );
      expect(row.status, 'auto');
      expect(row.description, 'Salt, table');
      expect(row.grams, isNotNull);
    });
  });
}
