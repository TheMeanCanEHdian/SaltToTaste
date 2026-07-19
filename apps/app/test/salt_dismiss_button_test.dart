import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:salt_app/core/widgets/salt_dismiss_button.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required VoidCallback onTap}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SaltDismissButton(
                ink: const Color(0xFF7D1420),
                onTap: onTap,
                semanticLabel: 'Remove tag dessert',
              ),
            ),
          ),
        ),
      );

  BoxDecoration circleDecoration(WidgetTester tester) =>
      tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).decoration!
          as BoxDecoration;

  testWidgets('fires onTap and meets the 24px target', (tester) async {
    var tapped = false;
    await pump(tester, onTap: () => tapped = true);

    final target = tester.getSize(
      find.ancestor(
        of: find.byIcon(LucideIcons.x),
        matching: find.byType(InkWell),
      ),
    );
    expect(target.width, greaterThanOrEqualTo(24));
    expect(target.height, greaterThanOrEqualTo(24));

    await tester.tap(find.byIcon(LucideIcons.x));
    expect(tapped, isTrue);
  });

  testWidgets('the circle deepens on hover', (tester) async {
    await pump(tester, onTap: () {});
    final resting = circleDecoration(tester).color!;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byIcon(LucideIcons.x)));
    await tester.pumpAndSettle();

    final hovered = circleDecoration(tester).color!;
    expect(
      hovered.a,
      greaterThan(resting.a),
      reason: 'hover must deepen the circle tint',
    );
  });
}
