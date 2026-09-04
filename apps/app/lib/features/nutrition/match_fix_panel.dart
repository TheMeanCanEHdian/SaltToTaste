import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';

import 'package:salt_shared/salt_shared.dart' show MatchBucket, matchBucketFor;

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/util/relative_age.dart';
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';

export 'package:salt_shared/salt_shared.dart' show MatchBucket;

/// The combined "change the match & set the amount" panel and the small pieces
/// it is built from ([WhyLine], [CurrentMatch], [CandidateRow], [SearchRow],
/// [UnitToggle]) plus the bucketing helpers.
///
/// Extracted from the per-recipe review sheet so the cross-recipe admin
/// nutrition-match queue can reuse exactly the same fix UX. Both surfaces drive
/// the same [NutritionCubit.override], so a fix looks and behaves identically
/// whether you reach it from one recipe's sheet or the whole-library queue.

/// Buckets an app-model match row via the ONE shared rule (salt_shared's
/// [matchBucketFor]) — the server's queue SQL mirrors the same rule, so the
/// two admin surfaces can never disagree about what still needs attention
/// (review B7).
MatchBucket matchBucketOf(IngredientMatch m) => matchBucketFor(
  status: m.status,
  fdcId: m.fdcId,
  grams: m.grams,
  confidence: m.confidence,
);

const Map<String, double> unitToGrams = {'g': 1, 'oz': 28.3495, 'lb': 453.592};

String fmtAmount(double v) =>
    v < 10 ? v.toStringAsFixed(1) : v.round().toString();

String gramSourceLabel(String? source) => switch (source) {
  'weight' => 'from the weight you gave',
  'portion' => 'USDA household portion',
  'density' => 'volume estimate',
  'piece' => 'typical size',
  'override' => 'set by hand',
  _ => 'no amount',
};

Widget sourceChip(String? dataType) {
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

/// The plain-language reason a line is where it is.
class WhyLine extends StatelessWidget {
  const WhyLine({super.key, required this.match, required this.bucket});

  final IngredientMatch match;
  final MatchBucket bucket;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (bucket) {
      // A weak match counts only when it has an amount; without one it is a
      // wrong food AND an unfilled amount, and it contributes nothing.
      MatchBucket.check => (
        'Match looks off — ${(match.confidence * 100).round()}% name '
            'confidence, '
            '${match.grams == null ? 'and no amount found — not counted' : 'but it is counting now'}',
        SaltColors.warnInk,
      ),
      MatchBucket.noAmount => (
        'Matched, but no amount found — not counted yet',
        SaltColors.infoInk,
      ),
      MatchBucket.noMatch => (
        'No USDA match found — not counted',
        SaltColors.errInk,
      ),
      MatchBucket.counted => ('', SaltColors.muted),
      MatchBucket.skipped => ('Excluded from the totals', SaltColors.muted),
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
class CurrentMatch extends StatelessWidget {
  const CurrentMatch({super.key, required this.match, required this.bucket});

  final IngredientMatch match;
  final MatchBucket bucket;

  @override
  Widget build(BuildContext context) {
    final description = match.description;
    if (match.fdcId == null) {
      // A deliberate no-match the engine explains — water, seasoning to
      // taste — says so; the badge alone read as "looks fine" for no reason.
      if (description == null || match.status != 'confirmed') {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '$description · counts as zero',
          style: const TextStyle(fontSize: 12.5, color: SaltColors.muted),
        ),
      );
    }
    if (description == null) {
      return const SizedBox.shrink();
    }
    final grams = match.grams;
    final amount = grams == null
        ? 'no amount'
        : '${fmtAmount(grams)} g · ${gramSourceLabel(match.gramSource)}';
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
              sourceChip(match.dataType),
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
class FixPanel extends StatefulWidget {
  const FixPanel({
    super.key,
    required this.match,
    required this.busy,
    required this.onDone,
    this.showCancel = true,
  });

  final IngredientMatch match;
  final bool busy;

  /// Fired ONLY by the Cancel button — an explicit "close without saving".
  /// Save deliberately fires nothing: the override is async, so hosts must
  /// observe success from cubit state (bucket change / attention-list
  /// shrink / error) rather than assume it at press time (review B5/B6).
  final VoidCallback onDone;

  /// Whether to show the ghost "Cancel" button. The review sheet opens the
  /// panel inline and uses it to close; the master-detail queue keeps the panel
  /// always open (there is nothing to close), so it hides the button.
  final bool showCancel;

  @override
  State<FixPanel> createState() => _FixPanelState();
}

class _FixPanelState extends State<FixPanel> {
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

  /// The text last seen in the field. A [TextEditingController] notifies its
  /// listeners on caret/selection moves too, so [_onChanged] compares against
  /// this to tell a real text edit from merely clicking into the box — only the
  /// former is a hand edit.
  String _lastText = '';

  void _setText(String value) {
    _settingText = true;
    _amt.text = value;
    _settingText = false;
    _lastText = value;
  }

  // Manual USDA search: kept LOCAL to this panel (not in the cubit) so two
  // open rows never show each other's results.
  final TextEditingController _term = TextEditingController();
  List<MatchCandidate>? _results;

  /// The last hand search's answer as a whole (its cache state and age).
  FoodSearch? _search;

  /// That answer when it was for the LINE's own words (the "Search live"
  /// under the candidate list), so the line's cache line can reflect it.
  FoodSearch? get _lineSearch {
    final search = _search;
    final query = widget.match.candidatesQuery;
    return search != null && query != null && search.query == query
        ? search
        : null;
  }

  /// The words a live search for this line asks: the server's own query
  /// (already normalized and rewritten, so the answer lands under the same
  /// cache key the line reads), falling back to the item and then the raw
  /// line — capped at the search route's 120-character limit.
  static String _lineTerm(IngredientMatch m) {
    final term = m.candidatesQuery ?? m.item ?? m.raw;
    return term.length > 120 ? term.substring(0, 120) : term;
  }

  bool _searching = false;
  String? _searchError;

  Future<void> _runSearch({String? term, bool fresh = false}) async {
    final query = (term ?? _term.text).trim();
    if (query.isEmpty || _searching) {
      return;
    }
    if (term != null) {
      _term.text = term;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final found = await context.read<NutritionRepository>().searchFoods(
        query,
        fresh: fresh,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _results = found.items;
        _search = found;
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
    final text = _amt.text;
    // Only an actual text change is a hand edit; clicking into the field (or
    // moving the caret) fires this listener too but must not mark the amount
    // dirty, or Save would freeze the displayed number instead of letting the
    // server recompute grams for a newly picked food.
    if (!_settingText && text != _lastText) {
      _amountDirty = true;
    }
    _lastText = text;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(FixPanel old) {
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
    _setText(g == null ? '' : fmtAmount(g / unitToGrams[_unit]!));
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
    return v == null ? null : v * unitToGrams[_unit]!;
  }

  void _changeUnit(String u) {
    if (u == _unit) {
      return;
    }
    final grams = _gramsFromField();
    if (grams != null) {
      // Keep the gram value under the new unit. Not a hand edit — switching
      // units must not count as setting the amount.
      _setText(fmtAmount(grams / unitToGrams[u]!));
    }
    // Always rebuild for the unit change itself: the field listener only fires
    // when the *text* changes, so relying on it drops the toggle's highlight
    // whenever the converted value renders identically (e.g. an empty field, or
    // a value that rounds the same) — the "didn't activate" bug.
    setState(() => _unit = u);
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
              CandidateRow(
                candidate: c,
                isCurrent: c.fdcId == m.fdcId,
                selected: c.fdcId == selectedId,
                busy: busy,
                onPick: busy
                    ? null
                    : () => setState(() => _stagedFdcId = c.fdcId),
              ),
          // Shown whenever FDC was asked — including a line it found NOTHING
          // for, which is the answer most worth refreshing. After a live
          // search for this line's own words, the line reflects that answer.
          if (m.candidatesCachedAt != null)
            CacheLine(
              query: m.candidatesQuery,
              cachedAt: _lineSearch?.cachedAt ?? m.candidatesCachedAt!,
              live: _lineSearch != null && !_lineSearch!.cached,
              onSearchLive: busy || _searching
                  ? null
                  : () => _runSearch(term: _lineTerm(m), fresh: true),
            ),
          SearchRow(
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
              CandidateRow(
                candidate: c,
                isCurrent: c.fdcId == m.fdcId,
                selected: c.fdcId == selectedId,
                busy: busy,
                onPick: busy
                    ? null
                    : () => setState(() => _stagedFdcId = c.fdcId),
              ),
            // The line above already speaks for a search of the line's own
            // words; say it once.
            if (_search != null &&
                _search!.cachedAt != null &&
                _lineSearch == null)
              CacheLine(
                query: _search!.query,
                cachedAt: _search!.cachedAt!,
                live: !_search!.cached,
                // Refresh the search this line speaks for, not whatever the
                // box says now.
                onSearchLive: _search!.cached && !busy && !_searching
                    ? () => _runSearch(term: _search!.query, fresh: true)
                    : null,
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
                      UnitToggle(unit: _unit, onChanged: _changeUnit),
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
                        // No onDone here: the override is async, so success
                        // must be OBSERVED from cubit state (the resolved
                        // line changes bucket / leaves the attention list),
                        // never assumed at press time — a failed save once
                        // advanced the guided flow and closed the panel as
                        // if it had worked (review B5/B6).
                        onPress: !canSave
                            ? null
                            : () => cubit.override(
                                m.position,
                                fdcId: pickChanged ? _stagedFdcId : null,
                                grams: _amountDirty ? grams : null,
                              ),
                        child: const Text('Save match & amount'),
                      ),
                      if (widget.showCancel) ...[
                        const SizedBox(width: 8),
                        FButton(
                          variant: FButtonVariant.ghost,
                          mainAxisSize: MainAxisSize.min,
                          onPress: busy ? null : widget.onDone,
                          child: const Text('Cancel'),
                        ),
                      ],
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
/// Where a candidate list came from and how old it is — one quiet line
/// with the age (the exact instant is the tooltip) and, for a cached
/// answer, the one action past the cache: a live search, which spends one
/// FDC request and replaces the stored answer for everyone.
class CacheLine extends StatelessWidget {
  const CacheLine({
    required this.cachedAt,
    required this.live,
    required this.onSearchLive,
    this.query,
    super.key,
  });

  /// When FDC was asked (UTC).
  final DateTime cachedAt;

  /// True when this answer was just fetched — nothing to refresh.
  final bool live;

  /// The words FDC was asked, when known (a hand search says; a line's
  /// candidate list does not).
  final String? query;
  final VoidCallback? onSearchLive;

  @override
  Widget build(BuildContext context) {
    final age = relativeAge(cachedAt);
    final asked = query == null ? 'FDC' : 'FDC asked for “$query”';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 5, 8, 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SaltColors.hairline)),
      ),
      child: Row(
        children: [
          Icon(
            live ? FLucideIcons.zap : FLucideIcons.clock,
            size: 12,
            color: live ? SaltColors.okInk : SaltColors.muted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: cachedAt.toLocal().toString(),
              child: Text(
                live ? '$asked · live, $age' : '$asked · cached $age',
                style: TextStyle(
                  fontSize: 11.5,
                  color: live ? SaltColors.okInk : SaltColors.muted,
                ),
              ),
            ),
          ),
          if (!live)
            FButton(
              variant: FButtonVariant.ghost,
              mainAxisSize: MainAxisSize.min,
              onPress: onSearchLive,
              prefix: const Icon(FLucideIcons.refreshCw, size: 12),
              child: const Text('Search live'),
            ),
        ],
      ),
    );
  }
}

class SearchRow extends StatelessWidget {
  const SearchRow({
    super.key,
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
                  : const Icon(FLucideIcons.search, size: 15),
              child: Text(searching ? 'Searching…' : 'Search'),
            ),
          ],
        ),
      ),
    );
  }
}

class CandidateRow extends StatelessWidget {
  const CandidateRow({
    super.key,
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
                        FLucideIcons.check,
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

class UnitToggle extends StatelessWidget {
  const UnitToggle({super.key, required this.unit, required this.onChanged});

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
