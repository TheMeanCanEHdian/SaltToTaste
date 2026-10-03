import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';
import 'package:salt_app/features/nutrition/nutrition_label.dart';

// A real computed label captured from the dev DB
// (recipe_nutrition.nutrients for `100-percent-whole-wheat-pancakes`,
// status=complete, serves 15). Nutrition is DB-only — it never lives in the
// YAML corpus — so a captured real payload is the closest to real-data
// testing this UI allows.
const _perServingJson = r'''
{"energy":{"label":"Calories","amount":156.22,"unit":"kcal","dv_percent":7.8},
"fat":{"label":"Total Fat","amount":6.98,"unit":"g","dv_percent":9.0},
"saturated":{"label":"Saturated Fat","amount":1.6,"unit":"g","dv_percent":8.0},
"trans":{"label":"Trans Fat","amount":0.03,"unit":"g"},
"cholesterol":{"label":"Cholesterol","amount":31.42,"unit":"mg","dv_percent":10.5},
"sodium":{"label":"Sodium","amount":241.75,"unit":"mg","dv_percent":10.5},
"carbs":{"label":"Total Carbohydrate","amount":18.43,"unit":"g","dv_percent":6.7},
"fiber":{"label":"Dietary Fiber","amount":2.2,"unit":"g","dv_percent":7.9},
"sugars":{"label":"Total Sugars","amount":1.78,"unit":"g"},
"protein":{"label":"Protein","amount":5.14,"unit":"g","dv_percent":10.3},
"vitamin_d":{"label":"Vitamin D","amount":0.64,"unit":"µg","dv_percent":3.2},
"calcium":{"label":"Calcium","amount":86.62,"unit":"mg","dv_percent":6.7},
"iron":{"label":"Iron","amount":0.98,"unit":"mg","dv_percent":5.4},
"potassium":{"label":"Potassium","amount":136.4,"unit":"mg","dv_percent":2.9}}
''';

/// Seeds a [NutritionCubit] into a fixed state without touching the network.
class _SeededNutritionCubit extends NutritionCubit {
  _SeededNutritionCubit(NutritionState seeded)
    : super(NutritionRepository(Dio()), 'test-slug') {
    emit(seeded);
  }
}

void main() {
  RecipeNutrition realCompleteLabel() => RecipeNutrition.fromJson({
    'status': 'complete',
    'serving_basis': 15,
    'total_grams': 1066.9,
    'matched_count': 8,
    'total_count': 8,
    'per_serving': jsonDecode(_perServingJson),
  });

  Future<void> pumpPanel(
    WidgetTester tester, {
    RecipeNutrition? nutrition,
    bool isAdmin = false,
    bool startExpanded = true,
    String? yieldText,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: buildMaterialTheme(buildForuiTheme()),
      home: FTheme(
        data: buildForuiTheme(),
        child: BlocProvider<NutritionCubit>.value(
          value: _SeededNutritionCubit(
            NutritionState(
              loading: false,
              nutrition: nutrition ?? realCompleteLabel(),
            ),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: NutritionPanel(
                isAdmin: isAdmin,
                startExpanded: startExpanded,
                yieldText: yieldText,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  // How open the collapsible fold is: 1 = fully expanded, 0 = fully folded.
  double foldValue(WidgetTester tester) =>
      tester.widget<FCollapsible>(find.byType(FCollapsible)).value;

  // v29 (Run 059 O20/S25): the banner reads the server's `stale_reason`
  // — the widget's wiring, not only the words.
  for (final (reason, words) in [
    ('underived', 'A decision is waiting on USDA'),
    ('interrupted', 'A compute is in progress or was interrupted'),
    ('inputs', 'Ingredients changed since this was computed.'),
  ]) {
    testWidgets('a stale label\'s banner says why: $reason', (tester) async {
      await pumpPanel(
        tester,
        nutrition: RecipeNutrition.fromJson({
          'status': 'stale',
          'stale_reason': reason,
          'serving_basis': 15,
          'total_grams': 1066.9,
          'matched_count': 8,
          'total_count': 8,
          'per_serving': jsonDecode(_perServingJson),
        }),
      );
      expect(find.textContaining(words), findsOneWidget);
    });
  }

  testWidgets('label starts expanded: fold open, Hide toggle', (tester) async {
    await pumpPanel(tester);

    // Calories-and-above is always visible.
    expect(find.text('Nutrition Facts'), findsOneWidget);
    expect(find.text('Amount per serving'), findsOneWidget);
    expect(find.text('Calories'), findsOneWidget);

    // The detail region is rendered and the fold is fully open.
    expect(find.text('% Daily Value*'), findsOneWidget);
    expect(foldValue(tester), moreOrLessEquals(1));

    // The toggle offers to fold, not unfold.
    expect(find.text('Hide details'), findsOneWidget);
    expect(find.text('Full nutrition facts'), findsNothing);
  });

  testWidgets('a per-batch basis says so beside the per-serving header; a '
      'serves count does not (basis_kind, checkpoint 6)', (tester) async {
    await pumpPanel(tester);
    expect(find.text('Per serving · serves 15'), findsOneWidget);
    expect(find.textContaining('per batch'), findsNothing);

    // The same real payload on the basis a MAKES 1 LOAF recipe gets.
    await pumpPanel(
      tester,
      nutrition: RecipeNutrition.fromJson({
        'status': 'complete',
        'serving_basis': 1,
        'basis_kind': 'per_batch',
        'total_grams': 1066.9,
        'matched_count': 8,
        'total_count': 8,
        'per_serving': jsonDecode(_perServingJson),
      }),
    );
    // D: an outlined tag beside the header, not header text.
    expect(find.text('Per serving · serves 1'), findsOneWidget);
    final tag = find.text('per batch');
    expect(tag, findsOneWidget);
    final box = tester.widget<Container>(
      find.ancestor(of: tag, matching: find.byType(Container)).first,
    );
    expect((box.decoration! as BoxDecoration).border, Border.all(width: 1.2));
    // No yield to name (Latin Flan has none): the tag stands alone.
    expect(find.textContaining('so one serving is'), findsNothing);
  });

  testWidgets('under the tag, one line names the yield it came from '
      '(Challah, "MAKES 1 LOAF")', (tester) async {
    RecipeNutrition batch(String kind) => RecipeNutrition.fromJson({
      'status': 'complete',
      'serving_basis': 1,
      'basis_kind': kind,
      'total_grams': 1066.9,
      'matched_count': 8,
      'total_count': 8,
      'per_serving': jsonDecode(_perServingJson),
    });
    await pumpPanel(
      tester,
      nutrition: batch('per_batch'),
      yieldText: 'MAKES 1 LOAF',
    );
    expect(
      find.text(
        'The recipe says "MAKES 1 LOAF", so one serving is the whole loaf.',
      ),
      findsOneWidget,
    );
    // A per-serving basis of 1 (MAKES 1 OMELET) says nothing of the sort.
    await pumpPanel(
      tester,
      nutrition: batch('per_serving'),
      yieldText: 'MAKES 1 OMELET',
    );
    expect(find.textContaining('so one serving is'), findsNothing);
  });

  test('perBatchYieldLine on the corpus MAKES-1 yields of snapshot 11', () {
    for (final (servings, line) in [
      (
        'MAKES 1 LOAF',
        'The recipe says "MAKES 1 LOAF", so one serving is the whole loaf.',
      ),
      (
        'MAKES ONE 9-INCH LOAF',
        'The recipe says "MAKES ONE 9-INCH LOAF", so one serving is the '
            'whole 9-inch loaf.',
      ),
      // Only the yield, up to its first comma; no count of one names no
      // thing, so the batch is the whole.
      (
        'MAKES ABOUT ¼ CUP, ENOUGH TO DRESS 8 TO 10 CUPS LIGHTLY PACKED '
            'GREENS',
        'The recipe says "MAKES ABOUT ¼ CUP", so one serving is the whole '
            'batch.',
      ),
      (
        'MAKES ENOUGH FOR ONE 9-INCH PIE',
        'The recipe says "MAKES ENOUGH FOR ONE 9-INCH PIE", so one serving '
            'is the whole batch.',
      ),
      // The first clause ends at a semicolon too.
      (
        'MAKES ABOUT 1½ CUPS; ENOUGH FOR 3 CUPS ICED COFFEE',
        'The recipe says "MAKES ABOUT 1½ CUPS", so one serving is the whole '
            'batch.',
      ),
      // A range from one is the midpoint batch, never "the whole to 16
      // eggs" (S6: per_batch).
      (
        'MAKES 1 TO 16 EGGS',
        'The recipe says "MAKES 1 TO 16 EGGS", so one serving is the whole '
            'batch.',
      ),
      // Synthesized (stated exception): the corpus writes every yield in
      // capitals; an editor-typed one is read the same way, and a trailing
      // parenthetical is no part of the thing.
      (
        'Makes 1 loaf',
        'The recipe says "Makes 1 loaf", so one serving is the whole loaf.',
      ),
      (
        'MAKES 1 LOAF (ABOUT 2 POUNDS)',
        'The recipe says "MAKES 1 LOAF (ABOUT 2 POUNDS)", so one serving is '
            'the whole loaf.',
      ),
      // No yield (Latin Flan), or a serves count at an admin's basis of 1.
      (null, null),
      ('SERVES 4', null),
    ]) {
      expect(perBatchYieldLine(servings), line, reason: servings);
    }
  });

  testWidgets('collapsing folds the detail region shut', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('Hide details'));
    await tester.pumpAndSettle();

    // The fold is fully closed: value 0 and the region clipped to no height
    // (FCollapsible also drops the clipped content from semantics/focus).
    expect(foldValue(tester), moreOrLessEquals(0));
    expect(tester.getSize(find.byType(FCollapsible)).height, 0);

    // Calories-and-above survives the fold.
    expect(find.text('Nutrition Facts'), findsOneWidget);
    expect(find.text('Amount per serving'), findsOneWidget);
    expect(find.text('Calories'), findsOneWidget);

    // The toggle now offers to unfold.
    expect(find.text('Full nutrition facts'), findsOneWidget);
    expect(find.text('Hide details'), findsNothing);
  });

  testWidgets('expanding again reopens the fold', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('Hide details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full nutrition facts'));
    await tester.pumpAndSettle();

    expect(foldValue(tester), moreOrLessEquals(1));
    expect(tester.getSize(find.byType(FCollapsible)).height, greaterThan(0));
    expect(find.text('Hide details'), findsOneWidget);
  });

  testWidgets('startExpanded:false opens folded (recipes with an image)', (
    tester,
  ) async {
    await pumpPanel(tester, startExpanded: false);
    await tester.pumpAndSettle();

    expect(foldValue(tester), moreOrLessEquals(0));
    expect(tester.getSize(find.byType(FCollapsible)).height, 0);
    expect(find.text('Full nutrition facts'), findsOneWidget);
    expect(find.text('Hide details'), findsNothing);
  });

  testWidgets('members get no panel when there is no nutrition data', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      nutrition: const RecipeNutrition(status: 'none'),
      isAdmin: false,
    );

    // Nothing at all — no empty placeholder, no label.
    expect(find.text('No nutrition data yet'), findsNothing);
    expect(find.text('Nutrition Facts'), findsNothing);
    expect(find.byType(FCollapsible), findsNothing);
  });

  testWidgets('admins still get the compute box when there is no data', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      nutrition: const RecipeNutrition(status: 'none'),
      isAdmin: true,
    );

    expect(find.text('No nutrition data yet'), findsOneWidget);
  });

  testWidgets('a label with no detail nutrient has no fold, and disposes '
      'without building one', (tester) async {
    // Stated exception (synthesized): every stored label carries the
    // detail nutrients; an energy-only map (the captured label cut to its
    // calories) is the no-fold case the widget still has to handle.
    await pumpPanel(
      tester,
      nutrition: RecipeNutrition.fromJson({
        'status': 'complete',
        'serving_basis': 15,
        'matched_count': 8,
        'total_count': 8,
        'per_serving': {
          'energy': (jsonDecode(_perServingJson) as Map)['energy'],
        },
      }),
    );
    expect(find.text('Nutrition Facts'), findsOneWidget);
    expect(find.byType(FCollapsible), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
