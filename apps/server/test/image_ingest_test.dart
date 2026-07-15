import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/services/image_ingest.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';

/// P5 image-ingest tests: magic-byte sniffing against a real corpus photo,
/// the streaming size cap, server-generated names, and the SSRF guards
/// (private/loopback hosts are rejected before any connection is made).
void main() {
  late Directory tempDir;
  late ServerConfig config;
  late Uint8List heroJpeg;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('salt-image-test');
    config = ServerConfig(
      dataDir: tempDir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    );
    heroJpeg = File(
      '$corpusImagesDir/0857-rich-chocolate-bundt-cake-hero.jpg',
    ).readAsBytesSync();
  });

  tearDownAll(() => tempDir.deleteSync(recursive: true));

  group('sniffImage', () {
    test('identifies a real corpus JPEG', () {
      final sniffed = sniffImage(heroJpeg);
      expect(sniffed, isNotNull);
      expect(sniffed!.extension, 'jpg');
      expect(sniffed.mimeType, 'image/jpeg');
    });

    test('identifies PNG and WebP signatures', () {
      // Synthesized headers: negative/limits inputs that cannot come from
      // the corpus (it only ships JPEGs).
      final png = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0,
      ]);
      expect(sniffImage(png)?.extension, 'png');
      final webp = Uint8List.fromList([
        ...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits,
      ]);
      expect(sniffImage(webp)?.extension, 'webp');
    });

    test('rejects a YAML file posing as an image', () {
      final yamlBytes = File(
        '$corpusRecipesDir/0857-rich-chocolate-bundt-cake.yaml',
      ).readAsBytesSync();
      expect(sniffImage(yamlBytes), isNull);
    });
  });

  test('collectImageBytes enforces the cap while streaming', () async {
    final oversized = Stream<List<int>>.fromIterable([
      for (var i = 0; i <= maxImageBytes ~/ heroJpeg.length + 1; i += 1)
        heroJpeg,
    ]);
    await expectLater(
      collectImageBytes(oversized),
      throwsA(isA<ValidationException>()),
    );
  });

  test('saveRecipeImage stores under a server-generated safe name', () {
    final reference = saveRecipeImage(
      config: config,
      sourceSlug: 'my-recipes',
      recipeId: 'manual-20260715-test-recipe',
      bytes: heroJpeg,
    );
    expect(reference, startsWith('images/manual-20260715-test-recipe-'));
    expect(reference, endsWith('.jpg'));
    final stored = File('${config.libraryDir}/my-recipes/$reference');
    expect(stored.existsSync(), isTrue);
    expect(stored.lengthSync(), heroJpeg.length);
  });

  test('saveRecipeImage rejects non-image bytes', () {
    expect(
      () => saveRecipeImage(
        config: config,
        sourceSlug: 'my-recipes',
        recipeId: 'manual-20260715-test-recipe',
        bytes: Uint8List.fromList('not an image'.codeUnits),
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  group('fetchImageFromUrl SSRF guards', () {
    // Crafted hostile URLs: negative-path inputs that cannot come from the
    // corpus. Each must be rejected by validation before any socket opens.
    const rejected = [
      'ftp://example.com/a.jpg',
      'file:///etc/passwd',
      'http://user:pass@example.com/a.jpg',
      'http://127.0.0.1/a.jpg',
      'http://localhost/a.jpg',
      'http://0.0.0.0/a.jpg',
      'http://10.1.2.3/a.jpg',
      'http://172.16.0.1/a.jpg',
      'http://192.168.1.10/a.jpg',
      'http://169.254.169.254/latest/meta-data',
      'http://100.64.0.1/a.jpg',
      'http://[::1]/a.jpg',
      'http://[fd00::1]/a.jpg',
      'http://[fe80::1]/a.jpg',
      'http://[::ffff:127.0.0.1]/a.jpg',
      'http://[::ffff:10.0.0.1]/a.jpg',
      'not a url at all',
    ];
    for (final url in rejected) {
      test('rejects $url', () async {
        await expectLater(
          fetchImageFromUrl(url),
          throwsA(isA<ValidationException>()),
        );
      });
    }
  });
}
