import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/recipes/detail/view_yaml_dialog.dart';

class _FakeRepo extends RecipeRepository {
  _FakeRepo() : super(dio: Dio());
  @override
  Future<String> recipeYamlText(String idOrSlug) async =>
      '${List.generate(60, (i) => 'line_$i: value').join('\n')}\n';
  @override
  Uri yamlUrl(String idOrSlug) => Uri.parse('http://example/$idOrSlug.yaml');
}

void main() {
  // A roomy surface so the collapsed cap (620) sits below the viewport and the
  // expanded size can grow past it.
  void bigSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget host() => RepositoryProvider<RecipeRepository>.value(
    value: _FakeRepo(),
    child: MaterialApp(
      theme: buildMaterialTheme(buildForuiTheme()),
      // Forui theme above the Navigator/Overlay, so the dialog finds it.
      builder: (context, child) =>
          FTheme(data: buildForuiTheme(), child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showViewYamlDialog(context, recipeId: 'r1'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  // The dialog's own sizing box: the only finite-width ConstrainedBox in the
  // dialog wide enough to be the frame (Forui's buttons are far narrower; the
  // Material Dialog's internal box is unbounded in width).
  BoxConstraints frame(WidgetTester tester) => tester
      .widgetList<ConstrainedBox>(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(ConstrainedBox),
        ),
      )
      .map((b) => b.constraints)
      .firstWhere((c) => c.maxWidth.isFinite && c.maxWidth >= 700);

  testWidgets('content is clipped to the rounded shape (no square corners)', (
    tester,
  ) async {
    bigSurface(tester);
    await open(tester);

    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    expect(
      dialog.clipBehavior,
      Clip.antiAlias,
      reason: 'the opaque code area/footer must be clipped to the rounded '
          'corners, else the bottom corners read as square',
    );
    expect(
      (dialog.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(12),
    );
  });

  testWidgets('the expand toggle enlarges the dialog and flips back', (
    tester,
  ) async {
    bigSurface(tester);
    await open(tester);

    // Collapsed: a comfortable reading box.
    expect(find.byTooltip('Expand'), findsOneWidget);
    final collapsed = frame(tester);
    expect(collapsed.maxWidth, 760);
    expect(collapsed.maxHeight, 620);

    await tester.tap(find.byTooltip('Expand'));
    await tester.pumpAndSettle();

    // Expanded: fills the viewport minus the 24px inset each side.
    expect(find.byTooltip('Shrink'), findsOneWidget);
    final expanded = frame(tester);
    expect(expanded.maxHeight, greaterThan(collapsed.maxHeight));
    expect(expanded.maxHeight, 1000 - 48);
    expect(expanded.maxWidth, 1200 - 48);

    // Toggling back restores the collapsed box.
    await tester.tap(find.byTooltip('Shrink'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Expand'), findsOneWidget);
    expect(frame(tester).maxHeight, 620);
  });
}
