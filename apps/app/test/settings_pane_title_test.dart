import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/settings/settings_page.dart';

/// A [PaneTitle] with a trailing action (the Logs download button) must line up
/// with the plain-title tabs — the content below it must start at the SAME
/// offset. A Forui FButton.icon is ~28px, taller than the ~20px title, so the
/// heading would sit lower without PaneTitle boxing the action to the title's
/// height.
///
/// MUST run with the real Open Sans font loaded: the default test font (Ahem)
/// has different metrics and reports a delta of 0 even when the real app is
/// misaligned — which is how this exact regression shipped twice.
void main() {
  setUpAll(() async {
    final loader = FontLoader('OpenSans');
    for (final path in const [
      'assets/fonts/OpenSans-Regular.ttf',
      'assets/fonts/OpenSans-SemiBold.ttf',
      'assets/fonts/OpenSans-Bold.ttf',
    ]) {
      loader.addFont(
        Future.value(File(path).readAsBytesSync().buffer.asByteData()),
      );
    }
    await loader.load();
  });

  testWidgets('a trailing action does not push the pane content down', (
    tester,
  ) async {
    const description = 'Identical on both panes so only the heading differs.';

    Widget pane(String marker, {Widget? trailing}) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PaneTitle('Title', description: description, trailing: trailing),
        Text(marker),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaterialTheme(buildForuiTheme()),
        home: FTheme(
          data: buildForuiTheme(),
          child: Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: pane('PLAIN')),
                Expanded(
                  child: pane(
                    'WITH_ACTION',
                    // The Logs tab's actual download button.
                    trailing: FButton.icon(
                      variant: FButtonVariant.ghost,
                      size: FButtonSizeVariant.xs,
                      onPress: () {},
                      child: const Icon(Icons.download_outlined, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final plainTop = tester.getTopLeft(find.text('PLAIN')).dy;
    final actionTop = tester.getTopLeft(find.text('WITH_ACTION')).dy;
    expect(
      (plainTop - actionTop).abs(),
      lessThan(1.0),
      reason:
          'the trailing action must not make the heading taller '
          '(plain=$plainTop with-action=$actionTop)',
    );
  });
}
