import 'package:salt_server/src/auth/tokens.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/http/timestamps.dart';
import 'package:salt_server/src/middleware/auth.dart';

/// `GET /api/v1/sessions` — the actor's sessions, newest first. The id is
/// the stored token hash (already one-way; safe as an opaque identifier).
Map<String, Object?> listSessionsHandler(SaltDatabase db, AuthUser actor) {
  // Prune before listing so the security-sensitive "active sessions" view
  // never shows expired ghosts.
  db.deleteExpiredSessions();
  return {
    'items': [
      for (final session in db.sessionsForUser(actor.id))
        {
          'id': session.tokenHash,
          'created_at': isoUtc(session.createdAt),
          'last_seen_at': isoUtc(session.lastSeenAt),
          'user_agent': session.userAgent,
          'remember': session.remember,
          'current': session.tokenHash == actor.sessionHash,
        },
    ],
  };
}

/// `DELETE /api/v1/sessions/<id>` — signs that session out. Only the
/// actor's own sessions; deleting the current one acts as logout.
void deleteSessionHandler(SaltDatabase db, AuthUser actor, String id) {
  final owned = db
      .sessionsForUser(actor.id)
      .any((session) => session.tokenHash == id);
  if (!owned) {
    throw const NotFoundException('session not found');
  }
  db.deleteSession(id);
}

/// [retentionDays] is the operator's `API_TOKEN_RETENTION_DAYS`. When it is
/// positive and the token is revoked, `deletes_at` is when the housekeeping
/// prune becomes eligible to remove the row (`revoked_at + retention`), letting
/// the UI show a countdown. It stays null for a live token and when retention
/// is 0 ("keep forever").
Map<String, Object?> _tokenJson(ApiTokenRow token, {int retentionDays = 0}) {
  final revokedAt = token.revokedAt;
  String? deletesAt;
  if (revokedAt != null && retentionDays > 0) {
    final parsed = DateTime.tryParse(revokedAt);
    if (parsed != null) {
      deletesAt = parsed
          .toUtc()
          .add(Duration(days: retentionDays))
          .toIso8601String();
    }
  }
  return {
    'id': token.id,
    'name': token.name,
    'prefix': token.prefix,
    'scope': token.scope,
    'created_at': isoUtc(token.createdAt),
    'last_used_at': isoUtc(token.lastUsedAt),
    'revoked': revokedAt != null,
    'deletes_at': deletesAt,
  };
}

/// `GET /api/v1/tokens` — the actor's personal access tokens. [retentionDays]
/// (the operator's `API_TOKEN_RETENTION_DAYS`) drives each revoked token's
/// `deletes_at`.
Map<String, Object?> listTokensHandler(
  SaltDatabase db,
  AuthUser actor, {
  int retentionDays = 0,
}) => {
  'items': [
    for (final token in db.apiTokensForUser(actor.id))
      _tokenJson(token, retentionDays: retentionDays),
  ],
};

/// The most live tokens one user may hold at once.
///
/// A person managing personal access tokens keeps a handful; 20 is generous
/// headroom. The cap is a resource bound, not a UX limit: a token mints with a
/// cheap, non-Argon2 request and its row is permanent (revocation is an UPDATE,
/// never a DELETE), so without a ceiling a member — session logins are always
/// full-scope, so `requireFullScope` does not gate on role — can grow the
/// `api_tokens` table for the deployment's lifetime and make every token
/// listing do more work, on the single serving isolate.
const int maxActiveTokensPerUser = 20;

/// `POST /api/v1/tokens` `{name, scope}` — mints a PAT. The full token value
/// appears only in this response.
Map<String, Object?> createTokenHandler(
  SaltDatabase db,
  AuthUser actor, {
  required String name,
  required String scope,
}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty || trimmed.length > 60) {
    throw const ValidationException('Token name must be 1-60 characters.');
  }
  if (scope != 'read' && scope != 'full') {
    throw const ValidationException("Scope must be 'read' or 'full'.");
  }
  if (db.activeApiTokenCount(actor.id) >= maxActiveTokensPerUser) {
    throw const ValidationException(
      'You already have the maximum of $maxActiveTokensPerUser active tokens. '
      'Revoke one before creating another.',
    );
  }
  final pat = generatePat();
  final id = db.createApiToken(
    userId: actor.id,
    name: trimmed,
    prefix: pat.prefix,
    tokenHash: hashToken(pat.token),
    scope: scope,
  );
  // A single-row read, not a scan of the user's whole list: the create path
  // must not get slower as revoked rows accumulate.
  final row = db.apiTokenById(id: id, userId: actor.id)!;
  return {'token': pat.token, 'item': _tokenJson(row)};
}

/// `DELETE /api/v1/tokens/<id>` — revokes the actor's token; 404 when the
/// token is absent, already revoked, or someone else's.
void revokeTokenHandler(SaltDatabase db, AuthUser actor, int id) {
  if (!db.revokeApiToken(id: id, userId: actor.id)) {
    throw const NotFoundException('token not found');
  }
}
