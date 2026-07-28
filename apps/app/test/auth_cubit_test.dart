import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salt_app/core/api/auth_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/features/auth/auth_cubit.dart';

import 'support/contract_goldens.dart';

/// The session state machine that gates the whole router.
///
/// Deliberately corpus-free — nothing here is recipe data, so CI (which has
/// no ATK corpus) runs every one of these. The transport is a canned Dio
/// adapter so the cubit drives the REAL [AuthRepository], including its
/// error-envelope decoding and its "a 401 on /auth/me means signed out"
/// rule.
///
/// Every success body is a committed contract golden — a real body captured
/// from the real server routes (`packages/salt_shared/test/fixtures/
/// contract/`), not a hand-built look-alike. A hand-built one is a SECOND,
/// unlinked definition of the wire shape: it stays green through any
/// server-side change, and it silently drops the fields the server really
/// sends (the captured `/auth/me` carries `scope` and `via`).
class _FakeAdapter implements HttpClientAdapter {
  /// Canned `(status, jsonBody)` per request path.
  final Map<String, (int, Map<String, Object?>)> routes = {};

  /// Every path requested, in order.
  final List<String> calls = [];

  /// When true every request fails as a transport error.
  bool offline = false;

  void ok(String path, Map<String, Object?> body) => routes[path] = (200, body);

  void fail(String path, int status, String code, [String? message]) =>
      routes[path] = (
        status,
        {
          'error': {
            'code': code,
            if (message != null) 'message': message,
            'request_id': 'req-test',
          },
        },
      );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options.path);
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no server in this test',
      );
    }
    final route = routes[options.path];
    if (route == null) {
      return ResponseBody.fromString(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'unrouted'},
        }),
        404,
        headers: _json,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(route.$2),
      route.$1,
      headers: _json,
    );
  }

  @override
  void close({bool force = false}) {}

  static final _json = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };
}

/// Real captured `/api/v1/auth/me` for an ordinary admin.
final _adminMe = golden('auth_me_admin');

/// Real captured `/api/v1/auth/me` for an account the server is forcing
/// through a password change (a MEMBER, so the role axis is real too).
final _forcedMe = golden('auth_me_must_change');

/// Real captured `/api/v1/auth/login` bodies for those two accounts.
final _adminLogin = golden('auth_login_admin');
final _forcedLogin = golden('auth_login_must_change');

/// Real captured `/api/v1/auth/change_password` success body.
final _changePasswordOk = golden('auth_change_password');

/// The `user` sub-object of a captured auth body.
Map<String, dynamic> _user(Map<String, dynamic> body) =>
    body['user']! as Map<String, dynamic>;

/// The captured admin's real username, used as login INPUT.
String get _adminUsername => '${_user(_adminMe)['username']}';

const _healthz = '/healthz';
const _me = '/api/v1/auth/me';
const _login = '/api/v1/auth/login';
const _logout = '/api/v1/auth/logout';
const _changePassword = '/api/v1/auth/change_password';

void main() {
  late _FakeAdapter adapter;
  late AuthCubit cubit;
  late List<AuthState> seen;

  setUp(() {
    adapter = _FakeAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;
    cubit = AuthCubit(AuthRepository(dio));
    seen = [];
    final sub = cubit.stream.listen(seen.add);
    addTearDown(sub.cancel);
    addTearDown(cubit.close);
  });

  /// Lets the broadcast stream deliver everything emitted so far.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// A claimed instance that answers `/auth/me` with the captured body [me].
  void claimedAndSignedIn(Map<String, dynamic> me) {
    adapter
      ..ok(_healthz, {'setup_required': false})
      ..ok(_me, me);
  }

  group('bootstrap', () {
    test('an unclaimed instance asks for setup and never calls /me', () async {
      adapter.ok(_healthz, {'setup_required': true});

      await cubit.bootstrap();
      await settle();

      expect(seen, [isA<AuthUnknown>(), isA<AuthSetupRequired>()]);
      expect(
        adapter.calls,
        [_healthz],
        reason: 'setup screens must not depend on an /auth/me round trip',
      );
      expect(cubit.user, isNull);
    });

    test('no session lands on the login page with no notice', () async {
      adapter
        ..ok(_healthz, {'setup_required': false})
        ..fail(_me, 401, 'unauthorized', 'Sign in to continue.');

      await cubit.bootstrap();
      await settle();

      expect(seen, [isA<AuthUnknown>(), isA<AuthSignedOut>()]);
      expect(
        (seen.last as AuthSignedOut).notice,
        isNull,
        reason: 'a cold start is not an expiry — no scary banner',
      );
    });

    test('a live session lands signed in with the account', () async {
      final expected = _user(_adminMe);
      expect(
        expected.keys,
        containsAll(<String>['scope', 'via']),
        reason:
            'the captured body carries fields the app ignores; a hand-built '
            'fake would silently drop them',
      );
      expect(expected['role'], 'admin', reason: 'the captured role');
      claimedAndSignedIn(_adminMe);

      await cubit.bootstrap();
      await settle();

      expect(seen, [isA<AuthUnknown>(), isA<AuthSignedIn>()]);
      final user = (seen.last as AuthSignedIn).user;
      expect(user.id, expected['id']);
      expect(user.username, expected['username']);
      expect(user.role, expected['role']);
      expect(user.isAdmin, isTrue);
      expect(user.mustChangePassword, expected['must_change_password']);
      expect(cubit.user, same(user));
    });

    test('must_change_password true forces the change screen', () async {
      // The server contract T5 pins from the other side: this exact key,
      // carrying true, is what strands the router on /change-password.
      final expected = _user(_forcedMe);
      expect(
        expected['must_change_password'],
        isTrue,
        reason: 'the golden must describe a forced-change account',
      );
      claimedAndSignedIn(_forcedMe);

      await cubit.bootstrap();
      await settle();

      expect(seen, [isA<AuthUnknown>(), isA<AuthPasswordChangeRequired>()]);
      expect(
        cubit.user?.mustChangePassword,
        isTrue,
        reason: 'the forced-change screen still needs the account',
      );
      expect(cubit.user?.username, expected['username']);
      expect(
        cubit.user?.isAdmin,
        isFalse,
        reason: "the captured account's role is member",
      );
    });

    test('an absent must_change_password key means not forced', () async {
      // AuthUserInfo.fromJson defaults the flag to false, so a body without
      // the key is a normal sign-in — the documented default, and the
      // fail-OPEN direction: dropping the key from the one body that
      // carries `true` signs the account straight in.
      claimedAndSignedIn({
        'user': Map<String, dynamic>.from(_user(_forcedMe))
          ..remove('must_change_password'),
      });

      await cubit.bootstrap();
      await settle();

      expect(seen.last, isA<AuthSignedIn>());
      expect(cubit.user!.mustChangePassword, isFalse);
    });

    test('an unreachable server shows retry, not a login form', () async {
      adapter.offline = true;

      await cubit.bootstrap();
      await settle();

      expect(seen, [isA<AuthUnknown>(), isA<AuthBootstrapFailed>()]);
      expect(
        (seen.last as AuthBootstrapFailed).message,
        startsWith("Couldn't reach"),
        reason: 'the repository message must reach the retry screen verbatim',
      );
    });

    test('a malformed 200 body fails bootstrap instead of stranding', () async {
      adapter
        ..ok(_healthz, {'setup_required': false})
        ..ok(_me, {'user': 'not an object'});

      await cubit.bootstrap();
      await settle();

      expect(seen, [isA<AuthUnknown>(), isA<AuthBootstrapFailed>()]);
      expect((seen.last as AuthBootstrapFailed).message, isNotEmpty);
    });

    test('a re-bootstrap re-shows the splash before deciding', () async {
      claimedAndSignedIn(_adminMe);
      await cubit.bootstrap();
      await settle();
      seen.clear();

      adapter.fail(_me, 401, 'unauthorized', 'Sign in to continue.');
      await cubit.bootstrap();
      await settle();

      expect(seen, [isA<AuthUnknown>(), isA<AuthSignedOut>()]);
      expect(cubit.user, isNull);
    });
  });

  group('sessionExpired', () {
    test('a signed-in session drops to signed out with a notice', () async {
      claimedAndSignedIn(_adminMe);
      await cubit.bootstrap();
      await settle();
      seen.clear();

      cubit.sessionExpired();
      await settle();

      expect(seen, [isA<AuthSignedOut>()]);
      expect(
        (seen.single as AuthSignedOut).notice,
        'Your session expired. Sign in again.',
      );
      expect(
        cubit.user,
        isNull,
        reason: 'a stale user would keep admin-only UI reachable',
      );
    });

    test('a forced-password-change session also drops out', () async {
      claimedAndSignedIn(_forcedMe);
      await cubit.bootstrap();
      await settle();
      seen.clear();

      cubit.sessionExpired();
      await settle();

      expect(seen, [isA<AuthSignedOut>()]);
      expect(cubit.user, isNull);
    });

    test('an already signed-out cubit emits nothing', () async {
      adapter
        ..ok(_healthz, {'setup_required': false})
        ..fail(_me, 401, 'unauthorized', 'Sign in to continue.');
      await cubit.bootstrap();
      await settle();
      seen.clear();

      cubit.sessionExpired();
      await settle();

      expect(
        seen,
        isEmpty,
        reason: 'concurrent 401s must not overwrite the login page notice',
      );
    });

    test('a bootstrap-failed cubit is not turned into a login page', () async {
      adapter.offline = true;
      await cubit.bootstrap();
      await settle();
      seen.clear();

      cubit.sessionExpired();
      await settle();

      expect(seen, isEmpty);
      expect(cubit.state, isA<AuthBootstrapFailed>());
    });
  });

  group('login', () {
    setUp(() async {
      adapter
        ..ok(_healthz, {'setup_required': false})
        ..fail(_me, 401, 'unauthorized', 'Sign in to continue.');
      await cubit.bootstrap();
      await settle();
      seen.clear();
    });

    test('bad credentials throw and leave the cubit usable', () async {
      adapter.fail(_login, 401, 'unauthorized', 'Wrong username or password.');

      await expectLater(
        cubit.login(
          username: _adminUsername,
          password: 'nope',
          remember: false,
        ),
        throwsA(
          isA<RepositoryException>()
              .having(
                (e) => e.message,
                'message',
                'Wrong username or password.',
              )
              .having((e) => e.code, 'code', 'unauthorized'),
        ),
      );
      await settle();

      expect(
        seen,
        isEmpty,
        reason: 'a rejected sign-in must not move the router anywhere',
      );
      expect(cubit.state, isA<AuthSignedOut>());

      // Not wedged: the very next attempt still works.
      adapter.ok(_login, _adminLogin);
      await cubit.login(
        username: '${_user(_adminLogin)['username']}',
        password: 'right',
        remember: true,
      );
      await settle();

      expect(seen, [isA<AuthSignedIn>()]);
      expect(cubit.user?.username, _user(_adminLogin)['username']);
      expect(cubit.user?.id, _user(_adminLogin)['id']);
    });

    test('a locked-out account surfaces the server message', () async {
      adapter.fail(_login, 429, 'locked', 'Too many attempts. Try later.');

      await expectLater(
        cubit.login(username: _adminUsername, password: 'x', remember: false),
        throwsA(
          isA<RepositoryException>()
              .having((e) => e.code, 'code', 'locked')
              .having(
                (e) => e.message,
                'message',
                'Too many attempts. Try later.',
              ),
        ),
      );
      await settle();
      expect(seen, isEmpty);
    });

    test('an unreachable server throws without changing state', () async {
      adapter.offline = true;

      await expectLater(
        cubit.login(username: _adminUsername, password: 'x', remember: false),
        throwsA(isA<RepositoryException>()),
      );
      await settle();

      expect(seen, isEmpty);
      expect(cubit.state, isA<AuthSignedOut>());
    });

    test('a temp password signs in straight to the change screen', () async {
      // The real login body for the account created with a temp password.
      expect(_user(_forcedLogin)['must_change_password'], isTrue);
      adapter.ok(_login, _forcedLogin);

      await cubit.login(
        username: '${_user(_forcedLogin)['username']}',
        password: 'temp',
        remember: false,
      );
      await settle();

      expect(seen, [isA<AuthPasswordChangeRequired>()]);
      expect(cubit.user?.mustChangePassword, isTrue);
      expect(cubit.user?.username, _user(_forcedLogin)['username']);
    });
  });

  group('changePassword', () {
    setUp(() async {
      claimedAndSignedIn(_forcedMe);
      await cubit.bootstrap();
      await settle();
      seen.clear();
    });

    test('success clears the forced-change flag, keeping identity', () async {
      adapter.ok(_changePassword, _changePasswordOk);

      await cubit.changePassword(currentPassword: 'temp', newPassword: 'new');
      await settle();

      expect(seen, [isA<AuthSignedIn>()]);
      final expected = _user(_forcedMe);
      final user = (seen.single as AuthSignedIn).user;
      expect(user.mustChangePassword, isFalse);
      expect(user.id, expected['id']);
      expect(user.username, expected['username']);
      expect(user.role, expected['role']);
    });

    test('a rejected password keeps the user locked on the screen', () async {
      adapter.fail(
        _changePassword,
        422,
        'validation',
        'Password is too common.',
      );

      await expectLater(
        cubit.changePassword(currentPassword: 'temp', newPassword: 'password'),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.message,
            'message',
            'Password is too common.',
          ),
        ),
      );
      await settle();

      expect(
        seen,
        isEmpty,
        reason: 'a failed change must not be reported as done',
      );
      expect(cubit.state, isA<AuthPasswordChangeRequired>());
    });
  });

  group('signOut', () {
    setUp(() async {
      claimedAndSignedIn(_adminMe);
      await cubit.bootstrap();
      await settle();
      seen.clear();
    });

    test('clears the session and says so', () async {
      // There is no logout golden: AuthRepository.logout() discards the body
      // entirely, so an `{ok: true}` stand-in defines no wire shape.
      adapter.ok(_logout, {'ok': true});

      await cubit.signOut();
      await settle();

      expect(seen, [isA<AuthSignedOut>()]);
      expect((seen.single as AuthSignedOut).notice, 'Signed out.');
      expect(cubit.user, isNull);
      expect(adapter.calls, contains(_logout));
    });

    test('still signs out locally when the server rejects it', () async {
      // The session may already be gone server-side; the user pressed
      // "Sign out" and must end up signed out regardless.
      adapter.fail(_logout, 401, 'unauthorized', 'Sign in to continue.');

      await cubit.signOut();
      await settle();

      expect(seen, [isA<AuthSignedOut>()]);
      expect(cubit.user, isNull);
    });

    test('still signs out locally when the server is unreachable', () async {
      adapter.offline = true;

      await cubit.signOut();
      await settle();

      expect(seen, [isA<AuthSignedOut>()]);
      expect(cubit.state, isA<AuthSignedOut>());
    });
  });
}
