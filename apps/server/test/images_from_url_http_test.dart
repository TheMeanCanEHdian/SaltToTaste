import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/app_pipeline.dart';
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/search/search_service.dart';
import 'package:salt_server/src/services/image_ingest.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart'
    show editableRecipeKeys, manualSourceSlug;
import 'package:test/test.dart';

import '../routes/api/v1/auth/login.dart' as login_route;
import '../routes/api/v1/recipes/[id]/images/from_url.dart' as from_url_route;
import '../routes/api/v1/recipes/[id]/images/store_from_url.dart'
    as store_from_url_route;
import '../routes/api/v1/recipes/index.dart' as recipes_route;
import 'support/corpus.dart';

/// T11 — the success path of `POST .../images/from_url` (and its store-only
/// twin), which had never executed: every existing image-ingest test stops at
/// a rejection.
///
/// A real download cannot run in a test — the SSRF guard requires a public
/// host, and a test must not reach the network — so the transport alone is
/// substituted through `debugImageHttpClientFactory`. The seam sits BELOW the
/// guards: the URL is still validated, every hop's address still has to be
/// public unicast, the connected peer is still re-checked, and status /
/// content-type / size / magic bytes are still enforced. The first group
/// proves exactly that by driving guard rejections THROUGH the seam.
///
/// Only the tests that read corpus bytes are gated on the corpus; the guard
/// and response-validation pins run everywhere, CI included (review T1).
///
/// The HTTP group serves the routes over the REAL production middleware chain
/// (`buildAppMiddleware`), not a hand-rolled look-alike — see the warning in
/// `lib/src/app_pipeline.dart`.
void main() {
  // Documentation-range literals (RFC 5737 TEST-NET-1/2/3): public unicast as
  // far as the guard is concerned, never routed, and used here as IP literals
  // so the guard's host check needs no DNS and no network.
  const publicHost = '192.0.2.10';
  const otherPublicHost = '198.51.100.7';
  const imageUrlText = 'https://$publicHost/photos/hero.jpg';

  final requested = <Uri>[];

  /// Installs [responder] as the transport [fetchImageFromUrl] uses and
  /// records every URL it is asked for.
  void installTransport(Future<HttpClientResponse> Function(Uri) responder) {
    requested.clear();
    debugImageHttpClientFactory = () => _FakeHttpClient(responder, requested);
  }

  /// A 200 image response whose socket landed on [peer] — or, when [peer] is
  /// null, one the transport reports no connection info for at all.
  _FakeResponse imageResponse(
    List<int> body, {
    String contentType = 'image/jpeg',
    String? peer = publicHost,
  }) => _FakeResponse(
    body: body,
    statusCode: HttpStatus.ok,
    headers: _FakeHeaders({HttpHeaders.contentTypeHeader: contentType}),
    connectionInfo: peer == null
        ? null
        : _FakeConnectionInfo(InternetAddress(peer)),
  );

  /// A 302 pointing at [location].
  _FakeResponse redirectResponse(String location, {String peer = publicHost}) =>
      _FakeResponse(
        body: const [],
        statusCode: HttpStatus.found,
        isRedirect: true,
        headers: _FakeHeaders({HttpHeaders.locationHeader: location}),
        connectionInfo: _FakeConnectionInfo(InternetAddress(peer)),
      );

  /// The message a caller actually receives when [transport] answers.
  Future<String> refusalMessage(
    Future<HttpClientResponse> Function(Uri) transport,
  ) async {
    installTransport(transport);
    try {
      await fetchImageFromUrl(imageUrlText);
      fail('the fetch should have been refused');
    } on ValidationException catch (error) {
      return error.message;
    }
  }

  tearDown(() {
    debugImageHttpClientFactory = null;
    requested.clear();
  });

  // Not a behavioural pin — an uninitialised nullable is null by language
  // rule, so this holds for free today and is NOT counted among the
  // behaviours this file covers. Its one job is to fail if someone later
  // gives the field an initialiser (or lib/ starts assigning it), which would
  // put a substituted transport on the production path.
  test('the transport seam has no default (nothing in lib/ assigns it)', () {
    expect(
      debugImageHttpClientFactory,
      isNull,
      reason: 'nothing in lib/ may substitute the image transport',
    );
  });

  group('the guards still run below the seam', () {
    test('a redirect hop onto a private host is rejected', () async {
      installTransport(
        (url) async => redirectResponse('http://10.0.0.7/a.jpg'),
      );
      await expectLater(
        fetchImageFromUrl(imageUrlText),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            imageFetchFailedMessage,
          ),
        ),
      );
      // The private hop was refused before it was ever requested.
      expect(requested.map((u) => u.host), [publicHost]);
    });

    test('a redirect hop onto a non-http scheme is rejected', () async {
      installTransport((url) async => redirectResponse('file:///etc/passwd'));
      await expectLater(
        fetchImageFromUrl(imageUrlText),
        throwsA(isA<ValidationException>()),
      );
      expect(requested.map((u) => u.host), [publicHost]);
    });

    test('a connection landing on a private peer is refused', () async {
      // DNS rebinding: the host validated public, the socket did not.
      installTransport(
        (url) async => imageResponse(const [], peer: '10.0.0.5'),
      );
      await expectLater(
        fetchImageFromUrl(imageUrlText),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            imageFetchFailedMessage,
          ),
        ),
      );
    });

    test('a response with no connection info is refused', () async {
      // Fail CLOSED. A null `connectionInfo` used to skip the rebinding
      // re-check entirely (2026-07-28 review, item 2) — and that re-check is
      // the only thing closing the window between the DNS guard and the
      // socket, so "I cannot tell you where this landed" has to deny. An
      // empty body would otherwise sail through content-type and size and
      // come back as a successful zero-byte fetch.
      installTransport((url) async => imageResponse(const [], peer: null));
      await expectLater(
        fetchImageFromUrl(imageUrlText),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            imageFetchFailedMessage,
          ),
        ),
      );
    });

    test('redirects are capped at exactly the documented budget', () async {
      var hop = 0;
      installTransport((url) async {
        hop += 1;
        return redirectResponse('https://$publicHost/hop-$hop.jpg');
      });
      await expectLater(
        fetchImageFromUrl(imageUrlText),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('redirected too many times'),
          ),
        ),
      );
      // Exact, not `greaterThan(1)`: the budget is the amplification factor
      // of one inbound API call on an internet-facing deployment, so widening
      // `_maxRedirects` (image_ingest.dart) must fail here. The loop runs
      // `hop = 0..._maxRedirects` inclusive, so the request count is the
      // initial fetch plus _maxRedirects (3) followed hops.
      expect(requested.length, 1 + 3);
    });

    test('a redirect onto another public host IS followed', () async {
      // The positive control for the two rejection tests above: the guard
      // refuses a private or non-http hop, and permits a public one. Needs no
      // corpus — the body is irrelevant to which URLs were requested — so it
      // runs in CI (review T1). The corpus-gated twin below adds that the
      // final response's bytes are what comes back.
      const finalUrl = 'https://$otherPublicHost/moved/hero.jpg';
      installTransport((url) async {
        if (url.host == publicHost) {
          return redirectResponse(finalUrl);
        }
        return imageResponse(const [], peer: otherPublicHost);
      });
      await fetchImageFromUrl(imageUrlText);
      expect(requested.map((u) => u.toString()), [imageUrlText, finalUrl]);
    });

    test('a non-image content-type is refused', () async {
      installTransport(
        (url) async => imageResponse(const [], contentType: 'text/html'),
      );
      await expectLater(
        fetchImageFromUrl(imageUrlText),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('not an image'),
          ),
        ),
      );
    });

    test('a non-200 status is refused', () async {
      installTransport(
        (url) async => _FakeResponse(
          body: const [],
          statusCode: HttpStatus.notFound,
          headers: _FakeHeaders(const {}),
          connectionInfo: _FakeConnectionInfo(InternetAddress(publicHost)),
        ),
      );
      await expectLater(
        fetchImageFromUrl(imageUrlText),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('HTTP 404'),
          ),
        ),
      );
    });
  });

  group('a blocked fetch is not a port scanner', () {
    // Review S13. A socket that CONNECTED to an internal address answered
    // 'must point at a public host', a REFUSED one answered 'connection
    // failed (Connection refused)', and a filtered one ran out the clock —
    // three distinguishable 422 bodies, i.e. a complete open/closed/filtered
    // oracle over loopback, the Docker bridge and cloud metadata for anyone
    // who can rebind DNS after the host check. `errorHandler()` copies an
    // AppException's message into the envelope verbatim, so the message IS
    // the client-visible outcome.
    //
    // A filtered port is a connect timeout, not the 20 s fetch timeout:
    // `connectionTimeout` is 10 s, so the client gives up first — which is
    // why this can be driven through the transport seam rather than by
    // waiting out the wall clock.
    test('open, closed and filtered are indistinguishable', () async {
      final open = await refusalMessage(
        (url) async => imageResponse(const [], peer: '127.0.0.1'),
      );
      final closed = await refusalMessage(
        (url) async => throw const SocketException(
          'Connection failed',
          osError: OSError('Connection refused', 61),
          port: 8080,
        ),
      );
      final filtered = await refusalMessage(
        (url) async => throw const SocketException(
          'Connection timed out',
          osError: OSError('Operation timed out', 60),
          port: 8080,
        ),
      );
      expect(open, imageFetchFailedMessage);
      expect(closed, open, reason: 'a closed port must answer like an open');
      expect(filtered, open, reason: 'a filtered port must answer alike too');
    });

    test('a TLS failure and an unverifiable peer answer alike', () async {
      final handshake = await refusalMessage(
        (url) async => throw const HandshakeException('certificate expired'),
      );
      final noPeer = await refusalMessage(
        (url) async => imageResponse(const [], peer: null),
      );
      expect(handshake, imageFetchFailedMessage);
      expect(noPeer, handshake);
    });
  });

  group('a rejected response is dropped, not drained', () {
    // Review S3: `drain()` has NO size limit, and the 25 MB cap is enforced
    // only in `collectImageBytes` on the ACCEPTED path — so every rejection
    // branch read the whole hostile body first (measured: 8,496 MB in 20 s
    // for one API call). The oversized-Content-Length branch was the
    // sharpest: it decided the body was too large and then read all of it.
    late _CountingBody body;

    setUp(() => body = _CountingBody());

    /// Asserts the fetch is refused AND that the refusal cost at most one
    /// already-buffered chunk of the body.
    Future<void> expectDropped(_FakeResponse Function(Stream<List<int>>) build)
    async {
      installTransport((url) async => build(body.stream));
      await expectLater(
        fetchImageFromUrl(imageUrlText),
        throwsA(isA<ValidationException>()),
      );
      expect(
        body.pulled,
        lessThanOrEqualTo(_CountingBody.chunkBytes),
        reason:
            'a rejected body must cost at most one buffered chunk, not the '
            '${_CountingBody.totalBytes ~/ (1024 * 1024)} MB on offer',
      );
    }

    _FakeResponse rejectable(
      Stream<List<int>> stream, {
      int statusCode = HttpStatus.ok,
      String contentType = 'image/jpeg',
      String peer = publicHost,
      String? location,
      int contentLength = 1,
    }) => _FakeResponse.streaming(
      stream: stream,
      statusCode: statusCode,
      isRedirect: location != null,
      headers: _FakeHeaders({
        HttpHeaders.contentTypeHeader: contentType,
        if (location != null) HttpHeaders.locationHeader: location,
      }),
      connectionInfo: _FakeConnectionInfo(InternetAddress(peer)),
      contentLength: contentLength,
    );

    test('an over-long Content-Length is not read', () async {
      await expectDropped(
        (stream) =>
            rejectable(stream, contentLength: maxImageBytes + 1),
      );
    });

    test('a private peer is not read', () async {
      await expectDropped((stream) => rejectable(stream, peer: '10.0.0.5'));
    });

    test('a redirect body is not read', () async {
      // The hop targets a private host, so the loop stops after this one
      // response and the count belongs to it alone.
      await expectDropped(
        (stream) => rejectable(
          stream,
          statusCode: HttpStatus.found,
          location: 'http://10.0.0.7/a.jpg',
        ),
      );
    });

    test('a non-200 body is not read', () async {
      await expectDropped(
        (stream) => rejectable(stream, statusCode: HttpStatus.notFound),
      );
    });

    test('a non-image body is not read', () async {
      await expectDropped(
        (stream) => rejectable(stream, contentType: 'text/html'),
      );
    });
  });

  group('the success path', skip: skipIfNoCorpus, () {
    // The one corpus photo the ingest suite already uses; a real ATK JPEG is
    // the only image data allowed to stand in for a downloaded one.
    const corpusImage = '0857-rich-chocolate-bundt-cake-hero.jpg';
    const corpusRecipe = '0857-rich-chocolate-bundt-cake.yaml';

    late Uint8List heroJpeg;
    late Directory tempDir;
    late ServerConfig config;
    late SaltDatabase db;
    late AuthRuntime runtime;
    late HttpServer server;
    late Uri baseUri;
    late String adminSession;
    // Synthesized credential: auth input cannot come from the recipe corpus.
    const adminPassword = 'admin-password-123';
    const csrf = {'X-Requested-With': 'SaltToTaste'};

    FutureOr<Response> dispatch(RequestContext context) {
      final path = context.request.uri.path;
      if (path == '/api/v1/auth/login') {
        return login_route.onRequest(context);
      }
      if (path == '/api/v1/recipes') {
        return recipes_route.onRequest(context);
      }
      final fromUrl = RegExp(
        r'^/api/v1/recipes/([^/]+)/images/from_url$',
      ).firstMatch(path);
      if (fromUrl != null) {
        return from_url_route.onRequest(context, fromUrl.group(1)!);
      }
      final storeFromUrl = RegExp(
        r'^/api/v1/recipes/([^/]+)/images/store_from_url$',
      ).firstMatch(path);
      if (storeFromUrl != null) {
        return store_from_url_route.onRequest(
          context,
          storeFromUrl.group(1)!,
        );
      }
      return Response(statusCode: HttpStatus.notFound, body: 'no route');
    }

    Future<(HttpClientResponse, String)> send(
      String method,
      String path, {
      Map<String, String> headers = const {},
      Object? jsonBody,
    }) async {
      // A real client against the real loopback test server — unrelated to
      // the substituted image transport, which only the fetch below uses.
      final client = HttpClient();
      try {
        final request = await client.openUrl(method, baseUri.resolve(path));
        headers.forEach(request.headers.set);
        if (jsonBody != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(jsonBody));
        }
        final response = await request.close();
        final body = await utf8.decoder.bind(response).join();
        return (response, body);
      } finally {
        client.close();
      }
    }

    Map<String, dynamic> jsonOf(String body) =>
        jsonDecode(body) as Map<String, dynamic>;

    Map<String, String> auth({bool withCsrf = false}) => {
      'Authorization': 'Bearer $adminSession',
      if (withCsrf) ...csrf,
    };

    setUpAll(() async {
      heroJpeg = File('$corpusImagesDir/$corpusImage').readAsBytesSync();
      tempDir = Directory.systemTemp.createTempSync('salt_from_url_test_');
      config = ServerConfig.fromEnvironment(
        environment: {'DATA_DIR': tempDir.path, 'LOG_LEVEL': 'ERROR'},
      );
      configureLogging(config);
      db = SaltDatabase.open(config.dbPath);
      runtime = AuthRuntime();

      // The production chain, built by the same function
      // routes/_middleware.dart calls (app_pipeline.dart documents why a
      // parallel hand-rolled pipeline is an anti-pattern here: one used to
      // keep the suite green through a security-relevant reorder).
      final pipeline = buildAppMiddleware(
        dispatch,
        config: config,
        database: db,
        authRuntime: runtime,
        nutritionProvider: _UnreachableProvider(),
        // maxRequests: 0 disables the search limiter; nothing here is a
        // search, and a 429 would mask the ingest result under test.
        searchRateLimiter: RequestRateLimiter(maxRequests: 0),
        searchService: () => InlineSearchService(db),
        logStore: LogStore(directory: config.logDir),
      );
      server = await serve(pipeline, InternetAddress.loopbackIPv4, 0);
      baseUri = Uri.parse('http://127.0.0.1:${server.port}');

      db.createUser(
        username: 'admin',
        passwordHash: await runtime.hasher.hash(adminPassword),
        role: 'admin',
      );
      final (response, body) = await send(
        'POST',
        '/api/v1/auth/login',
        jsonBody: {'username': 'admin', 'password': adminPassword},
      );
      expect(response.statusCode, HttpStatus.ok, reason: body);
      adminSession = jsonOf(body)['token'] as String;
    });

    tearDownAll(() async {
      await server.close(force: true);
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    /// Creates a fresh copy of the real Bundt cake recipe and returns its
    /// create-response body, so each test owns an independent recipe.
    Future<Map<String, dynamic>> createRecipe() async {
      final doc = loadCorpusRecipe(corpusRecipe).toMap();
      final (response, body) = await send(
        'POST',
        '/api/v1/recipes',
        headers: auth(withCsrf: true),
        jsonBody: {
          'recipe': {
            for (final key in editableRecipeKeys)
              if (doc.containsKey(key)) key: doc[key],
          },
        },
      );
      expect(response.statusCode, HttpStatus.created, reason: body);
      return jsonOf(body);
    }

    test('fetchImageFromUrl returns the fetched image verbatim', () async {
      installTransport((url) async => imageResponse(heroJpeg));
      final bytes = await fetchImageFromUrl(imageUrlText);
      expect(bytes, heroJpeg);
      expect(requested.map((u) => u.toString()), [imageUrlText]);
    });

    test(
      'the image kept after a cross-host redirect is the final one',
      () async {
        // The hop sequence itself is pinned ungated above; what needs corpus
        // bytes is that the bytes returned are the FINAL response's, not the
        // redirect's empty body.
        const finalUrl = 'https://$otherPublicHost/moved/hero.jpg';
        installTransport((url) async {
          if (url.host == publicHost) {
            return redirectResponse(finalUrl);
          }
          return imageResponse(heroJpeg, peer: otherPublicHost);
        });
        final bytes = await fetchImageFromUrl(imageUrlText);
        expect(bytes, heroJpeg);
      },
    );

    test('POST images/from_url stores the photo and returns the '
        'documented detail body', () async {
      final created = await createRecipe();
      final createdRecipe = created['recipe'] as Map<String, dynamic>;
      final id = createdRecipe['id'] as String;
      final slug = createdRecipe['slug'] as String;
      final createdImages = createdRecipe['images'] as Map<String, dynamic>;
      final priorCredit = (createdImages['credit'] as String? ?? '').trim();

      installTransport((url) async => imageResponse(heroJpeg));
      final (response, body) = await send(
        'POST',
        '/api/v1/recipes/$slug/images/from_url',
        headers: auth(withCsrf: true),
        jsonBody: {'url': imageUrlText},
      );
      expect(response.statusCode, HttpStatus.created, reason: body);
      expect(requested.map((u) => u.toString()), [imageUrlText]);

      // Evidence that this really is the production chain and not a
      // look-alike: these two headers come from securityHeaders() and
      // requestIdProvider(), neither of which a hand-rolled pipeline had.
      expect(response.headers.value('X-Content-Type-Options'), 'nosniff');
      expect(response.headers.value('X-Request-Id'), isNotEmpty);

      // The documented detail body (docs/API.md -> "201 detail body").
      final decoded = jsonOf(body);
      expect(
        decoded.keys.toSet(),
        {
          'recipe',
          'source_slug',
          'hero_image_url',
          'base_hash',
          'favorite',
          'note',
        },
      );
      expect(decoded['source_slug'], manualSourceSlug);
      expect(decoded['favorite'], false);
      expect(decoded['note'], isNull);
      expect(decoded['base_hash'], db.contentHashOf(id));

      final images =
          (decoded['recipe'] as Map<String, dynamic>)['images']
              as Map<String, dynamic>;
      final reference = images['hero'] as String;
      expect(reference, startsWith('images/$id-'));
      expect(reference, endsWith('.jpg'));
      expect(images['gallery'], isEmpty);
      // Precondition, asserted rather than branched on: the corpus recipe
      // carries no photo credit, so the default below is genuinely under
      // test. If the corpus ever gains one, this fails loudly instead of
      // silently disarming the assertion that follows (review Y6).
      expect(
        priorCredit,
        isEmpty,
        reason:
            '$corpusRecipe must ship without images.credit for the '
            'credit-default assertion below to mean anything',
      );
      expect(images['credit'], imageUrlText);
      // Pinned against the shape docs/API.md documents
      // (`/images/<source-slug>/<file>.jpg`), NOT against the same imageUrl()
      // helper the route used — otherwise a format change moves both sides.
      expect(
        decoded['hero_image_url'],
        '/images/my-recipes/${reference.substring('images/'.length)}',
      );

      // The bytes really landed in the library, byte-identical.
      final stored = File(
        '${config.libraryDir}/$manualSourceSlug/$reference',
      );
      expect(stored.existsSync(), isTrue);
      expect(stored.readAsBytesSync(), heroJpeg);

      // ...and the re-exported canonical YAML points at it.
      final exported = File(
        '${config.libraryDir}/$manualSourceSlug/recipes/$id.yaml',
      ).readAsStringSync();
      expect(exported, contains(reference.substring('images/'.length)));
    });

    test('the stored credit drops the download URL query string', () async {
      // A presigned S3/CDN URL carries its token in the query, and
      // `images.credit` is exported into the hand-editable YAML library and
      // shown in the UI — so the full URL wrote a live credential into a
      // file the user is invited to edit and share (2026-07-28 review,
      // item 1). The signature below is crafted: a negative-path input the
      // recipe corpus cannot supply.
      const signature = 'X-Amz-Signature=deadbeefdeadbeefdeadbeefdeadbeef';
      const presigned = '$imageUrlText?$signature&X-Amz-Expires=900';
      final created = await createRecipe();
      final createdRecipe = created['recipe'] as Map<String, dynamic>;
      final id = createdRecipe['id'] as String;
      final slug = createdRecipe['slug'] as String;

      installTransport((url) async => imageResponse(heroJpeg));
      final (response, body) = await send(
        'POST',
        '/api/v1/recipes/$slug/images/from_url',
        headers: auth(withCsrf: true),
        jsonBody: {'url': presigned},
      );
      expect(response.statusCode, HttpStatus.created, reason: body);
      // The query is stripped from what is STORED, never from what is
      // fetched — the signed URL still has to be the one downloaded.
      expect(requested.map((u) => u.toString()), [presigned]);

      final images =
          ((jsonOf(body)['recipe'] as Map<String, dynamic>)['images'])
              as Map<String, dynamic>;
      expect(images['credit'], imageUrlText);
      final exported = File(
        '${config.libraryDir}/$manualSourceSlug/recipes/$id.yaml',
      ).readAsStringSync();
      expect(exported, isNot(contains(signature)));
    });

    test('role=gallery appends and leaves the hero alone', () async {
      final created = await createRecipe();
      final slug =
          (created['recipe'] as Map<String, dynamic>)['slug'] as String;

      installTransport((url) async => imageResponse(heroJpeg));
      final (hero, heroBody) = await send(
        'POST',
        '/api/v1/recipes/$slug/images/from_url',
        headers: auth(withCsrf: true),
        jsonBody: {'url': imageUrlText},
      );
      expect(hero.statusCode, HttpStatus.created, reason: heroBody);
      final heroReference =
          ((jsonOf(heroBody)['recipe'] as Map<String, dynamic>)['images']
                  as Map<String, dynamic>)['hero']
              as String;

      final (response, body) = await send(
        'POST',
        '/api/v1/recipes/$slug/images/from_url',
        headers: auth(withCsrf: true),
        jsonBody: {'url': imageUrlText, 'role': 'gallery'},
      );
      expect(response.statusCode, HttpStatus.created, reason: body);
      final images =
          ((jsonOf(body)['recipe'] as Map<String, dynamic>)['images'])
              as Map<String, dynamic>;
      expect(images['hero'], heroReference);
      final gallery = images['gallery'] as List<dynamic>;
      expect(gallery, hasLength(1));
      expect(gallery.single, isNot(heroReference));
      expect(
        File(
          '${config.libraryDir}/$manualSourceSlug/${gallery.single}',
        ).existsSync(),
        isTrue,
      );
    });

    test('POST images/store_from_url returns a bare reference', () async {
      final created = await createRecipe();
      final recipe = created['recipe'] as Map<String, dynamic>;
      final slug = recipe['slug'] as String;
      // Whatever the corpus recipe shipped — the store call must not move it.
      final before = db.recipeByIdOrSlug(slug)!.recipe.images;

      installTransport((url) async => imageResponse(heroJpeg));
      final (response, body) = await send(
        'POST',
        '/api/v1/recipes/$slug/images/store_from_url',
        headers: auth(withCsrf: true),
        jsonBody: {'url': imageUrlText},
      );
      expect(response.statusCode, HttpStatus.created, reason: body);
      final decoded = jsonOf(body);
      expect(decoded.keys.toSet(), {'reference'});
      final reference = decoded['reference'] as String;
      expect(reference, startsWith('images/${recipe['id']}-'));
      expect(
        File(
          '${config.libraryDir}/$manualSourceSlug/$reference',
        ).readAsBytesSync(),
        heroJpeg,
      );

      // Store-only: the recipe document is untouched (docs/API.md) — the
      // stored file is referenced by nothing until a later PUT points at it.
      final after = db.recipeByIdOrSlug(slug)!.recipe.images;
      expect(after.hero, before.hero);
      expect(after.gallery, before.gallery);
      expect(after.credit, before.credit);
      expect(after.hero, isNot(reference));
    });
  });
}

/// A provider no image-ingest request may reach: nothing here touches
/// nutrition, so an outbound FoodData Central call would mean the chain wired
/// something the route should never have exercised.
final class _UnreachableProvider implements NutritionProvider {
  @override
  Future<List<FdcCandidate>> search(String query) async =>
      throw StateError('an image-ingest test reached FDC search("$query")');

  @override
  Future<FdcFood?> food(int fdcId) async =>
      throw StateError('an image-ingest test reached FDC food($fdcId)');
}

/// Minimal stand-ins for the dart:io HTTP transport. They implement only the
/// members `fetchImageFromUrl` actually touches; everything else is absorbed
/// by [noSuchMethod] (the real client's `userAgent`/timeout setters land
/// there).
class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._respond, this._requested);

  final Future<HttpClientResponse> Function(Uri) _respond;
  final List<Uri> _requested;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    _requested.add(url);
    return _FakeHttpClientRequest(url, _respond);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this.uri, this._respond);

  @override
  final Uri uri;
  final Future<HttpClientResponse> Function(Uri) _respond;

  @override
  Future<HttpClientResponse> close() => _respond(uri);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _FakeResponse({
    required List<int> body,
    required this.statusCode,
    required this.headers,
    required this.connectionInfo,
    this.isRedirect = false,
  }) : contentLength = body.length,
       super(Stream<List<int>>.fromIterable([body]));

  /// A response whose body is [stream] and whose declared [contentLength] is
  /// whatever the origin claimed — the two things a rejection path must be
  /// able to disagree about.
  _FakeResponse.streaming({
    required Stream<List<int>> stream,
    required this.statusCode,
    required this.headers,
    required this.connectionInfo,
    required this.contentLength,
    this.isRedirect = false,
  }) : super(stream);

  @override
  final int statusCode;

  @override
  final int contentLength;

  @override
  final HttpHeaders headers;

  @override
  final HttpConnectionInfo? connectionInfo;

  @override
  final bool isRedirect;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHeaders implements HttpHeaders {
  _FakeHeaders(this._values);

  final Map<String, String> _values;

  @override
  ContentType? get contentType {
    final raw = _values[HttpHeaders.contentTypeHeader];
    return raw == null ? null : ContentType.parse(raw);
  }

  @override
  String? value(String name) => _values[name.toLowerCase()];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A response body that hands out fixed-size chunks and counts the bytes it
/// was actually ASKED for. Its total dwarfs [maxImageBytes], so a reader with
/// no limit of its own consumes all of it — which is the difference the
/// rejection-path tests measure.
class _CountingBody {
  static const int chunkBytes = 64 * 1024;
  static const int chunks = 512;
  static const int totalBytes = chunkBytes * chunks; // 32 MiB

  int pulled = 0;

  Stream<List<int>> get stream async* {
    final chunk = Uint8List(chunkBytes);
    for (var i = 0; i < chunks; i += 1) {
      pulled += chunkBytes;
      yield chunk;
    }
  }
}

class _FakeConnectionInfo implements HttpConnectionInfo {
  _FakeConnectionInfo(this.remoteAddress);

  @override
  final InternetAddress remoteAddress;

  @override
  int get localPort => 0;

  @override
  int get remotePort => 443;
}
