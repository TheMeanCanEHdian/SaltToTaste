// Real corpus lines and steps wrap across adjacent literals.
// ignore_for_file: no_adjacent_strings_in_list

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';
import 'support/pinned_corpus_text.dart';

/// Matcher v15 (the Run 047 union): one weighed line and one sub-recipe
/// gate on every write path, rule rows that never take another copy's
/// decision, held media that stay held through an edit, a confirm and an
/// un-skip. Real corpus lines and steps as strings (recipe named on each;
/// [pinnedCorpusText] proves each exists), FDC answers recorded from sweep
/// snapshot 12. A guard no corpus line exercises is pinned on a synthesized
/// input, said so where it is.
void main() {
  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v15');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    db.upsertSource(slug: 'src', name: 'Test', type: 'book');
    return db;
  }

  Recipe recipeOf(
    List<List<String>> groups, {
    List<String> steps = const [],
    String title = 'r',
    String id = 'r',
    List<Subsection> subsections = const [],
    SaltDatabase? db,
  }) {
    final recipe = Recipe(
      id: id,
      title: title,
      slug: id,
      source: const RecipeSource(name: 'Test', type: 'book'),
      ingredients: [
        for (final raws in groups)
          IngredientGroup(items: [for (final raw in raws) lineOf(raw)]),
      ],
      steps: [
        for (final (i, text) in steps.indexed)
          RecipeStep(number: i + 1, text: text),
      ],
      subsections: subsections,
    );
    db?.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h$id');
    return recipe;
  }

  Subsection subsectionOf(String title, List<String> raws) => Subsection(
    title: title,
    kind: 'variation',
    ingredients: [
      IngredientGroup(items: [for (final raw in raws) lineOf(raw)]),
    ],
  );

  MatchBucket bucketOf(IngredientMatchRow row) => matchBucketFor(
    status: row.status,
    fdcId: row.fdcId,
    grams: row.grams,
    confidence: row.confidence,
    hold: row.hold,
    gramSource: row.gramSource,
  );

  IngredientMatchRow rowAt(SaltDatabase db, int position, {String id = 'r'}) =>
      db.ingredientMatchesFor(id).singleWhere((r) => r.position == position);

  /// A whole corpus recipe imported as the importer stores it.
  (SaltDatabase, Recipe) imported(String file) {
    final dir = Directory.systemTemp.createTempSync('salt-v15-corpus');
    addTearDown(() => dir.deleteSync(recursive: true));
    final config = ServerConfig(
      dataDir: dir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    );
    final db = SaltDatabase.open(config.dbPath);
    addTearDown(db.dispose);
    final root = Directory('${dir.path}/source')..createSync(recursive: true);
    Directory('${root.path}/recipes').createSync();
    File('$corpusRecipesDir/$file').copySync('${root.path}/recipes/$file');
    importSourceRoot(sourceRootPath: root.path, db: db, config: config);
    return (db, db.recipeByIdOrSlug(db.allRecipeIds().single)!.recipe);
  }

  group('E1: a repeated line takes the nth row of its text — an engine row '
      "never takes another copy's decision", () {
    const acquacotta =
        '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml';

    for (final (verb, body) in [
      ('a pick with typed grams', {'fdc_id': 173468, 'grams': 5}),
      ('a skip', {'skipped': true}),
    ]) {
      test("Acquacotta (0405): $verb on the second 'Salt and pepper' "
          '(position 18) stays there; a recompute leaves position 5 the '
          'seasoning rule row', () async {
        final (db, r) = imported(acquacotta);
        final provider = FixtureProvider(pending: pendingSearches);
        await matchAndCompute(db, provider, r);
        final salts = [
          for (final (i, l) in nutritionLines(r).indexed)
            if (l.raw == 'Salt and pepper') i,
        ];
        expect(salts, [5, 18]);
        await applyMatchOverride(db, provider, r, 18, body);
        final decided = rowAt(db, 18, id: r.id);
        await matchAndCompute(db, provider, r);
        final first = rowAt(db, 5, id: r.id);
        expect(
          (first.status, first.fdcId, first.grams, first.description),
          (
            'confirmed',
            null,
            null,
            'Seasoning to taste — no measurable amount',
          ),
        );
        final second = rowAt(db, 18, id: r.id);
        expect(
          (second.status, second.fdcId, second.grams),
          (decided.status, decided.fdcId, decided.grams),
        );
      }, skip: skipIfNoCorpus);
    }

    test("the same two lines in the soup's and the toast's groups, with no "
        'corpus: a pick on the second is never copied onto the first; moved '
        'down by a line put above both — its own "½ cup extra-virgin olive '
        'oil" — the pairing holds (the trim and the move are synthesized: a '
        'stated exception)', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = recipeOf(db: db, [
        ['Salt and pepper'],
        ['Salt and pepper'],
      ]);
      await matchAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 1, {
        'fdc_id': 173468,
        'grams': 3,
      });
      await matchAndCompute(db, provider, r);
      expect(rowAt(db, 0).fdcId, isNull);
      expect(rowAt(db, 1).fdcId, 173468);
      final moved = recipeOf(db: db, [
        ['½ cup extra-virgin olive oil', 'Salt and pepper'],
        ['Salt and pepper'],
      ]);
      await matchAndCompute(db, provider, moved);
      expect(rowAt(db, 1).fdcId, isNull);
      expect((rowAt(db, 2).fdcId, rowAt(db, 2).grams), (173468, 3));
    });

    test("Pad Thai's repeated '2 tablespoons peanut or vegetable oil' "
        '(positions 4 and 8; two lines of it, a stated trim): a skip on the '
        'second never reaches the first, an auto row', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      const oil = '2 tablespoons peanut or vegetable oil';
      final r = recipeOf(db: db, [
        [oil, oil],
      ]);
      await matchAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 1, {'skipped': true});
      await matchAndCompute(db, provider, r);
      expect((rowAt(db, 0).status, rowAt(db, 1).status), ('auto', 'skipped'));
    });
  });

  group('E2, E10: a held medium stays held through an amount edit, a '
      'confirm and an un-skip', () {
    // Sesame-Lemon Cucumber Salad (0052): its salt line and first step.
    const cucumberSalt = '1 tablespoon table salt';
    const cucumberStep =
        'Toss the cucumbers with the salt in a colander set over a large '
        'bowl. Weight the cucumbers with a gallon-sized zipper-lock bag '
        'filled with water; drain for 1 to 3 hours. Rinse and pat dry.';

    test("E2: 0052's rinsed-off salt — confirmed 0 g, then its amount edited "
        '(to "2 tablespoons table salt": a synthesized edit, a stated '
        'exception) — keeps its hold and (v16, Run 048) its 0 g poured away, '
        'and a second confirm writes 0 g again, never 36 g', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = recipeOf(
        db: db,
        [
          [cucumberSalt],
        ],
        steps: [cucumberStep],
      );
      await matchAndCompute(db, provider, r);
      var row = rowAt(db, 0);
      expect(
        (row.fdcId, row.grams, row.hold),
        (173468, null, 'discarded_medium'),
      );
      await applyMatchOverride(db, provider, r, 0, {'confirmed': true});
      expect((rowAt(db, 0).grams, rowAt(db, 0).gramSource), (0, 'discarded'));
      final edited = recipeOf(
        db: db,
        [
          ['2 tablespoons table salt'],
        ],
        steps: [cucumberStep],
      );
      await matchAndCompute(db, provider, edited);
      row = rowAt(db, 0);
      // RULE A (v25, Run 055 I1): the confirm resolves the hold — 0 g
      // poured away, no hold — at the PUT and at every compute alike.
      expect(
        (row.status, row.fdcId, row.grams, row.hold),
        ('confirmed', 173468, 0, null),
      );
      await applyMatchOverride(db, provider, edited, 0, {'confirmed': true});
      row = rowAt(db, 0);
      expect((row.grams, row.gramSource), (0, 'discarded'));
    });

    test("E2: a confirm reads the engine's own detector, not only the stored "
        'hold — a row v14 left confirmed with no grams and no hold confirms '
        'to 0 g (0052)', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = recipeOf(
        db: db,
        [
          [cucumberSalt],
        ],
        steps: [cucumberStep],
      );
      await matchAndCompute(db, provider, r);
      db.upsertIngredientMatch(
        rowAt(db, 0).copyWith(status: 'confirmed', clearHold: true),
      );
      await applyMatchOverride(db, provider, r, 0, {'confirmed': true});
      final row = rowAt(db, 0);
      expect((row.grams, row.gramSource), (0, 'discarded'));
    });

    // Perfect Poached Chicken Breasts (0112): its soy line in the poaching
    // brine (two of its lines and its first step).
    final poached = (
      lines: [
        '4 (6- to 8-ounce) boneless, skinless chicken breasts, trimmed',
        '½ cup soy sauce',
      ],
      step:
          'Cover chicken breasts with plastic wrap and pound thick ends '
          'gently with meat pounder until ¾ inch thick. Whisk 4 quarts water, '
          'soy sauce, salt, sugar, and garlic in Dutch oven until salt and '
          'sugar are dissolved. Arrange breasts, skinned side up, in steamer '
          'basket, making sure not to overlap them. Submerge steamer basket '
          'in brine and let sit at room temperature for 30 minutes.',
    );

    for (final (verb, body) in [
      ('a confirm', <String, Object?>{'confirmed': true}),
      ('a pick', <String, Object?>{'fdc_id': 2707442}),
    ]) {
      test("E10: 0112's poaching soy after $verb (0 g poured away), a skip "
          "and an un-skip is the engine's row again — no grams, held, in "
          'check', () async {
        final db = tempDb();
        final provider = FixtureProvider();
        final r = recipeOf(
          db: db,
          [poached.lines],
          title: 'Perfect Poached Chicken Breasts',
          steps: [poached.step],
        );
        await matchAndCompute(db, provider, r);
        expect(
          (rowAt(db, 1).grams, rowAt(db, 1).hold),
          (null, 'discarded_medium'),
        );
        await applyMatchOverride(db, provider, r, 1, body);
        expect(rowAt(db, 1).grams, 0);
        await applyMatchOverride(db, provider, r, 1, {'skipped': true});
        await applyMatchOverride(db, provider, r, 1, {'skipped': false});
        final row = rowAt(db, 1);
        expect(
          (row.status, row.grams, row.gramSource, row.hold),
          ('auto', null, null, 'discarded_medium'),
        );
        expect(bucketOf(row), MatchBucket.check);
      });
    }
  });
  group('E3, E4, E9, E11, E13: one weighed line and one sub-recipe gate on '
      'every path', () {
    // Mujaddara (0711): its plus line and its Crispy Onions subsection.
    const plusLine =
        '1 recipe Crispy Onions, plus 3 tablespoons reserved oil (recipe '
        'follows)';
    const onions = [
      '2 pounds onions, halved and sliced crosswise into ¼-inch-thick pieces',
      '2 teaspoons salt',
      '1½ cups vegetable oil',
    ];

    Future<(SaltDatabase, Recipe, FixtureProvider)> mujaddara() async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = recipeOf(
        db: db,
        [
          [plusLine],
        ],
        subsections: [subsectionOf('Crispy Onions', onions)],
      );
      await matchAndCompute(db, provider, r);
      final row = rowAt(db, 0);
      expect((row.fdcId, row.grams, row.hold), (2710180, 42.0, null));
      return (db, r, provider);
    }

    test("E3: a person's re-pick of the oil on 0711's plus line weighs the "
        'eaten 3 tablespoons — 42 g, never "1 recipe" as one onion (110 g); '
        'a confirm of a row with no grams weighs them too', () async {
      final (db, r, provider) = await mujaddara();
      await applyMatchOverride(db, provider, r, 0, {'fdc_id': 2710180});
      var row = rowAt(db, 0);
      expect(
        (row.status, row.fdcId, row.grams, row.gramSource),
        ('overridden', 2710180, 42.0, 'portion'),
      );
      db.upsertIngredientMatch(row.copyWith(clearGrams: true, status: 'auto'));
      await applyMatchOverride(db, provider, r, 0, {'confirmed': true});
      row = rowAt(db, 0);
      expect((row.status, row.grams), ('confirmed', 42.0));
    });

    test("E11: a skip then an un-skip of 0711's counted oil leaves it counted "
        'at 42 g, never held second_food', () async {
      final (db, r, provider) = await mujaddara();
      await applyMatchOverride(db, provider, r, 0, {'skipped': true});
      await applyMatchOverride(db, provider, r, 0, {'skipped': false});
      final row = rowAt(db, 0);
      expect((row.status, row.grams, row.hold), ('auto', 42.0, null));
      expect(bucketOf(row), MatchBucket.counted);
    });

    test("E3, E13: the matches GET reads 0711's line as its eaten oil — "
        'amount "3 tablespoon", candidates for the oil holding the row\'s '
        'food, the basis of the stored grams', () async {
      final (db, r, provider) = await mujaddara();
      final items = (await matchesBody(db, provider, r))['items']! as List;
      final item = items.single as Map<String, Object?>;
      expect(item['line_amount'], '3 tablespoon');
      final candidates = [
        for (final c in item['candidates']! as List)
          (c as Map<String, Object?>)['fdc_id'],
      ];
      expect(candidates, contains(2710180));
      expect(
        (item['match']! as Map<String, Object?>)['gram_basis'],
        '3 tablespoon · USDA portion',
      );
    });

    test("E3: the matches GET fills 0711's portions from the eaten 3 "
        'tablespoons — the "1 tablespoon" portion fills 42 g, never the '
        '"1 recipe" line\'s nothing', () async {
      final (db, r, provider) = await mujaddara();
      final item =
          ((await matchesBody(db, provider, r))['items']! as List).single
              as Map<String, Object?>;
      final fills = {
        for (final p in item['portions']! as List)
          (p as Map<String, Object?>)['description']: p['fill'],
      };
      expect(fills['1 tablespoon'], 42.0);
    });

    test("E13: the matches GET reports 0711's query as the eaten oil's — "
        'candidates_query "vegetable oil", whose answer names the '
        'ingredient', () async {
      final (db, r, provider) = await mujaddara();
      final item =
          ((await matchesBody(db, provider, r))['items']! as List).single
              as Map<String, Object?>;
      expect(
        (item['candidates_query'], item['candidates_name_ingredient']),
        ('vegetable oil', true),
      );
    });

    test("E3: the compute keys 0711's search on the eaten oil, never the "
        "raw line's key — a cached answer under that key (synthesized: "
        "the recorded 'onions' answer stored there, a stated exception; "
        'no path searches it) is never read for the oil', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = recipeOf(
        db: db,
        [
          [plusLine],
        ],
        subsections: [subsectionOf('Crispy Onions', onions)],
      );
      db.fdcSearchCachePut(
        searchQueryFor(lineKeyOf(nutritionLines(r).single)),
        jsonEncode([
          for (final c in await provider.search('onions')) c.toJson(),
        ]),
      );
      await matchAndCompute(db, provider, r);
      final row = rowAt(db, 0);
      expect((row.fdcId, row.grams), (2710180, 42.0));
    });

    test("E13: Roast Fresh Ham's (0249) sheet ranks as the compute does — the "
        "fresh shank half (168226), the row's own food, first", () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = recipeOf(db: db, [
        [
          '1 (6- to 8-pound) bone-in fresh half ham with skin, preferably '
              'shank end, rinsed',
        ],
      ]);
      await matchAndCompute(db, provider, r);
      expect(rowAt(db, 0).fdcId, 168226);
      final candidates = await candidatesForLine(
        db,
        provider,
        nutritionLines(r).single,
        cacheOnly: true,
      );
      expect(candidates.first.candidate.fdcId, 168226);
    });

    test('E9: an apply-to-all lands a marked count as the compute writes it — '
        '"8 Home-Fried Taco Shells (recipe follows)" (Ground Beef Tacos, '
        '0478) in two recipes, a pick of a food no count sizes on one makes '
        'the other the 0 g sub-recipe, never a no-grams row (the pairing and '
        'the food, "Vegetable oil, NFS", are synthesized: a stated '
        'exception)', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      const raw = '8 Home-Fried Taco Shells (recipe follows)';
      final a = recipeOf(db: db, id: 'a', [
        [raw],
      ]);
      final b = recipeOf(db: db, id: 'b', [
        [raw],
      ]);
      await matchAndCompute(db, provider, a);
      await matchAndCompute(db, provider, b);
      expect(rowAt(db, 0, id: 'a').fdcId, 172800);
      final applied = await applyMatchOverride(db, provider, b, 0, {
        'fdc_id': 2710180,
        'apply_to_all': true,
      });
      expect(applied!.lines, 1);
      for (final id in ['a', 'b']) {
        final row = rowAt(db, 0, id: id);
        expect(
          (row.status, row.fdcId, row.grams, row.description),
          ('confirmed', null, 0, subRecipeNote),
          reason: id,
        );
      }
    });

    test("E4: the stale hash reads 0711's eaten part from its subsection — "
        'the oil renamed there, or the subsection gone, changes it (both '
        'edits synthesized: a stated exception)', () {
      Recipe withSubs(List<Subsection> subsections) => recipeOf(
        [
          [plusLine],
        ],
        subsections: subsections,
      );
      final base = ingredientsHashOf(
        withSubs([subsectionOf('Crispy Onions', onions)]),
      );
      final olive = ingredientsHashOf(
        withSubs([
          subsectionOf('Crispy Onions', [
            ...onions.take(2),
            '1½ cups extra-virgin olive oil',
          ]),
        ]),
      );
      expect(olive, isNot(base));
      expect(ingredientsHashOf(withSubs(const [])), isNot(base));
      expect(ingredientsHashOf(withSubs(const [])), isNot(olive));
    });
  });
  group('E5, E6, E7, E12: masses and a split', () {
    final provider = FixtureProvider();

    Future<double?> gramsOn(String raw, int fdcId) async {
      final food = (await provider.food(fdcId))!;
      return lineGrams(tempDb(), lineOf(raw), food)?.grams;
    }

    test('E5: flake and coarse sea salt weigh like kosher salt (0.72 g/mL), '
        'never table salt — "2 tablespoons flake sea salt" (Sous-Vide '
        'Rosemary-Mustard Seed-Crusted Roast Beef, 0227) 21.3 g, not 36 g; '
        '"2 teaspoons coarse sea salt, divided" (Fougasse, 0805; its item '
        'reads "sea salt") 7.1 g; '
        '"1 tablespoon table salt" (0052) stays 18 g', () async {
      expect(
        await gramsOn('2 tablespoons flake sea salt', 173468),
        closeTo(2 * 14.7868 * 0.72, 0.01),
      );
      expect(
        await gramsOn('2 teaspoons coarse sea salt, divided', 173468),
        closeTo(2 * 4.92892 * 0.72, 0.01),
      );
      expect(
        await gramsOn('1 tablespoon table salt', 173468),
        closeTo(14.7868 * 1.22, 0.01),
      );
    });

    test('E6: a sub-gram "pepper" portion weighs only a small DRIED chile — '
        'arbol (Palak Dal, 0109), bird (Biang Biang Mian, 0376), small and '
        'dried (Orange-Flavored Chicken, 0525); never a fresh Thai chile '
        '(Panang Beef Curry, 0551), nor a bell pepper whose item names the '
        'noun ("2 jarred hot cherry peppers, stems removed", Pan-Seared '
        'Thick-Cut Boneless Pork Chops, 0199, put on the sun-dried record: a '
        'synthesized pairing, a '
        'stated exception)', () async {
      expect(await gramsOn('4 whole dried arbol chiles', 168570), 2.0);
      expect(await gramsOn('10–20 bird chiles, ground fine', 168570), 7.5);
      expect(
        await gramsOn('8 small whole dried red chiles (optional)', 168570),
        4.0,
      );
      expect(
        await gramsOn('1 Thai red chile, halved lengthwise (optional)', 168570),
        isNull,
      );
      // Small is not dried: Panang's line called small (a synthesized word,
      // a stated exception — every small fresh chile of the corpus is sized
      // by the piece table first, "1 small Thai chile" 2 g).
      expect(
        await gramsOn('1 small Thai red chile, halved lengthwise', 168570),
        isNull,
      );
      expect(
        await gramsOn('2 jarred hot cherry peppers, stems removed', 168570),
        isNull,
      );
      // A whole-gram pepper portion sizes any chile: "2 dried ancho chiles"
      // (Best Vegetarian Chili, 0498) is 2 × 17 g.
      expect(await gramsOn('2 dried ancho chiles', 169396), 34.0);
    });

    test('E7: a bare count whose parenthetical prints the volume is that '
        'volume — "4–6 Swiss chard leaves … (about 2 cups; optional)" '
        '(Hearty Chicken Noodle Soup, 0002) 72 g, not 240 g; "5½ fluid '
        'ounces (½ cup plus 3 tablespoons) champagne, chilled" (Champagne '
        'Cocktail, 1155) both parts, 163 mL — 165 g — not 990 g', () async {
      expect(
        await gramsOn(
          '4–6 Swiss chard leaves, ribs removed, torn into 1-inch pieces '
          '(about 2 cups; optional)',
          169991,
        ),
        closeTo(72, 0.01),
      );
      // As the corpus stores it: the bare count 5½ (1155's parse).
      const champagne =
          '5½ fluid ounces (½ cup plus 3 tablespoons) champagne, chilled';
      const stored = IngredientLine(
        raw: champagne,
        item: 'fluid ounces (1/2 cup plus 3 tablespoons) champagne',
        amounts: [
          Amount(measure: Measure.count, quantity: '5 1/2', primary: true),
        ],
      );
      final punch = (await provider.food(2710675))!;
      expect(
        lineGrams(tempDb(), stored, punch)?.grams,
        closeTo(163 / 29.5735 * 30, 0.01),
      );
    });

    test('E12: an animal or an adjective before a list of foods stays the '
        'adjective — "chicken or beef or vegetable broth", "dark or light or '
        'golden brown sugar" never split (no corpus line has the shape: '
        'synthesized, a stated exception); a list of foods still splits '
        "(0306's saltines, pinned in v14a A8)", () {
      for (final item in [
        'chicken or beef or vegetable broth',
        'dark or light or golden brown sugar',
      ]) {
        expect(leftAlternative(item, (_) => true), isNull, reason: item);
      }
    });
  });
  group('P1–P3: the sub-recipe fallback, a pick on a held medium, SR '
      'portions', () {
    final provider = FixtureProvider();

    /// [id]'s recorded detail with its portions stripped (a stated
    /// exception: no recorded record of the food lacks them).
    Future<String> stripped(int id) async {
      final food = (await provider.food(id))!;
      return jsonEncode(
        FdcFood(
          fdcId: food.fdcId,
          description: food.description,
          dataType: food.dataType,
          nutrientsPer100g: food.nutrientsPer100g,
          portions: const [],
        ).toJson(),
      );
    }

    test('P1: a marked count picked over the gate whose food gives no grams '
        'is the sub-recipe — "8 Home-Fried Taco Shells (recipe follows)" '
        '(0478) with "Taco shells, baked" cached portion-less', () async {
      final db = tempDb()..fdcFoodCachePut(172800, await stripped(172800));
      await matchAndCompute(
        db,
        FixtureProvider(),
        recipeOf(db: db, [
          ['8 Home-Fried Taco Shells (recipe follows)'],
        ]),
      );
      final row = rowAt(db, 0);
      expect(
        (row.status, row.fdcId, row.grams, row.description),
        ('confirmed', null, 0, subRecipeNote),
      );
    });

    test(
      'P1, P8: a pick BELOW the gate whose detail IS cached and gives no '
      'grams is the sub-recipe too — its grams say something about the '
      'food ("15 curry leaves (see this page)" on "Beef curry" at 0.465, '
      "v14a A5's synthesized line — red plums until matcher v21 and "
      'niçoise olives until v31 rose over the gate — the detail cached '
      'portion-less)',
      () async {
        final db = tempDb()..fdcFoodCachePut(2706388, await stripped(2706388));
        await matchAndCompute(
          db,
          FixtureProvider(),
          recipeOf(db: db, [
            ['15 curry leaves (see this page)'],
          ]),
        );
        expect(rowAt(db, 0).description, subRecipeNote);
      },
    );

    test('E11: an un-skip returns a skipped rule row to itself — the taco '
        "shells' sub-recipe row (their record cached portion-less, P1) and "
        "0405's 'Salt and pepper' — never an auto row on no food", () async {
      final db = tempDb()..fdcFoodCachePut(172800, await stripped(172800));
      final r = recipeOf(db: db, [
        ['8 Home-Fried Taco Shells (recipe follows)', 'Salt and pepper'],
      ]);
      await matchAndCompute(db, FixtureProvider(), r);
      for (final position in [0, 1]) {
        final before = rowAt(db, position);
        await applyMatchOverride(db, provider, r, position, {'skipped': true});
        await applyMatchOverride(db, provider, r, position, {
          'skipped': false,
        });
        final after = rowAt(db, position);
        expect(
          (after.status, after.fdcId, after.description),
          ('confirmed', null, before.description),
          reason: before.raw,
        );
      }
    });

    test(
      'E11: an un-skip gates a marked count on its food as the compute '
      'does — the below-gate curry-leaves pick (A5; plums until matcher '
      'v21, olives until v31) comes back held while its '
      'detail is uncached, and the 0 g sub-recipe once a cached detail '
      'gives it no grams (cached portion-less: a stated exception)',
      () async {
        final db = tempDb();
        final r = recipeOf(db: db, [
          ['15 curry leaves (see this page)'],
        ]);
        await matchAndCompute(db, FixtureProvider(), r);
        Future<IngredientMatchRow> skipAndBack() async {
          await applyMatchOverride(db, provider, r, 0, {'skipped': true});
          await applyMatchOverride(db, provider, r, 0, {'skipped': false});
          return rowAt(db, 0);
        }

        var row = await skipAndBack();
        expect((row.status, row.fdcId, row.grams), ('auto', 2706388, null));
        db.fdcFoodCachePut(2706388, await stripped(2706388));
        row = await skipAndBack();
        expect((row.status, row.description), ('confirmed', subRecipeNote));
      },
    );

    // Run 050 U2 overturned v15's E11 (the 0 g sub-recipe again): typed
    // grams are the person's row before any gate, as the compute keeps a
    // decided row and a confirm or pick keeps typed grams on this line.
    test('E11 (Run 050 U2): a food a person typed grams for on a sub-recipe '
        'the recipe makes apart, skipped and un-skipped, is their row again — '
        '"1 recipe Simple Tomato Sauce (recipe follows), warmed (see note)" '
        '(Lighter Chicken Parmesan, 0416; the pick synthesized: a stated '
        'exception)', () async {
      final db = tempDb();
      final r = recipeOf(db: db, [
        ['1 recipe Simple Tomato Sauce (recipe follows), warmed (see note)'],
      ]);
      await matchAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 0, {
        'fdc_id': 173468,
        'grams': 100,
      });
      expect((rowAt(db, 0).status, rowAt(db, 0).grams), ('overridden', 100));
      await applyMatchOverride(db, provider, r, 0, {'skipped': true});
      await applyMatchOverride(db, provider, r, 0, {'skipped': false});
      final row = rowAt(db, 0);
      expect(
        (row.status, row.fdcId, row.grams, row.gramSource),
        ('overridden', 173468, 100, 'override'),
      );
    });

    test('E9: an apply-to-all never counts a sub-recipe the recipe makes '
        'apart — "10 cups Vanilla Frosting (recipe follows)" (Rainbow Cake, '
        '1201) left an auto row on a food by an older engine (synthesized: a '
        'stated exception) lands as the 0 g sub-recipe', () async {
      final db = tempDb();
      const raw = '10 cups Vanilla Frosting (recipe follows)';
      final a = recipeOf(db: db, id: 'a', [
        [raw],
      ]);
      final b = recipeOf(db: db, id: 'b', [
        [raw],
      ]);
      await matchAndCompute(db, provider, a);
      await matchAndCompute(db, provider, b);
      db.upsertIngredientMatch(
        rowAt(db, 0, id: 'a').copyWith(
          fdcId: 173468,
          description: 'Salt, table',
          dataType: 'SR Legacy',
          confidence: 0.3,
          clearGrams: true,
          clearGramSource: true,
          status: 'auto',
        ),
      );
      await applyMatchOverride(db, provider, b, 0, {
        'fdc_id': 173430,
        'apply_to_all': true,
      });
      final row = rowAt(db, 0, id: 'a');
      expect((row.fdcId, row.grams, row.description), (null, 0, subRecipeNote));
    });

    test('P2: a pick on a held medium with an eaten plus part keeps that '
        "part — Shrimp Salad's (0286) \"¼ cup plus 1 tablespoon juice\", the "
        '¼ cup in the drained broth, the tablespoon in the dressing: 15.2 g '
        'on "Lemon juice, raw"', () async {
      final db = tempDb();
      final r = recipeOf(
        db: db,
        [
          [
            '1 pound extra-large shrimp (21 to 25 per pound), peeled and '
                'deveined (see this page)',
            '¼ cup plus 1 tablespoon juice from 2 to 3 lemons, spent halves '
                'reserved',
          ],
        ],
        steps: [
          'Combine the shrimp, ¼ cup of the lemon juice, the reserved lemon '
              'halves, parsley sprigs, tarragon sprigs, whole peppercorns, '
              'sugar, and 1 teaspoon salt with 2 cups cold water in a medium '
              'saucepan. Place the saucepan over medium heat and cook the '
              'shrimp, stirring several times, until pink, firm to the touch, '
              'and the centers are no longer translucent, 8 to 10 minutes '
              '(the water should be just bubbling around the edge of the pan '
              'and register 165 degrees on an instant-read thermometer). '
              'Remove the pan from the heat, cover, and let the shrimp sit in '
              'the broth for 2 minutes.',
          'Meanwhile, fill a medium bowl with ice water. Drain the shrimp '
              'into a colander and discard the lemon halves, herbs, and '
              'spices. Immediately transfer the shrimp to the ice water to '
              'stop the cooking and chill thoroughly, about 3 minutes. Remove '
              'the shrimp from the ice water and pat dry with paper towels.',
          'Whisk together the mayonnaise, celery, shallot, remaining 1 '
              'tablespoon lemon juice, the minced parsley, and minced '
              'tarragon in a medium bowl. Cut the shrimp in half lengthwise '
              'and then each half into thirds; add the shrimp to the '
              'mayonnaise mixture and toss to combine. Season with salt and '
              'pepper to taste and serve.',
        ],
      );
      await matchAndCompute(db, provider, r);
      expect(rowAt(db, 1).hold, 'discarded_medium');
      await applyMatchOverride(db, provider, r, 1, {'fdc_id': 167747});
      final row = rowAt(db, 1);
      expect(row.grams, closeTo(15.23, 0.01));
      expect(row.gramSource, 'discarded');
    });

    test('P3: an SR bare-noun portion is one item only when its amount is '
        'ONE — "30 saltine crackers" (Oven-Fried Onion Rings, 0315) on '
        '"Crackers, whole-wheat" (172749) is 30 × its "cracker" 4.6 g, never '
        '30 × the 28 g of "6 crackers, Triscuits, regular size" (the pick is '
        'synthesized, a stated exception: no recorded bare-noun portion of '
        'amount other than one names "medium" or "fruit")', () async {
      final crackers = (await provider.food(172749))!;
      final grams = lineGrams(
        tempDb(),
        lineOf('30 saltine crackers'),
        crackers,
      );
      expect(grams?.grams, closeTo(138.0, 1e-9));
    });
  });
  group("P4: the engine's own rule rows — rewritten, never a person's", () {
    const salt = '1 tablespoon table salt';
    const seasoning = 'Salt and pepper';

    IngredientMatchRow stored(
      String raw,
      int position, {
      required String status,
      required String description,
      int? fdcId,
    }) => IngredientMatchRow(
      recipeId: 'r',
      position: position,
      raw: raw,
      itemKey: lineKeyOf(lineOf(raw)),
      fdcId: fdcId,
      description: description,
      dataType: null,
      confidence: 1,
      grams: null,
      gramSource: null,
      status: status,
    );

    for (final (slot, note) in engineRuleNotes.indexed) {
      test('each note is a rule row the engine rewrites: a stale "$note" '
          'row on "$salt" (0052; an older engine\'s row, synthesized: a '
          'stated exception) becomes its salt', () async {
        final db = tempDb();
        final r = recipeOf(db: db, [
          [salt],
        ]);
        db.upsertIngredientMatch(
          stored(salt, 0, status: 'confirmed', description: note),
        );
        await matchAndCompute(db, FixtureProvider(), r);
        expect(rowAt(db, 0).fdcId, 173468, reason: 'slot $slot');
      });
    }

    test(
      "a person's row carrying a note is no rule row: moved by a line put "
      'above it, a confirm on a food and a confirm of no match travel '
      'with their lines (rows and move synthesized: a stated exception)',
      () async {
        final db = tempDb();
        recipeOf(db: db, [
          [seasoning, salt],
        ]);
        db
          ..upsertIngredientMatch(
            stored(
              seasoning,
              0,
              status: 'confirmed',
              description: 'No FoodData Central match',
            ),
          )
          ..upsertIngredientMatch(
            stored(
              salt,
              1,
              status: 'confirmed',
              description: engineRuleNotes[1],
              fdcId: 173468,
            ),
          );
        final moved = recipeOf(db: db, [
          ['½ cup soy sauce', seasoning, salt],
        ]);
        await matchAndCompute(db, FixtureProvider(), moved);
        expect(rowAt(db, 1).description, 'No FoodData Central match');
        expect(rowAt(db, 2).fdcId, 173468);
        expect(rowAt(db, 2).status, 'confirmed');
      },
    );

    test("the write guard, not the snapshot, protects a person's decision "
        'made while a compute runs: a skip of a seasoning row, a confirm of '
        'a row with no match, and a confirmed food under a note (the last '
        'synthesized: a stated exception) all stand', () async {
      for (final (label, decide) in [
        (
          'skip',
          (SaltDatabase db, Recipe r) =>
              applyMatchOverride(db, FixtureProvider(), r, 1, {
                'skipped': true,
              }),
        ),
        (
          'confirm',
          (SaltDatabase db, Recipe r) async {
            db.upsertIngredientMatch(
              stored(
                seasoning,
                1,
                status: 'unmatched',
                description: 'No FoodData Central match',
              ),
            );
            await applyMatchOverride(db, FixtureProvider(), r, 1, {
              'confirmed': true,
            });
          },
        ),
        (
          'food',
          (SaltDatabase db, Recipe r) async => db.upsertIngredientMatch(
            stored(
              seasoning,
              1,
              status: 'confirmed',
              description: engineRuleNotes[1],
              fdcId: 173468,
            ),
          ),
        ),
      ]) {
        final db = tempDb();
        final r = recipeOf(db: db, [
          [salt, seasoning],
        ]);
        db.upsertIngredientMatch(
          stored(
            seasoning,
            1,
            status: 'confirmed',
            description: engineRuleNotes[1],
          ),
        );
        final provider = FixtureProvider()..gate = Completer<void>();
        final compute = matchAndCompute(db, provider, r);
        await pumpEventQueue();
        await decide(db, r);
        final decided = rowAt(db, 1);
        provider.gate!.complete();
        await compute;
        final after = rowAt(db, 1);
        expect(
          (after.status, after.fdcId, after.description),
          (decided.status, decided.fdcId, decided.description),
          reason: label,
        );
      }
    });
  });
  group('P5: an SR "pepper" portion weighs a chile, and only a chile', () {
    final provider = FixtureProvider();

    Future<double?> gramsOn(String raw, int fdcId) async => lineGrams(
      tempDb(),
      lineOf(raw),
      await provider.food(fdcId),
    )?.grams;

    test('every spelling of the chile reads the "pepper" portion — "2 dried '
        'ancho chiles" (Best Vegetarian Chili, 0498) and its singular and '
        '"chili" spellings (synthesized: every corpus line of those forms is '
        'sized by the piece table first, a stated exception)', () async {
      for (final (raw, grams) in [
        ('2 dried ancho chiles', 34.0),
        ('1 dried ancho chile', 17.0),
        ('1 dried ancho chili', 17.0),
        ('2 dried ancho chilies', 34.0),
      ]) {
        expect(await gramsOn(raw, 169396), grams, reason: raw);
      }
    });

    test('a chile names only the "pepper" portion, and only a chile does: '
        '"2 dried ancho chiles" on Swiss chard\'s "leaf", and "2 dried '
        'anchos" (no chile named) on the ancho\'s "pepper", weigh nothing '
        '(both synthesized: a stated exception)', () async {
      expect(await gramsOn('2 dried ancho chiles', 169991), isNull);
      expect(await gramsOn('2 dried anchos', 169396), isNull);
    });
  });
  group('P6, P8: the poured-away detectors and the printed amounts', () {
    DiscardedMedium? mediumOf(Recipe recipe, int i) {
      final line = nutritionLines(recipe)[i];
      return discardedMediumOf(recipe, line, normalizeItem(lineItemOf(line)));
    }

    for (final (file, raws) in [
      // A mention sentence that combines, whisks or dissolves nothing.
      ('1084-rhode-islandstyle-fried-calamari.yaml', ['1 pound squid']),
      (
        '0461-simplified-cassoulet-with-pork-and-kielbasa.yaml',
        ['1 medium onion', '1 medium head garlic', 'Ground black pepper'],
      ),
      // A drain after an "add … toss" in the mention's own step only.
      (
        '0327-pasta-caprese.yaml',
        [
          '2–4 teaspoons juice',
          '1 small garlic clove',
          '1 small shallot',
          'Table salt and ground black pepper',
        ],
      ),
      // A later drain of a food the mention sentence does not name.
      (
        '0063-lentil-salad-with-olives-mint-and-feta.yaml',
        [
          '3 tablespoons white wine vinegar',
        ],
      ),
      (
        '0957-easy-apple-strudel.yaml',
        [
          '8 tablespoons (1 stick) unsalted butter',
          '¼ cup fresh bread crumbs',
        ],
      ),
    ]) {
      test(
        "P6: none of $file's lines ${raws.join(' / ')} is poured away",
        () {
          final r = loadCorpusRecipe(file);
          final lines = nutritionLines(r);
          for (final raw in raws) {
            final i = lines.indexWhere((l) => l.raw.startsWith(raw));
            expect(i, isNonNegative, reason: raw);
            expect(mediumOf(r, i), isNull, reason: lines[i].raw);
          }
        },
        skip: skipIfNoCorpus,
      );
    }

    test('P6: a later step draining a food the boil never named drains '
        "nothing — 0572's hummus steps with its later drain of the "
        'chickpeas made one of beans (a synthesized word, a stated '
        'exception)', () {
      final r = recipeOf(
        [
          ['2 (15-ounce) cans chickpeas, rinsed', '½ teaspoon baking soda'],
        ],
        steps: [
          'Combine chickpeas, baking soda, and 6 cups water in medium '
              'saucepan and bring to boil over high heat. Reduce heat and '
              'simmer, stirring occasionally, until chickpea skins begin to '
              'float to surface and chickpeas are creamy and very soft, 20 to '
              '25 minutes.',
          'While chickpeas cook, mince garlic using garlic press or '
              'rasp-style grater.',
          'Drain beans in colander and return to saucepan.',
        ],
      );
      expect(mediumOf(r, 1), isNull);
    });

    test('P6, P8: printed amounts — "2 1-pound whole boneless shell sirloin '
        'steaks …" (Pan-Seared Inexpensive Steaks, 0190) is 2 × 1 pound; "1 '
        '(750-milliliter) bottle red Burgundy or Pinot Noir" (Beef Burgundy, '
        '0457) 750 mL of the wine, and two bottles twice that (the count '
        'synthesized: a stated exception)', () async {
      final db = tempDb();
      expect(
        lineGrams(
          db,
          lineOf(
            '2 1-pound whole boneless shell sirloin steaks (top butt) or '
            'whole flap meat steaks, each about 1¼ inches thick',
          ),
          null,
        )?.grams,
        closeTo(907.18, 0.01),
      );
      final wine = (await FixtureProvider().food(174835))!;
      expect(
        lineGrams(
          db,
          lineOf('1 (750-milliliter) bottle red Burgundy or Pinot Noir'),
          wine,
        )?.grams,
        closeTo(745.6, 0.1),
      );
      expect(
        lineGrams(
          db,
          lineOf('2 (750-milliliter) bottles red Burgundy or Pinot Noir'),
          wine,
        )?.grams,
        closeTo(2 * 745.6, 0.2),
      );
    });

    test("P6: only a \"1 recipe\" line is a single food's yield — \"1 cup "
        "Easy-Peel Hard-Cooked Eggs\" beside 0731's subsection keeps its cup "
        '(a synthesized unit, a stated exception)', () {
      final r = recipeOf(
        [
          ['1 cup Easy-Peel Hard-Cooked Eggs (recipe follows)'],
        ],
        subsections: [
          subsectionOf('Easy-Peel Hard-Cooked Eggs', ['6 large eggs']),
        ],
      );
      expect(nutritionLines(r).single.amounts.single.unit, 'cup');
    });
  });
  group('E8, E10: a typed weight and an un-skipped pot share', () {
    test('E8: typed grams on "1 tablespoon minced fresh oregano" '
        '(Acquacotta, 0405) on its dried record read "entered by hand", '
        'never "approximate (dried herb record for a fresh herb)"', () {
      final line = lineOf('1 tablespoon minced fresh oregano');
      final row = IngredientMatchRow(
        recipeId: 'r',
        position: 0,
        raw: line.raw,
        fdcId: 171328,
        description: 'Spices, oregano, dried',
        dataType: 'SR Legacy',
        confidence: 1,
        grams: 5,
        gramSource: 'override',
        status: 'overridden',
      );
      expect(gramBasisFor(tempDb(), line, row), 'entered by hand');
    });

    test("E10: an un-skip of Stovetop Macaroni and Cheese's (0301) held pot "
        'salt re-weighs its line — the ½ teaspoon the custard eats (3.0 g), '
        'never a quarter of the stored share', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = recipeOf(
        db: db,
        [
          ['2 teaspoons table salt'],
        ],
        steps: [
          'Mix the eggs, 1 cup of the evaporated milk, ½ teaspoon of the '
              'salt, the pepper, mustard mixture, and hot sauce in a small '
              'bowl; set aside.',
          'Meanwhile, bring 2 quarts water to a boil in a large '
              'heavy-bottomed saucepan or Dutch oven. Add the remaining 1½ '
              'teaspoons salt and the macaroni; cook until almost tender but '
              'still a little firm to the bite. Drain and return to the pan '
              'over low heat. Add the butter; toss to melt.',
        ],
      );
      await matchAndCompute(db, provider, r);
      (double?, String?, String?) state() {
        final row = rowAt(db, 0);
        return (row.grams, row.gramSource, row.hold);
      }

      // ½ of the line's 12.03 g of table salt (173468).
      final computed = state();
      expect(computed.$1, closeTo(3.0066, 1e-4));
      expect((computed.$2, computed.$3), ('discarded', 'discarded_medium'));
      await applyMatchOverride(db, provider, r, 0, {'skipped': true});
      await applyMatchOverride(db, provider, r, 0, {'skipped': false});
      expect(state(), computed);
    });
  });
  test('P7: every corpus line and step the corpus-free pins transcribe '
      '(v14a, v14b, v15, v16, v17) still reads so in its corpus file', () {
    final texts = <String, Set<String>>{};
    Set<String> textOf(String file) => texts.putIfAbsent(file, () {
      final r = loadCorpusRecipe(file);
      final groups = [
        ...r.ingredients,
        for (final s in r.subsections) ...?s.ingredients,
      ];
      return {
        for (final g in groups)
          for (final l in g.items) l.raw,
        for (final s in r.steps) s.text,
        for (final s in r.subsections)
          for (final step in s.steps ?? const <RecipeStep>[]) step.text,
      };
    });
    expect(pinnedCorpusText, hasLength(greaterThan(100)));
    for (final (file, text) in pinnedCorpusText) {
      expect(textOf(file), contains(text), reason: file);
    }
  }, skip: skipIfNoCorpus);
}
