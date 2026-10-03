import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

// RULE A (v28): ONE action table per hold family. The server pins its SQL
// and its PUT gate against this table; this pins the table's own shape.
void main() {
  test('every entry finishes only by decisions it accepts, and accepts only '
      'decisions the sheet offers', () {
    for (final MapEntry(key: hold, value: actions) in holdActions.entries) {
      expect(
        actions.accepts.containsAll(actions.finishes),
        isTrue,
        reason: hold,
      );
      expect(actions.offers.containsAll(actions.accepts), isTrue, reason: hold);
      expect(actions.finishes, contains(HoldDecision.skip), reason: hold);
    }
    expect(holdActionsOf(null), unheldActions);
    expect(holdActionsOf('not-a-hold'), unheldActions);
  });

  test('a food with no record: a pick or a skip only, never library-wide; '
      'its rows bucket `check` whatever their grams', () {
    for (final hold in [foodGoneHold, foodUnavailableHold]) {
      final actions = holdActionsOf(hold);
      expect(actions.accepts, {HoldDecision.skip, HoldDecision.pick});
      expect(actions.finishes, {HoldDecision.skip, HoldDecision.pick});
      expect(actions.decidesLibraryWide, isFalse);
      expect(
        matchBucketFor(
          status: 'overridden',
          fdcId: 1,
          grams: 50,
          confidence: 1,
          hold: hold,
          gramSource: 'override',
        ),
        MatchBucket.check,
      );
    }
    expect(holdsAConfirmCannotFinish, [foodGoneHold, foodUnavailableHold]);
  });

  test('food_unavailable after THREE failing computes, as API.md says (the '
      'v28 closer: the documented number pinned)', () {
    expect(foodUnavailableAfter, 3);
  });

  test('v29 (Run 059 S8): every hold has ONE family, on its table entry — '
      'the family lists are read from the table, never copied', () {
    expect(mediumHolds, [
      'discarded_medium',
      'starter_discard',
      'coating',
      'partial_pour_away',
      'ambiguous_medium',
    ]);
    expect(lineHolds, [...mediumHolds, 'in_shell', 'second_food']);
    expect(noRecordHolds, [foodGoneHold, foodUnavailableHold]);
    expect(holdsOf({HoldKind.food}), [
      'no_nutrients',
      'unnamed_food',
      'dried_for_fresh',
      'cured_for_fresh',
      'borderline',
    ]);
    expect(
      HoldKind.values.expand((k) => holdsOf({k})).toSet(),
      holdActions.keys.toSet(),
    );
  });
}
