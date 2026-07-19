import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/auth_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/api/tags_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';
import 'package:salt_app/features/editor/editor_exit_guard.dart';
import 'package:salt_app/features/editor/editor_page.dart';

class _FakeRepo extends RecipeRepository {
  _FakeRepo(this._detail) : super(dio: Dio());
  final RecipeDetail _detail;
  @override
  Future<RecipeDetail> getRecipe(String idOrSlug) async => _detail;
}

void main() {
  Widget host(RecipeDetail detail) => MultiRepositoryProvider(
    providers: [
      RepositoryProvider<RecipeRepository>.value(value: _FakeRepo(detail)),
      RepositoryProvider<TagsRepository>.value(value: TagsRepository(Dio())),
      RepositoryProvider<EditorExitGuard>.value(value: EditorExitGuard()),
    ],
    child: BlocProvider(
      // _EditorScaffold reads AuthCubit in initState; a default (unknown) is fine.
      create: (_) => AuthCubit(AuthRepository(Dio())),
      child: MaterialApp(
        theme: buildMaterialTheme(buildForuiTheme()),
        home: FTheme(data: buildForuiTheme(), child: const EditorPage(slug: 'x')),
      ),
    ),
  );

  testWidgets('a component subsection expands to its nested editors', (
    tester,
  ) async {
    final recipe = Recipe(
      id: 'r1',
      title: 'Creamy Tomato Soup',
      slug: 'soup',
      source: const RecipeSource(name: 'ATK', type: 'manual'),
      ingredients: const [
        IngredientGroup(items: [IngredientLine(raw: '2 (28-ounce) cans tomatoes')]),
      ],
      steps: const [RecipeStep(number: 1, text: 'Simmer.')],
      subsections: const [
        Subsection(
          title: 'Classic Croutons',
          kind: 'component',
          servings: 'MAKES 2 CUPS',
          ingredients: [
            IngredientGroup(items: [IngredientLine(raw: '4 slices bread, cubed')]),
          ],
          steps: [RecipeStep(number: 1, text: 'Toast until golden.')],
        ),
      ],
    );
    await tester.pumpWidget(
      host(RecipeDetail(recipe: recipe, sourceSlug: 'soup')),
    );
    await tester.pumpAndSettle();

    // The subsection header renders (its title is in a field), collapsed —
    // the nested ingredient line isn't built yet.
    expect(find.text('Classic Croutons'), findsOneWidget);
    expect(find.text('4 slices bread, cubed'), findsNothing);

    // Expand it — the caret's tooltip is unique to a collapsed subsection
    // ('Expand'; ingredient toggles say 'Structured fields').
    final caret = find.byTooltip('Expand');
    expect(caret, findsOneWidget);
    await tester.ensureVisible(caret);
    await tester.pumpAndSettle();
    await tester.tap(caret);
    await tester.pumpAndSettle();

    // The nested ingredient + step editors built without throwing (a nested
    // ReorderableListView is the risk).
    expect(tester.takeException(), isNull);
    expect(find.text('4 slices bread, cubed'), findsOneWidget);
    expect(find.text('Toast until golden.'), findsOneWidget);
    expect(find.text('MAKES 2 CUPS'), findsOneWidget);
  });

  testWidgets('a prose-only variation shows the promote affordances', (
    tester,
  ) async {
    final recipe = Recipe(
      id: 'r2',
      title: 'Soup',
      slug: 'soup2',
      source: const RecipeSource(name: 'ATK', type: 'manual'),
      subsections: const [
        Subsection(title: 'Spicy', kind: 'variation', body: 'Add chipotles.'),
      ],
    );
    await tester.pumpWidget(
      host(RecipeDetail(recipe: recipe, sourceSlug: 'soup2')),
    );
    await tester.pumpAndSettle();

    final caret = find.byTooltip('Expand');
    await tester.ensureVisible(caret);
    await tester.pumpAndSettle();
    await tester.tap(caret);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Prose-only: the description prose plus the two promote buttons, and no
    // nested list yet.
    expect(find.text('Add chipotles.'), findsOneWidget);
    expect(find.widgetWithText(FButton, 'Add ingredients'), findsOneWidget);
    expect(find.widgetWithText(FButton, 'Add steps'), findsOneWidget);
  });

  testWidgets('a technique expands to its illustrated-step editor', (
    tester,
  ) async {
    final recipe = Recipe(
      id: 'r3',
      title: 'Bread',
      slug: 'bread',
      source: const RecipeSource(name: 'ATK', type: 'manual'),
      techniques: const [
        Technique(
          heading: 'Shaping the Loaf',
          description: 'Damp hands help.',
          steps: [TechniqueStep(number: 1, caption: 'Fold the dough over.')],
        ),
      ],
    );
    await tester.pumpWidget(
      host(RecipeDetail(recipe: recipe, sourceSlug: 'bread')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shaping the Loaf'), findsOneWidget);
    expect(find.text('Fold the dough over.'), findsNothing);

    final caret = find.byTooltip('Expand');
    expect(caret, findsOneWidget);
    await tester.ensureVisible(caret);
    await tester.pumpAndSettle();
    await tester.tap(caret);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Damp hands help.'), findsOneWidget);
    expect(find.text('Fold the dough over.'), findsOneWidget);
    // The recipe is saved (has an id), so the per-step photo controls show.
    expect(find.widgetWithText(FButton, 'Upload'), findsOneWidget);
    expect(find.widgetWithText(FButton, 'From URL'), findsOneWidget);
  });

  testWidgets('technique step photo controls do not overflow at mobile width', (
    tester,
  ) async {
    // The app's own 'mobile' preset is 375px — the width the review's repro
    // overflowed the Row+Expanded button slot on. The Wrap layout must not.
    tester.view.physicalSize = const Size(375, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final recipe = Recipe(
      id: 'r5',
      title: 'Bread',
      slug: 'bread',
      source: const RecipeSource(name: 'ATK', type: 'manual'),
      techniques: const [
        Technique(
          heading: 'Shaping the Loaf',
          steps: [
            TechniqueStep(number: 1, caption: 'Fold.', image: 'images/a.jpg'),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      host(RecipeDetail(recipe: recipe, sourceSlug: 'bread')),
    );
    await tester.pumpAndSettle();

    final caret = find.byTooltip('Expand');
    await tester.ensureVisible(caret);
    await tester.pumpAndSettle();
    await tester.tap(caret);
    await tester.pumpAndSettle();

    // A RenderFlex overflow raises a FlutterError that takeException() catches.
    expect(
      tester.takeException(),
      isNull,
      reason: 'no RenderFlex overflow at 375px',
    );
    // The step has an image, so the control set is Replace / From URL / Remove.
    expect(find.widgetWithText(FButton, 'Replace'), findsOneWidget);
    expect(find.widgetWithText(FButton, 'From URL'), findsOneWidget);
    expect(find.widgetWithText(FButton, 'Remove'), findsOneWidget);
  });
}
