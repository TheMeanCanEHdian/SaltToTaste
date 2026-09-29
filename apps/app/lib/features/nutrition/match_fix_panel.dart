import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';

import 'package:salt_shared/salt_shared.dart'
    show MatchBucket, belowConfidenceGate, matchBucketFor, vulgarFractionChars;

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
  hold: m.hold,
  gramSource: m.gramSource,
);

/// A row the engine counts at 0 g on a food it named BELOW the gate — an
/// amount-less line or a discarded medium (ruling 9, 2026-09-28): it adds
/// nothing, and the weak food is often a wrong guess ("Gel food dye" on
/// "Fast foods, coleslaw"), so the row reads [zeroLabel] with the food
/// hidden, and its fix asks for a food AND an amount. At 0.5 and above the
/// food stays. A SKIPPED zero row keeps it: skipping is no food choice, so
/// the weak guess stays hidden; a person's confirm or pick shows its food.
bool countsAsZeroGuess({
  required String status,
  required int? fdcId,
  required double? grams,
  required double confidence,
  String? gramSource,
  String? hold,
}) =>
    (status == 'auto' || status == 'skipped') &&
    fdcId != null &&
    grams == 0 &&
    (gramSource == 'discarded' || gramSource == 'unmeasured') &&
    hold != 'unnamed_food' &&
    belowConfidenceGate(confidence);

/// [countsAsZeroGuess] for an app-model match row.
bool zeroGuessOf(IngredientMatch m) => countsAsZeroGuess(
  status: m.status,
  fdcId: m.fdcId,
  grams: m.grams,
  confidence: m.confidence,
  gramSource: m.gramSource,
  hold: m.hold,
);

/// What a [countsAsZeroGuess] row reads in place of its food. An
/// 'unmeasured' zero WITH a written amount (sprigs, a sub-recipe line) has
/// an amount the engine does not measure — not an amount-less line.
String zeroLabel(IngredientMatch m) => m.gramSource == 'discarded'
    ? 'Counts as zero (discarded in cooking)'
    : m.lineAmount == null
    ? 'Counts as zero (no amount)'
    : 'Counts as zero (not measured)';

/// Why a [countsAsZeroGuess] row adds nothing, after its [zeroLabel].
String zeroReason(IngredientMatch m) => m.gramSource == 'discarded'
    ? ': the recipe discards it in cooking, so it adds nothing to the label.'
    : m.lineAmount == null
    ? ': the line gives no amount, so it adds nothing to the label.'
    : ': ${m.lineAmount} — not measured, counts as 0 g.';

/// A line held as a poured-away medium or as shellfish bought in the shell
/// (ruling 5): its card leads with "Skip, poured away" / "Enter edible
/// grams", never a plain confirm of the whole weight.
bool isHeldLine(IngredientMatch m) =>
    m.status == 'auto' &&
    (m.hold == 'discarded_medium' || m.hold == 'in_shell');

/// Whether a held medium carries an eaten part: its engine grams are only
/// what is eaten ("… only \"plus 1 teaspoon table salt\" counted" — every
/// such row of snapshot 11 is a "plus" part), so a confirm counts that.
/// Never an in-shell line.
bool hasEatenPlusPart(IngredientMatch m) =>
    m.hold == 'discarded_medium' &&
    m.gramSource == 'discarded' &&
    (m.grams ?? 0) > 0;

/// Whether the fix panel leads with the amount (C): a No grams line on a
/// plausible food, confirmed WITH its amount in one step. (A Check line with
/// no grams keeps the candidates first — its food is probably wrong — and
/// gets a plain Confirm whose server-side conversion needs no amount.)
bool confirmsWithAmount(IngredientMatch m) =>
    m.fdcId != null && matchBucketOf(m) == MatchBucket.noAmount;

/// Whether a line gets the plain "Confirm" (C · Check, no grams): an engine
/// pick below the gate stored without its food's detail, which the confirm
/// fetches to convert the line's own amount. Not a held line (ruling 5).
bool confirmsWithoutAmount(IngredientMatch m) =>
    m.fdcId != null &&
    m.grams == null &&
    !isHeldLine(m) &&
    matchBucketOf(m) == MatchBucket.check;

const Map<String, double> unitToGrams = {'g': 1, 'oz': 28.3495, 'lb': 453.592};

String fmtAmount(double v) =>
    v < 10 ? v.toStringAsFixed(1) : v.round().toString();

String gramSourceLabel(String? source) => switch (source) {
  'weight' => 'from the weight you gave',
  'portion' => 'USDA household portion',
  'density' => 'volume estimate',
  'piece' => 'typical size',
  'override' => 'set by hand',
  'discarded' => 'discarded in cooking',
  'unmeasured' => 'no amount on the line',
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

/// The plain-language reason the engine holds a line (the matches body's
/// `hold`), or null for none / an unknown code.
String? holdReason(String? hold) => switch (hold) {
  'no_nutrients' => 'USDA publishes no calories or macros for this food',
  'discarded_medium' =>
    'Looks like a cooking medium the recipe discards (frying oil, a brine, '
        'a soak, cheese-making milk, drained cooking water)',
  'in_shell' =>
    'Bought in the shell — USDA has no edible share for this record',
  'second_food' =>
    'This line also calls for a second ingredient the match does not cover',
  'unnamed_food' =>
    'The line does not say which food this is (like "2 tablespoons '
        'juice")',
  'dried_for_fresh' =>
    'The line asks for a fresh herb, but this is a dried or ground spice',
  'cured_for_fresh' =>
    'This is a preserved record for a fresh ingredient: the line asks for '
        'fresh meat, the match is cured',
  'borderline' => 'The match score is borderline; please confirm the food',
  _ => null,
};

/// The plain-language reason a line is where it is.
class WhyLine extends StatelessWidget {
  const WhyLine({super.key, required this.match, required this.bucket});

  final IngredientMatch match;
  final MatchBucket bucket;

  @override
  Widget build(BuildContext context) {
    final held = bucket == MatchBucket.check ? holdReason(match.hold) : null;
    final (text, color) = switch (bucket) {
      // Ruling 5: a held medium or shell line says which way out it takes.
      MatchBucket.check when held != null && match.hold == 'in_shell' => (
        '$held — held out of the totals: enter the edible grams (the shells '
            'are not eaten), or skip it',
        SaltColors.warnInk,
      ),
      MatchBucket.check when held != null && hasEatenPlusPart(match) => (
        '$held — held out of the totals: Confirm counts only the eaten '
            'part, or skip it if it is all poured away',
        SaltColors.warnInk,
      ),
      MatchBucket.check when held != null && isHeldLine(match) => (
        '$held — held out of the totals: skip it if it is poured away, or '
            'enter the grams that are eaten',
        SaltColors.warnInk,
      ),
      // A held line passes on its name: the reason is the engine's, not the
      // score's.
      MatchBucket.check when held != null => (
        '$held — held out of the totals until you confirm it',
        SaltColors.warnInk,
      ),
      // A weak match counts only when it has an amount; without one it is a
      // wrong food AND an unfilled amount, and it contributes nothing.
      MatchBucket.check => (
        'Match looks off — ${(match.confidence * 100).round()}% name '
            'confidence, '
            '${match.grams == null ? 'and no amount found — not counted' : 'held out of the totals until you confirm it'}',
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

/// A held line's skip, as ruling 5 words it for a held medium AND an
/// in-shell row alike.
const String heldSkipLabel = 'Skip, poured away';

/// A counted zero below the gate on the review sheet (ruling 9): what it
/// adds — nothing — with its weak food hidden. An admin can open the
/// engine's guess ("Engine guess — not used"); a member never sees it.
class ZeroRow extends StatefulWidget {
  const ZeroRow({super.key, required this.match, required this.isAdmin});

  final IngredientMatch match;
  final bool isAdmin;

  @override
  State<ZeroRow> createState() => _ZeroRowState();
}

class _ZeroRowState extends State<ZeroRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    const muted = TextStyle(fontSize: 11.5, color: SaltColors.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: zeroLabel(m),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: SaltColors.ink,
                ),
              ),
              TextSpan(text: zeroReason(m)),
            ],
          ),
          style: const TextStyle(fontSize: 12.5, color: SaltColors.muted),
        ),
        // ZeroRow stands in for WhyLine, so it carries the engine's hold.
        if (holdReason(m.hold) case final held?)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              held,
              style: const TextStyle(fontSize: 12, color: SaltColors.muted),
            ),
          ),
        if (widget.isAdmin) ...[
          const SizedBox(height: 4),
          SelectionContainer.disabled(
            child: FTappable(
              onPress: () => setState(() => _open = !_open),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _open
                        ? FLucideIcons.chevronDown
                        : FLucideIcons.chevronRight,
                    size: 12,
                    color: SaltColors.muted,
                  ),
                  const SizedBox(width: 4),
                  const Text('Engine guess — not used', style: muted),
                ],
              ),
            ),
          ),
          if (_open)
            Container(
              margin: const EdgeInsets.only(left: 14, top: 4),
              padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: SaltColors.hairline, width: 2),
                ),
              ),
              child: Text(
                '${m.description ?? 'No food'} · '
                '${(m.confidence * 100).round()}% name. Too weak to show as '
                "this line's food, and it adds 0 g either way.",
                style: muted,
              ),
            ),
        ],
      ],
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
    final kcal = match.kcalPer100g;
    // With no amount yet, what the food weighs in at says more than "no
    // amount" (C): the record's calories per 100 g, when cached.
    final amount = grams != null
        ? '${fmtAmount(grams)} g · ${gramSourceLabel(match.gramSource)}'
        : kcal != null
        ? '${kcal.round()} kcal per 100 g'
        : 'no amount';
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
    this.amountFocus,
    this.recipeTitle,
    this.onSkip,
    this.group,
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

  /// The amount field's focus, when the host moves it there ("Enter edible
  /// grams" on a held line, ruling 5).
  final FocusNode? amountFocus;

  /// The line's recipe, when the host knows it: the amount-first block
  /// then says what the confirm leaves the recipe waiting on, or that it
  /// finishes it (C).
  final String? recipeTitle;

  /// A Skip beside the amount-first block's Confirm (the queue's pane,
  /// whose own Skip then steps aside); null for none.
  final VoidCallback? onSkip;

  /// The queue group the line stands for, when it has other lines: its
  /// label, how many other lines it holds, and whether a fix keeps the pane
  /// on it ([staysOn]). The amount-first block then says whether the
  /// confirm can travel, and where the pane goes next (C).
  final ({String item, int others, bool staysOn})? group;

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

  /// The amount-first block's "Wrong food? Change the match…" is open.
  bool _changeOpen = false;

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
    } else if (old.match.portions.isEmpty && !_amountDirty) {
      // The record's portions may have arrived with grams and food
      // unchanged (a plain Confirm USDA could not convert caches the
      // detail): their one fill prefills now, as on a fresh mount. A typed
      // amount stays; once portions are shown, a tapped fill stays too.
      _resetAmount();
    }
    // A plain Confirm that USDA could not convert leaves the line in No
    // grams (C): the amount block takes over, and its field — remounted
    // there — takes the focus by its own autofocus.
  }

  void _resetAmount() {
    final m = widget.match;
    final g = m.grams;
    // A No grams line (grams null by its bucket) on a plausible food.
    if (confirmsWithAmount(m)) {
      // The line's unit names exactly one USDA portion: its fill is the
      // amount (4 × stick 113 g = 452 g), shown in the field and on the
      // button, never written until Confirm. Otherwise the field waits.
      final fills = [
        for (final p in m.portions)
          if (p.fill != null) p.fill!,
      ];
      _setText(fills.length == 1 ? portionGrams(fills.single) : '');
      return;
    }
    // A zero row's 0 g is no amount to start from (the server refuses 0).
    _setText(
      g == null || zeroGuessOf(m) ? '' : fmtAmount(g / unitToGrams[_unit]!),
    );
  }

  /// Stages [fdcId] as the panel's pick. An untouched prefill is the STORED
  /// record's portion fill, which means nothing for another food: it is
  /// cleared on a new pick (and comes back on a re-pick of the stored one),
  /// so a Save without a typed amount lets the server recompute (A2).
  void _stage(int fdcId) {
    setState(() => _stagedFdcId = fdcId);
    if (!_amountDirty && confirmsWithAmount(widget.match)) {
      if (fdcId == widget.match.fdcId) {
        _resetAmount();
      } else {
        _setText('');
      }
    }
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
    // Ruling 9: a zero below the gate offers its guess struck through and
    // unselected — only a food AND an amount count it.
    final zero = zeroGuessOf(m);
    // C: a plausible food with no grams leads with its amount.
    final confirmMode = confirmsWithAmount(m);

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
    // match — never the guess of a zero row). Nothing is written until Save.
    final selectedId = zero ? _stagedFdcId : (_stagedFdcId ?? m.fdcId);
    final pickChanged = zero
        ? _stagedFdcId != null
        : _stagedFdcId != null && _stagedFdcId != m.fdcId;
    final canSave = zero
        ? !busy && pickChanged && grams != null
        : !busy &&
              (pickChanged || (!confirmMode && _amountDirty && grams != null));
    void save() => cubit.override(
      m.position,
      fdcId: pickChanged ? _stagedFdcId : null,
      // A zero row always sends the field: the line has no amount of its own
      // to recompute from. Otherwise only a typed amount goes out — the
      // amount-first block's prefill is the stored record's fill, cleared on
      // a new pick ([_stage]), so the server recomputes for the pick (A2).
      grams: zero || _amountDirty ? grams : null,
    );

    final saveButton = FButton(
      mainAxisSize: MainAxisSize.min,
      // One explicit write: the staged food and (only if you actually typed
      // one) the amount. An untouched amount is omitted so the server
      // recalculates it for the new food rather than freezing the previous
      // food's grams. No onDone here: the override is async, so success must
      // be OBSERVED from cubit state (the resolved line changes bucket /
      // leaves the attention list), never assumed at press time — a failed
      // save once advanced the guided flow and closed the panel as if it had
      // worked (review B5/B6).
      onPress: canSave ? save : null,
      child: const Text('Save match & amount'),
    );
    final cancelButton = widget.showCancel
        ? FButton(
            variant: FButtonVariant.ghost,
            mainAxisSize: MainAxisSize.min,
            onPress: busy ? null : widget.onDone,
            child: const Text('Cancel'),
          )
        : null;

    final change = <Widget>[
      if (m.candidatesNameIngredient == false)
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Text(
            'Nothing in the search names this ingredient — search by '
            'hand below.',
            style: TextStyle(fontSize: 12.5, color: SaltColors.muted),
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
            guess: zero && c.fdcId == m.fdcId,
            selected: c.fdcId == selectedId,
            busy: busy,
            onPick: busy ? null : () => _stage(c.fdcId),
          ),
      // Shown whenever FDC was asked — including a line it found NOTHING
      // for, which is the answer most worth refreshing. After a live search
      // for this line's own words, the line reflects that answer.
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
            onPick: busy ? null : () => _stage(c.fdcId),
          ),
        // The line above already speaks for a search of the line's own
        // words; say it once.
        if (_search != null && _search!.cachedAt != null && _lineSearch == null)
          CacheLine(
            query: _search!.query,
            cachedAt: _search!.cachedAt!,
            live: !_search!.cached,
            // Refresh the search this line speaks for, not whatever the box
            // says now.
            onSearchLive: _search!.cached && !busy && !_searching
                ? () => _runSearch(term: _search!.query, fresh: true)
                : null,
          ),
      ],
    ];

    // The field + unit toggle + "≈ N g" readout: one field per panel, which
    // the amount-first block and the plain editor share.
    final amountRow = Row(
      children: [
        SizedBox(
          width: confirmMode ? 150 : 92,
          child: FTextField(
            control: FTextFieldControl.managed(controller: _amt),
            focusNode: widget.amountFocus,
            autofocus: confirmMode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            hint: confirmMode && m.lineAmount != null
                ? 'grams for ${m.lineAmount}'
                : 'e.g. 250',
            onSubmit: confirmMode ? (_) => _confirm(cubit) : null,
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
    );

    Widget caption(String text) => Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: SaltColors.muted,
      ),
    );

    // The plain editor (and a zero row's): the amount, then Save.
    final editor = SelectionContainer.disabled(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: SaltColors.hairline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            caption('Amount'),
            // What the current grams were computed from, so a volume or piece
            // estimate can be sanity-checked before adjusting — or, on a zero
            // row, that there is none.
            if (zero && m.gramSource == 'unmeasured')
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  m.lineAmount == null
                      ? 'The line gives no amount.'
                      : 'The line says ${m.lineAmount} — not measured, '
                            'counts as 0 g.',
                  style: const TextStyle(fontSize: 12, color: SaltColors.ink),
                ),
              )
            else if (!zero && m.gramBasis != null)
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
            amountRow,
            if (!zero && pickChanged && !_amountDirty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Leave this as-is and the amount is recalculated for '
                  'the food you picked.',
                  style: TextStyle(fontSize: 11.5, color: SaltColors.muted),
                ),
              ),
            const SizedBox(height: 11),
            Row(
              children: [
                saveButton,
                if (cancelButton != null) ...[
                  const SizedBox(width: 8),
                  cancelButton,
                ],
              ],
            ),
          ],
        ),
      ),
    );

    final List<Widget> body;
    if (confirmMode) {
      body = [
        _amountFirst(cubit, amountRow, caption),
        SelectionContainer.disabled(
          child: FTappable(
            onPress: () => setState(() => _changeOpen = !_changeOpen),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: SaltColors.hairline)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  const Icon(
                    FLucideIcons.search,
                    size: 14,
                    color: SaltColors.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _changeOpen
                          ? 'Wrong food? Pick one, then save it with the '
                                'amount above'
                          : 'Wrong food? Change the match…',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: SaltColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_changeOpen) ...[
          ...change,
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                saveButton,
                if (cancelButton != null) ...[
                  const SizedBox(width: 8),
                  cancelButton,
                ],
              ],
            ),
          ),
        ] else if (cancelButton != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: cancelButton,
          ),
      ];
    } else {
      body = [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          child: caption(
            zero
                ? 'Give it a food and an amount to count it'
                : 'Change the match & set the amount',
          ),
        ),
        ...change,
        editor,
      ];
    }
    return Container(
      decoration: BoxDecoration(
        color: SaltColors.panel,
        border: Border.all(color: SaltColors.hairline),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: body,
      ),
    );
  }

  /// Confirms the food WITH the typed amount (C); nothing without one. A
  /// staged pick of another food is what the person chose: it is written
  /// with the amount (the "Save match & amount" write), never a confirm of
  /// the food they rejected (A1).
  void _confirm(NutritionCubit cubit) {
    final grams = _gramsFromField();
    final m = widget.match;
    if (widget.busy || grams == null) {
      return;
    }
    final staged = _stagedFdcId;
    if (staged != null && staged != m.fdcId) {
      cubit.override(m.position, fdcId: staged, grams: grams);
    } else {
      cubit.override(m.position, confirmed: true, grams: grams);
    }
  }

  static final _hasNumber = RegExp('[0-9$vulgarFractionChars]');

  /// The amount-first block (C): what the line says, the record's USDA
  /// portions — the ones naming the line's unit tap-to-fill, the rest for
  /// reference — the field, and a Confirm that follows the number.
  Widget _amountFirst(
    NutritionCubit cubit,
    Widget amountRow,
    Widget Function(String) caption,
  ) {
    final m = widget.match;
    final grams = _gramsFromField();
    // The portions are the STORED record's: after a pick of another food
    // they describe the rejected one, so they step aside (A2).
    final picked = _stagedFdcId != null && _stagedFdcId != m.fdcId;
    final fits = m.portions.any((p) => p.fill != null);
    // A bare count ("8", "1–16") names no unit a portion could miss; a
    // one-word amount with no number in it is the unit alone ("dash": the
    // codec's quantity is empty).
    final words = m.lineAmount?.split(' ');
    final unit = words == null
        ? null
        : words.length > 1
        ? words.last
        : _hasNumber.hasMatch(words.single)
        ? null
        : words.single;
    final size = leadingSize(m.raw);
    // A count shows on every chip once one portion is not "1" ("1 tsp"
    // beside "5 slices"); a list of ones shows none ("tbsp", "cup").
    final counts = m.portions.any((p) => p.amount != null && p.amount != 1);
    const says = TextStyle(fontSize: 12, color: SaltColors.ink);
    final title = widget.recipeTitle;
    final waiting = title == null
        ? null
        : openLinesBesides(
            context.read<NutritionCubit>().state.matches ?? const [],
            m.position,
          );
    return SelectionContainer.disabled(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            caption('How much is it?'),
            const SizedBox(height: 3),
            if (m.lineAmount == null)
              const Text('The line gives no amount.', style: says)
            else
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'The line says '),
                    TextSpan(
                      text: m.lineAmount,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (size != null) TextSpan(text: ' $size'),
                    TextSpan(
                      text:
                          !picked &&
                              unit != null &&
                              m.portions.isNotEmpty &&
                              !fits
                          ? ". USDA's portions for this food don't include "
                                'a $unit, so the engine could not convert:'
                          : '.',
                    ),
                  ],
                ),
                style: says,
              ),
            if (picked)
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Text(
                  "Type the picked food's grams, or save the pick without "
                  'an amount to have it recalculated.',
                  style: TextStyle(fontSize: 11.5, color: SaltColors.muted),
                ),
              )
            else if (m.portions.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Text(
                  'USDA portions load after the first confirm.',
                  style: TextStyle(fontSize: 11.5, color: SaltColors.muted),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in m.portions) _portionChip(p, counts: counts),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            amountRow,
            const SizedBox(height: 11),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FButton(
                  mainAxisSize: MainAxisSize.min,
                  onPress: widget.busy || grams == null
                      ? null
                      : () => _confirm(cubit),
                  prefix: const Icon(FLucideIcons.check, size: 14),
                  child: Text(
                    grams != null
                        ? 'Confirm · ${portionGrams(grams)} g'
                        : 'Confirm with amount',
                  ),
                ),
                if (widget.onSkip != null)
                  FButton(
                    variant: FButtonVariant.ghost,
                    mainAxisSize: MainAxisSize.min,
                    onPress: widget.busy ? null : widget.onSkip,
                    prefix: const Icon(FLucideIcons.ban, size: 14),
                    child: const Text('Skip'),
                  ),
              ],
            ),
            if (title != null && waiting != null)
              _Consequence(recipe: title, waiting: waiting),
            ..._groupNotes(m),
          ],
        ),
      ),
    );
  }

  /// What the confirm means for the rest of the queue group (C): no
  /// apply-to-all offer when no other line of it is a target (`others` 0:
  /// they are already on this food at or above the gate), and, for a No
  /// grams group, that the pane stays on the ingredient.
  ///
  /// The note's "at N%" is [m]'s confidence: the queue opens a group on its
  /// example, the member with the LOWEST confidence (API.md), so N is the
  /// group's minimum and every other line sits at N% or above (snapshot
  /// 11's ginger: all 14 at 0.887).
  List<Widget> _groupNotes(IngredientMatch m) {
    final group = widget.group;
    if (group == null) {
      return const [];
    }
    final n = group.others;
    const bold = TextStyle(fontWeight: FontWeight.w700);
    return [
      if (m.others == 0)
        _Note(
          icon: FLucideIcons.info,
          spans: [
            TextSpan(
              text:
                  'No apply-to-all offer. The $n other ${group.item} '
                  '${n == 1 ? 'line is' : 'lines are'} already on this food '
                  'at ${(m.confidence * 100).round()}%, so '
                  '${n == 1 ? 'it is not a target' : 'they are not targets'}'
                  ', and a typed amount never travels.',
            ),
          ],
        ),
      if (group.staysOn)
        _Note(
          icon: FLucideIcons.arrowRight,
          spans: [
            const TextSpan(text: 'After the confirm the pane stays on '),
            TextSpan(text: group.item, style: bold),
            TextSpan(
              text:
                  ' and opens its next line ($n left), because each line '
                  'needs its own amount.',
            ),
          ],
        ),
    ];
  }

  /// One USDA portion: tap-to-fill when it names the line's unit ("4 ×
  /// stick 113 g = 452 g"), else for reference only ("tbsp · 14.2 g") —
  /// tapping "5 slices = 11 g" into a field for "1 piece" would write the
  /// wrong quantity.
  Widget _portionChip(FoodPortion p, {required bool counts}) {
    final fill = p.fill;
    final label = portionLabel(p, showOne: counts);
    final Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: fill == null ? SaltColors.hairline : SaltColors.maroon,
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        fill == null
            ? '$label · ${portionGrams(p.grams)} g'
            : '${portionGrams(fill / p.grams)} × $label '
                  '${portionGrams(p.grams)} g = ${portionGrams(fill)} g',
        style: TextStyle(
          fontSize: 11.5,
          color: fill == null ? SaltColors.muted : SaltColors.maroon,
          fontWeight: fill == null ? FontWeight.w400 : FontWeight.w700,
        ),
      ),
    );
    if (fill == null) {
      return chip;
    }
    return FTappable(
      onPress: widget.busy
          ? null
          : () => setState(() {
              _unit = 'g';
              _setText(portionGrams(fill));
            }),
      child: chip,
    );
  }
}

/// Grams as a portion chip and the confirm write them: whole numbers bare
/// (113, 452), else one decimal (14.2).
String portionGrams(double v) =>
    v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

/// A portion's name with its count when it is not one ("¼ cup slices (1\"
/// dia)", "5 slices (1\" dia)", "stick") — or when [showOne], one too
/// ("1 tsp" among counted chips).
String portionLabel(FoodPortion p, {bool showOne = false}) {
  final name = p.description ?? p.unit ?? '';
  final amount = p.amount;
  if (amount == null || (amount == 1 && !showOne)) {
    return name;
  }
  final count = amount == amount.roundToDouble()
      ? '${amount.toInt()}'
      : switch (amount) {
          0.25 => '¼',
          0.5 => '½',
          0.75 => '¾',
          _ => '$amount',
        };
  return '$count $name';
}

/// The size in parentheses right after a line's leading count — "(1½-inch)"
/// of "1 (1½-inch) piece ginger" — which the amount text drops; null when
/// the line has none.
String? leadingSize(String raw) =>
    RegExp(r'^[^(A-Za-z]*(\([^)]*\))').firstMatch(raw)?.group(1);

/// The OTHER lines of a recipe still open (No match, Check or No grams)
/// besides the one at [position], in line order: what a decision on that
/// line leaves its recipe waiting on.
List<IngredientMatch> openLinesBesides(
  List<IngredientMatch> matches,
  int position,
) => [
  for (final m in matches)
    if (m.position != position &&
        switch (matchBucketOf(m)) {
          MatchBucket.noMatch ||
          MatchBucket.check ||
          MatchBucket.noAmount => true,
          MatchBucket.counted || MatchBucket.skipped => false,
        })
      m,
];

/// What a confirm on the amount-first block does for its recipe (C): the
/// lines it still waits on, or — the recipe's only open line — that this
/// confirm finishes it.
class _Consequence extends StatelessWidget {
  const _Consequence({required this.recipe, required this.waiting});

  final String recipe;
  final List<IngredientMatch> waiting;

  @override
  Widget build(BuildContext context) {
    final n = waiting.length;
    if (waiting.isEmpty) {
      return _Note(
        icon: FLucideIcons.flag,
        color: SaltColors.okInk,
        spans: [
          const TextSpan(
            text: "This is the recipe's only open line, so this confirm ",
          ),
          TextSpan(
            text: 'finishes $recipe',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const TextSpan(text: '.'),
        ],
      );
    }
    return _Note(
      icon: FLucideIcons.info,
      spans: [
        TextSpan(
          text:
              '$recipe still waits on '
              '${n == 1 ? '1 more line' : '$n more lines'} after this: ',
        ),
        TextSpan(
          text: [for (final m in waiting) m.raw].join('; '),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
        const TextSpan(text: '.'),
      ],
    );
  }
}

/// One consequence line under the amount-first block: an icon and a
/// sentence, muted unless it names an outcome.
class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.spans,
    this.color = SaltColors.muted,
  });

  final IconData icon;
  final List<InlineSpan> spans;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 5),
            child: Icon(icon, size: 13, color: color),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(children: spans),
              style: TextStyle(fontSize: 11.5, color: color),
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
    this.guess = false,
  });

  final MatchCandidate candidate;

  /// The engine's guess on a zero row below the gate (ruling 9): struck
  /// through and marked "not used" — pickable, never pre-selected.
  final bool guess;

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
                    color: guess && !selected
                        ? SaltColors.muted
                        : SaltColors.ink,
                    decoration: guess && !selected
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                guess
                    ? 'engine guess · '
                          '${(candidate.confidence * 100).round()}% · not used'
                    : isCurrent
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
