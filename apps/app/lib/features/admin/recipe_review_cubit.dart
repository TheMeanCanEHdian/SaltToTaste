import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/recipe_repository.dart';

/// State of the admin recipe-review screen.
sealed class RecipeReviewState {
  const RecipeReviewState();
}

final class RecipeReviewLoading extends RecipeReviewState {
  const RecipeReviewLoading();
}

final class RecipeReviewError extends RecipeReviewState {
  const RecipeReviewError(this.message);

  final String message;
}

final class RecipeReviewLoaded extends RecipeReviewState {
  const RecipeReviewLoaded({
    required this.total,
    required this.categories,
    required this.items,
    required this.issue,
    required this.loadingMore,
    required this.exhausted,
  });

  /// Whole-library count of recipes with any issue (stable across filters).
  final int total;
  final List<RecipeReviewCategory> categories;
  final List<RecipeReviewItem> items;

  /// The active category filter, or null for "all issues".
  final String? issue;
  final bool loadingMore;
  final bool exhausted;

  /// Recipes matching the current filter (a category count, or [total]).
  int get filteredTotal => issue == null
      ? total
      : categories
            .firstWhere(
              (c) => c.id == issue,
              orElse: () => const RecipeReviewCategory(
                id: '',
                label: '',
                description: '',
                count: 0,
              ),
            )
            .count;

  bool get hasMore => !exhausted && items.length < filteredTotal;

  RecipeReviewLoaded copyWith({bool? loadingMore}) => RecipeReviewLoaded(
    total: total,
    categories: categories,
    items: items,
    issue: issue,
    exhausted: exhausted,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Loads the recipe data-quality report and pages its flagged list.
class RecipeReviewCubit extends Cubit<RecipeReviewState> {
  RecipeReviewCubit(this._repository) : super(const RecipeReviewLoading());

  static const int pageSize = 50;

  final RecipeRepository _repository;
  int _nextPage = 1;

  /// (Re)loads from the first page under the [issue] filter (null = all).
  Future<void> load({String? issue}) async {
    emit(const RecipeReviewLoading());
    _nextPage = 1;
    try {
      final report = await _repository.getRecipeReview(
        page: 1,
        limit: pageSize,
        issue: issue,
      );
      if (isClosed) {
        return;
      }
      _nextPage = 2;
      emit(
        RecipeReviewLoaded(
          total: report.total,
          categories: report.categories,
          items: report.items,
          issue: issue,
          loadingMore: false,
          exhausted: report.items.length < pageSize,
        ),
      );
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(RecipeReviewError(exception.message));
    }
  }

  /// Switches the category filter (null clears it). Unlike [load] this keeps the
  /// chrome (chips + counts) on screen and swaps only the list, so changing a
  /// filter updates values in place instead of flashing the full-page spinner.
  Future<void> filter(String? issue) async {
    final current = state;
    if (current is! RecipeReviewLoaded || current.issue == issue) {
      return;
    }
    // Highlight the newly-selected chip immediately; keep the list visible.
    emit(
      RecipeReviewLoaded(
        total: current.total,
        categories: current.categories,
        items: current.items,
        issue: issue,
        loadingMore: false,
        exhausted: current.exhausted,
      ),
    );
    _nextPage = 1;
    try {
      final report = await _repository.getRecipeReview(
        page: 1,
        limit: pageSize,
        issue: issue,
      );
      if (isClosed) {
        return;
      }
      _nextPage = 2;
      emit(
        RecipeReviewLoaded(
          total: report.total,
          categories: report.categories,
          items: report.items,
          issue: issue,
          loadingMore: false,
          exhausted: report.items.length < pageSize,
        ),
      );
    } on RepositoryException {
      // The filter didn't apply. Revert to the pre-filter state so the chip
      // highlight matches the list still on screen — leaving the new chip
      // selected over the old items shows data that contradicts the filter.
      if (!isClosed) {
        emit(current);
      }
    }
  }

  Future<void> loadMore() async {
    final current = state;
    if (current is! RecipeReviewLoaded ||
        current.loadingMore ||
        !current.hasMore) {
      return;
    }
    emit(current.copyWith(loadingMore: true));
    try {
      final report = await _repository.getRecipeReview(
        page: _nextPage,
        limit: pageSize,
        issue: current.issue,
      );
      if (isClosed) {
        return;
      }
      _nextPage += 1;
      final seen = {for (final item in current.items) item.id};
      emit(
        RecipeReviewLoaded(
          total: report.total,
          categories: report.categories,
          items: [
            ...current.items,
            for (final item in report.items)
              if (!seen.contains(item.id)) item,
          ],
          issue: current.issue,
          loadingMore: false,
          exhausted: report.items.length < pageSize,
        ),
      );
    } on RepositoryException {
      if (isClosed) {
        return;
      }
      final latest = state;
      if (latest is RecipeReviewLoaded) {
        emit(latest.copyWith(loadingMore: false));
      }
    }
  }
}
