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
}
