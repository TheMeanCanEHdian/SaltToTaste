import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;

/// State of one recipe's nutrition panel + review sheet.
final class NutritionState {
  const NutritionState({
    this.loading = true,
    this.nutrition,
    this.matches,
    this.computing = false,
    this.savingBasis = false,
    this.overridingPosition,
    this.error,
  });

  final bool loading;

  /// Null only while loading or after a failed initial load.
  final RecipeNutrition? nutrition;

  /// Loaded lazily when the review sheet opens.
  final List<IngredientMatch>? matches;

  /// A compute request is in flight (can take ~20s cold).
  final bool computing;
  final bool savingBasis;

  /// Position of the row whose override is in flight, or null.
  final int? overridingPosition;

  /// Last failure message (surfaced inline; cleared on the next action).
  final String? error;

  NutritionState copyWith({
    bool? loading,
    RecipeNutrition? nutrition,
    List<IngredientMatch>? matches,
    bool clearMatches = false,
    bool? computing,
    bool? savingBasis,
    int? overridingPosition,
    bool clearOverriding = false,
    String? error,
    bool clearError = false,
  }) =>
      NutritionState(
        loading: loading ?? this.loading,
        nutrition: nutrition ?? this.nutrition,
        matches: clearMatches ? null : (matches ?? this.matches),
        computing: computing ?? this.computing,
        savingBasis: savingBasis ?? this.savingBasis,
        overridingPosition: clearOverriding
            ? null
            : (overridingPosition ?? this.overridingPosition),
        error: clearError ? null : (error ?? this.error),
      );
}

/// Drives one recipe's label: load, compute, serving basis, and the review
/// sheet's match overrides.
class NutritionCubit extends Cubit<NutritionState> {
  NutritionCubit(this._repository, this.idOrSlug)
      : super(const NutritionState());

  final NutritionRepository _repository;

  /// The recipe this cubit serves.
  final String idOrSlug;

  /// Cancels an in-flight compute when the page goes away — otherwise the
  /// browser connection stays occupied for up to five minutes.
  CancelToken? _computeToken;

  // The `override(...)` action method shadows dart:core's @override
  // annotation inside this class body.
  // ignore: annotate_overrides
  Future<void> close() {
    _computeToken?.cancel('page disposed');
    return super.close();
  }

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final nutrition = await _repository.nutrition(idOrSlug);
      if (isClosed) {
        return;
      }
      emit(state.copyWith(loading: false, nutrition: nutrition));
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(loading: false, error: exception.message));
    }
  }

  /// Runs the full match+compute (admin) — slow-ish the first time.
  Future<void> compute() async {
    if (state.computing) {
      return;
    }
    emit(state.copyWith(computing: true, clearError: true));
    final token = _computeToken = CancelToken();
    try {
      final nutrition =
          await _repository.compute(idOrSlug, cancelToken: token);
      if (isClosed) {
        return;
      }
      emit(state.copyWith(
        computing: false,
        nutrition: nutrition,
        // The server re-matched every line: the cached sheet rows are
        // stale and must reload on next open.
        clearMatches: true,
      ));
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(computing: false, error: exception.message));
    } finally {
      if (identical(_computeToken, token)) {
        _computeToken = null;
      }
    }
  }

  /// Changes the per-serving divisor (instant server-side).
  Future<void> setServingBasis(int basis) async {
    if (state.savingBasis) {
      return;
    }
    emit(state.copyWith(savingBasis: true, clearError: true));
    try {
      final nutrition = await _repository.setServingBasis(idOrSlug, basis);
      if (isClosed) {
        return;
      }
      emit(state.copyWith(savingBasis: false, nutrition: nutrition));
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(savingBasis: false, error: exception.message));
    }
  }

  /// Loads the review sheet's rows (cached after first open; [force]
  /// refetches — the sheet's retry path).
  Future<void> loadMatches({bool force = false}) async {
    if (!force && state.matches != null) {
      return;
    }
    // A stale error from an earlier action must not headline the sheet.
    emit(state.copyWith(clearError: true));
    try {
      final matches = await _repository.matches(idOrSlug);
      if (isClosed) {
        return;
      }
      emit(state.copyWith(matches: matches));
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(error: exception.message));
    }
  }

  /// Applies one row override, then refreshes the label totals.
  Future<void> override(
    int position, {
    int? fdcId,
    double? grams,
    bool? confirmed,
    bool? skipped,
  }) async {
    if (state.overridingPosition != null) {
      return;
    }
    emit(state.copyWith(overridingPosition: position, clearError: true));
    final List<IngredientMatch> matches;
    try {
      matches = await _repository.overrideMatch(
        idOrSlug,
        position,
        fdcId: fdcId,
        grams: grams,
        confirmed: confirmed,
        skipped: skipped,
      );
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(clearOverriding: true, error: exception.message));
      return;
    }
    if (isClosed) {
      return;
    }
    // The PUT persisted: show its fresh match list even if the label
    // refresh below fails — discarding it would render rows the server
    // no longer has.
    emit(state.copyWith(matches: matches, clearOverriding: true));
    try {
      final nutrition = await _repository.nutrition(idOrSlug);
      if (isClosed) {
        return;
      }
      emit(state.copyWith(nutrition: nutrition));
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(
        error: 'Saved, but refreshing the label failed: '
            '${exception.message}',
      ));
    }
  }
}
