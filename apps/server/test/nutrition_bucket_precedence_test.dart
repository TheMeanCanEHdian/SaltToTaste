import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

/// A weak automatic match with NO grams used to bucket as `no_grams` — the
/// calm blue "no amount" — because the grams check came before the
/// confidence check. The Tarte Tatin's liqueur line matched a candy bar at
/// 0.41 and never looked wrong. Both implementations (salt_shared's
/// matchBucketFor for the app, the SQL CASE for the admin queue) now put a
/// low-confidence auto match in `check` first.
void main() {
  test('low confidence outranks no amount, in Dart', () {
    expect(
      matchBucketFor(
        status: 'auto',
        fdcId: 168761,
        grams: null,
        confidence: 0.41,
      ),
      MatchBucket.check,
    );
    // The other corners are unchanged.
    expect(
      matchBucketFor(
        status: 'auto',
        fdcId: 168761,
        grams: null,
        confidence: 0.9,
      ),
      MatchBucket.noAmount,
    );
    expect(
      matchBucketFor(
        status: 'auto',
        fdcId: 168761,
        grams: 28,
        confidence: 0.41,
      ),
      MatchBucket.check,
    );
    expect(
      matchBucketFor(
        status: 'overridden',
        fdcId: 168761,
        grams: null,
        confidence: 1,
      ),
      MatchBucket.noAmount,
      reason:
          'a human pick with no amount is an unfinished fix, not a wrong food',
    );
  });

  test('…and in the SQL queue counts', () {
    final dir = Directory.systemTemp.createTempSync('salt_bucket_prec');
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(() {
      db.dispose();
      dir.deleteSync(recursive: true);
    });
    db
      ..upsertSource(slug: 'manual', name: 'Manual', type: 'manual')
      ..upsertRecipe(
        const Recipe(
          id: 'r-liqueur',
          slug: 'r-liqueur',
          title: 'Tarte',
          source: RecipeSource(name: 'Manual', type: 'manual'),
          ingredients: [
            IngredientGroup(
              items: [IngredientLine(raw: '2 tablespoons Grand Marnier')],
            ),
          ],
        ),
        sourceSlug: 'manual',
        contentHash: 'x',
      )
      ..upsertIngredientMatch(
        const IngredientMatchRow(
          recipeId: 'r-liqueur',
          position: 0,
          raw: '2 tablespoons Grand Marnier',
          fdcId: 168761,
          description: 'Candies, NESTLE, 100 GRAND Bar',
          dataType: 'SR Legacy',
          confidence: 0.41,
          grams: null,
          gramSource: null,
          status: 'auto',
          itemKey: 'grand marnier',
        ),
      );
    expect(db.nutritionReviewCounts(), {'check': 1});
  });
}
