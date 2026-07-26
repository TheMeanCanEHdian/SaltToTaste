import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_badge.dart';
import 'package:salt_app/features/nutrition/match_fix_panel.dart';
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';

/// Opens the ingredient match review sheet (approved A+C hybrid redesign).
/// Everyone can read it; only admins get the change-match / set-amount / skip
/// actions. Wide screens get a centered dialog; phones a full-height sheet.
Future<void> showReviewSheet(BuildContext context, {required bool isAdmin}) {
  final cubit = context.read<NutritionCubit>()..loadMatches();
  final wide = MediaQuery.sizeOf(context).width >= Breakpoints.detailTwoColumn;
  if (!wide) {
    return showFSheet<void>(
      context: context,
      side: FLayout.btt,
      useSafeArea: true,
      mainAxisMaxRatio: null,
      builder: (context) => BlocProvider.value(
        value: cubit,
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: _ReviewSheet(isAdmin: isAdmin),
          ),
        ),
      ),
    );
  }
  return showFDialog<void>(
    context: context,
    builder: (context, _, animation) => BlocProvider.value(
      value: cubit,
      child: _ReviewSheet(isAdmin: isAdmin, animation: animation),
    ),
  );
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.isAdmin, this.animation});

  final bool isAdmin;
  final Animation<double>? animation;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet>
    with TickerProviderStateMixin {
  late final FTabController _tabs = FTabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NutritionCubit>().state;
    final matches = state.matches;
    final busy = state.overridingPosition != null;

    final attention = <IngredientMatch>[];
    final counted = <IngredientMatch>[];
    final skipped = <IngredientMatch>[];
    if (matches != null) {
      for (final m in matches) {
        final b = matchBucketOf(m);
        if (b == MatchBucket.skipped) {
          skipped.add(m);
        } else if (b == MatchBucket.counted) {
          counted.add(m);
        } else {
          attention.add(m);
        }
      }
      // Worst match first, so the most wrong lines lead.
      attention.sort((a, b) => a.confidence.compareTo(b.confidence));
    }

    final listView = _ListView(
      isAdmin: widget.isAdmin,
      busy: busy,
      attention: attention,
      counted: counted,
      skipped: skipped,
    );
    // With flagged lines, offer the Guided tab; otherwise the List stands
    // alone (no point in a "Guided (0)" tab).
    final Widget content;
    if (matches == null) {
      content = _LoadingOrError(state: state);
    } else if (attention.isEmpty) {
      content = listView;
    } else {
      content = FTabs(
        control: FTabManagedControl(controller: _tabs),
        expands: true,
        // The tab bar switches views; the inner lists scroll on their own.
        contentPhysics: const NeverScrollableScrollPhysics(),
        children: [
          FTabEntry(
            label: const SelectionContainer.disabled(child: Text('List')),
            child: listView,
          ),
          FTabEntry(
            label: SelectionContainer.disabled(
              child: Text('Guided (${attention.length})'),
            ),
            child: _GuidedFlow(
              isAdmin: widget.isAdmin,
              busy: busy,
              attention: attention,
              onExit: () => _tabs.animateTo(0),
            ),
          ),
        ],
      );
    }

    // Let people select and copy the text here — ingredient lines and USDA
    // food names are exactly what you want to paste into a search. Controls
    // opt out individually via SelectionContainer.disabled.
    final body = SelectionArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(state: state),
            if (widget.isAdmin &&
                state.nutrition != null &&
                state.nutrition!.servingBasis != null)
              _BasisRow(state: state),
            const Divider(height: 1, color: SaltColors.hairline),
            Expanded(child: content),
          ],
        ),
      ),
    );
    if (widget.animation == null) {
      return body;
    }
    return FDialog(
      animation: widget.animation,
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 760),
      builder: (context, style) => body,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final NutritionState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: const Text(
                    'Ingredient matches',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                if (_summaryLine(state) != null)
                  Text(
                    _summaryLine(state)!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: SaltColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          SelectionContainer.disabled(
            child: Tooltip(
              message: 'Close',
              child: FButton.icon(
                variant: FButtonVariant.ghost,
                onPress: () => Navigator.of(context).pop(),
                child: const Icon(Icons.close, size: 19),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingOrError extends StatelessWidget {
  const _LoadingOrError({required this.state});

  final NutritionState state;

  @override
  Widget build(BuildContext context) {
    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              state.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: SaltColors.errInk,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            FButton(
              variant: FButtonVariant.outline,
              mainAxisSize: MainAxisSize.min,
              onPress: () =>
                  context.read<NutritionCubit>().loadMatches(force: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    return const Center(
      child: CircularProgressIndicator(color: SaltColors.maroon),
    );
  }
}

/// The triage list: attention (open) over counted and skipped (collapsed).
class _ListView extends StatelessWidget {
  const _ListView({
    required this.isAdmin,
    required this.busy,
    required this.attention,
    required this.counted,
    required this.skipped,
  });

  final bool isAdmin;
  final bool busy;
  final List<IngredientMatch> attention;
  final List<IngredientMatch> counted;
  final List<IngredientMatch> skipped;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (attention.isNotEmpty)
          _CollapsibleGroup(
            title: 'Needs your attention',
            dot: SaltColors.warnInk,
            count: attention.length,
            initiallyExpanded: true,
            children: [
              for (final m in attention)
                _MatchRow(
                  key: ValueKey('att-${m.position}'),
                  match: m,
                  isAdmin: isAdmin,
                  busy: busy,
                ),
            ],
          ),
        _CollapsibleGroup(
          title: 'Counted — looks good',
          dot: SaltColors.okInk,
          count: counted.length,
          initiallyExpanded: attention.isEmpty,
          children: [
            for (final m in counted)
              _MatchRow(
                key: ValueKey('ok-${m.position}'),
                match: m,
                isAdmin: isAdmin,
                busy: busy,
              ),
          ],
        ),
        if (skipped.isNotEmpty)
          _CollapsibleGroup(
            title: 'Skipped',
            dot: SaltColors.muted,
            count: skipped.length,
            initiallyExpanded: false,
            children: [
              for (final m in skipped)
                _MatchRow(
                  key: ValueKey('sk-${m.position}'),
                  match: m,
                  isAdmin: isAdmin,
                  busy: busy,
                ),
            ],
          ),
      ],
    );
  }
}

class _CollapsibleGroup extends StatefulWidget {
  const _CollapsibleGroup({
    required this.title,
    required this.dot,
    required this.count,
    required this.initiallyExpanded,
    required this.children,
  });

  final String title;
  final Color dot;
  final int count;
  final bool initiallyExpanded;
  final List<Widget> children;

  @override
  State<_CollapsibleGroup> createState() => _CollapsibleGroupState();
}

class _CollapsibleGroupState extends State<_CollapsibleGroup> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FTappable(
          onPress: () => setState(() => _expanded = !_expanded),
          semanticsExpanded: _expanded,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: SaltColors.muted,
                ),
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: widget.dot,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${widget.count}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: SaltColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...widget.children,
        const Divider(height: 1, color: SaltColors.hairline),
      ],
    );
  }
}

class _MatchRow extends StatefulWidget {
  const _MatchRow({
    super.key,
    required this.match,
    required this.isAdmin,
    required this.busy,
  });

  final IngredientMatch match;
  final bool isAdmin;
  final bool busy;

  @override
  State<_MatchRow> createState() => _MatchRowState();
}

class _MatchRowState extends State<_MatchRow> {
  bool _fixOpen = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final b = matchBucketOf(m);
    final skipped = b == MatchBucket.skipped;
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SaltColors.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Opacity(
        opacity: skipped ? 0.6 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    m.raw,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _statusBadge(b),
              ],
            ),
            const SizedBox(height: 4),
            WhyLine(match: m, bucket: b),
            CurrentMatch(match: m, bucket: b),
            if (widget.isAdmin) ...[
              const SizedBox(height: 8),
              _actions(context, b),
              if (_fixOpen) ...[
                const SizedBox(height: 8),
                FixPanel(
                  match: m,
                  busy: widget.busy,
                  onDone: () => setState(() => _fixOpen = false),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  SaltBadge _statusBadge(MatchBucket b) => switch (b) {
    MatchBucket.counted => const SaltBadge('counted', tone: SaltBadgeTone.ok),
    MatchBucket.check => const SaltBadge('check match', tone: SaltBadgeTone.warn),
    MatchBucket.noAmount => const SaltBadge('no amount', tone: SaltBadgeTone.info),
    MatchBucket.noMatch => const SaltBadge('no match', tone: SaltBadgeTone.err),
    MatchBucket.skipped => const SaltBadge('skipped', tone: SaltBadgeTone.neutral),
  };

  Widget _actions(BuildContext context, MatchBucket b) {
    final cubit = context.read<NutritionCubit>();
    final busy = widget.busy;
    final toggleFix = busy ? null : () => setState(() => _fixOpen = !_fixOpen);
    if (b == MatchBucket.skipped) {
      return _ActionBar([
        _Action(
          icon: Icons.undo,
          label: 'Include again',
          onPressed: busy
              ? null
              : () => cubit.override(widget.match.position, confirmed: true),
        ),
        _Action(icon: Icons.tune, label: 'Fix…', onPressed: toggleFix),
      ]);
    }
    final primaryLabel = _fixOpen
        ? 'Close'
        : switch (b) {
            MatchBucket.counted => 'Adjust…',
            MatchBucket.check => 'Fix match & amount',
            MatchBucket.noAmount => 'Add amount',
            MatchBucket.noMatch => 'Find a match',
            MatchBucket.skipped => 'Fix…',
          };
    return _ActionBar([
      _Action(
        icon: _fixOpen ? Icons.close : Icons.tune,
        label: primaryLabel,
        primary: b != MatchBucket.counted && !_fixOpen,
        onPressed: toggleFix,
      ),
      if (b == MatchBucket.check)
        _Action(
          icon: Icons.check,
          label: 'Confirm as-is',
          onPressed: busy
              ? null
              : () => cubit.override(widget.match.position, confirmed: true),
        ),
      _Action(
        icon: Icons.block,
        label: 'Skip',
        onPressed: busy
            ? null
            : () => cubit.override(widget.match.position, skipped: true),
      ),
    ]);
  }
}

/// Guided mode: steps through the attention list, worst first, with Back.
class _GuidedFlow extends StatefulWidget {
  const _GuidedFlow({
    required this.isAdmin,
    required this.busy,
    required this.attention,
    required this.onExit,
  });

  final bool isAdmin;
  final bool busy;
  final List<IngredientMatch> attention;
  final VoidCallback onExit;

  @override
  State<_GuidedFlow> createState() => _GuidedFlowState();
}

class _GuidedFlowState extends State<_GuidedFlow> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final total = widget.attention.length;
    if (total == 0) {
      return _guidedDone(context);
    }
    final i = _i.clamp(0, total - 1);
    final m = widget.attention[i];
    final cubit = context.read<NutritionCubit>();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : i / total,
              minHeight: 6,
              backgroundColor: SaltColors.chipNeutral,
              color: SaltColors.maroon,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Line ${i + 1} of $total',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: SaltColors.muted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            m.raw,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          WhyLine(match: m, bucket: matchBucketOf(m)),
          CurrentMatch(match: m, bucket: matchBucketOf(m)),
          if (widget.isAdmin) ...[
            const SizedBox(height: 12),
            FixPanel(
              key: ValueKey('guided-${m.position}'),
              match: m,
              busy: widget.busy,
              onDone: _next,
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              FButton(
                variant: FButtonVariant.ghost,
                mainAxisSize: MainAxisSize.min,
                onPress: i == 0 ? null : () => setState(() => _i = i - 1),
                prefix: const Icon(Icons.arrow_back, size: 15),
                child: const Text('Back'),
              ),
              const Spacer(),
              if (widget.isAdmin)
                FButton(
                  variant: FButtonVariant.ghost,
                  mainAxisSize: MainAxisSize.min,
                  onPress: widget.busy
                      ? null
                      : () {
                          cubit.override(m.position, skipped: true);
                          _next();
                        },
                  child: const Text('Skip line'),
                ),
              const SizedBox(width: 8),
              FButton(
                variant: FButtonVariant.outline,
                mainAxisSize: MainAxisSize.min,
                onPress: _next,
                child: Text(i == total - 1 ? 'Finish' : 'Keep → next'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _next() {
    if (_i >= widget.attention.length - 1) {
      widget.onExit();
    } else {
      setState(() => _i = _i + 1);
    }
  }

  Widget _guidedDone(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: SaltColors.okBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: SaltColors.okInk),
          ),
          const SizedBox(height: 10),
          const Text(
            'All set',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Nothing else needs a look.',
            style: TextStyle(fontSize: 13, color: SaltColors.muted),
          ),
          const SizedBox(height: 14),
          FButton(
            mainAxisSize: MainAxisSize.min,
            onPress: widget.onExit,
            child: const Text('Back to list'),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar(this.actions);

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
    child: Wrap(spacing: 6, runSpacing: 6, children: actions),
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return FButton(
      variant: primary ? FButtonVariant.primary : FButtonVariant.outline,
      mainAxisSize: MainAxisSize.min,
      onPress: onPressed,
      prefix: Icon(icon, size: 14),
      child: Text(label),
    );
  }
}

/// "13 lines · 9 matched · 2 skipped · computed 2026-07-15".
String? _summaryLine(NutritionState state) {
  final nutrition = state.nutrition;
  if (nutrition == null || !nutrition.exists) {
    return null;
  }
  final parts = <String>[
    '${nutrition.totalCount} lines',
    '${nutrition.matchedCount} counting'
        '${nutrition.lowConfidence > 0 ? ' (${nutrition.lowConfidence} to review)' : ''}',
  ];
  final skipped =
      state.matches?.where((match) => match.status == 'skipped').length ?? 0;
  if (skipped > 0) {
    parts.add('$skipped skipped');
  }
  final computedAt = nutrition.computedAt;
  if (computedAt != null && computedAt.length >= 10) {
    parts.add('computed ${computedAt.substring(0, 10)}');
  }
  return parts.join(' · ');
}

/// Admin-only per-serving divisor control (kept next to the provenance it
/// affects, as in the approved P6 design).
class _BasisRow extends StatelessWidget {
  const _BasisRow({required this.state});

  final NutritionState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NutritionCubit>();
    final basis = state.nutrition!.servingBasis!;
    final busy = state.savingBasis;
    return SelectionContainer.disabled(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Row(
          children: [
            const Text(
              'Per-serving basis',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: 'Fewer servings',
              child: FButton.icon(
                variant: FButtonVariant.ghost,
                onPress: busy || basis <= 1
                    ? null
                    : () => cubit.setServingBasis(basis - 1),
                child: const Icon(Icons.remove, size: 16),
              ),
            ),
            Text(
              '$basis',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            Tooltip(
              message: 'More servings',
              child: FButton.icon(
                variant: FButtonVariant.ghost,
                onPress: busy || basis >= 1000
                    ? null
                    : () => cubit.setServingBasis(basis + 1),
                child: const Icon(Icons.add, size: 16),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                busy
                    ? 'Recomputing…'
                    : 'Totals divide by this — no new lookups.',
                style: const TextStyle(fontSize: 11.5, color: SaltColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
