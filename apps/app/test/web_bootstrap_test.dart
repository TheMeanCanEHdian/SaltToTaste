// The custom `web/flutter_bootstrap.js` carries two deliberate opt-outs that
// nothing else in the build enforces, and both fail SILENTLY if the file is
// ever regenerated (a `flutter create`, an SDK upgrade, or anyone following
// Flutter's "delete it and let us generate one" advice).
//
// These are file-content assertions rather than behavioural ones on purpose:
// the bootstrap is a build-time template, so there is no widget to pump and
// no runtime seam to observe. The value is the tripwire, not the mechanism.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String bootstrap;

  setUpAll(() {
    final file = File('web/flutter_bootstrap.js');
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'the custom bootstrap is gone — Flutter will generate a default one '
          'that registers a service worker AND resolves engine fonts against '
          'fonts.gstatic.com',
    );
    bootstrap = file.readAsStringSync();
  });

  test('engine font fallbacks resolve to this server, not Google', () {
    // Flutter web's engine defaults fontFallbackBaseUrl to
    // https://fonts.gstatic.com/s/ and fetches its default face on EVERY load,
    // even though this app renders entirely in bundled fonts. Self-hosted
    // means self-hosted: no third party learns who is reading recipes.
    expect(
      bootstrap,
      contains('fontFallbackBaseUrl'),
      reason: 'without this the engine calls fonts.gstatic.com on every load',
    );
    final value = RegExp(
      r'''fontFallbackBaseUrl\s*:\s*["']([^"']*)["']''',
    ).firstMatch(bootstrap)?.group(1);
    expect(value, isNotNull, reason: 'fontFallbackBaseUrl has no string value');
    expect(
      Uri.parse(value!).hasScheme,
      isFalse,
      reason: 'must be a relative (same-origin) base, not an absolute URL',
    );
  });

  test('the font the engine derives from that base is actually served', () {
    // The engine builds this exact path from the base URL (a lazy static in
    // the compiled engine). The name is the ENGINE's; the bytes are a TTF —
    // see web/fallback-fonts/README.md. If the base and the file ever
    // disagree the only symptom is a 404 per page load, which is precisely
    // the kind of thing nobody notices.
    final base = RegExp(
      r'''fontFallbackBaseUrl\s*:\s*["']([^"']*)["']''',
    ).firstMatch(bootstrap)!.group(1)!;
    final expected = File(
      'web/$base' 'roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2',
    );
    expect(
      expected.existsSync(),
      isTrue,
      reason: 'engine will request ${expected.path} and get a 404',
    );
    expect(expected.lengthSync(), greaterThan(1000), reason: 'not a stub');
  });

  test('no service worker is registered', () {
    // Flutter's offline-first worker serves the previously cached bundle on
    // the first load after a deploy, so an upgraded self-hosted server keeps
    // handing visitors the old app. Passing no serviceWorkerSettings to
    // load() is the supported opt-out.
    // Scoped to the CALL, not the file: the comment above it explains the
    // opt-out by naming `serviceWorkerSettings`, so a whole-file match reads
    // the prose and passes for the wrong reason. (It did, first try.)
    final call = bootstrap.substring(
      bootstrap.indexOf('_flutter.loader.load('),
    );
    expect(
      call,
      isNot(contains('serviceWorkerSettings')),
      reason: 'a registered worker serves a stale bundle after every upgrade',
    );
  });
}
