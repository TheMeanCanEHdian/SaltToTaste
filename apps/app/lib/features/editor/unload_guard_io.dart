/// Non-web stub of the browser beforeunload guard — desktop/mobile builds
/// have no browser tab to close out from under a dirty editor. Mirrors
/// `unload_guard_web.dart` (review B12).
class UnloadGuard {
  /// No-op off web.
  void install(bool Function() shouldPrompt) {}

  /// No-op off web.
  void remove() {}
}
