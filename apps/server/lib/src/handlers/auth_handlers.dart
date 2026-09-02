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

/// The audit channel: authentication, account administration, and the admin
/// actions that touch secret material — from here, from
/// `user_handlers`/`token_handlers`, and from the backup-download and
/// FDC-key routes. One logger name so an operator can filter the admin log
/// viewer to `auth` and read the whole story: who signed in, who failed, who
/// changed which account, and who took the database out of the building.
///
/// The viewer is `requireAdmin`-only and an admin can already list every
/// account, so naming a user here is not an enumeration oracle. No secret ever
/// reaches these lines: not a password, a token, a hash, or a setup/recovery
/// code.
///
/// ITS LEVEL IS PINNED, deliberately NOT inherited from `Logger.root`.
/// `LOG_LEVEL` is an operator verbosity knob and both `WARN` and `ERROR` are
/// supported values (`ServerConfig._parseLogLevel`) that feed
/// `Logger.root.level`. At either setting the whole audit trail — sign-ins,
/// PAT mints, backup downloads — would silently vanish while the failure
/// lines stayed, and an audit record that a routine verbosity choice deletes
/// is not an audit record. So this channel opts out of the knob: every audit
/// record it emits is published, at every supported `LOG_LEVEL`.
///
/// INFO, not ALL: INFO is the floor of the entire existing trail (every line
/// on this channel is `.info` or `.warning`), so nothing audit-worthy is
/// lost, while a `.fine()` debug line added here later is not force-published
/// to every deployment by a pin meant for the audit trail.
///
/// `configureLogging` already enables hierarchical logging; setting the flag
/// here too keeps the pin legal (the level setter throws without it) for
/// tests and CLI tools that never call it.
final Logger auditLog = _pinnedAuditLog();

Logger _pinnedAuditLog() {
  hierarchicalLoggingEnabled = true;
  return Logger('auth')..level = Level.INFO;
}

final Logger _log = auditLog;

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

/// Longest username [_usernamePattern] can accept — and so the most of one
/// worth keeping in a throttle key.
const int _maxUsernameLength = 32;

/// The name portion of a login throttle key: lowercased and bounded.
///
/// Bounded because the key outlives the request by up to an hour and the
/// caller chooses its length. Anything past [_maxUsernameLength] cannot name
/// a real account, so truncating only ever merges buckets that could never
/// have authenticated — stricter than separate ones, never looser.
String _throttleName(String username) {
  final lower = username.toLowerCase();
  return lower.length <= _maxUsernameLength
      ? lower
      : lower.substring(0, _maxUsernameLength);
}

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
           LoginRateLimiter(
             failureThreshold: ipFailureThreshold,
             escalate: false,
           ),
       verifyGate =
           verifyGate ?? ConcurrencyGate(limit: maxConcurrentVerifications);

  /// Aggregate failures from one address at which the whole IP locks —
  /// catches password spraying across many usernames, which per-account
  /// keys can't see.
  ///
  /// This one does NOT escalate. Its key is an address, and an address is
  /// not always one client: behind a proxy the operator has not declared
  /// with TRUST_PROXY, every request shares it, so an escalating lockout
  /// would let one attacker take the whole deployment to the 15-minute cap
  /// and hold it there. A flat lockout keeps horizontal-spray detection while
  /// bounding what a shared address can cost everyone behind it. The
  /// per-account limiter, whose key names one account, still escalates.
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
  _log.info('First-boot setup: admin $username (id $userId) created.');
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
    // Reset, promote, re-enable, and evict every API token — ONE transaction
    // (`resetToEnabledAdmin`). Any of the four alone can be the lockout, and
    // sessions alone are not enough: a PAT is its own credential and would
    // outlive the reset, so every existing token goes too and the operator
    // mints new ones once they are back in. As separate commits, a failure
    // between them left the account half recovered — new password live but
    // still disabled, or tokens dead and nothing else done. The rotation
    // drops the account's sessions, so whoever held one loses it here.
    revokedTokens = db.resetToEnabledAdmin(userId, passwordHash);
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

  // Bounded, log-safe rendering of the attempted name; see [_logName].
  final attempted = _logName(username);
  // The key is retained for an hour, so its size is the attacker's to choose
  // unless it is bounded here: `reserve()` below inserts it BEFORE every
  // refusal path, so 2 MiB usernames cost the server 279 MiB of resident
  // state for 200 free requests (measured) without ever charging an Argon2id.
  // Truncating at the longest name that could ever be real makes two overlong
  // names share a bucket, which is stricter than separate ones, never looser.
  final key = '$clientIp|${_throttleName(username)}';
  // Count both attempts BEFORE the hash, not after it. These two calls and
  // the checks inside them contain no await, so they are atomic against
  // every other in-flight request; splitting them around the ~60-100ms
  // Argon2id below is what let N concurrent attempts all pass a gate meant
  // to admit five. See LoginRateLimiter.reserve.
  final gate = runtime.rateLimiter.reserve(key);
  // The aggregate bucket is ALWAYS applied, and keyed on an address no
  // caller can choose: `clientIp` is the socket peer unless a TRUSTED proxy
  // supplied a forwarded value. An earlier attempt skipped this bucket when
  // the request carried `X-Forwarded-For` from an untrusted peer, reasoning
  // that such an address cannot identify one client — but the header is
  // attacker-supplied, so that handed any unauthenticated peer an opt-out
  // from horizontal-spray detection by adding one header (measured: 60
  // sprayed usernames, zero refusals). A security decision must never read a
  // value the attacker writes.
  //
  // What that leaves is the real dilemma the skip was trying to dodge: behind
  // a proxy the operator has not declared with TRUST_PROXY, every request
  // shares one address, so this bucket throttles the whole deployment as one
  // client. That is bounded rather than removed — the aggregate limiter does
  // not escalate (see AuthRuntime.ipRateLimiter), so the worst case is a
  // recurring short lockout instead of a 15-minute one, and the untrusted-
  // proxy warning tells the operator to fix the configuration that causes it.
  final ipGate = runtime.ipRateLimiter.reserve(clientIp);
  if (!gate.allowed || !ipGate.allowed) {
    final retryAfter = gate.retryAfter > ipGate.retryAfter
        ? gate.retryAfter
        : ipGate.retryAfter;
    // The generic access line says only "POST /auth/login -> 429": it carries
    // no actor, so without this an operator cannot tell which account is
    // being sprayed. One short fixed-shape line per rejected attempt, and the
    // request logger already writes one for the same request — both are
    // bounded (the path by `loggedPath`, the whole record again by the log
    // store), so this adds a constant, not a new amplification.
    _log.warning('Login locked out: $attempted from $clientIp.');
    throw LockedException(_ceilSeconds(retryAfter));
  }

  // Both reservations stand as failures unless this request reaches a
  // conclusion that says otherwise, so an attempt abandoned mid-hash stays
  // counted rather than evaporating.
  void releaseIpReservation() {
    runtime.ipRateLimiter.releaseReservation(clientIp);
  }

  final user = db.userByUsername(username);
  // Nothing past here may start an Argon2id hash without a slot: the
  // throttles bound attempts per key, never the total in flight.
  if (!runtime.verifyGate.tryAcquire()) {
    // A full gate is BACKPRESSURE, not a failed attempt, so it must give the
    // reservations back. Keeping them let a third party lock an account out
    // of itself: hold all 8 slots with throwaway usernames, and the real
    // owner's CORRECT password burns one reservation per try until their own
    // per-account bucket locks them out for 15 minutes. The reservation
    // exists to bound guesses; a request that was never allowed to guess has
    // not made one.
    runtime.rateLimiter.releaseReservation(key);
    runtime.ipRateLimiter.releaseReservation(clientIp);
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
    // Deliberately the same line whether the account exists or not: the
    // response is uniform for anti-enumeration reasons and the log has no
    // business being sharper than the response.
    _log.warning('Login failed: $attempted from $clientIp.');
    throw const ValidationException(_invalidCredentials);
  }
  if (user.disabled) {
    // Reached only with the correct password, so this only ever names the
    // state to the account's own owner (or someone already holding valid
    // credentials). A wrong password still yields the uniform error above, so
    // this cannot be used to enumerate usernames or account state.
    _log.warning(
      'Login refused: ${user.username} (id ${user.id}) is disabled, '
      'from $clientIp.',
    );
    throw const ValidationException(_accountDisabled);
  }

  runtime.rateLimiter.recordSuccess(key);
  // Success does NOT clear the aggregate IP bucket: a sprayer who finds one
  // valid credential must not regain a fresh horizontal budget. It does give
  // back THIS attempt's reservation, which was taken before the password was
  // known and is not a failure — otherwise ordinary logins from one address
  // would march the shared bucket to its own threshold.
  releaseIpReservation();
  _log.info('Login: ${user.username} (id ${user.id}) from $clientIp.');
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
  _log.info('Logout: ${user.username} (id ${user.id}).');
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
/// deleted (the current one is kept) and every personal access token of the
/// user is revoked — the count comes back as `revoked_tokens`.
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
      _log.warning(
        'Password change rejected: ${user.username} (id ${user.id}) gave the '
        'wrong current password.',
      );
      throw const ValidationException('Current password is incorrect.');
    }
  }
  final passwordHash = await runtime.hasher.hash(newPassword);
  // Eviction and rotation are ONE transaction (`updatePasswordHash` runs the
  // revocation inside its own): both land or neither does. As two statements
  // they could only be ORDERED, and the dangerous partial failure commits the
  // new password while leaving every PAT alive behind a 500 that reads as
  // "nothing happened" — the exact compromise state this eviction exists to
  // prevent.
  final revokedTokens = db.updatePasswordHash(
    user.id,
    passwordHash,
    mustChangePassword: false,
    keepSessionHash: user.sessionHash,
    revokeApiTokens: true,
  );
  // Every personal access token goes too, and there is deliberately no way to
  // opt out. A session alone is enough to mint a FULL-scope PAT (session
  // logins are always `full`, so `requireFullScope` admits them) and a PAT
  // has no expiry at all — so a password change that spared them evicted the
  // honest sessions and left the one credential an attacker minted from a
  // briefly-stolen cookie alive forever. "Changing my password ends any
  // credential minted from my account" has to hold on the path a victim
  // actually reaches for.
  //
  // The cost is the same one `resetPasswordHandler` already accepted for the
  // admin-driven path: a routine change also stops the user's own scripts,
  // and there is no version of this that spares them. Made visible rather
  // than silent — `revoked_tokens` says how many went.
  _log.info(
    'Password changed: ${user.username} (id ${user.id}); other sessions '
    'dropped, $revokedTokens API token(s) revoked.',
  );
  return {'ok': true, 'revoked_tokens': revokedTokens};
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
///
/// [allowEmpty] is for the few routes whose body is OPTIONAL: a request with
/// no body at all yields an empty map, and the content-type check moves to
/// after the read, applied only when bytes actually arrived. Presence cannot
/// be judged from headers — dart:io sends a written body chunked with no
/// Content-Length, and shelf strips Transfer-Encoding after dechunking — so
/// gating on either silently dropped real bodies. For every other caller the
/// content-type is still refused BEFORE a byte is read, so an unauthenticated
/// endpoint never pays to read an attacker's body it was going to reject.
Future<Map<String, Object?>> readJsonBody(
  Request request, {
  bool allowEmpty = false,
}) async {
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
  final isJson = mime?.toLowerCase() == 'application/json';
  if (!isJson && !allowEmpty) {
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
  if (builder.isEmpty && allowEmpty) {
    return const <String, Object?>{};
  }
  if (!isJson) {
    // Bytes arrived under the wrong type. Reached only via allowEmpty; every
    // other caller was refused above before reading.
    throw const ValidationException('Request body must be application/json.');
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

/// The ATTEMPTED username in a form that is safe to persist in the log.
///
/// [login] deliberately does not validate this field before using it, so it is
/// arbitrary caller-controlled text of arbitrary length. A value that cannot
/// match [_usernamePattern] cannot name an account either, so it is recorded
/// as a placeholder instead: that keeps an unbounded attacker-chosen string
/// out of the size-bounded log store (which rotates, so junk evicts history)
/// and out of the viewer's `rid=` correlation, without hiding any name that
/// could actually own an account.
String _logName(String username) {
  final normalized = username.trim().toLowerCase();
  return _usernamePattern.hasMatch(normalized) ? normalized : '<invalid>';
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
