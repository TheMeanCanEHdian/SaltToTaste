import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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

/// A log message that carries its request id as DATA rather than only as text.
///
/// `package:logging` keeps a non-String message on `LogRecord.object`, so
/// [LogStore.add] reads the id from the record instead of scraping it out of a
/// line the attacker shares (the request path is logged verbatim, and a path
/// like `/rid=00000000000000ff/probe` used to supply the stored id and delete
/// itself from the message — review S8). This is the ONLY way a record gets a
/// `request_id`: the store no longer parses one out of text at all, so no
/// emitter — present or future — can hand an attacker that field. [toString]
/// keeps the on-stdout format unchanged.
class RequestLogMessage {
  /// Wraps [text] with the server-generated [requestId] (null when the request
  /// id middleware is not installed).
  const RequestLogMessage(this.text, this.requestId);

  /// The formatted message, WITHOUT the `rid=` suffix.
  final String text;

  /// The server-generated request id, or null.
  final String? requestId;

  @override
  String toString() => '$text rid=${requestId ?? '-'}';
}

/// Longest request path written to a log record, in characters.
///
/// The path is attacker-chosen and `HttpServer` imposes no request-line limit
/// (a 200 KB path is accepted), while the log store retains a fixed number of
/// BYTES — so an uncapped path let an unauthenticated peer rotate all retained
/// history out in a few dozen requests (review S7). The longest path this app
/// can legitimately serve is `/images/<source>/<file>`; measured against the
/// 1,198-recipe ATK corpus that is 176 characters (a 62-char source slug plus
/// the 105-char longest image filename), and the longest API route with the
/// longest recipe id is 128. 256 keeps ~45% headroom over the real maximum;
/// nothing longer can address a resource that exists.
///
/// A path over the cap is cut with a marker stating how much was dropped —
/// never silently, which would make an attack read like an ordinary request.
const int maxLoggedPathChars = 256;

/// [path] bounded to [maxLoggedPathChars] for logging.
///
/// Lives HERE, next to the store, rather than in one middleware: every emitter
/// that formats a request path into a log line must route through it. The cap
/// was first applied only in `requestLogger`, and the sibling emitter in
/// `errorHandler` kept logging the raw path — one call site fixed, the finding
/// retired, the hole open (review P1).
String loggedPath(String path) => path.length <= maxLoggedPathChars
    ? path
    : '${path.substring(0, maxLoggedPathChars)}'
          '…[+${path.length - maxLoggedPathChars} chars]';

/// Longest message persisted per record, in characters — including any
/// exception and stack appended below it.
///
/// Retention is a fixed byte budget shared by every record, so an unbounded
/// message is an eviction primitive (S7) — and once stacks are persisted
/// (S15), a 500-storm is the same primitive. Measured: a real unhandled-error
/// record produced by this server's own middleware chain (message + the
/// exception + the FULL stack, down to the isolate bottom) is ~4,120
/// characters, so 8 KiB retains every frame of a genuine crash with room for a
/// deeper production chain, while still bounding a flood.
const int maxLogMessageChars = 8192;

/// Longest EMITTER TEXT persisted per record, before the exception and stack
/// are appended below it.
///
/// The text is the only part of a record an attacker can grow — it is where a
/// request path gets formatted in. A single head-keeping cap over the finished
/// concatenation therefore inverted the whole point of S15: a long enough path
/// pushed the exception type and every `#0` frame past the cut, so the stored
/// crash record was 8 KiB of the attacker's own path and nothing else. Giving
/// the text its own budget means the forensic tail is reserved and cannot be
/// evicted by anything the caller chooses. 1 KiB is ~3x the longest line this
/// server emits (method + the 256-char path cap + status + timing + client IP).
const int maxLogTextChars = 1024;

/// [message] with the record's exception and stack appended, when it carries
/// them.
///
/// `errorHandler` deliberately keeps the exception out of the response envelope
/// and logs it with the record — but the store persisted the message ALONE, so
/// the admin viewer showed every 500 as `Unhandled error on POST …` with no
/// type, no message and no frame (S15). Both go through the same
/// [redactLogMessage] the message does: an exception string or a frame can
/// carry a secret, and "secrets never logged" is binding.
String _withError(String message, LogRecord record) {
  final error = record.error;
  final stack = record.stackTrace;
  if (error == null && stack == null) {
    return message;
  }
  final buffer = StringBuffer(message);
  if (error != null) {
    // The type is NOT redundant: `StateError.toString()` is "Bad state: …"
    // and names nothing, and triage starts from the type.
    buffer.write('\n${error.runtimeType}: $error');
  }
  if (stack != null) {
    buffer.write('\n$stack');
  }
  return buffer.toString();
}

/// [message] bounded to [max], with a marker naming what was dropped — a
/// truncation the reader can see beats a line that lies.
String _cap(String message, int max) => message.length <= max
    ? message
    : '${message.substring(0, max)}'
          '\n[+${message.length - max} chars truncated]';

/// The persisted `message` for [record]: the emitter's [text] bounded on its
/// own, THEN the exception and stack appended, then the whole bounded again.
///
/// Two budgets, not one: see [maxLogTextChars]. Redaction runs before each cut
/// — the cap must never be what saves a secret, and a secret must not survive
/// by sitting past a cut.
String _composeMessage(String text, LogRecord record) {
  final capped = _cap(redactLogMessage(text), maxLogTextChars);
  return _cap(
    redactLogMessage(_withError(capped, record)),
    maxLogMessageChars,
  );
}

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
  int? _bytes;
  final Set<String> _knownLoggers = {};
  bool _loggersSeeded = false;

  String get _path => '$directory/server.jsonl';
  String get _backupPath => '$_path.1';

  /// Subscribes to [records] (typically `Logger.root.onRecord`).
  void attach(Stream<LogRecord> records) {
    if (maxBytes <= 0) {
      return;
    }
    _ensureDir();
    _seedKnownLoggers();
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

  /// One-off at boot: learn every logger already in the persisted history so
  /// the viewer's dropdown lists loggers whose records predate this process OR
  /// fall outside the Live-poll tail window. Kept fresh thereafter by [add].
  void _seedKnownLoggers() {
    if (_loggersSeeded) {
      return;
    }
    _loggersSeeded = true;
    _knownLoggers.addAll(
      _scanLogFiles(
        activePath: _path,
        backupPath: _backupPath,
        limit: 1,
      ).loggers,
    );
  }

  /// Every logger name that has appeared in the store — the FULL-history set
  /// for the viewer's filter dropdown, independent of the tail window a Live
  /// poll reads (a query's own `loggers` only covers the lines it scanned).
  List<String> get knownLoggers => _knownLoggers.toList()..sort();

  /// Appends one record (redacted, capped, request id lifted, any exception and
  /// stack persisted with it) to the active file, then rotates if it has grown
  /// past [maxBytes]. Writes are synchronous so a reader always sees complete
  /// lines and no flush lag.
  void add(LogRecord record) {
    if (maxBytes <= 0) {
      return;
    }
    // Record the logger for the dropdown even if the write below fails — the
    // logger IS active regardless of whether this line reached disk.
    _knownLoggers.add(record.loggerName);
    // Logging is best-effort and runs on EVERY request (via Logger.root): a
    // read-only or full data dir — or an object whose toString throws — must
    // never turn a log line into an uncaught error on the root zone. Create the
    // dir once (not per record), then swallow failures: a dropped log line
    // beats a poisoned request.
    try {
      final object = record.object;
      // The request id is SERVER-generated and only ever travels as data. An
      // emitter that did not pass a RequestLogMessage gets request_id: null
      // and its text verbatim — recovering an id from message text is what let
      // a path (and later, any message ending in attacker text) set the field
      // and silently delete itself from the record (S8 / review P5).
      final text = object is RequestLogMessage ? object.text : record.message;
      final requestId = object is RequestLogMessage ? object.requestId : null;
      final entry = LogEntry(
        // package:logging stamps LOCAL time; the API convention is UTC with a
        // Z suffix, and every other timestamp complies — a local wall clock
        // here made log/backup correlation off by the server's UTC offset
        // (review B19). Older stored lines keep their local form.
        time: record.time.toUtc().toIso8601String(),
        level: _bucket(record.level),
        logger: record.loggerName,
        message: _composeMessage(text, record),
        requestId: requestId,
      );
      _ensureDir();
      final line = utf8.encode('${jsonEncode(entry.toMap())}\n');
      // Track the size instead of stat-ing the file per record: this runs on
      // the serving isolate for every PRE-AUTH request, so the syscall is one
      // an unauthenticated peer gets to schedule (S7 aggravator). Seeded from
      // disk on the first write of a process, reset by _rotate.
      _bytes ??= _lengthOnDisk();
      File(_path).writeAsBytesSync(line, mode: FileMode.append);
      _bytes = _bytes! + line.length;
      if (_bytes! >= maxBytes) {
        _rotate();
      }
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      // The counter may not reflect what actually reached disk; re-seed it.
      _bytes = null;
    }
  }

  int _lengthOnDisk() {
    final file = File(_path);
    return file.existsSync() ? file.lengthSync() : 0;
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
    _bytes = 0;
  }

  /// Reads the store (rotation + active file) SYNCHRONOUSLY, newest first,
  /// filtered. [minLevel] shows that bucket and above; [logger] is an exact
  /// name; [query] is a case-insensitive substring of the message or request
  /// id; [limit] caps the item count. Also returns the distinct logger names.
  ///
  /// [maxScanBytes] bounds how much of the END of each file is read+parsed. The
  /// Live poll passes a cap so a recurring poll stays a few ms regardless of
  /// the on-disk size — it only needs recent lines. Pass null for the whole
  /// history, but only where a synchronous full parse is acceptable (a one-off,
  /// or a small store); the viewer's on-demand full search uses [queryFull].
  LogQueryResult query({
    String? minLevel,
    String? logger,
    String? query,
    int limit = 300,
    int? maxScanBytes,
  }) => _scanLogFiles(
    activePath: _path,
    backupPath: _backupPath,
    minLevel: minLevel,
    logger: logger,
    query: query,
    limit: limit,
    maxScanBytes: maxScanBytes,
  );

  /// Like [query] but reads the WHOLE history (no tail cap) OFF the serving
  /// isolate, so a full-history filter/search over a large log doesn't stall
  /// other requests. Used on demand (an explicit filter/search), NOT for the
  /// recurring Live poll. The result is capped at [limit], so only a small page
  /// — not the whole parsed log — crosses the isolate boundary back.
  Future<LogQueryResult> queryFull({
    String? minLevel,
    String? logger,
    String? query,
    int limit = 300,
  }) {
    // Capture sendable values; the closure must not reference `this`.
    final activePath = _path;
    final backupPath = _backupPath;
    return Isolate.run(
      () => _scanLogFiles(
        activePath: activePath,
        backupPath: backupPath,
        minLevel: minLevel,
        logger: logger,
        query: query,
        limit: limit,
      ),
    );
  }

  /// Cancels the log subscription.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}

/// Reads + parses + filters the two log files, newest first. Top-level (not a
/// method) and using only sendable arguments so it can run either inline (the
/// sync tail read) or inside `Isolate.run` (the off-isolate full read) — a
/// method closing over `this` could not cross the isolate boundary.
///
/// [LogEntry] is built directly from the decoded map rather than via its
/// `dart_mappable` mapper, which would need re-initialising in a fresh isolate.
LogQueryResult _scanLogFiles({
  required String activePath,
  required String backupPath,
  required int limit,
  String? minLevel,
  String? logger,
  String? query,
  int? maxScanBytes,
}) {
  final minRank = minLevel == null ? 0 : (logLevelRank[minLevel] ?? 0);
  final needle = query?.trim().toLowerCase();

  final all = <LogEntry>[];
  // Oldest generation first, then active — so file order is oldest→newest.
  for (final path in [backupPath, activePath]) {
    for (final line in _tailLinesOf(File(path), maxScanBytes)) {
      if (line.trim().isEmpty) {
        continue;
      }
      try {
        final map = jsonDecode(line) as Map<String, dynamic>;
        all.add(
          LogEntry(
            time: map['time'] as String,
            level: map['level'] as String,
            logger: map['logger'] as String,
            message: map['message'] as String,
            requestId: map['request_id'] as String?,
          ),
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

/// The lines of [file], or only those within the last [maxScanBytes] when it is
/// set — reading from the end and dropping the partial line the window sliced
/// through. Bounds the parse cost to the tail when a caller needs recent lines.
///
/// A file error (missing, or read-failed) yields an empty list rather than
/// throwing: on the OFF-ISOLATE full-scan path ([LogStore.queryFull]) the read
/// runs in a worker isolate that can race the serving isolate's rotation, which
/// renames/deletes the file out from under it between the `existsSync` check and
/// the read. That must degrade to "this file contributed nothing on this pass"
/// (the next read sees the rotated file), not surface as a 500.
List<String> _tailLinesOf(File file, int? maxScanBytes) {
  try {
    if (!file.existsSync()) {
      return const [];
    }
    final length = file.lengthSync();
    if (maxScanBytes == null || length <= maxScanBytes) {
      return file.readAsLinesSync();
    }
    // Read ONE byte before the window too. That lookback byte says whether the
    // window began on a line boundary: if it's a newline, the window's first
    // line is COMPLETE (keep it — drop only the lookback newline); otherwise
    // the window sliced through a line and we drop that partial remainder (up
    // to and including its terminating newline). `length > maxScanBytes` here,
    // so the window start is >= 1 and the lookback never underflows.
    final from = length - maxScanBytes - 1;
    final handle = file.openSync();
    try {
      final bytes = (handle..setPositionSync(from)).readSync(length - from);
      final text = utf8.decode(bytes, allowMalformed: true);
      final String kept;
      if (text.startsWith('\n')) {
        kept = text.substring(1);
      } else {
        final firstBreak = text.indexOf('\n');
        kept = firstBreak < 0 ? '' : text.substring(firstBreak + 1);
      }
      return const LineSplitter().convert(kept);
    } finally {
      handle.closeSync();
    }
  } on FileSystemException {
    return const [];
  }
}
