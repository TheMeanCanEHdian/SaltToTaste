import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:test/test.dart';

void main() {
  late DateTime clock;
  late LoginRateLimiter limiter;

  setUp(() {
    clock = DateTime.utc(2026, 7, 15, 12);
    limiter = LoginRateLimiter(now: () => clock);
  });

  void advance(Duration duration) => clock = clock.add(duration);

  test('unknown key is allowed', () {
    final result = limiter.check('10.0.0.1|alice');
    expect(result.allowed, isTrue);
    expect(result.retryAfter, Duration.zero);
  });

  test('four failures still allowed', () {
    for (var i = 0; i < 4; i++) {
      limiter.recordFailure('k');
    }
    expect(limiter.check('k').allowed, isTrue);
  });

  test('fifth failure locks for exactly 60 seconds', () {
    for (var i = 0; i < 5; i++) {
      limiter.recordFailure('k');
    }
    final locked = limiter.check('k');
    expect(locked.allowed, isFalse);
    expect(locked.retryAfter, const Duration(minutes: 1));

    advance(const Duration(seconds: 45));
    expect(limiter.check('k').retryAfter, const Duration(seconds: 15));

    advance(const Duration(seconds: 15));
    expect(limiter.check('k').allowed, isTrue);
  });

  test('each further failure doubles the lockout up to the 15-minute cap', () {
    const expected = [
      Duration(minutes: 1), // 5th failure
      Duration(minutes: 2), // 6th
      Duration(minutes: 4), // 7th
      Duration(minutes: 8), // 8th
      Duration(minutes: 15), // 9th: 16 min capped
      Duration(minutes: 15), // 10th: still capped
    ];
    for (var i = 0; i < 4; i++) {
      limiter.recordFailure('k');
    }
    for (final duration in expected) {
      limiter.recordFailure('k');
      final result = limiter.check('k');
      expect(result.allowed, isFalse);
      expect(result.retryAfter, duration);
      // Wait out the lock; the next failure must still double.
      advance(duration);
      expect(limiter.check('k').allowed, isTrue);
    }
  });

  test('success clears the failure history', () {
    for (var i = 0; i < 5; i++) {
      limiter.recordFailure('k');
    }
    expect(limiter.check('k').allowed, isFalse);

    advance(const Duration(minutes: 1));
    limiter.recordSuccess('k');

    // Back to a clean slate: four failures fine, fifth locks at base again.
    for (var i = 0; i < 4; i++) {
      limiter.recordFailure('k');
    }
    expect(limiter.check('k').allowed, isTrue);
    limiter.recordFailure('k');
    final locked = limiter.check('k');
    expect(locked.allowed, isFalse);
    expect(locked.retryAfter, const Duration(minutes: 1));
  });

  test('keys are independent', () {
    for (var i = 0; i < 5; i++) {
      limiter.recordFailure('10.0.0.1|alice');
    }
    expect(limiter.check('10.0.0.1|alice').allowed, isFalse);
    expect(limiter.check('10.0.0.1|bob').allowed, isTrue);
    expect(limiter.check('10.0.0.2|alice').allowed, isTrue);

    limiter.recordSuccess('10.0.0.1|bob');
    expect(limiter.check('10.0.0.1|alice').allowed, isFalse);
  });

  test('stale entries are pruned opportunistically', () {
    // Lock the key (6 failures -> 2 min lock), then leave it idle.
    for (var i = 0; i < 6; i++) {
      limiter.recordFailure('stale');
    }
    advance(const Duration(hours: 2));

    // Churn enough operations on other keys to trigger a prune sweep.
    for (var i = 0; i < 200; i++) {
      limiter.check('other');
    }

    // If 'stale' survived, this failure would be its 7th -> 4 min lock.
    // After pruning it is failure #1 of a fresh entry -> still allowed.
    limiter.recordFailure('stale');
    expect(limiter.check('stale').allowed, isTrue);
  });

  test('recent entries survive pruning', () {
    for (var i = 0; i < 5; i++) {
      limiter.recordFailure('fresh');
    }
    for (var i = 0; i < 200; i++) {
      limiter.check('other');
    }
    expect(limiter.check('fresh').allowed, isFalse);
  });
}
