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

/// Loads and pages the recipe grid.
class RecipeListCubit extends Cubit<RecipeListState> {
  RecipeListCubit(this._repository) : super(const RecipeListLoading());

  static const int pageSize = 48;

  final RecipeRepository _repository;
  int _nextPage = 1;

  Future<void> load() async {
    emit(const RecipeListLoading());
    _nextPage = 1;
    try {
      final page = await _repository.listRecipes(page: 1, limit: pageSize);
      _nextPage = 2;
      emit(RecipeListLoaded(
        items: page.items,
        total: page.total,
        loadingMore: false,
        exhausted: page.items.length < pageSize,
      ));
    } on RepositoryException catch (exception) {
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
      );
      _nextPage += 1;
      final items = [...current.items, ...page.items];
      emit(RecipeListLoaded(
        items: items,
        total: page.total,
        loadingMore: false,
        // Stop when a short (or empty) page arrives, regardless of `total`.
        exhausted: page.items.length < pageSize,
      ));
    } on RepositoryException {
      emit(current.copyWith(loadingMore: false, loadMoreFailed: true));
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
}
