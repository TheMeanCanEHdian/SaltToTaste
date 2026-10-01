// Run 050 P3/P4: a person's write addresses the STORED recipe:
// applyMatchOverride lays the rows out against the stored recipe (never the
// caller's copy — so the route's order of reading the body and the recipe
// does not matter; Run 051 C2 deleted the test that claimed it did) and
// reads it again after its own awaits, the response reloads it after the write,
// and an optional `raw` (the line text the client saw) refuses a write
// whose line moved: 409 line_moved, nothing written. Real data: 0405
// Acquacotta's own lines; the saves (reorders, inserts) and their
// interleavings are synthesized, a stated exception.
// Answers: FixtureProvider, never the network.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart' as frog;
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import '../routes/api/v1/recipes/[id]/nutrition/matches/[pos].dart'
    as match_route;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _oilHalf = '½ cup extra-virgin olive oil';
const _sp = 'Salt and pepper';
const _onion = '1 large onion, chopped coarse';
const _celery = '2 celery ribs, chopped coarse';

void main() {
  late SaltDatabase db;
  late _Hooked provider;
  late Recipe acqua;
  late Map<String, IngredientLine> byRaw;
  setUp(() {
    final dir = Directory.systemTemp.createTempSync('salt-line-moved');
    addTearDown(() => dir.deleteSync(recursive: true));
    db = SaltDatabase.open('${dir.path}/salt.db')
      ..upsertSource(slug: 'src', name: 'Test', type: 'book');
    addTearDown(db.dispose);
    provider = _Hooked(FixtureProvider(pending: pendingSearches));
    acqua = loadCorpusRecipe(
      '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml',
    );
    byRaw = {
      for (final g in acqua.ingredients)
        for (final l in g.items) l.raw: l,
    };
  });
  Recipe version(List<String> raws) => acqua.copyWith(
    ingredients: [
      IngredientGroup(
        group: acqua.ingredients.first.group,
        items: [for (final r in raws) byRaw[r]!],
      ),
    ],
  );
  void save(Recipe r) =>
      db.upsertRecipe(r, sourceSlug: 'src', contentHash: contentHashOf(r));
  Map<String, String> statusByRaw() => {
    for (final r in db.ingredientMatchesFor(acqua.id)) r.raw: r.status,
  };

  /// PUTs [body] to line [pos] through the real route and error handler,
  /// as a signed-in admin; the status and the decoded body.
  Future<(int, Map<String, dynamic>)> put(
    int pos,
    Map<String, Object?> body,
  ) async {
    final adminId =
        db.userByUsername('admin')?.id ??
        db.createUser(username: 'admin', passwordHash: 'unused', role: 'admin');
    Future<frog.Response> handler(frog.RequestContext context) =>
        match_route.onRequest(context, acqua.id, '$pos');
    final pipeline = handler
        .use(
          frog.provider<AuthUser?>(
            (_) => AuthUser(
              id: adminId,
              username: 'admin',
              role: 'admin',
              mustChangePassword: false,
              scope: 'full',
              via: 'session',
            ),
          ),
        )
        .use(frog.provider<NutritionProvider>((_) => provider))
        .use(frog.provider<SaltDatabase>((_) => db))
        .use(errorHandler())
        .use(requestIdProvider());
    final server = await frog.serve(pipeline, InternetAddress.loopbackIPv4, 0);
    final client = HttpClient();
    try {
      final request = await client.open('PUT', '127.0.0.1', server.port, '/');
      final bytes = utf8.encode(jsonEncode(body));
      request.headers
        ..contentType = ContentType.json
        ..contentLength = bytes.length
        ..set('X-Requested-With', csrfHeaderValue);
      request.add(bytes);
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      return (response.statusCode, jsonDecode(text) as Map<String, dynamic>);
    } finally {
      client.close();
      await server.close(force: true);
    }
  }

  test('P3: applyMatchOverride handed a copy read BEFORE a save lays the '
      "rows out on the stored lines: the new first line's skip stands, and "
      'the write lands on the stored line at its position', () async {
    final v0 = version([_onion, _celery]);
    save(v0);
    await matchAndCompute(db, provider, v0);
    final readEarlier = db.recipeByIdOrSlug(v0.id)!.recipe;
    final v1 = version([_oilHalf, _onion, _celery]);
    save(v1);
    await matchAndCompute(db, provider, v1);
    await applyMatchOverride(db, provider, v1, 0, {'skipped': true});
    await applyMatchOverride(db, provider, readEarlier, 1, {'skipped': true});
    expect(statusByRaw(), {
      _oilHalf: 'skipped',
      _onion: 'skipped',
      _celery: isNot('skipped'),
    });
  }, skip: skipIfNoCorpus);

  test("P3: a save during the write's own await (fetching the picked food) "
      'that moves the line: 409 line_moved naming where it is now, nothing '
      'written', () async {
    final v0 = version([_onion, _celery]);
    save(v0);
    provider.onCall = () => save(version([_oilHalf, _onion, _celery]));
    await expectLater(
      applyMatchOverride(db, provider, v0, 1, {'fdc_id': 173468, 'grams': 5}),
      throwsA(
        isA<LineMovedException>().having((e) => e.position, 'position', 2),
      ),
    );
    expect(db.ingredientMatchesFor(acqua.id), isEmpty);
  }, skip: skipIfNoCorpus);

  test("P3: a save during the write's own await that leaves the line where "
      'it was: the write lands, and the response lists the lines as saved '
      'since, reloaded after the write', () async {
    final v0 = version([_onion, _celery]);
    save(v0);
    provider.onCall = () => save(version([_onion, _celery, _oilHalf]));
    final (code, json) = await put(0, {
      'fdc_id': 173468,
      'grams': 5,
      'raw': _onion,
    });
    expect(code, HttpStatus.ok, reason: '$json');
    expect(
      [
        for (final item in json['items'] as List<dynamic>)
          (item as Map<String, dynamic>)['raw'],
      ],
      [_onion, _celery, _oilHalf],
    );
    expect(statusByRaw()[_onion], 'overridden');
  }, skip: skipIfNoCorpus);

  group('P4: `raw`, the line text the client saw', () {
    setUp(() async {
      final v0 = version([_oilHalf, _sp]);
      save(v0);
      await matchAndCompute(db, provider, v0);
    });

    test("a queue row's stored position after a save reorders the lines: "
        '409 line_moved with the position the line moved to, nothing '
        'written; the retry at that position lands on it', () async {
      save(version([_sp, _oilHalf]));
      final (code, json) = await put(0, {'skipped': true, 'raw': _oilHalf});
      expect(code, HttpStatus.conflict, reason: '$json');
      final error = json['error'] as Map<String, dynamic>;
      expect(error['code'], 'line_moved');
      expect(error['position'], 1);
      expect(statusByRaw().values, isNot(contains('skipped')));
      final (retry, body) = await put(1, {'skipped': true, 'raw': _oilHalf});
      expect(retry, HttpStatus.ok, reason: '$body');
      expect(statusByRaw(), {_oilHalf: 'skipped', _sp: isNot('skipped')});
    }, skip: skipIfNoCorpus);

    test('a line deleted since: 409 with position null (not a 404); a raw '
        'that is not a string: 422', () async {
      save(version([_sp]));
      final (code, json) = await put(1, {'skipped': true, 'raw': _oilHalf});
      expect(code, HttpStatus.conflict, reason: '$json');
      final error = json['error'] as Map<String, dynamic>;
      expect(error, containsPair('position', null));
      final (bad, _) = await put(0, {'skipped': true, 'raw': 3});
      expect(bad, HttpStatus.unprocessableEntity);
    }, skip: skipIfNoCorpus);

    test(
      'the raw the line still reads: the write lands as before',
      () async {
        final (code, json) = await put(1, {'skipped': true, 'raw': _sp});
        expect(code, HttpStatus.ok, reason: '$json');
        expect(statusByRaw()[_sp], 'skipped');
      },
      skip: skipIfNoCorpus,
    );
  });
}

/// [FixtureProvider] running [onCall] once, at its next call (an await).
class _Hooked implements NutritionProvider {
  _Hooked(this.inner);
  final FixtureProvider inner;
  void Function()? onCall;

  void _fire() {
    final hook = onCall;
    onCall = null;
    hook?.call();
  }

  @override
  Future<List<FdcCandidate>> search(String query) async {
    _fire();
    return inner.search(query);
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    _fire();
    return inner.food(fdcId);
  }
}
