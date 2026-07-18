import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_badge.dart';
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';

/// Opens the ingredient match review sheet (approved P6 design). Everyone
/// can read it; only admins get the Confirm/Change/Set-grams/Skip actions.
/// Wide screens get a centered dialog; phones a full-height bottom sheet.
Future<void> showReviewSheet(BuildContext context, {required bool isAdmin}) {
  final cubit = context.read<NutritionCubit>()..loadMatches();
  final wide = MediaQuery.sizeOf(context).width >= Breakpoints.detailTwoColumn;
  if (!wide) {
    return showFSheet<void>(
      context: context,
      side: FLayout.btt,
      useSafeArea: true,
      // A near-full-height sheet (~0.92): the default 9/16 cap would leave
      // the match list cramped. The FractionallySizedBox pins the 0.92; the
      // sheet frame paints nothing, so the white rounded surface is ours.
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
            child: _ReviewSheet(isAdmin: isAdmin, asBottomSheet: true),
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

class _ReviewSheet extends StatelessWidget {
  const _ReviewSheet({
    required this.isAdmin,
    this.asBottomSheet = false,
    this.animation,
  });

  final bool isAdmin;
  final bool asBottomSheet;

  /// The dialog route's scale/fade animation, threaded into [FDialog] on the
  /// wide (centered-dialog) path. Null on the bottom-sheet path.
  final Animation<double>? animation;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NutritionCubit>().state;
    final matches = state.matches;
    final body = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
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
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
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
                Tooltip(
                  message: 'Close',
                  child: FButton.icon(
                    variant: FButtonVariant.ghost,
                    onPress: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close, size: 19),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              'How each ingredient line was matched to USDA FoodData '
              'Central and converted to grams. The pill on the right shows '
              'the match confidence; lines marked "not matched" don\'t count '
              'toward the totals. Overrides persist and totals recompute '
              'instantly — no new lookups.',
              style: TextStyle(fontSize: 12.5, color: SaltColors.muted),
            ),
          ),
          if (state.error != null && matches != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                state.error!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: SaltColors.errInk,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (isAdmin &&
              state.nutrition != null &&
              state.nutrition!.servingBasis != null)
            _BasisRow(state: state),
          const Divider(height: 1, color: SaltColors.hairline),
          Expanded(
            child: matches == null
                ? (state.error != null
                      // A failed load is not "still loading": say so and
                      // offer a retry instead of a forever-spinner.
                      ? Center(
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
                                onPress: () => context
                                    .read<NutritionCubit>()
                                    .loadMatches(force: true),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : const Center(
                          child: CircularProgressIndicator(
                            color: SaltColors.maroon,
                          ),
                        ))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    itemCount: matches.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 18, color: SaltColors.hairline),
                    itemBuilder: (context, index) => _MatchRow(
                      match: matches[index],
                      isAdmin: isAdmin,
                      busy: state.overridingPosition != null,
                    ),
                  ),
          ),
        ],
      ),
    );
    if (asBottomSheet) {
      return body;
    }
    return FDialog(
      animation: animation,
      // Match the old Dialog's roomy width — the two-column provenance rows
      // need more than FDialog's 560 default.
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 760),
      builder: (context, style) => body,
    );
  }

  /// "13 lines · 12 matched · 1 skipped · computed 2026-07-15", from
  /// whatever is loaded so far.
  static String? _summaryLine(NutritionState state) {
    final nutrition = state.nutrition;
    if (nutrition == null || !nutrition.exists) {
      return null;
    }
    final parts = <String>[
      '${nutrition.totalCount} lines',
      '${nutrition.matchedCount} matched'
          '${nutrition.lowConfidence > 0 ? ' (${nutrition.lowConfidence} low-confidence)' : ''}',
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
}

/// Admin-only per-serving divisor control (the approved design keeps it
/// in the review sheet, next to the provenance it affects).
class _BasisRow extends StatelessWidget {
  const _BasisRow({required this.state});

  final NutritionState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NutritionCubit>();
    final basis = state.nutrition!.servingBasis!;
    final busy = state.savingBasis;
    return Padding(
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
              busy ? 'Recomputing…' : 'Totals divide by this — no new lookups.',
              style: const TextStyle(fontSize: 11.5, color: SaltColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.match,
    required this.isAdmin,
    required this.busy,
  });

  final IngredientMatch match;
  final bool isAdmin;
  final bool busy;

  /// The per-ingredient match-confidence badge. Label names the match state
  /// plainly — "high/medium/low" alone read as mystery ratings; these say what
  /// they mean (and unmatched lines are called out so it's clear they don't
  /// count toward the totals).
  SaltBadge get _confidenceBadge {
    final (label, tone) = switch (match.status) {
      'skipped' => ('skipped', SaltBadgeTone.neutral),
      'unmatched' => ('not matched', SaltBadgeTone.err),
      'overridden' || 'confirmed' => ('reviewed ✓', SaltBadgeTone.ok),
      _ when match.confidence >= 0.75 => ('strong match', SaltBadgeTone.ok),
      _ when match.confidence >= 0.5 => ('likely — check', SaltBadgeTone.warn),
      _ => ('weak — check', SaltBadgeTone.err),
    };
    return SaltBadge(label, tone: tone);
  }

  String get _gramSourceLabel => switch (match.gramSource) {
    'weight' => 'weight ✓ direct',
    'portion' => 'household portion',
    'density' => 'density est.',
    'piece' => 'piece est.',
    'override' => 'set by hand',
    _ => 'no grams',
  };

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NutritionCubit>();
    final skipped = match.status == 'skipped';
    return Opacity(
      opacity: skipped ? 0.55 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  match.raw,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _confidenceBadge,
            ],
          ),
          const SizedBox(height: 5),
          const SizedBox(height: 2),
          if (match.status == 'unmatched')
            // No USDA food — make it explicit that this line contributes
            // nothing, rather than showing a near-empty row.
            const Text(
              'Not counted — no USDA match found',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: SaltColors.errInk,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // The matched USDA food, labelled so it reads as the match.
                if (match.description != null)
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'matched to ',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: SaltColors.muted,
                          ),
                        ),
                        TextSpan(
                          text: match.description!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (match.dataType != null && match.dataType!.isNotEmpty)
                  SaltBadge(
                    match.dataType!,
                    tone: match.dataType == 'Foundation'
                        ? SaltBadgeTone.ok
                        : SaltBadgeTone.neutral,
                  ),
                Text(
                  match.grams == null
                      ? '· $_gramSourceLabel'
                      : '· ${match.grams!.toStringAsFixed(match.grams! < 10 ? 1 : 0)} g '
                            '($_gramSourceLabel)',
                  style: const TextStyle(fontSize: 12, color: SaltColors.muted),
                ),
                if (skipped)
                  const Text(
                    '· skipped',
                    style: TextStyle(
                      fontSize: 12,
                      color: SaltColors.muted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          if (isAdmin) ...[
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (match.status == 'auto')
                  _SmallAction(
                    icon: Icons.check,
                    label: 'Confirm',
                    onPressed: busy
                        ? null
                        : () => cubit.override(match.position, confirmed: true),
                  ),
                if (match.candidates.isNotEmpty)
                  _SmallAction(
                    icon: Icons.swap_horiz,
                    label: 'Change…',
                    onPressed: busy
                        ? null
                        : () => _pickCandidate(context, cubit),
                  ),
                // Grams scale a matched food; without one the server
                // rejects the write (422) — hide the dead end.
                if (match.fdcId != null)
                  _SmallAction(
                    icon: Icons.scale_outlined,
                    label: 'Set grams…',
                    onPressed: busy ? null : () => _setGrams(context, cubit),
                  ),
                if (!skipped)
                  _SmallAction(
                    icon: Icons.block,
                    label: 'Skip',
                    onPressed: busy
                        ? null
                        : () => cubit.override(match.position, skipped: true),
                  )
                else
                  _SmallAction(
                    icon: Icons.undo,
                    label: 'Include again',
                    onPressed: busy
                        ? null
                        : () => cubit.override(match.position, confirmed: true),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickCandidate(
    BuildContext context,
    NutritionCubit cubit,
  ) async {
    final picked = await showFDialog<MatchCandidate>(
      context: context,
      builder: (context, _, animation) => FDialog(
        animation: animation,
        // Bound the height so a long candidate list scrolls instead of
        // overflowing (the old SimpleDialog scrolled its children).
        constraints: const BoxConstraints(
          minWidth: 280,
          maxWidth: 480,
          maxHeight: 460,
        ),
        builder: (context, style) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                'Match for "${match.raw}"',
                style: style.titleTextStyle,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final candidate in match.candidates)
                      FTappable(
                        onPress: () => Navigator.of(context).pop(candidate),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  candidate.description,
                                  style: const TextStyle(fontSize: 13.5),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${candidate.dataType} · '
                                '${(candidate.confidence * 100).round()}%',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: SaltColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) {
      await cubit.override(match.position, fdcId: picked.fdcId);
    }
  }

  Future<void> _setGrams(BuildContext context, NutritionCubit cubit) async {
    final controller = TextEditingController(
      text: match.grams == null ? '' : match.grams!.toStringAsFixed(0),
    );
    try {
      await _promptAndSaveGrams(context, cubit, controller);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _promptAndSaveGrams(
    BuildContext context,
    NutritionCubit cubit,
    TextEditingController controller,
  ) async {
    final grams = await showFDialog<double>(
      context: context,
      builder: (context, _, animation) => FDialog(
        animation: animation,
        builder: (context, style) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Semantics(
                header: true,
                child: Text(
                  'Grams for "${match.raw}"',
                  style: style.titleTextStyle,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Semantics(
                label: 'Grams',
                child: FTextField(
                  control: FTextFieldControl.managed(controller: controller),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  hint: 'e.g. 250',
                  suffixBuilder: (_, _, _) => const Text('g'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: FButton(
                      variant: FButtonVariant.outline,
                      onPress: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FButton(
                      onPress: () => Navigator.of(
                        context,
                      ).pop(double.tryParse(controller.text)),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (grams != null && grams > 0) {
      await cubit.override(match.position, grams: grams);
    }
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FButton(
      variant: FButtonVariant.outline,
      mainAxisSize: MainAxisSize.min,
      onPress: onPressed,
      prefix: Icon(icon, size: 14),
      child: Text(label),
    );
  }
}
