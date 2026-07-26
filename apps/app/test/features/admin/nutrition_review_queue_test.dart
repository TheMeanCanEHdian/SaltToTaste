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
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    Object? body;
    if (path.contains('/admin/nutrition_review')) {
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
  Future<void> pumpQueue(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _Adapter();
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
}
