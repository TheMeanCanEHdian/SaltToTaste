import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/features/recipes/detail/recipe_detail_cubit.dart';

import 'support/contract_goldens.dart';
import 'support/corpus.dart';

/// The recipe detail page's cubit, driven through the REAL [RecipeRepository]
/// over a canned Dio adapter.
///
/// The recipe document is the COMMITTED contract golden — the real
/// `GET /api/v1/recipes/<slug>` body captured from the real server route
/// (`packages/salt_shared/test/fixtures/contract/recipe_detail.json`) for the
/// real recipe committed at `apps/server/test/fixtures/legacy-v0/`. That is
/// real data with no live corpus directory behind it, so every favorite and
/// note failure path — including the swallowed-failure defect this suite
/// exists to prevent — runs in CI, where there is no ATK corpus.
///
/// Only the ONE claim that needs a document richer than the golden (nested
/// subsections plus a technique) is corpus-gated.
class _FakeAdapter implements HttpClientAdapter {
  /// Body served by `GET /api/v1/recipes/<id>`; null makes it a 404.
  Map<String, Object?>? detail;

  /// Path suffixes whose requests fail with a 500 envelope.
  final Set<String> failing = {};

  /// When true every request fails as a transport error.
  bool offline = false;

  /// Every `(method, path)` requested, in order.
  final List<(String, String)> calls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    calls.add((options.method, path));
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no server in this test',
      );
    }
    if (failing.any(path.endsWith)) {
      return _envelope(500, 'internal', 'the server fell over');
    }
    if (path.endsWith('/favorite')) {
      return ResponseBody.fromString('{}', 200, headers: _json);
    }
    if (path.endsWith('/note')) {
      final sent = await _readJson(requestStream);
      final note = sent['note'] as String;
      // Mirrors routes/api/v1/recipes/[id]/note.dart: the stored note is
      // echoed back and an empty one deletes (null).
      return ResponseBody.fromString(
        jsonEncode({'note': note.isEmpty ? null : note}),
        200,
        headers: _json,
      );
    }
    final body = detail;
    if (body == null) {
      return _envelope(404, 'not_found', 'recipe not found');
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: _json);
  }

  static Future<Map<String, dynamic>> _readJson(
    Stream<Uint8List>? stream,
  ) async {
    if (stream == null) {
      return {};
    }
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  static ResponseBody _envelope(int status, String code, String message) =>
      ResponseBody.fromString(
        jsonEncode({
          'error': {'code': code, 'message': message, 'request_id': 'req-test'},
        }),
        status,
        headers: _json,
      );

  @override
  void close({bool force = false}) {}

  static final _json = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };
}

/// The captured detail body, exactly as the server sent it.
final _goldenDetail = golden('recipe_detail');
final _goldenRecipe = _goldenDetail['recipe']! as Map<String, dynamic>;
final _goldenSlug = _goldenRecipe['slug']! as String;

/// The captured body's real private note — used wherever a test needs a note
/// that is already stored server-side.
final _goldenNote = _goldenDetail['note']! as String;

void main() {
  late _FakeAdapter adapter;
  late RecipeRepository repository;
  late RecipeDetailCubit cubit;
  late List<RecipeDetailState> seen;

  setUpAll(RecipeMapper.ensureInitialized);

  setUp(() {
    adapter = _FakeAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;
    repository = RecipeRepository(dio: dio);
    cubit = RecipeDetailCubit(repository);
    seen = [];
    final sub = cubit.stream.listen(seen.add);
    addTearDown(sub.cancel);
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// The captured body with the per-user fields overridden. Only `favorite`
  /// and `note` vary: they are DB-only per-user data, so one capture can
  /// carry only one of their values at a time.
  Map<String, Object?> detailBody({bool favorite = false, String? note}) => {
    ..._goldenDetail,
    'favorite': favorite,
    'note': note,
  };

  group('load failures', () {
    test('a missing recipe shows the not-found wording', () async {
      await cubit.load('no-such-recipe');
      await settle();

      expect(seen, [isA<RecipeDetailLoading>(), isA<RecipeDetailError>()]);
      expect((seen.last as RecipeDetailError).message, 'Recipe not found.');
    });

    test('an unreachable server shows a retry-shaped message', () async {
      adapter.offline = true;

      await cubit.load('anything');
      await settle();

      expect(seen, [isA<RecipeDetailLoading>(), isA<RecipeDetailError>()]);
      expect(
        (seen.last as RecipeDetailError).message,
        startsWith("Couldn't reach"),
      );
    });

    test('a malformed 200 body errors instead of a stuck spinner', () async {
      adapter.detail = {'recipe': 'not an object'};

      await cubit.load('anything');
      await settle();

      expect(seen.last, isA<RecipeDetailError>());
      expect((seen.last as RecipeDetailError).message, isNotEmpty);
    });

    test('retrying after a failure re-enters loading first', () async {
      await cubit.load('no-such-recipe');
      await settle();
      seen.clear();

      await cubit.load('no-such-recipe');
      await settle();

      expect(seen, [isA<RecipeDetailLoading>(), isA<RecipeDetailError>()]);
    });
  });

  group('personal writes before a recipe loads', () {
    test('toggleFavorite is a no-op and issues no request', () async {
      await cubit.toggleFavorite();
      await settle();

      expect(seen, isEmpty);
      expect(adapter.calls, isEmpty);
      expect(cubit.state, isA<RecipeDetailLoading>());
    });

    test('saveNote reports failure rather than a phantom save', () async {
      expect(await cubit.saveNote('note text'), isFalse);
      await settle();

      expect(seen, isEmpty);
      expect(adapter.calls, isEmpty);
    });
  });

  group('with the captured detail body', () {
    setUp(() => adapter.detail = detailBody());

    test('the captured body loads with every field it carries', () async {
      // The golden verbatim: favorite AND note as the server really sent
      // them, so the two per-user fields are pinned in their captured state
      // and not only in the values this file overrides.
      adapter.detail = _goldenDetail;

      await cubit.load(_goldenSlug);
      await settle();

      expect(seen, [isA<RecipeDetailLoading>(), isA<RecipeDetailLoaded>()]);
      final detail = (seen.last as RecipeDetailLoaded).detail;
      expect(detail.recipe.id, _goldenRecipe['id']);
      expect(detail.recipe.slug, _goldenSlug);
      expect(detail.recipe.title, _goldenRecipe['title']);
      expect(
        detail.recipe.steps.length,
        (_goldenRecipe['steps']! as List).length,
        reason: 'the parsed document must survive the JSON round trip',
      );
      expect(
        detail.recipe.ingredients.expand((group) => group.items).length,
        (_goldenRecipe['ingredients']! as List)
            .cast<Map<String, dynamic>>()
            .expand((group) => group['items']! as List)
            .length,
      );
      // The wire fields around the document, from the real capture — the
      // server derives source_slug itself, so a hand-built stand-in would be
      // this file's own invention.
      expect(detail.sourceSlug, _goldenDetail['source_slug']);
      expect(detail.heroImageUrl, _goldenDetail['hero_image_url']);
      expect(detail.baseHash, _goldenDetail['base_hash']);
      expect(detail.favorite, _goldenDetail['favorite']);
      expect(detail.note, _goldenNote);
      expect((seen.last as RecipeDetailLoaded).personalDataError, isNull);
      expect(
        adapter.calls.single.$2,
        '/api/v1/recipes/${Uri.encodeComponent(_goldenSlug)}',
      );
    });

    group('favorite', () {
      setUp(() async {
        await cubit.load(_goldenSlug);
        await settle();
        seen.clear();
        adapter.calls.clear();
      });

      test('a successful toggle emits exactly the optimistic state', () async {
        await cubit.toggleFavorite();
        await settle();

        expect(seen, [isA<RecipeDetailLoaded>()]);
        final after = seen.single as RecipeDetailLoaded;
        expect(after.detail.favorite, isTrue);
        expect(after.personalDataError, isNull);
        expect(adapter.calls.single.$1, 'PUT');
      });

      test('a failed toggle reverts AND surfaces the failure', () async {
        adapter.failing.add('/favorite');

        await cubit.toggleFavorite();
        await settle();

        expect(seen, [
          isA<RecipeDetailLoaded>(),
          isA<RecipeDetailLoaded>(),
        ], reason: 'optimistic flip, then the revert');
        expect((seen.first as RecipeDetailLoaded).detail.favorite, isTrue);
        final reverted = seen.last as RecipeDetailLoaded;
        expect(reverted.detail.favorite, isFalse);
        expect(
          reverted.personalDataError,
          isNotNull,
          reason: 'a swallowed failure would leave a lying heart icon',
        );
      });

      test('a second tap while one is in flight is ignored', () async {
        final first = cubit.toggleFavorite();
        final second = cubit.toggleFavorite();
        await Future.wait([first, second]);
        await settle();

        expect(
          adapter.calls.where((call) => call.$2.endsWith('/favorite')),
          hasLength(1),
          reason: 'a double tap must not desync the heart from the server',
        );
        expect((cubit.state as RecipeDetailLoaded).detail.favorite, isTrue);
      });

      test('a toggle after a failure is allowed again', () async {
        adapter.failing.add('/favorite');
        await cubit.toggleFavorite();
        await settle();
        adapter.failing.clear();
        seen.clear();

        await cubit.toggleFavorite();
        await settle();

        expect((cubit.state as RecipeDetailLoaded).detail.favorite, isTrue);
        expect(
          (cubit.state as RecipeDetailLoaded).personalDataError,
          isNull,
          reason: 'the stale error must clear on the next success',
        );
      });

      test('unfavoriting a favorited recipe DELETEs', () async {
        // The captured body is itself a favorited recipe.
        expect(_goldenDetail['favorite'], isTrue);
        adapter.detail = _goldenDetail;
        await cubit.load(_goldenSlug);
        await settle();
        adapter.calls.clear();

        await cubit.toggleFavorite();
        await settle();

        expect(adapter.calls.single.$1, 'DELETE');
        expect((cubit.state as RecipeDetailLoaded).detail.favorite, isFalse);
      });

      test('the note is preserved across a favorite toggle', () async {
        adapter.detail = detailBody(note: _goldenNote);
        await cubit.load(_goldenSlug);
        await settle();

        await cubit.toggleFavorite();
        await settle();

        expect((cubit.state as RecipeDetailLoaded).detail.note, _goldenNote);
      });
    });

    group('note', () {
      setUp(() async {
        await cubit.load(_goldenSlug);
        await settle();
        seen.clear();
        adapter.calls.clear();
      });

      test('saving stores the trimmed text and reports success', () async {
        expect(await cubit.saveNote('  $_goldenNote  '), isTrue);
        await settle();

        expect(seen, [isA<RecipeDetailLoaded>()]);
        final after = seen.single as RecipeDetailLoaded;
        expect(after.detail.note, _goldenNote);
        expect(after.personalDataError, isNull);
        expect(adapter.calls.single.$1, 'PUT');
        expect(adapter.calls.single.$2, endsWith('/note'));
      });

      test('an empty note clears it', () async {
        expect(await cubit.saveNote(_goldenNote), isTrue);
        await settle();
        expect((cubit.state as RecipeDetailLoaded).detail.note, _goldenNote);

        expect(await cubit.saveNote('   '), isTrue);
        await settle();

        expect(
          (cubit.state as RecipeDetailLoaded).detail.note,
          isNull,
          reason: 'whitespace-only trims to empty, which deletes the note',
        );
      });

      test('a failed save returns false and surfaces the error', () async {
        adapter.detail = detailBody(note: _goldenNote);
        await cubit.load(_goldenSlug);
        await settle();
        seen.clear();
        adapter.failing.add('/note');

        expect(await cubit.saveNote('a replacement'), isFalse);
        await settle();

        expect(seen, [isA<RecipeDetailLoaded>()]);
        final after = seen.single as RecipeDetailLoaded;
        expect(
          after.detail.note,
          _goldenNote,
          reason: 'a failed write must not show the unsaved text as stored',
        );
        expect(after.personalDataError, isNotNull);
      });

      test(
        'an unreachable server fails the save rather than faking it',
        () async {
          adapter.offline = true;

          expect(await cubit.saveNote('offline text'), isFalse);
          await settle();

          expect(
            (cubit.state as RecipeDetailLoaded).personalDataError,
            startsWith("Couldn't reach"),
          );
        },
      );
    });
  });

  // --- corpus-backed: the ONE claim the golden cannot make -----------------

  group('with a richer ATK corpus document', skip: skipIfNoCorpus, () {
    /// The captured body's own recipe has no subsections and no techniques
    /// (measured: both lists are empty), so it cannot show that those parts
    /// of the document survive the wire. This one does.
    late Recipe recipe;

    setUpAll(() => recipe = loadCorpusRecipe('1105-yeasted-doughnuts.yaml'));

    test('subsections and techniques survive the JSON round trip', () async {
      expect(
        recipe.subsections,
        isNotEmpty,
        reason: 'the chosen corpus recipe must actually carry subsections',
      );
      expect(recipe.techniques, isNotEmpty);
      adapter.detail = {...detailBody(), 'recipe': recipe.toMap()};

      await cubit.load(recipe.slug);
      await settle();

      expect(seen, [isA<RecipeDetailLoading>(), isA<RecipeDetailLoaded>()]);
      final loaded = (seen.last as RecipeDetailLoaded).detail.recipe;
      expect(loaded.id, recipe.id);
      expect(loaded.title, recipe.title);
      expect(loaded.subsections.length, recipe.subsections.length);
      expect(
        loaded.subsections.map((section) => section.title),
        recipe.subsections.map((section) => section.title),
      );
      expect(loaded.techniques.length, recipe.techniques.length);
      expect(
        loaded.ingredients.expand((group) => group.items).length,
        recipe.ingredients.expand((group) => group.items).length,
      );
    });
  });
}
