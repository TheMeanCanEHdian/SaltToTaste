import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/auth/tokens.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';

/// Lifetime of a session created without "remember me" (fixed expiry).
const Duration sessionLifetime = Duration(days: 7);

/// Sliding lifetime of a "remember me" session: every authenticated request
/// extends the expiry to now plus this duration.
const Duration rememberSessionLifetime = Duration(days: 90);

/// Name of the anti-CSRF header required on mutating session requests.
const String csrfHeaderName = 'X-Requested-With';

/// Required value of [csrfHeaderName].
const String csrfHeaderValue = 'SaltToTaste';

/// The authenticated principal of a request, resolved by [authProvider].
///
/// Never carries secret material (no password hash, no token) — only the
/// SHA-256 [sessionHash] needed to identify the current session.
class AuthUser {
  /// Builds a resolved principal; see [authProvider] for how one is made.
  const AuthUser({
    required this.id,
    required this.username,
    required this.role,
    required this.mustChangePassword,
    required this.scope,
    required this.via,
    this.sessionHash,
  });

  /// User id (primary key of the `users` table).
  final int id;

  /// Username as stored (uniqueness is case-insensitive).
  final String username;

  /// `admin` or `member`.
  final String role;

  /// Whether the user must change their password before doing anything
  /// other than `/auth/me`, `/auth/logout`, or `/auth/change_password`.
  final bool mustChangePassword;

  /// Effective credential scope: `read` or `full`. Session logins are
  /// always `full`; PATs carry the scope they were created with.
  final String scope;

  /// How the request authenticated: `session` or `pat`.
  final String via;

  /// SHA-256 hash of the current session token when [via] is `session`;
  /// null for PATs. Derived from a secret — never log it.
  final String? sessionHash;

  /// Whether the user holds the `admin` role.
  bool get isAdmin => role == 'admin';

  /// Whether this request may mutate data: admin role AND `full` scope
  /// (effective permission = role ∩ scope).
  bool get canWrite => isAdmin && scope == 'full';
}

/// Middleware that resolves the request's credential into an [AuthUser?]
/// available via `context.read<AuthUser?>()` (null when unauthenticated).
///
/// Accepts either the [sessionCookieName] cookie or an
/// `Authorization: Bearer <token>` header (a PAT when the token starts with
/// [patMarker], otherwise a session token; the header wins when both are
/// present). Tokens are looked up by SHA-256 hash. Expired sessions are
/// deleted on sight; revoked PATs and disabled users resolve to null.
/// "Remember me" sessions get their expiry extended to now +
/// [rememberSessionLifetime]; every hit also updates the credential's and
/// user's last-seen timestamps.
///
/// Resolution is lazy (first `read`) and memoized, so the DB work — and the
/// last-seen/sliding-expiry writes — happen at most once per request. Must
/// be wired inside the [SaltDatabase] provider.
Middleware authProvider() {
  return (handler) {
    return (context) {
      AuthUser? user;
      var resolved = false;
      return handler(
        context.provide<AuthUser?>(() {
          if (!resolved) {
            resolved = true;
            user = _authenticate(context);
          }
          return user;
        }),
      );
    };
  };
}

/// Returns the authenticated user or throws.
///
/// Throws [UnauthorizedException] when the request is unauthenticated and
/// [PasswordChangeRequiredException] when the user is flagged to change
/// their password. Every endpoint except `/auth/me`, `/auth/logout`, and
/// `/auth/change_password` (which use
/// [requireUserAllowingPasswordChange]) must go through this.
AuthUser requireUser(RequestContext context) {
  final user = requireUserAllowingPasswordChange(context);
  if (user.mustChangePassword) {
    throw const PasswordChangeRequiredException();
  }
  return user;
}

/// Like [requireUser] but lets a must-change-password user through — only
/// for `/auth/me`, `/auth/logout`, and `/auth/change_password`.
AuthUser requireUserAllowingPasswordChange(RequestContext context) {
  final user = context.read<AuthUser?>();
  if (user == null) {
    throw const UnauthorizedException();
  }
  return user;
}

/// [requireUser] plus the `admin` role; throws [ForbiddenException]
/// otherwise.
AuthUser requireAdmin(RequestContext context) {
  final user = requireUser(context);
  if (!user.isAdmin) {
    throw const ForbiddenException('Administrator access required.');
  }
  return user;
}

/// [requireUser] plus write permission ([AuthUser.canWrite]); throws
/// [ForbiddenException] otherwise.
AuthUser requireWrite(RequestContext context) {
  final user = requireUser(context);
  if (!user.canWrite) {
    throw const ForbiddenException('Write access required.');
  }
  return user;
}

/// Throws [ForbiddenException] unless the credential's scope is `full`.
///
/// Every mutating endpoint must call this after its role guard: a
/// `read`-scoped PAT may browse (and, later, write personal data like
/// favorites) but may never mutate accounts, sessions, tokens, or recipes —
/// the documented invariant is effective permission = role ∩ scope.
/// Session logins are always `full`, so this only constrains PATs.
void requireFullScope(AuthUser user) {
  if (user.scope != 'full') {
    throw const ForbiddenException(
      'This action requires a full-scope token.',
    );
  }
}

/// Whether the caller attached this request's credential EXPLICITLY, rather
/// than the browser attaching it ambiently.
///
/// The cookie is the only ambient credential: a browser never sends
/// `Authorization` by itself. So any bearer credential — a PAT, and equally a
/// SESSION token presented as a bearer, which is the documented non-browser
/// client path (`docs/API.md`: the login response returns the token "for
/// non-browser clients") — was set by the caller's own code and cannot be the
/// cross-site shape the CSRF guards exist to stop. Keying on
/// `user.via == 'session'` instead refuses that caller, since a curl/script
/// client sends no proof header at all.
///
/// THE predicate both guards share, and deliberately the same [bearerToken]
/// the authenticator resolves the credential with. A bearer header that
/// [bearerToken] rejects leaves the request UNAUTHENTICATED — [_authenticate]
/// lets the header win outright and never falls back to the cookie — so a
/// guard reached with a resolved [AuthUser] and this predicate true is one the
/// bearer really authenticated. That is the whole reason the parse must not be
/// re-derived per call site: the guards used to test
/// `startsWith('bearer ')` themselves, which a malformed
/// `Authorization: Bearer <vertical tab>` satisfies while [bearerToken] trims
/// it to nothing — exempting a request the ambient cookie then authenticated.
///
/// Fail closed: absent, `Basic`, or malformed is ambient, so a credential kind
/// added later is guarded until someone decides otherwise.
bool _credentialIsExplicit(RequestContext context) =>
    bearerToken(context.request.headers['authorization']) != null;

/// Enforces the anti-CSRF header on mutating requests carrying an AMBIENT
/// credential.
///
/// When the request's credential was attached by the browser itself (the
/// session cookie — see [_credentialIsExplicit]) and the method is POST, PUT,
/// PATCH, or DELETE, the request must carry
/// `X-Requested-With: SaltToTaste` — a header cross-site HTML forms and
/// no-CORS fetches cannot set. Bearer requests are exempt (a browser never
/// attaches one ambiently). Throws [CsrfException] on failure.
///
/// [user] is kept so every mutating route reads `requireCsrf(context, user)`;
/// the decision no longer needs the principal, because whether the browser
/// attached the credential is a property of the request, not of who it
/// resolved to.
void requireCsrf(RequestContext context, AuthUser user) {
  if (_credentialIsExplicit(context)) {
    return;
  }
  const mutating = {
    HttpMethod.post,
    HttpMethod.put,
    HttpMethod.patch,
    HttpMethod.delete,
  };
  if (!mutating.contains(context.request.method)) {
    return;
  }
  if (context.request.headers['x-requested-with'] != csrfHeaderValue) {
    throw const CsrfException();
  }
}

/// `Sec-Fetch-Site` values that prove a request is not cross-site.
///
/// `same-origin` is our own page; `none` is a request with no initiator at all
/// (the address bar, a bookmark) — neither is something an attacker's page can
/// produce. `same-site` is NOT here: a sibling subdomain is not us. An ABSENT
/// header is not here either, which is the fail-closed half of
/// [requireNotCrossSite].
const Set<String> _notCrossSite = {'same-origin', 'none'};

/// Refuses an ambient (cookie) credential on a side-effectful GET that cannot
/// prove it is not a cross-site drive.
///
/// [requireCsrf] gates mutating METHODS only, and the session cookie is
/// `SameSite=Lax`, which a browser DOES send on a cross-site top-level
/// navigation. So an attacker page can point an admin's browser at an
/// expensive GET and the cookie rides along.
///
/// Two ways to prove it, because the callers differ:
/// * `X-Requested-With: SaltToTaste` — the app's dio sets it on every request,
///   and a cross-origin form or navigation cannot set a custom header.
/// * a `Sec-Fetch-Site` the browser itself stamped as not cross-site — needed
///   because the app opens the log export and the backup download with
///   `launchUrl` (a top-level navigation for the `Content-Disposition`
///   download), which carries no custom header.
///
/// Neither present is a refusal.
///
/// ONE implementation, called by every guarded route. It was copied into five
/// handlers, each re-deriving "is this a bearer request?" with its own
/// `startsWith('bearer ')` — five chances to disagree with the authenticator,
/// and they did (see [_credentialIsExplicit]).
///
/// Call it LAST among a route's guards but ABOVE the work it protects: the
/// whole point is cost, so a call placed under the expensive statement refuses
/// just as loudly while paying for it anyway. `route_auth_matrix_test` pins
/// that ordering, because no status assertion can see it.
void requireNotCrossSite(RequestContext context) {
  if (_credentialIsExplicit(context)) {
    return;
  }
  final headers = context.request.headers;
  if (headers['x-requested-with'] == csrfHeaderValue ||
      _notCrossSite.contains(headers['sec-fetch-site'])) {
    return;
  }
  throw const CsrfException();
}

/// The socket peer's address, or null when there is no real connection (bare
/// unit tests).
String? _peerAddress(RequestContext context) {
  try {
    return context.request.connectionInfo.remoteAddress.address;
    // `connectionInfo` null-asserts shelf's connection info, which is absent
    // outside a real shelf_io server; treat that as address unknown.
    // ignore: avoid_catching_errors
  } on TypeError {
    return null;
  }
}

/// Whether this request's `X-Forwarded-*` headers may be believed: only when
/// the socket peer is a configured proxy (`TRUST_PROXY` + `TRUSTED_PROXIES`).
///
/// The peer check is the whole point. `TRUST_PROXY=true` alone honoured
/// `X-Forwarded-For` from whoever happened to connect, so anyone who could
/// reach the port minted a fresh rate-limit bucket per request just by making
/// the header up — login throttling was decorative in the deployment the
/// README documents. A forwarded header only means anything coming from the
/// hop that appends it.
bool trustsForwardedHeaders(RequestContext context) =>
    context.read<ServerConfig>().isTrustedProxy(_peerAddress(context));

/// The client IP used for rate-limiting keys, taking [config] as the
/// trusted-proxy set explicitly — so it works in middleware wired OUTSIDE the
/// `ServerConfig` provider (the request logger, which runs upstream of the
/// providers). See [clientIp] for the provider-reading convenience wrapper.
///
/// From a trusted proxy, the RIGHTMOST `X-Forwarded-For` value is used — that
/// is the hop our own proxy appended. The leftmost values are client-supplied
/// and trivially spoofable; keying rate limits on them would give an attacker
/// a fresh bucket per request. Otherwise the socket peer address is used
/// (`unknown` when unavailable, e.g. in bare unit tests).
String clientIpFor(RequestContext context, ServerConfig config) {
  final peer = _peerAddress(context);
  if (config.isTrustedProxy(peer)) {
    final forwarded = context.request.headers['x-forwarded-for'];
    if (forwarded != null) {
      final last = forwarded.split(',').last.trim();
      if (last.isNotEmpty) {
        return last;
      }
    }
  }
  return peer ?? 'unknown';
}

/// Whether [clientIp] is an address many clients share rather than one
/// client's own, so a per-address penalty would fall on everyone.
///
/// True when the request carries `X-Forwarded-For` from a peer we do not
/// trust: something is proxying, but `TRUST_PROXY`/`TRUSTED_PROXIES` does not
/// say so, and every request therefore keys on that one hop's address. The
/// header cannot be believed (that is the point of the peer check) but its
/// presence is still evidence about the shape of the deployment, and the safe
/// reading of "I cannot tell these clients apart" is to not punish them as
/// one. A direct peer, or a correctly configured proxy, is not shared.
bool clientIpIsShared(RequestContext context) =>
    context.request.headers['x-forwarded-for'] != null &&
    !trustsForwardedHeaders(context);

/// [clientIpFor] resolved against the request-scoped `ServerConfig` provider.
String clientIp(RequestContext context) =>
    clientIpFor(context, context.read<ServerConfig>());

/// Whether the session cookie should carry `Secure`: when
/// [ServerConfig.secureCookies] forces it (direct-TLS or always-HTTPS
/// deployments), or when the request arrived over HTTPS at a trusted
/// reverse proxy ([ServerConfig.trustProxy] plus `X-Forwarded-Proto:
/// https`).
bool isSecureRequest(RequestContext context) {
  final config = context.read<ServerConfig>();
  if (config.secureCookies) {
    return true;
  }
  // Same peer check as clientIp: X-Forwarded-Proto means nothing from a peer
  // that is not our proxy. Spoofing it is not an escalation (claiming https
  // over http only stops the browser returning the cookie), but there is no
  // reason to believe a header from an untrusted hop, and one rule is easier
  // to keep true than two.
  if (!trustsForwardedHeaders(context)) {
    return false;
  }
  final proto = context.request.headers['x-forwarded-proto'];
  if (proto == null) {
    return false;
  }
  return proto.split(',').first.trim().toLowerCase() == 'https';
}

AuthUser? _authenticate(RequestContext context) {
  final db = context.read<SaltDatabase>();
  final bearer = bearerToken(context.request.headers['authorization']);
  if (bearer != null) {
    if (looksLikePat(bearer)) {
      return _authenticatePat(db, bearer);
    }
    return _authenticateSession(db, bearer);
  }
  final cookieToken = _cookieValue(
    context.request.headers['cookie'],
    sessionCookieName,
  );
  if (cookieToken != null) {
    return _authenticateSession(db, cookieToken);
  }
  return null;
}

AuthUser? _authenticateSession(SaltDatabase db, String token) {
  final hash = hashToken(token);
  final session = db.sessionByHash(hash);
  if (session == null) {
    return null;
  }
  final now = DateTime.now().toUtc();
  if (!session.expiresAt.isAfter(now)) {
    db.deleteSession(hash);
    return null;
  }
  final user = db.userById(session.userId);
  if (user == null || user.disabled) {
    return null;
  }
  if (session.remember) {
    db.touchSession(hash, extendTo: now.add(rememberSessionLifetime));
  } else {
    db.touchSession(hash);
  }
  db.touchUserActivity(user.id);
  return AuthUser(
    id: user.id,
    username: user.username,
    role: user.role,
    mustChangePassword: user.mustChangePassword,
    scope: 'full',
    via: 'session',
    sessionHash: hash,
  );
}

AuthUser? _authenticatePat(SaltDatabase db, String token) {
  final row = db.apiTokenByHash(hashToken(token));
  if (row == null || row.revokedAt != null) {
    return null;
  }
  final user = db.userById(row.userId);
  if (user == null || user.disabled) {
    return null;
  }
  db
    ..touchApiToken(row.id)
    ..touchUserActivity(user.id);
  return AuthUser(
    id: user.id,
    username: user.username,
    role: user.role,
    mustChangePassword: user.mustChangePassword,
    scope: row.scope,
    via: 'pat',
  );
}

/// The token from an `Authorization: Bearer <token>` header, or null when the
/// header is absent, is not a bearer credential, or carries a token that is
/// empty once trimmed.
///
/// THE bearer parser. [_authenticate] resolves the credential with it and
/// [_credentialIsExplicit] decides the CSRF guards with it, so "this request
/// carries a bearer credential" cannot mean two different things — which is
/// exactly what it meant while the guards re-implemented the test themselves.
String? bearerToken(String? authorization) {
  if (authorization == null) {
    return null;
  }
  const prefix = 'bearer ';
  if (authorization.length <= prefix.length ||
      authorization.substring(0, prefix.length).toLowerCase() != prefix) {
    return null;
  }
  final token = authorization.substring(prefix.length).trim();
  return token.isEmpty ? null : token;
}

String? _cookieValue(String? cookieHeader, String name) {
  if (cookieHeader == null) {
    return null;
  }
  for (final part in cookieHeader.split(';')) {
    final pair = part.trim();
    final eq = pair.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    if (pair.substring(0, eq) == name) {
      final value = pair.substring(eq + 1);
      return value.isEmpty ? null : value;
    }
  }
  return null;
}
