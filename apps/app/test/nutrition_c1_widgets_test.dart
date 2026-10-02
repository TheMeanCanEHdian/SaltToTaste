// _Recording overrides a method literally named `override`, which shadows the
// `@override` annotation inside that class.
// ignore_for_file: annotate_overrides
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/admin/nutrition_review_queue.dart';
import 'package:salt_app/features/nutrition/apply_to_all_strip.dart';
import 'package:salt_app/features/nutrition/match_fix_panel.dart';
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';
import 'package:salt_app/features/nutrition/review_sheet.dart';

import 'support/contract_goldens.dart';

/// Every override names the line it was made on: `raw` is the text of the
/// row shown at [position], so the server can refuse a write whose line
/// moved (409 line_moved). Dropping `raw` at any call site fails here.
void expectRawSent(NutritionState state, int position, String? raw) => expect(
  raw,
  state.matches!.singleWhere((m) => m.position == position).raw,
  reason: 'override($position) must send the raw it was made on',
);

/// Seeds match state, never touches the network, and records every write.
class _Recording extends NutritionCubit {
  _Recording(NutritionState s) : super(NutritionRepository(Dio()), 'slug') {
    emit(s);
  }

  final List<
    ({int position, int? fdcId, double? grams, bool? confirmed, bool? skipped})
  >
  writes = [];

  Future<void> loadMatches({bool force = false}) async {}

  Future<void> override(
    int position, {
    String? raw,
    int? fdcId,
    double? grams,
    bool? confirmed,
    bool? skipped,
  }) async {
    expectRawSent(state, position, raw);
    writes.add((
      position: position,
      fdcId: fdcId,
      grams: grams,
      confirmed: confirmed,
      skipped: skipped,
    ));
  }
}

/// The nutrition-rules golden's lines (real corpus lines computed over the
/// recorded FDC answers): the mussels held in the shell (6), the pasta
/// water's salt with its eaten "plus" part (10), pancetta counted as bacon
/// (11) and the butter sticks (12, counted by matcher v14: [butterNoGrams]).
IngredientMatch rulesLine(int position) => [
  for (final item in golden('nutrition_matches_rules')['items'] as List)
    IngredientMatch.fromJson(item as Map<String, dynamic>),
].singleWhere((m) => m.position == position);

/// The butter sticks (12) as matcher v13 stored them — Classic Yellow
/// Layer Cake (0884) pos 13 in sweep snapshot 12: grams null, its "stick"
/// portion unread. Matcher v14 reads the portion, so the rules golden
/// counts them at 452 g; the amount-first block below is what a person
/// sees on any such no-grams row, pinned on the golden's own portions.
IngredientMatch butterNoGrams({
  bool uncached = false,
  double? confidence,
  String? raw,
}) {
  final item = Map<String, dynamic>.of(
    (golden('nutrition_matches_rules')['items'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((m) => m['position'] == 12),
  );
  if (uncached) {
    item['portions'] = <Object?>[];
  }
  if (raw != null) {
    item['raw'] = raw;
  }
  item['match'] = {
    ...item['match'] as Map<String, dynamic>,
    'grams': null,
    'gram_source': null,
    'gram_basis': null,
    'confidence': ?confidence,
  };
  return IngredientMatch.fromJson(item);
}

// "1 cup packed brown sugar" (Cranberry Chutney with Apples and
// Crystallized Ginger) on "Sugars, brown" (168833): the record's
// "cup packed" and "cup unpacked" both name a cup — the fills the
// server computes — so which one the line means is the person's call.
IngredientMatch _brownSugar() => IngredientMatch.fromJson(const {
  'position': 6,
  'raw': '1 cup packed brown sugar',
  'line_amount': '1 cup',
  'portions': [
    {
      'amount': 1.0,
      'unit': null,
      'description': 'cup packed',
      'grams': 220.0,
      'fill': 220.0,
    },
    {
      'amount': 1.0,
      'unit': null,
      'description': 'tsp packed',
      'grams': 4.6,
      'fill': null,
    },
    {
      'amount': 1.0,
      'unit': null,
      'description': 'cup unpacked',
      'grams': 145.0,
      'fill': 145.0,
    },
  ],
  'match': {
    'fdc_id': 168833,
    'description': 'Sugars, brown',
    'data_type': 'SR Legacy',
    'confidence': 1.0,
    'grams': null,
    'gram_source': null,
    'status': 'auto',
  },
  'candidates': [],
});

/// Real sweep-snapshot-11 rows (nutrition is DB-only, never in the corpus).
// Rainbow Cake pos 8: an amount-less line the engine counts at 0 g on a 3%
// guess.
const _dye = IngredientMatch(
  position: 8,
  raw: 'Gel food dye (red, orange, yellow, green, blue, and purple)',
  fdcId: 170300,
  description: 'Fast foods, coleslaw',
  dataType: 'SR Legacy',
  confidence: 0.033333333333333326,
  grams: 0,
  gramSource: 'unmeasured',
  gramBasis: 'no amount on the line — counted as 0 g',
  status: 'auto',
);
// Skillet Chicken and Rice with Peas and Scallions pos 14: a 0 g row at 91%
// keeps its food.
const _lemon = IngredientMatch(
  position: 14,
  raw: 'Lemon wedges, for serving',
  fdcId: 2709168,
  description: 'Lemon, raw',
  dataType: 'Survey (FNDDS)',
  confidence: 0.91,
  grams: 0,
  gramSource: 'unmeasured',
  gramBasis: 'no amount on the line — counted as 0 g',
  status: 'auto',
);
// Chicken Francese pos 8: the one discarded zero below the gate.
const _fryingOil = IngredientMatch(
  position: 8,
  raw: '⅓ cup extra-virgin olive oil for frying',
  fdcId: 2710186,
  description: 'Olive oil',
  dataType: 'Survey (FNDDS)',
  confidence: 0.45666666666666667,
  grams: 0,
  gramSource: 'discarded',
  gramBasis: 'discarded in cooking — counted as 0 g',
  status: 'auto',
);
// Vietnamese Beef Pho pos 16: a right guess below the gate (Basil, raw).
const _basil = IngredientMatch(
  position: 16,
  raw: 'Sprigs fresh Thai or Italian basil',
  fdcId: 2709780,
  description: 'Basil, raw',
  dataType: 'Survey (FNDDS)',
  confidence: 0.37666666666666665,
  grams: 0,
  gramSource: 'unmeasured',
  status: 'auto',
);
// Perfect Roast Chicken pos 1: a brine's sugar, held, 94 g on its portion.
const _brineSugar = IngredientMatch(
  position: 1,
  raw: '½ cup sugar',
  fdcId: 746784,
  description: 'Sugars, granulated',
  dataType: 'Foundation',
  confidence: 0.95,
  grams: 94,
  gramSource: 'portion',
  status: 'auto',
  hold: 'discarded_medium',
);
// Chana Masala pos 2: ginger with no grams, and its record's cached portions
// (fdc_food_cache 169231), none of them a piece.
IngredientMatch get _ginger => IngredientMatch.fromJson(const {
  'position': 2,
  'raw': '1 (1½-inch) piece ginger, peeled and chopped coarse',
  'line_amount': '1 piece',
  // Its cached record's energy (208): 80 kcal per 100 g.
  'kcal_per_100g': 80.0,
  'portions': [
    {
      'amount': 5.0,
      'unit': null,
      'description': 'slices (1" dia)',
      'grams': 11.0,
      'fill': null,
    },
    {
      'amount': 0.25,
      'unit': null,
      'description': 'cup slices (1" dia)',
      'grams': 24.0,
      'fill': null,
    },
    {
      'amount': 1.0,
      'unit': null,
      'description': 'tsp',
      'grams': 2.0,
      'fill': null,
    },
  ],
  'match': {
    'fdc_id': 169231,
    'description': 'Ginger root, raw',
    'data_type': 'SR Legacy',
    'confidence': 0.887,
    'grams': null,
    'gram_source': null,
    'status': 'auto',
  },
  'candidates': [],
});

/// Rainbow Cake's stored label on snapshot 11 (complete, 10/10, basis 20),
/// over the rows a test puts on its sheet.
NutritionState _state(List<IngredientMatch> matches) => NutritionState(
  loading: false,
  nutrition: RecipeNutrition.fromJson(const {
    'status': 'complete',
    'serving_basis': 20,
    'matched_count': 10,
    'total_count': 10,
    'low_confidence': 0,
    'per_serving': {
      'energy': {'label': 'Calories', 'amount': 811.2, 'unit': 'kcal'},
    },
  }),
  matches: matches,
);

void main() {
  Future<_Recording> openSheet(
    WidgetTester tester,
    List<IngredientMatch> matches, {
    bool isAdmin = true,
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cubit = _Recording(_state(matches));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaterialTheme(buildForuiTheme()),
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

  /// The fix panel alone, as both surfaces host it.
  Future<_Recording> pumpPanel(
    WidgetTester tester,
    IngredientMatch match, {
    List<IngredientMatch>? recipe,
    String? recipeTitle,
    VoidCallback? onSkip,
  }) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cubit = _Recording(_state(recipe ?? [match]));
    // Dispose any previous tree first: an identical tree never remounts.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaterialTheme(buildForuiTheme()),
        builder: (context, child) =>
            FTheme(data: buildForuiTheme(), child: child!),
        home: RepositoryProvider<NutritionRepository>.value(
          value: NutritionRepository(Dio()),
          child: BlocProvider<NutritionCubit>.value(
            value: cubit,
            child: Scaffold(
              body: SingleChildScrollView(
                child: FixPanel(
                  match: match,
                  busy: false,
                  onDone: () {},
                  showCancel: false,
                  recipeTitle: recipeTitle,
                  onSkip: onSkip,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  bool enabled(WidgetTester tester, String label) =>
      tester
          .widget<FButton>(
            find.ancestor(of: find.text(label), matching: find.byType(FButton)),
          )
          .onPress !=
      null;

  group('U1: a zero below the gate is a zero, not a food (ruling 9)', () {
    testWidgets('the sheet row hides the guess behind "Counts as zero" and a '
        'grey badge; an admin can open the guess; the summary says it', (
      tester,
    ) async {
      // Both zeros are counted, and nothing needs attention: the Counted
      // group opens by itself.
      await openSheet(tester, [_dye, _lemon]);
      expect(find.text('counts as zero'), findsOneWidget);
      expect(
        find.textContaining('Counts as zero (no amount)', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Fast foods, coleslaw'), findsNothing);
      // 91%: the food stays, with the green badge.
      expect(
        find.textContaining('Lemon, raw', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('counted'), findsOneWidget);
      expect(
        find.textContaining('10 counting, 1 of them as zero'),
        findsOneWidget,
      );
      await tester.tap(find.text('Engine guess — not used'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Fast foods, coleslaw · 3% name. Too weak to show as this '
          "line's food, and it adds 0 g either way.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('a member never sees the guess', (tester) async {
      await openSheet(tester, [_dye], isAdmin: false);
      expect(find.text('Engine guess — not used'), findsNothing);
      expect(find.textContaining('coleslaw'), findsNothing);
    });

    testWidgets('the discarded zero says so', (tester) async {
      await openSheet(tester, [_fryingOil]);
      expect(
        find.textContaining(
          'Counts as zero (discarded in cooking)',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Olive oil'), findsNothing);
    });

    testWidgets('an amount alone does not save a zero row', (tester) async {
      await pumpPanel(tester, _basil);
      await tester.enterText(find.byType(EditableText).last, '5');
      await tester.pumpAndSettle();
      expect(enabled(tester, 'Save match & amount'), isFalse);
    });

    testWidgets('the fix panel strikes the guess, selects nothing, and saves '
        'only a food AND an amount', (tester) async {
      final cubit = await pumpPanel(tester, _basil);
      expect(
        find.text('Give it a food and an amount to count it'),
        findsOneWidget,
      );
      expect(find.text('engine guess · 38% · not used'), findsOneWidget);
      final guess = tester.widget<Text>(find.text('Basil, raw'));
      expect(guess.style!.decoration, TextDecoration.lineThrough);
      expect(find.byIcon(FLucideIcons.check), findsNothing);
      expect(find.text('The line gives no amount.'), findsOneWidget);
      expect(enabled(tester, 'Save match & amount'), isFalse);
      // A food alone is not enough: a pick re-derives grams from the line,
      // which has no amount...
      await tester.tap(find.text('Basil, raw'));
      await tester.pumpAndSettle();
      expect(find.byIcon(FLucideIcons.check), findsOneWidget);
      expect(enabled(tester, 'Save match & amount'), isFalse);
      // ...a food and an amount are.
      await tester.enterText(find.byType(EditableText).last, '5');
      await tester.pumpAndSettle();
      expect(enabled(tester, 'Save match & amount'), isTrue);
      await tester.tap(find.text('Save match & amount'));
      await tester.pumpAndSettle();
      expect(cubit.writes, [
        (
          position: 16,
          fdcId: 2709780,
          grams: 5.0,
          confirmed: null,
          skipped: null,
        ),
      ]);
    });
  });

  group('U3: grams belong to the confirm (the amount-first block)', () {
    testWidgets('"4 sticks unsalted butter": the one stick portion prefills '
        '452 and the button follows the number', (tester) async {
      final cubit = await pumpPanel(tester, butterNoGrams());
      expect(find.text('How much is it?'), findsOneWidget);
      expect(
        find.textContaining('The line says 4 stick.', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('4 × stick 113 g = 452 g'), findsOneWidget);
      expect(find.text('tbsp · 14.2 g'), findsOneWidget);
      expect(find.text('cup · 227 g'), findsOneWidget);
      expect(find.text('Confirm · 452 g'), findsOneWidget);
      expect(enabled(tester, 'Confirm · 452 g'), isTrue);
      // The candidates wait behind "Wrong food?".
      expect(find.text('Save match & amount'), findsNothing);
      await tester.tap(find.text('Confirm · 452 g'));
      await tester.pumpAndSettle();
      expect(cubit.writes, [
        (
          position: 12,
          fdcId: null,
          grams: 452.0,
          confirmed: true,
          skipped: null,
        ),
      ]);
    });

    testWidgets('a typed amount is replaced by a tap on the fitting portion; '
        'the reference portions do not fill', (tester) async {
      await pumpPanel(tester, butterNoGrams());
      await tester.enterText(find.byType(EditableText).first, '100');
      await tester.pumpAndSettle();
      expect(find.text('Confirm · 100 g'), findsOneWidget);
      await tester.tap(find.text('tbsp · 14.2 g'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm · 100 g'), findsOneWidget);
      await tester.tap(find.text('4 × stick 113 g = 452 g'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm · 452 g'), findsOneWidget);
    });

    testWidgets('ginger: no portion is a piece — the field asks for "grams '
        'for 1 piece" and Confirm waits for a number', (tester) async {
      final cubit = await pumpPanel(tester, _ginger);
      expect(
        find.textContaining(
          "USDA's portions for this food don't include a piece, so the "
          'engine could not convert:',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'The line says 1 piece (1½-inch). USDA',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text('5 slices (1" dia) · 11 g'), findsOneWidget);
      expect(find.text('¼ cup slices (1" dia) · 24 g'), findsOneWidget);
      // Among counted chips the one says its count.
      expect(find.text('1 tsp · 2 g'), findsOneWidget);
      expect(find.text('grams for 1 piece'), findsOneWidget);
      expect(find.text('Confirm with amount'), findsOneWidget);
      expect(enabled(tester, 'Confirm with amount'), isFalse);
      await tester.tap(find.text('5 slices (1" dia) · 11 g'));
      await tester.pumpAndSettle();
      expect(enabled(tester, 'Confirm with amount'), isFalse);
      await tester.enterText(find.byType(EditableText).first, '30');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm · 30 g'));
      await tester.pumpAndSettle();
      expect(cubit.writes.single.grams, 30);
      expect(cubit.writes.single.confirmed, isTrue);
    });

    testWidgets('"Wrong food?" opens the candidates and saves the pick with '
        'the amount above', (tester) async {
      await pumpPanel(tester, butterNoGrams());
      await tester.tap(find.text('Wrong food? Change the match…'));
      await tester.pumpAndSettle();
      expect(find.text('Save match & amount'), findsOneWidget);
      expect(enabled(tester, 'Save match & amount'), isFalse);
    });
  });

  group('Run 046 A1/A2: the staged pick is what the amount-first block '
      'writes', () {
    const peanut = 'Peanut butter, smooth style, without salt';

    Future<_Recording> pickPeanutButter(WidgetTester tester) async {
      final cubit = await pumpPanel(tester, butterNoGrams());
      await tester.tap(find.text('Wrong food? Change the match…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(peanut));
      await tester.pumpAndSettle();
      return cubit;
    }

    testWidgets("A2: a new pick clears the stored record's prefill and hides "
        'its portion chips', (tester) async {
      await pickPeanutButter(tester);
      expect(find.text('4 × stick 113 g = 452 g'), findsNothing);
      expect(find.text('tbsp · 14.2 g'), findsNothing);
      expect(find.text('Confirm with amount'), findsOneWidget);
      expect(enabled(tester, 'Confirm with amount'), isFalse);
      // A re-pick of the stored food brings the prefill back.
      await tester.tap(find.text('Butter, without salt'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm · 452 g'), findsOneWidget);
      expect(find.text('4 × stick 113 g = 452 g'), findsOneWidget);
    });

    testWidgets('A2: Save after a pick, amount untouched, sends no grams — '
        'the server recomputes for the pick', (tester) async {
      final cubit = await pickPeanutButter(tester);
      await tester.tap(find.text('Save match & amount'));
      await tester.pumpAndSettle();
      expect(cubit.writes, [
        (
          position: 12,
          fdcId: 172470,
          grams: null,
          confirmed: null,
          skipped: null,
        ),
      ]);
    });

    testWidgets('A1: Enter in the amount field writes the pick with the '
        'amount, never a confirm of the rejected butter', (tester) async {
      final cubit = await pickPeanutButter(tester);
      await tester.enterText(find.byType(EditableText).first, '300');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(cubit.writes, [
        (
          position: 12,
          fdcId: 172470,
          grams: 300.0,
          confirmed: null,
          skipped: null,
        ),
      ]);
    });

    testWidgets('A1: the Confirm button writes the pick with the amount', (
      tester,
    ) async {
      final cubit = await pickPeanutButter(tester);
      await tester.enterText(find.byType(EditableText).first, '452');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm · 452 g'));
      await tester.pumpAndSettle();
      expect(cubit.writes.single.fdcId, 172470);
      expect(cubit.writes.single.grams, 452);
      expect(cubit.writes.single.confirmed, isNull);
    });

    testWidgets('Run 048 P6: an amount typed BEFORE the pick stays', (
      tester,
    ) async {
      await pumpPanel(tester, butterNoGrams());
      await tester.tap(find.text('Wrong food? Change the match…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, '300');
      await tester.pumpAndSettle();
      await tester.tap(find.text(peanut));
      await tester.pumpAndSettle();
      expect(find.text('Confirm · 300 g'), findsOneWidget);
    });

    testWidgets("Run 048 P6: a pick on a counted line keeps its stored "
        'grams in the field (only the amount-first prefill clears)', (
      tester,
    ) async {
      // The rules golden's butter, counted at 452 g (matcher v14).
      await pumpPanel(tester, rulesLine(12));
      expect(find.text('452'), findsOneWidget);
      await tester.tap(find.text(peanut));
      await tester.pumpAndSettle();
      expect(find.text('452'), findsOneWidget);
    });

    testWidgets('Run 048 P6: a re-pick of the STORED food confirms it with '
        'the amount, never a pick write', (tester) async {
      final cubit = await pickPeanutButter(tester);
      await tester.tap(find.text('Butter, without salt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm · 452 g'));
      await tester.pumpAndSettle();
      expect(cubit.writes, [
        (
          position: 12,
          fdcId: null,
          grams: 452.0,
          confirmed: true,
          skipped: null,
        ),
      ]);
    });

    testWidgets("Run 048 P6: after a pick the stored record's portions stop "
        'explaining the miss', (tester) async {
      // Stated exception (synthesized grams): the rules golden's chicken
      // pieces (pos 3, its real portions and candidates) with grams null — a
      // pound line always converts by weight, so no stored row puts a
      // unit-bearing line with non-fitting portions AND other candidates
      // in No grams.
      final item = Map<String, dynamic>.of(
        (golden('nutrition_matches_rules')['items'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((m) => m['position'] == 3),
      );
      item['match'] = {
        ...item['match'] as Map<String, dynamic>,
        'grams': null,
        'gram_source': null,
        'gram_basis': null,
      };
      await pumpPanel(tester, IngredientMatch.fromJson(item));
      expect(
        find.textContaining("don't include a pound", findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.text('Wrong food? Change the match…'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Chicken, broilers or fryers, thigh, meat and skin, raw'),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining("don't include", findRichText: true),
        findsNothing,
      );
    });
  });

  testWidgets('S3: a bare count ("6 whole cloves") says the count and asks '
      'grams for it; no portion "misses a unit"', (tester) async {
    // Vietnamese Beef Pho pos 8: its matches body over a copy of snapshot
    // 12 (cache only): line_amount "6", the ground-clove record's two
    // cached portions, neither a fill.
    final cloves = IngredientMatch.fromJson(const {
      'position': 8,
      'raw': '6 whole cloves',
      'item': 'whole cloves',
      'line_amount': '6',
      'kcal_per_100g': 274.0,
      'portions': [
        {'amount': 1.0, 'description': 'tsp', 'grams': 2.1},
        {'amount': 1.0, 'description': 'tbsp', 'grams': 6.5},
      ],
      'match': {
        'fdc_id': 171321,
        'description': 'Spices, cloves, ground',
        'data_type': 'SR Legacy',
        'confidence': 0.9333333333333333,
        'grams': null,
        'status': 'auto',
      },
    });
    await pumpPanel(tester, cloves);
    expect(
      find.textContaining('The line says 6.', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining("don't include", findRichText: true),
      findsNothing,
    );
    expect(find.text('grams for 6'), findsOneWidget);
    expect(find.text('tsp · 2.1 g'), findsOneWidget);
  });

  testWidgets('R1: a unit-only amount ("Dash of hot sauce") is the unit: '
      'the portions "don\'t include a dash"', (tester) async {
    // Easier Fried Chicken (0149) pos 2: its matches body over snapshot 12's
    // cached 2710093 (pinned server-side in nutrition_c1_test.dart):
    // line_amount "dash", five portions, none a fill.
    final dash = IngredientMatch.fromJson(const {
      'position': 2,
      'raw': 'Dash of hot sauce',
      'item': 'of hot sauce',
      'line_amount': 'dash',
      'portions': [
        {'description': 'Quantity not specified', 'grams': 5.0},
        {'description': '10 drops', 'grams': 0.8},
        {'description': '1 packet', 'grams': 9.0},
        {'description': '1 tablespoon', 'grams': 16.0},
        {'description': 'Guideline amount per sandwich', 'grams': 9.0},
      ],
      'match': {
        'fdc_id': 2710093,
        'description': 'Hot pepper sauce',
        'data_type': 'Survey (FNDDS)',
        'confidence': 0.92333333333333334,
        'grams': null,
        'status': 'auto',
      },
    });
    await pumpPanel(tester, dash);
    expect(
      find.textContaining(
        "The line says dash. USDA's portions for this food don't include a "
        'dash, so the engine could not convert:',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.text('grams for dash'), findsOneWidget);
  });

  // Braised Chicken with Mustard and Herbs (0125) pos 1 in snapshot 12:
  // auto on 2727569 just above the gate with grams null (No grams), the
  // stored quantity '1 1/2–2' with no unit, and the record's one cached
  // portion (racc 114 g), which fills nothing.
  Map<String, dynamic> chicken0125({String lineAmount = '1 1/2–2'}) => {
    'position': 1,
    'raw':
        '1½–2 ounds bone-in split chicken breasts, trimmed and each cut '
        'crosswise into 2 pieces of equal mass',
    'line_amount': lineAmount,
    'portions': [
      {
        'amount': 1.0,
        'unit': 'racc',
        'description': null,
        'grams': 114.0,
        'fill': null,
      },
    ],
    'match': {
      'fdc_id': 2727569,
      'description': 'Chicken, breast, meat and skin, raw',
      'data_type': 'Foundation',
      'confidence': 0.51857142857142857,
      'grams': null,
      'gram_source': null,
      'status': 'auto',
    },
  };

  testWidgets("Run 048 A3: the codec's mixed number ('1 1/2–2') is a bare "
      'count, never the unit "1/2–2"', (tester) async {
    await pumpPanel(tester, IngredientMatch.fromJson(chicken0125()));
    expect(
      find.textContaining('The line says 1 1/2–2', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining("don't include", findRichText: true),
      findsNothing,
    );
  });

  testWidgets("Run 048 P6: a one-word vulgar fraction ('½') is a count, "
      'not a unit', (tester) async {
    // Stated exception (synthesized amount): the codec writes a half as
    // '1/2', so no corpus line_amount holds a vulgar fraction; a
    // hand-edited YAML quantity can ('quantity' is any string). 0125's
    // real row with its amount replaced by a bare '½'.
    await pumpPanel(
      tester,
      IngredientMatch.fromJson(chicken0125(lineAmount: '½')),
    );
    expect(
      find.textContaining('The line says ½', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining("don't include", findRichText: true),
      findsNothing,
    );
  });

  test('the zero-guess guards, one by one', () {
    // Indoor Pulled Pork (0246) pos 2 on snapshot 12: a discarded medium
    // whose "plus 2 teaspoons" is eaten and counted (9.5 g) on a 17.5%
    // guess — a line that counts shows its food.
    expect(
      countsAsZeroGuess(
        status: 'auto',
        fdcId: 167682,
        grams: 9.4666730687946981,
        confidence: 0.17500000000000004,
        gramSource: 'discarded',
      ),
      isFalse,
    );
    // Synthesized (stated exception): no snapshot row reaches these guards
    // below the gate — an unnamed food at 0 g waits for a person (Mechouia's
    // "2 tablespoons juice" sits at 0.89), a zero with no food has nothing
    // to hide, and the engine zeroes only a discarded or unmeasured line.
    const base = (
      status: 'auto',
      fdcId: 2709682,
      grams: 0.0,
      confidence: 0.3,
      gramSource: 'unmeasured',
    );
    expect(
      countsAsZeroGuess(
        status: base.status,
        fdcId: base.fdcId,
        grams: base.grams,
        confidence: base.confidence,
        gramSource: base.gramSource,
      ),
      isTrue,
    );
    expect(
      countsAsZeroGuess(
        status: base.status,
        fdcId: base.fdcId,
        grams: base.grams,
        confidence: base.confidence,
        gramSource: base.gramSource,
        hold: 'unnamed_food',
      ),
      isFalse,
    );
    expect(
      countsAsZeroGuess(
        status: base.status,
        fdcId: null,
        grams: base.grams,
        confidence: base.confidence,
        gramSource: base.gramSource,
      ),
      isFalse,
    );
    expect(
      countsAsZeroGuess(
        status: base.status,
        fdcId: base.fdcId,
        grams: base.grams,
        confidence: base.confidence,
        gramSource: 'weight',
      ),
      isFalse,
    );
    // zeroGuessOf passes the hold through.
    final unnamed = IngredientMatch.fromJson(const {
      'position': 11,
      'raw': '2 tablespoons juice',
      'match': {
        'fdc_id': 2709682,
        'description': 'Beet juice',
        'confidence': 0.3,
        'grams': 0,
        'gram_source': 'unmeasured',
        'status': 'auto',
        'hold': 'unnamed_food',
      },
    });
    expect(zeroGuessOf(unnamed), isFalse);
    // Synthesized (no snapshot holds a decided held row): the pasta water's
    // salt once a person confirmed its eaten part. It keeps its hold
    // (matcher v16), and the line is still held whatever its status —
    // Run 048 H1: an amount edit re-attached a decided held medium, and a
    // status-keyed isHeldLine dropped its "Skip, poured away" card.
    final confirmedSalt = IngredientMatch.fromJson({
      'position': 10,
      'raw': '1 tablespoon plus 1 teaspoon table salt',
      'match': {
        ...(golden('nutrition_matches_rules')['items'] as List)
                .cast<Map<String, dynamic>>()
                .singleWhere((m) => m['position'] == 10)['match']
            as Map<String, dynamic>,
        'status': 'confirmed',
      },
    });
    expect(isHeldLine(rulesLine(10)), isTrue);
    expect(isHeldLine(confirmedSalt), isTrue);
    // Whatever the status (Run 049 A2): a pick on it (an amount edit
    // re-attaches a picked held medium held, matcher v16) and a skip.
    for (final status in ['overridden', 'skipped']) {
      final decided = IngredientMatch.fromJson({
        'position': 10,
        'raw': '1 tablespoon plus 1 teaspoon table salt',
        'match': {
          ...(golden('nutrition_matches_rules')['items'] as List)
                  .cast<Map<String, dynamic>>()
                  .singleWhere((m) => m['position'] == 10)['match']
              as Map<String, dynamic>,
          'status': status,
        },
      });
      expect(decided.status, status);
      expect(isHeldLine(decided), isTrue, reason: status);
    }
  });

  group('Run 046 A5/A7: zero rows', () {
    // Snapshot 12: Tortilla Soup pos 7, below the gate at 0 g with a written
    // sprig amount (its line_amount from the server's lineAmountText over
    // the corpus line: "2 sprig") and a second_food hold.
    const epazote = IngredientMatch(
      position: 7,
      raw:
          '2 sprigs fresh epazote or 8 to 10 sprigs fresh cilantro plus 1 '
          'sprig fresh oregano',
      lineAmount: '2 sprig',
      fdcId: 171328,
      description: 'Spices, oregano, dried',
      dataType: 'SR Legacy',
      confidence: 0.18666666666666665,
      grams: 0,
      gramSource: 'unmeasured',
      status: 'auto',
      hold: 'second_food',
    );

    testWidgets('A7: a written sprig amount reads "not measured", not "no '
        'amount", and the second_food hold still shows', (tester) async {
      await openSheet(tester, [epazote], isAdmin: false);
      expect(
        find.textContaining(
          'Counts as zero (not measured): 2 sprig — not measured, counts as '
          '0 g.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('gives no amount', findRichText: true),
        findsNothing,
      );
      expect(find.text(holdReason('second_food')!), findsOneWidget);
      expect(find.textContaining('oregano, dried'), findsNothing);
    });

    testWidgets('a hold this app does not know reads its code verbatim — no '
        'hold renders blank', (tester) async {
      // 0799's real flour line; the hold code is synthesized (a stated
      // exception): an app older than a server's hold must still say the
      // line is held and by what.
      const flour = IngredientMatch(
        position: 0,
        raw: '4½ cups (24¾ ounces) whole-wheat flour',
        item: 'whole-wheat flour',
        lineAmount: '4½ cups',
        fdcId: 168944,
        description: 'Flour, whole wheat, unenriched',
        dataType: 'SR Legacy',
        confidence: 0.9,
        status: 'auto',
        hold: 'some_later_hold',
      );
      expect(
        holdReason('some_later_hold'),
        'Held by the engine: some later hold',
      );
      expect(holdReason(null), isNull);
      await openSheet(tester, [flour], isAdmin: false);
      expect(
        find.textContaining(
          'Held by the engine: some later hold',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    // v22 (the rulings Q1, Q2, Q4): the three new medium holds read in
    // words, the partial pour-away with the kept part the server sends
    // (`hold_note`); each is a LINE hold (isHeldLine) and the queue's
    // line-hold note names it. Real lines: 0799's flour, 0148's dredge,
    // 0129's soy sauce, as the v22 engine holds them (grams null).
    testWidgets('v22: starter_discard, coating and partial_pour_away read in '
        'words, the kept part included', (tester) async {
      const starter = IngredientMatch(
        position: 0,
        raw: '4½ cups (24¾ ounces) whole-wheat flour',
        item: 'whole-wheat flour',
        lineAmount: '4½ cups',
        fdcId: 790085,
        description: 'Flour, whole wheat, unenriched',
        dataType: 'Foundation',
        confidence: 1,
        status: 'auto',
        hold: 'starter_discard',
      );
      const dredge = IngredientMatch(
        position: 8,
        raw: '4 cups (20 ounces) unbleached all-purpose flour',
        item: 'unbleached all-purpose flour',
        lineAmount: '4 cups',
        fdcId: 789890,
        description: 'Flour, wheat, all-purpose, enriched, bleached',
        dataType: 'Foundation',
        confidence: 0.95,
        status: 'auto',
        hold: 'coating',
      );
      const soy = IngredientMatch(
        position: 1,
        raw: '1 cup soy sauce',
        item: 'soy sauce',
        lineAmount: '1 cup',
        fdcId: 2707442,
        description: 'Soy sauce',
        dataType: 'Survey (FNDDS)',
        confidence: 0.99,
        status: 'auto',
        hold: 'partial_pour_away',
        holdNote: '1 cup defatted cooking liquid',
      );
      // The wire: the server's matches body for 0129's soy line (v22
      // GET, nutrition_v22_rulings_test.dart) parses its kept part.
      final parsed = IngredientMatch.fromJson({
        'position': 1,
        'raw': '1 cup soy sauce',
        'match': {
          'fdc_id': 2707442,
          'description': 'Soy sauce',
          'data_type': 'Survey (FNDDS)',
          'confidence': 0.99,
          'grams': null,
          'gram_source': null,
          'status': 'auto',
          'hold': 'partial_pour_away',
          'hold_note': '1 cup defatted cooking liquid',
        },
      });
      expect(parsed.holdNote, soy.holdNote);
      // A medium hold's eaten "plus" part is its grams whatever the medium
      // (the server's _eatenPlusPart; no held library line has one yet, so
      // the 6 g is synthesized — a stated exception).
      expect(
        hasEatenPlusPart(
          IngredientMatch(
            position: dredge.position,
            raw: dredge.raw,
            fdcId: dredge.fdcId,
            grams: 6,
            gramSource: 'discarded',
            hold: 'coating',
          ),
        ),
        isTrue,
      );
      for (final m in [starter, dredge, soy]) {
        expect(isHeldLine(m), isTrue, reason: m.hold);
        expect(holdReason(m.hold), isNot(startsWith('Held by the engine')));
      }
      expect(
        holdReason('partial_pour_away', note: soy.holdNote),
        'Only part of the strained cooking liquid is kept (1 cup defatted '
        'cooking liquid); the rest is poured away',
      );
      await openSheet(tester, [starter, dredge, soy], isAdmin: false);
      for (final text in [
        'A starter feeding',
        'Dredging for a fried food',
        '(1 cup defatted cooking liquid); the rest is poured away',
      ]) {
        expect(
          find.textContaining(text, findRichText: true),
          findsOneWidget,
          reason: text,
        );
      }
    });

    // Run 054 S5/O6: a pick alone on a held line that is not divided keeps
    // its hold with no grams (the server's PUT: status overridden, grams
    // null, hold kept — nutrition_v23_rules_test G6 on these real lines),
    // which buckets No grams. The reason still shows, with the held ways
    // out — never "no amount found" alone, and never the amount-first
    // confirm, whose prefill would count the whole dredge.
    testWidgets('S5/O6: a picked held line in No grams says why it is held '
        'and leads with the held ways out', (tester) async {
      const dredge = IngredientMatch(
        position: 8,
        raw: '4 cups (20 ounces) unbleached all-purpose flour',
        item: 'unbleached all-purpose flour',
        lineAmount: '4 cups',
        fdcId: 789890,
        description: 'Flour, wheat, all-purpose, enriched, bleached',
        dataType: 'Foundation',
        confidence: 1,
        status: 'overridden',
        hold: 'coating',
      );
      const soy = IngredientMatch(
        position: 1,
        raw: '1 cup soy sauce',
        item: 'soy sauce',
        lineAmount: '1 cup',
        fdcId: 2707442,
        description: 'Soy sauce',
        dataType: 'Survey (FNDDS)',
        confidence: 1,
        status: 'overridden',
        hold: 'partial_pour_away',
        holdNote: '1 cup defatted cooking liquid',
      );
      for (final m in [dredge, soy]) {
        expect(matchBucketOf(m), MatchBucket.noAmount, reason: m.raw);
        expect(confirmsWithAmount(m), isFalse, reason: m.raw);
        // The queue pane still waits on it: a skip or the edible grams.
        expect(
          leftWaitingOnAmount(NutritionState(matches: [m]), m.position),
          isTrue,
          reason: m.raw,
        );
      }
      await openSheet(tester, [dredge, soy]);
      expect(
        find.textContaining(
          'Dredging for a fried food: most of it is shaken off or left in '
          'the dish, and no coating share is set — held out of the totals: '
          'skip it if it is poured away, or enter the grams that are eaten',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          '(1 cup defatted cooking liquid); the rest is poured away — held '
          'out of the totals',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('no amount found'), findsNothing);
      expect(find.text('Enter edible grams'), findsNWidgets(2));
      expect(find.text(heldSkipLabel), findsNWidgets(2));
      expect(find.text('Add amount'), findsNothing);
    });

    // Run 054 H5(a): a pick on a DIVIDED held line counts its eaten part and
    // resolves the hold — the server's row (nutrition_v24_rules_test H5(a),
    // 1133 Francese #5): overridden, the teaspoon's grams, discarded, no
    // hold, hold_note "eaten part counted after your pick". It counts, and
    // the counted row says why.
    testWidgets('H5(a): a pick that resolved a divided hold says its eaten '
        'part is counted after the pick', (tester) async {
      const flour = IngredientMatch(
        position: 5,
        raw: '¾ cup all-purpose flour, divided',
        item: 'all-purpose flour',
        lineAmount: '¾ cup',
        fdcId: 789890,
        description: 'Flour, wheat, all-purpose, enriched, bleached',
        dataType: 'Foundation',
        confidence: 1,
        grams: 2.51,
        gramSource: 'discarded',
        status: 'overridden',
        holdNote: 'eaten part counted after your pick',
      );
      expect(matchBucketOf(flour), MatchBucket.counted);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildMaterialTheme(buildForuiTheme()),
          builder: (context, child) =>
              FTheme(data: buildForuiTheme(), child: child!),
          home: const Scaffold(
            body: WhyLine(match: flour, bucket: MatchBucket.counted),
          ),
        ),
      );
      expect(
        find.textContaining('eaten part counted after your pick'),
        findsOneWidget,
      );
    });

    // Run 053 S16: ZeroRow stands in for WhyLine, so a counted-zero row
    // with a partial pour-away hold reads the kept part as the check row
    // does. The real line, record and score: 0129 Indoor Pulled Chicken's
    // liquid smoke (Pectin, liquid at 0.175, held partial_pour_away; its
    // kept part is keptLiquidOf's for that recipe). The 0 g 'discarded'
    // beside the hold is synthesized — a stated exception: the v22 engine
    // stores the held row without grams; this is the shape the sheet's
    // zero rule admits.
    testWidgets('S16: a zero row with a partial pour-away hold names the '
        'kept part', (tester) async {
      const smoke = IngredientMatch(
        position: 3,
        raw: '1 tablespoon liquid smoke, divided',
        item: 'liquid smoke',
        lineAmount: '1 tablespoon',
        fdcId: 167682,
        description: 'Pectin, liquid',
        confidence: 0.175,
        grams: 0,
        gramSource: 'discarded',
        status: 'auto',
        hold: 'partial_pour_away',
        holdNote: '½ cup reserved defatted liquid',
      );
      expect(zeroGuessOf(smoke), isTrue);
      await openSheet(tester, [smoke], isAdmin: false);
      expect(find.byType(ZeroRow), findsOneWidget);
      expect(
        find.textContaining(
          '(½ cup reserved defatted liquid); the rest is poured away',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    // v23 (Run 053 O9, closer D5): a divided line's part eaten outside the
    // dredge stays HELD with its grams — as a held medium's eaten "plus"
    // part does — and the row says which part, and that it waits on a
    // confirm. The real row: 1133 Chicken Francese's "¾ cup all-purpose
    // flour, divided", as the v23 engine stores it (2.51 g discarded,
    // coating) and the GET's hold_note (holdNoteOf).
    testWidgets('v23: a divided dredge names its eaten part and waits on a '
        'confirm', (tester) async {
      const flour = IngredientMatch(
        position: 5,
        raw: '¾ cup all-purpose flour, divided',
        item: 'all-purpose flour',
        lineAmount: '¾ cup',
        fdcId: 789890,
        description: 'Flour, wheat, all-purpose, enriched, bleached',
        dataType: 'Foundation',
        confidence: 0.95,
        grams: 2.51,
        gramSource: 'discarded',
        status: 'auto',
        hold: 'coating',
        holdNote: '1 teaspoon flour is used outside the dredge, eaten',
      );
      expect(hasEatenPlusPart(flour), isTrue);
      await openSheet(tester, [flour], isAdmin: false);
      expect(
        find.textContaining(
          'no coating share is set (1 teaspoon flour is used outside the '
          'dredge, eaten) — held out of the totals: Confirm counts only the '
          'eaten part',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('A7: the fix panel says what the line writes', (tester) async {
      await pumpPanel(tester, epazote);
      expect(
        find.text('The line says 2 sprig — not measured, counts as 0 g.'),
        findsOneWidget,
      );
      expect(find.text('The line gives no amount.'), findsNothing);
    });

    // The dye row as an admin left it after tapping Skip (the skip route
    // keeps fdc_id and grams, changing only the status).
    final skippedDye = IngredientMatch.fromJson({
      'position': _dye.position,
      'raw': _dye.raw,
      'match': {
        'fdc_id': _dye.fdcId,
        'description': _dye.description,
        'data_type': _dye.dataType,
        'confidence': _dye.confidence,
        'grams': 0,
        'gram_source': 'unmeasured',
        'status': 'skipped',
      },
    });

    testWidgets('A5: a skipped zero keeps its guess hidden from a member, '
        'and is not counted as a zero', (tester) async {
      await openSheet(tester, [skippedDye, _lemon], isAdmin: false);
      await tester.tap(find.text('Skipped'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Counts as zero (no amount)', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('coleslaw'), findsNothing);
      expect(find.text('skipped'), findsOneWidget);
      expect(find.textContaining('of them as zero'), findsNothing);
    });

    // Synthesized (stated exception): no snapshot holds a person's confirm
    // of a below-gate zero row (S4 now refuses one), so the dye row is set
    // to 'confirmed' to pin that a person's decision shows its food.
    testWidgets("a person's confirmed zero row shows its food", (tester) async {
      final confirmed = IngredientMatch.fromJson({
        'position': _dye.position,
        'raw': _dye.raw,
        'match': {
          'fdc_id': _dye.fdcId,
          'description': _dye.description,
          'data_type': _dye.dataType,
          'confidence': _dye.confidence,
          'grams': 0,
          'gram_source': 'unmeasured',
          'status': 'confirmed',
        },
      });
      expect(zeroGuessOf(confirmed), isFalse);
      await openSheet(tester, [confirmed], isAdmin: false);
      expect(
        find.textContaining('Fast foods, coleslaw', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Counts as zero'), findsNothing);
    });
  });

  group('U4: a held medium or shell line (ruling 5)', () {
    testWidgets('a brine sugar leads with "Skip, poured away" and "Enter '
        'edible grams" — no Confirm of the whole 94 g', (tester) async {
      final cubit = await openSheet(tester, [_brineSugar]);
      expect(find.text('Skip, poured away'), findsOneWidget);
      expect(find.text('Enter edible grams'), findsOneWidget);
      expect(find.text('Confirm'), findsNothing);
      expect(find.text('Confirm as-is'), findsNothing);
      expect(
        find.textContaining(
          'skip it if it is poured away, or enter the '
          'grams that are eaten',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Skip, poured away'));
      await tester.pumpAndSettle();
      expect(cubit.writes.single.skipped, isTrue);
    });

    testWidgets('"Enter edible grams" opens the panel on its amount field', (
      tester,
    ) async {
      await openSheet(tester, [_brineSugar]);
      await tester.tap(find.text('Enter edible grams'));
      await tester.pumpAndSettle();
      expect(find.text('Save match & amount'), findsOneWidget);
      final focused = FocusManager.instance.primaryFocus;
      expect(focused, isNotNull);
      final field = tester.widget<EditableText>(find.byType(EditableText).last);
      expect(field.focusNode.hasFocus, isTrue);
    });

    testWidgets("the pasta water's salt (0300) offers Confirm: its grams are "
        'the eaten "plus" part', (tester) async {
      final cubit = await openSheet(tester, [rulesLine(10)]);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Skip, poured away'), findsOneWidget);
      expect(
        find.textContaining('Confirm counts only the eaten part'),
        findsOneWidget,
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(cubit.writes.single.confirmed, isTrue);
    });

    testWidgets('mussels in the shell: never a Confirm; the skip reads as '
        'ruling 5 words it for held media and in-shell rows alike', (
      tester,
    ) async {
      await openSheet(tester, [rulesLine(6)]);
      expect(find.text('Enter edible grams'), findsOneWidget);
      expect(find.text('Skip, poured away'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Confirm'), findsNothing);
      expect(find.text('Confirm as-is'), findsNothing);
      expect(
        find.textContaining(
          'enter the edible grams (the shells are not '
          'eaten)',
        ),
        findsOneWidget,
      );
    });
  });

  test('an eaten "plus" part is a HELD medium\'s alone: never an in-shell '
      'row, never a zeroed medium the engine counts itself', () {
    // The pasta water's salt (0300): held, its "plus 1 teaspoon" eaten.
    expect(hasEatenPlusPart(rulesLine(10)), isTrue);
    // The mussels, held in the shell: no confirm counts a shell weight.
    expect(hasEatenPlusPart(rulesLine(6)), isFalse);
    // Pork Schnitzel (0233) pos 3 on snapshot 11: frying oil under the
    // zero policy, its "plus 1 tablespoon" eaten and counted — no hold, so
    // nothing for a person to confirm.
    const schnitzelOil = IngredientMatch(
      position: 3,
      raw: '2 cups plus 1 tablespoon vegetable oil',
      fdcId: 2710180,
      description: 'Vegetable oil, NFS',
      dataType: 'Survey (FNDDS)',
      confidence: 0.92333333333333334,
      grams: 14,
      gramSource: 'discarded',
      status: 'auto',
    );
    expect(hasEatenPlusPart(schnitzelOil), isFalse);
    // Synthesized (stated exception): no snapshot holds a held medium with
    // nothing eaten (every discarded held row is a "plus" part), so the
    // pasta water's salt at 0 g pins that a held medium with no eaten
    // grams offers no confirm of an eaten part.
    final nothingEaten = IngredientMatch.fromJson({
      'position': 10,
      'raw': '1 tablespoon plus 1 teaspoon table salt',
      'match': {
        'fdc_id': 173468,
        'description': 'Salt, table',
        'confidence': 1.0,
        'grams': 0,
        'gram_source': 'discarded',
        'status': 'auto',
        'hold': 'discarded_medium',
      },
    });
    expect(hasEatenPlusPart(nothingEaten), isFalse);
  });

  group('C: a Check line with no grams confirms without an amount', () {
    // Chana Masala pos 12 (snapshot 11): garam masala on a 1.5% guess, no
    // grams — the confirm fetches the food's detail and converts the line.
    const garam = IngredientMatch(
      position: 12,
      raw: '1½ teaspoons garam masala',
      fdcId: 171181,
      description: 'SMART SOUP, Indian Bean Masala',
      dataType: 'SR Legacy',
      confidence: 0.014999999999999958,
      status: 'auto',
    );

    testWidgets('the sheet offers Confirm, not Confirm as-is', (tester) async {
      final cubit = await openSheet(tester, [garam]);
      expect(find.text('Confirm as-is'), findsNothing);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(cubit.writes, [
        (
          position: 12,
          fdcId: null,
          grams: null,
          confirmed: true,
          skipped: null,
        ),
      ]);
    });
  });

  group('U5: the approximation basis (ruling 6)', () {
    testWidgets('pancetta says it is counted as bacon', (tester) async {
      await openSheet(tester, [rulesLine(11)]);
      expect(
        find.text(
          'amount: from 2 ounce · approximation (counted as Pork, cured, '
          'bacon, unprepared)',
        ),
        findsOneWidget,
      );
    });
  });

  group('U2: the offer promises, the receipt reconciles', () {
    // The almond-extract group of snapshot 11: its apply finishes six
    // recipes besides Almond Biscotti (whose whole almonds still wait).
    const promised = [
      (id: 'atk-tv-2023-0856-angel-food-cake', title: 'Angel Food Cake'),
      (id: 'atk-tv-2023-0870-best-almond-cake', title: 'Best Almond Cake'),
      (
        id: 'atk-tv-2023-0832-easy-holiday-sugar-cookies',
        title: 'Easy Holiday Sugar Cookies',
      ),
    ];

    Future<void> pumpStrip(
      WidgetTester tester, {
      ApplyOffer? offer,
      ApplyReceipt? applied,
      List<({String id, String title})>? promise,
      VoidCallback? onDismiss,
      VoidCallback? onDismissReceipt,
    }) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: buildMaterialTheme(buildForuiTheme()),
          builder: (context, child) =>
              FTheme(data: buildForuiTheme(), child: child!),
          home: Scaffold(
            body: ApplyToAllStrip(
              offer: offer,
              applied: applied,
              applying: false,
              onApply: () {},
              onDismiss: onDismiss ?? () {},
              onDismissReceipt: onDismissReceipt ?? () {},
              promised: promise,
            ),
          ),
        ),
      );
    }

    ApplyReceipt receipt(List<String> completed) => (
      position: 7,
      recipes: 8,
      lines: 8,
      failed: 0,
      completed: completed.length,
      completedRecipes: completed,
      raw: 'the decided line',
      moved: 0,
      decided: 0,
      gone: 0,
      failedLines: 0,
    );

    // Run 054 S8: the receipt's Dismiss is the receipt's own callback — a
    // strip handed a receipt and an offer (the cubit keeps both when a
    // decision lands on another line during an apply) never drops the
    // offer with it; "Not now" on an offer is the offer's.
    testWidgets("S8: the receipt's Dismiss calls only onDismissReceipt", (
      tester,
    ) async {
      var offers = 0;
      var receipts = 0;
      // Almond Biscotti's line, as the offer below states it.
      const offer = (
        position: 7,
        raw: '1½ teaspoons almond extract',
        label: 'almond extract',
        fdcId: null,
        confirmed: true,
        grams: null,
        others: 8,
        lines: 8,
      );
      await pumpStrip(
        tester,
        offer: offer,
        applied: receipt(const []),
        onDismiss: () => offers++,
        onDismissReceipt: () => receipts++,
      );
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect((offers, receipts), (0, 1));
      await pumpStrip(
        tester,
        offer: offer,
        onDismiss: () => offers++,
        onDismissReceipt: () => receipts++,
      );
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect((offers, receipts), (1, 1));
    });

    testWidgets("F7: the receipt says how many lines changed meanwhile and "
        'were left for their next compute — in the queue and the sheet', (
      tester,
    ) async {
      ApplyReceipt movedReceipt(
        int moved, {
        int decided = 0,
        int gone = 0,
        int failedLines = 0,
      }) => (
        position: 7,
        raw: 'the decided line',
        recipes: 8,
        lines: 6,
        failed: failedLines > 0 ? 1 : 0,
        completed: 0,
        completedRecipes: const [],
        moved: moved,
        decided: decided,
        gone: gone,
        failedLines: failedLines,
      );
      for (final promise in [promised, null]) {
        await pumpStrip(tester, applied: movedReceipt(2), promise: promise);
        expect(
          find.textContaining(
            '2 lines changed meanwhile and were left for their next compute.',
            findRichText: true,
          ),
          findsOneWidget,
        );
        await pumpStrip(tester, applied: movedReceipt(1), promise: promise);
        expect(
          find.textContaining(
            '1 line changed meanwhile and was left for its next compute.',
            findRichText: true,
          ),
          findsOneWidget,
        );
        await pumpStrip(tester, applied: movedReceipt(0), promise: promise);
        expect(
          find.textContaining('changed meanwhile', findRichText: true),
          findsNothing,
        );
        // Every other reason the server accounts for is said too, so the
        // receipt covers every offered line (Run 052's F7 class).
        await pumpStrip(
          tester,
          applied: movedReceipt(1, decided: 2, gone: 1, failedLines: 3),
          promise: promise,
        );
        expect(
          find.textContaining(
            '2 lines decided meanwhile; 1 line now another ingredient or '
            'gone; 3 lines failed. 1 line changed meanwhile',
            findRichText: true,
          ),
          findsOneWidget,
        );
        await pumpStrip(
          tester,
          applied: movedReceipt(0, gone: 2),
          promise: promise,
        );
        expect(
          find.textContaining(
            '2 lines now another ingredient or gone.',
            findRichText: true,
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('decided meanwhile', findRichText: true),
          findsNothing,
        );
      }
    });

    testWidgets('the offer says what applying finishes', (tester) async {
      const offer = (
        position: 7,
        raw: '1½ teaspoons almond extract',
        label: 'almond extract',
        fdcId: null,
        confirmed: true,
        grams: null,
        others: 8,
        lines: 8,
      );
      await pumpStrip(tester, offer: offer, promise: promised);
      expect(
        find.textContaining(
          'still waiting on this decision. Applying finishes 3 recipes.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      // Off the queue there is no promise to state.
      await pumpStrip(tester, offer: offer);
      expect(
        find.textContaining('Applying finishes', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('"as promised" when every promised recipe completed; else '
        'the ones this apply did not complete, by name', (tester) async {
      await pumpStrip(
        tester,
        applied: receipt([for (final r in promised) r.id]),
        promise: promised,
      );
      expect(
        find.textContaining(
          '3 recipes are now complete, as promised.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      await pumpStrip(
        tester,
        applied: receipt([promised.first.id]),
        promise: promised,
      );
      expect(
        find.textContaining(
          '1 recipe is now complete, short of the promise — Best Almond '
          'Cake and Easy Holiday Sugar Cookies were not completed by this '
          'apply.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      await pumpStrip(
        tester,
        applied: receipt([]),
        promise: promised.take(1).toList(),
      );
      expect(
        find.textContaining(
          'No recipe is complete yet: short of the promise — Angel Food '
          'Cake was not completed by this apply.',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('A6: reconciled by id — an unpromised completion is a bonus, '
        'and it never hides a promised recipe that did not complete', (
      tester,
    ) async {
      // Stands for S7's case: the decided line's own recipe (Cranberry Pecan
      // Muffins, two open pecan lines in one group) completes through the
      // reach, outside the promise.
      const own = 'atk-tv-2023-0765-cranberry-pecan-muffins';
      await pumpStrip(
        tester,
        applied: receipt([for (final r in promised) r.id, own]),
        promise: promised,
      );
      expect(
        find.textContaining(
          '4 recipes are now complete, one more than promised.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      // As many completions as promised, but one promised recipe is missing:
      // a count comparison would say "as promised".
      await pumpStrip(
        tester,
        applied: receipt([promised[0].id, promised[1].id, own]),
        promise: promised,
      );
      expect(
        find.textContaining(
          '3 recipes are now complete, one more than promised; short of the '
          'promise — Easy Holiday Sugar Cookies was not completed by this '
          'apply.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.textContaining('as promised'), findsNothing);
    });

    testWidgets('off the queue: N recipes, one recipe, or nothing said at 0', (
      tester,
    ) async {
      await pumpStrip(tester, applied: receipt(['a', 'b']));
      expect(
        find.textContaining('2 recipes are now complete.', findRichText: true),
        findsOneWidget,
      );
      await pumpStrip(tester, applied: receipt(['a']));
      expect(
        find.textContaining('1 recipe is now complete.', findRichText: true),
        findsOneWidget,
      );
      await pumpStrip(tester, applied: receipt([]));
      expect(
        find.textContaining('now complete', findRichText: true),
        findsNothing,
      );
    });
  });

  group('C: the amount-first block', () {
    // Chana Masala pos 12 (snapshot 11), still open beside the ginger.
    const garam = IngredientMatch(
      position: 12,
      raw: '1½ teaspoons garam masala',
      fdcId: 171181,
      description: 'SMART SOUP, Indian Bean Masala',
      dataType: 'SR Legacy',
      confidence: 0.014999999999999958,
      status: 'auto',
    );

    testWidgets('the matched-to line says the calories per 100 g where '
        'there is no amount yet', (tester) async {
      await openSheet(tester, [_ginger]);
      expect(find.text('· 80 kcal per 100 g'), findsOneWidget);
      expect(find.text('· no amount'), findsNothing);
    });

    testWidgets('Chana Masala still waits on its garam masala', (tester) async {
      await pumpPanel(
        tester,
        _ginger,
        recipe: [_ginger, garam],
        recipeTitle: 'Chana Masala',
      );
      expect(
        find.textContaining(
          'Chana Masala still waits on 1 more line after this: 1½ '
          'teaspoons garam masala.',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets("the butter is its recipe's only open line: the confirm "
        'finishes it', (tester) async {
      await pumpPanel(
        tester,
        butterNoGrams(),
        recipeTitle: 'Classic Yellow Layer Cake with Vanilla Buttercream',
      );
      expect(
        find.textContaining(
          "This is the recipe's only open line, so this confirm finishes "
          'Classic Yellow Layer Cake with Vanilla Buttercream.',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('Skip sits beside Confirm when the host asks', (tester) async {
      var skipped = 0;
      await pumpPanel(tester, _ginger, onSkip: () => skipped += 1);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(skipped, 1);
      await pumpPanel(tester, _ginger);
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('two portions naming the unit: nothing is prefilled, both '
        'fill on a tap', (tester) async {
      await pumpPanel(tester, _brownSugar());
      expect(find.text('Confirm with amount'), findsOneWidget);
      expect(enabled(tester, 'Confirm with amount'), isFalse);
      await tester.tap(find.text('1 × cup unpacked 145 g = 145 g'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm · 145 g'), findsOneWidget);
    });

    testWidgets('a plain Confirm that leaves the line in No grams hands the '
        'field the focus', (tester) async {
      final match = ValueNotifier<IngredientMatch>(garam);
      addTearDown(match.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final cubit = _Recording(_state([garam]));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: buildMaterialTheme(buildForuiTheme()),
          builder: (context, child) =>
              FTheme(data: buildForuiTheme(), child: child!),
          home: RepositoryProvider<NutritionRepository>.value(
            value: NutritionRepository(Dio()),
            child: BlocProvider<NutritionCubit>.value(
              value: cubit,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: ValueListenableBuilder<IngredientMatch>(
                    valueListenable: match,
                    builder: (context, m, _) => FixPanel(
                      match: m,
                      busy: false,
                      onDone: () {},
                      showCancel: false,
                      amountFocus: focus,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      // The server confirmed it and could not convert: No grams on a food.
      match.value = const IngredientMatch(
        position: 12,
        raw: '1½ teaspoons garam masala',
        fdcId: 171181,
        description: 'SMART SOUP, Indian Bean Masala',
        dataType: 'SR Legacy',
        confidence: 1,
        status: 'confirmed',
      );
      await tester.pumpAndSettle();
      expect(find.text('How much is it?'), findsOneWidget);
      expect(focus.hasFocus, isTrue);
    });

    group('R5: portions arriving on the same food and grams', () {
      // Stated exception (synthesized): the butter row (the rules golden's
      // real portions) first seen with its detail uncached — portions [],
      // as the matches body sends before a confirm caches the record.
      Future<ValueNotifier<IngredientMatch>> pumpLive(
        WidgetTester tester, [
        IngredientMatch? initial,
        _Recording? cubit,
      ]) async {
        final match = ValueNotifier<IngredientMatch>(
          initial ?? butterNoGrams(uncached: true),
        );
        addTearDown(match.dispose);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          MaterialApp(
            theme: buildMaterialTheme(buildForuiTheme()),
            builder: (context, child) =>
                FTheme(data: buildForuiTheme(), child: child!),
            home: RepositoryProvider<NutritionRepository>.value(
              value: NutritionRepository(Dio()),
              child: BlocProvider<NutritionCubit>.value(
                value: cubit ?? _Recording(_state([butterNoGrams()])),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: ValueListenableBuilder<IngredientMatch>(
                      valueListenable: match,
                      builder: (context, m, _) => FixPanel(
                        match: m,
                        busy: false,
                        onDone: () {},
                        showCancel: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return match;
      }

      testWidgets('the one fitting portion prefills without a remount', (
        tester,
      ) async {
        final match = await pumpLive(tester);
        expect(
          find.text('USDA portions load after the first confirm.'),
          findsOneWidget,
        );
        expect(find.text('Confirm with amount'), findsOneWidget);
        match.value = butterNoGrams();
        await tester.pumpAndSettle();
        expect(find.text('Confirm · 452 g'), findsOneWidget);
      });

      testWidgets('a typed amount stays', (tester) async {
        final match = await pumpLive(tester);
        await tester.enterText(find.byType(EditableText).first, '100');
        await tester.pumpAndSettle();
        match.value = butterNoGrams();
        await tester.pumpAndSettle();
        expect(find.text('4 × stick 113 g = 452 g'), findsOneWidget);
        expect(find.text('Confirm · 100 g'), findsOneWidget);
      });

      testWidgets('a tapped fill survives a rebuild that keeps the '
          'portions', (tester) async {
        final match = await pumpLive(tester, _brownSugar());
        await tester.tap(find.text('1 × cup unpacked 145 g = 145 g'));
        await tester.pumpAndSettle();
        match.value = _brownSugar();
        await tester.pumpAndSettle();
        expect(find.text('Confirm · 145 g'), findsOneWidget);
      });

      testWidgets('Run 049 A2: portions arriving after a person re-picks '
          "the STORED food prefill its fill, as with nothing staged", (
        tester,
      ) async {
        // Stated exception (synthesized), as the Run 048 A1 repro: the
        // person stages peanut butter, then the stored butter again.
        final cubit = _Recording(_state([butterNoGrams()]));
        final match = await pumpLive(
          tester,
          butterNoGrams(uncached: true, confidence: 0.3),
          cubit,
        );
        await tester.tap(
          find.text('Peanut butter, smooth style, without salt'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Butter, without salt'));
        await tester.pumpAndSettle();
        match.value = butterNoGrams();
        await tester.pumpAndSettle();
        expect(find.text('Confirm · 452 g'), findsOneWidget);
      });

      testWidgets('Run 051 A3: a reload that puts ANOTHER line under the '
          'panel drops what was typed and staged for the old one', (
        tester,
      ) async {
        // Stated exception (synthesized, the S14 repro): after a 409 reload
        // the row at position 12 is another real line of the golden (the
        // pancetta's text) on the same food and grams, so only its text
        // tells the panel it now stands on a different line.
        final other = butterNoGrams(confidence: 0.3, raw: rulesLine(11).raw);
        final cubit = _Recording(_state([other]));
        final match = await pumpLive(
          tester,
          butterNoGrams(confidence: 0.3),
          cubit,
        );
        await tester.tap(
          find.text('Peanut butter, smooth style, without salt'),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(EditableText).last, '100');
        await tester.pumpAndSettle();
        expect(find.text('100'), findsOneWidget);
        match.value = other;
        await tester.pumpAndSettle();
        // Nothing of the butter line's is left to save onto the pancetta
        // text: the typed 100 is gone and the staged peanut butter (172470)
        // with it, so Save has nothing to send.
        expect(find.text('100'), findsNothing);
        await tester.tap(find.text('Save match & amount'));
        await tester.pumpAndSettle();
        expect(cubit.writes, isEmpty);
      });

      testWidgets('S15: another line under the panel resets the unit to g '
          'and the typed flag, not only the staged pick and the text', (
        tester,
      ) async {
        // The rules golden's real ham (4) and chicken pieces (3) rows; the
        // ham panel then standing on the chicken line is the A3 reload.
        final ham = rulesLine(4);
        final chicken = rulesLine(3);
        final cubit = _Recording(_state([chicken]));
        final match = await pumpLive(tester, ham, cubit);
        await tester.tap(find.text('oz'));
        await tester.pumpAndSettle();
        expect(find.text('128'), findsOneWidget);
        await tester.enterText(find.byType(EditableText).last, '100');
        await tester.pumpAndSettle();
        match.value = chicken;
        await tester.pumpAndSettle();
        // The unit: the chicken's 1,587.572 g in grams, never in ounces (56).
        expect(find.text('1588'), findsOneWidget);
        // The typed flag: a pick on the chicken line now lets the server
        // weigh it — the reset field is no hand-typed amount to send.
        await tester.tap(
          find.text('Chicken, broilers or fryers, thigh, meat and skin, raw'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Save match'));
        await tester.pumpAndSettle();
        expect(cubit.writes.single.fdcId, 172385);
        expect(cubit.writes.single.grams, isNull);
      });

      testWidgets('Run 048 A1: portions arriving while ANOTHER food is '
          "staged never prefill the stored record's fill onto the pick", (
        tester,
      ) async {
        // Stated exception (synthesized, the Opus repro): the butter row
        // below the gate (confidence 0.3, a Check line with no grams) and
        // its detail uncached; the person stages peanut butter, a plain
        // Confirm of the stored butter lands in No grams on the same food,
        // and the butter's portions arrive.
        final cubit = _Recording(_state([butterNoGrams()]));
        final match = await pumpLive(
          tester,
          butterNoGrams(uncached: true, confidence: 0.3),
          cubit,
        );
        await tester.tap(
          find.text('Peanut butter, smooth style, without salt'),
        );
        await tester.pumpAndSettle();
        match.value = butterNoGrams();
        await tester.pumpAndSettle();
        expect(find.text('Confirm · 452 g'), findsNothing);
        expect(find.text('Confirm with amount'), findsOneWidget);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(cubit.writes, isEmpty);
      });
    });
  });
}
