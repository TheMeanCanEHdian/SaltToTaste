import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_badge.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget badge) => tester.pumpWidget(
    MaterialApp(
      theme: buildMaterialTheme(buildForuiTheme()),
      home: FTheme(
        data: buildForuiTheme(),
        child: Scaffold(body: Center(child: badge)),
      ),
    ),
  );

  testWidgets('static badge shows its label and is not a button', (
    tester,
  ) async {
    await pump(tester, const SaltBadge('read', tone: SaltBadgeTone.info));
    expect(find.text('read'), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
    expect(find.byIcon(LucideIcons.chevronRight), findsNothing);
  });

  testWidgets('tone maps to the SaltColors pair (info)', (tester) async {
    await pump(tester, const SaltBadge('read', tone: SaltBadgeTone.info));
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(SaltBadge),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((box.decoration as BoxDecoration).color, SaltColors.infoBg);
  });

  testWidgets('onTap makes it a button with a trailing chevron', (
    tester,
  ) async {
    var tapped = false;
    await pump(
      tester,
      SaltBadge(
        '4/5 matched — review',
        tone: SaltBadgeTone.warn,
        icon: LucideIcons.triangleAlert,
        semanticHint: 'Opens review',
        onTap: () => tapped = true,
      ),
    );
    expect(find.text('4/5 matched — review'), findsOneWidget);
    expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
    expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
    await tester.tap(find.byType(InkWell));
    expect(tapped, isTrue);
  });

  testWidgets('expand stretches to the parent width', (tester) async {
    await pump(
      tester,
      SizedBox(
        width: 320,
        child: SaltBadge(
          'matched',
          tone: SaltBadgeTone.ok,
          onTap: () {},
          expand: true,
        ),
      ),
    );
    // The tappable surface fills the 320-wide slot (chevron pushed to the edge).
    expect(tester.getSize(find.byType(InkWell)).width, closeTo(320, 0.5));
  });

  testWidgets('onDismiss adds a ✕ button that fires the callback', (
    tester,
  ) async {
    var dismissed = false;
    await pump(
      tester,
      SaltBadge(
        'chicken',
        onDismiss: () => dismissed = true,
        dismissHint: 'Clear filter',
      ),
    );
    expect(find.text('chicken'), findsOneWidget);
    expect(find.byIcon(LucideIcons.x), findsOneWidget);
    // A removable chip, not a navigation button.
    expect(find.byIcon(LucideIcons.chevronRight), findsNothing);

    await tester.tap(find.byIcon(LucideIcons.x));
    expect(dismissed, isTrue);
  });

  testWidgets('the ✕ tap target meets the 24px minimum', (tester) async {
    await pump(tester, SaltBadge('chicken', onDismiss: () {}));
    final target = tester.getSize(
      find.ancestor(
        of: find.byIcon(LucideIcons.x),
        matching: find.byType(InkWell),
      ),
    );
    expect(target.width, greaterThanOrEqualTo(24));
    expect(target.height, greaterThanOrEqualTo(24));
  });

  test('a badge cannot be both a nav button and a removable chip', () {
    expect(
      () => SaltBadge('x', onTap: () {}, onDismiss: () {}),
      throwsA(isA<AssertionError>()),
    );
  });

  testWidgets('a width-bounded filter pill ellipsizes rather than overflowing', (
    tester,
  ) async {
    const long = 'a very long search query that far exceeds the pill width';
    await pump(
      tester,
      SizedBox(
        width: 140,
        child: Row(
          children: [Flexible(child: SaltBadge(long, onDismiss: () {}))],
        ),
      ),
    );
    // Pumping without a RenderFlex overflow is itself the assertion that the
    // pixel-bound (Flexible + ellipsis) fix holds; confirm the label is set to
    // ellipsize and the ✕ survives.
    final text = tester.widget<Text>(find.text(long));
    expect(text.overflow, TextOverflow.ellipsis);
    expect(find.byIcon(LucideIcons.x), findsOneWidget);
  });
}
