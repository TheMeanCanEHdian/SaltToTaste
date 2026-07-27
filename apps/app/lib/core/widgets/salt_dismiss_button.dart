import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// The ✕ that removes a chip or dismisses a pill — a 24×24 tap target
/// (WCAG 2.5.8) around a visible 18px tinted circle, in the host's [ink]
/// colour so it tracks the chip's theme.
///
/// Shared by [SaltBadge]'s removable-filter variant and the search box's
/// [SearchChipView] so the affordance can't drift. On hover the circle deepens
/// (with the click cursor the InkWell already sets), so it reads as a button
/// like the others rather than a static glyph.
class SaltDismissButton extends StatefulWidget {
  const SaltDismissButton({
    super.key,
    required this.ink,
    required this.onTap,
    required this.semanticLabel,
  });

  /// The icon colour and the circle's tint — passed the chip's foreground so a
  /// tag chip's ✕ is rose, a neutral chip's is grey.
  final Color ink;

  final VoidCallback onTap;

  /// Screen-reader label, e.g. 'Remove tag dessert'.
  final String semanticLabel;

  @override
  State<SaltDismissButton> createState() => _SaltDismissButtonState();
}

class _SaltDismissButtonState extends State<SaltDismissButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (hovering) => setState(() => _hover = hovering),
        // The hover feedback is the circle deepening below, not a square-ish
        // ink overlay behind the round chip.
        hoverColor: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.ink.withValues(alpha: _hover ? 0.30 : 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(FLucideIcons.x, size: 12, color: widget.ink),
            ),
          ),
        ),
      ),
    );
  }
}
