import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/features/settings/settings_page.dart';

/// The settings pane cross-fade on tab change.
///
/// Drives the REAL [settingsTabTransition] builder (not a copy) with dummy
/// panes, the same way router_transition_test drives the real _fadePage — a
/// copy is how a transition ships dead while its test stays green.
void main() {
  Widget harness({
    required bool reduceMotion,
    required Key key,
    required String label,
  }) => MaterialApp(
    home: Scaffold(
      body: settingsTabTransition(
        reduceMotion: reduceMotion,
        contentKey: key,
        child: Text(label),
      ),
    ),
  );

  testWidgets('a tab change cross-fades: both panes are on screen mid-fade', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(reduceMotion: false, key: const ValueKey('a'), label: 'PANE A'),
    );
    await tester.pumpAndSettle();
    expect(find.text('PANE A'), findsOneWidget);

    // Switch tabs — a new key means a new child, so the switcher animates.
    await tester.pumpWidget(
      harness(reduceMotion: false, key: const ValueKey('b'), label: 'PANE B'),
    );
    await tester.pump(); // kick off
    await tester.pump(const Duration(milliseconds: 90)); // half of the 180ms in
    expect(
      find.text('PANE A'),
      findsOneWidget,
      reason: 'the outgoing pane must still be painted mid-fade',
    );
    expect(find.text('PANE B'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('PANE A'), findsNothing);
    expect(find.text('PANE B'), findsOneWidget);
  });

  testWidgets('reduced motion swaps instantly, no lingering pane', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(reduceMotion: true, key: const ValueKey('a'), label: 'PANE A'),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      harness(reduceMotion: true, key: const ValueKey('b'), label: 'PANE B'),
    );
    await tester.pumpAndSettle();
    expect(find.text('PANE A'), findsNothing);
    expect(find.text('PANE B'), findsOneWidget);
  });
}
