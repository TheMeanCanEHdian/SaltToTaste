import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/http/path_params.dart';
import 'package:test/test.dart';

void main() {
  group('decodePathParam (review B8)', () {
    test('decodes percent escapes the router leaves encoded', () {
      expect(decodePathParam('main%20course'), 'main course');
      expect(decodePathParam('saz%C3%B3n'), 'sazón');
      expect(decodePathParam('plain-slug_1'), 'plain-slug_1');
    });

    test('malformed escapes are a 422, not a 500', () {
      // Synthesized: only a hand-crafted client can send these.
      for (final raw in ['%G1', '%', '%2', '%FF']) {
        expect(
          () => decodePathParam(raw),
          throwsA(isA<ValidationException>()),
          reason: raw,
        );
      }
    });
  });
}
