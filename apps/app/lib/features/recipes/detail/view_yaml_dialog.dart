import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';

/// Opens the admin-only read-only viewer for a recipe's canonical YAML
/// export (approved P9 mockup). The recipe is edited in the editor; this is
/// just for verifying the on-disk source of truth.
///
/// Takes the recipe **id**, not its slug: the export on disk and the file the
/// Download button serves are both named for the id, and this dialog names
/// the file it is showing.
Future<void> showViewYamlDialog(
  BuildContext context, {
  required String recipeId,
}) {
  final repository = context.read<RecipeRepository>();
  return showDialog<void>(
    context: context,
    builder: (_) => _ViewYamlDialog(repository: repository, recipeId: recipeId),
  );
}

class _ViewYamlDialog extends StatefulWidget {
  const _ViewYamlDialog({required this.repository, required this.recipeId});

  final RecipeRepository repository;
  final String recipeId;

  @override
  State<_ViewYamlDialog> createState() => _ViewYamlDialogState();
}

class _ViewYamlDialogState extends State<_ViewYamlDialog> {
  String? _yaml;
  String? _error;
  bool _copied = false;

  /// Must match the server's `Content-Disposition` (recipe_handlers.dart) and
  /// the canonical export on disk — both are named for the id.
  String get _fileName => '${widget.recipeId}.yaml';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final yaml = await widget.repository.recipeYamlText(widget.recipeId);
      if (mounted) {
        setState(() => _yaml = yaml);
      }
    } on RepositoryException catch (exception) {
      if (mounted) {
        setState(() => _error = exception.message);
      }
    }
  }

  Future<void> _copy() async {
    final yaml = _yaml;
    if (yaml == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: yaml));
    if (mounted) {
      setState(() => _copied = true);
    }
  }

  Future<void> _download() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(
      widget.repository.yamlUrl(widget.recipeId),
      mode: LaunchMode.platformDefault,
    ).catchError((_) => false);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't open the download.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: SaltColors.hairline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const Divider(height: 1, color: SaltColors.hairline),
            Flexible(child: _codeArea()),
            const Divider(height: 1, color: SaltColors.hairline),
            Container(
              width: double.infinity,
              color: SaltColors.pageBackground,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: const Text(
                'Read-only — recipes are edited in the editor; the YAML is the '
                'on-disk source of truth.',
                style: TextStyle(fontSize: 12.5, color: SaltColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: const Text(
                    'Recipe YAML',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: SaltColors.chipInk,
                    ),
                  ),
                ),
                Text(
                  _fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'RobotoMono',
                    color: SaltColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: SaltColors.maroon,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 36),
            ),
            onPressed: _yaml == null ? null : _copy,
            icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
            label: Text(_copied ? 'Copied' : 'Copy'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: SaltColors.ink,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 36),
            ),
            onPressed: _download,
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Download'),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 19),
          ),
        ],
      ),
    );
  }

  Widget _codeArea() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: SaltColors.errInk,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    final yaml = _yaml;
    if (yaml == null) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(
          child: CircularProgressIndicator(
            color: SaltColors.maroon,
            semanticsLabel: 'Loading YAML',
          ),
        ),
      );
    }
    final lines = yaml.split('\n');
    // Drop a single trailing empty line (files end in a newline).
    if (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return Container(
      color: SaltColors.panel,
      child: SingleChildScrollView(
        primary: false,
        child: SelectionArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Line-number gutter.
              Container(
                color: SaltColors.pageBackground,
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < lines.length; i++)
                      Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontFamily: 'RobotoMono',
                          fontSize: 12.5,
                          height: 1.6,
                          color: Color(0xFFB7ADA6),
                        ),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1, color: SaltColors.hairline),
              // Code, horizontally scrollable for long lines.
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in lines)
                          Text.rich(_highlight(line), softWrap: false),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _base = TextStyle(
    fontFamily: 'RobotoMono',
    fontSize: 12.5,
    height: 1.6,
    color: SaltColors.ink,
  );
  static const _muted = TextStyle(
    fontFamily: 'RobotoMono',
    fontSize: 12.5,
    height: 1.6,
    color: SaltColors.muted,
  );
  static const _key = TextStyle(
    fontFamily: 'RobotoMono',
    fontSize: 12.5,
    height: 1.6,
    color: SaltColors.chipInk,
  );

  /// Light, per-line YAML tint: keys in deep maroon, punctuation muted, the
  /// rest ink — comments and list dashes muted. Not a full parser.
  static final _lineRe = RegExp(r'^(\s*)(- )?([A-Za-z0-9_]+)(:)(.*)$');
  static TextSpan _highlight(String line) {
    if (line.trimLeft().startsWith('#')) {
      return TextSpan(text: line, style: _muted);
    }
    final match = _lineRe.firstMatch(line);
    if (match == null) {
      // A bare list item or continuation line.
      final dash = RegExp(r'^(\s*)(- )(.*)$').firstMatch(line);
      if (dash != null) {
        return TextSpan(
          children: [
            TextSpan(text: dash.group(1), style: _base),
            TextSpan(text: dash.group(2), style: _muted),
            TextSpan(text: dash.group(3), style: _base),
          ],
        );
      }
      return TextSpan(text: line, style: _base);
    }
    return TextSpan(
      children: [
        TextSpan(text: match.group(1), style: _base),
        if (match.group(2) != null)
          TextSpan(text: match.group(2), style: _muted),
        TextSpan(text: match.group(3), style: _key),
        TextSpan(text: match.group(4), style: _muted),
        TextSpan(text: match.group(5), style: _base),
      ],
    );
  }
}
