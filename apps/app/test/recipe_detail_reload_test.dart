import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/core/api/auth_repository.dart';
import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/api/tags_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';
import 'package:salt_app/features/recipes/detail/recipe_detail_page.dart';
import 'package:salt_app/features/tags/tag_styles_cubit.dart';
import 'package:salt_app/router/app_router.dart' show fadePageForTest;

import 'support/contract_goldens.dart';
import 'support/corpus.dart';

/// After a save, the editor returns with `go('/r/<slug>')`. A detail page
/// reached by deep link or refresh is keyed by its route PATTERN, so that
/// go() keeps the very same page element (a card-opened page is push()ed
/// under a random key and gets rebuilt from scratch instead). The kept page
/// once went on showing the pre-edit recipe — on screen and in the tab —
/// until a browser refresh. Found by the F6 review's go_router lens.
///
/// Real RecipeDetailPage, real router pages, real RecipeRepository over the
/// COMMITTED contract golden (a real server response); the second load
/// returns the same recipe renamed, which is what the server serves after
/// a title edit (the slug is stable across renames).
class _Repo extends RecipeRepository {
  _Repo() : super(dio: goldenDio(golden('recipe_detail')));

  int loads = 0;

  @override
  Future<RecipeDetail> getRecipe(String idOrSlug) async {
    final detail = await super.getRecipe(idOrSlug);
    loads++;
    return RecipeDetail(
      recipe: loads == 1
          ? detail.recipe
          : detail.recipe.copyWith(title: 'RENAMED ${detail.recipe.title}'),
      sourceSlug: detail.sourceSlug,
      favorite: detail.favorite,
      note: detail.note,
      baseHash: detail.baseHash,
    );
  }
}

class _OfflineNutrition extends NutritionRepository {
  _OfflineNutrition() : super(Dio());

  @override
  Future<RecipeNutrition> nutrition(String idOrSlug) async =>
      throw const RepositoryException('offline');
}

/// Irish Soda Bread (corpus 0786, "MAKES 1 LOAF") over the golden's source.
class _SodaBread extends RecipeRepository {
  _SodaBread() : super(dio: goldenDio(golden('recipe_detail')));

  @override
  Future<RecipeDetail> getRecipe(String idOrSlug) async {
    final detail = await super.getRecipe(idOrSlug);
    return RecipeDetail(
      recipe: loadCorpusRecipe('0786-irish-soda-bread.yaml'),
      sourceSlug: detail.sourceSlug,
    );
  }
}

/// Its label as snapshot 12 stores it (basis 1, complete 8/8) and the
/// server reads it: per_batch, a MAKES yield of one loaf.
class _SodaBreadLabel extends NutritionRepository {
  _SodaBreadLabel() : super(Dio());

  @override
  Future<RecipeNutrition> nutrition(String idOrSlug) async =>
      RecipeNutrition.fromJson(const {
        'status': 'complete',
        'serving_basis': 1,
        'basis_kind': 'per_batch',
        'calories_per_serving': 2469.89,
        'total_grams': 1042.5,
        'matched_count': 8,
        'total_count': 8,
        'low_confidence': 0,
        // The core rows of its stored nutrients (a label with only
        // energy has no fold, whose lazy controller then trips dispose).
        'per_serving': {
          'energy': {
            'label': 'Calories',
            'amount': 2469.89,
            'unit': 'kcal',
            'dv_percent': 123.5,
          },
          'fat': {
            'label': 'Total Fat',
            'amount': 34.96,
            'unit': 'g',
            'dv_percent': 44.8,
          },
          'sodium': {
            'label': 'Sodium',
            'amount': 5788.04,
            'unit': 'mg',
            'dv_percent': 251.7,
          },
          'carbs': {
            'label': 'Total Carbohydrate',
            'amount': 467.38,
            'unit': 'g',
            'dv_percent': 170.0,
          },
          'protein': {
            'label': 'Protein',
            'amount': 70.67,
            'unit': 'g',
            'dv_percent': 141.3,
          },
        },
      });
}

class _SignedIn extends AuthCubit {
  _SignedIn() : super(AuthRepository(Dio())) {
    emit(
      const AuthSignedIn(
        AuthUserInfo(
          id: 1,
          username: 'admin',
          role: 'admin',
          mustChangePassword: false,
        ),
      ),
    );
  }
}

void main() {
  late List<String> labels;

  setUp(() {
    labels = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setApplicationSwitcherDescription') {
            labels.add((call.arguments as Map)['label'] as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  final slug = golden('recipe_detail')['recipe']['slug'] as String;
  final realTitle = golden('recipe_detail')['recipe']['title'] as String;

  Future<(GoRouter, _Repo)> pumpApp(
    WidgetTester tester, {
    required bool deepLink,
    RecipeRepository? recipes,
    NutritionRepository? nutrition,
    Size size = const Size(1200, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _Repo();
    final router = GoRouter(
      initialLocation: deepLink ? '/r/$slug' : '/',
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) =>
              fadePageForTest(state, const Text('HOME')),
        ),
        GoRoute(
          path: '/r/:slug',
          pageBuilder: (context, state) => fadePageForTest(
            state,
            RecipeDetailPage(slug: state.pathParameters['slug']!),
          ),
        ),
        GoRoute(
          path: '/r/:slug/edit',
          pageBuilder: (context, state) =>
              fadePageForTest(state, const Text('EDIT'), title: 'Edit recipe'),
        ),
      ],
    );
    addTearDown(router.dispose);
    final forui = buildForuiTheme();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<RecipeRepository>.value(value: recipes ?? repo),
          RepositoryProvider<NutritionRepository>.value(
            value: nutrition ?? _OfflineNutrition(),
          ),
          RepositoryProvider<TagsRepository>.value(
            value: TagsRepository(Dio()),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>(create: (_) => _SignedIn()),
            BlocProvider<TagStylesCubit>(
              create: (_) => TagStylesCubit(TagsRepository(Dio())),
            ),
          ],
          child: MaterialApp.router(
            title: 'Salt to Taste',
            theme: buildMaterialTheme(forui),
            routerConfig: router,
            builder: (context, child) => FTheme(
              data: forui,
              child: FToaster(child: child!),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (router, repo);
  }

  for (final deepLink in [true, false]) {
    testWidgets(
      'edit, save, go(same recipe) shows the saved recipe '
      '(${deepLink ? 'deep-linked, kept page' : 'card-opened, fresh page'})',
      (tester) async {
        final (router, repo) = await pumpApp(tester, deepLink: deepLink);
        if (!deepLink) {
          router.push('/r/$slug'); // how a recipe card opens it
          await tester.pumpAndSettle();
        }
        expect(labels.last, '$realTitle · Salt to Taste');
        expect(repo.loads, 1);

        router.push('/r/$slug/edit'); // the detail page's Edit button
        await tester.pumpAndSettle();
        expect(labels.last, 'Edit recipe · Salt to Taste');

        // What the editor does on Save: the repository call, then go().
        // runAsync: a widget test's clock is fake, and Dio's pipeline needs
        // the real event loop — awaited bare, the request never completes.
        await tester.runAsync(
          () => repo.updateRecipe(slug, {'title': 'RENAMED $realTitle'}),
        );
        // The editor's return (editor_page.dart): pop when it can.
        if (router.canPop()) {
          router.pop();
        } else {
          router.go('/r/$slug');
        }
        await tester.pumpAndSettle();

        expect(
          repo.loads,
          2,
          reason: 'reloaded exactly once after the save — by the kept page',
        );
        expect(find.text('RENAMED $realTitle'), findsOneWidget);
        expect(labels.last, 'RENAMED $realTitle · Salt to Taste');
      },
    );
  }

  // Both layouts hand the recipe's servings to the label: the right rail
  // (wide) and the section after the content (narrow).
  for (final (layout, size) in [
    ('wide', const Size(1200, 1000)),
    ('narrow', const Size(600, 1000)),
  ]) {
    testWidgets('the recipe page says where a per-batch serving comes from '
        '($layout)', (tester) async {
      await pumpApp(
        tester,
        deepLink: true,
        recipes: _SodaBread(),
        nutrition: _SodaBreadLabel(),
        size: size,
      );
      await tester.scrollUntilVisible(
        find.text('per batch'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text(
          'The recipe says "MAKES 1 LOAF", so one serving is the whole loaf.',
        ),
        findsOneWidget,
      );
    }, skip: skipIfNoCorpus != null);
  }
}
