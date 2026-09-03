import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;

/// An offer to push a decision just made on one line out to every other
/// recipe's unreviewed line of the same ingredient item: what to resend
/// (the pick, or the confirm) and how many recipes it would change.
typedef ApplyOffer = ({
  int position,
  String label,
  int? fdcId,
  bool confirmed,
  double? grams,
  int others,
});

/// The receipt of an apply-to-all, shown in place of the offer.
typedef ApplyReceipt = ({int position, int recipes, int lines, int failed});

/// The parsed ingredient item as a person would name it: parentheticals
/// dropped ("(1 1/2 sticks) unsalted butter" → "unsalted butter"), trimmed;
/// null when nothing is left.
String? itemLabel(String? item) {
  if (item == null) {
    return null;
  }
  final cleaned = item
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned.isEmpty ? null : cleaned;
}

/// State of one recipe's nutrition panel + review sheet.
final class NutritionState {
  const NutritionState({
    this.loading = true,
    this.nutrition,
    this.matches,
    this.computing = false,
    this.savingBasis = false,
    this.overridingPosition,
    this.offer,
    this.applied,
    this.applying = false,
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

  /// A pending apply-to-all offer for a line just decided, or null.
  final ApplyOffer? offer;

  /// The receipt of the last apply-to-all, until dismissed.
  final ApplyReceipt? applied;

  /// An apply-to-all request is in flight.
  final bool applying;

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
    ApplyOffer? offer,
    bool clearOffer = false,
    ApplyReceipt? applied,
    bool clearApplied = false,
    bool? applying,
    String? error,
    bool clearError = false,
  }) => NutritionState(
    loading: loading ?? this.loading,
    nutrition: nutrition ?? this.nutrition,
    matches: clearMatches ? null : (matches ?? this.matches),
    computing: computing ?? this.computing,
    savingBasis: savingBasis ?? this.savingBasis,
    overridingPosition: clearOverriding
        ? null
        : (overridingPosition ?? this.overridingPosition),
    offer: clearOffer ? null : (offer ?? this.offer),
    applied: clearApplied ? null : (applied ?? this.applied),
    applying: applying ?? this.applying,
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

  /// The compute job currently being polled, so load()'s re-attach and a
  /// fresh compute() don't spin up two poll loops for the same job.
  int? _watchingJob;

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final nutrition = await _repository.nutrition(idOrSlug);
      if (isClosed) {
        return;
      }
      emit(state.copyWith(loading: false, nutrition: nutrition));
      // Re-attach to a compute still running server-side — e.g. one started
      // before the page was navigated away and reopened. Without this the
      // page would show an enabled Compute button over a running job.
      final jobId = nutrition.computingJobId;
      if (jobId != null) {
        unawaited(_watchJob(jobId));
      }
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(loading: false, error: exception.message));
    }
  }

  /// Starts a background match+compute (admin) and polls it to completion.
  /// The POST returns immediately with a job id, so navigating away just
  /// stops the poll — the server finishes regardless and the fresh label is
  /// picked up on the next load (no erroring-while-succeeding).
  Future<void> compute() async {
    if (state.computing) {
      return;
    }
    emit(state.copyWith(computing: true, clearError: true));
    final int jobId;
    try {
      jobId = await _repository.startCompute(idOrSlug);
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(computing: false, error: exception.message));
      return;
    }
    if (isClosed) {
      return;
    }
    await _watchJob(jobId);
  }

  /// Polls [jobId] to completion, then reloads the label. Shared by compute()
  /// and load()'s re-attach; a second call for the same job is a no-op.
  Future<void> _watchJob(int jobId) async {
    if (_watchingJob == jobId) {
      return;
    }
    _watchingJob = jobId;
    emit(state.copyWith(computing: true, clearError: true));
    var failures = 0;
    try {
      while (true) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (isClosed) {
          return;
        }
        final NutritionJob job;
        try {
          job = await _repository.job(jobId);
          failures = 0;
        } on RepositoryException catch (exception) {
          // A transient blip: the job runs on the server regardless. Give up
          // only after several consecutive failures (e.g. session expired).
          failures += 1;
          if (failures < 8) {
            continue;
          }
          if (isClosed) {
            return;
          }
          emit(
            state.copyWith(
              computing: false,
              error:
                  'Lost track of the compute (${exception.message}). '
                  'Reload to check.',
            ),
          );
          return;
        }
        if (isClosed) {
          return;
        }
        if (job.status == 'running') {
          continue;
        }
        if (job.status == 'failed') {
          emit(
            state.copyWith(
              computing: false,
              error: job.log.isNotEmpty ? job.log.first : 'Compute failed.',
            ),
          );
          return;
        }
        // Done: pull the fresh label. Re-matching invalidated the cached
        // review-sheet rows, so drop them.
        try {
          final nutrition = await _repository.nutrition(idOrSlug);
          if (isClosed) {
            return;
          }
          emit(
            state.copyWith(
              computing: false,
              nutrition: nutrition,
              clearMatches: true,
            ),
          );
        } on RepositoryException catch (exception) {
          if (isClosed) {
            return;
          }
          emit(state.copyWith(computing: false, error: exception.message));
        }
        return;
      }
    } finally {
      if (_watchingJob == jobId) {
        _watchingJob = null;
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
    final MatchOverrideResult result;
    try {
      result = await _repository.overrideMatch(
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
    final matches = result.matches;
    // A pick or a confirm is a decision about the ingredient; if other
    // recipes' unreviewed lines of that item are not on this food yet, offer
    // to push it out. The count is the server's, fresh for the NEW food —
    // which is why the offer can only appear after the decision has landed.
    // A skip or a grams-only change is not a decision to broadcast.
    final decided = fdcId != null || confirmed == true;
    IngredientMatch? row;
    for (final m in matches) {
      if (m.position == position) {
        row = m;
        break;
      }
    }
    final offer = decided && row != null && row.others > 0
        ? (
            position: position,
            label: itemLabel(row.item) ?? row.raw,
            fdcId: fdcId,
            confirmed: confirmed == true,
            // The SAME save: a typed amount travels with the pick, or the
            // resend would recompute this line's grams from the estimate.
            grams: grams,
            others: row.others,
          )
        : null;
    // The PUT persisted: show its fresh match list even if the label
    // refresh below fails — discarding it would render rows the server
    // no longer has.
    emit(
      state.copyWith(
        matches: matches,
        clearOverriding: true,
        offer: offer,
        clearOffer: offer == null,
        clearApplied: true,
      ),
    );
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
      emit(
        state.copyWith(
          error:
              'Saved, but refreshing the label failed: '
              '${exception.message}',
        ),
      );
    }
  }

  /// Sends the pending offer's decision again with `apply_to_all`, and shows
  /// the server's receipt in its place. The offer stays on failure, so the
  /// admin can retry or dismiss it.
  Future<void> applyToAll() async {
    final offer = state.offer;
    if (offer == null || state.applying) {
      return;
    }
    emit(state.copyWith(applying: true, clearError: true));
    final MatchOverrideResult result;
    try {
      result = await _repository.overrideMatch(
        idOrSlug,
        offer.position,
        fdcId: offer.fdcId,
        grams: offer.grams,
        confirmed: offer.confirmed ? true : null,
        applyToAll: true,
      );
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(applying: false, error: exception.message));
      return;
    }
    if (isClosed) {
      return;
    }
    final applied = result.applied;
    // A decision landed on ANOTHER row while this apply was in flight raises
    // its own offer; that newer offer stands — only this one is retired.
    final stillCurrent = state.offer == offer;
    emit(
      state.copyWith(
        matches: result.matches,
        applying: false,
        clearOffer: stillCurrent,
        applied: applied == null
            ? null
            : (
                position: offer.position,
                recipes: applied.recipes,
                lines: applied.lines,
                failed: applied.failed,
              ),
      ),
    );
  }

  /// Drops the pending offer or the shown receipt.
  void dismissApply() {
    if (state.offer == null && state.applied == null) {
      return;
    }
    // A failed apply's error goes with the offer it belonged to; leaving it
    // would hold the admin queue on a line that is in fact resolved.
    emit(
      state.copyWith(clearOffer: true, clearApplied: true, clearError: true),
    );
  }
}
