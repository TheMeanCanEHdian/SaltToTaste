import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/features/admin/nutrition_review_queue.dart';
import 'package:salt_app/features/nutrition/apply_to_all_strip.dart';
import 'package:salt_app/features/nutrition/match_fix_panel.dart';

import 'support/contract_goldens.dart';

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

  testWidgets("a decision an amount edit carried says its grams in the "
      "totals come from the line's previous amount (match.carried_from, "
      'the matches GET golden) — in the sheet and the queue alike, both '
      'WhyLine', (tester) async {
    final items = [
      for (final item in golden('nutrition_matches')['items']! as List)
        item as Map<String, dynamic>,
    ];
    // The golden's rows carry nothing: no label on any of them.
    for (final item in items) {
      expect(item['match'], containsPair('carried_from', null));
      final m = IngredientMatch.fromJson(item);
      expect(m.carriedFrom, isNull);
      await pump(tester, m);
      expect(find.textContaining('previous amount'), findsNothing);
    }
    // The chocolate line, as the GET sends a person's confirm the layout
    // carried from its previous amount (the edit is synthesized: an amount
    // edit is never in the corpus).
    final chocolate = items.singleWhere((i) => i['position'] == 2);
    const before = '4 ounces bittersweet chocolate, chopped coarse';
    final m = IngredientMatch.fromJson({
      ...chocolate,
      'match': {
        ...chocolate['match']! as Map<String, dynamic>,
        'status': 'confirmed',
        'carried_from': before,
      },
    });
    expect(m.carriedFrom, before);
    await pump(tester, m);
    expect(
      find.text(
        'Decided on the line\'s previous amount ("$before") — its grams in '
        'the totals come from that amount; recompute to re-weigh',
      ),
      findsOneWidget,
    );
    // Run 053 S16: a counted row has no why-text of its own — only the
    // carried note shows, never an empty Text above it.
    expect(
      find.descendant(of: find.byType(WhyLine), matching: find.text('')),
      findsNothing,
    );
    // A carried skip weighs nothing: no grams to speak of.
    await pump(
      tester,
      IngredientMatch.fromJson({
        ...chocolate,
        'match': {
          ...chocolate['match']! as Map<String, dynamic>,
          'status': 'skipped',
          'carried_from': before,
        },
      }),
    );
    expect(find.textContaining('previous amount'), findsNothing);
  });

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

  testWidgets("a person's food USDA no longer serves (hold `food_gone`, "
      'server RULE A v27): its reason, and that a pick or a skip — not a '
      'confirm or typed grams — finishes it, in the sheet and the queue', (
    tester,
  ) async {
    // 0857's confirmed flour with 250 g typed, as the server derives it
    // when FDC answers "no such food" (the 404 is synthesized: Run 057
    // Opus critic 2's shape).
    const m = IngredientMatch(
      position: 1,
      raw: '1¾ cups (8¾ ounces) unbleached all-purpose flour',
      item: 'unbleached all-purpose flour',
      fdcId: 789890,
      description: 'Flour, wheat, all-purpose, unenriched, unbleached',
      confidence: 1,
      grams: 250,
      gramSource: 'override',
      status: 'confirmed',
      hold: 'food_gone',
    );
    expect(matchBucketOf(m), MatchBucket.check);
    await pump(tester, m);
    expect(
      find.textContaining('USDA no longer serves this food — pick again'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Pick another food, or skip the line'),
      findsOneWidget,
    );
    expect(find.textContaining('until you confirm it'), findsNothing);
    final note = lineHoldNote(
      NutritionReviewLine.fromJson({
        'recipe': {'id': 'r', 'slug': 'r', 'title': 'Rich Chocolate Bundt'},
        'position': 1,
        'raw': m.raw,
        'bucket': 'check',
        'match': {
          'status': 'confirmed',
          'fdc_id': 789890,
          'grams': 250,
          'hold': 'food_gone',
        },
      }),
    );
    expect(note, contains('Pick another food, or skip the line'));
  });

  test("an apply's receipt names the targets USDA could not weigh "
      '(`unavailable`, server RULE A v27: left for the next compute)', () {
    final note = ApplyToAllStrip.shortfallNote((
      position: 1,
      raw: '¼ cup extra-virgin olive oil',
      recipes: 1,
      lines: 1,
      failed: 0,
      completed: 0,
      completedRecipes: const [],
      moved: 0,
      decided: 0,
      gone: 0,
      failedLines: 0,
      unavailable: 2,
    ));
    expect(
      note,
      '2 lines not weighed (USDA unavailable; left for the next compute).',
    );
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
      '`cured_for_fresh`)', (tester) async {
    // Roast Fresh Ham (0249), as the v8 replay stores it.
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
        hold: 'cured_for_fresh',
      ),
    );
    expect(
      find.textContaining('a preserved record for a fresh ingredient'),
      findsOneWidget,
    );
    expect(find.textContaining('cured'), findsWidgets);
    expect(find.textContaining('fresh herb'), findsNothing);
  });
  // Run 055 S14/O10: WhyLine's hold arms outside Check, each on its own
  // bucket. The rows are the goldens' real lines; the decided states (a
  // pick whose food sizes no grams, a confirm that counts) are synthesized,
  // a stated exception — no golden row is in them.
  testWidgets('S14: a picked in-shell line with no grams (No grams) says '
      'enter the edible grams; a held reason rides the plain No grams text '
      'and a counted row; a skip says only that it is excluded', (
    tester,
  ) async {
    final mussels = IngredientMatch.fromJson({
      ...[
        for (final i in golden('nutrition_matches_rules')['items']! as List)
          i as Map<String, dynamic>,
      ].singleWhere((i) => i['position'] == 6),
    });
    expect(mussels.hold, 'in_shell');
    final picked = IngredientMatch(
      position: mussels.position,
      raw: mussels.raw,
      fdcId: mussels.fdcId,
      description: mussels.description,
      confidence: mussels.confidence,
      status: 'overridden',
      hold: 'in_shell',
    );
    expect(matchBucketOf(picked), MatchBucket.noAmount);
    await pump(tester, picked);
    expect(
      find.textContaining('enter the edible grams (the shells are not eaten)'),
      findsOneWidget,
    );
    const zest = IngredientMatch(
      position: 0,
      raw: '1 teaspoon grated lemon zest plus 2 tablespoons juice',
      item: 'grated lemon zest plus',
      fdcId: 2709168,
      description: 'Lemon, raw',
      confidence: 0.9,
      status: 'overridden',
      hold: 'second_food',
    );
    expect(matchBucketOf(zest), MatchBucket.noAmount);
    await pump(tester, zest);
    expect(
      find.text(
        'Matched, but no amount found — not counted yet. '
        '${holdReason('second_food')}',
      ),
      findsOneWidget,
    );
    const counted = IngredientMatch(
      position: 0,
      raw: '1 teaspoon grated lemon zest plus 2 tablespoons juice',
      item: 'grated lemon zest plus',
      fdcId: 2709168,
      description: 'Lemon, raw',
      confidence: 0.9,
      grams: 4.2,
      gramSource: 'portion',
      status: 'confirmed',
      hold: 'second_food',
    );
    expect(matchBucketOf(counted), MatchBucket.counted);
    await pump(tester, counted);
    expect(find.text(holdReason('second_food')!), findsOneWidget);
    const skipped = IngredientMatch(
      position: 0,
      raw: '1 teaspoon grated lemon zest plus 2 tablespoons juice',
      fdcId: 2709168,
      confidence: 0.9,
      status: 'skipped',
    );
    await pump(tester, skipped);
    expect(find.text('Excluded from the totals'), findsOneWidget);
  });

  // Run 057 S11/O11: the queue's line-hold copy and the app's keep-held set,
  // each pinned by its exact words (real rows of the v26 replay: New
  // England Clam Chowder's clams, Italian Pasta Salad's pepperoncini, Indoor
  // Pulled Chicken's broth, Breaded Chicken Cutlets' flour dredge; the eaten
  // part's grams are synthesized).
  NutritionReviewLine held(String raw, Map<String, Object?> match) =>
      NutritionReviewLine.fromJson({
        'recipe': {'id': 'r', 'slug': 'r', 'title': 'r'},
        'position': 0,
        'raw': raw,
        'bucket': 'check',
        'match': {'status': 'auto', 'fdc_id': 1, ...match},
      });
  const head = 'decided one line at a time, never offers apply-to-all. ';
  const noZero = '. There is no 0 g decision: the API rejects grams of 0.';

  test('the queue: in_shell and second_food — any decision finishes them '
      '(exact copy)', () {
    expect(
      lineHoldNote(
        held(
          '7 pounds medium-size hard-shell clams, such as cherrystones, '
          'washed and scrubbed clean',
          {'hold': 'in_shell'},
        ),
      ),
      'line hold (in shell): ${head}Any decision finishes it: Skip, or the '
      'typed edible grams (the shells are not eaten)$noZero',
    );
    expect(
      lineHoldNote(
        held(
          '1 cup pepperoncini, stemmed, plus 2 tablespoons reserved '
          'liquid',
          {'hold': 'second_food'},
        ),
      ),
      'line hold (second food): ${head}Any decision finishes it: Confirm, '
      'Skip, or a typed positive amount$noZero',
    );
  });

  test("the queue: a held medium's known eaten part — Confirm counts only "
      'it and a pick finishes it; with none, a pick keeps it held', () {
    const raw = '¾ cup unbleached all-purpose flour';
    expect(
      lineHoldNote(
        held(raw, {'hold': 'coating', 'gram_source': 'discarded', 'grams': 30}),
      ),
      'line hold (coating): ${head}Confirm counts only the eaten part (30 g), '
      'Skip if it is poured away, or enter the grams that are eaten; picking '
      'another food also finishes it$noZero',
    );
    expect(
      lineHoldNote(held(raw, {'hold': 'coating'})),
      'line hold (coating): ${head}Skip if it is poured away, or enter the '
      'grams that are eaten; picking another food keeps it held$noZero',
    );
  });

  test("a partial_pour_away (Indoor Pulled Chicken's broth) is kept held by "
      "a pick, as the server's eatenInPartHolds keeps it", () {
    expect(eatenInPartHolds, contains('partial_pour_away'));
    expect(
      heldFinishes('partial_pour_away'),
      'Skip if it is poured away, or enter the grams that are eaten; picking '
      'another food keeps it held',
    );
    expect(
      lineHoldNote(held('1 cup chicken broth', {'hold': 'partial_pour_away'})),
      contains('picking another food keeps it held'),
    );
  });
}
