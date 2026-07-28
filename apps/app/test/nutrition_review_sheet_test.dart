// _SeededCubit overrides a method literally named `override`, which shadows
// the `@override` annotation inside that class — so those two methods can't
// carry it.
// ignore_for_file: annotate_overrides
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';
import 'package:salt_app/features/nutrition/review_sheet.dart';

/// Seeds match state and never touches the network.
class _SeededCubit extends NutritionCubit {
  _SeededCubit(NutritionState s) : super(NutritionRepository(Dio()), 'slug') {
    emit(s);
  }

  /// Records every override so tests can assert WHEN a write happens.
  final List<({int position, int? fdcId, double? grams})> overrides = [];

  Future<void> loadMatches({bool force = false}) async {}

  Future<void> override(
    int position, {
    int? fdcId,
    double? grams,
    bool? confirmed,
    bool? skipped,
  }) async {
    overrides.add((position: position, fdcId: fdcId, grams: grams));
  }
}

/// Simulates the real cubit's override emissions offline: on success the row
/// is rewritten (skipped/confirmed/overridden) in a fresh match list — the
/// exact state sequence `NutritionCubit.override` emits; with [failWith] set
/// it emits the failure sequence (position cleared + error in one emit).
class _FlowCubit extends _SeededCubit {
  _FlowCubit(super.s, {this.failWith});

  final String? failWith;

  Future<void> override(
    int position, {
    int? fdcId,
    double? grams,
    bool? confirmed,
    bool? skipped,
  }) async {
    overrides.add((position: position, fdcId: fdcId, grams: grams));
    emit(state.copyWith(overridingPosition: position, clearError: true));
    final error = failWith;
    if (error != null) {
      emit(state.copyWith(clearOverriding: true, error: error));
      return;
    }
    final status = skipped == true
        ? 'skipped'
        : confirmed == true
        ? 'confirmed'
        : 'overridden';
    final updated = [
      for (final m in state.matches!)
        if (m.position == position)
          IngredientMatch(
            position: m.position,
            raw: m.raw,
            fdcId: fdcId ?? m.fdcId,
            description: m.description,
            dataType: m.dataType,
            confidence: m.confidence,
            grams: grams ?? m.grams,
            gramSource: m.gramSource,
            gramBasis: m.gramBasis,
            status: status,
            candidates: m.candidates,
          )
        else
          m,
    ];
    emit(state.copyWith(matches: updated, clearOverriding: true));
  }
}

// Match rows shaped like the real stored ingredient_matches for Acquacotta
// (nutrition is DB-only — never in the YAML corpus).
const _matches = <IngredientMatch>[
  IngredientMatch(
    position: 0,
    raw: '1 large onion, chopped coarse',
    fdcId: 1,
    description: 'Onions, red, raw',
    dataType: 'Foundation',
    confidence: 0.51,
    grams: 110,
    gramSource: 'piece',
    status: 'auto',
  ),
  IngredientMatch(
    position: 7,
    raw: '8 cups chicken broth',
    fdcId: 4,
    description: 'Soup, chicken broth cubes, dry',
    dataType: 'SR Legacy',
    confidence: 0.88,
    grams: 1893,
    gramSource: 'density',
    status: 'auto',
  ),
  IngredientMatch(
    position: 8,
    raw: '1 fennel bulb, cut into 1/2-inch pieces',
    fdcId: 3,
    description: 'Fennel, bulb, raw',
    dataType: 'Foundation',
    confidence: 1,
    status: 'auto',
  ),
  IngredientMatch(
    position: 10,
    raw: '1 small head escarole (10 oz), cut up',
    fdcId: 2,
    description: 'Cottage cheese, full fat, curd',
    dataType: 'Foundation',
    confidence: 0.34,
    grams: 283,
    gramSource: 'weight',
    gramBasis: 'from 10 oz',
    status: 'auto',
    candidates: [
      MatchCandidate(
        fdcId: 99,
        description: 'Escarole, cooked, boiled, drained',
        dataType: 'Foundation',
        confidence: 0.74,
      ),
    ],
  ),
  IngredientMatch(
    position: 5,
    raw: 'Salt and pepper',
    fdcId: 5,
    description: 'Peppers, sweet, green, cooked, boiled',
    dataType: 'SR Legacy',
    confidence: 0.47,
    status: 'skipped',
  ),
];

NutritionState _state() => NutritionState(
  loading: false,
  nutrition: RecipeNutrition.fromJson(const {
    'status': 'partial',
    'serving_basis': 8,
    'matched_count': 3,
    'total_count': 5,
    'low_confidence': 1,
    'per_serving': {
      'energy': {'label': 'Calories', 'amount': 100, 'unit': 'kcal'},
    },
  }),
  matches: _matches,
);

void main() {
  Future<_SeededCubit> open(
    WidgetTester tester, {
    bool isAdmin = true,
    _SeededCubit? seeded,
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = seeded ?? _SeededCubit(_state());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaterialTheme(buildForuiTheme()),
        // FTheme must wrap the Navigator so pushed dialogs/sheets inherit the
        // Forui accessibility scope too.
        builder: (context, child) =>
            FTheme(data: buildForuiTheme(), child: child!),
        home: BlocProvider<NutritionCubit>.value(
          value: cubit,
          child: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: FButton(
                  onPress: () => showReviewSheet(ctx, isAdmin: isAdmin),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return cubit;
  }

  testWidgets('list groups lines by their real bucket', (tester) async {
    await open(tester);
    expect(find.text('Ingredient matches'), findsOneWidget);
    expect(find.text('Needs your attention'), findsOneWidget);
    expect(find.text('Counted — looks good'), findsOneWidget);
    expect(find.text('Skipped'), findsOneWidget);
    // The attention group is open by default; its badges show.
    expect(find.text('check match'), findsOneWidget); // escarole
    expect(find.text('no amount'), findsOneWidget); // fennel
    // The gram basis is surfaced so an estimate can be sanity-checked.
    expect(find.textContaining('amount: from 10 oz'), findsOneWidget);
    // Counted collapses when there is attention — nothing counted showing yet.
    expect(find.text('counted'), findsNothing);
    // Expanding it reveals the counted rows.
    await tester.tap(find.text('Counted — looks good'));
    await tester.pumpAndSettle();
    expect(find.text('counted'), findsNWidgets(2)); // onion + broth
    expect(find.text('1 large onion, chopped coarse'), findsOneWidget);
  });

  testWidgets('fix panel shows current match, a real alternative, and a '
      'unit-converting amount', (tester) async {
    await open(tester);
    // Escarole is the only "check" line, so this label is unique.
    await tester.tap(find.text('Fix match & amount'));
    await tester.pumpAndSettle();

    expect(find.text('Change the match & set the amount'), findsOneWidget);
    // The current match is always shown (the bug fix), as a candidate.
    expect(find.text('Cottage cheese, full fat, curd'), findsOneWidget);
    // The real API alternative is offered.
    expect(find.text('Escarole, cooked, boiled, drained'), findsOneWidget);
    // Amount field + the manual USDA search field.
    expect(find.byType(FTextField), findsNWidgets(2));
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Save match & amount'), findsOneWidget);

    // Switching to oz surfaces a live gram conversion. Scroll the tall panel
    // so the toggle sits inside the dialog's viewport before tapping.
    await tester.ensureVisible(find.text('Save match & amount'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('oz'));
    await tester.pumpAndSettle();
    expect(find.textContaining('≈'), findsOneWidget);
  });

  testWidgets('picking a candidate stages it — nothing is written until Save', (
    tester,
  ) async {
    final cubit = await open(tester);
    await tester.tap(find.text('Fix match & amount'));
    await tester.pumpAndSettle();

    // Picking the alternative must NOT write — it only stages.
    final pick = find.text('Escarole, cooked, boiled, drained');
    await tester.ensureVisible(pick);
    await tester.tap(pick);
    await tester.pumpAndSettle();
    expect(cubit.overrides, isEmpty, reason: 'a pick alone is not a write');
    // The staged pick is reflected in the UI (not yet committed).
    expect(
      find.textContaining('recalculated for the food you picked'),
      findsOneWidget,
    );

    // Save commits the staged food (amount untouched → omitted so the server
    // recalculates it for the new food).
    final save = find.text('Save match & amount');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(cubit.overrides, hasLength(1));
    expect(cubit.overrides.single.fdcId, 99); // the escarole candidate
    expect(cubit.overrides.single.grams, isNull);
  });

  testWidgets('clicking into the amount field is not a hand edit — a re-pick '
      'still lets the server recalculate', (tester) async {
    final cubit = await open(tester);
    await tester.tap(find.text('Fix match & amount'));
    await tester.pumpAndSettle();

    // Stage a different food…
    final pick = find.text('Escarole, cooked, boiled, drained');
    await tester.ensureVisible(pick);
    await tester.tap(pick);
    await tester.pumpAndSettle();

    // …then merely click into the amount box (moving the caret, no typing).
    // A TextEditingController fires its listener on selection moves too, so this
    // used to flip the "edited by hand" flag and freeze the displayed grams.
    final amountField = find.byType(FTextField).last;
    await tester.ensureVisible(amountField);
    await tester.tap(amountField);
    await tester.pumpAndSettle();

    final save = find.text('Save match & amount');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(cubit.overrides, hasLength(1));
    expect(cubit.overrides.single.fdcId, 99);
    // The key assertion: grams stays omitted so the server recomputes for the
    // newly picked food, instead of freezing the old food's displayed weight.
    expect(
      cubit.overrides.single.grams,
      isNull,
      reason: 'a bare click must not turn into a hand-set amount',
    );
  });

  testWidgets('guided mode steps worst-match-first with Back disabled at the '
      'start', (tester) async {
    await open(tester);
    expect(find.text('Guided (2)'), findsOneWidget);
    await tester.tap(find.text('Guided (2)'));
    await tester.pumpAndSettle();

    expect(find.text('Line 1 of 2'), findsOneWidget);
    // Worst confidence first → escarole (34%) leads.
    expect(find.text('1 small head escarole (10 oz), cut up'), findsOneWidget);

    final back = tester.widget<FButton>(
      find.ancestor(of: find.text('Back'), matching: find.byType(FButton)),
    );
    expect(back.onPress, isNull);
  });

  testWidgets('members get a read-only view (no actions)', (tester) async {
    await open(tester, isAdmin: false);
    expect(find.text('Needs your attention'), findsOneWidget);
    expect(find.text('Fix match & amount'), findsNothing);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('guided skip advances by the list shrink alone (review B6)', (
    tester,
  ) async {
    // A third flagged line between escarole (0.34) and fennel (1.0): the
    // old code advanced the index AND let the list shrink, so this middle
    // line was silently jumped over on every fix/skip.
    const celery = IngredientMatch(
      position: 12,
      raw: '2 celery ribs, chopped',
      fdcId: 6,
      description: 'Celery, raw',
      dataType: 'Foundation',
      confidence: 0.42,
      grams: 80,
      gramSource: 'piece',
      status: 'auto',
    );
    final cubit = _FlowCubit(_state().copyWith(matches: [..._matches, celery]));
    await open(tester, seeded: cubit);
    await tester.tap(find.text('Guided (3)'));
    await tester.pumpAndSettle();
    expect(find.text('Line 1 of 3'), findsOneWidget);
    expect(find.text('1 small head escarole (10 oz), cut up'), findsOneWidget);

    await tester.ensureVisible(find.text('Skip line'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip line'));
    await tester.pumpAndSettle();

    expect(find.text('Line 1 of 2'), findsOneWidget);
    expect(find.text('2 celery ribs, chopped'), findsOneWidget);
  });

  testWidgets('a failed guided skip keeps the line and shows the error '
      '(review B5)', (tester) async {
    final cubit = _FlowCubit(_state(), failWith: "Couldn't reach the server.");
    await open(tester, seeded: cubit);
    await tester.tap(find.text('Guided (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Line 1 of 2'), findsOneWidget);

    await tester.ensureVisible(find.text('Skip line'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip line'));
    await tester.pumpAndSettle();

    // The failure is on screen, and the flow did NOT move on as if the
    // skip had landed.
    expect(find.text("Couldn't reach the server."), findsOneWidget);
    expect(find.text('Line 1 of 2'), findsOneWidget);
    expect(find.text('1 small head escarole (10 oz), cut up'), findsOneWidget);
  });
}
