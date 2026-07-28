import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/admin_handlers.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

/// The cross-recipe nutrition-match review queue. Corpus-independent: the
/// buckets are the whole point, so a synthetic recipe with one match per
/// bucket exercises them exactly (and runs in CI). Negative rows here are
/// crafted match states, not fabricated recipe content.
void main() {
  group('nutrition-review queue', () {
    late Directory tempDir;
    late SaltDatabase db;

    IngredientMatchRow m(
      int pos, {
      int? fdcId,
      double conf = 0.9,
      double? grams = 100,
      String status = 'auto',
    }) => IngredientMatchRow(
      recipeId: 'r1',
      position: pos,
      raw: 'line $pos',
      fdcId: fdcId,
      description: fdcId == null ? null : 'Food $fdcId',
      dataType: fdcId == null ? null : 'SR Legacy',
      confidence: conf,
      grams: grams,
      gramSource: grams == null ? null : 'weight',
      status: status,
    );

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('salt_nutq_');
      db = SaltDatabase.open('${tempDir.path}/salt.db')
        ..upsertSource(slug: 'src', name: 'Test', type: 'book')
        ..upsertRecipe(
          const Recipe(
            id: 'r1',
            title: 'Soup',
            slug: 'soup',
            source: RecipeSource(name: 'Test', type: 'book'),
            ingredients: [
              IngredientGroup(
                items: [
                  IngredientLine(raw: 'a'),
                  IngredientLine(raw: 'b'),
                  IngredientLine(raw: 'c'),
                  IngredientLine(raw: 'd'),
                  IngredientLine(raw: 'e'),
                  IngredientLine(raw: 'f'),
                  IngredientLine(raw: 'g'),
                  IngredientLine(raw: 'h'),
                ],
              ),
            ],
          ),
          sourceSlug: 'src',
          contentHash: 'h',
        )
        ..upsertIngredientMatch(m(0, conf: 0, grams: null)) // no_match
        ..upsertIngredientMatch(m(1, fdcId: 5, grams: null)) // no_grams
        ..upsertIngredientMatch(m(2, fdcId: 5, conf: 0.4)) // check
        ..upsertIngredientMatch(m(3, fdcId: 5)) // counted
        // Confirmed water: no fdc, no grams — but resolved, so NOT flagged.
        ..upsertIngredientMatch(m(4, grams: null, status: 'confirmed'))
        ..upsertIngredientMatch(m(5, fdcId: 5, status: 'skipped')) // skipped
        // Overridden with NULL grams: the human picked a food expecting it
        // to count and it doesn't — an unfinished fix, so it STAYS flagged
        // (review B7's decided corner; it was once hidden as 'counted').
        ..upsertIngredientMatch(
          m(6, fdcId: 5, grams: null, status: 'overridden'),
        )
        ..upsertIngredientMatch(
          m(7, conf: 0, grams: null, status: 'unmatched'),
        );
    });

    tearDown(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    Map<String, int> countsOf(Map<String, Object?> body) => {
      for (final b in body['buckets']! as List)
        (b as Map)['id'] as String: b['count'] as int,
    };

    test('flags only unresolved problem lines; total excludes skipped', () {
      final body = nutritionReviewHandler(db, page: 1, limit: 50);
      expect(body['total'], 5, reason: 'no_match x2 + no_grams x2 + check');
      expect(countsOf(body), {
        'no_match': 2,
        'no_grams': 2,
        'check': 1,
        'skipped': 1,
      });
    });

    test('confirmed/resolved lines never appear in the queue', () {
      final body = nutritionReviewHandler(db, page: 1, limit: 50);
      final items = body['items']! as List;
      expect(items, hasLength(5));
      final positions = {for (final i in items) (i as Map)['position']};
      expect(
        positions,
        {0, 1, 2, 6, 7},
        reason:
            'confirmed water (4), counted (3), skipped (5) are excluded; '
            'overridden-with-no-grams (6) stays flagged (review B7)',
      );
    });

    test('default items are worst-confidence first, with recipe context', () {
      final items =
          nutritionReviewHandler(db, page: 1, limit: 50)['items']! as List;
      expect(
        [for (final i in items) (i as Map)['bucket']],
        ['no_match', 'no_match', 'check', 'no_grams', 'no_grams'],
        reason: 'confidence asc: 0.0, 0.0, 0.4, 0.9, 0.9',
      );
      final first = items.first as Map;
      expect((first['recipe']! as Map)['title'], 'Soup');
      expect((first['recipe']! as Map)['slug'], 'soup');
      expect(first['match'], isNull, reason: 'no_match line has no match');
      final check = items[2] as Map;
      expect((check['match']! as Map)['confidence'], 0.4);
    });

    test('a bucket filter narrows the list but not the counts', () {
      final body = nutritionReviewHandler(
        db,
        page: 1,
        limit: 50,
        bucket: 'no_grams',
      );
      final items = body['items']! as List;
      expect(items, hasLength(2));
      expect({for (final i in items) (i as Map)['position']}, {1, 6});
      // Counts stay whole-library so the chips don't move when filtering.
      expect(body['total'], 5);
      expect(countsOf(body)['check'], 1);
    });

    test('skipped is browsable via its own filter', () {
      final body = nutritionReviewHandler(
        db,
        page: 1,
        limit: 50,
        bucket: 'skipped',
      );
      final items = body['items']! as List;
      expect(items, hasLength(1));
      expect((items.single as Map)['position'], 5);
    });

    test('the SQL bucket CASE mirrors salt_shared matchBucketFor exactly', () {
      // ONE rule, two implementations (review B7): the app buckets rows in
      // Dart via matchBucketFor; the queue buckets in SQL. This parity pin
      // is what keeps them from drifting apart again — the seeded rows
      // cover every corner shape (auto/unmatched/confirmed/overridden/
      // skipped, with and without food and grams).
      final expected = <String, int>{};
      for (final row in db.ingredientMatchesFor('r1')) {
        final bucket = matchBucketFor(
          status: row.status,
          fdcId: row.fdcId,
          grams: row.grams,
          confidence: row.confidence,
        ).wire;
        expected[bucket] = (expected[bucket] ?? 0) + 1;
      }
      expect(db.nutritionReviewCounts(), expected);
    });

    test('an unknown bucket filter is rejected', () {
      expect(
        () => nutritionReviewHandler(db, page: 1, limit: 50, bucket: 'bogus'),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('queue queries match the live schema (empty DB, no corpus)', () {
    late Directory tempDir;
    late SaltDatabase db;

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('salt_nutq_schema_');
      db = SaltDatabase.open('${tempDir.path}/salt.db');
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('the handler runs end-to-end on an empty library', () {
      final body = nutritionReviewHandler(db, page: 1, limit: 10);
      expect(body['total'], 0);
      expect(body['items'], isEmpty);
      // All buckets present at count 0 so the chips render.
      expect(body['buckets']! as List, hasLength(4));
    });
  });
}
