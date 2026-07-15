import 'package:flutter/material.dart';

import 'package:salt_app/core/theme/salt_theme.dart';

/// A tag chip in the SaltToTaste palette.
///
/// [onCard] renders the higher-contrast variant used on photo tiles.
class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key, this.onCard = false});

  final String label;
  final bool onCard;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: onCard ? Colors.white.withValues(alpha: 0.92) : SaltColors.chip,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: SaltColors.chipInk,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
