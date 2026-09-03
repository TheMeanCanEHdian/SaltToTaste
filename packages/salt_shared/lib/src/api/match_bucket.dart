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
/// - `confirmed` is always resolved, even with no match: confirming is the
///   deliberate "as-is is right" verdict (confirmed water is a no-match on
///   purpose).
enum MatchBucket {
  counted('counted'),
  check('check'),
  noAmount('no_grams'),
  noMatch('no_match'),
  skipped('skipped');

  const MatchBucket(this.wire);

  /// The bucket's wire/queue spelling (`no_grams`, not `noAmount`).
  final String wire;

  static MatchBucket fromWire(String value) =>
      values.firstWhere((bucket) => bucket.wire == value);
}

/// Buckets a match row from its stored state. Field semantics follow the
/// `ingredient_matches` table: [status] is one of
/// auto/unmatched/confirmed/overridden/skipped; [confidence] only flags
/// `auto` rows (a human-touched row is never "low confidence" — a human
/// looked at it).
MatchBucket matchBucketFor({
  required String status,
  required int? fdcId,
  required double? grams,
  required double confidence,
}) {
  if (status == 'skipped') {
    return MatchBucket.skipped;
  }
  if (status == 'overridden' && grams == null) {
    return MatchBucket.noAmount;
  }
  if (status == 'confirmed' || status == 'overridden') {
    return MatchBucket.counted;
  }
  if (fdcId == null) {
    return MatchBucket.noMatch;
  }
  // A weak match is first a WRONG food, whether or not it has an amount: a
  // 0.41 "100 GRAND Bar" for a liqueur line must read "check match", not the
  // calm "no amount" — the amount is the smaller of its problems.
  if (status == 'auto' && confidence < 0.5) {
    return MatchBucket.check;
  }
  if (grams == null) {
    return MatchBucket.noAmount;
  }
  return MatchBucket.counted;
}
