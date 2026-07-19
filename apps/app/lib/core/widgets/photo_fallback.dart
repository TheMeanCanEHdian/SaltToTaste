import 'package:flutter/material.dart';

import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_logo.dart';

/// The placeholder shown when a recipe has no photo, or its image fails to
/// load: a rose-tinted panel with the rose-tinted brand mark. One definition
/// shared by the grid tiles and the detail hero so they never drift apart.
class PhotoFallback extends StatelessWidget {
  const PhotoFallback({super.key, this.iconSize = 40, this.showIcon = true});

  /// The width of the brand mark (the glyph is landscape, so its height follows
  /// from the logo's aspect ratio).
  final double iconSize;

  /// When false, renders just the tinted panel (used for a broken hero image
  /// where a large mark would look odd).
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SaltColors.rose.withValues(alpha: 0.17),
      alignment: Alignment.center,
      child: showIcon
          ? SaltLogoGlyph(color: SaltColors.rose, width: iconSize)
          : null,
    );
  }
}
