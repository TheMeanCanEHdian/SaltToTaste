import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/settings/nutrition_tab.dart';

import 'support/contract_goldens.dart';

/// Serves the four endpoints the tab touches, driven by the committed
/// `nutrition_bulk_counts` golden: the counts preview, the FDC key status,
/// the scoped start (its 202 echoes the scope and the golden's count for
/// it), and the job poll.
class _Adapter implements HttpClientAdapter {
  _Adapter({Map<String, dynamic>? counts})
    : counts = counts ?? golden('nutrition_bulk_counts');

  /// The counts body — a test mutates it to stage the Stale=0 outcomes.
  Map<String, dynamic> counts;

  /// Served instead of [counts] once a job has been started — the numbers
  /// a sweep leaves behind, so the post-job re-fetch is observable.
  Map<String, dynamic>? countsAfterStart;

  /// Set to hold the counts answer back, for the loading state.
  Completer<void>? countsGate;

  /// What the job poll reports.
  String jobStatus = 'done';

  /// Overrides the 202's `total` (an out-of-date preview).
  int? startTotal;

  int countFetches = 0;
  int jobFetches = 0;

  /// Every POST body the tab sent to /nutrition/bulk.
  final List<Map<String, dynamic>> posts = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    final method = options.method;
    Object? body;
    var status = 200;
    if (method == 'GET' && path == '/api/v1/nutrition/bulk/counts') {
      countFetches += 1;
      await countsGate?.future;
      body = posts.isEmpty ? counts : (countsAfterStart ?? counts);
    } else if (method == 'GET' && path == '/api/v1/settings/fdc_key') {
      body = {'configured': true, 'masked': '••••7f2a'};
    } else if (method == 'POST' && path == '/api/v1/nutrition/bulk') {
      final sent = Map<String, dynamic>.from(options.data as Map);
      posts.add(sent);
      final scope = sent['scope'];
      status = 202;
      body = {
        'job_id': 7,
        'scope': scope,
        'total': startTotal ?? counts[scope],
      };
    } else if (method == 'GET' && path == '/api/v1/nutrition/jobs/7') {
      jobFetches += 1;
      final total = counts[posts.last['scope']]! as int;
      body = {
        'id': 7,
        'status': jobStatus,
        'total': total,
        'done': jobStatus == 'done' ? total : 0,
        'failed': 0,
        'log': <String>[],
      };
    } else {
      throw StateError('unexpected $method $path');
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final raw = golden('nutrition_bulk_counts');
  final missing = raw['missing']! as int;
  final stale = raw['stale']! as int;
  final all = raw['all']! as int;

  /// [settle] is false for a mount that re-attaches to a RUNNING job: the
  /// spinning button is an endless animation, so pumpAndSettle can never
  /// return and the caller pumps by hand instead.
  Future<_Adapter> open(
    WidgetTester tester, {
    _Adapter? adapter,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final served = adapter ?? _Adapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://contract'))
      ..httpClientAdapter = served;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaterialTheme(buildForuiTheme()),
        builder: (context, child) =>
            FTheme(data: buildForuiTheme(), child: child!),
        home: RepositoryProvider<NutritionRepository>.value(
          value: NutritionRepository(dio),
          child: const Scaffold(
            body: SingleChildScrollView(child: NutritionTab()),
          ),
        ),
      ),
    );
    // The adapter answers asynchronously; settle so the key status and the
    // counts preview have both landed (a held-back counts gate stays open).
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    return served;
  }

  /// The compute button (the only outline FButton with a compute label).
  FButton computeButton(WidgetTester tester) => tester.widget<FButton>(
    find.ancestor(
      of: find.textContaining(RegExp(r'^(Compute|Recompute) ')),
      matching: find.byType(FButton),
    ),
  );

  const staleHint =
      'Recipes whose ingredient lines changed since their last compute — '
      'the ones showing the amber “ingredients changed” banner. Your '
      'confirmed and overridden matches are kept; only unreviewed and '
      'changed lines are re-resolved.';
  const missingHint =
      'Recipes with no nutrition yet. Throttled to ~900 requests/hour — a '
      'large first run takes a while and resumes rate-limiting '
      'automatically.';
  const nothingStale =
      'Nothing is stale — every computed recipe still matches its '
      'ingredients.';

  testWidgets('the golden counts render on the segments', (tester) async {
    await open(tester);
    expect(find.text('Compute nutrition'), findsOneWidget);
    expect(find.text('Missing'), findsOneWidget);
    expect(find.text('Stale'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('$missing'), findsWidgets);
    expect(find.text('$stale'), findsWidgets);
    expect(find.text('$all'), findsWidgets);
    // Missing is the default: today's behaviour, its label and hint.
    expect(find.text('Compute $missing missing'), findsOneWidget);
    expect(find.text(missingHint), findsOneWidget);
    expect(find.byIcon(FLucideIcons.zap), findsOneWidget);
    expect(computeButton(tester).onPress, isNotNull);
  });

  testWidgets('selecting Stale changes the label, icon and hint', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Stale'));
    await tester.pumpAndSettle();
    expect(find.text('Recompute $stale stale'), findsOneWidget);
    expect(find.text(staleHint), findsOneWidget);
    expect(find.text(missingHint), findsNothing);
    expect(find.byIcon(FLucideIcons.refreshCw), findsOneWidget);
    expect(find.byIcon(FLucideIcons.zap), findsNothing);
  });

  testWidgets('Stale at 0 disables the button and shows the banner', (
    tester,
  ) async {
    final adapter = _Adapter(counts: {...raw, 'stale': 0});
    await open(tester, adapter: adapter);
    await tester.tap(find.text('Stale'));
    await tester.pumpAndSettle();
    expect(find.text('Recompute 0 stale'), findsOneWidget);
    expect(find.text(nothingStale), findsOneWidget);
    expect(find.byIcon(FLucideIcons.check), findsOneWidget);
    expect(computeButton(tester).onPress, isNull);
    expect(find.text(staleHint), findsNothing);
  });

  testWidgets('All confirms inline and posts only on Start anyway', (
    tester,
  ) async {
    final adapter = await open(tester);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Recompute all $all'), findsOneWidget);
    expect(find.text('This re-resolves every recipe'), findsNothing);

    await tester.tap(find.text('Recompute all $all'));
    await tester.pumpAndSettle();
    expect(find.text('This re-resolves every recipe'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.triangleAlert), findsOneWidget);
    expect(find.textContaining('several hours of FoodData'), findsOneWidget);
    expect(adapter.posts, isEmpty, reason: 'the confirm gates the start');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('This re-resolves every recipe'), findsNothing);
    expect(adapter.posts, isEmpty);

    await tester.tap(find.text('Recompute all $all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start anyway'));
    await tester.pumpAndSettle();
    expect(adapter.posts, [
      {'scope': 'all'},
    ]);
    expect(find.text('This re-resolves every recipe'), findsNothing);
    expect(find.text('All $all recipes recomputed.'), findsOneWidget);
  });

  testWidgets('the selected scope is what gets posted', (tester) async {
    final adapter = await open(tester);
    await tester.tap(find.text('Compute $missing missing'));
    await tester.pumpAndSettle();
    expect(adapter.posts, [
      {'scope': 'missing'},
    ]);
    expect(find.text('All $missing missing recipes computed.'), findsOneWidget);

    await tester.tap(find.text('Stale'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recompute $stale stale'));
    await tester.pumpAndSettle();
    expect(adapter.posts.last, {'scope': 'stale'});
  });

  testWidgets('a finished job re-fetches the counts and names its scope', (
    tester,
  ) async {
    final adapter = await open(tester);
    expect(adapter.countFetches, 1, reason: 'loaded once when the tab opens');
    await tester.tap(find.text('Stale'));
    await tester.pumpAndSettle();
    // The sweep leaves nothing stale: the re-fetch must show that.
    adapter.countsAfterStart = {...raw, 'stale': 0};
    await tester.tap(find.text('Recompute $stale stale'));
    await tester.pumpAndSettle();
    expect(adapter.countFetches, 2);
    expect(find.text('All $stale stale recipes recomputed.'), findsOneWidget);
    expect(find.text('Recompute 0 stale'), findsOneWidget);
    // One green message, not two: the summary stands in for the idle banner.
    expect(find.text(nothingStale), findsNothing);
    expect(computeButton(tester).onPress, isNull);
  });

  testWidgets('the control is disabled while a job runs', (tester) async {
    final adapter = _Adapter()..jobStatus = 'running';
    await open(tester, adapter: adapter);
    // The running button spins (an endless animation), so settle by hand.
    Future<void> pumpABit() async {
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.tap(find.text('Compute $missing missing'));
    await pumpABit();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.text('All'));
    await pumpABit();
    expect(
      find.text('Compute $missing missing'),
      findsOneWidget,
      reason: 'one bulk job at a time — the scope cannot change mid-run',
    );
    expect(computeButton(tester).onPress, isNull);

    // Let the 2s poll see the job finish: the control comes back and the
    // tab forgets the job (which the next test's fresh mount relies on).
    adapter.jobStatus = 'done';
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('All $missing missing recipes computed.'), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Recompute all $all'), findsOneWidget);
  });

  testWidgets('a remounted tab re-attaches to the running job AND its scope', (
    tester,
  ) async {
    // A tab switch disposes this widget while the job keeps running
    // server-side; the remount re-attaches by job id. It used to restore
    // only the summary's scope, so a Stale sweep in flight came back with
    // Missing selected and a spinning "Compute N missing" — the mockup's
    // Running card keeps the job's scope selected.
    final adapter = _Adapter()..jobStatus = 'running';
    await open(tester, adapter: adapter);
    Future<void> pumpABit() async {
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.tap(find.text('Stale'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recompute $stale stale'));
    await pumpABit();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Remount: a fresh widget tree, same process-wide job bookkeeping.
    // pumpWidget with an IDENTICAL tree updates the live State in place and
    // never runs initState, so the old _scope would simply survive and this
    // would pin nothing. Dispose it for real first.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await open(tester, adapter: adapter, settle: false);
    await pumpABit();
    expect(
      find.text('Recompute $stale stale'),
      findsOneWidget,
      reason: 'the running job is a Stale sweep; the control must say so',
    );
    expect(find.text('Compute $missing missing'), findsNothing);
    expect(computeButton(tester).onPress, isNull);

    // Let the job finish so the next test's fresh mount does not re-attach.
    adapter.jobStatus = 'done';
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('segments show no count while the preview loads', (tester) async {
    final adapter = _Adapter()..countsGate = Completer<void>();
    await open(tester, adapter: adapter);
    expect(find.text('Compute missing'), findsOneWidget);
    expect(find.text('$missing'), findsNothing);
    expect(find.text('0'), findsNothing, reason: 'never a false zero');
    await tester.tap(find.text('Stale'));
    await tester.pumpAndSettle();
    expect(find.text('Recompute stale'), findsOneWidget);
    expect(find.text(nothingStale), findsNothing);
    expect(computeButton(tester).onPress, isNotNull);

    adapter.countsGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Recompute $stale stale'), findsOneWidget);
  });

  testWidgets('a 202 with total 0 refreshes the counts instead of polling', (
    tester,
  ) async {
    final adapter = _Adapter()
      ..startTotal = 0
      ..countsAfterStart = {...raw, 'stale': 0};
    await open(tester, adapter: adapter);
    await tester.tap(find.text('Stale'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recompute $stale stale'));
    await tester.pumpAndSettle();
    expect(adapter.posts, [
      {'scope': 'stale'},
    ]);
    expect(adapter.jobFetches, 0);
    expect(adapter.countFetches, 2);
    expect(find.text(nothingStale), findsOneWidget);
  });
}
