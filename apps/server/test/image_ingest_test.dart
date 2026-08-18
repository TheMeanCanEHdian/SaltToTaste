import 'dart:io';
import 'dart:isolate';
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
///
/// Only the tests that READ corpus files sit behind the corpus gate — the
/// URL-guard, signature, and cap regression pins run everywhere, CI
/// included. A whole-file gate once skipped all of them there (review T1).
/// The one real photo committed to this repo (the legacy-v0 importer
/// fixture kept at the P8 cutover) — real JPEG bytes for the tests that need
/// them without the external corpus, so they run in CI too.
const String _fixtureImage =
    'test/fixtures/legacy-v0/_images/brown-butter-gemelli-with-asparagus,'
    '-walnuts,-and-lemony-ricotta.jpg';

void main() {
  late Directory tempDir;
  late ServerConfig config;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('salt-image-test');
    config = ServerConfig(
      dataDir: tempDir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    );
  });

  tearDownAll(() => tempDir.deleteSync(recursive: true));

  test('sniffImage identifies PNG and WebP signatures', () {
    // Synthesized headers: negative/limits inputs that cannot come from
    // the corpus (it only ships JPEGs).
    final png = Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0,
      0,
      0,
      0,
    ]);
    expect(sniffImage(png)?.extension, 'png');
    final webp = Uint8List.fromList([
      ...'RIFF'.codeUnits,
      0,
      0,
      0,
      0,
      ...'WEBP'.codeUnits,
    ]);
    expect(sniffImage(webp)?.extension, 'webp');
  });

  test('collectImageBytes enforces the cap while streaming', () async {
    // A synthetic filler chunk: this is a size-limits input (content never
    // matters to the cap), which the corpus cannot produce.
    final chunk = Uint8List(1024 * 1024);
    final oversized = Stream<List<int>>.fromIterable([
      for (var i = 0; i <= maxImageBytes ~/ chunk.length + 1; i += 1) chunk,
    ]);
    await expectLater(
      collectImageBytes(oversized),
      throwsA(isA<ValidationException>()),
    );
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

  test('concurrent saves for one recipe never clobber each other', () async {
    // The lost-write race (2026-07-28 review, item 5) needs two writers, and
    // `saveRecipeImage` is synchronous — nothing inside one isolate can
    // interleave with it — so reproducing it takes real isolates on one
    // library directory, which is also the shipped shape (a second replica
    // on the same volume). Every writer saves under the SAME recipe id in
    // the same second, so every save computes the same `<id>-<stamp>`
    // prefix: exactly the input the old scan-for-the-first-free-name
    // mishandled, both for `<name>.tmp` and for the rename target.
    const writers = 4;
    const perWriter = 15;
    final raceDir = Directory.systemTemp.createTempSync('salt-image-race');
    addTearDown(() => raceDir.deleteSync(recursive: true));
    final dataDir = raceDir.path;
    final bytes = File(_fixtureImage).readAsBytesSync();
    // A shared start instant, so the writers overlap instead of queueing
    // behind each other's isolate spawn.
    final startAt = DateTime.now()
        .add(const Duration(milliseconds: 300))
        .microsecondsSinceEpoch;

    final saved = await Future.wait([
      for (var writer = 0; writer < writers; writer += 1)
        Isolate.run(() async {
          final until = DateTime.fromMicrosecondsSinceEpoch(startAt);
          while (DateTime.now().isBefore(until)) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
          return [
            for (var i = 0; i < perWriter; i += 1)
              saveRecipeImage(
                config: ServerConfig(
                  dataDir: dataDir,
                  logLevel: Level.WARNING,
                  trustProxy: false,
                ),
                sourceSlug: 'my-recipes',
                recipeId: 'manual-20260715-race',
                bytes: bytes,
              ),
          ];
        }),
    ]);

    final references = saved.expand((refs) => refs).toList();
    expect(references, hasLength(writers * perWriter));
    expect(
      references.toSet(),
      hasLength(writers * perWriter),
      reason: 'two writers were handed the same stored filename',
    );
    for (final reference in references) {
      expect(
        File('$dataDir/library/my-recipes/$reference').readAsBytesSync(),
        bytes,
        reason: '$reference is not the photo its saver stored',
      );
    }
  });

  group('creditUrl keeps a credential out of the stored credit', () {
    // Crafted URLs: a presigned download URL is a negative-path input the
    // recipe corpus cannot supply.
    test('drops the query string a presigned URL signs with', () {
      expect(
        creditUrl(
          'https://bucket.s3.amazonaws.com/photos/hero.jpg'
          '?X-Amz-Signature=deadbeefdeadbeef&X-Amz-Expires=900',
        ),
        'https://bucket.s3.amazonaws.com/photos/hero.jpg',
      );
    });

    test('drops the fragment and userinfo, keeps a non-default port', () {
      expect(
        creditUrl('https://user:secret@cdn.example:8443/a/hero.jpg#frag'),
        'https://cdn.example:8443/a/hero.jpg',
      );
    });

    test('a URL with no host yields no credit at all', () {
      expect(creditUrl('not a url at all'), isEmpty);
    });
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

  group('against the real corpus photo', skip: skipIfNoCorpus, () {
    late Uint8List heroJpeg;

    setUpAll(() {
      heroJpeg = File(
        '$corpusImagesDir/0857-rich-chocolate-bundt-cake-hero.jpg',
      ).readAsBytesSync();
    });

    test('sniffImage identifies a real corpus JPEG', () {
      final sniffed = sniffImage(heroJpeg);
      expect(sniffed, isNotNull);
      expect(sniffed!.extension, 'jpg');
      expect(sniffed.mimeType, 'image/jpeg');
    });

    test('sniffImage rejects a YAML file posing as an image', () {
      final yamlBytes = File(
        '$corpusRecipesDir/0857-rich-chocolate-bundt-cake.yaml',
      ).readAsBytesSync();
      expect(sniffImage(yamlBytes), isNull);
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
  });
}
