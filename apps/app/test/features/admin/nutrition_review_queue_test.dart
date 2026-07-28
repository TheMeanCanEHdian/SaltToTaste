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
  _Adapter({this.failOverride = false});

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
      body = {
        'total': 2,
        'buckets': [
          {'id': 'no_match', 'label': 'No match', 'count': 1},
          {'id': 'no_grams', 'label': 'No grams', 'count': 0},
          {'id': 'check', 'label': 'Low confidence', 'count': 1},
          {'id': 'skipped', 'label': 'Skipped', 'count': 0},
        ],
        'items': [
          {
            'recipe': {'id': 'tatin', 'slug': 'tatin', 'title': 'Tarte Tatin'},
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
            'recipe': {'id': 'soup', 'slug': 'soup', 'title': 'Chicken Soup'},
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
  }) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = _Adapter(failOverride: failOverride);
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
}
