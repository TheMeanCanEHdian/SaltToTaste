import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// The SaltToTaste palette. Only [maroon] is a hard brand requirement; the
/// rest follow the approved P2 mockup (docs/mockups/p2-read-only.html).
abstract final class SaltColors {
  static const Color maroon = Color(0xFF960000);
  static const Color maroonHover = Color(0xFF7D1420);
  static const Color rose = Color(0xFF8C4242);
  static const Color chip = Color(0xFFF6E4E4);
  static const Color chipInk = Color(0xFF7D1420);
  static const Color ink = Color(0xFF23201F);
  static const Color muted = Color(0xFF6D6763);
  static const Color hairline = Color(0xFFE7E2DE);
  static const Color pageBackground = Color(0xFFFAF7F4);
}

/// Forui theme themed to the maroon identity, driving Forui widgets.
FThemeData buildForuiTheme() {
  final colors = FColors.neutralLight.copyWith(
    background: SaltColors.pageBackground,
    foreground: SaltColors.ink,
    primary: SaltColors.maroon,
    primaryForeground: Colors.white,
    secondary: SaltColors.chip,
    secondaryForeground: SaltColors.chipInk,
    mutedForeground: SaltColors.muted,
    border: SaltColors.hairline,
  );
  return FThemeData(colors: colors, touch: false, debugLabel: 'SaltToTaste');
}

/// Material theme derived from the Forui theme (for the router scaffolding
/// and custom widgets), with Open Sans applied app-wide.
ThemeData buildMaterialTheme(FThemeData forui) {
  final base = forui.toApproximateMaterialTheme();
  return base.copyWith(
    scaffoldBackgroundColor: SaltColors.pageBackground,
    textTheme: base.textTheme.apply(
      fontFamily: 'OpenSans',
      bodyColor: SaltColors.ink,
      displayColor: SaltColors.ink,
    ),
    colorScheme: base.colorScheme.copyWith(
      primary: SaltColors.maroon,
      secondary: SaltColors.rose,
    ),
  );
}
