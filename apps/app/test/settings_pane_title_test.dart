import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/settings/settings_page.dart';

/// A [PaneTitle] with a trailing action (the Logs download button) must line up
/// with the plain-title tabs — the content below it must start at the SAME
/// offset. A default IconButton is 48px and would push the whole pane down,
/// which is exactly the Logs-tab regression this guards against.
void main() {
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
                    // The Logs tab's actual download button: a Forui xs ghost
                    // icon button, small enough not to inflate the heading.
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
