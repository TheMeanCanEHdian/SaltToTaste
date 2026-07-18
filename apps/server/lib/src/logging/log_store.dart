import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_shared/salt_shared.dart';

/// Patterns whose captured secret (group 2) is masked before a record is
/// written.
///
/// The first-boot setup code and the recovery code are the only secrets ever
/// routed anywhere near a log line (and both are actually printed straight to
/// stdout, bypassing the logger). This redaction is defence-in-depth for the
/// admin log VIEWER — a new read surface that must never hand out a live code.
final List<RegExp> logRedactions = [
  RegExp(r'(setup code:\s*)(\S+)', caseSensitive: false),
  RegExp(r'(recovery code:\s*)(\S+)', caseSensitive: false),
];

/// Masks any secret [logRedactions] recognises in [message].
String redactLogMessage(String message) {
  var result = message;
  for (final pattern in logRedactions) {
    result = result.replaceAllMapped(pattern, (m) => '${m.group(1)}••••');
  }
  return result;
}

/// The `rid=<16 hex>` correlation id the request logger appends. Pulled into
/// its own field and stripped from the message so it isn't shown twice.
final RegExp _rid = RegExp(r'\s*rid=([0-9a-f]{16})\b');

/// Severity buckets, ordered — a `minLevel` filter shows its rank and above.
const Map<String, int> logLevelRank = {
  'DEBUG': 0,
  'INFO': 1,
  'WARN': 2,
  'ERROR': 3,
};

String _bucket(Level level) {
  if (level >= Level.SEVERE) {
    return 'ERROR';
  }
  if (level >= Level.WARNING) {
    return 'WARN';
  }
  if (level >= Level.INFO) {
    return 'INFO';
  }
  return 'DEBUG';
}

/// A page of log records plus the distinct logger names present in the store.
typedef LogQueryResult = ({List<LogEntry> items, List<String> loggers});

/// How much of the END of each log file the VIEWER parses per poll. The tail
/// holds far more than any `limit` of recent lines (~4k lines at 512 KiB), so a
/// Live poll stays a few ms regardless of the on-disk size. The full-history
/// export is exempt (it passes no cap).
const int logViewerScanBytes = 512 * 1024;

/// A persistent, file-backed store of server log records for the admin viewer.
///
/// Attaches to `Logger.root` and appends each record (secrets redacted) as one
/// JSON line to `<dir>/server.jsonl`. When the file passes [maxBytes] it rotates
/// to `server.jsonl.1` (keeping one generation), so the log survives restarts
/// and stays bounded. This is the SAME stream the process already prints to
/// stdout — persisted where the endpoint can read it back, rather than only the
/// last-N in memory.
class LogStore {
  /// Creates a store writing to `<directory>/server.jsonl`, rotating the active
  /// file at [maxBytes] (`<= 0` disables logging entirely).
  LogStore({required this.directory, this.maxBytes = 4 * 1024 * 1024});

  /// Directory holding `server.jsonl` (+ its `.1` rotation).
  final String directory;

  /// Rotate the active file once it reaches this size; `<= 0` disables logging.
  final int maxBytes;

  StreamSubscription<LogRecord>? _subscription;
  bool _dirReady = false;

  String get _path => '$directory/server.jsonl';
  String get _backupPath => '$_path.1';

  /// Subscribes to [records] (typically `Logger.root.onRecord`).
  void attach(Stream<LogRecord> records) {
    if (maxBytes <= 0) {
      return;
    }
    _ensureDir();
    _subscription?.cancel();
    _subscription = records.listen(add);
  }

  void _ensureDir() {
    if (_dirReady) {
      return;
    }
    Directory(directory).createSync(recursive: true);
    _dirReady = true;
  }

  /// Appends one record (redacted, request id lifted) to the active file, then
  /// rotates if it has grown past [maxBytes]. Writes are synchronous so a
  /// reader always sees complete lines and no flush lag.
  void add(LogRecord record) {
    if (maxBytes <= 0) {
      return;
    }
    final rid = _rid.firstMatch(record.message);
    final stripped = rid == null
        ? record.message
        : record.message.replaceFirst(_rid, '');
    final entry = LogEntry(
      time: record.time.toIso8601String(),
      level: _bucket(record.level),
      logger: record.loggerName,
      message: redactLogMessage(stripped),
      requestId: rid?.group(1),
    );
    // Logging is best-effort and runs on EVERY request (via Logger.root): a
    // read-only or full data dir must never turn a log line into an uncaught
    // error on the root zone. Create the dir once (not per record), then
    // swallow write failures — a dropped log line beats a poisoned request.
    try {
      _ensureDir();
      final file = File(_path)
        ..writeAsStringSync(
          '${jsonEncode(entry.toMap())}\n',
          mode: FileMode.append,
        );
      if (file.lengthSync() >= maxBytes) {
        _rotate();
      }
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}
  }

  void _rotate() {
    final backup = File(_backupPath);
    if (backup.existsSync()) {
      backup.deleteSync();
    }
    final active = File(_path);
    if (active.existsSync()) {
      active.renameSync(_backupPath);
    }
  }

  /// The lines of [file], or only those within the last [maxScanBytes] when it
  /// is set — reading from the end and dropping the partial line the window
  /// sliced through. Bounds the parse cost to the tail instead of the whole
  /// file when a caller only needs recent records.
  List<String> _tailLines(File file, int? maxScanBytes) {
    if (!file.existsSync()) {
      return const [];
    }
    final length = file.lengthSync();
    if (maxScanBytes == null || length <= maxScanBytes) {
      return file.readAsLinesSync();
    }
    final handle = file.openSync();
    try {
      final bytes = (handle..setPositionSync(length - maxScanBytes)).readSync(
        maxScanBytes,
      );
      final text = utf8.decode(bytes, allowMalformed: true);
      final firstBreak = text.indexOf('\n');
      return const LineSplitter().convert(
        firstBreak < 0 ? '' : text.substring(firstBreak + 1),
      );
    } finally {
      handle.closeSync();
    }
  }

  /// Reads the store (rotation + active file), newest first, filtered.
  /// [minLevel] shows that bucket and above; [logger] is an exact name; [query]
  /// is a case-insensitive substring of the message or request id; [limit] caps
  /// the item count. Also returns the distinct logger names for the filter.
  ///
  /// [maxScanBytes] bounds how much of the END of each file is read+parsed. The
  /// viewer (polled every few seconds while Live is on) passes a cap so a poll
  /// stays cheap regardless of the on-disk size — it only needs recent lines;
  /// the full-history export passes null. This keeps the synchronous parse off
  /// the serving isolate's critical path (see the #48 off-isolate lesson).
  LogQueryResult query({
    String? minLevel,
    String? logger,
    String? query,
    int limit = 300,
    int? maxScanBytes,
  }) {
    final minRank = minLevel == null ? 0 : (logLevelRank[minLevel] ?? 0);
    final needle = query?.trim().toLowerCase();

    final all = <LogEntry>[];
    // Oldest generation first, then active — so file order is oldest→newest.
    for (final path in [_backupPath, _path]) {
      for (final line in _tailLines(File(path), maxScanBytes)) {
        if (line.trim().isEmpty) {
          continue;
        }
        try {
          all.add(
            LogEntryMapper.fromMap(jsonDecode(line) as Map<String, dynamic>),
          );
          // A truncated/corrupt line must not fail the whole read.
          // ignore: avoid_catches_without_on_clauses
        } catch (_) {}
      }
    }

    final loggers = {for (final entry in all) entry.logger}.toList()..sort();

    final items = <LogEntry>[];
    for (final entry in all.reversed) {
      if ((logLevelRank[entry.level] ?? 0) < minRank) {
        continue;
      }
      if (logger != null && logger.isNotEmpty && entry.logger != logger) {
        continue;
      }
      if (needle != null && needle.isNotEmpty) {
        final inMessage = entry.message.toLowerCase().contains(needle);
        final inRid = entry.requestId?.toLowerCase().contains(needle) ?? false;
        if (!inMessage && !inRid) {
          continue;
        }
      }
      items.add(entry);
      if (items.length >= limit) {
        break;
      }
    }
    return (items: items, loggers: loggers);
  }

  /// Cancels the log subscription.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
