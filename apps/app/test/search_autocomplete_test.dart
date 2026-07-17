import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/core/api/auth_repository.dart';
import 'package:salt_app/core/api/tags_repository.dart';
import 'package:salt_app/core/widgets/salt_nav_bar.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';

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
  }) {
    navigations = [];
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _TagsAdapter(tags, delay: delay);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(appBar: SaltNavBar(), body: SizedBox()),
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
        child: MaterialApp.router(routerConfig: router),
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

  testWidgets('a real tag is offered after tag: and splices in quoted', (
    tester,
  ) async {
    await tester.pumpWidget(host(tags: ['ice cream']));
    await type(tester, 'tag:ice');
    await tester.pumpAndSettle();

    expect(find.text('ice cream'), findsOneWidget);
    await tester.tap(find.text('ice cream'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(
      field.controller!.text,
      'tag:"ice cream" ',
      reason: 'unquoted, this would search tag:ice AND the word cream',
    );
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
