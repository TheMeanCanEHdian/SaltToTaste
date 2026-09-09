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
  );
}

/// Loads and pages the cross-recipe nutrition-match review queue, tracks the
/// bucket filter, and holds the selected line for the master-detail fix pane.
class NutritionReviewCubit extends Cubit<NutritionReviewState> {
  NutritionReviewCubit(this._repository)
    : super(const NutritionReviewLoading());

  static const int pageSize = 50;

  final RecipeRepository _repository;
  int _nextPage = 1;

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
    // failed fetch has to put it back: otherwise the toggle silently flips
    // the memory and the NEXT reload (completeFix) switches the unit by
    // itself. Failure is silent, as in filter() — nothing changed.
    final previous = _groupedByBucket[current.bucket];
    _groupedByBucket[current.bucket] = grouped;
    try {
      await _reload(current.bucket, selectIndex: 0);
    } on RepositoryException {
      if (previous == null) {
        _groupedByBucket.remove(current.bucket);
      } else {
        _groupedByBucket[current.bucket] = previous;
      }
    }
  }

  /// One page-1 fetch in the current view, replacing the list. Throws
  /// [RepositoryException] — each caller decides what a failure looks like.
  ///
  /// The paging cursor moves only once the new list is on screen: reset before
  /// the fetch, a failure would leave the cubit asking for page 1 again while
  /// the state still holds page N, and every row of that reply would be
  /// dropped by loadMore's dedupe — "load more" stuck for good.
  Future<void> _reload(String? bucket, {required int selectIndex}) async {
    final report = await _repository.getNutritionReview(
      page: 1,
      limit: pageSize,
      bucket: bucket,
      grouped: groupedFor(bucket),
    );
    if (isClosed) {
      return;
    }
    _nextPage = 2;
    emit(_loadedFrom(report, bucket: bucket, selectIndex: selectIndex));
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
    try {
      final report = await _repository.getNutritionReview(
        page: _nextPage,
        limit: pageSize,
        bucket: current.bucket,
        grouped: current.grouped,
      );
      if (isClosed) {
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
        ),
      );
    } on RepositoryException {
      if (isClosed) {
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
  /// worst), or the new last line when it was at the end.
  ///
  /// Reloading resets to page one; a burn-down works from the worst lines at
  /// the top, so re-fetching the worst page after each fix is exactly right.
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
    try {
      // _loadedFrom clamps: an emptied queue clears the selection, and a
      // shorter one lands on its new last row.
      await _reload(current.bucket, selectIndex: index);
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
    required int selectIndex,
  }) {
    final items = report.items;
    final key = (selectIndex < 0 || items.isEmpty)
        ? null
        : items[selectIndex.clamp(0, items.length - 1)].key;
    return NutritionReviewLoaded(
      total: report.total,
      groups: report.groups,
      buckets: report.buckets,
      items: items,
      bucket: bucket,
      grouped: groupedFor(bucket),
      selectedKey: key,
      loadingMore: false,
      exhausted: items.length < pageSize,
    );
  }
}
