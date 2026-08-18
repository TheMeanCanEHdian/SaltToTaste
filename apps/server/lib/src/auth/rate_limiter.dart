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
    this.escalate = true,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Default consecutive failures at which lockout begins (per-account
  /// keys). An aggregate per-IP limiter uses a higher threshold to catch
  /// password spraying across many usernames.
  static const int defaultFailureThreshold = 5;

  /// Consecutive failures at which lockout begins for this instance.
  final int failureThreshold;

  /// Whether each failure past the threshold doubles the lockout.
  ///
  /// True for a key that names one account, where a longer lockout falls on
  /// the attacker. False for a key that may be SHARED — an address behind an
  /// undeclared proxy is every client at once, and escalating there lets one
  /// attacker hold everyone at the 15-minute cap.
  final bool escalate;

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

  /// Checks [key] and counts the attempt in ONE synchronous step, returning
  /// the same verdict [check] would.
  ///
  /// This exists because [check] and [recordFailure] used to sit on either
  /// side of the ~60-100ms Argon2id await in `login`, and Dart only switches
  /// tasks at an await: every request in flight during that gap saw a limiter
  /// with zero recorded failures, so N simultaneous attempts all passed a
  /// gate meant to admit [failureThreshold]. The limiter bounded the
  /// sequential RATE of attempts and never their CONCURRENT count — measured
  /// at 100 concurrent guesses against one account all being verified, and
  /// 150 concurrent logins holding 2.9 GiB of Argon2id state at once.
  ///
  /// Counting up front is what closes it: no await runs between the read and
  /// the write, so the (N+1)th concurrent caller sees the Nth's increment.
  /// An attempt that is abandoned mid-flight therefore stays counted, which
  /// is the safe direction for a throttle. Clear it with [recordSuccess], or
  /// give back just this one count with [releaseReservation].
  ({bool allowed, Duration retryAfter}) reserve(String key) {
    final gate = check(key);
    if (!gate.allowed) return gate;
    recordFailure(key);
    return gate;
  }

  /// Gives back a single [reserve] count for [key] without clearing its
  /// history, for a caller whose attempt turned out not to be a failure but
  /// whose earlier failures must still stand.
  void releaseReservation(String key) {
    final state = _states[key];
    if (state == null || state.failures == 0) return;
    state
      ..failures -= 1
      ..lastActivity = _now();
    if (state.failures < failureThreshold) state.lockedUntil = null;
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
      final doublings = escalate ? state.failures - failureThreshold : 0;
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

/// A hard ceiling on how many of something may be in flight at once.
///
/// The login throttles bound attempts per account and per address; neither
/// bounds the TOTAL. An attacker spreading guesses over many usernames stays
/// under every per-key threshold while still starting an unbounded number of
/// concurrent Argon2id hashes, each holding its own ~19 MiB block array on the
/// single serving isolate — measured at 2.9 GiB resident from one burst, from
/// ~30 KB of request traffic.
///
/// Refuses rather than queues: under attack a queue is itself the memory sink
/// it was meant to prevent, and a caller told to retry costs nothing to hold.
class ConcurrencyGate {
  /// Creates a gate admitting at most [limit] holders at once. A [limit] of
  /// zero or less disables it, so an operator can turn it off.
  ConcurrencyGate({required this.limit});

  /// Maximum simultaneous holders; zero or less disables the gate.
  final int limit;

  int _inFlight = 0;

  /// Holders currently admitted.
  int get inFlight => _inFlight;

  /// Takes a slot if one is free. Balance every `true` with [release].
  bool tryAcquire() {
    if (limit <= 0) return true;
    if (_inFlight >= limit) return false;
    _inFlight += 1;
    return true;
  }

  /// Returns a slot taken by [tryAcquire].
  void release() {
    if (limit <= 0) return;
    if (_inFlight > 0) _inFlight -= 1;
  }
}

/// In-memory per-key request-RATE limiter (sliding window).
///
/// Where [LoginRateLimiter] locks out after repeated FAILURES, this bounds the
/// RATE of otherwise-successful requests: it allows [maxRequests] within any
/// [window] per key and refuses the rest. It exists so one identity cannot
/// monopolise a synchronous, single-isolate resource — the SQLite FTS search
/// runs on dart_frog's one serving isolate, so a member looping expensive
/// queries adds latency for everyone (measured after the term cap of `#42`).
/// This does not remove that architectural limit; it caps any single caller's
/// share of it.
///
/// [maxRequests] of zero or less disables the limiter — every call is allowed
/// and nothing is recorded — so an operator can turn it off.
///
/// Pure and single-isolate; state is lost on restart, which is acceptable for
/// rate limiting.
class RequestRateLimiter {
  /// Creates a limiter allowing [maxRequests] per [window] per key. [now] is
  /// injectable for tests and defaults to the wall clock.
  RequestRateLimiter({
    this.maxRequests = defaultMaxRequests,
    this.window = const Duration(minutes: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Default requests allowed per [window] — generous enough that no human
  /// searching by hand reaches it, tight enough to neutralise a hammering
  /// loop's isolate share.
  static const int defaultMaxRequests = 60;

  /// Requests allowed per [window]; zero or less disables limiting.
  final int maxRequests;

  /// The sliding window over which [maxRequests] is counted.
  final Duration window;

  /// Entries with no in-window hits are discarded during opportunistic
  /// pruning, so a flood of distinct keys cannot grow the map without bound.
  static const int _pruneEvery = 256;

  final DateTime Function() _now;
  final Map<String, List<DateTime>> _hits = {};
  int _opsSincePrune = 0;

  /// Whether a request for [key] may proceed, recording it when it may.
  ///
  /// When blocked, `retryAfter` is the time until the oldest in-window hit
  /// ages out (always positive); when allowed it is [Duration.zero].
  ({bool allowed, Duration retryAfter}) check(String key) {
    if (maxRequests <= 0) {
      return (allowed: true, retryAfter: Duration.zero);
    }
    final now = _now();
    _maybePrune(now);
    final cutoff = now.subtract(window);
    final hits = _hits.putIfAbsent(key, () => <DateTime>[])
      // Drop hits at or before the cutoff; keep those strictly within the
      // window.
      ..removeWhere((hit) => !hit.isAfter(cutoff));
    if (hits.length < maxRequests) {
      hits.add(now);
      return (allowed: true, retryAfter: Duration.zero);
    }
    final retryAfter = hits.first.add(window).difference(now);
    return (
      allowed: false,
      // The oldest hit is within the window, so this is positive; the fallback
      // only guards a clock that moved backwards.
      retryAfter: retryAfter > Duration.zero ? retryAfter : window,
    );
  }

  void _maybePrune(DateTime now) {
    _opsSincePrune += 1;
    if (_opsSincePrune < _pruneEvery) {
      return;
    }
    _opsSincePrune = 0;
    final cutoff = now.subtract(window);
    _hits.removeWhere((_, hits) {
      hits.removeWhere((hit) => !hit.isAfter(cutoff));
      return hits.isEmpty;
    });
  }
}
