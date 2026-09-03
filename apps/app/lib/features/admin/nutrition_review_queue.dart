import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';

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
/// worst-first list of flagged ingredient lines on the left, the shared fix
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

/// The left pane: a header line over the worst-first list of flagged rows.
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
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              'No lines in this bucket.',
              style: TextStyle(fontSize: 13, color: SaltColors.muted),
            ),
          ),
        ),
    ];

    final header = Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SaltColors.hairline)),
      ),
      child: Text.rich(
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
            TextSpan(text: ' · ${state.filteredTotal} lines, worst first'),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
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

/// One flagged line in the queue: a bucket-coloured stripe, the recipe and raw
/// line, the current (often wrong) food, a bucket pill, and name confidence.
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
                    Text(
                      '${line.recipe.title} · line ${line.position}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: SaltColors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      line.raw,
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
      listenWhen: (previous, current) {
        if (current.error != null) {
          return false;
        }
        final settled = current.offer == null && current.applied == null;
        final fixLanded =
            previous.overridingPosition != null &&
            current.overridingPosition == null;
        final offerClosed =
            (previous.offer != null || previous.applied != null) && settled;
        return (fixLanded && settled) || offerClosed;
      },
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
          IngredientMatch? match;
          for (final m in matches) {
            if (m.position == line.position) {
              match = m;
              break;
            }
          }
          if (match == null) {
            // The line the queue pointed at is gone from the recipe (e.g. it
            // was just resolved and the refresh is landing) — a transient blank.
            return const _FixMessage(
              text: 'This line has been resolved.',
              isError: false,
            );
          }
          return _FixContent(line: line, match: match, state: state);
        },
      ),
    );
  }
}

class _FixContent extends StatelessWidget {
  const _FixContent({
    required this.line,
    required this.match,
    required this.state,
  });

  final NutritionReviewLine line;
  final IngredientMatch match;
  final NutritionState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NutritionCubit>();
    final busy = state.overridingPosition != null;
    final bucket = matchBucketOf(match);
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
          const SizedBox(height: 12),
          FixPanel(match: match, busy: busy, onDone: () {}, showCancel: false),
          if (state.offer?.position == match.position ||
              state.applied?.position == match.position) ...[
            const SizedBox(height: 12),
            ApplyToAllStrip(
              offer: state.offer?.position == match.position
                  ? state.offer
                  : null,
              applied: state.applied?.position == match.position
                  ? state.applied
                  : null,
              applying: state.applying,
              onApply: cubit.applyToAll,
              onDismiss: cubit.dismissApply,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (bucket == MatchBucket.check)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FButton(
                    variant: FButtonVariant.outline,
                    mainAxisSize: MainAxisSize.min,
                    onPress: busy
                        ? null
                        : () => cubit.override(match.position, confirmed: true),
                    prefix: const Icon(FLucideIcons.check, size: 14),
                    child: const Text('Confirm as-is'),
                  ),
                ),
              FButton(
                variant: FButtonVariant.ghost,
                mainAxisSize: MainAxisSize.min,
                onPress: busy
                    ? null
                    : () => cubit.override(match.position, skipped: true),
                prefix: const Icon(FLucideIcons.ban, size: 14),
                child: const Text('Skip'),
              ),
            ],
          ),
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
