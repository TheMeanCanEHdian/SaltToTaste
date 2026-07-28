import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/theme/salt_theme.dart';

/// Shows a one-time secret (a new user's temporary password, or a freshly
/// minted API token) in a modal the admin must acknowledge. A dialog — rather
/// than a panel appended below the form — means the value can't be scrolled
/// past on a long list or silently replaced when several are created in a row.
///
/// [body] is the plain-language instruction; it already includes any extra
/// consequence text (e.g. the revoked-tokens note on a password reset).
Future<void> showSecretDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String value,
}) {
  return showFDialog<void>(
    context: context,
    // The value shown here is returned by the server exactly once. A barrier
    // tap or Esc would discard it as completely as scrolling past the old
    // inline panel did, so the only way out is the explicit "I've saved it".
    barrierDismissible: false,
    builder: (context, _, animation) => FDialog(
      animation: animation,
      builder: (context, style) =>
          _SecretDialogBody(title: title, body: body, value: value),
    ),
  );
}

class _SecretDialogBody extends StatefulWidget {
  const _SecretDialogBody({
    required this.title,
    required this.body,
    required this.value,
  });

  final String title;
  final String body;
  final String value;

  @override
  State<_SecretDialogBody> createState() => _SecretDialogBodyState();
}

class _SecretDialogBodyState extends State<_SecretDialogBody> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                FLucideIcons.circleCheck,
                color: Color(0xFF2C5A1E),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: Color(0xFF2C5A1E),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            widget.body,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: SaltColors.ink,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1EFEC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    widget.value,
                    style: const TextStyle(
                      fontFamily: 'RobotoMono',
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FButton(
                variant: FButtonVariant.outline,
                mainAxisSize: MainAxisSize.min,
                onPress: () async {
                  await Clipboard.setData(ClipboardData(text: widget.value));
                  if (mounted) {
                    setState(() => _copied = true);
                  }
                },
                prefix: const Icon(FLucideIcons.copy, size: 16),
                // liveRegion announces the "Copy" → "Copied" flip so a screen
                // reader confirms the copy instead of it being silent.
                child: Semantics(
                  liveRegion: true,
                  child: Text(_copied ? 'Copied' : 'Copy'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: FButton(
              mainAxisSize: MainAxisSize.min,
              onPress: () => Navigator.of(context).pop(),
              child: const Text("I've saved it"),
            ),
          ),
        ],
      ),
    );
  }
}

/// A yes/no confirmation modal. Returns true only when the confirm button is
/// pressed (false on Cancel, dismiss, or barrier tap). [destructive] paints the
/// confirm button in the theme's tinted danger style.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showFDialog<bool>(
    context: context,
    builder: (context, _, animation) => FDialog(
      animation: animation,
      builder: (context, style) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text(title, style: style.titleTextStyle),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message, style: style.bodyTextStyle),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: FButton(
                    variant: FButtonVariant.outline,
                    onPress: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FButton(
                    variant: destructive
                        ? FButtonVariant.destructive
                        : FButtonVariant.primary,
                    onPress: () => Navigator.of(context).pop(true),
                    child: Text(confirmLabel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}
