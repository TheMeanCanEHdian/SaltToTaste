import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/handlers/admin_handlers.dart';
import 'package:salt_server/src/logging/log_store.dart';
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

    test('lifts and strips the request id', () {
      final s = store()
        ..add(
          _rec(Level.INFO, 'http', 'GET /x -> 200 (5ms) rid=0123456789abcdef'),
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
      final s = store()
        ..add(_rec(Level.INFO, 'http', 'chocolate cake rid=00000000000000aa'))
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

    test('fullScan reads the whole history, not just the tail', () async {
      final s = store();
      for (var i = 0; i < 60; i++) {
        s.add(_rec(Level.INFO, 'http', 'msg $i'));
      }
      final tail = await logsHandler(s, limit: 100);
      final full = await logsHandler(s, limit: 100, fullScan: true);
      // Both return the newest; only the full scan reaches the oldest lines
      // here (the seeded file is small, so assert on behavior via a huge store
      // is unnecessary — fullScan wires queryFull, covered in the store tests).
      expect(tail['items']! as List, isNotEmpty);
      expect(
        [for (final e in full['items']! as List) (e as Map)['message']],
        contains('msg 0'),
      );
    });
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
}
