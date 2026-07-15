import 'package:salt_server/src/auth/password_hasher.dart';
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/auth/setup_code.dart';
import 'package:salt_server/src/auth/tokens.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// Minimum accepted password length.
const int minPasswordLength = 12;

/// Uniform failure message for every unsuccessful login (unknown username,
/// wrong password, disabled account) so responses never reveal which
/// condition failed.
const String _invalidCredentials = 'Invalid username or password.';

final RegExp _usernamePattern =
    RegExp(r'^[a-z0-9_.-]{3,32}$', caseSensitive: false);

/// Process-wide mutable auth collaborators, provided into the request
/// context by `routes/_middleware.dart` (tests construct their own).
///
/// [setupCode] is the one-time first-boot code; it is non-null only while
/// the server has zero users and is cleared the moment setup succeeds.
/// A secret — never log it beyond the deliberate boot-time stdout line.
class AuthRuntime {
  /// Creates the runtime; [hasher] and [rateLimiter] default to production
  /// instances.
  AuthRuntime({
    PasswordHasher? hasher,
    LoginRateLimiter? rateLimiter,
    this.setupCode,
  })  : hasher = hasher ?? PasswordHasher(),
        rateLimiter = rateLimiter ?? LoginRateLimiter();

  /// Argon2id password hasher.
  final PasswordHasher hasher;

  /// Per `ip|username` login throttle.
  final LoginRateLimiter rateLimiter;

  /// First-boot setup code, or null once used (or when users already
  /// exist).
  String? setupCode;
}

/// A newly created session: the raw token (returned to the client exactly
/// once) and the JSON response body.
typedef SessionGrant = ({String token, Map<String, Object?> body});

/// Core of `POST /api/v1/auth/setup`: creates the first admin account.
///
/// Only allowed while the server has zero users ([ForbiddenException]
/// otherwise). [body] must carry `setup_code` matching [AuthRuntime.setupCode]
/// ([ValidationException] otherwise), a valid `username`, and a `password`
/// of at least [minPasswordLength] characters. Creates the admin (no forced
/// password change), consumes the setup code, and opens a non-remember
/// session.
Future<SessionGrant> setupAdmin(
  SaltDatabase db,
  AuthRuntime runtime,
  Map<String, Object?> body, {
  String? userAgent,
}) async {
  if (db.userCount() != 0) {
    throw const ForbiddenException('Setup has already been completed.');
  }
  final expected = runtime.setupCode;
  if (expected == null) {
    throw const ForbiddenException('Setup is not available.');
  }
  final code = requireStringField(body, 'setup_code');
  if (!setupCodeMatches(expected, code)) {
    throw const ValidationException('Invalid setup code.');
  }
  final username = _validUsername(requireStringField(body, 'username'));
  final password = requireStringField(body, 'password');
  _validNewPassword(password, field: 'password');

  final passwordHash = await runtime.hasher.hash(password);
  final userId = db.createUser(
    username: username,
    passwordHash: passwordHash,
    role: 'admin',
  );
  runtime.setupCode = null;
  final token = _openSession(
    db,
    userId: userId,
    remember: false,
    userAgent: userAgent,
  );
  return (
    token: token,
    body: {
      'token': token,
      'user': {'id': userId, 'username': username, 'role': 'admin'},
    },
  );
}

/// Core of `POST /api/v1/auth/login`.
///
/// Rate-limited per `<clientIp>|<username-lowercase>`: when locked, throws
/// [LockedException] carrying the remaining seconds. All failure modes
/// (unknown username — verified against a dummy hash so timing does not
/// leak existence — wrong password, disabled account) throw the same
/// uniform [ValidationException]. On success the failure count resets and
/// a session opens: fixed 7-day expiry, or 90-day sliding when
/// `remember: true`.
Future<SessionGrant> login(
  SaltDatabase db,
  AuthRuntime runtime,
  Map<String, Object?> body, {
  required String clientIp,
  String? userAgent,
}) async {
  final username = requireStringField(body, 'username');
  final password = requireStringField(body, 'password');
  final remember = _optionalBoolField(body, 'remember') ?? false;

  final key = '$clientIp|${username.toLowerCase()}';
  final gate = runtime.rateLimiter.check(key);
  if (!gate.allowed) {
    throw LockedException(_ceilSeconds(gate.retryAfter));
  }

  final user = db.userByUsername(username);
  if (user == null) {
    await runtime.hasher.dummyVerify(password);
    runtime.rateLimiter.recordFailure(key);
    throw const ValidationException(_invalidCredentials);
  }
  final verified = await runtime.hasher.verify(password, user.passwordHash);
  if (!verified || user.disabled) {
    runtime.rateLimiter.recordFailure(key);
    throw const ValidationException(_invalidCredentials);
  }

  runtime.rateLimiter.recordSuccess(key);
  final token = _openSession(
    db,
    userId: user.id,
    remember: remember,
    userAgent: userAgent,
  );
  return (
    token: token,
    body: {
      'token': token,
      'user': {
        'id': user.id,
        'username': user.username,
        'role': user.role,
        'must_change_password': user.mustChangePassword,
      },
    },
  );
}

/// Core of `POST /api/v1/auth/logout`: deletes the current session.
///
/// Only sessions can log out; a PAT gets a [ValidationException] (revoke
/// the token instead).
Map<String, Object?> logoutUser(SaltDatabase db, AuthUser user) {
  final sessionHash = user.sessionHash;
  if (user.via != 'session' || sessionHash == null) {
    throw const ValidationException(
      'A personal access token cannot log out; revoke it instead.',
    );
  }
  db.deleteSession(sessionHash);
  return {'ok': true};
}

/// Body of `GET /api/v1/auth/me` for the authenticated [user].
Map<String, Object?> currentUserBody(AuthUser user) => {
      'user': {
        'id': user.id,
        'username': user.username,
        'role': user.role,
        'must_change_password': user.mustChangePassword,
        'scope': user.scope,
        'via': user.via,
      },
    };

/// Core of `POST /api/v1/auth/change_password`.
///
/// PATs may not change passwords ([ForbiddenException]). `current_password`
/// is required and verified unless the account is flagged
/// must-change-password (its holder proved nothing but a temp credential,
/// which is exactly what is being replaced). The new password must be at
/// least [minPasswordLength] characters. All other sessions of the user are
/// deleted; the current one is kept.
Future<Map<String, Object?>> changePassword(
  SaltDatabase db,
  AuthRuntime runtime,
  AuthUser user,
  Map<String, Object?> body,
) async {
  if (user.via != 'session') {
    throw const ForbiddenException(
      'A personal access token cannot change the password.',
    );
  }
  final newPassword = requireStringField(body, 'new_password');
  _validNewPassword(newPassword, field: 'new_password');

  final row = db.userById(user.id);
  if (row == null) {
    throw const UnauthorizedException();
  }
  if (!row.mustChangePassword) {
    final current = requireStringField(body, 'current_password');
    final verified = await runtime.hasher.verify(current, row.passwordHash);
    if (!verified) {
      throw const ValidationException('Current password is incorrect.');
    }
  }
  final passwordHash = await runtime.hasher.hash(newPassword);
  db.updatePasswordHash(
    user.id,
    passwordHash,
    mustChangePassword: false,
    keepSessionHash: user.sessionHash,
  );
  return {'ok': true};
}

/// `Set-Cookie` value installing the session [token] (HttpOnly,
/// SameSite=Lax, plus `Secure` when [secure]).
String sessionCookie(String token, {required bool secure}) =>
    '$sessionCookieName=$token; Path=/; HttpOnly; SameSite=Lax'
    '${secure ? '; Secure' : ''}';

/// `Set-Cookie` value clearing the session cookie (logout).
String expiredSessionCookie({required bool secure}) =>
    '$sessionCookieName=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0; '
    'Expires=Thu, 01 Jan 1970 00:00:00 GMT${secure ? '; Secure' : ''}';

/// Awaits [readJson] (pass `context.request.json`) and requires the result
/// to be a JSON object; throws [ValidationException] on malformed JSON or
/// any other shape.
Future<Map<String, Object?>> readJsonBody(
  Future<Object?> Function() readJson,
) async {
  Object? decoded;
  try {
    decoded = await readJson();
  } on FormatException {
    throw const ValidationException('Request body must be valid JSON.');
  }
  if (decoded is! Map<String, Object?>) {
    throw const ValidationException('Request body must be a JSON object.');
  }
  return decoded;
}

/// Returns the non-empty string field [name] of [body], or throws
/// [ValidationException].
String requireStringField(Map<String, Object?> body, String name) {
  final value = body[name];
  if (value is! String || value.isEmpty) {
    throw ValidationException("'$name' is required.");
  }
  return value;
}

bool? _optionalBoolField(Map<String, Object?> body, String name) {
  final value = body[name];
  if (value == null) {
    return null;
  }
  if (value is! bool) {
    throw ValidationException("'$name' must be a boolean.");
  }
  return value;
}

String _validUsername(String username) {
  if (!_usernamePattern.hasMatch(username)) {
    throw const ValidationException(
      'Username must be 3-32 characters: letters, digits, '
      'underscore, dot, or dash.',
    );
  }
  return username;
}

void _validNewPassword(String password, {required String field}) {
  if (password.length < minPasswordLength) {
    throw ValidationException(
      "'$field' must be at least $minPasswordLength characters.",
    );
  }
}

String _openSession(
  SaltDatabase db, {
  required int userId,
  required bool remember,
  String? userAgent,
}) {
  final token = generateOpaqueToken();
  final now = DateTime.now().toUtc();
  db
    ..createSession(
      tokenHash: hashToken(token),
      userId: userId,
      expiresAt:
          now.add(remember ? rememberSessionLifetime : sessionLifetime),
      remember: remember,
      userAgent: userAgent,
    )
    ..touchUserActivity(userId);
  return token;
}

int _ceilSeconds(Duration duration) {
  final seconds = (duration.inMilliseconds + 999) ~/ 1000;
  return seconds < 1 ? 1 : seconds;
}
