import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:dart_frog/dart_frog.dart' hide requestLogger;
import 'package:logging/logging.dart';
import 'package:salt_server/src/app_pipeline.dart';
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/middleware/dev_cors.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/search/search_service.dart';
import 'package:test/test.dart';

import '../routes/api/v1/auth/login.dart' as login_route;

/// The shipped web app is NOT served by the middleware chain.
///
/// dart_frog's generated entry point builds
/// `Cascade().add(createStaticFileHandler()).add(buildRootHandler())`, and only
/// the second arm goes through `routes/_middleware.dart` ->
/// [buildAppMiddleware]. So `/index.html` and `/main.dart.js` — the real app
/// shell, which the Dockerfile copies into `public/` — were served before and
/// outside every middleware in the chain: measured `csp=false`,
/// `x-frame-options=SAMEORIGIN` (dart:io's default, not the promised `DENY`)
/// and no `Referrer-Policy` at all, while `/r/<slug>` returned byte-for-byte
/// the same HTML through `spaFallback` with all three.
///
/// Nothing could see it. Every HTTP test in this suite serves
/// `buildAppMiddleware` alone, which is the arm that was already correct, and
/// `route_auth_matrix_test`'s source tripwire only checks that
/// `_middleware.dart` CALLS `buildAppMiddleware` — never that
/// `buildAppMiddleware` is the outermost thing running. This file composes the
/// cascade the way the generated entry point does and asks the static arm
/// directly.
// A minimal app shell: the real Flutter build lives in gitignored public/, so
// no committed HTML can stand in for it. Nothing here is recipe data.
const String _shell =
    '<!DOCTYPE html><html><head><title>SaltToTaste</title></head>\n'
    '<body></body></html>';

/// Per-response headers that legitimately differ between a file served from
/// disk and one synthesized by the SPA fallback.
const Set<String> _perResponse = {
  'content-length',
  'content-type',
  'date',
  'cache-control',
  'last-modified',
  'etag',
  'accept-ranges',
  'x-request-id',
};

String md5Hex(String s) => md5.convert(utf8.encode(s)).toString();

class _UnusedNutrition implements NutritionProvider {
  @override
  Future<List<FdcCandidate>> search(String query) => throw UnimplementedError();

  @override
  Future<FdcFood?> food(int fdcId) => throw UnimplementedError();
}

void main() {
  late Directory tempDir;
  late Directory publicDir;
  late SaltDatabase database;
  late HttpServer server;
  late Uri baseUri;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('salt_static_headers_');
    publicDir = Directory('${tempDir.path}/public')..createSync();
    File('${publicDir.path}/index.html').writeAsStringSync(_shell);
    File('${publicDir.path}/main.dart.js').writeAsStringSync('void main(){}');
    File(
      '${publicDir.path}/flutter_bootstrap.js',
    ).writeAsStringSync('// bootstrap');
    final config = ServerConfig.fromEnvironment(
      environment: {'DATA_DIR': tempDir.path, 'LOG_LEVEL': 'ERROR'},
    );
    configureLogging(config);
    database = SaltDatabase.open('${tempDir.path}/salt.db');

    final routes = buildAppMiddleware(
      // Stands in for the generated route table: everything here is a miss,
      // so the SPA fallback answers /r/<slug> exactly as production does.
      // v105 U4: an /images/ path answers with the images route's own
      // header (routes/images/[source]/[file].dart:27 — STATED: the route
      // needs auth and a library, so its header is what stands in).
      (context) => context.request.uri.path == '/cookies'
          // v106 U7: two Set-Cookie values (STATED: no route sets two).
          ? Response(
              headers: {
                'set-cookie': ['a=1', 'b=2'],
              },
            )
          : context.request.uri.path.startsWith('/images/')
          ? Response(
              body: 'img',
              headers: {
                HttpHeaders.cacheControlHeader: 'private, max-age=86400',
              },
            )
          : Response(statusCode: HttpStatus.notFound, body: 'Route not found'),
      config: config,
      database: database,
      authRuntime: AuthRuntime(),
      nutritionProvider: _UnusedNutrition(),
      searchRateLimiter: RequestRateLimiter(),
      searchService: () => InlineSearchService(database),
      logStore: LogStore(directory: '${tempDir.path}/logs'),
      indexPath: '${publicDir.path}/index.html',
    );
    // The production composition, verbatim from build/bin/server.dart, then
    // handed to run()'s wrapper the same way the entry point hands it over.
    final cascade = Cascade()
        .add(createStaticFileHandler(path: publicDir.path))
        .add(routes)
        .handler;
    server = await serve(
      buildOutermostMiddleware(cascade, publicDir: publicDir.path),
      InternetAddress.loopbackIPv4,
      0,
    );
    baseUri = Uri.parse('http://127.0.0.1:${server.port}');
  });

  tearDownAll(() async {
    database.dispose();
    await server.close(force: true);
    tempDir.deleteSync(recursive: true);
  });

  Future<HttpClientResponse> get(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.getUrl(baseUri.resolve(path));
    headers.forEach(request.headers.set);
    final response = await request.close();
    await response.drain<void>();
    return response;
  }

  Map<String, String> headersOf(HttpClientResponse response) {
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values.join(', ');
    });
    return headers;
  }

  group('the static public/ tree', () {
    test('the app shell carries the same headers from either arm', () async {
      // The measurement that named the bug: the SAME HTML, one file on disk,
      // reachable two ways.
      final static = headersOf(await get('/index.html'));
      final viaChain = headersOf(await get('/r/some-slug'));

      expect(
        viaChain['content-security-policy'],
        isNotNull,
        reason:
            'the in-chain arm is the one that was always correct; if it '
            'has no CSP this test is comparing nothing',
      );
      expect(
        static['content-security-policy'],
        viaChain['content-security-policy'],
        reason:
            'the shipped index.html is served by the cascade arm ABOVE the '
            'middleware chain, so a CSP added inside buildAppMiddleware never '
            'reaches it',
      );
      expect(static['x-frame-options'], 'DENY');
      expect(static['referrer-policy'], 'same-origin');
      expect(static['x-content-type-options'], 'nosniff');
    });

    test('a non-HTML asset still gets the global headers', () async {
      final headers = headersOf(await get('/main.dart.js'));
      expect(headers['x-content-type-options'], 'nosniff');
      expect(headers['referrer-policy'], 'same-origin');
    });

    // v105 U4 (Run 079/080 S9 + O8): the static files went out with
    // Last-Modified only, so a browser reused an old bundle from its
    // heuristic cache after a deploy. Every response naming no
    // Cache-Control now revalidates; one that names its own keeps it.
    test('every static file revalidates; own headers kept', () async {
      for (final path in ['/main.dart.js', '/flutter_bootstrap.js']) {
        final headers = headersOf(await get(path));
        expect(headers['cache-control'], 'no-cache', reason: path);
        expect(headers['last-modified'], isNotNull, reason: path);
        // RE-PIN (v106 U4): was 304 on If-Modified-Since — IMS is now
        // stripped on the static arm (a date-only 304 kept a rolled-back
        // bundle); the ETag revalidates instead (the U4 group below).
        final again = await get(
          path,
          headers: {'if-modified-since': headers['last-modified']!},
        );
        expect(again.statusCode, HttpStatus.ok, reason: path);
        expect(headersOf(again)['cache-control'], 'no-cache', reason: path);
      }
      // `/` and the SPA fallback name none of their own (v106 U5: their
      // two lines deleted) — the outermost middleware's no-cache. In this
      // harness `/` is answered by spaFallback (the stub route 404s), so
      // routes/index.dart itself never runs here.
      expect(headersOf(await get('/'))['cache-control'], 'no-cache');
      expect(headersOf(await get('/r/some-slug'))['cache-control'], 'no-cache');
      expect(
        headersOf(await get('/images/atk-tv-2023/x.jpg'))['cache-control'],
        'private, max-age=86400',
      );
    });

    test('every non-per-response header matches the in-chain arm', () async {
      // The DRIFT catcher, and the reason this file exists rather than three
      // hardcoded header assertions: the next header added to the chain must
      // not silently miss public/ the way these three did. Anything the
      // routed response carries and the static one does not is that bug
      // happening again.
      final static = headersOf(await get('/index.html'));
      final viaChain = headersOf(await get('/r/some-slug'));
      final missing = {
        for (final entry in viaChain.entries)
          if (!_perResponse.contains(entry.key) &&
              static[entry.key] != entry.value)
            entry.key: '${entry.value} (static: ${static[entry.key]})',
      };
      expect(
        missing,
        isEmpty,
        reason:
            'these headers reach /r/<slug> through buildAppMiddleware but not '
            'the static app shell. Either move them into '
            'buildOutermostMiddleware, which wraps the whole cascade, or add '
            'the name to _perResponse if it genuinely varies per response.',
      );
    });

    test('main.dart still installs the outermost wrapper', () async {
      // A source tripwire, like route_auth_matrix_test's: dart_frog generates
      // build/bin/server.dart at build time, so nothing here executes the
      // real entry point. Dropping the wrapper from run() would restore the
      // bug with this file's other tests still green, because they compose
      // the cascade themselves.
      final source = File('main.dart').readAsStringSync();
      expect(
        source,
        contains('serve(buildOutermostMiddleware(handler)'),
        reason:
            'main.dart must hand the composed cascade — static public/ arm '
            'included — to buildOutermostMiddleware before serving it; that '
            'is the only seam outside the generated Cascade.',
      );
    });
  });

  Future<(int, Map<String, String>, String)> send(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.openUrl(method, baseUri.resolve(path));
    headers.forEach(request.headers.set);
    final response = await request.close();
    final body = await response
        .transform(const SystemEncoding().decoder)
        .join();
    return (response.statusCode, headersOf(response), body);
  }

  // v106 U3 (Run 081/082 S3 / O4 / C1): shelf_static THREW on a malformed
  // If-Modified-Since (parseHttpDate) and an int64-overflowing Range
  // (int.parse) — a bare text/plain 500 outside every header. STATED
  // synthesized negative-path requests (no browser sends them).
  group('v106 U3 the 500 path', () {
    test(
      'a malformed If-Modified-Since is ignored: 200 + the headers',
      () async {
        for (final ims in ['garbage', 'Sat, 07 Nov 2026 15:22:56 +0000']) {
          final (status, headers, _) = await send(
            '/index.html',
            headers: {'if-modified-since': ims},
          );
          expect(status, HttpStatus.ok, reason: ims);
          expect(headers['cache-control'], 'no-cache', reason: ims);
          expect(headers['referrer-policy'], 'same-origin', reason: ims);
          expect(headers['content-security-policy'], isNotNull, reason: ims);
          final js = await send(
            '/main.dart.js',
            headers: {'if-modified-since': ims},
          );
          expect((js.$1, js.$3), (HttpStatus.ok, 'void main(){}'), reason: ims);
        }
      },
    );

    test('an overflowing Range is ignored: 200 the whole body', () async {
      final (status, headers, body) = await send(
        '/main.dart.js',
        headers: {'range': 'bytes=0-99999999999999999999'},
      );
      expect((status, body), (HttpStatus.ok, 'void main(){}'));
      expect(headers['cache-control'], 'no-cache');
      // U13 (recorded, not changed): an open-ended range at or past EOF is
      // shelf_static's 200 with the whole body, not 416.
      final past = await send(
        '/main.dart.js',
        headers: {'range': 'bytes=9999999-'},
      );
      expect((past.$1, past.$3), (HttpStatus.ok, 'void main(){}'));
      final part = await send('/main.dart.js', headers: {'range': 'bytes=0-3'});
      expect((part.$1, part.$3), (HttpStatus.partialContent, 'void'));
      // closer 3 D2: the START field's 15-digit bound (the pin above
      // overflows only the END field).
      for (final r in [
        'bytes=99999999999999999999-',
        'bytes=99999999999999999999-3',
      ]) {
        final start = await send('/main.dart.js', headers: {'range': r});
        expect(
          (start.$1, start.$3),
          (HttpStatus.ok, 'void main(){}'),
          reason: r,
        );
      }
    });

    test('an uncaught error is the 500 envelope through the headers', () async {
      // STATED synthesized: a handler throwing at the outermost seam (the
      // routes arm's errorHandler catches its own; only the cascade's
      // static arm threw past it — the IMS / Range throws above).
      final boom = await serve(
        buildOutermostMiddleware(
          (_) => throw StateError('boom'),
          publicDir: publicDir.path,
        ),
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => boom.close(force: true));
      final client = HttpClient();
      addTearDown(client.close);
      final response = await (await client.getUrl(
        Uri.parse('http://127.0.0.1:${boom.port}/anything'),
      )).close();
      final body = await response
          .transform(const SystemEncoding().decoder)
          .join();
      final status = response.statusCode;
      final headers = headersOf(response);
      expect(status, HttpStatus.internalServerError);
      expect(headers['content-type'], startsWith('application/json'));
      expect(headers['cache-control'], 'no-cache');
      expect(headers['referrer-policy'], 'same-origin');
      expect(headers['x-content-type-options'], 'nosniff');
      final id = headers['x-request-id']!;
      expect(id, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(jsonDecode(body), {
        'error': {
          'code': 'internal',
          'message': 'Internal server error.',
          'request_id': id,
        },
      });
    });
  });

  // v106 U4 (Run 081/082 S7 / S8 / O7 / C3): shelf_static validated by
  // Last-Modified only ("not after" → 304), so a client holding a NEWER
  // Last-Modified than a rolled-back file got 304 and kept the newer
  // bundle. Now a strong ETag (md5, hashed once per path + mtime + size)
  // and If-Modified-Since stripped on the static arm.
  group('v106 U4 the ETag', () {
    test('ETag on 200 and HEAD; INM match 304, mismatch 200', () async {
      final (status, headers, _) = await send('/main.dart.js');
      final etag = headers['etag']!;
      expect(status, HttpStatus.ok);
      expect(etag, '"${md5Hex('void main(){}')}"');
      final head = await send('/main.dart.js', method: 'HEAD');
      expect((head.$1, head.$2['etag']), (HttpStatus.ok, etag));
      final hit = await send(
        '/main.dart.js',
        headers: {'if-none-match': etag},
      );
      expect((hit.$1, hit.$3), (HttpStatus.notModified, ''));
      expect(hit.$2['etag'], etag);
      expect(hit.$2['cache-control'], 'no-cache');
      // closer 3 D1: HEAD with a matching If-None-Match (strong and W/)
      // is the 304 too (the method gate's HEAD half).
      for (final tag in [etag, 'W/$etag']) {
        final headHit = await send(
          '/main.dart.js',
          method: 'HEAD',
          headers: {'if-none-match': tag},
        );
        expect(
          (headHit.$1, headHit.$2['etag']),
          (HttpStatus.notModified, etag),
          reason: tag,
        );
      }
      final miss = await send(
        '/main.dart.js',
        headers: {'if-none-match': '"stale"'},
      );
      expect((miss.$1, miss.$3), (HttpStatus.ok, 'void main(){}'));
      // A pre-ETag client (IMS only, the file's own date) gets the bytes.
      final ims = await send(
        '/main.dart.js',
        headers: {'if-modified-since': headers['last-modified']!},
      );
      expect((ims.$1, ims.$2['etag']), (HttpStatus.ok, etag));
      // A Range keeps 206.
      final range = await send(
        '/main.dart.js',
        headers: {'range': 'bytes=0-3'},
      );
      expect(range.$1, HttpStatus.partialContent);
    });

    test(
      'the rollback: new bytes, back-dated mtime, IMS newer + old ETag '
      '→ 200 with the new bytes; same size, new mtime → a new ETag',
      () async {
        final file = File('${publicDir.path}/rollback.js')
          ..writeAsStringSync('// NEW build');
        final first = await send('/rollback.js');
        final oldTag = first.$2['etag']!;
        file
          ..writeAsStringSync('// OLD build (rollback)')
          ..setLastModifiedSync(
            DateTime.now().toUtc().subtract(const Duration(days: 2)),
          );
        final back = await send(
          '/rollback.js',
          headers: {
            'if-modified-since': first.$2['last-modified']!,
            'if-none-match': oldTag,
          },
        );
        expect((back.$1, back.$3), (HttpStatus.ok, '// OLD build (rollback)'));
        expect(back.$2['etag'], isNot(oldTag));
        // Same path and size, new mtime → a new ETag (the cache keys on all
        // three; STATED synthesized: a same-size rewrite).
        final sameSize = await send('/rollback.js');
        file
          ..writeAsStringSync('// OLD build (rollbacX)')
          ..setLastModifiedSync(
            DateTime.now().toUtc().subtract(const Duration(days: 1)),
          );
        final rewritten = await send('/rollback.js');
        expect(rewritten.$3, '// OLD build (rollbacX)');
        expect(rewritten.$2['etag'], isNot(sameSize.$2['etag']));
        expect(rewritten.$2['etag'], '"${md5Hex('// OLD build (rollbacX)')}"');
      },
    );
  });

  // v106 closer 1 (verify1 D1 / D2): STATED synthesized requests (no
  // browser sends them) on the harness's own files.
  group('v106 closer 1 the ETag arm', () {
    test('a slash spelling is the same cache entry (keyed on the real '
        'path)', () async {
      final file = File('${publicDir.path}/same.js')..writeAsStringSync('AAAA');
      final mtime = DateTime.utc(2026);
      file.setLastModifiedSync(mtime);
      final first = await send('/same.js');
      // A same-mtime, same-size rewrite: the cache keeps the first hash, so
      // every spelling must answer the one entry's ETag.
      file
        ..writeAsStringSync('BBBB')
        ..setLastModifiedSync(mtime);
      for (final spelling in ['//same.js', '///same.js', '/./same.js']) {
        final client = HttpClient();
        addTearDown(client.close);
        final request = await client.openUrl(
          'GET',
          baseUri.replace(path: spelling),
        );
        final response = await request.close();
        await response.drain<void>();
        expect(
          (response.statusCode, response.headers.value('etag')),
          (HttpStatus.ok, first.$2['etag']),
          reason: spelling,
        );
      }
    });

    test('If-None-Match: * is a 304', () async {
      final hit = await send(
        '/main.dart.js',
        headers: {'if-none-match': '*'},
      );
      expect((hit.$1, hit.$3), (HttpStatus.notModified, ''));
    });

    // v106 closer 2 (verify2 D1): If-None-Match uses the WEAK comparison
    // (RFC 7232 §3.2) — a compressing proxy (nginx gzip) re-sends the
    // strong tag as W/"…". STATED synthesized request.
    test('a weak If-None-Match of the ETag is a 304', () async {
      final etag = (await send('/main.dart.js')).$2['etag']!;
      final hit = await send(
        '/main.dart.js',
        headers: {'if-none-match': '"stale", W/$etag'},
      );
      expect(
        (hit.$1, hit.$3, hit.$2['etag']),
        (HttpStatus.notModified, '', etag),
      );
    });

    test('a POST with a matching If-None-Match is never a 304', () async {
      final etag = (await send('/main.dart.js')).$2['etag']!;
      final post = await send(
        '/main.dart.js',
        method: 'POST',
        headers: {'if-none-match': etag},
      );
      // shelf_static serves the bytes to any method (measured: 200).
      expect((post.$1, post.$3), (HttpStatus.ok, 'void main(){}'));
    });
  });

  // v106 closer 4 (verify4 D1 / D2 / D3): the gates of staticFileValidators'
  // fileOf, on the real cascade. STATED synthesized inputs: a symlink out of
  // the root, a symlink inside it, a directory, a missing public dir — no
  // deploy has any of them; the bytes are this harness's own.
  group('v106 closer 4 the fileOf gates', () {
    test('a symlink out of the root carries no ETag and never 304s; one '
        "inside shares the real file's ETag", () async {
      const secret = 'TOP SECRET';
      File('${tempDir.path}/secret.txt').writeAsStringSync(secret);
      Link(
        '${publicDir.path}/leak.txt',
      ).createSync('${tempDir.path}/secret.txt');
      final leak = await send('/leak.txt');
      // shelf_static refuses it (outside the root) → the routes arm's 404
      // envelope (measured), never the outside file's bytes.
      expect(leak.$1, HttpStatus.notFound);
      expect(leak.$3, isNot(contains(secret)));
      expect(
        ((jsonDecode(leak.$3) as Map)['error'] as Map)['code'],
        'not_found',
      );
      expect(leak.$2['etag'], isNull);
      final oracle = await send(
        '/leak.txt',
        headers: {'if-none-match': '"${md5Hex(secret)}"'},
      );
      expect((oracle.$1, oracle.$2['etag']), (HttpStatus.notFound, null));
      File('${publicDir.path}/real.txt').writeAsStringSync('real bytes');
      Link(
        '${publicDir.path}/alias.txt',
      ).createSync('${publicDir.path}/real.txt');
      final real = await send('/real.txt');
      final alias = await send('/alias.txt');
      expect(real.$2['etag'], '"${md5Hex('real bytes')}"');
      expect(
        (alias.$1, alias.$3, alias.$2['etag']),
        (HttpStatus.ok, 'real bytes', real.$2['etag']),
      );
    });

    test("a directory request is the cascade's answer, never a 500", () async {
      Directory('${publicDir.path}/assets').createSync();
      for (final path in ['/assets', '/assets/']) {
        final (status, headers, body) = await send(path);
        // shelf_static 404s a directory; the extension-less path is then
        // the SPA fallback's shell (measured: 200 text/html).
        expect((status, body), (HttpStatus.ok, _shell), reason: path);
        expect(headers['etag'], isNull, reason: path);
      }
    });

    test('a missing public dir passes every request through', () async {
      final missing = await serve(
        buildOutermostMiddleware(
          (_) => Response(body: 'api'),
          publicDir: '${tempDir.path}/no-such-public',
        ),
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => missing.close(force: true));
      final client = HttpClient();
      addTearDown(client.close);
      final response = await (await client.getUrl(
        Uri.parse('http://127.0.0.1:${missing.port}/api/v1/x'),
      )).close();
      final body = await response
          .transform(const SystemEncoding().decoder)
          .join();
      expect((response.statusCode, body), (HttpStatus.ok, 'api'));
    });
  });

  /// The request exactly as spelled (no client-side normalisation:
  /// `Uri.parse` would drop the `/.` and read `//x` as an authority) — the
  /// probe tables' `curl --path-as-is`.
  Future<(int, Map<String, String>, String)> raw(
    String path, {
    Map<String, String> headers = const {},
    int? port,
    String method = 'GET',
  }) async {
    final socket = await Socket.connect('127.0.0.1', port ?? server.port);
    socket.write(
      '$method $path HTTP/1.1\r\nHost: x\r\nConnection: close\r\n'
      '${headers.entries.map((e) => '${e.key}: ${e.value}\r\n').join()}\r\n',
    );
    final out = await utf8.decoder.bind(socket).join();
    socket.destroy();
    final split = out.indexOf('\r\n\r\n');
    final head = out.substring(0, split).split('\r\n');
    return (
      int.parse(head.first.split(' ')[1]),
      {
        for (final line in head.skip(1))
          line.substring(0, line.indexOf(':')).toLowerCase(): line
              .substring(line.indexOf(':') + 1)
              .trim(),
      },
      out.substring(split + 4),
    );
  }

  /// The ERROR records a [LogStore] in [dir] holds (its JSON lines).
  List<Map<String, Object?>> severeIn(String dir) {
    final file = File('$dir/server.jsonl');
    return [
      if (file.existsSync())
        for (final line in file.readAsLinesSync())
          if ((jsonDecode(line) as Map<String, Object?>)['level'] == 'ERROR')
            jsonDecode(line) as Map<String, Object?>,
    ];
  }

  // v107 U1 (Run 083/084 S1 S12 S13 S15 S17 / O1 O5 O8 O11 O15 O16 O18):
  // fileOf joined the URL's segments with the separator while shelf_static
  // joins them with p.joinAll — a trailing slash / `//` / `/.` skipped
  // every validator (the date-only 304 and the 500 envelope back), a
  // `%2F`-encoded absolute segment reset shelf_static's join into the root,
  // and `/%2Fmain.dart.js` 404ed carrying main.dart.js's ETag (INM → 304).
  // v107: the URL canonicalised before both resolvers. STATED synthesized
  // requests (no browser sends them) on the harness's own files.
  group('v107 U1 one resolver', () {
    test('the empty / dot spellings ARE the file: 200 + its ETag, IMS '
        'stripped, the overflowing Range dropped', () async {
      final canonical = await send('/main.dart.js');
      final etag = canonical.$2['etag']!;
      final lm = canonical.$2['last-modified']!;
      for (final path in [
        '/main.dart.js/',
        '//main.dart.js',
        '/main.dart.js/.',
      ]) {
        final plain = await raw(path);
        // Base: 200 with NO ETag (fileOf null on a trailing '').
        expect(
          (plain.$1, plain.$2['etag'], plain.$3),
          (HttpStatus.ok, etag, 'void main(){}'),
          reason: path,
        );
        // Base: 304 date-only on '/main.dart.js/' and '/.'.
        final ims = await raw(path, headers: {'if-modified-since': lm});
        expect((ims.$1, ims.$2['etag']), (HttpStatus.ok, etag), reason: path);
        // Base: the 500 envelope.
        for (final h in [
          {'if-modified-since': 'garbage'},
          {'range': 'bytes=0-99999999999999999999'},
        ]) {
          final bad = await raw(path, headers: h);
          expect(
            (bad.$1, bad.$3),
            (HttpStatus.ok, 'void main(){}'),
            reason: '$path $h',
          );
        }
      }
    });

    // v108 V5 (Run 085/086 O12, Sonnet critics 1 / 3): the refusal was
    // wider than the harm; the validators now resolve exactly what
    // shelf_static serves. RE-PIN (ruled): '/<abs>%2Fmain.dart.js' 404 →
    // 200 the file WITH its ETag (shelf_static serves it bare); the four
    // spellings naming no file keep the 404 envelope — now the cascade's
    // (shelf_static 404 → spaFallback: a dotted last segment).
    test('a separator-bearing segment is what shelf_static answers: the '
        'file WITH its ETag, else the 404 envelope with none; never a 500, '
        'nothing logged', () async {
      final etag = (await send('/main.dart.js')).$2['etag']!;
      final logs = '${tempDir.path}/u1-logs';
      final store = LogStore(directory: logs)..attach(Logger.root.onRecord);
      addTearDown(store.dispose);
      final absolute = publicDir.resolveSymbolicLinksSync().replaceAll(
        '/',
        '%2F',
      );
      final file = '/$absolute%2Fmain.dart.js';
      final served = await raw(file);
      // Base (v107): the 404 envelope with no ETag.
      expect(
        (served.$1, served.$2['etag'], served.$3),
        (HttpStatus.ok, etag, 'void main(){}'),
      );
      expect((await raw(file, headers: {'if-none-match': etag})).$1, 304);
      expect(
        (await raw(file, headers: {'if-modified-since': 'garbage'})).$1,
        HttpStatus.ok,
      );
      for (final path in [
        '/%2Fmain.dart.js',
        '/main.dart.js%2F',
        '/main.dart.js%5C',
        '/x/%2E%2E%2Fmain.dart.js',
      ]) {
        for (final h in [
          <String, String>{},
          {'if-none-match': etag},
          {'if-modified-since': 'garbage'},
        ]) {
          final (status, headers, body) = await raw(path, headers: h);
          expect(
            (status, headers['etag']),
            (HttpStatus.notFound, null),
            reason: '$path $h',
          );
          final error = (jsonDecode(body) as Map)['error'] as Map;
          expect(error['code'], 'not_found', reason: path);
          expect(error['request_id'], headers['x-request-id'], reason: path);
          expect(headers['cache-control'], 'no-cache', reason: path);
        }
      }
      expect(severeIn(logs), isEmpty);
    });

    // v108 V5: RE-PIN (ruled) — the leading separator is route data too
    // (a free-text tag '/quick'; was the validators' 404 — v106 routed it);
    // '/api/<abs>%2Fmain.dart.js' is the file with its ETag (shelf_static
    // serves it bare; was the 404 envelope).
    test(
      'under /api/ a separator-bearing segment naming no file is route '
      'data, leading or inner; one shelf_static serves is the file',
      () async {
        // STATED synthesized (no corpus recipe's tag holds a separator): a
        // tag name is free text (tag_handlers.dart) and the app sends
        // `/api/v1/tags/${Uri.encodeComponent(name)}/style`. The route
        // stand-in echoes the decoded segments it was handed.
        final routed = await serve(
          buildOutermostMiddleware(
            Cascade()
                .add(createStaticFileHandler(path: publicDir.path))
                .add(
                  (c) => Response(body: 'routed ${c.request.uri.pathSegments}'),
                )
                .handler,
            publicDir: publicDir.path,
          ),
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => routed.close(force: true));
        for (final (method, path) in [
          ('GET', '/api/v1/tags/a%2Fb/style'),
          ('GET', '/api/v1/tags/a%5Cb/style'),
          ('GET', '/api/v1/recipes/x%2Fy'),
          ('GET', '/api/%2E%2E%2Fmain.dart.js'),
          ('PUT', '/api/v1/tags/%2Fquick/style'),
          ('PUT', '/api/v1/tags/%5Co%2F/style'),
          ('PUT', '/api/v1/tags/a%2Fb/style'),
          ('GET', '/api/%2Fmain.dart.js'),
        ]) {
          final (status, headers, body) = await raw(
            path,
            port: routed.port,
            method: method,
          );
          // Base (v107): '%2Fquick', '%5Co%2F' and '/api/%2Fmain.dart.js'
          // the validators' 404 envelope, never routed.
          expect(
            (status, headers['etag'], body),
            (HttpStatus.ok, null, 'routed ${Uri.parse(path).pathSegments}'),
            reason: '$method $path',
          );
        }
        final absolute = publicDir.resolveSymbolicLinksSync().replaceAll(
          '/',
          '%2F',
        );
        final (status, headers, body) = await raw(
          '/api/$absolute%2Fmain.dart.js',
          port: routed.port,
        );
        expect(
          (status, headers['etag'], body),
          (HttpStatus.ok, '"${md5Hex('void main(){}')}"', 'void main(){}'),
        );
      },
    );

    test('fileOf null <=> shelf_static 404: an ETag exactly when the body '
        "is the file's bytes", () async {
      final absolute = publicDir.resolveSymbolicLinksSync().replaceAll(
        '/',
        '%2F',
      );
      Directory('${publicDir.path}/assets').createSync(recursive: true);
      for (final path in [
        '/main.dart.js',
        '/MAIN.DART.JS',
        '//main.dart.js',
        '/./main.dart.js',
        '/main.dart.js/',
        '/MAIN.DART.JS/',
        '/main.dart.js/.',
        '/main.dart.js//',
        '/main.dart.js%2F',
        '/%2Fmain.dart.js',
        '/$absolute%2Fmain.dart.js',
        '/nope.js',
        '/',
        '/assets',
        '/assets/',
        '/%2e%2e/etc/passwd',
        '/r/some-slug',
        // v108 V5: the brief's rows (the base 404ed the file spellings).
        '/api/x/%2F$absolute%2Fmain.dart.js',
        '/api/$absolute%2Fmain.dart.js',
        '/assets%2F..%2Fmain.dart.js',
        '/%2Fetc%2Fpasswd',
        '/r/a%2Fb',
        '/r/a%5Cb',
        '/search%2Fx',
        '/..%00',
        '/..;/main.dart.js',
        '/main.dart.js%00.html',
      ]) {
        final (status, headers, body) = await raw(path);
        expect(
          headers['etag'] != null,
          body == 'void main(){}',
          reason: '$path → $status',
        );
      }
    });

    test('a 1,000-request burst of uncaught errors writes ONE SEVERE '
        'record; a 7,000-char error text keeps the stack', () async {
      // STATED synthesized: a handler throwing at the outermost seam with
      // caller-chosen text (the base's garbage-IMS throw quoted the header).
      final logs = '${tempDir.path}/burst-logs';
      final store = LogStore(directory: logs)..attach(Logger.root.onRecord);
      addTearDown(store.dispose);
      final boom = await serve(
        buildOutermostMiddleware(
          (c) => throw FormatException('bad ${c.request.uri.path}'),
          publicDir: publicDir.path,
        ),
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => boom.close(force: true));
      for (var i = 0; i < 1000; i++) {
        final (status, _, _) = await raw('/burst/$i', port: boom.port);
        expect(status, HttpStatus.internalServerError);
      }
      // Base: 1,000 records.
      expect(severeIn(logs), hasLength(1));
      final long = await serve(
        buildOutermostMiddleware(
          (_) => throw FormatException('g' * 7000),
          publicDir: publicDir.path,
        ),
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => long.close(force: true));
      expect((await raw('/x', port: long.port)).$1, 500);
      final message = severeIn(logs).last['message']! as String;
      // The error text cut at its own 1,024 (the one marker, BEFORE the
      // stack); the stack whole to its bottom frame. Base: the text
      // uncapped, the record cut at 8 KiB past '#0' — the marker after it
      // and the stack's tail gone (the 7,000 chars + frames > 8,192).
      expect(message, contains('static_asset_headers_test.dart'));
      expect('chars truncated]'.allMatches(message), hasLength(1));
      expect(
        message.indexOf('chars truncated]'),
        lessThan(message.indexOf('#0')),
      );
      expect(message, isNot(contains('g' * 1025)));
    });

    test(
      'the throttle: one record per site per 60 s after the first, '
      'naming the suppressed count, WITH the stack (closer 1 D3; v108 V1)',
      () async {
        // STATED synthesized: a fixed throw site under a fake clock.
        final logs = '${tempDir.path}/throttle-logs';
        final store = LogStore(directory: logs)..attach(Logger.root.onRecord);
        addTearDown(store.dispose);
        final t0 = DateTime.utc(2026, 11, 8);
        var t = t0;
        final boom = await serve(
          buildOutermostMiddleware(
            (_) => throw StateError('boom'),
            publicDir: publicDir.path,
            throttle: SevereThrottle(now: () => t),
          ),
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => boom.close(force: true));
        Future<List<String>> hit(Duration after, [int times = 1]) async {
          t = t0.add(after);
          for (var i = 0; i < times; i++) {
            expect((await raw('/t', port: boom.port)).$1, 500);
          }
          return [for (final r in severeIn(logs)) r['message']! as String];
        }

        var m = await hit(Duration.zero, 5);
        expect(m, hasLength(1));
        expect(m.single, contains('#0'));
        expect(m.single, isNot(contains('suppressed')));
        m = await hit(const Duration(seconds: 59));
        expect(m, hasLength(1));
        m = await hit(const Duration(seconds: 60));
        expect(m, hasLength(2));
        expect(m.last, contains('(5 like it suppressed)'));
        // v108 V1 (ruled): REVERSED — every written record carries its
        // stack (was isNot: a rotated store held no frame).
        expect(m.last, contains('#0'));
        m = await hit(const Duration(seconds: 119), 2);
        expect(m, hasLength(2));
        m = await hit(const Duration(seconds: 120));
        expect(m, hasLength(3));
        expect(m.last, contains('(2 like it suppressed)'));
        // v108 V1: REVERSED as above.
        expect(m.last, contains('#0'));
      },
    );
  });

  // v107 U5 / U8 (Run 083/084 S7 S14 / O9 O17; the critics' C2): If-Range
  // was read by neither layer (a stale If-Range + Range → 206 of the NEW
  // bytes), and a CLOSED range past EOF got shelf_static's bare 416 (no
  // Content-Range, no envelope). STATED synthesized requests.
  group('v107 U5 / U8 the Range drops', () {
    test(
      'If-Range: the ETag → 206; anything else → 200 the whole file',
      () async {
        final etag = (await send('/main.dart.js')).$2['etag']!;
        final hit = await send(
          '/main.dart.js',
          headers: {'range': 'bytes=0-3', 'if-range': etag},
        );
        expect((hit.$1, hit.$3), (HttpStatus.partialContent, 'void'));
        for (final stale in [
          '"nope"',
          'W/$etag',
          HttpDate.format(DateTime.now().toUtc()),
        ]) {
          final miss = await send(
            '/main.dart.js',
            headers: {'range': 'bytes=0-3', 'if-range': stale},
          );
          // Base: 206 'void' on every If-Range.
          expect(
            (miss.$1, miss.$3, miss.$2['content-length']),
            (HttpStatus.ok, 'void main(){}', '13'),
            reason: stale,
          );
        }
      },
    );

    test('the rollback shape with a stale If-Range → 200 with the new '
        'bytes', () async {
      final file = File('${publicDir.path}/resume.js')
        ..writeAsStringSync('// OLD bytes of the bundle');
      final old = await send('/resume.js');
      file.writeAsStringSync('// NEW bytes of the bundle!');
      final resumed = await send(
        '/resume.js',
        headers: {'range': 'bytes=10-', 'if-range': old.$2['etag']!},
      );
      expect(
        (resumed.$1, resumed.$3),
        (HttpStatus.ok, '// NEW bytes of the bundle!'),
      );
      expect(resumed.$2['etag'], '"${md5Hex('// NEW bytes of the bundle!')}"');
    });

    test(
      'a range starting at or past EOF is ignored: 200 + the ETag',
      () async {
        final etag = (await send('/main.dart.js')).$2['etag']!;
        for (final r in [
          'bytes=9999999-99999999',
          'bytes=13-20',
          'bytes=9999999-',
        ]) {
          final past = await send('/main.dart.js', headers: {'range': r});
          // Base: 'bytes=9999999-99999999' and 'bytes=13-20' a bare 416.
          expect(
            (past.$1, past.$3, past.$2['etag']),
            (HttpStatus.ok, 'void main(){}', etag),
            reason: r,
          );
        }
        final last = await send(
          '/main.dart.js',
          headers: {'range': 'bytes=12-20'},
        );
        expect((last.$1, last.$3), (HttpStatus.partialContent, '}'));
        // A suffix range (no start) is kept: the owner gate's mutant
        // reading a missing start as the size dropped it (200).
        final suffix = await send(
          '/main.dart.js',
          headers: {'range': 'bytes=-1'},
        );
        expect((suffix.$1, suffix.$3), (HttpStatus.partialContent, '}'));
      },
    );
  });

  // v107 U7 (Run 083/084 S9 S10 / O12 O13): the gates no pin killed.
  // STATED synthesized inputs on the harness's own files.
  group('v107 U7 the unkilled gates', () {
    test(
      "the production default publicDir 'public' (main.dart passes none)",
      () async {
        // v108 V11 (Run 085/086 O10): no chdir of the cwd (it is process-
        // wide — sibling suites' relative opens failed for ~2.2 ms):
        // ONE uniquely named file under the REAL relative `public/` (made
        // if absent; the file, and the directory if made here, removed).
        final dir = Directory('public');
        final made = !dir.existsSync();
        if (made) {
          dir.createSync();
        }
        final name = 'zz_v108_default_${newRequestId()}.js';
        File('public/$name').writeAsStringSync('APP');
        addTearDown(() {
          File('public/$name').deleteSync();
          if (made) {
            dir.deleteSync();
          }
        });
        final cascade = Cascade()
            .add(createStaticFileHandler())
            .add((_) => Response(statusCode: HttpStatus.notFound))
            .handler;
        final def = await serve(
          buildOutermostMiddleware(cascade),
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => def.close(force: true));
        final (status, headers, body) = await raw('/$name', port: def.port);
        // 'publicX': the arm a pass-through, no ETag.
        expect((status, body), (HttpStatus.ok, 'APP'));
        expect(headers['etag'], '"${md5Hex('APP')}"');
      },
    );

    test('a symlink into a SIBLING of the root (public2/) carries no ETag '
        'and never 304s', () async {
      const outside = 'SIBLING SECRET';
      Directory('${tempDir.path}/public2').createSync();
      File('${tempDir.path}/public2/x.js').writeAsStringSync(outside);
      Link(
        '${publicDir.path}/sib.js',
      ).createSync('${tempDir.path}/public2/x.js');
      final leak = await send('/sib.js');
      // `'$root'` without the separator: public2 passes the prefix test.
      expect((leak.$1, leak.$2['etag']), (HttpStatus.notFound, null));
      final oracle = await send(
        '/sib.js',
        headers: {'if-none-match': '"${md5Hex(outside)}"'},
      );
      expect((oracle.$1, oracle.$2['etag']), (HttpStatus.notFound, null));
    });

    test('a same-mtime DIFFERENT-size rewrite is a new ETag', () async {
      final file = File('${publicDir.path}/size.js')..writeAsStringSync('AAAA');
      final mtime = DateTime.utc(2026, 1, 2);
      file.setLastModifiedSync(mtime);
      final first = await send('/size.js');
      file
        ..writeAsStringSync('AAAAAAAA')
        ..setLastModifiedSync(mtime);
      final second = await send('/size.js');
      // The size term dropped: the first hash kept.
      expect(second.$3, 'AAAAAAAA');
      expect(second.$2['etag'], '"${md5Hex('AAAAAAAA')}"');
      expect(second.$2['etag'], isNot(first.$2['etag']));
    });

    test(
      "a 206's ETag is the 200's; a POST carries the file's own tag",
      () async {
        final full = await send('/main.dart.js');
        final part = await send(
          '/main.dart.js',
          headers: {'range': 'bytes=0-3'},
        );
        expect(part.$1, HttpStatus.partialContent);
        expect(part.$2['etag'], full.$2['etag']);
        final post = await send('/main.dart.js', method: 'POST');
        expect(post.$2['etag'], '"${md5Hex('void main(){}')}"');
      },
    );
  });

  // v107 U9 (Run 083/084 C2.2 / O4): "every response carries an
  // X-Request-Id" was false for the static arm; devCors still spread the
  // response's headers (two Set-Cookie → one).
  group('v107 U9 the request id and the devCors merge', () {
    test('a static 200, 206 and 304 carry an X-Request-Id', () async {
      final ok = await send('/main.dart.js');
      final part = await send('/main.dart.js', headers: {'range': 'bytes=0-3'});
      final hit = await send(
        '/main.dart.js',
        headers: {'if-none-match': ok.$2['etag']!},
      );
      expect(hit.$1, HttpStatus.notModified);
      for (final h in [ok.$2, part.$2, hit.$2]) {
        expect(h['x-request-id'], matches(RegExp(r'^[0-9a-f]{16}$')));
      }
      expect(ok.$2['x-request-id'], isNot(hit.$2['x-request-id']));
    });

    test("the 500's id is the one minted before the try (what every layer "
        'below read)', () async {
      // STATED synthesized: a handler recording the id it was provided,
      // then throwing at the outermost seam.
      String? seen;
      final boom = await serve(
        buildOutermostMiddleware((c) {
          seen = requestIdOf(c);
          throw StateError('boom');
        }, publicDir: publicDir.path),
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => boom.close(force: true));
      final (status, headers, body) = await raw('/x', port: boom.port);
      expect(status, HttpStatus.internalServerError);
      expect(seen, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(headers['x-request-id'], seen);
      expect(((jsonDecode(body) as Map)['error'] as Map)['request_id'], seen);
    });

    test("a route's own X-Request-Id is kept: the /api envelope's header "
        'id is its body id (closer 1 D2)', () async {
      final (status, headers, body) = await raw('/api/v1/no-such-route');
      final id = ((jsonDecode(body) as Map)['error'] as Map)['request_id'];
      expect(status, HttpStatus.notFound);
      // A mutant stamping the outermost id unconditionally: the header is
      // that id, the body (and the log) the routes chain's own.
      expect(headers['x-request-id'], id);
      expect(id, isA<String>());
    });

    test('two Set-Cookie values through devCors stay two', () async {
      final config = ServerConfig.fromEnvironment(
        environment: {
          'DATA_DIR': tempDir.path,
          'LOG_LEVEL': 'ERROR',
          'DEV_ALLOW_CORS': 'true',
        },
      );
      expect(config.devAllowCors, isTrue);
      final cors = await serve(
        devCors(config)(
          (_) => Response(
            headers: {
              'set-cookie': ['a=1', 'b=2'],
            },
          ),
        ),
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => cors.close(force: true));
      final client = HttpClient();
      addTearDown(client.close);
      final response = await (await client.getUrl(
        Uri.parse('http://127.0.0.1:${cors.port}/x'),
      )).close();
      await response.drain<void>();
      // Base: one joined "a=1, b=2".
      expect(response.headers['set-cookie'], ['a=1', 'b=2']);
      expect(
        response.headers.value('access-control-allow-credentials'),
        'true',
      );
    });
  });

  // v108 V5 + V4 (Run 085/086 S8 / O7 / O12, Sonnet critics 1 / 3): the
  // static arm answers exactly what shelf_static answers; the validators
  // only add their headers (the ETag, a 304, the Range rules). STATED
  // synthesized requests (the brief's table, measured base vs tip in the
  // fix108 plan) on the harness's own files.
  group('v108 V5 / V4 the static arm is shelf_static plus its validators', () {
    test('row by row: the pipeline answers as BARE shelf_static; an ETag '
        'exactly on a file; a non-file never 304s', () async {
      Directory('${publicDir.path}/v108dir').createSync();
      File('${publicDir.path}/v108dir/nested.js').writeAsStringSync('NESTED');
      File('${tempDir.path}/v108secret.js').writeAsStringSync('SECRET');
      Link(
        '${publicDir.path}/v108out.js',
      ).createSync('${tempDir.path}/v108secret.js');
      final routes = buildAppMiddleware(
        (c) {
          final p = c.request.uri.path;
          if (p == '/') {
            requireGet(c); // The real root route's guard (routes/index.dart).
            return Response(
              body: _shell,
              headers: {HttpHeaders.contentTypeHeader: 'text/html'},
            );
          }
          return p.startsWith('/api/')
              ? Response(body: 'routed ${c.request.uri.pathSegments}')
              : Response(statusCode: HttpStatus.notFound);
        },
        config: ServerConfig.fromEnvironment(
          environment: {'DATA_DIR': tempDir.path, 'LOG_LEVEL': 'ERROR'},
        ),
        database: database,
        authRuntime: AuthRuntime(),
        nutritionProvider: _UnusedNutrition(),
        searchRateLimiter: RequestRateLimiter(),
        searchService: () => InlineSearchService(database),
        logStore: LogStore(directory: '${tempDir.path}/v108-logs'),
        indexPath: '${publicDir.path}/index.html',
      );
      final cascade = Cascade()
          .add(createStaticFileHandler(path: publicDir.path))
          .add(routes)
          .handler;
      final bare = await serve(cascade, InternetAddress.loopbackIPv4, 0);
      addTearDown(() => bare.close(force: true));
      final full = await serve(
        buildOutermostMiddleware(cascade, publicDir: publicDir.path),
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => full.close(force: true));
      final abs = publicDir.resolveSymbolicLinksSync().replaceAll('/', '%2F');
      var files = 0;
      for (final (method, path) in [
        for (final m in ['GET', 'HEAD']) ...[
          (m, '/'),
          (m, '/index.html'),
          (m, '/main.dart.js'),
          (m, '/$abs%2Fmain.dart.js'),
          (m, '/v108dir%2Fnested.js'),
          (m, '/v108out.js'),
        ],
        ('GET', '/main.dart.js/'),
        ('GET', '//main.dart.js'),
        ('GET', '/main.dart.js/.'),
        ('GET', '/%2Fmain.dart.js'),
        ('GET', '/api/x/%2F$abs%2Fmain.dart.js'),
        ('GET', '/v108dir/nested.js'),
        ('GET', '/v108dir%2F..%2Fmain.dart.js'),
        ('GET', '/%2Fetc%2Fpasswd'),
        ('GET', '/r/a%2Fb'),
        ('GET', '/r/a%5Cb'),
        ('GET', '/search%2Fx'),
        ('PUT', '/api/v1/tags/%2Fquick/style'),
        ('PUT', '/api/v1/tags/%5Co%2F/style'),
        ('PUT', '/api/v1/tags/a%2Fb/style'),
        ('GET', '/..%00'),
        ('GET', '/..;/main.dart.js'),
        ('GET', '/main.dart.js%00.html'),
        ('GET', '/api/%2Fmain.dart.js'),
        ('GET', '/api/$abs%2Fmain.dart.js'),
      ]) {
        final b = await raw(path, port: bare.port, method: method);
        final f = await raw(path, port: full.port, method: method);
        final why = '$method $path';
        // Each side mints its own request id.
        String body(String s) =>
            s.replaceAll(RegExp('"request_id":"[0-9a-f]{16}"'), 'ID');
        expect(
          (f.$1, f.$2['content-type'], body(f.$3)),
          (b.$1, b.$2['content-type'], body(b.$3)),
          reason: why,
        );
        expect(b.$2['etag'], isNull, reason: why);
        // A file is what shelf_static serves with its Last-Modified.
        final isFile = b.$2['last-modified'] != null;
        expect(f.$2['etag'] != null, isFile, reason: why);
        if (isFile && method == 'GET') {
          files++;
          expect(f.$2['etag'], '"${md5Hex(f.$3)}"', reason: why);
        }
        final inm = await raw(
          path,
          port: full.port,
          method: method,
          headers: {'if-none-match': '*'},
        );
        expect(inm.$1, isFile ? HttpStatus.notModified : b.$1, reason: why);
      }
      // Not vacuous: 12 GET rows are files (index.html; main.dart.js by
      // nine spellings, the NUL-truncated one included; nested.js by two).
      expect(files, 12);
    });

    test('V4: GET / is 200 the shell and HEAD / the route answer through the '
        'outermost seam; the dot spellings are 404 by value', () async {
      final get = await raw('/');
      expect((get.$1, get.$3), (HttpStatus.ok, _shell));
      // The harness's stand-in route 404s '/', and spaFallback answers GET
      // only (production's routes/index.dart: requireGet → 405).
      expect((await raw('/', method: 'HEAD')).$1, HttpStatus.notFound);
      for (final path in ['/..%00', '/..;/main.dart.js']) {
        final (status, headers, body) = await raw(path);
        expect(
          (status, headers['etag'], (jsonDecode(body) as Map)['error'] != null),
          (HttpStatus.notFound, null, true),
          reason: path,
        );
      }
    });
  });

  // v108 V2 (Run 085/086 S12 / O1 O11): dart_frog's `Request.method`
  // throws for a token outside its enum; the outermost catch's own log
  // text read it again (the first per window a bare shelf_io 500, no record
  // ever written). STATED synthesized requests (no browser sends them).
  group('v108 V2 one gate for a method dart_frog cannot name', () {
    test('TRACE / PROPFIND / FOO on a file, a routed and an unknown path: '
        '405 with the envelope, Allow and the id, every time; GET '
        'unchanged; nothing SEVERE', () async {
      final logs = '${tempDir.path}/v2-logs';
      final store = LogStore(directory: logs)..attach(Logger.root.onRecord);
      addTearDown(store.dispose);
      for (final path in ['/main.dart.js', '/api/v1/auth/me', '/nope']) {
        for (final method in ['TRACE', 'TRACE', 'PROPFIND', 'FOO', 'FOO']) {
          final (status, headers, body) = await raw(path, method: method);
          // Base: the first a bare 500 text/plain, then the 500 envelope.
          expect(
            (status, headers['content-type']),
            (HttpStatus.methodNotAllowed, 'application/json'),
            reason: '$method $path',
          );
          final error = (jsonDecode(body) as Map)['error'] as Map;
          expect(error['code'], 'method_not_allowed');
          expect(error['request_id'], headers['x-request-id']);
          expect(
            headers['allow'],
            'DELETE, GET, HEAD, OPTIONS, PATCH, POST, PUT',
          );
          expect(headers['cache-control'], 'no-cache');
        }
      }
      expect((await raw('/main.dart.js')).$3, 'void main(){}');
      expect((await raw('/api/v1/auth/me')).$1, HttpStatus.notFound);
      expect((await raw('/nope')).$3, _shell);
      expect(severeIn(logs), isEmpty);
    });
  });

  // v108 V1 (Run 085/086 S1 S3 S11 S14 / O2 O8, Opus critic 1): ONE
  // throttle for both persisting catch-alls ([SevereThrottle]).
  group('v108 V1 one throttle', () {
    test('50 truncated login bodies through the real routes arm: ONE SEVERE '
        'record with its stack; the audit history kept', () async {
      // STATED synthesized (negative path: a client closing mid-body).
      final dir = Directory.systemTemp.createTempSync('salt_v108_v1_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final config = ServerConfig.fromEnvironment(
        environment: {'DATA_DIR': dir.path, 'LOG_LEVEL': 'ERROR'},
      );
      final db = SaltDatabase.open('${dir.path}/salt.db');
      addTearDown(db.dispose);
      final logs = '${dir.path}/logs';
      final store = LogStore(directory: logs)..attach(Logger.root.onRecord);
      addTearDown(store.dispose);
      final level = Logger.root.level;
      Logger.root.level = Level.WARNING;
      addTearDown(() => Logger.root.level = level);
      Logger('audit').warning('SENTINEL admin audit line');
      final routes = buildAppMiddleware(
        (c) => c.request.uri.path == '/api/v1/auth/login'
            ? Future.sync(() => login_route.onRequest(c))
            : Response(statusCode: HttpStatus.notFound),
        config: config,
        database: db,
        authRuntime: AuthRuntime(),
        nutritionProvider: _UnusedNutrition(),
        searchRateLimiter: RequestRateLimiter(),
        searchService: () => InlineSearchService(db),
        logStore: store,
      );
      final login = await serve(
        buildOutermostMiddleware(
          Cascade()
              .add(createStaticFileHandler(path: publicDir.path))
              .add(routes)
              .handler,
          publicDir: publicDir.path,
        ),
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => login.close(force: true));
      for (var i = 0; i < 50; i++) {
        final s = await Socket.connect('127.0.0.1', login.port);
        s.write(
          'POST /api/v1/auth/login HTTP/1.1\r\nHost: x\r\n'
          'Content-Type: application/json\r\nContent-Length: 5000\r\n\r\n'
          '{"user',
        );
        await s.flush();
        s.destroy();
      }
      for (var i = 0; i < 50 && severeIn(logs).isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      // Base: 50 records, each with its stack.
      final records = severeIn(logs);
      expect(records, hasLength(1));
      expect(records.single['message'], contains('#0'));
      expect(
        File('$logs/server.jsonl').readAsStringSync(),
        contains('SENTINEL admin audit line'),
      );
    });

    test('the two catch-alls share ONE throttle: one site thrown through '
        'both is one record', () async {
      final logs = '${tempDir.path}/v1-shared-logs';
      final store = LogStore(directory: logs)..attach(Logger.root.onRecord);
      addTearDown(store.dispose);
      final both = await serve(
        buildOutermostMiddleware(
          Cascade()
              .add(
                (c) => c.request.uri.path == '/outer'
                    ? _v108Boom()
                    : Response(statusCode: HttpStatus.notFound),
              )
              .add(errorHandler()((_) => _v108Boom()))
              .handler,
          publicDir: publicDir.path,
        ),
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => both.close(force: true));
      expect((await raw('/outer', port: both.port)).$1, 500);
      expect((await raw('/inner', port: both.port)).$1, 500);
      // Two instances: 2.
      expect(severeIn(logs), hasLength(1));
    });

    test('the clock: +60 s a record WITH its stack naming the count; a '
        '2 h BACKWARDS step is recorded at once', () {
      final records = <LogRecord>[];
      final log = Logger.detached('v108')..level = Level.ALL;
      final sub = log.onRecord.listen(records.add);
      addTearDown(sub.cancel);
      final t0 = DateTime.utc(2026, 11, 9);
      var t = t0;
      final throttle = SevereThrottle(now: () => t);
      final (error, stack) = _v108Caught();
      void hit(Duration at) {
        t = t0.add(at);
        throttle.severe(log, 'm', null, error, stack);
      }

      hit(Duration.zero);
      hit(const Duration(seconds: 30));
      hit(const Duration(seconds: 59));
      expect(records, hasLength(1));
      hit(const Duration(seconds: 60));
      expect(records, hasLength(2));
      expect(records.last.message, contains('(2 like it suppressed)'));
      expect(records.last.stackTrace, isNotNull);
      // Base (wall clock, `difference >= every`): silent for 2 h + 60 s.
      hit(const Duration(seconds: 60) - const Duration(hours: 2));
      expect(records, hasLength(3));
      expect(records.last.stackTrace, isNotNull);
      hit(const Duration(seconds: 61) - const Duration(hours: 2));
      expect(records, hasLength(3));
    });

    test('the key: one type from two sites is two records; two types from '
        'one site are two', () {
      final records = <LogRecord>[];
      final log = Logger.detached('v108k')..level = Level.ALL;
      final sub = log.onRecord.listen(records.add);
      addTearDown(sub.cancel);
      final throttle = SevereThrottle(now: () => DateTime.utc(2026, 11, 9));
      final sites = [
        _v108Caught(),
        _v108CaughtElsewhere(),
        _v108Caught(format: true),
      ];
      for (final (error, stack) in [...sites, ...sites]) {
        throttle.severe(log, 'm', null, error, stack);
      }
      // A constant key 1, a type-only key 2, a frame-only key 2.
      expect(records, hasLength(3));
    });
  });

  test(
    'v106 U7: two Set-Cookie values both leave the outermost seam',
    () async {
      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.getUrl(baseUri.resolve('/cookies'));
      final response = await request.close();
      await response.drain<void>();
      expect(response.headers['set-cookie'], ['a=1', 'b=2']);
    },
  );
}

/// v108 V1: a fixed throw site (its stack's top frame is this function).
Never _v108Boom() => throw StateError('v108 shared site');

/// A StateError — or, [format], an ArgumentError — thrown at ONE site
/// (one throw statement: one top frame), caught with its stack.
(Object, StackTrace) _v108Caught({bool format = false}) {
  try {
    throw format ? ArgumentError('x') : StateError('x');
  } catch (e, st) {
    return (e, st);
  }
}

/// A StateError thrown at ANOTHER site.
(Object, StackTrace) _v108CaughtElsewhere() {
  try {
    throw StateError('x');
  } catch (e, st) {
    return (e, st);
  }
}
