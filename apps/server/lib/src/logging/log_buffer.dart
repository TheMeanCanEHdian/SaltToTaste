import 'dart:async';
import 'dart:collection';

import 'package:logging/logging.dart';
import 'package:salt_shared/salt_shared.dart';

/// Patterns whose captured secret (group 2) is masked before a record enters
/// the buffer.
///
/// The first-boot setup code and the recovery code are the only secrets
/// deliberately written to the log (the operator reads them from the console);
/// everything else must never be logged at all. This redaction is therefore
/// defence-in-depth for the log VIEWER, which is a NEW read surface for those
/// two — an admin reading the endpoint must not be handed a live setup code.
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

/// A fixed-capacity, in-memory ring buffer of recent log records for the admin
/// log viewer. Attach it to `Logger.root.onRecord`; the oldest records fall off
/// once it is full. It is NOT persisted — a restart clears it.
class LogBuffer {
  /// Creates a buffer retaining up to [capacity] recent records.
  LogBuffer({this.capacity = 1000});

  /// Maximum records retained; `<= 0` disables buffering entirely.
  final int capacity;

  final ListQueue<LogEntry> _entries = ListQueue<LogEntry>();
  StreamSubscription<LogRecord>? _subscription;

  /// Distinct logger names seen so far, sorted — for the source filter.
  List<String> get loggers =>
      {for (final entry in _entries) entry.logger}.toList()..sort();

  /// Subscribes to [records] (typically `Logger.root.onRecord`). Replaces any
  /// previous subscription.
  void attach(Stream<LogRecord> records) {
    _subscription?.cancel();
    _subscription = records.listen(add);
  }

  /// Buffers one record, redacting secrets and lifting out its request id.
  void add(LogRecord record) {
    if (capacity <= 0) {
      return;
    }
    final rid = _rid.firstMatch(record.message);
    final stripped = rid == null
        ? record.message
        : record.message.replaceFirst(_rid, '');
    _entries.addLast(
      LogEntry(
        time: record.time.toIso8601String(),
        level: _bucket(record.level),
        logger: record.loggerName,
        message: redactLogMessage(stripped),
        requestId: rid?.group(1),
      ),
    );
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
  }

  /// Recent entries, NEWEST FIRST, optionally filtered. [minLevel] shows that
  /// bucket and above; [logger] is an exact name; [query] is a
  /// case-insensitive substring of the message or request id; [limit] caps the
  /// result count.
  List<LogEntry> entries({
    String? minLevel,
    String? logger,
    String? query,
    int limit = 200,
  }) {
    final minRank = minLevel == null ? 0 : (logLevelRank[minLevel] ?? 0);
    final needle = query?.trim().toLowerCase();
    final result = <LogEntry>[];
    for (final entry in _entries.toList().reversed) {
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
      result.add(entry);
      if (result.length >= limit) {
        break;
      }
    }
    return result;
  }

  /// Cancels the log subscription.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
