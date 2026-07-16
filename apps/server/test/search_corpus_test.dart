import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/recipe_handlers.dart';
import 'package:salt_server/src/search/fts_compiler.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';

/// The P4 gate: DSL queries against the whole real corpus, with expected
/// counts derived independently by scanning the recipe documents in Dart
/// (word-boundary matching that mirrors what the porter tokenizer does for
/// the specific words chosen — each test word is its own stem).
void main() {
  // Corpus-backed integration tests: skip (not fail) when the ATK corpus is
  // absent — e.g. CI — so `dart test` stays green. Set SALT_CORPUS_DIR to run.
  if (!corpusAvailable) {
    test('corpus-backed tests (skipped: corpus absent)', () {},
        skip: 'ATK corpus not present; set SALT_CORPUS_DIR');
    return;
  }
  late Directory tempDir;
  late SaltDatabase db;
  final decodedByName = <String, Recipe>{};

  ({List<RecipeCard> items, int total}) search(String query) {
    final parsed = parseSearchQuery(query);
    expect(parsed.errors, isEmpty, reason: 'parse errors for "$query"');
    return db.searchCards(compileSearch(parsed.root!), page: 1, limit: 100);
  }

  setUpAll(() {
    expect(corpusAvailable, isTrue, reason: 'corpus not found: $corpusRoot');
    tempDir = Directory.systemTemp.createTempSync('salt_search_corpus');
    db = SaltDatabase.open('${tempDir.path}/salt.db')
      ..upsertSource(slug: 'atk', name: 'ATK corpus', type: 'epub');
    final files = Directory(corpusRecipesDir)
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.yaml'));
    for (final file in files) {
      final recipe =
          RecipeYamlCodec.decode(file.readAsStringSync()).recipe;
      decodedByName[file.uri.pathSegments.last] = recipe;
      db.upsertRecipe(
        recipe,
        sourceSlug: 'atk',
        contentHash: contentHashOf(recipe),
      );
    }
    expect(decodedByName.length, 1198);
  });

  tearDownAll(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  /// Recipes whose [text] (per recipe) contains [word] with word boundaries,
  /// tolerating a plural 's' (mirroring the porter stem for these words).
  int expectedCount(bool Function(Recipe) predicate) =>
      decodedByName.values.where(predicate).length;

  bool hasWord(String? text, String word) {
    if (text == null) {
      return false;
    }
    return RegExp(
      '\\b${RegExp.escape(word)}(s|es)?\\b',
      caseSensitive: false,
    ).hasMatch(text);
  }

  String ingredientsText(Recipe recipe) => [
        for (final group in recipe.ingredients)
          for (final line in group.items) line.raw,
      ].join('\n');

  String directionsText(Recipe recipe) =>
      [for (final step in recipe.steps) step.text].join('\n');

  group('P4 gate: DSL results match grep-derived corpus counts', () {
    test('title:chicken and ingredient:ginger', () {
      final expected = expectedCount(
        (recipe) =>
            hasWord(recipe.title, 'chicken') &&
            hasWord(ingredientsText(recipe), 'ginger'),
      );
      expect(expected, greaterThan(0), reason: 'sanity: corpus has matches');
      expect(search('title:chicken and ingredient:ginger').total, expected);
    });

    test('tag:dessert or title:cake', () {
      final expected = expectedCount(
        (recipe) =>
            recipe.tags.contains('dessert') || hasWord(recipe.title, 'cake'),
      );
      expect(expected, greaterThan(0));
      expect(search('tag:dessert or title:cake').total, expected);
    });

    test('tag:dessert alone matches the corpus dessert count', () {
      final expected =
          expectedCount((recipe) => recipe.tags.contains('dessert'));
      expect(expected, 214, reason: 'known corpus dessert count');
      expect(search('tag:dessert').total, expected);
    });

    test('direction:"dutch oven" (phrase)', () {
      final expected = expectedCount(
        (recipe) => recipe.steps.any(
          (step) => step.text.toLowerCase().contains('dutch oven'),
        ),
      );
      expect(expected, greaterThan(0));
      expect(search('direction:"dutch oven"').total, expected);
    });

    test('general multi-word: sweet potato (AND semantics)', () {
      // Both words must appear somewhere in the indexed document.
      String indexed(Recipe recipe) => [
            recipe.title,
            recipe.category ?? '',
            recipe.tags.join(' '),
            ingredientsText(recipe),
            directionsText(recipe),
            recipe.notes ?? '',
            recipe.background ?? '',
            recipe.prepNotes ?? '',
          ].join('\n');
      final expected = expectedCount(
        (recipe) =>
            hasWord(indexed(recipe), 'sweet') &&
            hasWord(indexed(recipe), 'potato'),
      );
      expect(expected, greaterThan(0));
      // Porter stemming matches more surface forms ('sweeter', 'sweetest')
      // than the exact-word scan, so FTS returns at least the exact count.
      final total = search('sweet potato').total;
      expect(total, greaterThanOrEqualTo(expected));
      expect(total, lessThan(expected + 20),
          reason: 'stemming should only add a handful of variants');
    });

    test('general search reaches background prose', () {
      // 'bloomed' appears only in background text for some recipes (the P1
      // review's FTS-column fix) — a general search must find them.
      final expected = expectedCount(
        (recipe) =>
            hasWord(recipe.background, 'bloomed') ||
            hasWord(recipe.title, 'bloomed') ||
            hasWord(recipe.prepNotes, 'bloomed') ||
            hasWord(ingredientsText(recipe), 'bloomed') ||
            hasWord(directionsText(recipe), 'bloomed') ||
            hasWord(recipe.notes, 'bloomed'),
      );
      expect(expected, greaterThan(0));
      // 'bloomed' porter-stems to 'bloom', which also matches 'blooms',
      // 'blooming', and bare 'bloom' — so FTS may return MORE than the
      // exact-word count, never fewer.
      expect(
        search('bloomed').total,
        greaterThanOrEqualTo(expected),
      );
    });

    test('calories filter matches nothing until nutrition lands', () {
      expect(search('calories:<400').total, 0);
      expect(search('calories:<400 and tag:dessert').total, 0);
    });

    test('a parse error surfaces as validation', () {
      final parsed = parseSearchQuery('title:');
      expect(parsed.errors, isNotEmpty);
      // The handler path is the actual contract: broken queries must become
      // 422s, never silent fallbacks to the full listing.
      expect(
        () => listRecipes(db, page: 1, limit: 24, query: 'title:'),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('Invalid search'),
          ),
        ),
      );
    });

    test('an oversized query is rejected before parsing', () {
      expect(
        () => listRecipes(
          db,
          page: 1,
          limit: 24,
          query: 'chicken ' * 100,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('hostile MATCH syntax cannot crash the query', () {
      // Compiled as quoted literals, these must run (returning few or no
      // rows) rather than throwing an FTS syntax error.
      for (final hostile in [
        'title:"NEAR(a b)"',
        '"AND OR NOT"',
        'col:*star*',
      ]) {
        final parsed = parseSearchQuery(hostile);
        expect(parsed.errors, isEmpty, reason: hostile);
        final compiled = compileSearch(parsed.root!);
        expect(
          () => db.searchCards(compiled, page: 1, limit: 10),
          returnsNormally,
          reason: hostile,
        );
      }
    });

    test('tags listing counts match the corpus', () {
      final tags = db.listTags();
      final dessert = tags.singleWhere((tag) => tag.name == 'dessert');
      expect(dessert.count, 214);
      expect(dessert.icon, isNull);
    });

    test('tag style upsert round-trips', () {
      db.upsertTagStyle('dessert',
          icon: 'cake', color: '#7d1420', bgColor: '#f6e4e4');
      final dessert =
          db.listTags().singleWhere((tag) => tag.name == 'dessert');
      expect(dessert.icon, 'cake');
      expect(dessert.color, '#7d1420');
      expect(dessert.bgColor, '#f6e4e4');
    });

    test('calories under OR is rejected end-to-end', () {
      final parsed = parseSearchQuery('title:cake or calories:<300');
      expect(parsed.errors, isEmpty);
      expect(
        () => compileSearch(parsed.root!),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
