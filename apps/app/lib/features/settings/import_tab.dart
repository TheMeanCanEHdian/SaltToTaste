import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/api/import_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/async_view.dart';
import 'package:salt_app/features/settings/settings_page.dart';

/// The mockup's 560px content cap.
const double _sectionMaxWidth = 560;

const TextStyle _sectionHeading = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w700,
);
const TextStyle _hintStyle = TextStyle(fontSize: 12, color: SaltColors.muted);

/// A running import survives this widget: the job id + the candidate path
/// that started it let a remounted tab re-attach to the live job instead
/// of showing buttons that would only 409 (there is no server job-list
/// endpoint to rediscover it from).
int? _activeImportJobId;
String? _activeImportPath;

/// Import tab (admin): detected source folders from the server's import
/// directory, each importable with live job progress.
/// Design: docs/mockups/p7-import.html.
class ImportTab extends StatefulWidget {
  const ImportTab({super.key});

  @override
  State<ImportTab> createState() => _ImportTabState();
}

class _ImportTabState extends State<ImportTab> {
  bool _loaded = false;
  String? _loadError;
  ImportCandidates? _candidates;

  // The import job (one at a time).
  bool _starting = false;
  String? _startedPath; // the candidate.path whose row is pinned
  ImportJob? _job;
  String? _jobError;
  Timer? _pollTimer;
  bool _pollInFlight = false;
  int _pollFailures = 0;
  bool _logExpanded = false;

  bool get _importRunning => _starting || (_job?.running ?? false);

  @override
  void initState() {
    super.initState();
    _loadCandidates();
    // Re-attach to a job started before a tab switch.
    final activeJob = _activeImportJobId;
    if (activeJob != null) {
      _startedPath = _activeImportPath;
      _watchJob(activeJob);
      Future<void>.microtask(() {
        if (mounted) {
          _poll(context.read<ImportRepository>(), activeJob);
        }
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    setState(() {
      _loadError = null;
      if (!_importRunning) {
        // A finished job's summary clears when the list is rescanned.
        _job = null;
        _startedPath = null;
        _jobError = null;
      }
    });
    try {
      final candidates = await context.read<ImportRepository>().candidates();
      if (mounted) {
        setState(() {
          _candidates = candidates;
          _loaded = true;
        });
      }
    } on RepositoryException catch (exception) {
      if (mounted) {
        setState(() {
          _loadError = exception.message;
          _loaded = true;
        });
      }
    }
  }

  Future<void> _startImport(String path) async {
    final repository = context.read<ImportRepository>();
    setState(() {
      _starting = true;
      _startedPath = path;
      _job = null;
      _jobError = null;
      _logExpanded = false;
    });
    try {
      final jobId = await repository.start(path);
      // Record the job globally BEFORE the mounted check: if this widget
      // was disposed mid-request (a tab switch), a later mount must still
      // re-attach rather than orphan a running server-side job.
      _activeImportJobId = jobId;
      _activeImportPath = path;
      if (!mounted) {
        return;
      }
      _watchJob(jobId);
      await _poll(repository, jobId);
    } on RepositoryException catch (exception) {
      // Includes the 409 "already running" case (its message comes
      // through the conflict error code).
      if (mounted) {
        setState(() => _jobError = exception.message);
      }
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  void _watchJob(int jobId) {
    _pollFailures = 0;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _poll(context.read<ImportRepository>(), jobId),
    );
  }

  Future<void> _poll(ImportRepository repository, int jobId) async {
    if (_pollInFlight) {
      return;
    }
    _pollInFlight = true;
    try {
      final job = await repository.job(jobId);
      if (!job.running) {
        // Clear the re-attach globals on the terminal poll even if we are
        // unmounting, so a later mount doesn't resurrect this finished
        // job's summary (or spin up a stray poll timer).
        _activeImportJobId = null;
        _activeImportPath = null;
      }
      if (!mounted) {
        return;
      }
      _pollFailures = 0;
      setState(() {
        _job = job;
        _jobError = null;
      });
      if (!job.running) {
        _pollTimer?.cancel();
        _pollTimer = null;
      }
    } on RepositoryException catch (exception) {
      // A large import will see a transient blip; keep polling through a
      // few consecutive failures (the job is untouched server-side).
      // Past the threshold, give up: a persistent error (e.g. the session
      // expired) would otherwise poll forever and re-fail on every remount.
      _pollFailures += 1;
      if (_pollFailures < 8) {
        if (_pollFailures >= 3 && mounted) {
          setState(
            () => _jobError =
                'Progress updates are failing (${exception.message}) — '
                'the import keeps running on the server; retrying…',
          );
        }
        return;
      }
      _pollTimer?.cancel();
      _pollTimer = null;
      _activeImportJobId = null;
      _activeImportPath = null;
      if (mounted) {
        setState(
          () => _jobError =
              "Lost track of the import (${exception.message}). It may still "
              'be running on the server — Refresh to check.',
        );
      }
    } finally {
      _pollInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PaneTitle(
          'Import',
          description:
              'Bring existing recipe folders into the library — formats are '
              'detected automatically, and re-running an import is always '
              'safe.',
        ),
        Row(
          children: [
            Semantics(
              header: true,
              child: const Text('Source folders', style: _sectionHeading),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _importRunning ? null : _loadCandidates,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // A retry/Refresh clears _loadError synchronously while the fetch
        // is still in flight; gate on _candidates so _body() never runs
        // with a null list.
        if (_loadError != null && _candidates == null)
          ErrorView(message: _loadError!, onRetry: _loadCandidates)
        else if (!_loaded || _candidates == null)
          const LoadingView()
        else
          _body(),
      ],
    );
  }

  Widget _body() {
    final candidates = _candidates!;
    if (candidates.items.isEmpty) {
      return _EmptyState(
        importDir: candidates.importDir,
        onRefresh: _loadCandidates,
      );
    }
    // If a job is active for a folder that's no longer in the list (a
    // rescan dropped it mid-run), keep its progress visible with a
    // synthetic pinned row instead of losing it entirely.
    final hasPinnedRow =
        _startedPath != null &&
        candidates.items.any((c) => c.path == _startedPath);
    final orphanRow = !hasPinnedRow && _startedPath != null && _job != null
        ? ImportCandidate(
            path: _startedPath!,
            kind: _job!.legacy ? 'legacy' : 'v1',
            fileCount: _job!.total,
          )
        : null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _sectionMaxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final candidate in [
            if (orphanRow != null) orphanRow,
            ...candidates.items,
          ]) ...[
            _SourceRow(
              candidate: candidate,
              pinned: candidate.path == _startedPath,
              starting: _starting && candidate.path == _startedPath,
              job: candidate.path == _startedPath ? _job : null,
              jobError: candidate.path == _startedPath ? _jobError : null,
              anyRunning: _importRunning,
              logExpanded: _logExpanded,
              onImport: () => _startImport(candidate.path),
              onToggleLog: () => setState(() => _logExpanded = !_logExpanded),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 14),
          Semantics(
            header: true,
            child: const Text(
              'Where these folders come from',
              style: _sectionHeading,
            ),
          ),
          const SizedBox(height: 10),
          _Explainer(importDir: candidates.importDir),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.candidate,
    required this.pinned,
    required this.starting,
    required this.job,
    required this.jobError,
    required this.anyRunning,
    required this.logExpanded,
    required this.onImport,
    required this.onToggleLog,
  });

  final ImportCandidate candidate;
  final bool pinned;
  final bool starting;
  final ImportJob? job;
  final String? jobError;
  final bool anyRunning;
  final bool logExpanded;
  final VoidCallback onImport;
  final VoidCallback onToggleLog;

  bool get _running => starting || (job?.running ?? false);
  bool get _terminal => !starting && job != null && !job!.running;
  // Dim non-pinned rows while any import is running.
  bool get _dimmed => anyRunning && !pinned;

  @override
  Widget build(BuildContext context) {
    // Below the settings breakpoint the button drops full-width under the
    // name so a long folder name isn't squeezed out (approved P7 mobile
    // layout).
    final narrow =
        MediaQuery.sizeOf(context).width < Breakpoints.detailTwoColumn;
    final trailing = _trailing();
    return Opacity(
      opacity: _dimmed ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: _running ? SaltColors.maroon : SaltColors.hairline,
            width: _running ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1, right: 11),
                  child: Icon(
                    Icons.folder_outlined,
                    size: 18,
                    color: _running ? SaltColors.maroon : SaltColors.muted,
                  ),
                ),
                Expanded(child: _details(context)),
                if (!narrow && trailing != null) ...[
                  const SizedBox(width: 10),
                  trailing,
                ],
              ],
            ),
            if (narrow && trailing != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(width: double.infinity, child: trailing),
              ),
            if (_running) _progress(),
            if (_terminal) _summary(context),
            if (jobError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  jobError!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: SaltColors.errInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _details(BuildContext context) {
    final label = candidate.kind == 'legacy' ? '_recipes/' : 'recipes/*.yaml';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                _displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _KindChip(kind: candidate.kind),
          ],
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 12, color: SaltColors.muted),
            children: [
              TextSpan(
                text:
                    '${_thousands(candidate.fileCount)} '
                    '${candidate.fileCount == 1 ? 'recipe file' : 'recipe files'}'
                    ' · ',
              ),
              // The layout marker reads as a path fragment — mono, like the
              // mockup's <code> chip.
              TextSpan(
                text: label,
                style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String get _displayName =>
      candidate.path == '.' ? 'Import directory (root)' : candidate.path;

  /// The row's trailing control: the Import button when idle, an
  /// "Importing…" indicator while running, or null in the terminal state
  /// (the summary replaces it below).
  Widget? _trailing() {
    if (_running) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: SaltColors.maroon,
            ),
          ),
          SizedBox(width: 6),
          Text(
            'Importing…',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: SaltColors.maroon,
            ),
          ),
        ],
      );
    }
    if (_terminal) {
      return null;
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: SaltColors.maroon,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        textStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          fontFamily: 'OpenSans',
        ),
      ),
      onPressed: anyRunning ? null : onImport,
      icon: const Icon(Icons.drive_folder_upload_outlined, size: 15),
      label: const Text('Import'),
    );
  }

  Widget _progress() {
    final job = this.job;
    final value = (job != null && job.total > 0) ? job.done / job.total : null;
    final done = job?.done ?? 0;
    final total = job?.total ?? candidate.fileCount;
    final failed = job?.failed ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 10,
              color: SaltColors.maroon,
              backgroundColor: SaltColors.chipNeutral,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_thousands(done)} / ${_thousands(total)} files'
            '${failed > 0 ? ' · ${_thousands(failed)} failed' : ''}',
            style: const TextStyle(fontSize: 12.5, color: SaltColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final job = this.job!;
    final failedJob = job.status != 'done';
    final ink = failedJob ? SaltColors.errInk : SaltColors.okInk;
    final showLog = job.log.isNotEmpty;
    final String text;
    if (failedJob) {
      text =
          'Import failed after ${_thousands(job.done)} of '
          '${_thousands(job.total)} files';
    } else {
      text =
          '${_thousands(job.total)} files: '
          '${_thousands(job.imported)} imported, '
          '${_thousands(job.updated)} updated, '
          '${_thousands(job.skipped)} skipped, '
          '${_thousands(job.failed)} failed';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                failedJob ? Icons.error_outline : Icons.check_circle_outline,
                size: 16,
                color: ink,
              ),
              Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              if (showLog)
                MergeSemantics(
                  child: Semantics(
                    button: true,
                    child: InkWell(
                      onTap: onToggleLog,
                      child: Text(
                        // A failed run's log is errors, not just warnings.
                        logExpanded
                            ? (failedJob ? 'hide log' : 'hide warnings')
                            : (failedJob
                                  ? 'see log'
                                  : 'see warnings (${job.log.length})'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: ink,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (showLog && logExpanded) _LogBox(lines: job.log),
          const SizedBox(height: 6),
          const Text(
            'Re-running is safe: unchanged files skip, changed files update '
            '(the current YAML is backed up first), new files import.',
            style: _hintStyle,
          ),
        ],
      ),
    );
  }
}

/// The per-file warning log: a 200px scroll-capped mono panel (the
/// Nutrition tab's job-log treatment). The line count is also capped so a
/// huge log builds a bounded number of widgets, with a pointer to the
/// server log for the rest.
class _LogBox extends StatelessWidget {
  const _LogBox({required this.lines});

  final List<String> lines;

  static const int _cap = 200;

  @override
  Widget build(BuildContext context) {
    final shown = lines.length <= _cap ? lines : lines.take(_cap).toList();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 200),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SaltColors.panel,
        border: Border.all(color: SaltColors.hairline),
        borderRadius: BorderRadius.circular(9),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  line,
                  style: TextStyle(
                    fontFamily: 'RobotoMono',
                    fontSize: 12,
                    height: 1.35,
                    color: line.contains('failed')
                        ? SaltColors.errInk
                        : SaltColors.bodyText,
                    fontWeight: line.contains('failed')
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
            if (lines.length > _cap)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '… and ${lines.length - _cap} more — see the server log '
                  'for the full list.',
                  style: _hintStyle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final legacy = kind == 'legacy';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: legacy ? SaltColors.warnBg : SaltColors.infoBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        legacy ? 'LEGACY V0' : 'RECIPE EXTRACTION',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: legacy ? SaltColors.warnInk : SaltColors.infoInk,
        ),
      ),
    );
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer({required this.importDir});

  final String importDir;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: SaltColors.panel,
        border: Border.all(color: SaltColors.hairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: SaltColors.bodyText,
          ),
          children: [
            const TextSpan(text: 'The server only reads from its import '),
            const TextSpan(
              text: 'directory',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const TextSpan(text: ': '),
            TextSpan(
              text: importDir,
              style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12.5),
            ),
            const TextSpan(
              text:
                  '. Mount your corpus there (in Docker, '
                  '-v ~/recipes:/data/import) or copy a folder in, then '
                  'Refresh. Detection looks one level deep; formats are '
                  'auto-detected, and nothing is imported until you press '
                  'Import.',
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.importDir, required this.onRefresh});

  final String importDir;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _sectionMaxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        decoration: BoxDecoration(
          color: SaltColors.panel,
          border: Border.all(color: SaltColors.hairline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            const Text(
              'No source folders found',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: SaltColors.muted,
              ),
            ),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 13, color: SaltColors.muted),
                children: [
                  const TextSpan(text: 'Mount or copy a recipe folder into '),
                  TextSpan(
                    text: importDir,
                    style: const TextStyle(
                      fontFamily: 'RobotoMono',
                      fontSize: 12,
                    ),
                  ),
                  const TextSpan(text: ', then Refresh.'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "1198" -> "1,198".
String _thousands(int n) {
  final digits = n.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    buffer.write(digits[i]);
    final fromEnd = digits.length - 1 - i;
    if (fromEnd > 0 && fromEnd % 3 == 0) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}
