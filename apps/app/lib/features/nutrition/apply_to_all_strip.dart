import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';

/// The offer to push a just-made match decision out to every other recipe's
/// unreviewed line of the same ingredient, and — in its place once tapped —
/// the receipt of what that reached. Lives under the decided row in the
/// review sheet and above the footer in the admin queue's fix pane.
///
/// It is an offer, not a checkbox: the count for a newly picked food only
/// exists once the pick has landed, so it appears after the decision, sized
/// by the server's own count, and takes one tap.
class ApplyToAllStrip extends StatelessWidget {
  const ApplyToAllStrip({
    required this.offer,
    required this.applied,
    required this.applying,
    required this.onApply,
    required this.onDismiss,
    super.key,
  });

  /// The pending offer, or null once applied/dismissed.
  final ApplyOffer? offer;

  /// The receipt shown after an apply, until dismissed.
  final ApplyReceipt? applied;

  /// An apply is in flight (the button turns into the verb).
  final bool applying;
  final VoidCallback onApply;
  final VoidCallback onDismiss;

  static String _recipes(int n) => n == 1 ? '1 recipe' : '$n recipes';
  static String _lines(int n) => n == 1 ? '1 line' : '$n lines';

  @override
  Widget build(BuildContext context) {
    final receipt = applied;
    final pending = offer;
    if (receipt == null && pending == null) {
      return const SizedBox.shrink();
    }
    const bold = TextStyle(fontWeight: FontWeight.w700);
    final Widget icon;
    final Widget text;
    final List<Widget> buttons;
    String? footer;
    if (receipt != null) {
      final failed = receipt.failed;
      icon = Icon(
        failed > 0 ? FLucideIcons.triangleAlert : FLucideIcons.circleCheck,
        size: 17,
        color: failed > 0 ? SaltColors.errInk : SaltColors.maroon,
      );
      text = Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Applied to '),
            TextSpan(text: _recipes(receipt.recipes), style: bold),
            TextSpan(text: ' (${_lines(receipt.lines)}). '),
            if (failed == 0)
              const TextSpan(text: 'Their labels are recomputed.')
            else ...[
              TextSpan(text: _recipes(failed), style: bold),
              const TextSpan(
                text:
                    ' could not be recomputed — their lines are set, their '
                    'labels will refresh at the next compute. Details are in '
                    'the server log.',
              ),
            ],
          ],
        ),
        style: const TextStyle(fontSize: 13),
      );
      buttons = [
        FButton(
          variant: FButtonVariant.ghost,
          mainAxisSize: MainAxisSize.min,
          onPress: onDismiss,
          prefix: const Icon(FLucideIcons.x, size: 14),
          child: const Text('Dismiss'),
        ),
      ];
    } else {
      final o = pending!;
      icon = Icon(
        applying ? FLucideIcons.loaderCircle : FLucideIcons.copyCheck,
        size: 17,
        color: applying ? SaltColors.muted : SaltColors.maroon,
      );
      // The reach is food-agnostic: the others are not "on a different
      // match", they are the lines this decision has yet to reach — and the
      // unit that matters is lines (a recipe can hold several).
      final unit = _lines(o.lines);
      text = applying
          ? Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Applying to '),
                  TextSpan(text: unit, style: bold),
                  const TextSpan(text: '…'),
                ],
              ),
              style: const TextStyle(fontSize: 13),
            )
          : Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: o.lines == 1
                        ? '1 other line'
                        : '${o.lines} other lines',
                    style: bold,
                  ),
                  const TextSpan(text: ' of '),
                  TextSpan(text: o.label, style: bold),
                  TextSpan(text: ', in ${_recipes(o.others)}, '),
                  TextSpan(text: o.lines == 1 ? 'is' : 'are'),
                  const TextSpan(text: ' still waiting on this decision.'),
                ],
              ),
              style: const TextStyle(fontSize: 13),
            );
      buttons = [
        FButton(
          mainAxisSize: MainAxisSize.min,
          onPress: applying ? null : onApply,
          prefix: Icon(
            applying ? FLucideIcons.loaderCircle : FLucideIcons.copyCheck,
            size: 14,
          ),
          child: Text(
            applying ? 'Applying…' : 'Apply to $unit',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!applying)
          FButton(
            variant: FButtonVariant.ghost,
            mainAxisSize: MainAxisSize.min,
            onPress: onDismiss,
            child: const Text('Not now'),
          ),
      ];
      footer =
          'Sets this food on their unreviewed ${o.label} lines, each with '
          'its own amount, and recomputes their labels. Lines someone already '
          'decided are left alone. Reversible: pick a different food here and '
          'apply again.';
    }
    final actions = Wrap(spacing: 6, runSpacing: 6, children: buttons);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: SaltColors.hairline, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            // Inline on a wide sheet; on a phone the buttons take their own
            // line. A Wrap as a plain Row child gets unbounded width and
            // never wraps — it overflowed and clipped "Not now" off-screen.
            child: LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth < 560
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            icon,
                            const SizedBox(width: 12),
                            Expanded(child: text),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Align(alignment: Alignment.centerRight, child: actions),
                      ],
                    )
                  : Row(
                      children: [
                        icon,
                        const SizedBox(width: 12),
                        Expanded(child: text),
                        const SizedBox(width: 12),
                        actions,
                      ],
                    ),
            ),
          ),
          if (footer != null)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 7, 14, 9),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: SaltColors.hairline)),
              ),
              child: Text(
                footer,
                style: const TextStyle(fontSize: 12, color: SaltColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}
