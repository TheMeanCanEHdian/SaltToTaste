import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/core/api/auth_repository.dart';
import 'package:salt_app/core/api/tags_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_nav_bar.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';
import 'package:salt_app/features/search/search_chip_box.dart';

/// The nav bar's search autocomplete, driven through the real widget.
///
/// The contract worth pinning is what ENTER means. RawAutocomplete
/// pre-highlights option 0 and its `onFieldSubmitted` takes whatever is
/// highlighted, so the naive wiring makes typing `t` + Enter search for
/// `tag:` — the same shape as the editor's junk-tag bug (`des` + Enter minting
/// `des` beside `dessert`), reached from the opposite direction. Here the raw
/// text IS the right answer unless the user chose a row.
void main() {
  /// Long enough that a test can observe the popover before the fetch lands.
  const slowFetch = Duration(milliseconds: 300);
  late List<String> navigations;

  Widget host({
    List<String> tags = const ['dessert', 'main'],
    Duration delay = Duration.zero,
    String? initialQuery,
    VoidCallback? onRefresh,
  }) {
    navigations = [];
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _TagsAdapter(tags, delay: delay);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            appBar: SaltNavBar(
              initialQuery: initialQuery,
              onSearchRefresh: onRefresh,
            ),
            body: const SizedBox(),
          ),
        ),
        GoRoute(
          path: '/search',
          builder: (context, state) {
            navigations.add(state.uri.query);
            return const Scaffold(body: Text('results'));
          },
        ),
      ],
    );
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<TagsRepository>.value(value: TagsRepository(dio)),
      ],
      child: BlocProvider(
        // SaltNavBar's avatar menu reads AuthCubit unconditionally, before its
        // own null check, so the harness dies without one. AuthUnknown leaves
        // the avatar hidden, which is fine for search.
        create: (_) => AuthCubit(AuthRepository(dio)),
        child: MaterialApp.router(
          routerConfig: router,
          // Matches app.dart: Forui widgets (FDialog in the mobile search) need
          // the FTheme's FAccessibilityScope ancestor or they throw at build.
          builder: (context, child) =>
              FTheme(data: buildForuiTheme(), child: child ?? const SizedBox()),
        ),
      ),
    );
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pumpAndSettle();
  }

  testWidgets('Enter searches the raw text, not the first suggestion', (
    tester,
  ) async {
    // THE BUG this exists to prevent: `t` shows `title:`/`tag:` rows, and
    // RawAutocomplete would happily submit `tag:` on Enter.
    await tester.pumpWidget(host());
    await type(tester, 't');
    expect(find.text('title:'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(navigations, ['q=t'], reason: 'Enter must search what was typed');
  });

  testWidgets('arrow down then Enter takes the chosen row', (tester) async {
    await tester.pumpWidget(host());
    await type(tester, 't');

    // The FIRST arrow chooses the row already at index 0; letting
    // RawAutocomplete advance would skip it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // `title:` is the first keyword, and taking it leaves the caret ready for
    // a value rather than navigating.
    expect(navigations, isEmpty);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'title:');
    expect(field.controller!.selection.baseOffset, 6);
  });

  testWidgets('Escape after arrowing does not kill Enter', (tester) async {
    // THE BUG: Escape hides the popover but could not tell `_arrowed`, so
    // Enter routed to a handler guarded by `if (optionsView.isShowing)` and
    // silently no-opped. The key stayed dead until another character was
    // typed — no navigation, no feedback, nothing.
    await tester.pumpWidget(host());
    await type(tester, 'tag:d');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(navigations, ['q=tag%3Ad'], reason: 'Enter must still search');
  });

  testWidgets('an arrow with no rows showing does not kill Enter', (
    tester,
  ) async {
    // THE BUG: `chicken` offers nothing, so no popover ever opened — but the
    // arrow still armed `_arrowed`, and Enter then tried to take a row from an
    // empty list forever.
    await tester.pumpWidget(host());
    await type(tester, 'chicken');
    expect(find.text('title:'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(navigations, ['q=chicken']);
  });

  testWidgets('taking tag: opens the tag list without another keystroke', (
    tester,
  ) async {
    // The feature's flagship two-step. RawAutocomplete's own selection
    // suppresses the refresh and hides the popover, so taking `tag:` used to
    // close the list — the user had to type a character to see their tags.
    await tester.pumpWidget(host(tags: ['dessert', 'main']));
    await type(tester, 'tag');
    await tester.tap(find.text('tag:'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'tag:');
    expect(find.text('dessert'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
  });

  testWidgets('a pre-filled query offers rows once the tags arrive', (
    tester,
  ) async {
    // THE BUG: the vocabulary lands in a setState, and RawAutocomplete only
    // recomputes rows on a TEXT change — so the results page, whose field is
    // pre-filled, offered nothing at all until the user typed. optionsBuilder
    // returns a Future while the fetch is in flight instead.
    await tester.pumpWidget(host(tags: ['dessert'], delay: slowFetch));
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'tag:des');
    await tester.pump(); // the fetch is still in flight
    await tester.pumpAndSettle(slowFetch);

    expect(
      find.text('dessert'),
      findsOneWidget,
      reason:
          'the row must appear when the vocabulary lands, not on the next '
          'keystroke',
    );
  });

  testWidgets('typing after arrowing un-chooses the row', (tester) async {
    await tester.pumpWidget(host());
    await type(tester, 't');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // Keep typing: the rows underneath changed, so nothing is chosen now and
    // Enter goes back to meaning "search what I typed".
    await type(tester, 'tomato');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(navigations, ['q=tomato']);
  });

  testWidgets('taking a tag row lifts it into a quoted chip', (tester) async {
    await tester.pumpWidget(host(tags: ['ice cream']));
    await type(tester, 'tag:ice');
    await tester.pumpAndSettle();

    expect(find.text('ice cream'), findsOneWidget);
    await tester.tap(find.text('ice cream'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(
      field.controller!.text,
      '',
      reason: 'the completed clause lifts out of the text into a chip',
    );
    expect(
      find.text('ice cream'),
      findsOneWidget,
      reason: 'the tag is now shown as a chip',
    );

    // The chip serializes with quoting: unquoted this would search tag:ice AND
    // the word cream. (encodeQueryComponent renders the space as `+`.)
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(navigations, ['q=tag%3A%22ice+cream%22']);
  });

  testWidgets('a completed clause becomes a chip on the trailing space', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    // Type the clause and a space; the space commits it to a chip.
    await type(tester, 'tag:dessert ');

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, '', reason: 'the clause left the text');
    expect(find.text('dessert'), findsOneWidget, reason: 'now a chip');
    expect(find.text('tag:'), findsOneWidget, reason: "the chip's scope label");

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(navigations, ['q=tag%3Adessert']);
  });

  testWidgets('a plain word does not become a chip', (tester) async {
    await tester.pumpWidget(host());
    await type(tester, 'chicken ');
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(
      field.controller!.text,
      'chicken ',
      reason: 'bare words stay as editable text',
    );
  });

  testWidgets('Backspace at the start pops the last chip back to text', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await type(tester, 'tag:dessert ');
    expect(find.text('dessert'), findsOneWidget);

    // Caret is at offset 0 of the now-empty editor; Backspace pops the chip.
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'tag:dessert');
    // The chip is gone (the text `tag:dessert` re-offers a `dessert` suggestion
    // row, which is why we assert on the chip widget, not the word).
    expect(find.byType(SearchChipView), findsNothing);
  });

  testWidgets('a pre-filled query seeds chips', (tester) async {
    await tester.pumpWidget(host(initialQuery: 'tag:dessert chicken'));
    await tester.pumpAndSettle();
    // The scoped clause is a chip; the bare word stays as text.
    expect(find.text('dessert'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'chicken');
  });

  testWidgets('a query with or is not chipped, it stays as text', (
    tester,
  ) async {
    await tester.pumpWidget(host(initialQuery: 'tag:dessert or tag:snack'));
    await tester.pumpAndSettle();
    expect(find.text('dessert'), findsNothing, reason: 'or → no chips');
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'tag:dessert or tag:snack');
  });

  testWidgets('a mid-query row lands the caret after the INSERT', (
    tester,
  ) async {
    // The caret contract only bites where option.cursor and query.length
    // DIFFER, and every other test here takes a row at the end of the field
    // where they coincide — so `_take` could ignore option.cursor entirely and
    // stay green. Splicing mid-query is what separates them.
    await tester.pumpWidget(host());
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    // Text change WITH the caret mid-string: what typing after a click does.
    final controller = tester
        .widget<TextField>(find.byType(TextField).first)
        .controller!;
    controller.value = const TextEditingValue(
      text: 'ta pie',
      selection: TextSelection.collapsed(offset: 2),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('tag:'));
    await tester.pumpAndSettle();

    expect(controller.text, 'tag: pie');
    expect(
      controller.selection.baseOffset,
      4,
      reason:
          'the caret belongs after `tag:`, ready for the value — not at '
          'the end of the query, past a word the user was not editing',
    );
  });

  testWidgets('resubmitting the query on screen refreshes in place', (
    tester,
  ) async {
    // The results page passes initialQuery + onSearchRefresh, because go() to
    // the location you are already on is a no-op. Enter now routes through
    // _onEnter, so this path runs through the new code and had no test.
    var refreshes = 0;
    await tester.pumpWidget(
      host(initialQuery: 'chicken', onRefresh: () => refreshes++),
    );
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(refreshes, 1, reason: 'the same query must reload, not navigate');
    expect(navigations, isEmpty);
  });

  testWidgets('an ordinary word offers no rows at all', (tester) async {
    await tester.pumpWidget(host());
    await type(tester, 'chicken');
    // Nothing to complete: searching must not be interrupted by a popover.
    expect(find.text('title:'), findsNothing);
    expect(find.text('dessert'), findsNothing);
  });

  testWidgets('suggestions survive the tags endpoint failing', (tester) async {
    await tester.pumpWidget(host(tags: const []));
    await type(tester, 't');
    // Keyword rows do not depend on the vocabulary.
    expect(find.text('title:'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(navigations, ['q=t']);
  });

  group('mobile search dialog (compact width)', () {
    // Below Breakpoints.compact (600) the inline field is dropped for an icon
    // that opens a dialog — the whole feature used to vanish there (#43).
    // Shrinking the view swaps in that entirely different widget tree.
    Future<void> openMobile(
      WidgetTester tester, {
      List<String> tags = const ['dessert', 'main'],
      Duration delay = Duration.zero,
      String? initialQuery,
      VoidCallback? onRefresh,
    }) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          tags: tags,
          delay: delay,
          initialQuery: initialQuery,
          onRefresh: onRefresh,
        ),
      );
      // The inline TextField is not built at this width; only the icon is.
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
    }

    testWidgets('the icon opens a dialog and typing offers keyword rows', (
      tester,
    ) async {
      await openMobile(tester);
      await tester.enterText(find.byType(TextField), 't');
      await tester.pumpAndSettle();
      expect(find.text('title:'), findsOneWidget);
      expect(find.text('tag:'), findsOneWidget);
    });

    testWidgets('tapping tag: reveals the tags without another keystroke', (
      tester,
    ) async {
      await openMobile(tester, tags: ['dessert', 'main']);
      await tester.enterText(find.byType(TextField), 'tag');
      await tester.pumpAndSettle();
      await tester.tap(find.text('tag:'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'tag:');
      expect(find.text('dessert'), findsOneWidget);
      expect(find.text('main'), findsOneWidget);
    });

    testWidgets('tapping a tag row makes a chip and does not search', (
      tester,
    ) async {
      await openMobile(tester, tags: ['ice cream']);
      await tester.enterText(find.byType(TextField), 'tag:ice');
      await tester.pumpAndSettle();
      await tester.tap(find.text('ice cream'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '', reason: 'the clause became a chip');
      expect(find.text('ice cream'), findsOneWidget, reason: 'shown as a chip');
      expect(
        navigations,
        isEmpty,
        reason: 'taking a row fills the field; it does not submit',
      );
    });

    testWidgets('the Search button submits the typed query', (tester) async {
      await openMobile(tester);
      await tester.enterText(find.byType(TextField), 'tag:dessert');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FButton, 'Search'));
      await tester.pumpAndSettle();
      expect(navigations, ['q=tag%3Adessert']);
    });

    testWidgets('a typed tag value offers matching rows', (tester) async {
      // A pre-filled `tag:des` now seeds as a chip, so drive the value by
      // typing instead; the row must appear for the typed value.
      await openMobile(tester, tags: ['dessert']);
      await tester.enterText(find.byType(TextField), 'tag:des');
      await tester.pumpAndSettle();
      expect(find.text('dessert'), findsOneWidget);
    });

    testWidgets('a pre-filled query seeds a chip', (tester) async {
      await openMobile(tester, initialQuery: 'tag:dessert');
      expect(find.text('dessert'), findsOneWidget, reason: 'seeded as a chip');
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '');
    });

    testWidgets('resubmitting the query on screen refreshes in place', (
      tester,
    ) async {
      var refreshes = 0;
      await openMobile(
        tester,
        initialQuery: 'chicken',
        onRefresh: () => refreshes++,
      );
      await tester.tap(find.widgetWithText(FButton, 'Search'));
      await tester.pumpAndSettle();
      expect(refreshes, 1, reason: 'the same query must reload, not navigate');
      expect(navigations, isEmpty);
    });

    testWidgets('an ordinary word offers no rows', (tester) async {
      await openMobile(tester);
      await tester.enterText(find.byType(TextField), 'chicken');
      await tester.pumpAndSettle();
      expect(find.text('title:'), findsNothing);
      expect(find.text('dessert'), findsNothing);
    });
  });
}

/// Serves a fixed tag list to TagsRepository.listTags().
class _TagsAdapter implements HttpClientAdapter {
  _TagsAdapter(this.tags, {this.delay = Duration.zero});

  final List<String> tags;

  /// Simulates a cold server: rows must arrive when the fetch does.
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
        '{"items":[${tags.map((t) => '{"name":"$t","count":7,"style":{}}').join(',')}]}',
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
