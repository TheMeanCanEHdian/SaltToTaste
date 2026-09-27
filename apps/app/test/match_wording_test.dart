import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/features/nutrition/match_fix_panel.dart';

/// What the review sheet SAYS about a row — the two review fleets found the
/// engine's own explanation never reaching the screen, and a weak match
/// being told it "is counting now" when the totals hold it out.
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

  test('the sheet buckets an engine 0 g by its gram source, as the queue '
      'does', () {
    // Crispy Fish Sandwiches (1081): the frying oil is discarded at 0 g.
    const frying = IngredientMatch(
      position: 11,
      raw: '2 quarts peanut or vegetable oil for frying',
      fdcId: 2710187,
      description: 'Peanut oil',
      dataType: 'Survey (FNDDS)',
      confidence: 0.457,
      grams: 0,
      gramSource: 'discarded',
      status: 'auto',
    );
    expect(matchBucketOf(frying), MatchBucket.counted);
  });

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

  testWidgets(
    'a weak match with an amount is held out of the totals, and says so',
    (tester) async {
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
      // The engine holds a low-confidence auto match out of the totals until
      // it is confirmed — the sheet once claimed it "is counting now".
      expect(find.textContaining('held out of the totals'), findsOneWidget);
      expect(find.textContaining('counting now'), findsNothing);
    },
  );

  testWidgets('a line the engine holds at a passing score says why '
      '(the matches body\'s `hold`)', (tester) async {
    await pump(
      tester,
      const IngredientMatch(
        position: 0,
        raw: '1 teaspoon grated lemon zest plus 2 tablespoons juice',
        item: 'grated lemon zest plus',
        fdcId: 2709168,
        description: 'Lemon, raw',
        confidence: 0.9,
        grams: 4.2,
        status: 'auto',
        hold: 'second_food',
      ),
    );
    expect(
      find.textContaining('also calls for a second ingredient'),
      findsOneWidget,
    );
    expect(find.textContaining('name confidence'), findsNothing);
  });

  testWidgets('a line that names no food says so (hold `unnamed_food`)', (
    tester,
  ) async {
    // Mechouia (0661), as the v7 replay stores it.
    await pump(
      tester,
      const IngredientMatch(
        position: 11,
        raw: '2 tablespoons juice',
        item: '2 tablespoons juice',
        fdcId: 2709682,
        description: 'Beet juice',
        confidence: 0.89,
        grams: 0,
        status: 'auto',
        hold: 'unnamed_food',
      ),
    );
    expect(find.textContaining('does not say which food'), findsOneWidget);
    expect(find.textContaining('like "2 tablespoons'), findsOneWidget);
    expect(find.textContaining('unsweetened'), findsNothing);
  });

  testWidgets('a fresh herb line on a dried spice says so (hold '
      '`dried_for_fresh`)', (tester) async {
    // Ciambotta (0405).
    await pump(
      tester,
      const IngredientMatch(
        position: 0,
        raw: '⅓ cup fresh oregano leaves',
        item: 'fresh oregano leaves',
        fdcId: 171328,
        description: 'Spices, oregano, dried',
        confidence: 0.382,
        grams: 16,
        status: 'auto',
        hold: 'dried_for_fresh',
      ),
    );
    expect(find.textContaining('asks for a fresh herb'), findsOneWidget);
  });

  testWidgets('a fresh meat line on a cured record says so (hold '
      '`dried_for_fresh`)', (tester) async {
    // Roast Fresh Ham (0249), as the v7 replay stores it.
    await pump(
      tester,
      const IngredientMatch(
        position: 0,
        raw:
            '1 (6- to 8-pound) bone-in fresh half ham with skin, preferably '
            'shank end, rinsed',
        item: '(6- to 8-pound) bone-in fresh half ham with skin',
        fdcId: 169174,
        description:
            'Pork, cured, ham, rump, bone-in, separable lean only, unheated',
        confidence: 0.5,
        grams: 3628.7,
        status: 'auto',
        hold: 'dried_for_fresh',
      ),
    );
    expect(find.textContaining('fresh meat'), findsOneWidget);
    expect(find.textContaining('cured'), findsWidgets);
  });
}
