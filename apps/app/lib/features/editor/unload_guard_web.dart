import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// The browser-level exit guard for a dirty editor (review B12).
///
/// Browser refresh, tab close, and window close never enter the Flutter
/// router, so [EditorExitGuard]'s discard dialog cannot see them — the one
/// leave path that silently dropped an arbitrarily large editing session.
/// The platform's only affordance for it is the native `beforeunload`
/// prompt: while [install]'s `shouldPrompt` returns true, leaving the page
/// asks first (browsers show their own generic wording; the returnValue
/// text is ignored). Mirrors the no-op `unload_guard_io.dart` off web.
class UnloadGuard {
  bool Function()? _shouldPrompt;
  JSFunction? _listener;

  /// Registers the `beforeunload` handler; [shouldPrompt] is consulted at
  /// unload time, so it can read live cubit state.
  void install(bool Function() shouldPrompt) {
    _shouldPrompt = shouldPrompt;
    final listener = ((web.BeforeUnloadEvent event) {
      if (_shouldPrompt?.call() ?? false) {
        event
          ..preventDefault()
          // Chrome additionally requires a non-empty returnValue.
          ..returnValue = 'unsaved';
      }
    }).toJS;
    _listener = listener;
    web.window.addEventListener('beforeunload', listener as web.EventListener);
  }

  /// Deregisters the handler (editor dispose).
  void remove() {
    final listener = _listener;
    if (listener != null) {
      web.window.removeEventListener('beforeunload', listener);
    }
    _listener = null;
    _shouldPrompt = null;
  }
}
