import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// A real corpus line (pasta e fagioli) whose top pick publishes nothing.
const String _pastaLine =
    '8 ounces small pasta such as ditalini, tubetini, conchiglietti, or orzo';

/// Every rewrite this batch added, key → target: a deleted or retargeted
/// entry fails here even where its target is pending a live search.
const Map<String, String> _batchRewrites = {
  'vermouth': 'wine dessert dry',
  'dry vermouth': 'wine dessert dry',
  'spaghetti': 'pasta dry enriched',
  'turkey': 'turkey whole meat and skin raw',
  'chicken': 'chicken broilers or fryers meat and skin raw',
  'standing rib roast': 'beef rib whole raw',
  'sirloin tips': 'beef sirloin tip',
  'white sandwich bread': 'bread white commercially prepared',
  'hearty white sandwich bread': 'bread white commercially prepared',
  'slice white sandwich bread': 'bread white commercially prepared',
  'sweet potatoes': 'sweet potato raw unprepared',
  'frozen peas': 'peas green frozen unprepared',
  'frozen baby peas': 'peas green frozen unprepared',
  'frozen petite peas': 'peas green frozen unprepared',
  'frozen green peas': 'peas green frozen unprepared',
  'clam juice': 'mollusks clam canned liquid',
  'bottle clam juice': 'mollusks clam canned liquid',
  'bottled clam juice': 'mollusks clam canned liquid',
  'tomato sauce': 'tomato products canned sauce',
  'canned tomato sauce': 'tomato products canned sauce',
  'orange juice': 'orange juice raw',
  'short': 'pasta dry enriched',
  'dark': 'chocolate dark',
  'romaine heart': 'lettuce romaine raw',
  'romaine hearts': 'lettuce romaine raw',
  'romaine lettuce heart': 'lettuce romaine raw',
  'boneless pork butt roast': 'pork boston butt lean and fat',
  'boneless pork butt': 'pork boston butt lean and fat',
  'bone-in pork butt': 'pork boston butt lean and fat',
  '4-pound boneless pork butt roast': 'pork boston butt lean and fat',
  '5-pound boneless pork butt roast': 'pork boston butt lean and fat',
  'cottage cheese': 'cheese cottage creamed curd',
  'whole-milk cottage cheese': 'cheese cottage creamed curd',
  'whole-milk or 1 percent cottage cheese': 'cheese cottage creamed curd',
  'masa harina': 'corn flour masa harina',
  'lo mein noodles': 'pasta fresh-refrigerated plain as purchased',
  'dill': 'dill weed',
  'dill leaves': 'dill weed',
  'mint': 'spearmint',
  'mint leaves': 'spearmint',
  'kosher salt': 'salt table',
  'unsweetened coconut': 'nuts coconut meat dried not sweetened',
  'sweetened coconut': 'nuts coconut meat dried sweetened',
  'baby back ribs': 'pork backribs raw',
  'orange-flavored liqueur': 'liqueur',
  'lemon or lime wedges': 'lemon wedges',
  // Audit 3 (ACCURACY-2).
  'whole chicken': 'chicken broilers or fryers meat and skin raw',
  'whole chickens': 'chicken broilers or fryers meat and skin raw',
  'sirloin steak tips': 'beef sirloin tip',
  'sirloin steak tip': 'beef sirloin tip',
  'sirloin tip steaks': 'beef sirloin tip',
  'sirloin tip steak': 'beef sirloin tip',
  'burger buns': 'rolls hamburger or hotdog plain',
  'burger bun': 'rolls hamburger or hotdog plain',
  'hamburger buns': 'rolls hamburger or hotdog plain',
  'hamburger bun': 'rolls hamburger or hotdog plain',
  'simple tomato sauce': 'tomato products canned sauce',
  'rice vermicelli': 'rice noodles',
  'butter': 'butter salted',
  'butter with salt': 'butter salted',
  'european-style without salt butter': 'without salt butter',
  'cream of coconut': 'coconut cream canned sweetened',
  'gelatin': 'gelatins dry powder unsweetened',
  'unflavored gelatin': 'gelatins dry powder unsweetened',
  'unflavored powdered gelatin': 'gelatins dry powder unsweetened',
  'powdered gelatin': 'gelatins dry powder unsweetened',
  'peas': 'peas green raw',
  'butter beans': 'lima beans',
  'celery root': 'celeriac raw',
  'dutch-processed cocoa': 'dutch-processed cocoa powder',
  'yellow mustard seeds': 'mustard seeds',
  'brown mustard seeds': 'mustard seeds',
};

/// The sweep accuracy batch (audits 1 and 2, 2026-09-26), pinned on
/// recorded FDC answers (test/fixtures/fdc — the snapshot's answers for the
/// lines the audits measured) and real corpus lines.
void main() {
  final provider = FixtureProvider();
  Future<List<RankedCandidate>> rank(String query, [String? recorded]) async =>
      rankCandidates(query, await provider.search(recorded ?? query));
  Future<FdcFood> food(int id) async => (await provider.food(id))!;

  test('every rewrite target has a recorded answer', () {
    // The 27 targets once pending a live search are recorded from sweep
    // snapshot 7's cache (the sweep asked FDC for each).
    final recorded =
        jsonDecode(File('test/fixtures/fdc/searches.json').readAsStringSync())
            as Map<String, dynamic>;
    // A target no snapshot holds is named pending ([pendingSearches]).
    for (final key in queryRewriteKeys) {
      final target = searchQueryFor(key);
      expect(
        recorded.containsKey(target) || pendingSearches.contains(target),
        isTrue,
        reason: key,
      );
    }
    for (final MapEntry(:key, :value) in _batchRewrites.entries) {
      expect(searchQueryFor(key), value, reason: key);
    }
  });

  group('A1: a record with no energy', () {
    test('"Oil, olive, extra virgin" (748608) publishes fat only as 298: '
        '843 kcal per 100 g through the Atwater fallback', () async {
      final dir = Directory.systemTemp.createTempSync('salt-evoo');
      addTearDown(() => dir.deleteSync(recursive: true));
      final db = SaltDatabase.open('${dir.path}/salt.db');
      addTearDown(db.dispose);
      const recipe = Recipe(
        id: 'r1',
        title: 'Oil',
        slug: 'oil',
        source: RecipeSource(name: 'Test', type: 'book'),
        ingredients: [
          IngredientGroup(
            items: [IngredientLine(raw: '¼ cup extra-virgin olive oil')],
          ),
        ],
      );
      final evoo = await food(748608);
      expect(evoo.nutrientsPer100g.containsKey('208'), isFalse);
      expect(evoo.nutrientsPer100g.containsKey('204'), isFalse);
      db
        ..upsertSource(slug: 'src', name: 'Test', type: 'book')
        ..upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h')
        ..fdcFoodCachePut(748608, jsonEncode(evoo.toJson()));
      IngredientMatchRow row({String? hold}) => IngredientMatchRow(
        recipeId: 'r1',
        position: 0,
        raw: '¼ cup extra-virgin olive oil',
        fdcId: 748608,
        description: 'Oil, olive, extra virgin',
        dataType: 'Foundation',
        confidence: 1,
        grams: 100,
        gramSource: 'weight',
        status: 'auto',
        hold: hold,
      );
      // A held row (any reason) stays out of the totals whatever its score.
      db.upsertIngredientMatch(row(hold: 'second_food'));
      await recomputeTotals(db, provider, recipe, servingBasis: 1);
      expect(db.nutritionFor('r1')!.caloriesPerServing ?? 0, 0);
      db.upsertIngredientMatch(row());
      await recomputeTotals(db, provider, recipe, servingBasis: 1);
      expect(
        db.nutritionFor('r1')!.caloriesPerServing,
        closeTo(9 * evoo.nutrientsPer100g['298']!, 0.01),
      );
    });

    test('the guard: a record with no energy and a macro missing publishes '
        'nothing a total can use; salt is energy-free, not missing', () async {
      expect(publishesNothing(await food(2759000)), isTrue);
      // Audit 3: protein and fat but no carbohydrate counted 96 kcal/100 g.
      final beans = await food(747431);
      expect(beans.nutrientsPer100g.containsKey('205'), isFalse);
      expect(publishesNothing(beans), isTrue, reason: 'partial macros');
      expect(publishesNothing(await food(748608)), isFalse, reason: '298');
      expect(publishesNothing(await food(746775)), isFalse, reason: 'salt');
    });

    test('the engine holds a picked record that publishes nothing, and a '
        "docked record never stands in for the top pick's macros", () async {
      final dir = Directory.systemTemp.createTempSync('salt-hold');
      addTearDown(() => dir.deleteSync(recursive: true));
      final db = SaltDatabase.open('${dir.path}/salt.db');
      addTearDown(db.dispose);
      // Two real corpus lines (pasta e fagioli; grilled scallops).
      final recipe = Recipe(
        id: 'r2',
        title: 'Lines',
        slug: 'lines',
        source: const RecipeSource(name: 'Test', type: 'book'),
        ingredients: [
          IngredientGroup(
            items: [
              for (final raw in [
                _pastaLine,
                '2 teaspoons pink peppercorns, crushed',
              ])
                IngredientLine(
                  raw: raw,
                  item: parseIngredientLine(raw).item,
                  amounts: parseIngredientLine(raw).amounts,
                ),
            ],
          ),
        ],
      );
      db
        ..upsertSource(slug: 'src', name: 'Test', type: 'book')
        ..upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h');
      await matchAndCompute(db, provider, recipe);
      final rows = db.ingredientMatchesFor('r2');
      expect(rows[0].fdcId, 2758998);
      expect(rows[0].hold, 'no_nutrients');
      // "Fish, salmon, pink, raw" (no peppercorn) is complete but another
      // food; the energy-less "Beans, Dry, Pink (0% moisture)" top pick is
      // stood in for by its own raw form, which adds only form words.
      expect(rows[1].description, isNot('Fish, salmon, pink, raw'));
      expect(rows[1].description, 'Beans, pink, mature seeds, raw');
    });

    test("bare 'spaghetti' searches the enriched dry pasta", () async {
      final raw = await rank('spaghetti');
      expect(raw.first.candidate.fdcId, 2759000, reason: 'energy-less');
      final pasta = await rank(searchQueryFor('spaghetti'));
      expect(pasta.first.candidate.fdcId, 169736);
      expect(pasta.first.confidence, 1);
    });
  });

  group('A2/A3: the wrong animal, dishes and products', () {
    test('a bare animal is the whole bird; the cuts FDC files under the '
        'animal', () async {
      // 11 whole turkeys counted as "Bologna, turkey" at 0.90.
      expect(
        (await rank('turkey')).first.candidate.description,
        'Bologna, turkey',
      );
      expect(searchQueryFor('turkey'), 'turkey whole meat and skin raw');
      // The recorded 'turkey' answer holds no whole bird (171081), so the
      // rewrite's pick stays unverified until its ONE live search: pending.
      expect(
        [for (final c in await provider.search('turkey')) c.fdcId],
        isNot(contains(171081)),
      );
      expect(
        searchQueryFor('chicken'),
        'chicken broilers or fryers meat and skin raw',
      );
      expect(searchQueryFor('standing rib roast'), 'beef rib whole raw');
      expect(searchQueryFor('sirloin tips'), 'beef sirloin tip');
      // ...but an animal before a longer alternative is the adjective.
      expect(
        leftAlternative('chicken or vegetable broth', (_) => true),
        isNull,
      );
      expect(leftAlternative('dill or sweet pickles', (_) => true), isNull);
      expect(leftAlternative('dark or dark chocolate', (_) => true), isNull);
    });

    test('a record naming only another animal is docked', () async {
      final legs = await rank('turkey drumsticks and thighs');
      final skin = legs.firstWhere(
        (c) => c.candidate.description.startsWith('Chicken, skin'),
      );
      expect(skin.docked, isTrue);
      expect(skin.confidence, lessThan(0.5), reason: 'was 0.54, counted');
      expect(legs.first.candidate.description, startsWith('Turkey, thigh'));
    });

    test('a dish names the ingredient after "with"/"on": the head noun is '
        'read before it', () async {
      final broth = await rank('beef broth');
      expect(
        broth.first.candidate.description,
        'Soup, beef broth, less/reduced sodium, ready to serve',
      );
      final dish = broth.firstWhere(
        (c) => c.candidate.description.startsWith('Soup, vegetable with'),
      );
      expect(dish.docked, isTrue);
    });

    test('"N percent" is FDC\'s "N%"; heart is romaine; evaporated is a '
        'modified form; smoked salmon is not a fillet', () async {
      expect(
        (await rank('85 percent lean ground beef')).first.candidate.description,
        contains('85% lean'),
      );
      expect(headNounOf('romaine hearts'), 'romaine');
      expect(headNounOf('artichoke hearts'), 'artichoke');
      // A romaine record, not the organ: with the connector words out of
      // the ranker (matcher v8), SR's "Lettuce, cos or romaine, raw" edges
      // the Foundation "Lettuce, romaine, green, raw" — the same food.
      expect(
        (await rank('romaine hearts')).first.candidate.description,
        allOf(startsWith('Lettuce,'), contains('romaine')),
      );
      expect(
        (await rank('2 percent milk')).first.candidate.description,
        'Milk, reduced fat (2%)',
      );
      expect(
        (await rank('skin-on salmon fillets')).first.confidence,
        lessThan(0.5),
        reason: 'kippered and smoked records only',
      );
    });

    test('baby food, toddler food and tots are products', () async {
      final prunes = await rank('prunes');
      expect(
        prunes.first.candidate.description,
        startsWith('Plums, dried (prunes)'),
      );
      for (final c in prunes) {
        if (c.candidate.description.contains('Toddler')) {
          expect(c.docked, isTrue);
        }
      }
      final potatoes = await rank('sweet potatoes');
      final tots = potatoes.firstWhere(
        (c) => c.candidate.description == 'Sweet potato tots',
      );
      expect(tots.docked, isTrue);
      expect(potatoes.first, isNot(tots));
    });
  });

  group('products, negation, forms and a count-noun side effect', () {
    test('"Babyfood, juice, apple" and "Mint julep" are products: each '
        'names the head, only the marker docks it', () async {
      final juice = await rank('apple juice');
      expect(juice.first.candidate.description, 'Apple juice, 100%');
      expect(
        juice
            .firstWhere(
              (c) => c.candidate.description.startsWith('Babyfood, juice'),
            )
            .docked,
        isTrue,
      );
      final mint = await rank('dried mint');
      expect(
        mint.firstWhere((c) => c.candidate.description == 'Mint julep').docked,
        isTrue,
      );
    });

    test('smoked is a modified form: skin-on salmon fillets never rank the '
        'smoked sockeye first', () async {
      final salmon = await rank('skin-on salmon fillets');
      final smoked = salmon.firstWhere(
        (c) => c.candidate.description.contains('smoked'),
      );
      expect(smoked, isNot(salmon.first));
    });

    test('a negated word covers nothing: "not sweetened" is not the '
        "sweetened target (ranked on the source key's recorded answer; the "
        'target itself is pending one live search)', () async {
      final coconut = await rank(
        searchQueryFor('sweetened coconut'),
        'sweetened coconut',
      );
      expect(coconut.first.candidate.fdcId, 168586);
      final plain = coconut.firstWhere(
        (c) => c.candidate.description.endsWith('not sweetened'),
      );
      expect(plain.confidence, lessThan(0.7), reason: 'was 0.943, first');
    });

    test('"lemon or lime wedges": lemon-lime soda covered both alternatives '
        'once the count noun went, and an amount-less line resolves on its '
        'food, so it reads the lemon wedges answer', () async {
      expect(
        (await rank('lemon or lime wedges')).first.candidate.description,
        startsWith('Beverages, carbonated, lemon-lime soda'),
      );
      final lemon = await rank(searchQueryFor('lemon or lime wedges'));
      expect(lemon.first.candidate.description, 'Lemon, raw');
      expect(lemon.first.confidence, greaterThanOrEqualTo(0.5));
    });
  });

  group('A10: "A or B" splits only on an answer naming A', () {
    test(
      '"champagne vinegar or white wine vinegar": the answer for '
      "'champagne vinegar' names no vinegar, so the phrase is searched",
      () async {
        final dir = Directory.systemTemp.createTempSync('salt-or');
        addTearDown(() => dir.deleteSync(recursive: true));
        final db = SaltDatabase.open('${dir.path}/salt.db');
        addTearDown(db.dispose);
        for (final q in [
          'champagne vinegar',
          'champagne vinegar or white wine vinegar',
          'dry white wine',
        ]) {
          db.fdcSearchCachePut(
            q,
            jsonEncode([for (final c in await provider.search(q)) c.toJson()]),
          );
        }
        const item = 'champagne vinegar or white wine vinegar';
        expect(lineSearchFor(db, item, itemKeyFor(item)).query, item);
        // Vermouth has no FDC record: alone it is the sherry target, but
        // "vermouth or white wine" is the white wine FDC knows (B).
        expect(searchQueryFor('dry vermouth'), 'wine dessert dry');
        expect(searchQueryFor('vermouth'), 'wine dessert dry');
        const vermouth = 'dry vermouth or dry white wine';
        expect(
          lineSearchFor(db, vermouth, itemKeyFor(vermouth)).query,
          'dry white wine',
        );
        expect(
          (await rank('dry white wine')).first.candidate.description,
          'Wine, white',
        );
      },
    );

    test(
      'the relative guard: A splits when it ranks at least as well as the '
      'stored phrase; with no stored phrase, A must reach the review gate',
      () async {
        final dir = Directory.systemTemp.createTempSync('salt-or');
        addTearDown(() => dir.deleteSync(recursive: true));
        final db = SaltDatabase.open('${dir.path}/salt.db');
        addTearDown(db.dispose);
        Future<void> store(String q) async => db.fdcSearchCachePut(
          q,
          jsonEncode([for (final c in await provider.search(q)) c.toJson()]),
        );
        const peas = 'snow peas or sugar snap peas';
        await store('snow peas');
        // 'snow peas' names A but tops out below the gate (0.49): the
        // phrase nobody has searched yet is searched, not A.
        final a = (await rank('snow peas')).first.confidence;
        expect(a, allOf(greaterThan(0.45), lessThan(lowConfidence)));
        expect(lineSearchFor(db, peas, itemKeyFor(peas)).query, peas);
        // Once the phrase's own answer is stored and ranks lower (0.30), A
        // is the better answer and splits.
        await store(peas);
        expect((await rank(peas)).first.confidence, lessThan(a));
        expect(
          lineSearchFor(db, peas, itemKeyFor(peas)).query,
          'snow peas',
        );
        // An A at the gate or above splits with no phrase answer stored.
        await store('thyme');
        const thyme = 'thyme or dried';
        expect(lineSearchFor(db, thyme, itemKeyFor(thyme)).query, 'thyme');
      },
    );
  });

  group('A4/A6/A7: count nouns, varieties, docked records', () {
    test('a count noun is not part of the food: thyme leaves count', () async {
      final thyme = await rank('thyme leaves');
      expect(thyme.first.candidate.description, 'Thyme, fresh');
      expect(thyme.first.confidence, greaterThanOrEqualTo(0.5));
    });

    test(
      'dried-for-fresh stays off but for the herbs FDC has no fresh record '
      "of (the user's ruling R4, 2026-09-28); bone-in chicken pieces, "
      '"Chicken skin" under the count-noun cap, are the whole bird '
      '(audit 4)',
      () async {
        expect(allowDriedForFresh, isFalse);
        // The count noun leaves the query for such a herb's dried spice:
        // 'oregano leaves' lifts "Spices, oregano, dried" over the gate (it
        // sat at 0.38 until v13) …
        final oregano = await rank('oregano leaves');
        expect(oregano.first.candidate.description, 'Spices, oregano, dried');
        expect(oregano.first.confidence, closeTo(0.807, 0.001));
        // … while any other dried record the line does not ask for keeps it
        // ("1 tablespoon minced Thai chiles", 0642: v12's pin).
        final chiles = (await rank('thai chiles')).first;
        expect(chiles.candidate.description, 'Peppers, hot chile, sun-dried');
        expect(chiles.confidence, lessThan(lowConfidence));
        // The cap's known cost crossed the gate at exactly 0.50 (4 lines,
        // 6,577 g): under its own words the piece line still ranks "Chicken
        // skin" first, so the line searches the whole bird instead.
        final own = await rank('bone-in skin-on chicken pieces');
        expect(own.first.candidate.description, 'Chicken skin');
        final pieces = await rank(
          searchQueryFor('bone-in skin-on chicken pieces'),
        );
        expect(pieces.first.candidate.fdcId, 171447);
        expect(pieces.first.confidence, greaterThanOrEqualTo(lowConfidence));
      },
    );

    test('a fresh herb FDC has a fresh record of is held on its dried spice; '
        'oregano, sage and the others it has none of count (a flagged '
        "approximation, the user's ruling R4), and so does a line offering "
        'the dried form; fresh-grated nutmeg is not held', () {
      // Real corpus lines; the records are real answers' (thyme's answer
      // holds "Thyme, fresh" beside the dried spice).
      expect(
        driedForFresh(
          '1 teaspoon minced fresh thyme',
          'Spices, thyme, dried',
        ),
        isTrue,
      );
      expect(
        driedForFresh(
          '1 tablespoon minced fresh oregano',
          'Spices, oregano, dried',
        ),
        isFalse,
      );
      expect(
        driedForFresh(
          '1 tablespoon minced fresh sage leaves',
          'Spices, sage, ground',
        ),
        isFalse,
      );
      // Albóndigas en Chipotle: the line itself offers the dried form.
      expect(
        driedForFresh(
          '1 tablespoon minced fresh oregano or 1 teaspoon dried',
          'Spices, oregano, dried',
        ),
        isFalse,
      );
      expect(
        driedForFresh(
          '½ teaspoon fresh grated nutmeg, plus extra for serving',
          'Spices, nutmeg, ground',
        ),
        isFalse,
      );
    });

    test('an unqualified onion/carrot is the generic record, not red/baby '
        '(user answer #6, on by default)', () async {
      expect(varietyDockOn, isTrue);
      expect(
        (await rank('onion')).first.candidate.description,
        'Onions, yellow, raw',
      );
      expect(
        (await rank('carrots')).first.candidate.description,
        'Carrots, mature, raw',
      );
    });

    test('a bone-in cut prefers the bone-in record', () async {
      final thighs = await rank('bone-in chicken thighs');
      expect(
        thighs.first.candidate.description,
        'Chicken, thigh, meat and skin, raw',
      );
    });

    test('every record without the head noun is docked', () async {
      final pink = await rank('pink peppercorns');
      final salmon = pink.firstWhere(
        (c) => c.candidate.description == 'Fish, salmon, pink, raw',
      );
      expect(salmon.docked, isTrue);
    });
  });

  group('refix round 2: wrong foods the batch had started counting', () {
    test("a fish fillet with no species keeps 'fillet': one freshwater "
        'species is not white fish', () async {
      final fish = await rank('skinless white fish fillets');
      expect(fish.first.candidate.description, 'Fish, sucker, white, raw');
      expect(fish.first.confidence, lessThan(lowConfidence));
    });

    test("'meat' is a form tail: flap meat is not meat loaf, lobster meat "
        'is lobster', () async {
      expect(headNounOf('beef flap meat'), 'flap');
      final flap = await rank('beef flap meat');
      expect(flap.first.confidence, lessThan(lowConfidence));
      expect(headNounOf('lobster meat'), 'lobster');
      final lobster = await rank('lobster meat');
      expect(lobster.first.candidate.description, 'Lobster');
      expect(lobster.first.confidence, greaterThanOrEqualTo(lowConfidence));
    });

    test(
      'a line that asks for baby food names the baby-food markers',
      () async {
        final jar = await rank('carrot baby food');
        expect(jar.first.candidate.description, 'Baby Toddler food, NFS');
        expect(jar.first.docked, isFalse);
      },
    );

    test('the leaves of the food and its puffs are docked (the sweet potato '
        'target, ranked on its source answer: pending live)', () async {
      final potato = await rank(
        'sweet potato raw unprepared',
        'sweet potatoes',
      );
      for (final name in [
        'Sweet potato leaves, raw',
        'Sweet Potato puffs, frozen, unprepared',
      ]) {
        final c = potato.firstWhere((c) => c.candidate.description == name);
        expect(c.docked, isTrue, reason: name);
      }
      expect(potato.first.confidence, lessThan(lowConfidence));
    });
  });

  group('A5/A9/A11: grams on real corpus lines', () {
    GramResolution? gramsOf(String raw, [FdcFood? on]) {
      final parsed = parseIngredientLine(raw);
      return resolveGrams(
        amounts: parsed.amounts,
        food: on,
        normalizedItem: normalizeItem(parsed.item ?? raw),
        raw: raw,
      );
    }

    test('a fraction weight range reads its upper bound until user answer '
        '#1, like its hyphenated sibling', () {
      expect(rangeWeightsMidpoint, isFalse);
      // 4 pounds each (2 racks × 2 pounds).
      const chuck =
          '1 (3½ to 4-pound) boneless chuck-eye roast, pulled into 2 pieces '
          'at the natural seam and fat trimmed';
      const sibling =
          '1 (3½- to 4-pound) boneless beef chuck-eye roast, pulled into two '
          'pieces at natural seam and trimmed';
      const lamb =
          '2 racks of lamb (1¾ to 2 pounds each), fat trimmed to ⅛ to ¼ '
          'inch, rib bones frenched';
      for (final raw in [chuck, sibling, lamb]) {
        expect(gramsOf(raw)!.grams, closeTo(4 * 453.592, 0.1), reason: raw);
      }
      expect(
        gramsOf('¾–1 cup (5¼ to 7 ounces) sugar')!.grams,
        closeTo(7 * 28.3495, 0.1),
      );
      // The larger bound of a corpus typo ("14⅔ to 6½" for 16½).
      expect(
        gramsOf('2⅔–3 cups (14⅔ to 6½ ounces) bread flour')!.grams,
        closeTo(14 * 28.3495 + 2 / 3 * 28.3495, 0.1),
      );
      // A whole-number "N to M" keeps the midpoint it always had.
      expect(
        gramsOf(
          '4 (5 to 6-ounce) boneless, skinless chicken breasts, '
          'trimmed',
        )!.grams,
        closeTo(4 * 5.5 * 28.3495, 0.1),
      );
    });

    test('a leaked amount after "additional", a jar count and a curing '
        "salt's grade leave the key", () {
      String itemOf(String raw) =>
          normalizeItem(parseIngredientLine(raw).item ?? raw);
      expect(
        itemOf(
          '¾ cup skim milk plus 2 additional tablespoons, warmed to 110 '
          'degrees',
        ),
        'skim milk',
      );
      expect(itemOf('2 teaspoons pink curing salt #1'), 'pink curing salt');
      expect(
        itemOf(
          '8 cups jarred Morello cherries from 4 (24-ounce) jars, drained, '
          '2 cups juice reserved',
        ),
        'jarred morello cherries',
      );
    });

    test("a volume line reads the food's own SR tbsp/tsp portion after "
        'the density table', () async {
      final pepper = gramsOf('1 teaspoon pepper', await food(170931));
      expect(pepper!.grams, closeTo(2.3, 0.01));
      expect(pepper.source, GramSource.portion);
      // The table stays first: kosher salt on SR table salt (173468, 'tsp'
      // 6.0 g — 1.71× kosher's 0.72 g/mL, audit 1) keeps the kosher density.
      final kosher = gramsOf('1 teaspoon kosher salt', await food(173468));
      expect(kosher!.source, GramSource.density);
      expect(kosher.grams, closeTo(4.92892 * 0.72, 0.001));
    });

    test(
      'unicode fractions, scallions, seeds, package portions, strips',
      () async {
        expect(
          gramsOf(
            '4 (1¼- to 1½-pound) Cornish game hens, giblets discarded',
          )!.grams,
          closeTo(4 * 1.5 * 453.592, 0.1),
        );
        expect(gramsOf('6 scallions, sliced thin')!.grams, 90);
        // FDC's only mustard seed record is GROUND (170929): prepared
        // 'mustard' (1.05) no longer sizes the seeds (Run 050, v19) — only
        // their record's own portion does (nutrition_v19_test.dart G1).
        expect(gramsOf('1 tablespoon mustard seeds'), isNull);
        // A bunch is not a scallion: every piece entry is per piece.
        expect(
          gramsOf(
            '2 bunches scallions, whites sliced thin, greens cut into '
            '1-inch pieces',
          ),
          isNull,
        );
        expect(
          gramsOf('1 tablespoon cracked black peppercorns')!.grams,
          closeTo(14.7868 * 0.59, 0.001),
        );
        expect(gramsOf('30 saltine crackers', await food(2708167))!.grams, 90);
        expect(
          gramsOf(
            '12 (3-inch) strips lemon zest plus 6 tablespoons juice, plus '
            'extra juice for seasoning (3 lemons)',
          ),
          isNull,
          reason: 'a strip of zest is not a lemon',
        );
      },
    );

    test('a same-food second amount is added; a counted extra is not', () {
      final oil = gramsOf('¾ cup plus 2 tablespoons vegetable oil')!;
      expect(oil.grams, closeTo((0.75 * 236.588 + 2 * 14.7868) * 0.92, 0.01));
      expect(oil.basis, contains('+ 2 tablespoons'));
      expect(
        gramsOf(
          '2 tablespoons juice from 1 lemon, plus 1 lemon, cut into '
          'wedges',
        )!.grams,
        closeTo(2 * 14.7868 * 1.03, 0.01),
      );
    });

    test('a weight after the WHOLE "Q1 plus Q2" amount is the line total; '
        'one after Q1 weighs only Q1', () {
      // Was 438.3 g: the 8 ounces plus 1⅛ cups again (15 library lines).
      final total = gramsOf('1 teaspoon plus 1⅛ cups (8 ounces) sugar')!;
      expect(total.grams, closeTo(8 * 28.3495, 0.01));
      expect(total.basis, isNot(contains('+')));
      expect(
        gramsOf('2 teaspoons plus ½ cup (2½ ounces) all-purpose flour')!.grams,
        closeTo(2.5 * 28.3495, 0.01),
      );
      final first = gramsOf('½ cup (3½ ounces) plus 2 tablespoons sugar')!;
      expect(first.grams, greaterThan(3.5 * 28.3495 + 20));
      expect(first.basis, contains('+ 2 tablespoons'));
    });

    test('a pinch is the food\'s own FDC "dash" (user answer #3)', () async {
      expect(gramsOf('Pinch pepper', await food(170931))!.grams, 0.1);
    });

    test('the second part of a plus line', () {
      bool? same(String raw) => plusPartOf(raw)?.sameFood;
      expect(same('2 large eggs plus 1 large yolk'), isFalse);
      expect(
        same('1 teaspoon grated lemon zest plus 2 tablespoons juice'),
        isFalse,
      );
      expect(same('6 sprigs fresh parsley, plus 2 teaspoons minced'), isTrue);
      expect(
        same(
          '4 tablespoons unsalted butter, softened, plus ½ '
          'tablespoon, melted',
        ),
        isTrue,
      );
      expect(
        plusPartOf(
          '2 tablespoons vegetable oil, plus extra for '
          'brushing',
        ),
        isNull,
      );
      expect(
        plusPartOf(
          '2 Thai chiles, stemmed (1 left whole, 1 sliced '
          'thin), divided, plus 2 Thai chiles, stemmed and sliced thin, for '
          'serving (optional)',
        ),
        isNull,
      );
      expect(
        plusPartOf(
          '8 medium garlic cloves, minced or pressed through '
          'a garlic press (about 2 tablespoons plus 2 teaspoons)',
        ),
        isNull,
      );
    });

    test("a bone-in weight is scaled by the record's own raw refuse "
        '(user answer #4, on by default)', () async {
      expect(edibleYieldOn, isTrue);
      final chop = await food(167833);
      expect(edibleYieldOf(chop), closeTo(86 / 151, 1e-9));
      final chops = gramsOf(
        '4 (12-ounce) bone-in pork rib chops, 1½ inches thick, trimmed',
        chop,
      )!;
      expect(chops.grams, closeTo(4 * 12 * 28.3495 * 86 / 151, 0.01));
      expect(chops.basis, contains('0.57 edible'));
      expect(
        buysRefuse('1 (3½- to 4-pound) boneless pork butt roast'),
        isFalse,
      );
      // Audit 3 (A9): three shapes the audit 1 classifier missed.
      const steaks =
          '4 (12- to 16-ounce) strip or rib-eye steaks, with or without '
          'bone, 1¼ to 1½ inches thick';
      const chicken =
          '1 (3½- to 4-pound) chicken, cut into 8 pieces (4 breast pieces, 2 '
          'thighs, 2 drumsticks; see this page) and trimmed';
      for (final raw in [
        '4½ pounds lamb shoulder chops, each 1 to 1½ inches thick',
        steaks,
        chicken,
      ]) {
        expect(buysRefuse(raw), isTrue, reason: raw);
      }
      // No refuse portion in the record: the printed weight stands.
      expect(edibleYieldOf(await food(2708167)), isNull);
    });
  });

  group('audit 3 (ACCURACY-2): corrections and N1–N10', () {
    test('A7: a lower record stands in for macros only as the same food in '
        'another form', () async {
      // "Cabbage, napa, cooked" counted for napa cabbage because the raw
      // Foundation record (#1) publishes no energy; "Black bean salad"
      // stood in for black beans. Neither was docked.
      final napa = await rank('napa cabbage');
      expect(
        napa.first.candidate.description,
        'Cabbage, napa, leaf, destemmed, raw',
      );
      expect(napa.first.docked, isFalse);
      expect(
        sameFoodAsTop(
          'napa cabbage',
          napa.first.candidate.description,
          'Cabbage, napa, cooked',
        ),
        isFalse,
      );
      expect(
        sameFoodAsTop(
          'black beans',
          'Beans, Dry, Black (0% moisture)',
          'Black bean salad',
        ),
        isFalse,
      );
      // Form words and FDC's parenthetical notes are not another food.
      expect(
        sameFoodAsTop(
          'dried flageolet or great northern beans',
          'Beans, Dry, Great Northern (0% moisture)',
          "Beans, great northern, mature seeds, raw (Includes foods for USDA's "
              'Food Distribution Program)',
        ),
        isTrue,
      );
    });

    test('A9: a bone-in line is not the "meat only" record', () async {
      // 2 whole bone-in turkey breasts (6,350 g) counted on meat only: FDC's
      // class word 'whole' outranked the skin a bone-in bird cut is sold with.
      const raw = '1 (6- to 7-pound) whole bone-in turkey breast';
      const item = 'whole bone-in turkey breast';
      expect(impliesSkinOn(raw, item), isTrue);
      final breast = rankCandidates(
        item,
        await provider.search(item),
        skinOn: impliesSkinOn(raw, item),
      );
      expect(
        breast.first.candidate.description,
        'Turkey, all classes, breast, meat and skin, raw',
      );
      expect(breast.first.confidence, lessThan(lowConfidence));
      final meatOnly = breast.firstWhere((r) => r.candidate.fdcId == 171098);
      expect(meatOnly.confidence, lessThan(breast.first.confidence));
      // The review sheet's candidates rank the line the same way.
      final dir = Directory.systemTemp.createTempSync('salt-skin');
      addTearDown(() => dir.deleteSync(recursive: true));
      final db = SaltDatabase.open('${dir.path}/salt.db');
      addTearDown(db.dispose);
      final sheet = await candidatesForLine(
        db,
        provider,
        const IngredientLine(raw: raw, item: item),
      );
      expect(sheet.first.candidate.fdcId, breast.first.candidate.fdcId);
      // Skinned, said or not bone-in, or not a named bird cut: no skin.
      expect(
        impliesSkinOn(
          '1 (2-pound) bone-in turkey thigh, skinned, boned, trimmed, and cut '
              'into ½-inch pieces',
          'bone-in turkey thigh',
        ),
        isFalse,
      );
      expect(
        impliesSkinOn(
          '6 pounds bone-in chicken parts (breasts, thighs, and/or '
              'drumsticks), trimmed',
          'bone-in chicken parts',
        ),
        isFalse,
      );
      expect(impliesSkinOn('', 'bone-in pork chops'), isFalse);
    });

    test('N1: a can on a legume line ranks the canned record, never '
        'refried beans; other cans are untouched', () async {
      final pinto = await provider.search('pinto beans');
      // Without the can: the dry Foundation record (the engine then takes
      // "Pinto beans, NFS" for its macros — 3 lines counted NFS, audit 3).
      expect(
        rankCandidates('pinto beans', pinto).first.candidate.description,
        'Beans, Dry, Pinto (0% moisture)',
      );
      final canned = rankCandidates('pinto beans', pinto, canned: true);
      expect(
        canned.first.candidate.description,
        'Beans, pinto, canned, sodium added, drained and rinsed',
      );
      expect(
        canned
            .firstWhere((c) => c.candidate.description.startsWith('Refried'))
            .docked,
        isTrue,
      );
      final chickpeas = rankCandidates(
        'chickpeas',
        await provider.search('chickpeas'),
        canned: true,
      );
      expect(chickpeas.first.candidate.fdcId, 2644288);
      expect(
        namesCannedLegume('1 (15-ounce) can pinto beans', 'pinto beans'),
        isTrue,
      );
      expect(
        namesCannedLegume(
          '1 (15-ounce) can unsweetened pumpkin puree',
          'unsweetened pumpkin puree',
        ),
        isFalse,
      );
    });

    test(
      'N1 drained cans (user answer switch, default drained): no cached '
      'record publishes a drained-can portion, so the net weight stands',
      () async {
        expect(cannedDrained, isTrue);
        const raw = '1 (15-ounce) can chickpeas, drained and rinsed';
        final parsed = parseIngredientLine(raw);
        final grams = resolveGrams(
          amounts: parsed.amounts,
          food: await food(2644288),
          normalizedItem: normalizeItem(parsed.item ?? raw),
          raw: raw,
        );
        expect(grams!.grams, closeTo(15 * 28.3495, 0.1));
      },
    );

    test('N2: a record cooked a way the line does not say is docked; a line '
        'that names the cooking is not', () async {
      // With 'or' scored as a word (connectorTokensDropped off), FDC's own
      // "steamed or boiled" covered the line's "or"; the broiled record is
      // docked either way. With the switch on (matcher v8) the raw clams win.
      final recorded = await provider.search('littleneck or cherrystone clams');
      final scored = rankCandidates(
        'littleneck or cherrystone clams',
        recorded,
        dropConnectors: false,
      );
      expect(scored.first.candidate.description, 'Clams, steamed or boiled');
      final clams = await rank('littleneck or cherrystone clams');
      expect(clams.first.candidate.description, 'Clams, raw');
      for (final ranked in [scored, clams]) {
        expect(
          ranked.indexWhere(
            (c) => c.candidate.description == 'Clams, baked or broiled',
          ),
          greaterThan(0),
        );
      }
      // The four right cooked lines stay: kielbasa is "fully cooked" (not a
      // docked word), smoked ham names its cooking. Its grilled and
      // unheated records tie; v11 breaks the tie toward the one of no
      // cooking (matcher.rankCandidates).
      expect((await rank('kielbasa')).first.candidate.fdcId, 173879);
      expect(
        (await rank('smoked ham')).first.candidate.description,
        'Ham, honey, smoked, cooked',
      );
    });
  });

  group('audit 3: compound heads, kind words, lone adjectives, keys', () {
    test('N3/N10: rewrites on recorded answers', () async {
      Future<int> top(String key) async =>
          (await rank(searchQueryFor(key))).first.candidate.fdcId;
      expect(await top('yellow mustard seeds'), 170929);
      expect(await top('brown mustard seeds'), 170929);
      expect(await top('dutch-processed cocoa'), 169594);
      expect(await top('rice vermicelli'), 169742);
      expect(await top('european-style without salt butter'), 173430);
      // A mixed-case brand gets past the brand test (pinned gap): "Archway
      // Home Style Cookies, Dutch Cocoa" counted 0.55 for Dutch cocoa until
      // the rewrite.
      expect(brandTokensOf('Archway Home Style Cookies, Dutch Cocoa'), isEmpty);
      expect(
        (await rank('dutch-processed cocoa')).first.candidate.fdcId,
        173247,
      );
    });

    test("N3: pending targets ranked against their source key's recorded "
        'answer (the stand-in until one live search)', () async {
      expect(
        (await rank('butter salted', 'butter')).first.candidate.fdcId,
        173410,
      );
      expect(
        (await rank(
          'coconut cream canned sweetened',
          'cream of coconut',
        )).first.candidate.fdcId,
        2707571,
      );
      expect(
        (await rank('peas green raw', 'peas')).first.candidate.description,
        anyOf('Peas, green, raw', 'Green peas, raw'),
      );
      final lima = rankCandidates(
        'lima beans',
        await provider.search('butter beans'),
        canned: true,
      );
      expect(lima.first.candidate.description, 'Lima beans, from canned');
    });

    // Real corpus lines, item as the corpus parsed it.
    IngredientLine line(String raw, String item, [List<Amount>? amounts]) =>
        IngredientLine(
          raw: raw,
          item: item,
          amounts: amounts ?? parseIngredientLine(raw).amounts,
        );

    test('N4: a lone qualifier reads on to the next comma, or names no '
        'food; a rewrite key keeps its rewrite', () {
      final cornmeal = line(
        '1 cup (5 ounces) fine-ground, whole-grain yellow cornmeal',
        'fine-ground',
      );
      expect(lineItemOf(cornmeal), 'fine-ground whole-grain yellow cornmeal');
      expect(namesNoFood(cornmeal), isFalse);
      final coconut = line(
        '3 cups unsweetened, shredded, desiccated (dried) coconut',
        'unsweetened',
      );
      // Audit 4: every segment is read until one names a food.
      expect(
        lineItemOf(coconut),
        'unsweetened shredded desiccated (dried) coconut',
      );
      expect(namesNoFood(coconut), isFalse);
      expect(
        namesNoFood(
          line(
            '4 medium red, yellow, or orange bell peppers (about 6 ounces '
                'each), ½ inch trimmed off tops, cores and seeds discarded',
            'medium red',
          ),
        ),
        isFalse,
      );
      final pasta = line(
        '1 pound short, curly pasta, such as fusilli or campanelle',
        'short',
      );
      expect(lineItemOf(pasta), 'short');
      expect(
        searchQueryFor(normalizeItem(lineItemOf(pasta))),
        'pasta dry enriched',
      );
      // Bare juice takes its fruit from the line, or names no food.
      expect(
        lineItemOf(line('6 tablespoons juice (2 lemons)', 'juice (2 lemons)')),
        'lemon juice',
      );
      final juice = line('2 tablespoons juice', '2 tablespoons juice', []);
      expect(namesNoFood(juice), isTrue);
      expect(namesNoFood(line('1 onion, chopped fine', 'onion')), isFalse);
    });

    test('N5 (user answer switch, default on): a line naming a second food '
        'is keyed apart, and a stored decision re-keys to the same key', () {
      expect(secondFoodOwnKey, isTrue);
      for (final (raw, item, key) in [
        (
          '1 teaspoon grated zest plus 1 tablespoon juice from 1 lemon',
          'grated zest plus 1 tablespoon juice from 1 lemon',
          'lemon zest plus juice',
        ),
        (
          '¼ teaspoon grated lime zest plus 3 tablespoons juice (2 limes)',
          'grated lime zest plus 3 tablespoons juice (2 limes)',
          'lime zest plus juice',
        ),
        (
          '12 (3-inch) strips lemon zest plus 6 tablespoons juice, plus extra '
              'juice for seasoning (3 lemons)',
          '(3-inch) lemon zest',
          'lemon zest plus juice',
        ),
        (
          '2 large eggs plus 2 large yolks',
          'large eggs plus 2 large yolks',
          'egg plus yolk',
        ),
      ]) {
        final l = line(raw, item);
        expect(lineKeyOf(l), key, reason: raw);
        expect(decisionKeyFor(decisionItemOf(l)), key, reason: raw);
        expect(lineKeyOf(l), isNot(itemKeyFor(item)), reason: raw);
      }
      // A same-food second amount keeps the food's key.
      expect(
        lineKeyOf(
          line(
            '½ cup plus 2 tablespoons extra-virgin olive oil',
            'extra-virgin olive oil',
          ),
        ),
        'extra-virgin olive oil',
      );
    });
  });

  group('audit 3: piece weights, lost units, holds, named recipes', () {
    GramResolution? gramsOf(
      String raw, {
      List<Amount>? amounts,
      FdcFood? on,
    }) {
      final parsed = parseIngredientLine(raw);
      return resolveGrams(
        amounts: amounts ?? parsed.amounts,
        food: on,
        normalizedItem: normalizeItem(parsed.item ?? raw),
        raw: raw,
      );
    }

    test('N7: piece keys match whole words anchored to the head noun', () {
      expect(
        gramsOf(
          '½ pineapple, peeled, cored, and cut into ½-inch-thick rings',
        )!.grams,
        452.5,
      );
      expect(gramsOf('1 garlic head, halved crosswise')!.grams, 50);
      expect(
        gramsOf(
          '2 heads garlic, cloves separated, lightly crushed and peeled',
        )!.grams,
        100,
      );
      expect(gramsOf('4 garlic cloves, minced')!.grams, 12);
      expect(gramsOf('20 cherry tomatoes, quartered')!.grams, 340);
      expect(
        gramsOf('1 small cucumber, peeled, halved, and seeded')!.grams,
        158,
      );
      expect(
        gramsOf(
          '1 medium cucumber, peeled, halved lengthwise, seeded, and sliced '
          'thin (see this page)',
        )!.grams,
        201,
      );
      // 'sheet' is the head of "phyllo sheets"; 'phyllo' with a sheet unit.
      expect(gramsOf('14 (14 by 9-inch) phyllo sheets, thawed')!.grams, 266);
      expect(gramsOf('10 (14 by 9-inch) sheets phyllo, thawed')!.grams, 190);
      expect(gramsOf('3 large egg yolks')!.grams, 51);
      expect(
        gramsOf('4 jalapeño chiles, stemmed, seeded, and minced')!.grams,
        56,
      );
      // 'garlic' is not the food of a sub-recipe line.
      expect(gramsOf('1 recipe Spicy Garlic Oil (recipe follows)'), isNull);
    });

    test('N3: gelatin reads the volume its record names only in '
        'parentheses', () {
      // 169599 publishes "envelope (1 tbsp)" = 7 g and no leading volume.
      final gelatin = FdcFood.fromJson(
        (jsonDecode(File('test/fixtures/fdc/foods.json').readAsStringSync())
                as Map<String, dynamic>)['169599']
            as Map<String, dynamic>,
      );
      final tbsp = gramsOf('1 tablespoon unflavored gelatin', on: gelatin)!;
      expect((tbsp.grams, tbsp.source), (7, GramSource.portion));
      expect(
        gramsOf('2¾ teaspoons gelatin', on: gelatin)!.grams,
        closeTo(6.42, 0.01),
      );
    });

    test('a count the parse lost its unit from reads the unit back from the '
        'line (Strawberry Shortcakes: half-and-half was sized as half a '
        'piece, 7.5 g, then left without grams)', () async {
      // The corpus parsed "½ cup plus 1 tablespoon" as the bare count ½;
      // FDC's '1 individual container (.5 fl oz)' is 15 g. Matcher v8 reads
      // "½ cup" back from the raw line, and the plus part adds.
      final shortcake = gramsOf(
        '½ cup plus 1 tablespoon half-and-half or milk',
        amounts: const [Amount(measure: Measure.count, quantity: '1/2')],
        on: await food(2705594),
      )!;
      // "1 cup" 240 g for the half cup; the tablespoon at milk's density.
      expect(shortcake.source, GramSource.portion);
      expect(shortcake.grams, closeTo(240 / 2 + 14.7868 * 1.03, 0.01));
      // Fried Rice with Shrimp, Pork, and Shiitakes (0521): the bare count 3.
      expect(
        gramsOf(
          '3 tablespoons plus 1½ teaspoons peanut or vegetable oil',
          amounts: const [Amount(measure: Measure.count, quantity: '3')],
        )!.grams,
        closeTo((3 * 14.7868 + 1.5 * 4.92892) * 0.92, 0.01),
      );
      // Only when the raw's leading number is the amount's own.
      expect(
        gramsOf(
          '½ cup plus 1 tablespoon half-and-half or milk',
          amounts: const [Amount(measure: Measure.count, quantity: '2')],
        ),
        isNull,
      );
    });

    test('N9 (user answer switch): the 0.52–0.54 band is counted until '
        'the user answers', () {
      expect(holdBorderlineBand, isFalse);
    });

    test('N6: the lines that made named recipes "complete" on wrong data '
        'no longer count as they did', () async {
      // Grill-Roasted Turkey (0174/0175): the whole bird searches the whole
      // raw turkey (pending one live search), never "Bologna, turkey".
      expect(
        searchQueryFor(normalizeItem('(12- to 14-pound) turkey')),
        'turkey whole meat and skin raw',
      );
      // French Toast (0751/0752): the bread is not "Egg sandwich on white
      // bread".
      expect(
        searchQueryFor(normalizeItem('hearty white sandwich bread')),
        'bread white commercially prepared',
      );
      // Grill-Roasted Boneless Turkey Breast (0176): its bone-in breast
      // leaves 'meat only' counted for review (A9 test above); Strawberry
      // Shortcakes: the half-and-half line has no grams (test above).
    });

    test('the engine holds a line that names no food', () async {
      final dir = Directory.systemTemp.createTempSync('salt-unnamed');
      addTearDown(() => dir.deleteSync(recursive: true));
      final db = SaltDatabase.open('${dir.path}/salt.db');
      addTearDown(db.dispose);
      // Triple-coconut cream pie (0831); mechouia (0661).
      const coconut =
          '3 cups unsweetened, shredded, desiccated (dried) coconut';
      final recipe = Recipe(
        id: 'r3',
        title: 'Lines',
        slug: 'lines',
        source: const RecipeSource(name: 'Test', type: 'book'),
        ingredients: [
          IngredientGroup(
            items: [
              IngredientLine(
                raw: coconut,
                item: 'unsweetened',
                amounts: parseIngredientLine(coconut).amounts,
              ),
              const IngredientLine(
                raw: '2 tablespoons juice',
                item: '2 tablespoons juice',
              ),
            ],
          ),
        ],
      );
      db
        ..upsertSource(slug: 'src', name: 'Test', type: 'book')
        ..upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h');
      await matchAndCompute(db, provider, recipe);
      final rows = db.ingredientMatchesFor('r3');
      // The coconut line names its food once every segment is read (audit
      // 4), never "Applesauce, unsweetened" — and since matcher v8 its key
      // 'unsweetened desiccated coconut' is rewritten to the not-sweetened
      // record (170170), whose cups are read from its shredded sibling
      // (168586: "cup, shredded" 93 g).
      expect((rows[0].status, rows[0].fdcId), ('auto', 170170));
      expect(rows[0].grams, closeTo(3 * 93, 0.01));
      expect(rows[0].hold, isNull);
      expect(rows[1].hold, 'unnamed_food');
    });
  });

  group('A8/A11 on real corpus recipes', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late Map<String, Recipe> recipes;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-accuracy');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath);
      final sourceRoot = Directory('${tempDir.path}/source')
        ..createSync(recursive: true);
      Directory('${sourceRoot.path}/recipes').createSync();
      const files = {
        'schnitzel': '0116-chicken-schnitzel.yaml',
        'roast': '0134-perfect-roast-chicken.yaml',
        'fried': '0148-crispy-fried-chicken.yaml',
        'corned': '0091-home-corned-beef-with-vegetables.yaml',
        'ricotta': '0380-homemade-ricotta-cheese.yaml',
        'grilled': '0423-italian-style-grilled-chicken.yaml',
        'orange': '0536-crispy-orange-beef.yaml',
        'cocotte': '0173-turkey-breast-en-cocotte-with-pan-gravy.yaml',
        'ciambotta': '0405-ciambotta-italian-vegetable-stew.yaml',
        'scampi': '0428-ultimate-shrimp-scampi.yaml',
        'potatoes':
            '0691-salt-baked-potatoes-with-roasted-garlic-and-rosemary-'
            'butter.yaml',
        'gelato': '1203-pistachio-gelato.yaml',
        'cauliflower': '0656-grilled-cauliflower.yaml',
        'carrot': '0866-carrot-cake.yaml',
      };
      for (final name in files.values) {
        File(
          '$corpusRecipesDir/$name',
        ).copySync('${sourceRoot.path}/recipes/$name');
      }
      importSourceRoot(sourceRootPath: sourceRoot.path, db: db, config: config);
      recipes = {
        for (final entry in files.entries)
          entry.key: db
              .recipeByIdOrSlug(
                entry.value.substring(5, entry.value.length - 5),
              )!
              .recipe,
      };
      for (final recipe in recipes.values) {
        await matchAndCompute(db, provider, recipe);
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    (IngredientLine, DiscardedMedium?, IngredientMatchRow) lineOf(
      String recipe,
      String raw,
    ) {
      final lines = nutritionLines(recipes[recipe]!);
      final position = lines.indexWhere((line) => line.raw == raw);
      expect(position, isNonNegative, reason: raw);
      final line = lines[position];
      return (
        line,
        discardedMediumOf(
          recipes[recipe]!,
          line,
          normalizeItem(line.item ?? line.raw),
        ),
        db
            .ingredientMatchesFor(recipes[recipe]!.id)
            .firstWhere((row) => row.position == position),
      );
    }

    test('A9: the matched bone-in turkey breast is the skin-on record', () {
      final (_, _, row) = lineOf(
        'cocotte',
        '1 (6- to 7-pound) whole bone-in turkey breast',
      );
      expect(
        row.description,
        'Turkey, all classes, breast, meat and skin, raw',
      );
    });

    test('frying oil, a brine and a buttermilk soak count 0 g (user answer '
        '#2, zero by default)', () {
      expect(discardedMediaPolicy, DiscardedMediaPolicy.zero);
      for (final (recipe, raw, kind) in [
        (
          'schnitzel',
          '2 cups vegetable oil for frying',
          DiscardedMedium.fryingOil,
        ),
        ('roast', '½ cup table salt', DiscardedMedium.brine),
        ('fried', '½ cup table salt', DiscardedMedium.brine),
        ('fried', '7 cups buttermilk', DiscardedMedium.soak),
        // A quart of shrimp brine dissolves 3 tablespoons of salt.
        ('scampi', '3 tablespoons salt', DiscardedMedium.brine),
        // Home-Corned Beef brines in 4 quarts of water: its salt is a brine.
        ('corned', '¾ cup salt', DiscardedMedium.brine),
      ]) {
        final (_, medium, row) = lineOf(recipe, raw);
        expect(medium, kind, reason: raw);
        expect(row.grams, 0, reason: raw);
        expect(row.gramSource, 'discarded', reason: raw);
        expect(row.hold, isNull);
      }
      // The frying recipe's batter buttermilk is eaten.
      expect(lineOf('fried', '1 cup buttermilk').$2, isNull);
      // A total with a discarded line accounts it and adds nothing.
      expect(db.nutritionFor(recipes['schnitzel']!.id), isNotNull);
    });

    test('a salt bath and cheese-making milk go to review with only their '
        'eaten part as grams (v14, B6); '
        "brine sugar is zeroed (the user's ruling R3, 2026-09-28); a cake's "
        "oil and a rub's salt count", () {
      final (_, sugar, sugarRow) = lineOf('roast', '½ cup sugar');
      expect(sugar, DiscardedMedium.brineSugar);
      expect(
        (sugarRow.grams, sugarRow.gramSource, sugarRow.hold),
        (0, 'discarded', null),
      );
      for (final (recipe, raw, kind) in [
        (
          'potatoes',
          '2½ cups plus ⅛ teaspoon salt',
          DiscardedMedium.saltBath,
        ),
        (
          'gelato',
          '⅓ cup plus ¼ teaspoon table salt, divided',
          DiscardedMedium.saltBath,
        ),
        ('cauliflower', '¼ cup salt', DiscardedMedium.saltBath),
      ]) {
        final (_, medium, row) = lineOf(recipe, raw);
        expect(medium, kind, reason: raw);
        expect(row.hold, 'discarded_medium', reason: raw);
        if (raw.contains(' plus ')) {
          // Its "plus" part a step eats is its grams, held with it (v11): the
          // potatoes' "remaining ⅛ teaspoon salt" in the butter, the
          // gelato's ¼ teaspoon in the custard.
          expect(row.gramSource, 'discarded', reason: raw);
          expect(row.grams, inInclusiveRange(0.5, 2), reason: raw);
        } else {
          // No eaten part: no grams, never the poured-away line (v14, B6).
          expect((row.grams, row.gramSource), (null, null), reason: raw);
        }
      }
      expect(
        lineOf('corned', '½ cup packed brown sugar').$2,
        DiscardedMedium.brineSugar,
      );
      final (_, cake, cakeRow) = lineOf('carrot', '1½ cups vegetable oil');
      expect(cake, isNull);
      expect(cakeRow.grams, closeTo(336, 1));
      // Salt rubbed on the meat stays on it: slow-roasted pork shoulder,
      // gravlax.
      for (final (file, raw) in [
        (
          '0246-slow-roasted-pork-shoulder-with-peach-sauce.yaml',
          '⅓ cup kosher salt',
        ),
        ('1148-gravlax.yaml', '¼ cup kosher salt'),
      ]) {
        final recipe = loadCorpusRecipe(file);
        final line = nutritionLines(
          recipe,
        ).firstWhere((line) => line.raw == raw);
        expect(
          discardedMediumOf(recipe, line, normalizeItem(line.item ?? raw)),
          isNull,
          reason: file,
        );
      }
      final (_, milk, milkRow) = lineOf(
        'ricotta',
        '1 gallon pasteurized (not ultrapasteurized or UHT) whole milk',
      );
      expect(milk, DiscardedMedium.cheeseMilk);
      expect(milkRow.hold, 'discarded_medium');
      // The curds' weight nothing says: no grams until a person types
      // them (v14, B6) — never the gallon.
      expect(milkRow.grams, isNull);
    });

    test('400 g or more of oil is frying oil whatever the steps say (audit '
        '3: 29 lines; a 4-cup rule found 21)', () {
      final (line, _, row) = lineOf('orange', '3 cups vegetable oil');
      expect(row.grams, 0);
      expect(row.gramSource, 'discarded');
      final recipe = recipes['orange']!;
      final item = normalizeItem(line.item!);
      expect(
        discardedMediumOf(recipe, line, item, grams: 400),
        DiscardedMedium.fryingOil,
      );
      expect(discardedMediumOf(recipe, line, item, grams: 399), isNull);
    });

    test('a fresh oregano line counts on the dried spice record, a flagged '
        "approximation (the user's ruling R4, 2026-09-28)", () {
      final (_, _, row) = lineOf('ciambotta', '⅓ cup fresh oregano leaves');
      expect(row.description, 'Spices, oregano, dried');
      expect(row.hold, isNull);
      // A fresh volume at one third on the dried record: 16 g ⅓ (v14, Q2).
      expect(row.grams, closeTo(16 / 3, 0.01));
    });

    test('a matched line with no amount is a resolved 0 g, its food kept '
        '(user answer #3, on by default)', () {
      expect(amountlessLinesZero, isTrue);
      final (line, _, row) = lineOf('schnitzel', 'Lemon wedges');
      expect(line.amounts, isEmpty);
      expect(row.description, 'Lemon, raw', reason: 'the count noun is out');
      expect(row.grams, 0);
      expect(row.gramSource, 'unmeasured');
      expect(
        matchBucketFor(
          status: row.status,
          fdcId: row.fdcId,
          grams: row.grams,
          confidence: row.confidence,
          hold: row.hold,
        ),
        MatchBucket.counted,
      );
    });

    test('a zest-plus-juice line is never counted for the zest: since '
        'matcher v8 the juice counts on its own record', () {
      final (_, _, row) = lineOf(
        'grilled',
        '1 teaspoon grated lemon zest plus 2 tablespoons juice',
      );
      expect((row.fdcId, row.hold), (167747, null));
      expect(row.grams, closeTo(2 * 14.7868 * 1.03, 0.01));
      expect(
        matchBucketFor(
          status: row.status,
          fdcId: row.fdcId,
          grams: row.grams,
          confidence: row.confidence,
          hold: row.hold,
          gramSource: row.gramSource,
        ),
        MatchBucket.counted,
      );
    });
  });
}
