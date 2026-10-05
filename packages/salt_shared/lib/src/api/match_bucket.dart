import 'hold_actions.dart';

/// The triage bucket of one nutrition ingredient-match row.
///
/// ONE rule, defined once. The per-recipe review sheet (app) buckets rows
/// with [matchBucketFor]; the server's cross-recipe queue mirrors it in SQL
/// (`SaltDatabase._reviewBucketCase`, parity-pinned by a server test). The
/// two implementations once disagreed — a `confirmed`/`overridden` row with
/// no food or grams was "resolved" in the queue but "needs attention" on the
/// sheet, so a line could vanish from the queue while still contributing
/// nothing (review B7). The decided corners:
///
/// - `skipped` is always resolved: the human said "leave this line out".
/// - `overridden` with NULL grams stays in `no_grams`: the human picked a
///   food expecting it to count, and it doesn't yet — an unfinished fix,
///   not a resolution.
/// - `confirmed` is resolved, even with no match: confirming is the
///   deliberate "as-is is right" verdict (confirmed water is a no-match on
///   purpose) — but a confirmed FOOD with NULL grams stays in `no_grams`,
///   like an overridden one: the totals skip a food with no grams, so a
///   confirm on a line with no amount took it out of the queue while its
///   recipe stayed partial (checkpoint 6: 381 lines exposed, 17 recipes
///   left partial with nothing to review).
enum MatchBucket {
  counted('counted'),
  check('check'),
  noAmount('no_grams'),
  noMatch('no_match'),
  skipped('skipped'),

  /// A reference line no recipe counts yet (v41: held `choose_recipe` or
  /// `nested_recipe`, [recipeChoiceHolds]) — any status.
  chooseRecipe('choose_recipe');

  const MatchBucket(this.wire);

  /// The bucket's wire/queue spelling (`no_grams`, not `noAmount`).
  final String wire;

  static MatchBucket fromWire(String value) =>
      values.firstWhere((bucket) => bucket.wire == value);
}

/// The buckets that need a person ("needs attention", the queue's default
/// view), in chip order — ONE list for the app, the queue's labels and every
/// query of the server's queue (v41: `choose_recipe` joins them). `counted`
/// and `skipped` are never flagged.
const List<String> flaggedBuckets = [
  'no_match',
  'no_grams',
  'check',
  'choose_recipe',
];

/// The name-confidence gate: an `auto` match scored below it is flagged
/// `check`. Scores are sums of fixed fractions, so a line can land exactly on
/// it (checkpoint 6: 5 counted rows at 0.500); every comparison reads
/// [confidenceGateFloor], so a 1e-16 float drift never flips one.
const double confidenceGate = 0.5;

/// [confidenceGate] less a 1e-9 drift tolerance — what every "below the
/// gate" compares against, in Dart and in the server's SQL alike.
const double confidenceGateFloor = confidenceGate - 1e-9;

/// Whether [confidence] is below the gate ([confidenceGateFloor]).
bool belowConfidenceGate(double confidence) => confidence < confidenceGateFloor;

/// Buckets a match row from its stored state. Field semantics follow the
/// `ingredient_matches` table: [status] is one of
/// auto/unmatched/confirmed/overridden/skipped; [confidence] only flags
/// `auto` rows (a human-touched row is never "low confidence" — a human
/// looked at it). [hold] is the engine's reason for holding an `auto` row
/// out of the totals although its name score passes (`no_nutrients`,
/// `discarded_medium`, `second_food`): such a row is `check` too — and so is
/// a decided row held `food_gone` (its food is no longer served by USDA)
/// or `food_unavailable` (USDA kept failing on it, v28): it counts nothing
/// until a person picks again or skips it ([holdActions]).
///
/// [gramSource] `discarded` (a cooking medium the recipe throws away) or
/// `unmeasured` (a line with no amount, a sprig) at 0 g is the engine's
/// resolved zero: such a row is `counted` whatever its score or hold — no
/// decision on its food can change a total (audit 4: 34 such rows sat in
/// `check` for nothing) — except `unnamed_food`, which the engine sets on
/// purpose: "2 tablespoons juice" (the parser kept the amount in the item)
/// names no food and its 0 g drops a real amount, so it waits for a person
/// like any held line. The eaten part of a "plus" medium has grams and is bucketed
/// like any line.
MatchBucket matchBucketFor({
  required String status,
  required int? fdcId,
  required double? grams,
  required double confidence,
  String? hold,
  String? gramSource,
}) {
  if (status == 'skipped') {
    return MatchBucket.skipped;
  }
  // A person's food FDC no longer serves (`food_gone`, server RULE A, v27)
  // or keeps failing on (`food_unavailable`, v28): out of the totals
  // whatever its grams, waiting on a pick or a skip ([holdActions]).
  if (noRecordHolds.contains(hold)) {
    return MatchBucket.check;
  }
  // A reference line no recipe counts (v41), whoever decided it: a person's
  // nested pick, a decided row whose child is gone.
  if (recipeChoiceHolds.contains(hold)) {
    return MatchBucket.chooseRecipe;
  }
  if ((status == 'overridden' && grams == null) ||
      (status == 'confirmed' && fdcId != null && grams == null)) {
    return MatchBucket.noAmount;
  }
  if (status == 'confirmed' || status == 'overridden') {
    return MatchBucket.counted;
  }
  // A composite reference row (`gram_source` recipe, v41) has no food on
  // purpose: routed it is counted, a held marinade is `check` (below).
  if (fdcId == null && gramSource != 'recipe') {
    return MatchBucket.noMatch;
  }
  if ((gramSource == 'discarded' || gramSource == 'unmeasured') &&
      grams == 0 &&
      hold != 'unnamed_food') {
    return MatchBucket.counted;
  }
  // A weak match is first a WRONG food, whether or not it has an amount: a
  // 0.41 "100 GRAND Bar" for a liqueur line must read "check match", not the
  // calm "no amount" — the amount is the smaller of its problems.
  if (status == 'auto' && (belowConfidenceGate(confidence) || hold != null)) {
    return MatchBucket.check;
  }
  if (grams == null) {
    return MatchBucket.noAmount;
  }
  return MatchBucket.counted;
}
