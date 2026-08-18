import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/search/fts_compiler.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';

const _sourceSlug = 'atk-tv-2023';

Recipe _load(String fileName) => loadCorpusRecipe(fileName);

String _hashOf(Recipe recipe) => contentHashOf(recipe);

void main() {
  // Deliberately OUTSIDE the corpus gate below: these are security
  // regressions and CI has no corpus. The cache bound needs no recipe data —
  // an empty schema answers every query shape — and the filter semantics
  // need only calorie numbers, which are the DSL's input, not recipe data.
  _preparedStatementCacheIsBounded();
  _preparedSqlIsAlwaysConstant();
  _caloriesFilterSemantics();

  // Corpus-backed integration tests: skip (not fail) when the ATK corpus is
  // absent — e.g. CI — so `dart test` stays green. Set SALT_CORPUS_DIR to run.
  if (!corpusAvailable) {
    test(
      'corpus-backed tests (skipped: corpus absent)',
      () {},
      skip: 'ATK corpus not present; set SALT_CORPUS_DIR',
    );
    return;
  }
  late Recipe bundtCake; // Rich Chocolate Bundt Cake
  late Recipe sweetPotatoSoup; // Sweet Potato Soup
  late Recipe vinaigrette; // Foolproof Vinaigrette
  late Directory tempDir;
  late String dbPath;
  late SaltDatabase db;

  setUpAll(() {
    bundtCake = _load('0857-rich-chocolate-bundt-cake.yaml');
    sweetPotatoSoup = _load('0020-sweet-potato-soup.yaml');
    vinaigrette = _load('0038-foolproof-vinaigrette.yaml');
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('salt_db_test');
    dbPath = '${tempDir.path}/salt.db';
    db = SaltDatabase.open(dbPath)
      ..upsertSource(
        slug: _sourceSlug,
        name:
            "The Complete America's Test Kitchen TV Show Cookbook "
            '2001–2023',
        type: 'epub',
        meta: {'isbn': '9781954210110'},
      );
  });

  tearDown(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  void insertAllThree() {
    for (final recipe in [bundtCake, sweetPotatoSoup, vinaigrette]) {
      final outcome = db.upsertRecipe(
        recipe,
        sourceSlug: _sourceSlug,
        contentHash: _hashOf(recipe),
      );
      expect(outcome, UpsertOutcome.inserted);
    }
  }

  test('upserting three corpus recipes inserts three rows', () {
    insertAllThree();
    expect(db.recipeCount(), 3);
  });

  test('re-upserting with the same content hash is unchanged', () {
    insertAllThree();
    final outcome = db.upsertRecipe(
      bundtCake,
      sourceSlug: _sourceSlug,
      contentHash: _hashOf(bundtCake),
    );
    expect(outcome, UpsertOutcome.unchanged);
    expect(db.recipeCount(), 3);
  });

  test('re-upserting with a different content hash is updated', () {
    insertAllThree();
    final outcome = db.upsertRecipe(
      bundtCake,
      sourceSlug: _sourceSlug,
      contentHash: 'modified-$_sourceSlug',
    );
    expect(outcome, UpsertOutcome.updated);
    expect(db.recipeCount(), 3);
  });

  test('listCards paginates by title with tags and hero image URL', () {
    insertAllThree();

    final pageOne = db.listCards(page: 1, limit: 2);
    expect(pageOne.total, 3);
    expect(
      [for (final card in pageOne.items) card.title],
      ['Foolproof Vinaigrette', 'Rich Chocolate Bundt Cake'],
    );

    final pageTwo = db.listCards(page: 2, limit: 2);
    expect(pageTwo.total, 3);
    expect(
      [for (final card in pageTwo.items) card.title],
      ['Sweet Potato Soup'],
    );

    final bundtCard = pageOne.items[1];
    expect(bundtCard.id, bundtCake.id);
    expect(bundtCard.tags, ['dessert']);
    expect(
      bundtCard.heroImage,
      '/images/$_sourceSlug/0857-rich-chocolate-bundt-cake-hero.jpg',
    );
    expect(bundtCard.servingsText, bundtCake.servings);
  });

  test('recipeByIdOrSlug resolves both keys to a deep-equal recipe', () {
    insertAllThree();

    final byId = db.recipeByIdOrSlug(bundtCake.id);
    expect(byId, isNotNull);
    expect(byId!.recipe, equals(bundtCake));
    expect(byId.sourceSlug, _sourceSlug);

    final bySlug = db.recipeByIdOrSlug(bundtCake.slug);
    expect(bySlug, isNotNull);
    expect(bySlug!.recipe, equals(bundtCake));
    expect(bySlug.sourceSlug, _sourceSlug);

    expect(db.recipeByIdOrSlug('no-such-recipe'), isNull);
  });

  test('slug collision suffixes the slug in the row and the stored doc', () {
    insertAllThree();

    final duplicate = bundtCake.copyWith(id: 'test-dup');
    final outcome = db.upsertRecipe(
      duplicate,
      sourceSlug: _sourceSlug,
      contentHash: 'test-dup-hash',
    );
    expect(outcome, UpsertOutcome.inserted);
    expect(db.recipeCount(), 4);

    // The original id keeps the unsuffixed slug.
    expect(db.recipeByIdOrSlug(bundtCake.slug)!.recipe.id, bundtCake.id);

    // The duplicate row owns the suffixed slug, and its stored document
    // carries the same resolved slug so the detail response and the card
    // agree (the doc slug resolves back to this recipe, not the original).
    final suffixed = db.recipeByIdOrSlug('${bundtCake.slug}-2');
    expect(suffixed, isNotNull);
    expect(suffixed!.recipe.id, 'test-dup');
    expect(suffixed.recipe.slug, '${bundtCake.slug}-2');
  });

  test('FTS row exists and matches a stemmed title word', () {
    insertAllThree();

    final raw = sqlite3.open(dbPath);
    try {
      final count =
          raw.select(
                'SELECT count(*) AS n FROM recipe_fts WHERE recipe_fts MATCH ?',
                ['chocolate'],
              ).first['n']
              as int;
      expect(count, greaterThanOrEqualTo(1));
    } finally {
      raw.dispose();
    }
  });

  group('variation_count', () {
    // Decided 2026-07-16: count `variation` subsections ONLY. A `component`
    // is a sub-recipe (the dough for the pie), not a variant of the recipe,
    // so badging it would be wrong.
    test('counts variations, not components or subsections wholesale', () {
      // Sweet Cream Ice Cream is the discriminator: 3 variations AND 3
      // components, 6 subsections in all. A raw subsection count would say 6;
      // the honest answer is 3. A component is a sub-recipe, not a variant.
      final iceCream = _load('1164-sweet-cream-ice-cream.yaml');
      final variations = iceCream.subsections
          .where((s) => s.kind == 'variation')
          .length;
      final components = iceCream.subsections
          .where((s) => s.kind == 'component')
          .length;
      expect(variations, 3, reason: 'the fixture must have variants');
      expect(components, 3, reason: 'and components, or it proves nothing');
      expect(iceCream.subsections.length, 6);

      db.upsertRecipe(
        iceCream,
        sourceSlug: _sourceSlug,
        contentHash: _hashOf(iceCream),
      );
      final card = db
          .listCards(page: 1, limit: 50)
          .items
          .firstWhere((c) => c.id == iceCream.id);
      expect(
        card.variationCount,
        3,
        reason: 'counted the components too if this is 6',
      );
      expect(card.hasVariations, isTrue);
    });

    test('a recipe with no subsections carries 0, and says so', () {
      db.upsertRecipe(
        bundtCake,
        sourceSlug: _sourceSlug,
        contentHash: _hashOf(bundtCake),
      );
      final card = db.listCards(page: 1, limit: 50).items.single;
      expect(card.variationCount, 0);
      expect(card.hasVariations, isFalse);
    });

    test('an update keeps the count in step with the doc', () {
      final iceCream = _load('1164-sweet-cream-ice-cream.yaml');
      db.upsertRecipe(
        iceCream,
        sourceSlug: _sourceSlug,
        contentHash: _hashOf(iceCream),
      );
      // Strip the variations and re-save: the card must follow, or the badge
      // outlives the thing it describes. (The migration backfills once; only
      // upsertRecipe keeps it true afterwards.)
      final stripped = iceCream.copyWith(subsections: const []);
      db.upsertRecipe(
        stripped,
        sourceSlug: _sourceSlug,
        contentHash: '${_hashOf(iceCream)}-changed',
      );
      final card = db.listCards(page: 1, limit: 50).items.single;
      expect(card.variationCount, 0);
    });

    test('search results carry it too, not just the list', () {
      // searchCards has its OWN SELECT; adding the column to listCards alone
      // would leave every search result silently un-badged.
      final iceCream = _load('1164-sweet-cream-ice-cream.yaml');
      db.upsertRecipe(
        iceCream,
        sourceSlug: _sourceSlug,
        contentHash: _hashOf(iceCream),
      );
      final parsed = parseSearchQuery('ice cream');
      final found = db.searchCards(
        compileSearch(parsed.root!),
        page: 1,
        limit: 50,
      );
      // By identity, not by position: `first` is whatever bm25 ranked top,
      // so a ranking change could satisfy a positional assertion against the
      // wrong row.
      final card = found.items.firstWhere(
        (c) => c.id == iceCream.id,
        orElse: () => throw StateError('ice cream missing from results'),
      );
      expect(card.variationCount, 3);
    });
  });
}

/// S6: [SaltDatabase] caches every prepared statement forever, so the set of
/// SQL *texts* it can emit must be finite and small — otherwise a query whose
/// SHAPE varies (the `calories:` operators are the only lever a caller has)
/// pins a fresh pair of native statements per never-before-seen shape, for the
/// process lifetime, on the serving isolate and on every search worker's
/// connection. `GET /api/v1/recipes?q=` is reachable with a read-scoped PAT.
void _preparedStatementCacheIsBounded() {
  // Every operator the DSL can produce (`CaloriesOp`), in its written form.
  const ops = ['=', '<', '<=', '>', '>='];
  // One value throughout: the SQL text depends on the operator sequence, not
  // on the numbers.
  const value = 300;

  group('prepared-statement cache', () {
    late Directory tempDir;
    late SaltDatabase db;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('salt_db_stmt_cache');
      db = SaltDatabase.open('${tempDir.path}/salt.db');
    });

    tearDown(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    void search(String query) {
      final parsed = parseSearchQuery(query);
      final root = parsed.root;
      expect(root, isNotNull, reason: 'query did not parse: $query');
      for (final favoritesOnly in [false, true]) {
        db.searchCards(
          compileSearch(root!),
          page: 1,
          limit: 20,
          viewerId: 1,
          favoritesOnly: favoritesOnly,
        );
      }
    }

    /// Issues every calories-operator sequence of length [length], with and
    /// without a text term (the FTS join is the other shape lever).
    void sweep(int length) {
      var sequences = <List<String>>[<String>[]];
      for (var i = 0; i < length; i++) {
        sequences = [
          for (final seq in sequences)
            for (final op in ops) [...seq, op],
        ];
      }
      for (final seq in sequences) {
        final terms = [for (final op in seq) 'calories:$op$value'].join(' ');
        search(terms);
        search('chocolate $terms');
      }
    }

    // The closed form of everything searchCards can emit, and the reason a
    // caller cannot outrun it: the calories terms collapse to one lower and
    // one upper bound, each of which is absent, exclusive or inclusive, so
    // 3 x 3 - 1 = 8 calories fragments (a calories query always bounds one
    // side), x 2 (the FTS join) x 2 (favoritesOnly) x 2 statements (the
    // COUNT and the page), plus the 1 x 2 x 2 text-only shapes. Observed
    // too, not only derived.
    const searchShapes = 8 * 2 * 2 * 2 + 1 * 2 * 2;

    test('a widening space of query shapes does not grow it', () {
      search('chocolate');
      search('chocolate or cake');
      final baseline = db.preparedSqlTexts.length;

      sweep(1); // 5 operator sequences
      sweep(2); // 25 sequences — every reachable bound combination
      final afterPairs = db.preparedSqlTexts.length;

      sweep(3); // 125 sequences — 5x the sequences, 0 new shapes
      final afterAll = db.preparedSqlTexts.length;

      // The whole point: a 5x wider space of attacker-chosen shapes adds
      // nothing. Pre-fix, each operator SEQUENCE minted its own SQL text.
      expect(
        afterAll,
        afterPairs,
        reason: 'a new query shape pinned a new prepared statement',
      );
      expect(afterAll, greaterThan(baseline), reason: 'calories path unused?');
      expect(afterAll, searchShapes);
    });

    test('the DSL term cap cannot mint a statement either', () {
      search('chocolate');
      sweep(1);
      sweep(2);
      final before = db.preparedSqlTexts.length;
      // maxSearchTerms calories terms, cycling every operator: the largest
      // single query the parser accepts.
      final terms = [
        for (var i = 0; i < maxSearchTerms; i++)
          'calories:${ops[i % ops.length]}$value',
      ].join(' ');
      search(terms);
      search('chocolate $terms');
      expect(db.preparedSqlTexts.length, before);
      expect(before, searchShapes);
    });

    test('the unfiltered listing interpolates only a bool-picked filter', () {
      // listCards is the other method that interpolates into _prepared (its
      // favorites filter). Its whole space: 2 filter states x 2 statements.
      for (final favoritesOnly in [false, true]) {
        for (final page in [1, 2]) {
          db.listCards(
            page: page,
            limit: 20,
            viewerId: 1,
            favoritesOnly: favoritesOnly,
          );
        }
      }
      expect(db.preparedSqlTexts.length, 2 * 2);
    });

    test('the review queue binds its bucket filter instead of naming it', () {
      // The third interpolating site, and the one nothing counted: its
      // predicate was a local named `where` — the same name searchCards' is
      // pinned under — so the constant scan below whitelisted it on the NAME
      // while no shape test bounded what it could emit. Binding the bucket
      // makes the text a single compile-time constant: every bucket state,
      // one statement, nothing request-derived in the cache key.
      for (final bucket in [null, 'no_match', 'no_grams', 'check', 'counted']) {
        db.nutritionReviewLines(limit: 20, offset: 0, bucket: bucket);
      }
      expect(
        db.preparedSqlTexts.length,
        1,
        reason: 'the review queue emits one SQL text for every bucket',
      );
    });
  });
}

/// S6, the general case: the shape test above only proves that *searchCards'*
/// levers are bounded. The cache is never evicted, so the invariant is
/// class-wide — every `_prepared` SQL text must be a compile-time constant.
/// This reads the source and fails the moment a new one is not, wherever in
/// the class it appears.
///
/// The name whitelist below is the one thing that could let this guard lie, so
/// the COUNT of call sites using it is pinned too: `nutritionReviewLines` rode
/// in on the allowed name `where` while no shape test counted what it emitted,
/// and a mutation that interpolated a raw query parameter there left the whole
/// suite green. A new interpolating call site now fails here until whoever
/// adds it pins what it can emit — which is what the shape tests above do for
/// the four that remain.
void _preparedSqlIsAlwaysConstant() {
  // searchCards' FROM/WHERE/ORDER and listCards' favorites filter: locals,
  // so the source scan cannot see that they are constant — the shape tests
  // pin them by counting the SQL texts the two methods can actually emit.
  const pinnedLocals = {'from', 'where', 'order', 'favoriteFilter'};
  // And the only call sites allowed to use them: searchCards' COUNT + page,
  // listCards' COUNT + page. A fifth is an emitter nothing counts.
  const pinnedInterpolatingCalls = 4;

  test('every _prepared() argument is a string literal', () {
    final file = File('lib/src/db/salt_database.dart');
    expect(file.existsSync(), isTrue, reason: 'run tests from apps/server');
    final source = file.readAsStringSync();

    // Every call site, minus the declaration `_prepared(String sql)`.
    final callSites =
        RegExp(r'_prepared\(').allMatches(source).length -
        RegExp(r'_prepared\(String ').allMatches(source).length;
    // Calls whose whole argument is one or more adjacent string literals
    // (single- or double-quoted, wrapped across lines, trailing comma).
    const literal = r'''(?:r?'(?:[^'\\]|\\.)*'|r?"(?:[^"\\]|\\.)*")''';
    final literalCalls = RegExp(
      r'_prepared\(\s*((?:' + literal + r'\s*)+),?\s*\)',
    ).allMatches(source).toList();
    expect(
      literalCalls.length,
      callSites,
      reason:
          'a _prepared() call passes something other than a literal; '
          'a runtime-built SQL text can vary without bound',
    );

    // Anything interpolated into a cached SQL text must itself be constant:
    // either a `static const` of this class, or one of the pinned locals.
    final constants = {
      for (final m in RegExp(
        r'static const (?:String )?(\w+)\s*=',
      ).allMatches(source))
        m.group(1)!,
    };
    final interpolated = {
      for (final call in literalCalls)
        for (final name in RegExp(r'\$(\w+)').allMatches(call.group(1)!))
          name.group(1)!,
    };
    expect(
      interpolated.difference(constants.union(pinnedLocals)),
      isEmpty,
      reason:
          'a runtime value reached a cached SQL text: only a static '
          'const or a shape-pinned local may be interpolated into one',
    );

    // The whitelist is by NAME, so a new call site could inherit a pin it
    // never earned just by reusing one of those four names. Counting the
    // sites that interpolate a non-constant closes that: the check above says
    // WHAT may ride in, this one says HOW MANY places may.
    final interpolatingCalls = literalCalls
        .where(
          (call) => RegExp(r'\$(\w+)')
              .allMatches(call.group(1)!)
              .any((m) => !constants.contains(m.group(1))),
        )
        .length;
    expect(
      interpolatingCalls,
      pinnedInterpolatingCalls,
      reason:
          'a _prepared() call interpolates a non-constant local that no '
          'shape test counts; bind the value instead, or pin what the '
          'method can emit and update this count',
    );
  });
}

/// What the S6 fix rewrote: the `calories:` predicate. The cache bound was
/// bought by collapsing every operator sequence into one range, so these pin
/// the RESULTS — an inverted operator, a transposed bound or a collapse that
/// keeps the loosest bound instead of the tightest all pass a
/// statement-count assertion while handing the caller rows they filtered out.
///
/// Corpus-free on purpose (CI has no corpus): operators and thresholds are
/// the DSL's own input, and the rows below carry nothing but an id, a title
/// and a number — no recipe content is invented.
void _caloriesFilterSemantics() {
  // Ordered ascending: `calories:` queries sort lowest-first, so an expected
  // id list pins the ordering contract as well as the filter.
  const perServing = <String, double>{
    'r100': 100,
    'r200': 200,
    'r300': 300,
    'r400': 400,
    'r500': 500,
  };
  const noNutrition = 'r-uncomputed';

  group('calories filter semantics', () {
    late Directory tempDir;
    late SaltDatabase db;
    late Database raw;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('salt_db_calories');
      final path = '${tempDir.path}/salt.db';
      db = SaltDatabase.open(path); // migrates
      raw = sqlite3.open(path)
        ..execute(
          "INSERT INTO sources (slug, name, type) VALUES ('$_sourceSlug', "
          "'Test Kitchen', 'book')",
        );
      final insertRecipe = raw.prepare(
        'INSERT INTO recipes (id, slug, source_slug, title, doc, '
        'content_hash) VALUES (?, ?, ?, ?, ?, ?)',
      );
      final insertNutrition = raw.prepare(
        'INSERT INTO recipe_nutrition (recipe_id, calories_per_serving, '
        'nutrients, matched_count, total_count, status, ingredients_hash) '
        "VALUES (?, ?, '{}', 1, 1, 'complete', 'h')",
      );
      for (final id in [...perServing.keys, noNutrition]) {
        insertRecipe.execute([id, id, _sourceSlug, id, '{}', 'h-$id']);
        final calories = perServing[id];
        if (calories != null) {
          insertNutrition.execute([id, calories]);
        }
      }
      insertRecipe.dispose();
      insertNutrition.dispose();
    });

    tearDown(() {
      raw.dispose();
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    List<String> idsFor(String query) {
      final root = parseSearchQuery(query).root;
      expect(root, isNotNull, reason: 'query did not parse: $query');
      final found = db.searchCards(
        compileSearch(root!),
        page: 1,
        limit: 50,
      );
      final ids = [for (final card in found.items) card.id];
      expect(found.total, ids.length, reason: 'COUNT disagrees with the page');
      return ids;
    }

    test('each operator selects its own side of the threshold', () {
      expect(idsFor('calories:<300'), ['r100', 'r200']);
      expect(idsFor('calories:<=300'), ['r100', 'r200', 'r300']);
      expect(idsFor('calories:>300'), ['r400', 'r500']);
      expect(idsFor('calories:>=300'), ['r300', 'r400', 'r500']);
      expect(idsFor('calories:=300'), ['r300']);
      expect(idsFor('calories:300'), ['r300'], reason: 'bare value is =');
    });

    test('two terms are a range, inclusive where written inclusive', () {
      expect(idsFor('calories:>150 calories:<450'), [
        'r200',
        'r300',
        'r400',
      ]);
      expect(idsFor('calories:>=200 calories:<=400'), [
        'r200',
        'r300',
        'r400',
      ]);
      expect(idsFor('calories:>200 calories:<400'), ['r300']);
      expect(idsFor('calories:>=300 calories:<=300'), ['r300']);
    });

    test('repeated operators collapse to the TIGHTEST bound', () {
      // Both orders: a collapse that keeps the newest, or the loosest,
      // passes one of these and fails the other.
      expect(idsFor('calories:<500 calories:<300'), ['r100', 'r200']);
      expect(idsFor('calories:<300 calories:<500'), ['r100', 'r200']);
      expect(idsFor('calories:>100 calories:>300'), ['r400', 'r500']);
      expect(idsFor('calories:>300 calories:>100'), ['r400', 'r500']);
      expect(idsFor('calories:<=300 calories:<=200'), ['r100', 'r200']);
      expect(idsFor('calories:>=300 calories:>=400'), ['r400', 'r500']);
      // Exclusive wins a tie with inclusive: it admits strictly less.
      expect(idsFor('calories:<300 calories:<=300'), ['r100', 'r200']);
      expect(idsFor('calories:>=300 calories:>300'), ['r400', 'r500']);
    });

    test('unsatisfiable terms match nothing — never everything', () {
      expect(idsFor('calories:=300 calories:=400'), isEmpty);
      expect(idsFor('calories:>300 calories:<300'), isEmpty);
      expect(idsFor('calories:>=400 calories:<=300'), isEmpty);
      expect(idsFor('calories:=300 calories:>400'), isEmpty);
    });

    test('a recipe without computed nutrition never matches', () {
      expect(idsFor('calories:>=0'), perServing.keys);
      expect(idsFor('calories:<100000'), isNot(contains(noNutrition)));
    });

    test('the filter still range-scans the calories index', () {
      idsFor('calories:>150 calories:<450');
      final sql = db.preparedSqlTexts.singleWhere(
        (text) =>
            text.startsWith('SELECT COUNT(*)') &&
            text.contains('calories_per_serving > ?') &&
            text.contains('calories_per_serving < ?'),
      );
      final plan = [
        for (final row in raw.select('EXPLAIN QUERY PLAN $sql', [150, 450]))
          row['detail'] as String,
      ].join(' | ');
      // A `(? IS NULL OR calories < ?)` slot per operator is constant SQL
      // too, but not sargable: it plans a full scan of recipe_nutrition on
      // every search, on an endpoint any read-scoped PAT can reach.
      expect(plan, contains('idx_recipe_nutrition_calories'), reason: plan);
    });
  });
}
