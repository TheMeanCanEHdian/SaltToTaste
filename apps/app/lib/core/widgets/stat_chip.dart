import 'package:flutter/material.dart';

import 'package:salt_app/core/theme/salt_theme.dart';

/// A count chip that doubles as a filter toggle — the big number over a small
/// label, selectable, with a greyed disabled state for an empty category.
///
/// Shared by the admin review screens (recipe data-quality and the nutrition
/// match queue) so both sets of filter chips read identically.
class StatChip extends StatelessWidget {
  const StatChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.emphasized = false,
    this.enabled = true,
  });

  final String label;
  final int count;
  final bool selected;

  /// Draws the number in maroon even when unselected (the "Need attention"
  /// total), without the selected fill.
  final bool emphasized;

  /// A disabled chip (a category with a count of 0) is greyed and not tappable.
  final bool enabled;
  final VoidCallback onTap;

  static const Color _disabled = Color(0xFFBCB3AC);

  @override
  Widget build(BuildContext context) {
    // Selection alone drives the fill; "Need attention" is only emphasised by
    // its maroon number, so it no longer looks selected when it isn't.
    final border = !enabled
        ? SaltColors.hairline
        : (selected ? SaltColors.maroon : SaltColors.hairline);
    final bg = !enabled
        ? const Color(0xFFFBF9F7)
        : (selected ? const Color(0xFFF7ECEC) : Colors.white);
    final numberColor = !enabled
        ? _disabled
        : (emphasized || selected ? SaltColors.maroon : SaltColors.ink);
    final labelColor = enabled ? SaltColors.muted : _disabled;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minWidth: 104),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border, width: selected ? 1.5 : 1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: numberColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 12, color: labelColor)),
            ],
          ),
        ),
      ),
    );
  }
}
