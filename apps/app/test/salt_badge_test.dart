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
}
