import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/admin_handlers.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// The review queue GROUPED by ingredient (`?group=item`): one row per
/// ingredient key, carrying the group's example line flattened exactly like a
/// line item plus its reach, decided flag and amount spread.
///
/// Real data throughout: five corpus recipes, their real ingredient lines and
/// real keys (looked up, never spelled out), and real recorded FDC foods from
/// `test/fixtures/fdc/foods.json`. What IS crafted is each row's confidence,
/// grams and status — the triage state the queue sorts on. No sweep can be
/// asked for a five-recipe library that lands one group in two buckets, one
/// three-way confidence tie broken by grams, and two unkeyed rows at once.
void main() {
  group('nutrition-review groups', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;
    late Recipe soup;
    late Recipe bundt;
    late Recipe acquacotta;
    late Recipe tarte;
    late Recipe caramel;

    // Real recorded FDC foods (fdc_id, description, data_type).
    const salt = (id: 173468, desc: 'Salt, table', type: 'SR Legacy');
    const butter = (
      id: 173430,
      desc: 'Butter, without salt',
      type: 'SR Legacy',
    );
    const oil = (
      id: 2710180,
      desc: 'Vegetable oil, NFS',
      type: 'Survey (FNDDS)',
    );
    const broth = (
      id: 171609,
      desc: 'Soup, chicken broth, low sodium, canned',
      type: 'SR Legacy',
    );
    const powdered = (id: 169656, desc: 'Sugars, powdered', type: 'SR Legacy');
    const phyllo = (id: 172791, desc: 'Phyllo dough', type: 'SR Legacy');

    /// Every position in [recipe] whose ingredient key is [key].
    List<int> positionsOf(Recipe recipe, String key) => [
      for (final (index, line) in nutritionLines(recipe).indexed)
        if (itemKeyFor(line.item ?? line.raw) == key) index,
    ];

    int positionOf(Recipe recipe, String key) {
      final positions = positionsOf(recipe, key);
      expect(positions, isNotEmpty, reason: '$key must be a real line');
      return positions.first;
    }

    /// Writes one match row for a REAL line, in a crafted triage state.
    void seed(
      Recipe recipe,
      int position, {
      required double confidence,
      ({int id, String desc, String type})? food,
      double? grams,
      String status = 'auto',
      bool unkeyed = false,
      String? unkeyedAs,
    }) {
      final line = nutritionLines(recipe)[position];
      db.upsertIngredientMatch(
        IngredientMatchRow(
          recipeId: recipe.id,
          position: position,
          raw: line.raw,
          itemKey: unkeyed ? unkeyedAs : itemKeyFor(line.item ?? line.raw),
          fdcId: food?.id,
          description: food?.desc,
          dataType: food?.type,
          confidence: confidence,
          grams: grams,
          gramSource: grams == null ? null : 'weight',
          status: status,
        ),
      );
    }

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('salt-review-groups');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath);
      provider = FixtureProvider();
      final sourceRoot = Directory('${tempDir.path}/source')
        ..createSync(recursive: true);
      Directory('${sourceRoot.path}/recipes').createSync();
      for (final name in [
        '0002-classic-chicken-noodle-soup.yaml',
        '0857-rich-chocolate-bundt-cake.yaml',
        '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml',
        '1005-30-minute-tarte-tatin.yaml',
        '0879-easy-caramel-cake.yaml',
      ]) {
        File(
          '$corpusRecipesDir/$name',
        ).copySync('${sourceRoot.path}/recipes/$name');
      }
      importSourceRoot(sourceRootPath: sourceRoot.path, db: db, config: config);
      soup = db.recipeByIdOrSlug('classic-chicken-noodle-soup')!.recipe;
      bundt = db.recipeByIdOrSlug('rich-chocolate-bundt-cake')!.recipe;
      acquacotta = db
          .recipeByIdOrSlug('acquacotta-tuscan-white-bean-and-escarole-soup')!
          .recipe;
      tarte = db.recipeByIdOrSlug('30-minute-tarte-tatin')!.recipe;
      caramel = db.recipeByIdOrSlug('easy-caramel-cake')!.recipe;

      // --- the seeded library: 12 flagged lines making 7 groups ------------
      // No match: Grand Marnier, which FDC has no record of.
      seed(
        tarte,
        positionOf(tarte, 'grand marnier'),
        confidence: 0,
        status: 'unmatched',
      );
      // `table salt`: four lines over three recipes, and the one group whose
      // lines sit in TWO buckets (three `check`, one `no_grams`).
      seed(
        soup,
        positionOf(soup, 'table salt'),
        confidence: 0.05,
        food: salt,
        grams: 12,
      );
      seed(
        bundt,
        positionOf(bundt, 'table salt'),
        confidence: 0.05,
        food: salt,
        grams: 6,
      );
      final caramelSalts = positionsOf(caramel, 'table salt');
      expect(caramelSalts, hasLength(2), reason: 'the cake salts twice');
      seed(caramel, caramelSalts[0], confidence: 0.05, food: salt, grams: 4);
      seed(caramel, caramelSalts[1], confidence: 0.9, food: salt);
      // `without salt butter`: the example is decided by GRAMS, against the
      // title order (the tarte sorts first and has none).
      seed(
        bundt,
        positionOf(bundt, 'without salt butter'),
        confidence: 0.2,
        food: butter,
        grams: 170,
      );
      seed(
        tarte,
        positionOf(tarte, 'without salt butter'),
        confidence: 0.2,
        food: butter,
      );
      // Two olive-oil lines in ONE recipe: same confidence, same grams, so
      // only the position separates them.
      for (final position in positionsOf(
        acquacotta,
        'extra-virgin olive oil',
      )) {
        seed(acquacotta, position, confidence: 0.2, food: oil, grams: 27);
      }
      // A single-line group at the same confidence, for the reach tie-breaks.
      seed(
        acquacotta,
        positionOf(acquacotta, 'chicken broth'),
        confidence: 0.2,
        food: broth,
        grams: 1920,
      );
      // Two rows the key backfill has not reached (NULL and '') — never one
      // group of two.
      seed(
        bundt,
        positionOf(bundt, 'powdered sugar'),
        confidence: 0.95,
        food: powdered,
        unkeyed: true,
      );
      seed(
        tarte,
        positionOf(tarte, 'frozen puff pastry'),
        confidence: 0.95,
        food: phyllo,
        unkeyed: true,
        unkeyedAs: '',
      );
      // One ingredient already decided by a person.
      db.putDecision(
        itemKey: 'without salt butter',
        item: 'unsalted butter',
        fdcId: butter.id,
        description: butter.desc,
        dataType: butter.type,
        decidedBy: null,
      );
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    Map<String, Object?> report({
      String? bucket,
      bool grouped = true,
      int page = 1,
      int limit = 50,
    }) => nutritionReviewHandler(
      db,
      page: page,
      limit: limit,
      bucket: bucket,
      group: grouped ? 'item' : null,
    );

    List<Map<String, Object?>> itemsOf(Map<String, Object?> body) => [
      for (final item in body['items']! as List)
        (item as Map).cast<String, Object?>(),
    ];

    Map<String, Object?> groupFor(String itemKey, {String? bucket}) =>
        itemsOf(report(bucket: bucket)).firstWhere(
          (item) => item['item_key'] == itemKey,
          orElse: () => fail('no group for $itemKey'),
        );

    test('a group is the example line flattened, plus reach, decision and '
        'amount spread', () {
      final group = groupFor('table salt');
      final position = positionOf(soup, 'table salt');
      expect(group['recipe'], {
        'id': soup.id,
        'slug': soup.slug,
        'title': soup.title,
      });
      expect(group['position'], position);
      expect(group['raw'], nutritionLines(soup)[position].raw);
      expect(group['bucket'], 'check');
      expect((group['match']! as Map)['fdc_id'], salt.id);
      expect((group['match']! as Map)['confidence'], 0.05);
      expect(group['lines'], 4, reason: 'three recipes, the cake salts twice');
      expect(group['recipes'], 3);
      expect(group['decided'], isFalse);
      expect(group['grams'], {'min': 4.0, 'max': 12.0, 'missing': 1});
    });

    test('the example is the lowest-confidence line, then one WITH grams, '
        'then the recipe title, then the position', () {
      // Lowest confidence: the cake's 0.9 salt line is not the example, and
      // among the three at 0.05 (all with grams) the title decides.
      expect(groupFor('table salt')['recipe'], containsPair('slug', soup.slug));

      // Both butter lines are 0.2; the tarte's title sorts FIRST and its row
      // has no grams, so grams — not the title — picks the cake's line.
      final butterGroup = groupFor('without salt butter');
      expect(butterGroup['recipe'], containsPair('slug', bundt.slug));
      expect(
        tarte.title.compareTo(bundt.title),
        lessThan(0),
        reason: 'the title alone would have picked the tarte',
      );

      // Two lines of one recipe, same confidence and same grams: position.
      final oilPositions = positionsOf(acquacotta, 'extra-virgin olive oil');
      expect(oilPositions, hasLength(2));
      expect(
        groupFor('extra-virgin olive oil')['position'],
        oilPositions.first,
      );
    });

    test('a group is as bad as its worst member', () {
      // Three `check` lines and one `no_grams` line: the group is `check`.
      expect(groupFor('table salt')['bucket'], 'check');
      expect(groupFor('grand marnier')['bucket'], 'no_match');
      expect(groupFor('chicken broth')['bucket'], 'check');
    });

    test('worst confidence first, then lines, then recipes, then the key', () {
      expect(
        [
          for (final group in itemsOf(report()))
            '${group['item_key']}/${(group['recipe']! as Map)['slug']}',
        ],
        [
          'grand marnier/${tarte.slug}', // 0.0 — a no-match stores 0, not null
          'table salt/${soup.slug}', // 0.05
          // Three groups at 0.2: two lines beat one, and two recipes beat one.
          'without salt butter/${bundt.slug}',
          'extra-virgin olive oil/${acquacotta.slug}',
          'chicken broth/${acquacotta.slug}',
          // Two unkeyed groups, alike in everything but their key.
          '/${bundt.slug}',
          '/${tarte.slug}',
        ],
      );
    });

    test(
      'a row with no ingredient key is a group of one, and reports no key',
      () {
        final unkeyed = itemsOf(
          report(),
        ).where((group) => group['item_key'] == '').toList();
        expect(unkeyed, hasLength(2), reason: 'NULL and empty stay apart');
        for (final group in unkeyed) {
          expect(group['lines'], 1);
          expect(group['recipes'], 1);
          expect(group['decided'], isFalse);
        }
      },
    );

    test('a bucket filter groups only that bucket lines, and counts them', () {
      final groups = itemsOf(report(bucket: 'no_grams'));
      expect(groups, hasLength(3), reason: 'one salt line + the two unkeyed');
      final salt = groupFor('table salt', bucket: 'no_grams');
      expect(salt['bucket'], 'no_grams');
      expect(salt['lines'], 1, reason: 'the other three are `check`');
      expect(salt['recipes'], 1);
      expect(salt['position'], positionsOf(caramel, 'table salt')[1]);
      expect(salt['grams'], {'min': null, 'max': null, 'missing': 1});
    });

    test('`decided` is the ingredient decision, not the line status', () {
      expect(groupFor('without salt butter')['decided'], isTrue);
      for (final group in itemsOf(report())) {
        if (group['item_key'] != 'without salt butter') {
          expect(group['decided'], isFalse, reason: '${group['item_key']}');
        }
      }
    });

    test('both views count groups as well as lines, and a key whose lines '
        'span two buckets counts once', () {
      for (final grouped in [true, false]) {
        final body = report(grouped: grouped);
        expect(body['total'], 12, reason: 'lines, in both views');
        expect(body['groups'], 7, reason: 'grouped=$grouped');
        expect(
          {
            for (final bucket in body['buckets']! as List)
              (bucket as Map)['id']: [bucket['count'], bucket['groups']],
          },
          {
            'no_match': [1, 1],
            'check': [8, 4],
            'no_grams': [3, 3],
            'skipped': [0, 0],
          },
          reason:
              'the salt key is one of the check groups AND one of the '
              'no_grams groups, but only one of the seven',
        );
      }
    });

    test('paging counts groups, and never splits one across a page', () {
      final first = itemsOf(report(limit: 1));
      final second = itemsOf(report(page: 2, limit: 1));
      expect(first.single['item_key'], 'grand marnier');
      expect(second.single['item_key'], 'table salt');
      expect(
        second.single['lines'],
        4,
        reason: 'the whole group, not the members that fit on the page',
      );
    });

    test('`item` is the example line parsed item, exactly as the per-recipe '
        'matches endpoint reports it', () async {
      final group = groupFor('table salt');
      final matches = await matchesBody(db, provider, soup);
      final line =
          (matches['items']! as List)[group['position']! as int] as Map;
      expect(group['item'], line['item']);
      expect(group['item'], isNotNull, reason: 'the soup names its salt');
    });

    test('the line view sorts an ingredient lines together, so a group '
        'members can be worked in a straight run', () {
      expect(
        [
          for (final line in db.nutritionReviewLines(limit: 50, offset: 0))
            line.match.itemKey,
        ],
        [
          'grand marnier',
          'table salt',
          'table salt',
          'table salt',
          'chicken broth',
          'extra-virgin olive oil',
          'extra-virgin olive oil',
          'without salt butter',
          'without salt butter',
          'table salt',
          null,
          '',
        ],
        reason: 'worst confidence first, then the ingredient key',
      );
    });

    test('an unknown grouping is rejected, and no grouping is line mode', () {
      expect(
        () => nutritionReviewHandler(db, page: 1, limit: 50, group: 'foo'),
        throwsA(isA<ValidationException>()),
      );
      for (final group in [null, '']) {
        final items = itemsOf(
          nutritionReviewHandler(db, page: 1, limit: 50, group: group),
        );
        expect(items, hasLength(12), reason: 'lines, not groups');
        expect(items.first.containsKey('item_key'), isFalse);
      }
    });
  });

  /// A second library, seeded for the ORDER the queue produces: every tie
  /// here is inserted in the REVERSE of the order the clauses ask for, so a
  /// deleted clause falls back to insertion order and fails a test. Its
  /// decided row also pins that only UNDECIDED lines join an ingredient.
  group('nutrition-review group ordering', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late ServerConfig config;
    late SaltDatabase db;
    late FixtureProvider provider;
    late Recipe bundt;
    late Recipe acquacotta;
    late Recipe caramel;
    // The corpus holds the show's two Chicken Francese recipes — same TITLE,
    // different documents: the only pair that can tell the title tie-break
    // from the position one.
    late Recipe franceseA;
    late Recipe franceseB;

    const salt = (id: 173468, desc: 'Salt, table', type: 'SR Legacy');
    const butter = (
      id: 173430,
      desc: 'Butter, without salt',
      type: 'SR Legacy',
    );
    const broth = (
      id: 171609,
      desc: 'Soup, chicken broth, low sodium, canned',
      type: 'SR Legacy',
    );
    const powdered = (id: 169656, desc: 'Sugars, powdered', type: 'SR Legacy');
    const flour = (
      id: 789890,
      desc: 'Flour, wheat, all-purpose, enriched, bleached',
      type: 'Foundation',
    );

    List<int> positionsOf(Recipe recipe, String key) => [
      for (final (index, line) in nutritionLines(recipe).indexed)
        if (itemKeyFor(line.item ?? line.raw) == key) index,
    ];

    int positionOf(Recipe recipe, String key) {
      final positions = positionsOf(recipe, key);
      expect(positions, isNotEmpty, reason: '$key must be a real line');
      return positions.first;
    }

    /// Writes one match row for a REAL line, in a crafted triage state.
    /// [raw] overrides the stored text (the drift a recipe edit leaves).
    void seed(
      Recipe recipe,
      int position, {
      required double confidence,
      required ({int id, String desc, String type}) food,
      double? grams,
      String status = 'auto',
      String? raw,
    }) {
      final line = nutritionLines(recipe)[position];
      db.upsertIngredientMatch(
        IngredientMatchRow(
          recipeId: recipe.id,
          position: position,
          raw: raw ?? line.raw,
          itemKey: itemKeyFor(line.item ?? line.raw),
          fdcId: food.id,
          description: food.desc,
          dataType: food.type,
          confidence: confidence,
          grams: grams,
          gramSource: grams == null ? null : 'weight',
          status: status,
        ),
      );
    }

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('salt-review-order');
      config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath);
      provider = FixtureProvider();
      final sourceRoot = Directory('${tempDir.path}/source')
        ..createSync(recursive: true);
      Directory('${sourceRoot.path}/recipes').createSync();
      for (final name in [
        '0857-rich-chocolate-bundt-cake.yaml',
        '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml',
        '0879-easy-caramel-cake.yaml',
        '0420-chicken-francese.yaml',
        '1133-chicken-francese.yaml',
      ]) {
        File(
          '$corpusRecipesDir/$name',
        ).copySync('${sourceRoot.path}/recipes/$name');
      }
      importSourceRoot(sourceRootPath: sourceRoot.path, db: db, config: config);
      bundt = db.recipeByIdOrSlug('rich-chocolate-bundt-cake')!.recipe;
      acquacotta = db
          .recipeByIdOrSlug('acquacotta-tuscan-white-bean-and-escarole-soup')!
          .recipe;
      caramel = db.recipeByIdOrSlug('easy-caramel-cake')!.recipe;
      franceseA = db
          .recipeByIdOrSlug('atk-tv-2023-0420-chicken-francese')!
          .recipe;
      franceseB = db
          .recipeByIdOrSlug('atk-tv-2023-1133-chicken-francese')!
          .recipe;
      expect(franceseA.title, franceseB.title, reason: 'the same dish twice');
      expect(franceseA.id.compareTo(franceseB.id), lessThan(0));

      // Two single-line groups alike in worst, lines and recipes: only the
      // KEY separates them, and the later key is written first.
      seed(
        bundt,
        positionOf(bundt, 'powdered sugar'),
        confidence: 0.05,
        food: powdered,
        grams: 30,
      );
      seed(
        acquacotta,
        positionOf(acquacotta, 'chicken broth'),
        confidence: 0.05,
        food: broth,
        grams: 1920,
      );
      // The lowest-confidence member has NO grams while the higher one has:
      // confidence outranks the grams tie-break.
      seed(
        bundt,
        positionOf(bundt, 'all-purpose flour'),
        confidence: 0.4,
        food: flour,
        grams: 510,
      );
      seed(
        caramel,
        positionOf(caramel, 'all-purpose flour'),
        confidence: 0.1,
        food: flour,
      );
      // Tied on confidence, on having grams AND on the position: the TITLE
      // decides, and the later title is written first.
      seed(
        bundt,
        positionOf(bundt, 'table salt'),
        confidence: 0.45,
        food: salt,
        grams: 6,
      );
      seed(
        caramel,
        positionsOf(caramel, 'table salt').first,
        confidence: 0.45,
        food: salt,
        grams: 12,
      );
      // Tied on confidence, on having grams and on the TITLE (the same dish
      // twice): only the position separates them, and it runs against the
      // order the rows are stored in — the higher position is written first.
      seed(
        franceseA,
        positionsOf(franceseA, 'without salt butter').last,
        confidence: 0.3,
        food: butter,
        grams: 28,
      );
      seed(
        franceseB,
        positionOf(franceseB, 'without salt butter'),
        confidence: 0.3,
        food: butter,
        grams: 28,
      );
      // A line a person decided and left without an amount: never a member
      // of the salt group, however many lines that ingredient has.
      seed(
        caramel,
        positionsOf(caramel, 'table salt').last,
        confidence: 0.6,
        food: salt,
        status: 'overridden',
      );
      db.putDecision(
        itemKey: 'table salt',
        item: 'table salt',
        fdcId: salt.id,
        description: salt.desc,
        dataType: salt.type,
        decidedBy: null,
      );
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    Map<String, Object?> report({
      String? bucket,
      int page = 1,
      int limit = 50,
    }) => nutritionReviewHandler(
      db,
      page: page,
      limit: limit,
      bucket: bucket,
      group: 'item',
    );

    List<Map<String, Object?>> itemsOf(Map<String, Object?> body) => [
      for (final item in body['items']! as List)
        (item as Map).cast<String, Object?>(),
    ];

    Map<String, Object?> groupFor(String itemKey, {String? bucket}) =>
        itemsOf(report(bucket: bucket)).firstWhere(
          (item) => item['item_key'] == itemKey,
          orElse: () => fail('no group for $itemKey'),
        );

    test('the example is the LOWEST-confidence member even when a higher one '
        'has grams and it has none', () {
      final group = groupFor('all-purpose flour');
      expect(
        group['recipe'],
        containsPair('slug', caramel.slug),
        reason: 'confidence outranks the grams tie-break',
      );
      expect((group['match']! as Map)['grams'], isNull);
      expect(
        (group['match']! as Map)['confidence'],
        0.1,
        reason: "the example's score IS the group's minimum",
      );
      expect(group['grams'], {'min': 510.0, 'max': 510.0, 'missing': 1});
    });

    test('members tied on confidence, on having grams and on the position '
        'break on the recipe title, not on when they were written', () {
      expect(
        bundt.title.compareTo(caramel.title),
        greaterThan(0),
        reason: 'the row written FIRST sorts LAST by title',
      );
      expect(
        positionOf(bundt, 'table salt'),
        positionsOf(caramel, 'table salt').first,
        reason: 'the position cannot separate them',
      );
      expect(
        groupFor('table salt', bucket: 'check')['recipe'],
        containsPair('slug', caramel.slug),
      );
    });

    test('members tied on everything the title can see break on the '
        'position, not on the order the rows are stored in', () {
      final group = groupFor('without salt butter');
      expect(group['lines'], 2);
      expect(group['recipes'], 2);
      expect(
        positionsOf(franceseA, 'without salt butter').last,
        greaterThan(positionOf(franceseB, 'without salt butter')),
        reason: 'the row stored FIRST holds the higher position',
      );
      expect(group['recipe'], containsPair('slug', franceseB.slug));
      expect(group['position'], positionOf(franceseB, 'without salt butter'));
    });

    test('two groups tied on worst, lines and recipes page in KEY order', () {
      expect(
        [for (final group in itemsOf(report())) group['item_key']],
        [
          'chicken broth',
          'powdered sugar',
          'all-purpose flour',
          'without salt butter',
          'table salt', // the two undecided lines
          'table salt', // the decided line, its own group
        ],
      );
      expect(itemsOf(report(limit: 1)).single['item_key'], 'chicken broth');
      expect(
        itemsOf(report(page: 2, limit: 1)).single['item_key'],
        'powdered sugar',
        reason: 'the later key, though it was written first',
      );
    });

    test(
      'the key tie-break is IN the ORDER BY, not left to the query plan',
      () {
        // The test above proves the DIRECTION (`a.gkey DESC` reverses the tied
        // pair) but cannot prove the clause is there at all: `agg` is GROUP BY
        // gkey, so SQLite already emits its rows in key order and deleting the
        // tie-break changes nothing observable. Order across ties would then
        // rest on a plan property nothing documents — so pin the text.
        db.nutritionReviewGroups(limit: 1, offset: 0);
        final sql = db.preparedSqlTexts.singleWhere(
          (text) => text.contains('ROW_NUMBER() OVER (PARTITION BY gkey'),
          orElse: () => fail('the grouped query was not prepared'),
        );
        expect(
          sql,
          contains(
            'ORDER BY a.worst, a.lines DESC, a.recipes DESC, a.gkey '
            'LIMIT ? OFFSET ?',
          ),
        );
      },
    );

    test('a line someone already decided is a group of one — never part of '
        'the ingredient reach an apply would land on', () async {
      final decidedPosition = positionsOf(caramel, 'table salt').last;
      final undecided = groupFor('table salt', bucket: 'check');
      expect(undecided['lines'], 2);
      expect(undecided['recipes'], 2);

      final alone = itemsOf(report(bucket: 'no_grams')).single;
      expect(alone['item_key'], 'table salt', reason: 'it still reports it');
      expect(alone['lines'], 1);
      expect(alone['recipes'], 1);
      expect(alone['position'], decidedPosition);
      expect((alone['match']! as Map)['status'], 'overridden');
      expect(
        alone['decided'],
        isTrue,
        reason: "its ingredient's decision still shows on it",
      );

      // The pill promises exactly what the apply reaches: the example line's
      // own reach, counted the same way, is the group minus itself.
      final matches = await matchesBody(db, provider, caramel);
      final example =
          (matches['items']! as List)[undecided['position']! as int] as Map;
      expect(example['others_lines'], (undecided['lines']! as int) - 1);
    });

    test('a group whose example line text changed since the compute has no '
        '`item` — the row still says what it was written for', () {
      final position = positionOf(acquacotta, 'chicken broth');
      final line = nutritionLines(acquacotta)[position];
      expect(groupFor('chicken broth')['item'], isNotNull);

      seed(
        acquacotta,
        position,
        confidence: 0.05,
        food: broth,
        grams: 1920,
        raw: '${line.raw} (edited)',
      );
      final drifted = groupFor('chicken broth');
      expect(drifted['item'], isNull, reason: 'it describes a line that went');
      expect(drifted['raw'], '${line.raw} (edited)');

      seed(acquacotta, position, confidence: 0.05, food: broth, grams: 1920);
      expect(groupFor('chicken broth')['item'], isNotNull);
    });
  });
}
