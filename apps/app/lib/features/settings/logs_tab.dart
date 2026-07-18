import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:salt_app/core/api/logs_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/core/theme/salt_theme.dart';

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
    setState(() => _loading = true);
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
        Row(
          children: [
            const Text(
              'Logs',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: SaltColors.ink,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.download_outlined, size: 20),
              color: SaltColors.muted,
              tooltip: 'Download the log (matches the current filters)',
              visualDensity: VisualDensity.compact,
              onPressed: _download,
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Recent server activity from every logger, persisted across '
          'restarts. Live streams new records; the request id ties a request '
          'together. Secrets are redacted.',
          style: TextStyle(fontSize: 13.5, color: SaltColors.muted),
        ),
        const SizedBox(height: 16),
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
        if (page != null) ...[
          const SizedBox(height: 10),
          Text(
            'Showing ${page.items.length} record'
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
      child: const Icon(Icons.refresh, size: 18),
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
    return Container(
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
          for (var i = 0; i < page.items.length; i++)
            _row(page.items[i], last: i == page.items.length - 1),
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
          SizedBox(width: 66, child: _LevelBadge(entry.level)),
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
        const Icon(Icons.error_outline, color: SaltColors.errInk, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: SaltColors.errInk),
          ),
        ),
        TextButton(onPressed: _reload, child: const Text('Retry')),
      ],
    ),
  );

  /// The clock part of the ISO-8601 timestamp (HH:MM:SS.mmm).
  String _timeOf(String iso) {
    final t = iso.indexOf('T');
    if (t < 0) return iso;
    final rest = iso.substring(t + 1);
    final dot = rest.indexOf('.');
    return dot < 0 ? rest : rest.substring(0, dot + 4);
  }

  String _titleCase(String value) =>
      value[0] + value.substring(1).toLowerCase();
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge(this.level);

  final String level;

  @override
  Widget build(BuildContext context) {
    final (bg, ink) = switch (level) {
      'ERROR' => (SaltColors.errBg, SaltColors.errInk),
      'WARN' => (SaltColors.warnBg, SaltColors.warnInk),
      'INFO' => (SaltColors.infoBg, SaltColors.infoInk),
      _ => (SaltColors.chipNeutral, SaltColors.muted),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          level,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
      ),
    );
  }
}
