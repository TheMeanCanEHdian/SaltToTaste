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

/// Enforces the anti-CSRF header on mutating session requests.
///
/// When [user] authenticated via session and the method is POST, PUT,
/// PATCH, or DELETE, the request must carry
/// `X-Requested-With: SaltToTaste` — a header cross-site HTML forms and
/// no-CORS fetches cannot set. PATs are exempt (they are never sent
/// ambiently by a browser). Throws [CsrfException] on failure.
void requireCsrf(RequestContext context, AuthUser user) {
  if (user.via != 'session') {
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

/// Throws [MethodNotAllowedException] unless the request is a POST
/// (mirrors `requireGet` in `http/method_guard.dart`).
void requirePost(RequestContext context) {
  if (context.request.method != HttpMethod.post) {
    throw const MethodNotAllowedException('POST');
  }
}

/// The client IP used for rate-limiting keys: the first `X-Forwarded-For`
/// value when [ServerConfig.trustProxy] is set, otherwise the socket peer
/// address (`unknown` when unavailable, e.g. in bare unit tests).
String clientIp(RequestContext context) {
  if (context.read<ServerConfig>().trustProxy) {
    final forwarded = context.request.headers['x-forwarded-for'];
    if (forwarded != null) {
      final first = forwarded.split(',').first.trim();
      if (first.isNotEmpty) {
        return first;
      }
    }
  }
  try {
    return context.request.connectionInfo.remoteAddress.address;
    // `connectionInfo` null-asserts shelf's connection info, which is absent
    // outside a real shelf_io server; treat that as address unknown.
    // ignore: avoid_catching_errors
  } on TypeError {
    return 'unknown';
  }
}

/// Whether the session cookie should carry `Secure`: only when the request
/// arrived over HTTPS at a trusted reverse proxy
/// ([ServerConfig.trustProxy] plus `X-Forwarded-Proto: https`).
bool isSecureRequest(RequestContext context) {
  if (!context.read<ServerConfig>().trustProxy) {
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
  final bearer = _bearerToken(context.request.headers['authorization']);
  if (bearer != null) {
    if (looksLikePat(bearer)) {
      return _authenticatePat(db, bearer);
    }
    return _authenticateSession(db, bearer);
  }
  final cookieToken =
      _cookieValue(context.request.headers['cookie'], sessionCookieName);
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

String? _bearerToken(String? authorization) {
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
