import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/features/search/search_chip_box.dart';

void main() {
  Widget host({
    required List<SearchChip> chips,
    required TextEditingController controller,
    required FocusNode focus,
    required ScrollController scroll,
    double width = 400,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: Container(
              height: 38,
              color: Colors.white,
              child: SearchChipBox(
                chips: chips,
                controller: controller,
                focusNode: focus,
                scrollController: scroll,
                onRemoveChip: (_) {},
                onKeyEvent: (_, __) => KeyEventResult.ignored,
                onSubmitted: (_) {},
                hintText: 'Search recipes',
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('tapping the empty tail focuses the editor', (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    final scroll = ScrollController();
    addTearDown(() {
      controller.dispose();
      focus.dispose();
      scroll.dispose();
    });

    await tester.pumpWidget(
      host(chips: const [], controller: controller, focus: focus, scroll: scroll),
    );
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byType(SearchChipBox));
    // Tap the far right of the (wide) field, well past the content-width editor.
    await tester.tapAt(Offset(box.right - 15, box.center.dy));
    await tester.pump();

    expect(
      focus.hasFocus,
      isTrue,
      reason: 'tapping the empty tail must focus the field',
    );
  });

  testWidgets('renders chips + editor without overflow in a fixed-height bar', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    final scroll = ScrollController();
    addTearDown(() {
      controller.dispose();
      focus.dispose();
      scroll.dispose();
    });

    // More chips than fit — the row must scroll, not overflow the 38px height.
    final chips = [
      for (final raw in ['tag:dessert', 'title:pork', 'calories:<400', 'note:x'])
        parseSearchInput(raw).chips.single,
    ];
    await tester.pumpWidget(
      host(chips: chips, controller: controller, focus: focus, scroll: scroll),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SearchChipView), findsNWidgets(4));
    // The bar stays exactly one line tall.
    expect(tester.getSize(find.byType(SearchChipBox)).height, 38);
  });
}
