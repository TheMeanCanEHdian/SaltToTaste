import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/search/fts_compiler.dart';
import 'package:salt_server/src/search/search_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';

/// The #48 root cure: [IsolateSearchService] runs the FTS ranked search on
/// background isolates instead of the serving isolate. The load-bearing claim
/// is that it is BEHAVIOR-PRESERVING — same rows, same order, same totals as
/// the inline path — on real data, including favorites written through the main
/// connection but read through a worker's separate read-only WAL connection.
void main() {
  if (!corpusAvailable) {
    test(
      'search service tests (skipped: corpus absent)',
      () {},
      skip: skipIfNoCorpus,
    );
    return;
  }

  late Directory tempDir;
  late SaltDatabase db;
  late InlineSearchService inline;
  late IsolateSearchService isolate;
  var favoritingUser = 0;

  CompiledSearch compile(String query) {
    final parsed = parseSearchQuery(query);
    expect(parsed.errors, isEmpty, reason: 'parse errors for "$query"');
    return compileSearch(parsed.root!);
  }

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('salt_search_service');
    db = SaltDatabase.open('${tempDir.path}/salt.db')
      ..upsertSource(slug: 'atk', name: 'ATK corpus', type: 'epub');
    // The whole real corpus, so bm25 ordering, ties, and scoped columns are
    // exercised on the realistic dataset (parity itself holds at any size).
    final files = Directory(
      corpusRecipesDir,
    ).listSync().whereType<File>().where((file) => file.path.endsWith('.yaml'));
    for (final file in files) {
      final recipe = RecipeYamlCodec.decode(file.readAsStringSync()).recipe;
      db.upsertRecipe(
        recipe,
        sourceSlug: 'atk',
        contentHash: contentHashOf(recipe),
      );
    }

    // Favorite two chocolate recipes through the WRITER connection; the worker
    // reads them through its own read-only connection (WAL visibility check).
    favoritingUser = db.createUser(
      username: 'reader',
      passwordHash: 'x',
      role: 'member',
    );
    final chocolate = db.searchCards(compile('chocolate'), page: 1, limit: 100);
    expect(
      chocolate.items.length,
      greaterThanOrEqualTo(2),
      reason: 'need some chocolate recipes to favorite',
    );
    for (final card in chocolate.items.take(2)) {
      db.setFavorite(
        userId: favoritingUser,
        recipeId: card.id,
        favorite: true,
      );
    }

    inline = InlineSearchService(db);
    // Two workers so round-robin dispatch is exercised.
    isolate = await IsolateSearchService.spawn(
      dbPath: '${tempDir.path}/salt.db',
      count: 2,
    );
  });

  tearDownAll(() async {
    // Readers before the writer, or the final checkpoint blocks.
    await isolate.dispose();
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  /// Asserts the isolate path returns exactly what the inline path does.
  Future<void> expectParity(
    String query, {
    int page = 1,
    int limit = 100,
    int? viewerId,
    bool favoritesOnly = false,
  }) async {
    final compiled = compile(query);
    final want = await inline.search(
      compiled,
      page: page,
      limit: limit,
      viewerId: viewerId,
      favoritesOnly: favoritesOnly,
    );
    final got = await isolate.search(
      compiled,
      page: page,
      limit: limit,
      viewerId: viewerId,
      favoritesOnly: favoritesOnly,
    );
    expect(got.total, want.total, reason: 'total mismatch for "$query"');
    expect(
      got.items.map((c) => c.id).toList(),
      want.items.map((c) => c.id).toList(),
      reason: 'ordered ids mismatch for "$query"',
    );
    expect(
      got.items.map((c) => c.favorite).toList(),
      want.items.map((c) => c.favorite).toList(),
      reason: 'favorite flags mismatch for "$query"',
    );
  }

  group('parity with the inline path', () {
    test('a text term ranked by bm25', () => expectParity('chocolate'));
    test('a scoped term', () => expectParity('title:cake'));
    test('an OR of two terms', () => expectParity('butter or sugar'));
    test('multiple terms (AND)', () => expectParity('chicken soup'));
    test(
      'a calories filter (calorie-ordered)',
      () => expectParity('calories:<100000'),
    );
    test('the second page', () => expectParity('butter', page: 2, limit: 5));
    test('a no-hit query', () => expectParity('zzzzznotarealword'));
  });

  test('favorites written on the writer are visible to a worker', () async {
    // favoritesOnly must find exactly the two favorited rows, off-isolate.
    final got = await isolate.search(
      compile('chocolate'),
      page: 1,
      limit: 100,
      viewerId: favoritingUser,
      favoritesOnly: true,
    );
    expect(got.total, 2, reason: 'the two favorites, read via WAL');
    expect(got.items.every((c) => c.favorite), isTrue);
    // ...and matches inline, including the favorite flags on a full search.
    await expectParity('chocolate', viewerId: favoritingUser);
    await expectParity(
      'chocolate',
      viewerId: favoritingUser,
      favoritesOnly: true,
    );
  });

  test('concurrent searches all return the inline result', () async {
    final want = await inline.search(compile('cake'), page: 1, limit: 20);
    final wantIds = want.items.map((c) => c.id).toList();
    final results = await Future.wait([
      for (var i = 0; i < 20; i++)
        isolate.search(compile('cake'), page: 1, limit: 20),
    ]);
    for (final got in results) {
      expect(got.total, want.total);
      expect(got.items.map((c) => c.id).toList(), wantIds);
    }
  });

  test('a query that errors in SQLite propagates instead of hanging', () async {
    // A crafted (never compiler-produced) match referencing a missing FTS
    // column — FTS5 rejects it. The worker must report the failure, not hang.
    const bad = CompiledSearch(ftsMatch: 'nosuchcolumn:foo');
    await expectLater(
      isolate.search(bad, page: 1, limit: 10),
      throwsA(isA<StateError>()),
    );
    // The inline path errors on the same input too (a different type; both
    // throw).
    await expectLater(
      inline.search(bad, page: 1, limit: 10),
      throwsA(anything),
    );
    // The service is still usable after an error (worker stayed warm).
    await expectParity('chocolate');
  });

  test('a disposed service rejects further searches', () async {
    final temp = await IsolateSearchService.spawn(
      dbPath: '${tempDir.path}/salt.db',
      count: 1,
    );
    await temp.dispose();
    // The disposed guard throws synchronously, so match on the closure.
    expect(
      () => temp.search(compile('chocolate'), page: 1, limit: 10),
      throwsA(isA<StateError>()),
    );
  });
}
