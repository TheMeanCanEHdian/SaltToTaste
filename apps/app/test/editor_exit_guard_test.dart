import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/features/editor/editor_exit_guard.dart';

/// The exit guard the editor installs so go_router's `onExit` — the ONLY hook a
/// browser Back button reaches on web — can ask the still-mounted editor whether
/// it is safe to leave. The handlers under test ignore the context, so a single
/// real one (from a pumped widget) is threaded through every case.
void main() {
  Future<bool> allow(BuildContext _) async => true;
  Future<bool> block(BuildContext _) async => false;

  testWidgets('guards resolve as installed', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox();
        },
      ),
    );

    final guard = EditorExitGuard();

    // With no editor mounted, leaving is always allowed.
    expect(await guard.confirmExit(ctx), isTrue);

    // The installed handler decides.
    guard.install(block);
    expect(await guard.confirmExit(ctx), isFalse);

    // Removing it restores the always-allow default.
    guard.remove(block);
    expect(await guard.confirmExit(ctx), isTrue);

    // Stacked editors: the top-most handler wins; popping it hands back down.
    guard
      ..install(allow) // lower editor
      ..install(block); // top editor
    expect(await guard.confirmExit(ctx), isFalse);
    guard.remove(block);
    expect(await guard.confirmExit(ctx), isTrue);

    // Removing a never-installed handler is a harmless no-op.
    guard
      ..remove(allow)
      ..install(block)
      ..remove(allow);
    expect(await guard.confirmExit(ctx), isFalse);
  });
}
