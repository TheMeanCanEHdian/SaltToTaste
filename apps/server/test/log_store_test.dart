import 'dart:async';
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
    test('returns items (newest first) and loggers', () {
      final s = store()
        ..add(_rec(Level.INFO, 'http', 'one'))
        ..add(_rec(Level.WARNING, 'auth', 'two'));
      final body = logsHandler(s, limit: 10);
      final items = body['items']! as List;
      expect(items, hasLength(2));
      expect((items.first as Map)['message'], 'two');
      expect(body['loggers'], containsAll(<String>['http', 'auth']));
    });

    test('limit caps the result', () {
      final s = store();
      for (var i = 0; i < 10; i++) {
        s.add(_rec(Level.INFO, 'http', '$i'));
      }
      expect(logsHandler(s, limit: 3)['items']! as List, hasLength(3));
    });
  });
}
