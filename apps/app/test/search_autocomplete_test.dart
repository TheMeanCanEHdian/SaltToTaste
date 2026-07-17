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
  late List<String> navigations;

  Widget host({List<String> tags = const ['dessert', 'main']}) {
    navigations = [];
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _TagsAdapter(tags);
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
  _TagsAdapter(this.tags);

  final List<String> tags;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? __,
  ) async {
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
