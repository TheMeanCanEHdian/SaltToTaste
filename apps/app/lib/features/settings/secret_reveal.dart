import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One-time secret reveal (temp passwords, new API tokens): green panel,
/// monospace value, copy button. Per the approved design the value is never
/// shown again after leaving the screen.
class SecretReveal extends StatefulWidget {
  const SecretReveal({super.key, required this.title, required this.value});

  final String title;
  final String value;

  @override
  State<SecretReveal> createState() => _SecretRevealState();
}

class _SecretRevealState extends State<SecretReveal> {
  bool _copied = false;

  @override
  void didUpdateWidget(SecretReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new secret in the same slot must not claim it was already copied.
    if (oldWidget.value != widget.value) {
      _copied = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F3E4),
        border: Border.all(color: const Color(0xFFCFE6C6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              color: Color(0xFF2C5A1E),
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: SelectableText(
                    widget.value,
                    style: const TextStyle(
                      fontFamily: 'RobotoMono',
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.value));
                  if (mounted) {
                    setState(() => _copied = true);
                  }
                },
                child: Text(_copied ? 'Copied' : 'Copy'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
