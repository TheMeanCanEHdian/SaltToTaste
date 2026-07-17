import 'dart:async';
import 'dart:isolate';

import 'package:logging/logging.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/search/fts_compiler.dart';
import 'package:salt_shared/salt_shared.dart';

/// One page of ranked search results — the same shape
/// [SaltDatabase.searchCards] returns, so the implementations are
/// interchangeable.
typedef SearchPage = ({List<RecipeCard> items, int total});

/// Runs the FTS ranked recipe search for a compiled query.
///
/// Two implementations: [InlineSearchService] runs it synchronously on the
/// caller's isolate (the pre-#48 behavior, kept for tests and
/// `SEARCH_WORKER_ISOLATES=0`), and [IsolateSearchService] runs it on dedicated
/// background isolates so a heavy `bm25` query never blocks the serving loop.
/// The DoS surface #42/#47 measured — a synchronous ranked search stalling the
/// one event loop — is why this boundary exists.
abstract interface class SearchService {
  /// Ranked page of cards for [compiled]. Mirrors [SaltDatabase.searchCards].
  Future<SearchPage> search(
    CompiledSearch compiled, {
    required int page,
    required int limit,
    int? viewerId,
    bool favoritesOnly = false,
  });

  /// Releases any background isolates and their connections. Must run BEFORE
  /// the writer connection closes so its final WAL checkpoint is not blocked by
  /// a still-open reader.
  Future<void> dispose();
}

/// Runs search synchronously against [_db] on the calling isolate.
class InlineSearchService implements SearchService {
  /// Wraps the given database to run search synchronously on the calling
  /// isolate.
  InlineSearchService(this._db);

  final SaltDatabase _db;

  @override
  Future<SearchPage> search(
    CompiledSearch compiled, {
    required int page,
    required int limit,
    int? viewerId,
    bool favoritesOnly = false,
  }) async => _db.searchCards(
    compiled,
    page: page,
    limit: limit,
    viewerId: viewerId,
    favoritesOnly: favoritesOnly,
  );

  @override
  Future<void> dispose() async {}
}

/// Runs search on a pool of background isolates, each owning a read-only WAL
/// connection to the same database. Requests are round-robined; a worker that
/// dies is respawned lazily on its next use; a request that outruns the
/// per-request timeout (a stuck worker) fails rather than hanging forever.
class IsolateSearchService implements SearchService {
  IsolateSearchService._(this._workers, this._timeout);

  static final Logger _log = Logger('search');

  final List<_SearchWorker> _workers;
  final Duration _timeout;
  int _next = 0;
  bool _disposed = false;

  /// Spawns [count] workers (must be >= 1) against the migrated database at
  /// [dbPath]; the writer connection must already exist so readers can attach.
  static Future<IsolateSearchService> spawn({
    required String dbPath,
    required int count,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    assert(count >= 1, 'use InlineSearchService for 0 workers');
    final workers = <_SearchWorker>[];
    for (var i = 0; i < count; i++) {
      final worker = _SearchWorker(dbPath, i);
      await worker.ensureSpawned();
      workers.add(worker);
    }
    _log.info('Search running on $count background isolate(s)');
    return IsolateSearchService._(workers, timeout);
  }

  @override
  Future<SearchPage> search(
    CompiledSearch compiled, {
    required int page,
    required int limit,
    int? viewerId,
    bool favoritesOnly = false,
  }) {
    if (_disposed) {
      throw StateError('search service is disposed');
    }
    // Round-robin. A single worker serializes searches (still off the serving
    // isolate); more workers spread concurrent searches across cores.
    final worker = _workers[_next++ % _workers.length];
    return worker.run(
      compiled,
      page: page,
      limit: limit,
      viewerId: viewerId,
      favoritesOnly: favoritesOnly,
      timeout: _timeout,
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await Future.wait(_workers.map((w) => w.dispose()));
  }
}

/// A single background search isolate and its command channel. Lazily
/// (re)spawns so a crashed worker recovers on next use.
class _SearchWorker {
  _SearchWorker(this._dbPath, this._index);

  final String _dbPath;
  final int _index;
  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _exit;

  Future<void> ensureSpawned() async {
    if (_commands != null) {
      return;
    }
    final ready = ReceivePort();
    // onExit fires if the isolate dies (crash or uncaught error); clear the
    // channel so the next request respawns instead of sending into the void.
    _exit = ReceivePort()..listen((_) => _markDead());
    _isolate = await Isolate.spawn(
      _searchWorkerMain,
      _WorkerInit(_dbPath, ready.sendPort),
      onExit: _exit!.sendPort,
      debugName: 'search-worker-$_index',
    );
    _commands = await ready.first as SendPort;
  }

  void _markDead() {
    _commands = null;
    _isolate = null;
    _exit?.close();
    _exit = null;
  }

  Future<SearchPage> run(
    CompiledSearch compiled, {
    required int page,
    required int limit,
    required int? viewerId,
    required bool favoritesOnly,
    required Duration timeout,
  }) async {
    await ensureSpawned();
    final reply = ReceivePort();
    _commands!.send(
      _SearchRequest(
        compiled,
        page,
        limit,
        viewerId,
        favoritesOnly,
        reply.sendPort,
      ),
    );
    try {
      final response = await reply.first.timeout(timeout);
      if (response is _SearchFailure) {
        // Re-raise on the serving isolate so the error middleware wraps it in
        // the usual envelope, exactly as an inline search error would.
        throw StateError('search failed: ${response.message}');
      }
      final result = response as _SearchResult;
      return (items: result.items, total: result.total);
    } finally {
      reply.close();
    }
  }

  Future<void> dispose() async {
    final commands = _commands;
    if (commands == null) {
      return;
    }
    final done = ReceivePort();
    commands.send(_Shutdown(done.sendPort));
    try {
      // The worker closes its read-only connection, then replies.
      await done.first.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Fall through to a hard kill below.
    }
    done.close();
    _exit?.close();
    _exit = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
  }
}

/// Spawn payload: where the read-only connection opens and where to hand back
/// this worker's command port.
class _WorkerInit {
  const _WorkerInit(this.dbPath, this.ready);
  final String dbPath;
  final SendPort ready;
}

/// A search to run, with the port its result should be sent back on.
class _SearchRequest {
  const _SearchRequest(
    this.compiled,
    this.page,
    this.limit,
    this.viewerId,
    // A private isolate-message carrier; a positional flag is fine here.
    // ignore: avoid_positional_boolean_parameters
    this.favoritesOnly,
    this.reply,
  );
  final CompiledSearch compiled;
  final int page;
  final int limit;
  final int? viewerId;
  final bool favoritesOnly;
  final SendPort reply;
}

/// Successful result (cards copy across the isolate boundary intact).
class _SearchResult {
  const _SearchResult(this.items, this.total);
  final List<RecipeCard> items;
  final int total;
}

/// A search that threw inside the worker (e.g. a SQLite error). Only the
/// message crosses back; the serving isolate re-raises it.
class _SearchFailure {
  const _SearchFailure(this.message);
  final String message;
}

/// Asks the worker to close its connection and exit; it replies on [done].
class _Shutdown {
  const _Shutdown(this.done);
  final SendPort done;
}

/// Background-isolate entry point: opens a read-only connection and serves
/// searches until told to shut down.
void _searchWorkerMain(_WorkerInit init) {
  final db = SaltDatabase.openReadOnly(init.dbPath);
  final commands = ReceivePort();
  init.ready.send(commands.sendPort);
  commands.listen((message) {
    if (message is _Shutdown) {
      db.dispose();
      message.done.send(null);
      commands.close();
      return;
    }
    final request = message as _SearchRequest;
    try {
      final result = db.searchCards(
        request.compiled,
        page: request.page,
        limit: request.limit,
        viewerId: request.viewerId,
        favoritesOnly: request.favoritesOnly,
      );
      request.reply.send(_SearchResult(result.items, result.total));
      // The worker must survive a bad query (it stays warm for the next one),
      // so every failure is caught and reported rather than crashing.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      request.reply.send(_SearchFailure(error.toString()));
    }
  });
}
