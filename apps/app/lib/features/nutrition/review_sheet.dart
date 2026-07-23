import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_badge.dart';
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

// A line falls into exactly one bucket, derived from its stored match state.
// This mirrors the server: a line only "counts" with a food AND grams; only
// `auto` rows below 0.5 are flagged low-confidence.
enum _Bucket { counted, check, noAmount, noMatch, skipped }

_Bucket _bucketOf(IngredientMatch m) {
  if (m.status == 'skipped') return _Bucket.skipped;
  if (m.fdcId == null) return _Bucket.noMatch;
  if (m.grams == null) return _Bucket.noAmount;
  if (m.status == 'auto' && m.confidence < 0.5) return _Bucket.check;
  return _Bucket.counted;
}

const Map<String, double> _unitToGrams = {'g': 1, 'oz': 28.3495, 'lb': 453.592};

String _fmtAmount(double v) =>
    v < 10 ? v.toStringAsFixed(1) : v.round().toString();

String _gramSourceLabel(String? source) => switch (source) {
  'weight' => 'from the weight you gave',
  'portion' => 'USDA household portion',
  'density' => 'volume estimate',
  'piece' => 'typical size',
  'override' => 'set by hand',
  _ => 'no amount',
};

Widget _sourceChip(String? dataType) {
  if (dataType == null || dataType.isEmpty) {
    return const SizedBox.shrink();
  }
  final foundation = dataType == 'Foundation';
  return Tooltip(
    message: foundation
        ? "Foundation — USDA's newest lab-analyzed data (preferred)."
        : "SR Legacy — USDA's classic reference tables (frozen 2019).",
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: SaltColors.hairline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        dataType,
        style: const TextStyle(
          fontSize: 11,
          color: SaltColors.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
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
        final b = _bucketOf(m);
        if (b == _Bucket.skipped) {
          skipped.add(m);
        } else if (b == _Bucket.counted) {
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
    final b = _bucketOf(m);
    final skipped = b == _Bucket.skipped;
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
            _WhyLine(match: m, bucket: b),
            _CurrentMatch(match: m, bucket: b),
            if (widget.isAdmin) ...[
              const SizedBox(height: 8),
              _actions(context, b),
              if (_fixOpen) ...[
                const SizedBox(height: 8),
                _FixPanel(
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

  SaltBadge _statusBadge(_Bucket b) => switch (b) {
    _Bucket.counted => const SaltBadge('counted', tone: SaltBadgeTone.ok),
    _Bucket.check => const SaltBadge('check match', tone: SaltBadgeTone.warn),
    _Bucket.noAmount => const SaltBadge('no amount', tone: SaltBadgeTone.info),
    _Bucket.noMatch => const SaltBadge('no match', tone: SaltBadgeTone.err),
    _Bucket.skipped => const SaltBadge('skipped', tone: SaltBadgeTone.neutral),
  };

  Widget _actions(BuildContext context, _Bucket b) {
    final cubit = context.read<NutritionCubit>();
    final busy = widget.busy;
    final toggleFix = busy ? null : () => setState(() => _fixOpen = !_fixOpen);
    if (b == _Bucket.skipped) {
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
            _Bucket.counted => 'Adjust…',
            _Bucket.check => 'Fix match & amount',
            _Bucket.noAmount => 'Add amount',
            _Bucket.noMatch => 'Find a match',
            _Bucket.skipped => 'Fix…',
          };
    return _ActionBar([
      _Action(
        icon: _fixOpen ? Icons.close : Icons.tune,
        label: primaryLabel,
        primary: b != _Bucket.counted && !_fixOpen,
        onPressed: toggleFix,
      ),
      if (b == _Bucket.check)
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

/// The plain-language reason a line is where it is.
class _WhyLine extends StatelessWidget {
  const _WhyLine({required this.match, required this.bucket});

  final IngredientMatch match;
  final _Bucket bucket;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (bucket) {
      _Bucket.check => (
        'Match looks off — ${(match.confidence * 100).round()}% name '
            'confidence, but it is counting now',
        SaltColors.warnInk,
      ),
      _Bucket.noAmount => (
        'Matched, but no amount found — not counted yet',
        SaltColors.infoInk,
      ),
      _Bucket.noMatch => (
        'No USDA match found — not counted',
        SaltColors.errInk,
      ),
      _Bucket.counted => ('', SaltColors.muted),
      _Bucket.skipped => ('Excluded from the totals', SaltColors.muted),
    };
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Always shows what the line is currently matched to (even for no-amount /
/// skipped lines) — never hides it behind a "looks fine".
class _CurrentMatch extends StatelessWidget {
  const _CurrentMatch({required this.match, required this.bucket});

  final IngredientMatch match;
  final _Bucket bucket;

  @override
  Widget build(BuildContext context) {
    if (match.fdcId == null || match.description == null) {
      return const SizedBox.shrink();
    }
    final grams = match.grams;
    final amount = grams == null
        ? 'no amount'
        : '${_fmtAmount(grams)} g · ${_gramSourceLabel(match.gramSource)}';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'matched to ',
                      style: TextStyle(fontSize: 12.5, color: SaltColors.muted),
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
              _sourceChip(match.dataType),
              Text(
                '· $amount',
                style: const TextStyle(fontSize: 12, color: SaltColors.muted),
              ),
            ],
          ),
          // What the amount was computed against, so a volume/piece estimate
          // can be sanity-checked against the line.
          if (match.gramBasis != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'amount: ${match.gramBasis}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: SaltColors.muted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The combined "change the match AND set the amount" panel. Picking a
/// candidate recomputes grams on the server (showing the real recommended
/// amount); the amount field converts g / oz / lb.
class _FixPanel extends StatefulWidget {
  const _FixPanel({
    super.key,
    required this.match,
    required this.busy,
    required this.onDone,
  });

  final IngredientMatch match;
  final bool busy;
  final VoidCallback onDone;

  @override
  State<_FixPanel> createState() => _FixPanelState();
}

class _FixPanelState extends State<_FixPanel> {
  final TextEditingController _amt = TextEditingController();
  String _unit = 'g';

  /// A food picked in this panel but NOT yet saved. Nothing is written until
  /// Save, so picking a candidate can't silently change the label before you
  /// have had a chance to set the amount.
  int? _stagedFdcId;

  /// Whether the amount field was edited by hand (as opposed to being filled
  /// programmatically). On save, an untouched amount is omitted so the server
  /// recalculates it for the newly picked food instead of freezing the old one.
  bool _amountDirty = false;
  bool _settingText = false;

  void _setText(String value) {
    _settingText = true;
    _amt.text = value;
    _settingText = false;
  }

  // Manual USDA search: kept LOCAL to this panel (not in the cubit) so two
  // open rows never show each other's results.
  final TextEditingController _term = TextEditingController();
  List<MatchCandidate>? _results;
  bool _searching = false;
  String? _searchError;

  Future<void> _runSearch() async {
    final query = _term.text.trim();
    if (query.isEmpty || _searching) {
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final found = await context.read<NutritionRepository>().searchFoods(
        query,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _results = found;
        _searching = false;
      });
    } on RepositoryException catch (exception) {
      if (!mounted) {
        return;
      }
      setState(() {
        _searchError = exception.message;
        _searching = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _resetAmount();
    // Rebuild on every keystroke so the "≈ N g" readout and the Save-enabled
    // state track the field live (FTextField has no onChange callback).
    _amt.addListener(_onChanged);
  }

  void _onChanged() {
    if (!_settingText) {
      _amountDirty = true;
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(_FixPanel old) {
    super.didUpdateWidget(old);
    // A save landed and the server sent back the recomputed line — show its
    // amount and drop the staged pick, which is now the stored match.
    if (old.match.grams != widget.match.grams ||
        old.match.fdcId != widget.match.fdcId) {
      _unit = 'g';
      _stagedFdcId = null;
      _amountDirty = false;
      _resetAmount();
    }
  }

  void _resetAmount() {
    final g = widget.match.grams;
    _setText(g == null ? '' : _fmtAmount(g / _unitToGrams[_unit]!));
  }

  @override
  void dispose() {
    _amt.removeListener(_onChanged);
    _amt.dispose();
    _term.dispose();
    super.dispose();
  }

  double? _gramsFromField() {
    final v = double.tryParse(_amt.text.trim());
    return v == null ? null : v * _unitToGrams[_unit]!;
  }

  void _changeUnit(String u) {
    final grams = _gramsFromField();
    _unit = u;
    if (grams != null) {
      // Keep the gram value; the listener rebuilds with the new unit. Not a
      // hand edit — switching units must not count as setting the amount.
      _setText(_fmtAmount(grams / _unitToGrams[u]!));
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NutritionCubit>();
    final m = widget.match;
    final busy = widget.busy;

    // Current match first, then the API's ranked alternatives (deduped).
    final candidates = <MatchCandidate>[
      if (m.fdcId != null)
        MatchCandidate(
          fdcId: m.fdcId!,
          description: m.description ?? '(current match)',
          dataType: m.dataType ?? '',
          confidence: m.confidence,
        ),
      ...m.candidates.where((c) => c.fdcId != m.fdcId),
    ];

    final grams = _gramsFromField();
    // What is selected in this panel right now (staged pick, else the stored
    // match). Nothing is written until Save.
    final selectedId = _stagedFdcId ?? m.fdcId;
    final pickChanged = _stagedFdcId != null && _stagedFdcId != m.fdcId;
    final canSave = !busy && (pickChanged || (_amountDirty && grams != null));
    return Container(
      decoration: BoxDecoration(
        color: SaltColors.panel,
        border: Border.all(color: SaltColors.hairline),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Text(
              'Change the match & set the amount',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: SaltColors.muted,
              ),
            ),
          ),
          if (candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(
                'No other cached matches for this line.',
                style: TextStyle(fontSize: 12.5, color: SaltColors.muted),
              ),
            )
          else
            for (final c in candidates)
              _CandidateRow(
                candidate: c,
                isCurrent: c.fdcId == m.fdcId,
                selected: c.fdcId == selectedId,
                busy: busy,
                onPick: busy
                    ? null
                    : () => setState(() => _stagedFdcId = c.fdcId),
              ),
          _SearchRow(
            controller: _term,
            searching: _searching,
            onSearch: busy ? null : _runSearch,
          ),
          if (_searchError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                _searchError!,
                style: const TextStyle(
                  fontSize: 12,
                  color: SaltColors.errInk,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (_results != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
              child: Text(
                _results!.isEmpty
                    ? 'No USDA foods matched that term.'
                    : 'Results for "${_term.text.trim()}"',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: SaltColors.muted,
                ),
              ),
            ),
            for (final c in _results!)
              _CandidateRow(
                candidate: c,
                isCurrent: c.fdcId == m.fdcId,
                selected: c.fdcId == selectedId,
                busy: busy,
                onPick: busy
                    ? null
                    : () => setState(() => _stagedFdcId = c.fdcId),
              ),
          ],
          // The amount editor is all controls (field + unit toggle + save).
          SelectionContainer.disabled(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: SaltColors.hairline)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Amount',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: SaltColors.muted,
                    ),
                  ),
                  // What the current grams were computed from, so a volume or
                  // piece estimate can be sanity-checked before adjusting.
                  if (m.gramBasis != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'currently: ${m.gramBasis}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: SaltColors.muted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      SizedBox(
                        width: 92,
                        child: FTextField(
                          control: FTextFieldControl.managed(controller: _amt),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          hint: 'e.g. 250',
                        ),
                      ),
                      const SizedBox(width: 8),
                      _UnitToggle(unit: _unit, onChanged: _changeUnit),
                      const SizedBox(width: 10),
                      if (_unit != 'g' && grams != null)
                        Expanded(
                          child: Text(
                            '≈ ${grams.round()} g',
                            style: const TextStyle(
                              fontSize: 12,
                              color: SaltColors.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (pickChanged && !_amountDirty)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Leave this as-is and the amount is recalculated for '
                        'the food you picked.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: SaltColors.muted,
                        ),
                      ),
                    ),
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      FButton(
                        mainAxisSize: MainAxisSize.min,
                        // One explicit write: the staged food and (only if you
                        // actually typed one) the amount. An untouched amount is
                        // omitted so the server recalculates it for the new food
                        // rather than freezing the previous food's grams.
                        onPress: !canSave
                            ? null
                            : () {
                                cubit.override(
                                  m.position,
                                  fdcId: pickChanged ? _stagedFdcId : null,
                                  grams: _amountDirty ? grams : null,
                                );
                                widget.onDone();
                              },
                        child: const Text('Save match & amount'),
                      ),
                      const SizedBox(width: 8),
                      FButton(
                        variant: FButtonVariant.ghost,
                        mainAxisSize: MainAxisSize.min,
                        onPress: busy ? null : widget.onDone,
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Manual USDA search — the escape hatch when the matcher searched the wrong
/// words and every cached candidate is wrong.
class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.controller,
    required this.searching,
    required this.onSearch,
  });

  final TextEditingController controller;
  final bool searching;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    // A control row (a text field owns its own selection) — opt it out of the
    // sheet's SelectionArea so it doesn't fight the field or show an I-beam.
    return SelectionContainer.disabled(
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: SaltColors.hairline)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: FTextField(
                control: FTextFieldControl.managed(controller: controller),
                hint: 'Search USDA for a better match…',
                onSubmit: (_) => onSearch?.call(),
              ),
            ),
            const SizedBox(width: 8),
            FButton(
              variant: FButtonVariant.outline,
              mainAxisSize: MainAxisSize.min,
              onPress: searching ? null : onSearch,
              prefix: searching
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search, size: 15),
              child: Text(searching ? 'Searching…' : 'Search'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.isCurrent,
    required this.selected,
    required this.busy,
    required this.onPick,
  });

  final MatchCandidate candidate;

  /// The stored match — what the line uses today.
  final bool isCurrent;

  /// Chosen in this panel (staged, or the stored match when nothing is
  /// staged). Not written until Save.
  final bool selected;
  final bool busy;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    // A pick control, not prose — tapping it selects the food, so keep the
    // sheet's SelectionArea from swallowing the tap or showing an I-beam.
    return SelectionContainer.disabled(
      child: FTappable(
        onPress: onPick,
        child: Container(
          decoration: BoxDecoration(
            color: selected ? SaltColors.chip : null,
            border: const Border(top: BorderSide(color: SaltColors.hairline)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: selected
                    ? const Icon(
                        Icons.check,
                        size: 15,
                        color: SaltColors.maroon,
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  candidate.description,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: SaltColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isCurrent
                    ? 'current · ${(candidate.confidence * 100).round()}%'
                    : '${candidate.dataType} · '
                          '${(candidate.confidence * 100).round()}%',
                style: const TextStyle(fontSize: 11, color: SaltColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnitToggle extends StatelessWidget {
  const _UnitToggle({required this.unit, required this.onChanged});

  final String unit;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String u) {
      final selected = unit == u;
      return FTappable(
        onPress: () => onChanged(u),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          color: selected ? SaltColors.maroon : Colors.transparent,
          child: Text(
            u,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : SaltColors.muted,
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: SaltColors.hairline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [seg('g'), seg('oz'), seg('lb')],
        ),
      ),
    );
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
          _WhyLine(match: m, bucket: _bucketOf(m)),
          _CurrentMatch(match: m, bucket: _bucketOf(m)),
          if (widget.isAdmin) ...[
            const SizedBox(height: 12),
            _FixPanel(
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
