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
    String? hold,
    String? gramSource,
  }) => matchBucketFor(
    status: status,
    fdcId: fdcId,
    grams: grams,
    confidence: confidence,
    hold: hold,
    gramSource: gramSource,
  );

  group('matchBucketFor', () {
    test('skipped is always resolved', () {
      expect(bucket(status: 'skipped'), MatchBucket.skipped);
      expect(
        bucket(status: 'skipped', fdcId: null, grams: null),
        MatchBucket.skipped,
      );
    });

    test('a weak auto match is "check" whether or not it has grams', () {
      // A 0.41 "100 GRAND Bar" for a liqueur line with no portion used to
      // read as the calm "no amount"; the wrong food is the larger problem.
      expect(bucket(confidence: 0.41, grams: null), MatchBucket.check);
      expect(bucket(confidence: 0.41), MatchBucket.check);
      expect(bucket(grams: null), MatchBucket.noAmount);
    });
    test('a held auto match is "check" at any score; a decision ignores '
        'the hold', () {
      for (final hold in ['no_nutrients', 'discarded_medium', 'second_food']) {
        expect(bucket(hold: hold), MatchBucket.check, reason: hold);
        expect(bucket(hold: hold, grams: null), MatchBucket.check);
        expect(bucket(hold: hold, status: 'confirmed'), MatchBucket.counted);
        expect(bucket(hold: hold, status: 'skipped'), MatchBucket.skipped);
      }
    });
    test('an engine 0 g (discarded / unmeasured) is counted at any score or '
        'hold but unnamed_food; with grams it is bucketed like any line', () {
      // Audit 4: 34 such rows sat in `check` though no decision could change
      // a total ("2 quarts peanut or vegetable oil for frying" at 0.457).
      for (final source in ['discarded', 'unmeasured']) {
        expect(
          bucket(confidence: 0.457, grams: 0, gramSource: source),
          MatchBucket.counted,
          reason: source,
        );
        expect(
          bucket(grams: 0, hold: 'no_nutrients', gramSource: source),
          MatchBucket.counted,
          reason: source,
        );
        // "2 tablespoons juice" (0661, the parser kept the amount in the
        // item): its 0 g drops a real amount, so a person looks.
        expect(
          bucket(grams: 0, hold: 'unnamed_food', gramSource: source),
          MatchBucket.check,
          reason: source,
        );
        // The eaten part of a "plus" medium has grams.
        expect(
          bucket(confidence: 0.457, grams: 12, gramSource: source),
          MatchBucket.check,
          reason: source,
        );
      }
      expect(
        bucket(confidence: 0.457, grams: 0, gramSource: 'weight'),
        MatchBucket.check,
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
