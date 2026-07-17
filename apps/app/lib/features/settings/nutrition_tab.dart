import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/async_view.dart';
import 'package:salt_app/features/settings/settings_page.dart';

/// Column width for the key row, progress block, and basis panel — the
/// mockup's 560px content cap.
const double _sectionMaxWidth = 560;

/// A bulk job survives this widget: remembering the id across tab
/// switches lets a remounted tab re-attach to the running job instead of
/// silently dropping the progress UI (there is no server job-list
/// endpoint to rediscover it from).
int? _activeBulkJobId;

const TextStyle _sectionHeading = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w700,
);

const TextStyle _hintStyle = TextStyle(fontSize: 12, color: SaltColors.muted);

/// Nutrition tab (admin): the write-only FoodData Central API key, bulk
/// compute with live job progress, and the serving-basis explainer.
/// Design: docs/mockups/p6-nutrition.html, section 3.
class NutritionTab extends StatefulWidget {
  const NutritionTab({super.key});

  @override
  State<NutritionTab> createState() => _NutritionTabState();
}

class _NutritionTabState extends State<NutritionTab> {
  // FDC key (write-only: the server only ever returns a masked suffix).
  bool _keyLoaded = false;
  String? _keyLoadError;
  bool _configured = false;
  String? _masked;
  bool _replacingKey = false;
  bool _savingKey = false;
  String? _keySaveError;
  final _keyField = TextEditingController();

  // Bulk compute job.
  bool _startingBulk = false;
  NutritionJob? _job;
  String? _bulkError;
  Timer? _pollTimer;
  bool _pollInFlight = false;
  int _pollFailures = 0;
  bool _logExpanded = false;

  bool get _bulkRunning => _startingBulk || _job?.status == 'running';

  @override
  void initState() {
    super.initState();
    // Re-renders on typing so the Save button enables/disables.
    _keyField.addListener(() => setState(() {}));
    _loadKeyStatus();
    // A job started before a tab switch is still running server-side —
    // re-attach instead of presenting a button that would only 409.
    final activeJob = _activeBulkJobId;
    if (activeJob != null) {
      _watchJob(activeJob);
      // Show progress right away rather than after the first 2s tick.
      Future<void>.microtask(() {
        if (mounted) {
          _poll(context.read<NutritionRepository>(), activeJob);
        }
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _keyField.dispose();
    super.dispose();
  }

  Future<void> _loadKeyStatus() async {
    setState(() => _keyLoadError = null);
    try {
      final status = await context.read<NutritionRepository>().fdcKeyStatus();
      if (mounted) {
        setState(() {
          _configured = status.configured;
          _masked = status.masked;
          _keyLoaded = true;
        });
      }
    } on RepositoryException catch (exception) {
      if (mounted) {
        setState(() => _keyLoadError = exception.message);
      }
    }
  }

  Future<void> _saveKey() async {
    final key = _keyField.text.trim();
    if (key.isEmpty || _savingKey) {
      return;
    }
    setState(() {
      _savingKey = true;
      _keySaveError = null;
    });
    try {
      final status = await context.read<NutritionRepository>().setFdcKey(key);
      if (mounted) {
        // Never keep (or show) the full key after save — only the masked
        // suffix the server returns.
        _keyField.clear();
        setState(() {
          _configured = status.configured;
          _masked = status.masked;
          _replacingKey = false;
        });
      }
    } on RepositoryException catch (exception) {
      if (mounted) {
        setState(() => _keySaveError = exception.message);
      }
    } finally {
      if (mounted) {
        setState(() => _savingKey = false);
      }
    }
  }

  void _cancelReplace() {
    _keyField.clear();
    setState(() {
      _replacingKey = false;
      _keySaveError = null;
    });
  }

  Future<void> _startBulk() async {
    final repository = context.read<NutritionRepository>();
    setState(() {
      _startingBulk = true;
      _bulkError = null;
      _job = null;
      _logExpanded = false;
    });
    try {
      final jobId = await repository.startBulk();
      if (!mounted) {
        return;
      }
      _activeBulkJobId = jobId;
      _watchJob(jobId);
      await _poll(repository, jobId);
    } on RepositoryException catch (exception) {
      // Includes the 409 "already running" case (its message comes
      // through the conflict error code).
      if (mounted) {
        setState(() => _bulkError = exception.message);
      }
    } finally {
      if (mounted) {
        setState(() => _startingBulk = false);
      }
    }
  }

  void _watchJob(int jobId) {
    _pollFailures = 0;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _poll(context.read<NutritionRepository>(), jobId),
    );
  }

  Future<void> _poll(NutritionRepository repository, int jobId) async {
    if (_pollInFlight) {
      return;
    }
    _pollInFlight = true;
    try {
      final job = await repository.job(jobId);
      if (!mounted) {
        return;
      }
      _pollFailures = 0;
      setState(() {
        _job = job;
        _bulkError = null;
      });
      if (job.status != 'running') {
        _pollTimer?.cancel();
        _pollTimer = null;
        _activeBulkJobId = null;
      }
    } on RepositoryException catch (exception) {
      // An hour-long job WILL see a transient blip; keep polling and only
      // report after several consecutive failures — the job itself is
      // untouched server-side, so keep its id and progress on screen.
      _pollFailures += 1;
      if (_pollFailures >= 5 && mounted) {
        setState(
          () => _bulkError =
              'Progress updates are failing (${exception.message}) — '
              'the job keeps running on the server; retrying…',
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
          'Nutrition',
          description:
              'Nutrition facts are computed per serving from USDA FoodData '
              'Central. They live in the database only — never in the '
              'exported YAML.',
        ),
        Semantics(
          header: true,
          child: const Text('FoodData Central API key', style: _sectionHeading),
        ),
        const SizedBox(height: 10),
        if (!_keyLoaded && _keyLoadError != null)
          ErrorView(message: _keyLoadError!, onRetry: _loadKeyStatus)
        else if (!_keyLoaded)
          const LoadingView()
        else if (_configured && !_replacingKey)
          _configuredKey()
        else
          _keyInput(),
        const SizedBox(height: 28),
        Semantics(
          header: true,
          child: const Text('Compute all recipes', style: _sectionHeading),
        ),
        const SizedBox(height: 10),
        _computeSection(),
        const SizedBox(height: 28),
        Semantics(
          header: true,
          child: const Text('Serving basis', style: _sectionHeading),
        ),
        const SizedBox(height: 10),
        _basisPanel(),
      ],
    );
  }

  /// Neutral "Configured · `<masked>`" panel (mockup key-state: only the
  /// key icon is green; the mask is muted mono) with Replace-key action.
  Widget _configuredKey() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _sectionMaxWidth),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: SaltColors.panel,
              border: Border.all(color: SaltColors.hairline),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.key, size: 17, color: SaltColors.okInk),
                const SizedBox(width: 9),
                const Text(
                  'Configured',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: SaltColors.ink,
                  ),
                ),
                if (_masked != null)
                  Flexible(
                    child: Text(
                      ' · $_masked',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'RobotoMono',
                        fontSize: 13,
                        color: SaltColors.muted,
                      ),
                    ),
                  ),
                const Spacer(),
                const SizedBox(width: 10),
                FButton(
                  variant: FButtonVariant.outline,
                  size: FButtonSizeVariant.sm,
                  mainAxisSize: MainAxisSize.min,
                  onPress: () => setState(() {
                    _replacingKey = true;
                    _keySaveError = null;
                  }),
                  child: const Text('Replace key'),
                ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Write-only: the key is stored server-side and shown masked — '
            'it can be replaced but never re-read.',
            style: _hintStyle,
          ),
        ),
      ],
    );
  }

  /// Key entry (fresh install, or replacing an existing key).
  Widget _keyInput() {
    final canSave = !_savingKey && _keyField.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _sectionMaxWidth),
          child: Row(
            children: [
              Expanded(
                child: FTextField(
                  control: FTextFieldControl.managed(controller: _keyField),
                  enabled: !_savingKey,
                  autofocus: _replacingKey,
                  autocorrect: false,
                  hint: 'Paste your api.data.gov key',
                  onSubmit: (_) => _saveKey(),
                ),
              ),
              const SizedBox(width: 9),
              FButton(
                mainAxisSize: MainAxisSize.min,
                onPress: canSave ? _saveKey : null,
                child: _savingKey
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text('Saving…'),
                        ],
                      )
                    : const Text('Save key'),
              ),
              if (_configured) ...[
                const SizedBox(width: 9),
                FButton(
                  variant: FButtonVariant.outline,
                  mainAxisSize: MainAxisSize.min,
                  onPress: _savingKey ? null : _cancelReplace,
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ),
        if (_keySaveError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _keySaveError!,
              style: const TextStyle(fontSize: 12.5, color: SaltColors.errInk),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Get a free key at ', style: _hintStyle),
              InkWell(
                onTap: () => launchUrl(
                  Uri.parse('https://api.data.gov/signup/'),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text(
                  'api.data.gov/signup',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'OpenSans',
                    color: SaltColors.maroon,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const Text(' — one key per household server.', style: _hintStyle),
            ],
          ),
        ),
      ],
    );
  }

  Widget _computeSection() {
    final job = _job;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _sectionMaxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FButton(
            variant: FButtonVariant.outline,
            mainAxisSize: MainAxisSize.min,
            onPress: _bulkRunning ? null : _startBulk,
            prefix: _bulkRunning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: SaltColors.maroon,
                    ),
                  )
                : const Icon(Icons.bolt, size: 18),
            child: const Text('Compute all missing'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Throttled to ~900 requests/hour — a large first run takes a '
            'while and resumes rate-limiting automatically. Already-computed '
            'recipes are skipped.',
            style: TextStyle(fontSize: 12.5, color: SaltColors.muted),
          ),
          if (_bulkError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _bulkError!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: SaltColors.errInk,
                ),
              ),
            ),
          if (job != null)
            if (job.status == 'running')
              _jobProgress(job)
            else
              _jobSummary(job),
        ],
      ),
    );
  }

  Widget _jobProgress(NutritionJob job) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: job.total > 0 ? job.done / job.total : null,
              minHeight: 10,
              color: SaltColors.maroon,
              backgroundColor: SaltColors.chipNeutral,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_thousands(job.done)} / ${_thousands(job.total)} computed'
            '${job.failed > 0 ? ' · ${_thousands(job.failed)} failed' : ''}',
            style: const TextStyle(fontSize: 12.5, color: SaltColors.muted),
          ),
        ],
      ),
    );
  }

  /// Terminal-state summary line, plus the expandable failure log.
  Widget _jobSummary(NutritionJob job) {
    final failedJob = job.status != 'done';
    final ink = failedJob ? SaltColors.errInk : SaltColors.okInk;
    final showLog = failedJob || job.failed > 0;
    final String text;
    if (failedJob) {
      text =
          'Bulk compute failed after ${_thousands(job.done)} of '
          '${_thousands(job.total)} —';
    } else if (job.failed > 0) {
      text =
          '${_thousands(job.done)} computed, '
          '${_thousands(job.failed)} failed —';
    } else {
      text = 'All ${_thousands(job.total)} computed';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
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
                      onTap: () => setState(() => _logExpanded = !_logExpanded),
                      child: Text(
                        _logExpanded ? 'hide log' : 'see log',
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
          if (showLog && _logExpanded)
            Container(
              margin: const EdgeInsets.only(top: 8),
              constraints: const BoxConstraints(maxHeight: 200),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SaltColors.panel,
                border: Border.all(color: SaltColors.hairline),
                borderRadius: BorderRadius.circular(9),
              ),
              child: job.log.isEmpty
                  ? const Text('No log entries.', style: _hintStyle)
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final line in job.log)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                line,
                                style: const TextStyle(
                                  fontFamily: 'RobotoMono',
                                  fontSize: 12,
                                  color: SaltColors.bodyText,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  /// Explainer only — the per-recipe divisor control lives on the recipe
  /// page's label panel.
  Widget _basisPanel() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _sectionMaxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: SaltColors.panel,
          border: Border.all(color: SaltColors.hairline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Per-serving numbers divide the recipe total by the ',
              ),
              TextSpan(
                text: 'lower bound',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(
                text:
                    ' of the parsed servings — “SERVES 8 TO 10” computes '
                    'per ',
              ),
              TextSpan(
                text: '8',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(
                text:
                    ' (the conservative estimate). Admins can change a '
                    'recipe’s divisor in its match review sheet — open it '
                    'from the label’s match badge. Recipes whose servings '
                    'don’t parse (e.g. “MAKES 1 QUART”) get totals only — '
                    'no per-serving label — and are excluded from '
                    'calories: search.',
              ),
            ],
          ),
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: SaltColors.bodyText,
          ),
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
