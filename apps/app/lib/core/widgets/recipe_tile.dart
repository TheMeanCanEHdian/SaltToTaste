import 'package:flutter/material.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/photo_fallback.dart';
import 'package:salt_app/core/widgets/tag_chip.dart';

/// A grid tile: full-bleed photo with the title and tag chips overlaid on a
/// bottom gradient scrim, and a servings badge top-left (approved P2 design).
class RecipeTile extends StatelessWidget {
  const RecipeTile({super.key, required this.card, required this.onTap});

  final RecipeCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hero = card.heroImage;
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hero != null)
            Image.network(
              apiUrl(hero),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const PhotoFallback(),
            )
          else
            const PhotoFallback(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, SaltColors.cardScrim],
              ),
            ),
          ),
          if (card.servingsText != null)
            Positioned(
              top: 10,
              left: 11,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: SaltColors.cardBadge,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  card.servingsText!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
                      Shadow(blurRadius: 3, color: SaltColors.cardTitleShadow),
                    ],
                  ),
                ),
                if (card.tags.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      for (final tag in card.tags.take(3))
                        TagChip(tag, onCard: true),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap),
            ),
          ),
        ],
      ),
    );
  }
}
