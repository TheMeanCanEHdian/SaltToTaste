import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salt_app/core/theme/salt_theme.dart';

void main() {
  test('Forui theme carries the maroon brand color', () {
    final theme = buildForuiTheme();
    expect(theme.colors.primary, SaltColors.maroon);
    expect(theme.colors.secondaryForeground, SaltColors.chipInk);
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
