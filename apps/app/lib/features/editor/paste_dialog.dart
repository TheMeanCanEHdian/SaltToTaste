import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/editor/editor_cubit.dart';

/// The bulk ingredient-entry dialog (approved P5 design): paste a block of
/// text, one ingredient per line; lines ending with a colon become group
/// headers. Each line previews through the same parser as the rows.
Future<void> showPasteDialog(BuildContext context) {
  final cubit = context.read<EditorCubit>();
  return showDialog<void>(
    context: context,
    builder: (context) => BlocProvider.value(
      value: cubit,
      child: const _PasteDialog(),
    ),
  );
}

class _PasteDialog extends StatefulWidget {
  const _PasteDialog();

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
      title: const Text('Paste ingredients'),
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
            TextField(
              controller: _controller,
              onChanged: _changed,
              minLines: 4,
              maxLines: 8,
              autofocus: true,
              style: const TextStyle(fontSize: 13.5),
              decoration: const InputDecoration(
                hintText: '6 ounces bittersweet chocolate, chopped coarse\n'
                    '¾ cup boiling water\nFor the glaze:',
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: SaltColors.maroon),
          onPressed: _lines.isEmpty
              ? null
              : () {
                  context.read<EditorCubit>().addPastedLines(_lines);
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
        chip: ('group', SaltColors.chipNeutral, SaltColors.muted),
        text: line.substring(0, line.length - 1).trim().toUpperCase(),
        bold: true,
        detail: null,
      );
    }
    final parsed = parseIngredientLine(line);
    final primary = parsed.amounts.where((a) => a.primary).firstOrNull ??
        parsed.amounts.firstOrNull;
    final detail = primary == null
        ? null
        : '${primary.measure.name} · ${primary.quantity}'
            '${primary.unit == null ? '' : ' ${primary.unit}'}';
    return _row(
      chip: switch (parsed.confidence) {
        ParseConfidence.parsed => (
            'parsed',
            SaltColors.okBg,
            SaltColors.okInk,
          ),
        ParseConfidence.check => (
            'check',
            SaltColors.warnBg,
            SaltColors.warnInk,
          ),
        ParseConfidence.none => (
            'no amount',
            SaltColors.chipNeutral,
            SaltColors.muted,
          ),
      },
      text: line,
      bold: false,
      detail: detail,
    );
  }

  Widget _row({
    required (String, Color, Color) chip,
    required String text,
    required bool bold,
    required String? detail,
  }) {
    final (label, background, foreground) = chip;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
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
              style:
                  const TextStyle(fontSize: 12, color: SaltColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}
