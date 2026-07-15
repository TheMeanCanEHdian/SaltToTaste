import 'dart:convert';
import 'dart:io';

import 'package:salt_server/src/db/migrations.dart';
import 'package:salt_server/src/services/image_paths.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';

/// What [SaltDatabase.upsertRecipe] did with the given recipe.
enum UpsertOutcome {
  /// No row existed for the recipe id; a new one was inserted.
  inserted,

  /// A row existed with a different content hash; it was rewritten.
  updated,

  /// The existing row already carries the same content hash; nothing written.
  unchanged,
}

/// The SQLite data-access layer for the server.
///
/// Wraps a single `package:sqlite3` connection. All SQL uses prepared
/// statements with bound parameters (cached and reused across calls);
/// multi-statement work runs inside explicit transactions.
class SaltDatabase {
  SaltDatabase._(this._db);

  /// Opens (creating the file and its directory if needed) the database at
  /// [dbPath], configures WAL/foreign keys/busy timeout, and applies any
  /// pending [migrations].
  factory SaltDatabase.open(String dbPath) {
    final parent = File(dbPath).parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    final db = sqlite3.open(dbPath)
      ..execute('PRAGMA journal_mode = WAL')
      // NORMAL is durable under WAL (only a power loss at the wrong instant
      // can lose the last transaction, which a re-import replays) and avoids
      // an fsync per commit — the dominant cost of bulk import.
      ..execute('PRAGMA synchronous = NORMAL')
      ..execute('PRAGMA foreign_keys = ON')
      ..execute('PRAGMA busy_timeout = 5000');
    return SaltDatabase._(db).._migrate();
  }

  final Database _db;
  final Map<String, PreparedStatement> _statements = {};

  /// Returns a cached prepared statement for [sql], preparing it on first use.
  PreparedStatement _prepared(String sql) =>
      _statements[sql] ??= _db.prepare(sql);

  /// Closes the underlying connection and all cached statements.
  void dispose() {
    for (final statement in _statements.values) {
      statement.dispose();
    }
    _statements.clear();
    _db.dispose();
  }

  void _migrate() {
    var version = _db.select('PRAGMA user_version').first.columnAt(0) as int;
    while (version < migrations.length) {
      _db.execute('BEGIN');
      try {
        for (final statement in migrations[version]) {
          _db.execute(statement);
        }
        // PRAGMA does not support bound parameters; the value is the loop
        // counter, never external input.
        _db
          ..execute('PRAGMA user_version = ${version + 1}')
          ..execute('COMMIT');
      } catch (_) {
        _db.execute('ROLLBACK');
        rethrow;
      }
      version += 1;
    }
  }

  void _inTransaction(void Function() action) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      action();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Inserts or updates [recipe] plus all of its side tables
  /// (ingredients, tags, FTS) in one transaction.
  ///
  /// Returns [UpsertOutcome.unchanged] without touching the database when the
  /// existing row already carries [contentHash]. When another recipe id
  /// already owns `recipe.slug`, the stored slug gets a `-2`/`-3`/... suffix;
  /// the resolved slug is written into the stored document too, so the detail
  /// response and the card agree.
  UpsertOutcome upsertRecipe(
    Recipe recipe, {
    required String sourceSlug,
    required String contentHash,
  }) {
    final existing = _prepared(
      'SELECT content_hash FROM recipes WHERE id = ?',
    ).select([recipe.id]);
    if (existing.isNotEmpty &&
        existing.first['content_hash'] as String == contentHash) {
      return UpsertOutcome.unchanged;
    }
    final isUpdate = existing.isNotEmpty;
    final slug = _availableSlug(recipe.slug, ownerId: recipe.id);
    final stored = slug == recipe.slug ? recipe : recipe.copyWith(slug: slug);
    final doc = jsonEncode(stored.toMap());

    _inTransaction(() {
      if (isUpdate) {
        _prepared(
          'UPDATE recipes SET slug = ?, source_slug = ?, title = ?, '
          'category = ?, servings_text = ?, serves_min = ?, serves_max = ?, '
          'prep_min = ?, cook_min = ?, total_min = ?, hero_image = ?, '
          "doc = ?, content_hash = ?, updated_at = datetime('now') "
          'WHERE id = ?',
        ).execute([
          slug,
          sourceSlug,
          recipe.title,
          recipe.category,
          recipe.servings,
          recipe.serves?.min,
          recipe.serves?.max,
          recipe.times.prep,
          recipe.times.cook,
          recipe.times.total,
          recipe.images.hero,
          doc,
          contentHash,
          recipe.id,
        ]);
      } else {
        _prepared(
          'INSERT INTO recipes (id, slug, source_slug, title, category, '
          'servings_text, serves_min, serves_max, prep_min, cook_min, '
          'total_min, hero_image, doc, content_hash) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        ).execute([
          recipe.id,
          slug,
          sourceSlug,
          recipe.title,
          recipe.category,
          recipe.servings,
          recipe.serves?.min,
          recipe.serves?.max,
          recipe.times.prep,
          recipe.times.cook,
          recipe.times.total,
          recipe.images.hero,
          doc,
          contentHash,
        ]);
      }
      final rowid = _prepared('SELECT rowid FROM recipes WHERE id = ?')
          .select([recipe.id]).first['rowid'] as int;
      _rebuildIngredients(recipe);
      _rebuildTags(recipe);
      _rebuildFts(recipe, rowid);
    });
    return isUpdate ? UpsertOutcome.updated : UpsertOutcome.inserted;
  }

  /// First slug in `desired`, `desired-2`, `desired-3`, ... not owned by a
  /// recipe other than [ownerId].
  String _availableSlug(String desired, {required String ownerId}) {
    final taken = _prepared('SELECT 1 FROM recipes WHERE slug = ? AND id != ?');
    var candidate = desired;
    var suffix = 2;
    while (taken.select([candidate, ownerId]).isNotEmpty) {
      candidate = '$desired-$suffix';
      suffix += 1;
    }
    return candidate;
  }

  void _rebuildIngredients(Recipe recipe) {
    _prepared('DELETE FROM recipe_ingredients WHERE recipe_id = ?')
        .execute([recipe.id]);
    final insert = _prepared(
      'INSERT INTO recipe_ingredients '
      '(recipe_id, position, group_name, raw, item, prep, amounts) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
    );
    var position = 0;
    for (final group in recipe.ingredients) {
      for (final line in group.items) {
        insert.execute([
          recipe.id,
          position,
          group.group,
          line.raw,
          line.item,
          line.prep,
          jsonEncode([for (final amount in line.amounts) amount.toMap()]),
        ]);
        position += 1;
      }
    }
  }

  void _rebuildTags(Recipe recipe) {
    _prepared('DELETE FROM recipe_tags WHERE recipe_id = ?').execute(
      [recipe.id],
    );
    final insertTag = _prepared('INSERT OR IGNORE INTO tags (name) VALUES (?)');
    final selectTag = _prepared('SELECT id FROM tags WHERE name = ?');
    final linkTag = _prepared(
      'INSERT OR IGNORE INTO recipe_tags (recipe_id, tag_id) VALUES (?, ?)',
    );
    for (final tag in recipe.tags) {
      final name = tag.toLowerCase().trim();
      if (name.isEmpty) {
        continue;
      }
      insertTag.execute([name]);
      final tagId = selectTag.select([name]).first['id'] as int;
      linkTag.execute([recipe.id, tagId]);
    }
  }

  /// Rebuilds the FTS row for a recipe, keyed by the recipes rowid (the FTS
  /// docid) so delete/insert are O(1) rather than a full virtual-table scan.
  void _rebuildFts(Recipe recipe, int rowid) {
    _prepared('DELETE FROM recipe_fts WHERE rowid = ?').execute([rowid]);
    final tags = [
      for (final tag in recipe.tags) tag.toLowerCase().trim(),
    ].join(' ');
    final ingredients = [
      for (final group in recipe.ingredients)
        for (final line in group.items) line.raw,
    ].join('\n');
    final directions = [for (final step in recipe.steps) step.text].join('\n');
    _prepared(
      'INSERT INTO recipe_fts '
      '(rowid, recipe_id, title, category, tags, ingredients, directions, '
      'notes, background, prep_notes) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    ).execute([
      rowid,
      recipe.id,
      recipe.title,
      recipe.category ?? '',
      tags,
      ingredients,
      directions,
      recipe.notes ?? '',
      recipe.background ?? '',
      recipe.prepNotes ?? '',
    ]);
  }

  /// Inserts or updates a source row; [meta] is stored as JSON.
  void upsertSource({
    required String slug,
    required String name,
    required String type,
    Map<String, Object?> meta = const {},
  }) {
    _prepared(
      'INSERT INTO sources (slug, name, type, meta) VALUES (?, ?, ?, ?) '
      'ON CONFLICT(slug) DO UPDATE SET '
      'name = excluded.name, type = excluded.type, meta = excluded.meta',
    ).execute([slug, name, type, jsonEncode(meta)]);
  }

  /// Total number of recipes.
  int recipeCount() =>
      _db.select('SELECT COUNT(*) AS n FROM recipes').first['n'] as int;

  /// One page of recipe cards ordered by title (case-insensitive), plus the
  /// total row count. [page] is 1-based.
  ///
  /// `hero_image` holds the doc-relative path (`images/<file>`); the card
  /// exposes it as the serving URL `/images/<source_slug>/<safe-name>`.
  ({List<RecipeCard> items, int total}) listCards({
    required int page,
    required int limit,
  }) {
    final total = recipeCount();
    var offset = (page - 1) * limit;
    if (offset < 0) {
      offset = 0;
    }
    final rows = _db.select(
      'SELECT id, slug, source_slug, title, category, servings_text, '
      'total_min, hero_image FROM recipes '
      'ORDER BY title COLLATE NOCASE LIMIT ? OFFSET ?',
      [limit, offset],
    );
    final tagsByRecipe = _tagsFor([
      for (final row in rows) row['id'] as String,
    ]);
    final items = <RecipeCard>[
      for (final row in rows)
        RecipeCard(
          id: row['id'] as String,
          slug: row['slug'] as String,
          title: row['title'] as String,
          category: row['category'] as String?,
          heroImage: imageUrl(
            row['source_slug'] as String,
            row['hero_image'] as String?,
          ),
          tags: tagsByRecipe[row['id'] as String] ?? const [],
          servingsText: row['servings_text'] as String?,
          totalMinutes: row['total_min'] as int?,
        ),
    ];
    return (items: items, total: total);
  }

  /// Tags (sorted) for every recipe id in [recipeIds], fetched in one query.
  Map<String, List<String>> _tagsFor(List<String> recipeIds) {
    if (recipeIds.isEmpty) {
      return const {};
    }
    final placeholders = List.filled(recipeIds.length, '?').join(', ');
    final rows = _db.select(
      'SELECT rt.recipe_id AS rid, t.name AS name FROM recipe_tags rt '
      'JOIN tags t ON t.id = rt.tag_id '
      'WHERE rt.recipe_id IN ($placeholders) '
      'ORDER BY t.name',
      recipeIds,
    );
    final result = <String, List<String>>{};
    for (final row in rows) {
      (result[row['rid'] as String] ??= <String>[]).add(row['name'] as String);
    }
    return result;
  }

  /// The recipe whose id or slug equals [key], reconstructed from its stored
  /// JSON document, or null when absent.
  ({Recipe recipe, String sourceSlug})? recipeByIdOrSlug(String key) {
    final rows = _db.select(
      'SELECT doc, source_slug FROM recipes WHERE id = ? OR slug = ? LIMIT 1',
      [key, key],
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    final doc = jsonDecode(row['doc'] as String) as Map<String, dynamic>;
    return (
      recipe: RecipeMapper.fromMap(doc),
      sourceSlug: row['source_slug'] as String,
    );
  }

  // --------------------------------------------------------------------
  // Auth: users, sessions, API tokens (migration 002).
  //
  // Timestamps written from Dart are UTC ISO-8601 TEXT
  // (`DateTime.toUtc().toIso8601String()`); `created_at` columns default to
  // SQLite's `datetime('now')` (UTC, space-separated). Booleans are stored
  // as INTEGER 0/1. Password hashes and token hashes are opaque strings to
  // this layer and must never be logged.
  // --------------------------------------------------------------------

  static const _userColumns = 'id, username, password_hash, role, '
      'must_change_password, disabled, created_at, last_active_at';
  static const _sessionColumns = 'token_hash, user_id, created_at, '
      'expires_at, last_seen_at, remember, user_agent';
  static const _apiTokenColumns = 'id, user_id, name, prefix, scope, '
      'created_at, last_used_at, revoked_at';

  /// Current time as UTC ISO-8601 text, the storage format for timestamps
  /// written by this layer.
  static String _utcNowIso() => DateTime.now().toUtc().toIso8601String();

  static UserRow _userRow(Row row) => UserRow(
        id: row['id'] as int,
        username: row['username'] as String,
        passwordHash: row['password_hash'] as String,
        role: row['role'] as String,
        mustChangePassword: (row['must_change_password'] as int) != 0,
        disabled: (row['disabled'] as int) != 0,
        createdAt: row['created_at'] as String,
        lastActiveAt: row['last_active_at'] as String?,
      );

  static SessionRow _sessionRow(Row row) => SessionRow(
        tokenHash: row['token_hash'] as String,
        userId: row['user_id'] as int,
        expiresAt: DateTime.parse(row['expires_at'] as String),
        remember: (row['remember'] as int) != 0,
        createdAt: row['created_at'] as String,
        lastSeenAt: row['last_seen_at'] as String?,
        userAgent: row['user_agent'] as String?,
      );

  static ApiTokenRow _apiTokenRow(Row row) => ApiTokenRow(
        id: row['id'] as int,
        userId: row['user_id'] as int,
        name: row['name'] as String,
        prefix: row['prefix'] as String,
        scope: row['scope'] as String,
        createdAt: row['created_at'] as String,
        lastUsedAt: row['last_used_at'] as String?,
        revokedAt: row['revoked_at'] as String?,
      );

  /// Total number of users.
  int userCount() =>
      _db.select('SELECT COUNT(*) AS n FROM users').first['n'] as int;

  /// Inserts a new user and returns its id.
  ///
  /// Usernames are unique case-insensitively (`COLLATE NOCASE`); inserting a
  /// duplicate throws a catchable [SqliteException] with a
  /// `SQLITE_CONSTRAINT_UNIQUE` extended result code — callers own mapping
  /// that to a domain error.
  int createUser({
    required String username,
    required String passwordHash,
    required String role,
    bool mustChangePassword = false,
  }) {
    _prepared(
      'INSERT INTO users (username, password_hash, role, '
      'must_change_password) VALUES (?, ?, ?, ?)',
    ).execute(
      [username, passwordHash, role, if (mustChangePassword) 1 else 0],
    );
    return _db.lastInsertRowId;
  }

  /// The user named [username] (case-insensitive), or null when absent.
  UserRow? userByUsername(String username) {
    final rows = _prepared(
      'SELECT $_userColumns FROM users WHERE username = ?',
    ).select([username]);
    return rows.isEmpty ? null : _userRow(rows.first);
  }

  /// The user with [id], or null when absent.
  UserRow? userById(int id) {
    final rows = _prepared(
      'SELECT $_userColumns FROM users WHERE id = ?',
    ).select([id]);
    return rows.isEmpty ? null : _userRow(rows.first);
  }

  /// All users, ordered by username (case-insensitive).
  List<UserRow> listUsers() {
    final rows = _db.select(
      'SELECT $_userColumns FROM users ORDER BY username COLLATE NOCASE',
    );
    return [for (final row in rows) _userRow(row)];
  }

  /// Replaces the user's password hash and `must_change_password` flag, and
  /// deletes all of the user's sessions in the same transaction — except
  /// [keepSessionHash] when given (the session that performed the change).
  void updatePasswordHash(
    int userId,
    String passwordHash, {
    required bool mustChangePassword,
    String? keepSessionHash,
  }) {
    _inTransaction(() {
      _prepared(
        'UPDATE users SET password_hash = ?, must_change_password = ? '
        'WHERE id = ?',
      ).execute([passwordHash, if (mustChangePassword) 1 else 0, userId]);
      if (keepSessionHash == null) {
        _prepared('DELETE FROM sessions WHERE user_id = ?').execute([userId]);
      } else {
        _prepared(
          'DELETE FROM sessions WHERE user_id = ? AND token_hash != ?',
        ).execute([userId, keepSessionHash]);
      }
    });
  }

  /// Sets the user's role (`admin` or `member`).
  void setUserRole(int userId, String role) {
    _prepared('UPDATE users SET role = ? WHERE id = ?')
        .execute([role, userId]);
  }

  /// Enables or disables a user. Disabling also deletes all of the user's
  /// sessions (in the same transaction) so access ends immediately.
  void setUserDisabled(int userId, {required bool disabled}) {
    if (!disabled) {
      _prepared('UPDATE users SET disabled = 0 WHERE id = ?')
          .execute([userId]);
      return;
    }
    _inTransaction(() {
      _prepared('UPDATE users SET disabled = 1 WHERE id = ?')
          .execute([userId]);
      _prepared('DELETE FROM sessions WHERE user_id = ?').execute([userId]);
    });
  }

  /// Sets the user's `last_active_at` to now.
  void touchUserActivity(int userId) {
    _prepared('UPDATE users SET last_active_at = ? WHERE id = ?')
        .execute([_utcNowIso(), userId]);
  }

  /// Inserts a session row. [tokenHash] is the SHA-256 of the opaque session
  /// token — the token itself is never stored.
  void createSession({
    required String tokenHash,
    required int userId,
    required DateTime expiresAt,
    required bool remember,
    String? userAgent,
  }) {
    _prepared(
      'INSERT INTO sessions (token_hash, user_id, expires_at, remember, '
      'user_agent) VALUES (?, ?, ?, ?, ?)',
    ).execute([
      tokenHash,
      userId,
      expiresAt.toUtc().toIso8601String(),
      if (remember) 1 else 0,
      userAgent,
    ]);
  }

  /// The session with [tokenHash], or null when absent. Expiry is not
  /// checked here — callers compare [SessionRow.expiresAt] themselves.
  SessionRow? sessionByHash(String tokenHash) {
    final rows = _prepared(
      'SELECT $_sessionColumns FROM sessions WHERE token_hash = ?',
    ).select([tokenHash]);
    return rows.isEmpty ? null : _sessionRow(rows.first);
  }

  /// Sets the session's `last_seen_at` to now, and its `expires_at` to
  /// [extendTo] when given (sliding "remember me" expiry).
  void touchSession(String tokenHash, {DateTime? extendTo}) {
    if (extendTo == null) {
      _prepared('UPDATE sessions SET last_seen_at = ? WHERE token_hash = ?')
          .execute([_utcNowIso(), tokenHash]);
      return;
    }
    _prepared(
      'UPDATE sessions SET last_seen_at = ?, expires_at = ? '
      'WHERE token_hash = ?',
    ).execute([
      _utcNowIso(),
      extendTo.toUtc().toIso8601String(),
      tokenHash,
    ]);
  }

  /// Deletes the session with [tokenHash] (logout); no-op when absent.
  void deleteSession(String tokenHash) {
    _prepared('DELETE FROM sessions WHERE token_hash = ?')
        .execute([tokenHash]);
  }

  /// All sessions belonging to [userId], newest first.
  List<SessionRow> sessionsForUser(int userId) {
    final rows = _prepared(
      'SELECT $_sessionColumns FROM sessions WHERE user_id = ? '
      'ORDER BY created_at DESC, token_hash',
    ).select([userId]);
    return [for (final row in rows) _sessionRow(row)];
  }

  /// Housekeeping: deletes every session whose expiry is in the past. Cheap
  /// to call opportunistically. `datetime()` normalizes both sides to whole
  /// seconds, so a live session is never deleted early; an expired one may
  /// linger for under a second.
  void deleteExpiredSessions() {
    _prepared('DELETE FROM sessions WHERE datetime(expires_at) < datetime(?)')
        .execute([_utcNowIso()]);
  }

  /// Inserts an API token row and returns its id. [tokenHash] is the SHA-256
  /// of the full token; [prefix] is the short display prefix shown in lists.
  int createApiToken({
    required int userId,
    required String name,
    required String prefix,
    required String tokenHash,
    required String scope,
  }) {
    _prepared(
      'INSERT INTO api_tokens (user_id, name, prefix, token_hash, scope) '
      'VALUES (?, ?, ?, ?, ?)',
    ).execute([userId, name, prefix, tokenHash, scope]);
    return _db.lastInsertRowId;
  }

  /// The API token with [tokenHash], or null when absent. Revocation is not
  /// checked here — callers inspect [ApiTokenRow.revokedAt].
  ApiTokenRow? apiTokenByHash(String tokenHash) {
    final rows = _prepared(
      'SELECT $_apiTokenColumns FROM api_tokens WHERE token_hash = ?',
    ).select([tokenHash]);
    return rows.isEmpty ? null : _apiTokenRow(rows.first);
  }

  /// Sets the token's `last_used_at` to now.
  void touchApiToken(int id) {
    _prepared('UPDATE api_tokens SET last_used_at = ? WHERE id = ?')
        .execute([_utcNowIso(), id]);
  }

  /// All API tokens belonging to [userId] (revoked included), newest first.
  List<ApiTokenRow> apiTokensForUser(int userId) {
    final rows = _prepared(
      'SELECT $_apiTokenColumns FROM api_tokens WHERE user_id = ? '
      'ORDER BY created_at DESC, id DESC',
    ).select([userId]);
    return [for (final row in rows) _apiTokenRow(row)];
  }

  /// Revokes API token [id], but only when it belongs to [userId] and is not
  /// already revoked. Returns whether a row was changed — false means
  /// "not found, not yours, or already revoked" (callers treat all three the
  /// same to avoid leaking token existence).
  bool revokeApiToken({required int id, required int userId}) {
    _prepared(
      'UPDATE api_tokens SET revoked_at = ? '
      'WHERE id = ? AND user_id = ? AND revoked_at IS NULL',
    ).execute([_utcNowIso(), id, userId]);
    return _db.updatedRows > 0;
  }
}

/// A row from the `users` table. `passwordHash` is a secret — never log it.
class UserRow {
  /// Builds a row; see the `users` table (migration 002) for field meanings.
  const UserRow({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.role,
    required this.mustChangePassword,
    required this.disabled,
    required this.createdAt,
    this.lastActiveAt,
  });

  /// Primary key.
  final int id;

  /// Unique username (case-insensitive).
  final String username;

  /// Argon2id password hash. Secret — never log.
  final String passwordHash;

  /// `admin` or `member`.
  final String role;

  /// Whether the user must set a new password at next sign-in.
  final bool mustChangePassword;

  /// Whether sign-in is blocked for this user.
  final bool disabled;

  /// Creation timestamp (UTC text, SQLite `datetime('now')` format).
  final String createdAt;

  /// Last authenticated activity (UTC ISO-8601), or null if never.
  final String? lastActiveAt;
}

/// A row from the `sessions` table. `tokenHash` is derived from a secret —
/// never log it.
class SessionRow {
  /// Builds a row; see the `sessions` table (migration 002).
  const SessionRow({
    required this.tokenHash,
    required this.userId,
    required this.expiresAt,
    required this.remember,
    required this.createdAt,
    this.lastSeenAt,
    this.userAgent,
  });

  /// SHA-256 of the opaque session token (primary key). Never log.
  final String tokenHash;

  /// Owning user id.
  final int userId;

  /// Expiry instant (UTC).
  final DateTime expiresAt;

  /// Whether this is a "remember me" session with sliding expiry.
  final bool remember;

  /// Creation timestamp (UTC text).
  final String createdAt;

  /// Last authenticated request (UTC ISO-8601), or null if never touched.
  final String? lastSeenAt;

  /// User-Agent captured at sign-in, if any.
  final String? userAgent;
}

/// A row from the `api_tokens` table (the token secret itself is never
/// stored). `tokenHash` never leaves the DAL boundary via this row.
class ApiTokenRow {
  /// Builds a row; see the `api_tokens` table (migration 002).
  const ApiTokenRow({
    required this.id,
    required this.userId,
    required this.name,
    required this.prefix,
    required this.scope,
    required this.createdAt,
    this.lastUsedAt,
    this.revokedAt,
  });

  /// Primary key.
  final int id;

  /// Owning user id.
  final int userId;

  /// User-chosen label.
  final String name;

  /// Short display prefix of the token (safe to show in lists).
  final String prefix;

  /// `read` or `full`; effective permission is role ∩ scope.
  final String scope;

  /// Creation timestamp (UTC text).
  final String createdAt;

  /// Last use (UTC ISO-8601), or null if never used.
  final String? lastUsedAt;

  /// Revocation instant (UTC ISO-8601), or null while active.
  final String? revokedAt;
}
