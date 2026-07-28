import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:salt_app/core/api/logs_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/util/timestamps.dart';
import 'package:salt_app/core/widgets/salt_badge.dart';
import 'package:salt_app/features/settings/settings_page.dart' show PaneTitle;

/// Settings → Server → Logs (admin): a tail of recent server log records from
/// the persisted, rotating log store (survives restarts). Live polls for new
/// records; secrets are redacted server-side.
class LogsTab extends StatefulWidget {
  const LogsTab({super.key});

  @override
  State<LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<LogsTab> {
  static const _levels = ['', 'DEBUG', 'INFO', 'WARN', 'ERROR'];

  /// Shared toolbar control height. Forui's `FSelect`/`FTextField` render at a
  /// fixed ~36px and don't stretch to a taller box (they'd paint centered,
  /// leaving a gap), so every control is pinned to their natural height and the
  /// heights line up exactly.
  static const double _controlHeight = 36;

  /// Rows shown per page. The server sends up to 300 records; rendering them
  /// all in one Column hitched the pane on open, so the table is paged.
  static const int _pageSize = 50;
  int _pageIndex = 0;

  String _level = '';
  String _logger = '';
  String _query = '';
  bool _live = false;
  Timer? _pollTimer;
  final TextEditingController _search = TextEditingController();

  LogsPage? _page;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // With a filter active, matches can be older than the server's recent-tail
    // window, so ask for a full-history scan (the server runs it off its
    // serving isolate). An unfiltered view — including its Live poll — stays on
    // the cheap tail. Using the same rule for polls and explicit fetches keeps
    // a filtered Live view from collapsing to just the tail on the next poll.
    final full = _level.isNotEmpty || _logger.isNotEmpty || _query.isNotEmpty;
    try {
      final page = await context.read<LogsRepository>().getLogs(
        level: _level,
        logger: _logger,
        query: _query,
        fullScan: full,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _error = null;
        _loading = false;
        // Keep the current page in range if a Live poll shrank the result set.
        final maxIndex = page.items.isEmpty
            ? 0
            : (page.items.length - 1) ~/ _pageSize;
        if (_pageIndex > maxIndex) _pageIndex = maxIndex;
      });
    } on RepositoryException catch (exception) {
      if (!mounted) return;
      setState(() {
        _error = exception.message;
        _loading = false;
      });
    }
  }

  void _reload() {
    // A new filter/refresh starts back at the newest page.
    setState(() {
      _loading = true;
      _pageIndex = 0;
    });
    _load();
  }

  void _toggleLive() {
    setState(() => _live = !_live);
    _pollTimer?.cancel();
    if (_live) {
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _load());
    }
  }

  /// Opens the full persisted log (honoring the active filters, not the row
  /// cap) as a download. The server sets a `Content-Disposition` filename, so
  /// launching the URL saves a file rather than navigating.
  Future<void> _download() async {
    final url = context.read<LogsRepository>().downloadUrl(
      level: _level,
      logger: _logger,
      query: _query,
    );
    var ok = false;
    try {
      ok = await launchUrl(url, mode: LaunchMode.platformDefault);
    } on Exception {
      ok = false;
    }
    if (!ok && mounted) {
      showFToast(
        context: context,
        title: const Text("Couldn't start the download."),
        variant: FToastVariant.destructive,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PaneTitle(
          'Logs',
          description:
              'Recent server activity from every logger, persisted across '
              'restarts. Live streams new records; the request id ties a '
              'request together. Secrets are redacted.',
          // A Forui ghost icon button at the `xs` size (~28px) — small enough
          // to keep this heading level with the other tabs (measured: content
          // offset delta 0 vs a plain title).
          trailing: Tooltip(
            message: 'Download the log (matches the current filters)',
            child: FButton.icon(
              variant: FButtonVariant.ghost,
              size: FButtonSizeVariant.xs,
              semanticsLabel: 'Download the log',
              onPress: _download,
              child: const Icon(FLucideIcons.download, size: 18),
            ),
          ),
        ),
        _toolbar(page),
        const SizedBox(height: 14),
        if (_loading && page == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _errorBox(_error!)
        else if (page != null)
          _table(page),
        if (page != null && page.items.isNotEmpty) _pager(page),
        if (page != null) ...[
          const SizedBox(height: 10),
          Text(
            '${page.items.length} record'
            '${page.items.length == 1 ? '' : 's'} from the persisted log — '
            'it survives restarts. Full output also goes to the container logs.',
            style: const TextStyle(fontSize: 12, color: SaltColors.muted),
          ),
        ],
      ],
    );
  }

  Widget _toolbar(LogsPage? page) {
    // Every control is pinned to _controlHeight (the fields' natural height) so
    // they line up exactly. On a wide pane they sit in one row with the search
    // field flexing to fill the gap; only when the pane is genuinely narrow
    // (mobile) do they wrap.
    final level = _levelSegmented();
    final logger = FSelect<String>(
      items: {
        'All loggers': '',
        for (final name in page?.loggers ?? const <String>[]) name: name,
      },
      control: FSelectControl.lifted(
        value: _logger,
        onChange: (value) {
          setState(() => _logger = value ?? '');
          _reload();
        },
      ),
    );
    final search = FTextField(
      hint: 'Search message or request id',
      clearable: (value) => value.text.isNotEmpty,
      control: FTextFieldControl.managed(
        controller: _search,
        onChange: (value) {
          // React only to clearing (the x button empties the field).
          if (value.text.isEmpty && _query.isNotEmpty) {
            setState(() => _query = '');
            _reload();
          }
        },
      ),
      onSubmit: (value) {
        setState(() => _query = value);
        _reload();
      },
    );
    final live = _liveToggle();
    final refresh = FButton.icon(
      onPress: _reload,
      child: const Icon(FLucideIcons.refreshCw, size: 18),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Below this the fixed controls leave the search box too cramped, so
        // wrap instead.
        if (constraints.maxWidth >= 720) {
          return Row(
            children: [
              SizedBox(height: _controlHeight, child: level),
              const SizedBox(width: 10),
              SizedBox(width: 158, height: _controlHeight, child: logger),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(height: _controlHeight, child: search),
              ),
              const SizedBox(width: 10),
              SizedBox(height: _controlHeight, child: live),
              const SizedBox(width: 10),
              SizedBox(height: _controlHeight, child: refresh),
            ],
          );
        }
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(height: _controlHeight, child: level),
            SizedBox(width: 158, height: _controlHeight, child: logger),
            SizedBox(width: 210, height: _controlHeight, child: search),
            SizedBox(height: _controlHeight, child: live),
            SizedBox(height: _controlHeight, child: refresh),
          ],
        );
      },
    );
  }

  Widget _levelSegmented() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: SaltColors.hairline),
        borderRadius: BorderRadius.circular(9),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final level in _levels)
            InkWell(
              onTap: () {
                setState(() => _level = level);
                _reload();
              },
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                color: _level == level ? SaltColors.maroon : Colors.transparent,
                child: Text(
                  level.isEmpty ? 'All' : _titleCase(level),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: _level == level
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: _level == level ? Colors.white : SaltColors.bodyText,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _liveToggle() {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: _toggleLive,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _live ? SaltColors.infoBg : Colors.white,
          border: Border.all(
            color: _live ? const Color(0xFFBFD9D2) : SaltColors.hairline,
          ),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _live ? const Color(0xFF2F9D6B) : SaltColors.muted,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              'Live',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _live ? SaltColors.infoInk : SaltColors.bodyText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _table(LogsPage page) {
    if (page.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            'No records match.',
            style: TextStyle(color: SaltColors.muted),
          ),
        ),
      );
    }
    // Only the current page's rows are built — rendering all ~300 at once
    // hitched the pane on open.
    final start = _pageIndex * _pageSize;
    final rows = page.items.sublist(
      start,
      math.min(start + _pageSize, page.items.length),
    );
    // SelectionArea makes every cell's text selectable — including a drag
    // across columns and rows — so a timestamp, request id, or message can be
    // copied out. Only the table is wrapped; the interactive toolbar above is
    // left outside it.
    return SelectionArea(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        // The border goes in the FOREGROUND so it paints on top of the header's
        // fill; otherwise that fill covers the top corners of the outline.
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: SaltColors.hairline),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _header(),
            for (var i = 0; i < rows.length; i++)
              _row(rows[i], last: i == rows.length - 1),
          ],
        ),
      ),
    );
  }

  /// Prev/Next pager under the table; hidden when everything fits one page.
  Widget _pager(LogsPage page) {
    final total = page.items.length;
    final pageCount = (total + _pageSize - 1) ~/ _pageSize;
    if (pageCount <= 1) return const SizedBox.shrink();
    final start = _pageIndex * _pageSize + 1;
    final end = math.min(start + _pageSize - 1, total);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Text(
            'Showing $start–$end of $total',
            style: const TextStyle(fontSize: 12, color: SaltColors.muted),
          ),
          const Spacer(),
          FButton(
            variant: FButtonVariant.outline,
            size: FButtonSizeVariant.sm,
            mainAxisSize: MainAxisSize.min,
            onPress: _pageIndex > 0 ? () => setState(() => _pageIndex--) : null,
            child: const Text('Prev'),
          ),
          const SizedBox(width: 10),
          Text(
            'Page ${_pageIndex + 1} of $pageCount',
            style: const TextStyle(fontSize: 12.5, color: SaltColors.ink),
          ),
          const SizedBox(width: 10),
          FButton(
            variant: FButtonVariant.outline,
            size: FButtonSizeVariant.sm,
            mainAxisSize: MainAxisSize.min,
            onPress: _pageIndex < pageCount - 1
                ? () => setState(() => _pageIndex++)
                : null,
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    Widget cell(String label, {double? width, bool expand = false}) {
      final text = Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: Color(0xFF9A8D84),
        ),
      );
      if (expand) return Expanded(child: text);
      return SizedBox(width: width, child: text);
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFAF6F2),
        border: Border(bottom: BorderSide(color: SaltColors.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          cell('TIME', width: 88),
          const SizedBox(width: 12),
          cell('LEVEL', width: 66),
          cell('LOGGER', width: 86),
          cell('MESSAGE', expand: true),
          const SizedBox(width: 10),
          cell('REQUEST', width: 84),
        ],
      ),
    );
  }

  Widget _row(LogEntry entry, {required bool last}) {
    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF1EBE6))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 88, child: _mono(_timeOf(entry.time))),
          const SizedBox(width: 12),
          SizedBox(width: 66, child: _levelBadge(entry.level)),
          SizedBox(width: 86, child: _mono(entry.logger)),
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                fontSize: 13,
                color: entry.level == 'ERROR'
                    ? SaltColors.errInk
                    : SaltColors.ink,
                fontWeight: entry.level == 'ERROR'
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 84,
            child: entry.requestId == null
                ? _mono('—')
                : _mono(entry.requestId!),
          ),
        ],
      ),
    );
  }

  Widget _mono(String text) => Text(
    text,
    style: const TextStyle(
      fontFamily: 'RobotoMono',
      fontSize: 12,
      color: SaltColors.muted,
    ),
  );

  Widget _errorBox(String message) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: SaltColors.errBg,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        const Icon(
          FLucideIcons.circleAlert,
          color: SaltColors.errInk,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: SaltColors.errInk),
          ),
        ),
        FButton(
          variant: FButtonVariant.outline,
          size: FButtonSizeVariant.sm,
          mainAxisSize: MainAxisSize.min,
          onPress: _reload,
          child: const Text('Retry'),
        ),
      ],
    ),
  );

  /// The clock part, in the viewer's LOCAL zone — the old inline version
  /// showed the raw (UTC) clock, off by the zone offset when correlating
  /// with local wall clocks (review B18).
  String _timeOf(String iso) => formatClock(iso);

  String _titleCase(String value) =>
      value[0] + value.substring(1).toLowerCase();

  Widget _levelBadge(String level) {
    final tone = switch (level) {
      'ERROR' => SaltBadgeTone.err,
      'WARN' => SaltBadgeTone.warn,
      'INFO' => SaltBadgeTone.info,
      _ => SaltBadgeTone.neutral,
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: SaltBadge(level, tone: tone),
    );
  }
}
