import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salt_app/core/theme/salt_theme.dart';

void main() {
  test('Forui theme carries the maroon brand and the button colour system', () {
    final theme = buildForuiTheme();
    expect(theme.colors.primary, SaltColors.maroon);
    // The button colour system for a red brand (see CLAUDE.md): destructive is
    // distinguished from primary by FILL, not hue. Neutral buttons
    // (outline/ghost/secondary) must be grey — their text is
    // `secondaryForeground` and their hover fill is `secondary` — so a plain
    // "Cancel"/"Add" never reads as the red destructive button on hover.
    expect(theme.colors.secondary, SaltColors.chipNeutral);
    expect(theme.colors.secondaryForeground, SaltColors.ink);
    // Destructive uses the app's own error red so every danger surface (button,
    // error text, danger-card border) agrees, not Forui's brighter default.
    expect(theme.colors.destructive, SaltColors.errInk);
  });

  test('Material theme derives from the Forui theme with Open Sans', () {
    final material = buildMaterialTheme(buildForuiTheme());
    expect(material.colorScheme.primary, SaltColors.maroon);
    expect(material.textTheme.bodyMedium?.fontFamily, 'OpenSans');
  });

  test('FilledButton foreground is white for contrast on the maroon fill', () {
    // Forui's toApproximateMaterialTheme() gives filled buttons a dark
    // maroon (#7D1420) foreground — a ~1.15:1 contrast on the #960000 fill,
    // effectively invisible (the "Sign in" bug). buildMaterialTheme must
    // force white; guard against a future Forui upgrade regressing it.
    final material = buildMaterialTheme(buildForuiTheme());
    final style = material.filledButtonTheme.style;
    expect(style, isNotNull);
    expect(
      style!.foregroundColor?.resolve(<WidgetState>{}),
      Colors.white,
      reason: 'filled button label must be white on the maroon fill',
    );
    expect(
      style.iconColor?.resolve(<WidgetState>{}),
      Colors.white,
      reason: 'filled button icon must be white on the maroon fill',
    );
    expect(material.colorScheme.onPrimary, Colors.white);
  });
}
