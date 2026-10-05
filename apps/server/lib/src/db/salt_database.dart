import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:salt_server/src/db/migrations.dart';
import 'package:salt_server/src/search/fts_compiler.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';

final Logger _log = Logger('db');

// The hold families — `mediumHolds`, `lineHolds`, `noRecordHolds` — and
// `foodGoneHold` / `foodUnavailableHold` live in salt_shared, read from the
// ONE action table every consumer reads (`holdActions`, RULE A v28; each
// entry's `kind`, v29 — Run 059 S8: no list is copied by hand).

/// [holds] as an SQL list of string literals.
String _sqlList(Iterable<String> holds) => holds.map((h) => "'$h'").join(', ');

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
  ///
  /// The cache is never evicted, so every SQL text this class can emit must
  /// come from a fixed, finite set — no request input may reach the SQL
  /// string itself. [preparedSqlTexts] is the seam that pins it.
  PreparedStatement _prepared(String sql) =>
      _statements[sql] ??= _db.prepare(sql);

  /// The distinct SQL texts this connection has cached prepared statements
  /// for. Bounded by the code, not by traffic — see [_prepared].
  @visibleForTesting
  Iterable<String> get preparedSqlTexts => _statements.keys;

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

  /// `settings` key written when the 008 FTS reindex has covered EVERY row.
  ///
  /// The reindex is keyed on this marker, not on the start version. It used
  /// to run only when `startVersion < 8`, AFTER the loop had already committed
  /// `user_version = 8` — so if one stored doc failed to decode, the reindex
  /// rolled back and `open` threw exactly once; the next boot saw version 8
  /// and never tried again. One crash, then a deployment permanently serving
  /// the pre-008 narrow rows: subsection and technique text invisible to
  /// search, with no signal (review S-D1, the B1 symptom reachable through
  /// the upgrade path). A marker set only on full success makes the pass
  /// idempotent and retried at every boot until it is, and it heals a
  /// database that is already stuck at version 8 with narrow rows — which a
  /// fix inside the 008 transaction could not, since there is nothing left
  /// to roll back.
  static const String ftsWidenedSetting = 'fts.widened_v8';

  void _migrate() {
    final startVersion =
        _db.select('PRAGMA user_version').first.columnAt(0) as int;
    // A NEWER release wrote this file. Opening it anyway is how a rollback
    // silently corrupts derived state: a pre-008 build ran fine against a v8
    // database (008's SQL is a no-op), wrote narrow FTS rows under a SET
    // widened marker, and the re-upgrade then trusted the marker and never
    // re-derived them. Nothing a build can do with a schema it does not know
    // is safe; refuse, and say which build is needed.
    if (startVersion > migrations.length) {
      throw StateError(
        'This database is at schema version $startVersion, but this build '
        'only knows ${migrations.length}. It was written by a newer release; '
        'run that release (or newer), not this one.',
      );
    }
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
    if (migrations.length >= _ftsWideningVersion &&
        getSetting(ftsWidenedSetting) == null) {
      try {
        _reindexAllFts();
      } on SqliteException catch (error) {
        // Marker absent means this open takes the write lock (BEGIN
        // IMMEDIATE), which an at-head open never used to. Another
        // connection holding a write transaction past busy_timeout — an
        // operator's sqlite3 shell mid-transaction — would otherwise turn a
        // transient lock into a boot failure. The marker is still absent,
        // so the pass simply runs at the next open; nothing is lost.
        if (error.resultCode != _sqliteBusy) rethrow;
        _log.warning(
          'FTS reindex deferred: the database is locked by another '
          'connection ($error). It will run at the next open.',
        );
      }
    }
  }

  /// SQLITE_BUSY — the primary result code for "another connection holds the
  /// lock past busy_timeout".
  static const int _sqliteBusy = 5;

  /// Re-derives every FTS row from the stored doc JSON, then writes
  /// [ftsWidenedSetting] — but only if EVERY row was re-derived.
  ///
  /// A row whose doc will not decode is skipped, named in the log at WARNING,
  /// and leaves the marker unset, so the pass runs again at the next boot
  /// (~110 ms for 1,198 recipes) and names it again, until the row is fixed.
  /// The rows that did decode are committed, so search works for everything
  /// else in the meantime. Boot succeeds: for a household server a warning
  /// the operator sees at every start beats a process that will not start
  /// over one recipe. A database error inside the write is NOT caught — that
  /// is not a bad row, and it should fail loudly.
  ///
  /// On a fresh database there are no rows; the marker is written at once.
  void _reindexAllFts() {
    var failed = 0;
    _inTransaction(() {
      for (final row in _db.select('SELECT rowid, id, doc FROM recipes')) {
        final Recipe recipe;
        try {
          recipe = RecipeMapper.fromMap(
            jsonDecode(row['doc'] as String) as Map<String, dynamic>,
          );
          // A stored doc that will not decode is a data problem, not a code
          // path — whatever the parser throws, the answer is the same: name
          // the row and keep going.
          // ignore: avoid_catches_without_on_clauses
        } catch (error) {
          failed += 1;
          _log.warning(
            'FTS reindex skipped ${row['id']}: its stored document does not '
            'decode ($error). Search will not see its subsections. Delete it '
            'from the app, re-import its source, or fix its exported YAML '
            'and rescan; the reindex retries at every boot.',
          );
          continue;
        }
        _rebuildFts(recipe, row['rowid'] as int);
      }
      if (failed == 0) {
        setSetting(ftsWidenedSetting, DateTime.now().toUtc().toIso8601String());
      }
    });
    if (failed > 0) {
      _log.warning(
        'FTS reindex incomplete: $failed recipe(s) skipped; not marking done, '
        'will retry at next boot.',
      );
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

  /// [mediumHolds] as an SQL list (read from the action table, v29).
  @visibleForTesting
  static final String mediumHoldsSql = _sqlList(mediumHolds);

  /// [lineHolds] as an SQL list (read from the action table, v29).
  static final String lineHoldsSql = _sqlList(lineHolds);

  /// The holds no confirm and no typed grams finish
  /// ([holdsAConfirmCannotFinish] of salt_shared's ONE action table,
  /// `holdActions`; a const for the cached queries, pinned equal to the
  /// table): the queue's bucket,
  /// `finishes` and `finishable` read them (Run 058 O8, Sonnet critics 1
  /// and 3: a `food_gone` row with typed grams was promised a finish).
  @visibleForTesting
  static final String noRecordHoldsSql = _sqlList(noRecordHolds);

  /// [holdsAConfirmCannotFinish] as an SQL list — the holds the queue's
  /// `finishes` and `short` never promise to a confirm (v41: the food with
  /// no record and, beside it, a reference line no recipe counts).
  @visibleForTesting
  static final String noConfirmHoldsSql = _sqlList(holdsAConfirmCannotFinish);

  /// [flaggedBuckets] as an SQL list — the ONE list every queue query's
  /// "needs attention" set reads (v41: six literal copies before; a missed
  /// copy would leave a `choose_recipe` line out of `open_lines`).
  static final String flaggedBucketsSql = _sqlList(flaggedBuckets);

  /// [recipeChoiceHolds] as an SQL list (v41): the `choose_recipe` bucket.
  static final String recipeChoiceHoldsSql = _sqlList(recipeChoiceHolds);

  /// The four conditions a collapsed calories range can emit.
  ///
  /// Any number of ANDed `calories:` terms reduces to at most one lower and
  /// one upper bound (see [_caloriesRange]), so the calories fragment is one
  /// of nine combinations of these CONSTANTS whatever the caller types —
  /// versus one interpolated condition per parsed term, which let a caller
  /// mint a new SQL text (and so a new permanently cached prepared
  /// statement) per operator sequence, up to 5^24 of them. Each is a plain
  /// comparison against the indexed column, so SQLite still range-scans
  /// `idx_recipe_nutrition_calories` (migration 005) — a `(? IS NULL OR ...)`
  /// slot per operator would be constant too, but is not sargable.
  static const String _caloriesGt = 'n.calories_per_serving > ?';
  static const String _caloriesGte = 'n.calories_per_serving >= ?';
  static const String _caloriesLt = 'n.calories_per_serving < ?';
  static const String _caloriesLte = 'n.calories_per_serving <= ?';

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
    // otherwise relevance. Every value is a bound parameter and nothing
    // attacker-varied is interpolated, so the set of SQL texts this method
    // can emit is fixed and tiny (see _caloriesGt and friends).
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
      final range = _caloriesRange(compiled.calories);
      conditions.add('n.calories_per_serving IS NOT NULL');
      // A bound is absent only when the query asked for no bound on that
      // side; its value is a non-nullable num, so no code path can bind a
      // null here and turn the filter off. Contradictory terms
      // (`calories:=300 calories:=400`) survive as an unsatisfiable range and
      // SQLite answers zero rows — the filter is never silently dropped.
      final lower = range.lower;
      if (lower != null) {
        conditions.add(lower.inclusive ? _caloriesGte : _caloriesGt);
        params.add(lower.value);
      }
      final upper = range.upper;
      if (upper != null) {
        conditions.add(upper.inclusive ? _caloriesLte : _caloriesLt);
        params.add(upper.value);
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

  /// The id and source of the recipe [key] names (by id or slug) WITHOUT
  /// decoding its document.
  ///
  /// [recipeByIdOrSlug] decodes, so every per-recipe route — including
  /// delete — threw on a row whose stored document no longer parses, and the
  /// reindex warning that told the operator to remove that recipe pointed at
  /// a door that would not open. Deleting needs only the id and the source.
  ({String id, String sourceSlug})? recipeIdentityByIdOrSlug(String key) {
    final rows = _prepared(
      'SELECT id, source_slug FROM recipes WHERE id = ? OR slug = ? LIMIT 1',
    ).select([key, key]);
    if (rows.isEmpty) {
      return null;
    }
    return (
      id: rows.first['id'] as String,
      sourceSlug: rows.first['source_slug'] as String,
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
  String? fdcSearchCacheGet(String query) =>
      fdcSearchCacheEntry(query)?.response;

  /// The cached FDC search answer for [query] with WHEN it was fetched
  /// (UTC ISO-8601), or null when FDC has never been asked. Nothing expires
  /// this cache; the age is what a person sees to decide on a fresh search.
  ({String response, String fetchedAt})? fdcSearchCacheEntry(String query) {
    final rows = _prepared(
      'SELECT response, fetched_at FROM fdc_search_cache WHERE query = ?',
    ).select([query]);
    if (rows.isEmpty) {
      return null;
    }
    // Stored by SQLite's datetime('now'): "YYYY-MM-DD HH:MM:SS", UTC.
    final stored = rows.first['fetched_at'] as String;
    return (
      response: rows.first['response'] as String,
      fetchedAt: '${stored.replaceFirst(' ', 'T')}Z',
    );
  }

  /// Every cached search response that lists [fdcId] as a hit, in the
  /// cache's own order — an INDEXED lookup (migration 016's
  /// `fdc_search_cache_foods`, kept by triggers on every write of the
  /// cache), never a scan of every answer (Run 058 O5/S10).
  List<String> fdcSearchCacheHolding(int fdcId) => [
    for (final row in _prepared(
      'SELECT c.response FROM fdc_search_cache_foods f '
      'JOIN fdc_search_cache c ON c.query = f.query '
      'WHERE f.fdc_id = ? ORDER BY c.rowid',
    ).select([fdcId]))
      row['response'] as String,
  ];

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

  /// The ingredient's own decision: the food a person last picked or
  /// confirmed for [itemKey] in any recipe, or null when nobody has.
  IngredientDecisionRow? decisionFor(String itemKey) {
    final rows = _prepared(
      'SELECT item_key, item, fdc_id, description, data_type, decided_by, '
      'decided_at FROM ingredient_decisions WHERE item_key = ?',
    ).select([itemKey]);
    return rows.isEmpty ? null : IngredientDecisionRow.fromRow(rows.first);
  }

  /// Records a person's food decision for an ingredient — the newest write
  /// wins, whoever made it. [item] is the parsed text the key came from.
  void putDecision({
    required String itemKey,
    required String item,
    required int? fdcId,
    required String? description,
    required String? dataType,
    required int? decidedBy,
  }) {
    _prepared(
      'INSERT INTO ingredient_decisions (item_key, item, fdc_id, description, '
      'data_type, decided_by, decided_at) VALUES (?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(item_key) DO UPDATE SET item = excluded.item, '
      'fdc_id = excluded.fdc_id, description = excluded.description, '
      'data_type = excluded.data_type, decided_by = excluded.decided_by, '
      'decided_at = excluded.decided_at',
    ).execute([
      itemKey,
      item,
      fdcId,
      description,
      dataType,
      decidedBy,
      _utcNowIso(),
    ]);
  }

  /// Forgets an ingredient's decision (its lines keep their rows).
  void deleteDecision(String itemKey) {
    _prepared(
      'DELETE FROM ingredient_decisions WHERE item_key = ?',
    ).execute([itemKey]);
  }

  /// Every decision, oldest first.
  List<IngredientDecisionRow> allDecisions() {
    final rows = _prepared(
      'SELECT item_key, item, fdc_id, description, data_type, decided_by, '
      'decided_at FROM ingredient_decisions ORDER BY decided_at, item_key',
    ).select();
    return [for (final row in rows) IngredientDecisionRow.fromRow(row)];
  }

  /// Every match row keyed [itemKey], a person's rows on [fdcId] first (the
  /// line a decision was made on), then by recipe and position — the
  /// example lines the decision re-key reads a key change from.
  List<IngredientMatchRow> matchesForItemKey(String itemKey, {int? fdcId}) {
    final rows = _prepared(
      'SELECT recipe_id, position, raw, fdc_id, description, data_type, '
      'confidence, grams, gram_source, status, updated_at, item_key, hold, '
      'derived_seq, $_compositeColumns '
      'FROM ingredient_matches WHERE item_key = ? '
      "ORDER BY (status IN ('confirmed', 'overridden') AND fdc_id IS ?) DESC, "
      'recipe_id, position',
    ).select([itemKey, fdcId]);
    return [for (final row in rows) IngredientMatchRow.fromRow(row)];
  }

  /// Inserts a decision row as it is, stamps included (the re-key pass
  /// moving a row to its re-derived key). The caller has freed `row.itemKey`.
  void insertDecision(IngredientDecisionRow row) {
    _prepared(
      'INSERT INTO ingredient_decisions (item_key, item, fdc_id, description, '
      'data_type, decided_by, decided_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    ).execute([
      row.itemKey,
      row.item,
      row.fdcId,
      row.description,
      row.dataType,
      row.decidedBy,
      row.decidedAt,
    ]);
  }

  /// Recipe ids that have any match row (the key re-derivation's scan).
  List<String> recipesWithMatches() {
    final rows = _prepared(
      'SELECT DISTINCT recipe_id FROM ingredient_matches',
    ).select();
    return [for (final row in rows) row['recipe_id'] as String];
  }

  /// Every UNDECIDED row (`auto` / `unmatched`) carrying [itemKey], on any
  /// line but [excluding] — the rows an apply-to-all would land on, before
  /// the engine leaves out the lines naming a second food (`decisionReach`,
  /// which `others` / `others_lines` count).
  ///
  /// A row on a DIFFERENT food is a target whatever its score — the decision
  /// changes its food. A row already on [fdcId] is a target only BELOW
  /// [belowConfidence] (the flagged threshold) or while held by a FOOD hold
  /// (`no_nutrients`, `dried_for_fresh`, `cured_for_fresh`, `borderline`,
  /// `unnamed_food` — a food decision answers them): either sits in
  /// `check`, and a confirm is what lifts it out, rewritten as `auto` at
  /// confidence 1 with grams from its own amounts and the hold cleared. A
  /// row with a LINE hold (`second_food`, `discarded_medium`) is never
  /// reached, whatever its food or score: no decision on the key clears it
  /// (checkpoint 5); an `in_shell` row is left out by its text
  /// (`decisionReach`), matched or not. An unheld row at or above
  /// the threshold is already counted (or missing only an amount) — it
  /// waits on nothing here, and rewriting it would change nothing but the
  /// receipt. Nor does an engine 0 g on this food (an amount-less line, a
  /// sprig): counted whatever its score or food hold, a confirm leaves it
  /// counted (checkpoint 5 review: "Chili oil" was offered and never
  /// applied). With no [fdcId] (the line has no food yet) every other
  /// undecided row not line-held is one. A composite reference row
  /// (`gram_source` [recipeGramSource], v41) is never one: the line takes
  /// no food (design_v3 S18).
  List<IngredientMatchRow> undecidedMatchesForItemKey(
    String itemKey, {
    required ({String recipeId, int position}) excluding,
    required double belowConfidence,
    int? fdcId,
  }) {
    final rows =
        _prepared(
          'SELECT recipe_id, position, raw, fdc_id, description, data_type, '
          'confidence, grams, gram_source, status, updated_at, item_key, hold, '
          'derived_seq, $_compositeColumns '
          'FROM ingredient_matches WHERE item_key = ? '
          'AND NOT (recipe_id = ? AND position = ?) '
          "AND status IN ('auto', 'unmatched') "
          "AND COALESCE(hold, '') NOT IN ('second_food', $mediumHoldsSql) "
          "AND COALESCE(gram_source, '') != '$recipeGramSource' "
          'AND (? IS NULL OR COALESCE(fdc_id, -1) != ? OR ((confidence < ? '
          "OR hold IS NOT NULL) AND NOT (COALESCE(gram_source, '') IN "
          "('discarded', 'unmeasured') AND COALESCE(grams, -1) = 0 "
          "AND COALESCE(hold, '') != 'unnamed_food'))) "
          'ORDER BY recipe_id, position',
        ).select([
          itemKey,
          excluding.recipeId,
          excluding.position,
          fdcId,
          fdcId,
          belowConfidence,
        ]);
    return [for (final row in rows) IngredientMatchRow.fromRow(row)];
  }

  /// Every UNDECIDED routed reference row carrying [itemKey] (v41, design_v3
  /// §2.3 b) on any line but [excluding]: `auto`, `gram_source` recipe, a
  /// child, no hold — the rows a RECIPE decision's apply-to-all may land on,
  /// before the engine keeps those on another child or on the same child by
  /// a flagged default (`recipeReach`). The complement of the food reach
  /// ([undecidedMatchesForItemKey], S18); a held reference line is a LINE
  /// hold and never one.
  List<IngredientMatchRow> undecidedRoutedMatchesForItemKey(
    String itemKey, {
    required ({String recipeId, int position}) excluding,
  }) {
    final rows = _prepared(
      'SELECT recipe_id, position, raw, fdc_id, description, data_type, '
      'confidence, grams, gram_source, status, updated_at, item_key, hold, '
      'derived_seq, $_compositeColumns '
      'FROM ingredient_matches WHERE item_key = ? '
      'AND NOT (recipe_id = ? AND position = ?) '
      "AND status = 'auto' AND gram_source = '$recipeGramSource' "
      'AND child_recipe_id IS NOT NULL AND hold IS NULL '
      'ORDER BY recipe_id, position',
    ).select([itemKey, excluding.recipeId, excluding.position]);
    return [for (final row in rows) IngredientMatchRow.fromRow(row)];
  }

  /// Recipe ids that still have a match row with no item key (pre-009 rows
  /// the boot-time backfill has yet to key).
  List<String> recipesWithUnkeyedMatches() {
    final rows = _prepared(
      'SELECT DISTINCT recipe_id FROM ingredient_matches '
      'WHERE item_key IS NULL',
    ).select();
    return [for (final row in rows) row['recipe_id'] as String];
  }

  /// Sets the item key of one match row (the backfill's only write).
  void setMatchItemKey(String recipeId, int position, String itemKey) {
    _prepared(
      'UPDATE ingredient_matches SET item_key = ? '
      'WHERE recipe_id = ? AND position = ?',
    ).execute([itemKey, recipeId, position]);
  }

  /// All ingredient matches for a recipe, in position order.
  List<IngredientMatchRow> ingredientMatchesFor(String recipeId) {
    final rows = _prepared(
      'SELECT recipe_id, position, raw, fdc_id, description, data_type, '
      'confidence, grams, gram_source, status, updated_at, item_key, hold, '
      'derived_seq, $_compositeColumns '
      'FROM ingredient_matches WHERE recipe_id = ? ORDER BY position',
    ).select([recipeId]);
    return [for (final row in rows) IngredientMatchRow.fromRow(row)];
  }

  /// The triage bucket for a match row, in SQL — a verbatim mirror of the
  /// ONE shared rule in salt_shared's `matchBucketFor` (which the app's
  /// review sheet uses), parity-pinned by a test. The two copies once
  /// disagreed (review B7): an `overridden` row with NULL grams was
  /// "resolved" here yet "needs attention" on the sheet, so a line could
  /// vanish from this queue while contributing nothing. Decided corners:
  /// overridden+NULL grams stays `no_grams` (an unfinished fix), and so does
  /// a confirmed FOOD with NULL grams (the totals skip it, checkpoint 6);
  /// `confirmed` is otherwise resolved, even matchless (confirmed water is a
  /// deliberate no-match); the gate is `confidenceGateFloor` (0.5 less a
  /// 1e-9 drift tolerance); an engine 0 g (`discarded` / `unmeasured`) is `counted`
  /// whatever its score or hold but `unnamed_food`; a low-confidence auto
  /// match is `check` whether or not it has grams — a wrong food is the
  /// larger problem, and "no amount" read as calm.
  static final String _reviewBucketCase =
      '''
    CASE
      WHEN im.status = 'skipped' THEN 'skipped'
      WHEN im.hold IN ($noRecordHoldsSql) THEN 'check'
      WHEN im.hold IN ($recipeChoiceHoldsSql) THEN 'choose_recipe'
      WHEN im.status = 'overridden' AND im.grams IS NULL THEN 'no_grams'
      WHEN im.status = 'confirmed' AND im.fdc_id IS NOT NULL
        AND im.grams IS NULL THEN 'no_grams'
      WHEN im.status IN ('confirmed', 'overridden') THEN 'counted'
      WHEN im.fdc_id IS NULL AND im.gram_source IS NOT '$recipeGramSource'
        THEN 'no_match'
      WHEN im.gram_source IN ('discarded', 'unmeasured') AND im.grams = 0
        AND COALESCE(im.hold, '') != 'unnamed_food' THEN 'counted'
      WHEN im.confidence < 0.499999999 OR im.hold IS NOT NULL THEN 'check'
      WHEN im.grams IS NULL THEN 'no_grams'
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

  /// One page of flagged match lines across ALL recipes, each carrying its
  /// recipe's slug + title. [bucket] narrows to a single triage bucket;
  /// null returns every flagged bucket ([flaggedBuckets]), never
  /// `skipped` or `counted`.
  ///
  /// [sort] `worst` (the default here) is worst-confidence first;
  /// `finishes` first puts the lines that finish their recipe (`finishes`
  /// 1: its last open line, with grams or in No grams — see the query),
  /// then worst first — the grouped queue's order
  /// ([nutritionReviewGroups]) at line grain.
  ///
  /// Ties break on the ingredient key before the recipe title, so one
  /// ingredient's lines sit together: this list is the member view of the
  /// grouped queue ([nutritionReviewGroups]), and working an ingredient's
  /// lines one after another is a straight run down the page.
  List<NutritionReviewLineRow> nutritionReviewLines({
    required int limit,
    required int offset,
    String? bucket,
    String sort = 'worst',
  }) {
    // The bucket filter (twice — null takes the flagged-set branch, a
    // value takes the equality one) and the sort are BOUND, never
    // concatenated. It used to be a
    // local named `where`, which is also the name of one of searchCards'
    // shape-pinned locals, so the class-wide "every cached SQL text is
    // constant" guard whitelisted it while nothing counted what this method
    // could emit — request input was one edit from the never-evicted
    // statement cache (review S6). A single constant text cannot go wrong
    // that way.
    // `open_lines` is windowed over EVERY row of the recipe before the
    // filter: a line is its recipe's last open line whatever the chip.
    // `finishes` is the promise a confirm can keep (checkpoint-8 review,
    // Run 046): the last open line AND grams to count — a Check line with
    // grams, or a No grams line (the amount-first confirm supplies them).
    // A No match line (no food) or a Check line with no grams (a plain
    // Confirm leaves it without grams when USDA cannot convert) is 0 — and
    // so is a line held for a food with no record ([noRecordHoldsSql], the
    // action table: only a pick or a skip finishes it, v28).
    final rows = _prepared(
      "SELECT *, (open_lines = 1 AND COALESCE(hold, '') NOT IN "
      "($noConfirmHoldsSql) AND (bucket = 'no_grams' "
      "OR (bucket = 'check' AND grams IS NOT NULL))) AS finishes "
      'FROM (SELECT *, '
      'SUM(bucket IN ($flaggedBucketsSql)) '
      'OVER (PARTITION BY recipe_id) AS open_lines FROM ( '
      'SELECT im.recipe_id, im.position, im.raw, im.fdc_id, im.description, '
      'im.data_type, im.confidence, im.grams, im.gram_source, im.status, '
      'im.updated_at, im.item_key, im.hold, im.child_recipe_id, '
      'im.child_share, im.child_stamp, im.parts, r.slug AS review_slug, '
      'r.title AS review_title, '
      '$_reviewBucketCase AS bucket '
      'FROM ingredient_matches im JOIN recipes r ON r.id = im.recipe_id '
      ')) WHERE (? IS NULL AND bucket IN ($flaggedBucketsSql)) '
      'OR bucket = ? '
      "ORDER BY CASE WHEN ? = 'finishes' THEN finishes ELSE 0 END DESC, "
      'confidence ASC, item_key, review_title, position '
      'LIMIT ? OFFSET ?',
    ).select([bucket, bucket, sort, limit, offset]);
    return [
      for (final row in rows)
        (
          match: IngredientMatchRow.fromRow(row),
          slug: row['review_slug'] as String,
          title: row['review_title'] as String,
          bucket: row['bucket'] as String,
          finishes: row['finishes'] as int,
        ),
    ];
  }

  /// The flagged-line derived table both grouped queries below start from:
  /// every match row with its recipe context, its triage bucket and its
  /// GROUPING KEY. A row whose `item_key` is null or empty is keyed by its own
  /// identity, so unkeyed rows stay groups of one instead of collapsing into
  /// a single bucket-sized "group" of everything the backfill has not keyed.
  ///
  /// So is a row a person already DECIDED (`overridden` / `confirmed` /
  /// `skipped`): an apply-to-all reaches only undecided rows, so a decided
  /// one can never be part of an ingredient's reach — an `overridden` row
  /// with no grams is an amount problem on that one line. Keying it by its
  /// own identity keeps the group's "N lines · M recipes" equal to what the
  /// apply would land on, and draws that row as today's single line.
  ///
  /// So, too, is a row a LINE hold holds (`second_food`,
  /// `discarded_medium`, `in_shell`): no decision on the key reaches it
  /// (checkpoint 5 review: "sugar · 17 lines · 17 recipes" were 17 brine
  /// sugars one decision could never clear — 17 groups of one).
  ///
  /// Everything built on it reads the STORED match rows (Run 046): for a
  /// recipe edited since its last compute (`stale`, derived, never stored) a
  /// reworded or added line has no row of its own, so `finishes` (both
  /// grains) and `finishable` are an upper bound for it — the apply skips a
  /// reworded line and the recompute cannot account an added one. No SQL
  /// filter here: staleness needs the recipe hashed, and it is never stored.
  static final String _reviewFlaggedCte =
      'WITH flagged AS (SELECT im.*, r.slug AS review_slug, '
      'r.title AS review_title, $_reviewBucketCase AS bucket, '
      "CASE WHEN im.item_key IS NULL OR im.item_key = '' "
      "OR im.status NOT IN ('auto', 'unmatched') "
      "OR COALESCE(im.hold, '') IN ($lineHoldsSql) "
      "THEN im.recipe_id || '#' || im.position ELSE im.item_key END AS gkey "
      'FROM ingredient_matches im JOIN recipes r ON r.id = im.recipe_id)';

  /// The chain [nutritionReviewGroups] and [nutritionReviewFinishable]
  /// share (binds: the bucket filter, twice): the filtered `members`, each
  /// group's `example` (lowest confidence, then one with grams, then title,
  /// then position), and `solo` — every recipe whose flagged lines (in any
  /// bucket, whatever the filter) all sit in ONE group, so that group holds
  /// its last open lines, with `short` counting those of them that have no
  /// grams and are not a No grams example. A recipe with none short is one
  /// the group's decision finishes: the amount-first confirm supplies a No
  /// grams example's grams. A Check or No match example with no grams is
  /// short: a plain Confirm promises no grams — and so is a line held for a
  /// food with no record ([noRecordHoldsSql]: no confirm and no typed grams
  /// count it, v28). The count may under-promise
  /// a Check example whose cached record does convert — the accepted
  /// direction: never promise what a confirm may not count.
  static final String _reviewFinishCte =
      '$_reviewFlaggedCte, '
      'members AS (SELECT * FROM flagged WHERE '
      '(? IS NULL AND bucket IN ($flaggedBucketsSql)) '
      'OR bucket = ?), '
      'example AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY gkey '
      'ORDER BY confidence, (grams IS NULL), review_title, position) AS rn '
      'FROM members), '
      'solo AS (SELECT o.recipe_id, MIN(o.gkey) AS gkey, '
      "SUM((o.grams IS NULL AND (x.rn IS NULL OR o.bucket <> 'no_grams')) "
      "OR COALESCE(o.hold, '') IN ($noConfirmHoldsSql)) "
      'AS short FROM flagged o '
      'LEFT JOIN example x ON x.rn = 1 AND x.recipe_id = o.recipe_id '
      'AND x.position = o.position '
      'WHERE o.bucket IN ($flaggedBucketsSql) '
      'GROUP BY o.recipe_id HAVING COUNT(DISTINCT o.gkey) = 1)';

  /// Whole-library payoff of the grouped queue (its banner): how many
  /// recipes are ONE group decision from complete (each group's `finishes`,
  /// summed — a recipe sits in at most one group's count), and how many
  /// recipes wait on at least one open line.
  ({int finishable, int open}) nutritionReviewFinishable() {
    final row = _prepared(
      '$_reviewFinishCte '
      'SELECT (SELECT COUNT(*) FROM solo WHERE short = 0) AS finishable, '
      '(SELECT COUNT(DISTINCT recipe_id) FROM flagged '
      'WHERE bucket IN ($flaggedBucketsSql)) AS open',
    ).select([null, null]).first;
    return (
      finishable: row['finishable'] as int,
      open: row['open'] as int,
    );
  }

  /// A group's finished recipes as `{id, title}`, by title (SQLite's
  /// `json_group_array` promises no order).
  static List<({String id, String title})> _finishesRecipes(String? json) {
    final list =
        [
          for (final entry in (jsonDecode(json ?? '[]') as List<dynamic>))
            (
              id: (entry as Map<String, dynamic>)['id'] as String,
              title: entry['title'] as String,
            ),
        ]..sort((a, b) {
          final byTitle = a.title.compareTo(b.title);
          return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
        });
    return list;
  }

  /// The triage buckets by severity, worst first — the rank
  /// [nutritionReviewGroups] aggregates over (a group is as bad as its worst
  /// member) and the order this index decodes.
  static const List<String> _reviewBucketRanks = [
    'no_match',
    'choose_recipe',
    'check',
    'no_grams',
    'skipped',
  ];

  /// One page of flagged match lines GROUPED by ingredient key: one row per
  /// group, carrying its example line (the lowest-confidence member, then one
  /// that has grams, then recipe title, then position — deterministic, so a
  /// reload never shuffles the work) plus the group's reach and amount spread.
  ///
  /// Members are the lines that pass the same filter as [nutritionReviewLines]
  /// — [bucket] null means the flagged buckets — so every count here is
  /// counted inside the current filter.
  ///
  /// Each group carries `finishes`: the recipes one decision applied to the
  /// group completes — a recipe whose every flagged line (whatever the
  /// filter) sits in this group, each one with grams already or being the
  /// group's No grams example (the amount-first confirm supplies its grams;
  /// a Check or No match example with no grams finishes nothing).
  /// A pick of a different food can finish more (it recomputes the reached
  /// lines' grams): the count may undercount, never over-promise a confirm.
  /// `finishesRecipes` names those recipes, and `lastOpen` counts every
  /// recipe whose open lines all sit in the group, grams or not (a No grams
  /// group's "last open line in N recipes": each needs its own amount).
  ///
  /// [sort] `finishes` (the default) orders by that count, then lines, then
  /// worst confidence; `worst` orders worst-confidence first, then by reach.
  /// Both end on the key: a stable page boundary, and a group is never split
  /// across pages.
  List<NutritionReviewGroupRow> nutritionReviewGroups({
    required int limit,
    required int offset,
    String? bucket,
    String sort = 'finishes',
  }) {
    // Bound, never concatenated — the same rule (and the same reason) as
    // nutritionReviewLines: one constant text for every bucket and sort
    // state. A line-held example is decided by nothing on its key: never
    // badged.
    final rows = _prepared(
      '$_reviewFinishCte, '
      'agg AS (SELECT gkey, COUNT(*) AS lines, '
      'COUNT(DISTINCT recipe_id) AS recipes, MIN(confidence) AS worst, '
      'MIN(grams) AS gmin, MAX(grams) AS gmax, '
      'COUNT(*) FILTER (WHERE grams IS NULL) AS gmissing, '
      "MIN(CASE bucket WHEN 'no_match' THEN 0 WHEN 'choose_recipe' THEN 1 "
      "WHEN 'check' THEN 2 WHEN 'no_grams' THEN 3 ELSE 4 END) AS worst_bucket "
      'FROM members GROUP BY gkey), '
      'fin AS (SELECT s.gkey, COUNT(*) AS last_open, '
      'COUNT(*) FILTER (WHERE s.short = 0) AS n, '
      "json_group_array(json_object('id', r.id, 'title', r.title)) "
      'FILTER (WHERE s.short = 0) AS names '
      'FROM solo s JOIN recipes r ON r.id = s.recipe_id GROUP BY s.gkey) '
      'SELECT e.*, a.lines AS group_lines, a.recipes AS group_recipes, '
      'a.gmin, a.gmax, a.gmissing, a.worst_bucket, '
      'COALESCE(f.n, 0) AS finishes, COALESCE(f.last_open, 0) AS last_open, '
      'f.names AS finishes_names, '
      "(d.item_key IS NOT NULL AND COALESCE(e.hold, '') NOT IN "
      '($lineHoldsSql)) AS decided '
      'FROM agg a JOIN example e ON e.gkey = a.gkey AND e.rn = 1 '
      'LEFT JOIN fin f ON f.gkey = a.gkey '
      'LEFT JOIN ingredient_decisions d ON d.item_key = e.item_key '
      "ORDER BY CASE WHEN ? = 'worst' THEN 0 ELSE COALESCE(f.n, 0) END DESC, "
      "CASE WHEN ? = 'worst' THEN a.worst ELSE 0 END, "
      'a.lines DESC, a.worst, a.recipes DESC, a.gkey '
      'LIMIT ? OFFSET ?',
    ).select([bucket, bucket, sort, sort, limit, offset]);
    return [
      for (final row in rows)
        (
          match: IngredientMatchRow.fromRow(row),
          slug: row['review_slug'] as String,
          title: row['review_title'] as String,
          bucket: _reviewBucketRanks[row['worst_bucket'] as int],
          // The SYNTHETIC key of an unkeyed row is an implementation detail
          // and never leaves the database: such a group reports no key.
          itemKey: (row['item_key'] as String?) ?? '',
          lines: row['group_lines'] as int,
          recipes: row['group_recipes'] as int,
          decided: (row['decided'] as int) != 0,
          gramsMin: (row['gmin'] as num?)?.toDouble(),
          gramsMax: (row['gmax'] as num?)?.toDouble(),
          gramsMissing: row['gmissing'] as int,
          finishes: row['finishes'] as int,
          lastOpen: row['last_open'] as int,
          finishesRecipes: _finishesRecipes(row['finishes_names'] as String?),
        ),
    ];
  }

  /// How many distinct ingredient GROUPS the flagged lines make: one count per
  /// triage bucket, plus `flagged` over the flagged buckets together (a
  /// key whose lines span two buckets counts once there). The line counts stay
  /// [nutritionReviewCounts]' job — the chips never change unit.
  ({int flagged, Map<String, int> byBucket}) nutritionReviewGroupCounts() {
    final rows = _prepared(
      '$_reviewFlaggedCte '
      'SELECT bucket, COUNT(DISTINCT gkey) AS n FROM flagged GROUP BY bucket '
      'UNION ALL '
      "SELECT '', COUNT(DISTINCT gkey) FROM flagged "
      'WHERE bucket IN ($flaggedBucketsSql)',
    ).select();
    final byBucket = <String, int>{};
    var flagged = 0;
    for (final row in rows) {
      final bucket = row['bucket'] as String;
      if (bucket.isEmpty) {
        flagged = row['n'] as int;
      } else {
        byBucket[bucket] = row['n'] as int;
      }
    }
    return (flagged: flagged, byBucket: byBucket);
  }

  /// Creates or replaces one match row. With [layoutSeq], only while the
  /// recipe's layout is still that one ([layoutOf]), checked in the write's
  /// own transaction; returns whether the row was written.
  bool upsertIngredientMatch(IngredientMatchRow row, {int? layoutSeq}) =>
      _atLayout(row.recipeId, layoutSeq, () {
        _upsertMatch(row);
        return true;
      });

  /// Runs [write] — alone, or with [layoutSeq] inside one transaction that
  /// first checks the recipe's layout sequence is still [layoutSeq] (a
  /// relayout since the caller read the rows: nothing is written, false).
  bool _atLayout(String recipeId, int? layoutSeq, bool Function() write) {
    if (layoutSeq == null) {
      return write();
    }
    var written = false;
    _inTransaction(() {
      if (layoutSeqOf(recipeId) == layoutSeq) {
        written = write();
      }
    });
    return written;
  }

  void _upsertMatch(IngredientMatchRow row, {bool keepRetryCount = false}) {
    _prepared(
      'INSERT INTO ingredient_matches (recipe_id, position, raw, fdc_id, '
      'description, data_type, confidence, grams, gram_source, status, '
      'item_key, hold, updated_at, derived_seq, $_compositeColumns) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(recipe_id, position) DO UPDATE SET raw = excluded.raw, '
      'fdc_id = excluded.fdc_id, description = excluded.description, '
      'data_type = excluded.data_type, confidence = excluded.confidence, '
      'grams = excluded.grams, gram_source = excluded.gram_source, '
      'status = excluded.status, item_key = excluded.item_key, '
      'hold = excluded.hold, updated_at = excluded.updated_at, '
      'derived_seq = excluded.derived_seq, $_compositeUpdate, '
      'retry_count = CASE WHEN ? THEN retry_count ELSE 0 END',
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
      row.itemKey,
      row.hold,
      _utcNowIso(),
      row.derivedSeq,
      row.childRecipeId,
      row.childShare,
      row.childStamp,
      row.parts,
      if (keepRetryCount) 1 else 0,
    ]);
  }

  /// [upsertIngredientMatch] for the ENGINE's own writes: lands only where no
  /// human decision stands.
  ///
  /// `matchAndCompute` snapshots the existing rows once at entry, then awaits
  /// the provider per line — for the bulk provider, an uncapped rate-limit
  /// wait. A confirm/override/skip made through the review UI DURING that
  /// window was invisible to the snapshot, and the unconditional write at the
  /// end erased it: job done, zero failures, nothing logged. The guard is in
  /// the statement rather than in Dart because the decision has to be made
  /// against the row as it is at WRITE time, not as it was at entry.
  ///
  /// Overwrites when the existing row is undecided (`auto`, or `unmatched` —
  /// the engine's own "FDC had nothing", not a person's call). A decided row
  /// is left exactly as it is, whatever its text (Run 052 S1/Opus critic 3:
  /// a clause replacing any row of another text let an apply-to-all write
  /// over a person's skip the layout had carried onto the reached position;
  /// the one engine write over a decided row — an amount edit's re-derived
  /// row — is [replaceIngredientMatchIfUnchanged]) — except the engine's OWN
  /// rule rows
  /// ([isEngineRuleRow]: 'confirmed', no food, one of [engineRuleNotes]),
  /// which the engine rewrites when its rule changes (a sub-recipe row that
  /// now counts its food, matcher v14). Returns whether the row was written
  /// — the guard is in the statement, so this is the only way a caller can
  /// know. With [layoutSeq], the write lands only while the recipe's layout
  /// is still that one, as [upsertIngredientMatch] checks it.
  bool upsertIngredientMatchIfUndecided(
    IngredientMatchRow row, {
    int? layoutSeq,
  }) => _atLayout(row.recipeId, layoutSeq, () => _upsertIfUndecided(row));

  bool _upsertIfUndecided(IngredientMatchRow row) {
    _prepared(
      'INSERT INTO ingredient_matches (recipe_id, position, raw, fdc_id, '
      'description, data_type, confidence, grams, gram_source, status, '
      'item_key, hold, updated_at, derived_seq, $_compositeColumns) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(recipe_id, position) DO UPDATE SET raw = excluded.raw, '
      'fdc_id = excluded.fdc_id, description = excluded.description, '
      'data_type = excluded.data_type, confidence = excluded.confidence, '
      'grams = excluded.grams, gram_source = excluded.gram_source, '
      'status = excluded.status, item_key = excluded.item_key, '
      'hold = excluded.hold, updated_at = excluded.updated_at, '
      'derived_seq = excluded.derived_seq, $_compositeUpdate, '
      'retry_count = 0 '
      "WHERE ingredient_matches.status IN ('auto', 'unmatched') "
      "OR (ingredient_matches.status = 'confirmed' "
      'AND ingredient_matches.fdc_id IS NULL '
      'AND ingredient_matches.description IN (?, ?, ?, ?, ?, ?))',
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
      row.itemKey,
      row.hold,
      _utcNowIso(),
      row.derivedSeq,
      row.childRecipeId,
      row.childShare,
      row.childStamp,
      row.parts,
      ...engineRuleNotes,
    ]);
    return _db.updatedRows > 0;
  }

  /// Replaces the row at [row]'s position only while it still reads [over]
  /// ([sameMatchRow]) and the recipe's layout is still [layoutSeq], both
  /// checked in the write's own transaction; returns whether it was
  /// written. The compute's write of an amount-edited decided row
  /// (`derivedFor`) over the row it laid out: a person's write on
  /// that line since (an un-skip: Run 052 O3) is not that row, and stands.
  ///
  /// [keepRetryCount]: the held write of a FOOD failure (v29, Run 059 S2)
  /// keeps the row's `retry_count` — a held row is not re-asked, and an
  /// edit never restarts its count.
  bool replaceIngredientMatchIfUnchanged(
    IngredientMatchRow row, {
    required IngredientMatchRow over,
    required int layoutSeq,
    bool keepRetryCount = false,
  }) => _atLayout(row.recipeId, layoutSeq, () {
    if (!sameMatchRow(_matchAt(row.recipeId, row.position), over)) {
      return false;
    }
    _upsertMatch(row, keepRetryCount: keepRetryCount);
    return true;
  });

  /// The row at [position] of [recipeId] — ONE row read (Run 058 S12: the
  /// guards read the whole recipe per decided row, O(decided x rows)).
  IngredientMatchRow? _matchAt(String recipeId, int position) {
    final rows = _prepared(
      'SELECT recipe_id, position, raw, fdc_id, description, data_type, '
      'confidence, grams, gram_source, status, updated_at, item_key, hold, '
      'derived_seq, $_compositeColumns FROM ingredient_matches '
      'WHERE recipe_id = ? AND position = ?',
    ).select([recipeId, position]);
    return rows.isEmpty ? null : IngredientMatchRow.fromRow(rows.first);
  }

  /// The composite row's four columns (migration 018), in the order every
  /// explicit column list and both upserts bind them.
  static const String _compositeColumns =
      'child_recipe_id, child_share, child_stamp, parts';

  /// The upserts' DO UPDATE of [_compositeColumns].
  static const String _compositeUpdate =
      'child_recipe_id = excluded.child_recipe_id, '
      'child_share = excluded.child_share, '
      'child_stamp = excluded.child_stamp, parts = excluded.parts';

  /// [sameMatchRow] as an SQL guard over the row at `recipe_id = ? AND
  /// position = ?`, its binds [_sameRowBinds] — ONE statement checks and
  /// writes, so nothing can come between.
  static const String _sameRowSql =
      'WHERE recipe_id = ? AND position = ? AND raw IS ? AND status IS ? '
      'AND fdc_id IS ? AND confidence IS ? AND grams IS ? '
      'AND gram_source IS ? AND hold IS ? AND description IS ? '
      'AND child_recipe_id IS ? AND child_share IS ? AND child_stamp IS ? '
      'AND parts IS ?';

  static List<Object?> _sameRowBinds(IngredientMatchRow over) => [
    over.recipeId,
    over.position,
    over.raw,
    over.status,
    over.fdcId,
    over.confidence,
    over.grams,
    over.gramSource,
    over.hold,
    over.description,
    over.childRecipeId,
    over.childShare,
    over.childStamp,
    over.parts,
  ];

  /// Records that the row [over] — unchanged, checked in the write's own
  /// transaction as [replaceIngredientMatchIfUnchanged] checks it — was
  /// derived for [derivedSeq] (RULE A): its derived fields came out as
  /// stored, so only `derived_seq` is written (its `updated_at`, the last
  /// change of what it holds, stays). Returns whether it was written.
  ///
  /// [keepRetryCount]: a held row re-read from the caches and still held
  /// (v29, Run 059 S2) keeps its `retry_count`; a derivation resets it.
  bool markDerivedIfUnchanged(
    IngredientMatchRow over, {
    required String derivedSeq,
    required int layoutSeq,
    bool keepRetryCount = false,
  }) => _atLayout(over.recipeId, layoutSeq, () {
    // ONE guarded single-row UPDATE (Run 058 S12): written only while the
    // row is still [over] ([sameMatchRow]'s fields, in the statement).
    _prepared(
      'UPDATE ingredient_matches SET derived_seq = ?, '
      'retry_count = CASE WHEN ? THEN retry_count ELSE 0 END '
      '$_sameRowSql',
    ).execute([
      derivedSeq,
      if (keepRetryCount) 1 else 0,
      ..._sameRowBinds(over),
    ]);
    return _db.updatedRows > 0;
  });

  /// RULE A's FOOD failure (v28): counts one more compute that could not
  /// derive the row [over] — unchanged, guarded as [markDerivedIfUnchanged]
  /// guards — because FDC failed its food alone; returns the count now, or
  /// null when the row changed (or the layout moved) and nothing was
  /// counted. Any other write of the row resets it (migration 016).
  int? countFoodFailureIfUnchanged(
    IngredientMatchRow over, {
    required int layoutSeq,
  }) {
    int? count;
    _atLayout(over.recipeId, layoutSeq, () {
      final rows = _prepared(
        'UPDATE ingredient_matches SET retry_count = retry_count + 1 '
        '$_sameRowSql RETURNING retry_count',
      ).select(_sameRowBinds(over));
      count = rows.isEmpty ? null : rows.first['retry_count'] as int;
      return count != null;
    });
    return count;
  }

  /// Drops match rows at or beyond [fromPosition] (an edit shortened the
  /// ingredient list).
  void deleteIngredientMatchesFrom(String recipeId, int fromPosition) {
    _prepared(
      'DELETE FROM ingredient_matches WHERE recipe_id = ? AND position >= ?',
    ).execute([recipeId, fromPosition]);
  }

  /// Lays a recipe's match rows out anew in ONE transaction, before the
  /// caller awaits anything (the engine's `layoutMatchRows`, run by a compute
  /// and by a person's write): every row at a position in [drop] is deleted
  /// (its line is gone, or is another ingredient now), and each entry of
  /// [moves] takes the row at its key (the old position) to `to`, with
  /// `itemKey`. A row is moved, never rewritten — its status, food and
  /// grams stay as a person left them. The movers are parked at negative
  /// positions first, so a swap or a shift never meets the primary key, and
  /// whatever still sits at a destination (the engine's row of that line,
  /// re-derived after) is deleted; a destination is never another mover's
  /// or a kept row's position, by the pairing's construction. [lines] are
  /// the texts of the lines the rows are laid out on: a layout that moves or
  /// drops a row or lays them on other lines bumps the recipe's layout
  /// sequence and keeps the texts ([layoutOf]) in the same transaction; one
  /// that changes nothing writes nothing. A first layout always draws a seq
  /// (v24, Run 054 H4: the seq-0 no-bump branch is gone — every recipe laid
  /// out before 012 is seeded at boot instead, [seedLayout]).
  void relayoutIngredientMatches(
    String recipeId, {
    required Set<int> drop,
    required Map<int, ({int to, String? itemKey})> moves,
    required List<String> lines,
  }) {
    final texts = jsonEncode(lines);
    if (drop.isEmpty && moves.isEmpty && _layoutTextsOf(recipeId) == texts) {
      return;
    }
    final delete = _prepared(
      'DELETE FROM ingredient_matches WHERE recipe_id = ? AND position = ?',
    );
    final park = _prepared(
      'UPDATE ingredient_matches SET position = ? '
      'WHERE recipe_id = ? AND position = ?',
    );
    final place = _prepared(
      'UPDATE ingredient_matches SET position = ?, item_key = ?, '
      'updated_at = ? WHERE recipe_id = ? AND position = ?',
    );
    _inTransaction(() {
      for (final at in drop) {
        delete.execute([recipeId, at]);
      }
      final parked = [...moves.entries];
      for (final (i, move) in parked.indexed) {
        park.execute([-1 - i, recipeId, move.key]);
      }
      for (final (i, move) in parked.indexed) {
        delete.execute([recipeId, move.value.to]);
        place.execute([
          move.value.to,
          move.value.itemKey,
          _utcNowIso(),
          recipeId,
          -1 - i,
        ]);
      }
      // (A recipe deleted meanwhile has no layout to keep.) The seq is the
      // GLOBAL counter's next (migration 013): a recipe deleted and
      // re-created under its id never repeats a seq a writer read before.
      _prepared('UPDATE layout_counter SET seq = seq + 1').execute();
      _prepared(
        'INSERT INTO recipe_layout (recipe_id, seq, lines) '
        'SELECT ?, (SELECT seq FROM layout_counter), ? '
        'WHERE EXISTS (SELECT 1 FROM recipes WHERE id = ?) '
        'ON CONFLICT(recipe_id) DO UPDATE SET seq = excluded.seq, '
        'lines = excluded.lines',
      ).execute([recipeId, texts, recipeId]);
    });
  }

  /// The recipes with match rows or a nutrition stamp and no layout row —
  /// every one computed before migration 012 ([seedLayout]).
  List<String> recipesWithoutLayout() => [
    for (final row in _prepared(
      'SELECT id FROM recipes r WHERE NOT EXISTS '
      '(SELECT 1 FROM recipe_layout l WHERE l.recipe_id = r.id) AND '
      '(EXISTS (SELECT 1 FROM recipe_nutrition n WHERE n.recipe_id = r.id) '
      'OR EXISTS (SELECT 1 FROM ingredient_matches m '
      'WHERE m.recipe_id = r.id))',
    ).select())
      row['id'] as String,
  ];

  /// Seeds [recipeId]'s first layout (Run 054 H4: the boot backfill,
  /// services/layout_backfill.dart): a seq drawn from the global counter,
  /// [lines] as its texts, and its stamp's layout 0 (migration 013's "never
  /// laid out") moved to that seq — in ONE transaction, so a stamp always
  /// names a real layout and no seq is ever repeated for an id. Nothing when
  /// the recipe has a layout row already, or is gone. Returns whether it
  /// seeded.
  bool seedLayout(String recipeId, List<String> lines) {
    var seeded = false;
    _inTransaction(() {
      if (_layoutTextsOf(recipeId) != null ||
          _prepared(
            'SELECT 1 FROM recipes WHERE id = ?',
          ).select([recipeId]).isEmpty) {
        return;
      }
      _prepared('UPDATE layout_counter SET seq = seq + 1').execute();
      _prepared(
        'INSERT INTO recipe_layout (recipe_id, seq, lines) '
        'SELECT ?, seq, ? FROM layout_counter',
      ).execute([recipeId, jsonEncode(lines)]);
      _prepared(
        'UPDATE recipe_nutrition SET layout_seq = '
        '(SELECT seq FROM layout_counter) '
        'WHERE recipe_id = ? AND layout_seq = 0',
      ).execute([recipeId]);
      seeded = true;
    });
    return seeded;
  }

  /// A recipe's match-row layout (migration 012): `seq` changes with every
  /// layout that moved or dropped its rows or changed the lines they stand
  /// on, drawn from one global counter so it never repeats for a recipe id
  /// (migration 013; 0: never laid out — a recipe computed before 012 is
  /// seeded one at boot, [seedLayout]), `texts` is the JSON array of those
  /// lines' texts and `lines` decodes it (both null: never laid out).
  /// Decodes the texts: a reader of the lines only (the engine's
  /// `layoutMatchRows`, once per compute or write). A gate reads
  /// [layoutSeqOf] and a comparison [_layoutTextsOf] (RULE C, v26, Run 056 O9/S10: every row write decoded
  /// the whole layout twice — 400 legal 1,000-character lines, ~800 decodes
  /// of a 400 KB JSON per compute).
  ({int seq, String? texts, List<String>? lines}) layoutOf(String recipeId) {
    final rows = _prepared(
      'SELECT seq, lines FROM recipe_layout WHERE recipe_id = ?',
    ).select([recipeId]);
    if (rows.isEmpty) {
      return (seq: 0, texts: null, lines: null);
    }
    final texts = rows.first['lines'] as String;
    layoutDecodes++;
    return (
      seq: rows.first['seq'] as int,
      texts: texts,
      lines: (jsonDecode(texts) as List).cast<String>(),
    );
  }

  /// How many layouts [layoutOf] decoded — the cost pins' count.
  @visibleForTesting
  int layoutDecodes = 0;

  /// [layoutOf]'s `seq` alone: the column, never the texts.
  int layoutSeqOf(String recipeId) =>
      _prepared(
            'SELECT seq FROM recipe_layout WHERE recipe_id = ?',
          ).select([recipeId]).firstOrNull?['seq']
          as int? ??
      0;

  /// [layoutOf]'s `texts` as stored, never decoded.
  String? _layoutTextsOf(String recipeId) =>
      _prepared(
            'SELECT lines FROM recipe_layout WHERE recipe_id = ?',
          ).select([recipeId]).firstOrNull?['lines']
          as String?;

  /// The computed nutrition row for a recipe, or null.
  RecipeNutritionRow? nutritionFor(String recipeId) {
    final rows = _prepared(
      'SELECT recipe_id, serving_basis, calories_per_serving, nutrients, '
      'total_grams, matched_count, total_count, status, ingredients_hash, '
      'computed_at, layout_seq, totals, computing FROM recipe_nutrition '
      'WHERE recipe_id = ?',
    ).select([recipeId]);
    return rows.isEmpty ? null : RecipeNutritionRow.fromRow(rows.first);
  }

  /// RULE A's ONE predicate (v27, migration 014): whether the stamp `n`
  /// (a `recipe_nutrition` row) has a decided row (`isDecidedRow`: a
  /// person's confirm, pick, typed grams or skip — never the engine's rule
  /// rows) whose `derived_seq` is not the stamp's own key ([derivedKeyOf]):
  /// a decision no derivation has reached for the inputs and layout the
  /// totals were stamped on. Read by every freshness reader — the engine's
  /// `nutritionIsFresh` ([hasUnderivedRows]: the recipe page, the job
  /// loops' stop, the compute's own read after its stamp) and the stale
  /// sweep's scope ([recipesWithNutrition]) — at the time each reads, over
  /// the rows as stored: a writer that stamps never decides it (Run 057
  /// S15/O1: a compute's snapshot stamped fresh over a PUT's underived
  /// row).
  ///
  /// v29 (RULE A, Run 059): also a pass IN PROGRESS (`computing` > 0,
  /// migration 017 — a pass that has not reached its totals, Opus critic 1)
  /// and an ENGINE line whose food FDC failed (FOOD) and is not held yet
  /// (`unmatched` with a `retry_count`, `engineUnavailableNote`: the sweep
  /// asks again, once per pass, until [foodUnavailableAfter] holds it);
  /// v36 (Run 060 S4): also an `auto` row KEPT with its food through such a
  /// failure (a `retry_count`, not held [foodUnavailableHold] yet) — the
  /// row's OWN hold (`coating`, `partial_pour_away`, ...) is no such hold:
  /// its derivation failed all the same (verifier D1). Once HELD, such a
  /// kept row is keyed by `derived_seq` as a decided row is (the held
  /// write stamps it, every later compute re-stamps it, [unholdOn] clears
  /// it when a cache gains its food): a cache gain re-opens it with no
  /// request (verifier D2).
  static const String underivedSql =
      '(n.computing > 0 OR EXISTS (SELECT 1 FROM '
      'ingredient_matches m WHERE m.recipe_id = n.recipe_id AND '
      "((m.status IN ('confirmed', 'overridden', 'skipped') "
      "AND NOT (m.status = 'confirmed' AND m.fdc_id IS NULL "
      'AND m.description IN ($engineRuleNotesSql)) '
      "AND m.derived_seq IS NOT (n.layout_seq || ':' || n.ingredients_hash)) "
      "OR (m.status = 'auto' AND m.hold = '$foodUnavailableHold' "
      "AND m.derived_seq IS NOT (n.layout_seq || ':' || n.ingredients_hash)) "
      "OR (m.status IN ('unmatched', 'auto') AND m.retry_count > 0 "
      "AND m.hold IS NOT '$foodUnavailableHold') "
      'OR $childStampUnderivedSql)))';

  /// [underivedSql]'s child arm (v41, migration 018): a composite row
  /// derived from a stamp of its child (`child_stamp`) that is not the
  /// child's `computed_at` now — the child was recomputed, rebased, or is
  /// gone (no `recipe_nutrition` row: the subquery is NULL). Any status: the
  /// parent's stored totals hold the child either way. Over the row `m`.
  static const String childStampUnderivedSql =
      '(m.child_stamp IS NOT NULL AND m.child_stamp IS NOT '
      '(SELECT c.computed_at FROM recipe_nutrition c '
      'WHERE c.recipe_id = m.child_recipe_id))';

  /// The `gram_source` of every composite reference row (v41: routed, held
  /// `choose_recipe` / `nested_recipe`, a marinade's `discarded_recipe`),
  /// and of no food row: the FOOD reach ([undecidedMatchesForItemKey])
  /// never takes such a row (the line takes no food); a recipe decision's
  /// reach takes only them (design_v3 S18).
  static const String recipeGramSource = 'recipe';

  /// [engineRuleNotes] as an SQL list (a const, for the cached queries;
  /// pinned equal to the list).
  @visibleForTesting
  static const String engineRuleNotesSql =
      "'Sub-recipe — made from its own recipe, not counted in these totals', "
      "'Seasoning to taste — no measurable amount', "
      "'Equipment — not food, counts as zero', "
      "'Water/ice — counts as zero', "
      "'Continues the line above — counted with it', "
      "'Flavouring — no nutrients, counts as zero'";

  /// [underivedSql] for [recipeId]'s stamp; false with no stamp.
  bool hasUnderivedRows(String recipeId) =>
      _prepared(
        'SELECT $underivedSql AS u FROM recipe_nutrition n '
        'WHERE n.recipe_id = ?',
      ).select([recipeId]).firstOrNull?['u'] ==
      1;

  /// Clears `derived_seq` on [recipeId]'s rows at [positions]: their
  /// derived fields are no longer what the totals can count (the totals
  /// found no cached food for them, RULE A), so the next compute derives
  /// them again.
  void clearDerivedSeq(String recipeId, Iterable<int> positions) {
    final clear = _prepared(
      'UPDATE ingredient_matches SET derived_seq = NULL '
      'WHERE recipe_id = ? AND position = ?',
    );
    for (final position in positions) {
      clear.execute([recipeId, position]);
    }
  }

  /// The settings key migration 014 sets: its `derived_seq` backfill is
  /// owed ([finishDerivedSeqBackfill] clears it).
  static const String derivedSeqBackfillSetting =
      'nutrition.derived_seq_backfill';

  /// Migration 014's one-shot backfill, in ONE transaction with the
  /// marker's removal: every decided row of each recipe in [keys] (the
  /// recipes whose stamp is current) takes that recipe's key; every other
  /// stays null (underived). Run once: a later boot finds no marker, so an
  /// underived write is never "healed" by a restart.
  void finishDerivedSeqBackfill(Map<String, String> keys) {
    final mark = _prepared(
      'UPDATE ingredient_matches SET derived_seq = ? WHERE recipe_id = ? '
      "AND status IN ('confirmed', 'overridden', 'skipped')",
    );
    _inTransaction(() {
      for (final MapEntry(key: recipeId, value: key) in keys.entries) {
        mark.execute([key, recipeId]);
      }
      deleteSetting(derivedSeqBackfillSetting);
    });
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
    int? layoutSeq,
    String? totalsJson,
    Iterable<int> underived = const [],
    bool ending = false,
  }) => _inTransaction(() {
    // The rows the totals found no cached food for lose their derivation
    // and, [ending], the writer's own in-progress mark ([markComputing],
    // migration 017) is released — with the totals, in ONE transaction
    // (v29, RULE A); a writer that marked nothing leaves every other
    // writer's mark standing.
    clearDerivedSeq(recipeId, underived);
    _prepared(
      'INSERT INTO recipe_nutrition (recipe_id, serving_basis, '
      'calories_per_serving, nutrients, total_grams, matched_count, '
      'total_count, status, ingredients_hash, computed_at, layout_seq, '
      'totals) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(recipe_id) DO UPDATE SET '
      'serving_basis = excluded.serving_basis, '
      'calories_per_serving = excluded.calories_per_serving, '
      'nutrients = excluded.nutrients, '
      'total_grams = excluded.total_grams, '
      'matched_count = excluded.matched_count, '
      'total_count = excluded.total_count, status = excluded.status, '
      'ingredients_hash = excluded.ingredients_hash, '
      'computed_at = excluded.computed_at, layout_seq = excluded.layout_seq, '
      'totals = excluded.totals, '
      'computing = CASE WHEN ? THEN MAX(computing - 1, 0) ELSE computing END',
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
      layoutSeq,
      totalsJson,
      ending,
    ]);
  });

  /// Marks [recipeId]'s stamp IN PROGRESS (migration 017): a writer — a
  /// compute pass, a person's write, an apply-to-all target — is about to
  /// write rows whose totals are not written yet. An OWNED count: each
  /// writer adds one before its first row write and takes its own one away
  /// with its totals ([upsertRecipeNutrition]'s `ending`, one transaction)
  /// or [releaseComputing] — never another writer's. While it is above
  /// zero every freshness reader ([underivedSql]) reads the recipe stale.
  /// Returns whether a mark was taken: no stamp, nothing to mark (a recipe
  /// never computed is not fresh anyway), and nothing to release.
  bool markComputing(String recipeId) {
    _prepared(
      'UPDATE recipe_nutrition SET computing = computing + 1 '
      'WHERE recipe_id = ?',
    ).execute([recipeId]);
    return _db.updatedRows > 0;
  }

  /// The stamp prefix of totals a writer never finished ([releaseComputing]
  /// with `stale`, [resetInterruptedComputes]): no current hash equals it,
  /// and the page's `stale_reason` reads `interrupted`.
  static const String interruptedStamp = 'interrupted:';

  /// Ends a writer's mark ([markComputing]) on a path that writes no totals
  /// — taking its own one away when [owned], and when [stale] (it wrote
  /// rows the totals never counted: a throw) clearing the stamp, so the
  /// recipe reads stale (`interrupted`) until a compute stamps it again.
  void releaseComputing(
    String recipeId, {
    required bool owned,
    required bool stale,
  }) => _prepared(
    'UPDATE recipe_nutrition SET computing = MAX(computing - ?, 0), '
    'ingredients_hash = CASE WHEN ? AND ingredients_hash NOT LIKE '
    "'$interruptedStamp%' THEN '$interruptedStamp' || ingredients_hash "
    'ELSE ingredients_hash END WHERE recipe_id = ?',
  ).execute([if (owned) 1 else 0, stale, recipeId]);

  /// The boot's reconciliation (migration 017): a mark still held belongs
  /// to a writer of the process that died — its stamp is cleared (stale,
  /// `interrupted`) and the count reset. Returns how many recipes.
  int resetInterruptedComputes() {
    _prepared(
      'UPDATE recipe_nutrition SET computing = 0, ingredients_hash = CASE '
      "WHEN ingredients_hash LIKE '$interruptedStamp%' THEN ingredients_hash "
      "ELSE '$interruptedStamp' || ingredients_hash END WHERE computing > 0",
    ).execute([]);
    return _db.updatedRows;
  }

  /// RULE A (v29, Run 059 O1/S1/S6): a cache now holds [fdcIds] — every row
  /// held for having no record of one of them (`food_gone`,
  /// `food_unavailable`: [noRecordHolds]) loses its derivation, so its
  /// recipe reads stale and the next compute re-reads the hold from the
  /// caches (no request). One indexed UPDATE (migration 017's partial
  /// index) per cache write; nothing changes when no such row exists.
  void unholdOn(Iterable<int> fdcIds) {
    final ids = fdcIds.toSet();
    if (ids.isEmpty) {
      return;
    }
    _db.execute(
      'UPDATE ingredient_matches SET derived_seq = NULL '
      'WHERE hold IN ($noRecordHoldsSql) AND derived_seq IS NOT NULL '
      'AND fdc_id IN (${List.filled(ids.length, '?').join(', ')})',
      ids.toList(),
    );
  }

  /// A serving-basis change (`rebaseNutrition`): the divisor, the label
  /// divided by it and the totals it was divided from — never the status,
  /// the counts, the grams or the stamp (`ingredients_hash`, `layout_seq`).
  /// `computed_at` moves, as on every nutrition write
  /// ([recipeReviewFingerprint]).
  void rebaseRecipeNutrition({
    required String recipeId,
    required int servingBasis,
    required double? caloriesPerServing,
    required String nutrientsJson,
    required String totalsJson,
  }) {
    _prepared(
      'UPDATE recipe_nutrition SET serving_basis = ?, '
      'calories_per_serving = ?, nutrients = ?, totals = ?, '
      'computed_at = ? WHERE recipe_id = ?',
    ).execute([
      servingBasis,
      caloriesPerServing,
      nutrientsJson,
      totalsJson,
      _utcNowIso(),
      recipeId,
    ]);
  }

  /// Every recipe id, ordered — for whole-library maintenance passes.
  List<String> allRecipeIds() {
    final rows = _db.select('SELECT id FROM recipes ORDER BY id');
    return [for (final row in rows) row['id'] as String];
  }

  /// Every recipe's id and stored doc, ordered by id — the bulk scopes'
  /// one read of the documents (the parents-last partition, v41).
  List<({String id, String doc})> recipeDocs() => [
    for (final row in _db.select('SELECT id, doc FROM recipes ORDER BY id'))
      (id: row['id'] as String, doc: row['doc'] as String),
  ];

  /// Every library recipe's id, slug and title, by id — the sub-recipe
  /// resolver's title index (v41; one statement per resolver memo).
  List<({String id, String slug, String title})> recipeTitleIndex() => [
    for (final row in _prepared(
      'SELECT id, slug, title FROM recipes ORDER BY id',
    ).select())
      (
        id: row['id'] as String,
        slug: row['slug'] as String,
        title: row['title'] as String,
      ),
  ];

  /// Every titled subsection of every recipe: its host's id and its title,
  /// in document order — the resolver's section index (v41; one statement,
  /// never a document decode).
  List<({String host, String title})> subsectionTitleIndex() => [
    for (final row in _prepared(
      r"SELECT r.id AS host, json_extract(s.value, '$.title') AS title "
      r"FROM recipes r, json_each(r.doc, '$.subsections') s "
      r"WHERE json_extract(s.value, '$.title') IS NOT NULL "
      'ORDER BY r.id, s.key',
    ).select())
      (host: row['host'] as String, title: row['title'] as String),
  ];

  /// The recipes holding a composite row whose child is one of [childIds]
  /// (`child_recipe_id`, migration 018), ordered by id — the parents a
  /// stale sweep appends after their children (v41, design_v3 F7a).
  List<String> recipesReadingChildren(Iterable<String> childIds) => [
    for (final row in _prepared(
      'SELECT DISTINCT recipe_id FROM ingredient_matches '
      'WHERE child_recipe_id IN (SELECT value FROM json_each(?)) '
      'ORDER BY recipe_id',
    ).select([jsonEncode(childIds.toList())]))
      row['recipe_id'] as String,
  ];

  /// Recipe ids that have no computed nutrition yet (bulk-job work list).
  List<String> recipeIdsWithoutNutrition() {
    final rows = _db.select(
      'SELECT r.id FROM recipes r '
      'LEFT JOIN recipe_nutrition n ON n.recipe_id = r.id '
      'WHERE n.recipe_id IS NULL ORDER BY r.id',
    );
    return [for (final row in rows) row['id'] as String];
  }

  /// Every recipe that has stored nutrition, with the doc and the hash the
  /// compute stored — everything the caller needs to decide staleness.
  ///
  /// Staleness is `ingredients_hash != ingredientsHashOf(recipe)`, a SHA-256
  /// over a JSON projection of the ingredient lines computed in Dart, so it
  /// cannot be a WHERE clause; the caller decodes and compares. (Note
  /// `recipe_nutrition.status` is no help: its CHECK constraint allows
  /// 'stale' but nothing ever WRITES it — the value is derived at read time.)
  ///
  /// Deliberately NO timestamp prefilter. Two were tried and both were wrong.
  /// Comparing `updated_at` against `computed_at` first failed on FORMAT (one
  /// is SQLite's `datetime('now')`, the other Dart's `toIso8601String()`; a
  /// raw `>=` compares ' ' to 'T' at char 11 and is false for every same-day
  /// pair) and then, once normalised, on SEMANTICS: `computed_at` is stamped
  /// when the ROW is written, but the hash describes the recipe as it was
  /// when the compute STARTED, before its provider awaits — so an edit that
  /// lands during a compute has `updated_at < computed_at` while the stored
  /// hash no longer matches, and a plain recompute (serving basis, match
  /// override) restamps `computed_at` while keeping the old hash. Either way
  /// the prefilter dropped a recipe the UI itself labels stale. Hashing every
  /// row is correct by definition and was measured at ~110 ms for the whole
  /// 1,198-recipe library — cheaper than a third trap.
  ///
  /// `layoutCurrent` is the other half of freshness (migration 013): the
  /// stamp's layout sequence is still the recipe's ([layoutOf]).
  /// `underived` is RULE A's half ([underivedSql]): a decided row no
  /// derivation reached for the stamp.
  List<
    ({
      String id,
      String doc,
      String ingredientsHash,
      bool layoutCurrent,
      bool underived,
    })
  >
  recipesWithNutrition() {
    final rows = _db.select(
      'SELECT r.id AS id, r.doc AS doc, n.ingredients_hash AS h, '
      'n.layout_seq IS COALESCE(l.seq, 0) AS lc, $underivedSql AS ud '
      'FROM recipes r JOIN recipe_nutrition n ON n.recipe_id = r.id '
      'LEFT JOIN recipe_layout l ON l.recipe_id = r.id '
      'ORDER BY r.id',
    );
    return [
      for (final row in rows)
        (
          id: row['id'] as String,
          doc: row['doc'] as String,
          ingredientsHash: row['h'] as String,
          layoutCurrent: row['lc'] == 1,
          underived: row['ud'] == 1,
        ),
    ];
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
  /// UTC ISO-8601 with a FIXED six-digit fraction. `toIso8601String` emits
  /// three digits when the microseconds happen to be zero and six otherwise,
  /// and `...001Z` sorts AFTER `...001005Z` as text — so "most recent by
  /// updated_at" could pick the older of two writes in the same millisecond.
  static String _utcNowIso() => fixedWidthUtcIso(DateTime.now());

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
  ///
  /// [revokeApiTokens] revokes every live API token of the user inside that
  /// SAME transaction; the return value is how many went (0 when not asked).
  /// A parameter rather than a second call on purpose: a PAT is a standalone
  /// credential that outlives a password, so "password rotated, tokens still
  /// live" is the compromise state the eviction exists to prevent (review
  /// S4). Two statements outside one transaction can only ORDER that risk — a
  /// partial failure still splits them, and the caller sees a 500 that reads
  /// as "nothing happened". One transaction removes the split: both land or
  /// neither does.
  int updatePasswordHash(
    int userId,
    String passwordHash, {
    required bool mustChangePassword,
    // Required, with no default: this is the one method every password
    // rotation routes through, and a defaulted `false` would let a fourth
    // caller ship "password changed, every token still live" — the exact
    // compromise state above — by saying nothing at all. Costs one word at
    // each call site and cannot be got wrong by omission.
    required bool revokeApiTokens,
    String? keepSessionHash,
  }) {
    var revoked = 0;
    _inTransaction(() {
      if (revokeApiTokens) {
        revoked = _revokeAllApiTokens(userId);
      }
      _writePasswordHash(
        userId,
        passwordHash,
        mustChangePassword: mustChangePassword,
      );
      _deleteSessions(userId, keepTokenHash: keepSessionHash);
    });
    return revoked;
  }

  /// Account recovery as ONE transaction: revokes every live API token,
  /// rotates the password (dropping every session), promotes to `admin` and
  /// re-enables. Returns how many tokens were revoked.
  ///
  /// Four writes, one commit. Any one of them alone can be the lockout, so as
  /// separate commits a failure between them left the account half recovered
  /// — the operator's new password live on an account still disabled, or the
  /// tokens dead and nothing else done. Recovery is used when control of the
  /// account is in doubt, which is why the tokens go at all: see
  /// [updatePasswordHash] for why they go inside the transaction.
  int resetToEnabledAdmin(int userId, String passwordHash) {
    var revoked = 0;
    _inTransaction(() {
      revoked = _revokeAllApiTokens(userId);
      _writePasswordHash(userId, passwordHash, mustChangePassword: false);
      _deleteSessions(userId);
      _prepared(
        "UPDATE users SET role = 'admin', disabled = 0 WHERE id = ?",
      ).execute([userId]);
    });
    return revoked;
  }

  void _writePasswordHash(
    int userId,
    String passwordHash, {
    required bool mustChangePassword,
  }) {
    _prepared(
      'UPDATE users SET password_hash = ?, must_change_password = ? '
      'WHERE id = ?',
    ).execute([passwordHash, if (mustChangePassword) 1 else 0, userId]);
  }

  void _deleteSessions(int userId, {String? keepTokenHash}) {
    if (keepTokenHash == null) {
      _prepared('DELETE FROM sessions WHERE user_id = ?').execute([userId]);
      return;
    }
    _prepared(
      'DELETE FROM sessions WHERE user_id = ? AND token_hash != ?',
    ).execute([userId, keepTokenHash]);
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
      _deleteSessions(userId);
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
  /// A PAT is a standalone credential that survives a password reset, so
  /// leaving them live would hand whoever caused the lockout a way straight
  /// back in. PRIVATE on purpose: every caller wants it welded to a password
  /// rotation, so it is reachable only through [updatePasswordHash] and
  /// [resetToEnabledAdmin], which run it in their own transaction.
  int _revokeAllApiTokens(int userId) {
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

/// One end of a calories range: a threshold and whether it is inclusive.
///
/// `value` is non-nullable on purpose — "no bound" is the absence of the
/// whole record, never a null inside one, so a filter can never be turned
/// off by a missing value, and a nullable [CaloriesNode.value] would stop
/// compiling here rather than start returning unfiltered rows.
typedef _CaloriesBound = ({num value, bool inclusive});

/// Collapses ANDed calories [nodes] to at most one lower and one upper bound.
///
/// A conjunction over one numeric column is an interval: repeats of an
/// operator reduce to the tightest bound (`c < 300 AND c < 500` is
/// `c < 300`), and `=` is simply both bounds at once (`c = 300` is
/// `c >= 300 AND c <= 300`). Contradictions need no special case — they come
/// out as an empty interval (`c >= 400 AND c <= 300`), which matches nothing.
({_CaloriesBound? lower, _CaloriesBound? upper}) _caloriesRange(
  List<CaloriesNode> nodes,
) {
  _CaloriesBound? lower;
  _CaloriesBound? upper;
  for (final node in nodes) {
    final value = node.value;
    switch (node.op) {
      case CaloriesOp.lt:
        upper = _tighterUpper(upper, (value: value, inclusive: false));
      case CaloriesOp.lte:
        upper = _tighterUpper(upper, (value: value, inclusive: true));
      case CaloriesOp.gt:
        lower = _tighterLower(lower, (value: value, inclusive: false));
      case CaloriesOp.gte:
        lower = _tighterLower(lower, (value: value, inclusive: true));
      case CaloriesOp.eq:
        lower = _tighterLower(lower, (value: value, inclusive: true));
        upper = _tighterUpper(upper, (value: value, inclusive: true));
    }
  }
  return (lower: lower, upper: upper);
}

/// The stricter of two lower bounds: the larger value, and on a tie the
/// exclusive one (`> 300` admits less than `>= 300`).
_CaloriesBound _tighterLower(_CaloriesBound? current, _CaloriesBound other) =>
    current == null ||
        other.value > current.value ||
        (other.value == current.value && !other.inclusive)
    ? other
    : current;

/// The stricter of two upper bounds: the smaller value, exclusive on a tie.
_CaloriesBound _tighterUpper(_CaloriesBound? current, _CaloriesBound other) =>
    current == null ||
        other.value < current.value ||
        (other.value == current.value && !other.inclusive)
    ? other
    : current;

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
/// row plus the recipe context (slug/title) and its computed triage bucket,
/// and `finishes`: 1 when it is its recipe's only open line (any decision on
/// it completes the recipe), else 0.
typedef NutritionReviewLineRow = ({
  IngredientMatchRow match,
  String slug,
  String title,
  String bucket,
  int finishes,
});

/// One ingredient GROUP of the review queue: its EXAMPLE line (the same shape
/// as [NutritionReviewLineRow] — match row, recipe slug/title) plus what the
/// group adds: `bucket` is the worst member's bucket, `itemKey` the key the
/// group is joined on (empty for an unkeyed row, which is a group of one),
/// `lines`/`recipes` its reach inside the current filter, `decided` whether
/// `ingredient_decisions` already holds the key, and the grams triple the
/// amount spread over the members.
typedef NutritionReviewGroupRow = ({
  IngredientMatchRow match,
  String slug,
  String title,
  String bucket,
  String itemKey,
  int lines,
  int recipes,
  bool decided,
  double? gramsMin,
  double? gramsMax,
  int gramsMissing,
  int finishes,
  int lastOpen,
  List<({String id, String title})> finishesRecipes,
});

/// [time] in UTC as ISO-8601 with a FIXED six-digit fraction
/// (`2026-09-03T01:02:03.001000Z`). `toIso8601String` emits three digits
/// when the microseconds happen to be zero and six otherwise, and as text
/// `...001Z` sorts AFTER `...001005Z` — so anything ordered by such a column
/// could rank the older of two writes in the same millisecond as newer.
String fixedWidthUtcIso(DateTime time) {
  final iso = time.toUtc().toIso8601String(); // ...SS.mmmZ or ...SS.mmmuuuZ
  return iso.length == 24 ? '${iso.substring(0, 23)}000Z' : iso;
}

/// One tag with its usage count and optional chip style.
/// One row of `ingredient_matches`.
/// One row of `ingredient_decisions`: a person's food for an ingredient.
class IngredientDecisionRow {
  /// Builds a row from its parts.
  const IngredientDecisionRow({
    required this.itemKey,
    required this.item,
    required this.fdcId,
    required this.description,
    required this.dataType,
    required this.decidedBy,
    required this.decidedAt,
  });

  /// Decodes a selected row.
  factory IngredientDecisionRow.fromRow(Row row) => IngredientDecisionRow(
    itemKey: row['item_key'] as String,
    item: row['item'] as String,
    fdcId: row['fdc_id'] as int?,
    description: row['description'] as String?,
    dataType: row['data_type'] as String?,
    decidedBy: row['decided_by'] as int?,
    decidedAt: row['decided_at'] as String,
  );

  /// The decision key (`itemKeyFor` of [item]).
  final String itemKey;

  /// The parsed ingredient text the key was derived from.
  final String item;

  /// The chosen FoodData Central food; null is reserved for a human
  /// "no match" (not written yet).
  final int? fdcId;

  /// The food's description and data type as stored at decision time.
  final String? description;

  /// See [description].
  final String? dataType;

  /// Who decided (null when the account is gone).
  final int? decidedBy;

  /// When, UTC ISO.
  final String decidedAt;
}

/// The notes the nutrition engine stores on its OWN 'confirmed' rows that
/// carry no food (engine.dart writes them): a sub-recipe reference, a
/// seasoning to taste, equipment, water, a split line's tail (v37), a
/// zero-nutrient flavouring (v37). Such a
/// row is the engine's rule, never a person's call, so the engine may
/// rewrite it
/// ([SaltDatabase.upsertIngredientMatchIfUndecided], [isEngineRuleRow]).
const List<String> engineRuleNotes = [
  'Sub-recipe — made from its own recipe, not counted in these totals',
  'Seasoning to taste — no measurable amount',
  'Equipment — not food, counts as zero',
  'Water/ice — counts as zero',
  // v37 (Z14): the corpus split a line's tail onto its own line.
  'Continues the line above — counted with it',
  // v37 (the class ruling): a zero-nutrient flavouring, 0 g on no food.
  'Flavouring — no nutrients, counts as zero',
];

/// The note of an ENGINE line's row whose food FDC failed (a FOOD failure,
/// v29 RULE A): `unmatched`, no food, counted by `retry_count` and held
/// `food_unavailable` after `foodUnavailableAfter` computes.
const String engineUnavailableNote =
    'FoodData Central could not serve this food';

/// Whether [row] is one of the engine's own rule rows ([engineRuleNotes]):
/// 'confirmed' on no food under one of its notes. A person's confirm of a
/// food, or of any other note, is not.
bool isEngineRuleRow(IngredientMatchRow row) =>
    row.status == 'confirmed' &&
    row.fdcId == null &&
    engineRuleNotes.contains(row.description);

/// One row of `ingredient_matches`: a recipe line's food, grams, status
/// and decision key.
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
    this.itemKey,
    this.hold,
    this.derivedSeq,
    this.childRecipeId,
    this.childShare,
    this.childStamp,
    this.parts,
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
    itemKey: row['item_key'] as String?,
    hold: row['hold'] as String?,
    derivedSeq: row['derived_seq'] as String?,
    childRecipeId: row['child_recipe_id'] as String?,
    childShare: (row['child_share'] as num?)?.toDouble(),
    childStamp: row['child_stamp'] as String?,
    parts: row['parts'] as String?,
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

  /// The matcher's normalized item text (`normalizeItem`) — the key under
  /// which a human decision on this line is found from OTHER recipes.
  /// Null only on rows written before migration 009 and not yet backfilled.
  final String? itemKey;

  /// Why an `auto` row is held out of the totals although its name score
  /// passes (migration 011): `no_nutrients` (the record publishes no energy
  /// and no macros), `discarded_medium` (frying oil, a brine, a soak or
  /// cheese-making milk set to review), `second_food` (the line names a
  /// second ingredient). Null when nothing holds it. A person's decision on
  /// the row clears it (a skip, a pick, a confirm, a grams edit); an un-skip
  /// re-derives it for the food on the row.
  final String? hold;

  /// What a decided row's derived fields were computed for (migration 014,
  /// RULE A): the [derivedKeyOf] its last successful derivation wrote, or
  /// null — none for the inputs it stands on. Not part of the row's identity
  /// ([sameMatchRow]): a compute re-deriving it changes no decision.
  final String? derivedSeq;

  /// A SUB-RECIPE row's child (migration 018): the `recipes.id` of the
  /// recipe the line is made from, or null (not a composite row).
  final String? childRecipeId;

  /// The share of the child's batch the line counts (> 0), or null.
  final double? childShare;

  /// The child's `recipe_nutrition.computed_at` the row was derived from
  /// ([SaltDatabase.childStampUnderivedSql] reads it), or null.
  final String? childStamp;

  /// A TWO-PART row's counted records, as stored: a JSON array (rendered
  /// bacon: the cooked record and the fat kept in the pan), or null. Never
  /// with a child (the column's CHECK).
  final String? parts;

  /// Copy with changed fields (explicit clears for the nullables).
  IngredientMatchRow copyWith({
    int? position,
    String? raw,
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
    String? itemKey,
    String? hold,
    bool clearHold = false,
    String? derivedSeq,
    bool clearDerivedSeq = false,
    String? childRecipeId,
    double? childShare,
    String? childStamp,
    bool clearChildStamp = false,
    bool clearChild = false,
    String? parts,
    bool clearParts = false,
  }) => IngredientMatchRow(
    recipeId: recipeId,
    position: position ?? this.position,
    raw: raw ?? this.raw,
    fdcId: clearFdcId ? null : (fdcId ?? this.fdcId),
    description: description ?? this.description,
    dataType: dataType ?? this.dataType,
    confidence: confidence ?? this.confidence,
    grams: clearGrams ? null : (grams ?? this.grams),
    gramSource: clearGramSource ? null : (gramSource ?? this.gramSource),
    status: status ?? this.status,
    itemKey: itemKey ?? this.itemKey,
    hold: clearHold ? null : (hold ?? this.hold),
    derivedSeq: clearDerivedSeq ? null : (derivedSeq ?? this.derivedSeq),
    // [clearChild] clears the child's three columns; [clearChildStamp] the
    // stamp alone (a gone child keeps its id, design_v3 §2.2 item 4).
    childRecipeId: clearChild ? null : (childRecipeId ?? this.childRecipeId),
    childShare: clearChild ? null : (childShare ?? this.childShare),
    childStamp: clearChild || clearChildStamp
        ? null
        : (childStamp ?? this.childStamp),
    parts: clearParts ? null : (parts ?? this.parts),
  );
}

/// The one value a decided row's `derived_seq` and its recipe's stamp are
/// compared by (RULE A, migration 014): the layout [layoutSeq] and the
/// nutrition inputs' hash [ingredientsHash] a derivation read.
String derivedKeyOf(int layoutSeq, String ingredientsHash) =>
    '$layoutSeq:$ingredientsHash';

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
    this.layoutSeq,
    this.totalsJson,
    this.computing = 0,
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
    layoutSeq: row['layout_seq'] as int?,
    totalsJson: row['totals'] as String?,
    computing: row['computing'] as int,
  );

  /// How many writers hold an in-progress mark ([SaltDatabase
  /// .markComputing], migration 017): above zero, the stamp is stale
  /// (`stale_reason: interrupted`).
  final int computing;

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
  /// comparing [ingredientsHash] to the current recipe and [layoutSeq] to
  /// its current layout: `nutritionIsFresh` in the engine).
  final String status;

  /// Hash of the ingredient lines the totals were computed from.
  final String ingredientsHash;

  /// Compute time (UTC ISO-8601).
  final String? computedAt;

  /// The recipe's layout sequence ([SaltDatabase.layoutOf]) the totals were
  /// computed on (migration 013); null on a stamp that names none.
  final int? layoutSeq;

  /// JSON: nutrient key -> the per-recipe total [nutrientsJson] divides by
  /// [servingBasis], unrounded (migration 015); null on a row written before.
  final String? totalsJson;
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

/// Whether [a] and [b] are the same stored row (its text, decision and
/// grams; not its position, key or write time), both absent included.
bool sameMatchRow(IngredientMatchRow? a, IngredientMatchRow? b) =>
    (a == null && b == null) ||
    (a != null &&
        b != null &&
        a.raw == b.raw &&
        a.status == b.status &&
        a.fdcId == b.fdcId &&
        a.confidence == b.confidence &&
        a.grams == b.grams &&
        a.gramSource == b.gramSource &&
        a.hold == b.hold &&
        a.description == b.description &&
        a.childRecipeId == b.childRecipeId &&
        a.childShare == b.childShare &&
        a.childStamp == b.childStamp &&
        a.parts == b.parts);
