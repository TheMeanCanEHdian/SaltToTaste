import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salt_shared/salt_shared.dart' show isValidTagColorHex;

import 'package:salt_app/core/api/tags_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/lucide_catalog.g.dart';
import 'package:salt_app/features/tags/tag_styles_cubit.dart';

/// The search-DSL query selecting recipes carrying [tag], with the tag text
/// escaped for the parser's quoted-phrase syntax (a tag containing `"` or
/// `\` must not break the query a chip tap runs).
String tagQuery(String tag) {
  final escaped = tag.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return 'tag:"$escaped"';
}

/// Parses a `#RRGGBB` string (the ONE shared rule — salt_shared's
/// [isValidTagColorHex], review S5), or null.
Color? colorFromHex(String? hex) {
  if (hex == null || !isValidTagColorHex(hex)) {
    return null;
  }
  return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

/// A tag chip in the SaltToTaste palette, styled per the admin's tag styles
/// (Lucide icon + colors) when one exists for [label].
///
/// [onCard] renders the higher-contrast variant used on photo tiles.
/// A non-null [onTap] makes the chip interactive (detail-page chips run a
/// `tag:` search). [styleOverride] bypasses the app-wide styles — the tag
/// editor uses it for its live preview.
class TagChip extends StatelessWidget {
  const TagChip(
    this.label, {
    super.key,
    this.onCard = false,
    this.onTap,
    this.styleOverride,
  });

  final String label;
  final bool onCard;
  final VoidCallback? onTap;
  final TagStyle? styleOverride;

  @override
  Widget build(BuildContext context) {
    // Styles are progressive enhancement: no cubit (tests) or no entry for
    // this tag both mean the default look.
    TagStyle? style = styleOverride;
    if (style == null) {
      try {
        style = context.select<TagStylesCubit, TagStyle?>(
          (cubit) => cubit.state[label],
        );
      } on Object {
        style = null;
      }
    }
    final ink = colorFromHex(style?.color) ?? SaltColors.chipInk;
    // The default (unstyled) chip is the same colour everywhere — the 'raspberry'
    // fill on the page and on a photo tile. On a tile any chip gets a soft
    // shadow to lift it off the photo (previously the default used a muddy
    // semi-transparent white instead).
    final fill = colorFromHex(style?.bgColor) ?? SaltColors.chip;
    final icon = style?.icon == null ? null : lucideIconsByName[style!.icon];

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(6),
        boxShadow: onCard
            ? const [BoxShadow(color: Colors.black26, blurRadius: 4)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: ink),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return chip;
    }
    // Interactive chips (tag search on the detail page) need a real tap
    // target: the ~22px pill fails WCAG 2.5.8 (24px), so pad the hit area
    // vertically — a little on desktop, more on touch — without changing the
    // visible pill. MergeSemantics folds the tag name + role into one node.
    final targetPad = isCompactWidth(context) ? 9.0 : 4.0;
    return MergeSemantics(
      child: Semantics(
        button: true,
        hint: 'Search this tag',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: targetPad),
            child: chip,
          ),
        ),
      ),
    );
  }
}
