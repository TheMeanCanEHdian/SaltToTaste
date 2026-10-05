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
    // v41: no confirm finishes a reference line no recipe counts either
    // (a confirmed marinade, `discarded_recipe`, is poured away: finished).
    expect(holdsAConfirmCannotFinish, [
      foodGoneHold,
      foodUnavailableHold,
      'choose_recipe',
      'nested_recipe',
    ]);
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
    // v41 (A2): the reference holds are LINE holds — each a queue group of
    // one, never reached by a key decision.
    expect(lineHolds, [
      ...mediumHolds,
      'in_shell',
      'second_food',
      'choose_recipe',
      'nested_recipe',
      'discarded_recipe',
    ]);
    expect(holdsOf({HoldKind.recipe}), [
      'choose_recipe',
      'nested_recipe',
      'discarded_recipe',
    ]);
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

  test('v41 (S10, A5, N2): the reference holds and the routed row read the '
      'one table; `recipe` is never an unheld food row\'s', () {
    const recipe = HoldDecision.recipe;
    for (final hold in ['choose_recipe', 'nested_recipe']) {
      final actions = holdActionsOf(hold);
      expect(actions.kind, HoldKind.recipe);
      expect(actions.accepts, {HoldDecision.skip, recipe});
      expect(actions.finishes, {HoldDecision.skip, recipe});
      expect(actions.offers, {HoldDecision.skip, recipe});
      expect(actions.decidesLibraryWide, isFalse);
    }
    final marinade = holdActionsOf('discarded_recipe');
    expect(marinade.accepts, {HoldDecision.skip, HoldDecision.confirm, recipe});
    expect(marinade.decidesLibraryWide, isFalse);
    // A routed row (no hold, a child): confirm, choose another, skip — and
    // it may be applied to others (N2).
    final routed = holdActionsOf(null, routed: true);
    expect(routed.accepts, {HoldDecision.skip, HoldDecision.confirm, recipe});
    expect(routed.decidesLibraryWide, isTrue);
    // An unheld FOOD row offers and accepts no recipe pick (F3: `_every`
    // unchanged).
    expect(holdActionsOf(null).offers.contains(recipe), isFalse);
    expect(holdActionsOf(null).accepts.contains(recipe), isFalse);
    expect(unheldActions.offers, {
      HoldDecision.skip,
      HoldDecision.pick,
      HoldDecision.confirm,
      HoldDecision.typed,
    });
  });

  test('v41: the choose_recipe bucket — any status; a routed row is counted, '
      'a held marinade check (S3)', () {
    for (final status in ['auto', 'confirmed', 'overridden']) {
      for (final hold in recipeChoiceHolds) {
        expect(
          matchBucketFor(
            status: status,
            fdcId: null,
            grams: 0,
            confidence: 1,
            hold: hold,
            gramSource: 'recipe',
          ),
          MatchBucket.chooseRecipe,
          reason: '$status $hold',
        );
      }
    }
    expect(
      matchBucketFor(
        status: 'auto',
        fdcId: null,
        grams: 642.9,
        confidence: 1,
        gramSource: 'recipe',
      ),
      MatchBucket.counted,
    );
    expect(
      matchBucketFor(
        status: 'auto',
        fdcId: null,
        grams: 0,
        confidence: 1,
        hold: 'discarded_recipe',
        gramSource: 'recipe',
      ),
      MatchBucket.check,
    );
    // A no-food row of any other kind is still no match.
    expect(
      matchBucketFor(status: 'auto', fdcId: null, grams: null, confidence: 0),
      MatchBucket.noMatch,
    );
  });
}
