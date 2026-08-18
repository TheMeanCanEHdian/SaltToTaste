// The login throttle under CONCURRENCY, and the aggregate bucket behind a
// shared address (security pass S1/S2).
//
// The bug these pin: `check()` read the limiter and `recordFailure()` wrote
// it, with the ~60-100ms Argon2id await in between. Dart only switches tasks
// at an await, so every request in flight during that gap saw zero recorded
// failures and passed a gate meant to admit five — measured at 100 concurrent
// guesses against one account all being verified, and 150 concurrent logins
// holding 2.9 GiB of Argon2id state at once. The limiter bounded the
// sequential RATE of attempts and never their CONCURRENT count.
//
// Every test here therefore drives login() CONCURRENTLY. A sequential version
// of any of them passes against the old code, which is exactly why the old
// suite missed this.

import 'dart:io';

import 'package:salt_server/src/auth/password_hasher.dart';
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:test/test.dart';

/// Stands in for Argon2id: same await-in-the-middle shape, none of the cost,
/// and it counts both total and simultaneous verifications. The delay is what
/// reproduces the interleaving — with no await there is no race to close.
class _FakeHasher extends PasswordHasher {
  static const String correctPassword = 'correct-horse-battery';

  /// Long enough that concurrent calls genuinely overlap. Without a real
  /// suspension point there is no interleaving and nothing to pin.
  static const Duration delay = Duration(milliseconds: 20);

  int verifications = 0;
  int inFlight = 0;
  int peakInFlight = 0;

  Future<bool> _run(bool result) async {
    verifications += 1;
    inFlight += 1;
    if (inFlight > peakInFlight) peakInFlight = inFlight;
    await Future<void>.delayed(delay);
    inFlight -= 1;
    return result;
  }

  @override
  Future<bool> verify(String password, String phcString) =>
      _run(password == correctPassword);

  @override
  Future<void> dummyVerify(String password) async {
    await _run(false);
  }
}

void main() {
  late Directory tempDir;
  late SaltDatabase db;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('salt_login_concurrency_');
    final config = ServerConfig.fromEnvironment(
      environment: {'DATA_DIR': tempDir.path, 'LOG_LEVEL': 'ERROR'},
    );
    db = SaltDatabase.open(config.dbPath);
  });

  tearDown(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  int createUser(String username) => db.createUser(
    username: username,
    // The hasher is faked, so the stored PHC is never parsed. Not a
    // credential and not data under test.
    passwordHash: 'unused-by-the-fake-hasher',
    role: 'member',
  );

  /// Runs [count] logins at once and returns the outcome of each, so a test
  /// can count refusals instead of drowning in the first thrown error.
  Future<List<Object>> stormLogin(
    AuthRuntime runtime, {
    required int count,
    required String username,
    String password = 'wrong-password',
    String clientIp = '203.0.113.9',
    String Function(int)? usernameFor,
  }) => Future.wait([
    for (var i = 0; i < count; i += 1)
      login(
            db,
            runtime,
            {
              'username': usernameFor?.call(i) ?? username,
              'password': password,
            },
            clientIp: clientIp,
          )
          .then<Object>((grant) => 'ok')
          .onError<AppException>((error, _) => error),
  ]);

  group('the reservation is taken before the hash (S1)', () {
    test('concurrent guesses at one account cannot outrun the threshold', () {
      // The headline pin. 50 simultaneous wrong-password attempts must cost
      // at most `failureThreshold` password verifications; the rest must be
      // refused unseen. Before the fix all 50 were verified, because every
      // one of them read the limiter before any of them wrote to it.
      final hasher = _FakeHasher();
      final runtime = AuthRuntime(hasher: hasher);
      createUser('victim');

      return stormLogin(runtime, count: 50, username: 'victim').then((
        outcomes,
      ) {
        final locked = outcomes.whereType<LockedException>().length;
        expect(
          hasher.verifications,
          lessThanOrEqualTo(LoginRateLimiter.defaultFailureThreshold),
          reason:
              'a concurrent burst must not buy more password verifications '
              'than the sequential threshold allows',
        );
        expect(
          locked,
          50 - hasher.verifications,
          reason: 'every attempt that was not verified must have been a 429',
        );
        expect(outcomes.whereType<ValidationException>(), isNotEmpty);
      });
    });

    test('an unknown username is throttled too, not just a real one', () async {
      // dummyVerify runs for nonexistent accounts on purpose (no timing
      // oracle), so it is an equally good way to spend the server's CPU and
      // must sit behind the same reservation.
      final hasher = _FakeHasher();
      final runtime = AuthRuntime(hasher: hasher);

      final outcomes = await stormLogin(runtime, count: 40, username: 'ghost');
      expect(
        hasher.verifications,
        lessThanOrEqualTo(LoginRateLimiter.defaultFailureThreshold),
      );
      expect(outcomes.whereType<LockedException>(), isNotEmpty);
    });

    test('a correct password still succeeds and clears the account', () async {
      final hasher = _FakeHasher();
      final runtime = AuthRuntime(hasher: hasher);
      createUser('alice');

      // Two failures, then the real password: the reservation must not have
      // turned a legitimate login into a lockout.
      await stormLogin(runtime, count: 2, username: 'alice');
      final grant = await login(
        db,
        runtime,
        {'username': 'alice', 'password': _FakeHasher.correctPassword},
        clientIp: '203.0.113.9',
      );
      expect(grant.token, isNotEmpty);
      // Success clears the per-account history, so the next attempt is fresh.
      expect(runtime.rateLimiter.check('203.0.113.9|alice').allowed, isTrue);
    });
  });

  group('total in-flight hashes are bounded (S1 memory)', () {
    test('simultaneous verifications never exceed the gate', () async {
      // Spread over many DISTINCT usernames, so every per-account bucket
      // stays under its own threshold and only the global gate can bound the
      // total. This is the shape that reached 2.9 GiB resident.
      final hasher = _FakeHasher();
      final runtime = AuthRuntime(hasher: hasher);
      for (var i = 0; i < 60; i += 1) {
        createUser('user$i');
      }

      await stormLogin(
        runtime,
        count: 60,
        username: 'unused',
        usernameFor: (i) => 'user$i',
      );
      expect(
        hasher.peakInFlight,
        lessThanOrEqualTo(AuthRuntime.maxConcurrentVerifications),
        reason:
            'each concurrent Argon2id holds ~19 MiB; without a ceiling the '
            'per-key throttles never bound the total',
      );
      expect(hasher.peakInFlight, greaterThan(1), reason: 'sanity: overlapped');
    });

    test('the gate releases, so later logins are not permanently refused', () {
      final hasher = _FakeHasher();
      final runtime = AuthRuntime(hasher: hasher);
      createUser('bob');

      return stormLogin(
        runtime,
        count: 30,
        username: 'unused',
        usernameFor: (i) => 'filler$i',
      ).then((_) async {
        // Gate slots are returned in a finally, so a burst cannot strand them.
        expect(runtime.verifyGate.inFlight, 0);
        final grant = await login(
          db,
          runtime,
          {'username': 'bob', 'password': _FakeHasher.correctPassword},
          clientIp: '198.51.100.4',
        );
        expect(grant.token, isNotEmpty);
      });
    });
  });

  group('the aggregate per-address bucket (S2)', () {
    test('an attacker-chosen header cannot switch the bucket off', () async {
      // The first attempt at S2 skipped the aggregate bucket whenever the
      // request carried X-Forwarded-For from an untrusted peer, reasoning that
      // such an address cannot identify one client. But that header is
      // attacker-supplied, so it handed any unauthenticated peer an opt-out
      // from horizontal-spray detection: measured at 60 sprayed usernames and
      // zero refusals. login() no longer takes that signal at all, so this
      // pins the property structurally — spraying is bounded whatever the
      // caller sends.
      final hasher = _FakeHasher();
      final runtime = AuthRuntime(hasher: hasher);
      var refusals = 0;
      for (var round = 0; round < 8; round += 1) {
        final outcomes = await stormLogin(
          runtime,
          count: 5,
          username: 'unused',
          usernameFor: (i) => 'sprayed${round * 5 + i}',
        );
        refusals += outcomes.whereType<LockedException>().length;
      }
      expect(
        refusals,
        greaterThan(0),
        reason:
            'the aggregate bucket must fire on a horizontal spray no matter '
            'what headers the caller attached',
      );
    });

    test('the aggregate lockout does not escalate', () {
      // The per-account key names one account, so a longer lockout falls on
      // the attacker and escalation is right. An ADDRESS may be shared — behind
      // a proxy the operator has not declared, it is every client at once — so
      // escalating there would let one attacker take everyone to the 15-minute
      // cap and hold them. Flat instead: spray detection kept, blast radius
      // bounded.
      final limiter = LoginRateLimiter(
        failureThreshold: AuthRuntime.ipFailureThreshold,
        escalate: false,
      );
      for (var i = 0; i < AuthRuntime.ipFailureThreshold * 3; i += 1) {
        limiter.recordFailure('198.51.100.7');
      }
      final blocked = limiter.check('198.51.100.7');
      expect(blocked.allowed, isFalse);
      expect(
        blocked.retryAfter,
        lessThanOrEqualTo(LoginRateLimiter.baseLockout),
        reason: 'a shared address must never reach the escalated cap',
      );
    });

    test(
      'ordinary successes do not march the aggregate to a lockout',
      () async {
        // The reservation is taken before the password is known, so a success
        // has to give it back — otherwise enough normal logins from one address
        // would trip the horizontal bucket on their own.
        final hasher = _FakeHasher();
        final runtime = AuthRuntime(hasher: hasher);
        for (var i = 0; i < 40; i += 1) {
          createUser('member$i');
        }

        for (var i = 0; i < 40; i += 1) {
          final grant = await login(
            db,
            runtime,
            {'username': 'member$i', 'password': _FakeHasher.correctPassword},
            clientIp: '198.51.100.7',
          );
          expect(
            grant.token,
            isNotEmpty,
            reason: 'login $i must still succeed',
          );
        }
      },
    );
  });
  group('a gate refusal is backpressure, not a failed attempt', () {
    test('a full gate does not lock a user out of their own account', () async {
      // The gate refusal used to keep the reservations it had already taken,
      // which handed a third party an account-lockout primitive: hold every
      // slot with throwaway usernames, and the real owner's CORRECT password
      // burns one reservation per try until their own per-account bucket
      // locks them out for 15 minutes. The gate is taken directly here so the
      // test turns on the property, not on timing.
      final hasher = _FakeHasher();
      final runtime = AuthRuntime(
        hasher: hasher,
        verifyGate: ConcurrencyGate(limit: 1),
      );
      createUser('victim');

      expect(runtime.verifyGate.tryAcquire(), isTrue, reason: 'hold the slot');
      for (var i = 0; i < 6; i += 1) {
        await expectLater(
          login(
            db,
            runtime,
            {'username': 'victim', 'password': _FakeHasher.correctPassword},
            clientIp: '203.0.113.55',
          ),
          throwsA(isA<LockedException>()),
          reason: 'attempt $i must be refused by the full gate',
        );
      }
      runtime.verifyGate.release();

      // Six refusals is past the 5-failure threshold. If they had counted,
      // this correct password would now be locked out.
      final grant = await login(
        db,
        runtime,
        {'username': 'victim', 'password': _FakeHasher.correctPassword},
        clientIp: '203.0.113.55',
      );
      expect(
        grant.token,
        isNotEmpty,
        reason: 'requests the gate never let guess must not count as guesses',
      );
      expect(hasher.verifications, 1, reason: 'only the admitted one hashed');
    });

    test(
      'an overlong username cannot mint an unbounded throttle key',
      () async {
        // reserve() inserts the key BEFORE every refusal path and holds it for
        // an hour, so an unbounded name is retained memory the caller chooses:
        // measured at 279 MiB of RSS for 200 free requests. Truncating at the
        // longest name that could ever be real means two overlong names share a
        // bucket — which is what this asserts, and which is stricter than
        // separate buckets, never looser.
        final runtime = AuthRuntime(hasher: _FakeHasher());
        final stem = 'z' * 40;
        for (var i = 0; i < LoginRateLimiter.defaultFailureThreshold; i += 1) {
          await expectLater(
            login(
              db,
              runtime,
              {'username': '$stem-A', 'password': 'nope'},
              clientIp: '203.0.113.77',
            ),
            throwsA(isA<AppException>()),
          );
        }
        await expectLater(
          login(
            db,
            runtime,
            {'username': '$stem-B', 'password': 'nope'},
            clientIp: '203.0.113.77',
          ),
          throwsA(isA<LockedException>()),
          reason:
              'two names sharing their first 32 characters must share one '
              'bucket, or the key is the caller-chosen length again',
        );
      },
    );
  });
}
