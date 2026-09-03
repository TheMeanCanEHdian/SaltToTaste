import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:salt_app/router/app_router.dart' show fadePageForTest;

/// The page transition contract.
///
/// This drives the app's real _fadePage (via fadePageForTest). An earlier
/// version of this file tested a LOCAL COPY and stayed green with the fix
/// deleted from the router — proving nothing.
///
/// It exists because the fade shipped DEAD and a browser check missed it.
/// A CustomTransitionPage with a null key makes `Page.canUpdate` true for any
/// two pages, so the Navigator updates the existing route in place instead of
/// pushing — and an updated route runs no transition. `context.push()` still
/// animates (it adds a second entry), which is exactly why eyeballing one
/// screen said "fine" while every `context.go()` — home -> search, the case
/// the feature was built for — did nothing.
///
/// So these tests assert on Navigator's push/remove events and on both pages
/// being on screen mid-transition, not on a screenshot.
void main() {
  // The app's REAL _fadePage, via its @visibleForTesting export. Not a copy:
  // a copy is what let the dead fade ship green.
  const fadePage = fadePageForTest;

  /// Records what the Navigator actually did.
  final events = <String>[];
  final observer = _RecordingObserver(events);

  GoRouter buildTestRouter({required bool withKey}) => GoRouter(
    initialLocation: '/',
    observers: [observer],
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => withKey
            ? fadePage(state, const Text('HOME'))
            : _keylessFadePage(const Text('HOME')),
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (context, state) => withKey
            ? fadePage(state, const Text('SEARCH'))
            : _keylessFadePage(const Text('SEARCH')),
      ),
    ],
  );

  testWidgets('go() cross-fades: both pages are on screen mid-transition', (
    tester,
  ) async {
    events.clear();
    final router = buildTestRouter(withKey: true);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    // Only the go() navigation is under test; drop the initial route's push.
    events.clear();

    router.go('/search');
    await tester.pump();
    // 90ms into a 180ms fade: the outgoing page must still be painted.
    await tester.pump(const Duration(milliseconds: 90));
    expect(
      find.text('HOME'),
      findsOneWidget,
      reason: 'the old page must still be on screen mid-fade',
    );
    expect(find.text('SEARCH'), findsOneWidget);
    expect(
      events,
      containsAll(<String>['push', 'remove']),
      reason: 'a real transition pushes a route; an in-place update does not',
    );

    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsNothing);
    expect(find.text('SEARCH'), findsOneWidget);
  });

  testWidgets('without state.pageKey the transition never runs', (
    tester,
  ) async {
    // Pins the bug itself: this is what shipped. If someone drops the key
    // again, the test above would keep passing on push() routes — this one
    // catches it.
    events.clear();
    final router = buildTestRouter(withKey: false);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    events.clear();

    router.go('/search');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(
      find.text('HOME'),
      findsNothing,
      reason:
          'a keyless page is reused in place, so HOME vanishes instantly — '
          'this is the dead-fade bug, asserted so it cannot come back unnoticed',
    );
    expect(events, isNot(contains('push')));
  });
  testWidgets('the real _fadePage names the tab after the route', (
    tester,
  ) async {
    final labels = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setApplicationSwitcherDescription') {
            labels.add((call.arguments as Map)['label'] as String);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => fadePage(state, const Text('HOME')),
        ),
        GoRoute(
          path: '/search',
          pageBuilder: (context, state) =>
              fadePage(state, const Text('SEARCH'), title: 'Search'),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(labels.last, 'Salt to Taste');

    router.go('/search');
    await tester.pumpAndSettle();
    expect(labels.last, 'Search · Salt to Taste');

    router.go('/');
    await tester.pumpAndSettle();
    expect(labels.last, 'Salt to Taste');
  });

  testWidgets('Back to a kept go_router page re-asserts its title', (
    tester,
  ) async {
    // push() adds a second route on top of the kept '/' page; pop() (what
    // browser Back does) uncovers it. go_router calls the pageBuilder again
    // on pop, but the route and its State are KEPT (one initState across the
    // round trip, asserted below), so the DocumentTitle only sees a same-
    // title didUpdateWidget. A build-time title — Flutter's own Title widget
    // — passes the go() pin above and fails this one: nothing but the route
    // becoming current again can put the name back.
    final labels = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setApplicationSwitcherDescription') {
            labels.add((call.arguments as Map)['label'] as String);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    var homeMounts = 0;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => fadePage(
            state,
            _MountCounter(
              onMount: () => homeMounts++,
              child: const Text('HOME'),
            ),
            title: 'Favorites',
          ),
        ),
        GoRoute(
          path: '/edit',
          pageBuilder: (context, state) =>
              fadePage(state, const Text('EDIT'), title: 'Edit recipe'),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(labels.last, 'Favorites · Salt to Taste');

    router.push('/edit');
    await tester.pumpAndSettle();
    expect(labels.last, 'Edit recipe · Salt to Taste');

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(
      homeMounts,
      1,
      reason:
          'pop must uncover the KEPT page (one initState across the round '
          'trip); a fresh mount would let a build-time title pass this pin',
    );
    expect(labels.last, 'Favorites · Salt to Taste');
  });
}

/// The broken shape, for the contrast test above. Do not use in the app.
Page<void> _keylessFadePage(Widget child) => CustomTransitionPage<void>(
  child: child,
  transitionDuration: const Duration(milliseconds: 180),
  transitionsBuilder: (context, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
);

/// Counts initState so a test can tell a kept route from a fresh mount.
class _MountCounter extends StatefulWidget {
  const _MountCounter({required this.onMount, required this.child});
  final VoidCallback onMount;
  final Widget child;

  @override
  State<_MountCounter> createState() => _MountCounterState();
}

class _MountCounterState extends State<_MountCounter> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _RecordingObserver extends NavigatorObserver {
  _RecordingObserver(this.events);

  final List<String> events;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      events.add('push');

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      events.add('remove');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      events.add('pop');
}
