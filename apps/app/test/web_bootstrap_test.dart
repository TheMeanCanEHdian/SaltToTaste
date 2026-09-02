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
  group('declared icons exist and are what they claim to be', () {
    // web/favicon.png held real ICO bytes and was declared image/png. The tab
    // icon still looked right -- browsers sniff -- so the only symptom was a
    // 404 on the automatic /favicon.ico probe, once per page load, which is
    // invisible unless someone reads the access log. A wrong declared type is
    // exactly the kind of thing nothing else in this build checks.
    final magic = <String, List<int>>{
      // ICO: reserved=0, type=1 (icon).
      '.ico': [0x00, 0x00, 0x01, 0x00],
      // PNG signature.
      '.png': [0x89, 0x50, 0x4E, 0x47],
    };

    test('every <link rel="icon"> href resolves to a file', () {
      final html = File('web/index.html').readAsStringSync();
      final links = RegExp(
        r'''<link\s+rel="icon"[^>]*href="([^"]+)"''',
      ).allMatches(html).map((m) => m.group(1)!).toList();
      expect(links, isNotEmpty, reason: 'no icon links found to check');
      for (final href in links) {
        expect(
          File('web/$href').existsSync(),
          isTrue,
          reason: '<link rel="icon" href="$href"> points at nothing',
        );
      }
    });

    test('the automatic /favicon.ico probe finds a real ICO', () {
      // Browsers request this whether or not it is declared, so the name is
      // not ours to choose.
      final ico = File('web/favicon.ico');
      expect(ico.existsSync(), isTrue, reason: '/favicon.ico will 404');
      expect(
        ico.readAsBytesSync().take(4),
        magic['.ico'],
        reason: 'favicon.ico is not ICO-formatted',
      );
    });

    test('each icon href declares the type its bytes actually are', () {
      final html = File('web/index.html').readAsStringSync();
      final links = RegExp(
        r'''<link\s+rel="icon"\s+type="([^"]+)"\s+href="([^"]+)"''',
      ).allMatches(html);
      const expectedFor = {
        'image/x-icon': '.ico',
        'image/vnd.microsoft.icon': '.ico',
        'image/png': '.png',
      };
      for (final m in links) {
        final declared = m.group(1)!;
        final href = m.group(2)!;
        final wantExt = expectedFor[declared];
        if (wantExt == null) continue; // svg and friends: nothing to sniff
        expect(
          href.endsWith(wantExt),
          isTrue,
          reason: '$href is declared $declared but is not a $wantExt',
        );
        expect(
          File('web/$href').readAsBytesSync().take(4),
          magic[wantExt],
          reason: '$href is declared $declared, bytes say otherwise',
        );
      }
    });
  });

}
