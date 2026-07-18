import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_logo.dart';

/// The brand logo widgets that replaced the old raster PNGs.
///
/// Text metrics are asserted with the REAL Open Sans loaded — the default test
/// font (Ahem) is monospaced, so the justified-tagline maths would look right
/// under it while being wrong in the app (the trap that bit the settings
/// heading three times).
void main() {
  setUpAll(() async {
    final loader = FontLoader('OpenSans');
    for (final path in const [
      'assets/fonts/OpenSans-Light.ttf',
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

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  group('SaltWordmark', () {
    testWidgets('renders both lines in the right weights and colour', (
      tester,
    ) async {
      await tester.pumpWidget(host(const SaltWordmark(color: Colors.white)));

      final title = tester.widget<Text>(find.text('Salt to Taste'));
      final tagline = tester.widget<Text>(find.text('Recipe Manager'));

      expect(title.style!.fontWeight, FontWeight.w600);
      expect(tagline.style!.fontWeight, FontWeight.w300);
      expect(title.style!.color, Colors.white);
      expect(tagline.style!.color, Colors.white);
      // Never inherit the "text without a Material" yellow underline.
      expect(title.style!.decoration, TextDecoration.none);
      expect(tagline.style!.decoration, TextDecoration.none);
      expect(title.style!.fontFamily, 'OpenSans');
      expect(tagline.style!.fontFamily, 'OpenSans');
    });

    testWidgets('tracks the tagline out to the title width', (tester) async {
      const titleSize = 40.0;
      await tester.pumpWidget(host(const SaltWordmark(titleSize: titleSize)));

      final tagline = tester.widget<Text>(find.text('Recipe Manager'));
      final spacing = tagline.style!.letterSpacing!;
      expect(spacing, greaterThan(0), reason: 'tagline must be tracked out');

      // The tracked tagline should span the title width (the original banner
      // justified the two lines to equal width: measured ratio 0.994).
      double widthOf(String text, TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout();
        return painter.width;
      }

      final titleWidth = widthOf(
        'Salt to Taste',
        const TextStyle(
          fontFamily: 'OpenSans',
          fontWeight: FontWeight.w600,
          fontSize: titleSize,
        ),
      );
      final trackedTagline = widthOf(
        'Recipe Manager',
        TextStyle(
          fontFamily: 'OpenSans',
          fontWeight: FontWeight.w300,
          fontSize: titleSize * 0.56,
          letterSpacing: spacing,
        ),
      );
      // Tracked width lands within one letter-slot of the title (the last
      // glyph's right edge on the title's; the box carries one trailing slot).
      expect((trackedTagline - titleWidth).abs(), lessThan(spacing + 1));
    });
  });

  testWidgets('SaltLogoMark: white glyph on a maroon disc', (tester) async {
    await tester.pumpWidget(host(const SaltLogoMark(size: 48)));

    final container = tester.widget<Container>(
      find.ancestor(
        of: find.byType(SvgPicture),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color, SaltColors.maroon);

    final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(svg.width, closeTo(48 * 0.86, 0.01));
    // The mark passes width ONLY, so height is the derived side. Assert it is
    // emitted: SvgPicture with a single dimension lays out blank on CanvasKit
    // (web), and flutter_test/Skia hides that — so nothing but this assertion
    // guards the load-bearing derivation.
    expect(svg.height, isNotNull);
    expect(svg.height, closeTo(48 * 0.86 * 449 / 591, 0.01));
    // Recoloured to the foreground via currentColor (not a srcIn colorFilter,
    // which renders blank on CanvasKit).
    expect(svg.colorFilter, isNull);
    final loader = svg.bytesLoader as SvgAssetLoader;
    expect(loader.theme?.currentColor, const Color(0xFFFFFFFF));
  });

  testWidgets('SaltLogoGlyph.precache warms the cache without throwing', (
    tester,
  ) async {
    // Real bundle I/O — needs runAsync. A completing future (no throw) is the
    // contract; startup calls it best-effort to avoid the first-paint pop-in.
    await tester.runAsync(() => SaltLogoGlyph.precache());
  });

  testWidgets('SaltLogoBanner: glyph sits left of the wordmark', (
    tester,
  ) async {
    await tester.pumpWidget(host(const SaltLogoBanner(color: Colors.white)));

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('Salt to Taste'), findsOneWidget);
    expect(find.text('Recipe Manager'), findsOneWidget);

    // The banner glyph passes height ONLY, so width is the derived side — the
    // mirror of the mark's case. Guard that both dimensions reach SvgPicture so
    // the glyph can't silently blank on CanvasKit web.
    final glyph = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(glyph.height, isNotNull);
    expect(glyph.width, isNotNull);

    final glyphRight = tester.getBottomRight(find.byType(SvgPicture)).dx;
    final wordmarkLeft = tester.getTopLeft(find.text('Salt to Taste')).dx;
    expect(glyphRight, lessThanOrEqualTo(wordmarkLeft));
  });
}
