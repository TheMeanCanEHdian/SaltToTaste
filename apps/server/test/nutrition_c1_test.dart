// Real corpus lines wrap across adjacent literals.
// ignore_for_file: no_adjacent_strings_in_list

import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart' as frog;
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/admin_handlers.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import '../routes/api/v1/admin/nutrition_review.dart' as review_route;
import '../routes/api/v1/recipes/[id]/nutrition/matches/[pos].dart'
    as match_route;
import 'support/applied.dart';
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// C1 (the review-UI rulings of 2026-09-28): the queue's `finishes` count
/// and `sort`, the apply receipt's `completed`, the cache-only `portions`,
/// the approximation basis and the single-portion yield rule. Pinned WITHOUT
/// the corpus on real corpus lines (recipe named on each) in their real
/// sweep-snapshot-11 triage states, over recorded FDC answers; the corpus
/// and snapshot groups at the end skip without them.
void main() {
  final provider = FixtureProvider();

  /// Sends [method] (with [body], if any) to [route] through the real
  /// pipeline's error handler, as a signed-in admin; returns the status and
  /// the decoded body.
  Future<(int, Map<String, dynamic>)> callRoute(
    SaltDatabase db,
    frog.Handler route,
    String method, {
    String path = '/',
    Map<String, Object?>? body,
  }) async {
    final adminId =
        db.userByUsername('admin')?.id ??
        db.createUser(username: 'admin', passwordHash: 'unused', role: 'admin');
    final pipeline = route
        .use(
          frog.provider<AuthUser?>(
            (_) => AuthUser(
              id: adminId,
              username: 'admin',
              role: 'admin',
              mustChangePassword: false,
              scope: 'full',
              via: 'session',
            ),
          ),
        )
        .use(frog.provider<NutritionProvider>((_) => provider))
        .use(frog.provider<SaltDatabase>((_) => db))
        .use(errorHandler())
        .use(requestIdProvider());
    final server = await frog.serve(pipeline, InternetAddress.loopbackIPv4, 0);
    final client = HttpClient();
    try {
      final request = await client.open(method, '127.0.0.1', server.port, path);
      request.headers
        ..contentType = ContentType.json
        ..set('X-Requested-With', csrfHeaderValue);
      if (body != null) {
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      return (response.statusCode, jsonDecode(text) as Map<String, dynamic>);
    } finally {
      client.close();
      await server.close(force: true);
    }
  }

  /// PUTs [body] to line [pos] of [slug] through the real override route,
  /// as a signed-in admin, and returns the decoded response.
  Future<Map<String, dynamic>> putOverRoute(
    SaltDatabase db,
    String slug,
    int pos,
    Map<String, Object?> body,
  ) async {
    final (status, json) = await callRoute(
      db,
      (context) => match_route.onRequest(context, slug, '$pos'),
      'PUT',
      body: body,
    );
    expect(status, HttpStatus.ok, reason: '$json');
    return json;
  }

  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-c1');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    db.upsertSource(slug: 'src', name: 'Test', type: 'book');
    return db;
  }

  Recipe recipeOf(
    SaltDatabase db,
    String title,
    List<String> raws, {
    String? servings,
    String? id,
  }) {
    id ??= title.toLowerCase().replaceAll(RegExp('[^a-z]+'), '-');
    final recipe = Recipe(
      id: id,
      title: title,
      slug: id,
      source: const RecipeSource(name: 'Test', type: 'book'),
      servings: servings,
      serves: parseServings(servings),
      ingredients: [
        IngredientGroup(items: [for (final raw in raws) lineOf(raw)]),
      ],
    );
    db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h$id');
    return recipe;
  }

  /// Writes [recipe]'s line [position] in its real snapshot-11 state.
  void seed(
    SaltDatabase db,
    Recipe recipe,
    int position, {
    required double confidence,
    int? fdcId,
    String? description,
    double? grams,
    String? gramSource,
    String? hold,
    String status = 'auto',
  }) {
    final line = nutritionLines(recipe)[position];
    db.upsertIngredientMatch(
      IngredientMatchRow(
        recipeId: recipe.id,
        position: position,
        raw: line.raw,
        itemKey: lineKeyOf(line),
        fdcId: fdcId,
        description: description,
        dataType: 'SR Legacy',
        confidence: confidence,
        grams: grams,
        gramSource: gramSource,
        status: status,
        hold: hold,
      ),
    );
  }

  const vanilla = 173471; // "Vanilla extract", almond extract's engine pick
  const pecans = 2346395; // "Nuts, pecans, halves, raw"

  /// Six real recipes, cut to the lines the queue reads, each line in its
  /// snapshot-11 state: almond extract (0.475, check) is the last open line
  /// of Angel Food Cake and Easy Holiday Sugar Cookies; the pecan lines have
  /// no grams, and Best Baked Apples' is the group's example (the title
  /// order among ties) while Oatmeal Muffins' is not; Chana Masala waits on
  /// two groups; Perfect Roast Chicken's brine sugar is a line hold.
  SaltDatabase library() {
    final db = tempDb();
    final angel = recipeOf(db, 'Angel Food Cake', [
      '12 large egg whites, at room temperature',
      '½ teaspoon almond extract',
    ]);
    seed(
      db,
      angel,
      0,
      confidence: 0.95,
      fdcId: 747997,
      grams: 396,
      gramSource: 'piece',
      description: 'Eggs, Grade A, Large, egg white',
    );
    seed(
      db,
      angel,
      1,
      confidence: 0.475,
      fdcId: vanilla,
      grams: 2.1,
      gramSource: 'portion',
      description: 'Vanilla extract',
    );
    final cookies = recipeOf(db, 'Easy Holiday Sugar Cookies', [
      '¼ teaspoon almond extract',
    ]);
    seed(
      db,
      cookies,
      0,
      confidence: 0.475,
      fdcId: vanilla,
      grams: 1.05,
      gramSource: 'portion',
      description: 'Vanilla extract',
    );
    for (final (title, raw) in [
      ('Best Baked Apples', '⅓ cup coarsely chopped pecans, toasted'),
      ('Oatmeal Muffins', '⅓ cup pecans, chopped fine'),
    ]) {
      seed(
        db,
        recipeOf(db, title, [raw]),
        0,
        confidence: 0.92,
        fdcId: pecans,
        description: 'Nuts, pecans, halves, raw',
      );
    }
    final chana = recipeOf(db, 'Chana Masala', [
      '1 (1½-inch) piece ginger, peeled and chopped coarse',
      '1½ teaspoons garam masala',
    ]);
    seed(
      db,
      chana,
      0,
      confidence: 0.887,
      fdcId: 169231,
      description: 'Ginger root, raw',
    );
    seed(
      db,
      chana,
      1,
      confidence: 0.015,
      fdcId: 171181,
      description: 'SMART SOUP, Indian Bean Masala',
    );
    final chicken = recipeOf(db, 'Perfect Roast Chicken', ['½ cup sugar']);
    seed(
      db,
      chicken,
      0,
      confidence: 0.95,
      fdcId: 746784,
      grams: 94,
      gramSource: 'portion',
      hold: 'discarded_medium',
      description: 'Sugars, granulated',
    );
    return db;
  }

  group('U2: finishes and sort (nutritionReviewGroups)', () {
    ({String key, int lines, int finishes}) rowOf(NutritionReviewGroupRow g) =>
        (key: g.itemKey, lines: g.lines, finishes: g.finishes);

    test('finishes counts the recipes whose every open line is in the group, '
        'each with grams or the example: almond extract finishes both its '
        "recipes, pecans only the example's, Chana Masala nothing, the "
        'held brine sugar its own', () {
      final groups = library().nutritionReviewGroups(limit: 50, offset: 0);
      expect(
        [for (final g in groups) rowOf(g)],
        [
          (key: 'almond extract', lines: 2, finishes: 2),
          (key: 'pecan', lines: 2, finishes: 1),
          (key: 'sugar', lines: 1, finishes: 1),
          (key: 'garam masala', lines: 1, finishes: 0),
          (key: 'ginger', lines: 1, finishes: 0),
        ],
      );
      final pecan = groups[1];
      expect(pecan.title, 'Best Baked Apples', reason: 'the example');
    });

    test('a tie on finishes goes to more lines, then the worse match: '
        "Goan Pork Vindaloo's ginger makes ginger two lines (finishing "
        'nothing: neither line has grams, and Chana Masala waits on garam '
        'masala), so it sorts before garam masala (one line at 1.5%)', () {
      final db = library();
      seed(
        db,
        recipeOf(db, 'Goan Pork Vindaloo', [
          '1 (1½-inch) piece ginger, peeled and sliced crosswise ⅛ inch thick',
        ]),
        0,
        confidence: 0.887,
        fdcId: 169231,
        description: 'Ginger root, raw',
      );
      expect(
        [
          for (final g in db.nutritionReviewGroups(limit: 50, offset: 0))
            rowOf(g),
        ],
        [
          (key: 'almond extract', lines: 2, finishes: 2),
          (key: 'pecan', lines: 2, finishes: 1),
          (key: 'sugar', lines: 1, finishes: 1),
          (key: 'ginger', lines: 2, finishes: 0),
          (key: 'garam masala', lines: 1, finishes: 0),
        ],
      );
    });

    test('each group names the recipes it finishes and counts the recipes '
        'it holds the last open lines of; the banner sums the library', () {
      final db = library();
      final groups = {
        for (final g in db.nutritionReviewGroups(limit: 50, offset: 0))
          g.itemKey: g,
      };
      List<String> titles(String key) => [
        for (final r in groups[key]!.finishesRecipes) r.title,
      ];
      expect(titles('almond extract'), [
        'Angel Food Cake',
        'Easy Holiday Sugar Cookies',
      ]);
      expect(
        groups['almond extract']!.finishesRecipes.first.id,
        'angel-food-cake',
      );
      // Both pecan lines are their recipes' last; only the example's
      // finishes (Oatmeal Muffins' has no grams, and is not the example).
      expect(titles('pecan'), ['Best Baked Apples']);
      expect(groups['pecan']!.lastOpen, 2);
      expect(titles('ginger'), isEmpty);
      expect(groups['ginger']!.lastOpen, 0);
      expect(titles('sugar'), ['Perfect Roast Chicken']);
      expect(db.nutritionReviewFinishable(), (finishable: 4, open: 6));
      final body = nutritionReviewHandler(
        db,
        page: 1,
        limit: 50,
        group: 'item',
      );
      expect(body['finishable'], 4);
      expect(body['open_recipes'], 6);
      final pecan = (body['items']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .firstWhere((g) => g['item_key'] == 'pecan');
      expect(pecan['finishes_recipes'], [
        {'id': 'best-baked-apples', 'title': 'Best Baked Apples'},
      ]);
      expect(pecan['last_open'], 2);
      // The line mode has no banner.
      final lines = nutritionReviewHandler(db, page: 1, limit: 50);
      expect(lines.containsKey('finishable'), isFalse);
    });

    test(
      'sort=worst is the worst-confidence order, finishes carried along',
      () {
        final groups = library().nutritionReviewGroups(
          limit: 50,
          offset: 0,
          sort: 'worst',
        );
        expect(
          [for (final g in groups) rowOf(g)],
          [
            (key: 'garam masala', lines: 1, finishes: 0),
            (key: 'almond extract', lines: 2, finishes: 2),
            (key: 'ginger', lines: 1, finishes: 0),
            (key: 'pecan', lines: 2, finishes: 1),
            (key: 'sugar', lines: 1, finishes: 1),
          ],
        );
      },
    );

    test('a bucket filter narrows the members, never what a recipe still '
        'waits on: under no_grams ginger still finishes nothing (garam '
        'masala is open in check)', () {
      final groups = library().nutritionReviewGroups(
        limit: 50,
        offset: 0,
        bucket: 'no_grams',
      );
      expect(
        [for (final g in groups) rowOf(g)],
        [
          (key: 'pecan', lines: 2, finishes: 1),
          (key: 'ginger', lines: 1, finishes: 0),
        ],
      );
    });

    test('the body carries finishes per group; sort defaults to finishes '
        'and an unknown sort is a 422', () {
      final db = library();
      final body = nutritionReviewHandler(
        db,
        page: 1,
        limit: 50,
        group: 'item',
      );
      final items = body['items']! as List<Object?>;
      final first = items.first! as Map<String, Object?>;
      expect(first['item_key'], 'almond extract');
      expect(first['finishes'], 2);
      final worst = nutritionReviewHandler(
        db,
        page: 1,
        limit: 50,
        group: 'item',
        sort: 'worst',
      );
      expect(
        ((worst['items']! as List<Object?>).first!
            as Map<String, Object?>)['item_key'],
        'garam masala',
      );
      expect(
        () => nutritionReviewHandler(
          db,
          page: 1,
          limit: 50,
          group: 'item',
          sort: 'best',
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('Run 046: finishes promises only what a confirm can count', () {
    /// The library plus three real snapshot-11 rows: Parmesan Farrotto's
    /// farro, a Check line with NO grams (0.495) and the recipe's only open
    /// line; Greek-Style Shrimp's ouzo, a No match line, its recipe's only
    /// open line; and Stovetop Rice Pudding's counted sugar (complete).
    SaltDatabase wider() {
      final db = library();
      seed(
        db,
        recipeOf(db, 'Parmesan Farrotto', ['1½ cups whole farro']),
        0,
        confidence: 0.495,
        fdcId: 2710828,
        description: 'Farro, pearled, dry, raw',
      );
      seed(
        db,
        recipeOf(db, 'Greek-Style Shrimp with Tomatoes and Feta', [
          '3 tablespoons ouzo',
        ]),
        0,
        confidence: 0,
        status: 'unmatched',
      );
      seed(
        db,
        recipeOf(db, 'Stovetop Rice Pudding', ['⅔ cup (4⅔ ounces) sugar']),
        0,
        confidence: 0.95,
        fdcId: 746784,
        grams: 132.29766666666666,
        gramSource: 'weight',
        description: 'Sugars, granulated',
      );
      return db;
    }

    test('groups: the farro (a Check example with no grams) and the ouzo '
        "(No match) finish nothing, though each is its recipe's last open "
        'line; the banner counts neither, nor the complete rice pudding as '
        'open', () {
      final db = wider();
      final groups = {
        for (final g in db.nutritionReviewGroups(limit: 50, offset: 0))
          g.itemKey: g,
      };
      for (final key in ['whole farro', 'ouzo']) {
        expect(groups[key]!.finishes, 0, reason: key);
        expect(groups[key]!.finishesRecipes, isEmpty, reason: key);
        expect(groups[key]!.lastOpen, 1, reason: key);
      }
      // The No grams pecan example still finishes its own recipe.
      expect(groups['pecan']!.finishes, 1);
      expect(db.nutritionReviewFinishable(), (finishable: 4, open: 8));
    });

    test('lines: the farro and the ouzo are 0, the No grams pecans 1; a '
        'skipped line with grams is never a finisher', () {
      final db = wider();
      Map<String, int> finishesOf(String? bucket) => {
        for (final item
            in (nutritionReviewHandler(
                      db,
                      page: 1,
                      limit: 50,
                      bucket: bucket,
                    )['items']!
                    as List<Object?>)
                .cast<Map<String, Object?>>())
          item['raw']! as String: item['finishes']! as int,
      };
      final all = finishesOf(null);
      expect(all['1½ cups whole farro'], 0);
      expect(all['3 tablespoons ouzo'], 0);
      expect(all['⅓ cup pecans, chopped fine'], 1);
      expect(all['½ teaspoon almond extract'], 1);
      // Skip Angel Food Cake's egg whites (396 g): the almond extract stays
      // its last open line, and the skipped line finishes nothing.
      final angel = db.recipeByIdOrSlug('angel-food-cake')!.recipe;
      db.upsertIngredientMatch(
        db.ingredientMatchesFor(angel.id)[0].copyWith(status: 'skipped'),
      );
      expect(finishesOf('skipped'), {
        '12 large egg whites, at room temperature': 0,
      });
      expect(finishesOf(null)['½ teaspoon almond extract'], 1);
    });

    test('finishes_recipes is in title order, not the row order: the almond '
        'extract recipes under their real ids (0856 Angel Food Cake, 0832 '
        'Easy Holiday Sugar Cookies) come out of SQLite by id', () {
      final db = tempDb();
      for (final (id, title, raw, grams) in [
        (
          'atk-tv-2023-0856-angel-food-cake',
          'Angel Food Cake',
          '½ teaspoon almond extract',
          2.1,
        ),
        (
          'atk-tv-2023-0832-easy-holiday-sugar-cookies',
          'Easy Holiday Sugar Cookies',
          '¼ teaspoon almond extract',
          1.05,
        ),
      ]) {
        seed(
          db,
          recipeOf(db, title, [raw], id: id),
          0,
          confidence: 0.475,
          fdcId: vanilla,
          grams: grams,
          gramSource: 'portion',
          description: 'Vanilla extract',
        );
      }
      final almond = db.nutritionReviewGroups(limit: 50, offset: 0).single;
      expect(
        [for (final r in almond.finishesRecipes) r.title],
        [
          'Angel Food Cake',
          'Easy Holiday Sugar Cookies',
        ],
      );
    });
  });

  group('Run 046 over the routes', () {
    test(
      'GET /admin/nutrition_review forwards sort: worst orders '
      'worst-first, the default is finishes, an unknown sort is a 422',
      () async {
        final db = library();
        Future<(int, Map<String, dynamic>)> get(String query) => callRoute(
          db,
          review_route.onRequest,
          'GET',
          path: '/?group=item$query',
        );
        String firstKey(Map<String, dynamic> body) =>
            ((body['items']! as List<Object?>).first!
                    as Map<String, Object?>)['item_key']!
                as String;
        final (defaultStatus, byDefault) = await get('');
        expect(defaultStatus, HttpStatus.ok);
        expect(firstKey(byDefault), 'almond extract');
        final (worstStatus, worst) = await get('&sort=worst');
        expect(worstStatus, HttpStatus.ok);
        expect(firstKey(worst), 'garam masala');
        final (bogusStatus, bogus) = await get('&sort=bogus');
        expect(bogusStatus, HttpStatus.unprocessableEntity);
        expect((bogus['error']! as Map<String, Object?>)['code'], 'validation');
      },
    );

    test('a bare confirm of a below-gate zero row is refused (zero_row): '
        "Tacos Dorados' pickled jalapeño slices (0.465, 0 g, unmeasured) — "
        'auto or skipped; its chopped tomato (0.92, 0 g) confirms, and so '
        'does a zero row with typed grams', () async {
      final db = tempDb();
      final tacos = recipeOf(db, 'Tacos Dorados (Crispy Tacos)', [
        'Chopped tomato',
        'Pickled jalapeño slices',
      ]);
      seed(
        db,
        tacos,
        0,
        confidence: 0.92,
        fdcId: 1999634,
        grams: 0,
        gramSource: 'unmeasured',
        description: 'Tomato, roma',
      );
      seed(
        db,
        tacos,
        1,
        confidence: 0.465,
        fdcId: 2710096,
        grams: 0,
        gramSource: 'unmeasured',
        description: 'Peppers, jalapenos',
      );
      Future<(int, Map<String, dynamic>)> confirm(int pos) => callRoute(
        db,
        (context) => match_route.onRequest(context, tacos.slug, '$pos'),
        'PUT',
        body: {'confirmed': true},
      );
      for (final status in ['auto', 'skipped']) {
        db.upsertIngredientMatch(
          db.ingredientMatchesFor(tacos.id)[1].copyWith(status: status),
        );
        final (code, body) = await confirm(1);
        expect(code, HttpStatus.unprocessableEntity, reason: status);
        expect(
          (body['error']! as Map<String, Object?>)['code'],
          'zero_row',
          reason: status,
        );
        expect(db.ingredientMatchesFor(tacos.id)[1].status, status);
        expect(
          db.decisionFor(lineKeyOf(nutritionLines(tacos)[1])),
          isNull,
        );
      }
      final (tomato, _) = await confirm(0);
      expect(tomato, HttpStatus.ok);
      expect(db.ingredientMatchesFor(tacos.id)[0].status, 'confirmed');
      // Typed grams are a real answer: Chinese Pork Dumplings' chili oil
      // (on "Oil, canola" at 0.475, 0 g) confirms with 5 g.
      final dumplings = recipeOf(db, 'Chinese Pork Dumplings', ['Chili oil']);
      seed(
        db,
        dumplings,
        0,
        confidence: 0.475,
        fdcId: 172336,
        grams: 0,
        gramSource: 'unmeasured',
        description: 'Oil, canola',
      );
      final (oil, _) = await callRoute(
        db,
        (context) => match_route.onRequest(context, dumplings.slug, '0'),
        'PUT',
        body: {'confirmed': true, 'grams': 5},
      );
      expect(oil, HttpStatus.ok);
      final row = db.ingredientMatchesFor(dumplings.id).single;
      expect((row.status, row.grams), ('confirmed', 5.0));
    });
  });

  group('R2: the zero-row guard, term by term, over the route', () {
    Future<(int, Map<String, dynamic>)> confirm(
      SaltDatabase db,
      Recipe recipe,
    ) => callRoute(
      db,
      (context) => match_route.onRequest(context, recipe.slug, '0'),
      'PUT',
      body: {'confirmed': true},
    );

    test('Indoor Pulled Pork (0246) pos 2, snapshot 12: below the gate '
        '(0.175), discarded, but its eaten "plus 2 teaspoons" weighs '
        '9.47 g — not a zero, so a bare confirm stands', () async {
      final db = tempDb();
      final pork = recipeOf(
        db,
        'Indoor Pulled Pork with Sweet and Tangy Barbecue Sauce',
        ['3 tablespoons plus 2 teaspoons liquid smoke'],
      );
      seed(
        db,
        pork,
        0,
        confidence: 0.17500000000000004,
        fdcId: 167682,
        grams: 9.4666730687946981,
        gramSource: 'discarded',
        description: 'Pectin, liquid',
      );
      final (code, body) = await confirm(db, pork);
      expect(code, HttpStatus.ok, reason: '$body');
      final row = db.ingredientMatchesFor(pork.id).single;
      expect(row.status, 'confirmed');
      expect(row.grams, closeTo(9.4667, 1e-4));
    });

    test('Chicken Francese (1133) pos 8, snapshot 12: below the gate '
        '(0.457), 0 g discarded on "Olive oil" — a zero: a bare confirm is '
        'refused (zero_row)', () async {
      final db = tempDb();
      final francese = recipeOf(db, 'Chicken Francese', [
        '⅓ cup extra-virgin olive oil for frying',
      ]);
      seed(
        db,
        francese,
        0,
        confidence: 0.45666666666666667,
        fdcId: 2710186,
        grams: 0,
        gramSource: 'discarded',
        description: 'Olive oil',
      );
      final (code, body) = await confirm(db, francese);
      expect(code, HttpStatus.unprocessableEntity, reason: '$body');
      expect((body['error']! as Map<String, Object?>)['code'], 'zero_row');
      expect(db.ingredientMatchesFor(francese.id).single.status, 'auto');
    });

    test('P12 (Run 048), the status term: the same Chicken Francese row '
        "ALREADY confirmed (a person's 0 g poured away: synthesized from "
        "snapshot 12's row, a stated exception) re-confirms — the guard "
        'refuses only a guess no person looked at', () async {
      final db = tempDb();
      final francese = recipeOf(db, 'Chicken Francese', [
        '⅓ cup extra-virgin olive oil for frying',
      ]);
      seed(
        db,
        francese,
        0,
        confidence: 0.45666666666666667,
        fdcId: 2710186,
        grams: 0,
        gramSource: 'discarded',
        description: 'Olive oil',
        status: 'confirmed',
      );
      final (code, body) = await confirm(db, francese);
      expect(code, HttpStatus.ok, reason: '$body');
      final row = db.ingredientMatchesFor(francese.id).single;
      expect((row.status, row.grams), ('confirmed', 0));
    });

    test('a 0 g below-gate row on another gram source is no engine zero: '
        'it confirms', () async {
      // Stated exception (synthesized): snapshot 12 holds no 0 g row on a
      // source but unmeasured or discarded. Tacos Dorados' real jalapeño
      // row (0.465) with its source swapped to portion.
      final db = tempDb();
      final tacos = recipeOf(db, 'Tacos Dorados (Crispy Tacos)', [
        'Pickled jalapeño slices',
      ]);
      seed(
        db,
        tacos,
        0,
        confidence: 0.465,
        fdcId: 2710096,
        grams: 0,
        gramSource: 'portion',
        description: 'Peppers, jalapenos',
      );
      final (code, body) = await confirm(db, tacos);
      expect(code, HttpStatus.ok, reason: '$body');
      expect(db.ingredientMatchesFor(tacos.id).single.status, 'confirmed');
    });

    test('a line that names no food (hold unnamed_food) is held, not a '
        'zero: it confirms', () async {
      // Stated exception (synthesized): the one unnamed_food row on
      // snapshot 12, Mechouia (0661) pos 11 "2 tablespoons juice" (0 g,
      // unmeasured, on Beet juice), sits ABOVE the gate at 0.89; its
      // confidence is lowered to 0.475 here.
      final db = tempDb();
      final mechouia = recipeOf(
        db,
        'Mechouia (Tunisian-Style Grilled Vegetables)',
        ['2 tablespoons juice'],
      );
      seed(
        db,
        mechouia,
        0,
        confidence: 0.475,
        fdcId: 2709682,
        grams: 0,
        gramSource: 'unmeasured',
        hold: 'unnamed_food',
        description: 'Beet juice',
      );
      final (code, body) = await confirm(db, mechouia);
      expect(code, HttpStatus.ok, reason: '$body');
      expect(db.ingredientMatchesFor(mechouia.id).single.status, 'confirmed');
    });
  });

  group('U2 in the Lines view: a line finishes its recipe when it is the '
      "recipe's last open line", () {
    test('the Lines view defaults to the finishes order: the lines that '
        'finish their recipe first, then worst first; sort=worst is worst '
        'first', () {
      final db = library();
      List<String> order([String? sort]) => [
        for (final item
            in (nutritionReviewHandler(
                      db,
                      page: 1,
                      limit: 50,
                      sort: sort,
                    )['items']!
                    as List<Object?>)
                .cast<Map<String, Object?>>())
          '${(item['recipe']! as Map<String, Object?>)['title']} · '
              '${item['raw']}',
      ];
      const almondCake = 'Angel Food Cake · ½ teaspoon almond extract';
      const almondCookies =
          'Easy Holiday Sugar Cookies · ¼ teaspoon almond extract';
      const pecanApples =
          'Best Baked Apples · ⅓ cup coarsely chopped pecans, toasted';
      const pecanMuffins = 'Oatmeal Muffins · ⅓ cup pecans, chopped fine';
      const sugar = 'Perfect Roast Chicken · ½ cup sugar';
      const garam = 'Chana Masala · 1½ teaspoons garam masala';
      const ginger =
          'Chana Masala · 1 (1½-inch) piece ginger, peeled and chopped coarse';
      expect(order(), [
        almondCake,
        almondCookies,
        pecanApples,
        pecanMuffins,
        sugar,
        garam,
        ginger,
      ]);
      expect(order('finishes'), order());
      expect(order('worst'), [
        garam,
        almondCake,
        almondCookies,
        ginger,
        pecanApples,
        pecanMuffins,
        sugar,
      ]);
    });

    test('P8 (Run 048): the finishes order reads the `finishes` flag, never '
        "the last open line alone — Greek-Style Shrimp's last open line, "
        '"3 tablespoons ouzo", No match, finishes nothing and sorts after '
        'Oatmeal Muffins\' pecans (no grams on "Pecans" at 0.92: a Confirm '
        "can count them), whatever the rows' order", () {
      final db = tempDb();
      final shrimp = recipeOf(db, 'Greek-Style Shrimp', [
        '3 tablespoons ouzo',
      ]);
      seed(db, shrimp, 0, confidence: 0, status: 'unmatched');
      final muffins = recipeOf(db, 'Oatmeal Muffins', [
        '⅓ cup pecans, chopped fine',
      ]);
      seed(
        db,
        muffins,
        0,
        confidence: 0.92,
        fdcId: 2346395,
        description: 'Pecans',
      );
      final items =
          nutritionReviewHandler(db, page: 1, limit: 50)['items']!
              as List<Object?>;
      expect(
        [
          for (final item in items.cast<Map<String, Object?>>())
            (item['raw'], item['finishes']),
        ],
        [('⅓ cup pecans, chopped fine', 1), ('3 tablespoons ouzo', 0)],
      );
    });

    test('almond extract, the pecans and the held brine sugar each finish '
        "their recipe; Chana Masala's two open lines finish nothing, even "
        'under a filter that shows only one of them', () {
      final db = library();
      Map<String, int> finishesOf(String? bucket) {
        final items =
            nutritionReviewHandler(
                  db,
                  page: 1,
                  limit: 50,
                  bucket: bucket,
                )['items']!
                as List<Object?>;
        return {
          for (final item in items.cast<Map<String, Object?>>())
            '${(item['recipe']! as Map<String, Object?>)['title']} · '
                    '${item['raw']}':
                item['finishes']! as int,
        };
      }

      expect(finishesOf(null), {
        'Angel Food Cake · ½ teaspoon almond extract': 1,
        'Easy Holiday Sugar Cookies · ¼ teaspoon almond extract': 1,
        'Best Baked Apples · ⅓ cup coarsely chopped pecans, toasted': 1,
        'Oatmeal Muffins · ⅓ cup pecans, chopped fine': 1,
        'Chana Masala · 1 (1½-inch) piece ginger, peeled and chopped coarse': 0,
        'Chana Masala · 1½ teaspoons garam masala': 0,
        'Perfect Roast Chicken · ½ cup sugar': 1,
      });
      expect(finishesOf('no_grams'), {
        'Best Baked Apples · ⅓ cup coarsely chopped pecans, toasted': 1,
        'Oatmeal Muffins · ⅓ cup pecans, chopped fine': 1,
        'Chana Masala · 1 (1½-inch) piece ginger, peeled and chopped coarse': 0,
      });
      // Skip the garam masala: the ginger becomes Chana Masala's last open
      // line, and the skipped line itself finishes nothing.
      final chana = db.recipeByIdOrSlug('chana-masala')!.recipe;
      db.upsertIngredientMatch(
        db.ingredientMatchesFor(chana.id)[1].copyWith(status: 'skipped'),
      );
      expect(
        finishesOf('no_grams')['Chana Masala · 1 (1½-inch) piece ginger, '
            'peeled and chopped coarse'],
        1,
      );
      expect(finishesOf('skipped'), {
        'Chana Masala · 1½ teaspoons garam masala': 0,
      });
    });
  });

  group('U2: the apply receipt counts the recipes it completed', () {
    test('confirming almond extract with apply_to_all completes Easy Holiday '
        'Sugar Cookies (its last open line) but not Summer Peach Cake, whose '
        'peach schnapps is still open: completed 1 of 2', () async {
      final db = library();
      final peach = recipeOf(db, 'Summer Peach Cake', [
        '5 tablespoons peach schnapps',
        '¼ teaspoon plus ⅛ teaspoon almond extract',
      ]);
      seed(
        db,
        peach,
        0,
        confidence: 0.212,
        fdcId: 325430,
        grams: 48.125,
        gramSource: 'portion',
        description: 'Peaches, yellow, raw',
      );
      seed(
        db,
        peach,
        1,
        confidence: 0.475,
        fdcId: vanilla,
        grams: 1.575,
        gramSource: 'portion',
        description: 'Vanilla extract',
      );
      final byTitle = <String, Recipe>{};
      for (final title in [
        'Angel Food Cake',
        'Easy Holiday Sugar Cookies',
        'Summer Peach Cake',
      ]) {
        final recipe = db
            .recipeByIdOrSlug(
              title.toLowerCase().replaceAll(RegExp('[^a-z]+'), '-'),
            )!
            .recipe;
        byTitle[title] = recipe;
        await recomputeTotals(db, provider, recipe);
        expect(db.nutritionFor(recipe.id)!.status, 'partial', reason: title);
      }
      // Over the route itself: the wire receipt names the completed recipe
      // (the app's shortfall naming reconciles by these ids).
      final body = await putOverRoute(
        db,
        'angel-food-cake',
        1,
        {'confirmed': true, 'apply_to_all': true},
      );
      expect(body['applied'], {
        'recipes': 2,
        'lines': 2,
        'failed': 0,
        'completed': 1,
        'completed_recipes': [byTitle['Easy Holiday Sugar Cookies']!.id],
        'moved': 0,
        'decided': 0,
        'gone': 0,
        'failed_lines': 0,
      });
      expect(
        db.nutritionFor(byTitle['Easy Holiday Sugar Cookies']!.id)!.status,
        'complete',
      );
      expect(
        db.nutritionFor(byTitle['Summer Peach Cake']!.id)!.status,
        'partial',
      );
    });
  });

  test(
    'a reached recipe that was complete already is not counted: a pick '
    'of Bacon bits on the bacon of Hearty Lentil Soup reaches the counted '
    'bacon line of Boston Baked Beans (another food), which stays complete',
    () async {
      final db = tempDb();
      final byTitle = <String, Recipe>{};
      for (final (title, raw, grams) in [
        (
          'Hearty Lentil Soup',
          '3 ounces (3 slices) bacon, cut into ¼-inch pieces',
          85.0485,
        ),
        (
          'Boston Baked Beans',
          '2 ounces (about 2 slices) bacon, cut into ¼-inch pieces',
          56.699,
        ),
      ]) {
        final recipe = recipeOf(db, title, [raw]);
        seed(
          db,
          recipe,
          0,
          confidence: 1,
          fdcId: 168277,
          grams: grams,
          gramSource: 'weight',
          description: 'Pork, cured, bacon, unprepared',
        );
        await recomputeTotals(db, provider, recipe);
        expect(db.nutritionFor(recipe.id)!.status, 'complete', reason: title);
        byTitle[title] = recipe;
      }
      final applied = await applyMatchOverride(
        db,
        provider,
        byTitle['Hearty Lentil Soup']!,
        0,
        {'fdc_id': 2707466, 'apply_to_all': true},
      );
      expect(
        applied,
        appliedIs(
          recipes: 1,
          lines: 1,
          failed: 0,
          completed: 0,
          completedRecipes: const [],
        ),
      );
      final beans = byTitle['Boston Baked Beans']!;
      expect(db.ingredientMatchesFor(beans.id).single.fdcId, 2707466);
      expect(db.nutritionFor(beans.id)!.status, 'complete');
    },
  );

  group('U3: portions (portionFill, the matches body)', () {
    test('kcalPer100g falls back to 4/9/4 on a record that publishes no '
        'energy: "Oil, olive, extra virgin" (748608, fat only) and "Beans, '
        'Dry, Red (0% moisture)" (747431, protein and fat)', () async {
      expect(kcalPer100g((await provider.food(748608))!), closeTo(843.3, 1e-9));
      expect(
        kcalPer100g((await provider.food(747431))!),
        closeTo(4 * 21.3 + 9 * 1.16, 1e-9),
      );
      // Stated exception (synthesized): no real record lacking energy
      // publishes carbohydrate — none of snapshot 11's 35 energy-less
      // cached records, none of the recorded answers — so the carbohydrate
      // factor is pinned on a made-up record carrying only 205.
      expect(
        kcalPer100g(
          const FdcFood(
            fdcId: 0,
            description: 'synthesized: carbohydrate only',
            dataType: 'Foundation',
            nutrientsPer100g: {'205': 10},
            portions: [],
          ),
        ),
        40,
      );
    });

    test(
      '"4 sticks unsalted butter" (Classic Yellow Layer Cake, 0884) fills '
      'only the stick portion of "Butter, without salt": 4 × 113 g',
      () async {
        final butter = (await provider.food(173430))!;
        final line = lineOf(
          '4 sticks unsalted butter, cut into chunks and softened',
        );
        expect(lineAmountText(line.amounts), '4 stick');
        expect(
          {
            for (final p in butter.portions)
              p.description: portionFill(p, line.amounts),
          },
          {
            'pat (1" sq, 1/3" high)': null,
            'tbsp': null,
            'stick': 452.0,
            'cup': null,
          },
        );
        // A tablespoon line names "tbsp" (Carrot-Ginger Soup's butter).
        final tbsp = lineOf('2 tablespoons unsalted butter');
        expect(
          [for (final p in butter.portions) portionFill(p, tbsp.amounts)],
          [null, closeTo(28.4, 1e-9), null, null],
        );
      },
    );

    test('"1 (1½-inch) piece ginger" (Chana Masala) names no portion of '
        '"Ginger root, raw": nothing fills, all are reference', () async {
      final ginger = (await provider.food(169231))!;
      final line = lineOf(
        '1 (1½-inch) piece ginger, peeled and chopped coarse',
      );
      expect(lineAmountText(line.amounts), '1 piece');
      expect([
        for (final p in ginger.portions) portionFill(p, line.amounts),
      ], everyElement(isNull));
      // "½ cup chopped fresh ginger" (Thai Chicken Curry with Potatoes and
      // Peanuts) names the quarter-cup portion: ½ ÷ ¼ × 24 g.
      final cup = lineOf('½ cup chopped fresh ginger');
      expect(
        [
          for (final p in ginger.portions) portionFill(p, cup.amounts),
        ],
        [null, 48.0, null],
      );
    });

    test('a portion\'s leading count divides its weight: "2 (750-ml) bottles '
        'rosé wine" (Rosé Sangria, 1136) on "Wine, rose" (2710690), whose '
        'cached portion is "1/2 bottle" 375 g, fills 2 ÷ ½ × 375', () {
      // Snapshot 11's fdc_food_cache portion for 2710690, verbatim (one of
      // the 23 whose leading count differs from `amount`, here null).
      const halfBottle = FdcPortion(
        gramWeight: 375,
        description: '1/2 bottle',
      );
      final wine = lineOf('2 (750-ml) bottles rosé wine');
      expect(portionFill(halfBottle, wine.amounts), 1500.0);
    });

    test('a zero quantity or a blank unit fills nothing; an empty amount '
        'says none', () async {
      // Stated exceptions (synthesized): the parser never writes a quantity
      // of 0, a unit of spaces, or an empty quantity with no unit, but a
      // hand-edited YAML document can.
      final stick = (await provider.food(173430))!.portions.firstWhere(
        (p) => p.description == 'stick',
      );
      const zero = Amount(measure: Measure.count, quantity: '0', unit: 'stick');
      expect(portionFill(stick, const [zero]), isNull);
      const blank = Amount(measure: Measure.count, quantity: '4', unit: '  ');
      expect(unitAmountOf(const [blank]), isNull);
      expect(lineAmountText(const [blank]), '4');
      // Nor an empty quantity with no unit: no amount to say, not "".
      const empty = Amount(measure: Measure.count, quantity: '');
      expect(lineAmountText(const [empty]), isNull);
    });

    test(
      'the matches body reads portions from fdc_food_cache alone: empty '
      'and no fetch while the detail is uncached, listed once it is',
      () async {
        final db = tempDb();
        final cake = recipeOf(
          db,
          'Classic Yellow Layer Cake with Vanilla Buttercream',
          ['4 sticks unsalted butter, cut into chunks and softened'],
        );
        seed(
          db,
          cake,
          0,
          confidence: 1,
          fdcId: 173430,
          description: 'Butter, without salt',
        );
        final counting = FixtureProvider();
        final before = await matchesBody(db, counting, cake);
        final line =
            (before['items']! as List<Object?>).single! as Map<String, Object?>;
        expect(line['portions'], isEmpty);
        expect(line['kcal_per_100g'], isNull);
        expect(line['line_amount'], '4 stick');
        expect(counting.foodCalls, 0);
        db.fdcFoodCachePut(
          173430,
          jsonEncode((await provider.food(173430))!.toJson()),
        );
        final after = await matchesBody(db, counting, cake);
        final portions =
            ((after['items']! as List<Object?>).single!
                    as Map<String, Object?>)['portions']!
                as List<Object?>;
        expect(portions, hasLength(4));
        expect(
          ((after['items']! as List<Object?>).single!
              as Map<String, Object?>)['kcal_per_100g'],
          717.0,
        );
        expect(portions[2], {
          'amount': 1.0,
          'unit': null,
          'description': 'stick',
          'grams': 113.0,
          'fill': 452.0,
        });
        expect(counting.foodCalls, 0);
      },
    );
  });

  group('Run 046: line_amount reads a bare count, kcal_per_100g the '
      'nutrient sibling', () {
    test('"8 large sea scallops, tendons removed" (Grilled Scallops with '
        'Fennel and Orange Salad for Two, 0651) gives "8", which fills no '
        'portion; a line with no amount gives null', () async {
      final scallops = lineOf('8 large sea scallops, tendons removed');
      expect(lineAmountText(scallops.amounts), '8');
      final butter = (await provider.food(173430))!;
      expect([
        for (final p in butter.portions) portionFill(p, scallops.amounts),
      ], everyElement(isNull));
      // A unit amount still wins over a count ("4 sticks": Classic Yellow
      // Layer Cake's line, 0884).
      expect(
        lineAmountText(
          lineOf(
            '4 sticks unsalted butter, cut into chunks and softened',
          ).amounts,
        ),
        '4 stick',
      );
      // Ultimate Cream of Tomato Soup's seasoning line gives none.
      expect(
        lineAmountText(lineOf('Table salt and cayenne pepper').amounts),
        isNull,
      );
    });

    test('"Dash of hot sauce" (Easier Fried Chicken, 0149, snapshot 12: '
        'auto on 2710093 with no grams) gives the unit alone, "dash", which '
        'fills none of the cached portions', () async {
      final db = tempDb();
      final chicken = recipeOf(db, 'Easier Fried Chicken', [
        'Dash of hot sauce',
      ]);
      seed(
        db,
        chicken,
        0,
        confidence: 0.92333333333333334,
        fdcId: 2710093,
        description: 'Hot pepper sauce',
      );
      db.fdcFoodCachePut(
        2710093,
        jsonEncode((await provider.food(2710093))!.toJson()),
      );
      final line =
          ((await matchesBody(db, provider, chicken))['items']!
                      as List<Object?>)
                  .single!
              as Map<String, Object?>;
      expect(line['line_amount'], 'dash');
      final portions = line['portions']! as List<Object?>;
      expect(portions, hasLength(5));
      expect([
        for (final p in portions) (p! as Map<String, Object?>)['fill'],
      ], everyElement(isNull));
    });

    test(
      'a No grams napa line (Yakisoba, 0520, snapshot 12) reads 16 kcal '
      'per 100 g from SR 169979, as the totals count it — not the '
      "Foundation record's own 4.26; null while the sibling is uncached",
      () async {
        final db = tempDb();
        final yakisoba = recipeOf(
          db,
          'Yakisoba (Japanese Stir-Fried Noodles with Beef)',
          ['6 cups napa cabbage, sliced crosswise into ½-inch strips'],
        );
        seed(
          db,
          yakisoba,
          0,
          confidence: 0.95,
          fdcId: 2727583,
          description: 'Cabbage, napa, leaf, destemmed, raw',
        );
        db.fdcFoodCachePut(
          2727583,
          jsonEncode((await provider.food(2727583))!.toJson()),
        );
        Future<num?> kcal() async =>
            (((await matchesBody(db, provider, yakisoba))['items']!
                            as List<Object?>)
                        .single!
                    as Map<String, Object?>)['kcal_per_100g']
                as num?;
        expect(await kcal(), isNull, reason: 'the sibling is uncached');
        // The recorded answer that holds 169979 (its search hit, 208 = 16).
        db.fdcSearchCachePut(
          'chinese wheat noodles',
          jsonEncode(await provider.search('chinese wheat noodles')),
        );
        expect(await kcal(), 16.0);
      },
    );
  });

  group('U5: the approximation basis (isApproximation, gramBasisFor)', () {
    IngredientMatchRow rowOf(String raw, int fdcId, String description) =>
        IngredientMatchRow(
          recipeId: 'r',
          position: 0,
          raw: raw,
          fdcId: fdcId,
          description: description,
          dataType: 'SR Legacy',
          confidence: 1,
          grams: 56.699,
          gramSource: 'weight',
          status: 'auto',
        );

    bool flagged(String raw, int fdcId, String description) {
      final line = lineOf(raw);
      return isApproximation(
        item: normalizeItem(lineItemOf(line)),
        raw: raw,
        fdcId: fdcId,
        description: description,
      );
    }

    test('each flagged approximation on its record, as snapshot 11 holds '
        'them', () {
      for (final (raw, id, description) in [
        // Pasta e Ceci; Streamlined French Onion Soup; Multicooker Hawaiian
        // Oxtail Soup (chen pi); the rest as listed in docs/API.md.
        (
          '2 ounces pancetta, cut into ½-inch pieces',
          168277,
          'Pork, cured, bacon, unprepared',
        ),
        (
          '1½ ounces Asiago cheese, grated (about ¾ cup)',
          325036,
          'Cheese, parmesan, grated',
        ),
        ('5 allspice berries', 171315, 'Spices, allspice, ground'),
        (
          '1 tablespoon whole allspice berries',
          171315,
          'Spices, allspice, ground',
        ),
        ('2 teaspoons grated lime zest', 167749, 'Lemon peel, raw'),
        ('¼ ounce chen pi', 169103, 'Orange peel, raw'),
        (
          '¼ cup stemmed, patted dry, and minced pepperoncini',
          2710095,
          'Peppers, hot, pickled',
        ),
        ('1 tablespoon minced fresh oregano', 171328, 'Spices, oregano, dried'),
        ('1 teaspoon minced fresh sage', 170935, 'Spices, sage, ground'),
        (
          '1 tablespoon minced fresh tarragon',
          170937,
          'Spices, tarragon, dried',
        ),
        (
          '2 tablespoons minced fresh marjoram',
          170928,
          'Spices, marjoram, dried',
        ),
        (
          '1 tablespoon minced fresh chervil leaves',
          171318,
          'Spices, chervil, dried',
        ),
      ]) {
        expect(flagged(raw, id, description), isTrue, reason: raw);
      }
    });

    test("never the food itself, a line that offers it, or a person's other "
        'record', () {
      for (final (raw, id, description) in [
        (
          '1 ounce Parmesan cheese, grated (½ cup)',
          325036,
          'Cheese, parmesan, grated',
        ),
        (
          '3 ounces pancetta or bacon (about 3 slices), chopped fine',
          168277,
          'Pork, cured, bacon, unprepared',
        ),
        ('1 teaspoon dried oregano', 171328, 'Spices, oregano, dried'),
        ('¼ teaspoon ground allspice', 171315, 'Spices, allspice, ground'),
        ('1 teaspoon grated lemon zest', 167749, 'Lemon peel, raw'),
        // A person's pick of another record for the pancetta line.
        (
          '2 ounces pancetta, cut into ½-inch pieces',
          168367,
          'Pork, cured, ham, rump, bone-in, separable lean and fat, '
              'unheated',
        ),
      ]) {
        expect(flagged(raw, id, description), isFalse, reason: raw);
      }
    });

    test('the basis says it after the amount; a line with no grams says '
        'nothing', () {
      final db = tempDb();
      const raw = '2 ounces pancetta, cut into ½-inch pieces';
      final row = rowOf(raw, 168277, 'Pork, cured, bacon, unprepared');
      expect(
        gramBasisFor(db, lineOf(raw), row),
        'from 2 ounce · approximation (counted as Pork, cured, bacon, '
        'unprepared)',
      );
      expect(
        gramBasisFor(db, lineOf(raw), row.copyWith(clearGrams: true)),
        isNull,
      );
    });

    test("a person's confirm or pick of the record keeps the suffix (the "
        'record relation is the approximation); a skipped row, which counts '
        'nothing, drops it (Run 046)', () {
      final db = tempDb();
      const raw = '2 ounces pancetta, cut into ½-inch pieces';
      final row = rowOf(raw, 168277, 'Pork, cured, bacon, unprepared');
      const flaggedBasis =
          'from 2 ounce · approximation (counted as Pork, cured, bacon, '
          'unprepared)';
      for (final status in ['overridden', 'confirmed']) {
        expect(
          gramBasisFor(db, lineOf(raw), row.copyWith(status: status)),
          flaggedBasis,
          reason: status,
        );
      }
      expect(
        gramBasisFor(db, lineOf(raw), row.copyWith(status: 'skipped')),
        'from 2 ounce',
      );
    });
  });

  group('U6: per batch at a basis of 1, never a single-portion yield '
      '(basisKindOf)', () {
    test('the corpus MAKES-1 yields of snapshot 11', () {
      for (final (servings, kind) in [
        ('MAKES 1 LOAF', 'per_batch'),
        ('MAKES 1 LARGE ROUND LOAF', 'per_batch'),
        ('MAKES ONE 9-INCH LOAF', 'per_batch'),
        ('MAKES ENOUGH FOR ONE 9-INCH PIE', 'per_batch'),
        ('MAKES ONE 9-INCH SINGLE CRUST', 'per_batch'),
        ('MAKES ABOUT 1 QUART', 'per_batch'),
        (
          'MAKES ABOUT ¼ CUP, ENOUGH TO DRESS 8 TO 10 CUPS LIGHTLY PACKED '
              'GREENS',
          'per_batch',
        ),
        (null, 'per_batch'), // Latin Flan: no yield at all
        // An admin's 1 on a larger serves count or yield: the batch.
        ('SERVES 8 (MAKES ABOUT 1 QUART)', 'per_batch'),
        ('MAKES ONE 8-INCH LOAF, SERVING 8', 'per_batch'),
        ('MAKES ABOUT 2 CUPS, ENOUGH FOR 4 SANDWICHES', 'per_batch'),
        ('MAKES 1 OMELET', 'per_serving'),
        ('MAKES 1 COCKTAIL', 'per_serving'),
        // A range starting at one is a batch: Sous Vide Soft-Poached Eggs
        // counts '1–16 large eggs' at the midpoint, 425 g (Run 046).
        ('MAKES 1 TO 16 EGGS', 'per_batch'),
        // A yield of MORE than one portion is a batch: an admin's basis of
        // 1 then divides by nothing (refix round 2) — the snapshot-11
        // yields that name a listed noun with another count or head.
        ('MAKES 12 SANDWICHES', 'per_batch'),
        ('MAKES 12 EGGS', 'per_batch'),
        ('MAKES 12 COCKTAILS', 'per_batch'),
        ('MAKES 32 SANDWICH COOKIES', 'per_batch'),
      ]) {
        expect(basisKindOf(1, servings: servings), kind, reason: servings);
      }
      // The ruling's list, and only it: "MAKES 4 BURGERS" (two corpus
      // recipes) at an admin's basis of 1 reads per batch.
      expect(singlePortionYields, {
        'omelet',
        'cocktail',
        'sandwich',
        'egg',
        'drink',
      });
      expect(basisKindOf(1, servings: 'MAKES 4 BURGERS'), 'per_batch');
      // A larger basis divides the batch, whatever the yield.
      expect(basisKindOf(2, servings: 'MAKES 2 LOAVES'), 'per_serving');
    });

    test('the head noun decides, in the first clause only, a trailing '
        'parenthetical dropped; "ONE" counts as 1', () {
      // Stated exceptions (synthesized): no corpus yield has a count of 1
      // with a listed noun as a modifier, a second clause that names a
      // listed noun (before or after the single portion), a parenthetical
      // after a single portion, or ONE spelled out before a listed noun, so
      // these parts of the rule are pinned on made-up yields another
      // library could carry.
      // The head is the loaf; "sandwich" only modifies it.
      expect(basisKindOf(1, servings: 'MAKES 1 SANDWICH LOAF'), 'per_batch');
      // The first clause is one cocktail; what follows is not the yield.
      expect(
        basisKindOf(1, servings: 'MAKES 1 COCKTAIL; EASILY DOUBLED'),
        'per_serving',
      );
      // The first clause is a cup (a batch); the sandwich after the comma
      // is what it dresses — never the head noun.
      expect(
        basisKindOf(1, servings: 'MAKES 1 CUP, ENOUGH FOR 1 SANDWICH'),
        'per_batch',
      );
      expect(
        basisKindOf(1, servings: 'MAKES 1 COCKTAIL (ABOUT 4 OUNCES)'),
        'per_serving',
      );
      expect(basisKindOf(1, servings: 'MAKES ONE OMELET'), 'per_serving');
      // The yield count must be one: a singular listed noun after a larger
      // count (a hand edit dropping the plural) is still a batch at an
      // admin's basis of 1.
      expect(basisKindOf(1, servings: 'MAKES 2 OMELET'), 'per_batch');
    });

    test('a recipe that SERVES one is a serving, never a batch', () {
      // Stated exception (synthesized): no corpus recipe serves 1 (the ATK
      // corpus has no serves_min of 1); an edited or imported recipe can.
      for (final servings in ['SERVES 1', 'SERVES 1 TO 2', '1']) {
        expect(
          basisKindOf(1, servings: servings),
          'per_serving',
          reason: servings,
        );
      }
      // An admin's 1 on a recipe that serves more is still the batch.
      expect(basisKindOf(1, servings: 'SERVES 4'), 'per_batch');
    });

    test("the nutrition body reads the recipe's own yield", () async {
      final db = tempDb();
      for (final (servings, kind) in [
        ('MAKES 1 OMELET', 'per_serving'),
        ('MAKES 1 LOAF', 'per_batch'),
      ]) {
        final recipe = recipeOf(db, servings, [
          '¼ teaspoon ground allspice',
        ], servings: servings);
        await recomputeTotals(db, provider, recipe);
        final body = nutritionBody(db, recipe, forAdmin: false);
        expect(body['serving_basis'], 1, reason: servings);
        expect(body['basis_kind'], kind, reason: servings);
      }
    });
  });

  group('U6 on the corpus recipes', skip: skipIfNoCorpus, () {
    test('Challah, the loaves and the sous-vide eggs (1 to 16) per batch; '
        'the omelet and the cocktail per serving', () async {
      final db = tempDb();
      for (final (file, kind) in [
        ('1110-challah.yaml', 'per_batch'),
        ('0973-all-butter-double-crust-pie-dough.yaml', 'per_batch'),
        ('0038-foolproof-vinaigrette.yaml', 'per_batch'),
        ('0929-latin-flan.yaml', 'per_batch'),
        ('1148-omelet-with-cheddar-and-chives.yaml', 'per_serving'),
        ('1155-champagne-cocktail.yaml', 'per_serving'),
        ('0728-sous-vide-soft-poached-eggs.yaml', 'per_batch'),
        ('0803-ciabatta.yaml', 'per_serving'),
      ]) {
        final recipe = loadCorpusRecipe(file);
        db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: file);
        await recomputeTotals(db, provider, recipe);
        expect(
          nutritionBody(db, recipe, forAdmin: false)['basis_kind'],
          kind,
          reason: file,
        );
      }
    });
  });

  // A sweep snapshot (key-stripped, read through a temp copy) when
  // SALT_REVIEW_SNAPSHOT names one: the SQL's `finishes` against the rule
  // recomputed in Dart for every group, and the payoff of the default order.
  final snapshot = Platform.environment['SALT_REVIEW_SNAPSHOT'];
  group(
    'U2 on a sweep snapshot',
    skip: snapshot == null || !File(snapshot).existsSync()
        ? 'set SALT_REVIEW_SNAPSHOT to a sweep snapshot to run'
        : null,
    () {
      test('finishes equals the rule over every group, and the default '
          'order finishes more recipes in its first 10 and 25 groups', () {
        final dir = Directory.systemTemp.createTempSync('salt-c1-snap');
        addTearDown(() => dir.deleteSync(recursive: true));
        File(snapshot!).copySync('${dir.path}/salt.db');
        final db = SaltDatabase.open('${dir.path}/salt.db');
        addTearDown(db.dispose);
        // Every open line, keyed as the queue keys it.
        final open =
            <
              ({
                String recipe,
                String title,
                String key,
                MatchBucket bucket,
                IngredientMatchRow row,
              })
            >[];
        for (final id in db.allRecipeIds()) {
          final recipe = db.recipeByIdOrSlug(id)!.recipe;
          for (final row in db.ingredientMatchesFor(recipe.id)) {
            final bucket = matchBucketFor(
              status: row.status,
              fdcId: row.fdcId,
              grams: row.grams,
              confidence: row.confidence,
              hold: row.hold,
              gramSource: row.gramSource,
            );
            if (bucket == MatchBucket.counted ||
                bucket == MatchBucket.skipped) {
              continue;
            }
            final perLine =
                (row.itemKey ?? '').isEmpty ||
                !{'auto', 'unmatched'}.contains(row.status) ||
                {
                  'second_food',
                  'discarded_medium',
                  'in_shell',
                }.contains(row.hold);
            open.add((
              recipe: recipe.id,
              title: recipe.title,
              key: perLine ? '${recipe.id}#${row.position}' : row.itemKey!,
              bucket: bucket,
              row: row,
            ));
          }
        }
        // Each group's example: lowest confidence, then grams, title, pos.
        final example = <String, ({String recipe, int position})>{};
        final sorted = [...open]
          ..sort((a, b) {
            final byConf = a.row.confidence.compareTo(b.row.confidence);
            if (byConf != 0) return byConf;
            final byGrams = (a.row.grams == null ? 1 : 0).compareTo(
              b.row.grams == null ? 1 : 0,
            );
            if (byGrams != 0) return byGrams;
            final byTitle = a.title.compareTo(b.title);
            return byTitle != 0
                ? byTitle
                : a.row.position.compareTo(b.row.position);
          });
        for (final line in sorted) {
          example.putIfAbsent(
            line.key,
            () => (recipe: line.recipe, position: line.row.position),
          );
        }
        final byRecipe = <String, List<({String key, bool ok})>>{};
        for (final line in open) {
          final ex = example[line.key]!;
          // A confirm can supply grams only on a No grams example (the
          // amount-first block): a Check or No match example with no grams
          // stays short (Run 046).
          byRecipe.putIfAbsent(line.recipe, () => []).add((
            key: line.key,
            ok:
                line.row.grams != null ||
                (line.bucket == MatchBucket.noAmount &&
                    ex.recipe == line.recipe &&
                    ex.position == line.row.position),
          ));
        }
        // The Lines grain: a line finishes when it is its recipe's only open
        // line AND it has grams or sits in No grams.
        final lineFinishes = {
          for (final line in open)
            '${line.recipe}#${line.row.position}':
                byRecipe[line.recipe]!.length == 1 &&
                    (line.row.grams != null ||
                        line.bucket == MatchBucket.noAmount)
                ? 1
                : 0,
        };
        final lines = db.nutritionReviewLines(limit: 100000, offset: 0);
        expect(lines, hasLength(open.length));
        for (final l in lines) {
          final id = '${l.match.recipeId}#${l.match.position}';
          expect(l.finishes, lineFinishes[id], reason: id);
        }
        final linePromises = lineFinishes.values.where((f) => f == 1).length;
        final expected = <String, int>{};
        for (final lines in byRecipe.values) {
          final keys = {for (final l in lines) l.key};
          if (keys.length == 1 && lines.every((l) => l.ok)) {
            expected.update(keys.single, (n) => n + 1, ifAbsent: () => 1);
          }
        }
        String keyOf(NutritionReviewGroupRow g) => example.entries
            .firstWhere(
              (e) =>
                  e.value.recipe == g.match.recipeId &&
                  e.value.position == g.match.position,
            )
            .key;
        final groups = db.nutritionReviewGroups(limit: 100000, offset: 0);
        expect(groups, hasLength(example.length));
        expect(db.nutritionReviewFinishable(), (
          finishable: expected.values.fold(0, (a, b) => a + b),
          open: byRecipe.length,
        ));
        for (final g in groups) {
          expect(g.finishes, expected[keyOf(g)] ?? 0, reason: keyOf(g));
        }
        // Both orders, recomputed: finishes, then lines, then the worst
        // match; worst, then lines. Each then recipes and the key.
        final keys = {for (final g in groups) g: keyOf(g)};
        int tail(NutritionReviewGroupRow a, NutritionReviewGroupRow b) {
          final byRecipes = b.recipes.compareTo(a.recipes);
          return byRecipes != 0 ? byRecipes : keys[a]!.compareTo(keys[b]!);
        }

        int byFinishes(NutritionReviewGroupRow a, NutritionReviewGroupRow b) {
          for (final c in [
            b.finishes.compareTo(a.finishes),
            b.lines.compareTo(a.lines),
            a.match.confidence.compareTo(b.match.confidence),
          ]) {
            if (c != 0) {
              return c;
            }
          }
          return tail(a, b);
        }

        int byWorst(NutritionReviewGroupRow a, NutritionReviewGroupRow b) {
          for (final c in [
            a.match.confidence.compareTo(b.match.confidence),
            b.lines.compareTo(a.lines),
          ]) {
            if (c != 0) {
              return c;
            }
          }
          return tail(a, b);
        }

        expect(
          [for (final g in groups) keys[g]],
          [
            for (final g in [...groups]..sort(byFinishes)) keys[g],
          ],
        );
        int payoff(List<NutritionReviewGroupRow> ordered, int n) {
          final top = {for (final g in ordered.take(n)) keyOf(g)};
          return byRecipe.values
              .where(
                (lines) => lines.every((l) => l.ok && top.contains(l.key)),
              )
              .length;
        }

        final worst = db.nutritionReviewGroups(
          limit: 100000,
          offset: 0,
          sort: 'worst',
        );
        final worstKeys = {for (final g in worst) g: keyOf(g)};
        keys.addAll(worstKeys);
        expect(
          [for (final g in worst) keys[g]],
          [
            for (final g in [...worst]..sort(byWorst)) keys[g],
          ],
        );
        final table = {
          for (final n in [10, 25])
            n: (finishes: payoff(groups, n), worst: payoff(worst, n)),
        };
        printOnFailure('payoff: $table');
        // The measured table, for the review record.
        // ignore: avoid_print
        print(
          'C1 payoff on $snapshot: $table; finishable '
          '${db.nutritionReviewFinishable()}; line promises $linePromises',
        );
        for (final row in table.values) {
          expect(row.finishes, greaterThan(row.worst));
        }
      });
    },
  );
}
