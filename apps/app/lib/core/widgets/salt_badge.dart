import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:salt_app/core/theme/salt_theme.dart';

/// Semantic colour tone for a [SaltBadge], mapped to the `SaltColors` token
/// pairs so every status pill tracks the theme.
enum SaltBadgeTone {
  neutral(SaltColors.chipNeutral, SaltColors.muted),
  ok(SaltColors.okBg, SaltColors.okInk),
  warn(SaltColors.warnBg, SaltColors.warnInk),
  err(SaltColors.errBg, SaltColors.errInk),
  info(SaltColors.infoBg, SaltColors.infoInk),
  brand(SaltColors.maroon, Color(0xFFFFFFFF));

  const SaltBadgeTone(this.background, this.foreground);

  /// The pill fill.
  final Color background;

  /// The label (and icon) colour.
  final Color foreground;
}

/// A small status pill in the SaltToTaste palette — token scopes, user roles,
/// log levels, parse confidence, nutrition status, and the like.
///
/// One standardised shape (radius, weight) for what used to be a dozen ad-hoc
/// `Container` pills. Built on Forui's [FBadge]: a fully-specified [FBadgeStyle]
/// replaces the variant base (`FBadgeStyle.call(_) => this`), so the badge
/// renders purely from the [tone] here.
///
/// Pass [onTap] to make it a button — it grows a subtle border, a trailing
/// chevron, and button semantics. [expand] then stretches it to the parent's
/// width with the chevron pushed to the far edge (the nutrition match badge's
/// mobile layout); FBadge shrink-wraps, so that one variant renders an
/// equivalent box rather than an FBadge.
///
/// Still NOT used for `TagChip` (per-tag admin colours), the numeric nav count
/// badge, or the photo-tile overlay badges — those carry behaviour/among a
/// palette this semantic API doesn't model.
class SaltBadge extends StatelessWidget {
  const SaltBadge(
    this.label, {
    super.key,
    this.tone = SaltBadgeTone.neutral,
    this.icon,
    this.onTap,
    this.semanticHint,
    this.expand = false,
  }) : assert(!expand || onTap != null, 'expand only applies to a tappable badge');

  final String label;
  final SaltBadgeTone tone;

  /// Optional leading icon (Lucide).
  final IconData? icon;

  /// When non-null the badge is a button: an [InkWell], a trailing chevron, a
  /// subtle border, and button semantics. Null = a plain, static label.
  final VoidCallback? onTap;

  /// Screen-reader hint for the tappable variant (e.g. 'Opens ingredient
  /// review').
  final String? semanticHint;

  /// Stretch to the parent's full width, chevron pushed to the far edge. Only
  /// valid with [onTap].
  final bool expand;

  /// The shared pill radius (matches `TagChip`).
  static const double radius = 6;

  @override
  Widget build(BuildContext context) {
    final ink = tone.foreground;
    final interactive = onTap != null;
    final labelStyle = TextStyle(
      color: ink,
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      height: 1.0,
    );

    Widget content({required bool spread}) => Row(
      mainAxisSize: spread ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: ink),
          const SizedBox(width: 5),
        ],
        // No explicit fontFamily: the label inherits the app font (OpenSans)
        // via the label style below / FBadge's DefaultTextStyle merge.
        if (spread) Flexible(child: Text(label)) else Text(label),
        if (interactive) ...[
          if (spread) const Spacer() else const SizedBox(width: 6),
          Icon(LucideIcons.chevronRight, size: 14, color: ink),
        ],
      ],
    );

    final decoration = BoxDecoration(
      color: tone.background,
      borderRadius: BorderRadius.circular(radius),
      border: interactive
          ? Border.all(color: Color.lerp(tone.background, ink, 0.22)!)
          : null,
    );
    final padding = interactive
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 9, vertical: 3);

    final Widget pill;
    if (expand) {
      // FBadge (IntrinsicWidth) can't stretch, so build the full-width variant
      // directly with the same decoration/padding/label style.
      pill = DecoratedBox(
        decoration: decoration,
        child: Padding(
          padding: padding,
          child: DefaultTextStyle.merge(style: labelStyle, child: content(spread: true)),
        ),
      );
    } else {
      pill = FBadge(
        style: FBadgeStyle(
          decoration: decoration,
          labelTextStyle: labelStyle,
          padding: padding,
        ),
        child: content(spread: false),
      );
    }

    if (!interactive) {
      return pill;
    }
    return MergeSemantics(
      child: Semantics(
        button: true,
        hint: semanticHint,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: pill,
        ),
      ),
    );
  }
}
