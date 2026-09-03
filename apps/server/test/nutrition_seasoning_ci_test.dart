import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/services/legacy_import.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/fdc_fixtures.dart';

/// The seasoning-to-taste shortcut where CI can see it: the one real
/// legacy-v0 recipe committed to this repo lists amount-less "Salt" and
/// "Pepper" lines. (nutrition_seasoning_test.dart carries the corpus-backed
/// cases; the review found every engine-level pin sat behind the corpus gate.)
void main() {
  late Directory tempDir;
  late SaltDatabase db;
  late Recipe recipe;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('salt-seasoning-ci');
    final config = ServerConfig(
      dataDir: tempDir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    );
    db = SaltDatabase.open(config.dbPath);
    final root = Directory('${tempDir.path}/legacy')..createSync();
    for (final entity in Directory(
      'test/fixtures/legacy-v0',
    ).listSync(recursive: true)) {
      final relative = entity.path.substring('test/fixtures/legacy-v0'.length);
      if (entity is Directory) {
        Directory('${root.path}$relative').createSync(recursive: true);
      } else if (entity is File) {
        File('${root.path}$relative').createSync(recursive: true);
        entity.copySync('${root.path}$relative');
      }
    }
    importLegacyRoot(sourceRootPath: root.path, db: db, config: config);
    recipe = db
        .recipeByIdOrSlug(
          'brown-butter-gemelli-with-asparagus-walnuts-and-lemony-ricotta',
        )!
        .recipe;
    await matchAndCompute(db, FixtureProvider(), recipe);
  });

  tearDownAll(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  test(
    'amount-less "Salt" and "Pepper" are confirmed as seasoning to taste',
    () {
      final lines = nutritionLines(recipe);
      final rows = db.ingredientMatchesFor(recipe.id);
      for (final word in ['Salt', 'Pepper']) {
        final position = lines.indexWhere((l) => l.raw == word);
        expect(position, isNonNegative, reason: '$word is a real fixture line');
        expect(lines[position].amounts, isEmpty);
        final row = rows.firstWhere((r) => r.position == position);
        expect(row.status, 'confirmed', reason: word);
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
        );
      }
    },
  );
}
