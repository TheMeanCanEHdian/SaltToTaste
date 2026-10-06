import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';
import 'package:salt_shared/salt_shared.dart' show HoldDecision;

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_badge.dart';
import 'package:salt_app/features/nutrition/apply_to_all_strip.dart';
import 'package:salt_app/features/nutrition/match_fix_panel.dart';
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';
import 'package:salt_app/features/nutrition/recipe_fix_panel.dart';

/// Opens the ingredient match review sheet (approved A+C hybrid redesign).
/// Everyone can read it; only admins get the change-match / set-amount / skip
/// actions. Wide screens get a centered dialog; phones a full-height sheet.
/// [cubit] is another recipe's (a child recipe's sheet, v41) — the caller
/// owns it — else the one in [context]; [parent] names the recipe for the
/// recipe fix panel.
Future<void> showReviewSheet(
  BuildContext context, {
  required bool isAdmin,
  NutritionCubit? cubit,
  ReviewParent? parent,
}) {
  final sheetCubit = (cubit ?? context.read<NutritionCubit>())..loadMatches();
  final wide = MediaQuery.sizeOf(context).width >= Breakpoints.detailTwoColumn;
  if (!wide) {
    return showFSheet<void>(
      context: context,
      side: FLayout.btt,
      useSafeArea: true,
      mainAxisMaxRatio: null,
      builder: (context) => BlocProvider.value(
        value: sheetCubit,
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: _ReviewSheet(isAdmin: isAdmin, parent: parent),
          ),
        ),
      ),
    );
  }
  return showFDialog<void>(
    context: context,
    builder: (context, _, animation) => BlocProvider.value(
      value: sheetCubit,
      child: _ReviewSheet(
        isAdmin: isAdmin,
        animation: animation,
        parent: parent,
      ),
    ),
  );
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.isAdmin, this.animation, this.parent});

  final bool isAdmin;
  final Animation<double>? animation;
  final ReviewParent? parent;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet>
    with TickerProviderStateMixin {
  // Created up front, not lazily: a sheet with nothing to review never
  // reads it, and a lazy one was first built in dispose(), where looking up
  // the TickerMode of a deactivated element throws.
  late final FTabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = FTabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NutritionCubit>().state;
    final matches = state.matches;
    // An apply-to-all in flight walks every other recipe; a decision made on
    // another row meanwhile would race its receipt.
    final busy = state.overridingPosition != null || state.applying;
    // The row that just raised an offer (or holds its receipt) may have moved
    // into a collapsed group by the very decision that raised it.
    final spotlight = state.offer?.position ?? state.applied?.position;

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
      parent: widget.parent,
      busy: busy,
      spotlight: spotlight,
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
              parent: widget.parent,
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
            // A section has no serving basis of its own: the basis PUT
            // takes no section and would set its HOST's (v44).
            if (widget.isAdmin &&
                context.read<NutritionCubit>().section == null &&
                state.nutrition != null &&
                state.nutrition!.servingBasis != null)
              _BasisRow(state: state),
            const Divider(height: 1, color: SaltColors.hairline),
            // A failed action (Skip/Confirm/Save — network blip, expired
            // session, server reject) must be visible: once matches are
            // loaded, _LoadingOrError never shows, so without this strip
            // the admin believes the fix was applied (review B5).
            if (matches != null && state.error != null)
              Container(
                width: double.infinity,
                color: SaltColors.errBg,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(
                  state.error!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: SaltColors.errInk,
                  ),
                ),
              ),
            // A receipt whose line a save has since edited or removed stands
            // under no row; it is shown here, above the list, until
            // dismissed — never dropped (Run 053 O17).
            if (state.applied case final receipt? when receipt.position == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: ApplyToAllStrip(
                  offer: null,
                  applied: receipt,
                  applying: state.applying,
                  onApply: () {},
                  onDismiss: () {},
                  onDismissReceipt: context
                      .read<NutritionCubit>()
                      .dismissReceipt,
                ),
              ),
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
                child: const Icon(FLucideIcons.x, size: 19),
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
    required this.parent,
    required this.busy,
    required this.spotlight,
    required this.attention,
    required this.counted,
    required this.skipped,
  });

  final bool isAdmin;
  final ReviewParent? parent;
  final bool busy;
  final List<IngredientMatch> attention;
  final List<IngredientMatch> counted;
  final List<IngredientMatch> skipped;

  /// The position whose apply-to-all offer or receipt is showing, if any —
  /// the group holding it opens so the strip is on screen.
  final int? spotlight;

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
            expandOn: attention.any((m) => m.position == spotlight),
            children: [
              for (final m in attention)
                _MatchRow(
                  key: ValueKey('att-${m.position}'),
                  match: m,
                  isAdmin: isAdmin,
                  parent: parent,
                  busy: busy,
                ),
            ],
          ),
        _CollapsibleGroup(
          title: 'Counted — looks good',
          dot: SaltColors.okInk,
          count: counted.length,
          initiallyExpanded: attention.isEmpty,
          expandOn: counted.any((m) => m.position == spotlight),
          children: [
            for (final m in counted)
              _MatchRow(
                key: ValueKey('ok-${m.position}'),
                match: m,
                isAdmin: isAdmin,
                parent: parent,
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
            expandOn: skipped.any((m) => m.position == spotlight),
            children: [
              for (final m in skipped)
                _MatchRow(
                  key: ValueKey('sk-${m.position}'),
                  match: m,
                  isAdmin: isAdmin,
                  parent: parent,
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
    this.expandOn = false,
  });

  final String title;
  final Color dot;
  final int count;
  final bool initiallyExpanded;
  final List<Widget> children;

  /// Opens the group (once, when this turns true) because a child needs to
  /// be seen — the row a just-made decision moved here along with its
  /// apply-to-all offer. The person can still collapse it afterwards.
  final bool expandOn;

  @override
  State<_CollapsibleGroup> createState() => _CollapsibleGroupState();
}

class _CollapsibleGroupState extends State<_CollapsibleGroup> {
  late bool _expanded = widget.initiallyExpanded || widget.expandOn;

  @override
  void didUpdateWidget(_CollapsibleGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expandOn && !oldWidget.expandOn && !_expanded) {
      _expanded = true;
    }
  }

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
                  _expanded
                      ? FLucideIcons.chevronDown
                      : FLucideIcons.chevronRight,
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

/// The one line under a not-routed reference row's "not counted" badge:
/// why the engine counts nothing for it (v42, Q2 (a)); null for any other
/// reason.
String? notRoutedNote(String? reason) => switch (reason) {
  'section' => 'Its section has no totals yet — not counted',
  'served_with' => 'Served with this recipe, not made from it — not counted',
  'no_amount' => 'No amount on the line — not counted',
  'no_share' => 'No share the yield can read — not counted',
  'no_ingredients' => 'Its section lists no ingredients — not counted',
  _ => null,
};

class _MatchRow extends StatefulWidget {
  const _MatchRow({
    super.key,
    required this.match,
    required this.isAdmin,
    required this.busy,
    this.parent,
  });

  final IngredientMatch match;
  final bool isAdmin;
  final bool busy;
  final ReviewParent? parent;

  @override
  State<_MatchRow> createState() => _MatchRowState();
}

class _MatchRowState extends State<_MatchRow> {
  bool _fixOpen = false;

  /// The fix panel's amount field — where "Enter edible grams" lands.
  final FocusNode _amountFocus = FocusNode();

  @override
  void dispose() {
    _amountFocus.dispose();
    super.dispose();
  }

  /// Opens the fix panel on its amount (ruling 5's "Enter edible grams").
  void _enterGrams() {
    final opening = !_fixOpen;
    setState(() => _fixOpen = opening);
    if (opening) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _amountFocus.requestFocus();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final b = matchBucketOf(m);
    final skipped = b == MatchBucket.skipped;
    final zero = zeroGuessOf(m);
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
                // A skipped zero keeps its hidden guess but reads skipped.
                if (zero && !skipped)
                  const SaltBadge('counts as zero', tone: SaltBadgeTone.neutral)
                // A reference the engine does not route counts nothing and
                // makes the label partial (v41, A3 a).
                else if (!skipped && m.child?.state == 'not_routed')
                  const SaltBadge('not counted', tone: SaltBadgeTone.neutral)
                else
                  _statusBadge(b),
              ],
            ),
            // Why a not-routed reference counts nothing (v42, Q2 (a)).
            if (!skipped && m.child?.state == 'not_routed')
              if (notRoutedNote(m.child?.reason) case final note?)
                Text(
                  note,
                  style: const TextStyle(fontSize: 12, color: SaltColors.muted),
                ),
            const SizedBox(height: 4),
            if (zero)
              ZeroRow(match: m, isAdmin: widget.isAdmin)
            else ...[
              WhyLine(match: m, bucket: b, recipeTitle: widget.parent?.title),
              CurrentMatch(match: m, bucket: b),
            ],
            // Members see where a routed row's numbers come from, not Change.
            if (!widget.isAdmin && _routedChild(m) != null) ...[
              const SizedBox(height: 8),
              _ActionBar([_openChild(context, _routedChild(m)!)]),
            ],
            if (widget.isAdmin) ...[
              const SizedBox(height: 8),
              _actions(context, b),
              // The apply-to-all offer (or its receipt) for THIS row, right
              // under the decision that raised it.
              BlocBuilder<NutritionCubit, NutritionState>(
                buildWhen: (previous, current) =>
                    previous.offer != current.offer ||
                    previous.applied != current.applied ||
                    previous.applying != current.applying,
                builder: (context, state) {
                  final offer = offerIsFor(state.offer, m) ? state.offer : null;
                  final receipt = receiptIsFor(state.applied, m)
                      ? state.applied
                      : null;
                  if (offer == null && receipt == null) {
                    return const SizedBox.shrink();
                  }
                  final cubit = context.read<NutritionCubit>();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ApplyToAllStrip(
                      offer: offer,
                      applied: receipt,
                      applying: state.applying,
                      onApply: cubit.applyToAll,
                      onDismiss: cubit.dismissOffer,
                      onDismissReceipt: cubit.dismissReceipt,
                    ),
                  );
                },
              ),
              if (_fixOpen) ...[
                const SizedBox(height: 8),
                // Close only on OBSERVED success for this row. A failed
                // save keeps the panel (and its staged fix) open with the
                // error strip above — closing at press time discarded the
                // admin's work as if it had saved (review B5).
                BlocListener<NutritionCubit, NutritionState>(
                  listenWhen: (previous, current) =>
                      previous.overridingPosition == m.position &&
                      current.overridingPosition == null &&
                      current.error == null,
                  listener: (context, _) => setState(() => _fixOpen = false),
                  child: m.child != null
                      ? RecipeFixPanel(
                          match: m,
                          busy: widget.busy,
                          parent: widget.parent,
                          onSkip: () => context.read<NutritionCubit>().override(
                            m.position,
                            raw: m.raw,
                            skipped: true,
                          ),
                        )
                      : FixPanel(
                          match: m,
                          busy: widget.busy,
                          onDone: () => setState(() => _fixOpen = false),
                          amountFocus: _amountFocus,
                        ),
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
    MatchBucket.check => const SaltBadge(
      'check match',
      tone: SaltBadgeTone.warn,
    ),
    MatchBucket.noAmount => const SaltBadge(
      'no amount',
      tone: SaltBadgeTone.info,
    ),
    MatchBucket.noMatch => const SaltBadge('no match', tone: SaltBadgeTone.err),
    MatchBucket.skipped => const SaltBadge(
      'skipped',
      tone: SaltBadgeTone.neutral,
    ),
    MatchBucket.chooseRecipe => const SaltBadge(
      'choose recipe',
      tone: SaltBadgeTone.warn,
    ),
  };

  /// The routed child of [m] that has a sheet of its own, or null.
  RecipeRef? _routedChild(IngredientMatch m) {
    final child = m.child;
    return child != null && child.state == 'routed' && child.slug != null
        ? child
        : null;
  }

  /// "Open the recipe's matches" (v41): the child recipe's own review
  /// sheet, on a cubit of its own that closes with the sheet — the child's
  /// lines are where its numbers come from.
  Widget _openChild(BuildContext context, RecipeRef child) => FButton(
    variant: FButtonVariant.ghost,
    mainAxisSize: MainAxisSize.min,
    onPress: () {
      final cubit = NutritionCubit(
        context.read<NutritionRepository>(),
        child.slug!,
        // A section's sheet reads its own lines and totals (v44).
        section: child.section,
      )..load();
      showReviewSheet(
        context,
        isAdmin: widget.isAdmin,
        cubit: cubit,
        parent: (title: child.title ?? child.slug!, hasSections: null),
      ).whenComplete(cubit.close);
    },
    prefix: const Icon(FLucideIcons.book, size: 14),
    suffix: const Icon(FLucideIcons.chevronRight, size: 14),
    child: const Text("Open the recipe's matches"),
  );

  /// A reference line's own bar (v41), from the action table: a routed row
  /// offers Change (the recipe panel) and its child's sheet; a held one
  /// Choose a recipe and Skip — and a poured-away marinade its Confirm (the
  /// open panel carries both, so the bar drops them); a
  /// reference the engine does not route, Skip alone (A3 a).
  Widget _referenceActions(BuildContext context, RecipeRef child) {
    final cubit = context.read<NutritionCubit>();
    final m = widget.match;
    final busy = widget.busy;
    final routed = child.state == 'routed';
    return _ActionBar([
      if (offers(m, HoldDecision.recipe))
        _Action(
          icon: _fixOpen
              ? FLucideIcons.x
              : routed
              ? FLucideIcons.pencil
              : FLucideIcons.book,
          label: _fixOpen
              ? 'Close'
              : routed
              ? 'Change'
              : 'Choose a recipe',
          primary: !routed && !_fixOpen,
          onPressed: busy ? null : () => setState(() => _fixOpen = !_fixOpen),
        ),
      if (!routed && !_fixOpen && offers(m, HoldDecision.confirm))
        _Action(
          icon: FLucideIcons.check,
          label: 'Confirm (poured away)',
          onPressed: busy
              ? null
              : () => cubit.override(m.position, raw: m.raw, confirmed: true),
        ),
      if (!routed && !_fixOpen && offers(m, HoldDecision.skip))
        _Action(
          icon: FLucideIcons.ban,
          label: 'Skip',
          onPressed: busy
              ? null
              : () => cubit.override(m.position, raw: m.raw, skipped: true),
        ),
      if (_routedChild(m) case final routedChild?)
        _openChild(context, routedChild),
    ]);
  }

  Widget _actions(BuildContext context, MatchBucket b) {
    final cubit = context.read<NutritionCubit>();
    final busy = widget.busy;
    final toggleFix = busy ? null : () => setState(() => _fixOpen = !_fixOpen);
    if (widget.match.child case final child? when b != MatchBucket.skipped) {
      return _referenceActions(context, child);
    }
    if (b == MatchBucket.skipped) {
      return _ActionBar([
        _Action(
          icon: FLucideIcons.undo2,
          label: 'Include again',
          // Un-skip, back to automatic triage — NOT confirmed:true, which
          // would bless whatever match the line had and hide it from the
          // admin queue as resolved (review B7).
          onPressed: busy
              ? null
              : () => cubit.override(
                  widget.match.position,
                  raw: widget.match.raw,
                  skipped: false,
                ),
        ),
        _Action(
          icon: FLucideIcons.slidersHorizontal,
          label: 'Fix…',
          onPressed: toggleFix,
        ),
      ]);
    }
    // Ruling 5: a held medium or shell line leads with its two ways out;
    // Confirm only where the row carries an eaten "plus" part.
    // A held line in No grams (a pick alone kept its hold) leads the same
    // way (Run 054 S5/O6).
    if ((b == MatchBucket.check || b == MatchBucket.noAmount) &&
        isHeldLine(widget.match)) {
      return _ActionBar([
        _Action(
          icon: _fixOpen ? FLucideIcons.x : FLucideIcons.scale,
          label: _fixOpen ? 'Close' : 'Enter edible grams',
          primary: !_fixOpen,
          onPressed: busy ? null : _enterGrams,
        ),
        if (hasEatenPlusPart(widget.match) &&
            offers(widget.match, HoldDecision.confirm))
          _Action(
            icon: FLucideIcons.check,
            label: 'Confirm',
            onPressed: busy
                ? null
                : () => cubit.override(
                    widget.match.position,
                    raw: widget.match.raw,
                    confirmed: true,
                  ),
          ),
        _Action(
          icon: FLucideIcons.ban,
          label: heldSkipLabelFor(widget.match.hold),
          onPressed: busy
              ? null
              : () => cubit.override(
                  widget.match.position,
                  raw: widget.match.raw,
                  skipped: true,
                ),
        ),
      ]);
    }
    final primaryLabel = _fixOpen
        ? 'Close'
        : switch (b) {
            // A rendered two-part row (v41): Change undoes the rule.
            MatchBucket.counted when widget.match.parts.isNotEmpty => 'Change',
            MatchBucket.counted => 'Adjust…',
            MatchBucket.check => 'Fix match & amount',
            MatchBucket.noAmount => 'Add amount',
            MatchBucket.noMatch => 'Find a match',
            MatchBucket.skipped => 'Fix…',
            MatchBucket.chooseRecipe => 'Choose a recipe',
          };
    return _ActionBar([
      _Action(
        icon: _fixOpen ? FLucideIcons.x : FLucideIcons.slidersHorizontal,
        label: primaryLabel,
        primary: b != MatchBucket.counted && !_fixOpen,
        onPressed: toggleFix,
      ),
      // Blessing a weak match makes it count; with no amount it would count
      // nothing and merely vanish from the queue, so the line needs a pick
      // and an amount instead.
      // C: with no grams the confirm needs no amount — the server fetches
      // the food's detail and converts the line.
      if (confirmsWithoutAmount(widget.match))
        _Action(
          icon: FLucideIcons.check,
          label: 'Confirm',
          onPressed: busy
              ? null
              : () => cubit.override(
                  widget.match.position,
                  raw: widget.match.raw,
                  confirmed: true,
                ),
        ),
      if (b == MatchBucket.check &&
          widget.match.grams != null &&
          offers(widget.match, HoldDecision.confirm))
        _Action(
          icon: FLucideIcons.check,
          label: 'Confirm as-is',
          onPressed: busy
              ? null
              : () => cubit.override(
                  widget.match.position,
                  raw: widget.match.raw,
                  confirmed: true,
                ),
        ),
      _Action(
        icon: FLucideIcons.ban,
        label: 'Skip',
        onPressed: busy
            ? null
            : () => cubit.override(
                widget.match.position,
                raw: widget.match.raw,
                skipped: true,
              ),
      ),
    ]);
  }
}

/// Guided mode: steps through the attention list, worst first, with Back.
class _GuidedFlow extends StatefulWidget {
  const _GuidedFlow({
    required this.isAdmin,
    required this.parent,
    required this.busy,
    required this.attention,
    required this.onExit,
  });

  final bool isAdmin;
  final ReviewParent? parent;
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
          WhyLine(
            match: m,
            bucket: matchBucketOf(m),
            recipeTitle: widget.parent?.title,
          ),
          CurrentMatch(match: m, bucket: matchBucketOf(m)),
          if (widget.isAdmin) ...[
            const SizedBox(height: 12),
            // onDone only fires for Cancel ("changed nothing, next"). A
            // SAVED line leaves the attention list on the refresh, which
            // advances the flow by itself — incrementing here too skipped
            // the next flagged line on every fix (review B6).
            if (m.child != null)
              RecipeFixPanel(
                key: ValueKey('guided-${m.position}'),
                match: m,
                busy: widget.busy,
                parent: widget.parent,
              )
            else
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
                prefix: const Icon(FLucideIcons.arrowLeft, size: 15),
                child: const Text('Back'),
              ),
              const Spacer(),
              if (widget.isAdmin)
                FButton(
                  variant: FButtonVariant.ghost,
                  mainAxisSize: MainAxisSize.min,
                  // No _next(): on success the line leaves the attention
                  // list, so this index already shows the next flagged
                  // line — incrementing too skipped one (review B6). On
                  // failure the line stays and the error strip explains.
                  onPress: widget.busy
                      ? null
                      : () => cubit.override(
                          m.position,
                          raw: m.raw,
                          skipped: true,
                        ),
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
            child: const Icon(FLucideIcons.check, color: SaltColors.okInk),
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
  // Ruling 9: the counted zeros below the gate are said, not hidden.
  // A skipped zero counts nothing at all: it is among the skipped.
  final zeros =
      state.matches
          ?.where((match) => zeroGuessOf(match) && match.status == 'auto')
          .length ??
      0;
  // v41: how many of the counting lines are counted from a child recipe.
  final routed =
      state.matches
          ?.where(
            (match) =>
                match.child?.state == 'routed' && match.status != 'skipped',
          )
          .length ??
      0;
  final parts = <String>[
    '${nutrition.totalCount} lines',
    '${nutrition.matchedCount} counting'
        '${zeros > 0 ? ', $zeros of them as zero' : ''}'
        '${routed > 0 ? ', $routed of them from a recipe' : ''}'
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
                child: const Icon(FLucideIcons.minus, size: 16),
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
                child: const Icon(FLucideIcons.plus, size: 16),
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
