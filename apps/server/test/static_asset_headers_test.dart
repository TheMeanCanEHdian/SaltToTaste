import 'dart:async';
import 'dart:io';

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

class _UnusedNutrition implements NutritionProvider {
  @override
  Future<List<FdcCandidate>> search(String query) => throw UnimplementedError();

  @override
  Future<FdcFood?> food(int fdcId) => throw UnimplementedError();
}

void main() {
  late Directory tempDir;
  late SaltDatabase database;
  late HttpServer server;
  late Uri baseUri;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('salt_static_headers_');
    final publicDir = Directory('${tempDir.path}/public')..createSync();
    File('${publicDir.path}/index.html').writeAsStringSync(_shell);
    File('${publicDir.path}/main.dart.js').writeAsStringSync('void main(){}');
    final config = ServerConfig.fromEnvironment(
      environment: {'DATA_DIR': tempDir.path, 'LOG_LEVEL': 'ERROR'},
    );
    configureLogging(config);
    database = SaltDatabase.open('${tempDir.path}/salt.db');

    final routes = buildAppMiddleware(
      // Stands in for the generated route table: everything here is a miss,
      // so the SPA fallback answers /r/<slug> exactly as production does.
      (_) => Response(statusCode: HttpStatus.notFound, body: 'Route not found'),
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
      buildOutermostMiddleware(cascade),
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

  Future<HttpClientResponse> get(String path) async {
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.getUrl(baseUri.resolve(path));
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
        reason: 'the in-chain arm is the one that was always correct; if it '
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
}
