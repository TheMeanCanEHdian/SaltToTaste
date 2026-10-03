/// RULE A (matcher v28): ONE action table per hold family — which of a
/// person's decisions finish a held line, which the review sheet offers,
/// which the match PUT accepts, and whether the decision gate may record
/// the food as the ingredient's decision library-wide. Every consumer reads
/// it: the server's PUT gate (`applyMatchOverride`) and the review queue's
/// `finishes`/`finishable` SQL (parity-pinned against this table), the
/// app's sheet and queue (`heldFinishes`, the buttons). Run 058 pattern
/// (b): a hold family threaded through the buckets but not through the
/// actions let each consumer keep its own rule (a Confirm offered, and
/// accepted, on a food USDA no longer serves).
library;

/// A person's decision on a match line.
enum HoldDecision {
  /// "Leave this line out" (`skipped: true`).
  skip,

  /// Another food (`fdc_id`).
  pick,

  /// "This food, as the engine weighs it" (`confirmed: true`).
  confirm,

  /// Grams a person typed on the line's food (`grams`).
  typed,
}

/// A decided row whose food FDC answers "no such food" for (a 404) and no
/// cache holds — or whose nutrient sibling FDC answers so (v27, RULE A).
const String foodGoneHold = 'food_gone';

/// A decided row whose food FDC errors on (not a 404: a 4xx or a 5xx after
/// the retries, for that one id) in [foodUnavailableAfter] computes running
/// (v28, RULE A's FOOD failure class): held for a person, so one food never
/// blocks a sweep and never sits underived forever.
const String foodUnavailableHold = 'food_unavailable';

/// How many computes in a row may fail on one decided row's food (a FOOD
/// failure) before the row is held [foodUnavailableHold].
const int foodUnavailableAfter = 3;

/// What a hold says about its line — its FAMILY (v29, RULE A, Run 059
/// S8): the one place a hold's membership is stated; every list of a
/// family ([mediumHolds], [lineHolds], [noRecordHolds]) and every SQL list
/// of one is read from [holdActions], never copied by hand.
enum HoldKind {
  /// A FOOD hold of the engine's own pick (a decision answers it).
  food,

  /// A LINE hold: a medium the recipe pours away, wholly or in part.
  medium,

  /// A LINE hold that is no medium: a shell, a second food.
  line,

  /// A person's decision on a food with no record (`food_gone`,
  /// `food_unavailable`).
  noRecord,
}

/// What a person may do on a line held for one hold kind.
class HoldActions {
  /// Builds a table entry.
  const HoldActions({
    required this.kind,
    required this.finishes,
    required this.offers,
    required this.accepts,
    required this.decidesLibraryWide,
  });

  /// The hold's family.
  final HoldKind kind;

  /// The decisions that always answer the hold (the line leaves `check`).
  final Set<HoldDecision> finishes;

  /// The decisions the review sheet and queue offer on it.
  final Set<HoldDecision> offers;

  /// The decisions the match PUT accepts on it (any other is a 422).
  final Set<HoldDecision> accepts;

  /// Whether a pick or confirm on it may become the ingredient's decision
  /// in every recipe (`ingredient_decisions`).
  final bool decidesLibraryWide;
}

const Set<HoldDecision> _every = {
  HoldDecision.skip,
  HoldDecision.pick,
  HoldDecision.confirm,
  HoldDecision.typed,
};

/// A FOOD hold of the engine's own pick: any decision answers it.
const HoldActions _foodHold = HoldActions(
  kind: HoldKind.food,
  finishes: _every,
  offers: _every,
  accepts: _every,
  decidesLibraryWide: true,
);

/// A wholly poured-away medium: a pick is 0 g, resolved.
const HoldActions _pouredAway = HoldActions(
  kind: HoldKind.medium,
  finishes: _every,
  offers: _every,
  accepts: _every,
  decidesLibraryWide: true,
);

/// A shell or a second food on the line: any decision answers it.
const HoldActions _lineFood = HoldActions(
  kind: HoldKind.line,
  finishes: _every,
  offers: _every,
  accepts: _every,
  decidesLibraryWide: true,
);

/// A medium a part of whose line is eaten: a pick alone keeps the hold
/// unless the engine knows the eaten part (so it is no promise).
const HoldActions _eatenInPart = HoldActions(
  kind: HoldKind.medium,
  finishes: {HoldDecision.skip, HoldDecision.confirm, HoldDecision.typed},
  offers: _every,
  accepts: _every,
  decidesLibraryWide: true,
);

/// A food FDC does not serve (or will not serve now): only another food or
/// a skip finishes it; a confirm or typed grams cannot count it, and it is
/// never recorded library-wide.
const HoldActions _noRecord = HoldActions(
  kind: HoldKind.noRecord,
  finishes: {HoldDecision.skip, HoldDecision.pick},
  offers: {HoldDecision.skip, HoldDecision.pick},
  accepts: {HoldDecision.skip, HoldDecision.pick},
  decidesLibraryWide: false,
);

/// Every hold the server writes, by kind. A row with no hold reads
/// [unheldActions] ([holdActionsOf]).
const Map<String, HoldActions> holdActions = {
  // FOOD holds of the engine's pick (a decision answers them).
  'no_nutrients': _foodHold,
  'unnamed_food': _foodHold,
  'dried_for_fresh': _foodHold,
  'cured_for_fresh': _foodHold,
  'borderline': _foodHold,
  // LINE holds: a wholly poured-away medium — a pick is 0 g, resolved.
  'discarded_medium': _pouredAway,
  'starter_discard': _eatenInPart,
  'coating': _eatenInPart,
  'partial_pour_away': _eatenInPart,
  'ambiguous_medium': _eatenInPart,
  'in_shell': _lineFood,
  'second_food': _lineFood,
  // A person's decision on a food with no record.
  foodGoneHold: _noRecord,
  foodUnavailableHold: _noRecord,
};

/// The actions on a line no hold holds.
const HoldActions unheldActions = _foodHold;

/// [holdActions] for [hold] (null: [unheldActions]).
HoldActions holdActionsOf(String? hold) => holdActions[hold] ?? unheldActions;

/// The holds of [kinds], in table order.
List<String> holdsOf(Set<HoldKind> kinds) => [
  for (final MapEntry(:key, :value) in holdActions.entries)
    if (kinds.contains(value.kind)) key,
];

/// The holds of a medium the recipe pours away ([HoldKind.medium]).
final List<String> mediumHolds = holdsOf({HoldKind.medium});

/// Every LINE hold — what the line says about its medium, its shell or a
/// second food, whatever food it is matched on.
final List<String> lineHolds = holdsOf({HoldKind.medium, HoldKind.line});

/// The holds of a person's decision on a food with no record.
final List<String> noRecordHolds = holdsOf({HoldKind.noRecord});

/// The holds a confirm (or typed grams) cannot finish — the queue's
/// `finishes` never promises them a finish by a confirm.
Iterable<String> get holdsAConfirmCannotFinish => [
  for (final MapEntry(:key, :value) in holdActions.entries)
    if (!value.finishes.contains(HoldDecision.confirm)) key,
];
