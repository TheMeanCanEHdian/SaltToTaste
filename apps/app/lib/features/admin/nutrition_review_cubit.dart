import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/api/recipe_repository.dart';

/// State of the cross-recipe nutrition-match review queue.
sealed class NutritionReviewState {
  const NutritionReviewState();
}

final class NutritionReviewLoading extends NutritionReviewState {
  const NutritionReviewLoading();
}

final class NutritionReviewError extends NutritionReviewState {
  const NutritionReviewError(this.message);

  final String message;
}

final class NutritionReviewLoaded extends NutritionReviewState {
  const NutritionReviewLoaded({
    required this.total,
    required this.groups,
    required this.buckets,
    required this.items,
    required this.bucket,
    required this.grouped,
    required this.selectedKey,
    required this.loadingMore,
    required this.exhausted,
    this.sort = NutritionReviewCubit.defaultSort,
    this.finishable = 0,
    this.openRecipes = 0,
  });

  /// Whole-library count of flagged lines (stable across the bucket filter).
  final int total;

  /// The same lines as distinct ingredient groups — reported in both views,
  /// so the header can name both units from one request.
  final int groups;
  final List<NutritionReviewBucket> buckets;

  /// The rows on screen: flagged LINES, or ingredient GROUPS when [grouped].
  final List<NutritionReviewLine> items;

  /// The active bucket filter, or null for "all flagged" (the default queue).
  final String? bucket;

  /// True when [items] are ingredient groups (`group=item`) rather than lines.
  final bool grouped;

  /// The line shown in the fix pane, keyed by [NutritionReviewLine.key], or
  /// null when nothing is selected (e.g. an empty queue).
  final String? selectedKey;
  final bool loadingMore;
  final bool exhausted;

  /// The queue order, of groups or lines: `finishes` (what one decision
  /// completes, the default) or `worst` (the worst match first).
  final String sort;

  /// The grouped queue's banner (whole-library): recipes one group
  /// decision completes, of those still waiting on an open line.
  final int finishable;
  final int openRecipes;

  /// The selected line, resolved from [items] (null if it is gone — e.g. just
  /// fixed, before the reload completes).
  NutritionReviewLine? get selected {
    for (final line in items) {
      if (line.key == selectedKey) {
        return line;
      }
    }
    return null;
  }

  /// Flagged lines matching the current filter (a bucket count, or [total]).
  int get linesTotal {
    if (bucket == null) {
      return total;
    }
    for (final b in buckets) {
      if (b.id == bucket) {
        return b.count;
      }
    }
    return 0;
  }

  /// The same, counted as ingredient groups.
  int get groupsTotal {
    if (bucket == null) {
      return groups;
    }
    for (final b in buckets) {
      if (b.id == bucket) {
        return b.groups;
      }
    }
    return 0;
  }

  /// Rows matching the current filter, in the unit [items] is listed in —
  /// so paging compares like with like (against lines it over-reports).
  int get filteredTotal => grouped ? groupsTotal : linesTotal;

  bool get hasMore => !exhausted && items.length < filteredTotal;

  NutritionReviewLoaded copyWith({
    List<NutritionReviewLine>? items,
    String? selectedKey,
    bool clearSelection = false,
    bool? loadingMore,
  }) => NutritionReviewLoaded(
    total: total,
    groups: groups,
    buckets: buckets,
    items: items ?? this.items,
    bucket: bucket,
    grouped: grouped,
    selectedKey: clearSelection ? null : (selectedKey ?? this.selectedKey),
    loadingMore: loadingMore ?? this.loadingMore,
    exhausted: exhausted,
    sort: sort,
    finishable: finishable,
    openRecipes: openRecipes,
  );
}

/// Loads and pages the cross-recipe nutrition-match review queue, tracks the
/// bucket filter, and holds the selected line for the master-detail fix pane.
class NutritionReviewCubit extends Cubit<NutritionReviewState> {
  NutritionReviewCubit(this._repository)
    : super(const NutritionReviewLoading());

  static const int pageSize = 50;

  /// The queue opens on what one decision finishes: the groups that finish
  /// the most recipes, or the lines that finish theirs (C1, B).
  static const String defaultSort = 'finishes';

  final RecipeRepository _repository;
  int _nextPage = 1;

  /// Page-1 fetches asked for: a reply to an older one, superseded by a later
  /// tap, is dropped — the last tap wins (A3).
  int _requested = 0;

  /// Page-1 lists put on screen: a "Load more" reply that lands after a
  /// reload replaced its list is dropped rather than appended to (or
  /// replacing) the new list (A3).
  int _shown = 0;

  /// The order for this session, in either view (`finishes` | `worst`).
  String _sort = defaultSort;

  /// Which view each bucket was last left in, for this session — flipping the
  /// toggle under one chip must survive a trip through the others.
  final Map<String?, bool> _groupedByBucket = {};

  /// The view a bucket opens in: grouped everywhere the work is a food
  /// problem an ingredient decision fixes, lines where it is per-line (an
  /// amount, a skip). `skipped` is never grouped — a skip does not travel.
  bool groupedFor(String? bucket) {
    if (bucket == 'skipped') {
      return false;
    }
    return _groupedByBucket[bucket] ??
        (bucket != 'no_grams' && bucket != 'skipped');
  }

  /// Switches the current bucket between ingredients and lines, remembers it
  /// for that bucket, and reloads from page 1 (the unit of paging changed).
  Future<void> setGrouped(bool grouped) async {
    final current = state;
    if (current is! NutritionReviewLoaded || current.grouped == grouped) {
      return;
    }
    // The memory has to be set before the fetch (_reload reads it), so a
    // failed fetch has to put it back — [_reload] does: otherwise the
    // toggle silently flips the memory and the NEXT reload (completeFix)
    // switches the unit by itself. Failure is silent, as in filter() —
    // nothing changed.
    _groupedByBucket[current.bucket] = grouped;
    try {
      await _reload(current.bucket, selectIndex: 0);
    } on RepositoryException {
      return;
    }
  }

  /// Switches the order (`finishes` | `worst`) and reloads from page 1.
  /// Compared with the REQUESTED order, so a second tap while the first is
  /// in flight wins (A3). A failed fetch leaves the view as it was, and
  /// [_reload] puts the order back to the one on screen — unless a later
  /// request superseded it (that failure is dropped).
  Future<void> setSort(String sort) async {
    final current = state;
    if (current is! NutritionReviewLoaded || _sort == sort) {
      return;
    }
    _sort = sort;
    try {
      await _reload(current.bucket, selectIndex: 0);
    } on RepositoryException {
      // [_reload] put the order back to the one on screen.
    }
  }

  /// One page-1 fetch in the current view, replacing the list. Throws
  /// [RepositoryException] — each caller decides what a failure looks like.
  ///
  /// The paging cursor moves only once the new list is on screen: reset before
  /// the fetch, a failure would leave the cubit asking for page 1 again while
  /// the state still holds page N, and every row of that reply would be
  /// dropped by loadMore's dedupe — "load more" stuck for good.
  ///
  /// [stayOn], when that ingredient key is still on the new page, selects it
  /// in place of the row at [selectIndex]. Only page 1 is fetched, so a
  /// group reached through "Load more" that now sorts past row [pageSize]
  /// is not found, and the selection falls back to [selectIndex] (A8: the
  /// stated page-1 fallback, not a re-fetch of every loaded page).
  ///
  /// A reply superseded by a later reload is dropped (A3), and so is a
  /// superseded FAILURE: it returns silently, so no caller's catch rewinds
  /// the order or the grouping, or shows an error, under the newer request.
  /// The LATEST request's failure puts the order and the screen's grouping
  /// memory back to what the screen shows, then throws.
  /// The list is stamped with the order and view it was fetched with (with
  /// the failure drop that equals `_sort` at emit time — a current reply's
  /// order cannot have moved since it was sent — so the stamp is the
  /// request's own, and the two can never drift).
  Future<void> _reload(
    String? bucket, {
    required int selectIndex,
    String? stayOn,
  }) async {
    final ticket = ++_requested;
    final sort = _sort;
    final grouped = groupedFor(bucket);
    final NutritionReviewReport report;
    try {
      report = await _repository.getNutritionReview(
        page: 1,
        limit: pageSize,
        bucket: bucket,
        grouped: grouped,
        sort: sort,
      );
    } on RepositoryException {
      if (ticket != _requested) {
        return;
      }
      // The latest request failed: the memory goes back to what the screen
      // shows — a superseded request's change too, whose own caller never
      // rewinds it (Run 049: setSort then filter both failing left `worst`
      // remembered under a `finishes` list, and the next tap sent nothing).
      final shown = state;
      if (shown is NutritionReviewLoaded) {
        _sort = shown.sort;
        if (groupedFor(shown.bucket) != shown.grouped) {
          _groupedByBucket[shown.bucket] = shown.grouped;
        }
      }
      rethrow;
    }
    if (isClosed || ticket != _requested) {
      return;
    }
    _nextPage = 2;
    _shown += 1;
    emit(
      _loadedFrom(
        report,
        bucket: bucket,
        grouped: grouped,
        sort: sort,
        selectIndex: selectIndex,
        stayOn: stayOn,
      ),
    );
  }

  /// (Re)loads from the first page under the [bucket] filter (null = all
  /// flagged). The first line is auto-selected so the fix pane is never blank
  /// while there is work to do.
  Future<void> load({String? bucket}) async {
    emit(const NutritionReviewLoading());
    try {
      await _reload(bucket, selectIndex: 0);
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(NutritionReviewError(exception.message));
    }
  }

  /// Switches the bucket filter (null clears it). Keeps the chrome (chips +
  /// counts) on screen and swaps only the list, selecting the first line of the
  /// new view — so changing a filter updates in place instead of flashing the
  /// full-page spinner.
  Future<void> filter(String? bucket) async {
    final current = state;
    if (current is! NutritionReviewLoaded || current.bucket == bucket) {
      return;
    }
    try {
      await _reload(bucket, selectIndex: 0);
    } on RepositoryException {
      // The filter didn't apply — leave the current view untouched.
      return;
    }
  }

  /// Appends the next page (the queue's "Load more").
  Future<void> loadMore() async {
    final current = state;
    if (current is! NutritionReviewLoaded ||
        current.loadingMore ||
        !current.hasMore) {
      return;
    }
    emit(current.copyWith(loadingMore: true));
    final shown = _shown;
    try {
      final report = await _repository.getNutritionReview(
        page: _nextPage,
        limit: pageSize,
        bucket: current.bucket,
        grouped: current.grouped,
        // The order of the list on screen, which this page extends.
        sort: current.sort,
      );
      // A reload replaced the list meanwhile: this page belongs to the old one.
      if (isClosed || shown != _shown) {
        return;
      }
      _nextPage += 1;
      final seen = {for (final line in current.items) line.key};
      emit(
        NutritionReviewLoaded(
          total: report.total,
          groups: report.groups,
          buckets: report.buckets,
          items: [
            ...current.items,
            for (final line in report.items)
              if (!seen.contains(line.key)) line,
          ],
          bucket: current.bucket,
          grouped: current.grouped,
          selectedKey: current.selectedKey,
          loadingMore: false,
          exhausted: report.items.length < pageSize,
          sort: current.sort,
          finishable: current.finishable,
          openRecipes: current.openRecipes,
        ),
      );
    } on RepositoryException {
      if (isClosed || shown != _shown) {
        return;
      }
      final latest = state;
      if (latest is NutritionReviewLoaded) {
        emit(latest.copyWith(loadingMore: false));
      }
    }
  }

  /// Selects a line for the fix pane.
  void select(String key) {
    final current = state;
    if (current is NutritionReviewLoaded && current.selectedKey != key) {
      emit(current.copyWith(selectedKey: key));
    }
  }

  /// Called once a fix (re-pick / confirm / skip) has been written for the
  /// selected line: reloads the top of the queue — the fixed line drops out —
  /// and advances the selection to the line that took its place (the next
  /// in the queue's order), or the new last line when it was at the end.
  ///
  /// Reloading resets to page one; a burn-down works from the top of the
  /// order (`finishes` or `worst`), so re-fetching page one after each fix is
  /// exactly right.
  Future<void> completeFix() async {
    final current = state;
    if (current is! NutritionReviewLoaded) {
      return;
    }
    // Where the fixed line sat, so the reload can land on its successor.
    var index = 0;
    for (var i = 0; i < current.items.length; i++) {
      if (current.items[i].key == current.selectedKey) {
        index = i;
        break;
      }
    }
    // A No grams GROUP keeps the pane on its ingredient (C): each line needs
    // its own amount, so its next line is the next piece of work.
    final fixed = current.selected;
    final stayOn = fixed != null && current.grouped && staysOnIngredient(fixed)
        ? fixed.itemKey
        : null;
    try {
      // _loadedFrom clamps: an emptied queue clears the selection, and a
      // shorter one lands on its new last row.
      await _reload(current.bucket, selectIndex: index, stayOn: stayOn);
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(NutritionReviewError(exception.message));
    }
  }

  NutritionReviewLoaded _loadedFrom(
    NutritionReviewReport report, {
    required String? bucket,
    required bool grouped,
    required String sort,
    required int selectIndex,
    String? stayOn,
  }) {
    final items = report.items;
    String? key;
    for (final line in items) {
      if (stayOn != null && line.itemKey == stayOn) {
        key = line.key;
        break;
      }
    }
    key ??= (selectIndex < 0 || items.isEmpty)
        ? null
        : items[selectIndex.clamp(0, items.length - 1)].key;
    return NutritionReviewLoaded(
      total: report.total,
      groups: report.groups,
      buckets: report.buckets,
      items: items,
      bucket: bucket,
      grouped: grouped,
      selectedKey: key,
      loadingMore: false,
      exhausted: items.length < pageSize,
      sort: sort,
      finishable: report.finishable,
      openRecipes: report.openRecipes,
    );
  }
}

/// Whether a fix on [line], a grouped row, keeps the pane on its ingredient
/// and opens its next line (C): a No grams group of more than one line —
/// each line needs its own amount, so the next one is the next piece of
/// work, and a typed amount never travels.
bool staysOnIngredient(NutritionReviewLine line) =>
    line.bucket == 'no_grams' &&
    line.lines > 1 &&
    (line.itemKey ?? '').isNotEmpty;
