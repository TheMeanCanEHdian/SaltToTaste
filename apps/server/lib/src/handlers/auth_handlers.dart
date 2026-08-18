import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_frog/dart_frog.dart' show Request;
import 'package:logging/logging.dart';
import 'package:salt_server/src/auth/password_hasher.dart';
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/auth/recovery.dart';
import 'package:salt_server/src/auth/setup_code.dart';
import 'package:salt_server/src/auth/tokens.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/middleware/auth.dart';

final Logger _log = Logger('auth');

/// Minimum accepted password length.
const int minPasswordLength = 12;

/// Uniform failure message for an unsuccessful login (unknown username or
/// wrong password) so responses never reveal which condition failed.
const String _invalidCredentials = 'Invalid username or password.';

/// Shown when the password checks out but the account is disabled. Reachable
/// only *after* a correct password, so — unlike a state check before auth —
/// it cannot enumerate usernames or account state: an attacker without the
/// password still gets [_invalidCredentials]. It only tells the account's own
/// owner why a correct password was refused.
const String _accountDisabled =
    'This account has been disabled. Contact an administrator.';

/// Shown when no recovery code is pending (or the pending one expired):
/// names the command that opens the window, since only someone on the
/// server host can run it anyway.
const String _recoveryUnavailable =
    'Account recovery is not open. Run "dart run salt_server:recover" on '
    'the server to get a code.';

final RegExp _usernamePattern = RegExp(
  r'^[a-z0-9_.-]{3,32}$',
  caseSensitive: false,
);

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
    LoginRateLimiter? ipRateLimiter,
    ConcurrencyGate? verifyGate,
    this.setupCode,
  }) : hasher = hasher ?? PasswordHasher(),
       rateLimiter = rateLimiter ?? LoginRateLimiter(),
       ipRateLimiter =
           ipRateLimiter ??
           LoginRateLimiter(failureThreshold: ipFailureThreshold),
       verifyGate =
           verifyGate ?? ConcurrencyGate(limit: maxConcurrentVerifications);

  /// Aggregate failures from one address at which the whole IP locks —
  /// catches password spraying across many usernames, which per-account
  /// keys can't see.
  static const int ipFailureThreshold = 25;

  /// Password verifications allowed in flight at once, across all accounts
  /// and addresses.
  ///
  /// The per-key throttles cannot bound this: an attacker spreading guesses
  /// over many usernames stays under every threshold while still starting an
  /// unbounded number of hashes, and each Argon2id holds ~19 MiB on the one
  /// serving isolate. At this limit a burst costs roughly 150 MiB instead of
  /// the 2.9 GiB measured before the gate — enough headroom that ordinary
  /// simultaneous logins never touch it.
  static const int maxConcurrentVerifications = 8;

  /// Argon2id password hasher.
  final PasswordHasher hasher;

  /// Per `ip|username` login throttle (vertical brute force).
  final LoginRateLimiter rateLimiter;

  /// Per-IP aggregate throttle (horizontal password spraying).
  final LoginRateLimiter ipRateLimiter;

  /// Ceiling on simultaneous password verifications.
  final ConcurrencyGate verifyGate;

  /// First-boot setup code, or null once used (or when users already
  /// exist).
  String? setupCode;
}

/// A newly created session: the raw token (returned to the client exactly
/// once), the JSON response body, and whether this is a "remember me" session
/// — which the route needs, because the cookie has to say so too.
typedef SessionGrant = ({
  String token,
  Map<String, Object?> body,
  bool remember,
});

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
  // Re-check after the ~100ms hash await: two concurrent setup requests
  // could both pass the guards above while suspended, and "first boot
  // creates exactly one admin" must hold. No awaits below this check.
  if (db.userCount() != 0 || runtime.setupCode == null) {
    throw const ForbiddenException('Setup has already been completed.');
  }
  runtime.setupCode = null;
  final userId = db.createUser(
    username: username,
    passwordHash: passwordHash,
    role: 'admin',
  );
  final token = _openSession(
    db,
    userId: userId,
    remember: false,
    userAgent: userAgent,
  );
  return (
    token: token,
    remember: false,
    body: {
      'token': token,
      'user': {'id': userId, 'username': username, 'role': 'admin'},
    },
  );
}

/// Core of `POST /api/v1/auth/recover`: takes an operator-issued recovery
/// code and hands back a working admin account.
///
/// Unauthenticated by design — it is the way out of "every admin is disabled"
/// and "no admin exists at all", so requiring a sign-in would defeat it.
/// Possession of the code printed by `dart run salt_server:recover` *is* the
/// proof of server access, exactly as with the first-boot setup code.
///
/// [body] must carry a `recovery_code` ([ForbiddenException] when none is
/// pending or it expired, [ValidationException] when it simply does not
/// match), a valid `username`, and a `new_password` of at least
/// [minPasswordLength] characters. The named account is reset to an enabled
/// admin with that password — created first if it does not exist — its
/// sessions and API tokens are all revoked, the code is consumed, and a
/// non-remember session opens.
///
/// Rate-limited per IP exactly like [login], and for a sharper reason: this
/// endpoint is unauthenticated and grants admin, and checking a code costs
/// only a SHA-256 (the Argon2 hash happens after), so an unthrottled attacker
/// could guess far faster here than at the login form. Every failure is
/// logged — attempts on the way into an admin account are precisely what an
/// operator needs to see.
Future<SessionGrant> recoverAdmin(
  SaltDatabase db,
  AuthRuntime runtime,
  Map<String, Object?> body, {
  required String clientIp,
  String? userAgent,
}) async {
  // Recovery gets its OWN budget, deliberately NOT login's shared per-IP one.
  //
  // Gating this on `ipRateLimiter` — which is what "rate-limit it exactly like
  // login" produces — inverts the feature: failed logins are precisely what
  // makes an operator need /recover, and they would fill the very bucket that
  // then refuses a VALID code. It is worse on the default deployment, where
  // TRUST_PROXY is unset (config.dart) so clientIp resolves to the reverse
  // proxy's address for every request and one user's fat-fingered logins would
  // lock recovery for the whole household.
  //
  // Keyed on the IP alone: the code IS the credential here, so unlike login
  // there is no account to scope the budget to.
  final key = 'recover|$clientIp';
  final gate = runtime.rateLimiter.check(key);
  if (!gate.allowed) {
    // Before the code check, so a locked-out caller learns nothing about
    // whether their guess was close.
    throw LockedException(_ceilSeconds(gate.retryAfter));
  }

  void countFailure(String reason) {
    // Only the recovery key: a wrong code must not spend login's budget
    // either, or a code-guesser could lock the household out of signing in.
    runtime.rateLimiter.recordFailure(key);
    // The attempted code is a secret and never reaches the log.
    _log.warning('Recovery attempt rejected from $clientIp: $reason.');
  }

  final code = requireStringField(body, 'recovery_code');
  switch (checkRecoveryCode(db, code)) {
    case RecoveryCodeStatus.unavailable:
      countFailure('no recovery code is pending');
      throw const ForbiddenException(_recoveryUnavailable);
    case RecoveryCodeStatus.invalid:
      countFailure('wrong recovery code');
      throw const ValidationException('Invalid recovery code.');
    case RecoveryCodeStatus.valid:
      break;
  }
  final username = _validUsername(requireStringField(body, 'username'));
  final newPassword = requireStringField(body, 'new_password');
  _validNewPassword(newPassword, field: 'new_password');

  final passwordHash = await runtime.hasher.hash(newPassword);
  // Re-check after the ~100ms hash await, for the same reason setupAdmin
  // does: two concurrent requests could both pass the check above while
  // suspended, and the code is single-use. Consume it before touching any
  // account, and take no awaits below this point.
  if (checkRecoveryCode(db, code) != RecoveryCodeStatus.valid) {
    throw const ForbiddenException(_recoveryUnavailable);
  }
  clearRecoveryCode(db);

  final existing = db.userByUsername(username);
  final int userId;
  // Echo the stored spelling for an existing account: the lookup is
  // case-insensitive, so what was typed is not necessarily what is on file.
  final resolvedUsername = existing?.username ?? username;
  var revokedTokens = 0;
  if (existing == null) {
    userId = db.createUser(
      username: username,
      passwordHash: passwordHash,
      role: 'admin',
    );
  } else {
    userId = existing.id;
    // Reset, promote, re-enable: any of the three alone can be the lockout.
    // The password update drops the account's existing sessions, so whoever
    // (or whatever) held one loses it here.
    db
      ..updatePasswordHash(userId, passwordHash, mustChangePassword: false)
      ..setUserRole(userId, 'admin')
      ..setUserDisabled(userId, disabled: false);
    // Sessions alone are not enough: a PAT is its own credential and would
    // outlive the password reset. Recovery is used when control of the
    // account is in doubt, so every existing token goes too — the operator
    // can mint new ones once they are back in.
    revokedTokens = db.revokeAllApiTokens(userId);
  }
  runtime.rateLimiter.recordSuccess(key);
  // The code itself is a secret and never reaches the log; that recovery was
  // used, and on whom, is exactly what an operator needs to see afterwards.
  _log.info(
    'Recovery code used: $resolvedUsername is now an enabled admin '
    '(sessions dropped; $revokedTokens API token(s) revoked).',
  );

  final token = _openSession(
    db,
    userId: userId,
    remember: false,
    userAgent: userAgent,
  );
  return (
    token: token,
    remember: false,
    body: {
      'token': token,
      'user': {'id': userId, 'username': resolvedUsername, 'role': 'admin'},
    },
  );
}

/// Retry advertised when [AuthRuntime.verifyGate] is full. Short on purpose:
/// the backlog drains in the time one hash takes, so this is backpressure,
/// not a lockout, and must not read as one to a legitimate client.
const Duration _verifyBusyRetry = Duration(seconds: 2);

/// Core of `POST /api/v1/auth/login`.
///
/// Rate-limited per `<clientIp>|<username-lowercase>`: when locked, throws
/// [LockedException] carrying the remaining seconds. An unknown username
/// (verified against a dummy hash so timing does not leak existence) or a
/// wrong password throws the uniform [_invalidCredentials]. A disabled
/// account whose password checks out throws the specific [_accountDisabled]
/// instead — reachable only with the correct password, so it stays
/// enumeration-safe. On success the failure count resets and a session opens:
/// fixed 7-day expiry, or 90-day sliding when `remember: true`.
///
/// [sharedClientIp] says [clientIp] cannot identify one client — it is the
/// address of a reverse proxy every request arrives from — which suppresses
/// the aggregate per-address lockout that would otherwise deny the whole
/// deployment. The per-account throttle is unaffected.
Future<SessionGrant> login(
  SaltDatabase db,
  AuthRuntime runtime,
  Map<String, Object?> body, {
  required String clientIp,
  String? userAgent,
  bool sharedClientIp = false,
}) async {
  final username = requireStringField(body, 'username');
  final password = requireStringField(body, 'password');
  final remember = _optionalBoolField(body, 'remember') ?? false;

  final key = '$clientIp|${username.toLowerCase()}';
  // Count both attempts BEFORE the hash, not after it. These two calls and
  // the checks inside them contain no await, so they are atomic against
  // every other in-flight request; splitting them around the ~60-100ms
  // Argon2id below is what let N concurrent attempts all pass a gate meant
  // to admit five. See LoginRateLimiter.reserve.
  final gate = runtime.rateLimiter.reserve(key);
  // A shared address cannot identify a client, so the aggregate bucket is
  // not applied to one: with TRUST_PROXY off (the default) every request
  // arrives from the reverse proxy, and 25 failures across distinct
  // usernames would lock out every account on the deployment — permanently,
  // since success deliberately does not clear this bucket. Skipping it costs
  // spray detection; enforcing it hands any unauthenticated peer a total
  // denial of service. The per-account throttle above still stands.
  final ipGate = sharedClientIp
      ? (allowed: true, retryAfter: Duration.zero)
      : runtime.ipRateLimiter.reserve(clientIp);
  if (!gate.allowed || !ipGate.allowed) {
    final retryAfter = gate.retryAfter > ipGate.retryAfter
        ? gate.retryAfter
        : ipGate.retryAfter;
    throw LockedException(_ceilSeconds(retryAfter));
  }

  // Both reservations stand as failures unless this request reaches a
  // conclusion that says otherwise, so an attempt abandoned mid-hash stays
  // counted rather than evaporating.
  void releaseIpReservation() {
    if (!sharedClientIp) runtime.ipRateLimiter.releaseReservation(clientIp);
  }

  final user = db.userByUsername(username);
  // Nothing past here may start an Argon2id hash without a slot: the
  // throttles bound attempts per key, never the total in flight.
  if (!runtime.verifyGate.tryAcquire()) {
    throw LockedException(_ceilSeconds(_verifyBusyRetry));
  }
  final bool verified;
  try {
    if (user == null) {
      // Still hashed for an unknown username: the uniform cost is what keeps
      // login from enumerating accounts by timing.
      await runtime.hasher.dummyVerify(password);
      verified = false;
    } else {
      verified = await runtime.hasher.verify(password, user.passwordHash);
    }
  } finally {
    runtime.verifyGate.release();
  }
  if (user == null || !verified) {
    throw const ValidationException(_invalidCredentials);
  }
  if (user.disabled) {
    // Reached only with the correct password, so this only ever names the
    // state to the account's own owner (or someone already holding valid
    // credentials). A wrong password still yields the uniform error above, so
    // this cannot be used to enumerate usernames or account state.
    throw const ValidationException(_accountDisabled);
  }

  runtime.rateLimiter.recordSuccess(key);
  // Success does NOT clear the aggregate IP bucket: a sprayer who finds one
  // valid credential must not regain a fresh horizontal budget. It does give
  // back THIS attempt's reservation, which was taken before the password was
  // known and is not a failure — otherwise ordinary logins from one address
  // would march the shared bucket to its own threshold.
  releaseIpReservation();
  final token = _openSession(
    db,
    userId: user.id,
    remember: remember,
    userAgent: userAgent,
  );
  return (
    token: token,
    remember: remember,
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
/// `Set-Cookie` value for a new session.
///
/// A "remember me" session gets `Max-Age`, and must: without it the browser
/// treats this as a session cookie and drops it when the window closes, so the
/// 90-day sliding session the server faithfully recorded was unreachable — the
/// feature did nothing on web at all. Without remember there is deliberately
/// no `Max-Age`: dying with the browser IS the intent.
///
/// The server-side session SLIDES (every authenticated request extends it) but
/// this `Max-Age` is fixed at sign-in, so a continuously-active user is asked
/// to sign in again 90 days after signing IN rather than 90 days after their
/// last visit. Closing that gap would mean a `Set-Cookie` on every response,
/// which is not worth it.
String sessionCookie(
  String token, {
  required bool secure,
  bool remember = false,
}) =>
    '$sessionCookieName=$token; Path=/; HttpOnly; SameSite=Lax'
    '${remember ? '; Max-Age=${rememberSessionLifetime.inSeconds}' : ''}'
    '${secure ? '; Secure' : ''}';

/// `Set-Cookie` value clearing the session cookie (logout).
String expiredSessionCookie({required bool secure}) =>
    '$sessionCookieName=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0; '
    'Expires=Thu, 01 Jan 1970 00:00:00 GMT${secure ? '; Secure' : ''}';

/// Largest accepted JSON request body. Recipes are the biggest legitimate
/// payload and the corpus's largest document is well under 100 KB; the cap
/// exists so an unauthenticated-to-cheap request cannot balloon memory
/// before per-field length checks ever run.
const int maxJsonBodyBytes = 2 * 1024 * 1024;

/// Reads [request]'s body as a JSON object with the size cap enforced
/// *while reading* (a declared or actual body over [maxJsonBodyBytes] is
/// rejected before it is buffered whole); throws [ValidationException] on
/// oversize, malformed JSON, or any non-object shape.
Future<Map<String, Object?>> readJsonBody(Request request) async {
  // The Content-Type is a security check, not politeness, and it is the only
  // thing guarding the UNAUTHENTICATED endpoints — `requireCsrf` needs a
  // session to key on, so login and setup cannot use it.
  //
  // A cross-site HTML form can only send `application/x-www-form-urlencoded`,
  // `multipart/form-data` or `text/plain` — and `enctype="text/plain"` can be
  // shaped into a valid JSON document, so parsing whatever bytes arrived let
  // an attacker's page POST to /auth/login and sign a victim into the
  // ATTACKER's account. Demanding `application/json` closes it: a form cannot
  // produce that header, and a scripted `fetch` that sets it triggers a CORS
  // preflight this server never approves.
  final mime = request.headers['content-type']?.split(';').first.trim();
  if (mime?.toLowerCase() != 'application/json') {
    throw const ValidationException('Request body must be application/json.');
  }
  final declared = int.tryParse(request.headers['content-length'] ?? '');
  if (declared != null && declared > maxJsonBodyBytes) {
    throw const ValidationException('Request body is too large.');
  }
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request.bytes()) {
    builder.add(chunk);
    if (builder.length > maxJsonBodyBytes) {
      throw const ValidationException('Request body is too large.');
    }
  }
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(builder.takeBytes()));
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
  // Same normalization as admin-created accounts (user_handlers):
  // trimmed and lowercased before validation and storage, so the setup
  // admin's username follows the same rules as everyone else's.
  final normalized = username.trim().toLowerCase();
  if (!_usernamePattern.hasMatch(normalized)) {
    throw const ValidationException(
      'Username must be 3-32 characters: letters, digits, '
      'underscore, dot, or dash.',
    );
  }
  return normalized;
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
      expiresAt: now.add(remember ? rememberSessionLifetime : sessionLifetime),
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
