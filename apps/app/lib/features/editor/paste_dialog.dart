import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_badge.dart';

/// The bulk ingredient-entry dialog (approved P5 design): paste a block of
/// text, one ingredient per line; lines ending with a colon become group
/// headers. Each line previews through the same parser as the rows.
///
/// [onSubmit] receives the accepted lines, so the same dialog serves the
/// top-level ingredient list and each subsection's.
Future<void> showPasteDialog(
  BuildContext context, {
  required void Function(List<String> lines) onSubmit,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _PasteDialog(onSubmit: onSubmit),
  );
}

class _PasteDialog extends StatefulWidget {
  const _PasteDialog({required this.onSubmit});

  final void Function(List<String> lines) onSubmit;

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  final TextEditingController _controller = TextEditingController();
  List<String> _lines = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    setState(() {
      _lines = [
        for (final line in value.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = _lines.where((line) => line.endsWith(':')).length;
    final ingredients = _lines.length - groups;
    return AlertDialog(
      title: Semantics(header: true, child: const Text('Paste ingredients')),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'One ingredient per line. Lines ending with a colon become '
              'group headers.',
              style: TextStyle(fontSize: 13, color: SaltColors.muted),
            ),
            const SizedBox(height: 10),
            Semantics(
              label: 'Ingredient list, one per line',
              child: TextField(
                controller: _controller,
                onChanged: _changed,
                minLines: 4,
                maxLines: 8,
                autofocus: true,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  hintText:
                      '6 ounces bittersweet chocolate, chopped coarse\n'
                      '¾ cup boiling water\nFor the glaze:',
                ),
              ),
            ),
            if (_lines.isNotEmpty) ...[
              const SizedBox(height: 12),
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: SaltColors.hairline),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final line in _lines) _PreviewRow(line: line),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        FButton(
          variant: FButtonVariant.outline,
          mainAxisSize: MainAxisSize.min,
          onPress: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FButton(
          mainAxisSize: MainAxisSize.min,
          onPress: _lines.isEmpty
              ? null
              : () {
                  widget.onSubmit(_lines);
                  Navigator.of(context).pop();
                },
          child: Text(
            groups == 0
                ? 'Add $ingredients ingredient${ingredients == 1 ? '' : 's'}'
                : 'Add $ingredients ingredient${ingredients == 1 ? '' : 's'} '
                      '+ $groups group${groups == 1 ? '' : 's'}',
          ),
        ),
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    if (line.endsWith(':')) {
      return _row(
        chip: ('group', SaltBadgeTone.neutral),
        text: line.substring(0, line.length - 1).trim().toUpperCase(),
        bold: true,
        detail: null,
      );
    }
    final parsed = parseIngredientLine(line);
    final primary =
        parsed.amounts.where((a) => a.primary).firstOrNull ??
        parsed.amounts.firstOrNull;
    final detail = primary == null
        ? null
        : '${primary.measure.name} · ${primary.quantity}'
              '${primary.unit == null ? '' : ' ${primary.unit}'}';
    return _row(
      chip: switch (parsed.confidence) {
        ParseConfidence.parsed => ('parsed', SaltBadgeTone.ok),
        ParseConfidence.check => ('check', SaltBadgeTone.warn),
        ParseConfidence.none => ('no amount', SaltBadgeTone.neutral),
      },
      text: line,
      bold: false,
      detail: detail,
    );
  }

  Widget _row({
    required (String, SaltBadgeTone) chip,
    required String text,
    required bool bold,
    required String? detail,
  }) {
    final (label, tone) = chip;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          SaltBadge(label, tone: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          if (detail != null) ...[
            const SizedBox(width: 10),
            Text(
              detail,
              style: const TextStyle(fontSize: 12, color: SaltColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}
