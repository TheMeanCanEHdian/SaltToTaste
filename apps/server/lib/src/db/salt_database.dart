import 'dart:convert';
import 'dart:io';

import 'package:salt_server/src/db/migrations.dart';
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
/// statements with bound parameters; multi-statement work runs inside
/// explicit transactions.
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
      ..execute('PRAGMA foreign_keys = ON')
      ..execute('PRAGMA busy_timeout = 5000');
    return SaltDatabase._(db).._migrate();
  }

  final Database _db;

  /// Closes the underlying connection.
  void dispose() => _db.dispose();

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

  T _inTransaction<T>(T Function() action) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      _db.execute('COMMIT');
      return result;
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
  /// the JSON document is stored unmodified.
  UpsertOutcome upsertRecipe(
    Recipe recipe, {
    required String sourceSlug,
    required String contentHash,
  }) {
    final existing = _db.select(
      'SELECT content_hash FROM recipes WHERE id = ?',
      [recipe.id],
    );
    if (existing.isNotEmpty &&
        existing.first['content_hash'] as String == contentHash) {
      return UpsertOutcome.unchanged;
    }
    final isUpdate = existing.isNotEmpty;
    final slug = _availableSlug(recipe.slug, ownerId: recipe.id);
    final doc = jsonEncode(recipe.toMap());

    _inTransaction(() {
      if (isUpdate) {
        _db.execute(
          'UPDATE recipes SET slug = ?, source_slug = ?, title = ?, '
          'category = ?, servings_text = ?, serves_min = ?, serves_max = ?, '
          'prep_min = ?, cook_min = ?, total_min = ?, hero_image = ?, '
          "doc = ?, content_hash = ?, updated_at = datetime('now') "
          'WHERE id = ?',
          [
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
          ],
        );
      } else {
        _db.execute(
          'INSERT INTO recipes (id, slug, source_slug, title, category, '
          'servings_text, serves_min, serves_max, prep_min, cook_min, '
          'total_min, hero_image, doc, content_hash) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
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
          ],
        );
      }
      _rebuildIngredients(recipe);
      _rebuildTags(recipe);
      _rebuildFts(recipe);
    });
    return isUpdate ? UpsertOutcome.updated : UpsertOutcome.inserted;
  }

  /// First slug in `desired`, `desired-2`, `desired-3`, ... not owned by a
  /// recipe other than [ownerId].
  String _availableSlug(String desired, {required String ownerId}) {
    var candidate = desired;
    var suffix = 2;
    while (true) {
      final taken = _db.select(
        'SELECT 1 FROM recipes WHERE slug = ? AND id != ?',
        [candidate, ownerId],
      );
      if (taken.isEmpty) {
        return candidate;
      }
      candidate = '$desired-$suffix';
      suffix += 1;
    }
  }

  void _rebuildIngredients(Recipe recipe) {
    _db.execute(
      'DELETE FROM recipe_ingredients WHERE recipe_id = ?',
      [recipe.id],
    );
    final insert = _db.prepare(
      'INSERT INTO recipe_ingredients '
      '(recipe_id, position, group_name, raw, item, prep, amounts) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
    );
    try {
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
    } finally {
      insert.dispose();
    }
  }

  void _rebuildTags(Recipe recipe) {
    _db.execute('DELETE FROM recipe_tags WHERE recipe_id = ?', [recipe.id]);
    for (final tag in recipe.tags) {
      final name = tag.toLowerCase().trim();
      if (name.isEmpty) {
        continue;
      }
      _db.execute('INSERT OR IGNORE INTO tags (name) VALUES (?)', [name]);
      final tagId =
          _db.select('SELECT id FROM tags WHERE name = ?', [name]).first['id']
              as int;
      _db.execute(
        'INSERT OR IGNORE INTO recipe_tags (recipe_id, tag_id) VALUES (?, ?)',
        [recipe.id, tagId],
      );
    }
  }

  void _rebuildFts(Recipe recipe) {
    _db.execute('DELETE FROM recipe_fts WHERE recipe_id = ?', [recipe.id]);
    final tags = [
      for (final tag in recipe.tags) tag.toLowerCase().trim(),
    ].join(' ');
    final ingredients = [
      for (final group in recipe.ingredients)
        for (final line in group.items) line.raw,
    ].join('\n');
    final directions = [for (final step in recipe.steps) step.text].join('\n');
    _db.execute(
      'INSERT INTO recipe_fts '
      '(recipe_id, title, category, tags, ingredients, directions, notes) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        recipe.id,
        recipe.title,
        recipe.category ?? '',
        tags,
        ingredients,
        directions,
        recipe.notes ?? '',
      ],
    );
  }

  /// Inserts or updates a source row; [meta] is stored as JSON.
  void upsertSource({
    required String slug,
    required String name,
    required String type,
    Map<String, Object?> meta = const {},
  }) {
    _db.execute(
      'INSERT INTO sources (slug, name, type, meta) VALUES (?, ?, ?, ?) '
      'ON CONFLICT(slug) DO UPDATE SET '
      'name = excluded.name, type = excluded.type, meta = excluded.meta',
      [slug, name, type, jsonEncode(meta)],
    );
  }

  /// Total number of recipes.
  int recipeCount() =>
      _db.select('SELECT COUNT(*) AS n FROM recipes').first['n'] as int;

  /// One page of recipe cards ordered by title (case-insensitive), plus the
  /// total row count. [page] is 1-based.
  ///
  /// `hero_image` holds the doc-relative path (`images/<file>`); the card
  /// exposes it as the serving URL `/images/<source_slug>/<basename>`.
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
    final tagsFor = _db.prepare(
      'SELECT t.name FROM tags t '
      'JOIN recipe_tags rt ON rt.tag_id = t.id '
      'WHERE rt.recipe_id = ? ORDER BY t.name',
    );
    try {
      final items = <RecipeCard>[
        for (final row in rows)
          RecipeCard(
            id: row['id'] as String,
            slug: row['slug'] as String,
            title: row['title'] as String,
            category: row['category'] as String?,
            heroImage: _heroImageUrl(
              row['hero_image'] as String?,
              row['source_slug'] as String,
            ),
            tags: [
              for (final tagRow in tagsFor.select([row['id'] as String]))
                tagRow['name'] as String,
            ],
            servingsText: row['servings_text'] as String?,
            totalMinutes: row['total_min'] as int?,
          ),
      ];
      return (items: items, total: total);
    } finally {
      tagsFor.dispose();
    }
  }

  static String? _heroImageUrl(String? heroImage, String sourceSlug) {
    if (heroImage == null || heroImage.isEmpty) {
      return null;
    }
    const prefix = 'images/';
    final basename = heroImage.startsWith(prefix)
        ? heroImage.substring(prefix.length)
        : heroImage.split('/').last;
    return '/images/$sourceSlug/$basename';
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
