import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// apply-to-all resolves each target line's grams from the LINE's own words,
/// not from the singular decision key: the density and piece tables match by
/// substring on the query form ('nuts', 'oats', 'chocolate chips'), and the
/// singular key ('walnut') misses them — every propagated line landed with no
/// grams and dropped out of its label (both fleets, 2026-09-07). Two real
/// recipes that list "cup walnuts".
void main() {
  test(
    'apply-to-all keeps the gram estimate on a plural-keyed pantry item',
    skip: skipIfNoCorpus,
    () async {
      final tempDir = Directory.systemTemp.createTempSync('salt-apply-grams');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      final db = SaltDatabase.open(config.dbPath);
      addTearDown(db.dispose);
      final sourceRoot = Directory('${tempDir.path}/source')
        ..createSync(recursive: true);
      Directory('${sourceRoot.path}/recipes').createSync();
      for (final name in [
        '0040-arugula-salad-with-figs-prosciutto-walnuts-and-parmesan.yaml',
        '0315-pinto-beanbeet-burgers.yaml',
      ]) {
        File(
          '$corpusRecipesDir/$name',
        ).copySync('${sourceRoot.path}/recipes/$name');
      }
      importSourceRoot(sourceRootPath: sourceRoot.path, db: db, config: config);
      final provider = FixtureProvider();
      final salad = db
          .recipeByIdOrSlug(
            'arugula-salad-with-figs-prosciutto-walnuts-and-parmesan',
          )!
          .recipe;
      final burgers = db.recipeByIdOrSlug('pinto-beanbeet-burgers')!.recipe;
      await matchAndCompute(db, provider, salad);
      await matchAndCompute(db, provider, burgers);
      int walnuts(Recipe recipe) => nutritionLines(
        recipe,
      ).indexWhere((l) => l.raw.contains('cup walnuts'));
      expect(walnuts(salad), isNonNegative);
      expect(walnuts(burgers), isNonNegative);
      // Any recorded food will do: the grams come from the density table's
      // 'nuts' entry, keyed on the line's words.
      final applied = await applyMatchOverride(
        db,
        provider,
        salad,
        walnuts(salad),
        {
          'fdc_id': 173468,
          'apply_to_all': true,
        },
      );
      expect(applied!.lines, 1);
      final row = db
          .ingredientMatchesFor(burgers.id)
          .firstWhere((r) => r.position == walnuts(burgers));
      expect(row.fdcId, 173468);
      expect(row.grams, isNotNull, reason: "'walnut' must not miss 'nuts'");
      expect(row.gramSource, 'density');
    },
  );
}
