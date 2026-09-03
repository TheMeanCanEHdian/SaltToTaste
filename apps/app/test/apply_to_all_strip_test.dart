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

  for (final width in [360.0, 900.0]) {
    testWidgets('fits and stays tappable at $width px', (tester) async {
      var dismissed = 0;
      await pumpAt(tester, width, onDismiss: () => dismissed++);
      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(find.text('Apply to 41 recipes'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      final notNow = tester.getRect(find.text('Not now'));
      expect(notNow.right, lessThanOrEqualTo(width), reason: 'on screen');
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle(); // the button's press feedback timers
      expect(dismissed, 1, reason: 'reachable, not clipped away');
    });
  }
}
