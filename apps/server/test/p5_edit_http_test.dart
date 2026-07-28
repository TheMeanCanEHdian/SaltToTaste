import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart' hide requestLogger;
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/auth/tokens.dart';
import 'package:salt_server/src/bootstrap.dart' show fdcApiKeySetting;
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/middleware/request_logger.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/search/search_service.dart';
import 'package:salt_server/src/services/import_job.dart' show importJobRunning;
import 'package:salt_server/src/services/recipe_edit_service.dart'
    show editableRecipeKeys;
import 'package:test/test.dart';

import '../routes/api/v1/auth/login.dart' as login_route;
import '../routes/api/v1/backups/[name].dart' as backup_route;
import '../routes/api/v1/backups/index.dart' as backups_route;
import '../routes/api/v1/import/candidates.dart' as candidates_route;
import '../routes/api/v1/import/index.dart' as import_route;
import '../routes/api/v1/import/jobs/[id].dart' as import_job_route;
import '../routes/api/v1/library/index.dart' as library_route;
import '../routes/api/v1/library/rescan.dart' as rescan_route;
import '../routes/api/v1/nutrition/bulk.dart' as bulk_route;
import '../routes/api/v1/nutrition/jobs/[id].dart' as nutrition_job_route;
import '../routes/api/v1/nutrition/search.dart' as nutrition_search_route;
import '../routes/api/v1/recipes/[id]/favorite.dart' as favorite_route;
import '../routes/api/v1/recipes/[id]/images/from_url.dart' as from_url_route;
import '../routes/api/v1/recipes/[id]/images/index.dart' as images_route;
import '../routes/api/v1/recipes/[id]/images/store.dart' as store_route;
import '../routes/api/v1/recipes/[id]/images/store_from_url.dart'
    as store_from_url_route;
import '../routes/api/v1/recipes/[id]/index.dart' as recipe_route;
import '../routes/api/v1/recipes/[id]/note.dart' as note_route;
import '../routes/api/v1/recipes/[id]/nutrition/compute.dart' as compute_route;
import '../routes/api/v1/recipes/[id]/nutrition/index.dart' as nutrition_route;
import '../routes/api/v1/recipes/[id]/nutrition/matches/[pos].dart'
    as match_route;
import '../routes/api/v1/recipes/[id]/nutrition/matches/index.dart'
    as matches_route;
import '../routes/api/v1/recipes/index.dart' as recipes_route;
import '../routes/api/v1/settings/fdc_key.dart' as fdc_key_route;
import '../routes/api/v1/tags/[name]/style.dart' as tag_style_route;
import '../routes/api/v1/tags/index.dart' as tags_route;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

// Synthesized credentials: auth inputs cannot come from the recipe corpus.
const _adminPassword = 'admin-password-123';
const _memberPassword = 'correct-horse-battery';
const _csrf = {'X-Requested-With': 'SaltToTaste'};

/// P5 endpoint permission matrix + CRUD flow over real HTTP, with the real
/// Bundt cake corpus recipe as the create/update payload.
void main() {
  late Directory tempDir;
  late ServerConfig config;
  late SaltDatabase db;
  late AuthRuntime runtime;
  late HttpServer server;
  late Uri baseUri;

  late String adminSession; // bearer form of the admin session token
  late String memberSession;
  late String adminReadPat;
  late Map<String, Object?> submission; // the editor's create payload
  late FixtureProvider fixtureProvider;

  FutureOr<Response> dispatch(RequestContext context) {
    final path = context.request.uri.path;
    switch (path) {
      case '/api/v1/auth/login':
        return login_route.onRequest(context);
      case '/api/v1/recipes':
        return recipes_route.onRequest(context);
      case '/api/v1/library':
        return library_route.onRequest(context);
      case '/api/v1/library/rescan':
        return rescan_route.onRequest(context);
      case '/api/v1/backups':
        return backups_route.onRequest(context);
      case '/api/v1/nutrition/bulk':
        return bulk_route.onRequest(context);
      case '/api/v1/nutrition/search':
        return nutrition_search_route.onRequest(context);
      case '/api/v1/import':
        return import_route.onRequest(context);
      case '/api/v1/import/candidates':
        return candidates_route.onRequest(context);
      case '/api/v1/settings/fdc_key':
        return fdc_key_route.onRequest(context);
      case '/api/v1/tags':
        return tags_route.onRequest(context);
      default:
        for (final (pattern, handler)
            in <(RegExp, FutureOr<Response> Function(RequestContext, String))>[
              (
                RegExp(r'^/api/v1/recipes/([^/]+)/favorite$'),
                favorite_route.onRequest,
              ),
              (RegExp(r'^/api/v1/recipes/([^/]+)/note$'), note_route.onRequest),
              (
                RegExp(r'^/api/v1/recipes/([^/]+)/images$'),
                images_route.onRequest,
              ),
              (
                RegExp(r'^/api/v1/recipes/([^/]+)/images/from_url$'),
                from_url_route.onRequest,
              ),
              (
                RegExp(r'^/api/v1/recipes/([^/]+)/images/store$'),
                store_route.onRequest,
              ),
              (
                RegExp(r'^/api/v1/recipes/([^/]+)/images/store_from_url$'),
                store_from_url_route.onRequest,
              ),
              (
                RegExp(r'^/api/v1/recipes/([^/]+)/nutrition/compute$'),
                compute_route.onRequest,
              ),
              (
                RegExp(r'^/api/v1/recipes/([^/]+)/nutrition/matches$'),
                matches_route.onRequest,
              ),
              (
                RegExp(r'^/api/v1/recipes/([^/]+)/nutrition$'),
                nutrition_route.onRequest,
              ),
              (RegExp(r'^/api/v1/backups/([^/]+)$'), backup_route.onRequest),
              (
                RegExp(r'^/api/v1/tags/([^/]+)/style$'),
                tag_style_route.onRequest,
              ),
              (RegExp(r'^/api/v1/recipes/([^/]+)$'), recipe_route.onRequest),
            ]) {
          final match = pattern.firstMatch(path);
          if (match != null) {
            return handler(context, match.group(1)!);
          }
        }
        final importJob = RegExp(
          r'^/api/v1/import/jobs/([^/]+)$',
        ).firstMatch(path);
        if (importJob != null) {
          return import_job_route.onRequest(context, importJob.group(1)!);
        }
        final nutritionJob = RegExp(
          r'^/api/v1/nutrition/jobs/([^/]+)$',
        ).firstMatch(path);
        if (nutritionJob != null) {
          return nutrition_job_route.onRequest(context, nutritionJob.group(1)!);
        }
        final matchOverride = RegExp(
          r'^/api/v1/recipes/([^/]+)/nutrition/matches/([^/]+)$',
        ).firstMatch(path);
        if (matchOverride != null) {
          return match_route.onRequest(
            context,
            matchOverride.group(1)!,
            matchOverride.group(2)!,
          );
        }
        return Response(statusCode: HttpStatus.notFound, body: 'no route');
    }
  }

  Future<(HttpClientResponse, String)> send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    Object? jsonBody,
    List<int>? rawBody,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, baseUri.resolve(path));
      headers.forEach(request.headers.set);
      if (jsonBody != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(jsonBody));
      } else if (rawBody != null) {
        request.add(rawBody);
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

  Map<String, dynamic> errorOf(String body) =>
      jsonOf(body)['error'] as Map<String, dynamic>;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('salt_p5_http_test_');
    config = ServerConfig.fromEnvironment(
      environment: {'DATA_DIR': tempDir.path, 'LOG_LEVEL': 'ERROR'},
    );
    configureLogging(config);
    db = SaltDatabase.open(config.dbPath);
    runtime = AuthRuntime();

    fixtureProvider = FixtureProvider();
    final pipeline = dispatch
        .use(authProvider())
        .use(provider<NutritionProvider>((_) => fixtureProvider))
        // The recipe-listing route reads a search rate limiter for `?q=`
        // queries; disabled here (maxRequests: 0) so the suite's many
        // searches never trip it. Prod wires a live limiter in app_pipeline.
        .use(
          provider<RequestRateLimiter>(
            (_) => RequestRateLimiter(maxRequests: 0),
          ),
        )
        .use(provider<AuthRuntime>((_) => runtime))
        .use(provider<SaltDatabase>((_) => db))
        .use(provider<SearchService>((_) => InlineSearchService(db)))
        .use(provider<ServerConfig>((_) => config))
        .use(errorHandler())
        .use(requestLogger())
        .use(requestIdProvider());
    server = await serve(pipeline, InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://127.0.0.1:${server.port}');

    final adminId = db.createUser(
      username: 'admin',
      passwordHash: await runtime.hasher.hash(_adminPassword),
      role: 'admin',
    );
    db.createUser(
      username: 'sam',
      passwordHash: await runtime.hasher.hash(_memberPassword),
      role: 'member',
    );

    Future<String> login(String username, String password) async {
      final (response, body) = await send(
        'POST',
        '/api/v1/auth/login',
        jsonBody: {'username': username, 'password': password},
      );
      expect(response.statusCode, HttpStatus.ok, reason: body);
      return jsonOf(body)['token'] as String;
    }

    adminSession = await login('admin', _adminPassword);
    memberSession = await login('sam', _memberPassword);

    final pat = generatePat();
    db.createApiToken(
      userId: adminId,
      name: 'read pat',
      prefix: pat.prefix,
      tokenHash: hashToken(pat.token),
      scope: 'read',
    );
    adminReadPat = pat.token;

    // The permission matrix + CSRF/404/405 tests only need *a* payload to
    // assert 403/4xx on; use the real Bundt when the corpus is present, else
    // a minimal synthetic recipe so those run in CI. The corpus-backed
    // groups (CRUD/nutrition/import) are skipped without the corpus.
    final doc = corpusAvailable
        ? loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml').toMap()
        : <String, Object?>{'title': 'CI Test Recipe'};
    submission = {
      'recipe': {
        for (final key in editableRecipeKeys)
          if (doc.containsKey(key)) key: doc[key],
      },
    };
  });

  tearDownAll(() async {
    await server.close(force: true);
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  Map<String, String> auth(String token, {bool csrf = false}) => {
    'Authorization': 'Bearer $token',
    if (csrf) ..._csrf,
  };

  /// POSTs a compute and waits for the background job to leave `running`,
  /// returning its final job row. Compute is a 202 + `{job_id}`: the label
  /// lands in the DB later, so every assertion about it must come after this.
  Future<Map<String, dynamic>> computeAndWait(String recipeSlug) async {
    final (accepted, acceptedBody) = await send(
      'POST',
      '/api/v1/recipes/$recipeSlug/nutrition/compute',
      headers: auth(adminSession, csrf: true),
    );
    expect(
      accepted.statusCode,
      HttpStatus.accepted,
      reason: 'compute is asynchronous now: $acceptedBody',
    );
    final jobId = jsonOf(acceptedBody)['job_id'];
    expect(jobId, isA<int>(), reason: acceptedBody);

    // Poll the real endpoint the client polls. The FDC provider is a
    // recorded fixture here, so this settles in a few ticks; the deadline
    // only exists so a hang fails loudly instead of hanging the suite.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final (progress, progressBody) = await send(
        'GET',
        '/api/v1/nutrition/jobs/$jobId',
        headers: auth(adminSession),
      );
      expect(progress.statusCode, HttpStatus.ok, reason: progressBody);
      final job = jsonOf(progressBody);
      if (job['status'] != 'running') {
        return job;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('nutrition job $jobId never left "running"');
  }

  group('permission matrix', () {
    // Every server-data mutation must 403 for a member session and for an
    // admin's read-scoped PAT alike (effective permission = role ∩ scope).
    final mutations = <(String, String, Object?)>[
      (
        'POST',
        '/api/v1/recipes',
        {
          'recipe': {'title': 'X'},
        },
      ),
      (
        'PUT',
        '/api/v1/recipes/anything',
        {
          'recipe': {'title': 'X'},
        },
      ),
      ('DELETE', '/api/v1/recipes/anything', null),
      ('POST', '/api/v1/recipes/anything/images', null),
      (
        'POST',
        '/api/v1/recipes/anything/images/from_url',
        {'url': 'https://example.com/a.jpg'},
      ),
      ('POST', '/api/v1/recipes/anything/images/store', null),
      (
        'POST',
        '/api/v1/recipes/anything/images/store_from_url',
        {'url': 'https://example.com/a.jpg'},
      ),
      ('POST', '/api/v1/library/rescan', null),
      ('POST', '/api/v1/backups', {'include_images': false}),
      (
        'DELETE',
        '/api/v1/backups/salt-backup-20260101T000000-manual.tar.gz',
        null,
      ),
      ('POST', '/api/v1/recipes/anything/nutrition/compute', null),
      ('PUT', '/api/v1/recipes/anything/nutrition', {'serving_basis': 6}),
      (
        'PUT',
        '/api/v1/recipes/anything/nutrition/matches/0',
        {'skipped': true},
      ),
      ('PUT', '/api/v1/settings/fdc_key', {'api_key': 'x'}),
      ('POST', '/api/v1/nutrition/bulk', null),
      ('POST', '/api/v1/import', {'path': 'x'}),
    ];

    test('members are denied every server-data mutation', () async {
      for (final (method, path, body) in mutations) {
        final (response, responseBody) = await send(
          method,
          path,
          headers: auth(memberSession, csrf: true),
          jsonBody: body,
        );
        expect(
          response.statusCode,
          HttpStatus.forbidden,
          reason: '$method $path must be forbidden for a member',
        );
        expect(errorOf(responseBody)['code'], 'forbidden');
      }
    });

    test(
      'an admin read-scoped PAT is denied every server-data mutation',
      () async {
        for (final (method, path, body) in mutations) {
          final (response, responseBody) = await send(
            method,
            path,
            headers: auth(adminReadPat),
            jsonBody: body,
          );
          expect(
            response.statusCode,
            HttpStatus.forbidden,
            reason: '$method $path must be forbidden for a read PAT',
          );
          expect(errorOf(responseBody)['code'], 'forbidden');
        }
      },
    );

    test('admin-only reads are denied to members', () async {
      for (final path in [
        '/api/v1/library',
        '/api/v1/backups',
        '/api/v1/import/candidates',
      ]) {
        final (response, _) = await send(
          'GET',
          path,
          headers: auth(memberSession),
        );
        expect(response.statusCode, HttpStatus.forbidden, reason: path);
      }
    });

    test('a session mutation without the CSRF header -> 403 csrf', () async {
      final (response, body) = await send(
        'POST',
        '/api/v1/recipes',
        headers: auth(adminSession),
        jsonBody: submission,
      );
      expect(response.statusCode, HttpStatus.forbidden);
      expect(errorOf(body)['code'], 'csrf');
    });
  });

  group('recipe CRUD over HTTP', skip: skipIfNoCorpus, () {
    late String slug;
    late String id;
    late String uploadSlug;

    test('POST creates the Bundt cake and exports it', () async {
      final (response, body) = await send(
        'POST',
        '/api/v1/recipes',
        headers: auth(adminSession, csrf: true),
        jsonBody: submission,
      );
      expect(response.statusCode, HttpStatus.created, reason: body);
      final recipe = jsonOf(body)['recipe'] as Map<String, dynamic>;
      slug = recipe['slug'] as String;
      id = recipe['id'] as String;
      expect(recipe['title'], 'Rich Chocolate Bundt Cake');
      expect(jsonOf(body)['favorite'], false);
      expect(
        File('${config.libraryDir}/my-recipes/recipes/$id.yaml').existsSync(),
        isTrue,
      );
    });

    test('members can favorite and annotate it', () async {
      final (favorite, favoriteBody) = await send(
        'PUT',
        '/api/v1/recipes/$slug/favorite',
        headers: auth(memberSession, csrf: true),
      );
      expect(favorite.statusCode, HttpStatus.ok, reason: favoriteBody);
      expect(jsonOf(favoriteBody)['favorite'], true);

      final (note, noteBody) = await send(
        'PUT',
        '/api/v1/recipes/$slug/note',
        headers: auth(memberSession, csrf: true),
        jsonBody: {'note': 'Used 70% chocolate — perfect at 45 min.'},
      );
      expect(note.statusCode, HttpStatus.ok, reason: noteBody);

      // The member's detail view carries their personal data...
      final (detail, detailBody) = await send(
        'GET',
        '/api/v1/recipes/$slug',
        headers: auth(memberSession),
      );
      expect(detail.statusCode, HttpStatus.ok);
      expect(jsonOf(detailBody)['favorite'], true);
      expect(jsonOf(detailBody)['note'], contains('70% chocolate'));

      // ...and the admin's view does not see the member's note.
      final (adminDetail, adminDetailBody) = await send(
        'GET',
        '/api/v1/recipes/$slug',
        headers: auth(adminSession),
      );
      expect(jsonOf(adminDetailBody)['favorite'], false);
      expect(jsonOf(adminDetailBody)['note'], isNull);
    });

    test(
      'a read-scoped PAT may write personal data (documented exception)',
      () async {
        final (favorite, body) = await send(
          'PUT',
          '/api/v1/recipes/$slug/favorite',
          headers: auth(adminReadPat),
        );
        expect(favorite.statusCode, HttpStatus.ok, reason: body);
      },
    );

    test('the favorites filter narrows the listing per user', () async {
      // A second recipe nobody favorites, so the filter provably filters.
      final (second, secondBody) = await send(
        'POST',
        '/api/v1/recipes',
        headers: auth(adminSession, csrf: true),
        jsonBody: submission,
      );
      expect(second.statusCode, HttpStatus.created, reason: secondBody);

      final (all, allBody) = await send(
        'GET',
        '/api/v1/recipes',
        headers: auth(memberSession),
      );
      expect(all.statusCode, HttpStatus.ok);
      expect(jsonOf(allBody)['total'], 2);

      final (mine, mineBody) = await send(
        'GET',
        '/api/v1/recipes?favorites=true',
        headers: auth(memberSession),
      );
      expect(mine.statusCode, HttpStatus.ok);
      expect(
        jsonOf(mineBody)['total'],
        1,
        reason: 'only the favorited recipe, not both',
      );
      final items = jsonOf(mineBody)['items'] as List<dynamic>;
      expect((items.single as Map<String, dynamic>)['slug'], slug);
      expect((items.single as Map<String, dynamic>)['favorite'], true);

      // Combined with a search (covers the searchCards favoritesOnly SQL).
      final (searched, searchedBody) = await send(
        'GET',
        '/api/v1/recipes?favorites=true&q=chocolate',
        headers: auth(memberSession),
      );
      expect(searched.statusCode, HttpStatus.ok);
      expect(
        jsonOf(searchedBody)['total'],
        1,
        reason: 'both recipes match "chocolate"; only one is favorited',
      );

      // The admin favorited the first recipe through their read PAT — their
      // filter is independent of the member's and also excludes the second.
      final (adminFavs, adminFavsBody) = await send(
        'GET',
        '/api/v1/recipes?favorites=true',
        headers: auth(adminSession),
      );
      expect(adminFavs.statusCode, HttpStatus.ok);
      expect(jsonOf(adminFavsBody)['total'], 1);

      // Remove the second recipe again to keep later expectations simple.
      final secondSlug =
          (jsonOf(secondBody)['recipe'] as Map<String, dynamic>)['slug']
              as String;
      final (removed, _) = await send(
        'DELETE',
        '/api/v1/recipes/$secondSlug',
        headers: auth(adminSession, csrf: true),
      );
      expect(removed.statusCode, HttpStatus.noContent);
    });

    test('PUT updates through the same endpoint shape', () async {
      final (response, body) = await send(
        'PUT',
        '/api/v1/recipes/$slug',
        headers: auth(adminSession, csrf: true),
        jsonBody: {
          'recipe': {'category': 'Celebration Cakes'},
        },
      );
      expect(response.statusCode, HttpStatus.ok, reason: body);
      final recipe = jsonOf(body)['recipe'] as Map<String, dynamic>;
      expect(recipe['category'], 'Celebration Cakes');
      expect(
        recipe['title'],
        'Rich Chocolate Bundt Cake',
        reason: 'merge semantics keep unsubmitted fields',
      );
    });

    test('rescan and library status report over HTTP', () async {
      final (rescan, rescanBody) = await send(
        'POST',
        '/api/v1/library/rescan',
        headers: auth(adminSession, csrf: true),
      );
      expect(rescan.statusCode, HttpStatus.ok, reason: rescanBody);
      final report = jsonOf(rescanBody)['last_scan'] as Map<String, dynamic>;
      expect(report['files_seen'], greaterThanOrEqualTo(1));

      final (status, statusBody) = await send(
        'GET',
        '/api/v1/library',
        headers: auth(adminSession),
      );
      expect(status.statusCode, HttpStatus.ok);
      expect(jsonOf(statusBody)['last_scan'], isNotNull);
    });

    test('backups: create, list, download, delete', () async {
      final (create, createBody) = await send(
        'POST',
        '/api/v1/backups',
        headers: auth(adminSession, csrf: true),
        jsonBody: {'include_images': false},
      );
      expect(create.statusCode, HttpStatus.created, reason: createBody);
      final backup = jsonOf(createBody)['backup'] as Map<String, dynamic>;
      final name = backup['name'] as String;

      final (list, listBody) = await send(
        'GET',
        '/api/v1/backups',
        headers: auth(adminSession),
      );
      expect(list.statusCode, HttpStatus.ok);
      final names = [
        for (final item in jsonOf(listBody)['items'] as List<dynamic>)
          (item as Map<String, dynamic>)['name'],
      ];
      expect(names, contains(name));

      // The archive is binary; read it as bytes rather than UTF-8 text.
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          baseUri.resolve('/api/v1/backups/$name'),
        );
        auth(adminSession).forEach(request.headers.set);
        final download = await request.close();
        expect(download.statusCode, HttpStatus.ok);
        expect(download.headers.contentType?.mimeType, 'application/gzip');
        final bytes = await download.fold<int>(
          0,
          (total, chunk) => total + chunk.length,
        );
        expect(bytes, greaterThan(0));
      } finally {
        client.close();
      }

      final (remove, _) = await send(
        'DELETE',
        '/api/v1/backups/$name',
        headers: auth(adminSession, csrf: true),
      );
      expect(remove.statusCode, HttpStatus.noContent);
    });

    test('DELETE removes the recipe after taking a backup', () async {
      final (response, _) = await send(
        'DELETE',
        '/api/v1/recipes/$slug',
        headers: auth(adminSession, csrf: true),
      );
      expect(response.statusCode, HttpStatus.noContent);

      final (gone, goneBody) = await send(
        'GET',
        '/api/v1/recipes/$slug',
        headers: auth(adminSession),
      );
      expect(gone.statusCode, HttpStatus.notFound);
      expect(errorOf(goneBody)['code'], 'not_found');

      final (backups, backupsBody) = await send(
        'GET',
        '/api/v1/backups',
        headers: auth(adminSession),
      );
      expect(backups.statusCode, HttpStatus.ok);
      final names = [
        for (final item in jsonOf(backupsBody)['items'] as List<dynamic>)
          (item as Map<String, dynamic>)['name'] as String,
      ];
      expect(
        names.where((name) => name.contains('before-delete')),
        isNotEmpty,
        reason: 'deletes are always preceded by a backup',
      );
    });

    test('uploading real corpus photo bytes sets the hero image', () async {
      // Re-create a recipe to attach the photo to.
      final (create, createBody) = await send(
        'POST',
        '/api/v1/recipes',
        headers: auth(adminSession, csrf: true),
        jsonBody: submission,
      );
      expect(create.statusCode, HttpStatus.created);
      uploadSlug =
          (jsonOf(createBody)['recipe'] as Map<String, dynamic>)['slug']
              as String;

      final photo = File(
        '$corpusImagesDir/0857-rich-chocolate-bundt-cake-hero.jpg',
      ).readAsBytesSync();
      final (upload, uploadBody) = await send(
        'POST',
        '/api/v1/recipes/$uploadSlug/images?role=hero',
        headers: auth(adminSession, csrf: true),
        rawBody: photo,
      );
      expect(upload.statusCode, HttpStatus.created, reason: uploadBody);
      expect(jsonOf(uploadBody)['hero_image_url'], isNotNull);

      // Garbage bytes are rejected by the magic-byte check.
      final (bad, badBody) = await send(
        'POST',
        '/api/v1/recipes/$uploadSlug/images?role=hero',
        headers: auth(adminSession, csrf: true),
        rawBody: utf8.encode('definitely not an image'),
      );
      expect(bad.statusCode, HttpStatus.unprocessableEntity, reason: badBody);
    });

    test('images/store returns a reference without attaching it', () async {
      // Create with the `images` key stripped, so the hero legitimately
      // starts null — that is what proves the store endpoint doesn't attach
      // what it stores (the real Bundt submission ships a hero of its own).
      final recipeNoImages = Map<String, Object?>.of(
        submission['recipe']! as Map<String, Object?>,
      )..remove('images');
      final (create, createBody) = await send(
        'POST',
        '/api/v1/recipes',
        headers: auth(adminSession, csrf: true),
        jsonBody: {'recipe': recipeNoImages},
      );
      expect(create.statusCode, HttpStatus.created, reason: createBody);
      final slug =
          (jsonOf(createBody)['recipe'] as Map<String, dynamic>)['slug']
              as String;

      final photo = File(
        '$corpusImagesDir/0857-rich-chocolate-bundt-cake-hero.jpg',
      ).readAsBytesSync();
      final (store, storeBody) = await send(
        'POST',
        '/api/v1/recipes/$slug/images/store',
        headers: auth(adminSession, csrf: true),
        rawBody: photo,
      );
      expect(store.statusCode, HttpStatus.created, reason: storeBody);
      expect(jsonOf(storeBody)['reference'] as String, startsWith('images/'));

      // Store does NOT attach: the recipe's hero image stays null.
      final (get, getBody) = await send(
        'GET',
        '/api/v1/recipes/$slug',
        headers: auth(adminSession),
      );
      expect(get.statusCode, HttpStatus.ok);
      expect(
        jsonOf(getBody)['hero_image_url'],
        isNull,
        reason: 'store must not set the hero',
      );

      // Garbage bytes are still rejected by the magic-byte check.
      final (bad, badBody) = await send(
        'POST',
        '/api/v1/recipes/$slug/images/store',
        headers: auth(adminSession, csrf: true),
        rawBody: utf8.encode('not an image'),
      );
      expect(bad.statusCode, HttpStatus.unprocessableEntity, reason: badBody);

      // Clean up so the shared library count stays predictable downstream.
      await send(
        'DELETE',
        '/api/v1/recipes/$slug',
        headers: auth(adminSession, csrf: true),
      );
    });

    test(
      'images/store_from_url guards SSRF and bad input, attaches nothing',
      () async {
        final recipeNoImages = Map<String, Object?>.of(
          submission['recipe']! as Map<String, Object?>,
        )..remove('images');
        final (create, createBody) = await send(
          'POST',
          '/api/v1/recipes',
          headers: auth(adminSession, csrf: true),
          jsonBody: {'recipe': recipeNoImages},
        );
        expect(create.statusCode, HttpStatus.created, reason: createBody);
        final slug =
            (jsonOf(createBody)['recipe'] as Map<String, dynamic>)['slug']
                as String;

        // A loopback target is rejected by the SSRF guard before any socket
        // opens — the ValidationException surfaces as a 422.
        final (ssrf, ssrfBody) = await send(
          'POST',
          '/api/v1/recipes/$slug/images/store_from_url',
          headers: auth(adminSession, csrf: true),
          jsonBody: {'url': 'http://127.0.0.1/a.jpg'},
        );
        expect(
          ssrf.statusCode,
          HttpStatus.unprocessableEntity,
          reason: 'SSRF target must be rejected: $ssrfBody',
        );

        // A link-local metadata address is likewise rejected.
        final (meta, metaBody) = await send(
          'POST',
          '/api/v1/recipes/$slug/images/store_from_url',
          headers: auth(adminSession, csrf: true),
          jsonBody: {'url': 'http://169.254.169.254/latest/meta-data'},
        );
        expect(
          meta.statusCode,
          HttpStatus.unprocessableEntity,
          reason: metaBody,
        );

        // A missing url is a 422, not a crash.
        final (missing, missingBody) = await send(
          'POST',
          '/api/v1/recipes/$slug/images/store_from_url',
          headers: auth(adminSession, csrf: true),
          jsonBody: <String, Object?>{},
        );
        expect(
          missing.statusCode,
          HttpStatus.unprocessableEntity,
          reason: missingBody,
        );

        // Nothing was attached to the recipe by any of the above.
        final (get, getBody) = await send(
          'GET',
          '/api/v1/recipes/$slug',
          headers: auth(adminSession),
        );
        expect(jsonOf(getBody)['hero_image_url'], isNull);

        await send(
          'DELETE',
          '/api/v1/recipes/$slug',
          headers: auth(adminSession, csrf: true),
        );
      },
    );

    test('missing recipes 404; bad inputs 422; wrong methods 405', () async {
      // Personal-data and image endpoints on a recipe that does not exist —
      // authorized requests, so the 404 (not a 403) must come through.
      for (final (method, path) in [
        ('PUT', '/api/v1/recipes/no-such-recipe/favorite'),
        ('PUT', '/api/v1/recipes/no-such-recipe/note'),
        ('GET', '/api/v1/recipes/no-such-recipe/note'),
        ('POST', '/api/v1/recipes/no-such-recipe/images'),
      ]) {
        final (response, body) = await send(
          method,
          path,
          headers: auth(adminSession, csrf: true),
          jsonBody: method == 'PUT' && path.endsWith('/note')
              ? {'note': 'x'}
              : null,
        );
        expect(
          response.statusCode,
          HttpStatus.notFound,
          reason: '$method $path',
        );
        expect(errorOf(body)['code'], 'not_found');
      }

      // An invalid image role is a 422 and must not leave an orphan file.
      final imagesDir = Directory('${config.libraryDir}/my-recipes/images');
      final imagesBefore = imagesDir.existsSync()
          ? imagesDir.listSync().length
          : 0;
      final (badRole, badRoleBody) = await send(
        'POST',
        '/api/v1/recipes/$uploadSlug/images?role=banana',
        headers: auth(adminSession, csrf: true),
        rawBody: utf8.encode('body is irrelevant'),
      );
      expect(badRole.statusCode, HttpStatus.unprocessableEntity);
      expect(errorOf(badRoleBody)['code'], 'validation');
      final imagesAfter = imagesDir.existsSync()
          ? imagesDir.listSync().length
          : 0;
      expect(
        imagesAfter,
        imagesBefore,
        reason: 'a rejected role must not write an image file',
      );

      // Note-body validation: non-string and over-length are 422s.
      final (badNote, _) = await send(
        'PUT',
        '/api/v1/recipes/$uploadSlug/note',
        headers: auth(adminSession, csrf: true),
        jsonBody: {'note': 42},
      );
      expect(badNote.statusCode, HttpStatus.unprocessableEntity);
      final (longNote, _) = await send(
        'PUT',
        '/api/v1/recipes/$uploadSlug/note',
        headers: auth(adminSession, csrf: true),
        jsonBody: {'note': 'x' * 20001},
      );
      expect(longNote.statusCode, HttpStatus.unprocessableEntity);

      // Unsupported methods get the 405 envelope with an Allow header.
      final (patch, patchBody) = await send(
        'PATCH',
        '/api/v1/recipes/$uploadSlug',
        headers: auth(adminSession, csrf: true),
        jsonBody: {'recipe': <String, Object?>{}},
      );
      expect(patch.statusCode, HttpStatus.methodNotAllowed);
      expect(errorOf(patchBody)['code'], 'method_not_allowed');
      final allow = patch.headers.value('allow') ?? '';
      expect(allow, contains('GET'));
      expect(allow, contains('PUT'));
      expect(allow, contains('DELETE'));
    });
  });

  group(
    'nutrition over HTTP (success paths, recorded real FDC data)',
    skip: skipIfNoCorpus,
    () {
      late String slug;

      setUpAll(() async {
        // The CRUD group deleted its Bundt; create a fresh one.
        final (response, body) = await send(
          'POST',
          '/api/v1/recipes',
          headers: auth(adminSession, csrf: true),
          jsonBody: submission,
        );
        expect(response.statusCode, HttpStatus.created, reason: body);
        slug =
            (jsonOf(body)['recipe']! as Map<String, dynamic>)['slug']!
                as String;
      });

      test('compute -> label -> serving basis -> review flow', () async {
        // Serving basis before any compute is a 422, not a silent write.
        final (early, earlyBody) = await send(
          'PUT',
          '/api/v1/recipes/$slug/nutrition',
          headers: auth(adminSession, csrf: true),
          jsonBody: {'serving_basis': 6},
        );
        expect(early.statusCode, HttpStatus.unprocessableEntity);
        expect(errorOf(earlyBody)['code'], 'validation');

        // Admin computes; the Bundt is honestly partial (garnish line).
        final job = await computeAndWait(slug);
        expect(job['status'], 'done', reason: 'compute job failed: $job');

        // The label is fetched, not returned by the compute POST.
        final (computed, computedBody) = await send(
          'GET',
          '/api/v1/recipes/$slug/nutrition',
          headers: auth(adminSession),
        );
        expect(computed.statusCode, HttpStatus.ok, reason: computedBody);
        final label = jsonOf(computedBody);
        expect(label['status'], 'partial');
        expect(label['total_count'], 13);
        expect(label['matched_count'], 12);
        expect(
          label['computing_job_id'],
          isNull,
          reason: 'the job is finished; nothing should still be re-attachable',
        );
        final calories = (label['calories_per_serving']! as num).toDouble();
        expect(calories, greaterThan(350));
        expect(calories, lessThan(650));
        expect(
          label['low_confidence'],
          isA<int>(),
          reason: 'the badge needs the unreviewed low-confidence count',
        );

        // Members read the label and the match transparency.
        final (memberRead, memberBody) = await send(
          'GET',
          '/api/v1/recipes/$slug/nutrition',
          headers: auth(memberSession),
        );
        expect(memberRead.statusCode, HttpStatus.ok);
        expect(jsonOf(memberBody)['status'], 'partial');

        final (matchesRead, matchesReadBody) = await send(
          'GET',
          '/api/v1/recipes/$slug/nutrition/matches',
          headers: auth(memberSession),
        );
        expect(matchesRead.statusCode, HttpStatus.ok);
        final items = (jsonOf(matchesReadBody)['items']! as List)
            .cast<Map<String, dynamic>>();
        expect(items, hasLength(13));
        final flour = items.firstWhere(
          (item) => (item['raw']! as String).contains('all-purpose flour'),
        );
        expect(
          flour['candidates']! as List,
          isNotEmpty,
          reason: 'cache-only candidates come from the compute-time cache',
        );

        // Serving basis rescales instantly.
        final (rebased, rebasedBody) = await send(
          'PUT',
          '/api/v1/recipes/$slug/nutrition',
          headers: auth(adminSession, csrf: true),
          jsonBody: {'serving_basis': 6},
        );
        expect(rebased.statusCode, HttpStatus.ok);
        final rebasedCalories =
            (jsonOf(rebasedBody)['calories_per_serving']! as num).toDouble();
        expect(rebasedCalories, closeTo(calories * 2, 1));

        // Grams without a matched food (the locally-matched water line has
        // no FDC food to scale): a 422, not a silent no-op.
        final water = items.firstWhere(
          (item) => (item['raw']! as String).contains('boiling water'),
        );
        expect((water['match']! as Map<String, dynamic>)['fdc_id'], isNull);
        final (gramsOnly, gramsOnlyBody) = await send(
          'PUT',
          '/api/v1/recipes/$slug/nutrition/matches/${water['position']}',
          headers: auth(adminSession, csrf: true),
          jsonBody: {'grams': 10},
        );
        expect(gramsOnly.statusCode, HttpStatus.unprocessableEntity);
        expect(errorOf(gramsOnlyBody)['code'], 'validation');

        // The garnish line matched a food but has no resolvable amount;
        // skipping it completes the label.
        final garnish = items.firstWhere(
          (item) => (item['raw']! as String).contains('Confectioners'),
        );
        final position = garnish['position'];
        final (skip, skipBody) = await send(
          'PUT',
          '/api/v1/recipes/$slug/nutrition/matches/$position',
          headers: auth(adminSession, csrf: true),
          jsonBody: {'skipped': true},
        );
        expect(skip.statusCode, HttpStatus.ok, reason: skipBody);
        final skippedRow = (jsonOf(skipBody)['items']! as List)
            .cast<Map<String, dynamic>>()[position! as int];
        expect(
          (skippedRow['match']! as Map<String, dynamic>)['status'],
          'skipped',
        );
        final (finalRead, finalBody) = await send(
          'GET',
          '/api/v1/recipes/$slug/nutrition',
          headers: auth(memberSession),
        );
        expect(finalRead.statusCode, HttpStatus.ok);
        expect(jsonOf(finalBody)['status'], 'complete');
      });

      test(
        'a compute in flight: single-flight, and admin-only re-attach',
        () async {
          // Hold the compute open so the in-flight state is observable; the
          // recorded fixtures otherwise finish before the next request lands.
          final gate = Completer<void>();
          fixtureProvider.gate = gate;
          addTearDown(() {
            fixtureProvider.gate = null;
            if (!gate.isCompleted) gate.complete();
          });

          // A fresh recipe whose ingredient text has never been matched, so
          // the compute must call the provider and block on the gate. Reusing
          // the Bundt's lines would hit the ingredient-match cache and finish
          // before the next request landed, leaving nothing in flight to
          // observe.
          final (created, createdBody) = await send(
            'POST',
            '/api/v1/recipes',
            headers: auth(adminSession, csrf: true),
            jsonBody: {
              ...submission,
              'recipe': {
                ...(submission['recipe']! as Map<String, Object?>),
                'title': 'Single Flight Bundt',
                'ingredients': [
                  {
                    'group': null,
                    'items': [
                      {'raw': '2 cups uncached-single-flight-test-flour'},
                    ],
                  },
                ],
              },
            },
          );
          expect(created.statusCode, HttpStatus.created, reason: createdBody);
          final freshSlug =
              (jsonOf(createdBody)['recipe']! as Map<String, dynamic>)['slug']!
                  as String;
          addTearDown(() async {
            await send(
              'DELETE',
              '/api/v1/recipes/$freshSlug',
              headers: auth(adminSession, csrf: true),
            );
          });

          final (first, firstBody) = await send(
            'POST',
            '/api/v1/recipes/$freshSlug/nutrition/compute',
            headers: auth(adminSession, csrf: true),
          );
          expect(first.statusCode, HttpStatus.accepted, reason: firstBody);
          final jobId = jsonOf(firstBody)['job_id'];

          // Single-flight: a second POST while one runs re-attaches to the same
          // job rather than double-spending the FDC budget.
          final (second, secondBody) = await send(
            'POST',
            '/api/v1/recipes/$freshSlug/nutrition/compute',
            headers: auth(adminSession, csrf: true),
          );
          expect(second.statusCode, HttpStatus.accepted, reason: secondBody);
          expect(
            jsonOf(secondBody)['job_id'],
            jobId,
            reason:
                'a concurrent compute must re-attach, not start a second job',
          );

          // An admin reopening the page re-attaches via computing_job_id...
          final (adminRead, adminBody) = await send(
            'GET',
            '/api/v1/recipes/$freshSlug/nutrition',
            headers: auth(adminSession),
          );
          expect(
            jsonOf(adminBody)['computing_job_id'],
            jobId,
            reason: adminBody,
          );

          // ...but a member must NOT be handed a job id: polling it is
          // admin-only, so every poll would 403 and surface as a false
          // "lost track of the compute" error on their label.
          final (memberRead, memberBody) = await send(
            'GET',
            '/api/v1/recipes/$freshSlug/nutrition',
            headers: auth(memberSession),
          );
          expect(memberRead.statusCode, HttpStatus.ok);
          expect(
            jsonOf(memberBody).containsKey('computing_job_id'),
            isFalse,
            reason: 'a member cannot poll the job endpoint: $memberBody',
          );

          // The job endpoint itself stays admin-only.
          final (memberJob, memberJobBody) = await send(
            'GET',
            '/api/v1/nutrition/jobs/$jobId',
            headers: auth(memberSession),
          );
          expect(memberJob.statusCode, HttpStatus.forbidden);
          expect(errorOf(memberJobBody)['code'], 'forbidden');

          gate.complete();
          // Let the job drain, then the id is gone: nothing left to re-attach.
          final deadline = DateTime.now().add(const Duration(seconds: 30));
          while (DateTime.now().isBefore(deadline)) {
            final (progress, progressBody) = await send(
              'GET',
              '/api/v1/nutrition/jobs/$jobId',
              headers: auth(adminSession),
            );
            expect(progress.statusCode, HttpStatus.ok, reason: progressBody);
            if (jsonOf(progressBody)['status'] != 'running') break;
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          final (afterRead, afterBody) = await send(
            'GET',
            '/api/v1/recipes/$freshSlug/nutrition',
            headers: auth(adminSession),
          );
          expect(
            jsonOf(afterBody).containsKey('computing_job_id'),
            isFalse,
            reason: 'the finished job must stop being advertised: $afterBody',
          );
        },
      );

      test('a yield-only recipe divides by the yield, not the batch', () async {
        // Post-split, `MAKES ABOUT 16 LARGE COOKIES` leaves serves null. The
        // basis must fall back to the yield count, or the label would report
        // one 16-cookie batch as a single serving.
        final (created, createdBody) = await send(
          'POST',
          '/api/v1/recipes',
          headers: auth(adminSession, csrf: true),
          jsonBody: {
            ...submission,
            'recipe': {
              ...(submission['recipe']! as Map<String, Object?>),
              'title': 'Yield Basis Cookies',
              'servings': 'MAKES ABOUT 16 LARGE COOKIES',
            },
          },
        );
        expect(created.statusCode, HttpStatus.created, reason: createdBody);
        final recipe = jsonOf(createdBody)['recipe']! as Map<String, dynamic>;
        final yieldSlug = recipe['slug']! as String;
        addTearDown(() async {
          await send(
            'DELETE',
            '/api/v1/recipes/$yieldSlug',
            headers: auth(adminSession, csrf: true),
          );
        });
        expect(
          recipe['serves'],
          isNull,
          reason: 'a yield is not a serving count: $createdBody',
        );

        final job = await computeAndWait(yieldSlug);
        expect(job['status'], 'done', reason: 'compute job failed: $job');
        final (read, readBody) = await send(
          'GET',
          '/api/v1/recipes/$yieldSlug/nutrition',
          headers: auth(adminSession),
        );
        expect(read.statusCode, HttpStatus.ok, reason: readBody);
        expect(jsonOf(readBody)['serving_basis'], 16, reason: readBody);
      });

      test('an ingredient edit flips the label to stale', () async {
        // Drop the garnish line via the normal PUT (merge semantics).
        final (before, beforeBody) = await send(
          'GET',
          '/api/v1/recipes/$slug',
          headers: auth(adminSession),
        );
        expect(before.statusCode, HttpStatus.ok, reason: beforeBody);
        final recipe = jsonOf(beforeBody)['recipe']! as Map<String, dynamic>;
        final groups = (recipe['ingredients']! as List)
            .cast<Map<String, dynamic>>();
        final lastGroup = groups.last;
        final lastItems = (lastGroup['items']! as List)
            .cast<Map<String, dynamic>>();
        lastGroup['items'] = lastItems.sublist(0, lastItems.length - 1);
        final (edited, editedBody) = await send(
          'PUT',
          '/api/v1/recipes/$slug',
          headers: auth(adminSession, csrf: true),
          jsonBody: {
            'recipe': {'ingredients': groups},
          },
        );
        expect(edited.statusCode, HttpStatus.ok, reason: editedBody);

        final (read, readBody) = await send(
          'GET',
          '/api/v1/recipes/$slug/nutrition',
          headers: auth(memberSession),
        );
        expect(read.statusCode, HttpStatus.ok);
        expect(jsonOf(readBody)['status'], 'stale');

        // The review HIGH: a serving-basis change must NOT clear staleness.
        final (rebased, rebasedBody) = await send(
          'PUT',
          '/api/v1/recipes/$slug/nutrition',
          headers: auth(adminSession, csrf: true),
          jsonBody: {'serving_basis': 12},
        );
        expect(rebased.statusCode, HttpStatus.ok, reason: rebasedBody);
        expect(jsonOf(rebasedBody)['status'], 'stale');

        // Recomputing clears it.
        final job = await computeAndWait(slug);
        expect(job['status'], 'done', reason: 'recompute job failed: $job');
        final (recomputed, recomputedBody) = await send(
          'GET',
          '/api/v1/recipes/$slug/nutrition',
          headers: auth(memberSession),
        );
        expect(recomputed.statusCode, HttpStatus.ok, reason: recomputedBody);
        final label = jsonOf(recomputedBody);
        expect(
          label['status'],
          'complete',
          reason: 'the unresolvable garnish line is gone',
        );
        expect(label['total_count'], 12);
      });
    },
  );

  group(
    'import over HTTP (success paths, real corpus)',
    skip: skipIfNoCorpus,
    () {
      setUpAll(() {
        // Drop two real corpus files into a v1 source root inside the
        // allowlisted import directory.
        final recipes = Directory('${config.importDir}/atk-two/recipes')
          ..createSync(recursive: true);
        for (final name in [
          '0857-rich-chocolate-bundt-cake.yaml',
          '0747-100-percent-whole-wheat-pancakes.yaml',
        ]) {
          File('$corpusRecipesDir/$name').copySync('${recipes.path}/$name');
        }
      });

      test('candidates lists the detected v1 root for an admin', () async {
        final (response, body) = await send(
          'GET',
          '/api/v1/import/candidates',
          headers: auth(adminSession),
        );
        expect(response.statusCode, HttpStatus.ok, reason: body);
        final data = jsonOf(body);
        expect(data['import_dir'], config.importDir);
        final items = (data['items']! as List).cast<Map<String, dynamic>>();
        final atk = items.firstWhere((item) => item['path'] == 'atk-two');
        expect(atk['kind'], 'v1');
        expect(atk['file_count'], 2);
      });

      test('a non-string path is a 422, not a crash', () async {
        final (response, body) = await send(
          'POST',
          '/api/v1/import',
          headers: auth(adminSession, csrf: true),
          jsonBody: {'path': 42},
        );
        expect(response.statusCode, HttpStatus.unprocessableEntity);
        expect(errorOf(body)['code'], 'validation');
      });

      test('a path outside the import dir is a 422', () async {
        final (response, body) = await send(
          'POST',
          '/api/v1/import',
          headers: auth(adminSession, csrf: true),
          jsonBody: {'path': '../../etc'},
        );
        expect(response.statusCode, HttpStatus.unprocessableEntity);
        expect(errorOf(body)['code'], 'validation');
      });

      test(
        'POST starts a job; it runs to done and jobs/<id> reports it',
        () async {
          final (started, startedBody) = await send(
            'POST',
            '/api/v1/import',
            headers: auth(adminSession, csrf: true),
            jsonBody: {'path': 'atk-two'},
          );
          expect(started.statusCode, 202, reason: startedBody);
          final jobId = (jsonOf(startedBody)['job_id']! as num).toInt();

          var job = <String, dynamic>{};
          final deadline = DateTime.now().add(const Duration(seconds: 30));
          while (DateTime.now().isBefore(deadline)) {
            final (poll, pollBody) = await send(
              'GET',
              '/api/v1/import/jobs/$jobId',
              headers: auth(adminSession),
            );
            expect(poll.statusCode, HttpStatus.ok, reason: pollBody);
            job = jsonOf(pollBody);
            // The terminal row is written from inside the isolate, which only
            // then clears the single-flight latch. The next test fires imports
            // back-to-back, so waiting on the row alone races that latch.
            if (job['status'] != 'running' && !importJobRunning) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(
            job['status'],
            'done',
            reason: 'still running after 30s: $job',
          );
          expect(job['total'], 2);
          expect(job['imported'], 2);
          expect(job['legacy'], false);
          expect(job['log'], isA<List<dynamic>>());
        },
      );

      test('a second import while one runs is a 409', () async {
        // Fire two back-to-back; the second must lose the single-flight race
        // (the first is still in its isolate).
        final first = send(
          'POST',
          '/api/v1/import',
          headers: auth(adminSession, csrf: true),
          jsonBody: {'path': 'atk-two'},
        );
        final second = send(
          'POST',
          '/api/v1/import',
          headers: auth(adminSession, csrf: true),
          jsonBody: {'path': 'atk-two'},
        );
        final results = await Future.wait([first, second]);
        final codes = results.map((r) => r.$1.statusCode).toList();
        expect(
          codes,
          containsAll([202, HttpStatus.conflict]),
          reason: 'one starts (202), one is rejected (409): $codes',
        );
        final conflictBody = results
            .firstWhere((r) => r.$1.statusCode == HttpStatus.conflict)
            .$2;
        expect(errorOf(conflictBody)['code'], 'conflict');
      });

      test('jobs/<id> for an unknown or non-numeric id is a 404', () async {
        for (final id in ['999999', 'abc']) {
          final (response, body) = await send(
            'GET',
            '/api/v1/import/jobs/$id',
            headers: auth(adminSession),
          );
          expect(response.statusCode, HttpStatus.notFound, reason: 'id=$id');
          expect(errorOf(body)['code'], 'not_found');
        }
      });
    },
  );

  group('concurrent-save precondition (review B11)', () {
    // Corpus-free: the precondition mechanics need any recipe at all.
    late String recipeId;
    late String baseHash;

    test('detail carries base_hash; a stale echo is a 409', () async {
      final (created, createdBody) = await send(
        'POST',
        '/api/v1/recipes',
        headers: auth(adminSession, csrf: true),
        jsonBody: {
          'recipe': {'title': 'Two Tabs Probe'},
        },
      );
      expect(created.statusCode, HttpStatus.created, reason: createdBody);
      recipeId = (jsonOf(createdBody)['recipe'] as Map)['id'] as String;
      baseHash = jsonOf(createdBody)['base_hash'] as String;

      // Tab B saves first (no precondition — scripted last-write-wins
      // stays legal).
      final (other, otherBody) = await send(
        'PUT',
        '/api/v1/recipes/$recipeId',
        headers: auth(adminSession, csrf: true),
        jsonBody: {
          'recipe': {'category': 'Tab B'},
        },
      );
      expect(other.statusCode, HttpStatus.ok, reason: otherBody);

      // Tab A still holds the original hash: its save must NOT silently
      // obliterate Tab B's.
      final (conflicted, conflictedBody) = await send(
        'PUT',
        '/api/v1/recipes/$recipeId',
        headers: auth(adminSession, csrf: true),
        jsonBody: {
          'recipe': {'category': 'Tab A'},
          'base_hash': baseHash,
        },
      );
      expect(conflicted.statusCode, HttpStatus.conflict);
      expect(errorOf(conflictedBody)['code'], 'conflict');

      // Reload → fresh hash → the save goes through, and the response
      // carries the NEXT hash so the editor can keep saving.
      final (reloaded, reloadedBody) = await send(
        'GET',
        '/api/v1/recipes/$recipeId',
        headers: auth(adminSession),
      );
      expect(reloaded.statusCode, HttpStatus.ok);
      final freshHash = jsonOf(reloadedBody)['base_hash'] as String;
      final (saved, savedBody) = await send(
        'PUT',
        '/api/v1/recipes/$recipeId',
        headers: auth(adminSession, csrf: true),
        jsonBody: {
          'recipe': {'category': 'Tab A'},
          'base_hash': freshHash,
        },
      );
      expect(saved.statusCode, HttpStatus.ok, reason: savedBody);
      expect(jsonOf(savedBody)['base_hash'], isA<String>());
      expect(jsonOf(savedBody)['base_hash'], isNot(freshHash));
    });

    test('cleanup: the probe recipe deletes', () async {
      final (deleted, _) = await send(
        'DELETE',
        '/api/v1/recipes/$recipeId',
        headers: auth(adminSession, csrf: true),
      );
      expect(deleted.statusCode, HttpStatus.noContent);
    });
  });

  group('FDC provider failure surfaces as 422 (review B15)', () {
    test('the manual food search names the fixable cause, not a 500', () async {
      db.setSetting(fdcApiKeySetting, 'test-key');
      fixtureProvider.failWith =
          'FoodData Central rejected the API key. '
          'Check it in Settings → Nutrition.';
      try {
        // A unique term so the search cache cannot answer before the
        // provider throws.
        final (response, body) = await send(
          'GET',
          '/api/v1/nutrition/search?q=b15-probe-term',
          headers: auth(adminSession),
        );
        expect(
          response.statusCode,
          HttpStatus.unprocessableEntity,
          reason: body,
        );
        expect(errorOf(body)['code'], 'validation');
        expect(errorOf(body)['message'], contains('rejected the API key'));
      } finally {
        fixtureProvider.failWith = null;
      }
    });
  });

  group('encoded path parameters (review B8)', () {
    // dart_frog's router matches the percent-ENCODED path and hands captures
    // to onRequest undecoded, and the app client encodes correctly — so any
    // tag with a space or non-ASCII letter arrived as 'main%20course' and
    // 404ed forever. Synthesized names: the encoding path is unreachable
    // with single-word corpus tags. Runs corpus-free (CI covers it).
    late String recipeId;

    test('a tag with a space (and accents) can be styled', () async {
      final (created, createdBody) = await send(
        'POST',
        '/api/v1/recipes',
        headers: auth(adminSession, csrf: true),
        jsonBody: {
          'recipe': {
            'title': 'Tag URL Encoding Probe',
            'tags': ['main course', 'sazón'],
          },
        },
      );
      expect(created.statusCode, HttpStatus.created, reason: createdBody);
      recipeId = (jsonOf(createdBody)['recipe'] as Map)['id'] as String;

      for (final tag in ['main course', 'sazón']) {
        final (styled, styledBody) = await send(
          'PUT',
          '/api/v1/tags/${Uri.encodeComponent(tag)}/style',
          headers: auth(adminSession, csrf: true),
          jsonBody: {'icon': 'utensils', 'color': '#960000'},
        );
        expect(
          styled.statusCode,
          HttpStatus.ok,
          reason: '$tag: $styledBody',
        );
      }

      final (listed, listedBody) = await send(
        'GET',
        '/api/v1/tags',
        headers: auth(adminSession),
      );
      expect(listed.statusCode, HttpStatus.ok);
      final items = (jsonOf(listedBody)['items'] as List)
          .cast<Map<String, dynamic>>();
      final styledNames = [
        for (final item in items)
          if (item['icon'] == 'utensils') item['name'],
      ];
      expect(styledNames, containsAll(['main course', 'sazón']));
    });

    test('cleanup: the probe recipe deletes by its id', () async {
      final (deleted, deletedBody) = await send(
        'DELETE',
        '/api/v1/recipes/$recipeId',
        headers: auth(adminSession, csrf: true),
      );
      expect(deleted.statusCode, HttpStatus.noContent, reason: deletedBody);
    });
  });
}
