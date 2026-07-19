import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salt_app/app.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  // Warm the brand-mark SVG before first paint so it doesn't visibly pop in on
  // the login card / nav bar (white) or the recipe photo placeholders (rose —
  // a fresh grid can show dozens at once). The cache key includes the tint, so
  // each colour is warmed separately. Best-effort AND time-boxed: on web this
  // is a network fetch, and a slow/stalled one must never hold the app on the
  // boot screen — cap the wait and proceed (an un-warmed mark just falls back
  // to the normal async load). A thrown failure (e.g. 404) is likewise
  // swallowed.
  try {
    await Future.wait([
      SaltLogoGlyph.precache(),
      SaltLogoGlyph.precache(SaltColors.rose),
    ]).timeout(const Duration(milliseconds: 600));
  } catch (_) {}
  // Read the stored prefs (the list layout) before first paint so the choice
  // is applied synchronously. Best-effort: a failure just means the in-memory
  // default (grid) with no persistence this session.
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {}
  runApp(SaltApp(prefs: prefs));
}
