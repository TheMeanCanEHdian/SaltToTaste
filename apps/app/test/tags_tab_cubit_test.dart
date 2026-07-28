import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salt_app/core/api/tags_repository.dart';
import 'package:salt_app/features/settings/tags_tab_cubit.dart';
import 'package:salt_app/features/tags/tag_styles_cubit.dart';

import 'support/contract_goldens.dart';
import 'support/corpus.dart';

/// Settings → Tags: the load/filter/sort/edit state machine, driven through
/// the REAL [TagsRepository] over a canned Dio adapter.
///
/// The state-machine group is corpus-free, so CI runs all of it. Its
/// listings are the committed contract goldens — real `GET /api/v1/tags`
/// bodies captured from the real route, before and after a style was saved
/// (`packages/salt_shared/test/fixtures/contract/tags_{unstyled,styled}
/// .json`) — so the icon name and hexes it saves are the ones the server
/// really stored, not this file's invention. The one hand-built row is a
/// crafted hostile tag NAME, a negative-path input the corpus cannot supply,
/// which pins that the style URL is percent-encoded.
///
/// The filter/sort group works over the REAL ATK tag vocabulary and skips
/// without `SALT_CORPUS_DIR`.
class _FakeAdapter implements HttpClientAdapter {
  /// Rows served by `GET /api/v1/tags`, in the server's wire shape.
  List<Map<String, Object?>> tags = [];

  bool failList = false;
  bool failStyle = false;
  bool offline = false;

  /// Held open to keep a style write in flight.
  Completer<void>? styleGate;

  /// Every `(method, path)` requested, in order.
  final List<(String, String)> calls = [];

  /// Bodies sent to the style endpoint, in order.
  final List<Map<String, dynamic>> styleWrites = [];

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
    if (path.endsWith('/style')) {
      styleWrites.add(await _readJson(requestStream));
      await styleGate?.future;
      if (failStyle) {
        // The real server's admin-only rejection.
        return _envelope(403, 'forbidden', 'Admin access is required.');
      }
      return ResponseBody.fromString('{}', 200, headers: _json);
    }
    if (failList) {
      return _envelope(500, 'internal', 'the server fell over');
    }
    return ResponseBody.fromString(
      jsonEncode({'items': tags}),
      200,
      headers: _json,
    );
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

/// A tags-listing row in the server's wire shape — for the names no capture
/// can supply (the crafted hostile name; the corpus-derived vocabulary).
Map<String, Object?> _row(String name, int count) => {
  'name': name,
  'count': count,
  'icon': null,
  'color': null,
  'bg_color': null,
};

/// The rows of a captured `GET /api/v1/tags` body.
List<Map<String, Object?>> _goldenRows(String name) =>
    (golden(name)['items']! as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList();

/// The real listing before any style was saved, and after.
final _unstyledRows = _goldenRows('tags_unstyled');
final _styledRows = _goldenRows('tags_styled');

/// The one captured row that carries a real saved style.
final _styledRow = _styledRows.firstWhere((row) => row['icon'] != null);
final _styledName = _styledRow['name']! as String;

void main() {
  late _FakeAdapter adapter;
  late TagsRepository repository;
  late TagStylesCubit appStyles;
  late TagsTabCubit cubit;
  late List<TagsTabState> seen;

  setUp(() {
    adapter = _FakeAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;
    repository = TagsRepository(dio);
    appStyles = TagStylesCubit(repository);
    cubit = TagsTabCubit(repository, appStyles);
    seen = [];
    final sub = cubit.stream.listen(seen.add);
    addTearDown(sub.cancel);
    addTearDown(cubit.close);
    addTearDown(appStyles.close);
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  // --- corpus-free: the state machine --------------------------------------

  group('the editor state machine (corpus-free)', () {
    // A name the corpus cannot produce, chosen to break a naive URL build:
    // a path separator, a fragment marker, a space, and a non-ASCII letter.
    const hostile = 'a/b#c ré';
    const hostileEncoded = 'a%2Fb%23c%20r%C3%A9';

    setUp(() => adapter.tags = _unstyledRows);

    /// The captured row the editor tests operate on, as the cubit parsed it.
    TagInfo editable() =>
        cubit.state.tags!.firstWhere((tag) => tag.name == _styledName);

    test('a failed load surfaces the error and keeps no rows', () async {
      adapter.failList = true;

      await cubit.load();
      await settle();

      expect(seen, hasLength(2), reason: 'clear-then-fail');
      expect(seen.first.loadError, isNull);
      expect(seen.last.loadError, isNotNull);
      expect(cubit.state.tags, isNull);
      expect(cubit.state.visibleTags, isEmpty);
    });

    test('an unreachable server also surfaces a message', () async {
      adapter.offline = true;

      await cubit.load();
      await settle();

      expect(cubit.state.loadError, startsWith("Couldn't reach"));
    });

    test('a retry clears the stale error and lands the rows', () async {
      adapter.failList = true;
      await cubit.load();
      await settle();
      expect(cubit.state.loadError, isNotNull);
      seen.clear();

      adapter.failList = false;
      await cubit.load();
      await settle();

      expect(seen, hasLength(2));
      expect(seen.first.loadError, isNull, reason: 'cleared before refetching');
      expect(seen.last.loadError, isNull);
      expect(
        cubit.state.tags!.map((tag) => tag.name).toSet(),
        _unstyledRows.map((row) => row['name']).toSet(),
      );
      expect(
        {for (final tag in cubit.state.tags!) tag.name: tag.count},
        {for (final row in _unstyledRows) row['name']: row['count']},
      );
      expect(
        cubit.state.tags!.every((tag) => tag.style.isEmpty),
        isTrue,
        reason: 'the captured pre-style listing carries no chip styling',
      );
    });

    group('after a successful load', () {
      setUp(() async {
        await cubit.load();
        await settle();
        seen.clear();
        adapter.calls.clear();
      });

      test(
        'opening the editor seeds the draft from the stored style',
        () async {
          // The captured listing AFTER a style was saved — a real icon name
          // and real hexes, so a renamed style key would land here.
          adapter.tags = _styledRows;
          await cubit.load();
          await settle();
          seen.clear();

          cubit.openEditor(editable());
          await settle();

          expect(seen, hasLength(1));
          final state = seen.single;
          expect(state.editingTag, _styledName);
          expect(state.draftIcon, _styledRow['icon']);
          expect(state.draftColor, _styledRow['color']);
          expect(state.draftBgColor, _styledRow['bg_color']);
          expect(state.canSave, isTrue);
          expect(state.saveError, isNull);
        },
      );

      test('a half-typed hex blocks Save and issues no request', () async {
        cubit
          ..openEditor(editable())
          ..setDraftColors(color: '#12');
        await settle();
        expect(cubit.state.draftColorInvalid, isTrue);
        expect(cubit.state.canSave, isFalse);
        seen.clear();

        await cubit.save();
        await settle();

        expect(seen, isEmpty, reason: 'a blocked save must not emit');
        expect(adapter.styleWrites, isEmpty);
        expect(
          cubit.state.editingTag,
          _styledName,
          reason: 'the editor stays open so the field can be corrected',
        );
      });

      test('an invalid BACKGROUND hex blocks Save too', () async {
        // The other hex field: a valid foreground must not let a broken
        // background through to the wire.
        cubit
          ..openEditor(editable())
          ..setDraftColors(
            color: _styledRow['color']! as String,
            bgColor: 'rebeccapurple',
          );
        await settle();

        expect(cubit.state.draftColorInvalid, isFalse);
        expect(cubit.state.draftBgColorInvalid, isTrue);
        expect(cubit.state.canSave, isFalse);
        seen.clear();

        await cubit.save();
        await settle();

        expect(seen, isEmpty);
        expect(adapter.styleWrites, isEmpty);
        expect(cubit.state.editingTag, _styledName);
      });

      test(
        'a rejected save surfaces the reason and keeps the editor open',
        () async {
          adapter.failStyle = true;
          cubit
            ..openEditor(editable())
            ..setDraftColors(color: _styledRow['color']! as String);
          await settle();
          seen.clear();

          await cubit.save();
          await settle();

          expect(seen, hasLength(2), reason: 'saving=true, then the failure');
          expect(seen.first.saving, isTrue);
          expect(seen.first.saveError, isNull);
          expect(seen.last.saving, isFalse);
          expect(
            seen.last.saveError,
            'Admin access is required.',
            reason: 'a swallowed failure would look like a successful save',
          );
          expect(
            seen.last.editingTag,
            _styledName,
            reason: 'closing the editor would discard the unsaved draft',
          );
          expect(
            adapter.calls.where((call) => call.$1 == 'GET'),
            isEmpty,
            reason: 'a failed save must not trigger the success-path reload',
          );
        },
      );

      test('a successful save closes the editor, reloads, and refreshes '
          'the app-wide styles', () async {
        // Saving exactly the style the capture proves the server stored.
        cubit
          ..openEditor(editable())
          ..setDraftIcon(_styledRow['icon']! as String)
          ..setDraftColors(
            color: _styledRow['color']! as String,
            bgColor: _styledRow['bg_color']! as String,
          );
        await settle();
        // The server now returns the saved style on the next listing — the
        // captured post-save body.
        adapter.tags = _styledRows;
        seen.clear();

        await cubit.save();
        await settle();

        expect(adapter.styleWrites.single, {
          'icon': _styledRow['icon'],
          'color': _styledRow['color'],
          'bg_color': _styledRow['bg_color'],
        });
        expect(seen.map((s) => s.saving).toList(), [true, false, false, false]);
        expect(seen[1].editingTag, isNull, reason: 'the editor closes');
        expect(
          seen.last.tags!
              .firstWhere((tag) => tag.name == _styledName)
              .style
              .icon,
          _styledRow['icon'],
        );
        expect(
          appStyles.state[_styledName]?.color,
          _styledRow['color'],
          reason: 'chips elsewhere must pick the new style up immediately',
        );
      });

      test('the style URL percent-encodes the tag name', () async {
        adapter.tags = [_row(hostile, 3)];
        await cubit.load();
        await settle();
        adapter.calls.clear();

        cubit.openEditor(cubit.state.tags!.single);
        await cubit.save();
        await settle();

        expect(adapter.calls.first.$1, 'PUT');
        expect(adapter.calls.first.$2, '/api/v1/tags/$hostileEncoded/style');
      });

      test('an all-empty draft saves the style-clearing body', () async {
        adapter.tags = _styledRows;
        await cubit.load();
        await settle();
        cubit
          ..openEditor(editable())
          ..resetDraft();
        await settle();

        expect(cubit.state.draftIcon, isNull);
        expect(cubit.state.draftColor, '');
        expect(cubit.state.draftBgColor, '');
        expect(cubit.state.draftStyle.isEmpty, isTrue);

        await cubit.save();
        await settle();

        expect(adapter.styleWrites.single, {
          'icon': null,
          'color': null,
          'bg_color': null,
        });
      });

      test('a pasted hex is trimmed before it reaches the wire', () async {
        // A hex pasted with surrounding whitespace is still valid: the
        // preview and what Save sends are both the trimmed value, so they
        // can never disagree.
        final hex = _styledRow['color']! as String;
        cubit
          ..openEditor(editable())
          ..setDraftColors(color: '  $hex  ');
        await settle();

        expect(cubit.state.draftColorInvalid, isFalse);
        expect(cubit.state.draftStyle.color, hex);
        await cubit.save();
        await settle();
        expect(adapter.styleWrites.single['color'], hex);
      });

      test('the editor cannot be reopened while a save is in flight', () async {
        final gate = Completer<void>();
        adapter.styleGate = gate;
        cubit.openEditor(editable());
        final saving = cubit.save();
        await settle();
        expect(cubit.state.saving, isTrue);
        seen.clear();

        cubit.openEditor(editable());
        await settle();
        expect(seen, isEmpty, reason: 'openEditor is ignored while saving');

        gate.complete();
        await saving;
        await settle();
        expect(cubit.state.saving, isFalse);
      });

      test('a second save while one is in flight is ignored', () async {
        final gate = Completer<void>();
        adapter.styleGate = gate;
        cubit.openEditor(editable());
        final first = cubit.save();
        await settle();
        final second = cubit.save();
        gate.complete();
        await Future.wait([first, second]);
        await settle();

        expect(adapter.styleWrites, hasLength(1));
      });

      test('save with no editor open does nothing', () async {
        expect(cubit.state.editingTag, isNull);

        await cubit.save();
        await settle();

        expect(seen, isEmpty);
        expect(adapter.styleWrites, isEmpty);
      });

      test('closing the editor drops the draft and the error', () async {
        adapter.failStyle = true;
        cubit.openEditor(editable());
        await cubit.save();
        await settle();
        expect(cubit.state.saveError, isNotNull);
        seen.clear();

        cubit.closeEditor();
        await settle();

        expect(seen.single.editingTag, isNull);
        expect(seen.single.saveError, isNull);
      });
    });
  });

  // --- corpus-backed: the real ATK tag vocabulary ---------------------------

  group(
    'filter and sort over the real tag vocabulary',
    skip: skipIfNoCorpus,
    () {
      /// Every real label the corpus carries, with the number of recipes on it
      /// — computed from the data at test time, never hardcoded.
      ///
      /// The ATK extraction's own `tags:` field is degenerate (measured: ONE
      /// distinct value across all 1,198 recipes), which cannot exercise a
      /// filter or a tie-broken sort, so the recipes' real `category:` strings
      /// join it. Those are the same kind of thing the tab renders — real
      /// library label text, with real mixed case, punctuation, and curly
      /// apostrophes — and their counts are real.
      late Map<String, int> counts;

      setUpAll(() {
        counts = <String, int>{};
        for (final recipe in loadAllCorpusRecipes()) {
          final category = recipe.category;
          for (final label in [
            ...recipe.tags,
            if (category != null) category,
          ]) {
            counts[label] = (counts[label] ?? 0) + 1;
          }
        }
      });

      setUp(() async {
        // The server lists tags ordered by name; the cubit re-sorts.
        final names = counts.keys.toList()..sort();
        adapter.tags = [for (final name in names) _row(name, counts[name]!)];
        await cubit.load();
        await settle();
        seen.clear();
      });

      test('the whole vocabulary loads', () {
        expect(
          counts.length,
          greaterThan(5),
          reason: 'too few distinct labels to exercise filtering or sorting',
        );
        expect(cubit.state.tags, hasLength(counts.length));
        expect(cubit.state.visibleTags, hasLength(counts.length));
      });

      test('the default sort is most-recipes, ties broken by name', () {
        final expected = counts.keys.toList()
          ..sort((a, b) {
            final byCount = counts[b]!.compareTo(counts[a]!);
            return byCount != 0
                ? byCount
                : a.toLowerCase().compareTo(b.toLowerCase());
          });

        expect(cubit.state.sort, TagSort.mostRecipes);
        expect(
          cubit.state.visibleTags.map((tag) => tag.name).toList(),
          expected,
        );
      });

      test('the alphabetical sort orders case-insensitively', () async {
        cubit.setSort(TagSort.alphabetical);
        await settle();

        final expected = counts.keys.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        expect(seen.single.sort, TagSort.alphabetical);
        expect(
          cubit.state.visibleTags.map((tag) => tag.name).toList(),
          expected,
        );
      });

      test(
        'the filter is a case-insensitive substring over real names',
        () async {
          // A real fragment: the first three characters of the commonest tag.
          final busiest = counts.entries.reduce(
            (a, b) => b.value > a.value ? b : a,
          );
          final fragment = busiest.key.substring(0, 3);
          final expected = counts.keys
              .where(
                (name) => name.toLowerCase().contains(fragment.toLowerCase()),
              )
              .toSet();

          cubit.setFilter(fragment.toUpperCase());
          await settle();

          expect(seen.single.filter, fragment.toUpperCase());
          expect(
            cubit.state.visibleTags.map((tag) => tag.name).toSet(),
            expected,
          );
          expect(
            cubit.state.visibleTags.map((tag) => tag.name),
            contains(busiest.key),
          );
          expect(
            expected.length,
            lessThan(counts.length),
            reason: 'the fragment must actually narrow the list',
          );
        },
      );

      test(
        'a filter matching nothing empties the list without losing it',
        () async {
          cubit.setFilter('zzzz-no-such-tag-zzzz');
          await settle();

          expect(cubit.state.visibleTags, isEmpty);
          expect(
            cubit.state.tags,
            hasLength(counts.length),
            reason: 'filtering is a view, not a mutation',
          );
        },
      );

      test('whitespace-only filter shows everything', () async {
        cubit.setFilter('   ');
        await settle();

        expect(cubit.state.visibleTags, hasLength(counts.length));
      });
    },
  );
}
