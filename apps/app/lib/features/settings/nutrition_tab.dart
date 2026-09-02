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

/// The scope [_activeBulkJobId] was started with, so a re-attached tab can
/// still name it in the done summary.
BulkScope? _activeBulkScope;

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
  BulkScope _scope = BulkScope.missing;

  /// Null until the preview lands (or when it failed): the segments show no
  /// count rather than 0 — a 0 disables the Stale button.
  BulkCounts? _counts;
  bool _confirmingAll = false;
  bool _startingBulk = false;
  NutritionJob? _job;
  BulkScope? _jobScope;
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
    _loadCounts();
    // A job started before a tab switch is still running server-side —
    // re-attach instead of presenting a button that would only 409.
    final activeJob = _activeBulkJobId;
    if (activeJob != null) {
      _jobScope = _activeBulkScope;
      // The control must show the RUNNING job's scope, not the default: a
      // remounted tab with a Stale sweep in flight otherwise selects Missing
      // and the spinning button reads "Compute N missing".
      _scope = _activeBulkScope ?? _scope;
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

  Future<void> _loadCounts() async {
    try {
      final counts = await context.read<NutritionRepository>().bulkCounts();
      if (mounted) {
        setState(() => _counts = counts);
      }
    } on RepositoryException catch (exception) {
      if (mounted) {
        setState(() => _bulkError = exception.message);
      }
    }
  }

  /// `All` confirms inline before spending hours of FDC budget; the other
  /// scopes start at once.
  void _computePressed() {
    if (_scope == BulkScope.all && !_confirmingAll) {
      setState(() => _confirmingAll = true);
    } else {
      _startBulk();
    }
  }

  Future<void> _startBulk() async {
    final repository = context.read<NutritionRepository>();
    final scope = _scope;
    setState(() {
      _startingBulk = true;
      _confirmingAll = false;
      _bulkError = null;
      _job = null;
      _jobScope = scope;
      _logExpanded = false;
    });
    try {
      final started = await repository.startBulk(scope);
      if (!mounted) {
        return;
      }
      if (started.total == 0) {
        // Nothing selected (the preview was out of date): the job is already
        // finished server-side, so refresh the counts instead of polling.
        await _loadCounts();
        return;
      }
      _activeBulkJobId = started.jobId;
      _activeBulkScope = started.scope;
      _watchJob(started.jobId);
      await _poll(repository, started.jobId);
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
        _activeBulkScope = null;
        unawaited(_loadCounts());
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
          child: const Text('Compute nutrition', style: _sectionHeading),
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
                const Icon(FLucideIcons.key, size: 17, color: SaltColors.okInk),
                const SizedBox(width: 9),
                const Text(
                  'Configured',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: SaltColors.ink,
                  ),
                ),
                // One flexible element takes all the slack so the button sits
                // flush right. (A Flexible mask PLUS a Spacer both claimed
                // flex, so the loose mask left space that stranded the button
                // short of the edge.) The mask still ellipsizes when long.
                Expanded(
                  child: Text(
                    _masked == null ? '' : ' · $_masked',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'RobotoMono',
                      fontSize: 13,
                      color: SaltColors.muted,
                    ),
                  ),
                ),
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
    final count = _counts?.of(_scope);
    final running = _bulkRunning;
    // A 0 count is a job that does nothing; no count yet is still startable
    // (the 202 reports the total).
    final canStart = !running && count != 0;
    final nothingStale = _scope == BulkScope.stale && count == 0;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _sectionMaxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ScopeControl(
            scope: _scope,
            counts: _counts,
            enabled: !running,
            onSelect: (scope) => setState(() {
              _scope = scope;
              _confirmingAll = false;
            }),
          ),
          const SizedBox(height: 12),
          FButton(
            variant: FButtonVariant.outline,
            mainAxisSize: MainAxisSize.min,
            onPress: canStart ? _computePressed : null,
            prefix: running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: SaltColors.maroon,
                    ),
                  )
                : Icon(
                    _scope == BulkScope.missing
                        ? FLucideIcons.zap
                        : FLucideIcons.refreshCw,
                    size: 18,
                  ),
            child: Text(_buttonLabel(count)),
          ),
          // The idle banner and a job's summary are both green messages
          // about the same fact; a finished sweep shows its summary alone
          // (the mockup's Done card), the banner only when there is no job.
          if (nothingStale && job == null)
            const _OkBanner(
              'Nothing is stale — every computed recipe still matches its '
              'ingredients.',
            )
          else if (_confirmingAll)
            _confirmAll()
          else if (_scope != BulkScope.all)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _scope == BulkScope.missing
                    ? 'Recipes with no nutrition yet. Throttled to ~900 '
                          'requests/hour — a large first run takes a while '
                          'and resumes rate-limiting automatically.'
                    : 'Recipes whose ingredient lines changed since their '
                          'last compute — the ones showing the amber '
                          '“ingredients changed” banner. Your confirmed and '
                          'overridden matches are kept; only unreviewed and '
                          'changed lines are re-resolved.',
                style: const TextStyle(fontSize: 12.5, color: SaltColors.muted),
              ),
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

  /// "Compute 1,190 missing" / "Recompute 3 stale" / "Recompute all 1,198";
  /// without a count yet, the bare verb form.
  String _buttonLabel(int? count) {
    final n = count == null ? null : _thousands(count);
    return switch (_scope) {
      BulkScope.missing => n == null ? 'Compute missing' : 'Compute $n missing',
      BulkScope.stale => n == null ? 'Recompute stale' : 'Recompute $n stale',
      BulkScope.all => n == null ? 'Recompute all' : 'Recompute all $n',
    };
  }

  /// The inline confirm for `All` — shown before anything is started.
  Widget _confirmAll() {
    const ink = SaltColors.warnInk;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: SaltColors.warnBg,
        border: Border.all(color: const Color(0xFFF0DDBA), width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(FLucideIcons.triangleAlert, size: 15, color: ink),
              SizedBox(width: 7),
              Text(
                'This re-resolves every recipe',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text:
                      'At ~900 requests/hour that is several hours of '
                      'FoodData Central budget, most of it re-ranking lines '
                      'that already match. Your confirmed and overridden '
                      'matches are kept. Usually ',
                ),
                TextSpan(
                  text: 'Stale',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ' is what you want.'),
              ],
            ),
            style: TextStyle(fontSize: 13, height: 1.5, color: ink),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FButton(
                size: FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                onPress: _startBulk,
                child: const Text('Start anyway'),
              ),
              const SizedBox(width: 8),
              FButton(
                variant: FButtonVariant.ghost,
                size: FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                onPress: () => setState(() => _confirmingAll = false),
                child: const Text('Cancel'),
              ),
            ],
          ),
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
      final n = _thousands(job.total);
      text = switch (_jobScope) {
        BulkScope.stale => 'All $n stale recipes recomputed.',
        BulkScope.all => 'All $n recipes recomputed.',
        BulkScope.missing || null => 'All $n missing recipes computed.',
      };
    }
    if (!showLog) {
      // Nothing failed and nothing to expand: the summary IS the banner.
      return _OkBanner(text);
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
                failedJob ? FLucideIcons.circleAlert : FLucideIcons.circleCheck,
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

/// The Missing / Stale / All choice, each segment carrying its preview
/// count. Forui 0.24 has no segmented single-choice widget (FTabs is a view
/// switcher with no disabled state; FSelectGroup draws radio circles), so
/// this is built on [FTappable] — the primitive FButton and FRadio share —
/// the way the label's collapse bar and the review queue's rows are: it
/// carries Forui's focus/hover/keyboard handling and radio semantics while
/// the segment paints the mockup's chip tint. A selection, not an action, so
/// the tint is the chip colour, never solid maroon.
class _ScopeControl extends StatelessWidget {
  const _ScopeControl({
    required this.scope,
    required this.counts,
    required this.enabled,
    required this.onSelect,
  });

  final BulkScope scope;
  final BulkCounts? counts;

  /// False while a job runs — one bulk job at a time (the server 409s a
  /// second).
  final bool enabled;
  final ValueChanged<BulkScope> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: SaltColors.hairline),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, option) in BulkScope.values.indexed) ...[
            if (index > 0) const SizedBox(width: 3),
            _Segment(
              label: switch (option) {
                BulkScope.missing => 'Missing',
                BulkScope.stale => 'Stale',
                BulkScope.all => 'All',
              },
              count: counts?.of(option),
              selected: option == scope,
              onPress: enabled ? () => onSelect(option) : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.count,
    required this.selected,
    required this.onPress,
  });

  final String label;

  /// Null while the preview is loading: no pill rather than a false 0.
  final int? count;
  final bool selected;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    final ink = selected ? SaltColors.chipInk : SaltColors.muted;
    return FTappable(
      onPress: onPress,
      selected: selected,
      semanticsButton: false,
      semanticsChecked: selected,
      semanticsInMutuallyExclusiveGroup: true,
      builder: (context, states, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? SaltColors.chip : null,
          borderRadius: BorderRadius.circular(7),
        ),
        child: child,
      ),
      child: MouseRegion(
        cursor: onPress == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : const Color(0xFFF4EFE9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _thousands(count),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: count == 0 ? const Color(0xFFB8B1AC) : ink,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The green "nothing to do" line under the button.
class _OkBanner extends StatelessWidget {
  const _OkBanner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: SaltColors.okBg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(FLucideIcons.check, size: 16, color: SaltColors.okInk),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: SaltColors.okInk),
            ),
          ),
        ],
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
