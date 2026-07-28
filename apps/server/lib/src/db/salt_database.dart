import 'dart:convert';
import 'dart:io';

import 'package:salt_server/src/db/migrations.dart';
import 'package:salt_server/src/search/fts_compiler.dart';
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

  /// Opens a **read-only** connection to an already-created, already-migrated
  /// database — for the search worker isolates (#48), which run the FTS ranked
  /// query off the serving isolate. Under WAL many readers coexist with the one
  /// writer, so a worker's connection sees committed data without blocking it.
  ///
  /// Opened read-write (WAL readers participate fully, avoiding the read-only
  /// WAL-recovery pitfall) but pinned with `PRAGMA query_only` so it can never
  /// write. It does NOT migrate: the writer connection owns the schema, and a
  /// query-only connection could not run migrations anyway.
  factory SaltDatabase.openReadOnly(String dbPath) {
    final db = sqlite3.open(dbPath)
      ..execute('PRAGMA busy_timeout = 5000')
      ..execute('PRAGMA foreign_keys = ON')
      ..execute('PRAGMA query_only = TRUE');
    return SaltDatabase._(db);
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

  /// The migration that widened FTS content to subsections/techniques; a
  /// database upgrading across it needs its FTS rows re-derived in Dart
  /// (see _reindexAllFts — the text comes from nested doc JSON that SQL
  /// cannot maintainably re-derive).
  static const int _ftsWideningVersion = 8;

  void _migrate() {
    final startVersion =
        _db.select('PRAGMA user_version').first.columnAt(0) as int;
    var version = startVersion;
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
    if (startVersion < _ftsWideningVersion &&
        migrations.length >= _ftsWideningVersion) {
      _reindexAllFts();
    }
  }

  /// Re-derives every FTS row from the stored doc JSON. Runs once when an
  /// existing database upgrades across [_ftsWideningVersion]; on a fresh
  /// database there are no rows and this is a no-op.
  void _reindexAllFts() {
    _inTransaction(() {
      for (final row in _db.select('SELECT rowid, doc FROM recipes')) {
        final recipe = RecipeMapper.fromMap(
          jsonDecode(row['doc'] as String) as Map<String, dynamic>,
        );
        _rebuildFts(recipe, row['rowid'] as int);
      }
    });
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
    // Kept in step with migration 007's backfill: `variation` only, because a
    // `component` is a sub-recipe rather than a variant of this one. If these
    // two ever disagree, a card's badge silently depends on whether the recipe
    // has been re-saved since the migration.
    final variationCount = stored.subsections
        .where((subsection) => subsection.kind == 'variation')
        .length;

    _inTransaction(() {
      if (isUpdate) {
        _prepared(
          'UPDATE recipes SET slug = ?, source_slug = ?, title = ?, '
          'category = ?, servings_text = ?, serves_min = ?, serves_max = ?, '
          'prep_min = ?, cook_min = ?, total_min = ?, hero_image = ?, '
          'variation_count = ?, '
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
          variationCount,
          doc,
          contentHash,
          recipe.id,
        ]);
      } else {
        _prepared(
          'INSERT INTO recipes (id, slug, source_slug, title, category, '
          'servings_text, serves_min, serves_max, prep_min, cook_min, '
          'total_min, hero_image, variation_count, doc, content_hash) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
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
          variationCount,
          doc,
          contentHash,
        ]);
      }
      final rowid =
          _prepared(
                'SELECT rowid FROM recipes WHERE id = ?',
              ).select([recipe.id]).first['rowid']
              as int;
      _rebuildIngredients(recipe);
      _rebuildTags(recipe);
      _rebuildFts(recipe, rowid);
    });
    return isUpdate ? UpsertOutcome.updated : UpsertOutcome.inserted;
  }

  /// Whether a recipe row with exactly this [id] exists.
  bool recipeExists(String id) =>
      _prepared('SELECT 1 FROM recipes WHERE id = ?').select([id]).isNotEmpty;

  /// Public form of the slug-collision resolution [upsertRecipe] applies, so
  /// callers that need the final slug *before* encoding the canonical YAML
  /// (the editor save path) resolve it identically.
  String availableSlug(String desired, {required String ownerId}) =>
      _availableSlug(desired, ownerId: ownerId);

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
    _prepared(
      'DELETE FROM recipe_ingredients WHERE recipe_id = ?',
    ).execute([recipe.id]);
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
    _pruneOrphanTags();
  }

  /// Drops tag rows no recipe links to anymore, so the tags list reflects
  /// reality after edits and deletes. `tag_styles` rows are keyed by name and
  /// deliberately survive, so a re-added tag gets its old style back.
  void _pruneOrphanTags() {
    _prepared(
      'DELETE FROM tags WHERE id NOT IN '
      '(SELECT DISTINCT tag_id FROM recipe_tags)',
    ).execute();
  }

  /// Deletes the recipe row plus its FTS entry (side tables cascade).
  /// Returns false when no such recipe exists.
  bool deleteRecipe(String recipeId) {
    final rows = _prepared(
      'SELECT rowid FROM recipes WHERE id = ?',
    ).select([recipeId]);
    if (rows.isEmpty) {
      return false;
    }
    final rowid = rows.first['rowid'] as int;
    _inTransaction(() {
      _prepared('DELETE FROM recipe_fts WHERE rowid = ?').execute([rowid]);
      _prepared('DELETE FROM recipes WHERE id = ?').execute([recipeId]);
      _pruneOrphanTags();
    });
    return true;
  }

  /// Rebuilds the FTS row for a recipe, keyed by the recipes rowid (the FTS
  /// docid) so delete/insert are O(1) rather than a full virtual-table scan.
  ///
  /// Subsection content joins the same columns as its top-level counterpart
  /// (383 of the 1,198 corpus recipes carry subsections — their ingredients
  /// and steps must be searchable). Subsection titles/body and technique
  /// headings/descriptions fold into the background column: prose, not
  /// recipe titles, so they must not skew bm25's title weighting.
  void _rebuildFts(Recipe recipe, int rowid) {
    _prepared('DELETE FROM recipe_fts WHERE rowid = ?').execute([rowid]);
    final tags = [
      for (final tag in recipe.tags) tag.toLowerCase().trim(),
    ].join(' ');
    final ingredients = [
      for (final group in recipe.ingredients)
        for (final line in group.items) line.raw,
      for (final sub in recipe.subsections)
        for (final group in sub.ingredients ?? const <IngredientGroup>[])
          for (final line in group.items) line.raw,
    ].join('\n');
    final directions = [
      for (final step in recipe.steps) step.text,
      for (final sub in recipe.subsections)
        for (final step in sub.steps ?? const <RecipeStep>[]) step.text,
      for (final technique in recipe.techniques)
        for (final step in technique.steps)
          if (step.caption.isNotEmpty) step.caption,
    ].join('\n');
    final background = [
      if ((recipe.background ?? '').isNotEmpty) recipe.background!,
      for (final sub in recipe.subsections) ...[
        if ((sub.title ?? '').isNotEmpty) sub.title!,
        if ((sub.body ?? '').isNotEmpty) sub.body!,
      ],
      for (final technique in recipe.techniques) ...[
        if ((technique.heading ?? '').isNotEmpty) technique.heading!,
        if ((technique.description ?? '').isNotEmpty) technique.description!,
      ],
    ].join('\n');
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
      background,
      recipe.prepNotes ?? '',
    ]);
  }

  /// Whether a sources row with this [slug] exists.
  bool sourceExists(String slug) => _prepared(
    'SELECT 1 FROM sources WHERE slug = ?',
  ).select([slug]).isNotEmpty;

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

  /// Writes a compacted point-in-time snapshot of the whole database to
  /// [path] (`VACUUM INTO`). The target must not exist yet.
  void vacuumInto(String path) {
    // VACUUM cannot run inside a transaction and takes the path as a bound
    // expression, so no string interpolation is needed.
    _db.execute('VACUUM INTO ?', [path]);
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
    int? viewerId,
    bool favoritesOnly = false,
  }) {
    var offset = (page - 1) * limit;
    if (offset < 0) {
      offset = 0;
    }
    if (favoritesOnly && viewerId == null) {
      return (items: const <RecipeCard>[], total: 0);
    }
    final favoriteFilter = favoritesOnly
        ? ' WHERE EXISTS (SELECT 1 FROM user_favorites f '
              'WHERE f.user_id = ? AND f.recipe_id = recipes.id)'
        : '';
    final filterParams = favoritesOnly ? [viewerId] : const <Object?>[];
    final total =
        _prepared(
              'SELECT COUNT(*) AS n FROM recipes$favoriteFilter',
            ).select(filterParams).first['n']
            as int;
    final rows = _prepared(
      'SELECT recipes.id, slug, source_slug, title, category, '
      'servings_text, total_min, hero_image, variation_count, '
      'n.calories_per_serving AS calories FROM recipes '
      'LEFT JOIN recipe_nutrition n ON n.recipe_id = recipes.id'
      '$favoriteFilter '
      'ORDER BY title COLLATE NOCASE LIMIT ? OFFSET ?',
    ).select([...filterParams, limit, offset]);
    return (items: _cardsFromRows(rows, viewerId: viewerId), total: total);
  }

  /// Builds cards (with tags batched in one query) from a result set that
  /// carries the standard card columns.
  List<RecipeCard> _cardsFromRows(ResultSet rows, {int? viewerId}) {
    final ids = [for (final row in rows) row['id'] as String];
    final tagsByRecipe = _tagsFor(ids);
    final favorites = viewerId == null
        ? const <String>{}
        : _favoriteIdsAmong(viewerId, ids);
    return [
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
          caloriesPerServing: (row['calories'] as num?)?.toDouble(),
          favorite: favorites.contains(row['id'] as String),
          variationCount: row['variation_count'] as int? ?? 0,
        ),
    ];
  }

  /// The subset of [recipeIds] the user has favorited, in one query.
  Set<String> _favoriteIdsAmong(int userId, List<String> recipeIds) {
    if (recipeIds.isEmpty) {
      return const {};
    }
    final placeholders = List.filled(recipeIds.length, '?').join(', ');
    final rows = _db.select(
      'SELECT recipe_id FROM user_favorites '
      'WHERE user_id = ? AND recipe_id IN ($placeholders)',
      [userId, ...recipeIds],
    );
    return {for (final row in rows) row['recipe_id'] as String};
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

  /// One page of search results for a parsed and [compiled] query, ordered
  /// by relevance (bm25) — or by calories when the query filters on them.
  ///
  /// Calories filters need the nutrition tables (P6); until they exist any
  /// calories-constrained query truthfully matches nothing.
  ({List<RecipeCard> items, int total}) searchCards(
    CompiledSearch compiled, {
    required int page,
    required int limit,
    int? viewerId,
    bool favoritesOnly = false,
  }) {
    final match = compiled.ftsMatch;
    if (match == null && compiled.calories.isEmpty) {
      return listCards(
        page: page,
        limit: limit,
        viewerId: viewerId,
        favoritesOnly: favoritesOnly,
      );
    }
    if (favoritesOnly && viewerId == null) {
      return (items: const <RecipeCard>[], total: 0);
    }
    var offset = (page - 1) * limit;
    if (offset < 0) {
      offset = 0;
    }

    // Assemble FROM/WHERE/ORDER from the three optional constraints: the
    // FTS match, the calories filter (via recipe_nutrition — recipes
    // without computed nutrition truthfully never match), and favorites.
    // Calorie queries order lowest-first (the old app's contract);
    // otherwise relevance. All values are bound parameters; the only
    // interpolations are operator symbols from the CaloriesOp enum.
    final params = <Object?>[];
    var from = 'FROM recipes r';
    final conditions = <String>[];
    if (match != null) {
      from = 'FROM recipe_fts f JOIN recipes r ON r.rowid = f.rowid';
      conditions.add('recipe_fts MATCH ?');
      params.add(match);
    }
    // Always joined (LEFT) so text-only results still carry the calorie
    // badge; the calories filter tightens it to an inner-join semantics
    // via the IS NOT NULL condition.
    from += ' LEFT JOIN recipe_nutrition n ON n.recipe_id = r.id';
    if (compiled.calories.isNotEmpty) {
      conditions.add('n.calories_per_serving IS NOT NULL');
      for (final node in compiled.calories) {
        conditions.add('n.calories_per_serving ${node.op.symbol} ?');
        params.add(node.value);
      }
    }
    if (favoritesOnly) {
      conditions.add(
        'EXISTS (SELECT 1 FROM user_favorites uf '
        'WHERE uf.user_id = ? AND uf.recipe_id = r.id)',
      );
      params.add(viewerId);
    }
    final where = 'WHERE ${conditions.join(' AND ')}';
    // Title tiebreakers: equal bm25 scores (and equal calorie values) are
    // common, and OFFSET pagination needs a stable total order.
    final order = compiled.orderByCalories
        ? 'ORDER BY n.calories_per_serving, r.title COLLATE NOCASE'
        : 'ORDER BY bm25(recipe_fts), r.title COLLATE NOCASE';

    final total =
        _prepared('SELECT COUNT(*) AS n $from $where').select(params).first['n']
            as int;
    final rows = _prepared(
      'SELECT r.id, r.slug, r.source_slug, r.title, r.category, '
      'r.servings_text, r.total_min, r.hero_image, r.variation_count, '
      'n.calories_per_serving '
      'AS calories $from $where $order LIMIT ? OFFSET ?',
    ).select([...params, limit, offset]);
    return (items: _cardsFromRows(rows, viewerId: viewerId), total: total);
  }

  /// Every recipe's stored doc plus its nutrition status, for the admin
  /// recipe-review scan. `nutStatus == null` means nutrition was never
  /// computed. Ordered by title so the review list is stable.
  List<
    ({
      String id,
      String slug,
      String source,
      String title,
      String doc,
      String? nutStatus,
      int matched,
      int total,
    })
  >
  recipeReviewScanRows() {
    final rows = _db.select(
      'SELECT r.id, r.slug, r.source_slug AS source, r.title, r.doc, '
      'n.status AS nut_status, n.matched_count, n.total_count '
      'FROM recipes r LEFT JOIN recipe_nutrition n ON n.recipe_id = r.id '
      'ORDER BY r.title COLLATE NOCASE',
    );
    return [
      for (final row in rows)
        (
          id: row['id'] as String,
          slug: row['slug'] as String,
          source: row['source'] as String,
          title: row['title'] as String,
          doc: row['doc'] as String,
          nutStatus: row['nut_status'] as String?,
          matched: (row['matched_count'] as int?) ?? 0,
          total: (row['total_count'] as int?) ?? 0,
        ),
    ];
  }

  /// A cheap fingerprint of everything the recipe-review report is derived from
  /// (recipe rows and their nutrition), for memoizing the expensive full scan.
  /// It changes whenever a recipe or a nutrition row is inserted, updated, or
  /// deleted: a recipe write stamps `recipes.updated_at`, a nutrition write
  /// stamps `recipe_nutrition.computed_at` (the two tables name their timestamp
  /// differently — nutrition has no `updated_at`), and a delete moves the row
  /// count. So the cache is never served stale beyond same-second concurrent
  /// edits — immaterial for a data-quality view. Sub-millisecond: two counts
  /// and two maxes.
  String recipeReviewFingerprint() {
    final row = _db
        .select(
          'SELECT (SELECT count(*) FROM recipes) AS rc, '
          "(SELECT coalesce(max(updated_at), '') FROM recipes) AS rm, "
          '(SELECT count(*) FROM recipe_nutrition) AS nc, '
          "(SELECT coalesce(max(computed_at), '') FROM recipe_nutrition) AS nm",
        )
        .first;
    return '${row['rc']}|${row['rm']}|${row['nc']}|${row['nm']}';
  }

  /// Every tag with its recipe count and (optional) chip style, ordered by
  /// name.
  List<TagInfoRow> listTags() {
    final rows = _db.select(
      'SELECT t.name AS name, COUNT(rt.recipe_id) AS n, '
      's.icon AS icon, s.color AS color, s.bg_color AS bg_color '
      'FROM tags t '
      'LEFT JOIN recipe_tags rt ON rt.tag_id = t.id '
      'LEFT JOIN tag_styles s ON s.tag_name = t.name '
      'GROUP BY t.id ORDER BY t.name',
    );
    return [
      for (final row in rows)
        TagInfoRow(
          name: row['name'] as String,
          count: row['n'] as int,
          icon: row['icon'] as String?,
          color: row['color'] as String?,
          bgColor: row['bg_color'] as String?,
        ),
    ];
  }

  /// Whether a tag with this (lowercased) [name] exists.
  bool tagExists(String name) =>
      _prepared('SELECT 1 FROM tags WHERE name = ?').select([name]).isNotEmpty;

  /// Creates or updates the chip style for [tagName].
  void upsertTagStyle(
    String tagName, {
    String? icon,
    String? color,
    String? bgColor,
  }) {
    _prepared(
      'INSERT INTO tag_styles (tag_name, icon, color, bg_color) '
      'VALUES (?, ?, ?, ?) '
      'ON CONFLICT(tag_name) DO UPDATE SET '
      'icon = excluded.icon, color = excluded.color, '
      'bg_color = excluded.bg_color',
    ).execute([tagName, icon, color, bgColor]);
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

  /// The stored content hash for [recipeId], or null when absent.
  ///
  /// The hash is SHA-256 of the canonical YAML the server last exported, so
  /// comparing it against a library file's text detects external edits.
  String? contentHashOf(String recipeId) {
    final rows = _prepared(
      'SELECT content_hash FROM recipes WHERE id = ?',
    ).select([recipeId]);
    return rows.isEmpty ? null : rows.first['content_hash'] as String;
  }

  /// id, source slug, and content hash of every recipe — the DB side of the
  /// library reconciliation scan.
  List<({String id, String sourceSlug, String contentHash})>
  listRecipeHashes() {
    final rows = _db.select(
      'SELECT id, source_slug, content_hash FROM recipes ORDER BY id',
    );
    return [
      for (final row in rows)
        (
          id: row['id'] as String,
          sourceSlug: row['source_slug'] as String,
          contentHash: row['content_hash'] as String,
        ),
    ];
  }

  /// The settings-table value for [key], or null when unset.
  String? getSetting(String key) {
    final rows = _prepared(
      'SELECT value FROM settings WHERE key = ?',
    ).select([key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  /// Creates or replaces the settings-table value for [key].
  void setSetting(String key, String value) {
    _prepared(
      'INSERT INTO settings (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
    ).execute([key, value]);
  }

  /// Removes the settings-table row for [key]; a no-op when it is unset.
  ///
  /// Unsetting differs from storing an empty value: [getSetting] then reports
  /// null, which is how single-use secrets (the recovery code) are consumed
  /// rather than left behind as a spent row.
  void deleteSetting(String key) {
    _prepared('DELETE FROM settings WHERE key = ?').execute([key]);
  }

  // --------------------------------------------------------------------
  // Nutrition (migration 005): FDC caches, per-line matches, computed
  // per-serving totals, bulk-job bookkeeping.
  // --------------------------------------------------------------------

  /// Cached FDC search response JSON for a normalized query, or null.
  String? fdcSearchCacheGet(String query) {
    final rows = _prepared(
      'SELECT response FROM fdc_search_cache WHERE query = ?',
    ).select([query]);
    return rows.isEmpty ? null : rows.first['response'] as String;
  }

  /// Stores a search response in the cache.
  void fdcSearchCachePut(String query, String responseJson) {
    _prepared(
      'INSERT INTO fdc_search_cache (query, response) VALUES (?, ?) '
      'ON CONFLICT(query) DO UPDATE SET response = excluded.response, '
      "fetched_at = datetime('now')",
    ).execute([query, responseJson]);
  }

  /// Cached FDC food-detail JSON, or null.
  String? fdcFoodCacheGet(int fdcId) {
    final rows = _prepared(
      'SELECT response FROM fdc_food_cache WHERE fdc_id = ?',
    ).select([fdcId]);
    return rows.isEmpty ? null : rows.first['response'] as String;
  }

  /// Stores a food detail in the cache.
  void fdcFoodCachePut(int fdcId, String responseJson) {
    _prepared(
      'INSERT INTO fdc_food_cache (fdc_id, response) VALUES (?, ?) '
      'ON CONFLICT(fdc_id) DO UPDATE SET response = excluded.response, '
      "fetched_at = datetime('now')",
    ).execute([fdcId, responseJson]);
  }

  /// All ingredient matches for a recipe, in position order.
  List<IngredientMatchRow> ingredientMatchesFor(String recipeId) {
    final rows = _prepared(
      'SELECT recipe_id, position, raw, fdc_id, description, data_type, '
      'confidence, grams, gram_source, status, updated_at '
      'FROM ingredient_matches WHERE recipe_id = ? ORDER BY position',
    ).select([recipeId]);
    return [for (final row in rows) IngredientMatchRow.fromRow(row)];
  }

  /// The triage bucket for a match row, in SQL — the same buckets the
  /// per-recipe review sheet uses (`_bucketOf`), EXCEPT that a `confirmed` or
  /// `overridden` line is treated as `counted`: it has been resolved, so a
  /// cross-recipe "needs attention" queue must not surface it (e.g. confirmed
  /// water is a deliberate no-match, not a problem to fix).
  static const String _reviewBucketCase = '''
    CASE
      WHEN im.status IN ('confirmed', 'overridden') THEN 'counted'
      WHEN im.status = 'skipped' THEN 'skipped'
      WHEN im.fdc_id IS NULL THEN 'no_match'
      WHEN im.grams IS NULL THEN 'no_grams'
      WHEN im.confidence < 0.5 THEN 'check'
      ELSE 'counted'
    END''';

  /// Count of match rows in each triage bucket, across all computed recipes.
  Map<String, int> nutritionReviewCounts() {
    final rows = _prepared(
      'SELECT bucket, COUNT(*) AS n FROM ( '
      'SELECT $_reviewBucketCase AS bucket FROM ingredient_matches im '
      ') GROUP BY bucket',
    ).select();
    return {for (final row in rows) row['bucket'] as String: row['n'] as int};
  }

  /// One page of flagged match lines across ALL recipes, worst-confidence
  /// first, each carrying its recipe's slug + title. [bucket] narrows to a
  /// single triage bucket; null returns every flagged bucket
  /// (no_match / no_grams / check), never `skipped` or `counted`.
  List<NutritionReviewLineRow> nutritionReviewLines({
    required int limit,
    required int offset,
    String? bucket,
  }) {
    final where = bucket == null
        ? "bucket IN ('no_match', 'no_grams', 'check')"
        : 'bucket = ?';
    final rows = _prepared(
      'SELECT * FROM ( '
      'SELECT im.recipe_id, im.position, im.raw, im.fdc_id, im.description, '
      'im.data_type, im.confidence, im.grams, im.gram_source, im.status, '
      'im.updated_at, r.slug AS review_slug, r.title AS review_title, '
      '$_reviewBucketCase AS bucket '
      'FROM ingredient_matches im JOIN recipes r ON r.id = im.recipe_id '
      ') WHERE $where '
      'ORDER BY confidence ASC, review_title, position LIMIT ? OFFSET ?',
    ).select([if (bucket != null) bucket, limit, offset]);
    return [
      for (final row in rows)
        (
          match: IngredientMatchRow.fromRow(row),
          slug: row['review_slug'] as String,
          title: row['review_title'] as String,
          bucket: row['bucket'] as String,
        ),
    ];
  }

  /// Creates or replaces one match row.
  void upsertIngredientMatch(IngredientMatchRow row) {
    _prepared(
      'INSERT INTO ingredient_matches (recipe_id, position, raw, fdc_id, '
      'description, data_type, confidence, grams, gram_source, status, '
      'updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(recipe_id, position) DO UPDATE SET raw = excluded.raw, '
      'fdc_id = excluded.fdc_id, description = excluded.description, '
      'data_type = excluded.data_type, confidence = excluded.confidence, '
      'grams = excluded.grams, gram_source = excluded.gram_source, '
      'status = excluded.status, updated_at = excluded.updated_at',
    ).execute([
      row.recipeId,
      row.position,
      row.raw,
      row.fdcId,
      row.description,
      row.dataType,
      row.confidence,
      row.grams,
      row.gramSource,
      row.status,
      _utcNowIso(),
    ]);
  }

  /// Drops match rows at or beyond [fromPosition] (an edit shortened the
  /// ingredient list).
  void deleteIngredientMatchesFrom(String recipeId, int fromPosition) {
    _prepared(
      'DELETE FROM ingredient_matches WHERE recipe_id = ? AND position >= ?',
    ).execute([recipeId, fromPosition]);
  }

  /// The computed nutrition row for a recipe, or null.
  RecipeNutritionRow? nutritionFor(String recipeId) {
    final rows = _prepared(
      'SELECT recipe_id, serving_basis, calories_per_serving, nutrients, '
      'total_grams, matched_count, total_count, status, ingredients_hash, '
      'computed_at FROM recipe_nutrition WHERE recipe_id = ?',
    ).select([recipeId]);
    return rows.isEmpty ? null : RecipeNutritionRow.fromRow(rows.first);
  }

  /// Creates or replaces the computed nutrition for a recipe.
  void upsertRecipeNutrition({
    required String recipeId,
    required int servingBasis,
    required double? caloriesPerServing,
    required String nutrientsJson,
    required double totalGrams,
    required int matchedCount,
    required int totalCount,
    required String status,
    required String ingredientsHash,
  }) {
    _prepared(
      'INSERT INTO recipe_nutrition (recipe_id, serving_basis, '
      'calories_per_serving, nutrients, total_grams, matched_count, '
      'total_count, status, ingredients_hash, computed_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(recipe_id) DO UPDATE SET '
      'serving_basis = excluded.serving_basis, '
      'calories_per_serving = excluded.calories_per_serving, '
      'nutrients = excluded.nutrients, '
      'total_grams = excluded.total_grams, '
      'matched_count = excluded.matched_count, '
      'total_count = excluded.total_count, status = excluded.status, '
      'ingredients_hash = excluded.ingredients_hash, '
      'computed_at = excluded.computed_at',
    ).execute([
      recipeId,
      servingBasis,
      caloriesPerServing,
      nutrientsJson,
      totalGrams,
      matchedCount,
      totalCount,
      status,
      ingredientsHash,
      _utcNowIso(),
    ]);
  }

  /// Every recipe id, ordered — for whole-library maintenance passes.
  List<String> allRecipeIds() {
    final rows = _db.select('SELECT id FROM recipes ORDER BY id');
    return [for (final row in rows) row['id'] as String];
  }

  /// Recipe ids that have no computed nutrition yet (bulk-job work list).
  List<String> recipeIdsWithoutNutrition() {
    final rows = _db.select(
      'SELECT r.id FROM recipes r '
      'LEFT JOIN recipe_nutrition n ON n.recipe_id = r.id '
      'WHERE n.recipe_id IS NULL ORDER BY r.id',
    );
    return [for (final row in rows) row['id'] as String];
  }

  /// Creates a nutrition bulk-job row; returns its id.
  int createNutritionJob(int total) {
    _prepared(
      'INSERT INTO nutrition_jobs (status, total, started_at) '
      "VALUES ('running', ?, ?)",
    ).execute([total, _utcNowIso()]);
    return _db.lastInsertRowId;
  }

  /// Updates bulk-job progress.
  void updateNutritionJob(
    int id, {
    required int done,
    required int failed,
    String? status,
    String? logJson,
  }) {
    _prepared(
      'UPDATE nutrition_jobs SET done = ?, failed = ?, '
      'status = COALESCE(?, status), log = COALESCE(?, log), '
      "finished_at = CASE WHEN ? IN ('done','failed') THEN ? "
      'ELSE finished_at END WHERE id = ?',
    ).execute([done, failed, status, logJson, status ?? '', _utcNowIso(), id]);
  }

  /// Creates an import-job row; returns its id.
  int createImportJob({required String sourcePath, required bool legacy}) {
    _prepared(
      'INSERT INTO import_jobs (status, source_path, legacy, started_at) '
      "VALUES ('running', ?, ?, ?)",
    ).execute([sourcePath, if (legacy) 1 else 0, _utcNowIso()]);
    return _db.lastInsertRowId;
  }

  /// Updates import-job progress (called from the import isolate).
  void updateImportJobProgress(int id, {required int done, int? total}) {
    _prepared(
      'UPDATE import_jobs SET done = ?, total = COALESCE(?, total) '
      'WHERE id = ?',
    ).execute([done, total, id]);
  }

  /// Records an import job's terminal state and summary counters.
  void finishImportJob(
    int id, {
    required String status,
    required int total,
    required int done,
    required int imported,
    required int updated,
    required int skipped,
    required int failed,
    required String logJson,
  }) {
    _prepared(
      'UPDATE import_jobs SET status = ?, total = ?, done = ?, '
      'imported = ?, updated = ?, skipped = ?, failed = ?, log = ?, '
      'finished_at = ? WHERE id = ?',
    ).execute([
      status,
      total,
      done,
      imported,
      updated,
      skipped,
      failed,
      logJson,
      _utcNowIso(),
      id,
    ]);
  }

  /// One import-job row as JSON-ready values, or null.
  Map<String, Object?>? importJob(int id) {
    final rows = _prepared(
      'SELECT id, status, source_path, legacy, total, done, imported, '
      'updated, skipped, failed, log, started_at, finished_at '
      'FROM import_jobs WHERE id = ?',
    ).select([id]);
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return {
      'id': row['id'],
      'status': row['status'],
      'source_path': row['source_path'],
      'legacy': row['legacy'] == 1,
      'total': row['total'],
      'done': row['done'],
      'imported': row['imported'],
      'updated': row['updated'],
      'skipped': row['skipped'],
      'failed': row['failed'],
      'log': jsonDecode(row['log'] as String),
      'started_at': row['started_at'],
      'finished_at': row['finished_at'],
    };
  }

  /// Marks import jobs still `running` as failed — boot reconciliation,
  /// same contract as [failOrphanedNutritionJobs].
  int failOrphanedImportJobs() {
    _prepared(
      "UPDATE import_jobs SET status = 'failed', finished_at = ?, "
      r"log = json_insert(log, '$[#]', "
      "'interrupted by a server restart') WHERE status = 'running'",
    ).execute([_utcNowIso()]);
    return _db.updatedRows;
  }

  /// Marks jobs still `running` as failed — called once at boot, where a
  /// `running` row can only be an orphan from a crashed/restarted process
  /// (the job loop lives in server memory). Returns how many were closed.
  int failOrphanedNutritionJobs() {
    _prepared(
      "UPDATE nutrition_jobs SET status = 'failed', finished_at = ?, "
      r"log = json_insert(log, '$[#]', "
      "'interrupted by a server restart') WHERE status = 'running'",
    ).execute([_utcNowIso()]);
    return _db.updatedRows;
  }

  /// One bulk-job row as JSON-ready values, or null.
  Map<String, Object?>? nutritionJob(int id) {
    final rows = _prepared(
      'SELECT id, status, total, done, failed, log, started_at, finished_at '
      'FROM nutrition_jobs WHERE id = ?',
    ).select([id]);
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return {
      'id': row['id'],
      'status': row['status'],
      'total': row['total'],
      'done': row['done'],
      'failed': row['failed'],
      'log': jsonDecode(row['log'] as String),
      'started_at': row['started_at'],
      'finished_at': row['finished_at'],
    };
  }

  // --------------------------------------------------------------------
  // Favorites & personal notes (migration 004) — per-user, DB-only data.
  // --------------------------------------------------------------------

  /// Whether [userId] has favorited [recipeId].
  bool isFavorite({required int userId, required String recipeId}) => _prepared(
    'SELECT 1 FROM user_favorites WHERE user_id = ? AND recipe_id = ?',
  ).select([userId, recipeId]).isNotEmpty;

  /// Adds or removes the favorite mark; both directions are idempotent.
  void setFavorite({
    required int userId,
    required String recipeId,
    required bool favorite,
  }) {
    if (favorite) {
      _prepared(
        'INSERT OR IGNORE INTO user_favorites (user_id, recipe_id) '
        'VALUES (?, ?)',
      ).execute([userId, recipeId]);
    } else {
      _prepared(
        'DELETE FROM user_favorites WHERE user_id = ? AND recipe_id = ?',
      ).execute([userId, recipeId]);
    }
  }

  /// The user's personal note body for [recipeId], or null when none exists.
  String? noteFor({required int userId, required String recipeId}) {
    final rows = _prepared(
      'SELECT body FROM user_notes WHERE user_id = ? AND recipe_id = ?',
    ).select([userId, recipeId]);
    return rows.isEmpty ? null : rows.first['body'] as String;
  }

  /// Creates or replaces the user's personal note for [recipeId].
  void setNote({
    required int userId,
    required String recipeId,
    required String body,
  }) {
    _prepared(
      'INSERT INTO user_notes (user_id, recipe_id, body, updated_at) '
      'VALUES (?, ?, ?, ?) '
      'ON CONFLICT(user_id, recipe_id) DO UPDATE SET '
      'body = excluded.body, updated_at = excluded.updated_at',
    ).execute([userId, recipeId, body, _utcNowIso()]);
  }

  /// Deletes the user's personal note for [recipeId]; idempotent.
  void deleteNote({required int userId, required String recipeId}) {
    _prepared(
      'DELETE FROM user_notes WHERE user_id = ? AND recipe_id = ?',
    ).execute([userId, recipeId]);
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

  static const _userColumns =
      'id, username, password_hash, role, '
      'must_change_password, disabled, created_at, last_active_at';
  static const _sessionColumns =
      'token_hash, user_id, created_at, '
      'expires_at, last_seen_at, remember, user_agent';
  static const _apiTokenColumns =
      'id, user_id, name, prefix, scope, '
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
    _prepared('UPDATE users SET role = ? WHERE id = ?').execute([role, userId]);
  }

  /// Enables or disables a user. Disabling also deletes all of the user's
  /// sessions (in the same transaction) so access ends immediately.
  void setUserDisabled(int userId, {required bool disabled}) {
    if (!disabled) {
      _prepared('UPDATE users SET disabled = 0 WHERE id = ?').execute([userId]);
      return;
    }
    _inTransaction(() {
      _prepared('UPDATE users SET disabled = 1 WHERE id = ?').execute([userId]);
      _prepared('DELETE FROM sessions WHERE user_id = ?').execute([userId]);
    });
  }

  /// Permanently deletes the user. Everything keyed to them — sessions, API
  /// tokens, favorites, and personal notes — cascades (`ON DELETE CASCADE`);
  /// recipes are not user-owned, so they are untouched. Returns whether a row
  /// was removed (false = no such user). Unlike disable, this is irreversible.
  bool deleteUser(int userId) {
    _prepared('DELETE FROM users WHERE id = ?').execute([userId]);
    return _db.updatedRows > 0;
  }

  /// Sets the user's `last_active_at` to now.
  void touchUserActivity(int userId) {
    _prepared(
      'UPDATE users SET last_active_at = ? WHERE id = ?',
    ).execute([_utcNowIso(), userId]);
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
      _prepared(
        'UPDATE sessions SET last_seen_at = ? WHERE token_hash = ?',
      ).execute([_utcNowIso(), tokenHash]);
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
    _prepared('DELETE FROM sessions WHERE token_hash = ?').execute([tokenHash]);
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
    _prepared(
      'DELETE FROM sessions WHERE datetime(expires_at) < datetime(?)',
    ).execute([_utcNowIso()]);
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

  /// The API token with [id] owned by [userId], or null. A single-row lookup so
  /// echoing a freshly-minted token does not re-read the user's whole list.
  ApiTokenRow? apiTokenById({required int id, required int userId}) {
    final rows = _prepared(
      'SELECT $_apiTokenColumns FROM api_tokens WHERE id = ? AND user_id = ?',
    ).select([id, userId]);
    return rows.isEmpty ? null : _apiTokenRow(rows.first);
  }

  /// How many LIVE (non-revoked) tokens [userId] holds — the count a per-user
  /// cap is enforced against. Revoked rows are excluded: they are spent, and
  /// counting them would lock a user out of minting after routine rotation.
  int activeApiTokenCount(int userId) {
    final rows = _prepared(
      'SELECT COUNT(*) AS n FROM api_tokens '
      'WHERE user_id = ? AND revoked_at IS NULL',
    ).select([userId]);
    return rows.first['n'] as int;
  }

  /// Sets the token's `last_used_at` to now.
  void touchApiToken(int id) {
    _prepared(
      'UPDATE api_tokens SET last_used_at = ? WHERE id = ?',
    ).execute([_utcNowIso(), id]);
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

  /// Revokes every live API token belonging to [userId]; returns how many.
  ///
  /// For account recovery: a PAT is a standalone credential that survives a
  /// password reset, so leaving them live would hand whoever caused the
  /// lockout a way straight back in.
  int revokeAllApiTokens(int userId) {
    _prepared(
      'UPDATE api_tokens SET revoked_at = ? '
      'WHERE user_id = ? AND revoked_at IS NULL',
    ).execute([_utcNowIso(), userId]);
    return _db.updatedRows;
  }

  /// Housekeeping: deletes revoked API tokens whose revocation is older than
  /// [cutoff], returning how many were removed. Live tokens (`revoked_at IS
  /// NULL`) are never touched. How long a revoked row is kept is a
  /// data-retention policy the operator sets via `API_TOKEN_RETENTION_DAYS`;
  /// the mint-then-revoke loop that grows this table without such pruning was a
  /// recorded residual. `datetime()` normalizes both sides, matching
  /// [deleteExpiredSessions].
  int deleteRevokedApiTokensBefore(DateTime cutoff) {
    _prepared(
      'DELETE FROM api_tokens '
      'WHERE revoked_at IS NOT NULL AND datetime(revoked_at) < datetime(?)',
    ).execute([cutoff.toUtc().toIso8601String()]);
    return _db.updatedRows;
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

/// A flagged match line for the cross-recipe nutrition-review queue: the match
/// row plus the recipe context (slug/title) and its computed triage bucket.
typedef NutritionReviewLineRow = ({
  IngredientMatchRow match,
  String slug,
  String title,
  String bucket,
});

/// One tag with its usage count and optional chip style.
/// One row of `ingredient_matches`.
class IngredientMatchRow {
  /// Builds a row from its parts.
  const IngredientMatchRow({
    required this.recipeId,
    required this.position,
    required this.raw,
    required this.fdcId,
    required this.description,
    required this.dataType,
    required this.confidence,
    required this.grams,
    required this.gramSource,
    required this.status,
    this.updatedAt,
  });

  /// Decodes a database row.
  factory IngredientMatchRow.fromRow(Row row) => IngredientMatchRow(
    recipeId: row['recipe_id'] as String,
    position: row['position'] as int,
    raw: row['raw'] as String,
    fdcId: row['fdc_id'] as int?,
    description: row['description'] as String?,
    dataType: row['data_type'] as String?,
    confidence: (row['confidence'] as num).toDouble(),
    grams: (row['grams'] as num?)?.toDouble(),
    gramSource: row['gram_source'] as String?,
    status: row['status'] as String,
    updatedAt: row['updated_at'] as String?,
  );

  /// Recipe the line belongs to.
  final String recipeId;

  /// Zero-based line position across all ingredient groups.
  final int position;

  /// The line's raw text when the match was made (staleness display).
  final String raw;

  /// Matched FDC food id, or null (water-like / unmatched).
  final int? fdcId;

  /// Matched food description.
  final String? description;

  /// Matched food data type (`Foundation` / `SR Legacy`).
  final String? dataType;

  /// Match confidence 0–1.
  final double confidence;

  /// Resolved grams for the whole line, or null.
  final double? grams;

  /// How grams were determined (a `GramSource` name), or null.
  final String? gramSource;

  /// `auto` | `confirmed` | `overridden` | `skipped` | `unmatched`.
  final String status;

  /// Last write time (UTC ISO-8601).
  final String? updatedAt;

  /// Copy with changed fields (explicit clears for the nullables).
  IngredientMatchRow copyWith({
    int? fdcId,
    bool clearFdcId = false,
    String? description,
    String? dataType,
    double? confidence,
    double? grams,
    bool clearGrams = false,
    String? gramSource,
    bool clearGramSource = false,
    String? status,
  }) => IngredientMatchRow(
    recipeId: recipeId,
    position: position,
    raw: raw,
    fdcId: clearFdcId ? null : (fdcId ?? this.fdcId),
    description: description ?? this.description,
    dataType: dataType ?? this.dataType,
    confidence: confidence ?? this.confidence,
    grams: clearGrams ? null : (grams ?? this.grams),
    gramSource: clearGramSource ? null : (gramSource ?? this.gramSource),
    status: status ?? this.status,
  );
}

/// One row of `recipe_nutrition`.
class RecipeNutritionRow {
  /// Builds a row from its parts.
  const RecipeNutritionRow({
    required this.recipeId,
    required this.servingBasis,
    required this.caloriesPerServing,
    required this.nutrientsJson,
    required this.totalGrams,
    required this.matchedCount,
    required this.totalCount,
    required this.status,
    required this.ingredientsHash,
    required this.computedAt,
  });

  /// Decodes a database row.
  factory RecipeNutritionRow.fromRow(Row row) => RecipeNutritionRow(
    recipeId: row['recipe_id'] as String,
    servingBasis: row['serving_basis'] as int?,
    caloriesPerServing: (row['calories_per_serving'] as num?)?.toDouble(),
    nutrientsJson: row['nutrients'] as String,
    totalGrams: (row['total_grams'] as num?)?.toDouble(),
    matchedCount: row['matched_count'] as int,
    totalCount: row['total_count'] as int,
    status: row['status'] as String,
    ingredientsHash: row['ingredients_hash'] as String,
    computedAt: row['computed_at'] as String?,
  );

  /// Recipe the totals belong to.
  final String recipeId;

  /// Per-serving divisor used for the stored values.
  final int? servingBasis;

  /// Denormalized kcal per serving (search filter/ordering).
  final double? caloriesPerServing;

  /// JSON: nutrient key → {label, amount, unit, dv_percent?}.
  final String nutrientsJson;

  /// Total contributing grams across the whole recipe.
  final double? totalGrams;

  /// Lines contributing nutrients (incl. zero-value water).
  final int matchedCount;

  /// Total ingredient lines at compute time.
  final int totalCount;

  /// `complete` | `partial` (staleness is derived at read time by
  /// comparing [ingredientsHash] to the current recipe).
  final String status;

  /// Hash of the ingredient lines the totals were computed from.
  final String ingredientsHash;

  /// Compute time (UTC ISO-8601).
  final String? computedAt;
}

/// One tag with its recipe count and chip style.
class TagInfoRow {
  /// Creates a tag row as returned by [SaltDatabase.listTags].
  const TagInfoRow({
    required this.name,
    required this.count,
    this.icon,
    this.color,
    this.bgColor,
  });

  /// Lowercase tag name.
  final String name;

  /// Number of recipes carrying the tag.
  final int count;

  /// Lucide icon name, when styled.
  final String? icon;

  /// Foreground `#RRGGBB`, when styled.
  final String? color;

  /// Background `#RRGGBB`, when styled.
  final String? bgColor;
}
