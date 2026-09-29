import 'dart:convert';
import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/fdc_fixtures.dart';

/// A provider that throws on every call: FDC out of budget, or a replay that
/// must never reach the network. Not data — no answer is invented.
class _Offline implements NutritionProvider {
  int calls = 0;

  @override
  Future<List<FdcCandidate>> search(String query) async {
    calls += 1;
    throw NutritionProviderException('offline: $query');
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    calls += 1;
    throw NutritionProviderException('offline: $fdcId');
  }
}

/// Matcher v7 (checkpoint-4 audit and the v6 review fleets): every
/// mechanism pinned WITHOUT the corpus — real corpus lines and step texts
/// embedded as strings (recipe named on each), FDC answers from the recorded
/// fixtures (test/fixtures/fdc, the sweep snapshot's answers).
void main() {
  final provider = FixtureProvider();
  Future<List<RankedCandidate>> rank(String query, [String? recorded]) async =>
      rankCandidates(query, await provider.search(recorded ?? query));
  Future<FdcFood> food(int id) async => (await provider.food(id))!;

  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  GramResolution? gramsOf(String raw, [FdcFood? on]) {
    final line = lineOf(raw);
    return resolveGrams(
      amounts: line.amounts,
      food: on,
      normalizedItem: normalizeItem(lineItemOf(line)),
      raw: raw,
    );
  }

  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v7');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    db.upsertSource(slug: 'src', name: 'Test', type: 'book');
    return db;
  }

  Recipe recipeOf(
    SaltDatabase db,
    String id,
    List<String> raws, {
    List<String> steps = const [],
    List<IngredientLine>? lines,
  }) {
    final recipe = Recipe(
      id: id,
      title: id,
      slug: id,
      source: const RecipeSource(name: 'Test', type: 'book'),
      ingredients: [
        IngredientGroup(items: lines ?? [for (final raw in raws) lineOf(raw)]),
      ],
      steps: [
        for (final (i, text) in steps.indexed)
          RecipeStep(number: i + 1, text: text),
      ],
    );
    db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h$id');
    return recipe;
  }

  MatchBucket bucketOf(IngredientMatchRow row) => matchBucketFor(
    status: row.status,
    fdcId: row.fdcId,
    grams: row.grams,
    confidence: row.confidence,
    hold: row.hold,
    gramSource: row.gramSource,
  );

  // Red Beans and Rice (0712): Foundation 747431 "Beans, Dry, Red (0%
  // moisture)" publishes protein and fat, no energy and no carbohydrate —
  // held `no_nutrients`. (Napa cabbage was the example here until matcher
  // v10 read its nutrients from a sibling record: nutrition_v10_test.)
  const redBeans =
      '1 pound (about 2 cups) dried small red beans, picked over and rinsed';

  group('M1: apply-to-all reaches a held sibling on the same food', () {
    test('dried red beans: others counts the held sibling, the confirm lands '
        'on it and clears the hold', () async {
      final db = tempDb();
      final a = recipeOf(db, 'ra', [redBeans]);
      final b = recipeOf(db, 'rb', [redBeans]);
      for (final r in [a, b]) {
        await matchAndCompute(db, provider, r);
      }
      final before = db.ingredientMatchesFor('rb').single;
      expect(
        (before.hold, before.confidence >= lowConfidence),
        (
          'no_nutrients',
          true,
        ),
      );
      final item =
          ((await matchesBody(db, provider, a))['items']! as List).single
              as Map;
      expect(item['others'], 1);
      expect(item['others_lines'], 1);
      final applied = await applyMatchOverride(db, provider, a, 0, {
        'confirmed': true,
        'apply_to_all': true,
      });
      expect(applied!.lines, 1);
      final after = db.ingredientMatchesFor('rb').single;
      expect((after.status, after.confidence, after.hold), ('auto', 1, null));
      expect(bucketOf(after), MatchBucket.counted);
    });

    test('extra-virgin olive oil rows held at confidence 1 are counted in '
        'the reach and rewritten', () async {
      final db = tempDb();
      const raw = '¼ cup extra-virgin olive oil';
      final r1 = recipeOf(db, 'r1', [raw]);
      recipeOf(db, 'r2', [raw]);
      IngredientMatchRow held(String id) => IngredientMatchRow(
        recipeId: id,
        position: 0,
        raw: raw,
        fdcId: 748608,
        description: 'Oil, olive, extra virgin',
        dataType: 'Foundation',
        confidence: 1,
        grams: 54,
        gramSource: 'density',
        status: 'auto',
        hold: 'no_nutrients',
        itemKey: lineKeyOf(lineOf(raw)),
      );
      db
        ..upsertIngredientMatch(held('r1'))
        ..upsertIngredientMatch(held('r2'));
      final reach = decisionReach(
        db,
        lineKeyOf(lineOf(raw)),
        excluding: (recipeId: 'r1', position: 0),
        fdcId: 748608,
      );
      expect([for (final row in reach) row.recipeId], ['r2']);
      final applied = await applyMatchOverride(db, provider, r1, 0, {
        'confirmed': true,
        'apply_to_all': true,
      });
      expect(applied!.lines, 1);
      expect(db.ingredientMatchesFor('r2').single.hold, isNull);
    });
  });

  // v7's "a key-wide decision supersedes second_food" was reversed by
  // matcher v8 (checkpoint 5: it counted 48 lemon lines at the zest's
  // grams): a line hold never clears by key — pinned in
  // nutrition_v8_test.dart.

  group('M2: a person decision clears the hold', () {
    test('pick, skip and un-skip: the picked food is never held for the '
        "engine's old reason; un-skip re-derives the engine's own", () async {
      final db = tempDb();
      final b = recipeOf(db, 'rb', [redBeans]);
      await matchAndCompute(db, provider, b);
      IngredientMatchRow row() => db.ingredientMatchesFor('rb').single;
      // "Beans, kidney, red, mature seeds, raw" (173744) publishes energy.
      await applyMatchOverride(db, provider, b, 0, {'fdc_id': 173744});
      expect((row().status, row().hold), ('overridden', null));
      await applyMatchOverride(db, provider, b, 0, {'skipped': true});
      expect((row().status, row().hold), ('skipped', null));
      await applyMatchOverride(db, provider, b, 0, {'skipped': false});
      expect((row().status, row().fdcId, row().hold), ('auto', 173744, null));
      expect(bucketOf(row()), MatchBucket.counted);
      expect(db.nutritionFor('rb')!.status, 'complete');

      // The engine's own food (a library with no decision on the key):
      // skipped and back, its reason is re-derived.
      final fresh = tempDb();
      final c = recipeOf(fresh, 'rc', [redBeans]);
      await matchAndCompute(fresh, provider, c);
      await applyMatchOverride(fresh, provider, c, 0, {'skipped': true});
      expect(fresh.ingredientMatchesFor('rc').single.hold, isNull);
      await applyMatchOverride(fresh, provider, c, 0, {'skipped': false});
      expect(fresh.ingredientMatchesFor('rc').single.hold, 'no_nutrients');
      // A confirm is a decision: the hold goes.
      await applyMatchOverride(fresh, provider, c, 0, {'confirmed': true});
      expect(fresh.ingredientMatchesFor('rc').single.hold, isNull);
    });

    test('un-skip of a row an older build skipped with its hold, on a food '
        'nothing caches: the stale reason goes', () async {
      // Before the hold was cleared on skip (d60bcd1), a skipped row kept
      // the engine's reason; with no cached food it cannot be re-derived.
      final db = tempDb();
      final b = recipeOf(db, 'rb', [redBeans]);
      db.upsertIngredientMatch(
        IngredientMatchRow(
          recipeId: 'rb',
          position: 0,
          raw: redBeans,
          fdcId: 747431,
          description: 'Beans, Dry, Red (0% moisture)',
          dataType: 'Foundation',
          confidence: 0.61,
          grams: 453.6,
          gramSource: 'weight',
          status: 'skipped',
          hold: 'no_nutrients',
          itemKey: lineKeyOf(lineOf(redBeans)),
        ),
      );
      await applyMatchOverride(db, provider, b, 0, {'skipped': false});
      final row = db.ingredientMatchesFor('rb').single;
      expect((row.status, row.hold), ('auto', null));
    });
  });

  group('M3: an engine 0 g is counted whatever its score or hold but '
      'unnamed_food', () {
    // Crispy Fish Sandwiches (1081): "Peanut oil" 0.457, discarded at 0 g.
    const frying = '2 quarts peanut or vegetable oil for frying';

    test('matchBucketFor, recomputeTotals and the queue SQL agree', () async {
      final db = tempDb();
      final r = recipeOf(db, 'r1', [frying, 'Chili oil']);
      IngredientMatchRow zero(int position, String raw, String source) =>
          IngredientMatchRow(
            recipeId: 'r1',
            position: position,
            raw: raw,
            fdcId: 1,
            description: 'Oil',
            dataType: 'SR Legacy',
            confidence: 0.457,
            grams: 0,
            gramSource: source,
            status: 'auto',
            hold: position == 1 ? 'no_nutrients' : null,
            itemKey: lineKeyOf(lineOf(raw)),
          );
      db
        ..upsertIngredientMatch(zero(0, frying, 'discarded'))
        ..upsertIngredientMatch(zero(1, 'Chili oil', 'unmeasured'));
      await recomputeTotals(db, provider, r);
      expect(db.nutritionFor('r1')!.status, 'complete');
      for (final row in db.ingredientMatchesFor('r1')) {
        expect(bucketOf(row), MatchBucket.counted);
      }
      expect(db.nutritionReviewCounts(), {'counted': 2});
      final body = nutritionBody(db, r, forAdmin: true);
      expect(body['low_confidence'], 0);
    });

    test('a line naming no food waits for a person at 0 g: "2 tablespoons '
        'juice" (0661, the parser kept the amount in the item)', () async {
      final db = tempDb();
      const juice = '2 tablespoons juice';
      final r = recipeOf(
        db,
        'r1',
        const [],
        // As the corpus stores it: no amounts, the amount inside the item.
        lines: [const IngredientLine(raw: juice, item: juice)],
      );
      await matchAndCompute(db, provider, r);
      final row = db.ingredientMatchesFor('r1').single;
      expect(
        (row.grams, row.gramSource, row.hold),
        (0, 'unmeasured', 'unnamed_food'),
      );
      expect(bucketOf(row), MatchBucket.check);
      expect(db.nutritionReviewCounts(), {'check': 1});
      expect(db.nutritionFor('r1')!.status, 'partial');
      expect(nutritionBody(db, r, forAdmin: true)['low_confidence'], 1);
    });

    test('the same line saved from the editor, which parses its amount, '
        'waits for a person too', () async {
      final db = tempDb();
      // Mechouia (0661) as the editor stores it: 2 tablespoons of "juice".
      final line = lineOf('2 tablespoons juice');
      expect(line.amounts, isNotEmpty);
      final r = recipeOf(db, 'r1', const [], lines: [line]);
      await matchAndCompute(db, provider, r);
      final row = db.ingredientMatchesFor('r1').single;
      expect(row.hold, 'unnamed_food');
      expect(bucketOf(row), MatchBucket.check);
    });
  });

  group('M8/M9: a discarded medium under a pick, and its eaten part', () {
    test('re-picking the food of a frying-oil line keeps it discarded at '
        '0 g (Chicken Schnitzel 0116)', () async {
      final db = tempDb();
      final r = recipeOf(db, 'r1', ['2 cups vegetable oil for frying']);
      await matchAndCompute(db, provider, r);
      final row = db.ingredientMatchesFor('r1').single;
      expect((row.grams, row.gramSource), (0, 'discarded'));
      final other = (await rank('vegetable oil')).firstWhere(
        (c) => c.candidate.fdcId != row.fdcId,
      );
      await applyMatchOverride(db, provider, r, 0, {
        'fdc_id': other.candidate.fdcId,
      });
      final picked = db.ingredientMatchesFor('r1').single;
      expect(picked.status, 'overridden');
      expect((picked.grams, picked.gramSource), (0, 'discarded'));
    });

    test('Indoor Pulled Pork (0246): the 2 teaspoons rubbed on the pork '
        'count; Oven-Fried Chicken (0150) dissolves all its salt', () async {
      final db = tempDb();
      final pork = recipeOf(
        db,
        'pork',
        ['1 cup plus 2 teaspoons table salt'],
        steps: [
          // ignore: no_adjacent_strings_in_list
          'Dissolve 1 cup of the salt, ½ cup of the sugar, and 3 tablespoons '
              'of the liquid smoke in 1 gallon cold water in a large '
              'container. Submerge the pork in the brine, cover with plastic '
              'wrap, and refrigerate for 2 hours.',
          // ignore: no_adjacent_strings_in_list
          'While the pork brines, combine the mustard and remaining 2 '
              'teaspoons liquid smoke in a small bowl; set aside. Combine the '
              'black pepper, paprika, remaining 2 tablespoons sugar, '
              'remaining 2 teaspoons salt, and cayenne in a second small '
              'bowl; set aside.',
        ],
      );
      final chicken = recipeOf(
        db,
        'chicken',
        ['½ cup plus 2 tablespoons table salt'],
        steps: [
          // ignore: no_adjacent_strings_in_list
          'Add the buttermilk and stir until the salt and sugar are '
              'completely dissolved. Submerge the chicken in the brine and '
              'refrigerate for 2 to 3 hours.',
        ],
      );
      for (final r in [pork, chicken]) {
        await matchAndCompute(db, provider, r);
      }
      final kept = db.ingredientMatchesFor('pork').single;
      expect(kept.gramSource, 'discarded');
      expect(kept.grams, closeTo(2 * 4.92892 * 1.22, 0.01));
      expect(
        gramBasisFor(db, nutritionLines(pork).single, kept),
        'discarded in cooking — only "plus 2 teaspoons table salt" counted',
      );
      expect(bucketOf(kept), MatchBucket.counted);
      expect(db.nutritionFor('pork')!.totalGrams, closeTo(12.0, 0.1));
      final all = db.ingredientMatchesFor('chicken').single;
      expect((all.grams, all.gramSource), (0, 'discarded'));
    });
  });

  group('Run 041 critic: an amount edit on a decided discarded line', () {
    test('a confirmed frying-oil line typed over from 2 cups to 3 cups stays '
        'at 0 g discarded (Chicken Schnitzel 0116)', () async {
      final db = tempDb();
      final r = recipeOf(db, 'r1', ['2 cups vegetable oil for frying']);
      await matchAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 0, {'confirmed': true});
      final confirmed = db.ingredientMatchesFor('r1').single;
      expect(confirmed.status, 'confirmed');
      expect((confirmed.grams, confirmed.gramSource), (0, 'discarded'));
      expect(db.nutritionFor('r1')!.totalGrams, 0);
      // The amount typed over: the decided row is re-attached by key and
      // its grams re-derived — through the same outcome as a fresh compute.
      final edited = r.copyWith(
        ingredients: [
          IngredientGroup(items: [lineOf('3 cups vegetable oil for frying')]),
        ],
      );
      db.upsertRecipe(edited, sourceSlug: 'src', contentHash: 'edited');
      await matchAndCompute(db, provider, edited);
      final row = db.ingredientMatchesFor('r1').single;
      expect(row.raw, '3 cups vegetable oil for frying');
      expect(row.status, 'confirmed', reason: 'the decision stands');
      expect(row.fdcId, confirmed.fdcId);
      expect((row.grams, row.gramSource), (0, 'discarded'));
      expect(bucketOf(row), MatchBucket.counted);
      expect(db.nutritionFor('r1')!.totalGrams, 0);
    });
  });

  group('M4/M5/M6/M13/M15: lines, plus parts, ranges, portions, keys', () {
    test('M4: a lone qualifier reads segment by segment to the food', () {
      IngredientLine as(String raw, String item) => IngredientLine(
        raw: raw,
        item: item,
        amounts: parseIngredientLine(raw).amounts,
      );
      // Stuffed bell peppers (0308); Paris-Brest (0908); penne arrabbiata
      // (0334) — each item as the corpus parsed it.
      for (final (raw, item, read) in [
        (
          '4 medium red, yellow, or orange bell peppers (about 6 ounces '
              'each), ½ inch trimmed off tops, cores and seeds discarded',
          'medium red',
          'red yellow or orange bell peppers (about 6 ounces each)',
        ),
        // Matcher v8 drops the segments of prep words only.
        (
          '2 tablespoons toasted, skinned, and chopped hazelnuts',
          'toasted',
          'and chopped hazelnuts',
        ),
        (
          '¼ cup stemmed, patted dry, and minced pepperoncini',
          'stemmed',
          'and minced pepperoncini',
        ),
      ]) {
        final line = as(raw, item);
        expect(lineItemOf(line), read, reason: raw);
        expect(namesNoFood(line), isFalse, reason: raw);
      }
      // Bun cha (0559): a continuation of the line above names no food.
      expect(
        namesNoFood(
          as('lengthwise, seeded, and sliced thin on bias', 'lengthwise'),
        ),
        isTrue,
      );
    });

    test('M5: the same food both ways — a sauce apart from its chile, the '
        'wedges apart from the juice', () {
      // Chipotle lines (the corpus has both), Parmesan (0403).
      for (final raw in [
        // ignore: no_adjacent_strings_in_list
        '2 tablespoons minced canned chipotle chile in adobo sauce plus 2 '
            'teaspoons adobo sauce',
        '1 Parmesan cheese rind, plus 3 ounces Parmesan, shredded (1 cup)',
      ]) {
        expect(plusPartOf(raw)!.sameFood, isFalse, reason: raw);
      }
      const wedges =
          '2 tablespoons juice from 1 lemon, plus 1 lemon, cut into wedges';
      expect(plusPartOf(wedges)!.sameFood, isFalse);
      // Croissants (0758): the first part qualifies the same butter.
      expect(
        plusPartOf(
          // ignore: no_adjacent_strings_in_list
          '24 tablespoons European-style unsalted butter, very cold, plus 3 '
          'tablespoons unsalted butter at room temperature',
        )!.sameFood,
        isTrue,
      );
      // Still one food: "¾ cup plus 2 tablespoons", a part naming none.
      expect(
        plusPartOf('¾ cup plus 2 tablespoons vegetable oil')!.sameFood,
        isTrue,
      );
    });

    test('M6: "(3½- to 4-pound)" and "(1¼- to 1½-pound)" are ranges under '
        'both range-switch values', () {
      const chuck =
          '1 (3½- to 4-pound) boneless beef chuck-eye roast, pulled into two '
          'pieces at natural seam and trimmed';
      const hens = '4 (1¼- to 1½-pound) Cornish game hens, giblets discarded';
      const sibling =
          '1 (3½ to 4-pound) boneless chuck-eye roast, pulled into 2 pieces '
          'at the natural seam and fat trimmed';
      expect(parenWeightGrams(chuck), closeTo(4 * 453.592, 0.01));
      expect(parenWeightGrams(hens), closeTo(1.5 * 453.592, 0.01));
      expect(
        parenWeightGrams(chuck, midpoint: true),
        closeTo(3.75 * 453.592, 0.01),
      );
      expect(
        parenWeightGrams(sibling, midpoint: true),
        closeTo(3.75 * 453.592, 0.01),
      );
      expect(
        parenWeightGrams(hens, midpoint: true),
        closeTo(1.375 * 453.592, 0.01),
      );
      // B2: a whole-number hyphenated range keeps its upper bound.
      expect(
        parenWeightGrams(
          '4 (6- to 8-ounce) boneless, skinless chicken breasts, trimmed',
          midpoint: true,
        ),
        closeTo(8 * 28.3495, 0.01),
      );
    });

    test('M13: a volume line reads the portion it names, else the median '
        '(Pasta, dry, enriched 169736)', () async {
      final pasta = await food(169736);
      // Harira (0026): no "cup orzo" portion — the median, 91 g a cup.
      expect(gramsOf('½ cup orzo', pasta)!.grams, closeTo(45.5, 0.01));
      // Italian wedding soup (0402) names no shape: the median too.
      expect(gramsOf('1 cup ditalini pasta', pasta)!.grams, closeTo(91, 0.01));
      // "Nuts, almonds" (170567): "cup, sliced" 92 g for sliced almonds
      // (Almond-Crusted Chicken 0042), not the first-listed whole 143 g; a
      // line naming no form reads the whole nut since matcher v8 (the
      // median of whole, slivered, ground and sliced was 101.5 g; Nut-Crusted
      // Chicken 0117).
      final almonds = await food(170567);
      expect(gramsOf('1 cup sliced almonds', almonds)!.grams, 92);
      expect(gramsOf('1 cup almonds, chopped coarse', almonds)!.grams, 143);
    });

    // M14 (the restated-parenthetical guard) is not shipped: with M5 the
    // Parmesan line (0403) names a second food, so its plus part is never
    // added, and no other library line reached the guard (replay: 0 lines).
    test('M5 keeps the Parmesan line (0403) from summing its restatement', () {
      final parm = gramsOf(
        '1 Parmesan cheese rind, plus 3 ounces Parmesan, shredded (1 cup)',
      )!;
      expect(parm.grams, closeTo(236.588 * 0.42, 0.01));
      expect(parm.basis, isNot(contains('+')));
    });

    test('M5: wedges for serving are no second food; an eaten counted extra '
        'is', () async {
      final juice = await food(167747); // "Lemon juice, raw"
      final r = recipeOf(tempDb(), 'r1', const []);
      String? holdOf(String raw) =>
          engineOutcome(r, lineOf(raw), juice, gramsOf(raw, juice)).hold;
      // Chicken Under a Brick (0075): the wedges are served with it.
      expect(
        holdOf(
          '2 tablespoons juice from 1 lemon, plus 1 lemon, cut into wedges',
        ),
        isNull,
      );
      // Coconut Layer Cake (0878): the whole egg goes into the batter.
      expect(
        holdOf('5 large egg whites plus 1 large egg, at room temperature'),
        'second_food',
      );
    });

    test('M15: a second food is keyed from each part with its amounts '
        'cut', () {
      for (final (raw, key) in [
        ('2 large eggs plus 2 large yolks', 'egg plus yolk'),
        ('1 large egg plus 1 large yolk', 'egg plus yolk'),
        ('6 large eggs plus 2 large yolks', 'egg plus yolk'),
        (
          '10 (3-inch) strips orange peel, sliced thin lengthwise (¼ cup), '
              'plus ¼ cup juice (2 oranges)',
          'orange peel plus juice',
        ),
        (
          '¼ cup chopped pickled hot cherry peppers, plus ¼ cup brine',
          'pickled hot cherry pepper plus brine',
        ),
        (
          '1 teaspoon grated zest plus 1 tablespoon juice from 1 lemon',
          'lemon zest plus juice',
        ),
        // Recipe 0473: B's own amount in the first part's "A or B".
        (
          '2 sprigs fresh epazote or 8 to 10 sprigs fresh cilantro plus 1 '
              'sprig fresh oregano',
          'epazote or cilantro plus oregano',
        ),
      ]) {
        expect(lineKeyOf(lineOf(raw)), key, reason: raw);
        expect(decisionKeyFor(decisionItemOf(lineOf(raw))), key, reason: raw);
      }
    });
  });

  group('M7/M17/M18: detail fetches, pinches and sprigs', () {
    // Grill-Smoked Pork Chops (0598); 167833 publishes a raw refuse portion.
    const chops =
        '4 (12-ounce) bone-in pork rib chops, 1½ inches thick, trimmed';

    test('M7: a bone-in weight on a search hit fetches the detail once for '
        'its yield; offline, the compute fails (matcher v9) and a gross row '
        'stored before says no yield was applied', () async {
      final detail = await food(167833);
      final hit = FdcFood(
        fdcId: detail.fdcId,
        description: detail.description,
        dataType: detail.dataType,
        nutrientsPer100g: detail.nutrientsPer100g,
        portions: const [],
      );
      final db = tempDb();
      final fixtures = FixtureProvider();
      final (_, scaled) = await gramsFor(db, fixtures, hit, lineOf(chops));
      expect(fixtures.foodCalls, 1);
      expect(scaled!.grams, closeTo(4 * 12 * 28.3495 * 86 / 151, 0.01));
      expect(scaled.basis, contains('0.57 edible'));
      await gramsFor(db, fixtures, hit, lineOf(chops));
      expect(fixtures.foodCalls, 1, reason: 'cached once');

      final bare = tempDb();
      final offline = _Offline();
      // Offline, the yield fails the compute: a row counted at the gross
      // weight with a current hash would never fetch it again (checkpoint 5
      // review: 0201's chops counted 1,361 g).
      await expectLater(
        gramsFor(bare, offline, hit, lineOf(chops)),
        throwsA(isA<NutritionProviderException>()),
      );
      expect(offline.calls, 1);
      // A row a v8 compute stored at the gross weight, the detail cached
      // later: its basis never claims the yield.
      final gross = gramsOf(chops, hit)!;
      expect(gross.grams, closeTo(4 * 12 * 28.3495, 0.01));
      expect(gross.basis, contains('no edible yield'));
      bare.fdcFoodCachePut(167833, jsonEncode(detail.toJson()));
      final row = IngredientMatchRow(
        recipeId: 'r',
        position: 0,
        raw: chops,
        fdcId: 167833,
        description: detail.description,
        dataType: detail.dataType,
        confidence: 1,
        grams: gross.grams,
        gramSource: 'weight',
        status: 'auto',
      );
      final basis = gramBasisFor(bare, lineOf(chops), row)!;
      expect(basis, contains('no edible yield'));
      expect(basis, isNot(contains('0.57')));
    });

    test('M17: a pinch is the teaspoon portion ÷ 16 when the record has no '
        'dash; a sprig is an unmeasured 0 g (switch on)', () async {
      // Ultimate Cream of Tomato Soup (0013); "Spices, allspice, ground"
      // (171315) publishes tsp 1.9 g and no dash.
      final pinch = gramsOf('Pinch ground allspice', await food(171315))!;
      expect(pinch.grams, closeTo(1.9 / 16, 1e-9));
      // Black pepper's own dash still wins (0.1 g).
      expect(gramsOf('Pinch pepper', await food(170931))!.grams, 0.1);
      expect(sprigZeroOn, isTrue);
      // Best Beef Stew (0005).
      final sprig = gramsOf('4 sprigs fresh thyme')!;
      expect((sprig.grams, sprig.source), (0, GramSource.unmeasured));
      // French-Style Pork Chops (0211): the sprigs add 0 g, so the minced
      // part's portion is the line's source ("Thyme, fresh" 173470).
      final plus = gramsOf(
        '4 sprigs fresh thyme, plus ¼ teaspoon minced',
        await food(173470),
      )!;
      expect(plus.source, GramSource.portion);
      expect(plus.grams, greaterThan(0));
    });

    test('M18: an engine pick below the gate fetches no detail and stores '
        'no portion grams; a confirm resolves them', () async {
      final db = tempDb();
      final fixtures = FixtureProvider();
      // Ground Beef and Cheese Enchiladas (0486): "Adobo, with noodles"
      // (2708809) at 0.215. (Lime zest was the example until matcher v10
      // rewrote it to a pending search.)
      const chipotle =
          '1 tablespoon minced canned chipotle chile in adobo sauce';
      final r = recipeOf(db, 'r1', [chipotle]);
      await matchAndCompute(db, fixtures, r);
      final row = db.ingredientMatchesFor('r1').single;
      expect((row.fdcId, row.grams), (2708809, null));
      expect(row.confidence, lessThan(lowConfidence));
      expect(fixtures.foodCalls, 0);
      await applyMatchOverride(db, fixtures, r, 0, {'confirmed': true});
      final confirmed = db.ingredientMatchesFor('r1').single;
      expect(fixtures.foodCalls, 1);
      // Its FNDDS "1 tablespoon" portion.
      expect(confirmed.grams, closeTo(14, 0.01));
      expect(confirmed.status, 'confirmed');

      // A detail already cached is the engine's food, fetch or not: the pick
      // below the gate gets its portion grams with no provider call.
      final cached = tempDb()
        ..fdcFoodCachePut(2708809, jsonEncode((await food(2708809)).toJson()));
      final again = FixtureProvider();
      final r2 = recipeOf(cached, 'r2', [chipotle]);
      await matchAndCompute(cached, again, r2);
      expect(
        cached.ingredientMatchesFor('r2').single.grams,
        closeTo(14, 0.01),
      );
      expect(again.foodCalls, 0);
    });
  });

  group('M10/M11/M12/M16: ranker and rewrites on recorded answers', () {
    test('M10: a half counts like any count noun — breast halves (0002, '
        '0496) and spiral-sliced half hams (0251, 1081) keep their records; '
        'the fresh half ham (0249) is held off the cured one', () async {
      final breast = await rank('bone-in skin-on chicken breast halves');
      expect(
        breast.first.candidate.description,
        'Chicken, breast, meat and skin, raw',
      );
      expect(breast.first.confidence, greaterThanOrEqualTo(lowConfidence));
      final spiral = await rank('spiral-sliced bone-in half ham');
      expect(spiral.first.candidate.description, startsWith('Pork, cured'));
      expect(spiral.first.confidence, greaterThanOrEqualTo(lowConfidence));
      const fresh =
          '1 (6- to 8-pound) bone-in fresh half ham with skin, preferably '
          'shank end, rinsed';
      final ham = await rank('bone-in half ham with skin');
      expect(ham.first.candidate.description, contains('cured'));
      final r = recipeOf(tempDb(), 'r1', [fresh]);
      final outcome = engineOutcome(
        r,
        lineOf(fresh),
        ham.first.candidate.toFood(),
        null,
        picked: true,
      );
      // Its own reason since matcher v8 (a cured meat, not a dried herb).
      expect(outcome.hold, 'cured_for_fresh');
    });

    test('M11: the cap never leaves only a dish word — curry leaves (0109) '
        'are not every curry dish at 0.89', () async {
      final curry = await rank('curry leaves');
      expect(curry.first.confidence, lessThan(lowConfidence));
    });

    test('M12: the unsweetened-coconut target ranks the not-sweetened record '
        "first on the recorded 'nuts coconut meat dried' answer (pending one "
        'live search)', () async {
      expect(
        searchQueryFor('unsweetened coconut'),
        'nuts coconut meat dried not sweetened',
      );
      final target = await rank(
        'nuts coconut meat dried not sweetened',
        'nuts coconut meat dried',
      );
      expect(target.first.candidate.fdcId, 170170);
      // Under the old target the CREAMED record led.
      expect(
        (await rank('nuts coconut meat dried')).first.candidate.fdcId,
        168585,
      );
    });

    test('M16: chicken pieces are the whole bird; instant yeast; the raw '
        'Cornish hen; FNDDS "cooked" docked', () async {
      for (final key in [
        'bone-in skin-on chicken pieces',
        'bone-in chicken pieces',
      ]) {
        final whole = await rank(searchQueryFor(key));
        expect(whole.first.candidate.fdcId, 171447, reason: key);
      }
      final yeast = await rank(searchQueryFor('instant or rapid-rise yeast'));
      expect(yeast.first.candidate.fdcId, 2710005);
      expect(yeast.first.confidence, greaterThanOrEqualTo(lowConfidence));
      expect(
        (await rank('instant or rapid-rise yeast')).first.confidence,
        lessThan(lowConfidence),
      );
      for (final key in ['cornish game hens', 'whole cornish game hens']) {
        expect(
          searchQueryFor(key),
          'chicken cornish game hens meat and skin raw',
        );
      }
      final hen = await rank(
        'chicken cornish game hens meat and skin raw',
        'cornish game hens',
      );
      expect(hen.first.candidate.fdcId, 171507);
      // Under its own words the FNDDS cooked hen no longer leads.
      final own = await rank('cornish game hens');
      expect(own.first.candidate.description, isNot(contains('cooked')));
    });

    test('M16: the Tandoori line (0569) counts on the whole raw bird, not '
        '"Chicken skin"', () async {
      final db = tempDb();
      final r = recipeOf(db, 'r1', [
        // ignore: no_adjacent_strings_in_list
        '3 pounds bone-in, skin-on chicken pieces (split breasts cut in half, '
            'drumsticks, and/or thighs), trimmed and skin removed',
      ]);
      await matchAndCompute(db, provider, r);
      final row = db.ingredientMatchesFor('r1').single;
      expect(row.fdcId, 171447);
      expect(row.grams, closeTo(3 * 453.592, 0.01));
      expect(bucketOf(row), MatchBucket.counted);
    });

    test(
      'M16: variety, form, packing, equipment, salt and bun rules',
      () async {
        // 85 percent lean ground beef (13 lines): the generic 85% record.
        expect(
          (await rank('85 percent lean ground beef')).first.candidate.fdcId,
          171796,
        );
        // "¼ cup loosely packed fresh parsley leaves, torn" (0048).
        expect(
          normalizeItem('loosely packed fresh parsley leaves'),
          'parsley leaves',
        );
        final parsley = await rank(searchQueryFor('parsley leaves'));
        expect(parsley.first.confidence, greaterThanOrEqualTo(lowConfidence));
        // "1½ cups long-grain or basmati rice" (0062): not the instant rice.
        final rice = await rank('long-grain or basmati rice');
        expect(rice.first.candidate.description, isNot(contains('instant')));
        // "12 ounces cherry tomatoes, halved" (0011): matcher v8 retargets
        // 'ripe tomatoes', whose recorded answer leads with 170457 — roma
        // won under 'tomatoes' and has no volume portion.
        expect(searchQueryFor('cherry tomatoes'), 'ripe tomatoes');
        final tomatoes = await rank('ripe tomatoes');
        expect(tomatoes.first.candidate.fdcId, 170457);
        expect(tomatoes.first.confidence, greaterThanOrEqualTo(lowConfidence));
        expect((await rank('tomatoes')).first.candidate.fdcId, isNot(170457));
        // Crispy Thai Eggplant Salad (0053): its cup of cherry tomatoes.
        expect(
          gramsOf('1 cup cherry tomatoes, halved', await food(170457)),
          isNotNull,
        );
        // "1 large plastic oven bag" (0251).
        expect(isNonFood(normalizeItem('large plastic oven bag')), isTrue);
        // "2 teaspoons pink curing salt #1" (0091).
        final curing = await rank(
          searchQueryFor(normalizeItem('pink curing salt #1')),
        );
        expect(curing.first.candidate.fdcId, 173468);
        // "6 burger buns" (0314).
        expect(gramsOf('6 burger buns')!.grams, 6 * 52);
      },
    );
  });

  group('P1–P7: pins the fleets found missing', () {
    test('P1: a recompute rewrites the hold of an EXISTING row, both '
        'ways', () async {
      final db = tempDb();
      const evoo = '¼ cup extra-virgin olive oil';
      final r = recipeOf(db, 'r1', [evoo, redBeans]);
      IngredientMatchRow stale(int position, String raw, String? hold) =>
          IngredientMatchRow(
            recipeId: 'r1',
            position: position,
            raw: raw,
            fdcId: 1,
            description: 'Old',
            dataType: 'SR Legacy',
            confidence: 0.9,
            grams: 1,
            gramSource: 'weight',
            status: 'auto',
            hold: hold,
            itemKey: lineKeyOf(lineOf(raw)),
          );
      db
        ..upsertIngredientMatch(stale(0, evoo, 'second_food'))
        ..upsertIngredientMatch(stale(1, redBeans, null));
      await matchAndCompute(db, provider, r);
      final rows = db.ingredientMatchesFor('r1');
      expect([for (final row in rows) row.hold], [null, 'no_nutrients']);
    });

    test('P2: the variety words move recorded picks', () async {
      // Cremini lines (22): beech, 0.525, without the dock.
      expect(
        (await rank('cremini mushrooms')).first.candidate.description,
        'Mushroom, crimini',
      );
      // "3 cups medium-grain rice" (0101): brown led white by 0.015.
      expect((await rank('medium-grain rice')).first.candidate.fdcId, 168879);
      // Roma keeps the lead on its Foundation nudge, docked 0.03.
      final tomato = (await rank('tomatoes')).first;
      expect(tomato.candidate.description, 'Tomato, roma');
      expect(tomato.confidence, closeTo(0.92, 1e-9));
    });

    test('P3: boneless short ribs and shanks never take the yield path', () {
      // Braised Beef Short Ribs (0087); beef shanks.
      for (final raw in [
        '3½ pounds boneless beef short ribs, trimmed of excess fat',
        '3 pounds boneless long-cut beef shanks',
      ]) {
        expect(buysRefuse(raw), isFalse, reason: raw);
      }
      expect(
        buysRefuse('5 pounds bone-in English-style beef short ribs, trimmed'),
        isTrue,
      );
    });

    test('P5: a counted extra of the same food is not added (0461)', () {
      expect(
        gramsOf('1 medium onion, peeled, plus 1 small onion, minced')!.grams,
        110,
      );
    });

    test('P6: an ordinary 4-cup milk line is not cheese-making milk', () {
      final db = tempDb();
      // Classic Macaroni and Cheese (0300).
      final mac = recipeOf(
        db,
        'mac',
        ['5 cups milk'],
        steps: [
          // ignore: no_adjacent_strings_in_list
          'Whisking constantly, gradually add the milk; bring the mixture to '
              'a boil, whisking constantly (the mixture must reach a full '
              'boil to fully thicken).',
        ],
      );
      // Homemade Ricotta Cheese (0380).
      const gallon =
          '1 gallon pasteurized (not ultrapasteurized or UHT) whole milk';
      final ricotta = recipeOf(
        db,
        'ricotta',
        [gallon],
        steps: [
          // ignore: no_adjacent_strings_in_list
          'Let sit undisturbed until mixture fully separates into solid '
              'curds and translucent whey, 5 to 10 minutes.',
        ],
      );
      DiscardedMedium? of(Recipe r) {
        final line = nutritionLines(r).single;
        return discardedMediumOf(r, line, normalizeItem(lineItemOf(line)));
      }

      expect(of(mac), isNull);
      expect(of(ricotta), DiscardedMedium.cheeseMilk);
    });

    test('P7: the band and drained-can switches change their lines; held '
        'rows count as low confidence; the 0 g bases reach the body', () async {
      // The band: cremini's recorded top scores 0.525.
      final cremini = (await rank('cremini mushrooms')).first.confidence;
      expect(inBorderlineBand(cremini), isFalse, reason: 'switch off');
      expect(inBorderlineBand(cremini, on: true), isTrue);
      expect(inBorderlineBand(0.54, on: true), isFalse);
      expect(inBorderlineBand(0.52, on: true), isTrue);
      expect(inBorderlineBand(0.519, on: true), isFalse);
      // Drained: Pan Bagnat (0467) on "Fish, tuna, light, canned in oil,
      // drained solids" (173708: "can (12.5 oz), drained" 321 g).
      const tuna = '2 (6½-ounce) jars oil-packed tuna, drained';
      final record = await food(173708);
      const net = 2 * 6.5 * 28.3495;
      const share = 321 / (12.5 * 28.3495);
      expect(gramsOf(tuna, record)!.grams, closeTo(net * share, 0.01));
      expect(drainedCanGrams(net, record, tuna, on: false), isNull);
      expect(gramsOf(tuna)!.grams, closeTo(net, 0.01), reason: 'no record');

      final db = tempDb();
      final r = recipeOf(db, 'r1', [
        redBeans,
        '2 cups vegetable oil for frying',
        'Lemon wedges',
      ]);
      await matchAndCompute(db, provider, r);
      expect(nutritionBody(db, r, forAdmin: false)['low_confidence'], 1);
      final items = (await matchesBody(db, provider, r))['items']! as List;
      String? basis(int i) =>
          ((items[i] as Map)['match']! as Map)['gram_basis'] as String?;
      expect(basis(1), 'discarded in cooking — counted as 0 g');
      expect(basis(2), 'no amount on the line — counted as 0 g');
    });
  });

  group('P8: discard classes and hold wiring without the corpus', () {
    test('brine salt, brine sugar, a salt bath and a rub', () {
      final db = tempDb();
      DiscardedMedium? of(Recipe r, int i) {
        final line = nutritionLines(r)[i];
        return discardedMediumOf(r, line, normalizeItem(lineItemOf(line)));
      }

      // Perfect Roast Chicken (0134).
      final roast = recipeOf(
        db,
        'roast',
        ['½ cup table salt', '½ cup sugar'],
        steps: [
          // ignore: no_adjacent_strings_in_list
          'Dissolve the salt and sugar in 2 quarts cold water in a large '
              'container. Submerge the chicken in the brine, cover, and '
              'refrigerate for 1 hour.',
        ],
      );
      expect(of(roast, 0), DiscardedMedium.brine);
      expect(of(roast, 1), DiscardedMedium.brineSugar);
      // Grilled Cauliflower (0656): a dunk, no brine, no rub.
      final dunk = recipeOf(
        db,
        'dunk',
        ['¼ cup salt'],
        steps: [
          // ignore: no_adjacent_strings_in_list
          'Whisk 2 cups water, salt, and sugar in medium bowl until salt and '
              'sugar dissolve. Holding wedges by core, gently dunk in '
              'salt-sugar mixture until evenly moistened (do not dry—residual '
              'water will help cauliflower steam).',
        ],
      );
      expect(of(dunk, 0), DiscardedMedium.saltBath);
      // Slow-Roasted Pork Shoulder (0246): the rub stays on the meat.
      final rub = recipeOf(
        db,
        'rub',
        ['⅓ cup kosher salt'],
        steps: [
          // ignore: no_adjacent_strings_in_list
          'Combine the salt and brown sugar in a medium bowl. Rub the salt '
              'mixture over the entire pork shoulder and into the slits.',
        ],
      );
      expect(of(rub, 0), isNull);
    });

    // EXCEPTION to the real-data rule, stated on purpose: the corpus holds no

    // shortening or lard frying line, no 'for soaking' line and no dry-brine

    // step, yet other libraries do. These three valid inputs are synthesized

    // so the rules they exercise are not shipped unpinned (2026-09-27, Run 041;

    // the user decides whether the rules stay).

    test('"for brining" alone classifies a line; the rules no corpus line '
        'needs alone still read a typed one', () {
      final db = tempDb();
      DiscardedMedium? alone(String raw, {List<String> steps = const []}) {
        final r = recipeOf(db, 'r${raw.hashCode}', [raw], steps: steps);
        final line = nutritionLines(r).single;
        return discardedMediumOf(
          r,
          line,
          normalizeItem(lineItemOf(line)),
          grams: 600,
        );
      }

      // Real corpus lines, read without their recipes' steps.
      expect(alone('½ cup table salt, for brining'), DiscardedMedium.brine);
      expect(alone('¼ cup sugar, for brining'), DiscardedMedium.brineSugar);
      // Negative path (no corpus line: the verifier's typed inputs). A dry
      // brine's salt stays on the meat — the brine rule would read
      // "dry-brine" as a brine; shortening and lard fry; a soak says so.
      expect(
        alone(
          '¼ cup kosher salt',
          steps: [
            // ignore: no_adjacent_strings_in_list
            'Rub salt all over turkey and refrigerate, uncovered, to '
                'dry-brine for 24 hours.',
          ],
        ),
        isNull,
      );
      expect(
        alone('3 cups vegetable shortening, for frying'),
        DiscardedMedium.fryingOil,
      );
      expect(alone('2 pounds lard, for frying'), DiscardedMedium.fryingOil);
      expect(alone('6 cups buttermilk, for soaking'), DiscardedMedium.soak);
    });

    test('the engine writes second_food and discarded_medium; a fresh '
        "oregano line counts on the dried spice (the user's ruling R4, "
        '2026-09-28)', () async {
      final db = tempDb();
      final r = recipeOf(
        db,
        'r1',
        [
          // Tinga de Pollo (0482; the lemon zest line held here until
          // matcher v8 counts it by rule); Ciambotta (0405); Grilled
          // Cauliflower (0656).
          // ignore: no_adjacent_strings_in_list
          '2 tablespoons minced canned chipotle chile in adobo sauce plus 2 '
              'teaspoons adobo sauce',
          '⅓ cup fresh oregano leaves',
          '¼ cup salt',
        ],
        steps: [
          // ignore: no_adjacent_strings_in_list
          'Whisk 2 cups water, salt, and sugar in medium bowl until salt and '
              'sugar dissolve. Holding wedges by core, gently dunk in '
              'salt-sugar mixture until evenly moistened (do not dry—residual '
              'water will help cauliflower steam).',
        ],
      );
      await matchAndCompute(db, provider, r);
      final rows = db.ingredientMatchesFor('r1');
      expect(
        [for (final row in rows) row.hold],
        ['second_food', null, 'discarded_medium'],
      );
      expect(rows[1].description, 'Spices, oregano, dried');
      // A fresh volume at one third on the dried record (v14, Q2).
      expect(rows[1].grams, closeTo(16 / 3, 0.01));
      expect(bucketOf(rows[1]), MatchBucket.counted);
      // Held with no eaten part: no grams stored (v14, B6).
      expect(rows[2].grams, isNull);
      expect(bucketOf(rows[0]), MatchBucket.check);
      expect(bucketOf(rows[2]), MatchBucket.check);
    });
  });

  group('P9: every ranker rule shows on a recorded answer', () {
    test('the cook-state dock: roasted, a line naming the cooking, dry '
        'roasted nuts, beans from dried', () async {
      // "10 ounces boneless country-style pork ribs, trimmed" (0510): the
      // roasted record would lead at 0.763 undocked. (Since matcher v8 the
      // lean-and-fat broiled record, 169199, ties it and leads by answer
      // order: the 'and' of "lean and fat" no longer costs precision.)
      expect(
        (await rank('boneless country-style pork ribs')).first.candidate.fdcId,
        anyOf(169197, 169199),
      );
      // Turkey Tetrazzini (0303) names its cooking: no dock.
      final leftover = await rank(
        'leftover cooked boneless turkey or chicken meat',
      );
      expect(leftover.first.candidate.fdcId, 331960);
      expect(leftover.first.confidence, greaterThanOrEqualTo(lowConfidence));
      // Fried Rice (0521): "5 cups cold cooked white rice" names its
      // cooking, so FNDDS's "Rice, white, cooked, glutinous" is not docked
      // below the SR record (0.678 against 0.658).
      final rice = await rank('cold cooked white rice');
      expect(rice.first.candidate.fdcId, 2708422);
      // Chicken and Spiced Freekeh (1179): nuts are sold dry roasted.
      final pistachios = await rank('shelled without salt pistachios');
      expect(pistachios.first.candidate.fdcId, 170185);
      expect(pistachios.first.confidence, greaterThanOrEqualTo(lowConfidence));
      // Our Favorite Chili (0008): "from dried" is docked 0.10.
      expect(
        (await rank('dried pinto beans')).first.confidence,
        closeTo(0.79, 1e-9),
      );
    });

    test('a record naming no animal is not a wrong species; celery ribs; '
        'artichoke hearts', () async {
      // Fish and Chips (0255): the whitefish record names no listed animal.
      expect(
        (await rank(
          'cod or other thick whitefish fillets',
        )).first.candidate.fdcId,
        173711,
      );
      // "1 celery rib, sliced ¼ inch thick" (0002): 'rib' counts celery.
      expect(
        (await rank('celery rib')).first.confidence,
        greaterThanOrEqualTo(0.9),
      );
      // Bruschetta (1189): 'hearts' is the plant's, not the organ.
      expect(
        (await rank('artichoke hearts')).first.candidate.description,
        'Artichoke',
      );
    });

    test('imported is a variety; "lightly packed" drops the adverb; a romaine '
        'heart is romaine; whole peppercorns have their own density', () async {
      // Braised Lamb Shanks (1192): matcher v8 docks 'imported' only beside
      // a domestic record of the same cut, and no domestic fore-shank is in
      // the answer — the New Zealand fore-shank (lean and fat), not the
      // leg's shank half the v7 dock sent it to (174315).
      expect((await rank('lamb shanks')).first.candidate.fdcId, 172513);
      // "½ cup lightly packed baby spinach" (0216).
      expect(normalizeItem('lightly packed baby spinach'), 'baby spinach');
      // "1 romaine heart, cut into ½-inch pieces (about 3 cups)" (0044).
      expect(headNounOf(normalizeItem('romaine heart')), 'romaine');
      // Alcatra (0007): "1½ teaspoons peppercorns" on "Spices, pepper,
      // black" (170931) at 0.59 g/mL, not its ground teaspoon.
      final pepper = gramsOf('1½ teaspoons peppercorns', await food(170931))!;
      expect(pepper.source, GramSource.density);
      expect(pepper.grams, closeTo(4.4, 0.05));
    });

    test('the macro fallback steps down to a form record only', () {
      // Salami lines: "Salami, hard, sliced" publishes no energy.
      expect(
        sameFoodAsTop('salami', 'Salami, hard, sliced', 'Salami, NFS'),
        isTrue,
      );
      // New England Baked Beans (0678).
      expect(
        sameFoodAsTop(
          'dried navy beans',
          'Beans, Dry, Navy (0% moisture)',
          'Beans, navy, mature seeds, raw',
        ),
        isTrue,
      );
    });

    test('a typed line of count nouns alone keeps its tokens (negative '
        'path: no corpus line is all count nouns)', () async {
      final ranked = rankCandidates(
        'cloves',
        await provider.search('lemon zest'),
      );
      expect(ranked, isNotEmpty);
      expect(ranked.every((c) => !c.confidence.isNaN), isTrue);
      // Unguarded, an empty token set scores every record 1.0 ("Lemon, raw",
      // "Pie, lemon"): a junk pick would count at full confidence.
      expect(ranked.first.confidence, lessThan(lowConfidence));
    });
  });
}
