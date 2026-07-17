/// In-memory login rate limiter with exponential lockout.
///
/// Keyed by an opaque string (the caller uses `ip|username`). After
/// [failureThreshold] consecutive failures the key is locked for
/// [baseLockout]; every further failure doubles the lockout up to
/// [maxLockout]. A successful login clears the key. Lock expiry does not
/// reset the failure count — only success does — so an attacker cannot
/// retry at the base rate by waiting out each lock.
///
/// Pure and single-isolate; state is lost on restart, which is acceptable
/// for login throttling.
class LoginRateLimiter {
  /// Creates a limiter locking after [failureThreshold] consecutive
  /// failures. [now] is injectable for tests and defaults to the wall
  /// clock.
  LoginRateLimiter({
    this.failureThreshold = defaultFailureThreshold,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Default consecutive failures at which lockout begins (per-account
  /// keys). An aggregate per-IP limiter uses a higher threshold to catch
  /// password spraying across many usernames.
  static const int defaultFailureThreshold = 5;

  /// Consecutive failures at which lockout begins for this instance.
  final int failureThreshold;

  /// Lockout applied at the [failureThreshold]th failure.
  static const Duration baseLockout = Duration(minutes: 1);

  /// Upper bound on any lockout.
  static const Duration maxLockout = Duration(minutes: 15);

  /// Entries idle this long are discarded during opportunistic pruning.
  static const Duration _staleAfter = Duration(hours: 1);

  /// Prune at most once per this many mutating/checking calls.
  static const int _pruneEvery = 128;

  final DateTime Function() _now;
  final Map<String, _KeyState> _states = {};
  int _opsSincePrune = 0;

  /// Whether a login attempt for [key] may proceed.
  ///
  /// When blocked, `retryAfter` is the remaining lockout (always positive);
  /// when allowed it is [Duration.zero].
  ({bool allowed, Duration retryAfter}) check(String key) {
    _maybePrune();
    final state = _states[key];
    if (state == null) return (allowed: true, retryAfter: Duration.zero);
    final lockedUntil = state.lockedUntil;
    if (lockedUntil == null) return (allowed: true, retryAfter: Duration.zero);
    final remaining = lockedUntil.difference(_now());
    if (remaining <= Duration.zero) {
      return (allowed: true, retryAfter: Duration.zero);
    }
    return (allowed: false, retryAfter: remaining);
  }

  /// Records a failed login attempt for [key], starting or extending the
  /// lockout once the threshold is reached.
  void recordFailure(String key) {
    _maybePrune();
    final now = _now();
    final state = _states.putIfAbsent(key, _KeyState.new)
      ..failures += 1
      ..lastActivity = now;
    if (state.failures >= failureThreshold) {
      final doublings = state.failures - failureThreshold;
      state.lockedUntil = now.add(_lockoutForDoublings(doublings));
    }
  }

  /// Records a successful login for [key], clearing its failure history.
  void recordSuccess(String key) {
    _states.remove(key);
    _maybePrune();
  }

  static Duration _lockoutForDoublings(int doublings) {
    var lockout = baseLockout;
    for (var i = 0; i < doublings; i++) {
      lockout *= 2;
      if (lockout >= maxLockout) return maxLockout;
    }
    return lockout;
  }

  void _maybePrune() {
    _opsSincePrune += 1;
    if (_opsSincePrune < _pruneEvery) return;
    _opsSincePrune = 0;
    final cutoff = _now().subtract(_staleAfter);
    _states.removeWhere((_, state) {
      final lockedUntil = state.lockedUntil;
      final idleSince =
          (lockedUntil != null && lockedUntil.isAfter(state.lastActivity))
          ? lockedUntil
          : state.lastActivity;
      return idleSince.isBefore(cutoff);
    });
  }
}

class _KeyState {
  int failures = 0;
  DateTime lastActivity = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? lockedUntil;
}
