import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/app.dart';

void main() {
  // Clean path URLs on web (`/r/<slug>` instead of `/#/r/<slug>`); a no-op
  // on other platforms. The `includeHash: true` (the 2nd positional arg) keeps
  // the URL FRAGMENT on a cold load — `usePathUrlStrategy()` hardcodes it OFF,
  // which drops the `#` so a deep link like `/settings#import` would open the
  // default tab instead of Import. Fragment routing (settings tabs) needs it.
  setUrlStrategy(PathUrlStrategy(BrowserPlatformLocation(), true));
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
