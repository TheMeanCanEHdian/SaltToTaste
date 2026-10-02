import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/features/admin/nutrition_review_queue.dart';
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';

import 'support/contract_goldens.dart';

/// The rules golden's butter sticks (Classic Yellow Layer Cake, pos 12) with
/// [match] fields replaced: the same real line in another bucket.
IngredientMatch _butter(Map<String, dynamic> match) {
  final item = Map<String, dynamic>.of(
    (golden('nutrition_matches_rules')['items'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((m) => m['position'] == 12),
  );
  item['match'] = {...item['match'] as Map<String, dynamic>, ...match};
  return IngredientMatch.fromJson(item);
}

/// The admin queue's advance rule as the pure predicate the pane listens
/// with: advance exactly once per resolved line — at once when the fix
/// raised no apply-to-all offer, otherwise when the offer or its receipt is
/// closed — and never while an error shows.
void main() {
  const idle = NutritionState(loading: false);
  const offer = (
    position: 3,
    raw: '2 large eggs',
    label: 'eggs',
    fdcId: 1,
    confirmed: false,
    grams: null,
    others: 2,
    lines: 2,
  );
  const receipt = (
    position: 3,
    recipes: 2,
    lines: 2,
    failed: 0,
    completed: 0,
    completedRecipes: <String>[],
    raw: '2 large eggs',
    moved: 0,
    decided: 0,
    gone: 0,
    failedLines: 0,
  );
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
    // dismissOffer clears offer AND error in one emit.
    expect(queueShouldAdvance(failed, idle), isTrue);
    // A failed override (no offer involved) never advances either.
    expect(queueShouldAdvance(inFlight, idle.copyWith(error: 'no')), isFalse);
  });

  test('an unrelated emit does not advance', () {
    expect(queueShouldAdvance(idle, idle), isFalse);
    expect(queueShouldAdvance(idle, idle.copyWith(loading: true)), isFalse);
  });

  group('A4: the pane stays on a line left waiting on an amount', () {
    // No grams on its food, as each decision leaves it: a plain Confirm USDA
    // could not convert, and a pick that ended without grams.
    final waiting = _butter({
      'grams': null,
      'gram_source': null,
      'status': 'confirmed',
    });
    final picked = _butter({
      'fdc_id': 172470,
      'description': 'Peanut butter, smooth style, without salt',
      'grams': null,
      'gram_source': null,
      'status': 'overridden',
    });
    // No match: no food at all.
    final unmatched = _butter({
      'fdc_id': null,
      'description': null,
      'confidence': 0.0,
      'grams': null,
      'gram_source': null,
    });
    final counted = _butter({});

    test('after an offer or its receipt closes over it', () {
      final raised = idle.copyWith(offer: offer, matches: [waiting]);
      final closed = idle.copyWith(matches: [waiting]);
      expect(queueShouldAdvance(raised, closed), isTrue);
      expect(paneAdvances(raised, closed, 12), isFalse);
      final applied = idle.copyWith(applied: receipt, matches: [waiting]);
      expect(paneAdvances(applied, closed, 12), isFalse);
      // Once the line has grams the same close advances.
      expect(
        paneAdvances(raised, idle.copyWith(matches: [counted]), 12),
        isTrue,
      );
    });

    test('after a pick from No match that ends without grams', () {
      final before = inFlight.copyWith(matches: [unmatched]);
      final after = idle.copyWith(matches: [picked]);
      expect(paneAdvances(before, after, 12), isFalse);
      // A pick that ends counted advances.
      expect(
        paneAdvances(before, idle.copyWith(matches: [counted]), 12),
        isTrue,
      );
    });

    test('after a pick on a No grams line that ends without grams', () {
      final before = inFlight.copyWith(matches: [waiting]);
      expect(
        paneAdvances(before, idle.copyWith(matches: [picked]), 12),
        isFalse,
      );
    });
  });

  // Run 050 P4: the queue lists a row at its STORED position; after a save
  // (before the next compute) the recipe's rows sit on the moved lines. The
  // pane finds the queue's line by its text, nearest its stored position.
  group('queueMatchOf', () {
    final line = NutritionReviewLine.fromJson(
      (golden('nutrition_review')['items'] as List).first
          as Map<String, dynamic>,
    );
    List<IngredientMatch> rows(Map<int, int> moved) => [
      for (final item
          in (golden('nutrition_matches')['items'] as List)
              .cast<Map<String, dynamic>>())
        IngredientMatch.fromJson({
          ...item,
          'position': moved[item['position'] as int] ?? item['position'] as int,
        }),
    ];

    test('the row at the stored position when it reads the line', () {
      expect(line.position, 12);
      final match = queueMatchOf(rows(const {}), line)!;
      expect((match.position, match.raw), (12, line.raw));
    });

    test('the line moved up one by a save: its row where it is now', () {
      final match = queueMatchOf(rows(const {12: 11, 11: 12}), line)!;
      expect((match.position, match.raw), (11, line.raw));
    });

    // Run 051 A2. Synthesized row lists (a stated exception): the golden's
    // real rows with the queued line removed, shifted or repeated — the
    // layouts a save can leave before the next compute; no new text.
    List<IngredientMatch> without(List<IngredientMatch> all) => [
      for (final m in all)
        if (m.raw != line.raw) m,
    ];
    IngredientMatch twin(int position) =>
        IngredientMatch(position: position, raw: line.raw, item: line.item);

    test('no row reads the line (edited or deleted): null — never the '
        'row a save put at its position', () {
      // A line inserted above moved every line down one, and the queued
      // line's amount was edited: the eggs now sit at its position.
      final shifted = without(rows({for (var p = 0; p < 12; p++) p: p + 1}));
      expect(shifted.any((m) => m.position == line.position), isTrue);
      expect(queueMatchOf(shifted, line), isNull);
    });

    test('twins: the one nearest the stored position', () {
      final rest = without(rows(const {}));
      final match = queueMatchOf([twin(9), ...rest, twin(14)], line)!;
      expect(match.position, 14);
    });

    test('twins equally near: the lower one', () {
      final rest = without(rows(const {}));
      final match = queueMatchOf([twin(11), ...rest, twin(13)], line)!;
      expect(match.position, 11);
    });
  });
}
