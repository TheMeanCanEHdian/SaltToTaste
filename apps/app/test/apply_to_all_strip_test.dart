import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/nutrition/apply_to_all_strip.dart';

/// The strip must fit every sheet it is shown in. Below 720 logical px the
/// review sheet is a full-width bottom sheet, so a phone is ~360 px — where a
/// Wrap placed as a plain Row child never wrapped, overflowed, and clipped
/// "Not now" off-screen.
void main() {
  // The test font is a square-glyph fallback (every character as wide as the
  // font size), which makes "Apply to 41 recipes" 266 px — twice its real
  // width. Load the app's own face so widths mean what they mean in the app.
  setUpAll(() async {
    // The app's own face, under the family names the theme asks for: the
    // Material theme's OpenSans and Forui's typography (Inter, a package
    // font), so button labels measure as they do in the app.
    final openSans = FontLoader('OpenSans');
    for (final file in [
      'OpenSans-Regular.ttf',
      'OpenSans-SemiBold.ttf',
      'OpenSans-Bold.ttf',
    ]) {
      openSans.addFont(rootBundle.load('assets/fonts/$file'));
    }
    await openSans.load();
    final inter = FontLoader('packages/forui/Inter')
      ..addFont(rootBundle.load('packages/forui/assets/fonts/inter/Inter.ttf'));
    await inter.load();
  });

  const offer = (
    position: 0,
    label: 'unsalted butter',
    fdcId: 1,
    confirmed: false,
    grams: null,
    others: 41,
    lines: 41,
  );

  Future<void> pumpAt(
    WidgetTester tester,
    double width, {
    required VoidCallback onDismiss,
    int others = 41,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaterialTheme(buildForuiTheme()),
        builder: (context, child) =>
            FTheme(data: buildForuiTheme(), child: child!),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(18),
            child: ApplyToAllStrip(
              offer: (
                position: offer.position,
                label: offer.label,
                fdcId: offer.fdcId,
                confirmed: offer.confirmed,
                grams: offer.grams,
                others: others,
                lines: others,
              ),
              applied: null,
              applying: false,
              onApply: () {},
              onDismiss: onDismiss,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a four-digit count still fits at phone width', (tester) async {
    await pumpAt(tester, 360, onDismiss: () {}, others: 1198);
    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(find.text('Not now'), findsOneWidget);
  });

  /// The strip, sized by the group's other lines — the one sentence it
  /// tells. Real numbers from the approved mockup's jalapeno chile group
  /// (5 lines, 5 recipes).
  Future<void> pumpKept(
    WidgetTester tester, {
    required int lines,
    required int others,
    bool applying = false,
  }) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaterialTheme(buildForuiTheme()),
        builder: (context, child) =>
            FTheme(data: buildForuiTheme(), child: child!),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(18),
            child: ApplyToAllStrip(
              offer: (
                position: 2,
                label: 'jalapeno chile',
                fdcId: null,
                confirmed: true,
                grams: null,
                others: others,
                lines: lines,
              ),
              applied: null,
              applying: applying,
              onApply: () {},
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the strip says the other LINES are waiting on the decision', (
    tester,
  ) async {
    await pumpKept(tester, lines: 4, others: 4);
    expect(find.textContaining('4 other lines'), findsOneWidget);
    expect(find.textContaining('jalapeno chile'), findsWidgets);
    expect(find.textContaining('in 4 recipes'), findsOneWidget);
    expect(
      find.textContaining('are still waiting on this decision.'),
      findsOneWidget,
    );
    // Never the pick wording — nothing here is on a different match.
    expect(find.textContaining('with a different match'), findsNothing);
    expect(find.text('Apply to 4 lines'), findsOneWidget);
  });

  testWidgets('one line in one recipe reads in the singular', (tester) async {
    await pumpKept(tester, lines: 1, others: 1);
    expect(find.textContaining('1 other line'), findsOneWidget);
    expect(find.textContaining('in 1 recipe,'), findsOneWidget);
    expect(
      find.textContaining('is still waiting on this decision.'),
      findsOneWidget,
    );
    expect(find.text('Apply to 1 line'), findsOneWidget);
  });

  testWidgets('two lines in one recipe count lines, not recipes', (
    tester,
  ) async {
    // Saffron threads: two lines of one ingredient in a single recipe.
    await pumpKept(tester, lines: 2, others: 1);
    expect(find.textContaining('2 other lines'), findsOneWidget);
    expect(find.textContaining('in 1 recipe,'), findsOneWidget);
    expect(find.text('Apply to 2 lines'), findsOneWidget);
  });

  testWidgets('applying counts lines too', (tester) async {
    await pumpKept(tester, lines: 4, others: 4, applying: true);
    expect(find.textContaining('Applying to '), findsOneWidget);
    expect(find.textContaining('4 lines'), findsWidgets);
  });

  for (final width in [360.0, 900.0]) {
    testWidgets('fits and stays tappable at $width px', (tester) async {
      var dismissed = 0;
      await pumpAt(tester, width, onDismiss: () => dismissed++);
      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(find.text('Apply to 41 lines'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      final notNow = tester.getRect(find.text('Not now'));
      expect(notNow.right, lessThanOrEqualTo(width), reason: 'on screen');
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle(); // the button's press feedback timers
      expect(dismissed, 1, reason: 'reachable, not clipped away');
    });
  }
}
