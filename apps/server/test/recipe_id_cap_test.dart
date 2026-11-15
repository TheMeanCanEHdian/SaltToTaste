// v111 Y5 (Sonnet S12, measured worse by the union: unionY/b B3): a recipe id
// had no length cap — the editor mints `manual-<yyyymmdd>-<slugify(title)>`
// from a title of up to 250 characters (`½` folds to three), the id is a FILE
// name, and `_store` upserted the row BEFORE the export opened
// `<id>.yaml.tmp` over NAME_MAX: a 500, the row KEPT, and every later
// reconciliation scan THREW at it (report never persisted, later rows never
// self-healed, `POST /library/rescan` a 500). v111: (1) the slug is cut to
// [maxMintedSlugLength] at the mint; (2) a failed export leaves the database
// as it was; (3) the scan's self-heal counts a failed export and goes on.
// Corpus-free: STATED synthesized negative-path inputs (as p5_edit_http's
// corpus-free probes): title-only recipes with over-long titles, a read-only
// library directory (a real I/O failure), and a row planted with an id no
// v111 path can mint (a database written before v111).
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart' hide requestLogger;
import 'package:logging/logging.dart';
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/auth/tokens.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/middleware/request_logger.dart';
import 'package:salt_server/src/search/search_service.dart';
import 'package:salt_server/src/services/library_scan.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import '../routes/api/v1/library/rescan.dart' as rescan_route;
import '../routes/api/v1/recipes/[id]/index.dart' as recipe_route;
import '../routes/api/v1/recipes/index.dart' as recipes_route;

void main() {
  late Directory tmp;
  late ServerConfig config;
  late SaltDatabase db;
  late HttpServer server;
  late String token;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('salt_recipe_id_cap_');
    config = ServerConfig.fromEnvironment(
      environment: {'DATA_DIR': tmp.path, 'LOG_LEVEL': 'ERROR'},
    );
    db = SaltDatabase.open(config.dbPath);
    Future<Response> inner(RequestContext c) async {
      final p = c.request.uri.path;
      if (p == '/api/v1/recipes') return recipes_route.onRequest(c);
      if (p == '/api/v1/library/rescan') return rescan_route.onRequest(c);
      if (p.startsWith('/api/v1/recipes/')) {
        return recipe_route.onRequest(
          c,
          p.substring('/api/v1/recipes/'.length),
        );
      }
      return Response(statusCode: HttpStatus.notFound);
    }

    final pipeline = inner
        .use(authProvider())
        .use(
          provider<RequestRateLimiter>(
            (_) => RequestRateLimiter(maxRequests: 0),
          ),
        )
        .use(provider<AuthRuntime>((_) => AuthRuntime()))
        .use(provider<SaltDatabase>((_) => db))
        .use(provider<SearchService>((_) => InlineSearchService(db)))
        .use(provider<ServerConfig>((_) => config))
        .use(errorHandler(throttle: SevereThrottle()))
        .use(requestLogger())
        .use(requestIdProvider());
    server = await serve(pipeline, InternetAddress.loopbackIPv4, 0);
    final adminId = db.createUser(
      username: 'admin',
      passwordHash: 'x',
      role: 'admin',
    );
    final pat = generatePat();
    db.createApiToken(
      userId: adminId,
      name: 'p',
      prefix: pat.prefix,
      tokenHash: hashToken(pat.token),
      scope: 'full',
    );
    token = pat.token;
  });

  tearDownAll(() async {
    await server.close(force: true);
    db.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<(int, Map<String, dynamic>)> send(
    String method,
    String path, [
    Object? body,
  ]) async {
    final client = HttpClient();
    try {
      final rq = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${server.port}$path'),
      );
      rq.headers.set('authorization', 'Bearer $token');
      if (body != null) {
        rq.headers.contentType = ContentType.json;
        rq.write(jsonEncode(body));
      }
      final rs = await rq.close();
      final text = await utf8.decoder.bind(rs).join();
      return (rs.statusCode, jsonDecode(text) as Map<String, dynamic>);
    } finally {
      client.close();
    }
  }

  String idOf(Map<String, dynamic> body) =>
      (body['recipe'] as Map<String, dynamic>)['id'] as String;
  File exportOf(String id) =>
      File('${config.libraryDir}/$manualSourceSlug/recipes/$id.yaml');

  test('Y5 (1): a 250-character title (ASCII, and `½` folding to three) '
      'mints an id whose every derived name fits; the export exists; a '
      'colliding cut is `-2`; a rescan answers 200 and persists', () async {
    final (ascii, asciiBody) = await send('POST', '/api/v1/recipes', {
      'recipe': {'title': 'a' * 250},
    });
    // Base: 500 `internal` (a 266-character id) and the row kept.
    expect(ascii, HttpStatus.created, reason: '$asciiBody');
    final id = idOf(asciiBody);
    // `manual-YYYYMMDD-` (16) + the slug cut to exactly 190.
    expect(id.length, 16 + 190);
    expect(id.substring(16), 'a' * 190);
    // The slug is the SAME cut (owner gate: `availableSlug` reading the
    // uncut slug survived every other pin).
    expect((asciiBody['recipe'] as Map<String, dynamic>)['slug'], 'a' * 190);
    expect(exportOf(id).existsSync(), isTrue);

    final (half, halfBody) = await send('POST', '/api/v1/recipes', {
      'recipe': {'title': '½' * 250},
    });
    // Base: 500 (a 766-character id).
    expect(half, HttpStatus.created, reason: '$halfBody');
    final halfId = idOf(halfBody);
    expect(halfId.length, lessThanOrEqualTo(16 + 190));
    expect(halfId.endsWith('-'), isFalse);
    expect(exportOf(halfId).existsSync(), isTrue);

    // The trailing-dash trim (closer1 D1: the `½` title's cut ends in '1', so
    // the check above cannot see it): 'a'×189 + ' ' + 'b'×60 slugs to
    // 'a'×189 + '-' + 'b'×60, whose 190-character cut ends in '-'.
    final (dash, dashBody) = await send('POST', '/api/v1/recipes', {
      'recipe': {'title': '${'a' * 189} ${'b' * 60}'},
    });
    expect(dash, HttpStatus.created, reason: '$dashBody');
    final dashId = idOf(dashBody);
    expect(dashId.length, 16 + 189);
    expect(dashId.substring(16), 'a' * 189);
    expect(exportOf(dashId).existsSync(), isTrue);

    // A title that differs only past the cut collides: the uniquing suffix.
    final (twin, twinBody) = await send('POST', '/api/v1/recipes', {
      'recipe': {'title': '${'a' * 200}b'},
    });
    expect(twin, HttpStatus.created, reason: '$twinBody');
    expect(idOf(twinBody), '$id-2');
    expect(idOf(twinBody).length, lessThanOrEqualTo(209));

    final (rescan, rescanBody) = await send('POST', '/api/v1/library/rescan');
    expect(rescan, HttpStatus.ok, reason: '$rescanBody');
    expect(lastScanReport(db), isNotNull);
    expect(
      (rescanBody['last_scan'] as Map).containsKey('export_failed'),
      isFalse,
    );
  });

  test('Y5 (2): an export that throws (a read-only library directory) '
      'leaves the database as it was — a create stores no row and reserves '
      'no slug; an update keeps the old row', () async {
    final (made, madeBody) = await send('POST', '/api/v1/recipes', {
      'recipe': {'title': 'Read Only Probe'},
    });
    expect(made, HttpStatus.created, reason: '$madeBody');
    final id = idOf(madeBody);
    final before = db.contentHashOf(id);
    final dir = Directory('${config.libraryDir}/$manualSourceSlug/recipes');
    Process.runSync('chmod', ['555', dir.path]);
    addTearDown(() => Process.runSync('chmod', ['755', dir.path]));

    final (create, _) = await send('POST', '/api/v1/recipes', {
      'recipe': {'title': 'Never Stored Probe'},
    });
    expect(create, HttpStatus.internalServerError);
    // Base: the row stayed (and its slug with it).
    expect(
      db.listRecipeHashes().where((r) => r.id.contains('never-stored-probe')),
      isEmpty,
    );
    expect(
      db.availableSlug('never-stored-probe', ownerId: 'x'),
      'never-stored-probe',
    );

    final (update, _) = await send('PUT', '/api/v1/recipes/$id', {
      'recipe': {'title': 'Renamed Probe'},
    });
    expect(update, HttpStatus.internalServerError);
    // Base: the new title stored with no export.
    expect(db.contentHashOf(id), before);
    expect(db.recipeByIdOrSlug(id)!.recipe.title, 'Read Only Probe');
  });

  test('Y5 (2): a FIRST create whose export throws leaves no source row '
      'either (owner gate: the create without its outer transaction '
      'survived — the `my-recipes` row stayed)', () {
    final dir = Directory.systemTemp.createTempSync('salt_recipe_id_first_');
    final fresh = ServerConfig.fromEnvironment(
      environment: {'DATA_DIR': dir.path, 'LOG_LEVEL': 'ERROR'},
    );
    final freshDb = SaltDatabase.open(fresh.dbPath);
    final library = Directory(fresh.libraryDir)..createSync(recursive: true);
    Process.runSync('chmod', ['555', library.path]);
    addTearDown(() {
      Process.runSync('chmod', ['755', library.path]);
      freshDb.dispose();
      dir.deleteSync(recursive: true);
    });
    expect(
      () => createRecipe(freshDb, fresh, {'title': 'First Probe'}),
      throwsA(isA<FileSystemException>()),
    );
    expect(freshDb.sourceExists(manualSourceSlug), isFalse);
    expect(freshDb.recipeCount(), 0);
  });

  test('Y5 (3): a row whose export cannot be written is counted and the '
      'self-heal goes on — later rows re-exported, the report persisted, '
      'the rescan 200, ONE SEVERE naming the row', () async {
    final severe = <LogRecord>[];
    final sub = Logger.root.onRecord
        .where((r) => r.level >= Level.SEVERE)
        .listen(severe.add);
    addTearDown(sub.cancel);
    // A row no v111 path can mint (a database written before v111): its
    // `.yaml.tmp` is over NAME_MAX. Sorted BEFORE every `manual-` row.
    final long = 'a-${'b' * 260}';
    final planted = RecipeYamlCodec.decode(
      'schema_version: 2\nid: $long\ntitle: Planted\nslug: planted\n'
      'source:\n  name: My Recipes\n  type: manual\n',
    ).recipe;
    db.upsertRecipe(planted, sourceSlug: manualSourceSlug, contentHash: 'x');
    final (made, madeBody) = await send('POST', '/api/v1/recipes', {
      'recipe': {'title': 'Self Heal Probe'},
    });
    expect(made, HttpStatus.created, reason: '$madeBody');
    final later = idOf(madeBody);
    exportOf(later).deleteSync();
    db.deleteSetting(lastScanSettingKey);

    final (rescan, rescanBody) = await send('POST', '/api/v1/library/rescan');
    // Base: 500 — the scan threw at the planted row.
    expect(rescan, HttpStatus.ok, reason: '$rescanBody');
    final report = rescanBody['last_scan'] as Map<String, dynamic>;
    expect(report['export_failed'], 1);
    expect(report['re_exported'], [later]);
    expect(exportOf(later).existsSync(), isTrue);
    expect(lastScanReport(db)?['export_failed'], 1);
    // ONE SEVERE per scan (owner gate: the scan without it survived), a
    // plain Logger record — not through the HTTP catch-alls' throttle.
    expect(
      [for (final r in severe) (r.loggerName, r.message)],
      [
        (
          'library',
          'Library scan: 1 missing export(s) could not be written: $long',
        ),
      ],
    );
    expect(severe.single.error, isA<FileSystemException>());
  });
  test('Y5 (4): an id over maxRecipeIdLength (218) is unsafe — the scan '
      "skips a library file named by one (base: stored, then the scan's "
      're-export threw on every scan); 218 passes', () {
    expect(isSafeRecipeId('a' * maxRecipeIdLength), isTrue);
    expect(isSafeRecipeId('a' * (maxRecipeIdLength + 1)), isFalse);
    final long = 'b${'c' * 246}';
    final dir = Directory('${config.libraryDir}/zz-long/recipes')
      ..createSync(recursive: true);
    File('${dir.path}/$long.yaml').writeAsStringSync(
      'schema_version: 2\nid: $long\ntitle: Long Id\nslug: long-id\n'
      'source:\n  name: Long\n  type: manual\n',
    );
    final report = scanLibrary(db: db, config: config);
    expect(db.recipeExists(long), isFalse);
    expect(
      [for (final s in report.skipped) s.reason],
      contains('unsafe file name'),
    );
    dir.parent.deleteSync(recursive: true);
  });
}
