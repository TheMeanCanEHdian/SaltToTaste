import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/photo_fallback.dart';
import 'package:salt_app/core/widgets/salt_logo.dart';
import 'package:salt_app/core/widgets/tag_chip.dart';

/// Formats a total-minutes duration for the list row's meta: "45 min",
/// "1 hr", "1 hr 30 min". Whole hours drop the minutes.
String formatCookTime(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours hr' : '$hours hr $rest min';
}

/// A recipe as a horizontal row (the list layout): a small photo thumbnail,
/// the title, its meta (servings · calories · time · variations), tag chips,
/// and a favorite indicator.
///
/// Responsive per-row: on a wide row everything sits on one line with the
/// title taking the slack; when the row gets tight the meta + tags wrap under
/// the title. The favorite heart is an indicator only — favoriting happens on
/// the recipe page, same as the grid tile.
class RecipeRow extends StatefulWidget {
  const RecipeRow({super.key, required this.card, required this.onTap});

  final RecipeCard card;
  final VoidCallback onTap;

  /// Below this row width the single line can't hold title + meta + tags, so
  /// the meta + tags drop under the title.
  static const double _singleLineMin = 640;

  @override
  State<RecipeRow> createState() => _RecipeRowState();
}

class _RecipeRowState extends State<RecipeRow> {
  bool _hover = false;

  static List<String> _metaParts(RecipeCard card) {
    return [
      if (card.servingsText != null) card.servingsText!,
      if (card.caloriesPerServing != null)
        '${card.caloriesPerServing!.round()} kcal',
      if (card.totalMinutes != null) formatCookTime(card.totalMinutes!),
      if (card.hasVariations)
        card.variationCount == 1
            ? '+1 variation'
            : '+${card.variationCount} variations',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final meta = _metaParts(card);
    final tags = card.tags.take(3).toList();

    // One accessible name from the same facts shown visually, so a screen
    // reader announces the recipe in one go (the visual content is excluded).
    final labelParts = <String>[
      card.title,
      ...meta,
      if (tags.isNotEmpty) 'tagged ${tags.join(', ')}',
      if (card.favorite) 'favorited',
    ];

    return Semantics(
      button: true,
      label: labelParts.join(', '),
      child: Stack(
        children: [
          // The card surface. Hover eases the fill over 120ms (AnimatedContainer
          // tweens the colour — a plain Material won't, it only animates
          // shape/elevation). The border stays a constant hairline: a hover
          // outline read as an alarming red accent that the grid tiles don't
          // have, so the hover is the subtle fill change alone.
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
            decoration: BoxDecoration(
              color: _hover ? SaltColors.panel : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SaltColors.hairline),
            ),
            child: ExcludeSemantics(
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    constraints.maxWidth >= RecipeRow._singleLineMin
                    ? _wide(card, meta, tags)
                    : _stacked(card, meta, tags),
              ),
            ),
          ),
          // The tap surface sits ON TOP of the fill so its ink ripple is
          // actually visible — the ripple paints on the Material, so the
          // opaque fill below would hide it (this is why the grid tiles put
          // their InkWell in a Positioned.fill too; see recipe_tile.dart).
          // hoverColor stays transparent: the border + fill change above is the
          // hover feedback, and a grey overlay would stack on top of it.
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                onHover: (hovering) => setState(() => _hover = hovering),
                hoverColor: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Wide row: image · title · meta · tags · heart on one line. The meta font
  /// is a touch larger here than when stacked.
  ///
  /// The title is the sole [Expanded], so it absorbs all the slack and the meta
  /// / tags / heart are pushed to the right edge (right-justified). The title
  /// ellipsizes as it shrinks; the row only switches to single-line above the
  /// 640 width, where the fixed trailing items comfortably fit.
  Widget _wide(RecipeCard card, List<String> meta, List<String> tags) {
    final trailing = <Widget>[
      if (meta.isNotEmpty) _metaText(meta, fontSize: 14),
      if (tags.isNotEmpty)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tag in tags) ...[
              TagChip(tag),
              if (tag != tags.last) const SizedBox(width: 5),
            ],
          ],
        ),
      _heart(card),
    ];
    return Row(
      children: [
        _thumb(card),
        const SizedBox(width: 16),
        Expanded(child: _title(card)),
        const SizedBox(width: 16),
        for (final widget in trailing) ...[
          widget,
          if (widget != trailing.last) const SizedBox(width: 14),
        ],
      ],
    );
  }

  /// Narrow row: image · [ title / meta (line 2) / tags (line 3) ] · heart.
  Widget _stacked(RecipeCard card, List<String> meta, List<String> tags) {
    return Row(
      children: [
        _thumb(card),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _title(card),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 6),
                _metaText(meta),
              ],
              // Tags get their own line below the meta once details wrap.
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [for (final tag in tags) TagChip(tag)],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        _heart(card),
      ],
    );
  }

  // The title wraps to as many lines as it needs so it's always fully visible
  // (rows can then differ in height).
  Widget _title(RecipeCard card) => Text(
    card.title,
    style: const TextStyle(
      fontSize: 15.5,
      fontWeight: FontWeight.w600,
      color: SaltColors.ink,
      height: 1.25,
    ),
  );

  Widget _metaText(List<String> parts, {double fontSize = 12.5}) => Text(
    parts.join(' · '),
    style: TextStyle(fontSize: fontSize, color: SaltColors.muted),
  );

  // Lucide (forui's set) has no filled heart, so the favorited state reads from
  // the colour: maroon when favorited, faint when not.
  Widget _heart(RecipeCard card) => Icon(
    FLucideIcons.heart,
    size: 18,
    color: card.favorite
        ? SaltColors.maroon
        : SaltColors.muted.withValues(alpha: 0.3),
  );

  Widget _thumb(RecipeCard card) {
    final hero = card.heroImage;
    final content = hero == null
        ? const PhotoFallback(iconSize: 44)
        : Stack(
            fit: StackFit.expand,
            children: [
              const PhotoFallback(showIcon: false),
              Image.network(
                apiUrl(hero),
                fit: BoxFit.cover,
                // Decode at the thumbnail's own size, not the source's — the
                // library's photos are full-resolution originals (see
                // recipe_tile.dart). 64 logical px at the device ratio.
                cacheWidth:
                    (64 * MediaQuery.devicePixelRatioOf(context)).round().clamp(
                      64,
                      256,
                    ),
                errorBuilder: (_, __, ___) => const Center(
                  child: SaltLogoGlyph(color: SaltColors.rose, width: 44),
                ),
              ),
            ],
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(width: 64, height: 64, child: content),
    );
  }
}
