// Real corpus lines wrap across adjacent literals; the table keeps each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Matcher v35: the portobello caps (the owner's two requests, 2026-10-04:
/// the search 'mushrooms portabella raw' and the detail of 169255). Each
/// row is a real corpus line at the record, grams, bucket and basis the
/// cache-only replay of the live copy derives at v35; the answers are
/// recorded from that copy (tool/record_fdc_fixtures.dart --from-db).
void main() {
  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v35');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    return db;
  }

  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  test('the counted portobellos land on 169255 at its piece figure; the '
      'weighed caps keep the Foundation record', () async {
    for (final (file, _, raw, fdcId, grams, bucket, basis) in _rows) {
      final line = lineOf(raw);
      final db = tempDb()
        ..upsertSource(slug: 'src', name: 'Test', type: 'book');
      final recipe = Recipe(
        id: 'r',
        title: 'r',
        slug: 'r',
        source: const RecipeSource(name: 'Test', type: 'book'),
        ingredients: [
          IngredientGroup(items: [line]),
        ],
      );
      db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'hr');
      await matchAndCompute(db, FixtureProvider(), recipe);
      final row = db.ingredientMatchesFor('r').single;
      expect(row.fdcId, fdcId, reason: '$file: $raw');
      expect(row.grams?.toStringAsFixed(2), grams, reason: raw);
      expect(
        matchBucketFor(
          status: row.status,
          fdcId: row.fdcId,
          grams: row.grams,
          confidence: row.confidence,
          hold: row.hold,
          gramSource: row.gramSource,
        ).wire,
        bucket,
        reason: raw,
      );
      expect(gramBasisFor(db, line, row), basis, reason: raw);
    }
  });

  test('every row is a real corpus line at its position', () {
    for (final (file, position, raw, _, _, _, _) in _rows) {
      final line = nutritionLines(loadCorpusRecipe(file))[position];
      expect(line.raw, raw, reason: file);
      expect(lineOf(raw).amounts, line.amounts, reason: raw);
      expect(
        normalizeItem(lineItemOf(lineOf(raw))),
        normalizeItem(lineItemOf(line)),
        reason: raw,
      );
    }
  }, skip: skipIfNoCorpus);

  test("the piece figure is the record's own '1 piece whole' portion, which "
      'the whole-item finder alone reads as a dish serving', () async {
    final food = (await FixtureProvider().food(169255))!;
    final whole = food.portions.singleWhere(
      (p) => p.description == 'piece whole',
    );
    expect((whole.amount, whole.unit, whole.gramWeight), (1.0, null, 84.0));
    for (final raw in [
      '1 large portobello mushroom cap, cut into ½-inch pieces',
      '6–8 portobello mushrooms (each 4 to 6 inches), stemmed, wiped clean, gills removed, and cut into 2-inch wedges',
    ]) {
      final parsed = parseIngredientLine(raw);
      expect(
        resolveGrams(
          amounts: parsed.amounts,
          food: food,
          normalizedItem: normalizeItem(parsed.item ?? raw),
          raw: raw,
        )?.grams,
        // 'large' is no piece-table size; the bare 6–8 reads its midpoint.
        raw.startsWith('1 ') ? whole.gramWeight : 7 * whole.gramWeight,
        reason: raw,
      );
    }
  });
}

/// (corpus file, position, raw, fdc id, grams, bucket, basis).
const List<(String, int, String, int?, String?, String, String?)> _rows = [
  (
    '0006-hearty-beef-and-vegetable-stew.yaml',
    3,
    '1 large portobello mushroom cap, cut into ½-inch pieces',
    169255,
    '84.00',
    'counted',
    "1 × 84 g each · approximate (FDC's 'piece whole' portion read as one cap)",
  ),
  (
    '0546-stir-fried-portobellos-with-ginger-oyster-sauce.yaml',
    11,
    '6–8 portobello mushrooms (each 4 to 6 inches), stemmed, wiped clean, gills removed, and cut into 2-inch wedges',
    169255,
    '588.00',
    'counted',
    "6–8 × 84 g each · approximate (FDC's 'piece whole' portion read as one portobello)",
  ),
  // Not reached by v35's keys ('portobello mushroom caps' reads its v21
  // answer): a weight line, unchanged.
  (
    '0343-spaghetti-with-quick-mushroom-ragu.yaml',
    3,
    '8 ounces portobello mushroom caps, gills removed, caps cut into ½-inch pieces (about 1½ cups)',
    2003598,
    '226.80',
    'counted',
    'from 8 ounce',
  ),
];
