import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/app.dart';

void main() {
  // Clean path URLs on web (`/r/<slug>` instead of `/#/r/<slug>`); a no-op
  // on other platforms.
  usePathUrlStrategy();
  // Make imperative navigation reflect in the browser URL (web only). go_router
  // defaults this OFF, so `context.push('/r/<slug>')` — how nearly every
  // drill-down here navigates (recipe cards, the avatar menu, edit) — left the
  // address bar frozen at wherever the last `context.go()` landed. With it on,
  // a pushed route updates the URL and gets its own history entry, so the URL
  // tracks the page and the browser Back button pops correctly (which is why
  // the in-app back control is dropped on web).
  GoRouter.optionURLReflectsImperativeAPIs = true;
  runApp(const SaltApp());
}
