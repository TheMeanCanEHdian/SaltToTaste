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
  });

  final List<RecipeCard> items;
  final int total;

  /// Whether the next page is currently being fetched.
  final bool loadingMore;

  bool get hasMore => items.length < total;
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
      ));
    } on RepositoryException catch (exception) {
      emit(RecipeListError(exception.message));
    }
  }

  Future<void> loadMore() async {
    final current = state;
    if (current is! RecipeListLoaded ||
        current.loadingMore ||
        !current.hasMore) {
      return;
    }
    emit(RecipeListLoaded(
      items: current.items,
      total: current.total,
      loadingMore: true,
    ));
    try {
      final page = await _repository.listRecipes(
        page: _nextPage,
        limit: pageSize,
      );
      _nextPage += 1;
      emit(RecipeListLoaded(
        items: [...current.items, ...page.items],
        total: page.total,
        loadingMore: false,
      ));
    } on RepositoryException {
      // Keep what we have; the user can scroll again to retry.
      emit(RecipeListLoaded(
        items: current.items,
        total: current.total,
        loadingMore: false,
      ));
    }
  }
}
