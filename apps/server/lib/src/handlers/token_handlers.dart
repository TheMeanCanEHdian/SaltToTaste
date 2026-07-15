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

Map<String, Object?> _tokenJson(ApiTokenRow token) => {
      'id': token.id,
      'name': token.name,
      'prefix': token.prefix,
      'scope': token.scope,
      'created_at': isoUtc(token.createdAt),
      'last_used_at': isoUtc(token.lastUsedAt),
      'revoked': token.revokedAt != null,
    };

/// `GET /api/v1/tokens` — the actor's personal access tokens.
Map<String, Object?> listTokensHandler(SaltDatabase db, AuthUser actor) => {
      'items': [
        for (final token in db.apiTokensForUser(actor.id)) _tokenJson(token),
      ],
    };

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
  final pat = generatePat();
  final id = db.createApiToken(
    userId: actor.id,
    name: trimmed,
    prefix: pat.prefix,
    tokenHash: hashToken(pat.token),
    scope: scope,
  );
  final row = db
      .apiTokensForUser(actor.id)
      .firstWhere((token) => token.id == id);
  return {'token': pat.token, 'item': _tokenJson(row)};
}

/// `DELETE /api/v1/tokens/<id>` — revokes the actor's token; 404 when the
/// token is absent, already revoked, or someone else's.
void revokeTokenHandler(SaltDatabase db, AuthUser actor, int id) {
  if (!db.revokeApiToken(id: id, userId: actor.id)) {
    throw const NotFoundException('token not found');
  }
}
