import 'dart:async';

import 'package:flutter/widgets.dart';

/// A route-exit guard the editor installs so the router's `GoRoute.onExit` can
/// ask the still-mounted editor whether it is safe to leave.
///
/// This exists because of a web fact: the browser Back button is a platform
/// history pop that reaches go_router through `setNewRoutePath` and fires
/// `onExit` — it never reaches `PopScope`. `onExit` runs with the ROOT
/// navigator context, above the editor's `BlocProvider`, so it cannot read the
/// editor's dirty state directly. The editor bridges that gap: it [install]s a
/// handler (which reads its own cubit and, if there are unsaved changes, shows
/// the discard-changes dialog) on mount and [remove]s it on dispose. Routing
/// every leave path — Back button, Cancel, browser Back, an in-app `go` — through
/// this one guard is what makes the confirmation consistent.
///
/// A list rather than a single slot so a stacked second editor is handled: the
/// top handler decides, and removing a lower one leaves the top intact.
class EditorExitGuard {
  final List<Future<bool> Function(BuildContext context)> _handlers = [];

  /// Registers [handler] as the active exit guard. Pass the SAME reference to
  /// [remove] on dispose.
  void install(Future<bool> Function(BuildContext context) handler) =>
      _handlers.add(handler);

  /// Deregisters [handler]. A no-op if it was already removed.
  void remove(Future<bool> Function(BuildContext context) handler) =>
      _handlers.remove(handler);

  /// Whether it is OK to leave the guarded route now. With no editor mounted
  /// (the common case) it is always true; otherwise the top-most editor decides
  /// — returning false keeps the user on the page.
  Future<bool> confirmExit(BuildContext context) async =>
      _handlers.isEmpty ? true : _handlers.last(context);
}
