import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/photo_fallback.dart';
import 'package:salt_app/core/widgets/salt_logo.dart';
import 'package:salt_app/core/widgets/tag_chip.dart';

/// A grid tile: full-bleed photo with the title and tag chips overlaid on a
/// bottom gradient scrim, a servings badge top-left (approved P2 design),
/// and — for favorites — a heart badge top-right (an indicator only; the
/// recipe page is where a favorite is toggled).
class _CardBadge extends StatelessWidget {
  const _CardBadge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: SaltColors.cardBadge,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A tile's hero photo, decoded at the size it is actually drawn.
///
/// The library's photos are full-resolution originals — a median 1819x1918,
/// which is 13 MB once decoded to RGBA. A 48-tile page is therefore ~640 MB of
/// bitmaps against Flutter's 100 MB image cache, so the cache evicts and
/// re-decodes constantly while scrolling. Decoding to the tile's own width
/// costs ~20 MB for the same page.
///
/// This only fixes the DECODE. Each original is still ~390 KB over the wire
/// (~19 MB per page); shrinking that needs the server to generate thumbnails,
/// which is a separate decision.
class _TileImage extends StatelessWidget {
  const _TileImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Bucket the target width so a few pixels of layout drift (a window
        // resize, a scrollbar appearing) doesn't invalidate the cache and
        // re-decode every visible tile.
        //
        // Width-only is right for these photos: under BoxFit.cover a source
        // taller than the 4:3 tile is width-limited, so the tile's width IS
        // the decoded width. Only 14 of the 1,242 library photos are wider
        // than 4:3, and the worst of them under-resolves by 1.18x — invisible,
        // and not worth decoding a source aspect we don't know yet to fix.
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final drawn = constraints.maxWidth * devicePixelRatio;
        final bucketed = (drawn / 160).ceil() * 160;
        return Stack(
          fit: StackFit.expand,
          children: [
            // The tinted panel sits UNDER the photo rather than instead of it.
            //
            // It used to be a loadingBuilder, which was the worst of both
            // worlds: Flutter web emits no ImageChunkEvent (its NetworkImage
            // builds a chunkless MultiFrameImageStreamCompleter), so
            // `progress` was always null, the placeholder never rendered, and
            // the builder fell through to the AnimatedOpacity sitting at
            // opacity 0 — leaving the tile FULLY TRANSPARENT for the whole
            // download. On IO it was the mirror image: chunks fire, so the
            // placeholder replaced the fade's subtree and the fade never ran.
            // Underneath, the panel just works on both.
            const PhotoFallback(showIcon: false),
            Image.network(
              url,
              fit: BoxFit.cover,
              cacheWidth: bucketed.clamp(160, 2048),
              // Fade in rather than pop: on a cold grid the photos arrive
              // scattered over a second or two, and 12 tiles snapping in at
              // random is more distracting than the fade. While frame is null
              // the image is transparent and the panel above shows through.
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded ||
                    MediaQuery.disableAnimationsOf(context)) {
                  return child;
                }
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: child,
                );
              },
              // Just the icon: the tinted panel is already underneath, and a
              // second PhotoFallback here would stack its translucent rose on
              // top of the first — a broken photo would read as a DARKER tile
              // than a photo-less one, which is exactly backwards.
              errorBuilder: (_, __, ___) => const Center(
                child: SaltLogoGlyph(color: SaltColors.rose, width: 88),
              ),
            ),
          ],
        );
      },
    );
  }
}

class RecipeTile extends StatelessWidget {
  const RecipeTile({super.key, required this.card, required this.onTap});

  final RecipeCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hero = card.heroImage;
    // The whole tile is one button; build its accessible name from the same
    // facts shown visually so a screen reader announces the recipe in one go.
    final labelParts = <String>[card.title];
    if (card.servingsText != null) {
      labelParts.add(card.servingsText!);
    }
    if (card.caloriesPerServing != null) {
      labelParts.add('${card.caloriesPerServing!.round()} kcal per serving');
    }
    if (card.tags.isNotEmpty) {
      labelParts.add('tagged ${card.tags.take(3).join(', ')}');
    }
    final tileLabel = labelParts.join(', ');

    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Visual content — excluded from semantics (the tap target below
          // carries the name, so the title isn't announced twice) and with
          // text scaling capped so the overlaid title can't blow out the
          // fixed-ratio tile at large OS text sizes.
          ExcludeSemantics(
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hero != null)
                    _TileImage(url: apiUrl(hero))
                  else
                    const PhotoFallback(iconSize: 88),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, SaltColors.cardScrim],
                      ),
                    ),
                  ),
                  if (card.servingsText != null ||
                      card.caloriesPerServing != null ||
                      card.hasVariations)
                    Positioned(
                      top: 10,
                      left: 11,
                      right: 44, // stay clear of the favorite heart
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          if (card.servingsText != null)
                            _CardBadge(card.servingsText!),
                          // Per-serving calories once nutrition is computed.
                          if (card.caloriesPerServing != null)
                            _CardBadge(
                              '${card.caloriesPerServing!.round()} kcal',
                            ),
                          // Variations only — a `component` subsection is a
                          // sub-recipe (the dough for the pie), not another
                          // way to make this one, so it earns no badge. The
                          // count is worth showing: "+3 variations" tells you
                          // how much more is in there, which a flag cannot.
                          if (card.hasVariations)
                            _CardBadge(
                              card.variationCount == 1
                                  ? '+1 variation'
                                  : '+${card.variationCount} variations',
                            ),
                        ],
                      ),
                    ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 11,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Tags sit ABOVE the title so the title stays anchored
                        // at the tile's bottom edge whether or not tags exist.
                        if (card.tags.isNotEmpty) ...[
                          Wrap(
                            spacing: 5,
                            runSpacing: 4,
                            children: [
                              for (final tag in card.tags.take(3))
                                TagChip(tag, onCard: true),
                            ],
                          ),
                          const SizedBox(height: 7),
                        ],
                        Text(
                          card.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            height: 1.22,
                            shadows: [
                              Shadow(
                                blurRadius: 3,
                                color: SaltColors.cardTitleShadow,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: Semantics(
                button: true,
                label: tileLabel,
                child: InkWell(onTap: onTap),
              ),
            ),
          ),
          if (card.favorite)
            Positioned(
              top: 8,
              right: 8,
              // A non-interactive badge: it marks the card as a favorite;
              // favoriting/unfavoriting happens on the recipe page.
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(7),
                child: Semantics(
                  label: 'Favorited',
                  child: const Icon(
                    FLucideIcons.heart,
                    size: 15,
                    color: SaltColors.maroon,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
