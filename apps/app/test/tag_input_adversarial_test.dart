
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/api/tags_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/editor/editor_cubit.dart';
import 'package:salt_app/features/editor/editor_page.dart';

/// Adversarial probes for the round-3 _TagsInput fixes.
void main() {
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
        builder: (context, child) =>
            FTheme(data: forui, child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: BlocProvider(
            create: (context) =>
                EditorCubit(context.read<RecipeRepository>())..startNew(),
            child: const _Harness(),
          ),
        ),
      ),
    );
  }

  List<String> tagsOf(WidgetTester tester) =>
      tester.element(find.byType(_Harness)).read<EditorCubit>().state.tags;

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first).controller!.text;

  // ==================================================================
  // FINDING 1 (HIGH): the Create-row sentinel was committed as a real tag.
  // Now doubly dead: the sentinel is gone, AND blur commits nothing at all.
  // ==================================================================
  testWidgets(
    'arrow-down to the Create row puts the plain typed text in the field',
    (tester) async {
      await tester.pumpWidget(host(tags: ['dessert']));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'sheet-pan');
      await tester.pumpAndSettle();

      // The mockup contract says Enter takes the HIGHLIGHTED row, and
      // FAutocomplete highlights nothing until arrow-down -- so arrow-down is
      // exactly the gesture the contract asks the user to make.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      // An item's value is NOT a private channel: taking focus writes it
      // straight into the visible field (forui autocomplete.dart:1531-1536,
      // `_controller.text = widget.format(value)`, format being the identity
      // here). The Create row's value is therefore the plain typed text, and
      // arrowing onto it must leave the field showing exactly what was typed.
      // It once held a NUL-prefixed ` create:sheet-pan`, on screen and all.
      expect(
        fieldText(tester),
        'sheet-pan',
        reason: 'no sentinel may reach the field the user is looking at',
      );
    },
  );

  // ==================================================================
  // The commit contract (user's call, 2026-07-16): a tag is added ONLY by an
  // explicit act. Blur is not one.
  // ==================================================================
  group('only an explicit act commits a tag', () {
    testWidgets('typing and clicking away adds NOTHING', (tester) async {
      await tester.pumpWidget(host(tags: ['dessert']));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'weeknight');
      await tester.pumpAndSettle();

      // Exactly what clicking Save, or any other field, does.
      FocusScope.of(tester.element(find.byType(_Harness))).unfocus();
      await tester.pumpAndSettle();

      expect(
        tagsOf(tester),
        isEmpty,
        reason: 'blur must not invent a tag the user never committed. '
            'Actual: ${tagsOf(tester)}',
      );
      expect(
        fieldText(tester),
        'weeknight',
        reason: 'and the text stays put, visibly still not a chip, rather '
            'than being silently swallowed',
      );
    });

    testWidgets('blur cannot mint the junk near-duplicate', (tester) async {
      // The whole reason this widget exists. Enter on "des" resolves to
      // "dessert"; blur used to take "des" literally and save it alongside.
      await tester.pumpWidget(host(tags: ['dessert']));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'des');
      await tester.pumpAndSettle();

      FocusScope.of(tester.element(find.byType(_Harness))).unfocus();
      await tester.pumpAndSettle();

      expect(
        tagsOf(tester),
        isEmpty,
        reason: 'clicking Save with "des" half-typed must not create "des". '
            'Actual: ${tagsOf(tester)}',
      );
    });

    testWidgets('Enter still commits, and still matches', (tester) async {
      await tester.pumpWidget(host(tags: ['dessert']));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'des');
      await tester.pumpAndSettle();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        tagsOf(tester),
        ['dessert'],
        reason: 'removing the blur commit must not disarm Enter',
      );
    });

    testWidgets('pressing the Create row still commits', (tester) async {
      await tester.pumpWidget(host(tags: ['dessert']));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'sheet-pan');
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Create'));
      await tester.pumpAndSettle();

      expect(
        tagsOf(tester),
        ['sheet-pan'],
        reason: 'the other explicit commit path must still work',
      );
    });
  });

  // ==================================================================
  // The junk near-duplicate, reachable through the PRIMARY path. Found by the
  // review's completeness critic; no finder lens covered it.
  // ==================================================================
  testWidgets('Enter matches even when the match is already on the recipe', (
    tester,
  ) async {
    await tester.pumpWidget(host(tags: ['dessert']));
    await tester.pumpAndSettle();

    // Commit "dessert" — the ordinary thing to do first.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'dessert');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tagsOf(tester), ['dessert']);

    // Now type a near-miss OF THE TAG THE RECIPE ALREADY HAS and press Enter.
    // Resolution must consult the whole vocabulary; the popover's "don't offer
    // what you already have" rule is a DISPLAY rule, and folding it into
    // resolution made `dessert` invisible to the matcher, so Enter found no
    // match and minted `des` — the exact bug this widget exists to prevent,
    // via its primary path.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'des');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      tagsOf(tester),
      ['dessert'],
      reason: 'Enter must resolve to the tag already present and no-op, not '
          'create the junk near-duplicate. Actual: ${tagsOf(tester)}',
    );
  });

  // ==================================================================
  // The `Create` row must stay reachable by keyboard.
  // ==================================================================
  testWidgets('arrowing onto a suggestion does not delete the Create row', (
    tester,
  ) async {
    await tester.pumpWidget(host(tags: ['dessert', 'grilling']));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'des');
    await tester.pumpAndSettle();
    expect(find.textContaining('Create'), findsOneWidget);

    // Arrow-down previews `dessert` BY WRITING IT INTO THE FIELD (forui
    // autocomplete.dart:1531-1535). The Create row is built from what the user
    // TYPED, so the preview must not be able to delete it — it once did,
    // leaving the deliberate-near-miss escape hatch mouse-only.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Create'),
      findsOneWidget,
      reason: 'previewing a suggestion must not remove the Create row',
    );

    // And it is genuinely reachable: arrow past the suggestion onto Create,
    // then Enter creates the near-miss the user deliberately asked for.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      tagsOf(tester),
      ['des'],
      reason: 'keyboard users must be able to reach Create. '
          'Actual: ${tagsOf(tester)}',
    );
  });

  // ==================================================================
  // FINDING 2 (HIGH): popover and Enter disagree while the vocabulary loads.
  // ==================================================================
  testWidgets(
    'F2: typing before the tags fetch lands -> popover offers only Create, Enter takes dessert',
    (tester) async {
      await tester.pumpWidget(
        host(tags: ['dessert', 'grilling'], delay: const Duration(seconds: 2)),
      );
      await tester.pump();

      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'des');
      await tester.pump();

      // The vocabulary lands. setState rebuilds _TagsInput, but forui only
      // re-runs `filter` when the field TEXT changes (autocomplete.dart:1249
      // `if (_previous == _controller.text) return;`), and didUpdateWidget's
      // control.update returns updated=false for the same controller
      // (autocomplete_controller.control.dart:54). So _data stays stale.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(
        find.text('dessert'),
        findsWidgets,
        reason:
            'once the vocabulary is loaded the popover must offer "dessert"; '
            'it still shows only the Create row, yet Enter will take "dessert"',
      );
    },
  );

  // The fix's mechanism: `filter` hands forui a FUTURE while the tags request
  // is in flight, so `Content` parks the popover on its loadingBuilder and does
  // not call contentBuilder at all (autocomplete_content.dart:70-80). A popover
  // that knows nothing must therefore OFFER nothing — above all not `Create`,
  // which against an empty vocabulary is a lie: it says "no such tag exists"
  // when the truth is "the tags have not arrived".
  testWidgets('while the vocabulary is in flight the popover offers no rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(tags: ['dessert', 'grilling'], delay: const Duration(seconds: 2)),
    );
    await tester.pump();
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'des');
    await tester.pump();

    // Mid-fetch: nothing pressable.
    expect(
      find.textContaining('Create'),
      findsNothing,
      reason: 'Create cannot be offered before the vocabulary is known',
    );
    expect(find.text('dessert'), findsNothing, reason: 'not known yet either');

    // It lands, and the popover fills itself in — with NO further keystroke.
    // (The old code re-ran `filter` only on a text change, so it needed one.)
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(
      find.text('dessert'),
      findsWidgets,
      reason: 'the awaited future resolved and contentBuilder finally ran',
    );
  });

  // ==================================================================
  // FINDING 3 (MED): text typed during the await is silently destroyed.
  // ==================================================================
  testWidgets('F3: typing during the 2s await -> the new text is wiped', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(tags: ['dessert'], delay: const Duration(seconds: 2)),
    );
    await tester.pump();

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'des');
    await tester.pump();

    // Enter while the fetch is in flight: editor_page.dart:666 clears first.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(fieldText(tester), '', reason: 'text vanished with no feedback');

    // The user sees an empty field and types the next tag.
    await tester.enterText(find.byType(TextField).first, 'grilling');
    await tester.pump();
    expect(fieldText(tester), 'grilling');

    // The fetch lands and _onSubmit resumes -> _addNamed clears the field
    // (editor_page.dart:616), destroying what the user just typed.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(
      fieldText(tester),
      'grilling',
      reason: "the resumed Enter must not wipe the user's in-progress text",
    );
  });

  // The counterpart: once the vocabulary IS known, `Create "des"` is offered
  // again — alongside `dessert` — and pressing it really does create `des`.
  // That is the design, not the round-1 bug: the junk near-duplicate was born
  // from Create being the ONLY row on offer, so the user pressed it having
  // never been shown `dessert`. Presented with both, the same press is an
  // informed choice, and the widget must honour it.
  testWidgets('once the vocabulary is known, Create is an informed choice', (
    tester,
  ) async {
    await tester.pumpWidget(host(tags: ['dessert', 'grilling']));
    await tester.pump();
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'des');
    await tester.pumpAndSettle();

    expect(
      find.text('dessert'),
      findsWidgets,
      reason: 'the near-miss the user might have meant is shown FIRST',
    );
    final createRow = find.textContaining('Create');
    expect(createRow, findsOneWidget, reason: 'and creating is still possible');

    await tester.tap(createRow);
    await tester.pumpAndSettle();

    expect(
      tagsOf(tester),
      ['des'],
      reason:
          'the user saw "dessert" and chose Create anyway — honour it. '
          'Actual: ${tagsOf(tester)}',
    );
  });
}

class _Harness extends StatelessWidget {
  const _Harness();

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

  /// Simulates a cold server: the popover must not decide before this lands.
  final Duration delay;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? __,
  ) async {
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
