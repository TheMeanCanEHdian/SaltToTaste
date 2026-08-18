import 'dart:async';
import 'dart:convert';
import 'dart:io';

// dart_frog ships its own `requestLogger`; ours is the one under test.
import 'package:dart_frog/dart_frog.dart' hide requestLogger;
import 'package:logging/logging.dart';
import 'package:salt_server/src/handlers/admin_handlers.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/middleware/request_logger.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

LogRecord _rec(Level level, String logger, String message) =>
    LogRecord(level, message, logger);

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('salt_logstore_'));
  tearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  LogStore store({int maxBytes = 4 * 1024 * 1024}) =>
      LogStore(directory: dir.path, maxBytes: maxBytes);

  group('redaction', () {
    test('masks the setup code', () {
      expect(
        redactLogMessage('SaltToTaste setup code: D5UP-8J4X — open the app'),
        'SaltToTaste setup code: •••• — open the app',
      );
    });

    test('masks the recovery code, case-insensitively', () {
      expect(
        redactLogMessage('Recovery code: ABCD-1234'),
        'Recovery code: ••••',
      );
    });

    test('leaves ordinary messages alone', () {
      expect(redactLogMessage('GET /healthz -> 200'), 'GET /healthz -> 200');
    });
  });

  group('LogStore', () {
    test('reads records newest-first', () {
      final s = store();
      for (var i = 0; i < 5; i++) {
        s.add(_rec(Level.INFO, 'http', 'msg $i'));
      }
      expect(s.query().items.map((e) => e.message), [
        'msg 4',
        'msg 3',
        'msg 2',
        'msg 1',
        'msg 0',
      ]);
    });

    test('lifts the request id from the record, not the text', () {
      const message = RequestLogMessage(
        'GET /x -> 200 (5ms)',
        '0123456789abcdef',
      );
      final s = store()
        ..add(
          LogRecord(Level.INFO, '$message', 'http', null, null, null, message),
        );
      final entry = s.query().items.single;
      expect(entry.requestId, '0123456789abcdef');
      expect(entry.message, 'GET /x -> 200 (5ms)');
    });

    test('redacts the setup code on the way in — never on disk', () {
      store().add(_rec(Level.INFO, 'bootstrap', 'setup code: SECRET1 — open'));
      // The secret must not survive anywhere in the persisted file.
      final onDisk = File('${dir.path}/server.jsonl').readAsStringSync();
      expect(onDisk, contains('••••'));
      expect(onDisk, isNot(contains('SECRET1')));
    });

    test('buckets levels and filters by minLevel', () {
      final s = store()
        ..add(_rec(Level.FINE, 'a', 'd'))
        ..add(_rec(Level.INFO, 'a', 'i'))
        ..add(_rec(Level.WARNING, 'a', 'w'))
        ..add(_rec(Level.SEVERE, 'a', 'e'));
      expect(s.query().items.map((e) => e.level), [
        'ERROR',
        'WARN',
        'INFO',
        'DEBUG',
      ]);
      expect(s.query(minLevel: 'WARN').items.map((e) => e.message), ['e', 'w']);
    });

    test('filters by logger and by query (message or rid)', () {
      const cake = RequestLogMessage('chocolate cake', '00000000000000aa');
      final s = store()
        ..add(
          LogRecord(Level.INFO, '$cake', 'http', null, null, null, cake),
        )
        ..add(_rec(Level.INFO, 'auth', 'login ok'));
      expect(s.query(logger: 'auth').items.map((e) => e.message), ['login ok']);
      expect(s.query(query: 'CHOCOLATE').items.map((e) => e.logger), ['http']);
      expect(s.query(query: '00000000000000aa').items.single.logger, 'http');
      expect(s.query().loggers, ['auth', 'http']);
    });

    test('limit caps the result', () {
      final s = store();
      for (var i = 0; i < 10; i++) {
        s.add(_rec(Level.INFO, 'http', '$i'));
      }
      expect(s.query(limit: 3).items, hasLength(3));
    });

    test('maxBytes 0 disables the store', () {
      store(maxBytes: 0).add(_rec(Level.INFO, 'a', 'x'));
      expect(File('${dir.path}/server.jsonl').existsSync(), isFalse);
      expect(store(maxBytes: 0).query().items, isEmpty);
    });

    test('survives a restart — a new store reads the prior file', () {
      store().add(_rec(Level.INFO, 'http', 'before restart'));
      // A fresh store over the same directory — as if the process restarted.
      final reopened = store();
      expect(reopened.query().items.single.message, 'before restart');
    });

    test('rotates past maxBytes, keeping one generation and the newest', () {
      // Tiny cap: each record trips a rotation, so only recent records survive
      // across the active file + its single `.1` backup.
      final s = store(maxBytes: 200);
      for (var i = 0; i < 12; i++) {
        s.add(_rec(Level.INFO, 'http', 'm$i'));
      }
      final messages = s.query().items.map((e) => e.message).toList();
      expect(messages.first, 'm11', reason: 'newest is always retained');
      expect(messages, isNot(contains('m0')), reason: 'oldest rotated out');
      expect(messages.length, lessThan(12), reason: 'history is bounded');
      // At most the active file + one backup exist (no unbounded .2, .3, ...).
      expect(File('${dir.path}/server.jsonl.2').existsSync(), isFalse);
    });

    test('rotation resets the size counter — retention is not one line', () {
      // The in-memory counter that replaced the per-record lengthSync() is
      // load-bearing for S7, and only its SEED was pinned. Drop the reset in
      // _rotate() and it stays >= maxBytes forever, so EVERY subsequent record
      // rotates and the store keeps a single line per generation — 90%+ of
      // retained history silently destroyed, with the rest of the suite green.
      final s = store(maxBytes: 1024);
      for (var i = 0; i < 60; i++) {
        s.add(_rec(Level.INFO, 'http', 'msg $i'));
      }
      expect(
        s.query().items,
        hasLength(greaterThan(5)),
        reason: 'a full generation is retained, not one line per rotation',
      );
    });

    test('maxScanBytes reads only the tail of the file', () {
      final s = store();
      for (var i = 0; i < 60; i++) {
        s.add(_rec(Level.INFO, 'http', 'msg $i'));
      }
      // A small scan window: only the most recent lines are parsed.
      final tail = s
          .query(maxScanBytes: 400)
          .items
          .map((e) => e.message)
          .toList();
      expect(tail.first, 'msg 59', reason: 'newest is always present');
      expect(
        tail,
        isNot(contains('msg 0')),
        reason: 'lines beyond the window are not scanned',
      );
      expect(tail.length, lessThan(60), reason: 'the window bounds the scan');
      // Without the cap the whole file is read (proves the cap is what bounds).
      expect(s.query().items.map((e) => e.message), contains('msg 0'));
    });

    test('tail read keeps a complete oldest line at the window boundary', () {
      // Equal-length JSON lines, so a maxScanBytes that is an exact multiple of
      // the line length lands the window start ON a line boundary — the case
      // that used to drop that (complete, non-partial) boundary line.
      final lines = [
        for (var i = 0; i < 20; i++)
          jsonEncode(
            LogEntry(
              time: '2026-01-01T00:00:00.000',
              level: 'INFO',
              logger: 'http',
              message: 'row-${i.toString().padLeft(2, '0')}',
            ).toMap(),
          ),
      ];
      final lineLen = lines.first.length + 1; // + newline; all lines equal
      File(
        '${dir.path}/server.jsonl',
      ).writeAsStringSync(lines.map((l) => '$l\n').join());
      final s = store();
      // A 5-line window starts exactly on a line boundary (byte 15*lineLen).
      final got = s
          .query(maxScanBytes: 5 * lineLen)
          .items
          .map((e) => e.message)
          .toList();
      expect(
        got,
        hasLength(5),
        reason: 'the boundary line is kept, not dropped',
      );
      expect(got.last, 'row-15', reason: 'oldest line in the window survives');
    });

    test(
      'queryFull reads the whole history off-isolate, not just the tail',
      () async {
        final s = store();
        for (var i = 0; i < 60; i++) {
          s.add(_rec(Level.INFO, 'http', 'msg $i'));
        }
        // The capped sync read (the Live poll) misses the oldest lines.
        expect(
          s.query(maxScanBytes: 400).items.map((e) => e.message),
          isNot(contains('msg 0')),
        );
        // queryFull (on-demand search) scans everything, off the isolate.
        final full = await s.queryFull(limit: 100);
        expect(full.items.map((e) => e.message), contains('msg 0'));
        expect(
          full.items.first.message,
          'msg 59',
          reason: 'still newest-first',
        );
        final filtered = await s.queryFull(query: 'msg 42');
        expect(filtered.items.single.message, 'msg 42');
      },
    );

    test(
      'queryFull survives a file that errors on read (concurrent rotation)',
      () async {
        if (Platform.isWindows) {
          return; // the chmod trigger is POSIX-only; server runs on Linux.
        }
        final s = store()..add(_rec(Level.INFO, 'http', 'hello'));
        // File exists but the read fails — the exact shape of a rotation's
        // rename/delete landing between the existsSync check and the read on
        // the off-isolate scan. Must degrade to empty, not throw a 500.
        await Process.run('chmod', ['000', '${dir.path}/server.jsonl']);
        addTearDown(
          () => Process.run('chmod', ['644', '${dir.path}/server.jsonl']),
        );
        final result = await s.queryFull(limit: 10);
        expect(result.items, isEmpty, reason: 'unreadable file skipped');
      },
    );

    test(
      'add() swallows write failures — best-effort logging never throws',
      () {
        final s = store();
        // A directory where the active file should be makes every write throw;
        // add() must DROP the record, not poison the request path (it runs on
        // Logger.root for every request).
        Directory('${dir.path}/server.jsonl').createSync(recursive: true);
        expect(() => s.add(_rec(Level.INFO, 'http', 'x')), returnsNormally);
      },
    );

    test('attach consumes a record stream', () async {
      final controller = StreamController<LogRecord>.broadcast();
      final s = store()..attach(controller.stream);
      controller.add(_rec(Level.INFO, 'http', 'streamed'));
      await Future<void>.delayed(Duration.zero);
      expect(s.query().items.single.message, 'streamed');
      await s.dispose();
      await controller.close();
    });
  });

  group('attacker-controlled input', () {
    test('caps an oversized message, with a marker naming the loss', () {
      // Retention is a fixed byte budget, so an unbounded message is an
      // eviction primitive (S7). The cut must be visible: a silently truncated
      // line reads like the real thing.
      final s = store()..add(_rec(Level.INFO, 'http', 'A' * 10000));
      final message = s.query().items.single.message;
      expect(message.length, lessThan(10000));
      expect(message, startsWith('A' * maxLogTextChars));
      expect(
        message,
        endsWith(
          '[+${10000 - maxLogTextChars} chars '
          'truncated]',
        ),
      );
    });

    test('an oversized message cannot evict the exception and stack', () {
      // The text budget exists for this: a head-keeping cap over the FINISHED
      // concatenation let an attacker-sized message prefix push the exception
      // type and every frame past the cut, so the stored crash record was the
      // attacker's own text and nothing else — S15 defeated by the very
      // request that crashed the server.
      final s = store()
        ..add(
          LogRecord(
            Level.SEVERE,
            'Unhandled error on GET /${'A' * 10000}',
            'http',
            StateError('sensitive internal detail'),
            StackTrace.current,
          ),
        );
      final message = s.query().items.single.message;
      expect(message, contains('StateError'));
      expect(message, contains('sensitive internal detail'));
      expect(message, contains('#0'));
      expect(message.length, lessThanOrEqualTo(maxLogMessageChars + 64));
    });

    test('the text budget is small enough to keep a deep stack', () {
      // maxLogTextChars is a VALUE, not just a mechanism: whatever it is comes
      // straight off the record's total budget, so raising it silently eats
      // frames off the other end. The test above proves SOME of the stack
      // survives; this one pins how much. Measured on the record below: at
      // 1 KiB it keeps 104 of its 120 frames, at 4 KiB only 59 — and every
      // other test in this file stays green either way.
      const frames = 120;
      const frame =
          '      package:salt_server/src/handlers/auth_handlers.dart 471:22';
      final stack = StackTrace.fromString(
        [
          for (var i = 0; i < frames; i++)
            '#${i.toString().padLeft(3, '0')}$frame',
        ].join('\n'),
      );
      final s = store()
        ..add(
          LogRecord(
            Level.SEVERE,
            'Unhandled error on GET /${'A' * 10000}',
            'http',
            StateError('boom'),
            stack,
          ),
        );
      final kept = RegExp(
        r'^#\d+ ',
        multiLine: true,
      ).allMatches(s.query().items.single.message).length;
      expect(
        kept,
        greaterThanOrEqualTo(95),
        reason:
            'the emitter-text budget grew and ate the forensic tail: a '
            'record capped at $maxLogMessageChars chars cannot spend '
            '$maxLogTextChars of them on attacker text',
      );
    });

    test('a `rid=` in the message text cannot supply the request id', () {
      // The store does not parse an id out of text at all any more. The
      // anchored fallback that replaced the unanchored scan (S8) still let any
      // emitter whose message ENDS with attacker text set the field AND have
      // that text silently deleted — e.g. import's 'Failed to import <name>'.
      final s = store()
        ..add(
          _rec(
            Level.INFO,
            'importer',
            'Failed to import cake.yaml rid=deadbeefdeadbeef',
          ),
        );
      final entry = s.query().items.single;
      expect(entry.requestId, isNull, reason: 'ids are data, never text');
      expect(
        entry.message,
        'Failed to import cake.yaml rid=deadbeefdeadbeef',
        reason: 'and nothing is silently stripped out of the record',
      );
    });

    test('a structured request id is taken from the record, not the text', () {
      const message = RequestLogMessage(
        'GET /rid=00000000000000ff/probe -> 404 (1ms)',
        'deadbeefdeadbeef',
      );
      final s = store()
        ..add(
          LogRecord(Level.INFO, '$message', 'http', null, null, null, message),
        );
      final entry = s.query().items.single;
      expect(entry.requestId, 'deadbeefdeadbeef');
      expect(entry.message, contains('/rid=00000000000000ff/probe'));
    });

    test('an exception and its stack are persisted, redacted', () {
      // S15: the store kept only record.message, so a 500 was retained with no
      // type, message or frame. Both new parts must pass through the SAME
      // redaction — a secret in an exception string is still a secret.
      const summary = RequestLogMessage(
        'Unhandled error on POST /x',
        'deadbeefdeadbeef',
      );
      final s = store()
        ..add(
          LogRecord(
            Level.SEVERE,
            '$summary',
            'http',
            StateError('rejected, recovery code: HUNTER2'),
            StackTrace.current,
            null,
            summary,
          ),
        );
      final entry = s.query().items.single;
      expect(entry.requestId, 'deadbeefdeadbeef');
      expect(entry.message, contains('StateError'));
      expect(entry.message, contains('#0'));
      expect(entry.message, contains('recovery code: ••••'));
      expect(entry.message, isNot(contains('HUNTER2')));
      // ...and nothing survives unredacted on disk either.
      final onDisk = File('${dir.path}/server.jsonl').readAsStringSync();
      expect(onDisk, isNot(contains('HUNTER2')));
    });

    test('a reopened store rotates on the existing size, not from zero', () {
      // The size is tracked in memory now (no stat per pre-auth record), so a
      // fresh store over an existing file must seed the counter from disk —
      // otherwise a restart grants a whole extra maxBytes of growth.
      final first = store(maxBytes: 400);
      final file = File('${dir.path}/server.jsonl');
      do {
        first.add(_rec(Level.INFO, 'http', 'filling'));
      } while (file.lengthSync() < 300);
      final before = file.lengthSync();
      store(maxBytes: 400).add(_rec(Level.INFO, 'http', 'after restart'));
      expect(
        File('${dir.path}/server.jsonl.1').existsSync(),
        isTrue,
        reason: 'the pre-existing $before bytes count toward maxBytes',
      );
    });
  });

  group('request logging over a real chain', () {
    late HttpServer server;
    late Uri baseUri;
    late LogStore logStore;

    setUp(() async {
      logStore = store();
      Logger.root.level = Level.ALL;
      logStore.attach(Logger.root.onRecord);
      Response dispatch(RequestContext context) {
        // startsWith, not ==: the flood/eviction tests must be able to drive
        // the EXPENSIVE (500 + persisted stack) path with a long path too.
        if (context.request.uri.path.startsWith('/boom')) {
          throw StateError('sensitive internal detail');
        }
        return Response(body: 'ok');
      }

      // The real middlewares, in the production order (outermost last).
      final pipeline = const Pipeline()
          .addMiddleware(requestIdProvider())
          .addMiddleware(requestLogger())
          .addMiddleware(errorHandler())
          .addHandler(dispatch);
      server = await serve(pipeline, InternetAddress.loopbackIPv4, 0);
      baseUri = Uri.parse('http://127.0.0.1:${server.port}');
    });

    tearDown(() async {
      await logStore.dispose();
      await server.close(force: true);
    });

    Future<HttpClientResponse> send(String path) async {
      final client = HttpClient();
      try {
        final request = await client.getUrl(baseUri.resolve(path));
        final response = await request.close();
        await response.drain<void>();
        return response;
      } finally {
        client.close();
      }
    }

    test('a 100 KB request path cannot flood the store', () async {
      // HttpServer imposes no request-line limit, and the store keeps a fixed
      // number of BYTES — so an uncapped path let an unauthenticated peer
      // rotate all retained history out in a few dozen requests (S7).
      await send('/${'a' * (100 * 1024)}');
      await Future<void>.delayed(Duration.zero);
      final entry = logStore.query().items.single;
      expect(entry.message.length, lessThan(maxLoggedPathChars + 128));
      expect(entry.message, contains('…[+'));
      expect(
        File('${dir.path}/server.jsonl').lengthSync(),
        lessThan(1024),
        reason: 'one junk request costs the store well under a KiB',
      );
    });

    test(
      'a 100 KB request path on the 500 path cannot flood it either',
      () async {
        // The EXPENSIVE path, which the flood test above does not exercise: a
        // 500 persists the exception and the full stack as well, and the error
        // handler formats the same attacker-chosen path into its own record.
        // Both records must stay bounded, and — the S15 point — the forensics
        // must survive a path chosen to evict them.
        final response = await send('/boom/${'a' * (100 * 1024)}');
        expect(response.statusCode, HttpStatus.internalServerError);
        await Future<void>.delayed(Duration.zero);
        final entry = logStore.query(minLevel: 'ERROR').items.single;
        expect(entry.message, contains('…[+'), reason: 'path is capped');
        expect(entry.message, contains('StateError'));
        expect(entry.message, contains('sensitive internal detail'));
        expect(entry.message, contains('#0'));
        expect(entry.requestId, response.headers.value(requestIdHeader));
        expect(entry.requestId, isNotNull);
        // Measured on this chain: 4,939 bytes for the pair of records (INFO
        // access line + ERROR with its whole stack), independent of the 100 KB
        // path. Uncapped it was 8,741 — and that larger record was pure
        // attacker padding, with the stack evicted.
        expect(
          File('${dir.path}/server.jsonl').lengthSync(),
          lessThan(6 * 1024),
          reason: 'one junk 500 costs a bounded, mostly-forensic ~5 KiB',
        );
      },
    );

    test(
      'the stored request id is the server id, not one from the path',
      () async {
        final response = await send('/rid=00000000000000ff/secret-probe');
        await Future<void>.delayed(Duration.zero);
        final entry = logStore.query().items.single;
        expect(entry.requestId, response.headers.value(requestIdHeader));
        expect(entry.requestId, isNot('00000000000000ff'));
        expect(
          entry.message,
          contains('/rid=00000000000000ff/secret-probe'),
          reason: 'the viewer must show what was actually requested',
        );
      },
    );

    test('a 500 is retained WITH its exception and stack', () async {
      final response = await send('/boom');
      expect(response.statusCode, HttpStatus.internalServerError);
      await Future<void>.delayed(Duration.zero);
      final entry = logStore.query(minLevel: 'ERROR').items.single;
      expect(entry.message, contains('Unhandled error on GET /boom'));
      expect(entry.message, contains('StateError'));
      expect(entry.message, contains('sensitive internal detail'));
      expect(entry.message, contains('#0'));
      expect(entry.requestId, response.headers.value(requestIdHeader));
      // The cap is sized from this: a real crash record must fit whole.
      expect(entry.message.length, lessThan(maxLogMessageChars));
      printOnFailure('crash record: ${entry.message.length} chars');
    });
  });

  group('logsHandler', () {
    test('returns items (newest first) and loggers', () async {
      final s = store()
        ..add(_rec(Level.INFO, 'http', 'one'))
        ..add(_rec(Level.WARNING, 'auth', 'two'));
      final body = await logsHandler(s, limit: 10);
      final items = body['items']! as List;
      expect(items, hasLength(2));
      expect((items.first as Map)['message'], 'two');
      expect(body['loggers'], containsAll(<String>['http', 'auth']));
    });

    test('limit caps the result', () async {
      final s = store();
      for (var i = 0; i < 10; i++) {
        s.add(_rec(Level.INFO, 'http', '$i'));
      }
      final body = await logsHandler(s, limit: 3);
      expect(body['items']! as List, hasLength(3));
    });

    test('fullScan reaches a quiet logger the tail window misses', () async {
      // A single old 'bootstrap' line, then > 512 KiB of recent http lines, so
      // the marker is OUTSIDE the tail window but inside the full history. This
      // distinguishes the two handler branches — a small seeded file where tail
      // and full return the same rows would not.
      final buffer = StringBuffer()
        ..writeln(
          jsonEncode(
            const LogEntry(
              time: '2020-01-01T00:00:00.000',
              level: 'INFO',
              logger: 'bootstrap',
              message: 'boot marker',
            ).toMap(),
          ),
        );
      var i = 0;
      while (buffer.length < 600 * 1024) {
        buffer.writeln(
          jsonEncode(
            LogEntry(
              time: '2026-01-01T00:00:00.000',
              level: 'INFO',
              logger: 'http',
              message: 'padding line $i to push the marker past the tail',
            ).toMap(),
          ),
        );
        i++;
      }
      File('${dir.path}/server.jsonl').writeAsStringSync(buffer.toString());
      final s = store();

      // The tail window (512 KiB) can't see the old bootstrap line...
      final tail = await logsHandler(s, logger: 'bootstrap', limit: 100);
      expect(tail['items']! as List, isEmpty, reason: 'tail excludes it');
      // ...but the full scan reaches it — the whole reason fullScan exists.
      final full = await logsHandler(
        s,
        logger: 'bootstrap',
        limit: 100,
        fullScan: true,
      );
      expect(
        [for (final e in full['items']! as List) (e as Map)['message']],
        contains('boot marker'),
      );
    });

    test(
      'dropdown lists loggers from full history, even a quiet old one',
      () async {
        // 'bootstrap' logged once, then > 512 KiB of http lines — bootstrap is
        // outside the tail window a Live poll reads, but stays selectable.
        final buffer = StringBuffer()
          ..writeln(
            jsonEncode(
              const LogEntry(
                time: '2020-01-01T00:00:00.000',
                level: 'INFO',
                logger: 'bootstrap',
                message: 'boot',
              ).toMap(),
            ),
          );
        var i = 0;
        while (buffer.length < 600 * 1024) {
          buffer.writeln(
            jsonEncode(
              LogEntry(
                time: '2026-01-01T00:00:00.000',
                level: 'INFO',
                logger: 'http',
                message: 'padding $i',
              ).toMap(),
            ),
          );
          i++;
        }
        File('${dir.path}/server.jsonl').writeAsStringSync(buffer.toString());
        final s = store();
        // Boot seeds the known-logger set from history.
        final controller = StreamController<LogRecord>.broadcast();
        s.attach(controller.stream);
        // A tail poll (fullScan:false) still lists the out-of-window logger.
        final poll = await logsHandler(s, limit: 100);
        expect(poll['loggers'], containsAll(<String>['bootstrap', 'http']));
        await controller.close();
        await s.dispose();
      },
    );
  });

  group('logsExportHandler', () {
    test('renders every record oldest-first with a .log filename', () {
      final s = store()
        ..add(_rec(Level.INFO, 'http', 'first'))
        ..add(_rec(Level.WARNING, 'auth', 'second'));
      final export = logsExportHandler(s);
      final lines = const LineSplitter().convert(export.body);
      expect(lines, hasLength(2));
      expect(lines.first, contains('INFO http first'));
      expect(lines.last, contains('WARN auth second'));
      expect(lines.first.indexOf('first'), isNonNegative);
      // Oldest first: 'first' precedes 'second'.
      expect(
        export.body.indexOf('first'),
        lessThan(export.body.indexOf('second')),
      );
      expect(export.filename, startsWith('salttotaste-logs-'));
      expect(export.filename, endsWith('.log'));
      expect(export.filename, isNot(contains(':')));
    });

    test('a multi-line crash keeps its rid on the header line', () {
      // ERROR records are routinely multi-line now (exception + stack below
      // the summary). Appending ' rid=<id>' after the message put a crash's
      // correlation id on its LAST stack frame while the header line — the one
      // a reader scans — carried none.
      const summary = RequestLogMessage(
        'Unhandled error on GET /boom',
        'deadbeefdeadbeef',
      );
      final s = store()
        ..add(
          LogRecord(
            Level.SEVERE,
            '$summary',
            'http',
            StateError('kaboom'),
            StackTrace.current,
            null,
            summary,
          ),
        );
      final lines = const LineSplitter().convert(logsExportHandler(s).body);
      expect(lines.length, greaterThan(1), reason: 'the stack is persisted');
      expect(lines.first, contains('ERROR http rid=deadbeefdeadbeef'));
      expect(lines.first, endsWith('Unhandled error on GET /boom'));
      expect(lines.last, isNot(contains('rid=')));
      expect(
        lines.skip(1),
        everyElement(startsWith('  ')),
        reason:
            'continuation lines are indented, so a reader can tell them '
            'from the start of the next record',
      );
    });

    test('appends the request id and honors filters, with no row cap', () {
      final s = store();
      for (var i = 0; i < 500; i++) {
        s.add(_rec(Level.INFO, 'http', 'req $i rid=00000000000000${i % 10}0'));
      }
      s.add(_rec(Level.SEVERE, 'nutrition', 'boom'));

      // No 300-row cap on export: all 500 http lines come through.
      final all = logsExportHandler(s, logger: 'http');
      expect(const LineSplitter().convert(all.body), hasLength(500));
      expect(all.body, contains('rid=0000000000000000'));

      // Level filter narrows to the one error.
      final errors = logsExportHandler(s, level: 'ERROR');
      final errorLines = const LineSplitter().convert(errors.body);
      expect(errorLines, hasLength(1));
      expect(errorLines.single, contains('ERROR nutrition boom'));
    });
  });
  group('a database exception cannot carry a secret to disk', () {
    // SqliteException.toString() renders the causing statement AND its bound
    // parameters. Persisting record.error (review S15) therefore turned any
    // DB-level failure into a disclosure: a SQLITE_BUSY while rotating a
    // password writes the argon2 hash, and one while saving the FoodData
    // Central key writes that key in plaintext — both then readable over
    // GET /api/v1/admin/logs. Crafted exception strings, since no real input
    // can force SQLITE_FULL on demand.
    test('bound parameters are masked, the statement is kept', () {
      const fdcKey = 'DEMO0000LIVEKEY0000';
      final rendered = redactLogMessage(
        'SqliteException(13): database or disk is full\n'
        '  Causing statement: INSERT INTO settings (key, value) VALUES (?, ?), '
        'parameters: fdc_api_key, $fdcKey',
      );
      expect(rendered, contains('INSERT INTO settings'));
      expect(rendered, contains('database or disk is full'));
      expect(
        rendered,
        isNot(contains(fdcKey)),
        reason: 'the live API key must not survive redaction',
      );
      expect(
        rendered,
        isNot(contains('fdc_api_key,')),
        reason: 'everything after "parameters:" goes, not just the last value',
      );
    });

    test('an argon2 hash bound to a password rotation is masked', () {
      const phc =
          r'$argon2id$v=19$m=19456,t=2,p=1$c29tZXNhbHQ$aGFzaHZhbHVlaGVyZQ';
      final rendered = redactLogMessage(
        'SqliteException(5): database is locked\n'
        '  Causing statement: UPDATE users SET password_hash = ? WHERE id = ?, '
        'parameters: $phc, 7',
      );
      expect(rendered, contains('UPDATE users SET password_hash'));
      expect(rendered, isNot(contains(phc)));
    });
  });
}
