import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

/// The ONE bucketing rule (review B7). The server's queue SQL mirrors this
/// function and is parity-pinned in apps/server/test/nutrition_review_test;
/// these are the rule's own corner pins. Match states are crafted (nutrition
/// rows are DB-only — they cannot come from the YAML corpus).
void main() {
  MatchBucket bucket({
    String status = 'auto',
    int? fdcId = 5,
    double? grams = 100,
    double confidence = 0.9,
  }) => matchBucketFor(
    status: status,
    fdcId: fdcId,
    grams: grams,
    confidence: confidence,
  );

  group('matchBucketFor', () {
    test('skipped is always resolved', () {
      expect(bucket(status: 'skipped'), MatchBucket.skipped);
      expect(
        bucket(status: 'skipped', fdcId: null, grams: null),
        MatchBucket.skipped,
      );
    });

    test('overridden with no grams STAYS flagged — an unfinished fix', () {
      expect(bucket(status: 'overridden', grams: null), MatchBucket.noAmount);
    });

    test('overridden with grams counts', () {
      expect(bucket(status: 'overridden'), MatchBucket.counted);
    });

    test('confirmed is always resolved, even matchless (confirmed water)', () {
      expect(
        bucket(status: 'confirmed', fdcId: null, grams: null),
        MatchBucket.counted,
      );
      expect(bucket(status: 'confirmed'), MatchBucket.counted);
    });

    test('auto/unmatched rows triage by their data', () {
      expect(bucket(fdcId: null), MatchBucket.noMatch);
      expect(
        bucket(status: 'unmatched', fdcId: null, grams: null, confidence: 0),
        MatchBucket.noMatch,
      );
      expect(bucket(grams: null), MatchBucket.noAmount);
      expect(bucket(confidence: 0.4), MatchBucket.check);
      expect(bucket(), MatchBucket.counted);
    });

    test('wire names round-trip (the queue speaks no_grams)', () {
      for (final value in MatchBucket.values) {
        expect(MatchBucket.fromWire(value.wire), value);
      }
      expect(MatchBucket.noAmount.wire, 'no_grams');
    });
  });
}
