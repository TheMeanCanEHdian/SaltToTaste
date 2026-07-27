import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/recipe_row.dart';
import 'package:salt_shared/salt_shared.dart';

import 'support/corpus.dart';

/// The list-layout row: its cook-time formatting, its favorite indicator, and
/// the responsive one-line ↔ stacked switch.
void main() {
  group('formatCookTime', () {
    test('sub-hour durations render as minutes', () {
      expect(formatCookTime(0), '0 min');
      expect(formatCookTime(45), '45 min');
      expect(formatCookTime(59), '59 min');
    });

    test('whole hours drop the minutes', () {
      expect(formatCookTime(60), '1 hr');
      expect(formatCookTime(120), '2 hr');
      expect(formatCookTime(180), '3 hr');
    });

    test('mixed durations show both parts', () {
      expect(formatCookTime(90), '1 hr 30 min');
      expect(formatCookTime(200), '3 hr 20 min');
      expect(formatCookTime(61), '1 hr 1 min');
    });
  });

  Widget host(RecipeCard card, double width) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: RecipeRow(card: card, onTap: () {}),
        ),
      ),
    ),
  );

  RecipeCard cardFrom(
    Recipe recipe, {
    String? heroImage,
    bool favorite = false,
  }) => RecipeCard(
    id: recipe.id,
    slug: recipe.slug,
    title: recipe.title,
    servingsText: recipe.servings,
    heroImage: heroImage,
    favorite: favorite,
  );

  group('recipe row', skip: skipIfNoCorpus, () {
    late Recipe bundt;

    setUpAll(() {
      bundt = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
    });

    // Lucide (forui's set) has no filled heart, so the favorited state is the
    // heart's COLOUR: maroon when favorited, faint when not.
    testWidgets('a favorited row shows a maroon heart', (tester) async {
      await tester.pumpWidget(host(cardFrom(bundt, favorite: true), 800));
      await tester.pump();
      expect(find.byIcon(FLucideIcons.heart), findsOneWidget);
      final heart = tester.widget<Icon>(find.byIcon(FLucideIcons.heart));
      expect(heart.color, SaltColors.maroon);
    });

    testWidgets('a non-favorited row shows a faint heart', (tester) async {
      await tester.pumpWidget(host(cardFrom(bundt), 800));
      await tester.pump();
      expect(find.byIcon(FLucideIcons.heart), findsOneWidget);
      final heart = tester.widget<Icon>(find.byIcon(FLucideIcons.heart));
      expect(heart.color, SaltColors.muted.withValues(alpha: 0.3));
    });

    testWidgets('a wide row keeps the title and meta on one line', (
      tester,
    ) async {
      // The recipe's servings is the sole meta part here, so its text IS the
      // meta line; on a wide row it sits beside the title (same baseline).
      expect(bundt.servings, isNotNull);
      await tester.pumpWidget(host(cardFrom(bundt), 800));
      await tester.pump();
      final titleY = tester.getTopLeft(find.text(bundt.title)).dy;
      final metaY = tester.getTopLeft(find.text(bundt.servings!)).dy;
      expect(
        (titleY - metaY).abs() < 6,
        isTrue,
        reason: 'title $titleY and meta $metaY should share a line',
      );
    });

    testWidgets('a narrow row stacks the meta under the title', (tester) async {
      await tester.pumpWidget(host(cardFrom(bundt), 360));
      await tester.pump();
      final titleY = tester.getTopLeft(find.text(bundt.title)).dy;
      final metaY = tester.getTopLeft(find.text(bundt.servings!)).dy;
      expect(
        metaY > titleY + 6,
        isTrue,
        reason: 'meta $metaY should sit below title $titleY when narrow',
      );
    });

    testWidgets('the thumbnail decodes at thumbnail size, not full res', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(cardFrom(bundt, heroImage: '/images/atk/hero.jpg'), 800),
      );
      await tester.pump();
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<ResizeImage>());
      final resize = image.image as ResizeImage;
      expect(resize.width, isNotNull);
      expect(
        resize.width! <= 256 && resize.width! >= 64,
        isTrue,
        reason: 'target ${resize.width} must be thumbnail-sized',
      );
    });
  });
}
