import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/app_pipeline.dart';
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/search/search_service.dart';
import 'package:test/test.dart';

import '../routes/api/v1/admin/nutrition_review.dart' as review_route;
import '../routes/api/v1/auth/change_password.dart' as change_password_route;
import '../routes/api/v1/auth/login.dart' as login_route;
import '../routes/api/v1/auth/me.dart' as me_route;
import '../routes/api/v1/import/candidates.dart' as candidates_route;
import '../routes/api/v1/import/index.dart' as import_route;
import '../routes/api/v1/import/jobs/[id].dart' as import_job_route;
import '../routes/api/v1/library/index.dart' as library_route;
import '../routes/api/v1/library/rescan.dart' as rescan_route;
import '../routes/api/v1/nutrition/jobs/[id].dart' as nutrition_job_route;
import '../routes/api/v1/recipes/[id]/favorite.dart' as favorite_route;
import '../routes/api/v1/recipes/[id]/index.dart' as recipe_route;
import '../routes/api/v1/recipes/[id]/note.dart' as note_route;
import '../routes/api/v1/recipes/[id]/nutrition/compute.dart' as compute_route;
import '../routes/api/v1/recipes/[id]/nutrition/index.dart' as nutrition_route;
import '../routes/api/v1/recipes/[id]/nutrition/matches/index.dart'
    as matches_route;
import '../routes/api/v1/recipes/index.dart' as recipes_route;
import '../routes/api/v1/tags/[name]/style.dart' as tag_style_route;
import '../routes/api/v1/tags/index.dart' as tags_route;
import '../routes/api/v1/users/index.dart' as users_route;
import 'support/contract_goldens.dart';
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

// Auth inputs cannot come from a recipe corpus, so they are synthesized —
// as everywhere else in this suite. Same for the personal note below: it is
// user-authored text, not recipe/ingredient/nutrition data.
const String _adminPassword = 'contract-admin-password';
const String _newPassword = 'contract-changed-password';
const String _tempUsername = 'newcomer';
const String _note = 'Halved the chili flakes.';
const Map<String, String> _csrf = {'X-Requested-With': 'SaltToTaste'};

/// The one real legacy-v0 recipe committed to this repo (kept from the P8
/// cutover). It needs no corpus, which is what lets the recipe, tag and
/// match goldens be captured in CI.
const String _legacyDir = 'test/fixtures/legacy-v0';
const String _legacyFile =
    'brown-butter-gemelli-with-asparagus,-walnuts,-and-lemony-ricotta.yaml';
const String _legacyImage =
    'brown-butter-gemelli-with-asparagus,-walnuts,-and-lemony-ricotta.jpg';

// The two corpus recipes with recorded real FDC responses (see
// test/fixtures/fdc), plus a third used only as a "new file appeared in the
// library" case for the reconciliation scan.
const String _bundtFile = '0857-rich-chocolate-bundt-cake.yaml';
const String _pancakesFile = '0747-100-percent-whole-wheat-pancakes.yaml';
const String _soupFile = '0020-sweet-potato-soup.yaml';
const String _bundtSlug = 'rich-chocolate-bundt-cake';

// A deliberately broken document — the one class of input the corpus cannot
// supply. It exercises the importer's failure counter and the scan's
// `skipped` entries, both of which the Flutter app parses.
const String _malformedName = 'zzzz-malformed-document.yaml';
const String _malformedYaml = 'title: "unterminated\n';

// A conflict copy exactly as `exportRecipeYaml` names them.
const String _conflictSuffix = '.conflict-20260101T120000.yaml';

/// Golden contract fixtures: the REAL server routes render the bodies, the
/// bodies are committed under `packages/salt_shared/test/fixtures/contract`,
/// and `apps/app/test/contract_golden_parse_test.dart` re-parses those same
/// files with the REAL Flutter models.
///
/// A server-side key rename now fails HERE (the golden no longer matches)
/// instead of silently changing what the app sees — the review's motivating
/// example being `must_change_password`, which the app defaults to `false`
/// when the key is missing, so a rename would quietly stop forcing password
/// changes.
///
/// The captures are split in two so that everything which can be generated
/// WITHOUT the ATK corpus is generated in CI as well. A gate around the
/// whole file would leave the pin to a developer machine, and the static
/// committed goldens the app parses would keep agreeing with themselves.
///
/// Regenerate deliberately:
///   SALT_CORPUS_DIR=... UPDATE_CONTRACT_GOLDENS=1 \
///     dart test test/contract_golden_test.dart
void main() {
  // Runs everywhere, corpus or not: the committed goldens are the app's
  // only input, so a deleted or corrupted one must fail in CI too. Skipped
  // while regenerating, when the files are being (re)created by this run.
  group(
    'committed contract goldens',
    skip: updateContractGoldens
        ? 'regenerating: the files are written by this run'
        : null,
    () {
      test('every named golden exists and is a JSON object', () {
        for (final name in contractGoldenNames) {
          final file = contractGoldenFile(name);
          expect(
            file.existsSync(),
            isTrue,
            reason:
                '${file.path} is missing; regenerate with '
                'UPDATE_CONTRACT_GOLDENS=1 dart test '
                'test/contract_golden_test.dart',
          );
          expect(
            jsonDecode(file.readAsStringSync()),
            isA<Map<String, Object?>>(),
            reason: '${file.path} must hold one response body',
          );
        }
      });

      test('the goldens carry no machine-specific values', () {
        for (final name in contractGoldenNames) {
          final text = contractGoldenFile(name).readAsStringSync();
          for (final leak in [
            Directory.systemTemp.path,
            '/Users/',
            '/home/',
          ]) {
            expect(
              text,
              isNot(contains(leak)),
              reason: '$name.json leaks a local path ($leak)',
            );
          }
        }
      });
    },
  );

  test('every golden belongs to exactly one capture group', () {
    expect(
      corpusFreeContractGoldenNames.toSet().intersection(
        corpusBackedContractGoldenNames.toSet(),
      ),
      isEmpty,
    );
    expect(
      {...corpusFreeContractGoldenNames, ...corpusBackedContractGoldenNames},
      contractGoldenNames.toSet(),
    );
  });

  // ------------------------------------------------------------------
  // No corpus needed — runs in CI, where the pin has to bite.
  // ------------------------------------------------------------------
  group('corpus-free bodies match the committed goldens', () {
    final harness = _Harness('salt_contract_free_');

    setUpAll(() async {
      await harness.start();
      final adminSession = await harness.seedAdminAndCaptureAuth();

      // A real recipe with no corpus: the committed legacy-v0 fixture,
      // imported through the real POST /api/v1/import (format
      // auto-detected).
      final root = Directory('${harness.config.importDir}/legacy sample')
        ..createSync(recursive: true);
      Directory('${root.path}/_recipes').createSync();
      Directory('${root.path}/_images').createSync();
      File('$_legacyDir/_recipes/$_legacyFile').copySync(
        '${root.path}/_recipes/$_legacyFile',
      );
      File('$_legacyDir/_images/$_legacyImage').copySync(
        '${root.path}/_images/$_legacyImage',
      );
      await harness.runImport('legacy sample', adminSession);

      final page = await harness.capture(
        'recipes_page',
        'GET',
        '/api/v1/recipes',
        headers: harness.auth(adminSession),
      );
      final card =
          (page['items']! as List<dynamic>).single as Map<String, dynamic>;
      final slug = card['slug']! as String;

      // Personal data, so `favorite`/`note` are pinned as populated values
      // rather than as nulls the app would parse either way.
      await harness.expectOk(
        'PUT',
        '/api/v1/recipes/$slug/favorite',
        headers: harness.auth(adminSession, csrf: true),
      );
      await harness.expectOk(
        'PUT',
        '/api/v1/recipes/$slug/note',
        headers: harness.auth(adminSession, csrf: true),
        jsonBody: {'note': _note},
      );
      // A word from the recipe's own real ingredient list, so the ranked FTS
      // path renders this body rather than the plain listing path. Captured
      // AFTER the favorite so the two card goldens differ where it matters:
      // recipes_page carries `favorite: false`, this one `true`.
      await harness.capture(
        'recipes_search',
        'GET',
        '/api/v1/recipes?q=asparagus',
        headers: harness.auth(adminSession),
      );
      await harness.capture(
        'recipe_detail',
        'GET',
        '/api/v1/recipes/$slug',
        headers: harness.auth(adminSession),
      );

      // A recipe whose nutrition was never computed: every line comes back
      // `"match": null`, which is the app's unmatched-line parse branch.
      await harness.capture(
        'nutrition_matches_uncomputed',
        'GET',
        '/api/v1/recipes/$slug/nutrition/matches',
        headers: harness.auth(adminSession),
      );

      // --- tags: before and after a chip style ---------------------------
      final unstyled = await harness.capture(
        'tags_unstyled',
        'GET',
        '/api/v1/tags',
        headers: harness.auth(adminSession),
      );
      final tag =
          ((unstyled['items']! as List<dynamic>).first
                  as Map<String, dynamic>)['name']!
              as String;
      await harness.expectOk(
        'PUT',
        '/api/v1/tags/${Uri.encodeComponent(tag)}/style',
        headers: harness.auth(adminSession, csrf: true),
        jsonBody: {
          'icon': 'utensils-crossed',
          'color': '#960000',
          'bg_color': '#F6E7E7',
        },
      );
      await harness.capture(
        'tags_styled',
        'GET',
        '/api/v1/tags',
        headers: harness.auth(adminSession),
      );

      await harness.captureMustChangeAccount(adminSession);
    });

    tearDownAll(harness.stop);

    _goldenComparisons(harness, corpusFreeContractGoldenNames);

    test('the must-change-password flag survives the wire as true', () {
      // The review's motivating regression: the app defaults this to
      // false, so a server-side rename would silently stop forcing the
      // change. Asserted on the captured body, not just the file.
      for (final name in ['auth_me_must_change', 'auth_login_must_change']) {
        final user =
            (harness.captured[name]! as Map<String, Object?>)['user']!
                as Map<String, Object?>;
        expect(
          user['must_change_password'],
          isTrue,
          reason: '$name must carry must_change_password: true',
        );
      }
      final admin =
          (harness.captured['auth_me_admin']! as Map<String, Object?>)['user']!
              as Map<String, Object?>;
      expect(admin['must_change_password'], isFalse);
    });
  });

  // ------------------------------------------------------------------
  // Needs the real corpus: a v1 source root with hero images and a
  // source.yaml, a reconciliation scan over it, and a nutrition compute
  // whose FDC responses were recorded against those exact lines.
  // ------------------------------------------------------------------
  group(
    'corpus-backed bodies match the committed goldens',
    skip: skipIfNoCorpus,
    () {
      final harness = _Harness('salt_contract_corpus_');

      setUpAll(() async {
        await harness.start();
        await harness.seedAdmin();
        final adminSession = await harness.login('admin', _adminPassword);

        // --- import: a real v1 source root inside the allowlist ------------
        final sourceRoot = Directory('${harness.config.importDir}/atk sample')
          ..createSync(recursive: true);
        Directory('${sourceRoot.path}/recipes').createSync();
        Directory('${sourceRoot.path}/images').createSync();
        File(
          '$corpusRoot/source.yaml',
        ).copySync('${sourceRoot.path}/source.yaml');
        for (final name in [_bundtFile, _pancakesFile]) {
          File(
            '$corpusRecipesDir/$name',
          ).copySync('${sourceRoot.path}/recipes/$name');
          final hero = '${name.substring(0, name.length - 5)}-hero.jpg';
          File('$corpusImagesDir/$hero').copySync(
            '${sourceRoot.path}/images/$hero',
          );
        }
        File(
          '${sourceRoot.path}/recipes/$_malformedName',
        ).writeAsStringSync(_malformedYaml);

        await harness.capture(
          'import_candidates',
          'GET',
          '/api/v1/import/candidates',
          headers: harness.auth(adminSession),
        );
        final importJobId = await harness.runImport('atk sample', adminSession);
        // The finished job row — the body the app's ImportJob model polls.
        await harness.capture(
          'import_job',
          'GET',
          '/api/v1/import/jobs/$importJobId',
          headers: harness.auth(adminSession),
        );

        // --- nutrition: a real compute over recorded real FDC responses ----
        final (computeStatus, computeBody) = await harness.send(
          'POST',
          '/api/v1/recipes/$_bundtSlug/nutrition/compute',
          headers: harness.auth(adminSession, csrf: true),
        );
        expect(computeStatus, HttpStatus.accepted, reason: computeBody);
        final computeJobId =
            (jsonDecode(computeBody) as Map<String, dynamic>)['job_id'];
        await harness.awaitJob(
          '/api/v1/nutrition/jobs/$computeJobId',
          harness.auth(adminSession),
        );
        await harness.capture(
          'nutrition',
          'GET',
          '/api/v1/recipes/$_bundtSlug/nutrition',
          headers: harness.auth(adminSession),
        );
        await harness.capture(
          'nutrition_matches',
          'GET',
          '/api/v1/recipes/$_bundtSlug/nutrition/matches',
          headers: harness.auth(adminSession),
        );
        // The cross-recipe triage queue built from that same compute — the
        // app's largest admin parse (buckets, rows, per-row recipe identity).
        await harness.capture(
          'nutrition_review',
          'GET',
          '/api/v1/admin/nutrition_review',
          headers: harness.auth(adminSession),
        );

        // --- library: every branch of a reconciliation scan -----------------
        // All real data: the pancakes' ORIGINAL corpus text stands in for a
        // hand edit (same recipe, non-canonical formatting -> the file wins),
        // and a third corpus recipe appears as a brand-new file.
        final librarySource = Directory(
          harness.config.libraryDir,
        ).listSync().whereType<Directory>().single;
        final libraryRecipes = '${librarySource.path}/recipes';
        final bundtId = loadCorpusRecipe(_bundtFile).id;
        final pancakesId = loadCorpusRecipe(_pancakesFile).id;
        final soupId = loadCorpusRecipe(_soupFile).id;
        // A conflict copy left behind by an earlier save, then the export
        // itself removed: the scan must list one and re-materialize the other.
        File('$libraryRecipes/$bundtId.yaml').renameSync(
          '$libraryRecipes/$bundtId$_conflictSuffix',
        );
        File('$corpusRecipesDir/$_pancakesFile').copySync(
          '$libraryRecipes/$pancakesId.yaml',
        );
        File('$corpusRecipesDir/$_soupFile').copySync(
          '$libraryRecipes/$soupId.yaml',
        );
        File('$libraryRecipes/$_malformedName').writeAsStringSync(
          _malformedYaml,
        );
        await harness.expectOk(
          'POST',
          '/api/v1/library/rescan',
          headers: harness.auth(adminSession, csrf: true),
        );
        await harness.capture(
          'library_last_scan',
          'GET',
          '/api/v1/library',
          headers: harness.auth(adminSession),
        );
      });

      tearDownAll(harness.stop);

      _goldenComparisons(harness, corpusBackedContractGoldenNames);
    },
  );
}

/// The per-golden comparisons: every declared [names] entry was captured
/// from a live route this run, carries nothing machine-specific, and matches
/// the committed file byte for byte.
void _goldenComparisons(_Harness harness, List<String> names) {
  test('every golden was captured from a live route', () {
    expect(harness.captured.keys.toSet(), names.toSet());
  });

  test("no captured body leaks this run's temp directory", () {
    for (final entry in harness.captured.entries) {
      expect(
        encodeContractGolden(entry.value),
        isNot(contains(harness.tempDir.path)),
        reason:
            '${entry.key} embeds the temp data dir — add its key to '
            'contractVolatileFields',
      );
    }
  });

  for (final name in names) {
    test('$name.json', () {
      final rendered = encodeContractGolden(harness.captured[name]);
      final file = contractGoldenFile(name);
      if (updateContractGoldens) {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(rendered);
      }
      expect(
        file.existsSync(),
        isTrue,
        reason: 'missing golden ${file.path}',
      );
      // Rendered body is the ACTUAL; the committed golden is the EXPECTED,
      // so a regression diff reads the way it happened.
      expect(
        rendered,
        file.readAsStringSync(),
        reason:
            'The $name response shape changed. If that was deliberate, '
            'regenerate with UPDATE_CONTRACT_GOLDENS=1 and check '
            'apps/app parses the new shape.',
      );
    });
  }
}

/// A live server over the real dart_frog route files and the REAL production
/// middleware chain (`buildAppMiddleware`, the same function
/// `routes/_middleware.dart` calls), plus the capture bookkeeping.
class _Harness {
  _Harness(this._tempPrefix);

  final String _tempPrefix;

  late final Directory tempDir;
  late final ServerConfig config;
  late final SaltDatabase db;
  late final AuthRuntime runtime;
  late final FixtureProvider fdc;
  late final HttpServer _server;
  late final Uri _baseUri;

  /// Golden name -> the redacted body captured from the live route.
  final Map<String, Object?> captured = <String, Object?>{};

  Future<void> start() async {
    tempDir = Directory.systemTemp.createTempSync(_tempPrefix);
    config = ServerConfig.fromEnvironment(
      environment: {
        'DATA_DIR': tempDir.path,
        'IMPORT_DIR': '${tempDir.path}/import',
        'LOG_LEVEL': 'ERROR',
      },
    );
    configureLogging(config);
    Directory(config.libraryDir).createSync(recursive: true);
    Directory(config.importDir).createSync(recursive: true);
    db = SaltDatabase.open(config.dbPath);
    runtime = AuthRuntime();
    fdc = FixtureProvider();

    final pipeline = buildAppMiddleware(
      _dispatch,
      config: config,
      database: db,
      authRuntime: runtime,
      nutritionProvider: fdc,
      // maxRequests: 0 disables the search limiter, so the `?q=` capture
      // cannot turn into a 429 that would pin the wrong body.
      searchRateLimiter: RequestRateLimiter(maxRequests: 0),
      searchService: () => InlineSearchService(db),
      logStore: LogStore(directory: config.logDir),
    );
    _server = await serve(pipeline, InternetAddress.loopbackIPv4, 0);
    _baseUri = Uri.parse('http://127.0.0.1:${_server.port}');
  }

  Future<void> stop() async {
    await _server.close(force: true);
    db.dispose();
    tempDir.deleteSync(recursive: true);
  }

  Map<String, String> auth(String token, {bool csrf = false}) => {
    'Authorization': 'Bearer $token',
    if (csrf) ..._csrf,
  };

  Future<(int, String)> send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    Object? jsonBody,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, _baseUri.resolve(path));
      headers.forEach(request.headers.set);
      if (jsonBody != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(jsonBody));
      }
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      return (response.statusCode, body);
    } finally {
      client.close();
    }
  }

  /// Sends a request whose body is not a golden and asserts it succeeded.
  Future<void> expectOk(
    String method,
    String path, {
    Map<String, String> headers = const {},
    Object? jsonBody,
  }) async {
    final (status, body) = await send(
      method,
      path,
      headers: headers,
      jsonBody: jsonBody,
    );
    expect(status, HttpStatus.ok, reason: '$method $path -> $body');
  }

  /// Sends the request, asserts it succeeded, and records the response body
  /// under [golden] with volatile values redacted.
  Future<Map<String, dynamic>> capture(
    String golden,
    String method,
    String path, {
    Map<String, String> headers = const {},
    Object? jsonBody,
  }) async {
    final (status, body) = await send(
      method,
      path,
      headers: headers,
      jsonBody: jsonBody,
    );
    expect(status, HttpStatus.ok, reason: '$method $path -> $body');
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    captured[golden] = redactContractVolatiles(decoded);
    return decoded;
  }

  Future<String> login(String username, String password) async {
    final (status, body) = await send(
      'POST',
      '/api/v1/auth/login',
      jsonBody: {'username': username, 'password': password},
    );
    expect(status, HttpStatus.ok, reason: body);
    return (jsonDecode(body) as Map<String, dynamic>)['token']! as String;
  }

  /// Creates the admin account every capture signs in as.
  Future<void> seedAdmin() async {
    db.createUser(
      username: 'admin',
      passwordHash: await runtime.hasher.hash(_adminPassword),
      role: 'admin',
    );
  }

  /// Seeds the admin, captures the two admin auth bodies, and returns a
  /// session token for it.
  Future<String> seedAdminAndCaptureAuth() async {
    await seedAdmin();
    await capture(
      'auth_login_admin',
      'POST',
      '/api/v1/auth/login',
      jsonBody: {
        'username': 'admin',
        'password': _adminPassword,
        'remember': true,
      },
    );
    final session = await login('admin', _adminPassword);
    await capture(
      'auth_me_admin',
      'GET',
      '/api/v1/auth/me',
      headers: auth(session),
    );
    return session;
  }

  /// Creates a member through the real endpoint and captures the three
  /// bodies of a forced-password-change sign-in.
  Future<void> captureMustChangeAccount(String adminSession) async {
    final (status, body) = await send(
      'POST',
      '/api/v1/users',
      headers: auth(adminSession, csrf: true),
      jsonBody: {'username': _tempUsername, 'role': 'member'},
    );
    expect(status, HttpStatus.ok, reason: body);
    // Not a golden: the body holds a one-time temp password.
    final tempPassword =
        (jsonDecode(body) as Map<String, dynamic>)['temp_password']! as String;
    await capture(
      'auth_login_must_change',
      'POST',
      '/api/v1/auth/login',
      jsonBody: {'username': _tempUsername, 'password': tempPassword},
    );
    final session = await login(_tempUsername, tempPassword);
    await capture(
      'auth_me_must_change',
      'GET',
      '/api/v1/auth/me',
      headers: auth(session),
    );
    await capture(
      'auth_change_password',
      'POST',
      '/api/v1/auth/change_password',
      headers: auth(session, csrf: true),
      jsonBody: {'new_password': _newPassword},
    );
  }

  /// Starts an import of [relativePath] and waits for it to finish,
  /// returning the job id.
  Future<int> runImport(String relativePath, String adminSession) async {
    final (status, body) = await send(
      'POST',
      '/api/v1/import',
      headers: auth(adminSession, csrf: true),
      jsonBody: {'path': relativePath},
    );
    expect(status, HttpStatus.accepted, reason: body);
    final jobId = ((jsonDecode(body) as Map<String, dynamic>)['job_id']! as num)
        .toInt();
    await awaitJob('/api/v1/import/jobs/$jobId', auth(adminSession));
    return jobId;
  }

  /// Polls [path] until its `status` leaves `running`.
  Future<void> awaitJob(String path, Map<String, String> headers) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      final (status, body) = await send('GET', path, headers: headers);
      expect(status, HttpStatus.ok, reason: body);
      final job = jsonDecode(body) as Map<String, dynamic>;
      if (job['status'] != 'running') {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('job at $path never left "running"');
  }
}

/// Routes the request to the same `onRequest` the dart_frog build would.
FutureOr<Response> _dispatch(RequestContext context) {
  final path = context.request.uri.path;
  switch (path) {
    case '/api/v1/auth/login':
      return login_route.onRequest(context);
    case '/api/v1/auth/me':
      return me_route.onRequest(context);
    case '/api/v1/auth/change_password':
      return change_password_route.onRequest(context);
    case '/api/v1/users':
      return users_route.onRequest(context);
    case '/api/v1/tags':
      return tags_route.onRequest(context);
    case '/api/v1/recipes':
      return recipes_route.onRequest(context);
    case '/api/v1/admin/nutrition_review':
      return review_route.onRequest(context);
    case '/api/v1/library':
      return library_route.onRequest(context);
    case '/api/v1/library/rescan':
      return rescan_route.onRequest(context);
    case '/api/v1/import':
      return import_route.onRequest(context);
    case '/api/v1/import/candidates':
      return candidates_route.onRequest(context);
  }
  for (final (pattern, handler)
      in <(RegExp, FutureOr<Response> Function(RequestContext, String))>[
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
        (
          RegExp(r'^/api/v1/recipes/([^/]+)/favorite$'),
          favorite_route.onRequest,
        ),
        (RegExp(r'^/api/v1/recipes/([^/]+)/note$'), note_route.onRequest),
        (RegExp(r'^/api/v1/recipes/([^/]+)$'), recipe_route.onRequest),
        (RegExp(r'^/api/v1/tags/([^/]+)/style$'), tag_style_route.onRequest),
        (RegExp(r'^/api/v1/import/jobs/([^/]+)$'), import_job_route.onRequest),
        (
          RegExp(r'^/api/v1/nutrition/jobs/([^/]+)$'),
          nutrition_job_route.onRequest,
        ),
      ]) {
    final match = pattern.firstMatch(path);
    if (match != null) {
      return handler(context, match.group(1)!);
    }
  }
  return Response(statusCode: HttpStatus.notFound, body: 'no route');
}
