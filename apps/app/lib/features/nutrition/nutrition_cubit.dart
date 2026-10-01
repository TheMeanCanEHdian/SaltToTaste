import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_shared/salt_shared.dart' show ApiErrorCodes;

/// An offer to push a decision just made on one line out to every other
/// undecided line of the same ingredient item: what to resend (the pick, or
/// the confirm), and how many recipes and lines it would change.
///
/// The reach is food-agnostic: the others are the undecided lines of this
/// ingredient, whatever food they happen to sit on — so the strip tells one
/// sentence, about lines waiting on this decision.
///
/// [raw] is the text of the line the offer was raised on, captured with the
/// offer and never re-read: every resend names that line, and a reload that
/// moves the lines moves (or withdraws) the offer by it (Run 051 A1 — a
/// retry that re-read the row at [position] wrote the food onto whatever
/// line a save had put there).
typedef ApplyOffer = ({
  int position,
  String raw,
  String label,
  int? fdcId,
  bool confirmed,
  double? grams,
  int others,
  int lines,
});

/// The receipt of an apply-to-all, shown in place of the offer: what it
/// reached, what failed, how many reached recipes it completed (and which:
/// the queue's receipt names a shortfall against its promise), and how many
/// targets it left because their recipe changed meanwhile ([moved]), was
/// decided meanwhile ([decided]), is another ingredient now or gone
/// ([gone]), or sat in a recipe that failed ([failedLines]). [raw]
/// is the offer's line text: the receipt stands under the row that reads it,
/// as the offer did ([receiptIsFor]).
typedef ApplyReceipt = ({
  int position,
  String raw,
  int recipes,
  int lines,
  int failed,
  int completed,
  List<String> completedRecipes,
  int moved,
  int decided,
  int gone,
  int failedLines,
});

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

/// [offer] on freshly reloaded [matches]: kept while the row at its
/// position still reads its line's text, moved to the one row that does when
/// a save shifted the line, and null — withdrawn — when no row, or more than
/// one (twin lines: which one it was is unknowable), reads it.
ApplyOffer? offerOnReload(ApplyOffer offer, List<IngredientMatch> matches) {
  final at = rowReading(matches, offer.raw, offer.position);
  if (at == null) {
    return null;
  }
  if (at.position == offer.position) {
    return offer;
  }
  return (
    position: at.position,
    raw: offer.raw,
    label: offer.label,
    fdcId: offer.fdcId,
    confirmed: offer.confirmed,
    grams: offer.grams,
    others: offer.others,
    lines: offer.lines,
  );
}

/// The row of [matches] that is the line reading [raw] last seen at
/// [position]: the row at [position] when it still reads [raw], else the one
/// row that does (a save shifted the line), else null — no row, or twins
/// none of which stands at [position] (which one it was is unknowable).
/// Every place the app names "the line the person acted on" goes through
/// here, never through a position alone (Run 052 O7/S6).
IngredientMatch? rowReading(
  List<IngredientMatch> matches,
  String raw,
  int position,
) {
  final reading = [
    for (final m in matches)
      if (m.raw == raw) m,
  ];
  for (final m in reading) {
    if (m.position == position) {
      return m;
    }
  }
  return reading.length == 1 ? reading.single : null;
}

/// [receipt] on freshly reloaded [matches], placed by its line's text as
/// [offerOnReload] places an offer; null when its line cannot be placed.
ApplyReceipt? receiptOnReload(
  ApplyReceipt receipt,
  List<IngredientMatch> matches,
) {
  final at = rowReading(matches, receipt.raw, receipt.position);
  if (at == null) {
    return null;
  }
  return (
    position: at.position,
    raw: receipt.raw,
    recipes: receipt.recipes,
    lines: receipt.lines,
    failed: receipt.failed,
    completed: receipt.completed,
    completedRecipes: receipt.completedRecipes,
    moved: receipt.moved,
    decided: receipt.decided,
    gone: receipt.gone,
    failedLines: receipt.failedLines,
  );
}

/// Whether [receipt] belongs under row [m]: as [offerIsFor].
bool receiptIsFor(ApplyReceipt? receipt, IngredientMatch m) =>
    receipt != null && receipt.position == m.position && receipt.raw == m.raw;

/// Whether [offer] belongs under row [m]: the row at its position that
/// still reads the text it was raised on (position alone showed the strip
/// under whatever line a save had moved there; text alone doubles it on
/// twin lines).
bool offerIsFor(ApplyOffer? offer, IngredientMatch m) =>
    offer != null && offer.position == m.position && offer.raw == m.raw;

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
      _emitRows(matches);
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(error: exception.message));
    }
  }

  /// Applies one row override, then refreshes the label totals. [raw] is
  /// the line's text as shown: when a save since moved that line, the
  /// server refuses (`line_moved`, nothing written) and the rows are
  /// reloaded, so the screen finds the line where it is now. It is also the
  /// offer's text — the line the person acted on and the server guarded on.
  Future<void> override(
    int position, {
    required String raw,
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
        raw: raw,
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
      if (exception.code == ApiErrorCodes.lineMoved) {
        await _reloadMatchesKeepingError();
      }
      return;
    }
    if (isClosed) {
      return;
    }
    final matches = result.matches;
    // A pick or a confirm is a decision about the ingredient; if any other
    // undecided line carries that item — on this food or another — offer to
    // push the decision out. The count is the server's, fresh after the
    // write, which is why the offer can only appear once it has landed.
    // A skip or a grams-only change is not a decision to broadcast.
    // The row is the one reading the SENT text, never the row the response
    // has at [position]: the response is read after the server's awaits, and
    // a save in them can stand another line there (Run 052 O7/S6) — then the
    // offer follows the text, or, unplaceable, is not raised.
    final decided = fdcId != null || confirmed == true;
    final row = rowReading(matches, raw, position);
    final offer = decided && row != null && row.others > 0
        ? (
            position: row.position,
            raw: raw,
            label: itemLabel(row.item) ?? row.raw,
            fdcId: fdcId,
            confirmed: confirmed == true,
            // The SAME save: a typed amount travels with the pick, or the
            // resend would recompute this line's grams from the estimate.
            grams: grams,
            others: row.others,
            lines: row.othersLines,
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

  /// Shows freshly fetched [matches]. Every reload of the rows goes through
  /// here, so a pending offer always follows its line by text
  /// ([offerOnReload]); one whose line it cannot place is withdrawn, and the
  /// message (after any already up) says so.
  void _emitRows(List<IngredientMatch> matches) {
    final offer = state.offer;
    final moved = offer == null ? null : offerOnReload(offer, matches);
    final withdrawn = offer != null && moved == null;
    // A shown receipt follows its line the same way; one whose line is gone
    // just goes (it reports what happened, nothing is left to act on).
    final receipt = state.applied;
    final placed = receipt == null ? null : receiptOnReload(receipt, matches);
    emit(
      state.copyWith(
        matches: matches,
        offer: moved,
        clearOffer: withdrawn,
        applied: placed,
        clearApplied: placed == null,
        error: withdrawn
            ? '${state.error ?? ''} ${_withdrawn(offer)}'.trim()
            : null,
      ),
    );
  }

  static String _withdrawn(ApplyOffer offer) =>
      'The apply-to-all offer for "${offer.raw}" was withdrawn: that line is '
      'no longer in the recipe as it was.';

  /// Refetches the rows after a `line_moved` refusal; the refusal's message
  /// stays up (a failed refetch leaves the rows as they were).
  Future<void> _reloadMatchesKeepingError() async {
    try {
      final matches = await _repository.matches(idOrSlug);
      if (isClosed) {
        return;
      }
      _emitRows(matches);
    } on RepositoryException {
      // The refusal already says to refresh; nothing more to add.
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
        // The line the offer was raised on — never the row now at its
        // position (a save since: 409, and the reload re-locates it).
        raw: offer.raw,
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
      if (exception.code == ApiErrorCodes.lineMoved) {
        await _reloadMatchesKeepingError();
      }
      return;
    }
    if (isClosed) {
      return;
    }
    final applied = result.applied;
    final matches = result.matches;
    // A decision landed on ANOTHER row while this apply was in flight raises
    // its own offer; that newer offer stands — only this one is retired. The
    // newer offer and the receipt are both placed by their line's TEXT on
    // the answer's rows, never by a position alone (Run 052 O7/S6).
    final newer = state.offer == offer ? null : state.offer;
    final kept = newer == null ? null : offerOnReload(newer, matches);
    final receipt = applied == null
        ? null
        : receiptOnReload((
            position: offer.position,
            raw: offer.raw,
            recipes: applied.recipes,
            lines: applied.lines,
            failed: applied.failed,
            completed: applied.completed,
            completedRecipes: applied.completedRecipes,
            moved: applied.moved,
            decided: applied.decided,
            gone: applied.gone,
            failedLines: applied.failedLines,
          ), matches);
    emit(
      state.copyWith(
        matches: matches,
        applying: false,
        offer: kept,
        clearOffer: kept == null,
        applied: receipt,
        clearApplied: receipt == null,
        error: newer != null && kept == null ? _withdrawn(newer) : null,
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
