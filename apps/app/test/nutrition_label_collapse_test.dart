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
const _perServingJson =
    r'''
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
}
