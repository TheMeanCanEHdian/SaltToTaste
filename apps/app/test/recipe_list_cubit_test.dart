import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/features/recipes/list/recipe_list_cubit.dart';
import 'package:salt_shared/salt_shared.dart';

import 'support/corpus.dart';

/// A Dio adapter serving canned list/favorite responses, so the cubit runs
/// against the real RecipeRepository (and its real favoriteChanges wiring)
/// with no server.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.cards);

  List<RecipeCard> cards;

  /// Favorite calls seen, as `(idOrSlug, favorite)`.
  final List<(String, bool)> favoriteCalls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path.contains('/favorite')) {
      final id = RegExp(
        r'/recipes/([^/]+)/favorite',
      ).firstMatch(path)!.group(1)!;
      favoriteCalls.add((Uri.decodeComponent(id), options.method == 'PUT'));
      return ResponseBody.fromString('{}', 200, headers: _jsonHeaders);
    }
    if (path.contains('/api/v1/recipes')) {
      // Honor page/limit like the real server, so paging math is testable.
      final page = int.parse(options.uri.queryParameters['page'] ?? '1');
      final limit = int.parse(
        options.uri.queryParameters['limit'] ?? '${RecipeListCubit.pageSize}',
      );
      final start = (page - 1) * limit;
      final slice = start >= cards.length
          ? const <RecipeCard>[]
          : cards.sublist(
              start,
              start + limit > cards.length ? cards.length : start + limit,
            );
      return ResponseBody.fromString(
        jsonEncode({
          'items': [for (final card in slice) card.toMap()],
          'total': cards.length,
          'page': page,
          'limit': limit,
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    return ResponseBody.fromString('{}', 404, headers: _jsonHeaders);
  }

  static final _jsonHeaders = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };

  @override
  void close({bool force = false}) {}
}

void main() {
  group('RecipeListCubit favorite reconciliation', skip: skipIfNoCorpus, () {
    late _FakeAdapter adapter;
    late RecipeRepository repository;

    /// Cards built from real corpus recipes — the grid's own projection.
    List<RecipeCard> corpusCards() => [
      for (final name in [
        '0857-rich-chocolate-bundt-cake.yaml',
        '0879-easy-caramel-cake.yaml',
      ])
        () {
          final recipe = loadCorpusRecipe(name);
          return RecipeCard(
            id: recipe.id,
            slug: recipe.slug,
            title: recipe.title,
            servingsText: recipe.servings,
            favorite: true,
          );
        }(),
    ];

    setUp(() {
      adapter = _FakeAdapter(corpusCards());
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = adapter;
      repository = RecipeRepository(dio: dio);
    });

    tearDown(() => repository.dispose());

    test('a favorites grid drops a card unfavorited elsewhere', () async {
      // The real sequence: /favorites is pushed over, the detail page
      // unfavorites, and this grid — still alive underneath — must not come
      // back showing the recipe and a stale count.
      final cubit = RecipeListCubit(repository, favoritesOnly: true);
      addTearDown(cubit.close);
      await cubit.load();
      final loaded = cubit.state as RecipeListLoaded;
      expect(loaded.items, hasLength(2));
      expect(loaded.total, 2);
      final gone = loaded.items.first;

      // What the detail page does — by slug, which is what it routes on.
      await repository.setFavorite(gone.slug, favorite: false);
      await Future<void>.delayed(Duration.zero);

      final after = cubit.state as RecipeListLoaded;
      expect(
        after.items.map((card) => card.id),
        isNot(contains(gone.id)),
        reason: 'the unfavorited recipe must leave the favorites grid',
      );
      expect(after.total, 1, reason: 'the eyebrow count must follow');
    });

    test('a library grid keeps the card and clears its heart', () async {
      final cubit = RecipeListCubit(repository);
      addTearDown(cubit.close);
      await cubit.load();
      final target = (cubit.state as RecipeListLoaded).items.first;

      await repository.setFavorite(target.id, favorite: false);
      await Future<void>.delayed(Duration.zero);

      final after = cubit.state as RecipeListLoaded;
      expect(after.items, hasLength(2), reason: 'nothing is removed here');
      expect(
        after.items.firstWhere((card) => card.id == target.id).favorite,
        isFalse,
        reason: 'the heart badge must clear',
      );
      expect(after.total, 2);
    });

    test('re-favoriting reloads a favorites grid that lost the card', () async {
      final cubit = RecipeListCubit(repository, favoritesOnly: true);
      addTearDown(cubit.close);
      await cubit.load();
      final target = (cubit.state as RecipeListLoaded).items.first;

      await repository.setFavorite(target.slug, favorite: false);
      await Future<void>.delayed(Duration.zero);
      expect((cubit.state as RecipeListLoaded).items, hasLength(1));

      // Favoriting it again: the card is not in the list and the cubit has no
      // copy of it, so only the server can restore it. That reload is async —
      // wait for the state it lands in rather than for a fixed number of
      // microtasks.
      await repository.setFavorite(target.slug, favorite: true);
      final reloaded = await cubit.stream.firstWhere(
        (state) => state is RecipeListLoaded,
      );

      expect(
        (reloaded as RecipeListLoaded).items,
        hasLength(2),
        reason: 'a re-favorited recipe must come back to the favorites grid',
      );
    });

    test('a closed cubit stops listening', () async {
      final cubit = RecipeListCubit(repository, favoritesOnly: true);
      await cubit.load();
      await cubit.close();
      // Emitting after close would throw; a leaked subscription would also
      // outlive every visited grid.
      await repository.setFavorite('anything', favorite: false);
      await Future<void>.delayed(Duration.zero);
    });

    test('unfavoriting then scrolling skips no recipe (review B17)', () async {
      // 50 real corpus recipes as favorites: one full page (48) plus two.
      final many = [
        for (final recipe in loadAllCorpusRecipes().take(50))
          RecipeCard(
            id: recipe.id,
            slug: recipe.slug,
            title: recipe.title,
            servingsText: recipe.servings,
            favorite: true,
          ),
      ];
      adapter.cards = many;
      final cubit = RecipeListCubit(repository, favoritesOnly: true);
      addTearDown(cubit.close);
      await cubit.load();
      expect((cubit.state as RecipeListLoaded).items, hasLength(48));

      // Unfavorite one from the "detail page": the card leaves this grid
      // AND the server-side list shrinks by one.
      final gone = many.first;
      adapter.cards = many.sublist(1);
      await repository.setFavorite(gone.slug, favorite: false);
      await Future<void>.delayed(Duration.zero);
      expect((cubit.state as RecipeListLoaded).items, hasLength(47));

      // Scroll to the end (the grid calls loadMore per scroll notch).
      var guard = 0;
      while ((cubit.state as RecipeListLoaded).hasMore && guard < 5) {
        await cubit.loadMore();
        guard += 1;
      }
      final after = cubit.state as RecipeListLoaded;
      // A fixed page counter fetched server rows 49.. of the shrunken list,
      // and the recipe that shifted into row 48 fell between the pages —
      // the grid completed with 48 of 49 favorites shown.
      expect(after.items, hasLength(49));
      expect(
        after.items.map((card) => card.id),
        containsAll(adapter.cards.map((card) => card.id)),
        reason: 'every remaining favorite must be shown — none skipped',
      );
    });
  });
}
