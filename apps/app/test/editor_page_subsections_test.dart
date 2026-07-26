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
        // Match the real app (app.dart): FTheme wraps via `builder`, ABOVE the
        // Navigator/Overlay — so a drag proxy in the overlay still finds it.
        // (Putting it at `home:` would leave the overlay outside FTheme and a
        // dragged FTextField would throw, which the app never does.)
        builder: (context, child) =>
            FTheme(data: buildForuiTheme(), child: child!),
        home: const EditorPage(slug: 'x'),
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
        IngredientGroup(
          items: [IngredientLine(raw: '2 (28-ounce) cans tomatoes')],
        ),
      ],
      steps: const [RecipeStep(number: 1, text: 'Simmer.')],
      subsections: const [
        Subsection(
          title: 'Classic Croutons',
          kind: 'component',
          servings: 'MAKES 2 CUPS',
          ingredients: [
            IngredientGroup(
              items: [IngredientLine(raw: '4 slices bread, cubed')],
            ),
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

  testWidgets('a technique step photo requests a source-rooted image URL', (
    tester,
  ) async {
    // The stored reference is the bare canonical `images/<file>`; the editor
    // must root it under the source slug (/images/<source>/<file>) — feeding
    // the bare reference to Image.network 404s and the photo never shows.
    final recipe = Recipe(
      id: 'r6',
      title: 'Bread',
      slug: 'bread',
      source: const RecipeSource(name: 'ATK', type: 'manual'),
      techniques: const [
        Technique(
          heading: 'Shaping the Loaf',
          steps: [
            TechniqueStep(
              number: 1,
              caption: 'Fold.',
              image: 'images/shape-01.jpg',
            ),
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

    final urls = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => i.image)
        .whereType<NetworkImage>()
        .map((n) => n.url)
        .toList();
    // apiBaseUrl is '' in tests, so the rooted path is served as-is.
    expect(urls, contains('/images/bread/shape-01.jpg'));
    expect(
      urls,
      isNot(contains('images/shape-01.jpg')),
      reason: 'must not feed the bare reference to Image.network',
    );
  });

  testWidgets('the save bar does not overflow at a 320px viewport', (
    tester,
  ) async {
    // iPhone SE portrait / Galaxy Fold cover — the Cancel + Save buttons plus
    // spacing used to overflow the status Row by ~14px here.
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final recipe = Recipe(
      id: 'r7',
      title: 'X',
      slug: 'x',
      source: const RecipeSource(name: 'ATK', type: 'manual'),
    );
    await tester.pumpWidget(
      host(RecipeDetail(recipe: recipe, sourceSlug: 'x')),
    );
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'the save bar must not overflow at 320px',
    );
    // Both actions still render (stacked below the status line).
    expect(find.widgetWithText(FButton, 'Save recipe'), findsOneWidget);
    expect(find.widgetWithText(FButton, 'Cancel'), findsOneWidget);
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

  testWidgets(
    'reorderable lists set a custom drag lift, never the grey default',
    (tester) async {
      // A recipe exercising the top-level reorderable lists (ingredients + a
      // group header, steps, and a technique).
      final recipe = Recipe(
        id: 'r1',
        title: 'Stew',
        slug: 'stew',
        source: const RecipeSource(name: 'ATK', type: 'manual'),
        ingredients: const [
          IngredientGroup(
            group: 'For the stew',
            items: [
              IngredientLine(raw: '1 onion'),
              IngredientLine(raw: '2 carrots'),
            ],
          ),
        ],
        steps: const [RecipeStep(number: 1, text: 'Cook.')],
        techniques: const [
          Technique(
            heading: 'Searing',
            steps: [TechniqueStep(number: 1, caption: 'Brown the meat.')],
          ),
        ],
      );
      await tester.pumpWidget(
        host(RecipeDetail(recipe: recipe, sourceSlug: 'stew')),
      );
      await tester.pumpAndSettle();

      // Capture the widgets up front — the loop pumps a throwaway tree to render
      // each proxy, which would invalidate a lazy finder iterable.
      final lists = tester
          .widgetList<ReorderableListView>(find.byType(ReorderableListView))
          .toList();
      expect(lists, isNotEmpty);

      for (final list in lists) {
        // A custom proxyDecorator is set — null would fall back to Flutter's
        // default: a canvasColor Material at elevation 6 (the grey box that
        // also bleeds past a rounded card's border).
        expect(
          list.proxyDecorator,
          isNotNull,
          reason: 'every reorderable list must override the grey default proxy',
        );

        // Invoking it yields either the ROW lift (opaque page-white, rounded so
        // the fill/shadow follow the corners) or the CARD lift (transparent, so
        // a card's bottom-margin isn't painted as padding) — never Flutter's
        // grey canvasColor default.
        final proxy = list.proxyDecorator!(
          const SizedBox(key: Key('dragged')),
          0,
          const AlwaysStoppedAnimation<double>(1),
        );
        await tester.pumpWidget(MaterialApp(home: proxy));
        final material = tester.widget<Material>(
          find.ancestor(
            of: find.byKey(const Key('dragged')),
            matching: find.byType(Material),
          ),
        );
        final isRowLift =
            material.color == Colors.white &&
            material.borderRadius == BorderRadius.circular(12);
        final isCardLift = material.type == MaterialType.transparency;
        expect(
          isRowLift || isCardLift,
          isTrue,
          reason: 'a custom row/card lift, never the grey canvasColor default',
        );
      }
    },
  );

  testWidgets('dragging a scoped row does not throw a grey ErrorWidget', (
    tester,
  ) async {
    // The regression: the drag overlay rebuilds an ingredient/step row outside
    // its InheritedWidget scope; _IngredientScope.of()'s `!` then threw, and the
    // release-mode ErrorWidget painted the blank grey box. Driving a real drag
    // exercises the proxy rebuild; the fix re-provides the scope so it doesn't
    // throw.
    final recipe = Recipe(
      id: 'r1',
      title: 'Stew',
      slug: 'stew',
      source: const RecipeSource(name: 'ATK', type: 'manual'),
      ingredients: const [
        IngredientGroup(
          items: [
            IngredientLine(raw: '1 onion'),
            IngredientLine(raw: '2 carrots'),
          ],
        ),
      ],
      steps: const [
        RecipeStep(number: 1, text: 'Chop.'),
        RecipeStep(number: 2, text: 'Simmer.'),
      ],
    );
    await tester.pumpWidget(
      host(RecipeDetail(recipe: recipe, sourceSlug: 'stew')),
    );
    await tester.pumpAndSettle();

    // Handles are in document order: ingredient rows first, then step cards.
    final handles = find.byIcon(Icons.drag_indicator);
    for (final index in [0, 2]) {
      final handle = handles.at(index);
      await tester.ensureVisible(handle);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump(); // build + lay out the drag proxy (rebuilds the item)
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.takeException(),
        isNull,
        reason: 'the drag proxy must rebuild the row without throwing',
      );
      await gesture.up();
      await tester.pumpAndSettle();
    }
  });
}
