import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/features/admin/nutrition_review_queue.dart';
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';

/// The admin queue's advance rule as the pure predicate the pane listens
/// with: advance exactly once per resolved line — at once when the fix
/// raised no apply-to-all offer, otherwise when the offer or its receipt is
/// closed — and never while an error shows.
void main() {
  const idle = NutritionState(loading: false);
  const offer = (
    position: 3,
    label: 'eggs',
    fdcId: 1,
    confirmed: false,
    grams: null,
    others: 2,
  );
  const receipt = (position: 3, recipes: 2, lines: 2, failed: 0);
  final inFlight = idle.copyWith(overridingPosition: 3);

  test('a fix with no offer advances at once', () {
    expect(queueShouldAdvance(inFlight, idle), isTrue);
  });

  test('a fix that raised an offer waits', () {
    final raised = idle.copyWith(offer: offer);
    expect(queueShouldAdvance(inFlight, raised), isFalse);
    // Applying turns the offer into a receipt — still waiting.
    final applied = raised.copyWith(clearOffer: true, applied: receipt);
    expect(queueShouldAdvance(raised, applied), isFalse);
    // Dismissing the receipt is the moment.
    expect(queueShouldAdvance(applied, idle), isTrue);
  });

  test('"Not now" advances', () {
    final raised = idle.copyWith(offer: offer);
    expect(queueShouldAdvance(raised, idle), isTrue);
  });

  test('never while an error shows; the dismissal that clears it advances', () {
    final raised = idle.copyWith(offer: offer);
    final failed = raised.copyWith(error: 'the server fell over');
    expect(queueShouldAdvance(raised, failed), isFalse);
    expect(queueShouldAdvance(failed, failed), isFalse);
    // dismissApply clears offer AND error in one emit.
    expect(queueShouldAdvance(failed, idle), isTrue);
    // A failed override (no offer involved) never advances either.
    expect(queueShouldAdvance(inFlight, idle.copyWith(error: 'no')), isFalse);
  });

  test('an unrelated emit does not advance', () {
    expect(queueShouldAdvance(idle, idle), isFalse);
    expect(queueShouldAdvance(idle, idle.copyWith(loading: true)), isFalse);
  });
}
