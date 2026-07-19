import 'package:flutter/material.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_dismiss_button.dart';

/// The inline search input surface: any committed [SearchChip]s, then a
/// growing text editor for the clause being typed, laid out on a single
/// horizontally-scrolling line (the nav bar's height is fixed, so the row
/// scrolls rather than wraps when chips overflow). The editor stays at the tail,
/// which is the only editable spot — chips are removed by their ✕ or by
/// Backspace, never edited in place.
///
/// Purely presentational: it owns no state. The host supplies the [controller]
/// (holding only the trailing text), the [chips] list, and the callbacks. Both
/// search surfaces (the desktop nav field and the mobile dialog) mount this so
/// they render identically.
class SearchChipBox extends StatelessWidget {
  const SearchChipBox({
    super.key,
    required this.chips,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.onRemoveChip,
    required this.onKeyEvent,
    required this.onSubmitted,
    this.autofocus = false,
    this.hintText,
    this.semanticLabel,
    this.prefix,
    this.suffix,
  });

  final List<SearchChip> chips;
  final TextEditingController controller;
  final FocusNode focusNode;

  /// Scrolls the chips + editor horizontally; the host keeps its tail visible.
  final ScrollController scrollController;

  /// A chip's ✕ was tapped.
  final void Function(int index) onRemoveChip;

  /// Key handling for the editor (Backspace-pops-a-chip, and on desktop the
  /// arrow/Escape autocomplete machinery), seen before the field's own.
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  /// Enter / the keyboard search action.
  final ValueChanged<String> onSubmitted;

  final bool autofocus;
  final String? hintText;
  final String? semanticLabel;

  /// Leading (search glyph) and trailing (help / submit) slots, fixed outside
  /// the scrolling area.
  final Widget? prefix;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final editor = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      // IntrinsicWidth so the field grows with its text (and the row can scroll
      // it into view); a plain TextField has no width in a scrollable row. The
      // hint is drawn as a separate overlay below, NOT via the decoration —
      // measured by IntrinsicWidth it would inflate the empty field to the full
      // hint width.
      child: IntrinsicWidth(
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: onKeyEvent,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            textInputAction: TextInputAction.search,
            onSubmitted: onSubmitted,
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(fontSize: 14, color: SaltColors.ink),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: EdgeInsets.symmetric(vertical: 9),
            ),
          ),
        ),
      ),
    );

    final scroller = SingleChildScrollView(
      controller: scrollController,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            SearchChipView(chip: chips[i], onRemove: () => onRemoveChip(i)),
            const SizedBox(width: 6),
          ],
          Semantics(label: semanticLabel, child: editor),
        ],
      ),
    );

    // A local transparent Material so the chips' ✕ InkWells ripple within the
    // field rather than on whatever Material sits far above (the maroon bar).
    return Material(
      type: MaterialType.transparency,
      child: Row(
        children: [
          if (prefix != null) prefix!,
          Expanded(
            // Tapping anywhere in the field — including the empty tail past the
            // (content-width) scroller — focuses the editor, matching a plain
            // search box. The GestureDetector wraps the full-width Stack, not
            // the scroller, which shrinks to its content.
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: focusNode.requestFocus,
              child: Stack(
                children: [
                  scroller,
                  // The hint overlays the empty editor (a plain field's hint),
                  // but sits outside IntrinsicWidth so its width never inflates
                  // the field. Listens to the controller so it clears the
                  // instant a character is typed, without the host rebuilding.
                  if (hintText != null && chips.isEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: controller,
                          builder: (context, value, _) {
                            if (value.text.isNotEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                hintText!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: SaltColors.muted,
                                  fontSize: 14,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (suffix != null) suffix!,
        ],
      ),
    );
  }
}

/// One committed clause as a dismissible chip: a muted `scope:` label, the
/// value, and a ✕. `tag:` chips get the rose tint (the app's tag colour); every
/// other scope is neutral grey. Mirrors `SaltBadge`'s dismiss affordance (radius
/// 6, a 24px ✕ target around an 18px circle).
class SearchChipView extends StatelessWidget {
  const SearchChipView({super.key, required this.chip, required this.onRemove});

  final SearchChip chip;
  final VoidCallback onRemove;

  static const double _radius = 6;

  @override
  Widget build(BuildContext context) {
    final tag = chip.isTag;
    final background = tag ? SaltColors.chip : SaltColors.chipNeutral;
    final valueInk = tag ? SaltColors.chipInk : SaltColors.ink;
    final scopeInk = tag
        ? SaltColors.chipInk.withValues(alpha: 0.62)
        : SaltColors.muted;
    final border = tag
        ? Color.lerp(SaltColors.chip, SaltColors.chipInk, 0.14)!
        : SaltColors.hairline;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${chip.scopeLabel}:',
              style: TextStyle(
                color: scopeInk,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                chip.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: valueInk,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
            ),
            SaltDismissButton(
              ink: valueInk,
              onTap: onRemove,
              semanticLabel: 'Remove ${chip.scopeLabel} ${chip.value}',
            ),
          ],
        ),
      ),
    );
  }
}
