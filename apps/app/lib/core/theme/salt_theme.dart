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

/// True at compact/touch layout widths, where interactive controls should
/// grow toward the 48px minimum touch target. Wider (desktop) layouts keep
/// the denser, approved look.
bool isCompactWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width < Breakpoints.compact;

/// Minimum size for the dense settings/editor action buttons: a 48px-tall
/// touch target everywhere (WCAG 2.5.5). Pair with
/// `MaterialTapTargetSize.shrinkWrap` so only the height is enforced.
Size denseActionMinSize(BuildContext context) => const Size(0, 48);

/// Forui theme themed to the maroon identity, driving Forui widgets.
FThemeData buildForuiTheme() {
  final colors = FColors.neutralLight.copyWith(
    background: SaltColors.pageBackground,
    foreground: SaltColors.ink,
    primary: SaltColors.maroon,
    primaryForeground: Colors.white,
    // Secondary drives the NEUTRAL button family: outline/ghost/secondary
    // buttons take their text from [secondaryForeground] and their hover fill
    // from [secondary]. Keep these neutral (grey, not the pink `chip`/maroon
    // `chipInk`) so a plain "Cancel"/"Add" button — and especially its hover —
    // never reads as the red destructive button. Primary stays maroon,
    // destructive stays red; only these must be neutral.
    secondary: SaltColors.chipNeutral,
    secondaryForeground: SaltColors.ink,
    mutedForeground: SaltColors.muted,
    border: SaltColors.hairline,
    // Destructive buttons use Forui's tinted `.destructive` variant (a pale
    // fill + this color as text). Point it at the app's own error red so every
    // danger surface — button, error text, danger-card border — agrees, rather
    // than Forui's default brighter `#E7000B`.
    destructive: SaltColors.errInk,
  );
  // Built once to get Forui's derived styles, then rebuilt with a
  // higher-contrast tab style (see [_contrastyTabs]). copyWith is avoided
  // deliberately: it hardcodes `touch: true`, which would undo `touch: false`.
  final defaults = FThemeData(
    colors: colors,
    touch: false,
    debugLabel: 'SaltToTaste',
  );
  return FThemeData(
    colors: colors,
    touch: false,
    debugLabel: 'SaltToTaste',
    tabsStyle: _contrastyTabs(defaults.tabsStyle),
  );
}

/// Forui derives the tab indicator from `background` (#FAF7F4) and the track
/// from `secondary` (#EFECEA). In this warm palette those two sit ~4% apart, so
/// the selected tab all but disappears. Paint the indicator white with a
/// hairline border on a definitively grey track so the selection reads at a
/// glance. Pinned by `test/theme_test.dart`.
FTabsStyle _contrastyTabs(FTabsStyle base) => FTabsStyleDelta.delta(
  // Square: the bar runs full-bleed between the panel edges, so Forui's
  // rounded track left clipped-looking corners against the divider above it.
  // The rounded indicator inside still carries the segmented-control read.
  decoration: DecorationDelta.value(
    const BoxDecoration(color: SaltColors.chipNeutral),
  ),
  indicatorDecoration: DecorationDelta.value(
    BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: SaltColors.hairline),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ],
    ),
  ),
)(base);

/// Material theme derived from the Forui theme (for the router scaffolding
/// and custom widgets), with Open Sans applied app-wide.
ThemeData buildMaterialTheme(FThemeData forui) {
  final base = forui.toApproximateMaterialTheme();
  // Forui's approximate Material theme gives every filled button a dark
  // maroon (#7D1420) foreground. On the maroon (#960000) fill that is a
  // 1.15:1 contrast — effectively invisible (the "Sign in" bug). Filled
  // buttons in this app always sit on a dark fill (maroon or errInk), so
  // force a white label + icon here; any button that sets its own
  // foregroundColor still wins via widget-level style merge.
  const whiteFg = WidgetStatePropertyAll<Color?>(Colors.white);
  final filledStyle = (base.filledButtonTheme.style ?? const ButtonStyle())
      .copyWith(foregroundColor: whiteFg, iconColor: whiteFg);
  return base.copyWith(
    scaffoldBackgroundColor: SaltColors.pageBackground,
    textTheme: base.textTheme.apply(
      fontFamily: 'OpenSans',
      // OpenSans lacks a few vulgar-fraction glyphs (⅓, ⅔). The offline
      // build (--no-web-resources-cdn) disables CanvasKit's Noto fallback,
      // so fall back to the bundled Arimo, which covers them — otherwise
      // those characters render blank in recipe prose.
      // Arimo covers most of what Open Sans lacks, but not ⅕ ⅖ ⅗ ⅘ ⅙ ⅚ ⅐ ⅑ ⅒
      // (verified against both cmaps); Inter — already bundled and loaded via
      // Forui — does. Without this the corpus's two ⅕/⅖ amounts render as a
      // tofu box, e.g. `1½ cups (10□ ounces) granulated sugar`.
      fontFamilyFallback: const ['Arimo', 'packages/forui/Inter'],
      bodyColor: SaltColors.ink,
      displayColor: SaltColors.ink,
    ),
    colorScheme: base.colorScheme.copyWith(
      primary: SaltColors.maroon,
      secondary: SaltColors.rose,
      onPrimary: Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(style: filledStyle),
  );
}
