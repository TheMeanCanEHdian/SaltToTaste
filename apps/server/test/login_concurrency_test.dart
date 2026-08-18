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
    bool sharedClientIp = false,
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
            sharedClientIp: sharedClientIp,
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

  group('the aggregate bucket behind a shared address (S2)', () {
    test('a shared address cannot be used to lock out every account', () async {
      // With TRUST_PROXY off (the default) every request arrives from the
      // reverse proxy, so the aggregate per-IP bucket is really a GLOBAL
      // bucket: 25 failures across distinct usernames locked out the whole
      // deployment, permanently, since success does not clear it.
      final hasher = _FakeHasher();
      final runtime = AuthRuntime(hasher: hasher);
      createUser('bystander');

      for (var round = 0; round < 12; round += 1) {
        await stormLogin(
          runtime,
          count: 5,
          username: 'unused',
          usernameFor: (i) => 'sprayed${round * 5 + i}',
          sharedClientIp: true,
        );
      }

      final grant = await login(
        db,
        runtime,
        {'username': 'bystander', 'password': _FakeHasher.correctPassword},
        clientIp: '203.0.113.9',
        sharedClientIp: true,
        userAgent: 'test',
      );
      expect(
        grant.token,
        isNotEmpty,
        reason:
            'an unrelated account must still be able to log in after 60 '
            'failures from the address everyone shares',
      );
    });

    test('a real per-client address still catches spraying', () async {
      // The protection must survive the fix: when the address does identify
      // one client, the aggregate lockout is exactly what should fire.
      final hasher = _FakeHasher();
      final runtime = AuthRuntime(hasher: hasher);
      createUser('target');

      for (var round = 0; round < 12; round += 1) {
        await stormLogin(
          runtime,
          count: 5,
          username: 'unused',
          usernameFor: (i) => 'sprayed${round * 5 + i}',
        );
      }

      await expectLater(
        login(
          db,
          runtime,
          {'username': 'target', 'password': _FakeHasher.correctPassword},
          clientIp: '203.0.113.9',
        ),
        throwsA(isA<LockedException>()),
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
}
