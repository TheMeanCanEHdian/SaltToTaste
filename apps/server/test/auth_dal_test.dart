import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

// Auth inputs are synthesized credentials — they cannot come from the recipe
// corpus. No real secrets appear here.
const _hashA = r'$argon2id$v=19$m=65536,t=3,p=4$c2ludGgtc2FsdA$ZmFrZS1oYXNoLWE';
const _hashB = r'$argon2id$v=19$m=65536,t=3,p=4$c2ludGgtc2FsdA$ZmFrZS1oYXNoLWI';

/// A deterministic 64-char fake SHA-256 hex digest for [seed].
String _fakeTokenHash(String seed) => seed.codeUnits
    .map((u) => u.toRadixString(16).padLeft(2, '0'))
    .join()
    .padRight(64, '0');

void main() {
  late Directory tempDir;
  late String dbPath;
  late SaltDatabase db;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('salt_auth_dal_test');
    dbPath = '${tempDir.path}/salt.db';
    db = SaltDatabase.open(dbPath);
  });

  tearDown(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  int createDenis({String role = 'admin'}) =>
      db.createUser(username: 'denis', passwordHash: _hashA, role: role);

  test('migration 002 applies: auth tables exist', () {
    final raw = sqlite3.open(dbPath);
    addTearDown(raw.dispose);
    expect(
      raw.select('PRAGMA user_version').first.columnAt(0) as int,
      greaterThanOrEqualTo(2),
    );
    final tables = raw
        .select(
          "SELECT name FROM sqlite_master WHERE type IN ('table', 'index') "
          'ORDER BY name',
        )
        .map((row) => row['name'] as String)
        .toSet();
    expect(
      tables,
      containsAll([
        'users',
        'sessions',
        'api_tokens',
        'idx_sessions_user_id',
        'idx_api_tokens_user_id',
      ]),
    );
  });

  group('users', () {
    test('createUser returns id; lookups roundtrip all fields', () {
      expect(db.userCount(), 0);
      final id = db.createUser(
        username: 'denis',
        passwordHash: _hashA,
        role: 'admin',
        mustChangePassword: true,
      );
      expect(db.userCount(), 1);

      final byName = db.userByUsername('denis');
      expect(byName, isNotNull);
      expect(byName!.id, id);
      expect(byName.username, 'denis');
      expect(byName.passwordHash, _hashA);
      expect(byName.role, 'admin');
      expect(byName.mustChangePassword, isTrue);
      expect(byName.disabled, isFalse);
      expect(byName.createdAt, isNotEmpty);
      expect(byName.lastActiveAt, isNull);

      final byId = db.userById(id);
      expect(byId, isNotNull);
      expect(byId!.username, 'denis');

      expect(db.userById(id + 999), isNull);
      expect(db.userByUsername('nobody'), isNull);
    });

    test('username lookup is case-insensitive', () {
      db.createUser(username: 'Denis', passwordHash: _hashA, role: 'admin');
      expect(db.userByUsername('denis'), isNotNull);
      expect(db.userByUsername('DENIS'), isNotNull);
    });

    test("duplicate username 'Denis' vs 'denis' throws SqliteException", () {
      db.createUser(username: 'Denis', passwordHash: _hashA, role: 'admin');
      expect(
        () => db.createUser(
          username: 'denis',
          passwordHash: _hashB,
          role: 'member',
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(db.userCount(), 1);
    });

    test('listUsers returns all users ordered by username', () {
      db
        ..createUser(username: 'zoe', passwordHash: _hashA, role: 'member')
        ..createUser(username: 'Alice', passwordHash: _hashA, role: 'admin');
      final users = db.listUsers();
      expect([for (final u in users) u.username], ['Alice', 'zoe']);
    });

    test('setUserRole updates role', () {
      final id = createDenis();
      db.setUserRole(id, 'member');
      expect(db.userById(id)!.role, 'member');
    });

    test('touchUserActivity sets last_active_at', () {
      final id = createDenis();
      expect(db.userById(id)!.lastActiveAt, isNull);
      db.touchUserActivity(id);
      final touched = db.userById(id)!.lastActiveAt;
      expect(touched, isNotNull);
      expect(DateTime.parse(touched!).isUtc, isTrue);
    });
  });

  group('password update and disable vs sessions', () {
    final future = DateTime.now().toUtc().add(const Duration(days: 7));

    test(
      'updatePasswordHash deletes other sessions, keeps keepSessionHash',
      () {
        final id = createDenis();
        final keep = _fakeTokenHash('session-keep');
        final drop1 = _fakeTokenHash('session-drop-1');
        final drop2 = _fakeTokenHash('session-drop-2');
        for (final hash in [keep, drop1, drop2]) {
          db.createSession(
            tokenHash: hash,
            userId: id,
            expiresAt: future,
            remember: false,
          );
        }

        db.updatePasswordHash(
          id,
          _hashB,
          mustChangePassword: false,
          // This case is about which SESSIONS survive; token eviction is
          // covered by its own tests.
          revokeApiTokens: false,
          keepSessionHash: keep,
        );

        expect(db.sessionByHash(keep), isNotNull);
        expect(db.sessionByHash(drop1), isNull);
        expect(db.sessionByHash(drop2), isNull);
        final user = db.userById(id)!;
        expect(user.passwordHash, _hashB);
        expect(user.mustChangePassword, isFalse);
      },
    );

    test('updatePasswordHash without keepSessionHash deletes all sessions', () {
      final id = createDenis();
      db
        ..createSession(
          tokenHash: _fakeTokenHash('session-reset'),
          userId: id,
          expiresAt: future,
          remember: true,
        )
        ..updatePasswordHash(
          id,
          _hashB,
          mustChangePassword: true,
          revokeApiTokens: false,
        );
      expect(db.sessionsForUser(id), isEmpty);
      expect(db.userById(id)!.mustChangePassword, isTrue);
    });

    test("disabling a user deletes its sessions, not other users'", () {
      final denis = createDenis();
      final other = db.createUser(
        username: 'alice',
        passwordHash: _hashB,
        role: 'member',
      );
      db
        ..createSession(
          tokenHash: _fakeTokenHash('denis-session'),
          userId: denis,
          expiresAt: future,
          remember: false,
        )
        ..createSession(
          tokenHash: _fakeTokenHash('alice-session'),
          userId: other,
          expiresAt: future,
          remember: false,
        )
        ..setUserDisabled(denis, disabled: true);

      expect(db.userById(denis)!.disabled, isTrue);
      expect(db.sessionsForUser(denis), isEmpty);
      expect(db.sessionsForUser(other), hasLength(1));

      db.setUserDisabled(denis, disabled: false);
      expect(db.userById(denis)!.disabled, isFalse);
    });
  });

  group('sessions', () {
    test('expiry roundtrips as an equal UTC DateTime', () {
      final id = createDenis();
      final hash = _fakeTokenHash('roundtrip');
      final expires = DateTime.utc(2026, 8, 1, 12, 30, 15, 250);
      db.createSession(
        tokenHash: hash,
        userId: id,
        expiresAt: expires,
        remember: true,
        userAgent: 'salt-test/1.0',
      );

      final row = db.sessionByHash(hash);
      expect(row, isNotNull);
      expect(row!.tokenHash, hash);
      expect(row.userId, id);
      expect(row.expiresAt, expires);
      expect(row.expiresAt.isUtc, isTrue);
      expect(row.remember, isTrue);
      expect(row.createdAt, isNotEmpty);
      expect(row.lastSeenAt, isNull);
      expect(row.userAgent, 'salt-test/1.0');

      expect(db.sessionByHash(_fakeTokenHash('absent')), isNull);
    });

    test('a local-time expiry is stored and read back as UTC', () {
      final id = createDenis();
      final hash = _fakeTokenHash('local-in');
      final local = DateTime(2026, 8, 1, 8, 30, 15);
      db.createSession(
        tokenHash: hash,
        userId: id,
        expiresAt: local,
        remember: false,
      );
      final row = db.sessionByHash(hash)!;
      expect(row.expiresAt.isUtc, isTrue);
      expect(row.expiresAt, local.toUtc());
    });

    test('touchSession sets last_seen_at; extendTo also moves expires_at', () {
      final id = createDenis();
      final hash = _fakeTokenHash('touch');
      final expires = DateTime.utc(2026, 8, 1, 12);
      db
        ..createSession(
          tokenHash: hash,
          userId: id,
          expiresAt: expires,
          remember: true,
        )
        ..touchSession(hash);
      var row = db.sessionByHash(hash)!;
      expect(row.lastSeenAt, isNotNull);
      expect(row.expiresAt, expires, reason: 'no extendTo: expiry unchanged');

      final extended = expires.add(const Duration(days: 90));
      db.touchSession(hash, extendTo: extended);
      row = db.sessionByHash(hash)!;
      expect(row.expiresAt, extended);
    });

    test('deleteSession removes the row; sessionsForUser lists the rest', () {
      final id = createDenis();
      final gone = _fakeTokenHash('gone');
      final kept = _fakeTokenHash('kept');
      final future = DateTime.now().toUtc().add(const Duration(days: 7));
      db
        ..createSession(
          tokenHash: gone,
          userId: id,
          expiresAt: future,
          remember: false,
        )
        ..createSession(
          tokenHash: kept,
          userId: id,
          expiresAt: future,
          remember: false,
        )
        ..deleteSession(gone);
      final remaining = db.sessionsForUser(id);
      expect([for (final s in remaining) s.tokenHash], [kept]);
    });

    test('deleteExpiredSessions removes only expired sessions', () {
      final id = createDenis();
      final expired = _fakeTokenHash('expired');
      final live = _fakeTokenHash('live');
      final now = DateTime.now().toUtc();
      db
        ..createSession(
          tokenHash: expired,
          userId: id,
          expiresAt: now.subtract(const Duration(hours: 1)),
          remember: false,
        )
        ..createSession(
          tokenHash: live,
          userId: id,
          expiresAt: now.add(const Duration(days: 7)),
          remember: true,
        )
        ..deleteExpiredSessions();
      expect(db.sessionByHash(expired), isNull);
      expect(db.sessionByHash(live), isNotNull);
    });
  });

  group('api tokens', () {
    test('create, lookup by hash, touch, and list roundtrip', () {
      final id = createDenis();
      final hash = _fakeTokenHash('pat-1');
      final tokenId = db.createApiToken(
        userId: id,
        name: 'CI read token',
        prefix: 'stt_pat_AbCd',
        tokenHash: hash,
        scope: 'read',
      );

      final row = db.apiTokenByHash(hash);
      expect(row, isNotNull);
      expect(row!.id, tokenId);
      expect(row.userId, id);
      expect(row.name, 'CI read token');
      expect(row.prefix, 'stt_pat_AbCd');
      expect(row.scope, 'read');
      expect(row.createdAt, isNotEmpty);
      expect(row.lastUsedAt, isNull);
      expect(row.revokedAt, isNull);

      db.touchApiToken(tokenId);
      expect(db.apiTokenByHash(hash)!.lastUsedAt, isNotNull);

      final listed = db.apiTokensForUser(id);
      expect(listed, hasLength(1));
      expect(listed.single.id, tokenId);
      expect(db.apiTokensForUser(id + 999), isEmpty);
      expect(db.apiTokenByHash(_fakeTokenHash('absent-pat')), isNull);
    });

    test('duplicate token_hash throws SqliteException', () {
      final id = createDenis();
      final hash = _fakeTokenHash('pat-dup');
      db.createApiToken(
        userId: id,
        name: 'first',
        prefix: 'stt_pat_AbCd',
        tokenHash: hash,
        scope: 'full',
      );
      expect(
        () => db.createApiToken(
          userId: id,
          name: 'second',
          prefix: 'stt_pat_EfGh',
          tokenHash: hash,
          scope: 'read',
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('revokeApiToken enforces ownership and single revocation', () {
      final owner = createDenis();
      final stranger = db.createUser(
        username: 'alice',
        passwordHash: _hashB,
        role: 'member',
      );
      final hash = _fakeTokenHash('pat-revoke');
      final tokenId = db.createApiToken(
        userId: owner,
        name: 'to revoke',
        prefix: 'stt_pat_WxYz',
        tokenHash: hash,
        scope: 'full',
      );

      expect(db.revokeApiToken(id: tokenId, userId: stranger), isFalse);
      expect(
        db.apiTokenByHash(hash)!.revokedAt,
        isNull,
        reason: 'wrong owner must not revoke',
      );

      expect(db.revokeApiToken(id: tokenId, userId: owner), isTrue);
      final revokedAt = db.apiTokenByHash(hash)!.revokedAt;
      expect(revokedAt, isNotNull);
      expect(DateTime.parse(revokedAt!).isUtc, isTrue);

      expect(
        db.revokeApiToken(id: tokenId, userId: owner),
        isFalse,
        reason: 'already revoked',
      );
      expect(
        db.revokeApiToken(id: tokenId + 999, userId: owner),
        isFalse,
        reason: 'nonexistent id',
      );
    });

    test('deleteRevokedApiTokensBefore prunes only old revoked tokens', () {
      final owner = createDenis();
      final revokedHash = _fakeTokenHash('pat-old');
      final revokedId = db.createApiToken(
        userId: owner,
        name: 'revoked',
        prefix: 'stt_pat_Old0',
        tokenHash: revokedHash,
        scope: 'read',
      );
      db.revokeApiToken(id: revokedId, userId: owner); // revoked_at ~= now
      final activeHash = _fakeTokenHash('pat-active');
      db.createApiToken(
        userId: owner,
        name: 'active',
        prefix: 'stt_pat_Act0',
        tokenHash: activeHash,
        scope: 'read',
      );

      // A cutoff BEFORE the revocation prunes nothing.
      expect(
        db.deleteRevokedApiTokensBefore(
          DateTime.now().toUtc().subtract(const Duration(days: 1)),
        ),
        0,
        reason: 'a recently revoked token is within the window',
      );
      expect(db.apiTokenByHash(revokedHash), isNotNull);

      // A cutoff AFTER the revocation prunes the revoked row — and only it.
      final pruned = db.deleteRevokedApiTokensBefore(
        DateTime.now().toUtc().add(const Duration(days: 1)),
      );
      expect(pruned, 1);
      expect(db.apiTokenByHash(revokedHash), isNull, reason: 'revoked pruned');
      expect(
        db.apiTokenByHash(activeHash),
        isNotNull,
        reason: 'an active (unrevoked) token is never pruned',
      );
    });
  });
}
