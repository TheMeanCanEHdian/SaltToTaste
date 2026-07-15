import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/recipe_repository.dart';

/// State of the paged recipe grid.
sealed class RecipeListState {
  const RecipeListState();
}

final class RecipeListLoading extends RecipeListState {
  const RecipeListLoading();
}

final class RecipeListError extends RecipeListState {
  const RecipeListError(this.message);

  final String message;
}

final class RecipeListLoaded extends RecipeListState {
  const RecipeListLoaded({
    required this.items,
    required this.total,
    required this.loadingMore,
    required this.exhausted,
    this.loadMoreFailed = false,
  });

  final List<RecipeCard> items;
  final int total;

  /// Whether the next page is currently being fetched.
  final bool loadingMore;

  /// True once a page returned fewer items than requested — there is no more
  /// to fetch even if [total] disagrees (a stale count must not loop forever).
  final bool exhausted;

  /// True when the last [RecipeListCubit.loadMore] failed; the grid shows a
  /// retry affordance rather than silently stalling.
  final bool loadMoreFailed;

  bool get hasMore => !exhausted && items.length < total;

  RecipeListLoaded copyWith({
    bool? loadingMore,
    bool? loadMoreFailed,
  }) =>
      RecipeListLoaded(
        items: items,
        total: total,
        exhausted: exhausted,
        loadingMore: loadingMore ?? this.loadingMore,
        loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
      );
}

/// Loads and pages the recipe grid — the whole library, search results
/// when constructed with a [query], or the caller's favorites when
/// [favoritesOnly] is set.
class RecipeListCubit extends Cubit<RecipeListState> {
  RecipeListCubit(this._repository, {this.query, this.favoritesOnly = false})
      : super(const RecipeListLoading());

  static const int pageSize = 48;

  final RecipeRepository _repository;

  /// Search-DSL query, or null for the plain library listing.
  final String? query;

  /// Restrict to the signed-in user's favorites.
  final bool favoritesOnly;
  int _nextPage = 1;

  Future<void> load() async {
    emit(const RecipeListLoading());
    _nextPage = 1;
    try {
      final page = await _repository.listRecipes(
        page: 1,
        limit: pageSize,
        query: query,
        favoritesOnly: favoritesOnly,
      );
      if (isClosed) {
        return;
      }
      _nextPage = 2;
      emit(RecipeListLoaded(
        items: page.items,
        total: page.total,
        loadingMore: false,
        exhausted: page.items.length < pageSize,
      ));
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(RecipeListError(exception.message));
    }
  }

  Future<void> loadMore() async {
    final current = state;
    if (current is! RecipeListLoaded ||
        current.loadingMore ||
        current.loadMoreFailed ||
        !current.hasMore) {
      return;
    }
    emit(current.copyWith(loadingMore: true));
    try {
      final page = await _repository.listRecipes(
        page: _nextPage,
        limit: pageSize,
        query: query,
        favoritesOnly: favoritesOnly,
      );
      if (isClosed) {
        return;
      }
      _nextPage += 1;
      // Merge into the LATEST state, not the pre-await snapshot — an
      // optimistic unfavorite that landed while this page was in flight
      // must survive. New items are deduped by id for the same reason.
      final base = state;
      final existing = base is RecipeListLoaded ? base.items : current.items;
      final seen = {for (final item in existing) item.id};
      final items = [
        ...existing,
        for (final item in page.items)
          if (!seen.contains(item.id)) item,
      ];
      emit(RecipeListLoaded(
        items: items,
        total: page.total,
        loadingMore: false,
        // Stop when a short (or empty) page arrives, regardless of `total`.
        exhausted: page.items.length < pageSize,
      ));
    } on RepositoryException {
      if (isClosed) {
        return;
      }
      final latest = state;
      if (latest is RecipeListLoaded) {
        emit(latest.copyWith(loadingMore: false, loadMoreFailed: true));
      }
    }
  }

  /// Clears a load-more failure so the next scroll (or a retry tap) fetches
  /// the same page again.
  void retryLoadMore() {
    final current = state;
    if (current is RecipeListLoaded && current.loadMoreFailed) {
      emit(current.copyWith(loadMoreFailed: false));
      loadMore();
    }
  }

  /// Removes the caller's favorite mark on [card] (the tile heart's tap),
  /// optimistically: on a favorites-only grid the card disappears, elsewhere
  /// its heart badge does. Reverted if the server rejects it.
  Future<void> unfavorite(RecipeCard card) async {
    final current = state;
    if (current is! RecipeListLoaded) {
      return;
    }
    final optimistic = [
      for (final item in current.items)
        if (item.id != card.id)
          item
        else if (!favoritesOnly)
          item.copyWith(favorite: false),
    ];
    emit(RecipeListLoaded(
      items: optimistic,
      total: favoritesOnly ? current.total - 1 : current.total,
      loadingMore: current.loadingMore,
      exhausted: current.exhausted,
      loadMoreFailed: current.loadMoreFailed,
    ));
    try {
      await _repository.setFavorite(card.id, favorite: false);
    } on RepositoryException {
      if (isClosed) {
        return;
      }
      // Revert just this card against the LATEST state (a page may have
      // loaded meanwhile); a favorites-only grid reloads to restore it.
      if (favoritesOnly) {
        await load();
        return;
      }
      final latest = state;
      if (latest is RecipeListLoaded) {
        emit(RecipeListLoaded(
          items: [
            for (final item in latest.items)
              if (item.id == card.id) item.copyWith(favorite: true) else item,
          ],
          total: latest.total,
          loadingMore: latest.loadingMore,
          exhausted: latest.exhausted,
          loadMoreFailed: latest.loadMoreFailed,
        ));
      }
    }
  }
}
