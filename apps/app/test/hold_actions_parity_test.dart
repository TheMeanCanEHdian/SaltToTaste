// v28 RULE A (Run 058 O7/S13, Opus critic 2, Sonnet critics 1 & 3): ONE
// action table per hold family (salt_shared `holdActions`) — the app's
// answer equals the table's for every hold × decision: the review sheet
// never offers a Confirm (or Confirm as-is) the table does not offer, the
// fix panel's typed-grams save is enabled only where the table offers typed
// grams, and the "how it finishes" copy ([heldFinishes], [lineHoldNote])
// says what the table finishes it by. The server side of the same table
// (the PUT's 422 gate, the queue's `finishes` SQL) is pinned in
// apps/server/test/nutrition_v28_rule_a_test.dart.
//
// Real data: 0857's flour line (Rich Chocolate Bundt) and its FDC record
// 789890, as Run 058's O7 probe used them. SYNTHESIZED (a stated
// exception): each hold put on that one row (a row of every hold family is
// what the table covers; the corpus has no food_gone or food_unavailable
// row) and the grams (null, or 250 typed).
// ignore_for_file: annotate_overrides
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show NutritionReviewLine;
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/admin/nutrition_review_queue.dart';
import 'package:salt_app/features/nutrition/match_fix_panel.dart';
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';
import 'package:salt_app/features/nutrition/review_sheet.dart';
import 'package:salt_shared/salt_shared.dart';

class _Sheet extends NutritionCubit {
  _Sheet(NutritionState s) : super(NutritionRepository(Dio()), 'slug') {
    emit(s);
  }
  Future<void> loadMatches({bool force = false}) async {}
  Future<void> override(
    int position, {
    String? raw,
    int? fdcId,
    double? grams,
    bool? confirmed,
    bool? skipped,
  }) async {}
}

const _raw = '1¾ cups (8¾ ounces) unbleached all-purpose flour';

IngredientMatch _held(String? hold, double? grams) => IngredientMatch(
  position: 1,
  raw: _raw,
  fdcId: 789890,
  description: 'Flour, wheat, all-purpose, unenriched, unbleached',
  dataType: 'Foundation',
  // No hold: an engine pick below the gate (Check); a hold: the person's
  // confirmed row carrying it.
  confidence: hold == null ? 0.3 : 1,
  grams: grams,
  gramSource: grams == null ? null : 'override',
  status: hold == null ? 'auto' : 'confirmed',
  hold: hold,
);

/// Opens the review sheet on [m] (Run 058 O7's harness).
Future<void> _open(WidgetTester t, IngredientMatch m) async {
  t.view.physicalSize = const Size(1000, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final c = _Sheet(
    NutritionState(
      loading: false,
      nutrition: RecipeNutrition.fromJson(const {
        'status': 'partial',
        'serving_basis': 8,
        'matched_count': 0,
        'total_count': 1,
        'low_confidence': 0,
        'per_serving': <String, Object?>{},
      }),
      matches: [m],
    ),
  );
  await t.pumpWidget(
    MaterialApp(
      theme: buildMaterialTheme(buildForuiTheme()),
      builder: (ctx, ch) => FTheme(data: buildForuiTheme(), child: ch!),
      home: BlocProvider<NutritionCubit>.value(
        value: c,
        child: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: FButton(
                onPress: () => showReviewSheet(ctx, isAdmin: true),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

/// Every hold the table holds, and none.
final List<String?> _holds = [null, ...holdActions.keys];

void main() {
  test('the table covers every hold the app names, and every hold reads its '
      'own reason (food_unavailable included)', () {
    for (final hold in holdActions.keys) {
      final reason = holdReason(hold);
      expect(reason, isNotNull, reason: hold);
      expect(reason, isNot(startsWith('Held by the engine')), reason: hold);
    }
  });

  test("the confirm predicates never offer what the hold's table row does "
      'not (every hold × grams none / typed)', () {
    for (final hold in _holds) {
      for (final grams in [null, 250.0]) {
        final m = _held(hold, grams);
        final offered = holdActionsOf(hold).offers;
        if (confirmsWithoutAmount(m) || confirmsWithAmount(m)) {
          expect(offered, contains(HoldDecision.confirm), reason: '$hold');
        }
        if (confirmsWithAmount(m)) {
          expect(offered, contains(HoldDecision.typed), reason: '$hold');
        }
        expect(
          noRecordHold(hold),
          !offered.contains(HoldDecision.confirm) &&
              !offered.contains(HoldDecision.typed),
          reason: '$hold',
        );
      }
    }
  });

  test('the "how it finishes" copy says what the table finishes it by', () {
    for (final hold in holdActions.keys) {
      final finishes = holdActionsOf(hold).finishes;
      final text = heldFinishes(hold);
      final noRecord =
          !finishes.contains(HoldDecision.confirm) &&
          !finishes.contains(HoldDecision.typed);
      expect(text.contains('cannot count'), noRecord, reason: hold);
      if (!noRecord) {
        expect(
          text.contains('picking another food keeps it held'),
          !finishes.contains(HoldDecision.pick),
          reason: hold,
        );
      }
    }
    for (final hold in [foodGoneHold, foodUnavailableHold]) {
      final note = lineHoldNote(
        NutritionReviewLine.fromJson({
          'recipe': {'id': 'r', 'slug': 'r', 'title': 'Rich Chocolate Bundt'},
          'position': 1,
          'raw': _raw,
          'bucket': 'check',
          'match': {
            'status': 'confirmed',
            'fdc_id': 789890,
            'grams': 250,
            'hold': hold,
          },
        }),
      );
      expect(
        note,
        startsWith(
          '${hold.replaceAll('_', ' ')}: decided one line at a time. '
          'Pick another food, or skip the line',
        ),
      );
    }
  });

  for (final (hold, typed) in [
    (null, true),
    (foodGoneHold, false),
    (foodUnavailableHold, false),
  ]) {
    testWidgets('the fix panel saves typed grams on the line\'s own food only '
        'where $hold\'s table row offers them', (t) async {
      final m = _held(hold, 250);
      await _open(t, m);
      await t.tap(find.text('Fix match & amount'));
      await t.pumpAndSettle();
      // The amount field, prefilled with the row's 250 g.
      final field = find.byWidgetPredicate(
        (w) => w is EditableText && w.controller.text == '250',
      );
      expect(field, findsOneWidget);
      await t.enterText(field, '100');
      await t.pumpAndSettle();
      final save = t.widget<FButton>(
        find.ancestor(
          of: find.text('Save match & amount'),
          matching: find.byType(FButton),
        ),
      );
      expect(save.onPress != null, typed, reason: '$hold');
      expect(holdActionsOf(hold).offers.contains(HoldDecision.typed), typed);
    });
  }

  for (final hold in _holds) {
    for (final grams in [null, 250.0]) {
      testWidgets("the sheet offers a Confirm only where $hold's table row "
          'does (grams $grams)', (t) async {
        final m = _held(hold, grams);
        await _open(t, m);
        final confirms =
            find.text('Confirm').evaluate().length +
            find.text('Confirm as-is').evaluate().length;
        if (!holdActionsOf(hold).offers.contains(HoldDecision.confirm)) {
          expect(confirms, 0, reason: '$hold');
        }
        // A food with no record says it is out of the totals, and how the
        // table finishes it.
        if (noRecordHold(hold)) {
          expect(
            find.textContaining(
              '— held out of the totals. Pick another food, or skip the line',
            ),
            findsOneWidget,
          );
        }
        // A plain line in check with typed grams is offered Confirm as-is:
        // the table's "offers" is what the sheet shows, not only bounds it.
        if (hold == null &&
            grams != null &&
            matchBucketOf(m) == MatchBucket.check) {
          expect(confirms, greaterThan(0));
        }
      });
    }
  }
}
