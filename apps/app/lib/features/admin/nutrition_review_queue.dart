import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';
import 'package:salt_shared/salt_shared.dart' show HoldDecision, mediumHolds;

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/async_view.dart';
import 'package:salt_app/core/widgets/salt_badge.dart';
import 'package:salt_app/core/widgets/stat_chip.dart';
import 'package:salt_app/features/admin/nutrition_review_cubit.dart';
import 'package:salt_app/features/nutrition/apply_to_all_strip.dart';
import 'package:salt_app/features/nutrition/match_fix_panel.dart';
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';

/// The cross-recipe nutrition-match review queue (Layout A, master-detail): a
/// list of flagged ingredient lines (or groups) on the left, in the chosen
/// order (what one decision finishes, by default, or the worst match first),
/// the shared fix
/// panel docked on the right. Fixing a line drops it and advances to the next.
///
/// Assumes an ancestor `BlocProvider<NutritionReviewCubit>` (the review page
/// creates it alongside the recipe-review cubit so both tab counts stay live).
class NutritionReviewQueue extends StatelessWidget {
  const NutritionReviewQueue({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NutritionReviewCubit, NutritionReviewState>(
      builder: (context, state) => switch (state) {
        NutritionReviewLoading() => const LoadingView(),
        NutritionReviewError(:final message) => ErrorView(
          message: message,
          onRetry: () => context.read<NutritionReviewCubit>().load(),
        ),
        NutritionReviewLoaded() => _Loaded(state: state),
      },
    );
  }
}

// Bucket id → badge tone / stripe colour. Red = unmatched, teal = matched but
// contributes nothing, amber = counting but probably wrong, grey = skipped.
SaltBadgeTone _bucketTone(String id) => switch (id) {
  'no_match' => SaltBadgeTone.err,
  'no_grams' => SaltBadgeTone.info,
  'check' => SaltBadgeTone.warn,
  'skipped' => SaltBadgeTone.neutral,
  _ => SaltBadgeTone.neutral,
};

Color _bucketStripe(String id) => switch (id) {
  'no_match' => SaltColors.errInk,
  'no_grams' => SaltColors.infoInk,
  'check' => SaltColors.warnInk,
  _ => SaltColors.muted,
};

/// Selected-row fill (matches the mockup's `--chipSel` and the stat chip).
const Color _selectedFill = Color(0xFFF7ECEC);

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state});

  final NutritionReviewLoaded state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NutritionReviewCubit>();
    if (state.total == 0 && state.bucket == null) {
      return const _Empty();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Breakpoints.detailTwoColumn;
        final filters = _BucketFilters(state: state, onSelect: cubit.filter);
        if (!wide) {
          // Stacked: the whole tab scrolls, queue over fix panel.
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                filters,
                const SizedBox(height: 16),
                _card(child: _QueueList(state: state, bounded: false)),
                const SizedBox(height: 14),
                _card(
                  fill: SaltColors.panel,
                  child: _FixPane(line: state.selected),
                ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            filters,
            const SizedBox(height: 16),
            Expanded(
              child: _card(
                clip: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ~1.15 : 1, queue slightly wider than the fix panel.
                    Expanded(
                      flex: 23,
                      child: _QueueList(state: state, bounded: true),
                    ),
                    const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: SaltColors.hairline,
                    ),
                    Expanded(
                      flex: 20,
                      child: ColoredBox(
                        color: SaltColors.panel,
                        child: _FixPane(line: state.selected),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// A white card with the app's hairline border painted in the foreground so
  /// it sits on top of any child fill (the panel-tinted fix pane).
  Widget _card({required Widget child, Color? fill, bool clip = false}) {
    return Container(
      decoration: BoxDecoration(
        color: fill ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: SaltColors.hairline),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      child: clip
          ? child
          : ClipRRect(borderRadius: BorderRadius.circular(12), child: child),
    );
  }
}

/// The count chips that double as the bucket filter. "Need attention" clears
/// the filter (all flagged); each bucket narrows to itself.
class _BucketFilters extends StatelessWidget {
  const _BucketFilters({required this.state, required this.onSelect});

  final NutritionReviewLoaded state;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        StatChip(
          label: 'Need attention',
          count: state.total,
          selected: state.bucket == null,
          emphasized: true,
          onTap: () => onSelect(null),
        ),
        for (final b in state.buckets)
          StatChip(
            label: b.label,
            count: b.count,
            selected: state.bucket == b.id,
            // A bucket with nothing in it isn't a useful filter.
            enabled: b.count > 0,
            onTap: () => onSelect(b.id),
          ),
      ],
    );
  }
}

/// The left pane: a header line over the ordered list of flagged rows.
class _QueueList extends StatelessWidget {
  const _QueueList({required this.state, required this.bounded});

  final NutritionReviewLoaded state;

  /// True in the wide master-detail layout, where the list fills a bounded
  /// height and scrolls internally; false when the whole tab scrolls (stacked).
  final bool bounded;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NutritionReviewCubit>();
    final label = state.bucket == null ? 'all flagged' : _bucketLabel(state);
    final rows = <Widget>[
      for (final line in state.items)
        _QueueRow(
          key: ValueKey(line.key),
          line: line,
          selected: line.key == state.selectedKey,
          onTap: () => cubit.select(line.key),
        ),
      if (state.hasMore)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: FButton(
              variant: FButtonVariant.outline,
              mainAxisSize: MainAxisSize.min,
              onPress: state.loadingMore ? null : cubit.loadMore,
              child: Text(state.loadingMore ? 'Loading…' : 'Load more'),
            ),
          ),
        ),
      if (state.items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              state.grouped
                  ? 'No ingredients in this bucket.'
                  : 'No lines in this bucket.',
              style: const TextStyle(fontSize: 13, color: SaltColors.muted),
            ),
          ),
        ),
    ];

    final header = Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SaltColors.hairline)),
      ),
      // Wrap, not Row: on a narrow (stacked) card the toggle drops under the
      // sentence instead of squeezing it.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 6,
        children: [
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 12, color: SaltColors.muted),
              children: [
                const TextSpan(text: 'Showing '),
                TextSpan(
                  text: label,
                  style: const TextStyle(
                    color: SaltColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: state.grouped
                      ? ' · ${state.groupsTotal} ingredients, '
                            '${state.linesTotal} lines · '
                      : ' · ${state.linesTotal} lines · ',
                ),
                // The active order, as the sentence's last words (B).
                TextSpan(
                  text: state.sort == 'worst'
                      ? 'worst match first'
                      : 'most recipes finished first',
                  style: const TextStyle(
                    color: SaltColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              // The order changes the view, it is no action: neutral grey,
              // one tap away — in either unit (a line finishes its recipe
              // when it is the last open one).
              _Segmented<String>(
                value: state.sort,
                onChanged: cubit.setSort,
                cells: const [
                  ('Finishes recipes', FLucideIcons.flag, 'finishes'),
                  ('Worst match', FLucideIcons.arrowDownWideNarrow, 'worst'),
                ],
              ),
              // A skip is per line and never travels, so there is no
              // ingredient view of that bucket to offer — hidden beats a
              // dead control.
              if (state.bucket != 'skipped')
                _Segmented<bool>(
                  value: state.grouped,
                  onChanged: cubit.setGrouped,
                  cells: const [
                    ('Ingredients', FLucideIcons.layers, true),
                    ('Lines', FLucideIcons.list, false),
                  ],
                ),
            ],
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        // The payoff of the whole queue (B), whole-library in either order.
        if (state.grouped && state.finishable > 0)
          _OneAway(finishable: state.finishable, open: state.openRecipes),
        if (bounded)
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: rows),
          )
        else
          ...rows,
      ],
    );
  }

  String _bucketLabel(NutritionReviewLoaded state) {
    for (final b in state.buckets) {
      if (b.id == state.bucket) {
        return b.label;
      }
    }
    return state.bucket ?? '';
  }
}

/// The banner under the grouped queue's header: how many of the recipes
/// still waiting are one group decision from complete.
class _OneAway extends StatelessWidget {
  const _OneAway({required this.finishable, required this.open});

  final int finishable;
  final int open;

  @override
  Widget build(BuildContext context) {
    const bold = TextStyle(fontWeight: FontWeight.w700);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: const BoxDecoration(
        color: SaltColors.okBg,
        border: Border(bottom: BorderSide(color: SaltColors.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2, right: 7),
            child: Icon(FLucideIcons.flag, size: 13, color: SaltColors.okInk),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$finishable', style: bold),
                  const TextSpan(text: ' of the '),
                  TextSpan(text: '$open', style: bold),
                  TextSpan(
                    text:
                        ' partial ${open == 1 ? 'recipe' : 'recipes'} '
                        '${finishable == 1 ? 'is' : 'are'} one group '
                        'decision away from complete. A count assumes the '
                        'decision is applied to its whole group.',
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 12, color: SaltColors.okInk),
            ),
          ),
        ],
      ),
    );
  }
}

/// A segment at the right end of the queue header — Finishes recipes |
/// Worst match (the order) and Ingredients | Lines (the unit): it changes
/// the view and nothing else. Neutral grey — switching a view is not a
/// primary action, so it is never maroon.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.onChanged,
    required this.cells,
  });

  final T value;
  final ValueChanged<T> onChanged;
  final List<(String, IconData, T)> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: SaltColors.hairline),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, icon, cell) in cells)
            _cell(label, icon, on: cell == value, value: cell),
        ],
      ),
    );
  }

  Widget _cell(
    String label,
    IconData icon, {
    required bool on,
    required T value,
  }) {
    final color = on ? SaltColors.ink : SaltColors.muted;
    return FTappable(
      onPress: on ? null : () => onChanged(value),
      child: ColoredBox(
        color: on ? SaltColors.chipNeutral : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One flagged line in the queue: a bucket-coloured stripe, the recipe and raw
/// line, the current (often wrong) food, a bucket pill, and name confidence.
///
/// A multi-line GROUP is the same shape with one slot swapped: the meta line
/// names the ingredient and its reach, the raw line is one member marked
/// "e.g.", and a fourth slot aggregates the members' amounts.
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.line,
    required this.selected,
    required this.onTap,
  });

  final NutritionReviewLine line;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final match = line.match;
    final food = match?.description ?? 'no food matched';
    final foodColor = switch (line.bucket) {
      'no_match' || 'check' => SaltColors.errInk,
      _ => SaltColors.bodyText,
    };
    // A group of one IS today's row — no pill, no "e.g.", no amount slot —
    // which is what makes grouping free on the majority of rows.
    final group = line.lines > 1;
    final amount = groupAmountLine(line);
    final soft = group ? lastOpenNote(line) : null;
    final hold = group ? null : lineHoldNote(line);
    return FTappable(
      onPress: onTap,
      child: DecoratedBox(
        // The bucket accent is a left border (a stretched child would demand an
        // infinite height inside the list's unbounded scroll axis).
        decoration: BoxDecoration(
          color: selected ? _selectedFill : null,
          border: Border(
            left: BorderSide(color: _bucketStripe(line.bucket), width: 3),
            bottom: const BorderSide(color: SaltColors.hairline),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (group)
                      _GroupMeta(line: line)
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${line.recipe.title} · line ${line.position}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: SaltColors.muted,
                            ),
                          ),
                          if (line.finishes > 0)
                            const FinishesPill('finishes this recipe'),
                        ],
                      ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        children: [
                          // The bold line is one member standing for the rest,
                          // so it never claims to be the thing being decided.
                          if (group)
                            const TextSpan(
                              text: 'e.g. ',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: SaltColors.muted,
                              ),
                            ),
                          TextSpan(text: line.raw),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: SaltColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '→ ',
                          style: TextStyle(
                            fontSize: 12,
                            color: SaltColors.muted,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            food,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: foodColor),
                          ),
                        ),
                      ],
                    ),
                    if (amount != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            FLucideIcons.scale,
                            size: 11,
                            color: amount.warn
                                ? SaltColors.warnInk
                                : SaltColors.muted,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: amount.text),
                                  // The soft note: how many recipes this
                                  // group holds the last open line of (B).
                                  if (soft != null)
                                    TextSpan(
                                      text: ' · $soft',
                                      style: const TextStyle(
                                        color: SaltColors.muted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: amount.warn
                                    ? SaltColors.warnInk
                                    : SaltColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (hold != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        hold,
                        style: const TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: SaltColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SaltBadge(
                    _rowBadgeLabel(line.bucket),
                    tone: _bucketTone(line.bucket),
                  ),
                  if (match != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      '${(match.confidence * 100).round()}% name',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: SaltColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A group row's meta slot: the ingredient, how far it reaches, and whether
/// it has already been decided (so the same ingredient is not decided twice).
class _GroupMeta extends StatelessWidget {
  const _GroupMeta({required this.line});

  final NutritionReviewLine line;

  @override
  Widget build(BuildContext context) {
    final label = groupLabel(line);
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: SaltColors.ink,
          ),
        ),
        // The leverage, findable by a scan without reading.
        DecoratedBox(
          decoration: BoxDecoration(
            color: SaltColors.chip,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            child: Text(
              '${line.lines} lines · '
              '${line.recipes == 1 ? '1 recipe' : '${line.recipes} recipes'}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: SaltColors.chipInk,
              ),
            ),
          ),
        ),
        // What one decision on the group completes (B); no pill at 0.
        if (line.finishes > 0)
          FinishesPill(
            line.finishes == 1
                ? 'finishes 1 recipe'
                : 'finishes ${line.finishes} recipes',
          ),
        if (line.decided) const SaltBadge('decided', tone: SaltBadgeTone.ok),
      ],
    );
  }
}

/// The green pill naming what a decision completes: an outcome, not a
/// problem.
class FinishesPill extends StatelessWidget {
  const FinishesPill(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SaltColors.okBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FLucideIcons.flag, size: 11, color: SaltColors.okInk),
            const SizedBox(width: 4),
            Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: SaltColors.okInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A group row's label: the example line's item, tidied — except for a key
/// that names a second food ('lemon zest plus juice', 'egg plus yolk'),
/// labelled by the key itself: the example's item names only its first
/// food, so the group read as plain lemon zest (checkpoint 5).
String groupLabel(NutritionReviewLine line) {
  final key = line.itemKey;
  if (key != null && key.contains(' plus ')) {
    return key;
  }
  return itemLabel(line.item) ?? key ?? '';
}

/// The group row's amount slot — one aggregate over the members' grams — and
/// whether it is a warning. Null when there is nothing to aggregate (a group
/// of one, or a range the server didn't report).
({String text, bool warn})? groupAmountLine(NutritionReviewLine line) {
  final n = line.lines;
  if (n < 2) {
    return null;
  }
  final missing = line.gramsMissing;
  final String text;
  if (missing >= n) {
    text = n == 2
        ? 'no amount on either line'
        : 'no amount on any of the $n lines';
  } else {
    final min = line.gramsMin;
    final max = line.gramsMax;
    if (min == null || max == null) {
      return null;
    }
    if (missing == 0) {
      text = min == max
          ? (n == 2
                ? '${fmtAmount(min)} g on both lines'
                : '${fmtAmount(min)} g on all $n lines')
          : 'amounts ${fmtAmount(min)}–${fmtAmount(max)} g, one per line';
    } else {
      text =
          'amounts ${fmtAmount(min)}–${fmtAmount(max)} g · '
          '$missing of $n lines have no amount';
    }
  }
  // The confirm is offered on the EXAMPLE line and, with no grams, asks for
  // the amount (C) — so the warning follows that line, not the aggregate: a
  // group where only the example is amount-less still asks. Say so before
  // the click, not after the pane opens.
  if (line.bucket == 'check' && line.match?.grams == null) {
    return (text: '$text — confirm asks for the amount', warn: true);
  }
  return (text: text, warn: false);
}

/// A No grams group's soft note (B): in how many recipes it holds the last
/// open line, each needing its own amount — "(this one included)" when the
/// example's recipe is one, which is exactly when the group finishes a
/// recipe (none of its lines has grams, so only the example's can). Null
/// for any other group, or none.
String? lastOpenNote(NutritionReviewLine line) {
  final n = line.lastOpen;
  if (line.bucket != 'no_grams' || n < 1) {
    return null;
  }
  return 'last open line in ${n == 1 ? '1 recipe' : '$n recipes'}'
      '${line.finishes > 0 ? ' (this one included)' : ''} · '
      '${n == 1 ? 'it needs' : 'each needs'} its own amount';
}

/// The italic sub-line of a line-held row (B, ruling 5): a line hold is
/// decided one line at a time and never offers apply-to-all; how it
/// finishes — and so for a `food_gone` row (a pick or skip finishes it;
/// server RULE A, v27). Null for any other row.
String? lineHoldNote(NutritionReviewLine line) {
  final match = line.match;
  const head = 'decided one line at a time, never offers apply-to-all. ';
  const noZero = '. There is no 0 g decision: the API rejects grams of 0.';
  return switch (match?.hold) {
    // Which decisions finish it, by hold kind ([heldFinishes]: a pick keeps
    // an eaten-in-part hold; Run 056 Sonnet critic 3 / Opus critic 3).
    final hold? when mediumHolds.contains(hold) =>
      'line hold (${hold.replaceAll('_', ' ')}): $head'
          '${heldFinishes(hold, eatenPart: match!.gramSource == 'discarded' && (match.grams ?? 0) > 0 ? match.grams : null)}$noZero',
    'in_shell' =>
      'line hold (in shell): ${head}Any decision finishes it: Skip, or the '
          'typed edible grams (the shells are not eaten)$noZero',
    'second_food' =>
      'line hold (second food): ${head}Any decision finishes it: Confirm, '
          'Skip, or a typed positive amount$noZero',
    // Not a line hold — the person's food has no record (gone from USDA,
    // or failing) — but decided one line at a time all the same (a decided
    // row is its own group); how it finishes is the action table's.
    final hold? when noRecordHold(hold) =>
      '${hold.replaceAll('_', ' ')}: decided one line at a time. '
          '${heldFinishes(hold)}.',
    _ => null,
  };
}

String _rowBadgeLabel(String bucket) => switch (bucket) {
  'no_match' => 'no match',
  'no_grams' => 'no grams',
  'check' => 'check match',
  'skipped' => 'skipped',
  _ => bucket,
};

/// The right pane. For the selected line it scopes a [NutritionCubit] to that
/// line's recipe (loading its full matches so the fix panel gets candidates),
/// finds the [IngredientMatch] at the line's position, and renders the shared
/// [FixPanel]. When a fix completes it refreshes the queue and advances.
class _FixPane extends StatelessWidget {
  const _FixPane({required this.line});

  final NutritionReviewLine? line;

  @override
  Widget build(BuildContext context) {
    final selected = line;
    if (selected == null) {
      return const _Placeholder();
    }
    return BlocProvider<NutritionCubit>(
      // Keyed by the exact line: selecting another row rebuilds a fresh cubit
      // (and fix-panel state) for the new recipe/position.
      key: ValueKey(selected.key),
      create: (context) => NutritionCubit(
        context.read<NutritionRepository>(),
        selected.recipe.slug,
      )..loadMatches(),
      child: _FixPaneBody(line: selected),
    );
  }
}

/// The row of the queue's [line] in its recipe's [matches]. The queue
/// lists a row at its STORED position, which a save since the last compute
/// can leave behind its line: the row reading the line's text nearest that
/// position (itself when the line did not move; the lower of two twins
/// equally near), and null when no row reads it — the line was edited or
/// removed. Never the row that now sits at the position: that is another
/// line, and acting on it wrote this line's fix onto it (Run 051 A2).
IngredientMatch? queueMatchOf(
  List<IngredientMatch> matches,
  NutritionReviewLine line,
) {
  IngredientMatch? nearest;
  for (final m in matches) {
    if (m.raw == line.raw &&
        (nearest == null ||
            (m.position - line.position).abs() <
                (nearest.position - line.position).abs())) {
      nearest = m;
    }
  }
  return nearest;
}

/// Whether a [NutritionState] transition means the selected line is done
/// and the queue should drop it and move on: a fix landed with no
/// apply-to-all offer pending, or the offer (or its receipt) was just
/// closed — and never while an error is showing (a failed override, or a
/// failed apply until it is dismissed, which clears the error too).
bool queueShouldAdvance(NutritionState previous, NutritionState current) {
  if (current.error != null) {
    return false;
  }
  final settled = current.offer == null && current.applied == null;
  final fixLanded =
      previous.overridingPosition != null && current.overridingPosition == null;
  final offerClosed =
      (previous.offer != null || previous.applied != null) && settled;
  return (fixLanded && settled) || offerClosed;
}

/// Whether the line at [position] is, after the transition, waiting on an
/// amount (No grams on a food): a plain Confirm USDA could not convert, a
/// pick from any bucket (No match, No grams) that ended without grams, or an
/// apply-to-all offer or receipt closing over such a line. The queue then
/// keeps the pane on that line — it is not done (A4). A null [position] is
/// a line no row reads any more (edited or removed): nothing of it waits,
/// whatever line now sits at its old position (Run 054 S9/O11).
bool leftWaitingOnAmount(NutritionState current, int? position) {
  if (position == null) {
    return false;
  }
  IngredientMatch? at(List<IngredientMatch>? matches) {
    for (final m in matches ?? const <IngredientMatch>[]) {
      if (m.position == position) {
        return m;
      }
    }
    return null;
  }

  // Any No grams row on a food — a held line too, whose pick alone kept
  // its hold with no grams: it still waits on its edible grams or a skip.
  final after = at(current.matches);
  return after != null &&
      after.fdcId != null &&
      matchBucketOf(after) == MatchBucket.noAmount;
}

/// The pane's advance rule: [queueShouldAdvance], unless the line at
/// [position] is left waiting on an amount ([leftWaitingOnAmount]).
bool paneAdvances(
  NutritionState previous,
  NutritionState current,
  int? position,
) =>
    queueShouldAdvance(previous, current) &&
    !leftWaitingOnAmount(current, position);

class _FixPaneBody extends StatelessWidget {
  const _FixPaneBody({required this.line});

  final NutritionReviewLine line;

  @override
  Widget build(BuildContext context) {
    return BlocListener<NutritionCubit, NutritionState>(
      // An override just completed SUCCESSFULLY (position cleared, no
      // error) — the line is resolved, so drop it from the queue and
      // advance. The error check is load-bearing: a FAILED override also
      // clears the position (in the same emit that sets the error), and
      // advancing on it moved the selection past a line that was never
      // fixed (review B5).
      // …unless the fix raised an apply-to-all offer: then the pane stays
      // on this line until the admin applies or declines (and the receipt
      // is dismissed), and advances at that moment instead.
      // …and unless a plain Confirm (or a pick) left the line waiting on an
      // amount: the pane stays on it, the field focused (C).
      listenWhen: (previous, current) => paneAdvances(
        previous,
        current,
        queueMatchOf(current.matches ?? const [], line)?.position,
      ),
      listener: (context, _) =>
          context.read<NutritionReviewCubit>().completeFix(),
      child: BlocBuilder<NutritionCubit, NutritionState>(
        builder: (context, state) {
          final matches = state.matches;
          if (matches == null) {
            if (state.error != null) {
              return _FixMessage(
                text: state.error!,
                isError: true,
                onRetry: () =>
                    context.read<NutritionCubit>().loadMatches(force: true),
              );
            }
            return const Center(
              child: CircularProgressIndicator(color: SaltColors.maroon),
            );
          }
          final match = queueMatchOf(matches, line);
          if (match == null) {
            // No line of the recipe reads the queued text: a save since the
            // last compute edited or removed it. Nothing here is this line —
            // but an apply made from it still shows its receipt (O17).
            const gone = _FixMessage(
              text:
                  'This line was edited or removed since the queue was '
                  "built. Recompute the recipe's nutrition to refresh it.",
              isError: false,
            );
            final receipt = state.applied;
            if (receipt == null) {
              return gone;
            }
            final cubit = context.read<NutritionCubit>();
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              children: [
                ApplyToAllStrip(
                  offer: null,
                  applied: receipt,
                  applying: state.applying,
                  onApply: () {},
                  onDismiss: () {},
                  onDismissReceipt: cubit.dismissReceipt,
                  promised: line.lines > 1 ? othersPromised(line) : null,
                ),
                gone,
              ],
            );
          }
          return _FixContent(line: line, match: match, state: state);
        },
      ),
    );
  }
}

class _FixContent extends StatefulWidget {
  const _FixContent({
    required this.line,
    required this.match,
    required this.state,
  });

  final NutritionReviewLine line;
  final IngredientMatch match;
  final NutritionState state;

  @override
  State<_FixContent> createState() => _FixContentState();
}

class _FixContentState extends State<_FixContent> {
  /// The fix panel's amount field — where "Enter edible grams" lands.
  final FocusNode _amountFocus = FocusNode();

  @override
  void dispose() {
    _amountFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final match = widget.match;
    final state = widget.state;
    final cubit = context.read<NutritionCubit>();
    final held = isHeldLine(match);
    final busy = state.overridingPosition != null || state.applying;
    final bucket = matchBucketOf(match);
    final amountFirst = confirmsWithAmount(match);
    void confirm() =>
        cubit.override(match.position, raw: line.raw, confirmed: true);
    void skip() => cubit.override(match.position, raw: line.raw, skipped: true);
    final waiting = openLinesBesides(state.matches ?? const [], match.position);
    // The pane's cubit is keyed by this one queue line (_FixPane), so every
    // offer and receipt it holds is this line's own decision — shown
    // wherever its anchor landed: on another twin of the line than
    // [match] (Run 054 O12), or unanchored (O17). Filtering them by the
    // row hid them and stuck the pane, which waits for them to close.
    final offer = state.offer;
    final receipt = state.applied;
    // The split shows only BEFORE the decision, on a group that promises.
    final split =
        line.lines > 1 &&
        line.finishes > 0 &&
        state.offer == null &&
        state.applied == null &&
        const {
          MatchBucket.check,
          MatchBucket.noAmount,
          MatchBucket.noMatch,
        }.contains(bucket);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${line.recipe.title} · ingredient line ${line.position}',
            style: const TextStyle(fontSize: 11.5, color: SaltColors.muted),
          ),
          const SizedBox(height: 3),
          Text(
            line.raw,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          WhyLine(match: match, bucket: bucket),
          CurrentMatch(match: match, bucket: bucket),
          // A failed Skip/Confirm/Save must say so — without this the
          // button re-enabled silently and the admin believed the fix
          // landed (review B5).
          if (state.error != null) ...[
            const SizedBox(height: 10),
            Text(
              state.error!,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: SaltColors.errInk,
              ),
            ),
          ],
          // Confirm and Skip sit above the fix panel (B) — except where the
          // amount block leads (C): its Confirm carries the amount, and its
          // Skip sits beside it.
          if (!amountFirst) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Ruling 5: a held medium or shell line leads with its two
                // ways out — the edible grams, or a skip — and offers a
                // confirm only for an eaten "plus" part, never a shell
                // weight.
                if (held)
                  FButton(
                    mainAxisSize: MainAxisSize.min,
                    onPress: busy ? null : _amountFocus.requestFocus,
                    prefix: const Icon(FLucideIcons.scale, size: 14),
                    child: const Text('Enter edible grams'),
                  ),
                if (held &&
                    hasEatenPlusPart(match) &&
                    offers(match, HoldDecision.confirm))
                  FButton(
                    variant: FButtonVariant.outline,
                    mainAxisSize: MainAxisSize.min,
                    onPress: busy ? null : confirm,
                    prefix: const Icon(FLucideIcons.check, size: 14),
                    child: const Text('Confirm'),
                  ),
                // Only a weak match WITH an amount can be blessed as-is;
                // without one, confirming resolves a line that contributes
                // nothing.
                if (!held &&
                    bucket == MatchBucket.check &&
                    match.grams != null &&
                    offers(match, HoldDecision.confirm))
                  FButton(
                    variant: FButtonVariant.outline,
                    mainAxisSize: MainAxisSize.min,
                    onPress: busy ? null : confirm,
                    prefix: const Icon(FLucideIcons.check, size: 14),
                    child: const Text('Confirm as-is'),
                  ),
                // C: a Check line with no grams confirms without an amount —
                // the server fetches the food's detail and converts the
                // line; one it cannot convert lands in No grams, and the
                // pane stays on it asking for the amount.
                if (confirmsWithoutAmount(match))
                  FButton(
                    variant: FButtonVariant.outline,
                    mainAxisSize: MainAxisSize.min,
                    onPress: busy ? null : confirm,
                    prefix: const Icon(FLucideIcons.check, size: 14),
                    child: const Text('Confirm'),
                  ),
                FButton(
                  variant: FButtonVariant.ghost,
                  mainAxisSize: MainAxisSize.min,
                  onPress: busy ? null : skip,
                  prefix: const Icon(FLucideIcons.ban, size: 14),
                  child: Text(held ? heldSkipLabelFor(match.hold) : 'Skip'),
                ),
              ],
            ),
          ],
          // Before the decision: what it finishes, by path (B).
          if (split) ...[
            const SizedBox(height: 12),
            FinishesSplit(line: line, match: match, waiting: waiting),
          ],
          if (offer != null || receipt != null) ...[
            const SizedBox(height: 12),
            ApplyToAllStrip(
              offer: offer,
              applied: receipt,
              applying: state.applying,
              onApply: cubit.applyToAll,
              onDismiss: cubit.dismissOffer,
              onDismissReceipt: cubit.dismissReceipt,
              promised: line.lines > 1 ? othersPromised(line) : null,
            ),
          ],
          const SizedBox(height: 12),
          FixPanel(
            match: match,
            busy: busy,
            onDone: () {},
            showCancel: false,
            amountFocus: _amountFocus,
            recipeTitle: line.recipe.title,
            onSkip: skip,
            group: line.lines > 1
                ? (
                    item: groupLabel(line),
                    others: line.lines - 1,
                    staysOn: staysOnIngredient(line),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// The recipes the group's `finishes` promises the APPLY completes, less
/// the decided line's own (its own confirm finishes that one, not the
/// apply). The pane's split, the offer and the receipt all hold to this one
/// list, so the pane never says one number and the strip another. (The
/// decided line's own recipe can still complete through the apply when a
/// second open line of it is in the group — Cranberry Pecan Muffins' two
/// pecan lines — and the receipt counts it as a bonus.)
List<({String id, String title})> othersPromised(NutritionReviewLine line) => [
  for (final r in line.finishesRecipes)
    if (r.id != line.recipe.id) r,
];

/// The pane's "What this decision finishes" (B), before the decision: this
/// line alone — its recipe finishes only when it is the recipe's last open
/// line AND a confirm can count it: it has grams, or it is a No grams line
/// whose confirm carries the amount (the server's `finishes`, S1) — and
/// then the apply to the rest of the group, with the recipes it completes
/// by name.
class FinishesSplit extends StatelessWidget {
  const FinishesSplit({
    super.key,
    required this.line,
    required this.match,
    required this.waiting,
  });

  final NutritionReviewLine line;

  /// The group's example line as the recipe holds it now.
  final IngredientMatch match;

  /// The example recipe's other open lines.
  final List<IngredientMatch> waiting;

  @override
  Widget build(BuildContext context) {
    const bold = TextStyle(fontWeight: FontWeight.w700);
    const body = TextStyle(fontSize: 12.5, color: SaltColors.ink);
    final alone =
        waiting.isEmpty &&
            (match.grams != null ||
                matchBucketOf(match) == MatchBucket.noAmount)
        ? 1
        : 0;
    final names = [for (final r in othersPromised(line)) r.title];
    final others = line.lines - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: SaltColors.hairline),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What this decision finishes',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: SaltColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'This line only: ', style: bold),
                TextSpan(text: alone == 1 ? '1 recipe.' : '0 recipes.'),
                if (waiting.isNotEmpty) ...[
                  TextSpan(text: ' ${line.recipe.title} still waits on '),
                  TextSpan(
                    text: waiting.length == 1
                        ? waiting.single.raw
                        : '${waiting.length} more lines',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                  const TextSpan(text: '.'),
                ],
              ],
            ),
            style: body,
          ),
          // An apply that completes nothing more is not promised (a No
          // grams group finishes only the example's own recipe).
          if (names.isNotEmpty) ...[
            const SizedBox(height: 5),
            Wrap(
              spacing: 6,
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Then Apply to the other '
                  '${others == 1 ? '1 line' : '$others lines'}:',
                  style: body.merge(bold),
                ),
                FinishesPill(
                  names.length == 1
                      ? '1 recipe complete'
                      : '${names.length} recipes complete',
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                names.length > 4
                    ? '${names.take(4).join(', ')} … +${names.length - 4}'
                    : names.join(', '),
                style: const TextStyle(fontSize: 11.5, color: SaltColors.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Nothing selected — the fix pane's resting state.
class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Select a line to fix its match and amount.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: SaltColors.muted),
        ),
      ),
    );
  }
}

class _FixMessage extends StatelessWidget {
  const _FixMessage({required this.text, required this.isError, this.onRetry});

  final String text;
  final bool isError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isError ? SaltColors.errInk : SaltColors.muted,
                fontWeight: isError ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 10),
              FButton(
                variant: FButtonVariant.outline,
                mainAxisSize: MainAxisSize.min,
                onPress: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The whole-queue empty state — nothing flagged anywhere.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Icon(FLucideIcons.circleCheck, size: 40, color: SaltColors.okInk),
            SizedBox(height: 12),
            Text(
              'Every ingredient line is matched — nothing to review.',
              style: TextStyle(fontSize: 15, color: SaltColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
