import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:dart_frog/dart_frog.dart' hide requestLogger;
import 'package:salt_server/src/app_pipeline.dart';
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/search/search_service.dart';
import 'package:test/test.dart';

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
