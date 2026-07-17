import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';

const _sourceSlug = 'atk-tv-2023';

Recipe _load(String fileName) => loadCorpusRecipe(fileName);

String _hashOf(Recipe recipe) => contentHashOf(recipe);

void main() {
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
}
