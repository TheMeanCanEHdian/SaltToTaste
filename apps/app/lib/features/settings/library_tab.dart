import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:salt_app/core/api/library_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/async_view.dart';
import 'package:salt_app/features/settings/settings_page.dart';

/// Status colors for scan-report lines and backup actions, matching the
/// approved mockup (docs/mockups/p5-editor.html, section 4).
const _okInk = SaltColors.okInk;
const _okBg = SaltColors.okBg;
const _warnInk = SaltColors.warnInk;
const _warnBg = SaltColors.warnBg;
const _errInk = SaltColors.errInk;
const _errBg = SaltColors.errBg;

/// Library tab (admin): YAML-library reconciliation (rescan + last scan
/// report) and backup management.
class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key});

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  LibraryScanReport? _report;
  bool _reportLoaded = false;
  String? _scanError;
  bool _scanning = false;

  List<BackupItem>? _backups;
  String? _backupsError;
  bool _backupBusy = false;
  bool _creatingBackup = false;
  bool _includePhotos = false;

  @override
  void initState() {
    super.initState();
    _loadScan();
    _loadBackups();
  }

  Future<void> _loadScan() async {
    setState(() => _scanError = null);
    try {
      final report = await context.read<LibraryRepository>().lastScan();
      if (mounted) {
        setState(() {
          _report = report;
          _reportLoaded = true;
        });
      }
    } on RepositoryException catch (exception) {
      if (mounted) {
        setState(() => _scanError = exception.message);
      }
    }
  }

  Future<void> _rescan() async {
    setState(() {
      _scanning = true;
      _scanError = null;
    });
    try {
      final report = await context.read<LibraryRepository>().rescan();
      if (mounted) {
        setState(() {
          _report = report;
          _reportLoaded = true;
        });
      }
    } on RepositoryException catch (exception) {
      if (mounted) {
        setState(() => _scanError = exception.message);
      }
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  Future<void> _loadBackups() async {
    setState(() => _backupsError = null);
    try {
      final backups = await context.read<LibraryRepository>().listBackups();
      if (mounted) {
        setState(() => _backups = backups);
      }
    } on RepositoryException catch (exception) {
      if (mounted) {
        setState(() => _backupsError = exception.message);
      }
    }
  }

  Future<void> _createBackup() async {
    setState(() {
      _creatingBackup = true;
      _backupBusy = true;
      _backupsError = null;
    });
    try {
      await context.read<LibraryRepository>().createBackup(
        includeImages: _includePhotos,
      );
      if (!mounted) {
        return;
      }
      await _loadBackups();
    } on RepositoryException catch (exception) {
      if (mounted) {
        setState(() => _backupsError = exception.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _creatingBackup = false;
          _backupBusy = false;
        });
      }
    }
  }

  Future<void> _download(BackupItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final url = context.read<LibraryRepository>().downloadUrl(item.name);
    var ok = false;
    try {
      ok = await launchUrl(url, mode: LaunchMode.platformDefault);
    } on Exception {
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't open the download.")),
      );
    }
  }

  Future<void> _delete(BackupItem item) async {
    final repository = context.read<LibraryRepository>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete backup?'),
        content: Text('Delete backup ${item.name}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _errInk),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _backupBusy = true;
      _backupsError = null;
    });
    try {
      await repository.deleteBackup(item.name);
      if (!mounted) {
        return;
      }
      await _loadBackups();
    } on RepositoryException catch (exception) {
      if (mounted) {
        setState(() => _backupsError = exception.message);
      }
    } finally {
      if (mounted) {
        setState(() => _backupBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PaneTitle(
          'Library',
          description:
              "Your recipes live as YAML files in the server's "
              'library — safe to edit by hand or sync elsewhere.',
        ),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: _scanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: SaltColors.maroon,
                      ),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: const Text('Rescan library'),
              onPressed: _scanning ? null : _rescan,
            ),
            if (_report != null && _report!.startedAt.isNotEmpty)
              Text(
                'Last scan: ${_prettyTimestamp(_report!.startedAt)}',
                style: const TextStyle(fontSize: 12.5, color: SaltColors.muted),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (!_reportLoaded && _scanError != null)
          ErrorView(message: _scanError!, onRetry: _loadScan)
        else if (!_reportLoaded)
          const LoadingView()
        else ...[
          ..._scanLines(_report),
          if (_scanError != null)
            _ScanLine(
              icon: Icons.error_outline,
              ink: _errInk,
              background: _errBg,
              lead: 'Scan failed',
              rest: ' — $_scanError',
            ),
        ],
        const SizedBox(height: 28),
        Semantics(
          header: true,
          child: const Text(
            'Backups',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: _creatingBackup
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: SaltColors.maroon,
                      ),
                    )
                  : const Icon(Icons.archive_outlined, size: 18),
              label: const Text('Back up now'),
              onPressed: _backupBusy ? null : _createBackup,
            ),
            Tooltip(
              message: 'Full copy — much larger',
              // MergeSemantics + an InkWell over the whole row give the box a
              // real accessible name ("Include photos") and a full tap target
              // that the label toggles, not a bare 32px checkbox.
              child: MergeSemantics(
                child: InkWell(
                  onTap: _backupBusy
                      ? null
                      : () => setState(() => _includePhotos = !_includePhotos),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _includePhotos,
                          activeColor: SaltColors.maroon,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onChanged: _backupBusy
                              ? null
                              : (value) => setState(
                                  () => _includePhotos = value ?? false,
                                ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Include photos',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Text(
              'Automatic before deletes and imports · keeps the last 14',
              style: TextStyle(fontSize: 12.5, color: SaltColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_backups == null && _backupsError != null)
          ErrorView(message: _backupsError!, onRetry: _loadBackups)
        else if (_backups == null)
          const LoadingView()
        else ...[
          if (_backupsError != null)
            _ScanLine(
              icon: Icons.error_outline,
              ink: _errInk,
              background: _errBg,
              lead: 'Backup action failed',
              rest: ' — $_backupsError',
            ),
          if (_backups!.isEmpty)
            const Text(
              'No backups yet.',
              style: TextStyle(fontSize: 13, color: SaltColors.muted),
            )
          else ...[
            const _BackupHeaderRow(),
            for (final item in _backups!)
              _BackupRow(
                item: item,
                busy: _backupBusy,
                onDownload: () => _download(item),
                onDelete: () => _delete(item),
              ),
          ],
        ],
      ],
    );
  }

  List<Widget> _scanLines(LibraryScanReport? report) {
    if (report == null) {
      return const [
        Text(
          'No scan has run yet.',
          style: TextStyle(fontSize: 13, color: SaltColors.muted),
        ),
      ];
    }
    if (report.clean) {
      return [
        _ScanLine(
          icon: Icons.check_circle_outline,
          ink: _okInk,
          background: _okBg,
          lead: 'Everything in sync',
          rest:
              ' — ${report.filesSeen} '
              '${report.filesSeen == 1 ? 'file' : 'files'} checked.',
        ),
      ];
    }
    return [
      if (report.updatedFromDisk.isNotEmpty)
        _ScanLine(
          icon: Icons.check_circle_outline,
          ink: _okInk,
          background: _okBg,
          lead:
              '${_count(report.updatedFromDisk.length, 'file', 'files')} '
              'updated from disk',
          rest: ' — ${_idList(report.updatedFromDisk)}',
        ),
      if (report.added.isNotEmpty)
        _ScanLine(
          icon: Icons.check_circle_outline,
          ink: _okInk,
          background: _okBg,
          lead:
              '${_count(report.added.length, 'recipe', 'recipes')} '
              'imported from new files',
          rest: ' — ${_idList(report.added)}',
        ),
      if (report.reExported.isNotEmpty)
        _ScanLine(
          icon: Icons.check_circle_outline,
          ink: _okInk,
          background: _okBg,
          lead:
              '${_count(report.reExported.length, 'missing export', 'missing exports')} '
              'rewritten from the database',
          rest: ' — ${_idList(report.reExported)}',
        ),
      for (final entry in report.skipped)
        _ScanLine(
          icon: Icons.error_outline,
          ink: _errInk,
          background: _errBg,
          lead: entry.file,
          rest: ' — ${entry.reason}',
        ),
      for (final file in report.conflictFiles)
        _ScanLine(
          icon: Icons.warning_amber,
          ink: _warnInk,
          background: _warnBg,
          lead: 'Conflict copy awaiting review: ',
          rest: file,
        ),
      if (report.conflictFiles.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Text(
            'A file edited both on disk and in the app keeps the app '
            'version; the disk edit is saved next to it as a '
            '.conflict-<timestamp>.yaml copy until you review it.',
            style: TextStyle(fontSize: 12.5, color: SaltColors.muted),
          ),
        ),
    ];
  }
}

/// "3 files", "1 recipe", ... — count plus singular/plural noun.
String _count(int n, String singular, String plural) =>
    '$n ${n == 1 ? singular : plural}';

/// First few ids, comma-joined, capped at four with an ellipsis.
String _idList(List<String> ids) {
  const cap = 4;
  final shown = ids.take(cap).join(', ');
  return ids.length > cap ? '$shown, …' : shown;
}

/// Renders a raw server timestamp readably without a date-format package:
/// "2026-07-15T09:14:03.221Z" -> "2026-07-15 09:14:03".
String _prettyTimestamp(String raw) {
  var pretty = raw.trim().replaceFirst('T', ' ');
  final dot = pretty.indexOf('.');
  if (dot != -1) {
    pretty = pretty.substring(0, dot);
  }
  if (pretty.endsWith('Z')) {
    pretty = pretty.substring(0, pretty.length - 1);
  }
  return pretty.trim();
}

/// `salt-backup-<stamp>[-n]-<trigger>.tar.gz` -> the trailing trigger word.
String _triggerFromName(String name) {
  const suffix = '.tar.gz';
  if (!name.endsWith(suffix)) {
    return '—';
  }
  final stem = name.substring(0, name.length - suffix.length);
  final dash = stem.lastIndexOf('-');
  if (dash == -1 || dash == stem.length - 1) {
    return '—';
  }
  return stem.substring(dash + 1);
}

/// Human-readable size with one decimal: "48.2 MB".
String _humanSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}

/// One tinted scan-report line: icon + bold lead + regular rest.
class _ScanLine extends StatelessWidget {
  const _ScanLine({
    required this.icon,
    required this.ink,
    required this.background,
    required this.lead,
    this.rest,
  });

  final IconData icon;
  final Color ink;
  final Color background;
  final String lead;
  final String? rest;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: ink),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: lead,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (rest != null) TextSpan(text: rest),
                ],
              ),
              style: TextStyle(fontSize: 13, color: ink, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupHeaderRow extends StatelessWidget {
  const _BackupHeaderRow();

  static const _style = TextStyle(
    fontSize: 11,
    letterSpacing: 1.1,
    fontWeight: FontWeight.w700,
    color: SaltColors.muted,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SaltColors.hairline)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 5, child: Text('WHEN', style: _style)),
          Expanded(flex: 3, child: Text('TRIGGER', style: _style)),
          Expanded(
            flex: 2,
            child: Text('SIZE', style: _style, textAlign: TextAlign.right),
          ),
          // Space over the actions column.
          SizedBox(width: 172),
        ],
      ),
    );
  }
}

class _BackupRow extends StatelessWidget {
  const _BackupRow({
    required this.item,
    required this.busy,
    required this.onDownload,
    required this.onDelete,
  });

  final BackupItem item;
  final bool busy;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SaltColors.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Tooltip(
              message: item.name,
              child: Text(
                _prettyTimestamp(item.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _triggerFromName(item.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: SaltColors.muted),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _humanSize(item.sizeBytes),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, color: SaltColors.muted),
            ),
          ),
          _SmallAction(label: 'Download', onTap: busy ? null : onDownload),
          _SmallAction(
            label: 'Delete',
            danger: true,
            onTap: busy ? null : onDelete,
          ),
        ],
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.label, this.onTap, this.danger = false});

  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: danger ? _errInk : SaltColors.ink,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          // Compact on desktop, a 48px touch target on narrow/touch widths.
          minimumSize: denseActionMinSize(context),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 12.5, fontFamily: 'OpenSans'),
        ),
        onPressed: onTap,
        child: Text(label),
      ),
    );
  }
}
