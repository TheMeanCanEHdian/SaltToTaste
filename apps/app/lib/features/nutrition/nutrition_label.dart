import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/widgets/salt_badge.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';
import 'package:salt_app/features/nutrition/review_sheet.dart';

/// The nutrition panel for a recipe detail page (approved P6 design): a
/// classic black-on-white FDA facts label with the app-palette match badge
/// and empty/stale/error states around it. Admin-only actions (compute,
/// recompute) are hidden for members; the server enforces regardless.
class NutritionPanel extends StatelessWidget {
  const NutritionPanel({
    super.key,
    required this.isAdmin,
    this.badgeFirst = false,
    this.startExpanded = true,
  });

  final bool isAdmin;

  /// Mobile layout: the match badge renders ABOVE the label so the
  /// transparency cue is seen before the numbers (approved P6 design);
  /// the wide right rail keeps it below.
  final bool badgeFirst;

  /// Whether the facts label opens expanded. Recipes with a hero image start
  /// collapsed (calories-and-above) so the image and the facts don't compete.
  final bool startExpanded;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NutritionCubit>().state;
    if (state.loading) {
      return const SizedBox.shrink();
    }
    final nutrition = state.nutrition;
    if (nutrition == null || !nutrition.exists) {
      // Members don't get an empty placeholder — only admins see the compute
      // box; for everyone else the panel takes no space at all.
      return isAdmin
          ? _EmptyState(isAdmin: isAdmin, state: state)
          : const SizedBox.shrink();
    }
    final badge = _MatchBadge(
      nutrition: nutrition,
      isAdmin: isAdmin,
      fullWidth: badgeFirst,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (nutrition.status == 'stale')
          _StaleBanner(state: state, isAdmin: isAdmin),
        if (badgeFirst) ...[badge, const SizedBox(height: 10)],
        Opacity(
          opacity: nutrition.status == 'stale' ? 0.55 : 1,
          child: _FdaLabel(
            nutrition: nutrition,
            initiallyExpanded: startExpanded,
          ),
        ),
        const SizedBox(height: 10),
        if (!badgeFirst) ...[badge, const SizedBox(height: 4)],
        const Text(
          'Computed from USDA FoodData Central',
          style: TextStyle(fontSize: 11.5, color: SaltColors.muted),
        ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              state.error!,
              style: const TextStyle(
                fontSize: 12.5,
                color: SaltColors.errInk,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isAdmin, required this.state});

  final bool isAdmin;
  final NutritionState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: SaltColors.panel,
        border: Border.all(color: SaltColors.hairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        // Mockup's empty-panel: a centered notice, no extra heading (the
        // narrow layout already titles the section).
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'No nutrition data yet',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            isAdmin
                ? 'Match ingredients against USDA FoodData Central to '
                      'build the label.'
                : 'Nutrition has not been computed for this recipe yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: SaltColors.muted),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 12),
            FButton(
              mainAxisSize: MainAxisSize.min,
              onPress: state.computing
                  ? null
                  : () => context.read<NutritionCubit>().compute(),
              prefix: state.computing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.bolt, size: 17),
              child: Text(state.computing ? 'Computing…' : 'Compute'),
            ),
            const SizedBox(height: 8),
            const Text(
              "Uses the server's FDC key · cached ingredients are free",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: SaltColors.muted),
            ),
          ],
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                state.error!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: SaltColors.errInk,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.state, required this.isAdmin});

  final NutritionState state;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: SaltColors.warnBg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_outlined,
            size: 16,
            color: SaltColors.warnInk,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Ingredients changed since this was computed.',
              style: TextStyle(
                fontSize: 12.5,
                color: SaltColors.warnInk,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isAdmin)
            FButton(
              variant: FButtonVariant.ghost,
              mainAxisSize: MainAxisSize.min,
              onPress: state.computing
                  ? null
                  : () => context.read<NutritionCubit>().compute(),
              child: Text(state.computing ? 'Computing…' : 'Recompute'),
            ),
        ],
      ),
    );
  }
}

class _MatchBadge extends StatelessWidget {
  const _MatchBadge({
    required this.nutrition,
    required this.isAdmin,
    this.fullWidth = false,
  });

  final RecipeNutrition nutrition;
  final bool isAdmin;

  /// Mobile: the badge stretches with the chevron pushed to the far edge
  /// (approved design); the rail keeps it intrinsic.
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final complete = !nutrition.needsReview;
    var label =
        '${nutrition.matchedCount}/${nutrition.totalCount} '
        'ingredients matched';
    if (nutrition.matchedCount >= nutrition.totalCount &&
        nutrition.lowConfidence > 0) {
      label = '$label — ${nutrition.lowConfidence} low-confidence — review';
    } else if (!complete) {
      label = '$label — review';
    }
    final badge = SaltBadge(
      label,
      tone: complete ? SaltBadgeTone.ok : SaltBadgeTone.warn,
      icon: complete ? LucideIcons.circleCheck : LucideIcons.triangleAlert,
      onTap: () => showReviewSheet(context, isAdmin: isAdmin),
      semanticHint: 'Opens ingredient review',
      expand: fullWidth,
    );
    // The parent Column stretches; the intrinsic (rail) pill must be left-
    // aligned so it hugs its label instead of spanning the whole column. The
    // fullWidth variant fills by design.
    return fullWidth
        ? badge
        : Align(alignment: Alignment.centerLeft, child: badge);
  }
}

/// The classic FDA facts panel. Deliberately black-on-white regardless of
/// app theme — the regulation label IS the design (approved mockup).
///
/// Collapsible: everything below the big Calories row (the %DV heading, the
/// nutrient rows, the vitamin block, and the footnote) folds behind an
/// in-label toggle bar so the panel can shrink to "calories and above". It
/// starts expanded and the choice is per-view only (not persisted).
class _FdaLabel extends StatefulWidget {
  const _FdaLabel({required this.nutrition, this.initiallyExpanded = true});

  final RecipeNutrition nutrition;

  /// Whether the fold starts open. Driven by the caller (collapsed when the
  /// recipe has a hero image).
  final bool initiallyExpanded;

  @override
  State<_FdaLabel> createState() => _FdaLabelState();
}

class _FdaLabelState extends State<_FdaLabel>
    with SingleTickerProviderStateMixin {
  late bool _expanded = widget.initiallyExpanded;

  // Drives the FCollapsible fold: 1 = fully open, 0 = clipped to nothing.
  late final AnimationController _foldController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: _expanded ? 1 : 0,
  );
  late final CurvedAnimation _fold = CurvedAnimation(
    parent: _foldController,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _fold.dispose();
    _foldController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _foldController.forward();
    } else {
      _foldController.reverse();
    }
  }

  RecipeNutrition get nutrition => widget.nutrition;

  // The nutrients that live in the collapsible region; when the recipe has
  // none of them there is nothing to fold, so the toggle bar is omitted.
  static const List<String> _detailKeys = [
    'fat',
    'saturated',
    'trans',
    'cholesterol',
    'sodium',
    'carbs',
    'fiber',
    'sugars',
    'sugars_added',
    'protein',
    'vitamin_d',
    'calcium',
    'iron',
    'potassium',
  ];

  bool get _hasDetails =>
      _detailKeys.any((k) => nutrition.perServing[k] != null);

  // Arimo: metric-compatible Arial/Helvetica for the regulation label
  // look (bundled so it renders in the offline build).
  static const TextStyle _base = TextStyle(
    color: Colors.black,
    fontSize: 12.5,
    height: 1.35,
    fontFamily: 'Arimo',
  );

  NutrientValue? _n(String key) => nutrition.perServing[key];

  String _amount(NutrientValue? value, {int decimals = 0}) {
    if (value == null) {
      return '—';
    }
    final rounded = decimals == 0
        ? value.amount.round().toString()
        : value.amount.toStringAsFixed(decimals);
    return '$rounded${value.unit == 'kcal' ? '' : value.unit}';
  }

  String _dv(NutrientValue? value) =>
      value?.dvPercent == null ? '' : '${value!.dvPercent!.round()}%';

  @override
  Widget build(BuildContext context) {
    final calories = _n('energy');
    final basis = nutrition.servingBasis;
    final grams = nutrition.totalGrams;
    final servingGrams = (grams != null && basis != null && basis > 0)
        ? grams / basis
        : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 1.5),
      ),
      child: DefaultTextStyle(
        style: _base,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: const Text(
                'Nutrition Facts',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                  fontFamily: 'Arimo',
                ),
              ),
            ),
            if (basis != null)
              Text('Per serving · serves $basis', style: _base),
            if (servingGrams != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Serving size',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${servingGrams.round()}g',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            const _Rule(8),
            const Text(
              'Amount per serving',
              style: TextStyle(
                color: Colors.black,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Calories',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  calories == null ? '—' : '${calories.amount.round()}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ],
            ),
            if (_hasDetails) ...[
              // FCollapsible clips the detail region as its value lerps 0→1;
              // at 0 it also drops the hidden rows from semantics and focus.
              AnimatedBuilder(
                animation: _fold,
                builder: (context, child) =>
                    FCollapsible(value: _fold.value, child: child!),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _details(),
                ),
              ),
              const SizedBox(height: 8),
              _ToggleBar(expanded: _expanded, onTap: _toggle),
            ],
          ],
        ),
      ),
    );
  }

  /// The collapsible region: the %DV heading down through the footnote. Kept
  /// out of [build] so the calories-and-above header stays readable at a
  /// glance and the fold point is unambiguous.
  List<Widget> _details() => [
    const _Rule(4),
    const Align(
      alignment: Alignment.centerRight,
      child: Text(
        '% Daily Value*',
        style: TextStyle(
          color: Colors.black,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    _row('Total Fat', _n('fat'), bold: true, decimals: 1),
    _row('Saturated Fat', _n('saturated'), indent: 1, decimals: 1),
    _row('Trans Fat', _n('trans'), indent: 1, decimals: 1, italicName: true),
    _row('Cholesterol', _n('cholesterol'), bold: true),
    _row('Sodium', _n('sodium'), bold: true),
    _row('Total Carbohydrate', _n('carbs'), bold: true, decimals: 1),
    _row('Dietary Fiber', _n('fiber'), indent: 1, decimals: 1),
    _row('Total Sugars', _n('sugars'), indent: 1, decimals: 1),
    _includesRow(_n('sugars_added')),
    _row('Protein', _n('protein'), bold: true, decimals: 1),
    const _Rule(8),
    _row('Vitamin D', _n('vitamin_d'), decimals: 1),
    _row('Calcium', _n('calcium')),
    _row('Iron', _n('iron'), decimals: 1),
    _row('Potassium', _n('potassium')),
    const _Rule(4),
    const Padding(
      padding: EdgeInsets.only(top: 4),
      child: Text(
        '* The % Daily Value tells you how much a nutrient in a '
        'serving contributes to a daily diet. 2,000 calories a day '
        'is used for general nutrition advice.',
        style: TextStyle(color: Colors.black, fontSize: 9.5),
      ),
    ),
  ];

  Widget _row(
    String name,
    NutrientValue? value, {
    bool bold = false,
    bool italicName = false,
    int indent = 0,
    int decimals = 0,
  }) {
    if (value == null) {
      return const SizedBox.shrink();
    }
    // The regulation label italicizes only the word "Trans".
    final TextSpan nameSpan;
    if (italicName && name.startsWith('Trans ')) {
      nameSpan = TextSpan(
        text: 'Trans',
        style: const TextStyle(fontStyle: FontStyle.italic),
        children: [
          TextSpan(
            text: name.substring('Trans'.length),
            style: const TextStyle(fontStyle: FontStyle.normal),
          ),
        ],
      );
    } else {
      nameSpan = TextSpan(
        text: name,
        style: TextStyle(
          fontStyle: italicName ? FontStyle.italic : FontStyle.normal,
        ),
      );
    }
    return _rowShell(
      indent: indent,
      name: TextSpan(
        style: TextStyle(
          color: Colors.black,
          fontSize: 12.5,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
        children: [
          nameSpan,
          TextSpan(
            text: ' ${_amount(value, decimals: decimals)}',
            style: const TextStyle(
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.normal,
            ),
          ),
        ],
      ),
      dv: _dv(value),
    );
  }

  /// The FDA's "Includes Xg Added Sugars" phrasing.
  Widget _includesRow(NutrientValue? value) {
    if (value == null) {
      return const SizedBox.shrink();
    }
    return _rowShell(
      indent: 2,
      name: TextSpan(
        text: 'Includes ${_amount(value, decimals: 1)} Added Sugars',
        style: const TextStyle(color: Colors.black, fontSize: 12.5),
      ),
      dv: _dv(value),
    );
  }

  Widget _rowShell({
    required int indent,
    required TextSpan name,
    required String dv,
  }) {
    return Container(
      padding: EdgeInsets.only(left: indent * 14.0, top: 2, bottom: 2),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.black)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text.rich(name)),
          const SizedBox(width: 8),
          // Fixed right-aligned column so every %DV lines up flush under the
          // "% Daily Value*" heading (the FDA label convention).
          SizedBox(
            width: 44,
            child: Text(
              dv,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The in-label collapse control: a full-width bar with a top rule (matching
/// the regulation row dividers) that folds the label to calories-and-above.
///
/// Built on [FTappable] (the Forui primitive [FButton] itself is built on)
/// rather than a themed button, so it carries Forui's focus/hover/keyboard
/// behaviour and button+expanded semantics while the child keeps the strict
/// black-on-white facts styling — the regulation label IS the design.
class _ToggleBar extends StatelessWidget {
  const _ToggleBar({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The label sits inside the detail page's SelectionArea; the bar is a
    // control, not selectable prose, so opt it out (matches the page's other
    // buttons and stops the I-beam cursor / text selection over its label).
    return SelectionContainer.disabled(
      child: FTappable(
        onPress: onTap,
        semanticsExpanded: expanded,
        builder: (context, states, child) => DecoratedBox(
          decoration: BoxDecoration(
            // Monochrome hover tint keeps the black-on-white aesthetic intact.
            color: states.contains(FTappableVariant.hovered)
                ? const Color(0x0A000000)
                : null,
            border: const Border(top: BorderSide(color: Colors.black)),
          ),
          child: child,
        ),
        child: MouseRegion(
          // FTappable defers the cursor by default; a control should show the
          // pointer like the app's FButtons do.
          cursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  expanded ? 'Hide details' : 'Full nutrition facts',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Arimo',
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 15,
                  color: Colors.black,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule(this.thickness);

  final double thickness;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: thickness,
      color: Colors.black,
      margin: const EdgeInsets.symmetric(vertical: 4),
    );
  }
}
