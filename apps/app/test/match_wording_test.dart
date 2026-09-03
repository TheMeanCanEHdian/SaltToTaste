import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/features/nutrition/match_fix_panel.dart';

/// What the review sheet SAYS about a row — the two review fleets found the
/// engine's own explanation never reaching the screen, and a weak match with
/// no amount being told it "is counting now".
void main() {
  Future<void> pump(WidgetTester tester, IngredientMatch match) async {
    final bucket = matchBucketOf(match);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              WhyLine(match: match, bucket: bucket),
              CurrentMatch(match: match, bucket: bucket),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('a seasoning-to-taste row says why it counts as zero', (
    tester,
  ) async {
    await pump(
      tester,
      const IngredientMatch(
        position: 0,
        raw: 'Salt and pepper',
        item: 'Salt and pepper',
        description: 'Seasoning to taste — no measurable amount',
        confidence: 1,
        status: 'confirmed',
      ),
    );
    expect(
      find.textContaining('Seasoning to taste — no measurable amount'),
      findsOneWidget,
    );
    expect(find.textContaining('counts as zero'), findsOneWidget);
  });

  testWidgets('a weak match with no amount is not "counting now"', (
    tester,
  ) async {
    await pump(
      tester,
      const IngredientMatch(
        position: 5,
        raw: '2 tablespoons Grand Marnier',
        fdcId: 168761,
        description: 'Candies, NESTLE, 100 GRAND Bar',
        dataType: 'SR Legacy',
        confidence: 0.41,
        status: 'auto',
      ),
    );
    expect(find.textContaining('not counted'), findsOneWidget);
    expect(find.textContaining('counting now'), findsNothing);
    expect(find.textContaining('no amount'), findsWidgets);
  });

  testWidgets('a weak match with an amount is counting, and says so', (
    tester,
  ) async {
    await pump(
      tester,
      const IngredientMatch(
        position: 10,
        raw: '1 small head escarole (10 oz), cut up',
        fdcId: 2,
        description: 'Cottage cheese, full fat, curd',
        dataType: 'Foundation',
        confidence: 0.34,
        grams: 283,
        gramSource: 'weight',
        status: 'auto',
      ),
    );
    expect(find.textContaining('counting now'), findsOneWidget);
  });
}
