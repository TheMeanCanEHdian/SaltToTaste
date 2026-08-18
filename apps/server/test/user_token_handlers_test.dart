import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/auth/password_hasher.dart';
import 'package:salt_server/src/auth/tokens.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart' show auditLog;
import 'package:salt_server/src/handlers/token_handlers.dart';
import 'package:salt_server/src/handlers/user_handlers.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late SaltDatabase db;
  late PasswordHasher hasher;
  late AuthUser admin;

  AuthUser actorFor(
    int id, {
    String role = 'member',
    String? sessionHash,
    String scope = 'full',
  }) => AuthUser(
    id: id,
    username: 'user$id',
    role: role,
    mustChangePassword: false,
    scope: scope,
    via: sessionHash == null ? 'pat' : 'session',
    sessionHash: sessionHash,
  );

  setUpAll(() {
    // `LOG_LEVEL=WARN` (and `ERROR`) are supported operator settings that set
    // Logger.root.level. Raising it here means every INFO expectation in
    // "account administration is recorded" holds only because `auditLog` pins
    // its own level — which is the point: an audit record a routine config
    // choice deletes is not an audit record.
    Logger.root.level = Level.SEVERE;
  });

  tearDownAll(() {
    Logger.root.level = Level.INFO;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('salt_user_handlers');
    db = SaltDatabase.open('${tempDir.path}/salt.db');
    hasher = PasswordHasher();
    final adminId = db.createUser(
      username: 'root',
      passwordHash: await hasher.hash('a-long-admin-password'),
      role: 'admin',
    );
    admin = actorFor(adminId, role: 'admin');
  });

  tearDown(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  group('users', () {
    test('create member: temp password verifies and forces change', () async {
      final result = await createUserHandler(
        db,
        hasher,
        admin,
        username: 'Sam',
        role: 'member',
      );
      final tempPassword = result['temp_password']! as String;
      expect(tempPassword, hasLength(20));

      final user = db.userByUsername('sam')!;
      expect(user.mustChangePassword, isTrue);
      expect(await hasher.verify(tempPassword, user.passwordHash), isTrue);
      final json = result['user']! as Map<String, Object?>;
      expect(json['username'], 'sam');
      expect(json['role'], 'member');
    });

    test('duplicate username is a 409 conflict (case-insensitive)', () async {
      await createUserHandler(
        db,
        hasher,
        admin,
        username: 'sam',
        role: 'member',
      );
      await expectLater(
        createUserHandler(db, hasher, admin, username: 'SAM', role: 'member'),
        throwsA(isA<ConflictException>()),
      );
    });

    test('self-demote and self-disable are blocked', () {
      expect(
        () => patchUserHandler(db, admin, admin.id, role: 'member'),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => patchUserHandler(db, admin, admin.id, disabled: true),
        throwsA(isA<ValidationException>()),
      );
    });

    test(
      'delete removes the account and cascades its sessions and tokens',
      () async {
        final created = await createUserHandler(
          db,
          hasher,
          admin,
          username: 'sam',
          role: 'member',
        );
        final samId = (created['user']! as Map<String, Object?>)['id']! as int;
        final sam = actorFor(samId);
        db.createSession(
          tokenHash: hashToken(generateOpaqueToken()),
          userId: samId,
          expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
          remember: false,
        );
        createTokenHandler(db, sam, name: 'sam-token', scope: 'read');
        expect(db.sessionsForUser(samId), isNotEmpty);
        expect(db.apiTokensForUser(samId), isNotEmpty);

        final result = deleteUserHandler(db, admin, samId);
        expect(result['ok'], isTrue);
        expect(db.userById(samId), isNull);
        expect(db.sessionsForUser(samId), isEmpty);
        expect(db.apiTokensForUser(samId), isEmpty);
      },
    );

    test('cannot delete your own account', () {
      expect(
        () => deleteUserHandler(db, admin, admin.id),
        throwsA(isA<ValidationException>()),
      );
    });

    test('deleting an unknown user is a 404', () {
      expect(
        () => deleteUserHandler(db, admin, 999999),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('reset password issues a new temp and kills sessions', () async {
      final created = await createUserHandler(
        db,
        hasher,
        admin,
        username: 'sam',
        role: 'member',
      );
      final samId = (created['user']! as Map<String, Object?>)['id']! as int;
      final sessionToken = generateOpaqueToken();
      db.createSession(
        tokenHash: hashToken(sessionToken),
        userId: samId,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
        remember: false,
      );
      expect(db.sessionsForUser(samId), hasLength(1));

      final reset = await resetPasswordHandler(db, hasher, admin, samId);
      final newTemp = reset['temp_password']! as String;
      final sam = db.userById(samId)!;
      expect(sam.mustChangePassword, isTrue);
      expect(await hasher.verify(newTemp, sam.passwordHash), isTrue);
      expect(db.sessionsForUser(samId), isEmpty);
    });
  });

  group('sessions', () {
    test('list marks the current session; delete is owner-scoped', () {
      final mine = generateOpaqueToken();
      final other = generateOpaqueToken();
      for (final token in [mine, other]) {
        db.createSession(
          tokenHash: hashToken(token),
          userId: admin.id,
          expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
          remember: false,
        );
      }
      final actor = actorFor(
        admin.id,
        role: 'admin',
        sessionHash: hashToken(mine),
      );
      final list = listSessionsHandler(db, actor);
      final items = (list['items']! as List).cast<Map<String, Object?>>();
      expect(items, hasLength(2));
      expect(
        items.where((item) => item['current'] == true).single['id'],
        hashToken(mine),
      );

      // A stranger cannot delete it.
      final stranger = actorFor(9999);
      expect(
        () => deleteSessionHandler(db, stranger, hashToken(other)),
        throwsA(isA<NotFoundException>()),
      );
      deleteSessionHandler(db, actor, hashToken(other));
      expect(db.sessionsForUser(admin.id), hasLength(1));
    });
  });

  group('tokens', () {
    test('create returns the full value once; it hashes to the row', () {
      final result = createTokenHandler(
        db,
        admin,
        name: 'iPad kitchen app',
        scope: 'read',
      );
      final token = result['token']! as String;
      expect(token, startsWith('stt_pat_'));
      final row = db.apiTokenByHash(hashToken(token))!;
      expect(row.userId, admin.id);
      expect(row.scope, 'read');
      final item = result['item']! as Map<String, Object?>;
      expect(item['prefix'], isNot(contains('stt_pat_')));
      expect(token, contains(item['prefix']! as String));
    });

    test('invalid scope and name are validation errors', () {
      expect(
        () => createTokenHandler(db, admin, name: 'x', scope: 'write'),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => createTokenHandler(db, admin, name: '', scope: 'read'),
        throwsA(isA<ValidationException>()),
      );
    });

    test('a member cannot mint tokens without bound', () {
      // Availability finding (#42): a token row is permanent (revocation is an
      // UPDATE, never a DELETE) and a member's session is always full-scope, so
      // without a cap a low-privilege account grows api_tokens for the
      // deployment's lifetime. The member reaches this handler exactly as an
      // admin does — the point is that role does not gate it.
      final memberId = db.createUser(
        username: 'member',
        passwordHash: 'x',
        role: 'member',
      );
      final member = actorFor(memberId);
      for (var i = 0; i < maxActiveTokensPerUser; i++) {
        createTokenHandler(db, member, name: 'tok$i', scope: 'read');
      }
      expect(
        () =>
            createTokenHandler(db, member, name: 'one too many', scope: 'read'),
        throwsA(isA<ValidationException>()),
        reason: 'the cap must reject the ${maxActiveTokensPerUser + 1}th',
      );
      expect(db.activeApiTokenCount(memberId), maxActiveTokensPerUser);
    });

    test('revoking frees a slot, but the revoked row is not counted', () {
      final memberId = db.createUser(
        username: 'rotator',
        passwordHash: 'x',
        role: 'member',
      );
      final member = actorFor(memberId);
      final ids = [
        for (var i = 0; i < maxActiveTokensPerUser; i++)
          (createTokenHandler(db, member, name: 'tok$i', scope: 'read')['item']!
                  as Map<String, Object?>)['id']!
              as int,
      ];
      // At the cap: the next mint fails.
      expect(
        () => createTokenHandler(db, member, name: 'blocked', scope: 'read'),
        throwsA(isA<ValidationException>()),
      );
      // Revoke one; a slot opens and the next mint succeeds.
      db.revokeApiToken(id: ids.first, userId: memberId);
      expect(db.activeApiTokenCount(memberId), maxActiveTokensPerUser - 1);
      expect(
        createTokenHandler(db, member, name: 'now ok', scope: 'read')['token'],
        isA<String>(),
      );
    });

    test('revoke is owner-scoped and single-shot', () {
      final result = createTokenHandler(
        db,
        admin,
        name: 'sync script',
        scope: 'full',
      );
      final id = (result['item']! as Map<String, Object?>)['id']! as int;

      final stranger = actorFor(9999);
      expect(
        () => revokeTokenHandler(db, stranger, id),
        throwsA(isA<NotFoundException>()),
      );
      revokeTokenHandler(db, admin, id);
      expect(
        () => revokeTokenHandler(db, admin, id),
        throwsA(isA<NotFoundException>()),
      );
      final listed = listTokensHandler(db, admin);
      final items = (listed['items']! as List).cast<Map<String, Object?>>();
      expect(items.single['revoked'], isTrue);
    });

    test('a revoked token reports deletes_at at revoked_at + retention', () {
      final result = createTokenHandler(db, admin, name: 'old', scope: 'read');
      final id = (result['item']! as Map<String, Object?>)['id']! as int;
      revokeTokenHandler(db, admin, id);

      Map<String, Object?> listedWith(int days) =>
          (listTokensHandler(db, admin, retentionDays: days)['items']! as List)
              .cast<Map<String, Object?>>()
              .single;

      // Retention 0 ("keep forever") means no scheduled deletion.
      expect(listedWith(0)['deletes_at'], isNull);

      // Retention 90 puts deletion ~90 days out from revocation.
      final deletesAt = DateTime.parse(listedWith(90)['deletes_at']! as String);
      final days = deletesAt.difference(DateTime.now().toUtc()).inDays;
      expect(days, inInclusiveRange(89, 90));
    });
  });

  group('account administration is recorded', () {
    // These handlers had ZERO loggers, so the only trace of an account being
    // created, promoted, disabled, deleted, or of a PAT being minted, was an
    // access line reading `PATCH /users/7 -> 200` — no actor, no target.

    /// Collects `auth` records emitted while [action] runs.
    ///
    /// Deliberately does NOT open the logger: [auditLog] pins its own level so
    /// the trail survives `LOG_LEVEL=WARN`/`ERROR`, and forcing the level here
    /// would mask the removal of that pin. `setUpAll` raises the root level to
    /// prove it.
    Future<List<LogRecord>> capture(Future<void> Function() action) async {
      final records = <LogRecord>[];
      final subscription = auditLog.onRecord.listen(records.add);
      try {
        await action();
        await Future<void>.delayed(Duration.zero);
      } finally {
        await subscription.cancel();
      }
      return records;
    }

    test('every event names the actor and the target', () async {
      late String tempPassword;
      late String patValue;
      late String resetTempPassword;
      late int samId;
      final records = await capture(() async {
        final created = await createUserHandler(
          db,
          hasher,
          admin,
          username: 'sam',
          role: 'member',
        );
        tempPassword = created['temp_password']! as String;
        samId = (created['user']! as Map<String, Object?>)['id']! as int;
        patchUserHandler(db, admin, samId, role: 'admin');
        patchUserHandler(db, admin, samId, disabled: true);
        patchUserHandler(db, admin, samId, disabled: false);

        // After the disable/enable cycle: disabling drops the user's
        // sessions, so a session made earlier would not survive to be
        // revoked here.
        final sam = actorFor(samId, sessionHash: hashToken('sam-session'));
        db.createSession(
          tokenHash: hashToken('sam-session'),
          userId: samId,
          expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
          remember: false,
        );

        final minted = createTokenHandler(
          db,
          sam,
          name: 'kitchen ipad',
          scope: 'full',
        );
        patValue = minted['token']! as String;
        final tokenId = (minted['item']! as Map<String, Object?>)['id']! as int;
        revokeTokenHandler(db, sam, tokenId);
        deleteSessionHandler(db, sam, hashToken('sam-session'));

        final reset = await resetPasswordHandler(db, hasher, admin, samId);
        resetTempPassword = reset['temp_password']! as String;
        deleteUserHandler(db, admin, samId);
      });

      final messages = [for (final record in records) record.message];
      final actor = admin.username;
      final owner = 'user$samId';
      for (final expected in [
        allOf(contains('User created: sam'), contains(actor)),
        allOf(contains('Role changed: sam'), contains(actor)),
        allOf(contains('Account disabled: sam'), contains(actor)),
        allOf(contains('Account enabled: sam'), contains(actor)),
        allOf(contains('API token minted:'), contains(owner)),
        allOf(contains('API token revoked:'), contains(owner)),
        allOf(contains('Session revoked'), contains(owner)),
        allOf(contains('Password reset: sam'), contains(actor)),
        allOf(contains('User deleted: sam'), contains(actor)),
      ]) {
        expect(messages, contains(expected));
      }

      // The token's NAME is caller-supplied text and stays out of the record
      // (it could carry a `rid=` the viewer would adopt as a correlation id);
      // the id and scope identify the token just as well.
      expect(messages, everyElement(isNot(contains('kitchen ipad'))));
      for (final secret in [
        tempPassword,
        resetTempPassword,
        patValue,
        hashToken('sam-session'),
        db.userById(admin.id)!.passwordHash,
      ]) {
        expect(messages, everyElement(isNot(contains(secret))));
      }
    });
  });

  group('a reset that fails leaves no half-done credential state', () {
    test('the eviction and the rotation are one transaction', () async {
      // `updatePasswordHash` revokes INSIDE its own transaction, so the two
      // cannot split. Ordering them was the older, weaker control: whichever
      // ran first, a partial failure still returned a 500 that reads as
      // "nothing happened" over a database where something had happened —
      // and with the rotation first that something is the compromise state
      // (new password committed, every PAT alive). Atomic: both or neither.
      final samId = db.createUser(
        username: 'sam',
        passwordHash: await hasher.hash('a-long-member-password'),
        role: 'member',
      );
      final sam = actorFor(samId);
      createTokenHandler(db, sam, name: 'nightly script', scope: 'full');

      // Hostile condition, synthesized because no request can produce it: a
      // trigger on the test's own database aborts the password UPDATE — and
      // only that UPDATE — the way a disk or constraint failure would.
      final raw = sqlite3.open('${tempDir.path}/salt.db');
      try {
        raw.execute(
          'CREATE TRIGGER halt_rotation AFTER UPDATE OF password_hash '
          "ON users BEGIN SELECT RAISE(ABORT, 'rotation failed'); END",
        );
        await expectLater(
          resetPasswordHandler(db, hasher, admin, samId),
          throwsA(isA<SqliteException>()),
        );
      } finally {
        raw
          ..execute('DROP TRIGGER IF EXISTS halt_rotation')
          ..dispose();
      }

      final items = (listTokensHandler(db, sam)['items']! as List)
          .cast<Map<String, Object?>>();
      final stored = db.userById(samId)!;
      expect(
        stored.mustChangePassword,
        isFalse,
        reason: 'the rotation itself must have rolled back',
      );
      // The forbidden combination is "password rotated, PAT alive". The
      // rotation rolled back, so the revocation must have gone with it —
      // anything else is half a reset the caller was told did not happen.
      expect(
        items.single['revoked'],
        isFalse,
        reason: 'the revocation must roll back with the rotation, not alone',
      );
      // Cheapest proof the two really are welded: the same handler, with
      // nothing sabotaging it, does both.
      final done = await resetPasswordHandler(db, hasher, admin, samId);
      expect(done['revoked_tokens'], 1);
      expect(db.userById(samId)!.mustChangePassword, isTrue);
    });
  });
}
