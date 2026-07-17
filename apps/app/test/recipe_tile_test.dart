import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/widgets/photo_fallback.dart';
import 'package:salt_app/core/widgets/recipe_tile.dart';
import 'package:salt_shared/salt_shared.dart';

import 'support/corpus.dart';

/// The grid tile's photo.
///
/// This had two confirmed defects that analyze, a green suite and a browser
/// screenshot all missed: tiles rendered FULLY TRANSPARENT for the whole
/// download on web (the placeholder was a loadingBuilder, and Flutter web
/// emits no chunk events, so it never fired and fell through to an
/// AnimatedOpacity sitting at 0), and a broken photo stacked two translucent
/// panels. Both are cheap to assert and were asserted by nothing.
void main() {
  Widget host(RecipeCard card) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          height: 240, // the grid's 4:3 tile
          child: RecipeTile(card: card, onTap: () {}),
        ),
      ),
    ),
  );

  RecipeCard cardFrom(Recipe recipe, {String? heroImage}) => RecipeCard(
    id: recipe.id,
    slug: recipe.slug,
    title: recipe.title,
    servingsText: recipe.servings,
    heroImage: heroImage,
  );

  group('tile photo', skip: skipIfNoCorpus, () {
    late Recipe bundt;

    setUpAll(() {
      bundt = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
    });

    testWidgets('a recipe with no photo shows the fallback panel', (
      tester,
    ) async {
      await tester.pumpWidget(host(cardFrom(bundt)));
      await tester.pump();
      expect(find.byType(PhotoFallback), findsOneWidget);
    });

    testWidgets('while a photo loads, the panel is painted underneath', (
      tester,
    ) async {
      // THE BUG: the placeholder was a loadingBuilder. On web `progress` is
      // always null (no chunk events), so it never rendered and the tile sat
      // at opacity 0 — blank, for the whole download. The panel must be in the
      // tree independently of any chunk event.
      await tester.pumpWidget(
        host(cardFrom(bundt, heroImage: '/images/atk/never-resolves.jpg')),
      );
      await tester.pump();

      expect(
        find.byType(PhotoFallback),
        findsOneWidget,
        reason: 'the tinted panel must paint under an unresolved photo',
      );
      expect(
        find.byType(Image),
        findsOneWidget,
        reason: 'the image is still in the tree, fading in over the panel',
      );
    });

    testWidgets('a photo is decoded at the tile size, not full resolution', (
      tester,
    ) async {
      // The library's photos are ~1819x1918 = 13MB each decoded; a 48-tile
      // page was ~640MB against Flutter's 100MB cache, so it thrashed.
      await tester.pumpWidget(
        host(cardFrom(bundt, heroImage: '/images/atk/hero.jpg')),
      );
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image;
      expect(
        provider,
        isA<ResizeImage>(),
        reason: 'cacheWidth must wrap the provider in a ResizeImage',
      );
      final resize = provider as ResizeImage;
      expect(
        resize.width,
        isNotNull,
        reason: 'a target width is what caps the decode',
      );
      expect(
        resize.width! <= 2048 && resize.width! >= 160,
        isTrue,
        reason: 'target ${resize.width} must be tile-sized, not source-sized',
      );
    });
  });
}
