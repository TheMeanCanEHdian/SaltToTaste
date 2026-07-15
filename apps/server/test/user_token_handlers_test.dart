import 'dart:io';

import 'package:salt_server/src/auth/password_hasher.dart';
import 'package:salt_server/src/auth/tokens.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/token_handlers.dart';
import 'package:salt_server/src/handlers/user_handlers.dart';
import 'package:salt_server/src/middleware/auth.dart';
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
  }) =>
      AuthUser(
        id: id,
        username: 'user$id',
        role: role,
        mustChangePassword: false,
        scope: scope,
        via: sessionHash == null ? 'pat' : 'session',
        sessionHash: sessionHash,
      );

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

    test('reset password issues a new temp and kills sessions', () async {
      final created = await createUserHandler(
        db,
        hasher,
        admin,
        username: 'sam',
        role: 'member',
      );
      final samId =
          (created['user']! as Map<String, Object?>)['id']! as int;
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
  });
}
