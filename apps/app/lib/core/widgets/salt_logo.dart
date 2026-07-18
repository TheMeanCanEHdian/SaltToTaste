import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:salt_app/core/theme/salt_theme.dart';

/// The brand vector — the pan/spices/flame mark in [assets/images/logo.svg].
///
/// A single monochrome path set with no baked-in colour, so callers recolour it
/// through [color]. Rendered via `flutter_svg` (the SVG is the hand-editable
/// source of truth) rather than a rasterised PNG, so it stays crisp at any size.
class SaltLogoGlyph extends StatelessWidget {
  const SaltLogoGlyph({super.key, this.color, this.width, this.height});

  final Color? color;
  final double? width;
  final double? height;

  static const String _asset = 'assets/images/logo.svg';

  /// logo.svg's viewBox is 591 × 449.
  static const double _aspect = 591 / 449;

  /// Decode + cache the mark ahead of first paint so it doesn't visibly "pop
  /// in" when a page mounts (flutter_svg loads the asset asynchronously on the
  /// first build otherwise). The cache key includes the tint, so warm the
  /// colour the surfaces actually use — white on the maroon nav bar / auth
  /// card. Call once at startup; best-effort (a failure just falls back to the
  /// normal async load).
  static Future<void> precache([
    Color color = const Color(0xFFFFFFFF),
  ]) async {
    await SvgAssetLoader(
      _asset,
      theme: SvgTheme(currentColor: color),
    ).loadBytes(null);
  }

  @override
  Widget build(BuildContext context) {
    // Give SvgPicture BOTH dimensions: with only one, CanvasKit (web) lays the
    // picture out blank (flutter_test tolerates a single dimension, so this only
    // shows up in the real app). Derive the missing side from the viewBox.
    var w = width;
    var h = height;
    if (w == null && h != null) w = h * _aspect;
    if (h == null && w != null) h = w / _aspect;
    // Tint via the SVG's `currentColor` (substituted at parse time) rather than
    // a `colorFilter`: a srcIn colour filter renders the picture BLANK on
    // CanvasKit (web) — verified directly, even with both dimensions set — while
    // flutter_test/Skia paints it fine, so the bug is invisible to goldens.
    // Requires `fill="currentColor"` on logo.svg's wrapper <g>.
    return SvgPicture.asset(
      _asset,
      width: w,
      height: h,
      fit: BoxFit.contain,
      theme: SvgTheme(currentColor: color ?? const Color(0xFF000000)),
    );
  }
}

/// The circular brand mark — the [SaltLogoGlyph] centred on a filled disc.
///
/// Replaces the old `logo_circle.png` for in-app use (the auth card). The glyph
/// is inset so it never touches the disc edge; the SVG is landscape (591×449),
/// so the inset is expressed as a fraction of the disc width and the glyph is
/// centred within it.
class SaltLogoMark extends StatelessWidget {
  const SaltLogoMark({
    super.key,
    this.size = 40,
    this.background = SaltColors.maroon,
    this.foreground = const Color(0xFFFFFFFF),
  });

  final double size;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      alignment: Alignment.center,
      // 0.86 of the disc width matches the old logo_circle.png inset (measured).
      child: SaltLogoGlyph(color: foreground, width: size * 0.86),
    );
  }
}

/// The full horizontal banner lockup — the [SaltLogoGlyph] beside the
/// [SaltWordmark], matching the old `logo_banner.png` (measured: the glyph is
/// as tall as the two text lines, set off by a gap ≈0.2× its height).
///
/// This is what the nav bar shows; [color] paints both the glyph and the text
/// (white on the maroon bar), and the whole lockup scales off [titleSize].
class SaltLogoBanner extends StatelessWidget {
  const SaltLogoBanner({
    super.key,
    this.color = SaltColors.maroon,
    this.titleSize = 20,
    this.gapFactor = 0.2,
  });

  final Color color;
  final double titleSize;

  /// Space between the glyph and the wordmark, as a fraction of [titleSize].
  /// The nav-bar default (0.2) is tight; roomier lockups (the login header)
  /// pass a larger value.
  final double gapFactor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SaltLogoGlyph(color: color, height: titleSize * 2.1),
        SizedBox(width: titleSize * gapFactor),
        SaltWordmark(color: color, titleSize: titleSize),
      ],
    );
  }
}

/// The stacked wordmark — "Salt to Taste" over "Recipe Manager".
///
/// The text half of the banner lockup. The title is Open Sans SemiBold (600),
/// the tagline Open Sans Light (300) tracked out so it spans the title width,
/// matching the original banner. Both lines take [color]; everything scales off
/// [titleSize] so one number sizes the whole lockup.
class SaltWordmark extends StatelessWidget {
  const SaltWordmark({
    super.key,
    this.color = SaltColors.maroon,
    this.titleSize = 19,
  });

  final Color color;
  final double titleSize;

  static const String _title = 'Salt to Taste';
  static const String _tagline = 'Recipe Manager';

  @override
  Widget build(BuildContext context) {
    final taglineSize = titleSize * 0.56;
    // `decoration: none` guards against the yellow "text without a Material"
    // fallback underline the widget would otherwise inherit in a bare context.
    final titleStyle = TextStyle(
      fontFamily: 'OpenSans',
      fontWeight: FontWeight.w600,
      fontSize: titleSize,
      height: 1.0,
      color: color,
      decoration: TextDecoration.none,
    );
    final taglineStyle = TextStyle(
      fontFamily: 'OpenSans',
      fontWeight: FontWeight.w300,
      fontSize: taglineSize,
      height: 1.0,
      color: color,
      decoration: TextDecoration.none,
    );

    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    double widthOf(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: TextScaler.noScaling,
      )..layout();
      return painter.width;
    }

    // Track the lighter, shorter tagline out so its last glyph lands on the
    // title's right edge — the original banner justified the two to equal
    // width (measured ratio 0.994). Distribute the slack across the glyph gaps.
    final gaps = _tagline.length - 1;
    final slack = widthOf(_title, titleStyle) - widthOf(_tagline, taglineStyle);
    final letterSpacing = (gaps > 0 && slack > 0) ? slack / gaps : 0.0;

    // A brand lockup is sized off [titleSize] and lives in a fixed-height bar,
    // so it must not resize with the platform text-scale (that would overflow
    // the bar and desync the tagline tracking, which is measured unscaled).
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_title, style: titleStyle, textScaler: TextScaler.noScaling),
        SizedBox(height: titleSize * 0.14),
        Text(
          _tagline,
          style: taglineStyle.copyWith(letterSpacing: letterSpacing),
          textScaler: TextScaler.noScaling,
        ),
      ],
    );
  }
}
