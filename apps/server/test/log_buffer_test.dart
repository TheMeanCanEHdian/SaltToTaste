import 'dart:async';

import 'package:logging/logging.dart';
import 'package:salt_server/src/handlers/admin_handlers.dart';
import 'package:salt_server/src/logging/log_buffer.dart';
import 'package:test/test.dart';

LogRecord _rec(Level level, String logger, String message) =>
    LogRecord(level, message, logger);

void main() {
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

  group('LogBuffer', () {
    test('keeps newest-first and evicts past capacity', () {
      final buffer = LogBuffer(capacity: 3);
      for (var i = 0; i < 5; i++) {
        buffer.add(_rec(Level.INFO, 'http', 'msg $i'));
      }
      expect(
        buffer.entries().map((e) => e.message),
        ['msg 4', 'msg 3', 'msg 2'],
      );
    });

    test('lifts and strips the request id', () {
      final buffer = LogBuffer()
        ..add(
          _rec(Level.INFO, 'http', 'GET /x -> 200 (5ms) rid=0123456789abcdef'),
        );
      final entry = buffer.entries().single;
      expect(entry.requestId, '0123456789abcdef');
      expect(entry.message, 'GET /x -> 200 (5ms)');
    });

    test('redacts the setup code on the way in', () {
      final buffer = LogBuffer()
        ..add(_rec(Level.INFO, 'bootstrap', 'setup code: SECRET1 — open'));
      final message = buffer.entries().single.message;
      expect(message, contains('••••'));
      expect(message, isNot(contains('SECRET1')));
    });

    test('buckets levels and filters by minLevel', () {
      final buffer = LogBuffer()
        ..add(_rec(Level.FINE, 'a', 'd'))
        ..add(_rec(Level.INFO, 'a', 'i'))
        ..add(_rec(Level.WARNING, 'a', 'w'))
        ..add(_rec(Level.SEVERE, 'a', 'e'));
      expect(
        buffer.entries().map((e) => e.level),
        ['ERROR', 'WARN', 'INFO', 'DEBUG'],
      );
      expect(
        buffer.entries(minLevel: 'WARN').map((e) => e.message),
        ['e', 'w'],
      );
    });

    test('filters by logger and by query (message or rid)', () {
      final buffer = LogBuffer()
        ..add(_rec(Level.INFO, 'http', 'chocolate cake rid=00000000000000aa'))
        ..add(_rec(Level.INFO, 'auth', 'login ok'));
      expect(buffer.entries(logger: 'auth').map((e) => e.message), [
        'login ok',
      ]);
      expect(
        buffer.entries(query: 'CHOCOLATE').map((e) => e.logger),
        ['http'],
      );
      expect(buffer.entries(query: '00000000000000aa').single.logger, 'http');
      expect(buffer.loggers, ['auth', 'http']);
    });

    test('capacity 0 disables buffering', () {
      final buffer = LogBuffer(capacity: 0)..add(_rec(Level.INFO, 'a', 'x'));
      expect(buffer.entries(), isEmpty);
    });

    test('attach consumes a record stream', () async {
      final controller = StreamController<LogRecord>.broadcast();
      final buffer = LogBuffer()..attach(controller.stream);
      controller.add(_rec(Level.INFO, 'http', 'streamed'));
      await Future<void>.delayed(Duration.zero);
      expect(buffer.entries().single.message, 'streamed');
      await buffer.dispose();
      await controller.close();
    });
  });

  group('logsHandler', () {
    test('returns items (newest first), capacity, and loggers', () {
      final buffer = LogBuffer(capacity: 500)
        ..add(_rec(Level.INFO, 'http', 'one'))
        ..add(_rec(Level.WARNING, 'auth', 'two'));
      final body = logsHandler(buffer, limit: 10);
      final items = body['items']! as List;
      expect(items, hasLength(2));
      expect((items.first as Map)['message'], 'two');
      expect(body['capacity'], 500);
      expect(body['loggers'], containsAll(<String>['http', 'auth']));
    });

    test('limit caps the result', () {
      final buffer = LogBuffer();
      for (var i = 0; i < 10; i++) {
        buffer.add(_rec(Level.INFO, 'http', '$i'));
      }
      expect(logsHandler(buffer, limit: 3)['items']! as List, hasLength(3));
    });
  });
}
