import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/api/tags_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/editor/editor_cubit.dart';
import 'package:salt_app/features/editor/editor_page.dart';

/// The editor's tag input.
///
/// Every test here corresponds to a defect an adversarial review found in the
/// hand-rolled RawAutocomplete version, which analyze, a passing suite and a
/// browser check all missed. The vocabulary is shared across the whole
/// library, so a near-miss duplicate (`des` beside `dessert`) is the failure
/// worth pinning.
void main() {
  /// Serves a fixed tag list to TagsRepository.listTags().
  Widget host({required List<String> tags, Duration delay = Duration.zero}) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _TagsAdapter(tags, delay: delay);
    final forui = buildForuiTheme();
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<TagsRepository>.value(value: TagsRepository(dio)),
        RepositoryProvider<RecipeRepository>.value(
          value: RecipeRepository(dio: dio),
        ),
      ],
      child: MaterialApp(
        theme: buildMaterialTheme(forui),
        // FTheme is installed the same way app.dart does it.
        builder: (context, child) =>
            FTheme(data: forui, child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: BlocProvider(
            create: (context) =>
                EditorCubit(context.read<RecipeRepository>())..startNew(),
            child: const _TagsInputHarness(),
          ),
        ),
      ),
    );
  }

  Future<void> typeTag(WidgetTester tester, String text) async {
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pumpAndSettle();
  }

  List<String> tagsOf(WidgetTester tester) => tester
      .element(find.byType(_TagsInputHarness))
      .read<EditorCubit>()
      .state
      .tags;

  testWidgets('Enter takes the match instead of minting a near-duplicate', (
    tester,
  ) async {
    // THE BUG: typing "des" + Enter created the junk tag `des` beside the real
    // `dessert`, because onSubmit hands over the raw text.
    await tester.pumpWidget(host(tags: ['dessert', 'grilling', 'salad']));
    await tester.pumpAndSettle();

    await typeTag(tester, 'des');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      tagsOf(tester),
      ['dessert'],
      reason: 'Enter must take the matching tag, not create "des"',
    );
  });

  testWidgets('Enter creates when nothing matches', (tester) async {
    await tester.pumpWidget(host(tags: ['dessert']));
    await tester.pumpAndSettle();

    await typeTag(tester, 'sheet-pan');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      tagsOf(tester),
      ['sheet-pan'],
      reason: 'with no match, Enter is the create path',
    );
  });

  testWidgets('an exact match wins over other substring matches', (
    tester,
  ) async {
    // 'salad' is both an exact hit and a substring of 'salad dressing'.
    await tester.pumpWidget(host(tags: ['salad dressing', 'salad']));
    await tester.pumpAndSettle();

    await typeTag(tester, 'salad');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(tagsOf(tester), ['salad']);
  });

  testWidgets('substring matches are offered, not just prefixes', (
    tester,
  ) async {
    // Forui's default filter is startsWith; the old field matched substrings
    // and losing that would be a silent regression ("sert" -> "dessert").
    await tester.pumpWidget(host(tags: ['dessert']));
    await tester.pumpAndSettle();

    await typeTag(tester, 'sert');
    expect(find.text('dessert'), findsWidgets);
  });

  testWidgets('a tag already on the recipe is never offered again', (
    tester,
  ) async {
    // THE BUG: after adding a tag, re-focusing re-offered it from a stale
    // options list, and clicking that row did nothing at all.
    await tester.pumpWidget(host(tags: ['dessert', 'grilling']));
    await tester.pumpAndSettle();

    await typeTag(tester, 'dess');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tagsOf(tester), ['dessert']);

    // Re-focus with an empty field: the vocabulary minus what we hold.
    await typeTag(tester, '');
    await tester.pumpAndSettle();

    // 'dessert' may still appear as the CHIP; it must not appear as an option.
    expect(
      find.descendant(
        of: find.byType(FAutocomplete<String>),
        matching: find.text('dessert'),
      ),
      findsNothing,
      reason: 'a tag already on the recipe must not be re-offered',
    );
  });
}

/// Just the tag field, with the editor's cubit around it.
class _TagsInputHarness extends StatelessWidget {
  const _TagsInputHarness();

  @override
  Widget build(BuildContext context) => BlocBuilder<EditorCubit, EditorState>(
    builder: (context, state) =>
        state.loading ? const SizedBox.shrink() : const TagsInputForTest(),
  );
}

/// Serves `GET /api/v1/tags`.
class _TagsAdapter implements HttpClientAdapter {
  _TagsAdapter(this.tags, {this.delay = Duration.zero});

  final List<String> tags;

  /// Simulates a cold server: Enter must not decide before this lands.
  final Duration delay;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (options.path.contains('/tags')) {
      return ResponseBody.fromString(
        '{"items":[${tags.map((t) => '{"name":"$t","count":1,"style":{}}').join(',')}]}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('{}', 404);
  }

  @override
  void close({bool force = false}) {}
}
