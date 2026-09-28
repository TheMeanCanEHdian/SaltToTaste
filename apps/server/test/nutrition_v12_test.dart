// Real corpus lines wrap across adjacent literals.
// ignore_for_file: no_adjacent_strings_in_list

import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/services/decision_rekey.dart';
import 'package:salt_server/src/services/item_key_backfill.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/fdc_fixtures.dart';

/// Matcher v12 (checkpoint 7): every mechanism pinned WITHOUT the corpus —
/// real corpus lines as strings (recipe named on each, the corpus's own
/// parse where the engine reads it), FDC answers recorded from sweep
/// snapshot 10.
void main() {
  final provider = FixtureProvider();
  Future<List<RankedCandidate>> rank(String query) async =>
      rankCandidates(query, await provider.search(query));

  IngredientLine count(String raw, String item, String quantity) =>
      IngredientLine(
        raw: raw,
        item: item,
        amounts: [
          Amount(measure: Measure.count, quantity: quantity, primary: true),
        ],
      );

  group('C1: the ranker strips "-es" only after s, ch, sh or o', () {
    test('"3 large egg whites" (Crunchy Baked Pork Chops, 0206) crosses the '
        'gate on the egg-white record it sat under at 0.415', () async {
      final top = (await rank('egg whites')).first;
      expect(top.candidate.fdcId, 747997);
      expect(top.confidence, closeTo(0.95, 0.001));
    });

    test('"2 pounds firm McIntosh apples" (Classic Apple Pie, 0977) reads '
        '"Apple, raw" as apple (0.485, was 0.06 in the replay) and stays '
        "under the gate: 'firm' is no credit word", () async {
      final top = (await rank('firm mcintosh apples')).first;
      expect(top.candidate.description, 'Apple, raw');
      expect(top.confidence, closeTo(0.485, 0.001));
      expect(belowConfidenceGate(top.confidence), isTrue);
    });

    test('"1 tablespoon minced Thai chiles" (Thai Grilled Cornish Game Hens, '
        '0642) stays in check on the sun-dried record: a dried record the '
        'line does not ask for keeps the count noun in the query', () async {
      final top = (await rank('thai chiles')).first;
      expect(top.candidate.description, 'Peppers, hot chile, sun-dried');
      expect(belowConfidenceGate(top.confidence), isTrue);
    });

    test('"-ches" and "-shes" lose their "es": "10 ounces frozen peaches, cut '
        'into 1-inch chunks …" (Slow-Roasted Pork Shoulder with Peach Sauce, '
        '0246) is "Peach, frozen", "8 ounces radishes, trimmed, halved, and '
        'sliced thin" (Red Snapper Ceviche, 0274) is "Radish"', () async {
      final peaches = (await rank('frozen peaches')).first;
      expect(peaches.candidate.fdcId, 2709253);
      expect(peaches.confidence, closeTo(0.99, 0.001));
      final radishes = (await rank('radishes')).first;
      expect(radishes.candidate.fdcId, 2709803);
      expect(radishes.confidence, closeTo(0.99, 0.001));
    });

    test(
      '"-ses" loses its "es": "3 ounces cheese (preferably mild cheddar) or '
      'a combination of cheeses, …" (Classic Grilled Cheese Sandwiches, '
      "0299) stays under the gate on its answer's one record, a salad",
      () async {
        final top = (await rank('cheese or a combination of cheeses')).first;
        expect(top.candidate.description, startsWith('Seven-layer salad'));
        expect(belowConfidenceGate(top.confidence), isTrue);
      },
    );

    test('tomatoes stay tomato: "-oes" still loses its "es", so the '
        'singular "Tomato, roma" covers a plural line as under v11', () async {
      final top = (await rank('tomatoes')).first;
      expect(top.candidate.description, 'Tomato, roma');
      expect(top.confidence, closeTo(0.92, 0.001));
    });
  });

  group('C1 guards: what the plain stem let cross the gate', () {
    test('"Spices," is a class: "½ teaspoon five-spice powder" (Beef Short '
        'Rib Ragu) is no chili powder, while a query naming the class keeps '
        'it', () async {
      final top = (await rank('five-spice powder')).first;
      expect(belowConfidenceGate(top.confidence), isTrue);
      final cayenne = rankCandidates(
        'spices pepper red cayenne',
        await provider.search('spices pepper red cayenne'),
      ).first;
      expect(cayenne.candidate.description, 'Spices, pepper, red or cayenne');
      expect(cayenne.confidence, 1.0);
    });

    test('a later segment\'s "spice" is the food\'s own word: "Spices, '
        'pumpkin pie spice" still covers "1 recipe spice paste (recipes '
        'follow)" (Best Grilled Chicken Thighs, 0629) as under v11', () async {
      final ranked = await rank('spice paste');
      final pie = ranked.firstWhere(
        (c) => c.candidate.description == 'Spices, pumpkin pie spice',
      );
      expect(pie.confidence, closeTo(0.441, 0.001));
    });

    test('"Beverages," is a class, not the ready-to-drink dock: "Beverages, '
        'coffee, instant, regular, powder" keeps 0.583 for "instant espresso '
        'powder"', () async {
      final top = (await rank('instant espresso powder')).first;
      expect(
        top.candidate.description,
        'Beverages, coffee, instant, regular, powder',
      );
      expect(top.confidence, closeTo(0.583, 0.001));
    });

    test('"⅓ cup pitted prunes" (Chicken Marbella) is no "Prune puree": a '
        'purée is a base-form change', () async {
      final top = (await rank('prunes')).first;
      expect(top.candidate.fdcId, 2758978); // Plums, dried (prunes), uncooked
      final puree = (await rank('prunes')).firstWhere(
        (c) => c.candidate.description == 'Prune puree',
      );
      expect(puree.confidence, lessThan(top.confidence));
    });

    test(
      '"1½ pounds marrow bones" (Simple Pot-au-Feu) stays under the gate '
      'on the one record its answer holds, an Alaska Native caribou',
      () async {
        final top = (await rank('marrow bones')).first;
        expect(top.candidate.description, contains('Alaska Native'));
        expect(top.docked, isTrue);
        expect(belowConfidenceGate(top.confidence), isTrue);
      },
    );

    test('"½ cup pitted niçoise olives" (Chicken Provençal) stays on "Olives, '
        'black": tapenade is a spread of them', () async {
      final ranked = await rank('nicoise olives');
      expect(ranked.first.candidate.description, 'Olives, black');
      expect(
        ranked
            .firstWhere((c) => c.candidate.description == 'Olive tapenade')
            .docked,
        isTrue,
      );
    });

    test('"1½ cups V8 juice" (Hearty Minestrone, 0028) is "Tomato and '
        'vegetable juice, 100%", not a V-FUSION blend its "Juices" now '
        'covers', () async {
      final top = (await rank('v8 juice')).first;
      expect(top.candidate.fdcId, 2709731);
      expect(top.confidence, closeTo(0.84, 0.001));
    });

    test('"2 large juice oranges" (Sangria) are oranges, not "Orange '
        'Pineapple Juice Blend"', () async {
      expect(searchQueryFor('juice oranges'), 'oranges');
      final top = (await rank('oranges')).first;
      expect(top.candidate.fdcId, 746771);
      expect(belowConfidenceGate(top.confidence), isFalse);
      final unwritten = (await rank('juice oranges')).first;
      expect(unwritten.candidate.description, 'Orange Pineapple Juice Blend');
    });
  });

  group('C2: zero-request rewrites and the normalizer', () {
    test(
      'the shrimp size words search the cached raw-shrimp answer: Banh Xeo '
      '(0560), Shrimp Tempura (0511), Garlicky Roasted Shrimp (0280)',
      () async {
        for (final raw in [
          '6 ounces medium-large shrimp (31 to 40 per pound), peeled, '
              'deveined, halved lengthwise, and halved crosswise',
          '1½ pounds colossal shrimp (8 to 12 per pound), peeled and deveined '
              '(see this page), tails left on',
          '2 pounds shell-on jumbo shrimp (16 to 20 per pound)',
        ]) {
          final item = parseIngredientLine(raw).item!;
          expect(
            searchQueryFor(normalizeItem(item)),
            'shrimp raw',
            reason: raw,
          );
        }
        final top = (await rank('shrimp raw')).first;
        expect(top.candidate.fdcId, 175179);
        expect(top.confidence, closeTo(0.953, 0.001));
      },
    );

    test('a skin-on salmon fillet searches the skinless answer: "4 (6- to '
        '8-ounce) skin-on salmon fillets" (Pan-Seared Brined Salmon), "1 '
        '(1-pound) skin-on salmon fillet" (Gravlax)', () async {
      expect(
        searchQueryFor('skin-on salmon fillets'),
        'skinless salmon fillet',
      );
      expect(searchQueryFor('skin-on salmon fillet'), 'skinless salmon fillet');
      final top = (await rank('skinless salmon fillet')).first;
      expect(top.candidate.fdcId, 2706284);
      expect(belowConfidenceGate(top.confidence), isFalse);
    });

    test('pepperoncini (Penne Arrabbiata: "¼ cup stemmed, patted dry, and '
        'minced pepperoncini"; its own answer is []) ranks "Peppers, hot, '
        'pickled" first', () async {
      expect(await provider.search('pepperoncini'), isEmpty);
      expect(searchQueryFor('pepperoncini'), 'pickled hot cherry peppers');
      final top = (await rank('pickled hot cherry peppers')).first;
      expect(top.candidate.fdcId, 2710095);
      expect(belowConfidenceGate(top.confidence), isFalse);
    });

    test('"¼ ounce chen pi" (Multicooker Hawaiian Oxtail Soup, 1172): a '
        'flagged approximation, counted as "Orange peel, raw"', () async {
      expect(searchQueryFor('chen pi'), 'orange peel');
      final top = (await rank('orange peel')).first;
      expect(top.candidate.fdcId, 169103);
      expect(belowConfidenceGate(top.confidence), isFalse);
    });

    test('"1 teaspoon grated fresh lime zest and" (Sweet and Saucy Glazed '
        'Salmon) loses its dangling connector: the lime-zest key and '
        'rewrite', () {
      const line = IngredientLine(
        raw: '1 teaspoon grated fresh lime zest and',
        item: 'grated fresh lime zest and',
        amounts: [
          Amount(
            measure: Measure.volume,
            quantity: '1',
            unit: 'teaspoon',
            primary: true,
          ),
        ],
      );
      expect(lineKeyOf(line), 'lime zest');
      expect(searchQueryFor(normalizeItem(lineItemOf(line))), 'lemon zest');
    });

    test(
      'the segments before the food are read past and a firmness dropped: "2 '
      'medium, firm, ripe tomatoes …" (Classic Greek Salad, 0048), "3 '
      'medium, ripe avocados" (Chunky Guacamole, 0472) — both cached',
      () {
        final tomatoes = count(
          '2 medium, firm, ripe tomatoes (6 ounces each), cored, seeded, and '
              'each tomato cut into 12 wedges',
          'medium',
          '2',
        );
        final avocados = count('3 medium, ripe avocados', 'medium', '3');
        expect(lineItemOf(tomatoes), 'medium ripe tomatoes (6 ounces each)');
        expect(normalizeItem(lineItemOf(tomatoes)), 'ripe tomatoes');
        expect(lineKeyOf(tomatoes), 'ripe tomato');
        expect(lineItemOf(avocados), 'medium ripe avocados');
        expect(normalizeItem(lineItemOf(avocados)), 'ripe avocados');
        expect(lineKeyOf(avocados), 'ripe avocado');
        // A colour segment still stays: "4 medium red, yellow, or orange bell
        // peppers …" (Classic Stuffed Bell Peppers, 0308).
        expect(
          lineKeyOf(
            count(
              '4 medium red, yellow, or orange bell peppers (about 6 ounces '
                  'each), ½ inch trimmed off tops, cores and seeds discarded',
              'medium red',
              '4',
            ),
          ),
          'red yellow or orange bell pepper',
        );
      },
    );

    test('the lines the size segment hid search recorded answers: "1 medium, '
        'ripe avocado, diced medium" (Chicken Enchiladas with Red Chile '
        'Sauce, 0487), "2 large, firm, ripe bananas, peeled and quartered" '
        '(Bananas Foster, 0959)', () async {
      final avocado = count(
        '1 medium, ripe avocado, diced medium',
        'medium',
        '1',
      );
      final bananas = count(
        '2 large, firm, ripe bananas, peeled and quartered',
        'large',
        '2',
      );
      expect(lineItemOf(bananas), 'large ripe bananas');
      final avocadoQuery = searchQueryFor(normalizeItem(lineItemOf(avocado)));
      final bananaQuery = searchQueryFor(normalizeItem(lineItemOf(bananas)));
      expect(avocadoQuery, 'ripe avocados');
      expect(bananaQuery, 'very ripe bananas');
      final avocadoTop = (await rank(avocadoQuery)).first;
      expect(avocadoTop.candidate.fdcId, 2710824);
      expect(belowConfidenceGate(avocadoTop.confidence), isFalse);
      final bananaTop = (await rank(bananaQuery)).first;
      expect(bananaTop.candidate.fdcId, 1105314);
      expect(belowConfidenceGate(bananaTop.confidence), isFalse);
    });
  });

  group('C3: a dozen', () {
    const mussels = mussels0105;

    test('"1 dozen mussels" is 12 mussels (180 g, not 15 g) keyed and '
        'searched as mussels', () async {
      expect(lineKeyOf(mussels), 'mussel');
      final query = normalizeItem(lineItemOf(mussels));
      expect(query, 'mussels');
      final top = (await rank(query)).first;
      expect(top.candidate.fdcId, 2706350);
      final grams = resolveGrams(
        amounts: mussels.amounts,
        food: await provider.food(2706350),
        normalizedItem: query,
        raw: mussels.raw,
      )!;
      expect(grams.grams, closeTo(180, 0.01));
    });
  });

  test('C4: the halibut lines search the raw-halibut query — pending one live '
      'search, so only its construction is pinned: Braised Halibut (0273), '
      'Cioppino (0108), Pan-Roasted Halibut Steaks', () {
    for (final item in [
      'skinless halibut fillets',
      'skinless halibut fillet',
      'halibut steaks',
    ]) {
      expect(
        searchQueryFor(item),
        'halibut atlantic and pacific raw',
        reason: item,
      );
    }
    expect(pendingSearches, contains('halibut atlantic and pacific raw'));
  });

  test('P1: a v11 decision on "dozen mussel" follows Paella\'s line to '
      '"mussel" at boot, decisions before rows', () {
    final dir = Directory.systemTemp.createTempSync('salt-v12');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    db.upsertSource(slug: 'src', name: 'Test', type: 'book');
    const recipe = Recipe(
      id: 'r0105',
      title: 'r0105',
      slug: 'r0105',
      source: RecipeSource(name: 'Test', type: 'book'),
      ingredients: [
        IngredientGroup(items: [mussels0105]),
      ],
    );
    db
      ..upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h')
      ..upsertIngredientMatch(
        IngredientMatchRow(
          recipeId: recipe.id,
          position: 0,
          raw: mussels0105.raw,
          itemKey: 'dozen mussel',
          fdcId: 2706350,
          description: 'Mussels',
          dataType: 'Survey (FNDDS)',
          confidence: 0.565,
          grams: 15,
          gramSource: 'piece',
          status: 'confirmed',
        ),
      )
      ..insertDecision(
        const IngredientDecisionRow(
          itemKey: 'dozen mussel',
          item: 'dozen mussels',
          fdcId: 2706350,
          description: 'Mussels',
          dataType: 'Survey (FNDDS)',
          decidedBy: null,
          decidedAt: '2026-09-28 00:00:00',
        ),
      )
      ..setSetting(decisionRekeySetting, '11')
      ..setSetting(itemKeyBackfillSetting, '11');
    rekeyAfterMatcherChange(db);
    expect(db.decisionFor('mussel')?.fdcId, 2706350);
    expect(db.decisionFor('dozen mussel'), isNull);
    expect(db.matchesForItemKey('mussel'), hasLength(1));
  });
}

/// Paella (0105), as the corpus parses it.
const IngredientLine mussels0105 = IngredientLine(
  raw: '1 dozen mussels, scrubbed and debearded',
  item: 'dozen mussels',
  amounts: [Amount(measure: Measure.count, quantity: '1', primary: true)],
);
