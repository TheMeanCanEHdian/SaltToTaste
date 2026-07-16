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

  /// Slightly warm panel fill for inset cards (notes, editor panels).
  static const Color panel = Color(0xFFFDFBF9);

  /// Neutral badge fill ("only you", disabled-ish chips).
  static const Color chipNeutral = Color(0xFFEFECEA);

  // Status colors (parse chips, scan-report lines, banners) — the single
  // source for the ok/warn/error trio used across the app.
  static const Color okBg = Color(0xFFE8F3E4);
  static const Color okInk = Color(0xFF2C5A1E);
  static const Color warnBg = Color(0xFFFDF1E2);
  static const Color warnInk = Color(0xFF8A5A12);
  static const Color errBg = Color(0xFFFBE9E9);
  static const Color errInk = Color(0xFF8A1212);

  /// Informational teal (the import tab's "Recipe Extraction" kind chip).
  static const Color infoBg = Color(0xFFE2EFEC);
  static const Color infoInk = Color(0xFF1F5C52);

  /// Body prose and step-card text (softer than [ink]).
  static const Color bodyText = Color(0xFF4A4442);
  static const Color stepText = Color(0xFF3F3A38);

  /// Overlays on photo tiles: bottom title scrim, the servings badge, and
  /// the title's drop shadow.
  static const Color cardScrim = Color(0xB8000000);
  static const Color cardBadge = Color(0x6B000000);
  static const Color cardTitleShadow = Color(0x66000000);
}

/// Shared responsive breakpoints (logical pixels) so the nav bar, grid, and
/// detail page switch layouts at the same widths.
abstract final class Breakpoints {
  /// Below this the nav bar collapses and the grid is a single column.
  static const double compact = 600;
  static const double medium = 900;
  static const double wide = 1200;

  /// At/above this the detail page uses its two-column layouts.
  static const double detailTwoColumn = 720;
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
