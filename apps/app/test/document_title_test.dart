import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/widgets/document_title.dart';

/// The tab-title contract: the CURRENT page names the tab, a covered page
/// keeps quiet, and coming back re-asserts the page underneath.
///
/// Flutter's [Title] only speaks when it builds, so a page returned to by
/// Back kept the title of the page that was just popped. That is the case
/// the pop test pins, and the one a build-time widget cannot pass.
void main() {
  late List<String> labels;

  setUp(() {
    labels = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setApplicationSwitcherDescription') {
            labels.add((call.arguments as Map)['label'] as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('a page names the tab; null is the bare app name', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DocumentTitle(title: 'Favorites', child: SizedBox()),
      ),
    );
    expect(labels.last, 'Favorites · Salt to Taste');

    await tester.pumpWidget(
      const MaterialApp(home: DocumentTitle(child: SizedBox())),
    );
    expect(labels.last, 'Salt to Taste');
  });

  testWidgets('a covered page stays quiet; Back re-asserts it', (tester) async {
    final underneath = ValueNotifier<String>('Bundt Cake');
    addTearDown(underneath.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: ValueListenableBuilder<String>(
          valueListenable: underneath,
          builder: (context, title, _) =>
              DocumentTitle(title: title, child: const SizedBox()),
        ),
      ),
    );
    expect(labels.last, 'Bundt Cake · Salt to Taste');

    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            const DocumentTitle(title: 'Edit recipe', child: SizedBox()),
      ),
    );
    await tester.pumpAndSettle();
    expect(labels.last, 'Edit recipe · Salt to Taste');

    // The page underneath re-renders with a new name while covered: the
    // top page's title must stand.
    underneath.value = 'Bundt Cake (Weeknight)';
    await tester.pump();
    expect(
      labels.last,
      'Edit recipe · Salt to Taste',
      reason: 'a page that is not current must not name the tab',
    );

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(
      labels.last,
      'Bundt Cake (Weeknight) · Salt to Taste',
      reason: 'Back must re-assert the page underneath, with its current name',
    );
  });

  testWidgets('a title change on the current page renames the tab', (
    tester,
  ) async {
    final title = ValueNotifier<String?>(null);
    addTearDown(title.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<String?>(
          valueListenable: title,
          builder: (context, value, _) =>
              DocumentTitle(title: value, child: const SizedBox()),
        ),
      ),
    );
    expect(labels.last, 'Salt to Taste');
    title.value = 'Rich Chocolate Bundt Cake';
    await tester.pump();
    expect(labels.last, 'Rich Chocolate Bundt Cake · Salt to Taste');
  });
}
