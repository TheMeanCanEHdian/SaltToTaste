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
}
