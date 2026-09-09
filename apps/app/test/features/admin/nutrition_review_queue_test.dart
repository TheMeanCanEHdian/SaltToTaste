import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/admin/nutrition_review_cubit.dart';
import 'package:salt_app/features/admin/nutrition_review_queue.dart';

/// Serves both endpoints the queue needs: the cross-recipe review list, and one
/// recipe's per-line matches (fetched when a row is selected, so the fix panel
/// gets candidates).
class _Adapter implements HttpClientAdapter {
  _Adapter({this.failOverride = false, this.reviewBody});

  /// A prepared review body, for the row/header cases — the default below is
  /// the two-line queue the fix-flow tests work against.
  final Map<String, dynamic>? reviewBody;

  /// When true, every override PUT fails with a 422 envelope — the network
  /// blip / budget-drained case the queue once silently advanced past
  /// (review B5).
  final bool failOverride;

  /// How many times the cross-recipe review list was (re)fetched —
  /// completeFix() reloads it, so this count observes queue advancement.
  int reviewFetches = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (failOverride &&
        options.method == 'PUT' &&
        path.contains('/nutrition/matches/')) {
      return ResponseBody.fromString(
        jsonEncode({
          'error': {
            'code': 'validation',
            'message':
                'The FoodData Central request budget for this hour '
                'is used up.',
          },
        }),
        422,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    Object? body;
    if (path.contains('/admin/nutrition_review')) {
      reviewFetches += 1;
      body =
          reviewBody ??
          {
            'total': 2,
            'groups': 2,
            'buckets': [
              {'id': 'no_match', 'label': 'No match', 'count': 1, 'groups': 1},
              {'id': 'no_grams', 'label': 'No grams', 'count': 0, 'groups': 0},
              {
                'id': 'check',
                'label': 'Low confidence',
                'count': 1,
                'groups': 1,
              },
              {'id': 'skipped', 'label': 'Skipped', 'count': 0, 'groups': 0},
            ],
            'items': [
              {
                'recipe': {
                  'id': 'tatin',
                  'slug': 'tatin',
                  'title': 'Tarte Tatin',
                },
                'position': 5,
                'raw': '2 tablespoons Grand Marnier',
                'bucket': 'check',
                'match': {
                  'fdc_id': 100,
                  'description': 'Candies, NESTLE, 100 GRAND Bar',
                  'data_type': 'SR Legacy',
                  'confidence': 0.41,
                  'grams': 28,
                  'gram_source': 'density',
                  'status': 'auto',
                },
              },
              {
                'recipe': {
                  'id': 'soup',
                  'slug': 'soup',
                  'title': 'Chicken Soup',
                },
                'position': 7,
                'raw': '2 bay leaves',
                'bucket': 'no_match',
                'match': null,
              },
            ],
            'page': 1,
            'limit': 50,
          };
    } else if (path.contains('/nutrition/matches')) {
      // The selected recipe's full match list (with a real alternative so the
      // fix panel can offer a re-pick).
      body = {
        'items': [
          {
            'position': 5,
            'raw': '2 tablespoons Grand Marnier',
            'match': {
              'fdc_id': 100,
              'description': 'Candies, NESTLE, 100 GRAND Bar',
              'data_type': 'SR Legacy',
              'confidence': 0.41,
              'grams': 28,
              'gram_source': 'density',
              'status': 'auto',
            },
            'candidates': [
              {
                'fdc_id': 200,
                'description': 'Alcoholic beverage, liqueur, coffee',
                'data_type': 'SR Legacy',
                'confidence': 0.58,
              },
            ],
          },
        ],
      };
    } else {
      body = {'status': 'none'};
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  Future<_Adapter> pumpQueue(
    WidgetTester tester, {
    bool failOverride = false,
    Map<String, dynamic>? reviewBody,
  }) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = _Adapter(
      failOverride: failOverride,
      reviewBody: reviewBody,
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final recipeRepo = RecipeRepository(dio: dio);
    final nutritionRepo = NutritionRepository(dio);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: recipeRepo),
          RepositoryProvider.value(value: nutritionRepo),
        ],
        child: MaterialApp(
          theme: buildMaterialTheme(buildForuiTheme()),
          builder: (context, child) =>
              FTheme(data: buildForuiTheme(), child: child!),
          home: BlocProvider(
            create: (_) => NutritionReviewCubit(recipeRepo)..load(),
            child: const Scaffold(body: NutritionReviewQueue()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return adapter;
  }

  /// A group item, as the server emits it in `group=item`: today's line item
  /// flattened (the example line at top level) plus the group fields. Every
  /// recipe, line, food and count here comes from the approved mockup.
  Map<String, dynamic> groupItem({
    required String slug,
    required String title,
    required int position,
    required String raw,
    required String bucket,
    required String itemKey,
    String? item,
    required int lines,
    required int recipes,
    bool decided = false,
    double? gramsMin,
    double? gramsMax,
    int gramsMissing = 0,
    String? food,
    double confidence = 0.495,
  }) => {
    'recipe': {'id': slug, 'slug': slug, 'title': title},
    'position': position,
    'raw': raw,
    'bucket': bucket,
    'match': food == null
        ? null
        : {
            'fdc_id': 1,
            'description': food,
            'data_type': 'SR Legacy',
            'confidence': confidence,
            'grams': gramsMin,
            'gram_source': 'piece',
            'status': 'auto',
          },
    'item_key': itemKey,
    'item': item,
    'lines': lines,
    'recipes': recipes,
    'decided': decided,
    'grams': {'min': gramsMin, 'max': gramsMax, 'missing': gramsMissing},
  };

  testWidgets('renders the worst-first queue and selects the first line', (
    tester,
  ) async {
    await pumpQueue(tester);
    // Both flagged rows are present, across two recipes.
    expect(find.text('2 tablespoons Grand Marnier'), findsWidgets);
    expect(find.text('2 bay leaves'), findsOneWidget);
    // Bucket pills from the row buckets.
    expect(find.text('check match'), findsOneWidget);
    expect(find.text('no match'), findsOneWidget);
    // Filter chips carry the whole-library counts.
    expect(find.text('Need attention'), findsOneWidget);
  });

  testWidgets('selecting a line loads its recipe matches into the fix panel', (
    tester,
  ) async {
    await pumpQueue(tester);
    // The first (worst) line is auto-selected, so its fix panel is already up.
    expect(find.text('Change the match & set the amount'), findsOneWidget);
    // The current match and the real alternative both appear in the panel.
    expect(find.text('Candies, NESTLE, 100 GRAND Bar'), findsWidgets);
    expect(find.text('Alcoholic beverage, liqueur, coffee'), findsOneWidget);
    // A "check" line offers Confirm-as-is alongside Skip.
    expect(find.text('Confirm as-is'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    // The persistent detail pane hides the fix panel's Cancel button.
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('a failed override shows its error and does NOT advance the '
      'queue (review B5)', (tester) async {
    final adapter = await pumpQueue(tester, failOverride: true);
    final fetchesBefore = adapter.reviewFetches;

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // The real, actionable message is on screen — not silence.
    expect(
      find.textContaining('FoodData Central request budget'),
      findsOneWidget,
    );
    // The selection stayed on the line that was never fixed, and the queue
    // was not reloaded (completeFix() must not fire on failure).
    expect(find.text('2 tablespoons Grand Marnier'), findsWidgets);
    expect(adapter.reviewFetches, fetchesBefore);
  });

  testWidgets('a successful override completes the fix and reloads the queue', (
    tester,
  ) async {
    final adapter = await pumpQueue(tester);
    final fetchesBefore = adapter.reviewFetches;

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(adapter.reviewFetches, fetchesBefore + 1);
  });

  /// The Low-confidence bucket, grouped: the jalapeño group the mockup's
  /// walkthrough clears, plus one single-line group above it.
  Map<String, dynamic> groupedBody() => {
    'total': 6,
    'groups': 2,
    'buckets': [
      {'id': 'no_match', 'label': 'No match', 'count': 0, 'groups': 0},
      {'id': 'no_grams', 'label': 'No grams', 'count': 0, 'groups': 0},
      {'id': 'check', 'label': 'Low confidence', 'count': 6, 'groups': 2},
      {'id': 'skipped', 'label': 'Skipped', 'count': 0, 'groups': 0},
    ],
    'items': [
      groupItem(
        slug: 'crispy-salt-and-pepper-shrimp',
        title: 'Crispy Salt and Pepper Shrimp',
        position: 4,
        raw: '2 teaspoons Sichuan peppercorns',
        bucket: 'check',
        itemKey: 'sichuan peppercorn',
        item: 'Sichuan peppercorns',
        lines: 1,
        recipes: 1,
        confidence: 0.03,
        food: 'Salad dressing, peppercorn dressing, commercial, regular',
      ),
      groupItem(
        slug: 'cheesy-nachos',
        title: 'Cheesy Nachos with Guacamole and Salsa',
        position: 2,
        raw: '2 large jalapeño chiles, sliced thin (about ¼ cup)',
        bucket: 'check',
        itemKey: 'jalapeno chile',
        item: 'jalapeño chiles',
        lines: 5,
        recipes: 5,
        gramsMin: 14,
        gramsMax: 63,
        food: 'Peppers, jalapeno, seeded, raw',
      ),
    ],
    'page': 1,
    'limit': 50,
  };

  testWidgets('a multi-line group names the ingredient, its reach and its '
      'amounts; a group of one is today\'s row', (tester) async {
    await pumpQueue(tester, reviewBody: groupedBody());

    // The group row: label, reach pill, "e.g." on the example, amount slot.
    expect(find.text('jalapeño chiles'), findsOneWidget);
    expect(find.text('5 lines · 5 recipes'), findsOneWidget);
    expect(
      find.text('e.g. 2 large jalapeño chiles, sliced thin (about ¼ cup)'),
      findsOneWidget,
    );
    expect(find.text('amounts 14–63 g, one per line'), findsOneWidget);
    expect(find.text('Peppers, jalapeno, seeded, raw'), findsWidgets);
    expect(find.text('decided'), findsNothing);

    // The single-line group is byte-for-byte the line row: recipe · line N,
    // the raw text unprefixed, and no reach pill or amount slot.
    expect(find.text('Crispy Salt and Pepper Shrimp · line 4'), findsOneWidget);
    expect(find.text('2 teaspoons Sichuan peppercorns'), findsWidgets);
    expect(find.text('1 lines · 1 recipes'), findsNothing);
    expect(find.textContaining('e.g. 2 teaspoons'), findsNothing);
  });

  testWidgets('the header counts both units and the segment switches them', (
    tester,
  ) async {
    final adapter = await pumpQueue(tester, reviewBody: groupedBody());
    expect(
      find.text('Showing all flagged · 2 ingredients, 6 lines · worst first'),
      findsOneWidget,
    );
    expect(find.text('Ingredients'), findsOneWidget);
    expect(find.text('Lines'), findsOneWidget);

    final before = adapter.reviewFetches;
    await tester.tap(find.text('Lines'));
    await tester.pumpAndSettle();
    // Switching the unit refetches page 1 — the unit of paging changed.
    expect(adapter.reviewFetches, before + 1);
    // Today's sentence, verbatim, in the lines view.
    expect(
      find.text('Showing all flagged · 6 lines, worst first'),
      findsOneWidget,
    );
  });

  testWidgets('a decided group says so, and a weak group with no amounts '
      'warns that Confirm as-is is unavailable', (tester) async {
    // herbes de Provence: two lines, neither with an amount, on a food that
    // is plainly wrong — the pane the admin is heading for has no Confirm.
    await pumpQueue(
      tester,
      reviewBody: {
        ...groupedBody(),
        'items': [
          groupItem(
            slug: 'chicken-bouillabaisse',
            title: 'Chicken Bouillabaisse',
            position: 16,
            raw: '1 teaspoon herbes de Provence (optional)',
            bucket: 'check',
            itemKey: 'herbe de provence',
            item: 'herbes de Provence (optional)',
            lines: 2,
            recipes: 2,
            decided: true,
            gramsMissing: 2,
            confidence: 0.03,
            food: 'Dulce de Leche',
          ),
        ],
      },
    );
    // itemLabel() drops the parenthetical: the label is the ingredient.
    expect(find.text('herbes de Provence'), findsOneWidget);
    expect(find.text('2 lines · 2 recipes'), findsOneWidget);
    expect(find.text('decided'), findsOneWidget);
    expect(
      find.text('no amount on either line — Confirm as-is is unavailable'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Skipped hides the segment and keeps the line-shaped empty text',
    (tester) async {
      await pumpQueue(
        tester,
        reviewBody: {
          ...groupedBody(),
          'buckets': [
            {'id': 'no_match', 'label': 'No match', 'count': 0, 'groups': 0},
            {'id': 'no_grams', 'label': 'No grams', 'count': 0, 'groups': 0},
            {'id': 'check', 'label': 'Low confidence', 'count': 6, 'groups': 2},
            {'id': 'skipped', 'label': 'Skipped', 'count': 3, 'groups': 3},
          ],
          'items': <Map<String, dynamic>>[],
        },
      );
      // A skip is per line and never travels, so there is no ingredient view.
      await tester.tap(find.text('Skipped'));
      await tester.pumpAndSettle();
      expect(find.text('Ingredients'), findsNothing);
      expect(find.text('Lines'), findsNothing);
      expect(find.text('No lines in this bucket.'), findsOneWidget);
      expect(find.text('No ingredients in this bucket.'), findsNothing);
    },
  );

  testWidgets('an empty grouped bucket says ingredients, not lines', (
    tester,
  ) async {
    await pumpQueue(
      tester,
      reviewBody: {...groupedBody(), 'items': <Map<String, dynamic>>[]},
    );
    expect(find.text('No ingredients in this bucket.'), findsOneWidget);
  });

  /// The remaining amount-slot variants, straight off the aggregate — the
  /// widget cases above cover the two that carry a warning and a range.
  NutritionReviewLine amountGroup({
    required int lines,
    required int missing,
    double? min,
    double? max,
    String bucket = 'no_grams',
    double? exampleGrams,
  }) => NutritionReviewLine(
    recipe: const NutritionReviewRecipe(id: 'x', slug: 'x', title: 'X'),
    position: 0,
    raw: 'x',
    bucket: bucket,
    // Confirm as-is is gated on the EXAMPLE line's own amount, so the row
    // carries the example's match, not the aggregate.
    match: exampleGrams == null
        ? null
        : NutritionReviewMatch(
            fdcId: 173430,
            description: 'Butter, without salt',
            dataType: 'SR Legacy',
            confidence: 0.4,
            status: 'auto',
            grams: exampleGrams,
          ),
    lines: lines,
    recipes: lines,
    gramsMin: min,
    gramsMax: max,
    gramsMissing: missing,
  );

  test('the amount aggregate reads in the group\'s own units', () {
    // makrut lime leaf: both members are 264 g.
    expect(
      groupAmountLine(
        amountGroup(lines: 2, missing: 0, min: 264, max: 264),
      )?.text,
      '264 g on both lines',
    );
    expect(
      groupAmountLine(
        amountGroup(lines: 7, missing: 0, min: 2.5, max: 2.5),
      )?.text,
      '2.5 g on all 7 lines',
    );
    // thyme: no amount anywhere, and no Confirm to lose (it is not a check).
    final none = groupAmountLine(amountGroup(lines: 4, missing: 4))!;
    expect(none.text, 'no amount on any of the 4 lines');
    expect(none.warn, isFalse);
    // Some have one, some don't.
    expect(
      groupAmountLine(
        amountGroup(lines: 7, missing: 2, min: 14, max: 63),
      )?.text,
      'amounts 14–63 g · 2 of 7 lines have no amount',
    );
    // A group of one has nothing to aggregate.
    expect(groupAmountLine(amountGroup(lines: 1, missing: 1)), isNull);
  });

  test('the Confirm warning follows the EXAMPLE line, not the aggregate', () {
    // The unsalted-butter group: the tarte's amount-less line is the example
    // (it is the lower-confidence member), the Bundt cake's carries its
    // 170 g. The pane opens on the example, so Confirm as-is is gone even
    // though the group has amounts — the aggregate alone never knew that.
    final example = amountGroup(
      lines: 2,
      missing: 1,
      min: 170.16649439999998,
      max: 170.16649439999998,
      bucket: 'check',
    );
    final warned = groupAmountLine(example)!;
    expect(
      warned.text,
      'amounts 170–170 g · 1 of 2 lines have no amount — '
      'Confirm as-is is unavailable',
    );
    expect(warned.warn, isTrue);

    // The same group with the 170 g line as its example: the button is
    // there, so there is nothing to warn about.
    final fine = groupAmountLine(
      amountGroup(
        lines: 2,
        missing: 1,
        min: 170.16649439999998,
        max: 170.16649439999998,
        bucket: 'check',
        exampleGrams: 170.16649439999998,
      ),
    )!;
    expect(fine.text, 'amounts 170–170 g · 1 of 2 lines have no amount');
    expect(fine.warn, isFalse);

    // Outside `check` an amount-less example has no Confirm to lose.
    final counted = groupAmountLine(
      amountGroup(lines: 2, missing: 1, min: 170.2, max: 170.2),
    )!;
    expect(counted.warn, isFalse);
  });
}
